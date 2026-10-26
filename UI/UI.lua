-- =============================================================================
-- EasyRaidForever - UI/UI.lua
-- Small helpers shared by the windows.
-- =============================================================================

local ADDON_NAME, ERF = ...
local L = ERF.L

local UI = {}
ERF.UI = UI

function UI.DurationText(seconds)
    seconds = math.floor(tonumber(seconds) or 0)
    if seconds < 60 then return string.format(L["%d sec"], seconds) end
    if seconds % 60 == 0 then return string.format(L["%d min"], seconds / 60) end
    return string.format(L["%d:%02d min"], math.floor(seconds / 60), seconds % 60)
end

-- Item data arrived (Widgets.Item): redraw once, not for every single item.
local pending = false
function UI.RefreshSoon()
    if pending then return end
    pending = true
    C_Timer.After(0.3, function()
        pending = false
        ERF:Notify("ITEMS")
    end)
end
