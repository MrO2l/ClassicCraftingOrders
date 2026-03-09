-- ============================================================
-- ClassicCraftingOrders - Communication Module
-- Uses SendAddonMessage (GUILD / PARTY / RAID / SAY range) for
-- peer-to-peer order broadcasting.
-- ============================================================
local ADDON_NAME, CCO = ...

CCO.Communication = {}
local Comm = CCO.Communication

-- ============================================================
-- Constants
-- ============================================================
local PREFIX         = CCO.prefix          -- "CCO_ORDERS" (registered in main)
local THROTTLE_SEC   = 5                   -- Minimum seconds between ANY sends
local REBROADCAST_SEC= 120                 -- How often to re-broadcast own orders
local MAX_QUEUE      = 20                  -- Max queued outgoing messages
local MSG_VERSION    = 1                   -- Protocol version byte

-- Message type identifiers (single ASCII char to save space)
local MT_ORDER_POST   = "P"   -- New / refreshed order posted
local MT_ORDER_CANCEL = "C"   -- Order cancelled / expired
local MT_ORDER_ACCEPT = "A"   -- Crafter accepted order
local MT_PRESENCE     = "X"   -- Player announces addon presence

-- Distribution channels to try (in priority order)
local DIST_PRIORITY = { "GUILD", "PARTY", "RAID", "YELL" }

-- ============================================================
-- Internal state
-- ============================================================
local lastSendTime   = 0
local sendQueue      = {}
local rebroadcastTimer = nil

-- ============================================================
-- Initialise
-- ============================================================
function Comm:Initialize()
    local f = CreateFrame("Frame")
    f:RegisterEvent("CHAT_MSG_ADDON")
    f:SetScript("OnEvent", function(_, event, prefix, message, channel, sender)
        if event == "CHAT_MSG_ADDON" and prefix == PREFIX then
            Comm:OnMessageReceived(message, channel, sender)
        end
    end)

    -- Throttled send loop
    local ticker = CreateFrame("Frame")
    local elapsed = 0
    ticker:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + dt
        if elapsed >= 0.1 then   -- check every 100 ms
            elapsed = 0
            Comm:ProcessQueue()
        end
    end)

    -- Schedule periodic re-broadcast of own orders
    self:ScheduleRebroadcast()
end

-- ============================================================
-- Sending
-- ============================================================

--- Queue a message for throttled delivery.
-- @param msgType  string  Single-char message type constant
-- @param payload  table   Key-value data to serialize
function Comm:SendMessage(msgType, payload)
    if #sendQueue >= MAX_QUEUE then
        CCO:PrintError("Send queue full – try again in a moment.")
        return
    end
    payload._v   = MSG_VERSION
    payload._t   = msgType
    local serialized = Comm:Serialize(payload)
    table.insert(sendQueue, serialized)
end

--- Drain up to one message per 0.1 s, respecting THROTTLE_SEC between bursts.
function Comm:ProcessQueue()
    if #sendQueue == 0 then return end
    local now = GetTime()
    if now - lastSendTime < THROTTLE_SEC then return end

    local msg = table.remove(sendQueue, 1)
    local dist = self:GetBestDistribution()
    if dist then
        C_ChatInfo.SendAddonMessage(PREFIX, msg, dist)
        lastSendTime = now
    else
        -- No valid channel; put the message back at the front
        table.insert(sendQueue, 1, msg)
    end
end

--- Pick the best distribution channel available to the player.
function Comm:GetBestDistribution()
    for _, dist in ipairs(DIST_PRIORITY) do
        if dist == "GUILD" and IsInGuild() then return "GUILD" end
        if dist == "RAID"  and IsInRaid()  then return "RAID"  end
        if dist == "PARTY" and IsInGroup() then return "PARTY" end
        if dist == "YELL"  then return "YELL" end
    end
    return "YELL"  -- fallback – limited range but always available
end

-- ============================================================
-- High-level send helpers
-- ============================================================

--- Broadcast a new / refreshed crafting order.
function Comm:BroadcastOrder(order)
    Comm:SendMessage(MT_ORDER_POST, {
        id     = order.id,
        item   = order.itemID,
        spell  = order.spellID,
        player = order.playerName,
        comm   = order.commission,  -- in copper
        mats   = order.matsProvided and 1 or 0,
        exp    = order.expires,     -- Unix-like GetTime() expiry
    })
end

--- Cancel an existing order.
function Comm:CancelOrder(orderID)
    Comm:SendMessage(MT_ORDER_CANCEL, { id = orderID })
end

--- Accept an order (tells the original poster a crafter was found).
function Comm:AcceptOrder(orderID, crafterName)
    Comm:SendMessage(MT_ORDER_ACCEPT, {
        id     = orderID,
        crafter= crafterName,
    })
end

--- Announce addon presence to peers.
function Comm:AnnouncePresence()
    Comm:SendMessage(MT_PRESENCE, { player = UnitName("player") })
end

-- ============================================================
-- Receiving
-- ============================================================

function Comm:OnMessageReceived(rawMsg, channel, senderFull)
    -- Ignore own messages
    local selfName = UnitName("player")
    local senderName = senderFull:match("^([^%-]+)")
    if senderName == selfName then return end

    local ok, data = pcall(Comm.Deserialize, Comm, rawMsg)
    if not ok or type(data) ~= "table" then return end

    local msgType = data._t
    if msgType == MT_ORDER_POST then
        CCO.OrderManager:ReceiveOrder({
            id           = data.id,
            itemID       = data.item,
            spellID      = data.spell,
            playerName   = data.player,
            commission   = data.comm,
            matsProvided = data.mats == 1,
            expires      = data.exp,
            source       = senderFull,
        })
    elseif msgType == MT_ORDER_CANCEL then
        CCO.OrderManager:CancelOrder(data.id)
    elseif msgType == MT_ORDER_ACCEPT then
        CCO.OrderManager:OnOrderAccepted(data.id, data.crafter)
    elseif msgType == MT_PRESENCE then
        -- Optional: show who else has the addon
        if CCO.db and CCO.db.char.settings.showPresenceMessages then
            CCO:Print(CCO.L["COMM_PLAYER_ONLINE"]:format(data.player or senderName))
        end
    end
end

-- ============================================================
-- Periodic re-broadcast of own active orders
-- ============================================================
function Comm:ScheduleRebroadcast()
    local ticker = CreateFrame("Frame")
    local elapsed = 0
    ticker:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + dt
        if elapsed >= REBROADCAST_SEC then
            elapsed = 0
            local orders = CCO.Database:GetMyOrders()
            for _, order in pairs(orders) do
                if order.expires > GetTime() then
                    Comm:BroadcastOrder(order)
                else
                    CCO.Database:RemoveMyOrder(order.id)
                end
            end
        end
    end)
end

-- ============================================================
-- Simple key=value serialization (no external library needed)
-- Avoids the 255-char limit per SendAddonMessage call by using
-- a compact format.  Max payload: ~200 chars.
-- ============================================================

function Comm:Serialize(t)
    local parts = {}
    for k, v in pairs(t) do
        local vs = tostring(v)
        -- Escape the separator character
        vs = vs:gsub("|", "||"):gsub(";", "\\;"):gsub("=", "\\=")
        table.insert(parts, tostring(k) .. "=" .. vs)
    end
    return table.concat(parts, ";")
end

function Comm:Deserialize(str)
    local t = {}
    for kv in (str .. ";"):gmatch("(.-[^\\]);") do
        local k, v = kv:match("^([^=]+)=(.*)")
        if k and v then
            v = v:gsub("\\;", ";"):gsub("\\=", "="):gsub("||", "|")
            -- Attempt numeric conversion
            t[k] = tonumber(v) or v
        end
    end
    return t
end
