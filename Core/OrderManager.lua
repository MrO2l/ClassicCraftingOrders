-- ============================================================
-- ClassicCraftingOrders - Order Manager
-- Central registry for all active orders (local + received).
-- ============================================================
local ADDON_NAME, CCO = ...

CCO.OrderManager = {}
local OM = CCO.OrderManager

-- ============================================================
-- Constants
-- ============================================================
local ORDER_DURATION   = 600    -- Orders expire after 10 minutes
local MAX_ORDERS       = 100    -- Cap the board size

-- ============================================================
-- Internal state
-- ============================================================
-- activeOrders[orderID] = orderTable
local activeOrders = {}

-- Callbacks registered by UI modules
local callbacks = {
    onOrderAdded   = {},
    onOrderRemoved = {},
    onOrderUpdated = {},
}

-- ============================================================
-- Initialise
-- ============================================================
function OM:Initialize()
    -- Purge expired orders periodically
    local ticker = CreateFrame("Frame")
    local elapsed = 0
    ticker:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + dt
        if elapsed >= 30 then    -- check every 30 s
            elapsed = 0
            OM:PurgeExpiredOrders()
        end
    end)
end

-- ============================================================
-- Order creation (local player posting)
-- ============================================================

--- Create a new crafting order and broadcast it.
-- @param itemID      number   WoW item ID
-- @param spellID     number   Tradeskill spell ID used to craft
-- @param commission  number   Tip in copper
-- @param matsProvided boolean  True = requester brings mats
-- @return order table or nil on failure
function OM:PostOrder(itemID, spellID, commission, matsProvided)
    if not itemID or not spellID then
        CCO:PrintError(CCO.L["ERR_RECIPE_NOT_FOUND"])
        return nil
    end

    local order = {
        id           = OM:GenerateID(),
        itemID       = itemID,
        spellID      = spellID,
        playerName   = CCO:GetPlayerKey(),
        commission   = commission or 0,
        matsProvided = matsProvided or false,
        expires      = GetTime() + ORDER_DURATION,
        status       = "searching",   -- searching | accepted | completed | cancelled
        crafterName  = nil,
    }

    activeOrders[order.id] = order
    CCO.Database:SaveMyOrder(order)
    CCO.Communication:BroadcastOrder(order)

    OM:FireCallback("onOrderAdded", order)
    CCO.UI.StatusMonitor:ShowStatus("searching", nil, order)
    return order
end

--- Cancel one of the player's own orders.
function OM:CancelMyOrder(orderID)
    local order = activeOrders[orderID]
    if not order then return end

    order.status = "cancelled"
    CCO.Communication:CancelOrder(orderID)
    CCO.Database:RemoveMyOrder(orderID)
    activeOrders[orderID] = nil
    OM:FireCallback("onOrderRemoved", orderID)
    CCO.UI.StatusMonitor:ShowStatus("cancelled")
end

-- ============================================================
-- Receiving orders from the network
-- ============================================================

function OM:ReceiveOrder(order)
    if not order or not order.id then return end

    -- Don't add own orders received back from the network
    if order.playerName == CCO:GetPlayerKey() then return end

    -- Cap total orders
    if OM:CountOrders() >= MAX_ORDERS then
        -- Remove oldest non-self order
        local oldest, oldestTime
        for id, o in pairs(activeOrders) do
            if o.playerName ~= CCO:GetPlayerKey() then
                if not oldestTime or o.expires < oldestTime then
                    oldest = id
                    oldestTime = o.expires
                end
            end
        end
        if oldest then
            activeOrders[oldest] = nil
            OM:FireCallback("onOrderRemoved", oldest)
        end
    end

    -- Check if the player can craft this (for highlighting)
    order.canCraft = CCO:IsRecipeKnown(order.spellID)

    if activeOrders[order.id] then
        -- Update existing (re-broadcast = refresh expiry)
        activeOrders[order.id] = order
        OM:FireCallback("onOrderUpdated", order)
    else
        activeOrders[order.id] = order
        OM:FireCallback("onOrderAdded", order)
    end
end

function OM:CancelOrder(orderID)
    if activeOrders[orderID] then
        activeOrders[orderID] = nil
        OM:FireCallback("onOrderRemoved", orderID)
    end
end

--- Called when a crafter accepted one of OUR orders.
function OM:OnOrderAccepted(orderID, crafterName)
    local order = activeOrders[orderID]
    if not order then return end

    -- Only react if we are the requester
    if order.playerName ~= CCO:GetPlayerKey() then return end

    order.status     = "accepted"
    order.crafterName = crafterName
    OM:FireCallback("onOrderUpdated", order)
    CCO.UI.StatusMonitor:ShowStatus("found", crafterName, order)
    CCO:Print(CCO.L["STATUS_FOUND"]:format(crafterName))
end

-- ============================================================
-- Queries
-- ============================================================

function OM:GetAllOrders()
    return activeOrders
end

function OM:GetOrder(orderID)
    return activeOrders[orderID]
end

function OM:GetMyOrders()
    local mine = {}
    local selfKey = CCO:GetPlayerKey()
    for id, order in pairs(activeOrders) do
        if order.playerName == selfKey then
            mine[id] = order
        end
    end
    return mine
end

function OM:CountOrders()
    local n = 0
    for _ in pairs(activeOrders) do n = n + 1 end
    return n
end

-- ============================================================
-- Housekeeping
-- ============================================================

function OM:PurgeExpiredOrders()
    local now = GetTime()
    for id, order in pairs(activeOrders) do
        if order.expires <= now then
            activeOrders[id] = nil
            OM:FireCallback("onOrderRemoved", id)
        end
    end
end

function OM:GenerateID()
    -- Combine player name + timestamp + random for uniqueness
    return (UnitName("player") or "x") .. "_" .. math.floor(GetTime()) .. "_" .. math.random(1000, 9999)
end

-- ============================================================
-- Callback system (lightweight pub/sub for UI modules)
-- ============================================================

function OM:RegisterCallback(event, handler)
    callbacks[event] = callbacks[event] or {}
    table.insert(callbacks[event], handler)
end

function OM:FireCallback(event, ...)
    if callbacks[event] then
        for _, fn in ipairs(callbacks[event]) do
            pcall(fn, ...)
        end
    end
end
