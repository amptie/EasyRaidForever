-- =============================================================================
-- EasyRaidForever - UI/LootMaster/TradeHelper.lua
--
-- Loot master helper for items that were awarded but not handed over by
-- master loot (Forever lets the loot master collect loot for ~2 hours and
-- hand it out later by trade):
--
--  * When a trade window opens with a player who is owed items, a small panel
--    next to it lists them with "Put in trade" (or "All").
--  * When the trade completes, every owed item that left the bags is marked
--    as traded (Loot.items entry.traded, persisted into the session).
--
-- Detection without combat log: item counts in the bags (C_Item.GetItemCount)
-- before and after the trade, confirmed by ERR_TRADE_COMPLETE (UI_INFO_MESSAGE)
-- or, as a fallback, checked a moment after TRADE_CLOSED.
-- =============================================================================

local ADDON_NAME, ERF = ...
local L = ERF.L
local Util = ERF.Util
local C = Util.COLORS
local W = ERF.Widgets

local TradeHelper = {}
ERF.TradeHelper = TradeHelper

local MAX_TRADE_SLOTS = 6        -- slot 7 is "will not be traded"
local partner                    -- name of the trade partner
local before = {}                -- [itemId] = count in bags when the trade opened
local frame, rows = nil, {}

local function Count(itemId)
    if not (C_Item and C_Item.GetItemCount) then return 0 end
    local ok, n = pcall(C_Item.GetItemCount, itemId, false)
    return ok and tonumber(n) or 0
end

-- First bag slot holding `itemId` that is not locked (already in trade).
local function FindInBags(itemId)
    if not C_Container then return nil end
    for bag = 0, (NUM_BAG_SLOTS or 4) do
        for slot = 1, (C_Container.GetContainerNumSlots(bag) or 0) do
            if C_Container.GetContainerItemID(bag, slot) == itemId then
                local info = C_Container.GetContainerItemInfo(bag, slot)
                if not (info and info.isLocked) then return bag, slot end
            end
        end
    end
    return nil
end

local function FreeTradeSlot()
    if type(GetTradePlayerItemLink) ~= "function" then return 1 end
    for i = 1, MAX_TRADE_SLOTS do
        if not GetTradePlayerItemLink(i) then return i end
    end
    return nil
end

-- Items currently offered by us: { [itemId] = true }
local function Offered()
    local set = {}
    if type(GetTradePlayerItemLink) ~= "function" then return set end
    for i = 1, MAX_TRADE_SLOTS do
        local link = GetTradePlayerItemLink(i)
        local id = link and tonumber(string.match(link, "item:(%d+)"))
        if id then set[id] = true end
    end
    return set
end

function TradeHelper:Owed()
    if not partner then return {} end
    return ERF.Loot:OwedTo(partner)
end

-- Puts one owed item into the trade window. ok, reason
function TradeHelper:Put(entry)
    if InCombatLockdown() then return false, L["Not possible in combat."] end
    if type(ClickTradeButton) ~= "function" then return false, L["Not available on this client."] end
    local tradeSlot = FreeTradeSlot()
    if not tradeSlot then return false, L["The trade window is full."] end
    local bag, slot = FindInBags(entry.itemId)
    if not bag then return false, L["Item not found in your bags."] end
    ClearCursor()
    C_Container.PickupContainerItem(bag, slot)
    ClickTradeButton(tradeSlot)
    ClearCursor()
    return true
end

function TradeHelper:PutAll()
    local offered = Offered()
    for _, e in ipairs(self:Owed()) do
        if not offered[e.itemId] then
            local ok, why = self:Put(e)
            if not ok then return W.Report(false, why) end
        end
    end
end

-- Marks owed items whose bag count dropped as traded.
function TradeHelper:Settle()
    if not partner then return 0 end
    local marked = 0
    local dropped = {}
    for itemId, n in pairs(before) do dropped[itemId] = n - Count(itemId) end
    for _, e in ipairs(ERF.Loot:OwedTo(partner)) do
        if (dropped[e.itemId] or 0) > 0 then
            dropped[e.itemId] = dropped[e.itemId] - 1
            e.traded = true
            marked = marked + 1
            local _, link = C_Item.GetItemInfo(e.itemId)
            Util.Print(L["%s handed over to %s."], link or ("item:" .. e.itemId), Util.ShortName(partner))
        end
    end
    -- Settle runs on ERR_TRADE_COMPLETE and again after TRADE_CLOSED.
    for itemId in pairs(before) do before[itemId] = Count(itemId) end
    if marked > 0 then ERF:Notify("LOOTMASTER") end
    return marked
end

-- ---------------------------------------------------------------------------
-- Panel
-- ---------------------------------------------------------------------------
local function Build()
    frame = W.Frame("Frame", "EasyRaidForeverTradeHelper", UIParent)
    frame:SetSize(250, 60)
    frame:SetFrameStrata("DIALOG")
    W.StyleWindow(frame)
    frame:Hide()
    frame.title = W.CreateLabel(frame, "", "normal", C.GOLD)
    frame.title:SetPoint("TOPLEFT", 10, -8)
    frame.title:SetPoint("RIGHT", frame, "RIGHT", -10, 0)
    frame.all = W.CreateButton(frame, L["Put all in trade"], 230, 22, function() TradeHelper:PutAll() end)
    frame.all:SetPoint("BOTTOM", 0, 8)
    W.MakePrimary(frame.all)
end

local function Row(i)
    if rows[i] then return rows[i] end
    local row = CreateFrame("Button", nil, frame)
    row:SetSize(230, 20)
    row:SetPoint("TOPLEFT", 10, -28 - (i - 1) * 22)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(18, 18)
    row.icon:SetPoint("LEFT")
    row.text = W.CreateLabel(row, "", "small")
    row.text:SetPoint("LEFT", row.icon, "RIGHT", 5, 0)
    row.text:SetPoint("RIGHT", row, "RIGHT", -70, 0)
    row.text:SetWordWrap(false)
    row.btn = W.CreateButton(row, L["Put in"], 62, 18, function()
        if row.entry then W.Report(TradeHelper:Put(row.entry)) end
    end)
    row.btn:SetPoint("RIGHT")
    row:SetScript("OnEnter", function(self) if self.entry then W.ItemTooltip(self, self.entry.itemId) end end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    rows[i] = row
    return row
end

function TradeHelper:Refresh()
    local owed = self:Owed()
    if not partner or #owed == 0 then
        if frame then frame:Hide() end
        return
    end
    if not frame then Build() end
    local offered = Offered()
    frame.title:SetText(string.format(L["Owed to %s"], Util.ShortName(partner)))
    for i, e in ipairs(owed) do
        local row = Row(i)
        row.entry = e
        local _, colored, icon = W.Item(e.itemId)
        row.icon:SetTexture(icon)
        row.text:SetText(colored .. " |cff8c94a6(" .. (e.awardedKind or "") .. ")|r")
        row.btn:SetAllowed(not offered[e.itemId], L["Already in the trade window."])
        row:Show()
    end
    for i = #owed + 1, #rows do rows[i]:Hide(); rows[i].entry = nil end
    frame:SetHeight(28 + #owed * 22 + 36)
    frame:ClearAllPoints()
    if TradeFrame and TradeFrame:IsShown() then
        frame:SetPoint("TOPLEFT", TradeFrame, "TOPRIGHT", 6, 0)
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", 300, 0)
    end
    frame:Show()
end

-- ---------------------------------------------------------------------------
-- Events
-- ---------------------------------------------------------------------------
local function OnShow()
    partner = nil
    wipe(before)
    local ev = ERF.Raid:Current()
    if not ev or ev.leader ~= ERF.playerName then return end
    local name = Util.UnitID("NPC")
    if not name then return end
    partner = name
    for _, e in ipairs(ERF.Loot:OwedTo(name)) do before[e.itemId] = Count(e.itemId) end
    TradeHelper:Refresh()
end

local function OnClosed()
    if frame then frame:Hide() end
    if not partner then return end
    -- The bags update a moment after the window closes.
    C_Timer.After(1, function()
        Util.Guard(function()
            TradeHelper:Settle()
            partner = nil
            wipe(before)
        end, "TradeHelper.closed")
    end)
end

function TradeHelper:Init()
    ERF:RegisterEventHandler("TRADE_SHOW", OnShow)
    ERF:RegisterEventHandler("TRADE_CLOSED", OnClosed)
    ERF:RegisterEventHandler("TRADE_PLAYER_ITEM_CHANGED", function()
        if partner then TradeHelper:Refresh() end
    end)
    ERF:RegisterEventHandler("UI_INFO_MESSAGE", function(_, _, message)
        if partner and ERR_TRADE_COMPLETE and message == ERR_TRADE_COMPLETE then
            C_Timer.After(0.5, function() Util.Guard(function() TradeHelper:Settle() end, "TradeHelper.complete") end)
        end
    end)
    ERF:OnChanged("TradeHelper", function(topic)
        if topic == "LOOTMASTER" and partner then TradeHelper:Refresh() end
    end)
end
