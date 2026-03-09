-- ============================================================
-- ClassicCraftingOrders - Main Entry Point
-- WoW TBC Classic Anniversary Edition
-- ============================================================

local ADDON_NAME, CCO = ...

-- Addon-wide namespace
_G["CCO"] = CCO
CCO.version = "1.0.0"
CCO.prefix  = "CCO_ORDERS"   -- RegisterAddonMessagePrefix key (max 16 chars)

-- ============================================================
-- Bootstrap: fired once all files are loaded
-- ============================================================
local bootstrapFrame = CreateFrame("Frame")
bootstrapFrame:RegisterEvent("ADDON_LOADED")
bootstrapFrame:RegisterEvent("PLAYER_LOGIN")
bootstrapFrame:RegisterEvent("PLAYER_LOGOUT")

bootstrapFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
        -- Initialize database FIRST so other modules can read defaults
        CCO.Database:Initialize()
        -- Register the hidden communication channel prefix
        C_ChatInfo.RegisterAddonMessagePrefix(CCO.prefix)
        CCO:Print(CCO.L["ADDON_LOADED_MSG"])

    elseif event == "PLAYER_LOGIN" then
        -- All sub-systems are ready; build UI and start listening
        CCO.Communication:Initialize()
        CCO.OrderManager:Initialize()
        -- RecipeScanner must init before UI so it can respond to tradeskill events
        CCO.RecipeScanner:Initialize()
        CCO.TradeAssistant:Initialize()
        CCO.UI.Dashboard:Initialize()
        CCO.UI.RecipeBrowser:Initialize()
        CCO.UI.OrderBoard:Initialize()
        CCO.UI.StatusMonitor:Initialize()
        -- Announce presence to nearby addon users
        CCO.Communication:AnnouncePresence()

    elseif event == "PLAYER_LOGOUT" then
        CCO.Database:Save()
    end
end)

-- ============================================================
-- Slash Commands
-- ============================================================
SLASH_CLASSICRAFTINGORDERS1 = "/cco"
SLASH_CLASSICRAFTINGORDERS2 = "/craftingorders"

SlashCmdList["CLASSICRAFTINGORDERS"] = function(msg)
    local cmd = strtrim(msg):lower()
    if cmd == "" or cmd == "show" then
        CCO.UI.Dashboard:Toggle()
    elseif cmd == "orders" then
        CCO.UI.OrderBoard:Toggle()
    elseif cmd == "help" then
        CCO:PrintHelp()
    elseif cmd == "reset" then
        CCO.UI.Dashboard:ResetPosition()
        CCO:Print(CCO.L["UI_RESET"])
    else
        CCO:Print(CCO.L["UNKNOWN_COMMAND"]:format(msg))
    end
end

-- ============================================================
-- Utility helpers
-- ============================================================

--- Print a message to the default chat frame with the addon prefix.
function CCO:Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ccff[CCO]|r " .. tostring(msg))
end

--- Print an error message.
function CCO:PrintError(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cffff3333[CCO Error]|r " .. tostring(msg))
end

--- Print the help text.
function CCO:PrintHelp()
    CCO:Print("|cffffd700" .. CCO.L["HELP_HEADER"] .. "|r")
    CCO:Print("|cff88ff88/cco|r - " .. CCO.L["HELP_SHOW"])
    CCO:Print("|cff88ff88/cco orders|r - " .. CCO.L["HELP_ORDERS"])
    CCO:Print("|cff88ff88/cco reset|r - " .. CCO.L["HELP_RESET"])
    CCO:Print("|cff88ff88/cco help|r - " .. CCO.L["HELP_HELP"])
end

--- Shallow-copy a table.
function CCO:CopyTable(t)
    local copy = {}
    for k, v in pairs(t) do copy[k] = v end
    return copy
end

--- Format gold amount (copper integer) into "Xg Ys Zc" string.
function CCO:FormatGold(copper)
    if not copper or copper < 0 then return "0c" end
    local g = math.floor(copper / 10000)
    local s = math.floor((copper % 10000) / 100)
    local c = copper % 100
    local result = ""
    if g > 0 then result = result .. "|cffffd700" .. g .. "g|r " end
    if s > 0 then result = result .. "|cffc0c0c0" .. s .. "s|r " end
    if c > 0 or result == "" then result = result .. "|ffcd7f32" .. c .. "c|r" end
    return strtrim(result)
end

--- Returns true if the player knows a given spell ID (recipe check).
function CCO:IsRecipeKnown(spellID)
    -- GetSpellInfo returns nil for unknown spells in Classic APIs
    return GetSpellInfo(spellID) ~= nil and IsSpellKnown(spellID)
end

--- Returns the player's name with realm, used as unique identifier.
function CCO:GetPlayerKey()
    return UnitName("player") .. "-" .. GetRealmName()
end
