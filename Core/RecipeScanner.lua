-- ============================================================
-- ClassicCraftingOrders - Recipe Scanner
--
-- Whenever the player opens a tradeskill window the scanner
-- reads the full recipe list directly from Blizzard's API
-- (GetTradeSkillInfo / GetTradeSkillItemLink / etc.) and
-- merges the result into CCO.RecipeDB, filling in any SpellIDs
-- and ItemIDs that the static data didn't have.
--
-- This is the LIVE data layer: it produces the same canonical
-- recipe information that databases like WoWhead publish.
-- ============================================================
local ADDON_NAME, CCO = ...

CCO.RecipeScanner = {}
local RS = CCO.RecipeScanner

-- ============================================================
-- State
-- ============================================================
RS.scannedProfessions = {}  -- set of skillLineID already scanned this session

-- ============================================================
-- Initialise: register tradeskill events
-- ============================================================
function RS:Initialize()
    local f = CreateFrame("Frame")
    f:RegisterEvent("TRADE_SKILL_SHOW")
    f:RegisterEvent("TRADE_SKILL_UPDATE")

    f:SetScript("OnEvent", function(_, event)
        if event == "TRADE_SKILL_SHOW" or event == "TRADE_SKILL_UPDATE" then
            RS:ScanCurrentTradeskill()
        end
    end)
end

-- ============================================================
-- Main scan routine
-- ============================================================
function RS:ScanCurrentTradeskill()
    -- GetTradeSkillLine() returns the name of the currently open tradeskill
    local profName, _, rank, maxRank = GetTradeSkillLine()
    if not profName or profName == "UNKNOWN" then return end

    -- Resolve to a skillLine ID using our profession name table
    local skillLineID = CCO.ProfessionsByName[profName]
    if not skillLineID then
        -- Unknown / gathering profession – skip
        return
    end

    -- Make sure we have a table in the DB for this profession
    if not CCO.RecipeDB[skillLineID] then
        CCO.RecipeDB[skillLineID] = {}
    end

    local numSkills = GetNumTradeSkills()
    if not numSkills or numSkills == 0 then return end

    -- Build a lookup of existing static recipes by name for quick merge
    local existingByName = {}
    for _, recipe in ipairs(CCO.RecipeDB[skillLineID]) do
        existingByName[recipe.name] = recipe
    end

    local scannedCount = 0

    for i = 1, numSkills do
        local skillName, skillType, numAvailable, isExpanded = GetTradeSkillInfo(i)
        if skillName and skillType ~= "header" then
            -- Build the recipe entry
            local recipe = RS:ReadRecipeAtIndex(i, skillName, skillType)
            if recipe then
                scannedCount = scannedCount + 1
                local existing = existingByName[skillName]
                if existing then
                    -- Patch missing fields into the static record
                    if not existing.spellID  and recipe.spellID  then existing.spellID  = recipe.spellID  end
                    if existing.itemID == nil and recipe.itemID  ~= nil then existing.itemID = recipe.itemID end
                    if not existing.minSkill and recipe.minSkill then existing.minSkill = recipe.minSkill end
                    if not existing.reagents or #existing.reagents == 0 then
                        existing.reagents = recipe.reagents
                    end
                    existing._scanned = true
                else
                    -- Add new recipe discovered at runtime
                    recipe._scanned = true
                    table.insert(CCO.RecipeDB[skillLineID], recipe)
                    existingByName[skillName] = recipe
                end
            end
        end
    end

    RS.scannedProfessions[skillLineID] = true

    -- Notify the UI so it can refresh
    if CCO.UI and CCO.UI.RecipeBrowser then
        CCO.UI.RecipeBrowser:OnDatabaseUpdated(skillLineID)
    end

    CCO:Print(string.format("[Scanner] %s: %d recipes indexed.", profName, scannedCount))
end

-- ============================================================
-- Read a single tradeskill entry at position `index`
-- ============================================================
function RS:ReadRecipeAtIndex(index, skillName, skillType)
    local recipe = {
        name     = skillName,
        minSkill = nil,
        spellID  = nil,
        itemID   = nil,
        reagents = {},
        source   = "unknown",
        _index   = index,
    }

    -- --- Created Item ---
    -- GetTradeSkillItemLink returns e.g. |cff...|Hitem:12345:...|h[Name]|h|r
    -- For enchants it returns a spell link.
    local itemLink = GetTradeSkillItemLink(index)
    if itemLink then
        -- Try item link first
        local itemID = itemLink:match("|Hitem:(%d+):")
        if itemID then
            recipe.itemID = tonumber(itemID)
        else
            -- Enchant / non-item result
            local enchantID = itemLink:match("|Henchant:(%d+)")
            if enchantID then
                recipe.spellID = tonumber(enchantID)
                recipe.itemID  = 0   -- explicit: no item produced
            end
        end
    end

    -- --- Recipe Spell Link ---
    -- GetTradeSkillRecipeLink returns the recipe's own spell link
    local recipeLink = GetTradeSkillRecipeLink(index)
    if recipeLink then
        local spellID = recipeLink:match("|Hspell:(%d+)")
        if spellID then
            recipe.spellID = tonumber(spellID)
        end
    end

    -- --- Min Skill Level ---
    -- We derive this from the difficulty colour:
    -- GetTradeSkillInfo skillType: "optimal"|"medium"|"easy"|"trivial"|"nodifficulty"
    -- To get the actual level threshold, we look at the tool-tip or use heuristic:
    -- Actually GetTradeSkillInfo(i) returns numAvailable and (in some builds) the
    -- required skill in the spell tooltip – simplest is to look at colour mapping.
    -- We'll store skillType and set minSkill from SavedVariables if previously seen.
    recipe.skillType = skillType

    -- --- Reagents ---
    local numReagents = GetTradeSkillNumReagents(index)
    if numReagents and numReagents > 0 then
        for r = 1, numReagents do
            local rName, rTexture, rCount, rPlayerCount = GetTradeSkillReagentInfo(index, r)
            if rName then
                local rItemLink = GetTradeSkillReagentItemLink(index, r)
                local rItemID
                if rItemLink then
                    rItemID = tonumber(rItemLink:match("|Hitem:(%d+):"))
                end
                -- Fallback: try name→ID resolution
                if not rItemID then
                    rItemID = select(1, GetItemInfoInstant(rName)) or 0
                end
                if rItemID and rItemID > 0 then
                    table.insert(recipe.reagents, { rItemID, rCount or 1, name = rName })
                end
            end
        end
    end

    return recipe
end

-- ============================================================
-- Utility: check if a given profession has been scanned
-- ============================================================
function RS:IsProfessionScanned(skillLineID)
    return RS.scannedProfessions[skillLineID] == true
end

-- ============================================================
-- Utility: Get combined (static + scanned) recipes for a
-- given profession, sorted by minSkill then name.
-- ============================================================
function RS:GetSortedRecipes(skillLineID)
    local recipes = CCO.RecipeDB[skillLineID] or {}
    local sorted  = {}
    for _, r in ipairs(recipes) do
        table.insert(sorted, r)
    end
    table.sort(sorted, function(a, b)
        local sa = a.minSkill or 0
        local sb = b.minSkill or 0
        if sa ~= sb then return sa < sb end
        return (a.name or "") < (b.name or "")
    end)
    return sorted
end

-- ============================================================
-- Utility: Check if the current player can craft a recipe
-- Compares the player's known skill vs the recipe's minSkill.
-- ============================================================
function RS:PlayerCanCraft(skillLineID, recipe)
    local profDB = CCO.db and CCO.db.char.professions
    if not profDB then return false end
    local prof = profDB[skillLineID]
    if not prof then return false end
    local minSkill = recipe.minSkill or 0
    return prof.rank >= minSkill
end
