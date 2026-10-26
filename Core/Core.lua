-- =============================================================================
-- EasyRaidForever - Core/Core.lua
-- Namespace bootstrap, SavedVariables, event plumbing and slash commands.
--
-- The addon does only what the website cannot do: rolling and handing out loot
-- in game. Everything else (raids, reserves, SR+ points, attendance, rules)
-- lives on the guild website. Data flow per raid:
--   website --"Export for addon" (SIR1 string)--> addon (soft reserves, bonus, specs)
--   addon   --"Export for website" (SIL1 string)--> website (awarded loot)
-- =============================================================================

local ADDON_NAME, ERF = ...
local L = ERF.L
local Util = ERF.Util

EasyRaidForever = ERF              -- global handle for macros / other addons
ERF.name    = "EasyRaidForever"
ERF.version = "1.0.0"

-- ---------------------------------------------------------------------------
-- SavedVariables (account-wide)
--
--  raid     -> the raid imported from the website (see Raid/Raid.lua), incl. the
--              loot awarded so far and the loot master list (pend)
--  options  -> local settings
--  ui       -> window positions
--
-- BETA NOTE: on the Forever beta SavedVariables were written but not read back.
-- So everything boots from an empty table, and the export string is the only
-- reliable way to get the loot to the website - export before logging out.
-- ---------------------------------------------------------------------------
local DB_DEFAULTS = {
    version = 1,
    raid    = nil,
    options = {
        minimap     = {},        -- owned by LibDBIcon
        debug       = false,
        showResults = true,      -- open the results window when a roll is decided
        rollDuration = 30,       -- seconds per roll
    },
    ui      = { windows = {} },
}

local function ApplyDefaults(target, defaults)
    for k, v in pairs(defaults) do
        if type(v) == "table" then
            if type(target[k]) ~= "table" then target[k] = {} end
            ApplyDefaults(target[k], v)
        elseif target[k] == nil then
            target[k] = v
        end
    end
end

function ERF:InitDB()
    if type(EasyRaidForeverDB) ~= "table" or (EasyRaidForeverDB.version or 0) < 1 or EasyRaidForeverDB.orgs then
        -- Fresh start (also replaces data of the old addon version 0.x).
        EasyRaidForeverDB = {}
    end
    ApplyDefaults(EasyRaidForeverDB, DB_DEFAULTS)
    self.db = EasyRaidForeverDB
    self.dbReady = true
end

ERF.playerName = nil

function ERF:InitPlayer()
    self.playerName = Util.PlayerName()
end

-- ---------------------------------------------------------------------------
-- Event dispatch: one frame, every handler individually guarded. Registration
-- is wrapped in pcall: on Forever an event that does not exist THROWS.
-- ---------------------------------------------------------------------------
ERF.eventHandlers = {}

local eventFrame = CreateFrame("Frame", "EasyRaidForeverEventFrame")
ERF.eventFrame = eventFrame

local function SafeRegister(event)
    local ok = pcall(eventFrame.RegisterEvent, eventFrame, event)
    if not ok then Util.Debug("event %s does not exist on this client", event) end
    return ok
end

function ERF:RegisterEventHandler(event, fn)
    local list = self.eventHandlers[event]
    if not list then
        list = {}
        self.eventHandlers[event] = list
        SafeRegister(event)
    end
    list[#list + 1] = fn
end

SafeRegister("ADDON_LOADED")
SafeRegister("PLAYER_ENTERING_WORLD")

eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        if ... == ADDON_NAME then ERF:InitDB() end
    elseif event == "PLAYER_ENTERING_WORLD" then
        ERF:InitPlayer()
        if ERF.Boot then ERF:Boot() end
    end
    local list = ERF.eventHandlers[event]
    if list then
        for i = 1, #list do Util.Guard(list[i], "event:" .. event, event, ...) end
    end
end)

-- ---------------------------------------------------------------------------
-- Change notification: modules call ERF:Notify(topic) after they changed data;
-- the UI subscribes with ERF:OnChanged(key, fn).
-- Topics: RAID (import / settings), LOOTMASTER, ROLLS, ITEMS
-- ---------------------------------------------------------------------------
ERF.listeners = {}

function ERF:OnChanged(key, fn)
    self.listeners[key] = fn
end

function ERF:Notify(topic, ...)
    for key, fn in pairs(self.listeners) do
        Util.Guard(fn, "listener:" .. tostring(key), topic, ...)
    end
end

-- ---------------------------------------------------------------------------
-- Slash commands
-- ---------------------------------------------------------------------------
SLASH_EASYRAIDFOREVER1 = "/easyraidforever"
SLASH_EASYRAIDFOREVER2 = "/erf"

SlashCmdList["EASYRAIDFOREVER"] = function(input)
    input = Util.Trim(input or "")
    local cmd, rest = string.match(input, "^(%S*)%s*(.*)$")
    cmd = string.lower(cmd or "")

    if cmd == "" or cmd == "show" then
        ERF.MainWindow:Toggle()
    elseif cmd == "import" then
        ERF.MainWindow:ShowImport()
    elseif cmd == "export" then
        ERF.MainWindow:ShowExport()
    elseif cmd == "lm" or cmd == "lootmaster" then
        ERF.LootMasterWindow:Toggle()
    elseif cmd == "rolls" then
        ERF.RollWindow:Toggle()
    elseif cmd == "results" then
        ERF.ResultsWindow:Toggle()
    elseif cmd == "item" then
        -- Adds items (links / IDs) to the loot master list.
        local ids = ERF.Raid:ParseItemIds(rest)
        if #ids == 0 then
            Util.Print(L["Usage: /erf item <shift-click items or item IDs>"])
        else
            for _, id in ipairs(ids) do
                local entry, why = ERF.Loot:AddItem(id)
                if not entry then Util.Print(why) break end
            end
            ERF.LootMasterWindow:Open()
        end
    elseif cmd == "check" then
        ERF.RunDiagnostics()
    elseif cmd == "debug" then
        ERF.db.options.debug = not ERF.db.options.debug
        Util.Print(L["Debug: %s"], ERF.db.options.debug and L["on"] or L["off"])
    elseif cmd == "reset" then
        if rest == "confirm" then
            EasyRaidForeverDB = nil
            ERF:InitDB()
            Util.Print(L["Database reset. Please /reload."])
        else
            Util.Print(L["This wipes ALL local data. Type |cffffffff/erf reset confirm|r to proceed."])
        end
    else
        Util.Print(L["Commands:"])
        print("  |cffffffff/erf|r - " .. L["open the window"])
        print("  |cffffffff/erf import|r / |cffffffff/erf export|r - " .. L["import from / export to the website"])
        print("  |cffffffff/erf lm|r - " .. L["loot master console"])
        print("  |cffffffff/erf rolls|r / |cffffffff/erf results|r - " .. L["roll window / results"])
        print("  |cffffffff/erf item <link>|r - " .. L["put items on the loot master list"])
        print("  |cffffffff/erf check|r - " .. L["check what this client supports"])
        print("  |cffffffff/erf debug|r - " .. L["toggle debug output"])
    end
end

-- Addon compartment (the addon button next to the minimap).
function EasyRaidForever_OnCompartmentClick()
    ERF.MainWindow:Toggle()
end
