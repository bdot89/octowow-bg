-- OctoBG :: util
-- Shared helpers: GUIDs, DLL wrappers (SuperWoW / nampower / UnitXP_SP3),
-- colours, time formatting, movable panels, texture rotation, the /bg sender
-- and the on-screen alert.

local B = OctoBG
local U = {}
B.U = U

U.MEDIA = "Interface\\AddOns\\OctoBG\\media\\"
U.FONT = "Fonts\\FRIZQT__.TTF"
U.NARROW = "Fonts\\ARIALN.TTF"
U.WHITE = "Interface\\ChatFrame\\ChatFrameBackground"
U.FLAG = { Alliance = "Interface\\WorldStateFrame\\AllianceFlag", Horde = "Interface\\WorldStateFrame\\HordeFlag" }
U.FACTION = { Alliance = { 0.3, 0.6, 1.0 }, Horde = { 1.0, 0.25, 0.2 } }
U.STEALTH = { 0.8, 0.4, 1.0 }   -- purple: where an enemy went into stealth
U.PI = 3.14159265358979

-- ---------------------------------------------------------------- GUIDs

-- GUID of a unit token. nampower's GetUnitGUID covers player, target,
-- mouseover, party/raid and raw GUIDs; SuperWoW's UnitExists returns the GUID
-- as its second value for every token (e.g. "raid5target").
function U.GuidOf(unit)
  if not unit then return nil end
  if GetUnitGUID then
    local g = GetUnitGUID(unit)
    if g then return g end
  end
  local _, g = UnitExists(unit)
  if type(g) == "string" then return g end
  return nil
end

-- True while the GUID is in the client's object list. GetUnitGUID keeps
-- working for Feign Death hunters, where UnitExists does not (Spy's finding).
function U.GuidExists(guid)
  if not guid then return false end
  if GetUnitGUID then return GetUnitGUID(guid) ~= nil end
  return UnitExists(guid) and true or false
end

-- Creature entry of a vanilla creature GUID: 0xF130 EEEEEE LLLLLL.
function U.CreatureEntry(guid)
  if type(guid) ~= "string" then return nil end
  if string.upper(string.sub(guid, 1, 6)) ~= "0XF130" then return nil end
  return tonumber(string.sub(guid, 7, 12), 16)
end

-- ---------------------------------------------------------------- DLL wrappers

-- Yards between the player and a unit/GUID (UnitXP_SP3), or nil.
function U.Distance(u)
  if not B.env.unitxp or not B.env.safe or not u then return nil end
  local ok, d = pcall(UnitXP, "distanceBetween", "player", u)
  if ok and type(d) == "number" then return d end
  return nil
end

-- Line of sight from the player to a unit/GUID (UnitXP_SP3), or nil.
function U.InSight(u)
  if not B.env.unitxp or not B.env.safe or not u then return nil end
  local ok, v = pcall(UnitXP, "inSight", "player", u)
  if not ok then return nil end
  if type(v) == "boolean" then return v end
  if type(v) == "number" then return v ~= 0 end
  return nil
end

-- World position x (north), y (west), z of a unit/GUID (SuperWoW), or nil.
-- Map.lua learns once whether this build hands the axes back swapped.
function U.Position(u)
  if not B.env.position or not B.env.safe or not u then return nil end
  local ok, x, y, z = pcall(UnitPosition, u)
  if not ok or type(x) ~= "number" or type(y) ~= "number" then return nil end
  if x == 0 and y == 0 then return nil end
  if B.db and B.db.swapXY then return y, x, z end
  return x, y, z
end

-- Raw (never swapped) position for the calibration in Map.lua.
function U.RawPosition(u)
  if not B.env.position or not B.env.safe then return nil end
  local ok, x, y = pcall(UnitPosition, u)
  if ok and type(x) == "number" and type(y) == "number" and not (x == 0 and y == 0) then
    return x, y
  end
  return nil
end

-- Target a unit by GUID (SuperWoW) and fall back to the exact name.
function U.TargetGuidOrName(guid, name)
  if guid and B.env.superwow and U.GuidExists(guid) then
    TargetUnit(guid)
    if not name or UnitName("target") == name then return true end
  end
  if name then
    TargetByName(name, true)
    return UnitName("target") == name
  end
  return false
end

-- ---------------------------------------------------------------- colours / text

-- High-contrast class colours for markers on a dark map. The 1.12 client's
-- RAID_CLASS_COLORS gives Shaman the Paladin pink and a dull Warlock purple,
-- and Warrior tan sits close to Druid orange; these are saturated and apart.
U.BRIGHT = {
  WARRIOR = { 0.92, 0.74, 0.52 },
  PALADIN = { 1.0, 0.42, 0.75 },
  HUNTER  = { 0.45, 1.0, 0.2 },
  ROGUE   = { 1.0, 0.96, 0.15 },
  PRIEST  = { 1.0, 1.0, 1.0 },
  SHAMAN  = { 0.1, 0.42, 1.0 },
  MAGE    = { 0.3, 0.9, 1.0 },
  WARLOCK = { 0.66, 0.4, 1.0 },
  DRUID   = { 1.0, 0.5, 0.0 },
}

function U.ClassColor(token)
  local m = B.db and B.db.markers
  local bc = token and m and m.bright and U.BRIGHT[token]
  if bc then return bc[1], bc[2], bc[3] end
  local c = token and RAID_CLASS_COLORS and RAID_CLASS_COLORS[token]
  if c then return c.r, c.g, c.b end
  return 0.75, 0.75, 0.75
end

function U.Hex(r, g, b)
  return string.format("|cff%02x%02x%02x", math.floor(r * 255), math.floor(g * 255), math.floor(b * 255))
end

-- Class token from a localised class name (the scoreboard returns those).
function U.ClassToken(name)
  if not name then return nil end
  local t = string.upper(name)
  if RAID_CLASS_COLORS and RAID_CLASS_COLORS[t] then return t end
  return nil
end

-- "45", "1:05" -- countdowns round up so 0 only shows when it is over.
function U.Time(s)
  if not s or s < 0 then s = 0 end
  s = math.ceil(s - 0.05)
  if s >= 60 then
    return string.format("%d:%02d", math.floor(s / 60), math.mod(s, 60))
  end
  return tostring(s)
end

function U.Text(parent, size, font, layer)
  local fs = parent:CreateFontString(nil, layer or "OVERLAY")
  fs:SetFont(font or U.FONT, size or 11, "OUTLINE")
  return fs
end

function U.Tex(parent, file, layer)
  local t = parent:CreateTexture(nil, layer or "ARTWORK")
  t:SetTexture(file or U.WHITE)
  return t
end

function U.Backdrop(f, alpha)
  f:SetBackdrop({
    bgFile = U.WHITE, edgeFile = U.WHITE, tile = false, tileSize = 0, edgeSize = 1,
    insets = { left = 1, right = 1, top = 1, bottom = 1 },
  })
  f:SetBackdropColor(0.04, 0.04, 0.05, alpha or 0.8)
  f:SetBackdropBorderColor(0.22, 0.22, 0.25, 1)
end

-- Rotate a square texture by angle a (radians, counter-clockwise on screen)
-- around its centre, using the 8-argument SetTexCoord.
function U.Rotate(tex, a)
  local s, c = math.sin(a) * 0.5, math.cos(a) * 0.5
  tex:SetTexCoord(0.5 - c + s, 0.5 - s - c,    -- upper left
                  0.5 - c - s, 0.5 - s + c,    -- lower left
                  0.5 + c + s, 0.5 + s - c,    -- upper right
                  0.5 + c - s, 0.5 + s + c)    -- lower right
end

-- ---------------------------------------------------------------- panels

-- Panels are placed by their TOPLEFT corner; positions live in B.db.pos[key].
-- In layout mode (/obg unlock) a blue handle covers each panel for dragging.
U.panels = {}

function U.SavePos(f)
  local x, y = f:GetLeft(), f:GetTop()
  if not x or not y then return end
  B.db.pos[f.key] = { x = x, y = y }
  f:ClearAllPoints()
  f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x, y)
end

function U.RestorePos(f)
  f:ClearAllPoints()
  local p = B.db and B.db.pos[f.key]
  if p then
    f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", p.x, p.y)
  else
    f:SetPoint(f.defPoint, UIParent, f.defPoint, f.defX, f.defY)
  end
end

function U.Panel(name, key, label, w, h, defPoint, defX, defY)
  local f = CreateFrame("Frame", name, UIParent)
  f:SetWidth(w)
  f:SetHeight(h)
  f:SetFrameStrata("MEDIUM")
  f:SetMovable(true)
  f:SetClampedToScreen(true)
  f:SetScale(B.db.scale or 1)
  f.key, f.defPoint, f.defX, f.defY = key, defPoint, defX, defY
  U.RestorePos(f)

  local hd = CreateFrame("Frame", nil, f)
  hd:SetAllPoints(f)
  hd:SetFrameLevel(f:GetFrameLevel() + 30)
  U.Backdrop(hd, 0.3)
  hd:SetBackdropColor(0.1, 0.45, 0.9, 0.3)
  hd:SetBackdropBorderColor(0.3, 0.7, 1, 1)
  hd:EnableMouse(true)
  local tx = U.Text(hd, 11)
  tx:SetPoint("CENTER", hd, "CENTER", 0, 0)
  tx:SetText(label or key)
  hd:SetScript("OnMouseDown", function()
    if arg1 == "LeftButton" then f:StartMoving() end
  end)
  hd:SetScript("OnMouseUp", function()
    f:StopMovingOrSizing()
    U.SavePos(f)
  end)
  if B.db.locked then hd:Hide() end
  f.handle = hd

  table.insert(U.panels, f)
  return f
end

function U.SetLocked(locked)
  B.db.locked = locked and true or false
  for i = 1, table.getn(U.panels) do
    local f = U.panels[i]
    if B.db.locked then f.handle:Hide() else f.handle:Show() end
  end
  B.test = not B.db.locked
  B:RefreshActive()
  B:Fire("OBG_LAYOUT", B.test)
end

function U.ResetPositions()
  B.db.pos = {}
  for i = 1, table.getn(U.panels) do U.RestorePos(U.panels[i]) end
end

function U.ApplyScale()
  for i = 1, table.getn(U.panels) do U.panels[i]:SetScale(B.db.scale or 1) end
end

-- ---------------------------------------------------------------- chat

-- Posts to /bg. One line a second at most, the same text once per 4 seconds,
-- colour/link codes stripped, 255 bytes max. Outside a battleground the line
-- only goes to the player's own chat.
local lastSend, lastMsg, lastMsgAt = 0, nil, 0
function U.SendBG(msg)
  if not msg or msg == "" then return false end
  local now = GetTime()
  if now - lastSend < 1 then return false end
  if msg == lastMsg and now - lastMsgAt < 4 then return false end
  lastSend, lastMsg, lastMsgAt = now, msg, now
  msg = string.gsub(msg, "|", "")
  if string.len(msg) > 255 then msg = string.sub(msg, 1, 255) end
  if B:IsBG() then
    SendChatMessage(msg, "BATTLEGROUND")
  else
    B:Print("(not in a battleground, not sent) " .. msg)
  end
  return true
end

-- ---------------------------------------------------------------- alert

local alert
function U.Alert(msg, r, g, b, sound)
  if not alert then
    alert = CreateFrame("Frame", "OctoBGAlert", UIParent)
    alert:SetWidth(600)
    alert:SetHeight(30)
    alert:SetPoint("TOP", UIParent, "TOP", 0, -190)
    alert:SetFrameStrata("HIGH")
    alert.text = U.Text(alert, 20)
    alert.text:SetPoint("CENTER", alert, "CENTER", 0, 0)
    alert:SetScript("OnUpdate", function()
      this.t = this.t - arg1
      if this.t <= 0 then
        this:Hide()
      elseif this.t < 1 then
        this:SetAlpha(this.t)
      end
    end)
  end
  alert.text:SetText(msg)
  alert.text:SetTextColor(r or 1, g or 0.82, b or 0)
  alert.t = 3.5
  alert:SetAlpha(1)
  alert:Show()
  if sound then PlaySound("RaidWarning") end
end
