-- OctoBG :: tactical map
-- The battleground's own map with live markers: you (arrow), raid members
-- (small class dots), every enemy the tracker can place (class-coloured
-- triangles with a black rim, always full colour; only a last known spot
-- fades, to half), both flag carriers (server-sent, anywhere on the map) and
-- the AB/AV objective icons. Under it: where the enemy carrier is.
--
-- Drawing order is fixed with child frames: regions sharing one draw layer
-- have no set order in this client (the map tiles and the panel backdrop were
-- both BACKGROUND and swapped at random, blacking the map out).

local B = OctoBG
local U = B.U
local M = B.Map
local TM = { tiles = {}, pals = {}, foes = {}, pois = {}, flags = {}, ghosts = {} }
B.TacMap = TM

-- The world map draws a 1002 x 668 area from a 4 x 3 grid of 256 px tiles;
-- map coordinates 0..1 span that area.
local MAP_W, MAP_H = 1002, 668
local POI = "Interface\\Minimap\\POIIcons"

local function Dot(parent, file, layer, size)
  local t = U.Tex(parent, file, layer)
  t:SetWidth(size)
  t:SetHeight(size)
  t:Hide()
  return t
end

local function Layer(f, level)
  local l = CreateFrame("Frame", nil, f)
  l:SetAllPoints(f)
  l:SetFrameLevel(level)
  return l
end

local function Size(t, s)
  t:SetWidth(s)
  t:SetHeight(s)
end

local function PlaceMap(tex, f, mx, my, w, h)
  tex:SetPoint("CENTER", f, "TOPLEFT", mx * w, -my * h)
  tex:Show()
end

function TM:Build()
  local w = B.db.map.width
  local f = U.Panel("OctoBGMap", "map", "Tactical map", w, w * MAP_H / MAP_W, "TOPLEFT", 30, -170)
  U.Backdrop(f, 0.9)
  f:Hide()
  self.frame = f
  local lv = f:GetFrameLevel()
  self.canvas = Layer(f, lv + 1)   -- tiles, darkening, objective icons
  self.palLayer = Layer(f, lv + 2) -- raid members
  self.foeLayer = Layer(f, lv + 3) -- enemies
  self.topLayer = Layer(f, lv + 4) -- flag carriers, you

  for i = 1, 12 do self.tiles[i] = U.Tex(self.canvas, nil, "BACKGROUND") end
  self.dim = U.Tex(self.canvas, U.WHITE, "BORDER")
  self.dim:SetAllPoints(f)

  self.me = Dot(self.topLayer, U.MEDIA .. "player", "OVERLAY", 14)
  self.flags.Alliance = Dot(self.topLayer, U.FLAG.Alliance, "OVERLAY", 18)
  self.flags.Horde = Dot(self.topLayer, U.FLAG.Horde, "OVERLAY", 18)
  self.where = U.Text(f, 10, U.NARROW)
  self.where:SetPoint("TOPLEFT", f, "BOTTOMLEFT", 2, -2)
  self.where:SetJustifyH("LEFT")
  self:Layout()
end

function TM:Layout()
  local f = self.frame
  if not f then return end
  local w = B.db.map.width
  local h = w * MAP_H / MAP_W
  f:SetWidth(w)
  f:SetHeight(h)
  local k = w / MAP_W
  for i = 1, 12 do
    local row = math.floor((i - 1) / 4)
    local col = math.mod(i - 1, 4)
    local tw = (col == 3) and (MAP_W - 768) or 256
    local th = (row == 2) and (MAP_H - 512) or 256
    local t = self.tiles[i]
    t:SetWidth(tw * k)
    t:SetHeight(th * k)
    t:SetPoint("TOPLEFT", f, "TOPLEFT", col * 256 * k, -row * 256 * k)
    t:SetTexCoord(0, tw / 256, 0, th / 256)
  end
  self.w, self.h = w, h
  self.dim:SetVertexColor(0, 0, 0, B.db.map.dim or 0)

  -- marker sizes grow with the map: stealth ring, its centre, enemy triangle, raid member
  self.ringS = math.max(12, math.min(20, w / 32))
  self.pipS = self.ringS * 0.55
  self.triS = self.ringS * 1.15
  self.palS = self.ringS * 0.6
  for i = 1, table.getn(self.foes) do Size(self.foes[i], self.triS) end
  for i = 1, table.getn(self.pals) do Size(self.pals[i], self.palS) end
end

function TM:SetFile(file)
  if file == self.file then return end
  self.file = file
  for i = 1, 12 do
    if file then
      self.tiles[i]:SetTexture("Interface\\WorldMap\\" .. file .. "\\" .. file .. i)
      self.tiles[i]:Show()
    else
      self.tiles[i]:Hide()
    end
  end
end

function TM:Foe(i)
  local t = self.foes[i]
  if not t then
    t = Dot(self.foeLayer, U.MEDIA .. "tri", "ARTWORK", self.triS)
    self.foes[i] = t
  end
  return t
end

function TM:Ghost(i)
  local gh = self.ghosts[i]
  if not gh then
    local c = U.STEALTH
    gh = {
      area = Dot(self.foeLayer, U.MEDIA .. "ring", "BORDER", 10),
      ring = Dot(self.foeLayer, U.MEDIA .. "badge", "ARTWORK", self.ringS),
      pip = Dot(self.foeLayer, U.MEDIA .. "pip", "OVERLAY", self.pipS),
    }
    gh.area:SetVertexColor(c[1], c[2], c[3], 0.6)
    gh.ring:SetVertexColor(c[1], c[2], c[3], 1)
    self.ghosts[i] = gh
  end
  return gh
end

-- Where enemies went into stealth, with a circle (to map scale) for how far
-- they may have moved since.
function TM:DrawStealth(f, w, h, now)
  local T = B.Tracker
  local d = M:Cur()
  local yd = d and (w / (d.L - d.R)) or 0     -- map pixels per yard
  local n = 0
  for guid, m in pairs(T.stealth) do
    local u = T.units[guid]
    if m.x and d and not (u and u.visible) and n < 20 then
      local mx, my = M:ToMap(m.x, m.y)
      if mx and mx >= 0 and mx <= 1 and my >= 0 and my <= 1 then
        n = n + 1
        local gh = self:Ghost(n)
        local r, g, b = U.ClassColor(m.class)
        gh.pip:SetVertexColor(r, g, b, 1)
        PlaceMap(gh.ring, f, mx, my, w, h)
        PlaceMap(gh.pip, f, mx, my, w, h)
        local rad = T:StealthRadius(m, now) * yd
        if rad >= 4 then
          Size(gh.area, rad * 2 * 64 / 61.5)
          PlaceMap(gh.area, f, mx, my, w, h)
        else
          gh.area:Hide()
        end
      end
    end
  end
  for i = n + 1, table.getn(self.ghosts) do
    local gh = self.ghosts[i]
    gh.area:Hide()
    gh.ring:Hide()
    gh.pip:Hide()
  end
end

function TM:Pal(i)
  local t = self.pals[i]
  if not t then
    t = Dot(self.palLayer, U.MEDIA .. "pip", "ARTWORK", self.palS)
    self.pals[i] = t
  end
  return t
end


function TM:Samples(f, w, h)
  self:SetFile("WarsongGulch")
  PlaceMap(self.flags.Alliance, f, 0.52, 0.8, w, h)
  PlaceMap(self.flags.Horde, f, 0.47, 0.35, w, h)
  U.Rotate(self.me, 0.6)
  PlaceMap(self.me, f, 0.5, 0.55, w, h)
  local spots = { { 0.52, 0.8, "ROGUE" }, { 0.49, 0.62, "MAGE" }, { 0.51, 0.6, "PRIEST" }, { 0.53, 0.63, "HUNTER" } }
  for i = 1, table.getn(spots) do
    local s = spots[i]
    local t = self:Foe(i)
    local r, g, b = U.ClassColor(s[3])
    t:SetVertexColor(r, g, b, 1)
    PlaceMap(t, f, s[1], s[2], w, h)
  end
  local p = self:Pal(1)
  local r, g, b = U.ClassColor("WARRIOR")
  p:SetVertexColor(r, g, b, 1)
  PlaceMap(p, f, 0.5, 0.61, w, h)
  local gh = self:Ghost(1)
  r, g, b = U.ClassColor("DRUID")
  gh.pip:SetVertexColor(r, g, b, 1)
  PlaceMap(gh.ring, f, 0.44, 0.5, w, h)
  PlaceMap(gh.pip, f, 0.44, 0.5, w, h)
  Size(gh.area, w * 0.09)
  PlaceMap(gh.area, f, 0.44, 0.5, w, h)
  self.where:SetText("|cffff5555EFC|r Testrogue - Horde base - lower level")
end

function TM:Update()
  local f, w, h = self.frame, self.w, self.h
  local d = M:Cur()
  local now = GetTime()

  if not d then
    -- layout mode outside a battleground: Warsong Gulch with sample markers
    self:Samples(f, w, h)
    return
  end
  self:SetFile(d.file)

  -- objective icons
  local marks = M:Landmarks()
  local np = 0
  for i = 1, table.getn(marks) do
    local m = marks[i]
    if m.tex and WorldMap_GetPOITextureCoords then
      np = np + 1
      local t = self.pois[np]
      if not t then
        t = Dot(self.canvas, POI, "ARTWORK", 14)
        self.pois[np] = t
      end
      t:SetTexCoord(WorldMap_GetPOITextureCoords(m.tex))
      PlaceMap(t, f, m.mx, m.my, w, h)
    end
  end
  for i = np + 1, table.getn(self.pois) do self.pois[i]:Hide() end

  -- raid (or party) members
  local nf = 0
  local nr = GetNumRaidMembers()
  local prefix, count = "raid", nr
  if nr == 0 then prefix, count = "party", GetNumPartyMembers() end
  for i = 1, count do
    local unit = prefix .. i
    if not UnitIsUnit(unit, "player") then
      local mx, my = M:UnitMap(unit)
      if mx then
        nf = nf + 1
        local t = self:Pal(nf)
        local _, class = UnitClass(unit)
        local r, g, b = U.ClassColor(class)
        t:SetVertexColor(r, g, b, UnitIsDeadOrGhost(unit) and 0.3 or 1)
        PlaceMap(t, f, mx, my, w, h)
      end
    end
  end
  for i = nf + 1, table.getn(self.pals) do self.pals[i]:Hide() end

  -- enemies: class-coloured triangles; a last known spot fades to half
  local ne = 0
  if B.db.map.enemies then
    local stealth = B.Tracker.stealth
    for guid, u in pairs(B.Tracker.units) do
      if u.x and not u.dead and now - (u.posAt or 0) < 10 and ne < 60 and not (stealth[guid] and not u.visible) then
        local mx, my = M:ToMap(u.x, u.y)
        if mx and mx >= 0 and mx <= 1 and my >= 0 and my <= 1 then
          ne = ne + 1
          local t = self:Foe(ne)
          local age = now - (u.posAt or 0)
          local a = (age > 2) and math.max(0.5, 1 - (age - 2) / 8) or 1
          local r, g, b = U.ClassColor(u.class)
          t:SetVertexColor(r, g, b, a)
          PlaceMap(t, f, mx, my, w, h)
        end
      end
    end
  end
  for i = ne + 1, table.getn(self.foes) do self.foes[i]:Hide() end
  self:DrawStealth(f, w, h, now)

  -- flag carriers (server-sent positions)
  local F = B.Flags
  for fac, t in pairs(self.flags) do
    local p = F.pos[fac]
    if p and now - p.t < 6 then
      PlaceMap(t, f, p.mx, p.my, w, h)
    else
      t:Hide()
    end
  end
  local efc = F:Enemy()
  if efc and not efc.dropped then
    self.where:SetText("|cffff5555EFC|r " .. efc.name .. (efc.where and (" - " .. efc.where) or ""))
  else
    self.where:SetText("")
  end

  -- me
  local mx, my = M:UnitMap("player")
  if mx then
    U.Rotate(self.me, M:Facing() or 0)
    PlaceMap(self.me, f, mx, my, w, h)
  else
    self.me:Hide()
  end
end

B:Every(0.2, function()
  local f = TM.frame
  if not f then return end
  local show = B.db.map.enabled
    and ((B.zone and M.DATA[B.zone]) or B.test or (B.db.hud.world and M.world))
  if show then
    if not f:IsShown() then f:Show() end
    TM:Update()
  elseif f:IsShown() then
    f:Hide()
  end
end, true)

B:On("OBG_ACTIVE", function(ev, on)
  if not on and TM.frame then TM.frame:Hide() end
end)

B:On("OBG_INIT", function() TM:Build() end)
