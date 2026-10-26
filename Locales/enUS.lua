-- =============================================================================
-- EasyRaidForever - Locales/enUS.lua
--
-- English is the source language: every short string in the code IS its own
-- enUS translation. deDE.lua only lists the strings it translates; a missing
-- entry falls back to the English key through the metatable below.
-- =============================================================================

local ADDON_NAME, ERF = ...

local L = setmetatable({}, {
    __index = function(_, key) return key end,
})
ERF.L = L

L["IMPORT_HELP"] = "On the guild website open the raid, click 'Export for addon' and copy the text. " ..
    "Paste it here (Ctrl+V) and click Import. The import contains the soft reserves, SR+ bonus and main / dual specs."
L["EXPORT_HELP"] = "Copy this text (Ctrl+C) and paste it on the guild website in the raid's edit view " ..
    "under 'Paste addon export'. It contains every item awarded in this raid."
L["NO_RAID_HELP"] = "No raid imported yet.\n\nOn the guild website open the raid and click 'Export for addon', " ..
    "then click 'Import from website' here. You become the loot master of this raid."
