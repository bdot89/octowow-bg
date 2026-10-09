-- OctoBG :: HUD
-- A radar around the player, click-through, drawn from the tracker:
--   * enemy players: class-coloured triangles with a black rim (raid members
--     are round dots), always full colour; only last known positions fade
--     (to 40 %, gone after 8 s); enemies beyond range sit on the edge, smaller
--   * the enemy flag carrier gets a flag, your target a white ring
--   * raid members as small class dots under the enemies (our carrier with a flag)
--   * rotates with the camera-independent player facing, or north-up
-- Friends, enemies and the top markers live on child frames so they always
-- stack the same way (regions sharing a draw layer have no set order).
-- Next to it a clickable enemy list (nearest first): health, distance, line
-- of sight and the enemy's important cooldowns from EnemyCooldowns.

local B = OctoBG
local U = B.U
local M = B.Map
local H = { blips = {}, pals = {}, rows = {}, cds = {}, ghosts = {} }
B.HUD = H

local sqrt = math.sqrt
local MAX_BLIPS, MAX_PALS, LIST_MAX = 40, 40, 15
local ROW_H = 16
local RING_RATIO = 64 / 61.5   -- ring.tga draws its circle at 61.5 of 64 px

-- ---------------------------------------------------------------- radar UI

local function NewTex(parent, file, layer, size)
  local t = U.Tex(parent, file, layer)
  t:SetWidth(size)
  t:SetHeight(size)
  t:Hide()
  return t
end

function H:Build()
  local db = B.db.hud
  local f = U.Panel("OctoBGHUD", "hud", "HUD", db.size, db.size, "CENTER", 0, -40)
  f:SetFrameStrata("BACKGROUND")
  f:EnableMouse(false)
  f:Hide()
  self.frame = f

  self.bg = U.Tex(f, U.MEDIA .. "glow", "BACKGROUND")
  self.bg:SetAllPoints(f)
  self.bg:SetVertexColor(0, 0, 0, 0.5)

  self.rings = {}
  for i = 1, 3 do
    local t = U.Tex(f, U.MEDIA .. "ring", "BORDER")
    t:SetPoint("CENTER", f, "CENTER", 0, 0)
    t:SetVertexColor(0.75, 0.75, 0.8, i == 3 and 0.5 or 0.22)
    local l = U.Text(f, 9, U.NARROW)
    l:SetTextColor(0.6, 0.6, 0.65)
    self.rings[i] = { tex = t, label = l }
  end

  local lv = f:GetFrameLevel()
  self.palLayer = CreateFrame("Frame", nil, f)
  self.foeLayer = CreateFrame("Frame", nil, f)
  self.topLayer = CreateFrame("Frame", nil, f)
  self.palLayer:SetAllPoints(f)
  self.foeLayer:SetAllPoints(f)
  self.topLayer:SetAllPoints(f)
  self.palLayer:SetFrameLevel(lv + 1)
  self.foeLayer:SetFrameLevel(lv + 2)
  self.topLayer:SetFrameLevel(lv + 3)

  self.me = U.Tex(self.topLayer, U.MEDIA .. "player", "OVERLAY")
  self.me:SetWidth(16)
  self.me:SetHeight(16)
  self.me:SetPoint("CENTER", f, "CENTER", 0, 0)

  self.north = U.Text(self.topLayer, 10)
  self.north:SetText("N")
  self.north:SetTextColor(1, 0.82, 0)

  self.info = U.Text(f, 10, U.NARROW)
  self.info:SetPoint("TOP", f, "BOTTOM", 0, -2)

  self.efcMark = NewTex(self.topLayer, U.FLAG.Alliance, "OVERLAY", 18)
  self.ffcMark = NewTex(self.topLayer, U.FLAG.Horde, "OVERLAY", 16)
  self:Layout()
end

function H:Layout()
  local f = self.frame
  if not f then return end
  local db = B.db.hud
  f:SetWidth(db.size)
  f:SetHeight(db.size)
  f:SetAlpha(db.alpha)
  self.radius = db.size / 2 - 10
  for i = 1, 3 do
    local r = self.radius * i / 3
    local ring = self.rings[i]
    ring.tex:SetWidth(r * 2 * RING_RATIO)
    ring.tex:SetHeight(r * 2 * RING_RATIO)
    ring.label:SetPoint("BOTTOM", f, "CENTER", 0, r + 1)
    ring.label:SetText(tostring(math.floor(db.range * i / 3 + 0.5)))
  end
end

function H:Blip(i)
  local b = self.blips[i]
  if b then return b end
  b = {
    tri = NewTex(self.foeLayer, U.MEDIA .. "tri", "ARTWORK", 16),
    mark = NewTex(self.topLayer, U.MEDIA .. "circle", "ARTWORK", 24),
    name = U.Text(self.topLayer, 9, U.NARROW),
  }
  b.mark:SetVertexColor(1, 1, 1, 0.9)
  self.blips[i] = b
  return b
end

function H:Pal(i)
  local p = self.pals[i]
  if p then return p end
  p = NewTex(self.palLayer, U.MEDIA .. "pip", "ARTWORK", 7)
  self.pals[i] = p
  return p
end

local function Place(tex, f, x, y)
  tex:SetPoint("CENTER", f, "CENTER", x, y)
  tex:Show()
end

-- ---------------------------------------------------------------- radar update

function H:DrawEnemies(f, now, px, py, facing, rotate, scale)
  local db = B.db.hud
  local range = db.range
  local tg = U.GuidOf("target")
  local efc = B.Flags:Enemy()
  local efcName = efc and not efc.dropped and efc.name
  local efcDrawn = false

  -- names for the nearest few living enemies
  local sorted, k = B.Tracker.sorted, 0
  for i = 1, table.getn(sorted) do
    local u = sorted[i]
    u.showName = nil
    if not u.dead and k < db.names then
      k = k + 1
      u.showName = true
    end
  end

  local stealth = B.Tracker.stealth
  local nb, seen, inSight = 0, 0, 0
  for guid, u in pairs(B.Tracker.units) do
    -- an enemy gone into stealth is drawn by DrawStealth instead
    if u.x and not u.dead and nb < MAX_BLIPS and not (stealth[guid] and not u.visible) then
      local age = now - (u.posAt or 0)
      if u.visible and not u.fake then
        local x, y = U.Position(guid)
        if x then
          u.x, u.y, u.posAt = x, y, now
          age = 0
        end
      end
      if age < 8 then
        local sx, sy = M.Relative(px, py, facing, u.x, u.y, rotate)
        local d = sqrt(sx * sx + sy * sy)
        local edge = d > range
        if not edge then
          seen = seen + 1
          if u.los ~= false then inSight = inSight + 1 end
        end
        if not edge or db.edge then
          if edge then sx, sy = sx / d * range, sy / d * range end
          nb = nb + 1
          local b = self:Blip(nb)
          local ox, oy = sx * scale, sy * scale
          local r, g, bl = U.ClassColor(u.class)
          local a = 1
          if age > 1.5 then a = math.max(0.4, 1 - (age - 1.5) / 6.5) end
          local ts = edge and 10 or 16
          b.tri:SetWidth(ts)
          b.tri:SetHeight(ts)
          b.tri:SetVertexColor(r, g, bl, a)
          Place(b.tri, f, ox, oy)
          if tg and guid == tg then Place(b.mark, f, ox, oy) else b.mark:Hide() end
          if efcName and u.name == efcName then
            self.efcMark:SetTexture(U.FLAG[B.faction or "Alliance"])
            Place(self.efcMark, f, ox + 6, oy + 9)
            efcDrawn = true
          end
          if u.showName and u.visible and not edge then
            b.name:SetText(u.name or "")
            b.name:SetTextColor(r, g, bl, a)
            b.name:SetPoint("TOP", f, "CENTER", ox, oy - 8)
            b.name:Show()
          else
            b.name:Hide()
          end
        end
      end
    end
  end
  for i = nb + 1, table.getn(self.blips) do
    local b = self.blips[i]
    b.tri:Hide()
    b.mark:Hide()
    b.name:Hide()
  end

  -- an enemy carrier we only know from the map: point at it from the edge
  if efcName and not efcDrawn and efc.x and efc.posAt and now - efc.posAt < 8 then
    local sx, sy = M.Relative(px, py, facing, efc.x, efc.y, rotate)
    local d = sqrt(sx * sx + sy * sy)
    if d > range then sx, sy = sx / d * range, sy / d * range end
    self.efcMark:SetTexture(U.FLAG[B.faction or "Alliance"])
    Place(self.efcMark, f, sx * scale, sy * scale)
    efcDrawn = true
  end
  if not efcDrawn then self.efcMark:Hide() end
  return seen, inSight
end

-- Where enemies went into stealth: purple ring with the class colour, a
-- growing circle for how far they may have moved, and "Prowl 6s".
function H:Ghost(i)
  local gh = self.ghosts[i]
  if gh then return gh end
  gh = {
    area = NewTex(self.foeLayer, U.MEDIA .. "ring", "BORDER", 10),
    ring = NewTex(self.foeLayer, U.MEDIA .. "badge", "ARTWORK", 15),
    pip = NewTex(self.foeLayer, U.MEDIA .. "pip", "OVERLAY", 8),
    label = U.Text(self.topLayer, 9, U.NARROW),
  }
  local c = U.STEALTH
  gh.area:SetVertexColor(c[1], c[2], c[3], 0.55)
  gh.ring:SetVertexColor(c[1], c[2], c[3], 1)
  gh.label:SetTextColor(c[1], c[2], c[3])
  self.ghosts[i] = gh
  return gh
end

function H:DrawStealth(f, now, px, py, facing, rotate, scale)
  local T = B.Tracker
  local range = B.db.hud.range
  local n = 0
  for guid, m in pairs(T.stealth) do
    local u = T.units[guid]
    if m.x and not (u and u.visible) and n < 20 then
      local sx, sy = M.Relative(px, py, facing, m.x, m.y, rotate)
      local d = sqrt(sx * sx + sy * sy)
      local edge = d > range
      if edge then sx, sy = sx / d * range, sy / d * range end
      n = n + 1
      local gh = self:Ghost(n)
      local ox, oy = sx * scale, sy * scale
      Place(gh.ring, f, ox, oy)
      local r, g, b = U.ClassColor(m.class)
      gh.pip:SetVertexColor(r, g, b, 1)
      Place(gh.pip, f, ox, oy)
      local rad = math.min(T:StealthRadius(m, now) * scale, self.radius)
      if not edge and rad >= 5 then
        gh.area:SetWidth(rad * 2 * RING_RATIO)
        gh.area:SetHeight(rad * 2 * RING_RATIO)
        Place(gh.area, f, ox, oy)
      else
        gh.area:Hide()
      end
      gh.label:SetText((m.kind or "Stealth") .. " " .. math.floor(now - m.lastSeen) .. "s")
      gh.label:SetPoint("TOP", f, "CENTER", ox, oy - 8)
      gh.label:Show()
    end
  end
  for i = n + 1, table.getn(self.ghosts) do
    local gh = self.ghosts[i]
    gh.area:Hide()
    gh.ring:Hide()
    gh.pip:Hide()
    gh.label:Hide()
  end
end

function H:DrawFriends(f, px, py, facing, rotate, scale)
  local np = 0
  local ffc = B.Flags:Friend()
  local ffcName = ffc and not ffc.dropped and ffc.name
  local ffcDrawn = false
  local range = B.db.hud.range
  if B.db.hud.friends then
    for i = 1, GetNumRaidMembers() do
      local unit = "raid" .. i
      if np < MAX_PALS and not UnitIsUnit(unit, "player") and not UnitIsDeadOrGhost(unit) then
        local x, y = M:UnitWorld(unit)
        if x then
          local sx, sy = M.Relative(px, py, facing, x, y, rotate)
          if sx * sx + sy * sy <= range * range then
            np = np + 1
            local p = self:Pal(np)
            local _, class = UnitClass(unit)
            local r, g, b = U.ClassColor(class)
            p:SetVertexColor(r, g, b, 0.85)
            Place(p, f, sx * scale, sy * scale)
            if ffcName and UnitName(unit) == ffcName then
              self.ffcMark:SetTexture(U.FLAG[B.enemy or "Horde"])
              Place(self.ffcMark, f, sx * scale + 5, sy * scale + 8)
              ffcDrawn = true
            end
          end
        end
      end
    end
  end
  for i = np + 1, table.getn(self.pals) do self.pals[i]:Hide() end
  if not ffcDrawn then self.ffcMark:Hide() end
end

function H:Update()
  local f = self.frame
  local db = B.db.hud
  local now = GetTime()
  local px, py = M:PlayerWorld()
  local facing = M:Facing()
  if B.test and not px then px, py = 0, 0 end
  if not px then
    self.info:SetText("|cffaaaaaano position (SuperWoW or a battleground map needed)|r")
    return
  end
  local rotate = db.rotate and facing ~= nil
  facing = facing or 0
  local scale = self.radius / db.range

  if rotate then
    self.me:SetTexCoord(0, 1, 0, 1)
    self.north:SetPoint("CENTER", f, "CENTER", math.sin(facing) * (self.radius + 2), math.cos(facing) * (self.radius + 2))
  else
    U.Rotate(self.me, facing)
    self.north:SetPoint("CENTER", f, "CENTER", 0, self.radius + 2)
  end

  local seen, inSight = self:DrawEnemies(f, now, px, py, facing, rotate, scale)
  self:DrawStealth(f, now, px, py, facing, rotate, scale)
  self:DrawFriends(f, px, py, facing, rotate, scale)
  if seen > 0 then
    self.info:SetText(seen .. (seen == 1 and " enemy" or " enemies") .. " within " .. db.range .. " yd  |cff88ff88" .. inSight .. " in sight|r")
  else
    self.info:SetText("|cff888888no enemies within " .. db.range .. " yd|r")
  end
end

-- ---------------------------------------------------------------- enemy list

-- Cooldowns worth seeing first: trinkets, immunities, escapes, fears, stuns,
-- interrupts. The rest follow by time left.
local PRIORITY = {
  ["Insignia of the Alliance"] = true, ["Insignia of the Horde"] = true, ["Will of the Forsaken"] = true,
  ["Divine Shield"] = true, ["Ice Block"] = true, ["Blessing of Protection"] = true, ["Vanish"] = true,
  ["Evasion"] = true, ["Blink"] = true, ["Psychic Scream"] = true, ["Intimidating Shout"] = true,
  ["Death Coil"] = true, ["Howl of Terror"] = true, ["Blind"] = true, ["Kidney Shot"] = true,
  ["Hammer of Justice"] = true, ["Frost Nova"] = true, ["Counterspell"] = true, ["Kick"] = true,
  ["Pummel"] = true, ["Shield Bash"] = true, ["Earth Shock"] = true, ["Spell Lock"] = true,
  ["Berserker Rage"] = true, ["Stoneform"] = true, ["Escape Artist"] = true, ["Perception"] = true,
}

-- Up to 3 { tex, rem } into H.cds; EnemyCooldowns' list is a shared scratch
-- table, so it is copied straight away.
local function Cooldowns(guid)
  local out = H.cds
  out.n = 0
  if not guid or not ECD or not ECD.GetActiveCooldowns then return out end
  local ok, list = pcall(ECD.GetActiveCooldowns, ECD, guid)
  if not ok or type(list) ~= "table" then return out end
  local n = 0
  for pass = 1, 2 do
    for i = 1, table.getn(list) do
      local e = list[i]
      local pri = PRIORITY[e.spellName or ""]
      if n < 3 and ((pass == 1 and pri) or (pass == 2 and not pri)) then
        n = n + 1
        if not out[n] then out[n] = {} end
        out[n].tex, out[n].rem = e.texture, e.remaining
      end
    end
  end
  out.n = n
  return out
end

function H:BuildList()
  local f = U.Panel("OctoBGList", "list", "Enemy list", 214, 18 + LIST_MAX * ROW_H, "CENTER", 260, -40)
  U.Backdrop(f, 0.7)
  f:Hide()
  self.list = f
  f.title = U.Text(f, 10)
  f.title:SetPoint("TOPLEFT", f, "TOPLEFT", 4, -3)
  for i = 1, LIST_MAX do
    local r = CreateFrame("Button", nil, f)
    r:SetWidth(210)
    r:SetHeight(ROW_H - 1)
    r:SetPoint("TOPLEFT", f, "TOPLEFT", 2, -16 - (i - 1) * ROW_H)
    r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    r.bar = U.Tex(r, U.WHITE, "BACKGROUND")
    r.bar:SetPoint("TOPLEFT", r, "TOPLEFT", 0, 0)
    r.bar:SetHeight(ROW_H - 1)
    r.name = U.Text(r, 10, U.NARROW)
    r.name:SetPoint("LEFT", r, "LEFT", 3, 0)
    r.name:SetWidth(96)
    r.name:SetJustifyH("LEFT")
    r.dist = U.Text(r, 10)
    r.dist:SetPoint("RIGHT", r, "RIGHT", -3, 0)
    r.los = NewTex(r, U.MEDIA .. "disc", "ARTWORK", 7)
    r.los:SetPoint("RIGHT", r, "RIGHT", -30, 0)
    r.cd = {}
    for j = 1, 3 do
      local ic = NewTex(r, nil, "ARTWORK", ROW_H - 2)
      ic:SetPoint("LEFT", r, "LEFT", 100 + (j - 1) * ROW_H, 0)
      ic:SetTexCoord(0.07, 0.93, 0.07, 0.93)
      local t = U.Text(r, 8, U.NARROW)
      t:SetPoint("CENTER", ic, "CENTER", 0, 0)
      r.cd[j] = { icon = ic, text = t }
    end
    r:SetScript("OnClick", function()
      if this.guid then U.TargetGuidOrName(this.guid, this.unitName) end
    end)
    r:Hide()
    self.rows[i] = r
  end
end

function H:UpdateList()
  local f = self.list
  local rows = math.min(B.db.list.rows, LIST_MAX)
  local sorted = B.Tracker.sorted
  local tg = U.GuidOf("target")
  local n, alive = 0, 0
  for i = 1, table.getn(sorted) do
    local u = sorted[i]
    if not u.dead then alive = alive + 1 end
    if n < rows and not u.dead then
      n = n + 1
      local r = self.rows[n]
      r.guid, r.unitName = (not u.fake) and u.guid or nil, u.name
      local cr, cg, cb = U.ClassColor(u.class)
      r.name:SetText(u.name or "?")
      r.name:SetTextColor(cr, cg, cb)
      local pct = (u.hp and u.hpmax and u.hpmax > 0) and (u.hp / u.hpmax) or 1
      r.bar:SetWidth(math.max(1, 210 * pct))
      if tg and u.guid == tg then
        r.bar:SetVertexColor(1, 1, 1, 0.3)
      else
        r.bar:SetVertexColor(cr, cg, cb, 0.22)
      end
      r.dist:SetText(u.dist and tostring(math.floor(u.dist)) or "")
      if u.los == nil then
        r.los:Hide()
      else
        if u.los then r.los:SetVertexColor(0.3, 1, 0.3) else r.los:SetVertexColor(1, 0.25, 0.2) end
        r.los:Show()
      end
      local cds = Cooldowns(u.guid)
      for j = 1, 3 do
        local c = r.cd[j]
        if j <= cds.n and cds[j].tex then
          c.icon:SetTexture(cds[j].tex)
          c.icon:Show()
          c.text:SetText(U.Time(cds[j].rem))
        else
          c.icon:Hide()
          c.text:SetText("")
        end
      end
      r:Show()
    end
  end
  for i = n + 1, LIST_MAX do self.rows[i]:Hide() end
  f.title:SetText("Enemies |cffaaaaaa" .. alive .. " seen|r")
  f:SetHeight(18 + math.max(1, n) * ROW_H)
end

-- ---------------------------------------------------------------- driver

function H:Visible()
  local db = B.db.hud
  if not db.enabled then return false end
  return B.test or B.zone ~= nil or db.world
end

B:Every(0.05, function()
  local f = H.frame
  if not f then return end
  if H:Visible() then
    if not f:IsShown() then f:Show() end
    H:Update()
  elseif f:IsShown() then
    f:Hide()
  end
end, true)

B:Every(0.25, function()
  local f = H.list
  if not f then return end
  if B.db.list.enabled and (B.test or B.zone ~= nil or (B.db.hud.world and B.db.hud.enabled)) then
    if not f:IsShown() then f:Show() end
    H:UpdateList()
  elseif f:IsShown() then
    f:Hide()
  end
end, true)

-- Tickers stop while inactive, so hide on the way out.
B:On("OBG_ACTIVE", function(ev, on)
  if on then return end
  if H.frame then H.frame:Hide() end
  if H.list then H.list:Hide() end
end)

B:On("OBG_INIT", function()
  H:Build()
  H:BuildList()
end)

function OctoBG_ToggleHUD()
  B.db.hud.enabled = not B.db.hud.enabled
  B:RefreshActive()
  B:Print("HUD " .. (B.db.hud.enabled and "on" or "off"))
end
