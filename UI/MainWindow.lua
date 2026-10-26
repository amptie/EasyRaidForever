-- =============================================================================
-- EasyRaidForever - UI/MainWindow.lua
--
-- One window: the imported raid with its soft reserves (incl. SR+ bonus and
-- main / dual spec) and the loot awarded so far, plus the two text dialogs
-- "Import from website" and "Export for website".
-- =============================================================================

local ADDON_NAME, ERF = ...
local L = ERF.L
local Util = ERF.Util
local C = Util.COLORS
local W = ERF.Widgets

local MW = {}
ERF.MainWindow = MW

local RES_COLS = {
    { text = L["Player"], width = 120 },
    { text = L["Spec"], width = 120 },
    { text = L["Item"], width = "*" },
    { text = L["Bonus"], width = 50, justify = "RIGHT" },
}
local LOOT_COLS = {
    { text = L["Item"], width = "*" },
    { text = L["Player"], width = 110 },
    { text = L["Choice"], width = 55 },
    { text = L["Boss"], width = 110 },
}

local P = {}

local function ItemText(raid, itemId)
    local _, colored = W.Item(itemId)
    -- While the client loads the item, the website's name is better than "loading..."
    if not C_Item.GetItemInfo(itemId) and raid.items[itemId] and raid.items[itemId].n then
        return "|cffa335ee[" .. raid.items[itemId].n .. "]|r"
    end
    return colored
end

-- ---------------------------------------------------------------------------
-- Text dialogs (import / export)
-- ---------------------------------------------------------------------------
local function TextDialog(key, title, help, readOnly, buttonText, onButton)
    local win = W.CreateWindow("EasyRaidForever" .. key, title, 520, 300)
    local p = W.CreateParagraph(win.Body, help, 500, C.TEXT_DIM)
    p:SetPoint("TOPLEFT", 0, 0)
    p:SetPoint("RIGHT", win.Body, "RIGHT", 0, 0)
    win.area = W.CreateTextArea(win.Body, 500, 160, readOnly)
    win.area:SetPoint("TOPLEFT", p, "BOTTOMLEFT", 0, -8)
    win.area:SetPoint("RIGHT", win.Body, "RIGHT", 0, 0)
    win.area:SetPoint("BOTTOM", win.Body, "BOTTOM", 0, 30)
    if buttonText then
        win.button = W.CreateButton(win.Body, buttonText, 140, 22, function() onButton(win) end)
        win.button:SetPoint("BOTTOMLEFT", 0, 0)
        W.MakePrimary(win.button)
    end
    win.status = W.CreateLabel(win.Body, "", "small", C.TEXT_DIM)
    win.status:SetPoint("LEFT", win.button or win.Body, buttonText and "RIGHT" or "LEFT", 10, 0)
    win.status:SetPoint("RIGHT", win.Body, "RIGHT", 0, 0)
    return win
end

function MW:ShowImport()
    if not self.importWin then
        self.importWin = TextDialog("Import", L["Import from website"], L["IMPORT_HELP"], false, L["Import"], function(win)
            local raid, why = ERF.Transfer:Import(win.area:GetText())
            if not raid then
                win.status:SetText(Util.CHAT_RED .. tostring(why) .. "|r")
                return
            end
            win.area:SetText("")
            win.status:SetText("")
            win:Hide()
            Util.Print(L["Raid imported: %s - you are the loot master."], raid.title)
            MW:Open()
        end)
    end
    self.importWin.area:SetText("")
    self.importWin.status:SetText("")
    self.importWin:Show()
    self.importWin.area.editBox:SetFocus()
end

function MW:ShowExport()
    local text, countOrWhy = ERF.Transfer:ExportLoot()
    if not text then return W.Report(false, countOrWhy) end
    if not self.exportWin then
        self.exportWin = TextDialog("Export", L["Export for website"], L["EXPORT_HELP"], true)
    end
    self.exportWin.area:SetText(text)
    self.exportWin.status:SetText(string.format(L["%d awarded item(s)"], countOrWhy))
    self.exportWin:Show()
    self.exportWin.area:SelectAll()
end

-- ---------------------------------------------------------------------------
-- Main window
-- ---------------------------------------------------------------------------
function MW:Build()
    if self.win then return end
    local win = W.CreateWindow("EasyRaidForeverMain", "EasyRaid Forever", 760, 480)
    self.win = win
    local b = win.Body

    P.title = W.CreateLabel(b, "", "title", C.GOLD)
    P.title:SetPoint("TOPLEFT", 0, 0)
    P.title:SetPoint("RIGHT", b, "RIGHT", 0, 0)
    P.sub = W.CreateLabel(b, "", "small", C.TEXT_DIM)
    P.sub:SetPoint("TOPLEFT", P.title, "BOTTOMLEFT", 0, -4)
    P.sub:SetPoint("RIGHT", b, "RIGHT", 0, 0)

    P.import = W.CreateButton(b, L["Import from website"], 150, 22, function() MW:ShowImport() end)
    P.import:SetPoint("TOPLEFT", 0, -44)
    P.export = W.CreateButton(b, L["Export for website"], 150, 22, function() MW:ShowExport() end)
    P.export:SetPoint("LEFT", P.import, "RIGHT", 6, 0)
    W.MakePrimary(P.export)
    P.lm = W.CreateButton(b, L["Loot master"], 110, 22, function() ERF.LootMasterWindow:Toggle() end)
    P.lm:SetPoint("LEFT", P.export, "RIGHT", 6, 0)
    P.rolls = W.CreateButton(b, L["Roll window"], 100, 22, function() ERF.RollWindow:Toggle() end)
    P.rolls:SetPoint("LEFT", P.lm, "RIGHT", 6, 0)
    P.results = W.CreateButton(b, L["Results"], 90, 22, function() ERF.ResultsWindow:Toggle() end)
    P.results:SetPoint("LEFT", P.rolls, "RIGHT", 6, 0)

    P.empty = W.CreateParagraph(b, L["NO_RAID_HELP"], 600, C.TEXT_DIM)
    P.empty:SetPoint("TOPLEFT", 0, -84)

    -- Left: soft reserves
    local left = W.CreatePanel(b)
    left:SetPoint("TOPLEFT", 0, -80)
    left:SetPoint("BOTTOM", b, "BOTTOM", 0, 0)
    left:SetPoint("RIGHT", b, "CENTER", -6, 0)
    P.left = left
    local lt = W.CreateSectionHeader(left, L["Soft reserves"], 200)
    lt:SetPoint("TOPLEFT", 6, -6)
    local lh = W.CreateHeaderRow(left, RES_COLS)
    lh:SetPoint("TOPLEFT", 6, -26)
    lh:SetPoint("RIGHT", left, "RIGHT", -6, 0)
    P.res = W.CreateScrollList(left, {
        rowHeight = 20,
        createRow = W.ColumnRowFactory(RES_COLS),
        updateRow = function(row, d)
            local raid = ERF.Raid:Current()
            row.cols[1]:SetText(Util.ClassName(d.name, d.class))
            row.cols[2]:SetText((d.ms or "-") .. (d.ds and (" |cff8c94a6/ " .. d.ds .. "|r") or ""))
            row.cols[3]:SetText(d.itemId and ItemText(raid, d.itemId) or ("|cff8c94a6" .. L["no items yet"] .. "|r"))
            row.cols[4]:SetText(d.bonus > 0 and (Util.CHAT_GREEN .. "+" .. d.bonus .. "|r") or "")
        end,
        onEnter = function(row, d) if d.itemId then W.ItemTooltip(row, d.itemId) end end,
    })
    P.res:SetPoint("TOPLEFT", lh, "BOTTOMLEFT", 0, -2)
    P.res:SetPoint("BOTTOMRIGHT", left, "BOTTOMRIGHT", -6, 6)
    P.res:SetEmptyText(L["Nobody reserved anything."])

    -- Right: awarded loot
    local right = W.CreatePanel(b)
    right:SetPoint("TOPLEFT", b, "TOP", 6, -80)
    right:SetPoint("BOTTOMRIGHT", 0, 0)
    P.right = right
    local rt = W.CreateSectionHeader(right, L["Awarded loot"], 200)
    rt:SetPoint("TOPLEFT", 6, -6)
    local rh = W.CreateHeaderRow(right, LOOT_COLS)
    rh:SetPoint("TOPLEFT", 6, -26)
    rh:SetPoint("RIGHT", right, "RIGHT", -6, 0)
    P.loot = W.CreateScrollList(right, {
        rowHeight = 20,
        createRow = W.ColumnRowFactory(LOOT_COLS),
        updateRow = function(row, d)
            local raid = ERF.Raid:Current()
            row.cols[1]:SetText(ItemText(raid, d.e.i))
            row.cols[2]:SetText(Util.ClassName(d.e.n, ERF.Raid:ClassOf(d.e.n)))
            row.cols[3]:SetText(Util.Colorize(d.e.k or "?", ERF.Raid.LOOT_KIND_COLORS[d.e.k] or C.TEXT))
            row.cols[4]:SetText(d.e.b or "-")
        end,
        onClick = function(_, d, button)
            if button ~= "RightButton" then return end
            W.ShowContextMenu({ { value = "REMOVE", text = L["Remove award"] } }, function()
                W.Confirm(L["Remove this award from the list? (The item itself stays where it is.)"], function()
                    ERF.Loot:Unaward(d.index)
                end)
            end, 160)
        end,
        onEnter = function(row, d)
            local lines = {}
            if d.e.sp then lines[#lines + 1] = { L["Spec"] .. ": " .. d.e.sp, 0.8, 0.8, 0.8 } end
            if d.e.r then lines[#lines + 1] = { L["Roll"] .. ": " .. d.e.r, 0.8, 0.8, 0.8 } end
            lines[#lines + 1] = { L["Right-click: remove award"], 0.6, 0.6, 0.6 }
            W.ItemTooltip(row, d.e.i, lines)
        end,
    })
    P.loot:SetPoint("TOPLEFT", rh, "BOTTOMLEFT", 0, -2)
    P.loot:SetPoint("BOTTOMRIGHT", right, "BOTTOMRIGHT", -6, 6)
    P.loot:SetEmptyText(L["No item awarded yet."])
end

function MW:Refresh()
    if not self.win or not self.win:IsShown() then return end
    local raid = ERF.Raid:Current()
    local leader = ERF.Raid:IsLeader()
    P.empty:SetShown(raid == nil)
    P.left:SetShown(raid ~= nil)
    P.right:SetShown(raid ~= nil)
    P.export:SetAllowed(raid ~= nil and leader, L["Only the loot master (who imported the raid) can do that."])
    P.lm:SetAllowed(raid ~= nil and leader, L["Only the loot master (who imported the raid) can do that."])
    if not raid then
        P.title:SetText(L["No raid imported"])
        P.sub:SetText(L["Rolls of the loot master reach you anyway - no import needed to roll."])
        return
    end

    P.title:SetText(raid.title .. (raid.instance and ("  |cff8c94a6" .. raid.instance .. "|r") or ""))
    local system = raid.system == "SRPLUS" and "SR+" or raid.system == "SR" and "SR" or L["no loot system"]
    P.sub:SetText(string.format("%s%s · %s · %s",
        raid.start and (Util.FormatDate(raid.start) .. " · ") or "", raid.group or "-", system,
        leader and (Util.CHAT_GREEN .. L["You are the loot master"] .. "|r")
            or string.format(L["Loot master: %s"], Util.ShortName(raid.leader))))

    local rows = {}
    for _, p in pairs(raid.players) do
        local any = false
        for itemId, pts in pairs(p.items) do
            any = true
            rows[#rows + 1] = { name = p.name, class = p.class, ms = p.ms, ds = p.ds, itemId = itemId,
                bonus = raid.system == "SRPLUS" and pts * (raid.bonus or 10) or 0 }
        end
        if not any then rows[#rows + 1] = { name = p.name, class = p.class, ms = p.ms, ds = p.ds, bonus = 0 } end
    end
    table.sort(rows, function(a, c)
        if a.name ~= c.name then return a.name < c.name end
        return (a.itemId or 0) < (c.itemId or 0)
    end)
    P.res:SetData(rows, true)

    local loot = {}
    for i = #raid.loot, 1, -1 do loot[#loot + 1] = { index = i, e = raid.loot[i] } end
    P.loot:SetData(loot, true)
end

function MW:Open()
    self:Build()
    self.win:Show()
    self:Refresh()
end

function MW:Toggle()
    self:Build()
    if self.win:IsShown() then self.win:Hide() else self:Open() end
end

function MW:Init()
    ERF:OnChanged("MainWindow", function(topic)
        if topic == "RAID" or topic == "ITEMS" or topic == "LOOTMASTER" then MW:Refresh() end
    end)
end
