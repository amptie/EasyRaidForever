-- =============================================================================
-- EasyRaidForever - UI/LootMaster/LootMasterWindow.lua
--
-- The loot master console (only for the player who imported the raid).
-- Left: every item of the opened corpses / bags (and items added by hand) with
-- its state. Right: the selected item - who reserved it (with SR+ bonus), the
-- live ranking with spec, and the actions: start / close / extend / cancel a
-- roll, reroll a tie, award to the winner or to anybody.
--
-- "Roll all" starts every waiting item at once - with the normal roll time or
-- a long timer (2 / 5 / 10 min) for loot collected over the evening (Forever:
-- loot stays tradeable for ~2 hours). "Award decided" hands out every finished
-- roll at once; items not handed over by master loot are marked "trade" until
-- the trade helper sees them leave the bags.
-- =============================================================================

local ADDON_NAME, ERF = ...
local L = ERF.L
local Util = ERF.Util
local C = Util.COLORS
local W = ERF.Widgets

local LM = {}
ERF.LootMasterWindow = LM

local ITEM_COLS = {
    { text = "", width = 26 },
    { text = L["Item"], width = "*" },
    { text = L["Status"], width = 110 },
}
local RANK_COLS = {
    { text = L["Player"], width = "*" },
    { text = L["Choice"], width = 55 },
    { text = L["Spec"], width = 90 },
    { text = L["Roll"], width = 45, justify = "RIGHT" },
    { text = L["Bonus"], width = 50, justify = "RIGHT" },
    { text = L["Total"], width = 50, justify = "RIGHT" },
}

local P = {}
local selected
local filter = "ALL"

local FILTERS = { "ALL", "OPEN", "DECIDED", "TRADE", "DONE" }
local FILTER_NAMES = {
    ALL = L["All items"], OPEN = L["Waiting / rolling"], DECIDED = L["Decided"],
    TRADE = L["To be traded"], DONE = L["Handed over"],
}

local function Matches(e)
    if filter == "OPEN" then return e.state == "NEW" or e.state == "ROLLING" end
    if filter == "DECIDED" then return e.state == "DECIDED" end
    if filter == "TRADE" then return e.state == "AWARDED" and e.trade and not e.traded end
    if filter == "DONE" then return e.state == "AWARDED" and (not e.trade or e.traded) end
    return true
end

local function RollOf(entry)
    return entry and entry.rollId and ERF.Rolls.active[entry.rollId] or nil
end

local function EntryStatus(entry)
    local roll = RollOf(entry)
    if entry.state == "AWARDED" then
        local s = Util.CHAT_GREEN .. string.format(L["-> %s"], Util.ShortName(entry.awardedTo)) .. "|r"
        if entry.trade and not entry.traded then s = s .. " |cffe8c46b" .. L["(trade)"] .. "|r" end
        return s
    end
    if entry.state == "ROLLING" and roll then
        return string.format(L["rolling %s"], ERF.UI.DurationText(math.max(0, math.floor(roll.endsAt - GetTime()))))
    end
    if entry.state == "DECIDED" then
        if entry.tie then return Util.CHAT_GOLD .. L["Tie"] .. "|r" end
        if entry.winner then return Util.ShortName(entry.winner.name) end
        return "|cff8c94a6" .. L["no rolls"] .. "|r"
    end
    return "|cff8c94a6" .. L["waiting"] .. "|r"
end

local function KindOf(roll, option)
    if roll and roll.sr then return "SR" end
    return ERF.Raid:LootKind(option)
end

-- ---------------------------------------------------------------------------
-- Actions
-- ---------------------------------------------------------------------------
local function StartRoll(entry)
    local _, why = ERF.Rolls:Start(entry)
    if why then W.Report(false, why) end
    LM:Refresh()
end

local function RollAll(duration)
    local started, failed = 0, nil
    for _, e in ipairs(ERF.Loot.items) do
        if e.state == "NEW" then
            local roll, why = ERF.Rolls:Start(e, nil, duration)
            if roll then started = started + 1 else failed = failed or why end
        end
    end
    Util.Print(L["%d roll(s) started."], started)
    if failed then Util.Print(Util.CHAT_RED .. "%s|r", failed) end
    LM:Refresh()
end

local function RollAllMenu(anchor)
    local normal = ERF.db.options.rollDuration or 30
    local items = { { value = 0, text = string.format(L["Normal roll time (%s)"], ERF.UI.DurationText(normal)) } }
    for _, s in ipairs({ 120, 300, 600 }) do
        items[#items + 1] = { value = s, text = ERF.UI.DurationText(s) }
    end
    W.ShowMenu(anchor, items, function(value) RollAll(value > 0 and value or nil) end, 180)
end

-- Awards every decided item (clear winner) in one go.
local function AwardDecided()
    local list = {}
    for _, e in ipairs(ERF.Loot.items) do
        if e.state == "DECIDED" and e.winner and not e.tie then list[#list + 1] = e end
    end
    if #list == 0 then return W.Report(false, L["No decided item with a clear winner."]) end
    W.Confirm(string.format(L["Award %d decided item(s) to their winners?"], #list), function()
        for _, e in ipairs(list) do
            local w = e.winner
            ERF.Loot:Award(e, w.name, KindOf(RollOf(e), w.o), w.sp, w.total)
        end
        LM:Refresh()
    end)
end

local function AddItem()
    W.Prompt(L["Item IDs or shift-clicked item links (several possible):"], "", function(text)
        local ids = ERF.Raid:ParseItemIds(text)
        if #ids == 0 then return W.Report(false, L["No item found in the text."]) end
        for _, id in ipairs(ids) do
            local entry, why = ERF.Loot:AddItem(id)
            if not entry then return W.Report(false, why) end
            selected = selected or entry
        end
        LM:Refresh()
    end)
end

local function DoAward(entry, player, kind, spec, total)
    local _, colored = W.Item(entry.itemId)
    W.Confirm(string.format(L["Award %s to %s (%s)?"], colored, Util.ShortName(player), kind), function()
        W.Report(ERF.Loot:Award(entry, player, kind, spec, total))
        LM:Refresh()
    end)
end

local function AwardWinner()
    local entry = selected
    local w = entry and entry.winner
    if not w then return W.Report(false, L["There is no winner yet."]) end
    DoAward(entry, w.name, KindOf(RollOf(entry), w.o), w.sp, w.total)
end

local function AwardToMenu(anchor)
    local entry = selected
    if not entry then return end
    local items = {}
    for _, r in ipairs((Util.GroupRoster())) do
        items[#items + 1] = { value = r.name, text = Util.ClassName(r.name, r.class) }
    end
    table.sort(items, function(a, b) return a.value < b.value end)
    W.ShowMenu(anchor, items, function(player)
        local kinds = {}
        for _, k in ipairs(ERF.Raid.LOOT_KINDS) do kinds[#kinds + 1] = { value = k, text = ERF.Raid.LOOT_KIND_NAMES[k] } end
        W.ShowContextMenu(kinds, function(kind)
            DoAward(entry, player, kind, ERF.Raid:SpecFor(player, kind), nil)
        end, 140)
    end, 200)
end

-- ---------------------------------------------------------------------------
-- Build
-- ---------------------------------------------------------------------------
function LM:Build()
    if self.win then return end
    local win = W.CreateWindow("EasyRaidForeverLootMaster", L["Loot master"], 820, 500)
    self.win = win
    local b = win.Body

    -- Left: item list.
    local left = W.CreatePanel(b)
    left:SetPoint("TOPLEFT", 0, 0)
    left:SetPoint("BOTTOMLEFT", 0, 0)
    left:SetWidth(340)
    P.add = W.CreateButton(left, L["Add item..."], 104, 22, AddItem)
    P.add:SetPoint("TOPLEFT", 6, -6)
    P.rollAll = W.CreateButton(left, L["Roll all..."], 104, 22, function(self) RollAllMenu(self) end)
    P.rollAll:SetPoint("LEFT", P.add, "RIGHT", 6, 0)
    P.rollAll.tooltipText = L["Starts a roll for every waiting item. Choose a long timer when you collected the loot of several bosses."]
    W.MakePrimary(P.rollAll)
    P.awardAll = W.CreateButton(left, L["Award decided"], 104, 22, AwardDecided)
    P.awardAll:SetPoint("LEFT", P.rollAll, "RIGHT", 6, 0)
    P.filter = W.CreateDropdown(left, 214, function()
        local items = {}
        for _, f in ipairs(FILTERS) do items[#items + 1] = { value = f, text = FILTER_NAMES[f] } end
        return items
    end, function(value)
        filter = value
        LM:Refresh()
    end)
    P.filter:SetPoint("TOPLEFT", P.add, "BOTTOMLEFT", 0, -6)
    P.clear = W.CreateButton(left, L["Clear done"], 104, 22, function() ERF.Loot:ClearAwarded() LM:Refresh() end)
    P.clear:SetPoint("LEFT", P.filter, "RIGHT", 6, 0)
    P.clear.tooltipText = L["Removes awarded items from the list (items still to be traded stay)."]
    local ih = W.CreateHeaderRow(left, ITEM_COLS)
    ih:SetPoint("TOPLEFT", 6, -62)
    ih:SetPoint("RIGHT", left, "RIGHT", -6, 0)
    P.items = W.CreateScrollList(left, {
        rowHeight = 26,
        createRow = function(list)
            local row = W.ColumnRowFactory(ITEM_COLS)(list)
            row.icon = row:CreateTexture(nil, "ARTWORK")
            row.icon:SetSize(22, 22)
            row.icon:SetPoint("LEFT", 3, 0)
            return row
        end,
        updateRow = function(row, e)
            local _, colored, icon = W.Item(e.itemId)
            row.icon:SetTexture(icon)
            local who = ERF.Raid:Reservers()[e.itemId]
            local src = (e.src == "BAGS" or e.inBags) and (" |cff8c94a6" .. L["[bags]"] .. "|r") or ""
            row.cols[2]:SetText(colored .. (who and (" |cffe8c46b(SR " .. #who .. ")|r") or "") .. src)
            row.cols[3]:SetText(EntryStatus(e))
        end,
        isSelected = function(e) return e == selected end,
        onClick = function(_, e, button)
            selected = e
            if button == "RightButton" then
                W.ShowContextMenu({ { value = "REMOVE", text = L["Remove from list"] } }, function()
                    ERF.Loot:RemoveEntry(e)
                    if selected == e then selected = nil end
                    LM:Refresh()
                end, 150)
            end
            LM:Refresh()
        end,
        onEnter = function(row, e) W.ItemTooltip(row, e.itemId) end,
    })
    P.items:SetPoint("TOPLEFT", ih, "BOTTOMLEFT", 0, -2)
    P.items:SetPoint("BOTTOMRIGHT", left, "BOTTOMRIGHT", -6, 6)
    P.items:SetEmptyText(L["Open a corpse (master loot) or add items by hand. Items appear here automatically."])

    -- Right: detail.
    local right = CreateFrame("Frame", nil, b)
    right:SetPoint("TOPLEFT", left, "TOPRIGHT", 12, 0)
    right:SetPoint("BOTTOMRIGHT", 0, 0)
    P.right = right

    P.icon = right:CreateTexture(nil, "ARTWORK")
    P.icon:SetSize(36, 36)
    P.icon:SetPoint("TOPLEFT", 0, 0)
    P.title = W.CreateLabel(right, "", "title", C.GOLD)
    P.title:SetPoint("TOPLEFT", P.icon, "TOPRIGHT", 8, -2)
    P.title:SetPoint("RIGHT", right, "RIGHT", 0, 0)
    P.sub = W.CreateLabel(right, "", "small", C.TEXT_DIM)
    P.sub:SetPoint("TOPLEFT", P.title, "BOTTOMLEFT", 0, -4)
    P.sub:SetPoint("RIGHT", right, "RIGHT", 0, 0)
    P.sub:SetWordWrap(true)

    P.start = W.CreateButton(right, L["Start roll"], 90, 22, function() if selected then StartRoll(selected) end end)
    P.start:SetPoint("TOPLEFT", 0, -50)
    W.MakePrimary(P.start)
    P.close = W.CreateButton(right, L["Close now"], 84, 22, function()
        local roll = RollOf(selected)
        if roll then ERF.Rolls:Close(roll) end
        LM:Refresh()
    end)
    P.close:SetPoint("LEFT", P.start, "RIGHT", 6, 0)
    P.extend = W.CreateButton(right, "+30s", 50, 22, function()
        local roll = RollOf(selected)
        if roll then ERF.Rolls:Extend(roll, 30) end
        LM:Refresh()
    end)
    P.extend:SetPoint("LEFT", P.close, "RIGHT", 6, 0)
    P.cancel = W.CreateButton(right, L["Cancel"], 70, 22, function()
        local roll = RollOf(selected)
        if roll then ERF.Rolls:Cancel(roll) end
        LM:Refresh()
    end)
    P.cancel:SetPoint("LEFT", P.extend, "RIGHT", 6, 0)
    P.reroll = W.CreateButton(right, L["Reroll tie"], 90, 22, function()
        if selected then W.Report(ERF.Rolls:RerollTie(selected) ~= nil, L["There is no tie to reroll."]) end
        LM:Refresh()
    end)
    P.reroll:SetPoint("LEFT", P.cancel, "RIGHT", 6, 0)

    local panel = W.CreatePanel(right)
    panel:SetPoint("TOPLEFT", 0, -80)
    panel:SetPoint("BOTTOMRIGHT", 0, 34)
    local rh = W.CreateHeaderRow(panel, RANK_COLS)
    rh:SetPoint("TOPLEFT", 6, -4)
    rh:SetPoint("RIGHT", panel, "RIGHT", -6, 0)
    P.ranking = W.CreateScrollList(panel, {
        rowHeight = 20,
        createRow = W.ColumnRowFactory(RANK_COLS),
        updateRow = function(row, d)
            local name = Util.ClassName(d.name, ERF.Raid:ClassOf(d.name))
            if d.waiting then
                row.cols[1]:SetText(name)
                row.cols[2]:SetText("|cff8c94a6" .. (d.passed and L["passed"] or L["waiting..."]) .. "|r")
                for i = 3, 6 do row.cols[i]:SetText("") end
                return
            end
            if d.winner then name = Util.CHAT_GOLD .. "> |r" .. name end
            row.cols[1]:SetText(name)
            row.cols[2]:SetText(d.o or "?")
            row.cols[3]:SetText(d.sp or "-")
            row.cols[4]:SetText(tostring(d.v))
            row.cols[5]:SetText((d.bn or 0) > 0 and (Util.CHAT_GREEN .. "+" .. d.bn .. "|r") or "")
            row.cols[6]:SetText(tostring(d.total))
        end,
        onClick = function(_, d)
            if d.waiting or not selected then return end
            DoAward(selected, d.name, KindOf(RollOf(selected), d.o), d.sp, d.total)
        end,
        onEnter = function(row, d)
            if d.waiting then return end
            GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
            GameTooltip:AddLine(L["Click to award the item to this player."], 1, 1, 1)
            GameTooltip:Show()
        end,
    })
    P.ranking:SetPoint("TOPLEFT", rh, "BOTTOMLEFT", 0, -2)
    P.ranking:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -6, 6)
    P.ranking:SetEmptyText(L["No rolls yet. Start the roll - or award the item directly."])

    P.award = W.CreateButton(right, L["Award to winner"], 140, 24, AwardWinner)
    P.award:SetPoint("BOTTOMLEFT", 0, 4)
    W.MakePrimary(P.award)
    P.awardTo = W.CreateButton(right, L["Award to..."], 110, 24, function(self) AwardToMenu(self) end)
    P.awardTo:SetPoint("LEFT", P.award, "RIGHT", 8, 0)
    P.hint = W.CreateLabel(right, "", "small", C.TEXT_DIM)
    P.hint:SetPoint("LEFT", P.awardTo, "RIGHT", 10, 0)
    P.hint:SetPoint("RIGHT", right, "RIGHT", 0, 0)

    local elapsed = 0
    win:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + dt
        if elapsed < 0.5 then return end
        elapsed = 0
        P.items:Redraw()
    end)
end

-- ---------------------------------------------------------------------------
-- Refresh
-- ---------------------------------------------------------------------------
function LM:Refresh()
    if not self.win or not self.win:IsShown() then return end
    local raid = ERF.Raid:Current()
    local items = ERF.Loot.items
    if selected then
        local still = false
        for _, e in ipairs(items) do if e == selected then still = true end end
        if not still then selected = nil end
    end
    local shown = {}
    local counts = { NEW = 0, DECIDED = 0, TRADE = 0 }
    for _, e in ipairs(items) do
        if Matches(e) then shown[#shown + 1] = e end
        if e.state == "NEW" then counts.NEW = counts.NEW + 1 end
        if e.state == "DECIDED" and e.winner and not e.tie then counts.DECIDED = counts.DECIDED + 1 end
        if e.state == "AWARDED" and e.trade and not e.traded then counts.TRADE = counts.TRADE + 1 end
    end
    selected = selected or shown[1]
    P.items:SetData(shown, true)
    P.filter:SetValue(filter, FILTER_NAMES[filter] .. (counts.TRADE > 0 and string.format(" (%d %s)", counts.TRADE, L["to trade"]) or ""))
    P.rollAll:SetAllowed(raid ~= nil and counts.NEW > 0, L["No waiting items."])
    P.awardAll:SetAllowed(counts.DECIDED > 0, L["No decided item with a clear winner."])

    P.right:SetShown(selected ~= nil)
    if not selected or not raid then return end

    local _, colored, icon = W.Item(selected.itemId)
    P.icon:SetTexture(icon)
    P.title:SetText(colored)
    local who = ERF.Raid:Reservers()[selected.itemId]
    local sub = selected.boss and (selected.boss .. "   ") or ""
    if who then
        local names = {}
        for _, p in ipairs(who) do
            local bonus = ERF.Raid:Bonus(p.name, selected.itemId)
            names[#names + 1] = p.name .. (bonus > 0 and (" +" .. bonus) or "")
        end
        sub = sub .. Util.CHAT_GOLD .. L["SR:"] .. "|r " .. table.concat(names, ", ")
    else
        sub = sub .. L["No soft reserve - open roll (MS > DS > OS > Greed)."]
    end
    P.sub:SetText(sub)

    local roll = RollOf(selected)
    local open = roll and roll.state == "OPEN"
    P.start:SetAllowed(not open and selected.state ~= "AWARDED", L["Not possible right now."])
    P.start:SetLabel(roll and not open and L["Roll again"] or L["Start roll"])
    P.close:SetAllowed(open, L["No open roll."])
    P.extend:SetAllowed(open, L["No open roll."])
    P.cancel:SetAllowed(open, L["No open roll."])
    P.reroll:SetAllowed(roll ~= nil and roll.tie ~= nil and not open, L["There is no tie to reroll."])
    P.award:SetAllowed(selected.winner ~= nil and selected.state ~= "AWARDED", L["There is no winner yet."])
    P.awardTo:SetAllowed(selected.state ~= "AWARDED", L["Already awarded."])

    local rows = {}
    if roll then
        for _, e in ipairs(ERF.Rolls:Rank(roll)) do
            e.winner = roll.winner and roll.winner.name == e.name
            rows[#rows + 1] = e
        end
        if roll.eligible then
            local answered = {}
            for n in pairs(roll.rolls) do answered[ERF.Raid.Key(n)] = true end
            local passed = {}
            for n in pairs(roll.passed) do passed[ERF.Raid.Key(n)] = true end
            for _, p in ipairs(who or {}) do
                local key = ERF.Raid.Key(p.name)
                if roll.eligible[key] and not answered[key] then
                    rows[#rows + 1] = { name = p.name, waiting = true, passed = passed[key] }
                end
            end
        end
    end
    P.ranking:SetData(rows, true)

    if selected.state == "AWARDED" then
        local t = string.format(L["Awarded to %s (%s)."], Util.ShortName(selected.awardedTo), selected.awardedKind or "?")
        if selected.trade and not selected.traded then
            t = t .. " " .. Util.CHAT_GOLD .. L["Trade with the player to hand it over."] .. "|r"
        end
        P.hint:SetText(t)
    elseif roll and roll.tie then
        P.hint:SetText(Util.CHAT_GOLD .. L["Tie between:"] .. "|r " .. table.concat(roll.tie, ", "))
    else
        P.hint:SetText(ERF.Loot.lootOpen and "" or L["Corpse closed - award now, hand over by trade."])
    end
end

function LM:Open()
    if not ERF.Raid:Current() then return W.Report(false, L["No raid imported."]) end
    if not ERF.Raid:IsLeader() then return W.Report(false, L["Only the loot master (who imported the raid) can do that."]) end
    self:Build()
    self.win:Show()
    self:Refresh()
end

function LM:Toggle()
    self:Build()
    if self.win:IsShown() then self.win:Hide() else self:Open() end
end

function LM:Init()
    ERF:OnChanged("LootMasterWindow", function(topic)
        if topic == "ROLLS" or topic == "LOOTMASTER" or topic == "ITEMS" or topic == "RAID" then LM:Refresh() end
    end)
end
