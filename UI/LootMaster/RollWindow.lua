-- =============================================================================
-- EasyRaidForever - UI/LootMaster/RollWindow.lua
--
-- ONE window with a compact list of all open rolls instead of one popup per
-- item (EasyRaidLoot stacked popups - with eight drops at once that covered
-- the screen). Each row: icon, item, note, countdown bar, the roll buttons.
-- Rows the player answered collapse into a status line; decided rows show
-- the winner for a short while. Opens itself when a new roll arrives.
-- At most six rows are visible (the rest scrolls), long timers show their
-- remaining time, and "Pass all" answers every open roll at once - so even
-- the loot of a whole evening rolled in one go does not flood the screen.
-- =============================================================================

local ADDON_NAME, ERF = ...
local L = ERF.L
local Util = ERF.Util
local C = Util.COLORS
local W = ERF.Widgets

local RW = {}
ERF.RollWindow = RW

local ROW_H = 46
local MAX_BUTTONS = 6
local SHOW_CLOSED = 30      -- seconds a decided roll stays in this list

local function Remaining(roll)
    return math.max(0, (roll.endsAt or 0) - GetTime())
end

local function Note(roll)
    if roll.sr then
        local n = 0
        for _ in pairs(roll.eligible or {}) do n = n + 1 end
        local bonus = ERF.Rolls:MyBonus(roll)
        local text = string.format(L["Soft reserve - %d contender(s)"], n)
        if bonus > 0 then text = text .. "  " .. Util.CHAT_GREEN .. string.format(L["your SR+ adds +%d"], bonus) .. "|r" end
        return text
    end
    return roll.boss and string.format(L["Open roll - %s"], roll.boss) or L["Open roll"]
end

local function StatusText(roll)
    if roll.state == "CLOSED" then
        if roll.winner then
            local spec = roll.winner.sp
            return string.format(L["Winner: %s (%s %d)%s"], Util.ShortName(roll.winner.name), roll.winner.o or "?",
                roll.winner.total or roll.winner.v or 0, spec and (" - " .. spec) or "")
        end
        if roll.tie then return Util.CHAT_GOLD .. L["Tie - the loot master rerolls it."] .. "|r" end
        return L["Nobody rolled."]
    end
    if roll.state == "CANCELLED" then return "|cff8c94a6" .. L["Cancelled"] .. "|r" end
    if roll.myChoice == "PASS" then return "|cff8c94a6" .. L["Passed"] .. "|r" end
    if roll.myChoice then
        local mine = roll.rolls[ERF.playerName]
        if mine then
            return string.format(L["You rolled %d (%s)%s - waiting for the others"], mine.v, roll.myChoice,
                (mine.bn or 0) > 0 and (" +" .. mine.bn) or "")
        end
        return string.format(L["Rolling for %s..."], roll.myChoice)
    end
    if not ERF.Rolls:CanRoll(roll) then return "|cff8c94a6" .. L["Not eligible (no reserve)"] .. "|r" end
    return nil
end

-- Rolls to list: open ones first (unanswered on top), then recent results.
local function Data()
    local out = {}
    local now = GetTime()
    for _, r in ipairs(ERF.Rolls:List()) do
        if r.state == "OPEN" or now - (r.closedAt or now) <= SHOW_CLOSED then
            local relevant = r.state ~= "OPEN" or ERF.Rolls:CanRoll(r) or r.myChoice
            if relevant then out[#out + 1] = r end
        end
    end
    local function rank(r)
        if r.state == "OPEN" and not r.myChoice then return 1 end
        if r.state == "OPEN" then return 2 end
        return 3
    end
    table.sort(out, function(a, b)
        if rank(a) ~= rank(b) then return rank(a) < rank(b) end
        return (a.endsAt or 0) < (b.endsAt or 0)
    end)
    return out
end

local function CreateRow(list)
    local row = CreateFrame("Button", nil, list.content)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(34, 34)
    row.icon:SetPoint("LEFT", 6, 1)

    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 8, -1)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)
    row.note = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.note:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -3)
    row.note:SetJustifyH("LEFT")
    row.note:SetWordWrap(false)
    row.note:SetTextColor(C.TEXT_DIM[1], C.TEXT_DIM[2], C.TEXT_DIM[3])

    row.bar = CreateFrame("StatusBar", nil, row)
    row.bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
    row.bar:SetHeight(3)
    row.bar:SetPoint("BOTTOMLEFT", 6, 2)
    row.bar:SetPoint("BOTTOMRIGHT", -6, 2)
    row.bar:SetMinMaxValues(0, 1)

    row.buttons = {}
    for i = 1, MAX_BUTTONS do
        local b = W.CreateButton(row, "", 48, 20, function(self)
            if row.data and self.label then
                ERF.Rolls:Choose(row.data, self.label)
                RW:Refresh()
            end
        end)
        if i == 1 then
            b:SetPoint("RIGHT", row, "RIGHT", -6, 4)
        else
            b:SetPoint("RIGHT", row.buttons[i - 1], "LEFT", -4, 0)
        end
        row.buttons[i] = b
    end
    row.status = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.status:SetPoint("RIGHT", row, "RIGHT", -8, 4)
    row.status:SetJustifyH("RIGHT")

    row:SetScript("OnSizeChanged", function(self, w)
        local free = (w or 400) - 60 - 6 * 52
        row.name:SetWidth(math.max(80, free))
        row.note:SetWidth(math.max(80, (w or 400) - 60))
    end)
    return row
end

local function UpdateRow(row, roll)
    local _, colored, icon = W.Item(roll.itemId)
    row.icon:SetTexture(icon)
    row.name:SetText(colored)
    local note = Note(roll)
    if roll.state == "OPEN" and (roll.duration or 0) >= 60 then
        note = note .. "  |cffe8c46b" .. ERF.UI.DurationText(math.floor(Remaining(roll))) .. "|r"
    end
    row.note:SetText(note)

    local status = StatusText(roll)
    local showButtons = status == nil
    -- Buttons right-to-left: the last option (usually Pass) sits at the edge.
    local opts = roll.options or {}
    for i, b in ipairs(row.buttons) do
        local o = opts[#opts - i + 1]
        if showButtons and o then
            b.label = o.label
            b:SetLabel(o.cap == 0 and L["Pass"] or o.label)
            b.tooltipText = o.cap > 0 and string.format(L["/roll 1-%d"], o.cap) or nil
            if i == #opts then W.MakePrimary(b) else b.primary = false b:SetEnabledState(true) end
            b:Show()
        else
            b.label = nil
            b:Hide()
        end
    end
    row.status:SetShown(not showButtons)
    row.status:SetText(status or "")

    if roll.state == "OPEN" then
        local frac = Remaining(roll) / math.max(1, roll.duration or 30)
        row.bar:SetValue(frac)
        row.bar:SetStatusBarColor(1 - frac * 0.1, 0.35 + frac * 0.45, 0.25)
        row.bar:Show()
    else
        row.bar:Hide()
    end
end

function RW:Build()
    if self.win then return end
    local win = W.CreateWindow("EasyRaidForeverRollWindow", L["Loot rolls"], 520, 3 * ROW_H + 60)
    win:SetFrameStrata("HIGH")
    self.win = win
    self.list = W.CreateScrollList(win.Body, {
        rowHeight = ROW_H,
        createRow = CreateRow,
        updateRow = UpdateRow,
        onEnter = function(row, roll) W.ItemTooltip(row, roll.itemId) end,
    })
    self.list:SetAllPoints()
    self.list:SetEmptyText(L["No open rolls."])

    self.passAll = W.CreateButton(win, L["Pass all"], 80, 20, function()
        local n = ERF.Rolls:PassAll()
        if n and n > 0 then Util.Print(L["Passed on %d roll(s)."], n) end
        RW:Refresh()
    end)
    self.passAll:SetPoint("TOPRIGHT", win, "TOPRIGHT", -40, -6)
    self.passAll.tooltipText = L["Passes on every roll you have not answered yet."]

    -- Countdown bars.
    local elapsed = 0
    win:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + dt
        if elapsed < 0.25 then return end
        elapsed = 0
        RW.list:Redraw()
    end)
end

function RW:Refresh()
    if not self.win then return end
    local data = Data()
    local rows = math.max(1, math.min(6, #data))
    self.win:SetHeight(rows * ROW_H + 60)
    local open = 0
    for _, r in ipairs(data) do if r.state == "OPEN" and not r.myChoice then open = open + 1 end end
    self.win.Title:SetText(open > 0 and string.format(L["Loot rolls (%d waiting for you)"], open) or L["Loot rolls"])
    self.passAll:SetAllowed(open > 0, L["No open rolls."])
    self.list:SetData(data, true)
end

function RW:Open()
    self:Build()
    self.win:Show()
    self:Refresh()
end

function RW:Toggle()
    self:Build()
    if self.win:IsShown() then self.win:Hide() else self:Open() end
end

function RW:Init()
    ERF:OnChanged("RollWindow", function(topic, what)
        if topic ~= "ROLLS" and topic ~= "ITEMS" then return end
        if what == "NEW" and ERF.Rolls:OpenCount(true) > 0 then
            RW:Open()
        elseif RW.win and RW.win:IsShown() then
            RW:Refresh()
        end
    end)
end
