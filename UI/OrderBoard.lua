-- ============================================================
-- ClassicCraftingOrders - Order Board UI
-- Displays all active network orders, highlighting craftable ones.
-- ============================================================
local ADDON_NAME, CCO = ...

CCO.UI = CCO.UI or {}
CCO.UI.OrderBoard = {}
local OB = CCO.UI.OrderBoard

-- ============================================================
-- Constants
-- ============================================================
local ROW_HEIGHT    = 32
local ROWS_VISIBLE  = 10
local COL_WIDTHS    = { item = 140, requester = 110, comm = 80, mats = 80, action = 60 }

-- ============================================================
-- State
-- ============================================================
OB.frame       = nil
OB.rows        = {}
OB.filterMode  = "all"    -- "all" | "craftable"
OB.sortKey     = "comm"   -- "item" | "comm" | "mats"
OB.sortAsc     = false

-- ============================================================
-- Initialise
-- ============================================================
function OB:Initialize()
    OB:CreateFrame()

    -- Subscribe to order events for live refresh
    CCO.OrderManager:RegisterCallback("onOrderAdded",   function() OB:Refresh() end)
    CCO.OrderManager:RegisterCallback("onOrderRemoved", function() OB:Refresh() end)
    CCO.OrderManager:RegisterCallback("onOrderUpdated", function() OB:Refresh() end)
end

-- ============================================================
-- Frame construction
-- ============================================================
function OB:CreateFrame()
    local totalW = COL_WIDTHS.item + COL_WIDTHS.requester + COL_WIDTHS.comm
                 + COL_WIDTHS.mats + COL_WIDTHS.action + 28
    local totalH = 60 + 28 + ROW_HEIGHT * ROWS_VISIBLE + 16 + 32

    local f = CreateFrame("Frame", "CCO_OrderBoard", UIParent)
    f:SetSize(totalW, totalH)
    f:SetPoint("CENTER")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:SetClampedToScreen(true)
    f:SetFrameStrata("MEDIUM")
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
    OB.frame = f

    -- Title
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", f, "TOP", 0, -10)
    title:SetText(CCO.L["ORDER_BOARD_TITLE"])

    -- Close
    local closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
    closeBtn:SetScript("OnClick", function() f:Hide() end)

    -- Filter toggle
    local filterBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    filterBtn:SetSize(140, 22)
    filterBtn:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -34)
    filterBtn:SetText("Show: All Orders")
    filterBtn:SetScript("OnClick", function()
        if OB.filterMode == "all" then
            OB.filterMode = "craftable"
            filterBtn:SetText("Show: Craftable Only")
        else
            OB.filterMode = "all"
            filterBtn:SetText("Show: All Orders")
        end
        OB:Refresh()
    end)
    OB.filterBtn = filterBtn

    -- Refresh button
    local refreshBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    refreshBtn:SetSize(80, 22)
    refreshBtn:SetPoint("TOPLEFT", f, "TOPLEFT", 162, -34)
    refreshBtn:SetText("Refresh")
    refreshBtn:SetScript("OnClick", function() OB:Refresh() end)

    -- Column headers
    OB:BuildHeaders(f)

    -- Scroll frame for rows
    local sf = CreateFrame("ScrollFrame", "CCO_OrderBoardScroll", f, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT",     f, "TOPLEFT",  14, -88)
    sf:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -28, 40)
    OB.scrollFrame = sf

    local content = CreateFrame("Frame", nil, sf)
    content:SetSize(totalW - 42, ROW_HEIGHT * ROWS_VISIBLE)
    sf:SetScrollChild(content)
    OB.listContent = content

    -- Empty-state label
    local emptyText = content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    emptyText:SetPoint("CENTER", content, "CENTER")
    emptyText:SetText(CCO.L["NO_ORDERS"])
    emptyText:Hide()
    OB.emptyText = emptyText

    -- Order count label
    local countText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    countText:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 16, 16)
    OB.countText = countText
end

-- ============================================================
-- Column headers
-- ============================================================
function OB:BuildHeaders(parent)
    local cols = {
        { label = CCO.L["COL_ITEM"],      key = "item",  width = COL_WIDTHS.item      },
        { label = CCO.L["COL_REQUESTER"], key = "req",   width = COL_WIDTHS.requester },
        { label = CCO.L["COL_COMMISSION"],key = "comm",  width = COL_WIDTHS.comm      },
        { label = CCO.L["COL_MATS"],      key = "mats",  width = COL_WIDTHS.mats      },
        { label = CCO.L["COL_ACTION"],    key = nil,     width = COL_WIDTHS.action    },
    }

    local xOff = 14
    for _, col in ipairs(cols) do
        local btn = CreateFrame("Button", nil, parent)
        btn:SetSize(col.width, 24)
        btn:SetPoint("TOPLEFT", parent, "TOPLEFT", xOff, -62)

        local lbl = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        lbl:SetAllPoints(btn)
        lbl:SetJustifyH("LEFT")
        lbl:SetText(col.label)

        if col.key then
            btn:SetScript("OnClick", function()
                if OB.sortKey == col.key then
                    OB.sortAsc = not OB.sortAsc
                else
                    OB.sortKey = col.key
                    OB.sortAsc = false
                end
                OB:Refresh()
            end)
            btn:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        end

        xOff = xOff + col.width
    end

    -- Header separator line
    local line = parent:CreateTexture(nil, "ARTWORK")
    line:SetHeight(1)
    line:SetPoint("TOPLEFT",  parent, "TOPLEFT",  14, -86)
    line:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -28, -86)
    line:SetTexture("Interface\\Buttons\\WHITE8X8")
    line:SetVertexColor(0.4, 0.4, 0.4)
    line:SetAlpha(1)
end

-- ============================================================
-- Refresh – rebuild the visible rows
-- ============================================================
function OB:Refresh()
    -- Clear existing rows
    for _, row in ipairs(OB.rows) do
        row:Hide()
        row:SetParent(nil)
    end
    OB.rows = {}

    -- Collect and optionally filter orders
    local orders = {}
    for _, order in pairs(CCO.OrderManager:GetAllOrders()) do
        if OB.filterMode == "all" or order.canCraft then
            table.insert(orders, order)
        end
    end

    -- Sort
    table.sort(orders, function(a, b)
        local va, vb
        if OB.sortKey == "item" then
            va = GetItemInfo(a.itemID) or ""
            vb = GetItemInfo(b.itemID) or ""
        elseif OB.sortKey == "comm" then
            va = a.commission
            vb = b.commission
        elseif OB.sortKey == "mats" then
            va = a.matsProvided and 0 or 1
            vb = b.matsProvided and 0 or 1
        else
            va = a.commission
            vb = b.commission
        end
        if OB.sortAsc then return va < vb else return va > vb end
    end)

    OB.emptyText:SetShown(#orders == 0)

    for i, order in ipairs(orders) do
        OB:CreateRow(order, i)
    end

    OB.listContent:SetHeight(math.max(ROW_HEIGHT * ROWS_VISIBLE, #orders * ROW_HEIGHT))

    if OB.countText then
        OB.countText:SetText("Orders: " .. #orders .. " / " .. CCO.OrderManager:CountOrders())
    end
end

-- ============================================================
-- Create a single row
-- ============================================================
function OB:CreateRow(order, index)
    local content = OB.listContent
    local yOff    = -(index - 1) * ROW_HEIGHT

    local row = CreateFrame("Frame", nil, content)
    row:SetSize(content:GetWidth(), ROW_HEIGHT - 2)
    row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, yOff)

    -- Alternating row background
    if index % 2 == 0 then
        row:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", tile = true, tileSize = 8 })
        row:SetBackdropColor(0.1, 0.1, 0.15, 0.4)
    end

    -- Craftable highlight
    if order.canCraft then
        row:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", tile = true, tileSize = 8 })
        row:SetBackdropColor(0.0, 0.25, 0.0, 0.5)
    end

    -- Item icon + name
    local itemName, _, _, _, _, _, _, _, _, iconPath = GetItemInfo(order.itemID or 0)
    local displayName = itemName or ("Item #" .. tostring(order.itemID))

    local icon = row:CreateTexture(nil, "ARTWORK")
    icon:SetSize(ROW_HEIGHT - 4, ROW_HEIGHT - 4)
    icon:SetPoint("LEFT", row, "LEFT", 2, 0)
    if iconPath then icon:SetTexture(iconPath) end

    local nameText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    nameText:SetPoint("LEFT", row, "LEFT", ROW_HEIGHT + 2, 0)
    nameText:SetWidth(COL_WIDTHS.item - ROW_HEIGHT - 4)
    nameText:SetJustifyH("LEFT")
    nameText:SetText(displayName)
    if order.canCraft then
        nameText:SetTextColor(0.2, 1, 0.4)
    end

    -- Requester
    local reqName = order.playerName:match("^([^%-]+)") or order.playerName
    local reqText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    reqText:SetPoint("LEFT", row, "LEFT", COL_WIDTHS.item + 2, 0)
    reqText:SetWidth(COL_WIDTHS.requester - 4)
    reqText:SetJustifyH("LEFT")
    reqText:SetText(reqName)

    -- Commission
    local commText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    commText:SetPoint("LEFT", row, "LEFT", COL_WIDTHS.item + COL_WIDTHS.requester + 2, 0)
    commText:SetWidth(COL_WIDTHS.comm - 4)
    commText:SetJustifyH("LEFT")
    commText:SetText(CCO:FormatGold(order.commission))

    -- Materials
    local matsText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    matsText:SetPoint("LEFT", row, "LEFT", COL_WIDTHS.item + COL_WIDTHS.requester + COL_WIDTHS.comm + 2, 0)
    matsText:SetWidth(COL_WIDTHS.mats - 4)
    matsText:SetJustifyH("LEFT")
    matsText:SetText(order.matsProvided and CCO.L["MATS_PROVIDED"] or CCO.L["MATS_NEEDED"])
    matsText:SetTextColor(order.matsProvided and 0.4 or 1, order.matsProvided and 1 or 0.6, 0.4)

    -- Accept button
    if order.canCraft then
        local acceptBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        acceptBtn:SetSize(56, 20)
        acceptBtn:SetPoint("LEFT", row, "LEFT",
            COL_WIDTHS.item + COL_WIDTHS.requester + COL_WIDTHS.comm + COL_WIDTHS.mats + 2, 0)
        acceptBtn:SetText(CCO.L["BTN_ACCEPT"])
        local capturedOrder = order
        acceptBtn:SetScript("OnClick", function()
            OB:AcceptOrder(capturedOrder)
        end)
    end

    -- Tooltip on hover
    row:SetScript("OnEnter", function()
        GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
        if order.itemID then
            GameTooltip:SetItemByID(order.itemID)
        end
        if order.canCraft then
            GameTooltip:AddLine(CCO.L["CAN_CRAFT"], 0.2, 1, 0.4)
        else
            GameTooltip:AddLine(CCO.L["CANNOT_CRAFT"], 1, 0.4, 0.4)
        end
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    table.insert(OB.rows, row)
    return row
end

-- ============================================================
-- Accept an order
-- ============================================================
function OB:AcceptOrder(order)
    local crafterName = CCO:GetPlayerKey()
    CCO.Communication:AcceptOrder(order.id, crafterName)

    -- Whisper the requester
    local requesterShort = order.playerName:match("^([^%-]+)")
    local itemName       = GetItemInfo(order.itemID) or ("Item #" .. order.itemID)
    local whisperMsg     = CCO.L["WHISPER_ACCEPT"]:format(itemName, CCO:FormatGold(order.commission))
    SendChatMessage(whisperMsg, "WHISPER", nil, requesterShort)

    CCO:Print(CCO.L["ORDER_ACCEPTED_MSG"]:format(itemName, requesterShort))
    OB:Refresh()
end

-- ============================================================
-- Visibility
-- ============================================================
function OB:Toggle()
    OB.frame:SetShown(not OB.frame:IsShown())
    if OB.frame:IsShown() then
        OB:Refresh()
    end
end
