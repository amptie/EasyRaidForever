-- =============================================================================
-- EasyRaidForever - Core/Util.lua
-- Small, dependency-free helpers used by every other module.
-- Loaded before Core, so nothing in here may touch ERF.db at load time.
--
-- WoW: Forever notes (see _data/WoW_Forever_API.md):
--  * Unit names can be SECRET values inside instances / during restrictions.
--    A secret cannot be compared, used as a table key or parsed, so every name
--    that comes out of a unit or roster API passes through Util.Readable first.
--  * Names are stored as full "Name-Realm" strings. Retail-based clients send
--    addon messages with the realm attached, and stripping it would merge two
--    different players from connected realms.
-- =============================================================================

local ADDON_NAME, ERF = ...
local L = ERF.L

local Util = {}
ERF.Util = Util

-- ---------------------------------------------------------------------------
-- Colour palette (one place, so every page looks identical).
-- Near-black panels, thin gold hairline, gold accent text. 0-1 RGB(A).
-- ---------------------------------------------------------------------------
Util.COLORS = {
    GOLD        = { 0.91, 0.77, 0.42 },
    GOLD_DIM    = { 0.91, 0.77, 0.42, 0.45 },
    PANEL_BG    = { 0.047, 0.055, 0.071, 0.97 },
    SUB_BG      = { 0.02, 0.02, 0.03, 0.50 },
    ROW_BG      = { 1, 1, 1, 0.03 },
    ROW_BG_ALT  = { 1, 1, 1, 0.06 },
    HAIRLINE    = { 1, 1, 1, 0.10 },
    TEXT        = { 0.87, 0.90, 0.96 },
    TEXT_DIM    = { 0.55, 0.58, 0.66 },
    GREEN       = { 0.32, 0.78, 0.45 },
    RED         = { 0.87, 0.35, 0.30 },
    BLUE        = { 0.31, 0.58, 0.84 },
    ORANGE      = { 0.95, 0.60, 0.25 },
}

Util.CHAT_GOLD  = "|cffe8c46b"
Util.CHAT_GREEN = "|cff52c773"
Util.CHAT_RED   = "|cffdd5a4d"
Util.CHAT_GREY  = "|cff8c94a6"
Util.CHAT_WHITE = "|cffffffff"
Util.CHAT_RESET = "|r"

-- ---------------------------------------------------------------------------
-- Output
-- ---------------------------------------------------------------------------
function Util.Print(msg, ...)
    if select("#", ...) > 0 then msg = string.format(msg, ...) end
    DEFAULT_CHAT_FRAME:AddMessage(Util.CHAT_GOLD .. "EasyRaidForever" .. Util.CHAT_RESET .. ": " .. tostring(msg))
end

function Util.Debug(msg, ...)
    if not (ERF.db and ERF.db.options and ERF.db.options.debug) then return end
    if select("#", ...) > 0 then msg = string.format(msg, ...) end
    DEFAULT_CHAT_FRAME:AddMessage(Util.CHAT_GREY .. "[ERF] " .. tostring(msg) .. Util.CHAT_RESET)
end

-- Last few swallowed errors, so /erf check can show them even with debug off.
-- The client stops reporting Lua errors after 100 per session, so a guarded
-- error that is only printed would easily go unnoticed during a long raid.
Util.errors = {}

-- pcall wrapper used on every callback boundary. A broken page or handler
-- must never take the whole addon (or the player's UI) down with it.
function Util.Guard(fn, tag, ...)
    local ok, err = pcall(fn, ...)
    if not ok then
        local line = tostring(tag) .. ": " .. tostring(err)
        table.insert(Util.errors, 1, line)
        if #Util.errors > 20 then table.remove(Util.errors) end
        Util.Debug("error in %s", line)
    end
    return ok, err
end

-- ---------------------------------------------------------------------------
-- Secret values (Midnight / Forever restriction system)
-- ---------------------------------------------------------------------------

-- True when `v` is a secret value this code may not inspect.
function Util.IsSecret(v)
    return issecretvalue ~= nil and issecretvalue(v) == true
end

-- Returns `v` when it is a normal, inspectable value, nil when it is secret.
function Util.Readable(v)
    if v == nil or Util.IsSecret(v) then return nil end
    return v
end

-- True while any addon restriction (combat, encounter, M+, PvP, map, chat) is
-- active. Used to postpone work that reads unit data.
function Util.IsRestricted()
    if C_RestrictedActions and C_RestrictedActions.IsAddOnRestrictionActive and Enum.AddOnRestrictionType then
        for _, kind in pairs(Enum.AddOnRestrictionType) do
            local ok, active = pcall(C_RestrictedActions.IsAddOnRestrictionActive, kind)
            if ok and active then return true end
        end
    end
    return InCombatLockdown() and true or false
end

-- ---------------------------------------------------------------------------
-- Tables (Lua 5.1)
-- ---------------------------------------------------------------------------
function Util.CopyTable(src)
    if type(src) ~= "table" then return src end
    local out = {}
    for k, v in pairs(src) do
        out[k] = (type(v) == "table") and Util.CopyTable(v) or v
    end
    return out
end

function Util.Count(t)
    if type(t) ~= "table" then return 0 end
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end

function Util.Contains(t, needle)
    if type(t) ~= "table" then return false end
    for i = 1, #t do
        if t[i] == needle then return true end
    end
    return false
end

function Util.SortedKeys(t, cmp)
    local keys = {}
    if type(t) == "table" then
        for k in pairs(t) do keys[#keys + 1] = k end
    end
    table.sort(keys, cmp)
    return keys
end

-- Deep equality for plain data tables (no metatables, no cycles).
function Util.DeepEqual(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    for k, v in pairs(a) do
        if not Util.DeepEqual(v, b[k]) then return false end
    end
    for k in pairs(b) do
        if a[k] == nil then return false end
    end
    return true
end

-- ---------------------------------------------------------------------------
-- Strings
-- ---------------------------------------------------------------------------
function Util.Trim(s)
    return (string.gsub(tostring(s or ""), "^%s*(.-)%s*$", "%1"))
end

function Util.Truncate(text, max)
    text = tostring(text or "")
    if #text <= max then return text end
    return string.sub(text, 1, math.max(1, max - 3)) .. "..."
end

function Util.ColorHex(r, g, b)
    return string.format("|cff%02x%02x%02x",
        math.floor((r or 1) * 255 + 0.5),
        math.floor((g or 1) * 255 + 0.5),
        math.floor((b or 1) * 255 + 0.5))
end

function Util.Colorize(text, color)
    return Util.ColorHex(color[1], color[2], color[3]) .. tostring(text) .. "|r"
end

-- Case-insensitive plain substring test, used by every search box.
function Util.Matches(text, query)
    if not query or query == "" then return true end
    return string.find(string.lower(tostring(text or "")), string.lower(query), 1, true) ~= nil
end

-- ---------------------------------------------------------------------------
-- Time. GetServerTime is used for everything that is shared between clients,
-- so two players with different local clocks still agree on ordering.
-- ---------------------------------------------------------------------------
function Util.Now()
    return GetServerTime and GetServerTime() or time()
end

function Util.FormatDate(ts)
    if not ts then return "-" end
    return date("%Y-%m-%d %H:%M", ts)
end

function Util.FormatDay(ts)
    if not ts then return "-" end
    return date("%a %d.%m.", ts)
end

-- Parses "YYYY-MM-DD HH:MM" (time optional). Returns a timestamp or nil.
function Util.ParseDate(text)
    text = Util.Trim(text)
    local y, m, d, hh, mm = string.match(text, "^(%d%d%d%d)%-(%d%d?)%-(%d%d?)%s*(%d?%d?):?(%d?%d?)$")
    if not y then
        -- German style "DD.MM.YYYY HH:MM"
        d, m, y, hh, mm = string.match(text, "^(%d%d?)%.(%d%d?)%.(%d%d%d%d)%s*(%d?%d?):?(%d?%d?)$")
    end
    if not y then return nil end
    local ok, ts = pcall(time, {
        year = tonumber(y), month = tonumber(m), day = tonumber(d),
        hour = tonumber(hh) or 20, min = tonumber(mm) or 0, sec = 0,
    })
    if ok then return ts end
    return nil
end

-- Unique-enough id for orgs, teams and events: time + random + player hash.
-- Two clients would have to create an object in the same second AND roll the
-- same 20-bit random number to collide.
local idCounter = 0
function Util.NewId()
    idCounter = idCounter + 1
    local seed = 0
    local me = ERF.playerName or "?"
    for i = 1, #me do seed = (seed * 31 + string.byte(me, i)) % 65521 end
    return string.format("%x%04x%05x%x", Util.Now(), seed, math.random(0, 0xFFFFF), idCounter % 16)
end

-- ---------------------------------------------------------------------------
-- Player names
-- ---------------------------------------------------------------------------

local myRealm
local function MyRealm()
    if not myRealm or myRealm == "" then
        myRealm = GetNormalizedRealmName and GetNormalizedRealmName() or nil
        if not myRealm or myRealm == "" then
            myRealm = string.gsub(GetRealmName() or "", "[%s%-]", "")
        end
    end
    return myRealm
end

-- WoW: FOREVER NAMES
-- Characters have a first name AND a surname. The game shows them with a
-- space ("Cele Brimbrum"); the technical, unique form - used by whispers and
-- addon message senders - joins them with a hyphen ("Cele-Brimbrum"), in the
-- place where retail has the realm. The addon stores that hyphen form and
-- shows the space form.

-- Any spelling -> the stored form:
--   "Cele Brimbrum" / "Cele-Brimbrum" -> "Cele-Brimbrum"
--   "Cele" (no second part)           -> "Cele-<own realm>" (retail style fallback)
-- Returns nil for secret or empty input.
function Util.FullName(name)
    name = Util.Readable(name)
    if type(name) ~= "string" then return nil end
    name = Util.Trim(name)
    if name == "" then return nil end
    if string.find(name, "-", 1, true) then return name end
    local first, second = string.match(name, "^(%S+)%s+(.+)$")
    if first then return first .. "-" .. (string.gsub(second, "%s+", "")) end
    local realm = MyRealm()
    if realm and realm ~= "" then return name .. "-" .. realm end
    return name
end

-- Display form: "Cele-Brimbrum" -> "Cele Brimbrum"; a suffix that is our own
-- realm (retail style) is hidden.
function Util.ShortName(name)
    if type(name) ~= "string" then return "?" end
    local realm = MyRealm()
    if realm and realm ~= "" then
        local base = string.match(name, "^(.-)%-" .. string.gsub(realm, "%p", "%%%0") .. "$")
        if base then return base end
    end
    return (string.gsub(name, "%-", " ", 1))
end

function Util.PlayerName()
    local name, realm = UnitFullName("player")
    name = Util.Readable(name)
    realm = Util.Readable(realm)
    if name and realm and realm ~= "" then return name .. "-" .. realm end
    return Util.FullName(name or UnitName("player") or "Unknown")
end

-- Class-coloured display name. `class` is a class file token ("WARRIOR").
function Util.ClassName(name, class)
    local short = Util.ShortName(name)
    if not class then return short end
    local c
    if C_ClassColor and C_ClassColor.GetClassColor then
        c = C_ClassColor.GetClassColor(class)
    end
    c = c or (RAID_CLASS_COLORS and RAID_CLASS_COLORS[class])
    if not c then return short end
    return Util.ColorHex(c.r, c.g, c.b) .. short .. "|r"
end

-- Localised class name for a class token.
function Util.ClassLabel(class)
    if not class then return "-" end
    if LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[class] then
        return LOCALIZED_CLASS_NAMES_MALE[class]
    end
    return class
end

-- ---------------------------------------------------------------------------
-- Group
-- ---------------------------------------------------------------------------

-- "RAID", "PARTY", "INSTANCE_CHAT" or nil when solo.
function Util.GroupChannel()
    if LE_PARTY_CATEGORY_INSTANCE and IsInGroup(LE_PARTY_CATEGORY_INSTANCE)
        and not IsInGroup(LE_PARTY_CATEGORY_HOME) then
        return "INSTANCE_CHAT"
    end
    if IsInRaid() then return "RAID" end
    if IsInGroup() then return "PARTY" end
    return nil
end

-- Full ID of a unit: UnitName returns (first name, surname) on Forever
-- (retail: name, realm). Returns nil when the name is secret.
function Util.UnitID(unit)
    local name, second = UnitName(unit)
    if Util.IsSecret(name) or not name then return nil end
    second = Util.Readable(second)
    if second and second ~= "" then return name .. "-" .. second end
    return Util.FullName(name)
end

-- Like FullName, but a bare first name ("Gutschy") is first looked up in the
-- current group and the active organisation, so it resolves to the right
-- "Gutschy-Shamane" instead of getting the realm appended. Used for names
-- from chat lines and typed input.
function Util.ResolveName(name)
    name = Util.Readable(name)
    if type(name) ~= "string" then return nil end
    name = Util.Trim(name)
    if name == "" then return nil end
    if string.find(name, "[-%s]") then return Util.FullName(name) end
    local lower = string.lower(name)
    local function pick(list)
        local found
        for _, full in ipairs(list) do
            local first = string.match(full, "^([^-]+)")
            if first and string.lower(first) == lower then
                if found and found ~= full then return nil, true end   -- ambiguous
                found = full
            end
        end
        return found
    end
    local names = {}
    for _, r in ipairs((Util.GroupRoster())) do names[#names + 1] = r.name end
    local hit, ambiguous = pick(names)
    if hit or ambiguous then return hit or Util.FullName(name) end
    -- Namen aus dem Import der Webseite (Reservierungen)
    if ERF.Raid and ERF.db then
        hit = pick(ERF.Raid:KnownNames())
        if hit then return hit end
    end
    return Util.FullName(name)
end

-- Current group as { { name, class, online, zone, subgroup }, ... }.
-- Entries whose name is secret are skipped and counted in the second return,
-- so callers can tell "nobody there" from "could not read it right now".
function Util.GroupRoster()
    local roster, secret = {}, 0

    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            local name, _, subgroup, _, _, fileName, zone, online = GetRaidRosterInfo(i)
            -- The unit API reliably carries the surname; the roster name may not.
            local full = Util.UnitID("raid" .. i) or Util.FullName(name)
            if full then
                roster[#roster + 1] = {
                    name = full,
                    class = Util.Readable(fileName),
                    online = Util.Readable(online) and true or false,
                    zone = Util.Readable(zone),
                    subgroup = Util.Readable(subgroup),
                }
            elseif name ~= nil then
                secret = secret + 1
            end
        end
        return roster, secret
    end

    local units = { "player" }
    if IsInGroup() then
        for i = 1, GetNumSubgroupMembers() do units[#units + 1] = "party" .. i end
    end
    for _, unit in ipairs(units) do
        local name = UnitName(unit)
        if Util.IsSecret(name) then
            secret = secret + 1
        elseif name then
            local full = Util.UnitID(unit)
            local _, class = UnitClass(unit)
            roster[#roster + 1] = {
                name = full,
                class = Util.Readable(class),
                online = Util.Readable(UnitIsConnected(unit)) and true or false,
                subgroup = 1,
            }
        end
    end
    return roster, secret
end

function Util.IsGroupLeaderOrAssist()
    if not IsInGroup() then return true end
    return UnitIsGroupLeader("player") or (IsInRaid() and UnitIsGroupAssistant("player")) or false
end

-- Class of the player's current target, or of a group member by name.
function Util.ClassOf(name)
    if not name then return nil end
    local roster = Util.GroupRoster()
    for i = 1, #roster do
        if roster[i].name == name then return roster[i].class end
    end
    if name == ERF.playerName then
        local _, class = UnitClass("player")
        return class
    end
    return nil
end
