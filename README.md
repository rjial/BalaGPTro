# BalaGPTro — BYOK AI Advisor & Chat for Balatro

BalaGPTro is a [Steamodded](https://github.com/Steamodded/smods) mod that adds a
**bring-your-own-key (BYOK) AI assistant** to Balatro. It reads your live run and
can:

- **Advise** on the best move for the current phase — which cards to play/discard,
  what to buy in the shop, which pack card to pick, or whether to skip a blind.
- **Chat** — answer free-form questions about your run (with conversation memory).
- **Predict score** for the cards you have selected.

The AI only *suggests*. It never takes actions for you, so your run and the game
balance are untouched.

> **Important:** this mod needs your own LLM API key (or a local/compatible
> endpoint). It is not affiliated with Anthropic, OpenAI, or Google.

---

## Features

- Three providers out of the box, each using its **native** request format:
  **Anthropic** (Messages API), **OpenAI** (Chat Completions), **Google Gemini**
  (generateContent).
- Works with **any OpenAI-compatible or Anthropic-compatible endpoint** via a
  Base URL override (OpenRouter, Groq, Ollama, LM Studio, Sumopod, proxies, …),
  with **one-click presets**.
- **Floating, draggable panel** (toggle with **F6**) that coexists with the game —
  no modal overlay, so you can keep playing while reading advice.
- Non-blocking network (`SMODS.https` on a background thread) — the game never
  freezes while waiting for a reply.
- **Phase-aware context**: sends only what matters for the current phase
  (hand / shop / pack / blind select), saving tokens.
- Reads each card's **actual ability** (including modded cards), boss-blind
  effects, debuffed cards, planet hand targets, shop prices, pack contents, and
  your run history.
- **Conversation memory** shared across Advice / Chat / Predict, so follow-ups and
  the model's own clarifying questions keep context.

---

## Requirements

- Balatro
- [Lovely injector](https://github.com/ethangreen-dev/lovely-injector)
- [Steamodded](https://github.com/Steamodded/smods) ≥ 1.0.0
- An API key for a supported provider, **or** a local/compatible endpoint.

`SMODS.https` and the bundled `json` library ship with Steamodded — no extra
dependencies are needed.

---

## Installation

Place the mod folder in your Balatro `Mods` directory:

- **Linux:** `~/.local/share/love/Mods/BalaGPTro/`
- **Windows:** `%AppData%/Balatro/Mods/BalaGPTro/`
- **macOS:** `~/Library/Application Support/Balatro/Mods/BalaGPTro/`

(During development on Linux you can symlink the repo into place:
`ln -s /path/to/BalaGPTro ~/.local/share/love/Mods/BalaGPTro`.)

Launch Balatro; "BalaGPTro" should appear in the **Mods** menu. **Restart the game
after editing any `.lua` file** — Lua is loaded at launch.

---

## Configuration

Open **Mods → BalaGPTro** in the main menu. The page has two columns:

- **Left — Provider & endpoint:** Provider cycle, **presets**, and the API Key /
  Model / Base URL fields.
- **Right — Options:** toggles and notes.

Steps:

1. **Pick a provider**, or click a **preset** (OpenAI, Anthropic, OpenRouter,
   Groq, Ollama, LM Studio, Sumopod) to fill provider + Base URL + a default model
   in one click.
2. **Paste your API Key.** For key-less local endpoints (Ollama, LM Studio) you
   can leave it empty — a key is only required when no Base URL is set.
3. Optionally set **Model** and **Base URL** overrides.
4. Toggle features as desired.

### Settings reference (`config.lua`)

| Key                  | Meaning                                                                        |
| -------------------- | ------------------------------------------------------------------------------ |
| `provider`           | `"anthropic"` \| `"openai"` \| `"gemini"`                                      |
| `api_key`            | Your key. Stored in **plaintext** — see Security.                              |
| `model`              | Model name. Empty = provider default.                                          |
| `base_url`           | Endpoint override. Empty = that provider's default cloud URL.                  |
| `max_tokens`         | Max tokens in the reply. Lower it (~400) if a model rambles.                   |
| `language`           | Reply language for auto-advice/score (chat mirrors your question).             |
| `advisor_enabled`    | Enable the "Advice" action.                                                    |
| `chat_enabled`       | Enable the chat box.                                                           |
| `auto_advise_on_draw`| Fire advice automatically each new hand (off by default; costs tokens).        |
| `score_exact_sim`    | Tier-2 exact score simulation — **not implemented yet**; falls back to Tier 1. |
| `debug_log`          | Log the full prompt/response (API key redacted) to the Balatro console/log.    |

### ⚠️ The "/" and ":" limitation

Balatro's in-game text fields **cannot type `/` or `:`**, so a Base URL or a model
name containing them (e.g. OpenRouter's `anthropic/claude-3.5-sonnet`) can't be
typed on screen. Either **use a preset**, or **edit `config.lua` directly**
(outside the game) for such values.

---

## Usage

Press **F6** in a run to toggle the floating panel. Drag it by its title bar;
it blocks clicks where it sits, so **drag it aside** (or close it with F6) when you
need to click cards or slots behind it. Its position is remembered.

Buttons:

- **Advice** — recommendation for the current phase.
- **Send** (or press **Enter** in the box) — ask a free-form question; chat keeps
  recent history so you can follow up or answer a question the AI asked.
- **Predict score** — select the cards to play first, then get a base chips × mult
  reading plus an estimated final score.
- **Cancel** — abandon an in-flight request. **Clear chat** — reset history.
- **Close (F6)** — hide the panel.

Long replies are **paginated** (◀ / ▶) so the window keeps a fixed size. While a
request is in flight, the action buttons are **disabled** (greyed); Cancel stays
active, and sending a new request supersedes the old one.

---

## What the AI sees

Per phase, BalaGPTro sends a compact, token-light summary:

- **Always:** ante/round, dollars, your **jokers** (with abilities + live values),
  consumables, **active tags**, **redeemed vouchers**, and **recent hands played
  this run** (type + cards).
- **Selecting a hand:** held cards, selected cards, the blind requirement, **boss
  effect** + cards marked `[DEBUFFED by blind]`, poker-hand levels (with play
  counts), and a remaining-deck summary.
- **Shop:** each shop joker / booster / voucher with effect + **buy price**, plus
  reroll cost.
- **Opening a pack:** each offered card (planets show their **target hand**), the
  pick count, and your held cards as **targets** for Tarot/Spectral effects.
- **Blind select:** Small / Big / Boss choices with chip requirement, reward,
  **skip tag** + effect, boss effect, and each blind's state
  (`Select` / `Defeated` / `Skipped` / `Upcoming`).

Modded cards are included automatically (their name/ability come from the same
localization tables); cards that ship no description fall back to the game's own
rendered tooltip.

---

## Using your existing Claude / local models

There is **no key-less way** to call Anthropic, OpenAI, or Google directly — the
cloud APIs require a key. To avoid putting a cloud key in the mod, run a **local
OpenAI-compatible server** and point the mod at it:

- **Ollama** (`http://localhost:11434/v1`) or **LM Studio**
  (`http://localhost:1234/v1`) — fully local models, no key needed.
- A local proxy bridging a subscription can expose an OpenAI-compatible endpoint;
  point the Base URL at it. Using subscription credentials in third-party apps may
  violate that provider's Terms of Service — check first.

> Local HTTP endpoints depend on the `SMODS.https` curl backend. If `localhost`
> fails to connect, try `127.0.0.1`.

---

## How it works

```
main.lua                 Entry: loads modules, F6 keybind, and hooks the
                         "play hand" / "start run" funcs to log hands played.
config.lua               Default settings (SMODS persists changes over this).
src/state.lua            Phase-aware capture of the game state; resolves card
                         abilities (incl. modded) and renders a compact prompt.
src/score.lua            Score prediction (Tier 1 from the game's hand levels).
src/providers.lua        Per-provider request builders + response parsers
                         (message arrays, empty/reasoning-content handling).
src/client.lua           Async LLM call via SMODS.https; supersede/cancel by id;
                         results deferred through G.E_MANAGER for safe UI updates.
src/prompts.lua          System prompt + phase-specific advisor / chat / score
                         templates.
src/ui_settings.lua      The two-column config_tab in the Mods menu.
src/ui_overlay.lua       The floating, draggable panel (F6): response pager,
                         chat input, actions, history, busy/disable logic.
src/draggable_container.lua  UIBox subclass that makes the panel draggable.
```

Network calls run on a background LÖVE thread; the callback is invoked on the main
thread (from Steamodded's patched `love.update`), and the result is deferred
through `G.E_MANAGER` before any UI update, so the game never freezes or races.

---

## Security

Your API key is stored in **plaintext** in `config.lua`. That file is
**gitignored** — copy `config.example.lua` to `config.lua` and fill in your key
there. Do not commit `config.lua` or share it. The mod never logs the key (it is
redacted even with `debug_log` on).

---

## Limitations

- **Tier-2 exact score simulation** is not implemented; `score_exact_sim` falls
  back to the Tier-1 estimate.
- Advice/prediction quality depends on the model. Reasoning models can be verbose
  or return empty `content`; lower `max_tokens` or pick a non-reasoning model.
- In-game text fields can't type `/` or `:` (see above).
- The floating panel blocks clicks where it sits — drag it aside or close it.
- Each request is otherwise stateless apart from the shared chat history; there is
  no cross-game memory.

---

## Versioning & releases

The mod follows [SemVer](https://semver.org/). The version in `BalaGPTro.json`
(`version`) is the single source of truth. A GitHub Action
(`.github/workflows/release.yml`) watches `main`: when that version changes to one
with no matching `v<version>` tag, it creates the tag and a GitHub Release with a
ready-to-install `BalaGPTro-v<version>.zip` (extract into your `Mods` folder).

To cut a release: bump `version` in `BalaGPTro.json` (e.g. `0.1.0` → `0.2.0`),
commit, and push to `main`.

---

## Credits & License

`src/draggable_container.lua` is derived from **BalaLib** by Toeler
(Balatro-HandPreview), modified for **Ankh** by MathIsFun0, and further modified
for the **SystemClock** mod by Breezebuilder — used under **GPLv3**.

Because of that GPLv3 component, **BalaGPTro is licensed under GPLv3**. See the
attribution header at the top of `src/draggable_container.lua` and `LICENSE.md`.

Not affiliated with LocalThunk, Anthropic, OpenAI, or Google.
