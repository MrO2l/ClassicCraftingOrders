# ClassicCraftingOrders – Developer Documentation

> **Target:** World of Warcraft – The Burning Crusade Classic Anniversary
> **Interface:** 20504 (TBC 2.5.4)
> **Version:** 1.3.0
> **Language:** Lua 5.1 / WoW XML

---

## Table of Contents

1. [Project Overview](#1-project-overview)
2. [Current Status](#2-current-status)
3. [Architecture](#3-architecture)
4. [File Structure](#4-file-structure)
5. [Module Reference](#5-module-reference)
6. [Data Flow](#6-data-flow)
7. [SavedVariables Schema](#7-savedvariables-schema)
8. [Network Protocol](#8-network-protocol)
9. [TBC Classic API Compatibility](#9-tbc-classic-api-compatibility)
10. [Known Limitations](#10-known-limitations)
11. [Slash Commands](#11-slash-commands)
12. [Extending the Addon](#12-extending-the-addon)

---

## 1. Project Overview

ClassicCraftingOrders is a **peer-to-peer crafting order system** for TBC Classic. It allows players to:

- **Post crafting orders** – search for a crafter for any known recipe, offer a commission, specify whether materials are provided
- **Browse orders as a crafter** – see all active orders in range, filtered to only those the player can craft
- **Complete the exchange** – whisper-to-accept handshake, then the Trade Assistant guides the item handover

There is **no server, no external database and no mail automation**. All communication uses `C_ChatInfo.SendAddonMessage` over the player's current group/guild/yell channel.

---

## 2. Current Status

| Area | Status | Notes |
|------|--------|-------|
| Core networking | ✅ Complete | Throttled send queue, auto-rebroadcast every 120 s |
| Order lifecycle | ✅ Complete | Post → broadcast → accept → trade → complete |
| Profession detection | ✅ Fixed (v1.2) | `rank > 0` bug removed; `SKILL_LINES_CHANGED` event added; case-insensitive name fallback |
| Recipe database (static) | ✅ Complete (v1.3) | **2,092 recipes** across all 9 crafting professions — auto-generated from CraftLib v0.5.0 |
| Recipe scanner (live) | ✅ Complete | Patches static DB from open tradeskill window; merges by recipe name |
| Main Dashboard UI | ✅ Fixed (v1.2) | `SetColorTexture` crash fixed; title-bar drag area; solid background |
| Recipe Browser UI | ✅ Redesigned (v1.3) | UIDropDownMenu profession picker, full-width recipe list, column headers, coloured source badges |
| Order Board UI | ✅ Complete | Sortable columns, craftable-only filter, accept button |
| Status Monitor UI | ✅ Complete | Floating HUD, spin animation, auto-hide on completion |
| Trade Assistant | ✅ Complete | Bag-slot glow, trade helper overlay |
| Localization | ✅ enUS + deDE + frFR + esES | Profession names for all four locales |
| AceDB-3.0 | ✅ Embedded stub | Full plain-Lua fallback path if library unavailable |
| TBC Classic API compat | ✅ Fixed (v1.2–1.3) | See [Section 9](#9-tbc-classic-api-compatibility) for full list |

### Open / Planned

- Recipe `minSkill` level is not reliably read from the live scan API (no direct accessor in TBC). Static DB values (from CraftLib) are used; the scanner fills gaps over time via the difficulty colour heuristic.
- Order range is limited to the player's current group/guild channel. Cross-realm order discovery is not possible without a relay.
- No in-game channel-selection config yet.

---

## 3. Architecture

```
┌─────────────────────────────────────────────────────┐
│                  ClassicCraftingOrders               │
│                                                      │
│  ┌──────────┐  ┌──────────┐  ┌───────────────────┐  │
│  │  Data/   │  │  Libs/   │  │   Localization/   │  │
│  │Professions│  │ AceDB    │  │  enUS  deDE  …    │  │
│  │ RecipeDB │  │ LibStub  │  └───────────────────┘  │
│  └────┬─────┘  └──────────┘                         │
│       │  read-only static data                       │
│  ┌────▼──────────────────────────────────────────┐   │
│  │                   Core/                        │   │
│  │  Database   Communication   OrderManager       │   │
│  │  RecipeScanner              TradeAssistant     │   │
│  └────┬──────────────────────────────────────────┘   │
│       │  callbacks / direct calls                     │
│  ┌────▼──────────────────────────────────────────┐   │
│  │                    UI/                         │   │
│  │  MainDashboard   RecipeBrowser   OrderBoard    │   │
│  │  StatusMonitor                                 │   │
│  └───────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────┘
```

**Load order** (defined in `.toc`):
```
Libs → Localization → Data → Core → UI → ClassicCraftingOrders.lua
```

The shared namespace `CCO` is the second vararg (`local ADDON_NAME, CCO = ...`) passed to every file by WoW's addon system. All public symbols are attached to this table.

---

## 4. File Structure

```
ClassicCraftingOrders/
├── ClassicCraftingOrders.toc       # TOC: interface version, load order
├── ClassicCraftingOrders.lua       # Bootstrap, slash commands, utility helpers
│
├── Libs/
│   ├── LibStub/LibStub.lua
│   ├── CallbackHandler-1.0/CallbackHandler-1.0.lua
│   └── AceDB-3.0/AceDB-3.0.lua
│
├── Localization/
│   ├── enUS.lua                    # Master string table (CCO.L = { … })
│   └── deDE.lua                    # German overrides
│
├── Data/
│   ├── Professions.lua             # Profession definitions + name→ID lookup tables
│   └── RecipeDB.lua                # Static recipe database (2,092 recipes — auto-generated)
│
├── Core/
│   ├── Database.lua                # AceDB wrapper, SavedVariables, profession cache
│   ├── Communication.lua           # SendAddonMessage send/receive, throttling
│   ├── OrderManager.lua            # Order registry, lifecycle, pub/sub callbacks
│   ├── RecipeScanner.lua           # Live tradeskill window scanner
│   └── TradeAssistant.lua          # Trade window hooks, bag glow, auto-fill
│
├── UI/
│   ├── MainDashboard.xml           # Bare frame declaration (CCO_Dashboard)
│   ├── MainDashboard.lua           # Dashboard logic, backdrop, drag, nav buttons
│   ├── RecipeBrowser.lua           # Recipe catalog + order posting form (v1.3 redesign)
│   ├── OrderBoard.lua              # Crafter order table view
│   └── StatusMonitor.lua           # Floating HUD for order state
│
└── README.md                       # This file
```

---

## 5. Module Reference

### 5.1 Main Entry Point – `ClassicCraftingOrders.lua`

Bootstraps the addon, registers slash commands and defines global utility helpers on the `CCO` namespace.

**Initialization sequence**

| Event | Action |
|-------|--------|
| `ADDON_LOADED` | `Database:Initialize()`, register addon message prefix |
| `PLAYER_LOGIN` | Initialize all Core and UI modules in dependency order; each wrapped in `pcall` to isolate failures |
| `PLAYER_LOGOUT` | `Database:Save()` |

**Public functions**

| Function | Description |
|----------|-------------|
| `CCO:Print(msg)` | Print `[CCO] msg` to default chat frame (cyan prefix) |
| `CCO:PrintError(msg)` | Print `[CCO Error] msg` in red |
| `CCO:PrintHelp()` | Print all slash commands |
| `CCO:CopyTable(t)` | Shallow-copy a table |
| `CCO:FormatGold(copper)` | Format copper integer as coloured `Xg Ys Zc` string |
| `CCO:IsRecipeKnown(spellID)` | Returns `true` if the player knows the given spell |
| `CCO:GetPlayerKey()` | Returns `"Name-Realm"` as unique player identifier |

---

### 5.2 `Core/Database.lua`

Wraps AceDB-3.0 (with a plain-Lua fallback). Exposes the `CCO.db` table and manages the profession cache.

**Public functions**

| Function | Description |
|----------|-------------|
| `DB:Initialize()` | Load SavedVariables, call `RefreshProfessions()`, register `SKILL_LINES_CHANGED` / `PLAYER_LOGIN` event listeners |
| `DB:Save()` | Called on logout; re-scans professions (AceDB saves automatically) |
| `DB:RefreshProfessions()` | Scan all skill lines; cache only crafting professions. Uses name-match (exact then case-insensitive) then skillLine ID whitelist fallback. Result stored in `CCO.db.char.professions[skillLineID]` |
| `DB:GetProfessions()` | Return the cached `char.professions` table |
| `DB:SaveMyOrder(order)` | Persist a player order to `char.myOrders` |
| `DB:RemoveMyOrder(orderID)` | Remove an order from `char.myOrders` |
| `DB:GetMyOrders()` | Return all orders posted by this character |
| `DB:ToggleFavourite(itemID)` | Toggle a recipe in `global.favourites`; returns new boolean state |
| `DB:IsFavourite(itemID)` | Returns `true` if an item is in the favourites set |
| `DB:GetSetting(key)` | Read a value from `char.settings` |
| `DB:SetSetting(key, value)` | Write a value to `char.settings` |

**SavedVariables root key:** `ClassicCraftingOrdersDB`

---

### 5.3 `Core/Communication.lua`

Handles all `SendAddonMessage` traffic. Messages are queued and drained at most once per `THROTTLE_SEC` (5 s). Own orders are rebroadcast every 120 s automatically.

**Constants**

| Name | Value | Purpose |
|------|-------|---------|
| `PREFIX` | `"CCO_ORDERS"` | Addon message prefix (≤ 16 chars) |
| `THROTTLE_SEC` | `5` | Minimum gap between sent messages |
| `REBROADCAST_SEC` | `120` | Re-broadcast interval for own orders |
| `MAX_QUEUE` | `20` | Maximum queued outgoing messages |
| `MSG_VERSION` | `1` | Protocol version byte in every message |

**Message types**

| Code | Constant | Payload keys |
|------|----------|--------------|
| `P` | `MT_ORDER_POST` | `id, item, spell, player, comm, mats, exp` |
| `C` | `MT_ORDER_CANCEL` | `id` |
| `A` | `MT_ORDER_ACCEPT` | `id, crafter` |
| `X` | `MT_PRESENCE` | `player` |

**Distribution channel priority:** GUILD → RAID → PARTY → YELL (fallback, ~300 yards)

**Public functions**

| Function | Description |
|----------|-------------|
| `Comm:Initialize()` | Register `CHAT_MSG_ADDON` listener, start send queue ticker and rebroadcast scheduler |
| `Comm:BroadcastOrder(order)` | Enqueue a `P` message |
| `Comm:CancelOrder(orderID)` | Enqueue a `C` message |
| `Comm:AcceptOrder(orderID, crafterName)` | Enqueue an `A` message |
| `Comm:AnnouncePresence()` | Enqueue an `X` message |
| `Comm:Serialize(t)` | Encode key-value table to `key=value;…` string with escaped delimiters |
| `Comm:Deserialize(str)` | Decode back to table; auto-converts numerics |

---

### 5.4 `Core/OrderManager.lua`

Central in-memory registry for all active orders (local + received). Fires lightweight pub/sub callbacks for UI modules.

**Constants:** `ORDER_DURATION = 600 s`, `MAX_ORDERS = 100`

**Order table fields**

```lua
{
    id           = "Name_timestamp_rand",  -- unique string key
    itemID       = number,
    spellID      = number,
    playerName   = "Name-Realm",
    commission   = number,                 -- copper
    matsProvided = boolean,
    expires      = GetTime() + 600,
    status       = "searching|accepted|completed|cancelled",
    crafterName  = string or nil,
    canCraft     = boolean,                -- set on receive
}
```

**Public functions**

| Function | Description |
|----------|-------------|
| `OM:Initialize()` | Start 30-s expiry purge ticker |
| `OM:PostOrder(itemID, spellID, commission, mats)` | Create, persist, broadcast. Returns order table or `nil` |
| `OM:CancelMyOrder(orderID)` | Cancel own order, broadcast cancel, fire callbacks |
| `OM:ReceiveOrder(order)` | Process an incoming order from the network; sets `canCraft` flag |
| `OM:CancelOrder(orderID)` | Remove any order by ID |
| `OM:OnOrderAccepted(orderID, crafterName)` | Update own order status, notify StatusMonitor |
| `OM:GetAllOrders()` | Return all `activeOrders` |
| `OM:GetOrder(orderID)` | Return single order or `nil` |
| `OM:GetMyOrders()` | Return only orders posted by the current player |
| `OM:CountOrders()` | Return total active order count |
| `OM:RegisterCallback(event, fn)` | Subscribe to `onOrderAdded`, `onOrderRemoved`, or `onOrderUpdated` |
| `OM:FireCallback(event, …)` | Dispatch event to all subscribers (wrapped in `pcall`) |
| `OM:PurgeExpiredOrders()` | Remove all orders past their `expires` time |
| `OM:GenerateID()` | Return a unique order ID string |

---

### 5.5 `Core/RecipeScanner.lua`

Listens for `TRADE_SKILL_SHOW` and `TRADE_SKILL_UPDATE`. When a tradeskill window is opened it reads every recipe via Blizzard's API and merges the result into `CCO.RecipeDB`.

**State:** `RS.scannedProfessions` – set of `skillLineID` values scanned this session

**Public functions**

| Function | Description |
|----------|-------------|
| `RS:Initialize()` | Register `TRADE_SKILL_SHOW` / `TRADE_SKILL_UPDATE` events |
| `RS:ScanCurrentTradeskill()` | Read the open tradeskill window and merge into `CCO.RecipeDB` |
| `RS:ReadRecipeAtIndex(i, name, type)` | Read one recipe at tradeskill index `i`; returns recipe table |
| `RS:IsProfessionScanned(skillLineID)` | Returns `true` if scanned this session |
| `RS:GetSortedRecipes(skillLineID)` | Return merged recipes sorted by `minSkill` then `name` |
| `RS:PlayerCanCraft(skillLineID, recipe)` | Returns `true` if player's cached rank meets `recipe.minSkill` |

**Scan data flow**
```
TRADE_SKILL_SHOW
  └─► ScanCurrentTradeskill()
        ├─ GetTradeSkillLine()         → profession name → skillLineID
        ├─ GetTradeSkillInfo(i)        → name, difficulty colour
        ├─ GetTradeSkillItemLink(i)    → itemID or enchantID
        ├─ GetTradeSkillRecipeLink(i)  → spellID
        └─ GetTradeSkillReagentInfo()  → reagent list
              └─► merge into CCO.RecipeDB[skillLineID]
                    └─► RecipeBrowser:OnDatabaseUpdated(skillLineID)
```

---

### 5.6 `Core/TradeAssistant.lua`

Hooks into the trade window. When an active order is linked to the current trade target it shows a helper overlay and highlights reagents in the player's bags.

**Events:** `TRADE_SHOW`, `TRADE_CLOSED`, `TRADE_PLAYER_ITEM_CHANGED`, `BAG_UPDATE`

**Public functions**

| Function | Description |
|----------|-------------|
| `TA:Initialize()` | Register trade events |
| `TA:FindOrderForPlayer(playerName)` | Scan active orders for one matching this player |
| `TA:ShowTradeHelper()` | Create/show the overlay frame anchored to the trade window |
| `TA:HideTradeHelper()` | Hide and clean up the overlay |
| `TA:UpdateTradeHelper()` | Refresh slot status on `TRADE_PLAYER_ITEM_CHANGED` |
| `TA:HighlightReagentsInBags(order)` | Apply green glow (`ButtonHilight-Square`) to relevant bag slots |
| `TA:ClearBagGlows()` | Remove all glow overlays |

---

### 5.7 `Data/Professions.lua`

Authoritative list of crafting professions for TBC Classic. Gathering professions and Fishing are intentionally excluded.

**Tables populated at load time**

| Table | Key → Value |
|-------|-------------|
| `CCO.Professions` | `skillLineID → profDef` |
| `CCO.ProfessionsByName` | `localizedName → skillLineID` (enUS + deDE + frFR + esES) |
| `CCO.CraftingSkillLineIDs` | `skillLineID → true` (O(1) whitelist) |

**Profession definition fields**

```lua
{
    skillLineID  = number,       -- Blizzard DBC skillLine ID
    name         = string,       -- enUS client name
    nameDE       = string,       -- deDE
    nameFR       = string,       -- frFR
    nameES       = string,       -- esES
    icon         = string,       -- texture suffix (without "Interface\\Icons\\")
    maxSkill     = 375,
    trainerSpell = number,
    category     = "primary" | "secondary",
}
```

**Supported professions:** Alchemy (171), Blacksmithing (164), Enchanting (333), Engineering (202), Jewelcrafting (755), Leatherworking (165), Tailoring (197), Cooking (185), First Aid (129)

**Public function**

| Function | Description |
|----------|-------------|
| `CCO:GetProfessionByName(name)` | Exact match first, then case-insensitive fallback. Returns `profDef` or `nil` |

---

### 5.8 `Data/RecipeDB.lua`

Static recipe database auto-generated from **CraftLib v0.5.0** TBC recipe data. Contains **2,092 recipes** across all 9 crafting professions.

> **Do not edit manually.** Re-generate with the bundled `convert_craftlib.py` script if recipe data needs updating.

**Recipe counts by profession**

| Profession | SkillLine ID | Recipes |
|------------|-------------|---------|
| Alchemy | 171 | 182 |
| Blacksmithing | 164 | 375 |
| Enchanting | 333 | 218 |
| Engineering | 202 | 239 |
| Jewelcrafting | 755 | 257 |
| Leatherworking | 165 | 376 |
| Tailoring | 197 | 314 |
| Cooking | 185 | 116 |
| First Aid | 129 | 15 |
| **Total** | | **2,092** |

**Entry structure**
```lua
CCO.RecipeDB[skillLineID] = {
    {
        spellID  = number,       -- may be nil until scanned live
        itemID   = number,       -- 0 for enchants
        name     = string,
        minSkill = number,
        source   = "trainer" | "vendor" | "drop" | "reputation" | "quest" | "discovery",
        reagents = { { itemID, count }, … },
    },
    …
}
```

**Helper functions** (defined in RecipeDB.lua, attached to the `CCO` namespace)

| Function | Description |
|----------|-------------|
| `CCO:GetRecipesForSkill(skillLineID)` | Return recipe list for one profession, or `{}` |
| `CCO:SearchRecipes(query)` | Case-insensitive substring search across all professions; returns `{ skillLineID, recipe }` pairs |

---

### 5.9 `UI/MainDashboard`

The primary window. Opened with `/cco`.

**XML (`MainDashboard.xml`)** declares only the bare `CCO_Dashboard` frame (360 × 460 px, strata HIGH, hidden, `inherits="BackdropTemplate"`). All visual and interactive setup is in Lua.

**Lua (`MainDashboard.lua`)**

| Function | Description |
|----------|-------------|
| `D:Initialize()` | Find `CCO_Dashboard`, apply background texture + `SetBackdrop`, create title-bar drag handle, close button, nav buttons |
| `D:BuildNavButtons()` | Create 4 nav buttons; each gets `SetFrameLevel(parent + 10)` to ensure click events reach the button |
| `D:BuildMyOrdersPanel()` | Scrollable list of the player's own active orders |
| `D:ShowMyOrdersPanel()` | Toggle the "My Orders" sub-panel; hides Settings if open |
| `D:RefreshMyOrders()` | Rebuild all rows in the My Orders scroll frame |
| `D:ShowSettingsPanel()` | Toggle the settings panel with three checkboxes; hides My Orders if open |
| `D:Toggle()` | Show/hide the window |
| `D:Hide()` | Hide the window and persist its shown state |
| `D:SavePosition()` | Write centre coordinates to `char.ui.dashboard.{x,y}` |
| `D:RestorePosition()` | Read saved position and re-anchor the frame |
| `D:ResetPosition()` | Centre on screen (used by `/cco reset`) |

**Background:** A `CreateTexture` layer (`WHITE8X8` tinted dark) is always created first as a guaranteed fallback. `SetBackdrop` is called afterwards for the tiled dialog texture and border.

**Drag:** The main frame does **not** use `EnableMouse(true)` or `RegisterForDrag`. A 34-px title-bar sub-frame owns drag handling so the parent never intercepts child button clicks.

---

### 5.10 `UI/RecipeBrowser.lua`

Recipe catalog where players browse recipes and create orders. Redesigned in v1.3 with a `UIDropDownMenu` profession picker replacing the left sidebar.

**Layout (v1.3)**
```
┌─────────────────────────────────────────────┐
│  Title bar                         [X]       │
├─────────────────────────────────────────────┤
│  [Profession ▼]  [Search…………]  [Clear]      │
├──────┬──────────────────────┬──────┬────────┤
│Recipe│                      │Source│ Skill  │
├──────┴──────────────────────┴──────┴────────┤
│  Recipe list (scrollable, full width)        │
│  • alternating row backgrounds               │
│  • difficulty-coloured names                 │
│  • coloured source badges                    │
│  • live-scan dot  ■  for scanner data        │
├─────────────────────────────────────────────┤
│  Detail pane: icon │ name │ skill │ reagents │
├─────────────────────────────────────────────┤
│  Commission: [__g] [__s] [__c]  ☑ Mats  [Post Order] │
└─────────────────────────────────────────────┘
```

**Profession dropdown** shows all 9 professions with:
- Recipe count in grey `(182)`
- Green `✓` if the player has that profession in their skill book

**Global search** — when no profession is selected, typing in the search box searches all 2,092 recipes across every profession. Clicking a result auto-selects the matching profession in the dropdown.

**Public functions**

| Function | Description |
|----------|-------------|
| `RB:Initialize()` | Create all sub-frames |
| `RB:OnDatabaseUpdated(skillLineID)` | Called by RecipeScanner; refreshes list if profession matches |
| `RB:SelectProfession(skillLineID)` | Set active profession, reset search, populate recipe list |
| `RB:PopulateRecipeList([filter])` | Build recipe rows; prefers live scanner data, falls back to static DB |
| `RB:GetDifficultyColor(minSkill, rank)` | Return `r,g,b` using Classic traffic-light scale |
| `RB:ShowRecipeDetail(recipe)` | Fill detail pane (icon, name, skill req, reagents) |
| `RB:ApplySearchFilter(text)` | Re-run `PopulateRecipeList` or trigger `GlobalSearch` |
| `RB:GlobalSearch(text)` | Cross-profession name search; clicking a result switches profession |
| `RB:PostOrder()` | Read commission inputs, call `OrderManager:PostOrder()` |
| `RB:Toggle()` | Show/hide; auto-selects player's first known profession on open |

**Difficulty colours**

| `rank - minSkill` | Colour |
|-------------------|--------|
| < 0 | Grey (can't learn yet) |
| 0 – 9 | Orange (skill-up likely) |
| 10 – 24 | Yellow |
| 25 – 49 | Green |
| ≥ 50 | Grey (trivial) |

**Source badge colours**

| Source | Colour |
|--------|--------|
| trainer | Light blue |
| vendor | Yellow |
| drop | Orange |
| reputation | Purple |
| quest | Bright yellow |
| discovery | Teal |

---

### 5.11 `UI/OrderBoard.lua`

Crafter-facing table of all active orders received from the network.

**Columns:** Item, Requester, Commission, Materials, Action (Accept button for craftable orders)

**Public functions**

| Function | Description |
|----------|-------------|
| `OB:Initialize()` | Create frame, subscribe to all three OrderManager callbacks |
| `OB:Refresh()` | Clear and rebuild all visible rows |
| `OB:CreateRow(order, index)` | Build one row with alternating background and accept button |
| `OB:AcceptOrder(order)` | Send accept message, whisper requester, refresh board |
| `OB:Toggle()` | Show/hide; calls `Refresh()` when opening |

Filter modes: `"all"` / `"craftable"`. Sort keys: `"item"`, `"comm"` (default), `"mats"`.

---

### 5.12 `UI/StatusMonitor.lua`

A small floating HUD anchored 200 px above the bottom of the screen. Shows the local player's current order state.

**Status keys**

| Key | Icon colour | Cancel btn | Auto-hide |
|-----|-------------|------------ |-----------|
| `searching` | Yellow | Yes | No |
| `found` | Green | No | No |
| `trade_ready` | Cyan | No | No |
| `completed` | Green | No | Yes (8 s) |
| `cancelled` | Red | No | Yes (8 s) |

**Public functions**

| Function | Description |
|----------|-------------|
| `SM:Initialize()` | Create frame; hide if `showStatusMonitor` setting is `false` |
| `SM:ShowStatus(key, crafterName, order)` | Update text, colour, animation, cancel button |
| `SM:Hide()` | Hide frame, stop animation, clear order ID |
| `SM:PlayAppearAnimation()` | Fade-in + 12-px upward slide over 0.3 s |

---

## 6. Data Flow

### Posting an order (Requester)

```
RecipeBrowser:PostOrder()
  └─► OrderManager:PostOrder(itemID, spellID, commission, mats)
        ├─► Database:SaveMyOrder(order)
        ├─► Communication:BroadcastOrder(order)
        │     └─► C_ChatInfo.SendAddonMessage("CCO_ORDERS", serialized, dist)
        ├─► OM:FireCallback("onOrderAdded")  →  OrderBoard:Refresh()
        └─► StatusMonitor:ShowStatus("searching")
```

### Receiving an order (Crafter)

```
CHAT_MSG_ADDON (prefix = "CCO_ORDERS")
  └─► Communication:OnMessageReceived()
        └─► OrderManager:ReceiveOrder(order)
              ├─► order.canCraft = CCO:IsRecipeKnown(spellID)
              └─► OM:FireCallback("onOrderAdded")  →  OrderBoard:Refresh()
```

### Accepting an order (Crafter)

```
OrderBoard:AcceptOrder(order)
  ├─► Communication:AcceptOrder(orderID, crafterName)
  └─► SendChatMessage(whisper to requester)

[Requester side receives MT_ORDER_ACCEPT]
OrderManager:OnOrderAccepted(orderID, crafterName)
  ├─► StatusMonitor:ShowStatus("found", crafterName)
  └─► OM:FireCallback("onOrderUpdated")
```

---

## 7. SavedVariables Schema

```lua
ClassicCraftingOrdersDB = {
    global = {
        favourites = { [itemID] = true, … },
        dbVersion  = 1,
    },
    char = {                      -- keyed by "Name-Realm" in fallback mode
        myOrders   = { [orderID] = order, … },
        professions= {
            [skillLineID] = {
                skillLineID = number,
                name        = string,
                rank        = number,
                maxRank     = number,
            },
        },
        ui = {
            dashboard  = { x = nil, y = nil, shown = false },
            orderBoard = { x = nil, y = nil, shown = false },
        },
        settings = {
            showOnlyMatchingOrders = true,
            broadcastInterval      = 120,
            showStatusMonitor      = true,
            commissionCurrency     = "gold",
            autoFillTrade          = true,
        },
    },
}
```

---

## 8. Network Protocol

### Message format

```
_t=<type>;<key>=<value>;…
```

All values are serialized as strings. The characters `|`, `;`, `=` inside values are escaped (`||`, `\;`, `\=`). Numbers are auto-cast via `tonumber()` on deserialization.

### Limits

| Parameter | Value |
|-----------|-------|
| Max message length | 255 bytes (WoW hard limit) |
| Send throttle | 5 s between messages |
| Max queue depth | 20 messages |
| Rebroadcast interval | 120 s |
| Order lifetime | 600 s (10 min) |
| Max active orders | 100 |

---

## 9. TBC Classic API Compatibility

TBC Classic Anniversary uses the **Shadowlands-era game client**. Several APIs behave differently from both retail and vanilla Classic. The table below documents every compatibility decision in the codebase.

| API | Status | Decision |
|-----|--------|----------|
| `Frame:SetBackdrop({…})` | ⚠️ Requires `BackdropTemplate` | In the Shadowlands client `SetBackdrop` was moved into `BackdropTemplateMixin`. **All** frames that call `SetBackdrop` must pass `"BackdropTemplate"` to `CreateFrame()` or declare `inherits="BackdropTemplate"` in XML |
| `Texture:SetColorTexture(r,g,b,a)` | ❌ Retail-only | Use `SetTexture("Interface\\Buttons\\WHITE8X8")` + `SetVertexColor()` |
| `"SearchBoxTemplate"` in `CreateFrame` | ❌ Cataclysm+ | Use `"InputBoxTemplate"` with manual placeholder text logic |
| `C_Timer.NewTimer()` | ❌ WoD+ | Use a `CreateFrame("Frame")` + `OnUpdate` countdown instead |
| `GetItemInfoInstant()` | ❌ MoP+ | **Not available.** Use `GetTradeSkillReagentItemLink(i, r)` for reagent IDs |
| `GameTooltip:SetItemByID()` | ❌ Legion+ | Use `GetItemInfo(id)` to get the item link, then `GameTooltip:SetHyperlink(link)` |
| `IsInGroup()` | ❌ Cataclysm+ | Use `GetNumPartyMembers() > 0` |
| `C_ChatInfo.SendAddonMessage()` | ✅ Available | Primary channel; falls back to `SendAddonMessage()` if `C_ChatInfo` is nil |
| `C_ChatInfo.RegisterAddonMessagePrefix()` | ✅ Available | Falls back to `RegisterAddonMessagePrefix()` |
| `GetTradeSkillInfo()` / `GetTradeSkillItemLink()` | ✅ Classic API | Used in RecipeScanner |
| `GetTradeSkillReagentInfo()` / `GetTradeSkillReagentItemLink()` | ✅ Classic API | Used in RecipeScanner for reagent data |
| `UIDropDownMenu_Initialize()` / `UIDropDownMenu_AddButton()` | ✅ All WoW versions | Used for the profession picker in RecipeBrowser |

**Separator / rule textures** — always use this pattern:
```lua
local line = parent:CreateTexture(nil, "ARTWORK")
line:SetTexture("Interface\\Buttons\\WHITE8X8")
line:SetVertexColor(r, g, b)
line:SetAlpha(a)
```

**`pcall` in PLAYER_LOGIN** — all `module:Initialize()` calls are wrapped in a `safeInit()` helper so a crash in one module does not prevent subsequent modules from loading:
```lua
local function safeInit(module, name)
    local ok, err = pcall(function() module:Initialize() end)
    if not ok then CCO:PrintError(name .. " init error: " .. tostring(err)) end
end
```

---

## 10. Known Limitations

- **`minSkill` from live scan** — TBC has no direct API to read the required skill level from a tradeskill entry. The scanner stores the difficulty colour category as `skillType` but not the exact threshold. Static DB values (from CraftLib) are used where available; scanner-only recipes show `minSkill = 0` until patched manually.
- **Order range** — limited to the player's current GUILD / RAID / PARTY channel; YELL is the fallback (~300 yard radius). No cross-realm broadcast.
- **Enchanting** — enchants produce no item (`itemID = 0`). Tooltips call `GetItemInfo(0)` which returns nil; a question-mark icon is shown as fallback.
- **Item icon cold cache** — `GetItemInfo()` returns `nil` for items the client has never seen before. Reagent icons fall back to a question mark until the item is cached by the game client.
- **AceDB stub** — the embedded AceDB-3.0 is a minimal stub. Full profile switching and cross-character data sharing are not implemented.
- **`spellID` in static DB** — CraftLib stores `id` (spell ID) for every recipe. This is mapped to `spellID` in RecipeDB. For recipes only known via live scan, `spellID` is filled in at runtime by `RecipeScanner:ScanCurrentTradeskill()`.

---

## 11. Slash Commands

| Command | Action |
|---------|--------|
| `/cco` or `/cco show` | Toggle the main dashboard |
| `/cco orders` | Open the order board directly |
| `/cco reset` | Re-centre the dashboard window on screen |
| `/cco help` | Print all commands to chat |
| `/craftingorders` | Alias for `/cco` |

---

## 12. Extending the Addon

### Regenerating the recipe database

The recipe database is auto-generated from CraftLib. To regenerate after updating CraftLib:

```bash
python3 convert_craftlib.py
```

The script reads all `Data/TBC/*/Recipes.lua` files from the CraftLib directory and writes a fresh `Data/RecipeDB.lua`.

### Adding a new locale

1. Create `Localization/xxXX.lua` (e.g. `esES.lua`)
2. Guard with `if GetLocale() ~= "esES" then return end`
3. Override keys in `CCO.L` that differ from `enUS`
4. Add the file to `.toc` after `Localization\enUS.lua`
5. Add translated profession names to `Data/Professions.lua`:
   ```lua
   nameES = "Alquimia",
   ```
   and include the new field in the `ProfessionsByName` builder loop:
   ```lua
   if prof.nameES then CCO.ProfessionsByName[prof.nameES] = id end
   ```

### Adding new static recipes manually

Edit `Data/RecipeDB.lua`. Add entries to the relevant profession table:

```lua
CCO.RecipeDB[171] = {          -- 171 = Alchemy
    { spellID = 12345, itemID = 67890, name = "Super Flask",
      minSkill = 350, source = "trainer",
      reagents = { {22785, 4}, {22789, 1}, {28570, 1} } },
    …
}
```

Note: reagents use plain `{itemID, count}` arrays (no named `R.` constants in the generated file).

### Subscribing to order events

```lua
CCO.OrderManager:RegisterCallback("onOrderAdded", function(order)
    -- order is the full order table
end)
CCO.OrderManager:RegisterCallback("onOrderRemoved", function(orderID)
    -- only the ID is passed for removed orders
end)
CCO.OrderManager:RegisterCallback("onOrderUpdated", function(order)
    -- fires when status changes (e.g. searching → accepted)
end)
```

### Adding a new setting

1. Add a default in `Core/Database.lua` → `defaults.char.settings`:
   ```lua
   myNewSetting = true,
   ```
2. Add a checkbox in `UI/MainDashboard.lua` → `D:ShowSettingsPanel()`:
   ```lua
   AddCheckbox(sp, "myNewSetting", "My setting label", -96)
   ```
3. Read it anywhere:
   ```lua
   if CCO.Database:GetSetting("myNewSetting") then … end
   ```
