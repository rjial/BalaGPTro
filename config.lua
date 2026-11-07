return {
    provider = "anthropic",          -- "anthropic" | "openai" | "gemini"
    api_key = "",                    -- WARNING: stored in plaintext in this file
    model = "",                      -- empty = provider default (see providers.lua)
    base_url = "",                   -- optional override (proxies / OpenAI-compatible)
    max_tokens = 600,
    language = "Indonesian",         -- reply language for auto-advice/score (chat mirrors your question)

    advisor_enabled = true,
    chat_enabled = true,
    auto_advise_on_draw = false,     -- fire advice automatically each new hand (off by default: costs tokens)
    score_exact_sim = false,         -- Tier 2 exact score simulation (experimental, may break across patches)
    debug_log = false,               -- log the full state/prompt sent to the AI into the Balatro console
    toggle_button = true,            -- show an on-screen "AI" button (alternative to the F6 keybind)
}
