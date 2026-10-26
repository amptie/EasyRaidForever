-- =============================================================================
-- EasyRaidForever - UI/LootMaster/ResultsWindow.lua
--
-- For every player: who gets which item, with which choice (SR / MS / OS ...)
-- and - for MS and OS - the spec the winner rolled for. Open rolls show the
-- current leader. Hovering a row lists every roll of that item.
-- =============================================================================

local ADDON_NAME, ERF = ...
local L = ERF.L
local Util = ERF.Util
local C = Util.COLORS
local W = ERF.Widgets

local RS = {}
ERF.ResultsWindow = RS

local COLS = {
    { text = "", width = 24 },
    { text = L["Item"], width = "*" },
    { text = L["Player"], width = 110 },
    { text = L["Choice"], width = 55 },
    { text = L["Spec"], width = 95 },
    { text = L["Roll"], width = 50, justify = "RIGHT" },
}

local function Row(roll)
    local ranking = ERF.Rolls:Rank(roll)
    local lead = roll.winner or ranking[1]
    local d = { roll = roll, ranking = ranking }
    if lead then
        d.player = lead.name
        d.choice = roll.sr and "SR" or lead.o
        d.spec = lead.sp
        d.total = lead.total or ((lead.v or 0) + (lead.bn or 0))
    end
    return d
end

function RS:Build()
    if self.win then return end
    local win = W.CreateWindow("EasyRaidForeverResults", L["Loot results"], 560, 260)
    self.win = win
    local header = W.CreateHeaderRow(win.Body, COLS)
    header:SetPoint("TOPLEFT", 0, 0)
    header:SetPoint("RIGHT", win.Body, "RIGHT", 0, 0)
    self.list = W.CreateScrollList(win.Body, {
        rowHeight = 22,
        createRow = function(list)
            local row = W.ColumnRowFactory(COLS)(list)
            row.icon = row:CreateTexture(nil, "ARTWORK")
            row.icon:SetSize(18, 18)
            row.icon:SetPoint("LEFT", 3, 0)
            return row
        end,
        updateRow = function(row, d)
            local roll = d.roll
            local _, colored, icon = W.Item(roll.itemId)
            row.icon:SetTexture(icon)
            row.cols[2]:SetText(colored)
            local open = roll.state == "OPEN"
            if roll.state == "CANCELLED" then
                row.cols[3]:SetText("|cff8c94a6" .. L["Cancelled"] .. "|r")
            elseif roll.tie and not open then
                row.cols[3]:SetText(Util.CHAT_GOLD .. L["Tie"] .. "|r")
            elseif d.player then
                local name = Util.ClassName(d.player, ERF.Raid:ClassOf(d.player))
                row.cols[3]:SetText(open and ("|cff8c94a6" .. L["leading:"] .. "|r " .. name) or name)
            else
                row.cols[3]:SetText(open and ("|cff8c94a6" .. L["rolling..."] .. "|r") or "-")
            end
            local kind = d.choice and (roll.sr and "SR" or ERF.Raid:LootKind(d.choice))
            row.cols[4]:SetText(kind and Util.Colorize(d.choice, ERF.Raid.LOOT_KIND_COLORS[kind] or C.TEXT) or "")
            -- The spec only matters for SR / MS / DS (main or dual spec) and Greed.
            local showSpec = kind == "MS" or kind == "DS" or kind == "SR" or kind == "GREED"
            row.cols[5]:SetText(showSpec and d.spec or "")
            row.cols[6]:SetText(d.total and tostring(d.total) or "")
        end,
        onEnter = function(row, d)
            local lines = { { " " } }
            for i, e in ipairs(d.ranking) do
                if i > 10 then break end
                local spec = e.sp
                lines[#lines + 1] = { string.format("%d. %s  %s %d%s%s", i, Util.ShortName(e.name), e.o or "?", e.total,
                    (e.bn or 0) > 0 and (" (" .. e.v .. "+" .. e.bn .. ")") or "", spec and ("  - " .. spec) or ""), 0.85, 0.85, 0.85 }
            end
            W.ItemTooltip(row, d.roll.itemId, lines)
        end,
    })
    self.list:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -2)
    self.list:SetPoint("BOTTOMRIGHT", 0, 0)
    self.list:SetEmptyText(L["No rolls yet."])
end

function RS:Refresh()
    if not self.win then return end
    local rows = {}
    local list = ERF.Rolls:List()
    for i = #list, 1, -1 do rows[#rows + 1] = Row(list[i]) end
    self.list:SetData(rows, true)
end

function RS:Open()
    self:Build()
    self.win:Show()
    self:Refresh()
end

function RS:Toggle()
    self:Build()
    if self.win:IsShown() then self.win:Hide() else self:Open() end
end

function RS:Init()
    ERF:OnChanged("ResultsWindow", function(topic, what)
        if topic ~= "ROLLS" and topic ~= "ITEMS" then return end
        if what == "RESULT" and ERF.db.options.showResults ~= false then
            RS:Open()
        elseif RS.win and RS.win:IsShown() then
            RS:Refresh()
        end
    end)
end
