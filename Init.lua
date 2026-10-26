-- =============================================================================
-- EasyRaidForever - Init.lua
--
-- Loaded last by the TOC. Core.lua calls ERF:Boot() on PLAYER_ENTERING_WORLD.
-- Boot is idempotent (the event fires on every loading screen) and starts
-- every subsystem in its own guard: a broken module costs its own feature,
-- never the whole addon.
-- =============================================================================

local ADDON_NAME, ERF = ...
local L = ERF.L
local Util = ERF.Util

function ERF:Boot()
    if self.booted then return end
    if not self.dbReady then self:InitDB() end
    self.booted = true

    Util.Guard(function() ERF.Comm:Init() end, "Boot.Comm")
    Util.Guard(function() ERF.Raid:Init() end, "Boot.Raid")
    Util.Guard(function() ERF.Loot:Init() end, "Boot.Loot")
    Util.Guard(function() ERF.Rolls:Init() end, "Boot.Rolls")
    Util.Guard(function() ERF.TradeHelper:Init() end, "Boot.TradeHelper")
    Util.Guard(function() ERF.RollWindow:Init() end, "Boot.RollWindow")
    Util.Guard(function() ERF.ResultsWindow:Init() end, "Boot.ResultsWindow")
    Util.Guard(function() ERF.LootMasterWindow:Init() end, "Boot.LootMaster")
    Util.Guard(function() ERF.MainWindow:Init() end, "Boot.MainWindow")
    Util.Guard(function() ERF.Minimap:Init() end, "Boot.Minimap")

    Util.Print(L["loaded. Type |cffffffff/erf|r to open the window."])
end

-- ---------------------------------------------------------------------------
-- Diagnostics (/erf check)
--
-- What the addon assumes about the Forever client but could not verify while
-- it was written: addon messages, /roll lines, loot APIs, the name format.
-- ---------------------------------------------------------------------------
local RESULT = {
    ok   = "|cff52c773 ok  |r",
    warn = "|cffe8c46bwarn |r",
    fail = "|cffdd5a4dFAIL |r",
}

function ERF.RunDiagnostics()
    local counts = { ok = 0, warn = 0, fail = 0 }
    local function report(state, label, detail)
        counts[state] = counts[state] + 1
        local line = string.format("  [%s] %s", RESULT[state], label)
        if detail then line = line .. "  |cff8c94a6" .. tostring(detail) .. "|r" end
        DEFAULT_CHAT_FRAME:AddMessage(line)
    end
    local function section(title) DEFAULT_CHAT_FRAME:AddMessage("|cffe8c46b" .. title .. "|r") end
    local function api(path, critical)
        local obj = _G
        for part in string.gmatch(path, "[^%.]+") do
            obj = type(obj) == "table" and obj[part] or nil
        end
        if type(obj) == "function" then report("ok", path) return true end
        report(critical and "fail" or "warn", path .. " " .. L["is missing"])
        return false
    end

    Util.Print(L["diagnostics"])
    local _, _, _, toc = GetBuildInfo()
    section(L["Client"])
    report("ok", "Interface " .. tostring(toc), "WOW_PROJECT_ID=" .. tostring(WOW_PROJECT_ID))

    section(L["Communication"])
    api("C_ChatInfo.SendAddonMessage", true)
    api("C_ChatInfo.RegisterAddonMessagePrefix", true)
    api("C_ChatInfo.InChatMessagingLockdown")
    local locked = ERF.Comm:IsLocked()
    report(locked and "warn" or "ok", L["chat lockdown"], locked and L["active - messages wait"] or L["inactive"])
    local st = ERF.Comm.stats
    report("ok", L["messages"], string.format("sent %d, received %d, dropped %d, lockdown waits %d, queued %d",
        st.sent, st.received, st.dropped, st.lockdownWaits, ERF.Comm:QueueSize()))
    local channel = Util.GroupChannel()
    report(channel and "ok" or "warn", L["group channel"], channel or L["not in a group"])
    local roster, secret = Util.GroupRoster()
    report(secret > 0 and "warn" or "ok", L["group roster readable"], string.format("%d readable, %d secret", #roster, secret))

    -- Forever characters have first name + surname; the website matches them
    -- by the first name. Shows the raw values the APIs deliver.
    section(L["Names"])
    local function raw(...)
        local out = {}
        for i = 1, select("#", ...) do
            local v = select(i, ...)
            out[#out + 1] = Util.IsSecret(v) and "<secret>" or string.format("%q", tostring(v))
        end
        return table.concat(out, ", ")
    end
    report("ok", "UnitName(player)", raw(UnitName("player")))
    report("ok", "UnitFullName(player)", raw(UnitFullName("player")))
    report("ok", L["stored as"], string.format("%s  ->  %s  (key %s)", tostring(ERF.playerName),
        Util.ShortName(ERF.playerName), tostring(ERF.Raid.Key(ERF.playerName))))
    if IsInRaid() then
        for i = 1, math.min(3, GetNumGroupMembers()) do
            report("ok", "GetRaidRosterInfo(" .. i .. ")", raw((GetRaidRosterInfo(i))))
        end
    elseif IsInGroup() then
        report("ok", "UnitName(party1)", raw(UnitName("party1")))
    end

    section(L["Loot"])
    api("RandomRoll", true)
    api("C_PartyInfo.GetLootMethod")
    api("GetNumLootItems", true)
    api("GetLootSlotLink", true)
    api("GetLootSlotInfo")
    api("GetMasterLootCandidate")
    api("GiveMasterLoot")
    local sample = string.format(RANDOM_ROLL_RESULT or "%s rolls %d (%d-%d)", "Tester", 42, 1, 100)
    local n, v, lo, hi = ERF.Rolls:ParseRoll(sample)
    report((n == "Tester" and v == 42 and lo == 1 and hi == 100) and "ok" or "fail", L["/roll lines can be read"], sample)
    if C_PartyInfo and C_PartyInfo.GetLootMethod then
        local ok, method = pcall(C_PartyInfo.GetLootMethod)
        local ml = Enum and Enum.LootMethod and Enum.LootMethod.Masterlooter
        report((ok and method == ml) and "ok" or "warn", L["loot method"],
            (ok and method == ml) and L["master loot"] or (L["not master loot - awards are recorded, items traded by hand"] .. " (" .. tostring(method) .. ")"))
    end

    section(L["Trade"])
    api("ClickTradeButton")
    api("GetTradePlayerItemLink")
    api("C_Container.PickupContainerItem")
    report(type(LOOT_ITEM_SELF) == "string" and "ok" or "warn", "LOOT_ITEM_SELF", tostring(LOOT_ITEM_SELF))
    report(type(ERR_TRADE_COMPLETE) == "string" and "ok" or "warn", "ERR_TRADE_COMPLETE", tostring(ERR_TRADE_COMPLETE))

    section(L["Data"])
    local raid = ERF.Raid:Current()
    report("ok", L["imported raid"], raid and string.format("%s (#%d), %d %s, %d %s", raid.title, raid.id,
        Util.Count(raid.players), L["players"], #raid.loot, L["awards"]) or L["none"])
    report(ERF.db.version and "ok" or "warn", "SavedVariables", "schema v" .. tostring(ERF.db.version))

    if #Util.errors > 0 then
        section(L["Recent errors"])
        for i = 1, math.min(5, #Util.errors) do report("fail", Util.errors[i]) end
    end

    DEFAULT_CHAT_FRAME:AddMessage(string.format("|cffe8c46bEasyRaidForever|r: %d ok, %d %s, %d %s.",
        counts.ok, counts.warn, L["warnings"], counts.fail, L["failures"]))
end
