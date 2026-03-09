-- ============================================================
-- ClassicCraftingOrders - Recipe Browser UI  (rewritten v3)
--
-- Layout (top to bottom):
--   1. Title bar + close button
--   2. Toolbar: [Profession dropdown] [Search box] [Clear btn]
--   3. Recipe list (scrollable, full width)
--   4. Detail / reagent pane
--   5. Order form strip (commission + post button)
--
-- API notes for TBC Classic Anniversary (Shadowlands-era client):
--   • UIDropDownMenu* functions  – available in all WoW versions
--   • SearchBoxTemplate          – NOT in TBC (Cataclysm+); use InputBoxTemplate
--   • GameTooltip:SetItemByID    – NOT in TBC (Legion+); use SetHyperlink
--   • C_Timer.NewTimer           – NOT in TBC (WoD+)
--   • SetBackdrop requires BackdropTemplate on frame
-- ============================================================
local ADDON_NAME, CCO = ...

CCO.UI = CCO.UI or {}
CCO.UI.RecipeBrowser = {}
local RB = CCO.UI.RecipeBrowser

-- ============================================================
-- Static profession list (shown in dropdown; data from RecipeDB)
-- ============================================================
local PROF_LIST = {
    { id = 171, name = "Alchemy",        icon = "Trade_Alchemy"               },
    { id = 164, name = "Blacksmithing",  icon = "Trade_BlackSmithing"         },
    { id = 333, name = "Enchanting",     icon = "Trade_Engraving"             },
    { id = 202, name = "Engineering",    icon = "Trade_Engineering"           },
    { id = 755, name = "Jewelcrafting",  icon = "INV_Misc_Gem_01"             },
    { id = 165, name = "Leatherworking", icon = "Trade_LeatherWorking"        },
    { id = 197, name = "Tailoring",      icon = "Trade_Tailoring"             },
    { id = 185, name = "Cooking",        icon = "INV_Misc_Food_15"            },
    { id = 129, name = "First Aid",      icon = "Spell_Holy_SealOfSacrifice"  },
}

-- Quick lookup by id
local PROF_BY_ID = {}
for _, p in ipairs(PROF_LIST) do
    PROF_BY_ID[p.id] = p
end

-- ============================================================
-- State
-- ============================================================
RB.frame           = nil
RB.selectedProfID  = nil   -- currently displayed profession skillLineID
RB.selectedRecipe  = nil   -- currently highlighted recipe table
RB.filteredRecipes = {}    -- recipes after search/filter

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
    local f = CreateFrame("Frame", "CCO_RecipeBrowser", UIParent, "BackdropTemplate")
    f:SetSize(560, 560)
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

    -- ---- Title ----
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", f, "TOP", 0, -10)
    title:SetText(CCO.L["RECIPE_BROWSER_TITLE"] or "New Crafting Order")

    -- ---- Close button ----
    local closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
    closeBtn:SetScript("OnClick", function() f:Hide() end)

    -- ---- Toolbar row ----
    RB:BuildToolbar(f)

    -- ---- Separator line ----
    local sep = f:CreateTexture(nil, "ARTWORK")
    sep:SetHeight(1)
    sep:SetPoint("TOPLEFT",  f, "TOPLEFT",  14, -64)
    sep:SetPoint("TOPRIGHT", f, "TOPRIGHT", -14, -64)
    sep:SetTexture("Interface\\Buttons\\WHITE8X8")
    sep:SetVertexColor(0.35, 0.35, 0.35)

    -- ---- Recipe list (full width) ----
    RB:BuildRecipeList(f)

    -- ---- Detail / reagent pane ----
    RB:BuildDetailPane(f)

    -- ---- Order form (bottom strip) ----
    RB:BuildOrderForm(f)

    -- ---- Scan hint ----
    local scanHint = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    scanHint:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 16, 48)
    scanHint:SetWidth(280)
    scanHint:SetJustifyH("LEFT")
    scanHint:SetTextColor(0.6, 0.6, 0.6)
    scanHint:SetText("Tip: Open your tradeskill window to scan live recipes.")
    RB.scanHint = scanHint
end

-- ============================================================
-- Toolbar: profession dropdown + search box
-- ============================================================
function RB:BuildToolbar(parent)

    -- ---- Profession dropdown (UIDropDownMenu – available in all WoW versions) ----
    local dropdown = CreateFrame("Frame", "CCO_ProfessionDropdown", parent, "UIDropDownMenuTemplate")
    dropdown:SetPoint("TOPLEFT", parent, "TOPLEFT", 2, -30)
    UIDropDownMenu_SetWidth(dropdown, 160)
    UIDropDownMenu_SetText(dropdown, CCO.L["LABEL_PROFESSION"] or "Select Profession")
    RB.profDropdown = dropdown

    UIDropDownMenu_Initialize(dropdown, function(self, level)
        local info = UIDropDownMenu_CreateInfo()

        -- Show all professions that have data in the RecipeDB
        for _, prof in ipairs(PROF_LIST) do
            local recipesForProf = CCO.RecipeDB and CCO.RecipeDB[prof.id]
            local count = recipesForProf and #recipesForProf or 0

            -- Check if the player actually has this profession
            local playerHas = CCO.db.char.professions and CCO.db.char.professions[prof.id]

            info.text     = prof.name .. " |cff888888(" .. count .. ")|r"
                            .. (playerHas and " |cff00ff00✓|r" or "")
            info.value    = prof.id
            info.checked  = (RB.selectedProfID == prof.id)
            info.disabled = (count == 0)

            -- Closure to capture profID and profName
            local capturedID   = prof.id
            local capturedName = prof.name
            info.func = function(btn)
                UIDropDownMenu_SetText(dropdown, capturedName)
                RB:SelectProfession(capturedID)
                CloseDropDownMenus()
            end

            UIDropDownMenu_AddButton(info, level)
        end
    end)

    -- Dropdown label
    local ddLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    ddLabel:SetPoint("TOPLEFT", parent, "TOPLEFT", 20, -34)
    ddLabel:SetTextColor(0.8, 0.8, 0.2)
    -- The UIDropDownMenu frame already has its own label inside; skip extra label

    -- ---- Search box ----
    -- NOTE: SearchBoxTemplate does NOT exist in TBC Classic (added in Cataclysm).
    local searchBg = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    searchBg:SetSize(200, 24)
    searchBg:SetPoint("LEFT", dropdown, "RIGHT", 8, 0)
    searchBg:SetBackdrop({
        bgFile  = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 8, edgeSize = 8,
        insets = { left=2, right=2, top=2, bottom=2 }
    })
    searchBg:SetBackdropColor(0.05, 0.05, 0.08, 0.9)

    local searchBox = CreateFrame("EditBox", "CCO_RecipeSearch", searchBg, "InputBoxTemplate")
    searchBox:SetSize(186, 18)
    searchBox:SetPoint("CENTER", searchBg, "CENTER", -1, 0)
    searchBox:SetAutoFocus(false)
    searchBox:SetMaxLetters(50)
    -- Manual placeholder (SearchBoxTemplate not available in TBC)
    local PLACEHOLDER = CCO.L["SEARCH_PLACEHOLDER"] or "Search recipes..."
    searchBox:SetText(PLACEHOLDER)
    searchBox:SetTextColor(0.5, 0.5, 0.5)
    searchBox:SetScript("OnEditFocusGained", function(self)
        if self:GetText() == PLACEHOLDER then
            self:SetText("")
            self:SetTextColor(1, 1, 1)
        end
    end)
    searchBox:SetScript("OnEditFocusLost", function(self)
        if self:GetText() == "" then
            self:SetText(PLACEHOLDER)
            self:SetTextColor(0.5, 0.5, 0.5)
        end
    end)
    searchBox:SetScript("OnTextChanged", function(self)
        local txt = self:GetText()
        if txt == PLACEHOLDER then txt = "" end
        RB:ApplySearchFilter(txt)
    end)
    searchBox:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
        self:SetText(PLACEHOLDER)
        self:SetTextColor(0.5, 0.5, 0.5)
        RB:ApplySearchFilter("")
    end)
    searchBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    RB.searchBox = searchBox

    -- Search icon (magnifying glass texture)
    local searchIcon = searchBg:CreateTexture(nil, "OVERLAY")
    searchIcon:SetSize(14, 14)
    searchIcon:SetPoint("RIGHT", searchBg, "RIGHT", -4, 0)
    searchIcon:SetTexture("Interface\\Common\\UI-Searchbox-Icon")

    -- ---- Clear button ----
    local clearBtn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    clearBtn:SetSize(50, 22)
    clearBtn:SetPoint("LEFT", searchBg, "RIGHT", 6, 0)
    clearBtn:SetText("Clear")
    clearBtn:SetScript("OnClick", function()
        searchBox:SetText(PLACEHOLDER)
        searchBox:SetTextColor(0.5, 0.5, 0.5)
        searchBox:ClearFocus()
        RB:ApplySearchFilter("")
    end)
end

-- ============================================================
-- Recipe List (scrollable, full width)
-- ============================================================
function RB:BuildRecipeList(parent)
    local bg = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    bg:SetPoint("TOPLEFT",  parent, "TOPLEFT",  12,  -68)
    bg:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -12, -68)
    bg:SetHeight(270)
    bg:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile     = true, tileSize = 8, edgeSize = 12,
        insets   = { left=2, right=2, top=2, bottom=2 }
    })
    bg:SetBackdropColor(0.04, 0.04, 0.06, 0.9)
    RB.recipeListBg = bg

    -- Column header strip
    local hdrBg = bg:CreateTexture(nil, "BACKGROUND")
    hdrBg:SetHeight(20)
    hdrBg:SetPoint("TOPLEFT",  bg, "TOPLEFT",  2, -2)
    hdrBg:SetPoint("TOPRIGHT", bg, "TOPRIGHT", -2, -2)
    hdrBg:SetTexture("Interface\\Buttons\\WHITE8X8")
    hdrBg:SetVertexColor(0.10, 0.10, 0.18, 0.9)

    local hdrItem = bg:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hdrItem:SetPoint("TOPLEFT", bg, "TOPLEFT", 26, -4)
    hdrItem:SetText("Recipe")
    hdrItem:SetTextColor(0.9, 0.9, 0.4)

    local hdrSkill = bg:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hdrSkill:SetPoint("TOPRIGHT", bg, "TOPRIGHT", -22, -4)
    hdrSkill:SetJustifyH("RIGHT")
    hdrSkill:SetText("Skill")
    hdrSkill:SetTextColor(0.9, 0.9, 0.4)

    local hdrSrc = bg:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hdrSrc:SetPoint("TOPRIGHT", bg, "TOPRIGHT", -70, -4)
    hdrSrc:SetJustifyH("RIGHT")
    hdrSrc:SetText("Source")
    hdrSrc:SetTextColor(0.9, 0.9, 0.4)

    -- Scroll frame (below header strip)
    local sf = CreateFrame("ScrollFrame", "CCO_RBScroll", bg, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT",     bg, "TOPLEFT",   3, -22)
    sf:SetPoint("BOTTOMRIGHT", bg, "BOTTOMRIGHT", -22, 3)
    RB.scrollFrame = sf

    local content = CreateFrame("Frame", nil, sf)
    content:SetSize(sf:GetWidth() or 510, 1)
    sf:SetScrollChild(content)
    RB.recipeListContent = content

    -- Empty-state label
    local emptyLbl = content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    emptyLbl:SetPoint("TOP", content, "TOP", 0, -30)
    emptyLbl:SetText("Select a profession from the dropdown above.")
    emptyLbl:SetTextColor(0.6, 0.6, 0.6)
    RB.emptyLabel = emptyLbl
end

-- ============================================================
-- Detail / Reagent Pane
-- ============================================================
function RB:BuildDetailPane(parent)
    local pane = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    pane:SetPoint("TOPLEFT",  parent, "TOPLEFT",  12, -346)
    pane:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -12, -346)
    pane:SetHeight(142)
    pane:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile     = true, tileSize = 8, edgeSize = 12,
        insets   = { left=2, right=2, top=2, bottom=2 }
    })
    pane:SetBackdropColor(0.04, 0.04, 0.08, 0.9)
    RB.detailPane = pane

    -- Item icon
    local icon = pane:CreateTexture(nil, "ARTWORK")
    icon:SetSize(44, 44)
    icon:SetPoint("TOPLEFT", pane, "TOPLEFT", 8, -8)
    RB.detailIcon = icon

    -- Item name
    local itemName = pane:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    itemName:SetPoint("TOPLEFT", pane, "TOPLEFT", 58, -10)
    itemName:SetWidth(460)
    itemName:SetJustifyH("LEFT")
    itemName:SetText("|cff888888Select a recipe|r")
    RB.detailItemName = itemName

    -- Skill / source info
    local skillReq = pane:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    skillReq:SetPoint("TOPLEFT", pane, "TOPLEFT", 58, -26)
    skillReq:SetTextColor(0.7, 0.7, 0.7)
    RB.detailSkillReq = skillReq

    -- Reagents label
    local reagLbl = pane:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    reagLbl:SetPoint("TOPLEFT", pane, "TOPLEFT", 8, -58)
    reagLbl:SetText(CCO.L["LABEL_REAGENTS"] or "Reagents:")
    reagLbl:SetTextColor(0.8, 0.8, 0.2)

    -- Separator
    local sep2 = pane:CreateTexture(nil, "ARTWORK")
    sep2:SetHeight(1)
    sep2:SetPoint("TOPLEFT",  pane, "TOPLEFT",  6,  -54)
    sep2:SetPoint("TOPRIGHT", pane, "TOPRIGHT", -6, -54)
    sep2:SetTexture("Interface\\Buttons\\WHITE8X8")
    sep2:SetVertexColor(0.25, 0.25, 0.30)

    -- Up to 8 reagent icons + text (2 rows of 4)
    RB.reagentIcons = {}
    RB.reagentTexts = {}
    local COL_W   = 126
    local ROW_GAP = 30
    for r = 1, 8 do
        local col   = (r - 1) % 4
        local row   = math.floor((r - 1) / 4)
        local xBase = 8  + col * COL_W
        local yBase = -68 - row * ROW_GAP

        local ico = pane:CreateTexture(nil, "ARTWORK")
        ico:SetSize(22, 22)
        ico:SetPoint("TOPLEFT", pane, "TOPLEFT", xBase, yBase)
        ico:Hide()
        RB.reagentIcons[r] = ico

        local txt = pane:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        txt:SetPoint("LEFT", ico, "RIGHT", 3, 0)
        txt:SetWidth(COL_W - 28)
        txt:SetJustifyH("LEFT")
        txt:Hide()
        RB.reagentTexts[r] = txt
    end
end

-- ============================================================
-- Order Form (bottom strip)
-- ============================================================
function RB:BuildOrderForm(parent)
    local strip = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    strip:SetPoint("BOTTOMLEFT",  parent, "BOTTOMLEFT",  12, 10)
    strip:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -12, 10)
    strip:SetHeight(40)
    strip:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        tile   = true, tileSize = 8,
    })
    strip:SetBackdropColor(0.06, 0.06, 0.10, 0.8)

    -- Commission label
    local commLbl = strip:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    commLbl:SetPoint("LEFT", strip, "LEFT", 8, 0)
    commLbl:SetText(CCO.L["LABEL_COMMISSION"] or "Commission:")
    commLbl:SetTextColor(0.9, 0.9, 0.4)

    -- Coin inputs (Gold / Silver / Copper)
    RB.inputGold   = RB:MakeCoinBox(strip, 106, 0, "g")
    RB.inputSilver = RB:MakeCoinBox(strip, 156, 0, "s")
    RB.inputCopper = RB:MakeCoinBox(strip, 206, 0, "c")

    -- "Mats provided" checkbox
    local matsCheck = CreateFrame("CheckButton", nil, strip, "UICheckButtonTemplate")
    matsCheck:SetPoint("LEFT", strip, "LEFT", 248, 2)
    matsCheck:SetChecked(true)
    RB.matsCheck = matsCheck
    local matsLbl = strip:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    matsLbl:SetPoint("LEFT", matsCheck, "RIGHT", 0, 0)
    matsLbl:SetText(CCO.L["LABEL_MATS_PROVIDED"] or "Mats provided")

    -- Favourite button
    local favBtn = CreateFrame("Button", nil, strip)
    favBtn:SetSize(22, 22)
    favBtn:SetPoint("RIGHT", strip, "RIGHT", -90, 0)
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
    favBtn:SetScript("OnEnter", function()
        GameTooltip:SetOwner(favBtn, "ANCHOR_TOP")
        GameTooltip:SetText("Toggle Favourite")
        GameTooltip:Show()
    end)
    favBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    RB.favBtn = favBtn
    RB.favTex = favTex

    -- Post Order button
    local postBtn = CreateFrame("Button", nil, strip, "UIPanelButtonTemplate")
    postBtn:SetSize(84, 26)
    postBtn:SetPoint("RIGHT", strip, "RIGHT", -2, 0)
    postBtn:SetText(CCO.L["BTN_POST_ORDER"] or "Post Order")
    postBtn:SetScript("OnClick", function() RB:PostOrder() end)
    RB.postBtn = postBtn
end

-- Helper: creates a numeric coin input box
function RB:MakeCoinBox(parent, xOff, yOff, suffix)
    local eb = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    eb:SetSize(36, 18)
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
-- Select a profession
-- ============================================================
function RB:SelectProfession(skillLineID)
    RB.selectedProfID = skillLineID
    RB.selectedRecipe = nil

    -- Reset search
    if RB.searchBox then
        local PLACEHOLDER = CCO.L["SEARCH_PLACEHOLDER"] or "Search recipes..."
        RB.searchBox:SetText(PLACEHOLDER)
        RB.searchBox:SetTextColor(0.5, 0.5, 0.5)
        RB.searchBox:ClearFocus()
    end

    RB:PopulateRecipeList()

    -- Show hint only if player has this profession and it's not yet scanned
    if RB.scanHint then
        local scanned = CCO.RecipeScanner and CCO.RecipeScanner:IsProfessionScanned(skillLineID)
        RB.scanHint:SetShown(not scanned)
    end

    -- Clear detail pane
    if RB.detailItemName then
        RB.detailItemName:SetText("|cff888888Select a recipe|r")
    end
    if RB.detailSkillReq then
        RB.detailSkillReq:SetText("")
    end
    for r = 1, 8 do
        if RB.reagentIcons[r] then RB.reagentIcons[r]:Hide() end
        if RB.reagentTexts[r] then RB.reagentTexts[r]:Hide() end
    end
    if RB.detailIcon then
        RB.detailIcon:SetTexture(nil)
    end
end

-- ============================================================
-- Populate recipe rows
-- ============================================================
function RB:PopulateRecipeList(filterText)
    filterText = filterText or (RB.searchBox and RB.searchBox:GetText()) or ""
    -- Strip placeholder
    local PLACEHOLDER = CCO.L["SEARCH_PLACEHOLDER"] or "Search recipes..."
    if filterText == PLACEHOLDER then filterText = "" end
    filterText = filterText:lower()

    -- Guard: scroll content may be nil if CreateFrame failed
    if not RB.recipeListContent then return end

    -- Clear old rows
    for _, child in ipairs({ RB.recipeListContent:GetChildren() }) do
        child:Hide()
        child:SetParent(nil)
    end
    if RB.emptyLabel then
        RB.emptyLabel:SetShown(not RB.selectedProfID)
    end

    if not RB.selectedProfID then return end

    -- Fetch recipes (live scan takes priority over static DB)
    local recipes
    if CCO.RecipeScanner and CCO.RecipeScanner.GetSortedRecipes then
        recipes = CCO.RecipeScanner:GetSortedRecipes(RB.selectedProfID)
    else
        recipes = {}
    end
    -- Fall back to static RecipeDB if scanner has nothing
    if not recipes or #recipes == 0 then
        local staticList = CCO.RecipeDB and CCO.RecipeDB[RB.selectedProfID] or {}
        recipes = staticList
    end

    -- Apply name filter
    local visible = {}
    for _, recipe in ipairs(recipes) do
        local nameMatch = filterText == "" or recipe.name:lower():find(filterText, 1, true)
        if nameMatch then
            table.insert(visible, recipe)
        end
    end

    RB.filteredRecipes = visible

    if #visible == 0 then
        if RB.emptyLabel then
            RB.emptyLabel:SetText(filterText ~= "" and "No recipes match your search."
                                                    or "No recipes found for this profession.")
            RB.emptyLabel:Show()
        end
        RB.recipeListContent:SetHeight(60)
        return
    end
    if RB.emptyLabel then RB.emptyLabel:Hide() end

    local ROW_H   = 22
    local contentW = RB.recipeListContent:GetWidth() or 510

    -- Player skill for colour coding
    local playerProf = CCO.db and CCO.db.char and CCO.db.char.professions
                        and CCO.db.char.professions[RB.selectedProfID]
    local playerRank = playerProf and playerProf.rank or 0

    -- Alternate row background colors
    local EVEN_COLOR  = { 0.10, 0.10, 0.16, 0.5 }
    local ODD_COLOR   = { 0.07, 0.07, 0.11, 0.5 }

    for i, recipe in ipairs(visible) do
        local row = CreateFrame("Button", nil, RB.recipeListContent)
        row:SetSize(contentW, ROW_H)
        row:SetPoint("TOPLEFT", RB.recipeListContent, "TOPLEFT", 0, -(i-1)*ROW_H)
        row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")

        -- Row background
        local rowBg = row:CreateTexture(nil, "BACKGROUND")
        rowBg:SetAllPoints(row)
        rowBg:SetTexture("Interface\\Buttons\\WHITE8X8")
        local c = (i % 2 == 0) and EVEN_COLOR or ODD_COLOR
        rowBg:SetVertexColor(c[1], c[2], c[3], c[4])

        -- Difficulty colour
        local r, g, b = RB:GetDifficultyColor(recipe.minSkill, playerRank)

        -- Item icon
        local ico = row:CreateTexture(nil, "ARTWORK")
        ico:SetSize(16, 16)
        ico:SetPoint("LEFT", row, "LEFT", 4, 0)
        local _, _, _, _, _, _, _, _, _, iconPath = GetItemInfo(recipe.itemID or 0)
        ico:SetTexture(iconPath or "Interface\\Icons\\INV_Misc_QuestionMark")

        -- Recipe name
        local nameLbl = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        nameLbl:SetPoint("LEFT", row, "LEFT", 24, 0)
        nameLbl:SetWidth(contentW - 170)
        nameLbl:SetJustifyH("LEFT")
        nameLbl:SetText(recipe.name)
        nameLbl:SetTextColor(r, g, b)

        -- Source badge
        local srcColors = {
            trainer    = { 0.6, 0.8, 1.0 },
            vendor     = { 0.8, 0.8, 0.4 },
            drop       = { 0.9, 0.5, 0.2 },
            reputation = { 0.6, 0.4, 0.9 },
            quest      = { 1.0, 1.0, 0.0 },
            discovery  = { 0.4, 0.9, 0.7 },
        }
        local src = recipe.source or "unknown"
        local sc = srcColors[src] or { 0.6, 0.6, 0.6 }
        local srcLbl = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        srcLbl:SetPoint("RIGHT", row, "RIGHT", -56, 0)
        srcLbl:SetWidth(90)
        srcLbl:SetJustifyH("RIGHT")
        srcLbl:SetText(src)
        srcLbl:SetTextColor(sc[1], sc[2], sc[3])

        -- Skill required
        local skillLbl = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        skillLbl:SetPoint("RIGHT", row, "RIGHT", -4, 0)
        skillLbl:SetWidth(48)
        skillLbl:SetJustifyH("RIGHT")
        if recipe.minSkill and recipe.minSkill > 0 then
            skillLbl:SetText(tostring(recipe.minSkill))
            skillLbl:SetTextColor(0.7, 0.7, 0.7)
        end

        -- Favourite star
        if recipe.itemID and CCO.Database:IsFavourite(recipe.itemID) then
            local star = row:CreateTexture(nil, "OVERLAY")
            star:SetSize(10, 10)
            star:SetPoint("LEFT", row, "LEFT", contentW - 160, 0)
            star:SetTexture("Interface\\RAIDFRAME\\UI-RaidFrame-Threat")
        end

        -- Live-scan badge (green dot)
        if recipe._scanned then
            local dot = row:CreateTexture(nil, "OVERLAY")
            dot:SetSize(6, 6)
            dot:SetPoint("TOPRIGHT", row, "TOPRIGHT", -2, -3)
            dot:SetTexture("Interface\\Buttons\\WHITE8X8")
            dot:SetVertexColor(0, 0.9, 0.2, 0.8)
        end

        local capturedRecipe = recipe
        row:SetScript("OnClick", function() RB:ShowRecipeDetail(capturedRecipe) end)
        row:SetScript("OnEnter", function()
            GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
            -- NOTE: SetItemByID is Legion+; use GetItemInfo → SetHyperlink instead
            if capturedRecipe.itemID and capturedRecipe.itemID > 0 then
                local _, iLink = GetItemInfo(capturedRecipe.itemID)
                if iLink then
                    GameTooltip:SetHyperlink(iLink)
                else
                    GameTooltip:SetText(capturedRecipe.name)
                end
            else
                GameTooltip:SetText(capturedRecipe.name)
            end
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end

    RB.recipeListContent:SetHeight(math.max(40, #visible * ROW_H))

    -- Recipe count
    if RB.recipeCountLbl then
        RB.recipeCountLbl:SetText("Showing " .. #visible .. " recipe(s)")
    else
        local countLbl = RB.recipeListBg:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        countLbl:SetPoint("BOTTOMRIGHT", RB.recipeListBg, "BOTTOMRIGHT", -24, 4)
        countLbl:SetTextColor(0.5, 0.5, 0.5)
        countLbl:SetText("Showing " .. #visible .. " recipe(s)")
        RB.recipeCountLbl = countLbl
    end
end

-- ============================================================
-- Difficulty colour (orange → yellow → green → grey)
-- ============================================================
function RB:GetDifficultyColor(minSkill, playerRank)
    minSkill   = minSkill   or 0
    playerRank = playerRank or 0
    local diff = playerRank - minSkill
    if diff < 0  then return 0.6, 0.6, 0.6 end  -- grey  (too high / not yet learnable)
    if diff < 10 then return 1.0, 0.5, 0.0 end  -- orange (optimal skill-up)
    if diff < 25 then return 1.0, 1.0, 0.0 end  -- yellow
    if diff < 50 then return 0.2, 0.9, 0.2 end  -- green
    return 0.5, 0.5, 0.5                         -- grey  (trivial, no skill-up)
end

-- ============================================================
-- Show recipe detail
-- ============================================================
function RB:ShowRecipeDetail(recipe)
    RB.selectedRecipe = recipe

    -- Item info
    local itemName, _, _, _, _, _, _, _, _, iconPath = GetItemInfo(recipe.itemID or 0)
    RB.detailItemName:SetText(itemName or recipe.name)
    RB.detailIcon:SetTexture(iconPath or "Interface\\Icons\\INV_Misc_QuestionMark")
    RB.detailIcon:Show()

    local source = recipe.source or "unknown"
    RB.detailSkillReq:SetText(string.format(
        "Skill required: %d  |  Source: %s  |  %s",
        recipe.minSkill or 0,
        source,
        recipe._scanned and "|cff00cc00Live data|r" or "|cffffcc00Static DB|r"
    ))

    -- Reagents
    for r = 1, 8 do
        RB.reagentIcons[r]:Hide()
        RB.reagentTexts[r]:Hide()
    end

    if recipe.reagents then
        for r, reagent in ipairs(recipe.reagents) do
            if r > 8 then break end
            local iID   = type(reagent) == "table" and (reagent[1] or reagent.itemID) or nil
            local cnt   = type(reagent) == "table" and (reagent[2] or reagent.count or 1) or 1
            local rName = type(reagent) == "table" and reagent.name or nil

            if iID and iID > 0 then
                local rItemName, _, _, _, _, _, _, _, _, rIcon = GetItemInfo(iID)
                RB.reagentIcons[r]:SetTexture(rIcon or "Interface\\Icons\\INV_Misc_QuestionMark")
                RB.reagentIcons[r]:Show()
                RB.reagentTexts[r]:SetText((rItemName or rName or "Item " .. iID) .. " x" .. cnt)
                RB.reagentTexts[r]:Show()
            end
        end
    end

    -- Favourite star state
    local isFav = recipe.itemID and recipe.itemID > 0
                  and CCO.Database:IsFavourite(recipe.itemID) or false
    RB.favTex:SetTexture(isFav and "Interface\\RAIDFRAME\\UI-RaidFrame-Threat"
                                or "Interface\\Buttons\\UI-EmptySlot-Disabled")
end

-- ============================================================
-- Apply search filter
-- ============================================================
function RB:ApplySearchFilter(text)
    if RB.selectedProfID then
        RB:PopulateRecipeList(text)
    elseif text ~= "" then
        -- Global search across all professions
        RB:GlobalSearch(text)
    end
end

-- Global cross-profession search
function RB:GlobalSearch(text)
    if not RB.recipeListContent then return end

    -- Clear old rows
    for _, child in ipairs({ RB.recipeListContent:GetChildren() }) do
        child:Hide()
        child:SetParent(nil)
    end

    local results = CCO:SearchRecipes(text)
    if #results == 0 then
        if RB.emptyLabel then
            RB.emptyLabel:SetText("No recipes match \"" .. text .. "\"")
            RB.emptyLabel:Show()
        end
        RB.recipeListContent:SetHeight(60)
        return
    end
    if RB.emptyLabel then RB.emptyLabel:Hide() end

    local ROW_H   = 22
    local contentW = RB.recipeListContent:GetWidth() or 510

    for i, result in ipairs(results) do
        local recipe   = result.recipe
        local profInfo = PROF_BY_ID[result.skillLineID]

        local row = CreateFrame("Button", nil, RB.recipeListContent)
        row:SetSize(contentW, ROW_H)
        row:SetPoint("TOPLEFT", RB.recipeListContent, "TOPLEFT", 0, -(i-1)*ROW_H)
        row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")

        -- Profession name prefix in light gold
        local profLbl = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        profLbl:SetPoint("LEFT", row, "LEFT", 4, 0)
        profLbl:SetWidth(110)
        profLbl:SetJustifyH("LEFT")
        profLbl:SetText(profInfo and profInfo.name or "?")
        profLbl:SetTextColor(0.8, 0.7, 0.3)

        local nameLbl = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        nameLbl:SetPoint("LEFT", row, "LEFT", 118, 0)
        nameLbl:SetWidth(contentW - 220)
        nameLbl:SetJustifyH("LEFT")
        nameLbl:SetText(recipe.name)

        local skillLbl = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        skillLbl:SetPoint("RIGHT", row, "RIGHT", -4, 0)
        skillLbl:SetWidth(48)
        skillLbl:SetJustifyH("RIGHT")
        skillLbl:SetText(tostring(recipe.minSkill or 0))
        skillLbl:SetTextColor(0.7, 0.7, 0.7)

        local capturedRecipe = recipe
        local capturedProfID = result.skillLineID
        row:SetScript("OnClick", function()
            -- Switch dropdown to this profession, then select recipe
            UIDropDownMenu_SetText(RB.profDropdown, profInfo and profInfo.name or "?")
            RB:SelectProfession(capturedProfID)
            RB:ShowRecipeDetail(capturedRecipe)
        end)
        row:SetScript("OnEnter", function()
            GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
            if capturedRecipe.itemID and capturedRecipe.itemID > 0 then
                local _, iLink = GetItemInfo(capturedRecipe.itemID)
                if iLink then
                    GameTooltip:SetHyperlink(iLink)
                else
                    GameTooltip:SetText(capturedRecipe.name)
                end
            else
                GameTooltip:SetText(capturedRecipe.name)
            end
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end

    RB.recipeListContent:SetHeight(math.max(40, #results * ROW_H))
end

-- ============================================================
-- Post Order
-- ============================================================
function RB:PostOrder()
    local recipe = RB.selectedRecipe
    if not recipe then
        CCO:PrintError(CCO.L["ORDER_MISSING_FIELDS"] or "Please select a recipe first.")
        return
    end

    if not recipe.spellID then
        CCO:PrintError("SpellID unknown for this recipe. Open your tradeskill window to scan it.")
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
        CCO:Print((CCO.L["ORDER_POSTED"] or "Order posted: %s"):format(displayName))
        RB.frame:Hide()
    end
end

-- ============================================================
-- Visibility
-- ============================================================
function RB:Toggle()
    if not RB.frame then
        CCO:PrintError("RecipeBrowser frame not ready.")
        return
    end

    local wasHidden = not RB.frame:IsShown()
    RB.frame:SetShown(wasHidden)

    if wasHidden then
        -- Auto-select the player's first available profession if none selected
        if not RB.selectedProfID then
            if CCO.db and CCO.db.char and CCO.db.char.professions then
                for id in pairs(CCO.db.char.professions) do
                    local profInfo = PROF_BY_ID[id]
                    if profInfo then
                        UIDropDownMenu_SetText(RB.profDropdown, profInfo.name)
                        RB:SelectProfession(id)
                        break
                    end
                end
            end
            -- If still nothing, pick first in the static list
            if not RB.selectedProfID then
                local first = PROF_LIST[1]
                UIDropDownMenu_SetText(RB.profDropdown, first.name)
                RB:SelectProfession(first.id)
            end
        end
    end
end
