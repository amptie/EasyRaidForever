-- =============================================================================
-- EasyRaidForever - Core/Serializer.lua
--
-- Turns plain Lua data (tables, strings, numbers, booleans) into a string and
-- back. Used for addon messages and for the export/backup string.
--
-- Format (no loadstring anywhere - data from other players is untrusted):
--   s<len>:<bytes>   string, length-prefixed so it never needs escaping
--   n<number>;       number
--   T / F            true / false
--   { k v k v ... }  table: alternating key and value, closed by "}"
--
-- Base64 + a checksum wrap the export string so it survives copy & paste
-- through forums, Discord and chat line wrapping.
-- =============================================================================

local ADDON_NAME, ERF = ...

local S = {}
ERF.Serializer = S

local MAX_DEPTH = 20

local function Write(v, out, depth)
    local t = type(v)
    if t == "string" then
        out[#out + 1] = "s" .. #v .. ":" .. v
    elseif t == "number" then
        -- %.17g keeps full precision; integers stay short.
        if v == math.floor(v) and math.abs(v) < 2^53 then
            -- %.0f rather than %d: %d may be a 32-bit int on some builds.
            out[#out + 1] = string.format("n%.0f;", v)
        else
            out[#out + 1] = string.format("n%.17g;", v)
        end
    elseif t == "boolean" then
        out[#out + 1] = v and "T" or "F"
    elseif t == "table" then
        if depth > MAX_DEPTH then error("table too deep") end
        out[#out + 1] = "{"
        for k, val in pairs(v) do
            local kt, vt = type(k), type(val)
            if (kt == "string" or kt == "number") and
               (vt == "string" or vt == "number" or vt == "boolean" or vt == "table") then
                Write(k, out, depth + 1)
                Write(val, out, depth + 1)
            end
        end
        out[#out + 1] = "}"
    else
        error("cannot serialize " .. t)
    end
end

function S.Serialize(v)
    local out = {}
    Write(v, out, 0)
    return table.concat(out)
end

-- Returns value, nextPos  or  nil, errorMessage
local function Read(str, pos, depth)
    if depth > MAX_DEPTH then return nil, "too deep" end
    local c = string.sub(str, pos, pos)
    if c == "s" then
        local colon = string.find(str, ":", pos + 1, true)
        if not colon then return nil, "bad string" end
        local len = tonumber(string.sub(str, pos + 1, colon - 1))
        if not len or len < 0 or colon + len > #str then return nil, "bad string length" end
        return string.sub(str, colon + 1, colon + len), colon + len + 1
    elseif c == "n" then
        local semi = string.find(str, ";", pos + 1, true)
        if not semi then return nil, "bad number" end
        local n = tonumber(string.sub(str, pos + 1, semi - 1))
        if not n then return nil, "bad number" end
        return n, semi + 1
    elseif c == "T" then
        return true, pos + 1
    elseif c == "F" then
        return false, pos + 1
    elseif c == "{" then
        local tbl = {}
        pos = pos + 1
        while true do
            if pos > #str then return nil, "unterminated table" end
            if string.sub(str, pos, pos) == "}" then return tbl, pos + 1 end
            local k, v
            k, pos = Read(str, pos, depth + 1)
            if k == nil then return nil, pos end
            if type(k) == "table" or type(k) == "boolean" then return nil, "bad key" end
            v, pos = Read(str, pos, depth + 1)
            if v == nil then return nil, pos end
            tbl[k] = v
        end
    end
    return nil, "unexpected '" .. c .. "' at " .. pos
end

function S.Deserialize(str)
    if type(str) ~= "string" or str == "" then return nil, "empty" end
    local ok, v, pos = pcall(Read, str, 1, 0)
    if not ok then return nil, tostring(v) end
    if v == nil then return nil, pos end
    if pos <= #str then return nil, "trailing data" end
    return v
end

-- ---------------------------------------------------------------------------
-- Base64 (RFC 4648 alphabet)
-- ---------------------------------------------------------------------------
local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local B64_INDEX = {}
for i = 1, 64 do B64_INDEX[string.byte(B64, i)] = i - 1 end

function S.ToBase64(data)
    local out = {}
    for i = 1, #data, 3 do
        local a, b, c = string.byte(data, i, i + 2)
        local n = a * 65536 + (b or 0) * 256 + (c or 0)
        local c1 = math.floor(n / 262144) % 64
        local c2 = math.floor(n / 4096) % 64
        local c3 = math.floor(n / 64) % 64
        local c4 = n % 64
        out[#out + 1] = string.sub(B64, c1 + 1, c1 + 1) .. string.sub(B64, c2 + 1, c2 + 1)
            .. (b and string.sub(B64, c3 + 1, c3 + 1) or "=")
            .. (c and string.sub(B64, c4 + 1, c4 + 1) or "=")
    end
    return table.concat(out)
end

function S.FromBase64(text)
    text = string.gsub(text or "", "[^%w%+/=]", "")
    local out = {}
    for i = 1, #text, 4 do
        local q = { string.byte(text, i, i + 3) }
        local n, pad = 0, 0
        for j = 1, 4 do
            local ch = q[j]
            local v
            if ch == nil or ch == 61 then -- "="
                v = 0
                pad = pad + 1
            else
                v = B64_INDEX[ch]
                if not v then return nil end
            end
            n = n * 64 + v
        end
        local a = math.floor(n / 65536) % 256
        local b = math.floor(n / 256) % 256
        local c = n % 256
        if pad >= 3 then return nil end
        out[#out + 1] = string.char(a)
        if pad < 2 then out[#out + 1] = string.char(b) end
        if pad < 1 then out[#out + 1] = string.char(c) end
    end
    return table.concat(out)
end

-- ---------------------------------------------------------------------------
-- Compression (LibDeflate, bundled). Addon messages regenerate at roughly one
-- per second per prefix, so size is sync speed: an organisation's core with a
-- hundred members shrinks to about a third.
--
-- Compressed data is marked with a leading "~"; uncompressed serialized data
-- always starts with "{", so both forms can be told apart on arrival.
-- ---------------------------------------------------------------------------
local LD = LibStub and LibStub("LibDeflate", true)

function S.Pack(data, minSize)
    if LD and #data >= (minSize or 200) then
        local ok, packed = pcall(LD.CompressDeflate, LD, data)
        if ok and packed and #packed + 1 < #data then return "~" .. packed end
    end
    return data
end

function S.Unpack(data)
    if string.sub(data, 1, 1) ~= "~" then return data end
    if not LD then return nil end
    local ok, raw = pcall(LD.DecompressDeflate, LD, string.sub(data, 2))
    if ok then return raw end
    return nil
end

-- Adler-32 style checksum, 8 hex digits.
function S.Checksum(data)
    local a, b = 1, 0
    for i = 1, #data do
        a = (a + string.byte(data, i)) % 65521
        b = (b + a) % 65521
    end
    return string.format("%04x%04x", b, a)
end
