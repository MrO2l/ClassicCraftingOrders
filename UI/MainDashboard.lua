-- ============================================================
-- ClassicCraftingOrders - Main Dashboard UI
--
-- BUG-FIX NOTES (v1.2):
--   1. SetColorTexture() does NOT exist in TBC Classic – replaced with
--      SetTexture + SetVertexColor + SetAlpha on all separator/line textures.
--   2. SetBackdropColor was too dark (0.08,0.08,0.12) – raised to a
--      visible dark-blue-grey.
--   3. CreateTexture solid-colour background added as guaranteed fallback
--      in case SetBackdrop is unavailable or its result is transparent.
--   4. Main frame no longer uses RegisterForDrag / EnableMouse on itself;
--      only a narrow title-bar sub-frame handles dragging.  This prevents
--      the parent frame from intercepting clicks meant for child buttons.
--   5. Each nav button gets an explicit SetFrameLevel() above the parent
--      so WoW's hit-test always routes clicks to the button, not the frame.
-- ============================================================
local ADDON_NAME, CCO = ...

CCO.UI         = CCO.UI or {}
CCO.UI.Dashboard = {}
local D        = CCO.UI.Dashboard

-- ============================================================
-- Helper: solid background texture (always works in TBC Classic)
-- ============================================================
local function ApplyBackground(f)
    -- Solid dark background via CreateTexture – guaranteed to be visible.
    -- Uses WHITE8X8 (a 1-px white texture) with SetVertexColor tinting.
    local bg = f:CreateTexture(nil, "BACKGROUND", nil, -8)
    bg:SetPoint("TOPLEFT",     f, "TOPLEFT",     0,  0)
    bg:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0,  0)
    bg:SetTexture("Interface\\Buttons\\WHITE8X8")
    bg:SetVertexColor(0.09, 0.09, 0.14)
    bg:SetAlpha(0.97)

    -- Also try the nicer tiled dialog texture via SetBackdrop.
    -- This adds the proper dialog border and tiled grey background.
    -- SetBackdrop is native on all frames in TBC Classic 2.5.x.
    if f.SetBackdrop then
        f:SetBackdrop({
            bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile     = true,
            tileSize = 32,
            edgeSize = 32,
            insets   = { left = 11, right = 12, top = 12, bottom = 11 },
        })
        -- Use a visible mid-grey tint (pure white = texture as-is).
        -- Do NOT use 0.08 – the texture is already dark; that would make
        -- it nearly invisible.
        f:SetBackdropColor(0.22, 0.22, 0.30, 0.96)
        if f.SetBackdropBorderColor then
            f:SetBackdropBorderColor(0.55, 0.55, 0.65, 1.0)
        end
    end
end

-- ============================================================
-- Helper: create a 1-px horizontal rule
-- NOTE: SetColorTexture() does NOT exist in TBC Classic (retail only).
--       Use SetTexture("…WHITE8X8") + SetVertexColor + SetAlpha instead.
-- ============================================================
local function MakeSeparator(parent, xLeft, xRight, yTop)
    local line = parent:CreateTexture(nil, "ARTWORK")
    line:SetPoint("TOPLEFT",  parent, "TOPLEFT",  xLeft,  yTop)
    line:SetPoint("TOPRIGHT", parent, "TOPRIGHT", xRight, yTop)
    line:SetHeight(1)
    line:SetTexture("Interface\\Buttons\\WHITE8X8")
    line:SetVertexColor(0.45, 0.45, 0.55)
    line:SetAlpha(0.80)
    return line
end

-- ============================================================
-- Initialise
-- ============================================================
function D:Initialize()
    -- CCO_Dashboard is the bare frame created by MainDashboard.xml
    local f = CCO_Dashboard
    if not f then
        CCO:PrintError("CCO_Dashboard frame not found – XML load failed.")
        return
    end
    D.frame = f

    -- Frame properties set in Lua for full control
    f:SetFrameStrata("HIGH")
    f:SetToplevel(true)          -- proper window-management focus
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    -- Do NOT call f:EnableMouse(true) on the main frame.
    -- Only the title-bar sub-frame handles mouse/drag so the main frame
    -- never steals click events meant for child buttons.

    -- Background + border
    ApplyBackground(f)

    -- ---- Title bar (acts as the drag handle) ----
    -- A thin sub-frame at the top of the window that owns EnableMouse
    -- and RegisterForDrag.  The rest of the window has no mouse handler,
    -- so button clicks always reach the buttons directly.
    local titleBar = CreateFrame("Frame", nil, f)
    titleBar:SetPoint("TOPLEFT",  f, "TOPLEFT",  0,  0)
    titleBar:SetPoint("TOPRIGHT", f, "TOPRIGHT",  0,  0)
    titleBar:SetHeight(34)
    titleBar:EnableMouse(true)
    titleBar:RegisterForDrag("LeftButton")
    titleBar:SetScript("OnDragStart", function() f:StartMoving() end)
    titleBar:SetScript("OnDragStop",  function() f:StopMovingOrSizing() end)
    D.titleBar = titleBar

    -- Title text
    local titleText = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    titleText:SetPoint("TOP", f, "TOP", 0, -12)
    titleText:SetText(CCO.L["DASHBOARD_TITLE"])
    D.titleText = titleText

    -- Separator under title
    MakeSeparator(f, 14, -14, -32)

    -- ---- Close button ----
    -- Must be a child of f (not titleBar) so it keeps its position when
    -- the window is resized; frame level is raised above the parent frame
    -- so the hit-test always reaches the button first.
    local closeBtn = CreateFrame("Button", "CCO_DashClose", f, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", 1, 1)
    closeBtn:SetScript("OnClick", function() D:Hide() end)
    closeBtn:SetFrameLevel(f:GetFrameLevel() + 10)
    D.closeBtn = closeBtn

    -- ---- Navigation + content ----
    D:BuildNavButtons()
    D:BuildMyOrdersPanel()
    D:RestorePosition()

    -- Restore open/closed state from last session
    local shown = CCO.db and CCO.db.char
                  and CCO.db.char.ui
                  and CCO.db.char.ui.dashboard
                  and CCO.db.char.ui.dashboard.shown
    if shown then f:Show() end
end

-- ============================================================
-- Navigation Buttons
-- ============================================================
local navButtons = {}
local navDefs    = {
    { key = "newOrder",   label = "BTN_NEW_ORDER",   action = function() CCO.UI.RecipeBrowser:Toggle() end },
    { key = "orderBoard", label = "BTN_ORDER_BOARD",  action = function() CCO.UI.OrderBoard:Toggle()   end },
    { key = "myOrders",   label = "BTN_MY_ORDERS",    action = function() D:ShowMyOrdersPanel()        end },
    { key = "settings",   label = "BTN_SETTINGS",     action = function() D:ShowSettingsPanel()        end },
}

function D:BuildNavButtons()
    local f       = D.frame
    local btnW    = 310
    local btnH    = 36
    local spacing = 8
    local startY  = -44  -- below title bar (34 px) + a little gap

    for i, def in ipairs(navDefs) do
        local btn = CreateFrame("Button", "CCO_DashBtn_" .. def.key, f, "UIPanelButtonTemplate")
        btn:SetSize(btnW, btnH)
        btn:SetPoint("TOP", f, "TOP", 0, startY - (i - 1) * (btnH + spacing))
        btn:SetText(CCO.L[def.label])
        btn:SetScript("OnClick", def.action)
        -- Raise frame level above parent so hit-test always routes here
        btn:SetFrameLevel(f:GetFrameLevel() + 10)
        navButtons[def.key] = btn
    end
end

-- ============================================================
-- My Orders Panel
-- ============================================================
function D:BuildMyOrdersPanel()
    local f     = D.frame
    local panel = CreateFrame("Frame", nil, f)
    panel:SetPoint("TOPLEFT",     f, "TOPLEFT",      14, -220)
    panel:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -14,  40)
    panel:Hide()
    D.myOrdersPanel = panel

    local hdr = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    hdr:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, 0)
    hdr:SetText(CCO.L["BTN_MY_ORDERS"])

    local sf = CreateFrame("ScrollFrame", "CCO_MyOrdersScroll", panel,
                           "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT",     panel, "TOPLEFT",      0, -22)
    sf:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -24,  0)
    D.myOrdersScrollFrame = sf

    local content = CreateFrame("Frame", nil, sf)
    content:SetSize(sf:GetWidth() or 300, 1)
    sf:SetScrollChild(content)
    D.myOrdersContent = content

    CCO.OrderManager:RegisterCallback("onOrderAdded",   function() D:RefreshMyOrders() end)
    CCO.OrderManager:RegisterCallback("onOrderRemoved", function() D:RefreshMyOrders() end)
    CCO.OrderManager:RegisterCallback("onOrderUpdated", function() D:RefreshMyOrders() end)
end

function D:ShowMyOrdersPanel()
    if not D.myOrdersPanel then return end
    D.myOrdersPanel:Show()
    D:RefreshMyOrders()
end

function D:RefreshMyOrders()
    if not D.myOrdersContent then return end
    local content = D.myOrdersContent

    for _, child in ipairs({ content:GetChildren() }) do
        child:Hide()
        child:SetParent(nil)
    end

    local myOrders = CCO.OrderManager:GetMyOrders()
    local yOffset  = 0
    local rowH     = 28

    for _, order in pairs(myOrders) do
        local row = CreateFrame("Frame", nil, content)
        row:SetSize(content:GetWidth() or 280, rowH)
        row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -yOffset)

        local itemName = GetItemInfo(order.itemID) or ("Item #" .. order.itemID)

        local nameText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        nameText:SetPoint("LEFT", row, "LEFT", 0, 0)
        nameText:SetWidth(170)
        nameText:SetText(itemName)
        nameText:SetJustifyH("LEFT")

        local commText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        commText:SetPoint("LEFT", row, "LEFT", 178, 0)
        commText:SetText(CCO:FormatGold(order.commission))

        local cancelBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        cancelBtn:SetSize(55, 20)
        cancelBtn:SetPoint("RIGHT", row, "RIGHT", 0, 0)
        cancelBtn:SetText("Cancel")
        local capturedID = order.id
        cancelBtn:SetScript("OnClick", function()
            CCO.OrderManager:CancelMyOrder(capturedID)
        end)

        yOffset = yOffset + rowH + 2
    end

    content:SetHeight(math.max(1, yOffset))
end

-- ============================================================
-- Settings Panel
-- ============================================================
function D:ShowSettingsPanel()
    if D.settingsPanel then
        D.settingsPanel:SetShown(not D.settingsPanel:IsShown())
        return
    end

    local f  = D.frame
    local sp = CreateFrame("Frame", nil, f)
    sp:SetPoint("TOPLEFT",     f, "TOPLEFT",      14, -220)
    sp:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -14,  40)
    -- Background for settings panel
    if sp.SetBackdrop then
        sp:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            tile   = true, tileSize = 8,
        })
        sp:SetBackdropColor(0.06, 0.06, 0.09, 0.85)
    end
    D.settingsPanel = sp

    MakeSeparator(f, 14, -14, -218)

    local function AddCheckbox(parent, key, labelStr, yOff)
        local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
        cb:SetPoint("TOPLEFT", parent, "TOPLEFT", 8, yOff)
        cb:SetFrameLevel(parent:GetFrameLevel() + 5)
        local ok, val = pcall(CCO.Database.GetSetting, CCO.Database, key)
        if ok then cb:SetChecked(val) end
        cb:SetScript("OnClick", function(self)
            CCO.Database:SetSetting(key, self:GetChecked())
        end)
        local lbl = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        lbl:SetPoint("LEFT", cb, "RIGHT", 4, 0)
        lbl:SetText(labelStr)
        return cb
    end

    AddCheckbox(sp, "showOnlyMatchingOrders", CCO.L["SETTING_ONLY_MATCHING"]  or "Nur herstellbare Aufträge hervorheben", -12)
    AddCheckbox(sp, "autoFillTrade",          CCO.L["SETTING_AUTO_FILL"]      or "Handelsfenster automatisch befüllen",   -40)
    AddCheckbox(sp, "showStatusMonitor",      CCO.L["SETTING_STATUS_MONITOR"] or "Status-Monitor anzeigen",               -68)
end

-- ============================================================
-- Visibility
-- ============================================================
function D:Toggle()
    if not D.frame then return end
    D.frame:SetShown(not D.frame:IsShown())
    D:_saveShown()
end

function D:Hide()
    if not D.frame then return end
    D.frame:Hide()
    D:_saveShown()
end

function D:_saveShown()
    if CCO.db and CCO.db.char and CCO.db.char.ui and CCO.db.char.ui.dashboard then
        CCO.db.char.ui.dashboard.shown = D.frame and D.frame:IsShown() or false
    end
end

-- ============================================================
-- Position persistence
-- ============================================================
function D:SavePosition()
    if not D.frame then return end
    local x, y  = D.frame:GetCenter()
    local scale = D.frame:GetEffectiveScale()
    if CCO.db and CCO.db.char and CCO.db.char.ui and CCO.db.char.ui.dashboard then
        CCO.db.char.ui.dashboard.x = x * scale
        CCO.db.char.ui.dashboard.y = y * scale
    end
end

function D:RestorePosition()
    if not D.frame then return end
    local ui = CCO.db and CCO.db.char and CCO.db.char.ui
               and CCO.db.char.ui.dashboard
    if ui and ui.x and ui.y then
        local scale = D.frame:GetEffectiveScale()
        D.frame:ClearAllPoints()
        D.frame:SetPoint("CENTER", UIParent, "BOTTOMLEFT", ui.x / scale, ui.y / scale)
    end
end

function D:ResetPosition()
    if not D.frame then return end
    D.frame:ClearAllPoints()
    D.frame:SetPoint("CENTER")
    D:SavePosition()
end
