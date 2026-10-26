-- =============================================================================
-- EasyRaidForever - Raid/Transfer.lua
--
-- Text strings between the guild website and the addon (copy & paste):
--
--   SIR1:<checksum8>:<base64>   website -> addon   ("Export for addon" on the website)
--     { v = 1, raid = { id, title, start, instance, group },
--       loot = { system, reserves, bonus },
--       players = { { n, c, ms, ds, r = { { i = itemId, p = points }, ... } }, ... },
--       items = { { i, n, b }, ... }, at }
--
--   SIL1:<checksum8>:<base64>   addon -> website   ("Export for website" here)
--     { v = 1, raid = id, at, loot = { { i = itemId, n = name, k = kind, b = boss, t = time, r = roll, sp = spec }, ... } }
--
-- Body = base64 of the serialized table (Core/Serializer.lua, never compressed so
-- the website can read it without a decompressor); checksum = Serializer.Checksum
-- of the serialized data. The website (lib/addon.js) implements the same format.
-- =============================================================================

local ADDON_NAME, ERF = ...
local L = ERF.L
local Util = ERF.Util
local S = ERF.Serializer

local Transfer = {}
ERF.Transfer = Transfer

local HEADER_IN = "SIR1"
local HEADER_OUT = "SIL1"

-- Returns payload or nil, reason
function Transfer:DecodeImport(text)
    text = string.gsub(text or "", "%s", "")
    local header, sum, body = string.match(text, "^(%w+):(%x+):(.+)$")
    if header ~= HEADER_IN then
        return nil, L["This is not an export of the guild website (it must start with SIR1:)."]
    end
    local data = S.FromBase64(body)
    if not data or S.Checksum(data) ~= sum then
        return nil, L["The string is damaged (checksum mismatch). Copy it again completely."]
    end
    local payload, err = S.Deserialize(data)
    if type(payload) ~= "table" then
        return nil, L["The string could not be read."] .. " " .. tostring(err)
    end
    return payload
end

-- Imports a website export. Returns raid or nil, reason.
function Transfer:Import(text)
    local payload, why = self:DecodeImport(text)
    if not payload then return nil, why end
    return ERF.Raid:Import(payload)
end

-- Loot of the current raid for the website. Returns text or nil, reason.
function Transfer:ExportLoot()
    local raid = ERF.Raid:Current()
    if not raid then return nil, L["No raid imported."] end
    local loot = {}
    for _, e in ipairs(raid.loot or {}) do
        loot[#loot + 1] = { i = e.i, n = Util.ShortName(e.n), k = e.k, b = e.b, t = e.t, r = e.r, sp = e.sp }
    end
    local data = S.Serialize({ v = 1, raid = raid.id, at = Util.Now(), loot = loot })
    return HEADER_OUT .. ":" .. S.Checksum(data) .. ":" .. S.ToBase64(data), #loot
end
