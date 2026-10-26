-- =============================================================================
-- EasyRaidForever - Raid/Loot.lua
--
-- The loot master list (only on the client that imported the raid):
--  * items of every corpse it opens (LOOT_OPENED, master loot) and items looted
--    into its bags (CHAT_MSG_LOOT - Forever lets the loot master collect loot and
--    hand it out by trade for ~2 hours), plus items added by hand
--  * starts rolls (Rolls.lua) and records awards in the raid's loot history,
--    which is exported to the website (Transfer.lua)
-- The list is mirrored into the raid (`pend`) so it survives a /reload.
-- =============================================================================

local ADDON_NAME, ERF = ...
local L = ERF.L
local Util = ERF.Util

local Loot = {}
ERF.Loot = Loot

Loot.items = {}            -- loot master list (runtime)
Loot.slots = {}            -- [slot] = itemId while a corpse is open
Loot.lootOpen = false
local entryCounter = 0

-- Set of names in the current group (readable ones).
function Loot:GroupSet()
    local set = {}
    for _, r in ipairs((Util.GroupRoster())) do set[r.name] = true end
    return set
end

local function Relevant(itemId, quality)
    return ERF.Raid:Reservers()[itemId] or ERF.Raid:IsKnownItem(itemId) or (quality and quality >= 4)
end

-- Adds an item to the loot master list. `slot` when it lies in an open corpse.
-- src: "CORPSE" (master loot window), "BAGS" (looted into the bags), "MANUAL".
function Loot:AddItem(itemId, slot, boss, src)
    local raid = ERF.Raid:Current()
    if not raid then return nil, L["No raid imported."] end
    if not ERF.Raid:IsLeader() then return nil, L["Only the loot master (who imported the raid) can do that."] end
    entryCounter = entryCounter + 1
    local entry = {
        key = entryCounter, itemId = itemId, slot = slot, src = src or (slot and "CORPSE" or "MANUAL"),
        boss = boss or raid.lastBoss or (raid.items[itemId] and raid.items[itemId].b) or nil,
        state = "NEW", at = Util.Now(),
    }
    table.insert(self.items, entry)
    ERF:Notify("LOOTMASTER")
    return entry
end

-- ---------------------------------------------------------------------------
-- Persistence of the list in the raid (survives /reload)
-- ---------------------------------------------------------------------------
local persistScheduled = false

function Loot:Persist()
    persistScheduled = false
    local raid = ERF.Raid:Current()
    if not raid or not ERF.Raid:IsLeader() then return end
    local pend = {}
    for _, e in ipairs(self.items) do
        pend[#pend + 1] = {
            k = e.key, i = e.itemId, b = e.boss, at = e.at, st = e.state, src = e.src,
            w = e.winner and e.winner.name or nil, wo = e.winner and e.winner.o or nil,
            sp = e.winner and e.winner.sp or nil, tot = e.winner and e.winner.total or nil,
            to = e.awardedTo, tk = e.awardedKind, tr = e.trade or nil, td = e.traded or nil,
        }
    end
    raid.pend = pend
end

function Loot:PersistSoon()
    if persistScheduled then return end
    persistScheduled = true
    C_Timer.After(2, function() Util.Guard(function() Loot:Persist() end, "Loot.persist") end)
end

-- Restores the list from the raid (after /reload or a new import).
function Loot:Restore()
    wipe(self.items)
    local raid = ERF.Raid:Current()
    if not raid or not raid.pend then return end
    for _, p in ipairs(raid.pend) do
        local state = p.st
        if state == "ROLLING" then state = "NEW" end   -- rolls are not resumed
        local entry = {
            key = p.k or 0, itemId = p.i, boss = p.b, at = p.at, state = state or "NEW", src = p.src,
            awardedTo = p.to, awardedKind = p.tk, trade = p.tr, traded = p.td,
        }
        if p.w then entry.winner = { name = p.w, o = p.wo, sp = p.sp, total = p.tot } end
        entryCounter = math.max(entryCounter, entry.key)
        table.insert(self.items, entry)
    end
end

-- Items still to be traded to a player (awarded without master loot).
function Loot:OwedTo(player)
    local out = {}
    for _, e in ipairs(self.items) do
        if e.state == "AWARDED" and e.trade and not e.traded and e.awardedTo == player then out[#out + 1] = e end
    end
    return out
end

-- ---------------------------------------------------------------------------
-- Items looted into the loot master's bags (CHAT_MSG_LOOT)
-- ---------------------------------------------------------------------------
local selfLootPatterns
local function SelfLootPatterns()
    if selfLootPatterns then return selfLootPatterns end
    selfLootPatterns = {}
    for _, fmt in ipairs({ LOOT_ITEM_SELF_MULTIPLE, LOOT_ITEM_SELF, LOOT_ITEM_PUSHED_SELF_MULTIPLE, LOOT_ITEM_PUSHED_SELF }) do
        if type(fmt) == "string" then
            local p = string.gsub(fmt, "([%(%)%.%+%-%*%?%[%]%^%$])", "%%%1")
            p = string.gsub(p, "%%s", "(.+)")
            p = string.gsub(p, "%%d", "%%d+")
            selfLootPatterns[#selfLootPatterns + 1] = "^" .. p .. "$"
        end
    end
    return selfLootPatterns
end

local function ItemQuality(itemId, slotQuality)
    if slotQuality then return slotQuality end
    if C_Item.GetItemQualityByID then
        local ok, q = pcall(C_Item.GetItemQualityByID, itemId)
        if ok then return q end
    end
    return nil
end

function Loot:OnChatLoot(text, looter)
    if not ERF.Raid:IsLeader() then return end
    if Util.IsSecret(text) or type(text) ~= "string" then return end
    local mine = false
    for _, p in ipairs(SelfLootPatterns()) do
        if string.match(text, p) then mine = true break end
    end
    if not mine and looter and not Util.IsSecret(looter) then
        mine = Util.ResolveName(looter) == ERF.playerName
    end
    if not mine then return end
    local itemId = tonumber(string.match(text, "item:(%d+)"))
    if not itemId or not Relevant(itemId, ItemQuality(itemId)) then return end

    -- Looted from a corpse that was already on the list: it is in the bags now.
    local now = Util.Now()
    for _, e in ipairs(self.items) do
        if e.itemId == itemId and e.src == "CORPSE" and not e.inBags and now - (e.at or 0) < 600 then
            e.inBags = true
            e.slot = nil
            ERF:Notify("LOOTMASTER")
            return
        end
    end
    self:AddItem(itemId, nil, nil, "BAGS")
end

function Loot:RemoveEntry(entry)
    for i, e in ipairs(self.items) do
        if e == entry then table.remove(self.items, i) break end
    end
    ERF:Notify("LOOTMASTER")
end

function Loot:ClearAwarded()
    for i = #self.items, 1, -1 do
        local e = self.items[i]
        -- Items still to be traded stay on the list (the trade helper needs them).
        if e.state == "AWARDED" and (not e.trade or e.traded) then table.remove(self.items, i) end
    end
    ERF:Notify("LOOTMASTER")
end

function Loot:OnLootOpened()
    self.lootOpen = true
    wipe(self.slots)
    local raid = ERF.Raid:Current()
    if not raid or not ERF.Raid:IsLeader() then return end
    local added = 0
    for slot = 1, (GetNumLootItems() or 0) do
        local link = GetLootSlotLink(slot)
        local itemId = link and tonumber(string.match(link, "item:(%d+)"))
        if itemId then
            self.slots[slot] = itemId
            local slotQuality
            if type(GetLootSlotInfo) == "function" then
                slotQuality = Util.Readable((select(5, GetLootSlotInfo(slot))))
            end
            if Relevant(itemId, ItemQuality(itemId, slotQuality)) then
                -- Skip items already on the list for this corpse slot.
                local known = false
                for _, e in ipairs(self.items) do
                    if e.itemId == itemId and e.slot == slot and e.state ~= "AWARDED" then known = true end
                end
                if not known then
                    self:AddItem(itemId, slot)
                    added = added + 1
                end
            end
        end
    end
    if added > 0 then ERF.LootMasterWindow:Open() end
end

function Loot:OnLootClosed()
    self.lootOpen = false
    wipe(self.slots)
    for _, e in ipairs(self.items) do e.slot = nil end
    ERF:Notify("LOOTMASTER")
end

-- Hands the item over via master loot when possible. Recording an award never
-- depends on this - without master loot the item is traded by hand.
function Loot:GiveItem(entry, player)
    if not (self.lootOpen and entry.slot and self.slots[entry.slot] == entry.itemId) then return false end
    if type(GetMasterLootCandidate) ~= "function" or type(GiveMasterLoot) ~= "function" then return false end
    for i = 1, 40 do
        local ok, candidate = pcall(GetMasterLootCandidate, entry.slot, i)
        candidate = ok and Util.ResolveName(candidate) or nil
        if candidate and candidate == player then
            return (pcall(GiveMasterLoot, entry.slot, i))
        end
    end
    return false
end

-- Records an award in the raid's loot history (exported to the website).
-- kind: "SR" / "MS" / "DS" / "OS" / "GREED" / "DE"
function Loot:Award(entry, player, kind, spec, total)
    local raid = ERF.Raid:Current()
    if not raid then return false, L["No raid imported."] end
    kind = kind or "MS"
    table.insert(raid.loot, {
        i = entry.itemId, n = player, k = kind, b = entry.boss, t = Util.Now(),
        r = total, sp = spec or ERF.Raid:SpecFor(player, kind),
    })
    entry.state = "AWARDED"
    entry.awardedTo, entry.awardedKind = player, kind
    local handed = player == ERF.playerName or self:GiveItem(entry, player)
    -- Not handed over directly: it goes by trade (see UI/LootMaster/TradeHelper.lua).
    entry.trade = not handed or nil
    local name, link = C_Item.GetItemInfo(entry.itemId)
    Util.Print(L["%s awarded to %s (%s)%s"], link or name or ("item:" .. entry.itemId), Util.ShortName(player),
        kind, handed and "" or (" - " .. L["hand it over by trade"]))
    ERF:Notify("LOOTMASTER")
    ERF:Notify("RAID")
    return true
end

-- Removes an award from the history (wrong click).
function Loot:Unaward(index)
    local raid = ERF.Raid:Current()
    if not raid or not raid.loot[index] then return end
    table.remove(raid.loot, index)
    ERF:Notify("RAID")
end

function Loot:Init()
    ERF:RegisterEventHandler("LOOT_OPENED", function() Loot:OnLootOpened() end)
    ERF:RegisterEventHandler("LOOT_CLOSED", function() Loot:OnLootClosed() end)
    ERF:RegisterEventHandler("CHAT_MSG_LOOT", function(_, text, looter) Loot:OnChatLoot(text, looter) end)
    ERF:OnChanged("LootPersist", function(topic)
        if topic == "ROLLS" or topic == "LOOTMASTER" then Loot:PersistSoon() end
    end)
    -- Back from a /reload: the list returns.
    self:Restore()
end
