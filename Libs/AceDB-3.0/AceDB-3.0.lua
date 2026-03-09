--[[
AceDB-3.0 - Minimal stub for ClassicCraftingOrders
Full version: https://www.curseforge.com/wow/addons/acedb-3-0

This stub is provided so the addon compiles without the full AceDB library.
Replace this file with the official AceDB-3.0 release for production use.
--]]

local MAJOR, MINOR = "AceDB-3.0", 27
local AceDB, oldminor = LibStub:NewLibrary(MAJOR, MINOR)
if not AceDB then return end

local defaultProto = {}
local AceDBObject = {}

--- Create or load a new database object.
-- @param sv       string  Name of the SavedVariables global
-- @param defaults table   Default values table with `global` and `char` keys
-- @param charKey  boolean If true, use a per-character profile
function AceDB:New(sv, defaults, charKey)
    -- Ensure the SavedVariables table exists
    _G[sv] = _G[sv] or {}
    local db = _G[sv]

    -- Initialise global section
    db.global = db.global or {}
    if defaults and defaults.global then
        for k, v in pairs(defaults.global) do
            if db.global[k] == nil then
                -- Deep copy table defaults
                if type(v) == "table" then
                    local copy = {}
                    for dk, dv in pairs(v) do copy[dk] = dv end
                    db.global[k] = copy
                else
                    db.global[k] = v
                end
            end
        end
    end

    -- Initialise per-character section
    local charKeyName = UnitName("player") .. "-" .. GetRealmName()
    db.char = db.char or {}
    db.char[charKeyName] = db.char[charKeyName] or {}
    local charDB = db.char[charKeyName]

    if defaults and defaults.char then
        for k, v in pairs(defaults.char) do
            if charDB[k] == nil then
                if type(v) == "table" then
                    local copy = {}
                    for dk, dv in pairs(v) do copy[dk] = dv end
                    charDB[k] = copy
                else
                    charDB[k] = v
                end
            end
        end
    end

    -- Return a unified proxy object
    local obj = setmetatable({}, {
        __index = function(t, k)
            if k == "global" then return db.global
            elseif k == "char" then return charDB
            end
        end,
        __newindex = function(t, k, v)
            if k == "global" then db.global = v
            elseif k == "char" then db.char[charKeyName] = v
            end
        end,
    })

    return obj
end
