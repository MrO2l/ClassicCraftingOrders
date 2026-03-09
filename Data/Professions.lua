-- ============================================================
-- ClassicCraftingOrders - Profession Definitions
--
-- Only CRAFTING professions are listed here.
-- Gathering professions (Mining, Herbalism, Skinning) and
-- the non-recipe secondary profession Fishing are intentionally
-- excluded because they produce no craftable orders.
--
-- SkillLine IDs are the Blizzard internal IDs for TBC 2.4.3
-- (Anniversary interface 20504). Source: Blizzard DBC data.
-- ============================================================
local ADDON_NAME, CCO = ...

CCO.Professions = {
    -- --------------------------------------------------------
    -- Primary Crafting Professions
    -- enUS = English client name (from GetSkillLineInfo)
    -- deDE = German client name
    -- frFR = French client name
    -- esES = Spanish (Spain) client name
    -- --------------------------------------------------------
    [171] = {
        skillLineID  = 171,
        name         = "Alchemy",
        nameDE       = "Alchemie",
        nameFR       = "Alchimie",
        nameES       = "Alquimia",
        icon         = "Trade_Alchemy",
        maxSkill     = 375,
        trainerSpell = 2259,
        category     = "primary",
    },
    [164] = {
        skillLineID  = 164,
        name         = "Blacksmithing",
        nameDE       = "Schmiedekunst",
        nameFR       = "Forge",
        nameES       = "Herrería",
        icon         = "Trade_BlackSmithing",
        maxSkill     = 375,
        trainerSpell = 2018,
        category     = "primary",
    },
    [333] = {
        skillLineID  = 333,
        name         = "Enchanting",
        nameDE       = "Verzauberkunst",
        nameFR       = "Enchantement",
        nameES       = "Encantamiento",
        icon         = "Trade_Engraving",
        maxSkill     = 375,
        trainerSpell = 7411,
        category     = "primary",
    },
    [202] = {
        skillLineID  = 202,
        name         = "Engineering",
        nameDE       = "Ingenieurskunst",
        nameFR       = "Ingénierie",
        nameES       = "Ingeniería",
        icon         = "Trade_Engineering",
        maxSkill     = 375,
        trainerSpell = 4036,
        category     = "primary",
    },
    [755] = {
        skillLineID  = 755,
        name         = "Jewelcrafting",
        nameDE       = "Juwelenschleifen",
        nameFR       = "Joaillerie",
        nameES       = "Joyería",
        icon         = "INV_Misc_Gem_01",
        maxSkill     = 375,
        trainerSpell = 25229,
        category     = "primary",
    },
    [165] = {
        skillLineID  = 165,
        name         = "Leatherworking",
        nameDE       = "Lederverarbeitung",
        nameFR       = "Travail du cuir",
        nameES       = "Peletería",
        icon         = "Trade_LeatherWorking",
        maxSkill     = 375,
        trainerSpell = 2108,
        category     = "primary",
    },
    [197] = {
        skillLineID  = 197,
        name         = "Tailoring",
        nameDE       = "Schneiderei",
        nameFR       = "Couture",
        nameES       = "Sastrería",
        icon         = "Trade_Tailoring",
        maxSkill     = 375,
        trainerSpell = 3908,
        category     = "primary",
    },
    -- --------------------------------------------------------
    -- Secondary Crafting Professions
    -- --------------------------------------------------------
    [185] = {
        skillLineID  = 185,
        name         = "Cooking",
        nameDE       = "Kochen",
        nameFR       = "Cuisine",
        nameES       = "Cocina",
        icon         = "INV_Misc_Food_15",
        maxSkill     = 375,
        trainerSpell = 818,
        category     = "secondary",
    },
    [129] = {
        skillLineID  = 129,
        name         = "First Aid",
        nameDE       = "Erste Hilfe",
        nameFR       = "Premiers secours",
        nameES       = "Primeros auxilios",
        icon         = "Spell_Holy_SealOfSacrifice",
        maxSkill     = 375,
        trainerSpell = 3273,
        category     = "secondary",
    },
}

-- Lookup by localized profession name (as returned by GetSkillLineInfo / GetTradeSkillLine).
-- Supports enUS, deDE, frFR, esES out of the box.
-- The case-insensitive fallback in Database.lua:RefreshProfessions() handles any
-- remaining capitalisation variants automatically.
CCO.ProfessionsByName = {}
for id, prof in pairs(CCO.Professions) do
    CCO.ProfessionsByName[prof.name]   = id
    if prof.nameDE then CCO.ProfessionsByName[prof.nameDE] = id end
    if prof.nameFR then CCO.ProfessionsByName[prof.nameFR] = id end
    if prof.nameES then CCO.ProfessionsByName[prof.nameES] = id end
end

-- Quick access: set of all crafting skillLine IDs for O(1) lookup
CCO.CraftingSkillLineIDs = {}
for id in pairs(CCO.Professions) do
    CCO.CraftingSkillLineIDs[id] = true
end

--- Returns the profession definition for a given skill line name.
-- Tries exact match first, then case-insensitive fallback.
-- @param name  string  Profession name as returned by GetSkillLineInfo()
-- @return      table|nil  CCO.Professions entry, or nil
function CCO:GetProfessionByName(name)
    if not name then return nil end
    -- Exact match (fastest path)
    local id = CCO.ProfessionsByName[name]
    if id then return CCO.Professions[id] end
    -- Case-insensitive fallback
    local nameLower = name:lower()
    for pName, pID in pairs(CCO.ProfessionsByName) do
        if pName:lower() == nameLower then
            return CCO.Professions[pID]
        end
    end
    return nil
end
