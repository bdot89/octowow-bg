-- OctoBG :: core
-- Namespace, saved variables, a pcall-guarded event bus, a ticker, DLL
-- detection, battleground detection and the slash command.
--
-- Handlers and tickers added with bgOnly run only while B.active is set:
-- inside a battleground or arena, in layout mode (/obg unlock), or when the
-- HUD is switched on for the open world. Events only bgOnly handlers want are
-- unregistered from the client while inactive, so nampower's busy *_OTHER and
-- *_GUID events cost nothing outside battlegrounds.

OctoBG = {}
local B = OctoBG

B.VERSION = "1.0.0"
B.env = { superwow = false, nampower = false, unitxp = false, safe = false }
B.zone = nil        -- "WSG", "AB", "AV", "TG" (Thorn Gorge), "ARENA" or nil
B.zoneName = nil
B.faction = nil     -- "Alliance" / "Horde" (UnitFactionGroup tokens)
B.enemy = nil
B.active = false
B.test = false      -- layout mode: every panel shows sample data and a drag handle

BINDING_HEADER_OCTOBG = "OctoBG"
BINDING_NAME_OCTOBG_TARGET_EFC = "Target enemy flag carrier"
BINDING_NAME_OCTOBG_SPELL_EFC = "Flag spell on enemy carrier"
BINDING_NAME_OCTOBG_TARGET_FFC = "Target friendly flag carrier"
BINDING_NAME_OCTOBG_INC_AUTO = "Announce incoming (counted)"
BINDING_NAME_OCTOBG_INC_1 = "Announce 1 incoming"
BINDING_NAME_OCTOBG_INC_2 = "Announce 2 incoming"
BINDING_NAME_OCTOBG_INC_3 = "Announce 3 incoming"
BINDING_NAME_OCTOBG_INC_4 = "Announce 4 incoming"
BINDING_NAME_OCTOBG_INC_5 = "Announce 5+ incoming"
BINDING_NAME_OCTOBG_SAFE = "Announce base safe"
BINDING_NAME_OCTOBG_HUD = "Toggle the HUD"

B.DEFAULTS = {
  locked = true,
  scale = 1,
  pos = {},
  swapXY = nil,      -- learned by Map: UnitPosition hands back (y, x)
  facingSign = 0,    -- learned by Map: 1 or -1 (0 = not learned yet, 1 assumed)
  flags = { enabled = true, alerts = true, lowHp = 30 },   -- .spell: nil = class default
  timers = { enabled = true, spirit = true, big = true, predict = true },
  inc = { enabled = true, radius = 50, alert = true, autoPost = false, autoAsked = false },
  hud = { enabled = true, rotate = true, range = 45, size = 240, alpha = 0.9, names = 3,
          friends = true, edge = true, world = false },
  list = { enabled = true, rows = 8 },
  map = { enabled = true, width = 260, enemies = true, dim = 0.3 },   -- dim: black over the map tiles
  stealth = { enabled = true, alert = true, range = 60 },   -- range: alert when they stealth this close
  markers = { bright = true, size = 1.25 },   -- bright: U.BRIGHT class colours; size: HUD/map marker scale
  reach = {},        -- per zone: how far enemies were picked up (Tracker)
  viewBackup = nil,  -- CVars as they were before /obg maxview
}

-- ---------------------------------------------------------------- output

function B:Print(msg)
  DEFAULT_CHAT_FRAME:AddMessage("|cff33ccffOctoBG|r " .. tostring(msg))
end

function B:Debug(msg)
  if self.debug then self:Print("|cff888888" .. tostring(msg) .. "|r") end
end

-- Errors are printed once each and kept for /obg errors (at most 30).
B.errors = {}
local nerr = 0
function B:Error(err)
  err = tostring(err)
  if self.errors[err] or nerr >= 30 then return end
  self.errors[err] = true
  nerr = nerr + 1
  self:Print("|cffff5555error:|r " .. err)
end

function B:ClearErrors()
  self.errors = {}
  nerr = 0
end

-- ---------------------------------------------------------------- event bus

local frame = CreateFrame("Frame", "OctoBGCore")
local handlers = {}     -- event -> { { fn = f, bg = bool }, ... }
local always = {}       -- event -> true when a handler wants it outside battlegrounds
local registered = {}

local function Sync(ev)
  if string.sub(ev, 1, 4) == "OBG_" then return end
  local want = always[ev] or B.active
  if want and not registered[ev] then
    frame:RegisterEvent(ev)
    registered[ev] = true
  elseif not want and registered[ev] then
    frame:UnregisterEvent(ev)
    registered[ev] = nil
  end
end

function B:On(ev, fn, bgOnly)
  if not handlers[ev] then handlers[ev] = {} end
  table.insert(handlers[ev], { fn = fn, bg = bgOnly })
  if not bgOnly then always[ev] = true end
  Sync(ev)
end

local function Dispatch(ev, a1, a2, a3, a4, a5, a6, a7, a8, a9)
  local list = handlers[ev]
  if not list then return end
  for i = 1, table.getn(list) do
    local h = list[i]
    if B.active or not h.bg then
      local ok, err = pcall(h.fn, ev, a1, a2, a3, a4, a5, a6, a7, a8, a9)
      if not ok then B:Error(err) end
    end
  end
end

frame:SetScript("OnEvent", function()
  Dispatch(event, arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8, arg9)
end)

-- Internal messages use the same bus; their names start with OBG_.
function B:Fire(msg, a1, a2, a3, a4)
  Dispatch(msg, a1, a2, a3, a4)
end

function B:SetActive(on)
  self.active = on and true or false
  for ev in pairs(handlers) do Sync(ev) end
end

function B:RefreshActive()
  local db = self.db
  local on = (self.zone ~= nil) or self.test
    or (db and db.hud.enabled and db.hud.world) or false
  if on ~= self.active then
    self:SetActive(on)
    self:Fire("OBG_ACTIVE", on)
  end
end

-- ---------------------------------------------------------------- ticker

local tickers = {}

function B:Every(interval, fn, bgOnly)
  table.insert(tickers, { iv = interval, t = 0, fn = fn, bg = bgOnly })
end

frame:SetScript("OnUpdate", function()
  local e = arg1 or 0
  for i = 1, table.getn(tickers) do
    local tk = tickers[i]
    if B.active or not tk.bg then
      tk.t = tk.t + e
      if tk.t >= tk.iv then
        tk.t = 0
        local ok, err = pcall(tk.fn)
        if not ok then B:Error(err) end
      end
    end
  end
end)

-- ---------------------------------------------------------------- zones

local ZONES = {
  ["Warsong Gulch"] = "WSG",
  ["Arathi Basin"] = "AB",
  ["Alterac Valley"] = "AV",
  ["Thorn Gorge"] = "TG",
  ["Blood Ring"] = "ARENA",
  ["Lordaeron Arena"] = "ARENA",
  ["Sunstrider Court"] = "ARENA",
}

function B:IsBG()
  return self.zone ~= nil and self.zone ~= "ARENA"
end

function B:UpdateZone(force)
  local name = GetRealZoneText()
  local z = ZONES[name or ""]
  self.zoneName = name
  if z ~= self.zone or force then
    local old = self.zone
    self.zone = z
    self:RefreshActive()
    self:Fire("OBG_ZONE", z, old)
  end
end

-- ---------------------------------------------------------------- startup

local function Merge(dst, src)
  for k, v in pairs(src) do
    if type(v) == "table" then
      if type(dst[k]) ~= "table" then dst[k] = {} end
      Merge(dst[k], v)
    elseif dst[k] == nil then
      dst[k] = v
    end
  end
end

local detected = false
local function Detect()
  local e = B.env
  e.superwow = (SUPERWOW_VERSION or (SetAutoloot and SpellInfo)) and true or false
  e.position = (e.superwow and UnitPosition) and true or false
  e.nampower = GetNampowerVersion and true or false
  -- UnitXP_SP3 overloads UnitXP; the feature test needs "player" in the world.
  local ok, v = pcall(UnitXP, "distanceBetween", "player", "player")
  e.unitxp = (ok and type(v) == "number") and true or false
end

B:On("ADDON_LOADED", function(ev, name)
  if name ~= "OctoBG" then return end
  if type(OctoBGDB) ~= "table" then OctoBGDB = {} end
  Merge(OctoBGDB, B.DEFAULTS)
  OctoBGDB.locked = true   -- layout mode never survives a reload
  B.db = OctoBGDB
  B:Fire("OBG_LOADED")
end)

B:On("PLAYER_LOGIN", function()
  B:Fire("OBG_INIT")
end)

B:On("PLAYER_ENTERING_WORLD", function()
  B.env.safe = true
  if not detected then
    detected = true
    Detect()
  end
  B.faction = UnitFactionGroup("player")
  B.enemy = (B.faction == "Alliance") and "Horde" or "Alliance"
  B:UpdateZone(true)
end)

B:On("ZONE_CHANGED_NEW_AREA", function()
  B:UpdateZone(false)
end)

-- No DLL calls during loading screens or logout (Error 132 prevention).
B:On("PLAYER_LEAVING_WORLD", function()
  B.env.safe = false
end)

B:On("PLAYER_LOGOUT", function()
  B.env.safe = false
  frame:UnregisterAllEvents()
  frame:SetScript("OnUpdate", nil)
  frame:SetScript("OnEvent", nil)
end)

-- ---------------------------------------------------------------- slash

B.commands = {}
local order = {}

function B:Command(name, help, fn)
  if not self.commands[name] then table.insert(order, name) end
  self.commands[name] = { help = help, fn = fn }
end

function B:Help()
  self:Print("v" .. self.VERSION .. " commands:")
  for i = 1, table.getn(order) do
    local c = self.commands[order[i]]
    if c.help then
      DEFAULT_CHAT_FRAME:AddMessage("  |cffffd100/obg " .. order[i] .. "|r - " .. c.help)
    end
  end
end

SLASH_OCTOBG1 = "/obg"
SLASH_OCTOBG2 = "/octobg"
SlashCmdList["OCTOBG"] = function(msg)
  local _, _, cmd, rest = string.find(msg or "", "^%s*(%S*)%s*(.-)%s*$")
  cmd = string.lower(cmd or "")
  if cmd == "" then cmd = "config" end
  local c = B.commands[cmd]
  if not c then
    B:Help()
    return
  end
  local ok, err = pcall(c.fn, rest or "")
  if not ok then B:Error(err) end
end
