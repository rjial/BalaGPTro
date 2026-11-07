--- Settings page shown in the SMODS mods menu (mod.config_tab).

local providers = require "providers"

local PROVIDER_LABELS = { "Anthropic", "OpenAI", "Gemini" }

local function provider_index()
    for i, key in ipairs(providers.order) do
        if key == BalaGPTro.config.provider then return i end
    end
    return 1
end

G.FUNCS.balagpt_set_provider = function(args)
    local i = args.to_key or args.to_val or 1
    BalaGPTro.config.provider = providers.order[i] or "anthropic"
end

-- Presets: one click sets provider + base_url + a sensible model, so the player
-- never has to type "/" or ":" into Balatro's restricted text fields.
local PRESETS = {
    { name = "OpenAI",     provider = "openai",    base_url = "",                               model = "gpt-4o" },
    { name = "Anthropic",  provider = "anthropic", base_url = "",                               model = "claude-opus-4-8" },
    { name = "OpenRouter", provider = "openai",    base_url = "https://openrouter.ai/api/v1",   model = "anthropic/claude-3.5-sonnet" },
    { name = "Groq",       provider = "openai",    base_url = "https://api.groq.com/openai/v1", model = "llama-3.3-70b-versatile" },
    { name = "Ollama",     provider = "openai",    base_url = "http://localhost:11434/v1",       model = "llama3.1" },
    { name = "LM Studio",  provider = "openai",    base_url = "http://localhost:1234/v1",         model = "" },
    { name = "Sumopod",    provider = "openai",    base_url = "https://ai.sumopod.com/v1",        model = "" },
}
for _, p in ipairs(PRESETS) do
    G.FUNCS["balagpt_preset_" .. p.name:gsub("%s", "")] = function(e)
        BalaGPTro.config.provider = p.provider
        BalaGPTro.config.base_url = p.base_url
        BalaGPTro.config.model = p.model
        -- Do NOT close the menu. Values are stored immediately; update the live
        -- "Current:" label in place so the player sees the change without the
        -- window disappearing. (Text-input fields refresh on next reopen.)
        if BalaGPTro.ui and BalaGPTro.ui.preset_label and BalaGPTro.ui.preset_label.config then
            BalaGPTro.ui.preset_label.config.text = "Current: " ..
                (p.base_url ~= "" and p.base_url or "(default endpoint)") ..
                "  |  model: " .. (p.model ~= "" and p.model or "(provider default)")
            if e and e.UIBox then e.UIBox:recalculate() end
        end
    end
end

-- Buttons must be COLUMN nodes (col=true) to sit side-by-side: the layout engine
-- advances the cursor DOWN after an R-type child and RIGHT after a C-type child,
-- and UIBox_button returns an R node unless col=true.
local function preset_buttons(from, to)
    local cols = {}
    for i = from, to do
        local p = PRESETS[i]
        if p then
            cols[#cols + 1] = UIBox_button {
                button = "balagpt_preset_" .. p.name:gsub("%s", ""),
                label = { p.name }, colour = G.C.BLUE, minw = 2.1, minh = 0.5, scale = 0.32,
                col = true,
            }
        end
    end
    return cols
end

local function row(node) return { n = G.UIT.R, config = { align = "cm", padding = 0.08 }, nodes = { node } } end

local function text_field(label, ref_value, w)
    return {
        n = G.UIT.R,
        config = { align = "cm", padding = 0.08 },
        nodes = {
            { n = G.UIT.T, config = { text = label, scale = 0.38, colour = G.C.UI.TEXT_LIGHT } },
            create_text_input {
                w = w or 6,
                max_length = 400,
                prompt_text = label,
                ref_table = BalaGPTro.config,
                ref_value = ref_value,
                extended_corpus = true,
                keyboard_offset = 1,
            },
        },
    }
end

local function note(text, scale)
    return row { n = G.UIT.T, config = { text = text, scale = scale or 0.32, colour = G.C.UI.TEXT_DARK } }
end

BalaGPTro.mod.config_tab = function()
    local cfg = BalaGPTro.config

    -- Live "Current:" label (updated in place by a preset click).
    local current_label = {
        n = G.UIT.T,
        config = { text = "Current: " .. tostring(cfg.base_url ~= "" and cfg.base_url or "(default endpoint)")
            .. "  |  model: " .. tostring(cfg.model ~= "" and cfg.model or "(provider default)"),
            scale = 0.3, colour = G.C.UI.TEXT_DARK },
    }
    BalaGPTro.ui.preset_label = current_label

    -- LEFT column: provider, presets, endpoint fields.
    local left = { n = G.UIT.C, config = { align = "tl", padding = 0.08 }, nodes = {
        row { n = G.UIT.T, config = { text = "Provider & endpoint", scale = 0.4, colour = G.C.UI.TEXT_LIGHT } },
        row(create_option_cycle {
            label = "Provider", scale = 0.7, w = 4,
            options = PROVIDER_LABELS, current_option = provider_index(), opt_callback = "balagpt_set_provider",
        }),
        note("Presets (set provider + URL + model):", 0.33),
        { n = G.UIT.R, config = { align = "cm", padding = 0.05 }, nodes = preset_buttons(1, 3) },
        { n = G.UIT.R, config = { align = "cm", padding = 0.05 }, nodes = preset_buttons(4, 6) },
        { n = G.UIT.R, config = { align = "cm", padding = 0.05 }, nodes = preset_buttons(7, 9) },
        row(current_label),
        text_field("API Key (plaintext)", "api_key", 6),
        text_field("Model (blank = default)", "model", 6),
        text_field("Base URL (optional)", "base_url", 6),
    } }

    -- RIGHT column: toggles + notes.
    local right = { n = G.UIT.C, config = { align = "tl", padding = 0.08 }, nodes = {
        row { n = G.UIT.T, config = { text = "Options", scale = 0.4, colour = G.C.UI.TEXT_LIGHT } },
        row(create_toggle { label = "Advisor enabled", ref_table = cfg, ref_value = "advisor_enabled" }),
        row(create_toggle { label = "Chat enabled", ref_table = cfg, ref_value = "chat_enabled" }),
        row(create_toggle { label = "Auto-advise each new hand", ref_table = cfg, ref_value = "auto_advise_on_draw" }),
        row(create_toggle { label = "On-screen AI button", ref_table = cfg, ref_value = "toggle_button" }),
        row(create_toggle { label = "Debug: log to console", ref_table = cfg, ref_value = "debug_log" }),
        note("Open the AI panel in a run with F6."),
        note("URL/model with '/' or ':'? Edit config.lua", 0.3),
        note("(the game blocks those keys in text fields).", 0.3),
    } }

    return {
        n = G.UIT.ROOT,
        config = { emboss = 0.05, minh = 6, r = 0.1, minw = 8, align = "tm", padding = 0.12, colour = G.C.BLACK },
        nodes = {
            row { n = G.UIT.T, config = { text = "BalaGPTro — BYOK AI Advisor", scale = 0.5, colour = G.C.UI.TEXT_LIGHT } },
            { n = G.UIT.R, config = { align = "tm", padding = 0.1 }, nodes = { left, right } },
        },
    }
end
