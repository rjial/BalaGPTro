--- BalaGPTro — BYOK AI advisor & chat for Balatro.
--- Entry point: wires modules, exposes them on the global `BalaGPTro`, and
--- registers the settings tab + overlay UI.

local mod = SMODS.current_mod
local path = mod.path:gsub("/$", "")
package.path = package.path .. string.format(";%s/src/?.lua", path)

BalaGPTro = {
    mod = mod,
    config = mod.config,            -- persisted table managed by SMODS
    ui = { response = "", input = "", status = "idle" },
    playlog = {},                   -- rolling log of hands played this run
}

-- Make config.lua authoritative: re-read it each launch and overwrite the
-- SMODS-persisted config. Edits to config.lua always take effect; changes made
-- in the in-game settings tab last only for the current session.
do
    local chunk = loadfile(path .. "/config.lua")
    if chunk then
        local ok, defaults = pcall(chunk)
        if ok and type(defaults) == "table" then
            for k, v in pairs(defaults) do mod.config[k] = v end
        end
    end
end

BalaGPTro.prompts   = require("prompts")
BalaGPTro.state     = require("state")
BalaGPTro.providers = require("providers")
BalaGPTro.client    = require("client")
BalaGPTro.score     = require("score")

require("ui_settings")   -- sets mod.config_tab
require("ui_overlay")    -- registers G.FUNCS + keybind

-- Hook "play hand" to log which poker hand + cards the player actually plays this
-- run (the game keeps no retrievable list), so Advice can see recent plays.
local orig_play = G.FUNCS.play_cards_from_highlighted
G.FUNCS.play_cards_from_highlighted = function(e)
    pcall(function()
        local cards = G.hand and G.hand.highlighted
        if cards and #cards > 0 then
            local ok, hand_key = pcall(G.FUNCS.get_poker_hand_info, cards)
            local names = {}
            for _, c in ipairs(cards) do
                if c.base then names[#names + 1] = tostring(c.base.value) .. (c.base.suit and (" of " .. c.base.suit) or "") end
            end
            BalaGPTro.playlog[#BalaGPTro.playlog + 1] = {
                ante = G.GAME and G.GAME.round_resets and G.GAME.round_resets.ante,
                hand = ok and hand_key or "?",
                cards = names,
            }
            while #BalaGPTro.playlog > 8 do table.remove(BalaGPTro.playlog, 1) end
        end
    end)
    return orig_play(e)
end

-- Clear the play log and (re)create the on-screen toggle button on a new run.
local orig_start = G.FUNCS.start_run
if orig_start then
    G.FUNCS.start_run = function(e, args)
        BalaGPTro.playlog = {}
        local r = orig_start(e, args)
        pcall(function() BalaGPTro.remove_toggle(); BalaGPTro.make_toggle() end)
        return r
    end
end

-- Remove the panel + toggle button when leaving to the main menu.
local orig_menu = G.FUNCS.go_to_menu
if orig_menu then
    G.FUNCS.go_to_menu = function(e)
        pcall(function() G.FUNCS.balagpt_close(); BalaGPTro.remove_toggle() end)
        return orig_menu(e)
    end
end

-- Keybind: open the AI panel at any time with F6.
SMODS.Keybind {
    key = "balagpt_open",
    key_pressed = "f6",
    event = "pressed",
    action = function()
        G.FUNCS.balagpt_open()
    end,
}

-- If a run is already active when the mod loads (e.g. continued run), show the button.
pcall(function() if G.ROOM_ATTACH then BalaGPTro.make_toggle() end end)

sendInfoMessage("BalaGPTro loaded (provider=" .. tostring(BalaGPTro.config.provider) .. ")", "BalaGPTro")
