-- =============================================================================
-- EasyRaidForever - Raid/Rolls.lua
--
-- Roll engine (taken over from the previous version). The loot master (the
-- client that imported the raid) is the only authority: it starts rolls,
-- tallies them and announces the winners.
--
-- Messages (group channel):
--   RB  loot master  roll begins / is extended  { r, i, sr, el, bn, op, d, b }
--   RI  player       "my next /roll is for roll r, option o"  { r, o }
--   RP  player       pass  { r }
--   RU  loot master  current tally  { r, t = { [name] = { v, bn, o, sp } } }
--   RW  loot master  roll closed  { r, w, o, sp, v, bn, tie }
--   RZ  loot master  roll cancelled  { r }
--
-- Reserved items: only the reservers roll, with button SR and their SR+ bonus.
-- Other items: MS > DS > OS > Greed - the /roll range tells the button apart
-- (MS 1-100, DS 1-99, OS 1-98, Greed 1-97), so players without the addon can
-- roll by hand.
--
-- HONESTY: the roll VALUE is never taken from an addon message. A player
-- presses a button (RI) and the addon performs a real /roll; the loot master
-- reads the result from the system chat line (CHAT_MSG_SYSTEM).
--
-- MANY ROLLS AT ONCE: the player's client rolls one after another (the next
-- roll only after its own previous result line), and the loot master queues RIs
-- and roll lines per player and pairs them first-in-first-out by roll range.
-- A line without an RI (player without the addon, lost message) is attributed
-- after LINE_WAIT seconds - or when the roll closes - to the oldest open roll
-- with a button of that range.
--
-- FOREVER: CHAT_MSG_SYSTEM is a secret value during chat lockdown (boss
-- encounters). Loot is handed out after the kill; a secret roll line is ignored.
-- ISOLATION: roll messages are only accepted from senders in the own group.
-- =============================================================================

local ADDON_NAME, ERF = ...
local L = ERF.L
local Util = ERF.Util
local Raid = ERF.Raid

local Rolls = {}
ERF.Rolls = Rolls

Rolls.active = {}        -- [rollId] = roll (open and recently closed)
Rolls.order = {}         -- rollIds in start order
local counter = 0
local intents = {}       -- loot master: [name] = { { r, o, at }, ... }  (FIFO)
local lines = {}         -- loot master: [name] = { { v, lo, hi, at }, ... } (FIFO)
local INTENT_TTL = 120
local LINE_WAIT = 8
local myQueue = {}       -- player: choices waiting for their roll { roll, opt }
local myInFlight         -- player: GetTime() of the last roll not yet seen in chat
local IN_FLIGHT_MAX = 3
local FlushLines
local KEEP_CLOSED = 300  -- seconds a decided roll stays in the results

local PASS = { label = "Pass", cap = 0 }

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------
local function Now() return GetTime() end

function Rolls:List()
    local out = {}
    for _, id in ipairs(self.order) do
        local r = self.active[id]
        if r then out[#out + 1] = r end
    end
    return out
end

function Rolls:OpenCount(onlyMine)
    local n = 0
    for _, r in ipairs(self:List()) do
        if r.state == "OPEN" and (not onlyMine or self:CanRoll(r) and not r.myChoice) then n = n + 1 end
    end
    return n
end

local function Eligible(roll, name)
    return not roll.eligible or roll.eligible[Raid.Key(name)] == true
end

-- May the local player roll on this?
function Rolls:CanRoll(roll)
    return roll.state == "OPEN" and Eligible(roll, ERF.playerName)
end

-- SR+ bonus of the local player on a roll (sent by the loot master).
function Rolls:MyBonus(roll)
    return roll.bonus and roll.bonus[Raid.Key(ERF.playerName)] or 0
end

function Rolls:OptionByLabel(roll, label)
    for idx, o in ipairs(roll.options) do
        if o.label == label then return o, idx end
    end
    return nil
end

local function Remember(roll)
    if not Rolls.active[roll.id] then table.insert(Rolls.order, roll.id) end
    Rolls.active[roll.id] = roll
end

local function Prune()
    local now = Now()
    for i = #Rolls.order, 1, -1 do
        local r = Rolls.active[Rolls.order[i]]
        if not r or (r.state ~= "OPEN" and now - (r.closedAt or now) > KEEP_CLOSED) then
            Rolls.active[Rolls.order[i]] = nil
            table.remove(Rolls.order, i)
        end
    end
end

-- Ranking: option order first (tier: MS before DS before OS ...), then total, then name.
function Rolls:Rank(roll)
    local list = {}
    for name, e in pairs(roll.rolls) do
        local opt, tier = self:OptionByLabel(roll, e.o)
        if tier and (opt.cap or 0) > 0 then
            list[#list + 1] = { name = name, v = e.v, bn = e.bn or 0, total = e.v + (e.bn or 0), o = e.o, sp = e.sp, tier = tier }
        end
    end
    table.sort(list, function(a, b)
        if a.tier ~= b.tier then return a.tier < b.tier end
        if a.total ~= b.total then return a.total > b.total end
        return a.name < b.name
    end)
    return list
end

local function IsGroupSender(sender)
    return ERF.Loot:GroupSet()[sender] == true
end

-- ---------------------------------------------------------------------------
-- Loot master side
-- ---------------------------------------------------------------------------
local function Broadcast(msgType, payload, dedupe)
    local channel = Util.GroupChannel()
    if channel then ERF.Comm:Send(msgType, payload, channel, nil, dedupe) end
end

local function RollPayload(roll)
    local el
    if roll.eligible then
        el = {}
        for k in pairs(roll.eligible) do el[#el + 1] = k end
    end
    return { r = roll.id, i = roll.itemId, sr = roll.sr or nil, el = el, bn = roll.bonus,
             op = roll.options, d = math.max(1, math.floor(roll.endsAt - Now())), b = roll.boss }
end

local function BroadcastTally(roll)
    local t = {}
    for name, e in pairs(roll.rolls) do t[name] = { v = e.v, bn = e.bn, o = e.o, sp = e.sp } end
    Broadcast("RU", { r = roll.id, t = t }, "RU|" .. roll.id)
end

-- Starts a roll for a loot master entry. `eligibleOverride` = set of keys (tie
-- reroll), `duration` overrides the roll time (long timers for loot collected
-- over the evening and rolled in one go). Returns the roll or nil, reason.
function Rolls:Start(entry, eligibleOverride, duration)
    local raid = Raid:Current()
    if not raid then return nil, L["No raid imported."] end
    if not Raid:IsLeader() then return nil, L["Only the loot master (who imported the raid) can do that."] end

    local reservers = Raid:Reservers()[entry.itemId]
    local sr = reservers ~= nil and #reservers > 0
    local eligible, bonus
    if sr then
        eligible, bonus = {}, {}
        for _, p in ipairs(reservers) do
            local key = Raid.Key(p.name)
            eligible[key] = true
            local b = Raid:Bonus(p.name, entry.itemId)
            if b > 0 then bonus[key] = b end
        end
    end
    if eligibleOverride then eligible = eligibleOverride end

    counter = counter + 1
    local d = duration or ERF.db.options.rollDuration or 30
    local roll = {
        id = raid.id .. ":" .. counter .. ":" .. entry.itemId,
        itemId = entry.itemId, boss = entry.boss, sr = sr, eligible = eligible, bonus = bonus,
        options = sr and { Raid.SR_OPTION, PASS } or Util.CopyTable(Raid.ROLL_OPTIONS),
        endsAt = Now() + d, duration = d,
        rolls = {}, passed = {}, state = "OPEN", isLeader = true, entryKey = entry.key,
        leader = ERF.playerName,
    }
    Remember(roll)
    entry.state = "ROLLING"
    entry.rollId = roll.id
    Broadcast("RB", RollPayload(roll))
    ERF:Notify("ROLLS")
    return roll
end

function Rolls:Extend(roll, seconds)
    if not roll.isLeader or roll.state ~= "OPEN" then return end
    roll.endsAt = roll.endsAt + (seconds or 15)
    Broadcast("RB", RollPayload(roll))
    ERF:Notify("ROLLS")
end

function Rolls:Cancel(roll)
    if not roll.isLeader then return end
    roll.state = "CANCELLED"
    roll.closedAt = Now()
    Broadcast("RZ", { r = roll.id })
    for _, e in ipairs(ERF.Loot.items) do
        if e.rollId == roll.id and e.state == "ROLLING" then e.state = "NEW" end
    end
    ERF:Notify("ROLLS")
end

function Rolls:Close(roll)
    if not roll.isLeader or roll.state ~= "OPEN" then return end
    -- Roll lines still waiting for their RI count before the roll closes.
    FlushLines(true)
    if roll.state ~= "OPEN" then return end
    local ranking = self:Rank(roll)
    roll.state = "CLOSED"
    roll.closedAt = Now()
    roll.ranking = ranking
    local top = ranking[1]
    local tie
    if top and ranking[2] and ranking[2].tier == top.tier and ranking[2].total == top.total then
        tie = {}
        for _, e in ipairs(ranking) do
            if e.tier == top.tier and e.total == top.total then tie[#tie + 1] = e.name end
        end
        roll.tie = tie
    elseif top then
        roll.winner = top
    end
    for _, e in ipairs(ERF.Loot.items) do
        if e.rollId == roll.id then
            e.state = "DECIDED"
            e.winner = roll.winner
            e.tie = roll.tie
        end
    end
    Broadcast("RW", { r = roll.id, w = top and not tie and top.name or nil, o = top and top.o,
        sp = top and top.sp, v = top and top.v, bn = top and top.bn, tie = tie })
    ERF:Notify("ROLLS")
end

-- Tie: a new roll among the tied players only.
function Rolls:RerollTie(entry)
    local roll = entry.rollId and self.active[entry.rollId]
    if not roll or not roll.tie then return nil end
    local set = {}
    for _, n in ipairs(roll.tie) do set[Raid.Key(n)] = true end
    return self:Start(entry, set)
end

-- Records a roll value for `name` on `target` (loot master).
local function Record(target, name, value, high, option)
    if not target or target.state ~= "OPEN" or target.rolls[name] then return false end
    if not Eligible(target, name) then return false end
    if not option then
        for _, o in ipairs(target.options) do if o.cap == high then option = o.label break end end
    end
    local bonus = target.sr and Raid:Bonus(name, target.itemId) or 0
    local kind = target.sr and "SR" or Raid:LootKind(option)
    target.rolls[name] = { v = value, bn = bonus, o = option, hi = high, sp = Raid:SpecFor(name, kind) }
    BroadcastTally(target)
    Rolls:CheckComplete(target)
    ERF:Notify("ROLLS")
    return true
end

-- Pairs queued intents and roll lines of one player (FIFO, by roll range).
local function Match(name)
    local iq, lq = intents[name], lines[name]
    if not iq or not lq then return end
    local i = 1
    while i <= #iq and #lq > 0 do
        local intent = iq[i]
        local r = Rolls.active[intent.r]
        local opt = r and Rolls:OptionByLabel(r, intent.o)
        if not r or r.state ~= "OPEN" or not opt or r.rolls[name] then
            table.remove(iq, i)                       -- stale intent
        else
            local found
            for j, line in ipairs(lq) do
                if line.lo == 1 and line.hi == opt.cap then found = j break end
            end
            if found then
                local line = table.remove(lq, found)
                table.remove(iq, i)
                Record(r, name, line.v, line.hi, intent.o)
            else
                i = i + 1
            end
        end
    end
    if #iq == 0 then intents[name] = nil end
    if #lq == 0 then lines[name] = nil end
end

-- A roll line nobody announced: the oldest open roll with a button of that range.
local function Fallback(name, line)
    if line.lo ~= 1 then return end
    for _, r in ipairs(Rolls:List()) do
        if r.isLeader and r.state == "OPEN" and not r.rolls[name] and Eligible(r, name) then
            for _, o in ipairs(r.options) do
                if o.cap == line.hi and o.cap > 0 then
                    Record(r, name, line.v, line.hi, o.label)
                    return
                end
            end
        end
    end
end

-- Lines that waited long enough (or all of them, `force`) go to the fallback.
function FlushLines(force)    -- forward-declared local (used by Close)
    local now = Now()
    for name, lq in pairs(lines) do
        local i = 1
        while i <= #lq do
            if force or now - lq[i].at >= LINE_WAIT then
                Fallback(name, table.remove(lq, i))
            else
                i = i + 1
            end
        end
        if #lq == 0 then lines[name] = nil end
    end
    for name, iq in pairs(intents) do
        for i = #iq, 1, -1 do
            if now - iq[i].at > INTENT_TTL then table.remove(iq, i) end
        end
        if #iq == 0 then intents[name] = nil end
    end
end

local function AddIntent(name, intent)
    intents[name] = intents[name] or {}
    table.insert(intents[name], intent)
    Match(name)
end

local function Attribute(name, value, low, high)
    lines[name] = lines[name] or {}
    table.insert(lines[name], { v = value, lo = low, hi = high, at = Now() })
    Match(name)
end

-- SR rolls close by themselves once every reserver answered (a few seconds later).
function Rolls:CheckComplete(roll)
    if not roll.eligible or roll.state ~= "OPEN" or roll.completing then return end
    local answered = {}
    for n in pairs(roll.rolls) do answered[Raid.Key(n)] = true end
    for n in pairs(roll.passed) do answered[Raid.Key(n)] = true end
    for key in pairs(roll.eligible) do
        if not answered[key] then return end
    end
    roll.completing = true
    C_Timer.After(3, function()
        roll.completing = nil
        if roll.state == "OPEN" then Rolls:Close(roll) end
    end)
end

-- "Name rolls 55 (1-100)" -> name, value, low, high  (locale independent)
local rollPattern
function Rolls:RollPattern()
    if rollPattern then return rollPattern end
    local fmt = RANDOM_ROLL_RESULT or "%s rolls %d (%d-%d)"
    local p = string.gsub(fmt, "([%(%)%.%+%-%*%?%[%]%^%$])", "%%%1")
    p = string.gsub(p, "%%s", "(.+)")
    p = string.gsub(p, "%%d", "(%%d+)")
    rollPattern = "^" .. p .. "$"
    return rollPattern
end

function Rolls:ParseRoll(text)
    local name, value, low, high = string.match(text, self:RollPattern())
    if not name then return nil end
    return name, tonumber(value), tonumber(low), tonumber(high)
end

function Rolls:OnSystemMessage(text)
    if Util.IsSecret(text) then return end
    local name, value, low, high = self:ParseRoll(text or "")
    if not name then return end
    local full = Util.ResolveName(name)
    if not full then return end
    if full == ERF.playerName and myInFlight then
        myInFlight = nil
        C_Timer.After(0.2, function() Util.Guard(function() Rolls:Pump() end, "Rolls.pump") end)
    end
    Attribute(full, value, low, high)
end

-- Closes expired rolls (loot master).
local function Tick()
    local now = Now()
    FlushLines(false)
    if myInFlight and now - myInFlight > IN_FLIGHT_MAX then
        myInFlight = nil
        Rolls:Pump()
    end
    for _, r in ipairs(Rolls:List()) do
        if r.isLeader and r.state == "OPEN" and now >= r.endsAt then Rolls:Close(r) end
    end
    Prune()
end

-- ---------------------------------------------------------------------------
-- Player side
-- ---------------------------------------------------------------------------

-- The local player presses a roll button (label) or passes (label nil / cap 0).
function Rolls:Choose(roll, label)
    if not self:CanRoll(roll) or roll.myChoice then return false end
    local opt = label and self:OptionByLabel(roll, label)
    if not opt or opt.cap == 0 then
        roll.myChoice = "PASS"
        roll.passed[ERF.playerName] = true
        if roll.isLeader then
            self:CheckComplete(roll)
        else
            local channel = Util.GroupChannel()
            if channel then ERF.Comm:Send("RP", { r = roll.id }, channel) end
        end
        ERF:Notify("ROLLS")
        return true
    end
    roll.myChoice = opt.label
    table.insert(myQueue, { roll = roll, opt = opt })
    self:Pump()
    ERF:Notify("ROLLS")
    return true
end

-- Performs the next queued roll - one at a time, so the loot master sees the
-- announcements (RI) and the chat lines in the same order.
function Rolls:Pump()
    if myInFlight then return end
    local q = table.remove(myQueue, 1)
    while q and q.roll.state ~= "OPEN" do q = table.remove(myQueue, 1) end
    if not q then return end
    local roll, opt = q.roll, q.opt
    if roll.isLeader then
        AddIntent(ERF.playerName, { r = roll.id, o = opt.label, at = Now() })
    else
        local channel = Util.GroupChannel()
        if channel then ERF.Comm:Send("RI", { r = roll.id, o = opt.label }, channel) end
    end
    myInFlight = Now()
    RandomRoll(1, opt.cap)
end

-- Passes on every open roll the player has not answered yet.
function Rolls:PassAll()
    local n = 0
    for _, r in ipairs(self:List()) do
        if self:CanRoll(r) and not r.myChoice then
            if self:Choose(r, nil) then n = n + 1 end
        end
    end
    return n
end

local function OnRB(sender, p)
    if type(p) ~= "table" or type(p.r) ~= "string" or type(p.i) ~= "number" or type(p.op) ~= "table" then return end
    if not IsGroupSender(sender) then return end
    local roll = Rolls.active[p.r] or { rolls = {}, passed = {} }
    if roll.isLeader then return end
    roll.id, roll.itemId, roll.boss = p.r, p.i, p.b
    roll.sr = p.sr and true or false
    roll.options = p.op
    roll.leader = sender
    roll.bonus = type(p.bn) == "table" and p.bn or nil
    roll.endsAt = Now() + (tonumber(p.d) or 30)
    roll.duration = roll.duration or tonumber(p.d) or 30
    roll.state = "OPEN"
    if type(p.el) == "table" then
        roll.eligible = {}
        for _, k in ipairs(p.el) do if type(k) == "string" then roll.eligible[k] = true end end
    else
        roll.eligible = nil
    end
    Remember(roll)
    ERF:Notify("ROLLS", "NEW")
end

local function OnRI(sender, p)
    if type(p) ~= "table" or type(p.r) ~= "string" then return end
    local roll = Rolls.active[p.r]
    if not roll or not roll.isLeader then return end
    local o = type(p.o) == "string" and p.o or nil
    local existing = roll.rolls[sender]
    if existing then
        -- The /roll line was faster than this message: complete the entry,
        -- as long as the stated button matches the range that was rolled.
        local opt = o and Rolls:OptionByLabel(roll, o)
        if opt and opt.cap == existing.hi then existing.o = o end
        BroadcastTally(roll)
        ERF:Notify("ROLLS")
        return
    end
    AddIntent(sender, { r = p.r, o = o, at = Now() })
end

local function OnRP(sender, p)
    if type(p) ~= "table" or type(p.r) ~= "string" then return end
    local roll = Rolls.active[p.r]
    if not roll or not roll.isLeader or roll.state ~= "OPEN" then return end
    roll.passed[sender] = true
    Rolls:CheckComplete(roll)
    ERF:Notify("ROLLS")
end

local function OnRU(sender, p)
    if type(p) ~= "table" or type(p.r) ~= "string" or type(p.t) ~= "table" then return end
    local roll = Rolls.active[p.r]
    if not roll or roll.leader ~= sender then return end
    roll.rolls = {}
    for name, e in pairs(p.t) do
        if type(name) == "string" and type(e) == "table" and type(e.v) == "number" then
            roll.rolls[name] = { v = e.v, bn = tonumber(e.bn) or 0, o = e.o, sp = e.sp }
        end
    end
    ERF:Notify("ROLLS")
end

local function OnRW(sender, p)
    if type(p) ~= "table" or type(p.r) ~= "string" then return end
    local roll = Rolls.active[p.r]
    if not roll or roll.leader ~= sender then return end
    roll.state = "CLOSED"
    roll.closedAt = Now()
    if type(p.w) == "string" then
        roll.winner = { name = p.w, o = p.o, sp = p.sp, v = tonumber(p.v) or 0, bn = tonumber(p.bn) or 0 }
        roll.winner.total = roll.winner.v + roll.winner.bn
    end
    roll.tie = type(p.tie) == "table" and p.tie or nil
    ERF:Notify("ROLLS", "RESULT")
end

local function OnRZ(sender, p)
    if type(p) ~= "table" or type(p.r) ~= "string" then return end
    local roll = Rolls.active[p.r]
    if not roll or roll.leader ~= sender then return end
    roll.state = "CANCELLED"
    roll.closedAt = Now()
    ERF:Notify("ROLLS")
end

function Rolls:Init()
    ERF.Comm:RegisterHandler("RB", OnRB)
    ERF.Comm:RegisterHandler("RI", OnRI)
    ERF.Comm:RegisterHandler("RP", OnRP)
    ERF.Comm:RegisterHandler("RU", OnRU)
    ERF.Comm:RegisterHandler("RW", OnRW)
    ERF.Comm:RegisterHandler("RZ", OnRZ)
    ERF:RegisterEventHandler("CHAT_MSG_SYSTEM", function(_, text) Rolls:OnSystemMessage(text) end)
    C_Timer.NewTicker(0.5, function() Util.Guard(Tick, "Rolls.tick") end)
end
