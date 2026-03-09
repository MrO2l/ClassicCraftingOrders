# Changelog

All notable changes to ClassicCraftingOrders are documented in this file.

Format based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).
Versions follow `MAJOR.MINOR.PATCH`.

---

## [1.5.0] – 2026-03-09

### Architecture – Communication completely rethought

This release replaces the v1.4.0 WHISPER-to-everyone approach with a
**GUILD/RAID primary broadcast + passive relay bridge + targeted WHISPER**
architecture. The result: O(1) sends per order post regardless of how
many CCO players are online, while still reaching strangers server-wide.

### Research findings that shaped the design
- `C_ChatInfo.SendAddonMessage` does **not** support `"CHANNEL"` distribution in TBC Classic Anniversary — Blizzard deliberately removed it in Classic Patch 1.13.3 (Dec 2019). Custom channel via addon messages is not possible.
- `JoinTemporaryChannel` only triggers `CHAT_MSG_CHANNEL` events, not `CHAT_MSG_ADDON`. No workaround exists.
- Actual rate limit: **10-message burst bucket, 1 msg/sec refill** (not 3–4/sec). Queue drain set to 0.8 s/msg (1.25 msg/sec, safely under limit).
- `GetGuildRosterInfo(i)` returns `"Name-Realm"` in TBC Classic Anniversary (realm suffix must be stripped for comparisons).
- `GetNumRaidMembers()` is fully available in TBC Classic Anniversary.
- YELL addon messages once per 90 s have no ban risk (confirmed via Blizzard forum documentation).

### Added
- **Relay system** — a player in both GUILD and a cross-guild RAID acts as a passive bridge: orders received via GUILD are automatically forwarded to RAID and vice versa. `ttl=1` limits this to exactly one hop, preventing exponential message growth.
- **`ttl` field** in `MT_ORDER_POST` and `MT_ORDER_CANCEL` payloads — relay hop budget. Set to `1` on first send, relay decrements to `0` before forwarding. Sync-reply whispers use `ttl=0` (never relayed).
- **`relayedIDs` set** — session-local deduplication table prevents a single order from being relayed more than once per client.
- **`BuildReachableSet()`** — builds a name-set from the current guild roster, raid, and party. Orders are only whispered to CCO players **not already in this set**, eliminating duplicate delivery to guild/raid members.
- **`GetAvailableChannels()`** — returns all active group/guild channels so all three functions (`QueueGroupBroadcast`, relay, relay-exclusion) share one consistent channel list.
- **Staggered QUERY delay** — when discovering a new CCO player, the WHISPER query is delayed by a random 2–5 s to smooth out thundering-herd situations when many players log in simultaneously.

### Changed
- **Queue drain rate**: 0.4 s/msg (v1.4.0) → **0.8 s/msg** (1.25 msg/sec), safely below the confirmed 1 msg/sec sustained rate limit.
- **`QueueTargetedWhispers`** now skips players already covered by GUILD/RAID/PARTY broadcast instead of whispering all `knownPlayers` indiscriminately. For a 500-member guild, this eliminates ~499 redundant whispers per order post.
- **`AcceptOrder`** whispers the requester directly (unchanged from v1.4.0).
- **Sync reply (`HandleQuery`)** sets `ttl=0` on whispered orders so the recipient does not relay them further.
- **`MSG_VERSION`** bumped `2` → `3` (new `ttl` field in P and C messages; v2 messages with no `ttl` treated as `ttl=0` — not relayed, safe backward compatibility).

### Removed
- Ongoing WHISPER delivery of new orders to all `knownPlayers` — replaced by relay + targeted whisper to unreachable players only.

---

## [1.4.0] – 2026-03-09

### Fixed – Communication (root cause of "can't see each other's orders")
- **`GetBestDistribution()` was sending to only ONE channel** — the function returned on the first match (GUILD → PARTY → RAID → YELL), so a player in a guild but not in a group would send via GUILD, while a friend without a shared guild/group would send via YELL. Neither could receive the other's messages.
- **YELL channel has only ~300 yard range** — strangers not in the same guild or group had no reliable way to exchange messages across a city or between zones.
- **No WHISPER-based discovery** — the only unlimited-range TBC Classic communication channel between strangers is WHISPER. The previous implementation never used it.
- **Throttle blocked multi-channel sends** — the 5-second-per-message throttle meant sending to 3 channels + 5 whispers would take 40+ seconds.
- **Deserializer broke on values containing `\` or `;`** — the old `gmatch("(.-[^\\]);")` pattern failed to handle escaped sequences correctly; replaced with a character-by-character state-machine parser.

### Added
- **`CCO.knownPlayers` registry** — `{ ["Name-Realm"] = { name, realm, lastSeen } }` — populated automatically as CCO presence pings are received
- **PRESENCE broadcast on login** (3-second delayed after all modules init) and every 90 seconds — sent via YELL + all available group/guild channels so strangers and group members alike can discover each other
- **WHISPER delivery for all order messages** — every `BroadcastOrder`, `CancelOrder` call now also whispers every entry in `CCO.knownPlayers`, giving unlimited-range delivery to all known CCO users
- **`MT_QUERY` message type (`"Q"`)** — when a new CCO player is discovered, the addon automatically whispers them a query; the recipient replies with all their active orders via WHISPER, synchronising state immediately
- **`Comm:HandlePresence(data, senderFull)`** — registers sender, detects first-time vs. returning player, triggers order query for new discoveries
- **`Comm:HandleQuery(requesterName)`** — responds to a query with all in-memory active orders via WHISPER
- **`Comm:PruneKnownPlayers()`** — removes players not seen for 10 minutes to keep the registry lean
- **`Comm:AcceptOrder()` now uses WHISPER directly to the requester** instead of broadcasting to all channels

### Changed
- `QueueBroadcast()` now sends to **all** matching group/guild channels simultaneously (GUILD + PARTY + RAID if all apply), not just the first matching one
- Send queue drain rate changed from 5 s/message → **0.4 s/message** (~2.5 msg/sec, safely below WoW's ~3–4 msg/sec rate limit)
- Queue capacity raised from 20 → **60** to accommodate multi-channel + whisper sends
- `MSG_VERSION` bumped from `1` → `2` (protocol change: added `realm` field to PRESENCE, new `MT_QUERY` type); v1 messages are silently ignored
- `CCO.version` corrected from `"1.0.0"` → `"1.4.0"` in `ClassicCraftingOrders.lua`

---

## [1.3.0] – 2026-03-09

### Added
- **Recipe database completely rebuilt** from CraftLib v0.5.0 TBC data — **2,092 recipes** across all 9 crafting professions (previously ~204 manually-authored entries)
- `convert_craftlib.py` — Python converter script that parses all CraftLib `Data/TBC/*/Recipes.lua` files and regenerates `Data/RecipeDB.lua` automatically
- `CCO:GetRecipesForSkill(skillLineID)` — helper function on the CCO namespace (defined in RecipeDB.lua) to fetch recipes for one profession
- `CCO:SearchRecipes(query)` — case-insensitive substring search across all 2,092 recipes; returns `{ skillLineID, recipe }` pairs
- **RecipeBrowser: UIDropDownMenu profession picker** replacing the left sidebar; dropdown shows recipe count per profession and a green ✓ for professions the player has in their skill book
- **RecipeBrowser: full-width recipe list** with column header strip (Recipe / Source / Skill)
- **RecipeBrowser: alternating row backgrounds** for better readability
- **RecipeBrowser: coloured source badges** — trainer (blue), vendor (yellow), drop (orange), reputation (purple), quest (yellow), discovery (teal)
- **RecipeBrowser: global cross-profession search** — when no profession is selected, typing in the search box searches all 2,092 recipes; clicking a result switches the dropdown and pre-selects the recipe
- **RecipeBrowser: live-scan indicator dot** (small green square) on rows where data was enriched by the live RecipeScanner
- **RecipeBrowser: Clear button** next to the search box to reset the filter in one click
- **RecipeBrowser: recipe count label** at the bottom of the list showing "Showing X recipe(s)"
- `source` field in RecipeDB now includes `"reputation"`, `"quest"` and `"discovery"` values (previously only trainer/vendor/drop)

### Changed
- `Data/RecipeDB.lua` is now **auto-generated**; the file header warns against manual edits and refers to `convert_craftlib.py`
- Reagents in RecipeDB now use plain `{itemID, count}` arrays with literal numbers — the local `R = { … }` reagent-constant block has been removed
- `RB:PopulateRecipeList()` now tries `RecipeScanner:GetSortedRecipes()` first and falls back to `CCO.RecipeDB` directly if the scanner has no data yet (previously only scanner path was used, causing empty list before first tradeskill scan)
- `RB:Toggle()` auto-selects the player's first known profession via `PROF_BY_ID` lookup instead of iterating `CCO.db.char.professions` without a name; if no known profession is found the first static entry (Alchemy) is pre-selected
- `RB:SelectProfession()` now clears the detail pane (icon, name, skill, reagents) when switching professions

### Removed
- Left profession sidebar (`BuildProfessionTabs`, `RebuildProfessionTabs`) replaced by UIDropDownMenu
- Local `R = { … }` reagent constant block from RecipeDB.lua

---

## [1.2.0] – 2026-03-08

### Fixed – TBC Classic API Compatibility
- **`Frame:SetBackdrop` nil crash** (`RecipeBrowser.lua:54`, `OrderBoard.lua:57`, `StatusMonitor.lua:51`) — In the Shadowlands-era client used by TBC Classic Anniversary `SetBackdrop` was moved into `BackdropTemplateMixin`. Added `"BackdropTemplate"` to all `CreateFrame` calls that use `SetBackdrop`; added `inherits="BackdropTemplate"` to `CCO_Dashboard` in `MainDashboard.xml`
- **`SearchBoxTemplate` does not exist in TBC Classic** (added in Cataclysm) — replaced with `InputBoxTemplate` in `RecipeBrowser.lua`; added manual placeholder text logic (`OnEditFocusGained` / `OnEditFocusLost`)
- **`C_Timer.NewTimer` does not exist in TBC Classic** (added in WoD) — replaced in `StatusMonitor.lua` with a `CreateFrame("Frame")` + `OnUpdate` countdown
- **`GetItemInfoInstant` does not exist in TBC Classic** (added in MoP) — removed from `RecipeScanner.lua` and `TradeAssistant.lua`; reagent item IDs are now sourced exclusively from `GetTradeSkillReagentItemLink`
- **`GameTooltip:SetItemByID` does not exist in TBC Classic** (added in Legion) — replaced in `RecipeBrowser.lua` and `OrderBoard.lua` with `GetItemInfo(id)` → `GameTooltip:SetHyperlink(link)`
- **`IsInGroup()` does not exist in TBC Classic** (added in Cataclysm) — replaced in `Communication.lua` with `GetNumPartyMembers() > 0`
- **`C_ChatInfo` nil guard** in `ClassicCraftingOrders.lua` — `C_ChatInfo.RegisterAddonMessagePrefix` now falls back to the global `RegisterAddonMessagePrefix` if `C_ChatInfo` is nil

### Fixed – Init chain crash isolation
- All `module:Initialize()` calls in the `PLAYER_LOGIN` handler are now wrapped with `safeInit()` using `pcall` — a crash in one module no longer prevents subsequent modules from loading

### Fixed – UI
- **"New Order" / "Order Board" showing nothing** — root cause was `SearchBoxTemplate` crash in `RecipeBrowser:CreateFrame()` leaving all child widgets nil; `Toggle()` then silently failed
- **"Order Board" frame nil** — same crash cascade; fixed by `SearchBoxTemplate` → `InputBoxTemplate` change
- **"My Orders" panel invisible** — added `BackdropTemplate`, `SetBackdrop`, solid `CreateTexture` fallback background, and empty-state label "You have no active crafting orders."
- **Panel mutual exclusion** — "My Orders" and "Settings" panels now hide each other when toggled; previously both could be open simultaneously
- **OrderBoard row backgrounds** — replaced `SetBackdrop` on individual row frames (would require `BackdropTemplate` per row, expensive) with `CreateTexture` on `"BACKGROUND"` layer
- **nil guard in `RB:Toggle()`** — added explicit check `if not RB.frame then` with a printed error
- **nil guard in `OB:Toggle()`** — same pattern applied to OrderBoard

---

## [1.1.0] – 2026-03-07

### Added
- German (deDE) localization (`Localization/deDE.lua`) with translated UI strings and profession names
- Jewelcrafting profession detection — added to `CCO.CraftingSkillLineIDs` whitelist and `CCO.Professions` table
- `SKILL_LINES_CHANGED` event in `Database.lua` to re-detect professions after talent-spec or realm-login delay
- Case-insensitive profession name fallback in `DB:RefreshProfessions()`
- Developer README.md with full architecture documentation, module reference, data flow diagrams, and API compatibility notes

### Fixed
- Main Dashboard close button had no `OnClick` handler — now calls `D:Toggle()`
- Main Dashboard background was invisible on first open — `SetBackdrop` call moved after frame creation and a `CreateTexture` solid-colour layer added as guaranteed fallback
- Profession detection incorrectly included gathering skills (Mining, Skinning, Herbalism) — fixed by using explicit `CCO.CraftingSkillLineIDs` whitelist instead of rank > 0 heuristic
- Recipe list not populating for Jewelcrafting — spellLine ID 755 was missing from the skill mapping
- Settings panel not visible — `BackdropColor` alpha was 0.0

### Changed
- `DB:RefreshProfessions()` now first tries exact name match, then case-insensitive match, then skillLine ID whitelist as final fallback
- `CCO.Professions` table extended with `frFR` and `esES` profession name fields (prepared for future localization)

---

## [1.0.0] – 2026-03-06

### Added
- Initial release of ClassicCraftingOrders
- `ClassicCraftingOrders.toc` — addon manifest targeting Interface 20504 (TBC Classic Anniversary)
- `ClassicCraftingOrders.lua` — bootstrap, PLAYER_LOGIN init, slash commands (`/cco`, `/craftingorders`), utility helpers (`CCO:Print`, `CCO:FormatGold`, `CCO:IsRecipeKnown`, etc.)
- `Data/Professions.lua` — static profession definitions for all 9 TBC crafting professions with skillLine IDs, icons, max skill, and multi-locale names
- `Data/RecipeDB.lua` — initial static recipe database (~204 hand-authored entries across 9 professions)
- `Core/Database.lua` — AceDB-3.0 wrapper with plain-Lua fallback; profession cache; favourites; settings; per-character order storage
- `Core/Communication.lua` — addon message send/receive via `C_ChatInfo.SendAddonMessage`; send throttling (5 s); automatic rebroadcast every 120 s; serialize/deserialize helpers
- `Core/OrderManager.lua` — in-memory order registry; order lifecycle (post → broadcast → accept → trade → complete); 10-minute expiry purge; pub/sub callbacks for UI
- `Core/RecipeScanner.lua` — `TRADE_SKILL_SHOW` / `TRADE_SKILL_UPDATE` listener; live scan merges recipe data (spellID, itemID, reagents) into `CCO.RecipeDB`
- `Core/TradeAssistant.lua` — trade window hooks; bag-slot glow for required reagents; helper overlay anchored to the trade frame
- `UI/MainDashboard.xml` — bare frame declaration (`CCO_Dashboard`, 360 × 460 px)
- `UI/MainDashboard.lua` — nav buttons (New Order, Order Board, My Orders, Settings); title-bar drag; close button; My Orders scrollable panel; Settings panel with checkboxes
- `UI/RecipeBrowser.lua` — profession sidebar tabs; recipe list with difficulty colour coding; reagent detail pane; commission input (gold/silver/copper); Post Order button; favourite toggle
- `UI/OrderBoard.lua` — crafter-facing order table; craftable-only filter; Accept button with whisper-to-accept flow; column sort (item / commission / mats)
- `UI/StatusMonitor.lua` — floating HUD showing current order status; fade-in animation; auto-hide after completion/cancellation; Cancel Order button
- `Libs/` — embedded LibStub, CallbackHandler-1.0, AceDB-3.0 (stub)
- `Localization/enUS.lua` — master string table

---

*Future entries should follow the format above: version, date, and categorised lists of Added / Changed / Fixed / Removed.*
