--[[ $Id: CallbackHandler-1.0.lua 3 2008-09-29 16:54:20Z mikk $ ]]
-- Minimal stub: full version should be obtained from CurseForge/WowAce.
-- This file exists so the TOC loads without error. Replace with the full
-- CallbackHandler-1.0 library from https://www.curseforge.com/wow/addons/callbackhandler

local MAJOR, MINOR = "CallbackHandler-1.0", 6
local CallbackHandler = LibStub:NewLibrary(MAJOR, MINOR)
if not CallbackHandler then return end -- No upgrade needed

local meta = {__index = function(tbl, key) rawset(tbl, key, {}) return tbl[key] end}

function CallbackHandler:New(target, RegisterName, UnregisterName, UnregisterAllName)
    RegisterName    = RegisterName    or "RegisterCallback"
    UnregisterName  = UnregisterName  or "UnregisterCallback"
    UnregisterAllName = UnregisterAllName or "UnregisterAllCallbacks"

    local events = setmetatable({}, meta)

    target[RegisterName] = function(self, event, method, ...)
        assert(type(event) == "string", "Bad argument #2 (string expected)")
        local regfunc
        if type(method) == "string" then
            regfunc = function(...) self[method](self, ...) end
        elseif type(method) == "function" then
            regfunc = method
        else
            error("Usage: RegisterCallback(event, methodname|func[, ...])", 2)
        end
        events[event][self] = regfunc
    end

    target[UnregisterName] = function(self, event)
        if events[event] then
            events[event][self] = nil
        end
    end

    target[UnregisterAllName] = function(self)
        for _, handlers in pairs(events) do
            handlers[self] = nil
        end
    end

    local function fire(event, ...)
        if events[event] then
            for _, fn in pairs(events[event]) do
                pcall(fn, event, ...)
            end
        end
    end

    return events, fire
end
