-- ============================================================
-- ClassicCraftingOrders - Communication Module  (v1.5.0)
--
-- ┌─────────────────────────────────────────────────────────┐
-- │                  ARCHITECTURE OVERVIEW                   │
-- ├─────────────────────────────────────────────────────────┤
-- │  PRIMARY BROADCAST (when posting an order)              │
-- │    GUILD  ──► all guild members, unlimited range (1 msg)│
-- │    RAID   ──► all raid  members, unlimited range (1 msg)│
-- │    PARTY  ──► all party members, unlimited range (1 msg)│
-- │    WHISPER ─► only CCO players not covered above        │
-- │                                                          │
-- │  RELAY (passive cross-channel bridge)                    │
-- │    A player in GUILD + RAID acts as a bridge:           │
-- │    order received via GUILD → forwarded to RAID (1 hop) │
-- │    order received via RAID  → forwarded to GUILD (1 hop)│
-- │    TTL = 1 → exactly one hop, no exponential growth     │
-- │                                                          │
-- │  DISCOVERY                                               │
-- │    1. YELL  (once on login + every 90 s) "I'm here"     │
-- │    2. New player seen → WHISPER them a QUERY            │
-- │    3. Recipient → WHISPER back current orders (1-time)  │
-- │    After sync: NO further WHISPER for ongoing orders    │
-- └─────────────────────────────────────────────────────────┘
--
-- WHY NOT CUSTOM CHANNEL:
--   Blizzard removed "CHANNEL" from addon messaging in
--   Classic Patch 1.13.3 (Dec 2019). C_ChatInfo.SendAddonMessage
--   supports only: PARTY, RAID, GUILD, WHISPER, SAY, YELL,
--   OFFICER. JoinTemporaryChannel only produces CHAT_MSG_CHANNEL
--   events (not CHAT_MSG_ADDON). Custom channels cannot carry
--   addon messages in TBC Classic Anniversary.
--
-- RATE LIMITS (Shadowlands-era client):
--   Per-prefix token bucket: 10-message burst, 1 msg/sec refill.
--   Posting one order = 3-5 sends (burst, well within bucket).
--   Queue drain: 0.8 s/msg (safe under sustained 1 msg/sec limit).
--   Reference: Wowpedia "Addon Comm Throttling", ChatThrottleLib.
--
-- SAFETY:
--   YELL: 1 per 90 s — normal addon behavior, no ban risk.
--   WHISPER: only on first contact + only to unreachable players.
--   Relay: queued like any other send, within rate limits.
-- ============================================================
local ADDON_NAME, CCO = ...

CCO.Communication = {}
local Comm = CCO.Communication

-- ============================================================
-- Constants
-- ============================================================
local PREFIX          = CCO.prefix    -- "CCO_ORDERS"
local DRAIN_INTERVAL  = 0.8           -- s between sends; 1.25 msg/s < 1 msg/s limit
local PRESENCE_SEC    = 90            -- presence broadcast interval (s)
local REBROADCAST_SEC = 120           -- re-broadcast own active orders (s)
local MAX_QUEUE       = 40            -- max queued sends (burst budget x4)
local MSG_VERSION     = 3             -- bump on protocol-breaking changes
local RELAY_TTL       = 1             -- relay hop limit (1 = exactly one relay)

-- Single-character message type IDs (minimal payload size)
local MT_ORDER_POST   = "P"   -- new / refreshed crafting order
local MT_ORDER_CANCEL = "C"   -- order cancelled or expired
local MT_ORDER_ACCEPT = "A"   -- crafter accepted an order
local MT_PRESENCE     = "X"   -- player presence / discovery ping
local MT_QUERY        = "Q"   -- request all active orders (WHISPER)

-- Channels used for primary broadcasts (priority order for relay decisions)
local BROADCAST_CHANNELS = { "GUILD", "RAID", "PARTY" }

-- ============================================================
-- State
-- ============================================================
local sendQueue  = {}   -- { msg=string, dist=string, target=string|nil }
local relayedIDs = {}   -- set of orderIDs already relayed this session

-- knownPlayers: players discovered to have CCO installed
--   key = "Name-Realm"  (full unique key)
--   value = { name="Name", realm="Realm", lastSeen=GetTime() }
CCO.knownPlayers = CCO.knownPlayers or {}

-- ============================================================
-- Initialise
-- ============================================================
function Comm:Initialize()

    -- ── Event listener ──────────────────────────────────────
    local listener = CreateFrame("Frame")
    listener:RegisterEvent("CHAT_MSG_ADDON")
    listener:SetScript("OnEvent", function(_, event, prefix, message, channel, sender)
        if event == "CHAT_MSG_ADDON" and prefix == PREFIX then
            Comm:OnMessageReceived(message, channel, sender)
        end
    end)

    -- ── Queue drain (one message per DRAIN_INTERVAL) ─────────
    local drainer  = CreateFrame("Frame")
    local drainAcc = 0
    drainer:SetScript("OnUpdate", function(_, dt)
        drainAcc = drainAcc + dt
        if drainAcc >= DRAIN_INTERVAL then
            drainAcc = 0
            Comm:DrainQueue()
        end
    end)

    -- ── Periodic presence broadcast ──────────────────────────
    local presTimer = CreateFrame("Frame")
    local presAcc   = 0
    presTimer:SetScript("OnUpdate", function(_, dt)
        presAcc = presAcc + dt
        if presAcc >= PRESENCE_SEC then
            presAcc = 0
            Comm:BroadcastPresence()
        end
    end)

    -- ── Periodic re-broadcast of own orders ──────────────────
    local rebroadTimer = CreateFrame("Frame")
    local rebroadAcc   = 0
    rebroadTimer:SetScript("OnUpdate", function(_, dt)
        rebroadAcc = rebroadAcc + dt
        if rebroadAcc >= REBROADCAST_SEC then
            rebroadAcc = 0
            local now = GetTime()
            for _, order in pairs(CCO.Database:GetMyOrders()) do
                if order.expires > now then
                    Comm:BroadcastOrder(order)
                else
                    CCO.Database:RemoveMyOrder(order.id)
                end
            end
        end
    end)

    -- ── Initial presence ping (3 s after login) ──────────────
    local initTimer = CreateFrame("Frame")
    local initAcc   = 0
    initTimer:SetScript("OnUpdate", function(self, dt)
        initAcc = initAcc + dt
        if initAcc >= 3 then
            self:SetScript("OnUpdate", nil)
            Comm:BroadcastPresence()
        end
    end)
end

-- ============================================================
-- Queue management
-- ============================================================

local function RawSend(msg, dist, target)
    if C_ChatInfo and C_ChatInfo.SendAddonMessage then
        if target then
            return C_ChatInfo.SendAddonMessage(PREFIX, msg, dist, target)
        else
            return C_ChatInfo.SendAddonMessage(PREFIX, msg, dist)
        end
    end
    -- Fallback (should not be needed on TBC Classic Anniversary)
    if target then
        SendAddonMessage(PREFIX, msg, dist, target)
    else
        SendAddonMessage(PREFIX, msg, dist)
    end
    return true
end

local function Enqueue(msg, dist, target)
    if #sendQueue >= MAX_QUEUE then
        -- Drop the oldest non-WHISPER entry to make room
        for i, entry in ipairs(sendQueue) do
            if entry.dist ~= "WHISPER" then
                table.remove(sendQueue, i)
                break
            end
        end
        if #sendQueue >= MAX_QUEUE then return end  -- still full: drop
    end
    table.insert(sendQueue, { msg = msg, dist = dist, target = target })
end

-- Drain one message from the queue.
-- If the server returns false (rate-limited), put it back at the front.
function Comm:DrainQueue()
    if #sendQueue == 0 then return end
    local entry = table.remove(sendQueue, 1)
    local ok = RawSend(entry.msg, entry.dist, entry.target)
    if ok == false then
        table.insert(sendQueue, 1, entry)   -- retry next tick
    end
end

-- ============================================================
-- Channel helpers
-- ============================================================

--- Returns a set (name → true) of players already reachable via
--- GUILD / RAID / PARTY broadcasts so we can skip whispering them.
--- GetGuildRosterInfo returns "Name-Realm" on TBC Anniversary;
--- we strip the realm to match UnitName() short names.
local function BuildReachableSet()
    local set = {}

    -- Guild members covered by GUILD broadcast
    if IsInGuild() then
        local total = GetNumGuildMembers()
        for i = 1, total do
            local fullName = GetGuildRosterInfo(i)
            if fullName then
                local short = fullName:match("^([^%-]+)") or fullName
                set[short] = true
            end
        end
    end

    -- Raid members covered by RAID broadcast
    if IsInRaid() then
        local total = GetNumRaidMembers and GetNumRaidMembers() or 0
        for i = 1, total do
            local name = GetRaidRosterInfo(i)
            if name then set[name] = true end
        end
    end

    -- Party members covered by PARTY broadcast
    if GetNumPartyMembers and GetNumPartyMembers() > 0 then
        for i = 1, GetNumPartyMembers() do
            local name = UnitName("party" .. i)
            if name then set[name] = true end
        end
    end

    return set
end

--- Returns a list of active group/guild channels for the player.
local function GetAvailableChannels()
    local channels = {}
    if IsInGuild()  then table.insert(channels, "GUILD") end
    if IsInRaid()   then table.insert(channels, "RAID")  end
    if GetNumPartyMembers and GetNumPartyMembers() > 0 then
        table.insert(channels, "PARTY")
    end
    return channels
end

-- ============================================================
-- Low-level send helpers
-- ============================================================

local function QueueOne(payload, dist, target)
    Enqueue(Comm:Serialize(payload), dist, target)
end

--- Send payload to all available group/guild channels.
local function QueueGroupBroadcast(payload)
    for _, ch in ipairs(GetAvailableChannels()) do
        QueueOne(payload, ch)
    end
end

--- WHISPER payload to all known CCO players NOT already covered
--- by a group/guild channel broadcast (avoids duplicate delivery).
local function QueueTargetedWhispers(payload)
    local reachable = BuildReachableSet()
    local selfName  = UnitName("player")
    for _, info in pairs(CCO.knownPlayers) do
        local name = info.name
        if name and name ~= selfName and not reachable[name] then
            QueueOne(payload, "WHISPER", name)
        end
    end
end

--- Full broadcast: group channels + targeted whispers.
local function QueueFull(payload)
    QueueGroupBroadcast(payload)
    QueueTargetedWhispers(payload)
end

-- ============================================================
-- Public broadcast API
-- ============================================================

--- Broadcast a new / refreshed crafting order.
function Comm:BroadcastOrder(order)
    QueueFull({
        _v     = MSG_VERSION,
        _t     = MT_ORDER_POST,
        id     = order.id,
        item   = order.itemID,
        spell  = order.spellID,
        player = order.playerName,
        comm   = order.commission,
        mats   = order.matsProvided and 1 or 0,
        exp    = order.expires,
        ttl    = RELAY_TTL,   -- relay hop budget
    })
end

--- Broadcast an order cancellation.
function Comm:CancelOrder(orderID)
    QueueFull({
        _v  = MSG_VERSION,
        _t  = MT_ORDER_CANCEL,
        id  = orderID,
        ttl = RELAY_TTL,
    })
end

--- Notify the requester that their order was accepted.
--- Sent via WHISPER directly to the requester (not broadcast).
function Comm:AcceptOrder(orderID, crafterName)
    local order = CCO.OrderManager:GetOrder(orderID)
    local payload = {
        _v      = MSG_VERSION,
        _t      = MT_ORDER_ACCEPT,
        id      = orderID,
        crafter = crafterName,
    }
    if order and order.playerName then
        local targetName = order.playerName:match("^([^%-]+)")
        if targetName then
            QueueOne(payload, "WHISPER", targetName)
            return
        end
    end
    -- Fallback: broadcast (all clients filter by order ID)
    QueueGroupBroadcast(payload)
end

--- Send a presence ping via YELL + all group/guild channels.
--- Informs other CCO players of our existence so they add us
--- to their knownPlayers registry and request our active orders.
function Comm:BroadcastPresence()
    local payload = {
        _v      = MSG_VERSION,
        _t      = MT_PRESENCE,
        player  = UnitName("player") or "?",
        realm   = GetRealmName()     or "?",
    }
    -- YELL: zone-wide discovery (range-limited but reaches strangers nearby)
    QueueOne(payload, "YELL")
    -- Group/guild channels: unlimited-range discovery within memberships
    QueueGroupBroadcast(payload)
end

-- ============================================================
-- Relay logic
-- ============================================================

--- Called after processing a valid P or C message.
--- If we are a "bridge" player (in multiple channels), we forward
--- the message to channels we were NOT already listening on.
--- TTL prevents infinite relay chains.
local function MaybeRelay(rawMsg, receivedChannel, ttl)
    if not ttl or ttl <= 0 then return end              -- hop budget exhausted
    if receivedChannel == "WHISPER" then return end     -- never relay whispers
    if receivedChannel == "YELL"    then return end     -- never relay yells

    -- Parse the message, decrement TTL, re-serialise
    local ok, data = pcall(Comm.Deserialize, Comm, rawMsg)
    if not ok or type(data) ~= "table" then return end

    -- Dedup: only relay each order ID once per session
    local orderID = data.id
    if orderID and relayedIDs[orderID] then return end
    if orderID then relayedIDs[orderID] = true end

    data.ttl = ttl - 1  -- consume one hop

    local relayMsg = Comm:Serialize(data)

    -- Relay to every channel we have EXCEPT the one we received from
    for _, ch in ipairs(GetAvailableChannels()) do
        if ch ~= receivedChannel then
            Enqueue(relayMsg, ch)
        end
    end
end

-- ============================================================
-- Receive
-- ============================================================

function Comm:OnMessageReceived(rawMsg, channel, senderFull)
    -- Ignore own messages (can echo on group channels)
    local selfName   = UnitName("player")
    local senderName = (senderFull or ""):match("^([^%-]+)") or senderFull
    if senderName == selfName then return end

    local ok, data = pcall(Comm.Deserialize, Comm, rawMsg)
    if not ok or type(data) ~= "table" then return end

    -- Silently drop messages from future protocol versions
    local msgVer = tonumber(data._v) or 0
    if msgVer > MSG_VERSION then return end

    local msgType = data._t
    local ttl     = tonumber(data.ttl) or 0

    -- ── Order post ──────────────────────────────────────────
    if msgType == MT_ORDER_POST then
        CCO.OrderManager:ReceiveOrder({
            id           = data.id,
            itemID       = data.item,
            spellID      = data.spell,
            playerName   = data.player,
            commission   = data.comm,
            matsProvided = data.mats == 1,
            expires      = data.exp,
        })
        MaybeRelay(rawMsg, channel, ttl)

    -- ── Order cancel ────────────────────────────────────────
    elseif msgType == MT_ORDER_CANCEL then
        CCO.OrderManager:CancelOrder(data.id)
        MaybeRelay(rawMsg, channel, ttl)

    -- ── Order accept ────────────────────────────────────────
    elseif msgType == MT_ORDER_ACCEPT then
        CCO.OrderManager:OnOrderAccepted(data.id, data.crafter)

    -- ── Presence ping ───────────────────────────────────────
    elseif msgType == MT_PRESENCE then
        Comm:HandlePresence(data, senderFull)

    -- ── Query: someone wants our active orders ───────────────
    elseif msgType == MT_QUERY then
        Comm:HandleQuery(senderName)
    end
end

-- ============================================================
-- Presence handler: discovery + initial handshake
-- ============================================================

function Comm:HandlePresence(data, senderFull)
    local name  = data.player or (senderFull or ""):match("^([^%-]+)")
    local realm = data.realm  or GetRealmName()
    if not name or name == "" then return end

    local playerKey = name .. "-" .. realm
    local isNew     = (CCO.knownPlayers[playerKey] == nil)

    CCO.knownPlayers[playerKey] = {
        name     = name,
        realm    = realm,
        lastSeen = GetTime(),
    }

    if isNew then
        -- New CCO player found → request their active orders.
        -- Small random delay avoids thundering-herd when many players
        -- all discover each other simultaneously (e.g. on group login).
        local delay    = 2 + math.random() * 3   -- 2–5 s
        local delayFrm = CreateFrame("Frame")
        local acc       = 0
        delayFrm:SetScript("OnUpdate", function(self, dt)
            acc = acc + dt
            if acc >= delay then
                self:SetScript("OnUpdate", nil)
                QueueOne({
                    _v     = MSG_VERSION,
                    _t     = MT_QUERY,
                    player = UnitName("player") or "?",
                }, "WHISPER", name)
            end
        end)

        if CCO.db and CCO.db.char.settings.showPresenceMessages then
            CCO:Print(name .. " is online with ClassicCraftingOrders.")
        end
    else
        CCO.knownPlayers[playerKey].lastSeen = GetTime()
    end
end

-- ============================================================
-- Query handler: reply with our active orders
-- ============================================================

function Comm:HandleQuery(requesterName)
    if not requesterName or requesterName == "" then return end
    local now = GetTime()
    for _, order in pairs(CCO.OrderManager:GetMyOrders()) do
        if order.expires > now then
            -- Send each active order directly to the requester via WHISPER.
            -- ttl = 0 so the requester does NOT relay these further.
            QueueOne({
                _v     = MSG_VERSION,
                _t     = MT_ORDER_POST,
                id     = order.id,
                item   = order.itemID,
                spell  = order.spellID,
                player = order.playerName,
                comm   = order.commission,
                mats   = order.matsProvided and 1 or 0,
                exp    = order.expires,
                ttl    = 0,   -- no relay for sync replies
            }, "WHISPER", requesterName)
        end
    end
end

-- ============================================================
-- Housekeeping
-- ============================================================

--- Remove players not seen for STALE_SEC to keep registry lean.
function Comm:PruneKnownPlayers()
    local STALE_SEC = 600
    local now = GetTime()
    for key, info in pairs(CCO.knownPlayers) do
        if now - (info.lastSeen or 0) > STALE_SEC then
            CCO.knownPlayers[key] = nil
        end
    end
end

-- ============================================================
-- Serialization — character-by-character, handles all escapes
--
-- Format: key=value;key=value;…
-- Escape: \ → \\    ; → \;    = → \=
-- All values are stored as strings; numerics are auto-cast on read.
-- Max safe payload ≈ 200 chars (WoW hard limit per message: 255 bytes).
-- ============================================================

function Comm:Serialize(t)
    local parts = {}
    for k, v in pairs(t) do
        local sv = tostring(v)
            :gsub("\\", "\\\\")
            :gsub(";",  "\\;")
            :gsub("=",  "\\=")
        table.insert(parts, tostring(k) .. "=" .. sv)
    end
    return table.concat(parts, ";")
end

function Comm:Deserialize(str)
    local t   = {}
    local buf = ""
    local i   = 1
    local len = #str
    while i <= len do
        local c = str:sub(i, i)
        if c == "\\" and i < len then
            buf = buf .. str:sub(i + 1, i + 1)
            i   = i + 2
        elseif c == ";" then
            local k, v = buf:match("^([^=]+)=(.*)")
            if k then t[k] = tonumber(v) or v end
            buf = ""
            i   = i + 1
        else
            buf = buf .. c
            i   = i + 1
        end
    end
    -- trailing pair (no trailing semicolon)
    if buf ~= "" then
        local k, v = buf:match("^([^=]+)=(.*)")
        if k then t[k] = tonumber(v) or v end
    end
    return t
end
