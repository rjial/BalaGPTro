--- The in-run AI panel: advice, free-form chat, and score prediction.
--- Opened with F6 (see main.lua) or G.FUNCS.balagpt_open().
---
--- The response area has a FIXED height: the full answer is wrapped into
--- BalaGPTro.ui.all_lines, and only PAGE lines are shown at once. ◀/▶ page
--- through long answers so the window never grows. All visible text is bound to
--- tables via ref_table/ref_value, so paging and new answers only mutate the
--- tables and call recalculate() — the overlay is never torn down (no flash).

local state_mod = require "state"
local client = require "client"
local score = require "score"
local prompts = require "prompts"
local DraggableContainer = require "draggable_container"

local WRAP = 60
local PAGE = 9           -- visible response rows
local MAX_LINES = 200    -- safety cap on total wrapped lines

local function ensure()
    local ui = BalaGPTro.ui
    ui.all_lines = ui.all_lines or {}
    ui.view = ui.view or {}
    for i = 1, PAGE do ui.view[i] = ui.view[i] or " " end
    ui.page = ui.page or 0
    ui.page_text = ui.page_text or ""
    ui.status_text = ui.status_text or "Ready"
    ui.chat_history = ui.chat_history or {}
    if ui.busy == nil then ui.busy = false end
end

-- Render the current page into the bound view slots + page indicator.
local function render_page()
    local ui = BalaGPTro.ui
    local total = #ui.all_lines
    local pages = math.max(1, math.ceil(total / PAGE))
    if ui.page < 0 then ui.page = 0 end
    if ui.page > pages - 1 then ui.page = pages - 1 end
    for i = 1, PAGE do
        local s = ui.all_lines[ui.page * PAGE + i]
        ui.view[i] = (s == nil or s == "") and " " or s
    end
    ui.page_text = (total > PAGE) and string.format("page %d/%d", ui.page + 1, pages) or " "
end

-- Word-wrap text into BalaGPTro.ui.all_lines.
local function set_lines(text)
    local out = {}
    for raw in tostring(text or ""):gmatch("[^\n]*") do
        if raw == "" then
            out[#out + 1] = ""
        else
            local cur = ""
            for word in raw:gmatch("%S+") do
                if #cur + #word + 1 > WRAP then
                    out[#out + 1] = cur; cur = word
                else
                    cur = (cur == "") and word or (cur .. " " .. word)
                end
            end
            if cur ~= "" then out[#out + 1] = cur end
        end
        if #out >= MAX_LINES then break end
    end
    BalaGPTro.ui.all_lines = out
    BalaGPTro.ui.page = 0
    render_page()
end

-- Recalculate the floating panel in place (bound text re-reads on recalculate).
local function recalc()
    local box = BalaGPTro.ui.box
    if box and box.recalculate then pcall(function() box:recalculate() end) end
end

-- Recreate the panel at its current position. Used to reset the chat text input:
-- the input widget keeps its own internal letters, so clearing the ref value is
-- not enough — rebuilding gives a fresh empty field in sync with the ref.
local function rebuild()
    local box = BalaGPTro.ui.box
    if not box then return end
    BalaGPTro.ui.pos = { x = box.T.x, y = box.T.y }
    pcall(function() box:remove() end)
    BalaGPTro.ui.box = nil
    G.FUNCS.balagpt_open()
end

-- Status also drives the `busy` flag: while thinking, action buttons are disabled.
local function set_status(s)
    BalaGPTro.ui.status_text = s
    BalaGPTro.ui.busy = (s == "Thinking…")
    recalc()
end

-- Button `func` (runs each update): grey the action buttons while busy. The button
-- stays set (so this func keeps running); the action itself no-ops while busy.
G.FUNCS.balagpt_btn_state = function(e)
    local rt = e.config.ref_table
    e.config.colour = BalaGPTro.ui.busy and G.C.UI.BACKGROUND_INACTIVE or (rt and rt.base) or e.config.colour
end

local function has_text(t) return t and t:gsub("%s", "") ~= "" end

-- Append an exchange to the shared conversation history (capped) so follow-ups —
-- including answering a question the model asked back — keep context.
local function push_history(user_content, assistant_content)
    BalaGPTro.ui.chat_history = BalaGPTro.ui.chat_history or {}
    local h = BalaGPTro.ui.chat_history
    h[#h + 1] = { role = "user", content = user_content }
    h[#h + 1] = { role = "assistant", content = assistant_content }
    while #h > 8 do table.remove(h, 1) end
end

local function handle(text, err)
    if has_text(text) then
        set_lines(text)
    else
        set_lines("⚠ " .. tostring(err or "Empty reply from the model. Try again."))
    end
    set_status("Ready")  -- also clears the busy flag and re-enables buttons
end

-- Handle a result AND record it in history under a short marker (for advice/predict).
local function handle_and_record(marker)
    return function(text, err)
        if has_text(text) then push_history(marker, text) end
        handle(text, err)
    end
end

-------------------------------------------------------------------- actions
G.FUNCS.balagpt_advise = function()
    if BalaGPTro.ui.busy then return end
    if not BalaGPTro.config.advisor_enabled then return handle("Advisor is disabled in config.") end
    set_status("Thinking…")
    local snap = state_mod.capture()
    client.ask(prompts.system, prompts.advisor(state_mod.to_prompt(snap), snap.phase),
        handle_and_record("[I asked you for advice on the current situation]"),
        BalaGPTro.ui.chat_history)   -- include prior conversation for continuity
end

G.FUNCS.balagpt_predict = function()
    if BalaGPTro.ui.busy then return end
    set_status("Thinking…")
    score.predict(handle_and_record("[I asked you to predict my score]"), BalaGPTro.ui.chat_history)
end

G.FUNCS.balagpt_chat_send = function()
    if BalaGPTro.ui.busy then return end
    if not BalaGPTro.config.chat_enabled then return handle("Chat is disabled in config.") end
    local q = BalaGPTro.ui.input or ""
    if q:gsub("%s", "") == "" then return handle("Type a question first.") end
    set_status("Thinking…")
    BalaGPTro.ui.chat_history = BalaGPTro.ui.chat_history or {}
    local history = BalaGPTro.ui.chat_history
    -- The new message carries the current state; prior turns are stored as the raw
    -- question + answer (no state) to keep the running history cheap.
    client.ask(prompts.system, prompts.chat(state_mod.to_prompt(), q), function(text, err)
        local ok = text and text:gsub("%s", "") ~= ""
        if ok then
            history[#history + 1] = { role = "user", content = q }
            history[#history + 1] = { role = "assistant", content = text }
            while #history > 6 do table.remove(history, 1) end  -- keep last 3 exchanges
            BalaGPTro.ui.input = ""
        end
        handle(text, err)
        if ok then rebuild() end   -- recreate panel so the input box is truly empty
    end, history)
end

G.FUNCS.balagpt_chat_clear = function()
    BalaGPTro.ui.chat_history = {}
    handle("Chat history cleared.")
end

G.FUNCS.balagpt_cancel = function()
    client.cancel()
    set_status("Ready")
end

G.FUNCS.balagpt_page_prev = function() BalaGPTro.ui.page = BalaGPTro.ui.page - 1; render_page(); recalc() end
G.FUNCS.balagpt_page_next = function() BalaGPTro.ui.page = BalaGPTro.ui.page + 1; render_page(); recalc() end

-------------------------------------------------------------------- panel
local function bound_line_row(i)
    return { n = G.UIT.R, config = { align = "cl", padding = 0.01 }, nodes = {
        { n = G.UIT.T, config = { ref_table = BalaGPTro.ui.view, ref_value = i,
            scale = 0.32, colour = G.C.UI.TEXT_LIGHT } },
    } }
end

-- Build the floating panel's node tree (its own ROOT; not an overlay menu).
local function panel_definition()
    local resp_rows = {}
    for i = 1, PAGE do resp_rows[#resp_rows + 1] = bound_line_row(i) end

    -- LEFT column: title + response box + pager.
    local left = { n = G.UIT.C, config = { align = "tl", padding = 0.06 }, nodes = {
        { n = G.UIT.R, config = { align = "cl", padding = 0.04 }, nodes = {
            { n = G.UIT.T, config = { ref_table = BalaGPTro.ui, ref_value = "status_text", scale = 0.35, colour = G.C.ORANGE } },
        } },
        { n = G.UIT.R,
          config = { align = "tm", padding = 0.08, r = 0.1, colour = G.C.GREY, emboss = 0.05, minw = 7, minh = 4.0 },
          nodes = { { n = G.UIT.C, config = { align = "tl", padding = 0.06 }, nodes = resp_rows } },
        },
        { n = G.UIT.R, config = { align = "cm", padding = 0.04 }, nodes = {
            UIBox_button { button = "balagpt_page_prev", label = { "<" }, colour = G.C.GREY, minw = 1.2, minh = 0.5, scale = 0.4, col = true },
            { n = G.UIT.T, config = { ref_table = BalaGPTro.ui, ref_value = "page_text", scale = 0.32, colour = G.C.UI.TEXT_LIGHT } },
            UIBox_button { button = "balagpt_page_next", label = { ">" }, colour = G.C.GREY, minw = 1.2, minh = 0.5, scale = 0.4, col = true },
        } },
    } }

    -- RIGHT column: input + action buttons.
    local right = { n = G.UIT.C, config = { align = "tm", padding = 0.06 }, nodes = {
        { n = G.UIT.R, config = { align = "cm", padding = 0.06 }, nodes = {
            create_text_input {
                id = "balagpt_chat_input",
                w = 4.2, h = 0.8, max_length = 200, prompt_text = "Click, then type",
                ref_table = BalaGPTro.ui, ref_value = "input", extended_corpus = true,
                callback = function() G.FUNCS.balagpt_chat_send() end,  -- Enter sends
            },
        } },
        { n = G.UIT.R, config = { align = "cm", padding = 0.05 }, nodes = {
            UIBox_button { button = "balagpt_chat_send", label = { "Send" }, colour = G.C.GREEN, minw = 4.2, minh = 0.5, scale = 0.38,
                func = "balagpt_btn_state", ref_table = { base = G.C.GREEN, action = "balagpt_chat_send" } },
        } },
        { n = G.UIT.R, config = { align = "cm", padding = 0.05 }, nodes = {
            UIBox_button { button = "balagpt_advise", label = { "Advice" }, colour = G.C.BLUE, minw = 4.2, minh = 0.5, scale = 0.38,
                func = "balagpt_btn_state", ref_table = { base = G.C.BLUE, action = "balagpt_advise" } },
        } },
        { n = G.UIT.R, config = { align = "cm", padding = 0.05 }, nodes = {
            UIBox_button { button = "balagpt_predict", label = { "Predict score" }, colour = G.C.PURPLE, minw = 4.2, minh = 0.5, scale = 0.38,
                func = "balagpt_btn_state", ref_table = { base = G.C.PURPLE, action = "balagpt_predict" } },
        } },
        { n = G.UIT.R, config = { align = "cm", padding = 0.05 }, nodes = {
            UIBox_button { button = "balagpt_cancel", label = { "Cancel" }, colour = G.C.ORANGE, minw = 2, minh = 0.45, scale = 0.34, col = true },
            UIBox_button { button = "balagpt_chat_clear", label = { "Clear chat" }, colour = G.C.GREY, minw = 2.2, minh = 0.45, scale = 0.34, col = true },
        } },
        { n = G.UIT.R, config = { align = "cm", padding = 0.05 }, nodes = {
            UIBox_button { button = "balagpt_close", label = { "Close (F6)" }, colour = G.C.RED, minw = 4.2, minh = 0.5, scale = 0.38 },
        } },
    } }

    return { n = G.UIT.ROOT, config = {
        align = "cm", padding = 0.1, r = 0.1, colour = { G.C.BLACK[1], G.C.BLACK[2], G.C.BLACK[3], 0.92 },
        emboss = 0.08, minw = 1, minh = 1,
    }, nodes = {
        { n = G.UIT.R, config = { align = "cm", padding = 0.04 }, nodes = {
            { n = G.UIT.T, config = { text = "BalaGPTro — drag me aside to click cards", scale = 0.28, colour = G.C.UI.TEXT_DARK } },
        } },
        { n = G.UIT.R, config = { align = "tm", padding = 0.04 }, nodes = { left, right } },
    } }
end

G.FUNCS.balagpt_close = function()
    if BalaGPTro.ui.box then
        pcall(function() BalaGPTro.ui.box:remove() end)
        BalaGPTro.ui.box = nil
    end
end

-- Persistent on-screen "AI" toggle button (alternative to the F6 keybind). It is a
-- tiny floating, draggable box; clicking it toggles the main panel.
function BalaGPTro.make_toggle()
    if BalaGPTro.ui.toggle_box then return end
    if BalaGPTro.config.toggle_button == false then return end
    if not G.ROOM_ATTACH then return end
    local rw = (G.ROOM and G.ROOM.T and G.ROOM.T.w) or 20
    local pos = BalaGPTro.ui.toggle_pos or { x = math.max(2, rw - 2.4), y = 3.6 }
    -- No inner UIBox_button: the CONTAINER itself is the click+drag target (like a
    -- Balatro card), so a quick click opens the panel and a press-drag moves it.
    local def = { n = G.UIT.ROOT, config = {
        align = "cm", padding = 0.12, r = 0.1, colour = G.C.BLUE, emboss = 0.05, minw = 1.3, minh = 0.6,
    }, nodes = {
        { n = G.UIT.R, config = { align = "cm" }, nodes = {
            { n = G.UIT.T, config = { text = "AI", scale = 0.45, colour = G.C.UI.TEXT_LIGHT } },
        } },
    } }
    local box = DraggableContainer {
        T = { x = pos.x, y = pos.y }, VT = { x = pos.x, y = pos.y },
        config = { major = G, bond = "Weak" }, definition = def, can_drag = true,
    }
    box.states.drag.can = true
    box.states.click.can = true
    box.click = function() G.FUNCS.balagpt_open() end   -- quick click toggles the panel
    local base_stop = box.stop_drag
    box.stop_drag = function(self) base_stop(self); BalaGPTro.ui.toggle_pos = { x = self.T.x, y = self.T.y } end
    BalaGPTro.ui.toggle_box = box
end

function BalaGPTro.remove_toggle()
    if BalaGPTro.ui.toggle_box then
        pcall(function() BalaGPTro.ui.toggle_box:remove() end)
        BalaGPTro.ui.toggle_box = nil
    end
end

-- F6 toggles the floating panel. It coexists with the game (not a modal overlay),
-- so you can keep playing while reading advice. Drag it anywhere by its body.
G.FUNCS.balagpt_open = function()
    ensure()
    if BalaGPTro.ui.box then return G.FUNCS.balagpt_close() end  -- toggle off
    if not G.ROOM_ATTACH then return end                        -- only inside the game room

    if #BalaGPTro.ui.all_lines == 0 then
        set_lines("Ask for advice, type a question, or predict your score.")
    end

    -- A DraggableContainer (UIBox subclass, major = G) is what makes the panel
    -- truly floating & draggable — the same proven approach as the SystemClock mod.
    -- Default to the top-right so it clears the consumable slots (top-left) and the
    -- pack/play cards (bottom-centre); the panel blocks clicks where it sits, so
    -- drag it aside if it ever covers something you need to click.
    local pos = BalaGPTro.ui.pos
    if not pos then
        local rw = (G.ROOM and G.ROOM.T and G.ROOM.T.w) or 20
        pos = { x = math.max(2, rw - 5.2), y = 0.3 }
    end
    local box = DraggableContainer {
        T = { x = pos.x, y = pos.y },
        VT = { x = pos.x, y = pos.y },
        config = { major = G, bond = "Weak" },
        definition = panel_definition(),
        can_drag = true,
    }
    -- Persist position across toggles.
    local base_stop = box.stop_drag
    box.stop_drag = function(self)
        base_stop(self)
        BalaGPTro.ui.pos = { x = self.T.x, y = self.T.y }
    end
    BalaGPTro.ui.box = box
end
