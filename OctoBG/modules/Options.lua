-- OctoBG :: options and slash commands
-- /obg opens the options window. Layout mode (/obg unlock) shows every panel
-- with sample data and a blue drag handle; /obg lock ends it.

local B = OctoBG
local U = B.U
local O = { checks = {}, sliders = {} }
B.Options = O

local W, H = 380, 670

StaticPopupDialogs["OCTOBG_AUTOPOST"] = {
  text = "OctoBG: post INC calls to /bg automatically when enemies reach the base you are standing at?\n\n(At most one call every 20 seconds, only for 2 or more enemies.)",
  button1 = YES,
  button2 = NO,
  OnAccept = function()
    B.db.inc.autoPost = true
    B.db.inc.autoAsked = true
    O:Refresh()
  end,
  OnCancel = function()
    B.db.inc.autoPost = false
    O:Refresh()
  end,
  timeout = 0,
  whileDead = 1,
  hideOnEscape = 1,
}

-- ---------------------------------------------------------------- widgets

local function Label(parent, text, x, y, size, r, g, b)
  local fs = U.Text(parent, size or 11)
  fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  fs:SetTextColor(r or 1, g or 1, b or 1)
  fs:SetText(text)
  return fs
end

-- get/set read and write the setting; a section's checks sit in two columns.
local function Check(parent, label, x, y, get, set, tip)
  local n = table.getn(O.checks) + 1
  local c = CreateFrame("CheckButton", "OctoBGCheck" .. n, parent, "UICheckButtonTemplate")
  c:SetWidth(22)
  c:SetHeight(22)
  c:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  local fs = U.Text(c, 10)
  fs:SetPoint("LEFT", c, "RIGHT", 2, 0)
  fs:SetText(label)
  c.get, c.set = get, set
  c:SetScript("OnClick", function()
    this.set(this:GetChecked() and true or false)
    O:Refresh()
  end)
  if tip then
    c:SetScript("OnEnter", function()
      GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
      GameTooltip:AddLine(label)
      GameTooltip:AddLine(tip, 1, 1, 1, 1)
      GameTooltip:Show()
    end)
    c:SetScript("OnLeave", function() GameTooltip:Hide() end)
  end
  O.checks[n] = c
  return c
end

local function Slider(parent, label, x, y, minV, maxV, step, get, set, fmt)
  local n = table.getn(O.sliders) + 1
  local name = "OctoBGSlider" .. n
  local s = CreateFrame("Slider", name, parent, "OptionsSliderTemplate")
  s:SetWidth(160)
  s:SetHeight(16)
  s:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  s:SetMinMaxValues(minV, maxV)
  s:SetValueStep(step)
  local lo, hi, tx = getglobal(name .. "Low"), getglobal(name .. "High"), getglobal(name .. "Text")
  if lo then lo:SetText("") end
  if hi then hi:SetText("") end
  s.label, s.fmt, s.get, s.set, s.tx = label, fmt or "%d", get, set, tx
  s:SetScript("OnValueChanged", function()
    if this.loading then return end
    local v = this:GetValue()
    this.set(v)
    if this.tx then this.tx:SetText(this.label .. ": " .. string.format(this.fmt, v)) end
  end)
  O.sliders[n] = s
  return s
end

local function Button(parent, text, w, x, y, fn)
  local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  b:SetWidth(w)
  b:SetHeight(22)
  b:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  b:SetText(text)
  b:SetScript("OnClick", fn)
  return b
end

-- ---------------------------------------------------------------- window

function O:Build()
  local db = B.db
  local f = CreateFrame("Frame", "OctoBGOptions", UIParent)
  f:SetWidth(W)
  f:SetHeight(H)
  f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
  f:SetFrameStrata("DIALOG")
  f:SetMovable(true)
  f:EnableMouse(true)
  f:SetClampedToScreen(true)
  U.Backdrop(f, 0.95)
  f:SetScript("OnMouseDown", function() this:StartMoving() end)
  f:SetScript("OnMouseUp", function() this:StopMovingOrSizing() end)
  f:Hide()
  table.insert(UISpecialFrames, "OctoBGOptions")   -- Escape closes it
  self.frame = f

  Label(f, "|cff33ccffOcto|rBG  |cff888888v" .. B.VERSION .. "|r", 12, -10, 14)
  self.status = Label(f, "", 12, -30, 10, 0.75, 0.75, 0.75)

  local x1, x2 = 12, 196
  local y = -52
  Label(f, "Flag carriers", x1, y, 11, 1, 0.82, 0)
  y = y - 16
  Check(f, "Show", x1, y, function() return db.flags.enabled end, function(v) db.flags.enabled = v end)
  Check(f, "Alerts (pickup, low HP)", x2, y, function() return db.flags.alerts end, function(v) db.flags.alerts = v end)
  y = y - 24
  Label(f, "Right-click spell:", x1 + 4, y - 4, 10)
  local eb = CreateFrame("EditBox", "OctoBGSpellBox", f, "InputBoxTemplate")
  eb:SetWidth(150)
  eb:SetHeight(20)
  eb:SetPoint("TOPLEFT", f, "TOPLEFT", x1 + 112, y)
  eb:SetAutoFocus(false)
  eb:SetScript("OnEnterPressed", function()
    db.flags.spell = this:GetText()
    this:ClearFocus()
    O:Refresh()
  end)
  eb:SetScript("OnEscapePressed", function() this:ClearFocus() end)
  self.spellBox = eb
  Button(f, "Default", 60, x1 + 270, y, function()
    db.flags.spell = nil
    O:Refresh()
  end)

  y = y - 30
  Label(f, "Timers", x1, y, 11, 1, 0.82, 0)
  y = y - 16
  Check(f, "Show", x1, y, function() return db.timers.enabled end, function(v) db.timers.enabled = v end)
  Check(f, "Spirit resurrection", x2, y, function() return db.timers.spirit end, function(v) db.timers.spirit = v end)
  y = y - 22
  Check(f, "Big res countdown", x1, y, function() return db.timers.big end, function(v) db.timers.big = v end)
  Check(f, "AB win prediction", x2, y, function() return db.timers.predict end, function(v) db.timers.predict = v end)

  y = y - 28
  Label(f, "INC calls", x1, y, 11, 1, 0.82, 0)
  y = y - 16
  Check(f, "Show the bar", x1, y, function() return db.inc.enabled end, function(v) db.inc.enabled = v end)
  Check(f, "Guard alert (only you)", x2, y, function() return db.inc.alert end, function(v) db.inc.alert = v end,
    "While you stand at a base, enemies arriving there raise an alert on your screen.")
  y = y - 22
  Check(f, "Auto-post guard alerts to /bg", x1, y, function() return db.inc.autoPost end, function(v)
    if v then
      db.inc.autoPost = false
      StaticPopup_Show("OCTOBG_AUTOPOST")
    else
      db.inc.autoPost = false
    end
  end, "Asks before switching on. Off by default.")

  y = y - 28
  Label(f, "HUD and enemy list", x1, y, 11, 1, 0.82, 0)
  y = y - 16
  Check(f, "HUD", x1, y, function() return db.hud.enabled end, function(v) db.hud.enabled = v B:RefreshActive() end)
  Check(f, "Rotate with facing", x2, y, function() return db.hud.rotate end, function(v) db.hud.rotate = v end,
    "Off: north is up, like the map.")
  y = y - 22
  Check(f, "Enemies past range on the edge", x1, y, function() return db.hud.edge end, function(v) db.hud.edge = v end)
  Check(f, "Raid members", x2, y, function() return db.hud.friends end, function(v) db.hud.friends = v end)
  y = y - 22
  Check(f, "Enemy list", x1, y, function() return db.list.enabled end, function(v) db.list.enabled = v end)
  Check(f, "Outside battlegrounds too", x2, y, function() return db.hud.world end, function(v) db.hud.world = v B:RefreshActive() end,
    "HUD, enemy list and tactical map in the open world as well (world PvP).")
  y = y - 22
  Check(f, "Stealth marks", x1, y, function() return db.stealth.enabled end, function(v) db.stealth.enabled = v end,
    "Where enemies went into Stealth, Prowl, Vanish or Shadowmeld, with a circle for how far they may have moved since.")
  Check(f, "Stealth alert (60 yd)", x2, y, function() return db.stealth.alert end, function(v) db.stealth.alert = v end,
    "Alert and sound when an enemy stealths within " .. db.stealth.range .. " yards.")

  y = y - 28
  Label(f, "Tactical map", x1, y, 11, 1, 0.82, 0)
  y = y - 16
  Check(f, "Show", x1, y, function() return db.map.enabled end, function(v) db.map.enabled = v end)
  Check(f, "Enemies on the map", x2, y, function() return db.map.enemies end, function(v) db.map.enemies = v end)

  y = y - 40
  Slider(f, "HUD range (yd)", x1 + 4, y, 20, 100, 5, function() return db.hud.range end, function(v) db.hud.range = v B.HUD:Layout() end)
  Slider(f, "HUD size", x2 + 4, y, 140, 420, 10, function() return db.hud.size end, function(v) db.hud.size = v B.HUD:Layout() end)
  y = y - 40
  Slider(f, "HUD opacity", x1 + 4, y, 0.2, 1, 0.05, function() return db.hud.alpha end, function(v) db.hud.alpha = v B.HUD:Layout() end, "%.2f")
  Slider(f, "Names on HUD", x2 + 4, y, 0, 10, 1, function() return db.hud.names end, function(v) db.hud.names = v end)
  y = y - 40
  Slider(f, "Enemy list rows", x1 + 4, y, 3, 15, 1, function() return db.list.rows end, function(v) db.list.rows = v end)
  Slider(f, "Map width", x2 + 4, y, 180, 520, 10, function() return db.map.width end, function(v) db.map.width = v B.TacMap:Layout() end)
  y = y - 40
  Slider(f, "INC count radius (yd)", x1 + 4, y, 20, 100, 5, function() return db.inc.radius end, function(v) db.inc.radius = v end)
  Slider(f, "EFC low HP alert (%)", x2 + 4, y, 10, 60, 5, function() return db.flags.lowHp end, function(v) db.flags.lowHp = v end)
  y = y - 40
  Slider(f, "Panel scale", x1 + 4, y, 0.6, 1.6, 0.05, function() return db.scale end, function(v) db.scale = v U.ApplyScale() end, "%.2f")
  Slider(f, "Map darkness (%)", x2 + 4, y, 0, 90, 5, function() return math.floor(db.map.dim * 100 + 0.5) end,
    function(v) db.map.dim = v / 100 B.TacMap:Layout() end)

  local by = -H + 34
  self.layoutBtn = Button(f, "Layout mode", 86, 12, by, function()
    U.SetLocked(not B.db.locked)
    O:Refresh()
  end)
  Button(f, "Reset pos.", 86, 102, by, function() U.ResetPositions() end)
  local mv = Button(f, "Max view", 86, 192, by, function() O:MaxView(false) end)
  mv:SetScript("OnEnter", function()
    GameTooltip:SetOwner(this, "ANCHOR_TOP")
    GameTooltip:AddLine("Max view distance")
    GameTooltip:AddLine("Raises unit draw distance, horizon and nameplate range. /obg maxview off puts them back.", 1, 1, 1, 1)
    GameTooltip:Show()
  end)
  mv:SetScript("OnLeave", function() GameTooltip:Hide() end)
  Button(f, "Close", 86, 282, by, function() f:Hide() end)

  f:SetScript("OnShow", function() O:Refresh() end)
end

function O:Refresh()
  local f = self.frame
  if not f or not f:IsShown() then return end
  for i = 1, table.getn(self.checks) do
    local c = self.checks[i]
    c:SetChecked(c.get() and 1 or nil)
  end
  for i = 1, table.getn(self.sliders) do
    local s = self.sliders[i]
    local v = s.get()
    s.loading = true
    s:SetValue(v)
    s.loading = nil
    if s.tx then s.tx:SetText(s.label .. ": " .. string.format(s.fmt, v)) end
  end
  self.spellBox:SetText(B.Flags:Spell())
  self.layoutBtn:SetText(B.db.locked and "Layout mode" or "Lock panels")
  self.status:SetText(O:StatusLine())
end

local function Mark(ok)
  return ok and "|cff55ff55yes|r" or "|cffff5555no|r"
end

function O:StatusLine()
  local e = B.env
  local cal
  if B.Map:CalibrationDone() then cal = "|cff55ff55calibrated|r" else cal = "|cffffd100learning (run forward a bit)|r" end
  return "SuperWoW " .. Mark(e.superwow) .. "  nampower " .. Mark(e.nampower) .. "  UnitXP " .. Mark(e.unitxp)
    .. "  facing " .. cal
end

-- ---------------------------------------------------------------- view distance

-- What /obg maxview raises (only ever up). None of these change what the
-- server sends: enemies further than its visibility range do not exist for
-- the client. They make what it does send visible on screen.
--   unitDrawDist         players/NPC models drawn this far (client, default 300)
--   horizonfarclip       horizon distance (client, default 2112)
--   farclip              terrain distance; the slider stops at 777
--   NP_NameplateDistance nameplate range, nampower (NampowerSettings allows 200)
--   NameplateRange       nameplate range, SuperWoW (SuperAPI allows 80)
-- Nameplates are also one of the ways OctoBG finds enemies who do nothing.
local VIEW = {
  { "farclip", 777 },
  { "horizonfarclip", 6226 },
  { "unitDrawDist", 1000 },
  { "NP_NameplateDistance", 200 },
  { "NameplateRange", 80 },
}

local function CVar(name)
  local ok, v = pcall(GetCVar, name)
  if ok then return v end
  return nil
end

function O:MaxView(off)
  if off then
    local bk = B.db.viewBackup
    if not bk then
      B:Print("nothing to restore - /obg maxview has not changed anything")
      return
    end
    for name, v in pairs(bk) do pcall(SetCVar, name, v) end
    B.db.viewBackup = nil
    B:Print("view settings put back as they were")
    return
  end
  local bk = B.db.viewBackup or {}
  for i = 1, table.getn(VIEW) do
    local name, want = VIEW[i][1], VIEW[i][2]
    local cur = CVar(name)
    if cur == nil then
      B:Print(name .. ": not on this client")
    elseif tonumber(cur) and tonumber(cur) >= want then
      B:Print(name .. " " .. cur .. " - already at least " .. want)
    else
      if bk[name] == nil then bk[name] = cur end
      pcall(SetCVar, name, tostring(want))
      B:Print(name .. " " .. cur .. " -> " .. tostring(CVar(name)))
    end
  end
  B.db.viewBackup = bk
  B:Print("saved to Config.wtf when you log out; /obg maxview off puts them back")
end

function O:PrintReach()
  local T = B.Tracker
  local max, drop, n = T:ReachSummary()
  if T.reachZone and max > 0 then
    B:Print("here (" .. T.reachZone .. "): enemies picked up as far as " .. math.floor(max) .. " yd"
      .. (drop and (", they drop out at about " .. math.floor(drop) .. " yd (" .. n .. " seen leaving)") or ""))
  end
  for zone, r in pairs(B.db.reach) do
    B:Print(zone .. ": up to " .. math.floor(r.max) .. " yd"
      .. (r.drop and (", drop out at ~" .. math.floor(r.drop) .. " yd") or "") .. " (" .. (r.day or "?") .. ")")
  end
end

function O:Toggle()
  if not self.frame then self:Build() end
  if self.frame:IsShown() then self.frame:Hide() else self.frame:Show() end
end

-- ---------------------------------------------------------------- slash commands

B:Command("config", "open the options", function() O:Toggle() end)
B:Command("unlock", "layout mode: sample data and drag handles on every panel", function()
  U.SetLocked(false)
  B:Print("layout mode on - drag the blue panels, /obg lock when done")
end)
B:Command("lock", "end layout mode", function()
  U.SetLocked(true)
  B:Print("panels locked")
end)
B:Command("hud", "toggle the HUD", function() OctoBG_ToggleHUD() end)
B:Command("reset", "move every panel back to its default place", function() U.ResetPositions() end)
B:Command("maxview", "raise draw distance, horizon and nameplate range (/obg maxview off: put back)", function(rest)
  O:MaxView(string.lower(rest or "") == "off")
end)
B:Command("reach", "how far away enemies were picked up, per zone", function() O:PrintReach() end)
B:Command("dim","<0-90> darken the tactical map so the markers stand out", function(rest)
  local v = tonumber(rest)
  if not v then
    B:Print("map darkness " .. math.floor(B.db.map.dim * 100 + 0.5) .. "% - /obg dim 0..90")
    return
  end
  B.db.map.dim = math.max(0, math.min(90, v)) / 100
  B.TacMap:Layout()
  O:Refresh()
end)
B:Command("calib", "forget the learned facing/axes and learn them again", function()
  B.Map:ResetCalibration()
  B:Print("calibration reset - run forward in a straight line for a few seconds")
end)
B:Command("status", "show detected DLLs and tracker state", function()
  B:Print(O:StatusLine())
  B:Print("zone " .. tostring(B.zone) .. " (" .. tostring(B.zoneName) .. "), active " .. tostring(B.active)
    .. ", enemies tracked " .. B.Tracker.count)
end)
B:Command("probe", "print what the client returns for positions and the map (for bug reports)", function()
  local M = B.Map
  local px, py, pz = U.Position("player")
  B:Print("UnitPosition player: " .. tostring(px) .. ", " .. tostring(py) .. ", " .. tostring(pz)
    .. "  raw facing: " .. tostring(M:RawFacing()) .. "  sign " .. tostring(B.db.facingSign)
    .. "  swapXY " .. tostring(B.db.swapXY))
  local mx, my = M:UnitMap("player")
  B:Print("map file: " .. tostring(GetMapInfo()) .. "  map pos: " .. tostring(mx) .. ", " .. tostring(my))
  if mx then
    local wx, wy = M:ToWorld(mx, my)
    B:Print("map -> world: " .. tostring(wx) .. ", " .. tostring(wy))
  end
  if UnitExists("target") then
    local g = U.GuidOf("target")
    local tx, ty, tz = U.Position("target")
    B:Print("target " .. tostring(UnitName("target")) .. " guid " .. tostring(g)
      .. " pos " .. tostring(tx) .. ", " .. tostring(ty) .. ", " .. tostring(tz)
      .. " dist " .. tostring(U.Distance("target")) .. " sight " .. tostring(U.InSight("target")))
  end
  if GetNumBattlefieldFlagPositions then
    for i = 1, GetNumBattlefieldFlagPositions() do
      local fx, fy, tok = GetBattlefieldFlagPosition(i)
      B:Print("flag " .. i .. ": " .. tostring(fx) .. ", " .. tostring(fy) .. " " .. tostring(tok))
    end
  end
end)
B:Command("debug", "toggle debug output", function()
  B.debug = not B.debug
  B:Print("debug " .. (B.debug and "on" or "off"))
end)
B:Command("errors", "list errors caught this session", function()
  local n = 0
  for err in pairs(B.errors) do
    n = n + 1
    B:Print(err)
  end
  if n == 0 then B:Print("no errors") end
  B:ClearErrors()
end)

B:On("OBG_INIT", function()
  B:Print("v" .. B.VERSION .. " loaded - /obg for options, /obg unlock to arrange the panels")
end)
