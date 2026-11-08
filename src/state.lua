--- Reads Balatro's live game state into a compact, token-light text block,
--- resolving each joker/consumable/shop item to its ACTUAL effect (not just a
--- name) via localization + the card's current `ability` values.

local M = {}

local desc_cache = {}  -- [set..":"..key] = cleaned description template

-- Strip Balatro loc formatting tags: {C:red}, {X:mult,C:white}, {}, {s:0.8} ...
local function strip_tags(s)
    return (s:gsub("{[^}]*}", ""))
end

-- Join + clean a localization description (table of lines) into one line.
local function resolve_desc(set, key)
    if not set or not key then return nil end
    local ck = set .. ":" .. key
    if desc_cache[ck] ~= nil then return desc_cache[ck] end
    local out = nil
    local loc = G.localization and G.localization.descriptions
    local entry = loc and loc[set] and loc[set][key]
    if entry and entry.text then
        local parts = {}
        for _, line in ipairs(entry.text) do parts[#parts + 1] = strip_tags(line) end
        out = table.concat(parts, " "):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
        if out == "" then out = nil end
    end
    desc_cache[ck] = out or false
    return out
end

-- Compact dump of the live numeric values on a card's ability table. These are
-- the CURRENT scaled values (e.g. a joker that grew to x5 mult), sent alongside
-- the ability description template so the AI knows the real numbers right now.
local function ability_values(card)
    local a = card and card.ability
    if type(a) ~= "table" then return nil end
    local keys = {
        "mult", "t_mult", "x_mult", "Xmult", "chips", "t_chips", "x_chips",
        "h_x_mult", "h_mult", "h_chips", "h_size", "d_size",
        "extra_value", "money", "dollars", "repetitions", "perma_bonus",
        "a_mult", "a_chips", "a_xmult", "size", "bonus", "hands", "discards",
    }
    local seen, bits = {}, {}
    local function add(k, v)
        if type(v) == "number" and v ~= 0 and not seen[k] then
            seen[k] = true; bits[#bits + 1] = k .. "=" .. tostring(v)
        end
    end
    for _, k in ipairs(keys) do add(k, a[k]) end
    -- Many jokers keep their scaling value(s) in ability.extra.
    if type(a.extra) == "number" then
        add("extra", a.extra)
    elseif type(a.extra) == "table" then
        for k, v in pairs(a.extra) do if type(v) == "number" then add("extra." .. tostring(k), v) end end
    end
    return (#bits > 0) and table.concat(bits, ",") or nil
end

local function center_of(card)
    return card and card.config and card.config.center
end

-- Recursively collect text from a generated UI node tree.
local function collect_text(node, out)
    if type(node) ~= "table" then return end
    if node.config and type(node.config.text) == "string" then out[#out + 1] = node.config.text end
    if node.nodes then for _, n in ipairs(node.nodes) do collect_text(n, out) end end
    for i = 1, #node do collect_text(node[i], out) end  -- `main` is an array of rows
end

-- Fallback for cards with NO registered localization description (e.g. some
-- modded jokers): render the card's own ability tooltip and extract its text.
local function generated_desc(card)
    if not card or type(card.generate_UIBox_ability_table) ~= "function" then return nil end
    local ok, t = pcall(function() return card:generate_UIBox_ability_table() end)
    if not ok or type(t) ~= "table" or not t.main then return nil end
    local parts = {}
    collect_text(t.main, parts)
    local s = table.concat(parts, " "):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
    return s ~= "" and s or nil
end

-- One-line description of a special card (joker / consumable / voucher / booster).
-- `in_shop` makes the price read as the BUY cost (card.cost) instead of sell value.
local function describe_special(card, in_shop)
    local c = center_of(card)
    if not c then return "?" end
    local name = (card.ability and card.ability.name) or c.name or c.key or "?"
    -- Prefer the registered localization template; fall back to rendering the
    -- card's own tooltip for modded cards that ship no description.
    local desc = resolve_desc(c.set, c.key) or generated_desc(card)
    local vals = ability_values(card)
    local line = name
    -- Planets (and anything with a target hand) level a specific poker hand; the
    -- template description leaves the hand name as a placeholder, so state it here.
    if c.config and c.config.hand_type then line = line .. " — levels " .. tostring(c.config.hand_type) end
    if desc then line = line .. " — " .. desc end
    if vals then line = line .. " [" .. vals .. "]" end
    if card.edition and card.edition.key then line = line .. " (" .. card.edition.key .. ")" end
    if card.debuff then line = line .. " [DEBUFFED]" end
    if in_shop then
        if card.cost then line = line .. " — buy $" .. tostring(card.cost) end
    elseif card.sell_cost then
        line = line .. " — sell $" .. tostring(card.sell_cost)
    end
    return line
end

-- One-line description of a playing card.
local function describe_playing(card)
    if not card or not card.base then return "?" end
    local s = (card.base.value or "?") .. " of " .. (card.base.suit or "?")
    local c = center_of(card)
    if c and c.key and c.key ~= "c_base" and c.set == "Enhanced" then
        s = s .. " +" .. (c.name or c.key)
    end
    if card.edition and card.edition.key then s = s .. " (" .. card.edition.key .. ")" end
    if card.seal then s = s .. " [" .. tostring(card.seal) .. " seal]" end
    if card.debuff then s = s .. " [DEBUFFED by blind]" end
    return s
end

local function list_special(area, in_shop)
    local out = {}
    if area and area.cards then
        for _, c in ipairs(area.cards) do out[#out + 1] = describe_special(c, in_shop) end
    end
    return out
end

local function list_playing(area)
    local out = {}
    if area and area.cards then
        for _, c in ipairs(area.cards) do out[#out + 1] = describe_playing(c) end
    end
    return out
end

-- Compact summary of the undrawn draw pile (G.deck): total + suit & rank tallies,
-- so the AI can reason about draw odds after a discard without listing every card.
local function deck_summary(area)
    if not area or not area.cards or #area.cards == 0 then return nil end
    local suits, ranks, total = {}, {}, 0
    for _, c in ipairs(area.cards) do
        if c.base then
            total = total + 1
            local su, ra = c.base.suit, c.base.value
            if su then suits[su] = (suits[su] or 0) + 1 end
            if ra then ranks[ra] = (ranks[ra] or 0) + 1 end
        end
    end
    local function fmt(t, order)
        local parts = {}
        if order then
            for _, k in ipairs(order) do if t[k] then parts[#parts + 1] = k .. ":" .. t[k] end end
        else
            local keys = {}
            for k in pairs(t) do keys[#keys + 1] = k end
            table.sort(keys)
            for _, k in ipairs(keys) do parts[#parts + 1] = k .. ":" .. t[k] end
        end
        return table.concat(parts, " ")
    end
    local rank_order = { "Ace", "King", "Queen", "Jack", "10", "9", "8", "7", "6", "5", "4", "3", "2" }
    return { total = total, suits = fmt(suits), ranks = fmt(ranks, rank_order) }
end

-- Tally the cards currently in hand by rank and suit, and derive the hand types
-- that are actually POSSIBLE from them. The LLM is unreliable at classifying a
-- hand by eye (e.g. calling two pair a full house), so hand it the raw counts
-- plus a factual feasibility line it only has to read, not compute.
local function hand_composition(area)
    if not area or not area.cards or #area.cards == 0 then return nil end
    local ranks, suits = {}, {}
    for _, c in ipairs(area.cards) do
        if c.base then
            local ra, su = c.base.value, c.base.suit
            if ra then ranks[ra] = (ranks[ra] or 0) + 1 end
            if su then suits[su] = (suits[su] or 0) + 1 end
        end
    end
    local max_same, pairs_n, trips_n, quad = 0, 0, 0, 0
    local rparts = {}
    for ra, n in pairs(ranks) do
        rparts[#rparts + 1] = ra .. "x" .. n
        if n > max_same then max_same = n end
        if n >= 2 then pairs_n = pairs_n + 1 end
        if n >= 3 then trips_n = trips_n + 1 end
        if n >= 4 then quad = quad + 1 end
    end
    table.sort(rparts)
    local max_suit, sparts = 0, {}
    for su, n in pairs(suits) do
        sparts[#sparts + 1] = su .. "x" .. n
        if n > max_suit then max_suit = n end
    end
    table.sort(sparts)
    -- What the counts permit (defaults; joker exceptions handled by the model).
    local can = {}
    if quad >= 1 then can[#can + 1] = "Four of a Kind" end
    if trips_n >= 1 and (pairs_n >= 2 or trips_n >= 2) then can[#can + 1] = "Full House" end
    if trips_n >= 1 then can[#can + 1] = "Three of a Kind" end
    if pairs_n >= 2 then can[#can + 1] = "Two Pair" end
    if pairs_n >= 1 then can[#can + 1] = "Pair" end
    if max_suit >= 5 then can[#can + 1] = "Flush (5 same suit available)" end
    local notes = {}
    if trips_n == 0 then notes[#notes + 1] = "no three-of-a-kind present, so Full House and Four of a Kind are IMPOSSIBLE" end
    if max_suit < 5 then notes[#notes + 1] = "no suit has 5 cards, so a Flush is not available" end
    return {
        ranks = table.concat(rparts, " "),
        suits = table.concat(sparts, " "),
        best = (#can > 0) and table.concat(can, ", ") or "High Card only",
        notes = (#notes > 0) and table.concat(notes, "; ") or nil,
    }
end

-- A pack can offer either special cards (joker/tarot/planet/spectral) or plain
-- playing cards (standard pack); describe each with the right renderer.
local function describe_any(card)
    local c = center_of(card)
    if c and card.base and (c.set == "Default" or c.set == "Enhanced") then
        return describe_playing(card)
    end
    return describe_special(card, false)
end

local function list_pack(area)
    local out = {}
    if area and area.cards then
        for _, c in ipairs(area.cards) do out[#out + 1] = describe_any(c) end
    end
    return out
end

local function pack_open()
    return G and G.pack_cards and not G.pack_cards.REMOVED
        and G.pack_cards.cards and #G.pack_cards.cards > 0
end

-- Current high-level phase, for phase-appropriate prompting.
function M.context()
    if not G or not G.STATE or not G.STATES then return "menu" end
    -- A booster pack (even one opened from the shop) takes priority: detect it by
    -- the actual card area being present, not by G.STATE which can lag/vary.
    if pack_open() then return "opening_pack" end
    local S = G.STATES
    local st = G.STATE
    if st == S.SELECTING_HAND then return "selecting_hand" end
    if st == S.SHOP then return "shop" end
    if st == S.BLIND_SELECT then return "blind_select" end
    if st == S.ROUND_EVAL then return "cash_out" end
    if st == S.TAROT_PACK or st == S.PLANET_PACK or st == S.SPECTRAL_PACK
        or st == S.STANDARD_PACK or st == S.BUFFOON_PACK then return "opening_pack" end
    return "in_run"
end

-- Capture a structured snapshot, gathering ONLY what the current phase needs so
-- we don't send irrelevant data (saves tokens). Jokers/consumables and the
-- money/ante meta are sent in every phase because they inform every decision.
function M.capture()
    local phase = M.context()
    local snap = { phase = phase }
    if not G or not G.GAME then return snap end
    local g = G.GAME

    -- Phase flags.
    local is_hand  = (phase == "selecting_hand" or phase == "in_run")
    local is_shop  = (phase == "shop")
    local is_pack  = (phase == "opening_pack")
    local is_blind = (phase == "blind_select")

    -- Always: money / progress meta + owned jokers & consumables.
    snap.ante    = g.round_resets and g.round_resets.ante
    snap.round   = g.round
    snap.dollars = g.dollars
    snap.jokers      = list_special(G.jokers)
    snap.consumables = list_special(G.consumeables)

    -- Run-so-far context (cheap): active tags and redeemed vouchers show the build
    -- trajectory. Each Advice is otherwise stateless (no turn-by-turn history).
    snap.tags = {}
    if g.tags then
        for _, t in ipairs(g.tags) do snap.tags[#snap.tags + 1] = t.name or t.key end
    end
    -- Hands actually played this run (logged by the play hook in main.lua).
    if BalaGPTro and BalaGPTro.playlog and #BalaGPTro.playlog > 0 then
        snap.playlog = BalaGPTro.playlog
    end
    snap.vouchers = {}
    if g.used_vouchers then
        for k, v in pairs(g.used_vouchers) do
            if v then snap.vouchers[#snap.vouchers + 1] = (G.P_CENTERS and G.P_CENTERS[k] and G.P_CENTERS[k].name) or k end
        end
        table.sort(snap.vouchers)
    end

    -- Hands/discards left only matter while a round is in progress.
    if is_hand or is_pack then
        snap.hands_left    = g.current_round and g.current_round.hands_left
        snap.discards_left = g.current_round and g.current_round.discards_left
    end

    -- Blind requirement + boss effect while a round is in progress.
    if is_hand and g.blind then
        snap.blind = {
            name = g.blind.name,
            chips = g.blind.chips,
            dollars = g.blind.dollars,
            boss = not not g.blind.boss,
        }
        local ok, eff = pcall(function()
            if g.blind.get_loc_debuff_text then return g.blind:get_loc_debuff_text() end
            return g.blind.loc_debuff_text
        end)
        if ok and type(eff) == "string" and eff ~= "" then snap.blind.effect = eff end
    end

    -- Blind select: the Small/Big/Boss choices + the SKIP TAG for Small/Big, so the
    -- AI can advise whether to skip a blind to grab its tag.
    if is_blind then
        snap.on_deck = g.blind_on_deck
        snap.blind_choices = {}
        local rr = g.round_resets
        if rr and rr.blind_choices then
            for _, typ in ipairs({ "Small", "Big", "Boss" }) do
                local bkey = rr.blind_choices[typ]
                if bkey then
                    local proto = G.P_BLINDS and G.P_BLINDS[bkey]
                    local e = { type = typ, name = (proto and proto.name) or bkey, reward = proto and proto.dollars }
                    e.state = rr.blind_states and rr.blind_states[typ]  -- Upcoming/Select/Current/Skipped/Defeated
                    local ok, amt = pcall(function()
                        return get_blind_amount(rr.blind_ante or rr.ante)
                            * ((proto and proto.mult) or 1)
                            * ((g.starting_params and g.starting_params.ante_scaling) or 1)
                    end)
                    if ok and amt then e.chips = math.floor(amt) end
                    if typ == "Boss" then e.effect = resolve_desc("Blind", bkey) end
                    local tkey = rr.blind_tags and rr.blind_tags[typ]
                    if tkey then
                        e.skip_tag = (G.P_TAGS and G.P_TAGS[tkey] and G.P_TAGS[tkey].name) or tkey
                        e.skip_tag_effect = resolve_desc("Tag", tkey)
                    end
                    snap.blind_choices[#snap.blind_choices + 1] = e
                end
            end
        end
    end

    -- Poker-hand run info: level, current chips/mult, and times played this run.
    -- Sent while playing and for planet choices in packs.
    if is_hand or is_pack then
        snap.hand_levels = {}
        if g.hands then
            for name, h in pairs(g.hands) do
                if h.visible then
                    snap.hand_levels[name] = { level = h.level, chips = h.chips, mult = h.mult, played = h.played }
                end
            end
        end
    end

    -- Held cards: needed while selecting a hand, AND during a pack (tarot/spectral
    -- cards target a card in hand, so the AI must see the candidates).
    if is_hand or is_pack then
        snap.held = list_playing(G.hand)
        snap.held_comp = hand_composition(G.hand)
        snap.selected = {}
        if G.hand and G.hand.highlighted then
            for _, c in ipairs(G.hand.highlighted) do snap.selected[#snap.selected + 1] = describe_playing(c) end
        end
    end
    -- Remaining draw pile summary, for discard/draw planning (hand phase only).
    if is_hand then
        snap.deck = deck_summary(G.deck)
    end

    -- Shop contents only in the shop.
    if is_shop then
        snap.shop_jokers   = list_special(G.shop_jokers, true)
        snap.shop_boosters = list_special(G.shop_booster, true)
        snap.shop_vouchers = list_special(G.shop_vouchers, true)
        snap.reroll_cost   = g.current_round and g.current_round.reroll_cost
    end

    -- Pack contents: capture whenever a pack area exists with cards (robust to the
    -- exact G.STATE, and to opening the panel before cards finish animating in).
    if is_pack or (G.pack_cards and not G.pack_cards.REMOVED and G.pack_cards.cards and #G.pack_cards.cards > 0) then
        snap.pack = list_pack(G.pack_cards)
        snap.pack_choices = g.pack_choices or (G.pack_cards and G.pack_cards.config and G.pack_cards.config.card_limit)
        -- Make sure hand info is present for Celestial/Planet packs even if the
        -- phase flag missed.
        if not snap.hand_levels and g.hands then
            snap.hand_levels = {}
            for name, h in pairs(g.hands) do
                if h.visible then
                    snap.hand_levels[name] = { level = h.level, chips = h.chips, mult = h.mult, played = h.played }
                end
            end
        end
    end

    return snap
end

local function section(title, lines)
    if not lines or #lines == 0 then return nil end
    return title .. ":\n  " .. table.concat(lines, "\n  ")
end

-- Render the snapshot into a compact text block for the LLM.
function M.to_prompt(snap)
    snap = snap or M.capture()
    local p = {}
    p[#p + 1] = "PHASE: " .. tostring(snap.phase)

    local meta = {}
    if snap.ante then meta[#meta + 1] = "ante " .. tostring(snap.ante) end
    if snap.round then meta[#meta + 1] = "round " .. tostring(snap.round) end
    if snap.dollars then meta[#meta + 1] = "$" .. tostring(snap.dollars) end
    if snap.hands_left then meta[#meta + 1] = (snap.hands_left) .. " hands" end
    if snap.discards_left then meta[#meta + 1] = (snap.discards_left) .. " discards" end
    if #meta > 0 then p[#p + 1] = table.concat(meta, " | ") end

    if snap.blind then
        p[#p + 1] = string.format("%s: %s — need %s chips (reward $%s)",
            snap.blind.boss and "BOSS BLIND" or "BLIND",
            tostring(snap.blind.name), tostring(snap.blind.chips), tostring(snap.blind.dollars))
        if snap.blind.effect then
            p[#p + 1] = "BOSS EFFECT: " .. snap.blind.effect .. " (debuffed cards are marked [DEBUFFED by blind])"
        end
    end

    if snap.blind_choices and #snap.blind_choices > 0 then
        if snap.on_deck then p[#p + 1] = "CHOOSING BLIND (on deck: " .. tostring(snap.on_deck) .. ")" end
        local bl = {}
        for _, e in ipairs(snap.blind_choices) do
            local s = string.format("%s: %s", e.type, tostring(e.name))
            if e.state then s = s .. " [" .. tostring(e.state) .. "]" end
            if e.chips then s = s .. " — need " .. tostring(e.chips) .. " chips" end
            if e.reward then s = s .. ", reward $" .. tostring(e.reward) end
            if e.effect then s = s .. " — effect: " .. e.effect end
            if e.skip_tag then
                s = s .. " | SKIP TAG: " .. e.skip_tag .. (e.skip_tag_effect and (" (" .. e.skip_tag_effect .. ")") or "")
            end
            bl[#bl + 1] = s
        end
        p[#p + 1] = "BLIND CHOICES:\n  " .. table.concat(bl, "\n  ")
    end

    if snap.hand_levels and next(snap.hand_levels) then
        local hl = {}
        for name, h in pairs(snap.hand_levels) do
            hl[#hl + 1] = string.format("%s lvl%s (%sx%s, played %s)",
                name, tostring(h.level), tostring(h.chips), tostring(h.mult), tostring(h.played or 0))
        end
        table.sort(hl)
        p[#p + 1] = "POKER HANDS (run info): " .. table.concat(hl, "; ")
    end

    -- Append each section only when non-empty. (Do NOT build an array literal with
    -- nil holes — ipairs stops at the first nil and silently drops the rest.)
    local function add(title, lines)
        local s = section(title, lines)
        if s then p[#p + 1] = s end
    end
    add("HELD CARDS", snap.held)
    if snap.held_comp then
        p[#p + 1] = "HAND COMPOSITION (facts — trust these over your own count):"
        p[#p + 1] = "  rank counts: " .. snap.held_comp.ranks
        p[#p + 1] = "  suit counts: " .. snap.held_comp.suits
        p[#p + 1] = "  best hand type available from these cards: " .. snap.held_comp.best
        if snap.held_comp.notes then p[#p + 1] = "  constraints: " .. snap.held_comp.notes end
    end
    add("SELECTED", snap.selected)
    if snap.deck then
        p[#p + 1] = string.format("DECK REMAINING (%d): suits %s | ranks %s",
            snap.deck.total, snap.deck.suits, snap.deck.ranks)
    end
    add("JOKERS (left-to-right order matters)", snap.jokers)
    add("CONSUMABLES", snap.consumables)
    add("ACTIVE TAGS", snap.tags)
    add("REDEEMED VOUCHERS (run)", snap.vouchers)
    if snap.playlog then
        local pl = {}
        for _, e in ipairs(snap.playlog) do
            pl[#pl + 1] = string.format("ante %s: %s [%s]",
                tostring(e.ante), tostring(e.hand), table.concat(e.cards or {}, ", "))
        end
        p[#p + 1] = "RECENT PLAYS (this run, newest last):\n  " .. table.concat(pl, "\n  ")
    end
    add("SHOP JOKERS", snap.shop_jokers)
    add("SHOP BOOSTERS", snap.shop_boosters)
    add("SHOP VOUCHERS", snap.shop_vouchers)
    add(snap.pack_choices and ("PACK — pick " .. tostring(snap.pack_choices)) or "PACK", snap.pack)

    if snap.reroll_cost then p[#p + 1] = "REROLL COST: $" .. tostring(snap.reroll_cost) end

    return table.concat(p, "\n")
end

return M
