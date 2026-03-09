-- ============================================================
-- ClassicCraftingOrders - Trade Assistant
-- Hooks into the trade window to help place reagents and
-- highlight required bag items for an active order.
-- ============================================================
local ADDON_NAME, CCO = ...

CCO.TradeAssistant = {}
local TA = CCO.TradeAssistant

-- ============================================================
-- Constants
-- ============================================================
local MAX_TRADE_SLOTS = 6
local GLOW_TEXTURE    = "Interface\\Buttons\\ButtonHilight-Square"

-- ============================================================
-- State
-- ============================================================
TA.currentOrder  = nil   -- The active order being traded
TA.glowFrames    = {}    -- Bag-slot glow overlays keyed by slotKey

-- ============================================================
-- Initialise
-- ============================================================
function TA:Initialize()
    local f = CreateFrame("Frame")
    f:RegisterEvent("TRADE_SHOW")
    f:RegisterEvent("TRADE_CLOSED")
    f:RegisterEvent("TRADE_PLAYER_ITEM_CHANGED")
    f:RegisterEvent("BAG_UPDATE")

    f:SetScript("OnEvent", function(_, event, ...)
        if     event == "TRADE_SHOW"                 then TA:OnTradeShow()
        elseif event == "TRADE_CLOSED"               then TA:OnTradeClosed()
        elseif event == "TRADE_PLAYER_ITEM_CHANGED"  then TA:OnTradeItemChanged(...)
        elseif event == "BAG_UPDATE"                 then TA:OnBagUpdate()
        end
    end)
end

-- ============================================================
-- Trade events
-- ============================================================

function TA:OnTradeShow()
    -- Determine if we are trading with someone related to an active order
    local tradeTarget = UnitName("NPC")  -- "NPC" frame holds the trade target name
    if not tradeTarget then return end

    -- Look for an order that involves this player
    TA.currentOrder = TA:FindOrderForPlayer(tradeTarget)
    if not TA.currentOrder then return end

    -- Show the trade helper overlay
    TA:ShowTradeHelper()
end

function TA:OnTradeClosed()
    TA:HideTradeHelper()
    TA:ClearBagGlows()
    TA.currentOrder = nil
end

function TA:OnTradeItemChanged()
    if TA.currentOrder then
        TA:UpdateTradeHelper()
    end
end

function TA:OnBagUpdate()
    if TA.currentOrder then
        TA:HighlightReagentsInBags(TA.currentOrder)
    end
end

-- ============================================================
-- Find order linked to a specific player name
-- ============================================================
function TA:FindOrderForPlayer(playerName)
    for _, order in pairs(CCO.OrderManager:GetAllOrders()) do
        local requester = order.playerName:match("^([^%-]+)")
        local crafter   = order.crafterName and order.crafterName:match("^([^%-]+)")
        if requester == playerName or crafter == playerName then
            return order
        end
    end
    return nil
end

-- ============================================================
-- Trade helper UI (overlay on TradeFrame)
-- ============================================================
function TA:ShowTradeHelper()
    if not TA.helperFrame then
        TA:CreateHelperFrame()
    end

    local order = TA.currentOrder
    if not order then return end

    -- Update labels
    local itemName = GetItemInfo(order.itemID) or ("Item #" .. order.itemID)
    TA.helperFrame.titleText:SetText(CCO.L["TRADE_HELPER_TITLE"])
    TA.helperFrame.infoText:SetText(itemName .. "\n" .. CCO:FormatGold(order.commission))
    TA.helperFrame:Show()

    -- Highlight reagents in bags
    TA:HighlightReagentsInBags(order)
end

function TA:HideTradeHelper()
    if TA.helperFrame then
        TA.helperFrame:Hide()
    end
end

function TA:UpdateTradeHelper()
    -- Check if all required items are already in the trade window
    if not TA.currentOrder then return end
    local filled = TA:CountFilledTradeSlots()
    if filled > 0 then
        TA.helperFrame.autoFillBtn:SetText(CCO.L["TRADE_AUTOFILL_DONE"])
        TA.helperFrame.autoFillBtn:Disable()
    else
        TA.helperFrame.autoFillBtn:SetText(CCO.L["TRADE_AUTOFILL_BTN"])
        TA.helperFrame.autoFillBtn:Enable()
    end
end

-- ============================================================
-- Auto-fill logic
-- ============================================================

--- Attempt to place required reagents into the trade window.
function TA:AutoFillTrade()
    local order = TA.currentOrder
    if not order then return end

    -- Build a list of required reagents for this spell
    local reagents = TA:GetReagentsForSpell(order.spellID)
    if not reagents or #reagents == 0 then
        CCO:PrintError(CCO.L["ERR_RECIPE_NOT_FOUND"])
        return
    end

    local slot     = 1
    local allFound = true

    for _, reagent in ipairs(reagents) do
        if slot > MAX_TRADE_SLOTS then break end
        local bagSlot, bagID = TA:FindItemInBags(reagent.itemID, reagent.count)
        if bagSlot then
            -- PickupContainerItem then drop into trade slot
            PickupContainerItem(bagID, bagSlot)
            ClickTradeButton(slot)
            slot = slot + 1
        else
            allFound = false
        end
    end

    if allFound then
        CCO:Print(CCO.L["TRADE_AUTOFILL_DONE"])
    else
        CCO:Print(CCO.L["TRADE_AUTOFILL_FAIL"])
    end
end

-- ============================================================
-- Bag-item highlighting (glow overlay)
-- ============================================================

function TA:HighlightReagentsInBags(order)
    TA:ClearBagGlows()
    if not order or not order.spellID then return end

    local reagents = TA:GetReagentsForSpell(order.spellID)
    if not reagents then return end

    for _, reagent in ipairs(reagents) do
        local bag, slot = TA:FindItemInBags(reagent.itemID, 1)
        if bag and slot then
            TA:AddBagGlow(bag, slot)
        end
    end
end

function TA:AddBagGlow(bag, slot)
    local key = bag .. "_" .. slot
    if TA.glowFrames[key] then return end

    -- Find the bag button frame
    local buttonName = "ContainerFrame" .. (bag + 1) .. "Item" .. (MAX_CONTAINER_ITEMS - slot + 1)
    local button = _G[buttonName]
    if not button then return end

    local glow = CreateFrame("Frame", nil, button)
    glow:SetAllPoints(button)
    glow:SetFrameLevel(button:GetFrameLevel() + 5)
    local tex = glow:CreateTexture(nil, "OVERLAY")
    tex:SetTexture(GLOW_TEXTURE)
    tex:SetBlendMode("ADD")
    tex:SetAllPoints(glow)
    tex:SetVertexColor(0, 1, 0.5, 0.8)   -- Green-teal glow

    -- Pulsing animation
    local ag   = tex:CreateAnimationGroup()
    local anim = ag:CreateAnimation("Alpha")
    anim:SetFromAlpha(0.3)
    anim:SetToAlpha(1.0)
    anim:SetDuration(0.8)
    anim:SetSmoothing("IN_OUT")
    ag:SetLooping("BOUNCE")
    ag:Play()

    glow.tex = tex
    glow.ag  = ag
    TA.glowFrames[key] = glow
end

function TA:ClearBagGlows()
    for key, glow in pairs(TA.glowFrames) do
        if glow.ag then glow.ag:Stop() end
        glow:Hide()
        glow:SetParent(nil)
        TA.glowFrames[key] = nil
    end
end

-- ============================================================
-- Spell / reagent helpers
-- ============================================================

--- Returns a list of {itemID, count} tables for a given spell.
function TA:GetReagentsForSpell(spellID)
    -- GetTradeSkillReagentInfo is available in Classic APIs
    -- We need to find the index of this spell in the tradeskill list first
    local reagents = {}
    local numSkills = GetNumTradeSkills()
    for i = 1, numSkills do
        local _, skillType, _, _, _, spellIDFound = GetTradeSkillInfo(i)
        if spellIDFound == spellID or skillType ~= "header" then
            -- Try index-based match
            local numReagents = GetTradeSkillNumReagents(i)
            if numReagents and numReagents > 0 then
                for r = 1, numReagents do
                    local rName, _, rCount = GetTradeSkillReagentInfo(i, r)
                    if rName then
                        -- NOTE: GetItemInfoInstant does NOT exist in TBC Classic (added in MoP).
                        --       Use GetTradeSkillReagentItemLink to resolve item IDs instead.
                        local rLink = GetTradeSkillReagentItemLink(i, r)
                        local rID = rLink and tonumber(rLink:match("|Hitem:(%d+):")) or nil
                        if rID then
                            table.insert(reagents, { itemID = rID, count = rCount or 1, name = rName })
                        end
                    end
                end
                break
            end
        end
    end
    return reagents
end

--- Scan bags for at least `count` units of `itemID`.
-- @return bag index, slot index, or nil
function TA:FindItemInBags(itemID, count)
    count = count or 1
    for bag = 0, NUM_BAG_SLOTS do
        for slot = 1, GetContainerNumSlots(bag) do
            local id = GetContainerItemID(bag, slot)
            if id == itemID then
                local _, stackCount = GetContainerItemInfo(bag, slot)
                if (stackCount or 0) >= count then
                    return bag, slot
                end
            end
        end
    end
    return nil, nil
end

--- Count how many trade slots are currently filled by the player.
function TA:CountFilledTradeSlots()
    local n = 0
    for slot = 1, MAX_TRADE_SLOTS do
        local name = GetTradePlayerItemInfo(slot)
        if name then n = n + 1 end
    end
    return n
end

-- ============================================================
-- Helper frame creation
-- ============================================================
function TA:CreateHelperFrame()
    local f = CreateFrame("Frame", "CCO_TradeHelper", TradeFrame)
    f:SetSize(220, 100)
    f:SetPoint("TOPRIGHT", TradeFrame, "TOPLEFT", -5, 0)
    f:SetBackdrop({
        bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile     = true, tileSize = 32, edgeSize = 16,
        insets   = { left=5, right=5, top=5, bottom=5 }
    })
    f:SetBackdropColor(0, 0, 0, 0.85)

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", f, "TOP", 0, -8)
    f.titleText = title

    local info = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    info:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -24)
    info:SetWidth(200)
    info:SetJustifyH("LEFT")
    f.infoText = info

    local btn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    btn:SetSize(160, 22)
    btn:SetPoint("BOTTOM", f, "BOTTOM", 0, 8)
    btn:SetText(CCO.L["TRADE_AUTOFILL_BTN"])
    btn:SetScript("OnClick", function() TA:AutoFillTrade() end)
    f.autoFillBtn = btn

    f:Hide()
    TA.helperFrame = f
end
