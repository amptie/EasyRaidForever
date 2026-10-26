-- =============================================================================
-- EasyRaidForever - Raid/Raid.lua
--
-- The raid imported from the guild website (Raid/Transfer.lua decodes it).
-- The player who imports it is the LOOT MASTER of this raid: only their client
-- starts rolls and records awards. Other raid members need no import - they
-- get every roll (with their own SR+ bonus) through addon messages.
--
--   ERF.db.raid = {
--     id, title, start, instance, group,          -- from the website
--     system = "SRPLUS"|"SR"|"NONE", reserves, bonus (roll bonus per SR+ point),
--     players  = { [key] = { name, class, ms, ds, items = { [itemId] = points } } },
--     items    = { [itemId] = { n = name, b = boss } },   -- item list of the instance
--     leader, importedAt, lastBoss,
--     loot     = { { i, n, k, b, t, r, sp }, ... },      -- awarded items (exported to the website)
--     pend     = { ... },                                -- loot master list (Loot.lua)
--   }
--
-- NAMES: WoW Forever characters have a first name and a surname ("Cele-Brimbrum"
-- internally, "Cele Brimbrum" on screen); the website usually knows only the first
-- name. Players are therefore matched by Raid.Key = lower-case first name.
-- =============================================================================

local ADDON_NAME, ERF = ...
local L = ERF.L
local Util = ERF.Util

local Raid = {}
ERF.Raid = Raid

-- Roll buttons for items nobody reserved, in priority order (MS > DS > OS > Greed).
-- The /roll range tells which button a roll belongs to (players without the addon
-- simply type e.g. /roll 99 for dual spec).
Raid.ROLL_OPTIONS = {
    { label = "MS", cap = 100 },
    { label = "DS", cap = 99 },
    { label = "OS", cap = 98 },
    { label = "Greed", cap = 97 },
    { label = "Pass", cap = 0 },
}
Raid.SR_OPTION = { label = "SR", cap = 100 }

-- Loot kinds as recorded and exported to the website
Raid.LOOT_KINDS = { "SR", "MS", "DS", "OS", "GREED", "DE" }
Raid.LOOT_KIND_NAMES = {
    SR = "SR", MS = L["Main spec"], DS = L["Dual spec"], OS = L["Off spec"], GREED = L["Greed"], DE = L["Disenchant"],
}
Raid.LOOT_KIND_COLORS = {
    SR = Util.COLORS.GOLD, MS = Util.COLORS.GREEN, DS = Util.COLORS.BLUE, OS = Util.COLORS.TEXT,
    GREED = Util.COLORS.TEXT_DIM, DE = Util.COLORS.ORANGE,
}

function Raid:LootKind(label)
    local key = string.upper(Util.Trim(label or ""))
    if key == "DISENCHANT" then key = "DE" end
    return key ~= "" and key or "MS"
end

-- "Cele-Brimbrum" / "Cele Brimbrum" / "cele" -> "cele"
function Raid.Key(name)
    if type(name) ~= "string" then return nil end
    local first = string.match(Util.Trim(name), "^([^%-%s]+)")
    return first and string.lower(first) or nil
end

-- ---------------------------------------------------------------------------
-- Access
-- ---------------------------------------------------------------------------
function Raid:Current()
    return ERF.db and ERF.db.raid or nil
end

function Raid:IsLeader()
    local raid = self:Current()
    return raid ~= nil and raid.leader == ERF.playerName
end

function Raid:PlayerOf(name)
    local raid = self:Current()
    local key = Raid.Key(name)
    return raid and key and raid.players[key] or nil
end

-- SR+ points of a player on an item (0 without SR+ or reserve).
function Raid:Points(name, itemId)
    local raid = self:Current()
    if not raid or raid.system ~= "SRPLUS" then return 0 end
    local p = self:PlayerOf(name)
    return p and p.items[itemId] or 0
end

function Raid:Bonus(name, itemId)
    local raid = self:Current()
    return self:Points(name, itemId) * (raid and raid.bonus or 10)
end

-- Did this player reserve the item?
function Raid:HasReserved(name, itemId)
    local p = self:PlayerOf(name)
    return p ~= nil and p.items[itemId] ~= nil
end

-- [itemId] = { player, ... } for all reserved items
function Raid:Reservers()
    local raid = self:Current()
    local map = {}
    if not raid or raid.system == "NONE" then return map end
    for _, p in pairs(raid.players) do
        for itemId in pairs(p.items) do
            map[itemId] = map[itemId] or {}
            table.insert(map[itemId], p)
        end
    end
    return map
end

-- Spec a winner rolled for: main spec for SR / MS / Greed, dual spec for DS.
function Raid:SpecFor(name, kind)
    local p = self:PlayerOf(name)
    if not p then return nil end
    if kind == "DS" then return p.ds end
    if kind == "SR" or kind == "MS" or kind == "GREED" then return p.ms end
    return nil
end

function Raid:ClassOf(name)
    local p = self:PlayerOf(name)
    return p and p.class or Util.ClassOf(name)
end

-- Names known from the import (used to resolve bare first names from chat lines).
function Raid:KnownNames()
    local raid = self:Current()
    local out = {}
    if not raid then return out end
    for _, p in pairs(raid.players) do out[#out + 1] = Util.FullName(p.name) end
    return out
end

function Raid:IsKnownItem(itemId)
    local raid = self:Current()
    return raid ~= nil and raid.items[itemId] ~= nil
end

-- Item IDs from links ("item:12345:...") or plain numbers.
function Raid:ParseItemIds(text)
    local ids, seen = {}, {}
    text = tostring(text or "")
    for id in string.gmatch(text, "item:(%d+)") do
        id = tonumber(id)
        if id and not seen[id] then seen[id] = true ids[#ids + 1] = id end
    end
    if #ids == 0 then
        for id in string.gmatch(text, "(%d+)") do
            id = tonumber(id)
            if id and id > 0 and not seen[id] then seen[id] = true ids[#ids + 1] = id end
        end
    end
    return ids
end

-- ---------------------------------------------------------------------------
-- Import (payload decoded by Transfer.lua)
-- ---------------------------------------------------------------------------
local CLASS_TOKENS = {
    warrior = "WARRIOR", paladin = "PALADIN", hunter = "HUNTER", rogue = "ROGUE", priest = "PRIEST",
    shaman = "SHAMAN", mage = "MAGE", warlock = "WARLOCK", druid = "DRUID",
}

-- Returns raid or nil, reason. Re-importing the same raid keeps the loot awarded so far.
function Raid:Import(p)
    if type(p) ~= "table" or type(p.raid) ~= "table" or type(p.raid.id) ~= "number" then
        return nil, L["The string could not be read."]
    end
    local old = self:Current()
    local keep = old and old.id == p.raid.id
    local raid = {
        id = p.raid.id,
        title = tostring(p.raid.title or "?"),
        start = tonumber(p.raid.start),
        instance = type(p.raid.instance) == "string" and p.raid.instance or nil,
        group = type(p.raid.group) == "string" and p.raid.group or nil,
        system = (p.loot and (p.loot.system == "SRPLUS" or p.loot.system == "SR")) and p.loot.system or "NONE",
        reserves = tonumber(p.loot and p.loot.reserves) or 1,
        bonus = tonumber(p.loot and p.loot.bonus) or 10,
        players = {},
        items = {},
        leader = ERF.playerName,
        importedAt = Util.Now(),
        lastBoss = keep and old.lastBoss or nil,
        loot = keep and old.loot or {},
        pend = keep and old.pend or {},
    }
    for _, pl in ipairs(type(p.players) == "table" and p.players or {}) do
        local key = type(pl.n) == "string" and Raid.Key(pl.n)
        if key then
            local items = {}
            for _, r in ipairs(type(pl.r) == "table" and pl.r or {}) do
                if type(r.i) == "number" then items[r.i] = tonumber(r.p) or 0 end
            end
            raid.players[key] = {
                name = pl.n,
                class = CLASS_TOKENS[pl.c] or (type(pl.c) == "string" and string.upper(pl.c)) or nil,
                ms = type(pl.ms) == "string" and pl.ms ~= "" and pl.ms or nil,
                ds = type(pl.ds) == "string" and pl.ds ~= "" and pl.ds or nil,
                items = items,
            }
        end
    end
    for _, it in ipairs(type(p.items) == "table" and p.items or {}) do
        if type(it.i) == "number" then raid.items[it.i] = { n = it.n, b = it.b } end
    end
    ERF.db.raid = raid
    if not keep then ERF.Loot:Restore() end
    ERF:Notify("RAID")
    return raid
end

function Raid:Clear()
    ERF.db.raid = nil
    ERF.Loot:Restore()
    ERF:Notify("RAID")
end

-- ---------------------------------------------------------------------------
-- Boss kills (the boss an item drops from)
-- ---------------------------------------------------------------------------
function Raid:Init()
    ERF:RegisterEventHandler("ENCOUNTER_END", function(_, encounterId, name, difficulty, size, success)
        local raid = Raid:Current()
        if not raid then return end
        if Util.Readable(success) == 1 then
            local readable = Util.Readable(name)
            if type(readable) == "string" then
                raid.lastBoss = readable
                ERF:Notify("RAID")
            end
        end
    end)
end
