-- ============================================================
-- ClassicCraftingOrders - Recipe Browser UI  (rewritten v2)
--
-- Data flow:
--   1. CCO.RecipeDB[skillLineID]  ← static recipes from Data/RecipeDB.lua
--   2. CCO.RecipeScanner          ← patches / extends DB when tradeskill
--                                    window is opened by the player
--   3. Only professions from CCO.CraftingSkillLineIDs are shown
--      (no combat skills, weapons, languages, gathering profs)
-- ============================================================
local ADDON_NAME, CCO = ...

CCO.UI = CCO.UI or {}
CCO.UI.RecipeBrowser = {}
local RB = CCO.UI.RecipeBrowser

-- ============================================================
-- State
-- ============================================================
RB.frame             = nil
RB.selectedProfID    = nil   -- currently displayed profession skillLineID
RB.selectedRecipe    = nil   -- currently highlighted recipe table
RB.filteredRecipes   = {}    -- after search/filter applied
RB.professionRows    = {}    -- profession tab buttons

-- ============================================================
-- Initialise
-- ============================================================
function RB:Initialize()
    RB:CreateFrame()
end

-- Called by RecipeScanner when new recipes were indexed
function RB:OnDatabaseUpdated(skillLineID)
    if RB.frame and RB.frame:IsShown() and RB.selectedProfID == skillLineID then
        RB:PopulateRecipeList()
    end
end

-- ============================================================
-- Frame construction
-- ============================================================
function RB:CreateFrame()
    local f = CreateFrame("Frame", "CCO_RecipeBrowser", UIParent)
    f:SetSize(560, 540)
    f:SetPoint("CENTER")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:SetClampedToScreen(true)
    f:SetFrameStrata("HIGH")
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop",  f.StopMovingOrSizing)
    f:SetBackdrop({
        bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile     = true, tileSize = 32, edgeSize = 32,
        insets   = { left=11, right=12, top=12, bottom=11 },
    })
    f:SetBackdropColor(0, 0, 0, 0.92)
    f:Hide()
    RB.frame = f

    -- Title
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", f, "TOP", 0, -10)
    title:SetText(CCO.L["RECIPE_BROWSER_TITLE"])

    -- Close
    local closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
    closeBtn:SetScript("OnClick", function() f:Hide() end)

    -- ---- Profession tabs (left sidebar) ----
    RB:BuildProfessionTabs(f)

    -- ---- Search bar ----
    local searchBox = CreateFrame("EditBox", "CCO_RecipeSearch", f, "SearchBoxTemplate")
    searchBox:SetSize(220, 20)
    searchBox:SetPoint("TOPLEFT", f, "TOPLEFT", 140, -36)
    searchBox:SetScript("OnTextChanged", function(self)
        RB:ApplySearchFilter(self:GetText())
    end)
    RB.searchBox = searchBox

    -- ---- Recipe list (middle pane) ----
    RB:BuildRecipeList(f)

    -- ---- Detail / reagent pane (right side) ----
    RB:BuildDetailPane(f)

    -- ---- Order form (bottom strip) ----
    RB:BuildOrderForm(f)

    -- ---- Hint: "Open tradeskill window to scan" ----
    local scanHint = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    scanHint:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 16, 46)
    scanHint:SetWidth(300)
    scanHint:SetJustifyH("LEFT")
    scanHint:SetTextColor(0.6, 0.6, 0.6)
    scanHint:SetText("Tip: Open your tradeskill window to scan all recipes.")
    RB.scanHint = scanHint
end

-- ============================================================
-- Profession Tabs (left sidebar)
-- ============================================================
function RB:BuildProfessionTabs(parent)
    local sidebar = CreateFrame("Frame", nil, parent)
    sidebar:SetPoint("TOPLEFT", parent, "TOPLEFT", 12, -32)
    sidebar:SetSize(120, 470)
    sidebar:SetBackdrop({
        bgFile  = "Interface\\Buttons\\WHITE8X8",
        tile    = true, tileSize = 8,
    })
    sidebar:SetBackdropColor(0.05, 0.05, 0.1, 0.6)
    RB.sidebar = sidebar

    -- "Profession" label
    local lbl = sidebar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lbl:SetPoint("TOP", sidebar, "TOP", 0, -6)
    lbl:SetText(CCO.L["LABEL_PROFESSION"])
    lbl:SetTextColor(0.8, 0.8, 0.2)
end

--- Rebuild profession tabs based on the player's crafting professions.
--- Called from Toggle() and OnDatabaseUpdated().
function RB:RebuildProfessionTabs()
    -- Clear old buttons
    for _, btn in ipairs(RB.professionRows) do
        btn:Hide()
        btn:SetParent(nil)
    end
    RB.professionRows = {}

    local profs = CCO.Database:GetProfessions()
    local yOff  = -26
    local sorted = {}
    for id, data in pairs(profs) do
        table.insert(sorted, { id = id, data = data })
    end
    table.sort(sorted, function(a, b)
        return (a.data.name or "") < (b.data.name or "")
    end)

    for _, entry in ipairs(sorted) do
        local profID = entry.id
        local data   = entry.data
        local profDef= CCO.Professions[profID]

        local btn = CreateFrame("Button", nil, RB.sidebar)
        btn:SetSize(116, 30)
        btn:SetPoint("TOPLEFT", RB.sidebar, "TOPLEFT", 2, yOff)

        -- Icon
        local iconTex = btn:CreateTexture(nil, "ARTWORK")
        iconTex:SetSize(22, 22)
        iconTex:SetPoint("LEFT", btn, "LEFT", 4, 0)
        if profDef and profDef.icon then
            iconTex:SetTexture("Interface\\Icons\\" .. profDef.icon)
        end

        -- Name + rank
        local nameText = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        nameText:SetPoint("LEFT", btn, "LEFT", 30, 2)
        nameText:SetWidth(82)
        nameText:SetJustifyH("LEFT")
        nameText:SetText(data.name)

        local rankText = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        rankText:SetPoint("LEFT", btn, "LEFT", 30, -9)
        rankText:SetTextColor(0.7, 0.7, 0.7)
        rankText:SetText(data.rank .. "/" .. (data.maxRank or 375))

        -- Scanner indicator (green dot if scanned this session)
        local dot = btn:CreateTexture(nil, "OVERLAY")
        dot:SetSize(8, 8)
        dot:SetPoint("TOPRIGHT", btn, "TOPRIGHT", -2, -2)
        dot:SetTexture("Interface\\Buttons\\WHITE8X8")
        dot:SetVertexColor(
            CCO.RecipeScanner:IsProfessionScanned(profID) and 0 or 0.8,
            CCO.RecipeScanner:IsProfessionScanned(profID) and 1 or 0.8,
            CCO.RecipeScanner:IsProfessionScanned(profID) and 0 or 0.8,
            0.8)
        btn._dot = dot

        btn:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")

        -- Selected state
        btn._bg = btn:CreateTexture(nil, "BACKGROUND")
        btn._bg:SetAllPoints(btn)
        btn._bg:SetTexture("Interface\\Buttons\\WHITE8X8")
        btn._bg:SetVertexColor(0.2, 0.4, 0.8, 0)

        local capturedID = profID
        btn:SetScript("OnClick", function()
            RB:SelectProfession(capturedID)
        end)

        btn:SetScript("OnEnter", function()
            GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
            local scanInfo = CCO.RecipeScanner:IsProfessionScanned(capturedID)
                and "Scanned ✓"
                or "Open tradeskill window to scan"
            GameTooltip:SetText(data.name .. " (" .. data.rank .. "/" .. (data.maxRank or 375) .. ")")
            GameTooltip:AddLine(scanInfo, 0.6, 0.6, 0.6)
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

        table.insert(RB.professionRows, btn)
        yOff = yOff - 34
    end

    -- If no professions found, show a message
    if #sorted == 0 then
        local noProf = RB.sidebar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        noProf:SetPoint("CENTER", RB.sidebar, "CENTER")
        noProf:SetWidth(110)
        noProf:SetJustifyH("CENTER")
        noProf:SetText(CCO.L["ERR_NO_PROFESSION"])
        noProf:SetTextColor(1, 0.4, 0.4)
        table.insert(RB.professionRows, noProf)
    end
end

-- ============================================================
-- Recipe List (scrollable middle pane)
-- ============================================================
function RB:BuildRecipeList(parent)
    local bg = CreateFrame("Frame", nil, parent)
    bg:SetPoint("TOPLEFT",  parent, "TOPLEFT",  140, -62)
    bg:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -12, -62)
    bg:SetHeight(290)
    bg:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 8, edgeSize = 12,
        insets = { left=2, right=2, top=2, bottom=2 }
    })
    bg:SetBackdropColor(0.04, 0.04, 0.06, 0.9)
    RB.recipeListBg = bg

    local sf = CreateFrame("ScrollFrame", "CCO_RBScroll", bg, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", bg, "TOPLEFT", 4, -4)
    sf:SetPoint("BOTTOMRIGHT", bg, "BOTTOMRIGHT", -22, 4)
    RB.scrollFrame = sf

    local content = CreateFrame("Frame", nil, sf)
    content:SetSize(sf:GetWidth() or 380, 1)
    sf:SetScrollChild(content)
    RB.recipeListContent = content

    -- Empty-state label
    local emptyLbl = content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    emptyLbl:SetPoint("TOP", content, "TOP", 0, -20)
    emptyLbl:SetText("Select a profession to view recipes.")
    emptyLbl:SetTextColor(0.6, 0.6, 0.6)
    RB.emptyLabel = emptyLbl
end

-- ============================================================
-- Detail / Reagent Pane
-- ============================================================
function RB:BuildDetailPane(parent)
    local pane = CreateFrame("Frame", nil, parent)
    pane:SetPoint("TOPLEFT",  parent, "TOPLEFT",  140, -360)
    pane:SetPoint("TOPRIGHT", parent, "TOPRIGHT",  -12, -360)
    pane:SetHeight(130)
    pane:SetBackdrop({
        bgFile  = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 8, edgeSize = 12,
        insets = { left=2, right=2, top=2, bottom=2 }
    })
    pane:SetBackdropColor(0.04, 0.04, 0.08, 0.9)
    RB.detailPane = pane

    local icon = pane:CreateTexture(nil, "ARTWORK")
    icon:SetSize(40, 40)
    icon:SetPoint("TOPLEFT", pane, "TOPLEFT", 6, -6)
    RB.detailIcon = icon

    local itemName = pane:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    itemName:SetPoint("TOPLEFT", pane, "TOPLEFT", 52, -8)
    itemName:SetWidth(300)
    itemName:SetJustifyH("LEFT")
    RB.detailItemName = itemName

    local skillReq = pane:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    skillReq:SetPoint("TOPLEFT", pane, "TOPLEFT", 52, -24)
    skillReq:SetTextColor(0.7, 0.7, 0.7)
    RB.detailSkillReq = skillReq

    local reagLbl = pane:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    reagLbl:SetPoint("TOPLEFT", pane, "TOPLEFT", 6, -52)
    reagLbl:SetText(CCO.L["LABEL_REAGENTS"])
    reagLbl:SetTextColor(0.8, 0.8, 0.2)

    -- Up to 8 reagent icons + text rows
    RB.reagentIcons = {}
    RB.reagentTexts = {}
    for r = 1, 8 do
        local col   = (r - 1) % 4
        local row   = math.floor((r - 1) / 4)
        local xBase = 6 + col * 90
        local yBase = -66 - row * 28

        local ico = pane:CreateTexture(nil, "ARTWORK")
        ico:SetSize(20, 20)
        ico:SetPoint("TOPLEFT", pane, "TOPLEFT", xBase, yBase)
        ico:Hide()
        RB.reagentIcons[r] = ico

        local txt = pane:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        txt:SetPoint("LEFT", ico, "RIGHT", 2, 0)
        txt:SetWidth(66)
        txt:SetJustifyH("LEFT")
        txt:Hide()
        RB.reagentTexts[r] = txt
    end
end

-- ============================================================
-- Order Form (bottom strip)
-- ============================================================
function RB:BuildOrderForm(parent)
    local strip = CreateFrame("Frame", nil, parent)
    strip:SetPoint("BOTTOMLEFT",  parent, "BOTTOMLEFT",  140, 10)
    strip:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -12, 10)
    strip:SetHeight(38)

    -- Commission label
    local commLbl = strip:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    commLbl:SetPoint("LEFT", strip, "LEFT", 0, 8)
    commLbl:SetText(CCO.L["LABEL_COMMISSION"])

    -- Gold input
    RB.inputGold   = RB:MakeCoinBox(strip, 100, 10, "g")
    RB.inputSilver = RB:MakeCoinBox(strip, 150, 10, "s")
    RB.inputCopper = RB:MakeCoinBox(strip, 200, 10, "c")

    -- Materials checkbox
    local matsCheck = CreateFrame("CheckButton", nil, strip, "UICheckButtonTemplate")
    matsCheck:SetPoint("LEFT", strip, "LEFT", 240, 4)
    matsCheck:SetChecked(true)
    RB.matsCheck = matsCheck
    local matsLbl = strip:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    matsLbl:SetPoint("LEFT", matsCheck, "RIGHT", 2, 0)
    matsLbl:SetText(CCO.L["LABEL_MATS_PROVIDED"])

    -- Favourite button
    local favBtn = CreateFrame("Button", nil, strip)
    favBtn:SetSize(20, 20)
    favBtn:SetPoint("RIGHT", strip, "RIGHT", -90, 4)
    local favTex = favBtn:CreateTexture(nil, "ARTWORK")
    favTex:SetAllPoints(favBtn)
    favTex:SetTexture("Interface\\Buttons\\UI-EmptySlot-Disabled")
    favBtn:SetScript("OnClick", function()
        if RB.selectedRecipe and RB.selectedRecipe.itemID and RB.selectedRecipe.itemID > 0 then
            local isFav = CCO.Database:ToggleFavourite(RB.selectedRecipe.itemID)
            favTex:SetTexture(isFav and "Interface\\RAIDFRAME\\UI-RaidFrame-Threat"
                                    or "Interface\\Buttons\\UI-EmptySlot-Disabled")
        end
    end)
    RB.favBtn = favBtn
    RB.favTex = favTex

    -- Post button
    local postBtn = CreateFrame("Button", nil, strip, "UIPanelButtonTemplate")
    postBtn:SetSize(80, 24)
    postBtn:SetPoint("RIGHT", strip, "RIGHT", 0, 4)
    postBtn:SetText(CCO.L["BTN_POST_ORDER"])
    postBtn:SetScript("OnClick", function() RB:PostOrder() end)
    RB.postBtn = postBtn
end

function RB:MakeCoinBox(parent, xOff, yOff, suffix)
    local eb = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    eb:SetSize(34, 18)
    eb:SetPoint("LEFT", parent, "LEFT", xOff, yOff)
    eb:SetNumeric(true)
    eb:SetMaxLetters(5)
    eb:SetNumber(0)
    local lbl = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    lbl:SetPoint("LEFT", eb, "RIGHT", 2, 0)
    lbl:SetText(suffix)
    return eb
end

-- ============================================================
-- Select a profession and load its recipe list
-- ============================================================
function RB:SelectProfession(skillLineID)
    RB.selectedProfID = skillLineID
    RB.selectedRecipe = nil

    -- Highlight selected tab
    for _, btn in ipairs(RB.professionRows) do
        if btn._bg then
            btn._bg:SetVertexColor(0.2, 0.4, 0.8, 0)
        end
    end
    -- Find the matching button and highlight it
    for _, btn in ipairs(RB.professionRows) do
        -- Buttons store capturedID via closure; find via position heuristic
        -- Instead we use the DB entry
    end

    -- Clear search
    if RB.searchBox then
        RB.searchBox:SetText("")
    end

    -- Populate list
    RB:PopulateRecipeList()

    -- Show scan hint if not yet scanned
    if RB.scanHint then
        RB.scanHint:SetShown(not CCO.RecipeScanner:IsProfessionScanned(skillLineID))
    end
end

-- ============================================================
-- Build recipe rows
-- ============================================================
function RB:PopulateRecipeList(filterText)
    filterText = filterText or (RB.searchBox and RB.searchBox:GetText()) or ""
    filterText = filterText:lower()

    -- Clear old rows
    for _, child in ipairs({ RB.recipeListContent:GetChildren() }) do
        child:Hide()
        child:SetParent(nil)
    end
    RB.emptyLabel:SetShown(not RB.selectedProfID)

    if not RB.selectedProfID then return end

    local recipes = CCO.RecipeScanner:GetSortedRecipes(RB.selectedProfID)

    -- Filter
    local visible = {}
    local playerProf = CCO.db.char.professions[RB.selectedProfID]
    local playerRank = playerProf and playerProf.rank or 0

    for _, recipe in ipairs(recipes) do
        local nameMatch = filterText == "" or recipe.name:lower():find(filterText, 1, true)
        if nameMatch then
            table.insert(visible, recipe)
        end
    end

    RB.filteredRecipes = visible

    if #visible == 0 then
        RB.emptyLabel:SetText("No recipes found.")
        RB.emptyLabel:Show()
        RB.recipeListContent:SetHeight(1)
        return
    end
    RB.emptyLabel:Hide()

    local ROW_H = 24
    local contentW = RB.recipeListContent:GetWidth() or 380

    for i, recipe in ipairs(visible) do
        local row = CreateFrame("Button", nil, RB.recipeListContent)
        row:SetSize(contentW, ROW_H)
        row:SetPoint("TOPLEFT", RB.recipeListContent, "TOPLEFT", 0, -(i-1)*ROW_H)
        row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")

        -- Difficulty colour
        local r, g, b = RB:GetDifficultyColor(recipe.minSkill, playerRank)

        -- Item icon
        local ico = row:CreateTexture(nil, "ARTWORK")
        ico:SetSize(18, 18)
        ico:SetPoint("LEFT", row, "LEFT", 2, 0)
        local _, _, _, _, _, _, _, _, _, iconPath = GetItemInfo(recipe.itemID or 0)
        if iconPath then
            ico:SetTexture(iconPath)
        else
            ico:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
        end

        -- Name
        local nameLbl = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        nameLbl:SetPoint("LEFT", row, "LEFT", 24, 0)
        nameLbl:SetWidth(contentW - 100)
        nameLbl:SetJustifyH("LEFT")
        nameLbl:SetText(recipe.name)
        nameLbl:SetTextColor(r, g, b)

        -- Skill required badge
        if recipe.minSkill and recipe.minSkill > 0 then
            local skillLbl = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            skillLbl:SetPoint("RIGHT", row, "RIGHT", -2, 0)
            skillLbl:SetText(tostring(recipe.minSkill))
            skillLbl:SetTextColor(0.6, 0.6, 0.6)
        end

        -- Favourite star
        if recipe.itemID and CCO.Database:IsFavourite(recipe.itemID) then
            local star = row:CreateTexture(nil, "OVERLAY")
            star:SetSize(10, 10)
            star:SetPoint("RIGHT", row, "RIGHT", -20, 0)
            star:SetTexture("Interface\\RAIDFRAME\\UI-RaidFrame-Threat")
        end

        -- Scanner badge (indicates live data)
        if recipe._scanned then
            local badge = row:CreateTexture(nil, "OVERLAY")
            badge:SetSize(8, 8)
            badge:SetPoint("TOPRIGHT", row, "TOPRIGHT", -2, -2)
            badge:SetTexture("Interface\\Buttons\\WHITE8X8")
            badge:SetVertexColor(0, 0.8, 0.2, 0.7)
        end

        local capturedRecipe = recipe
        row:SetScript("OnClick", function() RB:ShowRecipeDetail(capturedRecipe) end)
        row:SetScript("OnEnter", function()
            GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
            if capturedRecipe.itemID and capturedRecipe.itemID > 0 then
                GameTooltip:SetItemByID(capturedRecipe.itemID)
            else
                GameTooltip:SetText(capturedRecipe.name)
            end
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end

    RB.recipeListContent:SetHeight(math.max(1, #visible * ROW_H))
end

-- ============================================================
-- Difficulty color  (Classic traffic-light: orange→yellow→green→grey)
-- ============================================================
function RB:GetDifficultyColor(minSkill, playerRank)
    minSkill   = minSkill   or 0
    playerRank = playerRank or 0
    local diff = playerRank - minSkill
    if diff < 0  then return 0.6, 0.6, 0.6 end  -- grey (can't learn yet)
    if diff < 10 then return 1.0, 0.5, 0.0 end  -- orange (skill up likely)
    if diff < 25 then return 1.0, 1.0, 0.0 end  -- yellow
    if diff < 50 then return 0.2, 0.9, 0.2 end  -- green
    return 0.5, 0.5, 0.5                         -- grey (trivial)
end

-- ============================================================
-- Show detail for a selected recipe
-- ============================================================
function RB:ShowRecipeDetail(recipe)
    RB.selectedRecipe = recipe

    -- Item info
    local itemName, _, _, _, _, _, _, _, _, iconPath = GetItemInfo(recipe.itemID or 0)
    RB.detailItemName:SetText(itemName or recipe.name)
    if iconPath then
        RB.detailIcon:SetTexture(iconPath)
        RB.detailIcon:Show()
    else
        RB.detailIcon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
        RB.detailIcon:Show()
    end

    local source = recipe.source or "unknown"
    RB.detailSkillReq:SetText(
        string.format("Skill: %d  |  Source: %s  |  %s",
            recipe.minSkill or 0,
            source,
            recipe._scanned and "|cff00cc00Live|r" or "|cffffcc00Static|r"
        )
    )

    -- Reagents
    for r = 1, 8 do
        RB.reagentIcons[r]:Hide()
        RB.reagentTexts[r]:Hide()
    end

    if recipe.reagents then
        for r, reagent in ipairs(recipe.reagents) do
            if r > 8 then break end
            local iID  = reagent[1] or reagent.itemID
            local cnt  = reagent[2] or reagent.count or 1
            local rName = reagent.name

            if iID and iID > 0 then
                local rItemName, _, _, _, _, _, _, _, _, rIcon = GetItemInfo(iID)
                if rIcon then
                    RB.reagentIcons[r]:SetTexture(rIcon)
                else
                    RB.reagentIcons[r]:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
                end
                RB.reagentIcons[r]:Show()
                RB.reagentTexts[r]:SetText((rItemName or rName or "Item " .. iID) .. " x" .. cnt)
                RB.reagentTexts[r]:Show()
            end
        end
    end

    -- Update favourite star
    local isFav = recipe.itemID and recipe.itemID > 0
                  and CCO.Database:IsFavourite(recipe.itemID) or false
    RB.favTex:SetTexture(isFav and "Interface\\RAIDFRAME\\UI-RaidFrame-Threat"
                                or "Interface\\Buttons\\UI-EmptySlot-Disabled")
end

-- ============================================================
-- Search filter
-- ============================================================
function RB:ApplySearchFilter(text)
    if RB.selectedProfID then
        RB:PopulateRecipeList(text)
    end
end

-- ============================================================
-- Post Order
-- ============================================================
function RB:PostOrder()
    local recipe = RB.selectedRecipe
    if not recipe then
        CCO:PrintError(CCO.L["ORDER_MISSING_FIELDS"])
        return
    end
    if not recipe.spellID then
        CCO:PrintError("SpellID unknown – open tradeskill window first to scan this recipe.")
        return
    end

    local g = RB.inputGold:GetNumber()   or 0
    local s = RB.inputSilver:GetNumber() or 0
    local c = RB.inputCopper:GetNumber() or 0
    local totalCopper = (g * 10000) + (s * 100) + c

    local matsProvided = RB.matsCheck:GetChecked()

    local order = CCO.OrderManager:PostOrder(
        recipe.itemID,
        recipe.spellID,
        totalCopper,
        matsProvided
    )

    if order then
        local displayName = recipe.name
        if recipe.itemID and recipe.itemID > 0 then
            displayName = GetItemInfo(recipe.itemID) or recipe.name
        end
        CCO:Print(CCO.L["ORDER_POSTED"]:format(displayName))
        RB.frame:Hide()
    end
end

-- ============================================================
-- Visibility
-- ============================================================
function RB:Toggle()
    if not RB.frame:IsShown() then
        -- Rebuild profession tabs (detect current professions)
        RB:RebuildProfessionTabs()
        -- Auto-select the first profession if none selected
        if not RB.selectedProfID then
            local profs = CCO.Database:GetProfessions()
            for id in pairs(profs) do
                RB:SelectProfession(id)
                break
            end
        end
    end
    RB.frame:SetShown(not RB.frame:IsShown())
end
