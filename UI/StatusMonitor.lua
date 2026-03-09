-- ============================================================
-- ClassicCraftingOrders - Status Monitor UI
-- Small HUD element that shows the current order status for
-- the requesting player.
-- ============================================================
local ADDON_NAME, CCO = ...

CCO.UI = CCO.UI or {}
CCO.UI.StatusMonitor = {}
local SM = CCO.UI.StatusMonitor

-- ============================================================
-- Constants
-- ============================================================
local FRAME_W  = 260
local FRAME_H  = 70
local FADE_SEC = 8    -- Seconds before auto-hiding completed/cancelled state

-- ============================================================
-- State
-- ============================================================
SM.frame       = nil
SM.hideTimer   = nil

-- ============================================================
-- Initialise
-- ============================================================
function SM:Initialize()
    SM:CreateFrame()

    -- If the setting is disabled, keep it permanently hidden
    if not CCO.Database:GetSetting("showStatusMonitor") then
        SM.frame:Hide()
    end
end

-- ============================================================
-- Frame construction
-- ============================================================
function SM:CreateFrame()
    local f = CreateFrame("Frame", "CCO_StatusMonitor", UIParent, "BackdropTemplate")
    f:SetSize(FRAME_W, FRAME_H)
    f:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 200)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:SetClampedToScreen(true)
    f:SetFrameStrata("MEDIUM")
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop",  f.StopMovingOrSizing)
    f:SetBackdrop({
        bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile     = true, tileSize = 32, edgeSize = 16,
        insets   = { left=5, right=5, top=5, bottom=5 },
    })
    f:SetBackdropColor(0, 0, 0, 0.85)
    f:Hide()
    SM.frame = f

    -- Spinning icon (order searching animation)
    local spinIcon = f:CreateTexture(nil, "ARTWORK")
    spinIcon:SetSize(24, 24)
    spinIcon:SetPoint("LEFT", f, "LEFT", 10, 0)
    spinIcon:SetTexture("Interface\\COMMON\\RecentlyAbandonedQuests")
    SM.spinIcon = spinIcon

    -- Status text (main line)
    local statusText = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    statusText:SetPoint("LEFT",   f, "LEFT",  42, 8)
    statusText:SetPoint("RIGHT",  f, "RIGHT", -8, 8)
    statusText:SetJustifyH("LEFT")
    SM.statusText = statusText

    -- Sub-text (e.g. crafter name / instructions)
    local subText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    subText:SetPoint("LEFT",  f, "LEFT",  42, -10)
    subText:SetPoint("RIGHT", f, "RIGHT", -8, -10)
    subText:SetJustifyH("LEFT")
    SM.subText = subText

    -- Cancel button (shown during "searching")
    local cancelBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    cancelBtn:SetSize(60, 20)
    cancelBtn:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -6, 6)
    cancelBtn:SetText("Cancel")
    cancelBtn:SetScript("OnClick", function()
        if SM.currentOrderID then
            CCO.OrderManager:CancelMyOrder(SM.currentOrderID)
        end
        SM:Hide()
    end)
    cancelBtn:Hide()
    SM.cancelBtn = cancelBtn

    -- Pulse animation on the spin icon
    SM:SetupSpinAnimation()
end

function SM:SetupSpinAnimation()
    local ag = SM.spinIcon:CreateAnimationGroup()
    ag:SetLooping("REPEAT")
    local rot = ag:CreateAnimation("Rotation")
    rot:SetDegrees(360)
    rot:SetDuration(2)
    rot:SetOrigin("CENTER", 0, 0)
    SM.spinAG = ag
end

-- ============================================================
-- Public API
-- ============================================================

--- Show or update the status monitor.
-- @param statusKey  string  "searching" | "found" | "trade_ready" | "completed" | "cancelled"
-- @param crafterName string  Optional crafter name
-- @param order      table   Optional order table
function SM:ShowStatus(statusKey, crafterName, order)
    if not CCO.Database:GetSetting("showStatusMonitor") then return end

    SM.currentOrderID = order and order.id or SM.currentOrderID

    -- Cancel any pending auto-hide
    -- NOTE: C_Timer does NOT exist in TBC Classic (added in WoD). We use an
    --       OnUpdate frame as a timer instead; "cancel" = clear its OnUpdate.
    if SM.hideTimer then
        SM.hideTimer:SetScript("OnUpdate", nil)
        SM.hideTimer = nil
    end

    local mainText, subLine, iconColor, showCancel, startSpin, autoHide

    if statusKey == "searching" then
        mainText   = CCO.L["STATUS_SEARCHING"]
        subLine    = order and (GetItemInfo(order.itemID) or ("Item #" .. order.itemID)) or ""
        iconColor  = { 1, 0.8, 0 }
        showCancel = true
        startSpin  = true
        autoHide   = false

    elseif statusKey == "found" then
        mainText   = CCO.L["STATUS_FOUND"]:format(crafterName or "?")
        subLine    = CCO.L["STATUS_TRADE_READY"]:format(crafterName or "?")
        iconColor  = { 0.2, 1, 0.4 }
        showCancel = false
        startSpin  = false
        autoHide   = false

    elseif statusKey == "trade_ready" then
        mainText   = CCO.L["STATUS_TRADE_READY"]:format(crafterName or "?")
        subLine    = ""
        iconColor  = { 0.4, 0.8, 1 }
        showCancel = false
        startSpin  = false
        autoHide   = false

    elseif statusKey == "completed" then
        mainText   = CCO.L["STATUS_COMPLETED"]
        subLine    = ""
        iconColor  = { 0.2, 1, 0.4 }
        showCancel = false
        startSpin  = false
        autoHide   = true

    elseif statusKey == "cancelled" then
        mainText   = CCO.L["STATUS_CANCELLED"]
        subLine    = ""
        iconColor  = { 1, 0.3, 0.3 }
        showCancel = false
        startSpin  = false
        autoHide   = true
    else
        return
    end

    SM.statusText:SetText(mainText)
    SM.subText:SetText(subLine or "")
    SM.spinIcon:SetVertexColor(unpack(iconColor))
    SM.cancelBtn:SetShown(showCancel)

    if startSpin then
        SM.spinAG:Play()
    else
        SM.spinAG:Stop()
    end

    SM.frame:Show()
    SM:PlayAppearAnimation()

    if autoHide then
        -- NOTE: C_Timer.NewTimer does NOT exist in TBC Classic.
        --       Use a plain CreateFrame + OnUpdate as a countdown timer.
        local timerFrame = SM.hideTimer or CreateFrame("Frame")
        SM.hideTimer = timerFrame
        local elapsed = 0
        timerFrame:SetScript("OnUpdate", function(self, dt)
            elapsed = elapsed + dt
            if elapsed >= FADE_SEC then
                self:SetScript("OnUpdate", nil)
                SM.hideTimer = nil
                SM:Hide()
            end
        end)
    end
end

function SM:Hide()
    SM.frame:Hide()
    SM.currentOrderID = nil
    if SM.spinAG then SM.spinAG:Stop() end
end

-- ============================================================
-- Appear animation (slide up + fade in)
-- ============================================================
function SM:PlayAppearAnimation()
    SM.frame:SetAlpha(0)
    local startY = select(5, SM.frame:GetPoint()) or 200

    local ag = SM.frame:CreateAnimationGroup()
    local fade = ag:CreateAnimation("Alpha")
    fade:SetFromAlpha(0)
    fade:SetToAlpha(1)
    fade:SetDuration(0.3)
    fade:SetSmoothing("OUT")

    local move = ag:CreateAnimation("Translation")
    move:SetOffset(0, 12)
    move:SetDuration(0.3)
    move:SetSmoothing("OUT")

    ag:SetScript("OnFinished", function()
        SM.frame:SetAlpha(1)
    end)
    ag:Play()
end
