-- ============================================================
-- ClassicCraftingOrders - Database Module (AceDB-3.0)
-- ============================================================
local ADDON_NAME, CCO = ...

CCO.Database = {}
local DB = CCO.Database

-- Default values stored per-character and globally
local defaults = {
    global = {
        -- Pinned / favourite recipes (shared across all characters)
        favourites = {},
        -- Version for migration purposes
        dbVersion  = 1,
    },
    char = {
        -- Orders posted by THIS character that are still active
        myOrders = {},
        -- Known professions cache (updated on login)
        professions = {},
        -- UI state
        ui = {
            dashboard = { x = nil, y = nil, shown = false },
            orderBoard = { x = nil, y = nil, shown = false },
        },
        -- Settings
        settings = {
            showOnlyMatchingOrders = true,    -- Crafter: only highlight craftable orders
            broadcastInterval      = 120,     -- Seconds between order re-broadcasts
            showStatusMonitor      = true,
            commissionCurrency     = "gold",  -- "gold" | "items"
            autoFillTrade          = true,
        },
    },
}

--- Initialise (or load) the SavedVariables database.
function DB:Initialize()
    -- AceDB-3.0 creates the global table if it doesn't exist
    if LibStub and LibStub("AceDB-3.0", true) then
        self.db = LibStub("AceDB-3.0"):New("ClassicCraftingOrdersDB", defaults, true)
        CCO.db = self.db
    else
        -- Fallback: simple manual initialisation (no AceDB available)
        ClassicCraftingOrdersDB = ClassicCraftingOrdersDB or {}
        local sv = ClassicCraftingOrdersDB

        -- Global
        sv.global            = sv.global or {}
        sv.global.favourites = sv.global.favourites or {}
        sv.global.dbVersion  = sv.global.dbVersion  or 1

        -- Per-character (keyed by playerKey)
        local key = CCO:GetPlayerKey()
        sv.char              = sv.char or {}
        sv.char[key]         = sv.char[key] or {}
        local c              = sv.char[key]
        c.myOrders           = c.myOrders    or {}
        c.professions        = c.professions or {}
        c.ui                 = c.ui          or CCO:CopyTable(defaults.char.ui)
        c.settings           = c.settings    or CCO:CopyTable(defaults.char.settings)

        -- Expose via a unified interface
        CCO.db = {
            global = sv.global,
            char   = c,
        }
    end

    -- Refresh profession cache immediately
    self:RefreshProfessions()

    -- Also refresh whenever the player's skill lines change (e.g. after training
    -- a new profession rank or learning a new profession entirely).
    local skillFrame = CreateFrame("Frame")
    skillFrame:RegisterEvent("SKILL_LINES_CHANGED")
    skillFrame:RegisterEvent("PLAYER_LOGIN")
    skillFrame:SetScript("OnEvent", function()
        DB:RefreshProfessions()
    end)
end

--- Persist changes (called on PLAYER_LOGOUT).
function DB:Save()
    -- AceDB saves automatically; for fallback mode write is already live
    self:RefreshProfessions()
end

--- Scan and cache the player's CRAFTING professions only.
--
-- BUG-FIX: The previous implementation iterated ALL skill lines including
-- combat skills, weapons, languages, and gathering professions.  This caused
-- the addon to show non-crafting skills in the profession picker and to
-- incorrectly evaluate "can craft" checks against irrelevant skills.
--
-- The fix uses CCO.CraftingSkillLineIDs (defined in Data/Professions.lua),
-- which is the explicit allowlist of crafting profession skillLine IDs for
-- TBC Classic (Alchemy=171, Blacksmithing=164, Enchanting=333, Engineering=202,
-- Jewelcrafting=755, Leatherworking=165, Tailoring=197, Cooking=185, First Aid=129).
--
-- GetSkillLineInfo(i) return values in TBC Classic (2.4.3):
--   1: name          (string)
--   2: isHeader      (boolean)
--   3: isExpanded    (boolean)
--   4: skillRank     (number)
--   5: numTempPoints (number)
--   6: skillModifier (number)
--   7: skillMaxRank  (number)
--   8: isAuto        (boolean)
--   9: isExclusive   (boolean)
--  10: spellOffset   (number)
--  11: skillLine     (number)  ← skillLineID in TBC (same as 13th in some builds)
--  12: rankModifier  (number)
-- Note: The exact position of skillLineID varies by build; we match by NAME
-- as a safe fallback using CCO.ProfessionsByName.
function DB:RefreshProfessions()
    -- Guard: Professions.lua must be loaded first
    if not CCO.CraftingSkillLineIDs or not CCO.ProfessionsByName then
        return
    end

    local profs = {}
    local numLines = GetNumSkillLines()

    for i = 1, numLines do
        -- GetSkillLineInfo returns up to 12 values in TBC Classic
        local name, isHeader, _, rank, _, _, maxRank, _, _, _, skillLineArg = GetSkillLineInfo(i)

        -- Skip headers; rank can be 0 for newly-trained professions so we do NOT
        -- filter on rank > 0 (that was the original Jewelcrafting detection bug).
        if not isHeader and name then

            -- PRIMARY CHECK: exact match against localized profession names
            -- CCO.ProfessionsByName contains both enUS and deDE keys (and frFR via Professions.lua)
            local profID = CCO.ProfessionsByName[name]

            -- CASE-INSENSITIVE FALLBACK: some client builds return names with
            -- different capitalisation (e.g. "Jewelcrafting" vs "JewelCrafting")
            if profID == nil then
                local nameLower = name:lower()
                for pName, pID in pairs(CCO.ProfessionsByName) do
                    if pName:lower() == nameLower then
                        profID = pID
                        break
                    end
                end
            end

            -- SECONDARY CHECK: if TBC Classic returns a numeric skillLine ID
            -- in argument 11, verify it's in our crafting whitelist
            if profID == nil and type(skillLineArg) == "number" and skillLineArg > 0 then
                if CCO.CraftingSkillLineIDs[skillLineArg] then
                    profID = skillLineArg
                end
            end

            -- Only store if we identified it as a crafting profession
            if profID then
                profs[profID] = {
                    skillLineID = profID,
                    name        = name,
                    rank        = rank,
                    maxRank     = maxRank or 375,
                }
            end
        end
    end

    CCO.db.char.professions = profs

    -- Debug output (only once per session, remove in release)
    if not DB._profPrinted then
        DB._profPrinted = true
        local count = 0
        for _ in pairs(profs) do count = count + 1 end
        CCO:Print(string.format("Detected %d crafting profession(s).", count))
        for id, p in pairs(profs) do
            CCO:Print(string.format("  [%d] %s (%d/%d)", id, p.name, p.rank, p.maxRank))
        end
    end
end

--- Return the cached professions table.
function DB:GetProfessions()
    return CCO.db.char.professions
end

--- Add/update an order to the "my orders" list.
function DB:SaveMyOrder(order)
    CCO.db.char.myOrders[order.id] = order
end

--- Remove an order from the "my orders" list.
function DB:RemoveMyOrder(orderID)
    CCO.db.char.myOrders[orderID] = nil
end

--- Return all orders posted by this character.
function DB:GetMyOrders()
    return CCO.db.char.myOrders
end

--- Toggle a recipe as favourite.
function DB:ToggleFavourite(itemID)
    if CCO.db.global.favourites[itemID] then
        CCO.db.global.favourites[itemID] = nil
        return false
    else
        CCO.db.global.favourites[itemID] = true
        return true
    end
end

--- Check if a recipe is a favourite.
function DB:IsFavourite(itemID)
    return CCO.db.global.favourites[itemID] == true
end

--- Get a specific setting value.
function DB:GetSetting(key)
    return CCO.db.char.settings[key]
end

--- Set a specific setting value.
function DB:SetSetting(key, value)
    CCO.db.char.settings[key] = value
end
