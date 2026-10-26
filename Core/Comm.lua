-- =============================================================================
-- EasyRaidForever - Core/Comm.lua
--
-- Transport layer: typed messages of any size over C_ChatInfo.SendAddonMessage.
--
-- WHY NOT AceComm / ChatThrottleLib: both ignore the result code of
-- SendAddonMessage. On WoW: Forever (Midnight rules) a send can be refused with
-- Enum.SendAddonMessageResult.AddOnMessageLockdown while chat messaging is
-- locked down (boss encounters, instances). A lib that fire-and-forgets simply
-- loses those messages. This layer keeps them queued and retries.
--
--  * Messages are serialized (Serializer.lua), escaped and split into pieces
--    of at most MAX_PIECE bytes: "\001" first, "\002" middle, "\003" last.
--    A message that fits one piece is sent as-is (it starts with "{").
--  * One message is sent completely before the next one starts, so pieces of
--    two messages can never interleave on the receiving side.
--  * Token bucket throttle (per prefix the server allows a burst of ~10 and
--    regenerates ~1 message per second). Throttle results reset the bucket.
--  * While InChatMessagingLockdown() is true nothing is sent; the queue waits.
--  * PRIORITY: live raid messages (rolls, reserves) jump ahead of data sync.
--    A single-piece live message may even go out between the pieces of a
--    large sync message: it carries no piece marker, so the receiver handles
--    it directly without touching its reassembly buffer.
--  * The sender identity is always the transport sender (server-authenticated),
--    never anything inside the payload. Sync.lua relies on that for security.
-- =============================================================================

local ADDON_NAME, ERF = ...
local Util = ERF.Util
local S = ERF.Serializer

local Comm = {}
ERF.Comm = Comm

Comm.PREFIX   = "ERF"
Comm.PROTOCOL = 1

local MAX_PIECE   = 250
local BURST       = 8       -- stay a little below the server allowance
local REGEN       = 1.0     -- tokens per second
local MAX_BUFFER  = 256 * 1024

local handlers = {}
local queue = {}            -- FIFO of outgoing messages (priority ones first)
local urgent = {}           -- single-piece priority messages, sent before anything else
local current               -- message currently being sent piece by piece
local tokens = BURST
local lockedUntil = 0
local buffers = {}          -- incoming partial messages, keyed sender|channel

Comm.stats = { sent = 0, received = 0, dropped = 0, lockdownWaits = 0 }

-- ---------------------------------------------------------------------------
-- Escaping: \0 is not allowed in addon messages, and "|" / line breaks are
-- avoided to be safe. \127 is the escape byte.
-- ---------------------------------------------------------------------------
local ESC = {
    ["\127"] = "\127\127", ["\0"] = "\127" .. "0", ["|"] = "\127p",
    ["\n"] = "\127n", ["\r"] = "\127r",
}
local UNESC = { ["\127"] = "\127", ["0"] = "\0", ["p"] = "|", ["n"] = "\n", ["r"] = "\r" }

local function Escape(s)
    return (string.gsub(s, "[%z\127|\n\r]", ESC))
end

local function Unescape(s)
    return (string.gsub(s, "\127(.)", UNESC))
end

-- ---------------------------------------------------------------------------
-- Lockdown
-- ---------------------------------------------------------------------------
function Comm:IsLocked()
    if C_ChatInfo and C_ChatInfo.InChatMessagingLockdown then
        local ok, locked = pcall(C_ChatInfo.InChatMessagingLockdown)
        if ok and locked then return true end
    end
    return GetTime() < lockedUntil
end

-- Message types that belong to a running raid and must not wait for sync data.
Comm.PRIORITY = { RB = true, RI = true, RP = true, RU = true, RW = true, RZ = true, SR = true, SRX = true, SP = true }

function Comm:QueueSize()
    return #queue + #urgent + (current and 1 or 0)
end

-- ---------------------------------------------------------------------------
-- Sending
-- ---------------------------------------------------------------------------
local sender = CreateFrame("Frame")
sender:Hide()

-- Result codes (Enum.SendAddonMessageResult); numbers as fallback.
local function ResultKind(result)
    if result == nil or result == true or result == 0 then return "OK" end
    if result == false then return "DROP" end
    local R = Enum and Enum.SendAddonMessageResult or {}
    if result == (R.AddonMessageThrottle or 3) or result == (R.ChannelThrottle or 8) then return "THROTTLE" end
    if result == (R.AddOnMessageLockdown or 11) then return "LOCKDOWN" end
    if result == (R.GeneralError or 9) then return "THROTTLE" end -- transient, retry
    return "DROP"
end

local function SendPiece(msg, piece)
    local ok, result = pcall(C_ChatInfo.SendAddonMessage, Comm.PREFIX, piece, msg.channel, msg.target)
    if not ok then
        Util.Debug("SendAddonMessage failed: %s", tostring(result))
        return "DROP"
    end
    return ResultKind(result), result
end

sender:SetScript("OnUpdate", function(self, elapsed)
    tokens = math.min(BURST, tokens + elapsed * REGEN)

    if not current then
        current = table.remove(queue, 1)
        if not current and #urgent == 0 then
            self:Hide()
            return
        end
    end

    if Comm:IsLocked() then return end

    while urgent[1] and tokens >= 1 do
        local msg = urgent[1]
        local kind, raw = SendPiece(msg, msg.pieces[1])
        if kind == "OK" then
            tokens = tokens - 1
            Comm.stats.sent = Comm.stats.sent + 1
            table.remove(urgent, 1)
        elseif kind == "THROTTLE" then
            tokens = 0
            return
        elseif kind == "LOCKDOWN" then
            Comm.stats.lockdownWaits = Comm.stats.lockdownWaits + 1
            lockedUntil = GetTime() + 2
            return
        else
            Util.Debug("dropped %s to %s (%s)", tostring(msg.msgType), tostring(msg.channel), tostring(raw))
            Comm.stats.dropped = Comm.stats.dropped + 1
            table.remove(urgent, 1)
        end
    end

    while current and tokens >= 1 do
        local piece = current.pieces[current.idx]
        local kind, raw = SendPiece(current, piece)
        if kind == "OK" then
            tokens = tokens - 1
            current.idx = current.idx + 1
            if current.idx > #current.pieces then
                Comm.stats.sent = Comm.stats.sent + 1
                current = table.remove(queue, 1)
            end
        elseif kind == "THROTTLE" then
            tokens = 0
            return
        elseif kind == "LOCKDOWN" then
            Comm.stats.lockdownWaits = Comm.stats.lockdownWaits + 1
            lockedUntil = GetTime() + 2
            return
        else
            Util.Debug("dropped %s to %s (%s)", tostring(current.msgType), tostring(current.channel), tostring(raw))
            Comm.stats.dropped = Comm.stats.dropped + 1
            current = table.remove(queue, 1)
        end
    end
end)

-- Queues `payload` (plain data) as message type `msgType`.
-- `channel`: "GUILD", "RAID", "PARTY", "INSTANCE_CHAT" or "WHISPER" (+ target).
-- `dedupeKey` (optional): a queued, not yet started message with the same key
-- is replaced in place - a newer version of the same data makes the older
-- one pointless, and under the throttle every saved piece counts.
-- `urgentFlag` gives any message the priority of live raid messages.
function Comm:Send(msgType, payload, channel, target, dedupeKey, urgentFlag)
    if not channel then return false end
    if channel == "WHISPER" and not target then return false end
    if channel == "GUILD" and not IsInGuild() then return false end

    local ok, data = pcall(S.Serialize, { t = msgType, v = Comm.PROTOCOL, p = payload })
    if not ok then
        Util.Debug("serialize %s failed: %s", msgType, tostring(data))
        return false
    end
    data = Escape(S.Pack(data))

    local pieces = {}
    if #data <= MAX_PIECE then
        pieces[1] = data
    else
        local size = MAX_PIECE - 1
        local count = math.ceil(#data / size)
        for i = 1, count do
            local chunk = string.sub(data, (i - 1) * size + 1, i * size)
            local marker = (i == 1) and "\001" or ((i == count) and "\003" or "\002")
            pieces[i] = marker .. chunk
        end
    end

    local priority = Comm.PRIORITY[msgType] == true or urgentFlag == true
    local msg = {
        msgType = msgType, pieces = pieces, idx = 1, priority = priority,
        channel = channel, target = target, dedupeKey = dedupeKey,
    }
    local list = (priority and #pieces == 1) and urgent or queue
    if dedupeKey then
        for i = 1, #list do
            if list[i].dedupeKey == dedupeKey then
                list[i] = msg
                sender:Show()
                return true
            end
        end
    end
    if list == queue and priority then
        -- Behind the other priority messages, ahead of all sync data.
        local pos = 1
        while queue[pos] and queue[pos].priority do pos = pos + 1 end
        table.insert(queue, pos, msg)
    else
        list[#list + 1] = msg
    end
    sender:Show()
    return true
end

-- ---------------------------------------------------------------------------
-- Receiving
-- ---------------------------------------------------------------------------
function Comm:RegisterHandler(msgType, fn)
    handlers[msgType] = fn
end

local function Dispatch(senderName, data, channel)
    local raw = S.Unpack(Unescape(data))
    if not raw then
        Util.Debug("could not decompress message from %s", senderName)
        return
    end
    local msg, err = S.Deserialize(raw)
    if type(msg) ~= "table" or type(msg.t) ~= "string" then
        Util.Debug("bad message from %s: %s", senderName, tostring(err))
        return
    end
    if type(msg.v) == "number" and msg.v > Comm.PROTOCOL then
        -- A newer addon version: its format may differ. Tell the user once.
        if not Comm.newerVersionSeen then
            Comm.newerVersionSeen = true
            Util.Print(ERF.L["%s uses a newer EasyRaidForever version - please update."], Util.ShortName(senderName))
        end
    end
    local fn = handlers[msg.t]
    if fn then
        Comm.stats.received = Comm.stats.received + 1
        Util.Guard(fn, "comm:" .. msg.t, senderName, msg.p, channel)
    end
end

function Comm:OnAddonMessage(prefix, text, channel, senderName)
    if prefix ~= Comm.PREFIX then return end
    if Util.IsSecret(text) or Util.IsSecret(senderName) or Util.IsSecret(channel) then return end
    senderName = Util.FullName(senderName)
    if not senderName or senderName == ERF.playerName then return end
    if type(text) ~= "string" or text == "" then return end

    local key = senderName .. "|" .. tostring(channel)
    local marker = string.byte(text, 1)

    if marker == 1 then
        buffers[key] = { string.sub(text, 2) }
    elseif marker == 2 or marker == 3 then
        local buf = buffers[key]
        if not buf then return end -- missed the start; the sync layer re-requests
        buf[#buf + 1] = string.sub(text, 2)
        buf.size = (buf.size or 0) + #text
        if buf.size > MAX_BUFFER then
            buffers[key] = nil
            return
        end
        if marker == 3 then
            buffers[key] = nil
            Dispatch(senderName, table.concat(buf), channel)
        end
    else
        Dispatch(senderName, text, channel)
    end
end

function Comm:Init()
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
        C_ChatInfo.RegisterAddonMessagePrefix(Comm.PREFIX)
    end
    ERF:RegisterEventHandler("CHAT_MSG_ADDON", function(_, prefix, text, channel, senderName)
        Comm:OnAddonMessage(prefix, text, channel, senderName)
    end)
    -- Restrictions lifting: kick the queue so waiting messages go out at once.
    ERF:RegisterEventHandler("ADDON_RESTRICTION_STATE_CHANGED", function()
        lockedUntil = 0
        if Comm:QueueSize() > 0 then sender:Show() end
    end)
end
