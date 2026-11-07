# CLAUDE.md

Guidance for working on this repository.

## What this is

**Gebbo's Bottomless Bag** (`GebboBagTracker`): a World of Warcraft retail addon for the Midnight 12.1.x trinket *Gebbo's Bottomless Bag* (item 270164). When the trinket fires one of its six random "pulls", the addon shows a big glowing alert: which pull it is, how much Crit/Haste/Mastery/Versatility it gives (or takes), and how long it lasts. Each pull plays a custom sound.

Plain Lua against the WoW client API. There is no build step, no external libraries (no Ace3, LibStub, etc.) and no test framework. The repo root *is* the addon folder.

- GitHub: `rlucas2100/rlucas2100-GebbosTrinket_World_of_Warcraft` (renamed from `GebboBagTracker`; links must use the new name)
- Slash commands: `/gbag`, `/gebbo`
- SavedVariables: `GebboBagTrackerDB` (account-wide)

## Files and load order

The order comes from `GebboBagTracker.toc`. All files share the addon's private namespace table via `local ADDON, ns = ...`; nothing is global except `GebboBagTrackerDB`, the `SLASH_GEBBOBAG*` entries and `GebboBagTracker_OnAddonCompartmentClick`.

| File | Role |
| --- | --- |
| `Data.lua` | Static data only. Item/spell IDs, `ns.ARTIFACTS` (the six pulls: stats, base amount, decay/grow model, mood, sound, colour), `ns.THEME` (title text, panel gradient, rainbow/danger flags, engine priority), `ns.STAT`, `ns.STACK_ORDER`, sound paths, scaling constants. |
| `Core.lua` | Logic. Secret-value helpers, error catching, saved-setting defaults, spell-ID discovery, aura polling and the pull lifecycle, amount model and item-level calibration, sounds (addon and game-side), events, slash commands. |
| `UI.lua` | The addon-drawn alert panels. Builds one panel per pull lazily, the TOTAL strip, full-screen flash, per-frame animation (`UI_Tick`), layout/stacking, move/scale/lock. Also exports shared builders that `Engine.lua` reuses (`ns.Anim`, `ns.BuildBubbles`, `ns.BuildSparks`, `ns.BuildGemRow`, `ns.BuildBadge`, `ns.Text`, `ns.HSV`, `ns.Lighten`, `ns.FmtAmt`...). |
| `Engine.lua` | The game-drawn display for restricted content (raids, boss fights, Mythic+), built on 12.1's `AuraContainer` / `CustomAuraContainerTemplate`. |
| `Options.lua` | The custom settings window (`/gbag config`) and the stub under Options → AddOns. |
| `media/` | `.tga` textures (all original), `.ogg` sounds (all original). Loaded by path via `ns.MEDIA`. |
| `images/` | README screenshots and GIFs. Not loaded by the game. |
| `tools/render_previews.py` | Regenerates `images/` (see below). Not loaded by the game. |

`UI.lua` must load before `Engine.lua`, because Engine reads `ns.W`, `ns.H`, `ns.Anim` and the other builders at file scope.

## How it works

### The core problem: secret values (Midnight 12.x)
Inside raids, boss encounters and Mythic+, the client hands addons "secret" values for aura data. Comparing them, doing maths on them or indexing them throws an error. Every read in `Core.lua` therefore goes through:
- `Readable(v)`, which checks `issecretvalue` before touching a value;
- `Field(t, k)`, a `pcall`-wrapped table index;
- `ReadAura(id)`, which returns the string `"secret"` when the aura is hidden (and stamps `ns.secretSeen`).

Event handlers and per-frame scripts are wrapped in `ns.Safe(fn)`. It catches errors, keeps the last 20 in `ns.errLog` (`/gbag errors`) and prints a single notice. **Keep this pattern** for any new code that touches aura, unit or combat data. Never compare or do arithmetic on a value before checking `Readable`.

A secret number can still be *displayed*: `pcall(fontString.SetText, fs, secret)` works. `UI_Numbers` relies on this through `st.secretAmount`.

### Two display paths
1. **Addon-drawn** (`UI.lua`), used in the open world, or whenever auras are readable. `ns:Poll()` (every 0.1s in `OnUpdate`, plus throttled on `UNIT_AURA`) scans each pull's spell IDs, starts or ends a state in `ns.states[key]`, and reads the live amount from `aura.points`. The UI reads `ns.states` every frame.
2. **Engine (game-drawn)** (`Engine.lua`), used where `C_Secrets.ShouldAurasBeSecret()` is true (engine mode `auto`), always (`on`), or never (`off`). One `AuraContainer` holds an aura group per pull and filter, in `STACK_ORDER`. The *game* matches the aura, sets the icon, and drives the cooldown sweep and duration bar. The addon only styles each panel in `BuildPanel`, using pure `AnimationGroup` loops because there is no per-frame Lua state. Amounts there are estimates (`~`), from `ns:GetScaleFactor()`. Fading and growing pulls run their curve on a guarded `OnUpdate`; if the game blocks it, `ns.engineLive = false` and the text stays on the start value.
   - The container can only be (re)built **out of combat**. `ns.engineDirty` defers rebuilds, and a 0.25s ticker in `EngineInit` applies them. Spell IDs or buff/debuff kinds learned later change `Signature()` and trigger a rebuild.
   - `UI_OnProc` / `UI_UpdateVisibility` hide the addon-drawn panel for real pulls while the engine is active. Test pulls (`st.fake`) always use the addon path.

### Pull lifecycle (`Core.lua`)
`Poll` → aura seen → `StartProc` (creates the state, updates session stats) → `UpdateFromAura` (expiry, stacks, live amount, calibration) → `RefreshAmount` → `Announce` (sound + `UI_OnProc`) → … → aura gone or expired → `EndProc`.

The amount comes from one of these sources (`st.source`):
- `live`: read from the buff;
- `secret`: hidden, so it's displayed opaquely;
- `est`: the model × scale factor;
- `test`: a preview pull.

For dynamic pulls, `RefreshAmount` runs the documented curve (`decayPerSec`, `decayPerCast`, `growPerSec`) anchored to the first live value.

### Spell IDs
Only the Salmon's ID is hard-coded (`ids` in `Data.lua`). At login `ScanSpellRanges` checks the IDs in `ns.SCAN_RANGES` and matches spell names against each pull's `match` patterns (English only). `MaybeLearn` also learns IDs from live auras in the open world and saves them in `db.learnedIDs`. Users can add IDs with `/gbag setid <pull> <id>` (`db.manualIDs`). `db.auraKind[id]` records whether each ID is a buff (HELPFUL) or debuff (HARMFUL). The engine needs this to pick the right aura filter.

### Estimates and calibration
Base amounts were read at item level 334, before a 29% hotfix nerf (`ns.NERF = 0.71`). `GetScaleFactor()` prefers `db.calib[ilvl]`, which is saved whenever a `calibrate = true` pull (Salmon, Gralstone, Voidfin) is read live. Otherwise it extrapolates from the nearest calibrated item level with `ILVL_GROWTH`, or falls back to the rough constant.

### Sounds
`PlayArtifactSound` uses `PlaySoundFile` on `db.channel`. `RegisterNativeSounds` also registers each pull with `C_UnitAuras.AddAuraSound`, so the chimes still play where auras are secret. When a pull has a game-side handle, `Announce` skips the addon sound to avoid playing it twice. Registration is deferred out of combat via `ns.pendingNative`.

## The alert panel (for visual changes)

The geometry is defined once at the top of `UI.lua` (`W, H, ICON, CAMEO, GAP, TOTAL_H = 448, 132, 100, 84, 14, 40`; `MID_L`, `MID_R` bound the middle text column) and shared with Engine via `ns.*`. Layers from back to front:
1. Outer glow (`glow_outer`, ADD).
2. The panel: gradient `bgA → bgB` at 0.92 alpha, inner glow (`glow_inner`, ADD), rising bubbles (clipped), and 2px ADD edges.
3. Title, pull name, amount, the C/H/M/V gem row and the duration bar.
4. Right side: the cartoon badge (trinket icon masked into `badge_rim`, `ring`, `badge_shine`, squash-and-stretch hop), or the `voidfin` fish for the Voidfin.
5. Left side, the icon: two glows, rotating `rays_white`, the sliding `metal_rainbow` frame (desaturated and tinted unless `rainbow`), the icon, an inner glow, Blizzard's `IconAlertAnts`, the reverse cooldown sweep and the big timer.
6. Sparks flying out of the icon (not for `danger`).

Theme flags in `ns.THEME`:
- `rainbow` (Salmon): hue-cycling glows and edges, and a rainbow screen flash.
- `danger` (Voidfin): a fast `abs(sin)` pulse, desaturated green icon, wobble on entry, green flash, no sparks.

When two or more pulls are up at once, `UI_Layout` stacks them in `STACK_ORDER` and shows the TOTAL strip. `db.growUp` flips the direction.

**Keep `UI.lua` and `Engine.lua` visually in sync.** The engine panel is a separate, animation-group-only copy of the same look, so a visual change usually needs doing in both.

## Common tasks

**Add or change a pull:** edit `ns.ARTIFACTS`, `ns.THEME` and `ns.STACK_ORDER` in `Data.lua`. Every other file iterates over these tables. Use `/gbag test <key>` to preview, and add the key to the `/gbag test` help text in `Core.lua` and to the README.

**Add a setting:** add a default to `DEFAULTS` in `Core.lua` (`ApplyDefaults` fills missing keys for existing users and never overwrites). Add a control in `Options.lua` and, if useful, a slash command in `Core.lua`.

**Release:**
1. Bump `## Version:` in the `.toc`.
2. Update the README.
3. Zip a folder named exactly `GebboBagTracker` as `GebboBagTracker.zip`.
4. Attach it to a GitHub release.

The in-game folder **must** be named `GebboBagTracker`, because the `.toc` name, `ns.MEDIA` (built from the `ADDON` name) and `IconTexture` all depend on it. A "Download ZIP" of the repo gives a folder named after the GitHub repo, which won't load correctly; tell users to use the release zip.

`## Interface:` lists `120105, 120100, 120001`. Update it when a new client patch lands.

## Testing

There is no automated test suite; testing happens in game. Useful commands:
- `/gbag test [salmon|scroll|totem|gralstone|seashell|voidfin]`: fake pull through the addon-drawn path.
- `/gbag status`, `/gbag ids`, `/gbag engine auto|on|off`, `/gbag errors`, `/gbag stats`.
- `/gbag engine on` forces the game-drawn path in the open world, for checking `Engine.lua` without a raid or key.
- `/gbag unlock`: moving and scaling.

New or changed files in `media/` (textures, sounds) only load after a **full client restart**, not `/reload`. Lua changes do load on `/reload`.

## README images (`images/`)

**Real in-game screenshots** (prefer these; replace them when the look changes):
- `Gebbo_banner_ingame.png`: the hero banner, built around a stack of three game-drawn alerts cropped from a Mythic+ screenshot.
- `Gebbo_mythicplus_ingame.jpg`: the full Mythic+ screenshot. The chat window is blurred because it showed other players' and friends' names.
- `Gebbo_stack_ingame.png`: the three-alert stack crop.
- `Gebbo_six_pulls_ingame.png`: one real panel per pull on a dark backdrop. The Versatility panel is upscaled from the Mythic+ crop because there was no single shot of it.

**Rendered previews**, made with `tools/render_previews.py` (Python 3 + Pillow):
- `Gebbo_jackpot.gif` and `Gebbo_voidfin.gif`: animated, because the game can't capture these.
- `Gebbo_stacked_total_1280x720.png`: the TOTAL strip, which only appears on the addon-drawn path, so the Mythic+ shot doesn't show it.

How the script works:
- It recreates the alert panel from `UI.lua`'s geometry, colours and animation formulas, using the real `media/*.tga` textures.
- Run it from the repo root: `python tools/render_previews.py` renders stack and gif. Optional arguments: `<media> <out> banner|six|stack|gif`.
- The pull icons and bag badge are original cartoon stand-ins drawn in the script, because in game those slots show Blizzard's spell and item icons. Don't commit ripped icons.
- If you change the panel layout or theme colours, update the script's constants (`ARTS`, the geometry) and re-render.

The README's small print says which images are real and which are rendered. Keep it accurate.

## Conventions

- Tabs for indentation in Lua. Cache globals as locals at the top of a file (`local GetTime, pairs = GetTime, pairs`).
- Wrap all client API calls that might be missing or restricted in `pcall` and check for nil APIs (`C_UnitAuras and C_UnitAuras.X`), so the addon degrades gracefully across client versions.
- No combat-locked work: anything that creates or reshapes protected or engine frames checks `InCombatLockdown()` and defers.
- User-facing text uses plain words (pulls, Jackpot, Voidfin). Chat output goes through `ns.Print`, which adds the coloured prefix.
- Sounds and art are original and made for this addon. Keep it that way: no ripped game assets in `media/` or `images/`.
