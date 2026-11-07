--- Per-provider request builders and response parsers.
--- Each returns: build_request(cfg, system, user) -> url, options
---               parse_response(code, body)        -> text|nil, err|nil

local json = require "json"

local M = {}

local function trim_slash(u) return (u or ""):gsub("/$", "") end

-- Pull a deep field safely: dig(t, "a", 1, "b")
local function dig(t, ...)
    local cur = t
    for _, k in ipairs({ ... }) do
        if type(cur) ~= "table" then return nil end
        cur = cur[k]
    end
    return cur
end

local function http_error(code, body)
    if code == 0 then return "Network error: " .. tostring(body or "no response") end
    return "HTTP " .. tostring(code) .. ": " .. tostring(body or ""):sub(1, 300)
end

--------------------------------------------------------------------- Anthropic
M.anthropic = {
    default_model = "claude-opus-4-8",
    build_request = function(cfg, system, messages)
        local base = trim_slash(cfg.base_url ~= "" and cfg.base_url or "https://api.anthropic.com")
        local body = json.encode {
            model = (cfg.model ~= "" and cfg.model) or M.anthropic.default_model,
            max_tokens = cfg.max_tokens or 600,
            system = system,
            messages = messages,  -- array of {role="user"|"assistant", content=...}
        }
        local headers = {
            ["anthropic-version"] = "2023-06-01",
            ["content-type"] = "application/json",
        }
        if cfg.api_key and cfg.api_key ~= "" then headers["x-api-key"] = cfg.api_key end
        return base .. "/v1/messages", { method = "POST", headers = headers, data = body }
    end,
    parse_response = function(code, body)
        if code < 200 or code >= 300 then return nil, http_error(code, body) end
        local ok, t = pcall(json.decode, body)
        if not ok then return nil, "Bad JSON from Anthropic" end
        local text = dig(t, "content", 1, "text")
        if text then return text end
        return nil, dig(t, "error", "message") or "No content in Anthropic response"
    end,
}

------------------------------------------------------------------------ OpenAI
M.openai = {
    default_model = "gpt-4o",
    build_request = function(cfg, system, messages)
        local base = trim_slash(cfg.base_url ~= "" and cfg.base_url or "https://api.openai.com/v1")
        local msgs = { { role = "system", content = system } }
        for _, m in ipairs(messages) do msgs[#msgs + 1] = m end
        local body = json.encode {
            model = (cfg.model ~= "" and cfg.model) or M.openai.default_model,
            max_tokens = cfg.max_tokens or 600,
            messages = msgs,
        }
        local headers = { ["content-type"] = "application/json" }
        if cfg.api_key and cfg.api_key ~= "" then headers["authorization"] = "Bearer " .. cfg.api_key end
        return base .. "/chat/completions", { method = "POST", headers = headers, data = body }
    end,
    parse_response = function(code, body)
        if code < 200 or code >= 300 then return nil, http_error(code, body) end
        local ok, t = pcall(json.decode, body)
        if not ok then return nil, "Bad JSON from OpenAI" end
        local msg = dig(t, "choices", 1, "message")
        local text = msg and msg.content
        -- Some reasoning models leave `content` empty and put text in reasoning_content.
        if (not text or text == "") and msg then
            text = msg.reasoning_content or (dig(t, "choices", 1, "text"))
        end
        if text and text ~= "" then return text end
        local reason = dig(t, "choices", 1, "finish_reason")
        if reason == "length" then
            return nil, "Empty reply: hit the token limit before any text (raise max_tokens, or the model spent it all on hidden reasoning)."
        end
        return nil, dig(t, "error", "message") or ("Empty reply from model" .. (reason and (" (finish_reason=" .. tostring(reason) .. ")") or ""))
    end,
}

------------------------------------------------------------------------ Gemini
M.gemini = {
    default_model = "gemini-2.0-flash",
    build_request = function(cfg, system, messages)
        local base = trim_slash(cfg.base_url ~= "" and cfg.base_url or "https://generativelanguage.googleapis.com/v1beta")
        local model = (cfg.model ~= "" and cfg.model) or M.gemini.default_model
        local contents = {}
        for _, m in ipairs(messages) do
            contents[#contents + 1] = { role = (m.role == "assistant") and "model" or "user", parts = { { text = m.content } } }
        end
        local body = json.encode {
            system_instruction = { parts = { { text = system } } },
            contents = contents,
            generationConfig = { maxOutputTokens = cfg.max_tokens or 600 },
        }
        -- Key as query param (urlencoded).
        local url = string.format("%s/models/%s:generateContent?key=%s",
            base, model, (cfg.api_key or ""))
        return url, {
            method = "POST",
            headers = { ["content-type"] = "application/json" },
            data = body,
        }
    end,
    parse_response = function(code, body)
        if code < 200 or code >= 300 then return nil, http_error(code, body) end
        local ok, t = pcall(json.decode, body)
        if not ok then return nil, "Bad JSON from Gemini" end
        local text = dig(t, "candidates", 1, "content", "parts", 1, "text")
        if text then return text end
        return nil, dig(t, "error", "message") or "No content in Gemini response"
    end,
}

M.order = { "anthropic", "openai", "gemini" }

return M
