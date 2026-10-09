-- OctoBG :: enemy tracker
-- Collects enemy player GUIDs the way Spy's nampower module does (nampower
-- *_GUID and *_OTHER events, nameplate GUIDs), plus what the group is
-- targeting (SuperWoW GUIDs of raidNtarget) and the GUIDs Spy and
-- EnemyCooldowns already know. Every 0.2 s each known enemy gets a fresh
-- position (SuperWoW), distance and line of sight (UnitXP_SP3) and health.
--
-- Eviction: a unit missing from the object list for FORGET seconds is dropped,
-- at most MAX_UNITS are kept (oldest sighting goes first), and everything is
-- cleared on a zone change. Rejected GUIDs (NPCs, friends) are remembered for
-- 20 s, at most 500 before the list is wiped.

local B = OctoBG
local U = B.U
local T = { units = {}, count = 0, sorted = {} }
B.Tracker = T

local MAX_UNITS = 80
local FORGET = 25

local rejected, nrej = {}, 0

local function Reject(guid)
  if nrej >= 500 then
    rejected = {}
    nrej = 0
  end
  if not rejected[guid] then nrej = nrej + 1 end
  rejected[guid] = GetTime()
end

function T:Clear()
  self.units = {}
  self.count = 0
  self.sorted = {}
  self.stealth = {}
  self.nstealth = 0
  rejected = {}
  nrej = 0
end

function T:DropOldest()
  local oldG, oldT
  for g, u in pairs(self.units) do
    if not u.fake and (not oldT or u.seen < oldT) then oldG, oldT = g, u.seen end
  end
  if oldG then
    self.units[oldG] = nil
    self.count = self.count - 1
  end
end

-- Add a GUID if it is an enemy player; returns the record or nil.
function T:Consider(guid)
  if type(guid) ~= "string" or not B.env.safe then return nil end
  local u = self.units[guid]
  if u then return u end
  local r = rejected[guid]
  if r and GetTime() - r < 20 then return nil end
  if not U.GuidExists(guid) then return nil end
  if not UnitIsPlayer(guid) then Reject(guid) return nil end
  -- Hostile reaction first; arenas can match same-faction players, so there
  -- "can attack" counts too; the faction comparison is the last resort.
  local enemy = UnitIsEnemy("player", guid)
  if not enemy and B.zone == "ARENA" then enemy = UnitCanAttack("player", guid) end
  if not enemy then
    local tf = UnitFactionGroup(guid)
    enemy = (tf ~= nil and B.faction ~= nil and tf ~= B.faction)
  end
  if not enemy then Reject(guid) return nil end
  if self.count >= MAX_UNITS then self:DropOldest() end
  local _, class = UnitClass(guid)
  local now = GetTime()
  u = { guid = guid, name = UnitName(guid), class = class, seen = now, first = now }
  self.units[guid] = u
  self.count = self.count + 1
  B:Fire("OBG_ENEMY", guid)
  return u
end

function T:FindByName(name)
  if not name then return nil end
  for _, u in pairs(self.units) do
    if u.name == name then return u end
  end
  return nil
end

-- Living enemies with a known position within r yards of a world point,
-- position at most maxAge seconds old.
function T:CountNear(x, y, r, maxAge)
  local now, n = GetTime(), 0
  maxAge = maxAge or 3
  for _, u in pairs(self.units) do
    if u.x and not u.dead and now - (u.posAt or 0) <= maxAge then
      local dx, dy = u.x - x, u.y - y
      if dx * dx + dy * dy <= r * r then n = n + 1 end
    end
  end
  return n
end

-- Without positions: living, visible enemies within r yards of the player.
function T:CountAroundPlayer(r)
  local n = 0
  for _, u in pairs(self.units) do
    if u.visible and not u.dead and u.dist and u.dist <= r then n = n + 1 end
  end
  return n
end

-- ---------------------------------------------------------------- sources

local function OnGuidEvent(ev, guid, isPlayer)
  if isPlayer == 1 then T:Consider(guid) end
end

local GUID_EVENTS = {
  "UNIT_HEALTH_GUID", "UNIT_AURA_GUID", "UNIT_FLAGS_GUID", "UNIT_COMBAT_GUID",
  "UNIT_NAME_UPDATE_GUID", "UNIT_MANA_GUID", "UNIT_RAGE_GUID", "UNIT_ENERGY_GUID",
}
for i = 1, table.getn(GUID_EVENTS) do
  B:On(GUID_EVENTS[i], OnGuidEvent, true)
end

-- nampower: SPELL_START/GO_OTHER arg3 = caster, AUTO_ATTACK_OTHER arg1 =
-- attacker, SPELL_DAMAGE_EVENT_OTHER / SPELL_HEAL_BY_OTHER arg2 = caster,
-- BUFF_ADDED_OTHER arg1 = unit (layout documented in Spy's SpyNampower.lua).
B:On("SPELL_START_OTHER", function(ev, item, spell, caster) T:Consider(caster) end, true)
B:On("SPELL_GO_OTHER", function(ev, item, spell, caster)
  T:Consider(caster)
  if T.STEALTH[spell] then T:Stealthed(caster, spell) end
end, true)
B:On("AUTO_ATTACK_OTHER", function(ev, attacker) T:Consider(attacker) end, true)
B:On("SPELL_DAMAGE_EVENT_OTHER", function(ev, target, caster) T:Consider(caster) end, true)
B:On("SPELL_HEAL_BY_OTHER", function(ev, target, caster) T:Consider(caster) end, true)
-- BUFF_ADDED/REMOVED_OTHER: arg1 = unit, arg3 = spell id (Spy reads them so)
B:On("BUFF_ADDED_OTHER", function(ev, guid, a2, spell)
  T:Consider(guid)
  if T.STEALTH[spell] then T:Stealthed(guid, spell) end
end, true)
B:On("BUFF_REMOVED_OTHER", function(ev, guid, a2, spell)
  if T.STEALTH[spell] then T:Unstealthed(guid, spell) end
end, true)

-- UNIT_DIED (nampower) is a real death, never Feign Death.
B:On("UNIT_DIED", function(ev, guid)
  local u = guid and T.units[guid]
  if u then
    u.dead = true
    u.diedAt = GetTime()
  end
  if guid and T.stealth[guid] then T:DropStealth(guid) end
end, true)

-- ---------------------------------------------------------------- stealth

-- An enemy who stealths out of detection range stops existing for this
-- client (the server sends nothing more), so all OctoBG can show is where
-- they went into stealth and how far they could have moved since: a ring
-- growing at STEALTH_SPEED (rough stealth movement speed; Sprint beats it).
-- Spell ids as Spy's nampower module lists them.
T.STEALTH = {
  [1784] = "Stealth", [1785] = "Stealth", [1786] = "Stealth", [1787] = "Stealth",
  [5215] = "Prowl", [6783] = "Prowl", [9913] = "Prowl",
  [20580] = "Shadowmeld",
  [1856] = "Vanish", [1857] = "Vanish", [11327] = "Vanish", [11329] = "Vanish",
}
T.STEALTH_SPEED = 5
local STEALTH_KEEP, STEALTH_MAX = 20, 40

-- stealth[guid] = { name, class, kind, x, y, at, lastSeen, alertAt }
-- Eviction: 20 s after last seen, on death, on stealth ending, max 40, zone clears.
T.stealth = {}
T.nstealth = 0

function T:DropStealth(guid)
  if self.stealth[guid] then
    self.stealth[guid] = nil
    self.nstealth = self.nstealth - 1
  end
end

-- Create or refresh a stealth mark. key is the GUID, or "name:<name>" when
-- only the combat log named the enemy.
function T:SetMark(key, name, class, kind, x, y)
  local now = GetTime()
  local m = self.stealth[key]
  if not m then
    if self.nstealth >= STEALTH_MAX then
      local oldG, oldT
      for g, s in pairs(self.stealth) do
        if not oldT or s.lastSeen < oldT then oldG, oldT = g, s.lastSeen end
      end
      if oldG then self:DropStealth(oldG) end
    end
    m = {}
    self.stealth[key] = m
    self.nstealth = self.nstealth + 1
  end
  m.name, m.class, m.kind, m.x, m.y, m.at, m.lastSeen = name, class or m.class, kind, x, y, now, now
  return m
end

-- On-screen alert for a stealth close by. d = yards, or nil with near = true
-- when only the combat log saw it (that log reaches a short way only).
function T:StealthAlert(m, d, near)
  local now = GetTime()
  if not B.db.stealth.alert or now - (m.alertAt or 0) <= 10 then return end
  if not (near or (d and d <= B.db.stealth.range)) then return end
  m.alertAt = now
  local r, g, b = U.ClassColor(m.class)
  U.Alert((m.name or "?") .. " - " .. string.lower(m.kind) .. " " .. (d and (math.floor(d) .. " yd") or "nearby"), r, g, b, true)
end

function T:Stealthed(guid, spell)
  self:StealthMark(guid, self.STEALTH[spell])
end

function T:StealthMark(guid, kind)
  if not B.db.stealth.enabled or not kind then return end
  local u = self:Consider(guid)
  if not u then return end
  local x, y, z = U.Position(guid)
  if not x then x, y = u.x, u.y end
  if u.name then self:DropStealth("name:" .. u.name) end
  local m = self:SetMark(guid, u.name, u.class, kind, x, y)
  m.z = z
  self:StealthAlert(m, U.Distance(guid))
  B:Fire("OBG_STEALTH", guid, m)   -- Sync shares it and may call it out in /bg
end

-- Combat log fallback (works without nampower, and for enemies the tracker
-- has no GUID for yet): "Name gains Stealth." / "Name performs Vanish.".
-- Without a GUID the mark goes where the player stands: the hostile buff log
-- only reaches nearby players.
local LOG_KIND = { stealth = "Stealth", prowl = "Prowl", shadowmeld = "Shadowmeld", vanish = "Vanish" }
local KIND_CLASS = { Stealth = "ROGUE", Vanish = "ROGUE", Prowl = "DRUID" }
T.KIND_CLASS = KIND_CLASS

function T:StealthByName(name, kind)
  if not B.db.stealth.enabled then return end
  local u = self:FindByName(name)
  if u and not u.fake then
    self:StealthMark(u.guid, kind)
    return
  end
  local now = GetTime()
  for _, s in pairs(self.stealth) do
    if s.name == name and now - s.lastSeen < 2 then return end   -- nampower already marked it
  end
  local px, py = B.Map:PlayerWorld()
  if not px then return end
  local key = "name:" .. name
  local m = self:SetMark(key, name, KIND_CLASS[kind], kind, px, py)
  self:StealthAlert(m, nil, true)
  B:Fire("OBG_STEALTH", key, m)
end

local function OnStealthLog(ev, msg)
  if not msg then return end
  local _, _, name, spell = string.find(msg, "^(%S+) gains (%a+)%.$")
  if not name then _, _, name, spell = string.find(msg, "^(%S+) performs (%a+)%.$") end
  if not name then _, _, name, spell = string.find(msg, "^(%S+) casts (%a+)%.$") end
  local kind = spell and LOG_KIND[string.lower(spell)]
  if kind then T:StealthByName(name, kind) end
end
B:On("CHAT_MSG_SPELL_PERIODIC_HOSTILEPLAYER_BUFFS", OnStealthLog, true)
B:On("CHAT_MSG_SPELL_HOSTILEPLAYER_BUFF", OnStealthLog, true)

-- ---------------------------------------------------------------- shared by the raid

-- An enemy another OctoBG user sees (Sync.lua). The own client's view wins:
-- nothing is changed for a unit in this client's object list.
function T:Remote(guid, name, class, x, y, hp, from)
  local u = self.units[guid]
  if u and (u.fake or U.GuidExists(guid)) then return end
  local now = GetTime()
  if not u then
    if self.count >= MAX_UNITS then self:DropOldest() end
    u = { guid = guid, first = now }
    self.units[guid] = u
    self.count = self.count + 1
  end
  u.name, u.class = name or u.name, class or u.class
  u.x, u.y, u.z, u.posAt, u.seen, u.remoteAt, u.from = x, y, nil, now, now, now, from
  u.hp, u.hpmax = hp, 100
  if hp == 0 then u.dead = true else u.dead = nil end
  local m = self.stealth[guid]
  if m then m.x, m.y, m.lastSeen = x, y, now end
end

-- A stealth another OctoBG user saw.
function T:RemoteStealth(guid, name, class, kind, x, y)
  if not B.db.stealth.enabled then return end
  local u = self.units[guid]
  if u and u.visible then return end   -- this client sees it itself
  local m = self:SetMark(guid, name, class, kind, x, y)
  m.remote = true
  local px, py = B.Map:PlayerWorld()
  if px and x then self:StealthAlert(m, B.Map.Dist(px, py, x, y)) end
end

-- Vanish's own aura ends while its stealth goes on, so only the stealth
-- auras clear the mark.
function T:Unstealthed(guid, spell)
  if self.STEALTH[spell] ~= "Vanish" then self:DropStealth(guid) end
end

-- Yards the stealthed enemy may have moved since last seen.
function T:StealthRadius(m, now)
  return (now - m.lastSeen) * self.STEALTH_SPEED
end

-- ---------------------------------------------------------------- reach

-- How far away enemies are picked up here: the farthest UnitXP distance of
-- an enemy in the object list, and the distances at which living enemies
-- drop out of it (that is the server's visibility edge). Kept per zone in
-- db.reach[zone name] = { max, drop, n, day } (at most 60 zones).
T.reach, T.drops = 0, {}

function T:ReachSummary()
  local n = table.getn(self.drops)
  local drop
  if n > 0 then
    local c = {}
    for i = 1, n do c[i] = self.drops[i] end
    table.sort(c)
    drop = c[math.floor((n + 1) / 2)]
  end
  return self.reach, drop, n
end

function T:SaveReach()
  local zone = self.reachZone
  if not zone or self.reach <= 0 then return end
  local max, drop, n = self:ReachSummary()
  local db = B.db.reach
  local count = 0
  for _ in pairs(db) do count = count + 1 end
  if count >= 60 and not db[zone] then
    B.db.reach = {}
    db = B.db.reach
  end
  local old = db[zone]
  db[zone] = { max = math.max(max, old and old.max or 0), drop = drop or (old and old.drop), n = n, day = date("%d %b") }
  if self.reachIsBG or B.debug then
    B:Print(zone .. ": enemies picked up as far as " .. math.floor(max) .. " yd"
      .. (drop and (", they drop out at about " .. math.floor(drop) .. " yd (" .. n .. " seen leaving)") or ""))
  end
end

B:On("PLAYER_TARGET_CHANGED", function()
  T:Consider(U.GuidOf("target"))
end, true)

B:On("UPDATE_MOUSEOVER_UNIT", function()
  T:Consider(U.GuidOf("mouseover"))
end, true)

-- Open world: each zone gets its own reach figure (battlegrounds go through OBG_ZONE).
B:On("ZONE_CHANGED_NEW_AREA", function()
  local zone = GetRealZoneText()
  if B.zone or zone == T.reachZone then return end
  T:SaveReach()
  T.reachZone, T.reachIsBG, T.reach, T.drops = zone, false, 0, {}
end, true)

B:On("OBG_ZONE", function()
  T:SaveReach()
  T:Clear()
  T.reachZone, T.reachIsBG, T.reach, T.drops = B.zoneName, B:IsBG(), 0, {}
  if B.test then T:SetSamples(true) end
end)

-- Nameplates (nampower: frame:GetName(1) is the plate's GUID), the group's
-- targets, and the enemy tables of Spy and EnemyCooldowns.
function T:Harvest()
  if B.env.nampower then
    local kids = { WorldFrame:GetChildren() }
    for i = 1, table.getn(kids) do
      local ok, g = pcall(kids[i].GetName, kids[i], 1)
      if ok and type(g) == "string" and string.sub(g, 1, 2) == "0x" then self:Consider(g) end
    end
  end
  local nr = GetNumRaidMembers()
  if nr > 0 then
    for i = 1, nr do self:Consider(U.GuidOf("raid" .. i .. "target")) end
  else
    for i = 1, GetNumPartyMembers() do self:Consider(U.GuidOf("party" .. i .. "target")) end
  end
  self:Consider(U.GuidOf("target"))
  self:Consider(U.GuidOf("targettarget"))
  self:Consider(U.GuidOf("mouseover"))
  if SpySW and type(SpySW.enemyGuids) == "table" then
    for g in pairs(SpySW.enemyGuids) do self:Consider(g) end
  end
  if ECD and type(ECD.cache) == "table" then
    for g in pairs(ECD.cache) do self:Consider(g) end
  end
end

-- ---------------------------------------------------------------- refresh

local function ByDist(a, b)
  if a.dist and b.dist then return a.dist < b.dist end
  if a.dist then return true end
  return false
end

local harvestAt = 0
function T:Scan()
  if not B.env.safe then return end
  local now = GetTime()
  if now - harvestAt > 1 then
    harvestAt = now
    self:Harvest()
  end
  local sorted, n = self.sorted, 0
  local px, py
  for guid, u in pairs(self.units) do
    if u.fake then
      n = n + 1
      sorted[n] = u
    elseif U.GuidExists(guid) then
      u.seen = now
      u.visible = true
      local x, y, z = U.Position(guid)
      if x then u.x, u.y, u.z, u.posAt = x, y, z, now end
      u.dist = U.Distance(guid)
      if u.dist then
        u.lastDist = u.dist
        if u.dist > self.reach then self.reach = u.dist end
      end
      local m = self.stealth[guid]
      if m then
        m.x, m.y, m.lastSeen = u.x or m.x, u.y or m.y, now
      end
      if not u.losAt or now - u.losAt > 0.5 then
        u.los = U.InSight(guid)
        u.losAt = now
      end
      u.hp, u.hpmax = UnitHealth(guid), UnitHealthMax(guid)
      if u.hp and u.hp > 0 then
        u.dead = nil
      elseif UnitIsDeadOrGhost(guid) then
        u.dead = true
      end
      if not u.name then u.name = UnitName(guid) end
      n = n + 1
      sorted[n] = u
    else
      -- a living enemy leaving the object list far away marks the visibility edge
      if u.visible and not u.dead and u.lastDist and u.lastDist > 40 and not self.stealth[guid] then
        table.insert(self.drops, u.lastDist)
        if table.getn(self.drops) > 30 then table.remove(self.drops, 1) end
      end
      u.visible = nil
      u.dist = nil
      if u.remoteAt and now - u.remoteAt < 3 and u.x then
        -- shared by the raid: in the list, distance from the positions
        if not px then px, py = B.Map:PlayerWorld() end
        if px then u.dist = B.Map.Dist(px, py, u.x, u.y) end
        u.los = nil
        n = n + 1
        sorted[n] = u
      end
      if now - u.seen > FORGET then
        self.units[guid] = nil
        self.count = self.count - 1
      end
    end
  end
  for i = table.getn(sorted), n + 1, -1 do sorted[i] = nil end
  table.sort(sorted, ByDist)
  for guid, m in pairs(self.stealth) do
    if now - m.lastSeen > STEALTH_KEEP then self:DropStealth(guid) end
  end
end

B:Every(0.2, function() T:Scan() end, true)

-- ---------------------------------------------------------------- layout-mode samples

-- Sample enemies placed around the player so the HUD, list and map can be
-- arranged outside a battleground. They follow the player (relative offsets).
local SAMPLES = {
  { "Testrogue", "ROGUE", 12, 8, true },
  { "Testpriest", "PRIEST", -20, 25, true },
  { "Testwarrior", "WARRIOR", 30, -6, false },
  { "Testmage", "MAGE", -38, -30, true },
  { "Testhunter", "HUNTER", 52, 40, true },
}

function T:SetSamples(on)
  for g, u in pairs(self.units) do
    if u.fake then
      self.units[g] = nil
      self.count = self.count - 1
    end
  end
  self:DropStealth("sample")
  if not on then return end
  self.stealth.sample = { fake = true, name = "Testdruid", class = "DRUID", kind = "Prowl", lastSeen = GetTime() }
  self.nstealth = self.nstealth + 1
  for i = 1, table.getn(SAMPLES) do
    local s = SAMPLES[i]
    local g = "sample" .. i
    self.units[g] = { guid = g, fake = true, name = s[1], class = s[2], ox = s[3], oy = s[4],
                      los = s[5], hp = 100 - i * 13, hpmax = 100, seen = GetTime(), visible = true }
    self.count = self.count + 1
  end
end

-- Keep the samples around the player (world position if known, else 0,0).
B:Every(0.1, function()
  if not B.test then return end
  local px, py = B.Map:PlayerWorld()
  px, py = px or 0, py or 0
  local now = GetTime()
  for _, u in pairs(T.units) do
    if u.fake then
      local a = now * 0.15 + u.ox * 0.05
      local c, s = math.cos(a), math.sin(a)
      u.x = px + u.ox * c - u.oy * s
      u.y = py + u.ox * s + u.oy * c
      u.posAt = now
      u.seen = now
      u.dist = math.sqrt(u.ox * u.ox + u.oy * u.oy)
    end
  end
  local m = T.stealth.sample
  if m then
    m.x, m.y = px - 15, py + 34
    m.lastSeen = now - math.mod(now, 15)   -- the ring grows for 15 s, then starts again
  end
end, true)

B:On("OBG_LAYOUT", function(ev, on)
  T:SetSamples(on)
end)
