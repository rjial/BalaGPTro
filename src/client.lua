--- Async LLM client. One request in flight at a time. The SMODS.https callback
--- runs on the main thread (invoked from the patched love.update), but we still
--- defer the result through G.E_MANAGER so UI rebuilds happen at a safe point.

local https = require "SMODS.https"
local providers = require "providers"

local M = { busy = false, seq = 0, current = 0 }

--- Cancel the in-flight request: its result (when it arrives) is ignored. The
--- underlying HTTP call can't be aborted, but the response is discarded.
function M.cancel()
    M.current = M.current + 1   -- invalidate any outstanding request id
    M.busy = false
end

local function defer(fn)
    if G and G.E_MANAGER then
        G.E_MANAGER:add_event(Event({
            trigger = "immediate",
            blocking = false,
            func = function() fn(); return true end,
        }))
    else
        fn()
    end
end

--- Send a prompt. on_result(text, err) is called exactly once.
--- `history` (optional) is an array of prior {role="user"|"assistant", content=...}
--- messages, prepended before the new user message (used for chat continuity).
function M.ask(system, user, on_result, history)
    local cfg = BalaGPTro.config
    -- A base_url override usually means a local / compatible endpoint that may not
    -- need a key, so only require a key when hitting the default (cloud) endpoint.
    local has_base = cfg.base_url and cfg.base_url ~= ""
    if (not cfg.api_key or cfg.api_key == "") and not has_base then
        return on_result(nil, "No API key set. Open the mod config and paste your key (or set a Base URL for a local endpoint).")
    end
    local prov = providers[cfg.provider]
    if not prov then
        return on_result(nil, "Unknown provider: " .. tostring(cfg.provider))
    end
    -- A new request supersedes any in-flight one: bump the id so the old callback
    -- is ignored when it returns, then proceed. (No "still waiting" rejection.)
    M.seq = M.seq + 1
    local id = M.seq
    M.current = id
    M.busy = true

    -- Build the messages array: prior history (if any) + the new user message.
    local messages = {}
    if type(history) == "table" then
        for _, m in ipairs(history) do messages[#messages + 1] = m end
    end
    messages[#messages + 1] = { role = "user", content = user }

    local ok, url, options = pcall(prov.build_request, cfg, system, messages)
    if not ok then
        if id == M.current then M.busy = false end
        return on_result(nil, "Failed to build request: " .. tostring(url))
    end

    -- Debug: log exactly what is sent (API key redacted). Appears in the Balatro
    -- console / log file. Toggle via config.debug_log.
    if cfg.debug_log and sendInfoMessage then
        local safe_url = tostring(url):gsub("key=[^&]+", "key=***")
        sendInfoMessage("POST " .. safe_url .. " (model=" .. tostring(cfg.model ~= "" and cfg.model or "default") .. ")", "BalaGPTro")
        sendInfoMessage("PROMPT >>>\n" .. tostring(user), "BalaGPTro")
    end

    local done = false
    https.asyncRequest(url, options, function(code, body, _headers)
        if done then return end
        done = true
        defer(function()
            if id ~= M.current then return end  -- superseded/cancelled: drop stale result
            M.busy = false
            local text, err = prov.parse_response(code, body)
            if cfg.debug_log and sendInfoMessage then
                sendInfoMessage("RESPONSE (code " .. tostring(code) .. ") <<<\n" .. tostring(text or err), "BalaGPTro")
                -- Log the raw body (truncated) when parsing produced no text, to debug empties.
                if not text or text == "" then
                    sendInfoMessage("RAW BODY: " .. tostring(body or ""):sub(1, 1200), "BalaGPTro")
                end
            end
            on_result(text, err)
        end)
    end)
end

return M
