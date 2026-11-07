--- Score prediction. Tier 1 (default): read the game's own poker-hand level data
--- for the base chips x mult of the selected cards, then let the LLM reason the
--- full joker build-up. Tier 2 (exact simulation) is not implemented yet and the
--- config flag falls back to Tier 1.

local prompts = require "prompts"
local client = require "client"
local state_mod = require "state"

local M = {}

-- Base chips/mult (already level-adjusted) for the current card selection.
function M.base()
    local cards = G.hand and G.hand.highlighted
    if not cards or #cards == 0 then return nil, "Select the cards you want to play first." end

    local ok, hand_key = pcall(G.FUNCS.get_poker_hand_info, cards)
    if not ok or not hand_key then return nil, "Could not identify the poker hand." end

    local h = G.GAME and G.GAME.hands and G.GAME.hands[hand_key]
    if not h then return nil, "Could not read hand level data." end

    return { hand = hand_key, chips = h.chips, mult = h.mult, level = h.level }, nil
end

-- Predict the final score. on_result(text, err). `history` (optional) is passed
-- through for conversational continuity.
function M.predict(on_result, history)
    local b, err = M.base()
    if not b then return on_result(nil, err) end

    if BalaGPTro.config.score_exact_sim then
        sendWarnMessage("Tier-2 exact simulation not implemented; using Tier-1 estimate.", "BalaGPTro")
    end

    local state_text = state_mod.to_prompt()
    local user = prompts.score(state_text, b.chips, b.mult, b.hand)
    client.ask(prompts.system, user, function(text, e)
        if text then
            on_result(string.format("%s (lvl %s) — base %s x %s\n\n%s",
                b.hand, tostring(b.level), tostring(b.chips), tostring(b.mult), text), nil)
        else
            on_result(nil, e)
        end
    end, history)
end

return M
