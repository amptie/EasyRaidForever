-- =============================================================================
-- EasyRaidForever - UI/Minimap.lua
-- LibDataBroker launcher + LibDBIcon minimap button. The addon compartment
-- entry comes from the TOC (AddonCompartmentFunc) and needs no code here.
-- =============================================================================

local ADDON_NAME, ERF = ...
local L = ERF.L
local Util = ERF.Util

local Minimap = {}
ERF.Minimap = Minimap

local ICON = "Interface\\Icons\\INV_Misc_Book_09"

function Minimap:Init()
    local LDB = LibStub and LibStub("LibDataBroker-1.1", true)
    local DBIcon = LibStub and LibStub("LibDBIcon-1.0", true)
    if not LDB then return end

    self.broker = LDB:NewDataObject("EasyRaidForever", {
        type = "launcher",
        text = "EasyRaidForever",
        icon = ICON,
        OnClick = function(_, button)
            if button == "RightButton" and ERF.Raid:IsLeader() then
                ERF.LootMasterWindow:Toggle()
            elseif button == "RightButton" then
                ERF.RollWindow:Toggle()
            else
                ERF.MainWindow:Toggle()
            end
        end,
        OnTooltipShow = function(tt)
            tt:AddLine("EasyRaid Forever", 0.91, 0.77, 0.42)
            local raid = ERF.Raid:Current()
            if raid then
                tt:AddLine(raid.title or "?", 1, 1, 1)
                tt:AddLine(L["Loot master"] .. ": " .. Util.ShortName(raid.leader), 0.8, 0.8, 0.8)
                local open = ERF.Rolls:OpenCount()
                if open > 0 then tt:AddLine(string.format(L["%d open roll(s)"], open), 0.32, 0.78, 0.45) end
            else
                tt:AddLine(L["No raid imported."], 0.8, 0.8, 0.8)
            end
            tt:AddLine(" ")
            tt:AddLine(L["Left-click: open window"], 0.6, 0.6, 0.6)
            tt:AddLine(ERF.Raid:IsLeader() and L["Right-click: loot master"] or L["Right-click: roll window"], 0.6, 0.6, 0.6)
        end,
    })

    if DBIcon then
        DBIcon:Register("EasyRaidForever", self.broker, ERF.db.options.minimap)
        self.icon = DBIcon
    end
end
