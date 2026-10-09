-- OctoBG :: timers
-- One panel of bars:
--   * spirit resurrection waves per graveyard (spirit guides cast Spirit Heal
--     every 30 s; nampower reports the channel start 22011 and the heal 22012,
--     both seen in this server's combat logs),
--   * Arathi Basin bases (60 s after an assault) and Alterac Valley
--     towers/graveyards (5 min), from the system messages and herald yells,
--   * the game start countdown,
--   * Arathi Basin: who reaches 2000 first, from the measured resource rate.
-- While dead in a battleground a big "Resurrection in N" sits mid-screen.

local B = OctoBG
local U = B.U
local M = B.Map
local TM = { rows = {}, pool = {} }
B.Timers = TM

local WAVE = 30
local SPIRIT_CHANNEL, SPIRIT_HEAL = 22011, 22012
local GUIDE_FACTION = { [13116] = "Alliance", [13117] = "Horde" }
local FAC = { alliance = "Alliance", horde = "Horde" }
local EVFAC = { CHAT_MSG_BG_SYSTEM_ALLIANCE = "Alliance", CHAT_MSG_BG_SYSTEM_HORDE = "Horde" }
local ICON_RES = "Interface\\Icons\\Spell_Holy_Resurrection"
local ICON_WATCH = "Interface\\Icons\\INV_Misc_PocketWatch_01"
local POI = "Interface\\Minimap\\POIIcons"
local ROW_H, WIDTH, MAX_ROWS = 18, 236, 20
local BAR_TEX = "Interface\\TargetingFrame\\UI-StatusBar"

-- ---------------------------------------------------------------- spirit guides

-- guides[guid] = { faction, anchor = time of a wave, x, y, label, seen }
-- Eviction: a guide missing from the object list for 120 s is dropped
-- (captured AB/AV graveyards replace their guide); at most 24; zone clears.
local S = { guides = {}, n = 0 }
TM.spirit = S

local function Guide(guid)
  if type(guid) ~= "string" then return nil end
  local g = S.guides[guid]
  if not g then
    if S.n >= 24 then return nil end
    g = { guid = guid, faction = GUIDE_FACTION[U.CreatureEntry(guid) or 0] }
    S.guides[guid] = g
    S.n = S.n + 1
  end
  g.seen = GetTime()
  return g
end

-- nampower SPELL_START_OTHER: arg6 castTime, arg7 duration (ms). The channel
-- ends with the heal, so the next wave is start + duration.
B:On("SPELL_START_OTHER", function(ev, item, spell, caster, target, flags, castTime, duration)
  if spell ~= SPIRIT_CHANNEL then return end
  local g = Guide(caster)
  if not g then return end
  local ms = (duration and duration > 0 and duration) or (castTime and castTime > 0 and castTime) or WAVE * 1000
  g.anchor, g.own = GetTime() + ms / 1000, true
end, true)

B:On("SPELL_GO_OTHER", function(ev, item, spell, caster)
  if spell ~= SPIRIT_HEAL then return end
  local g = Guide(caster)
  if g then g.anchor, g.own = GetTime(), true end
end, true)

function S:Remaining(g, now)
  if not g.anchor then return nil end
  local d = now - g.anchor
  if d < 0 then return -d end
  return WAVE - math.mod(d, WAVE)
end

function S:Label(g, now)
  if g.label and now - (g.labelAt or 0) < 10 then return g.label end
  local x, y = U.Position(g.guid)
  if x then g.x, g.y = x, y end
  local label
  if B.zone == "WSG" and g.faction then
    label = g.faction .. " graveyard"
  elseif g.x then
    local m = M:NearestLandmark(g.x, g.y)
    if m then label = m.name end
  end
  if not label then label = g.faction and (g.faction .. " spirit guide") or "Spirit guide" end
  g.label, g.labelAt = label, now
  return label
end

-- A wave another OctoBG user measured (Sync.lua): rem = seconds to its next
-- wave. Waves this client measured itself are kept.
function S:Remote(guid, faction, rem, x, y)
  local g = Guide(guid)
  if not g then return end
  if not g.faction then g.faction = faction end
  if not g.own then g.anchor = GetTime() + rem end
  if x and not g.x then g.x, g.y, g.labelAt = x, y, 0 end
end

-- The guide the player would rise at: the nearest one of the player's side
-- (any side when the guide's faction is unknown).
function S:Nearest()
  local best, bestD
  local px, py = M:PlayerWorld()
  for _, g in pairs(self.guides) do
    if g.anchor and (not g.faction or not B.faction or g.faction == B.faction) then
      local d = U.Distance(g.guid)
      if not d and g.x and px then d = M.Dist(px, py, g.x, g.y) end
      if d and (not bestD or d < bestD) then best, bestD = g, d end
    end
  end
  return best, bestD
end

function S:Prune(now)
  for guid, g in pairs(self.guides) do
    if U.GuidExists(guid) then
      g.seen = now
    elseif now - g.seen > 120 then
      self.guides[guid] = nil
      self.n = self.n - 1
    end
  end
end

-- The spirit healer dialog's own timer is exact; it also syncs the nearest guide.
B:On("AREA_SPIRIT_HEALER_IN_RANGE", function()
  local t = GetAreaSpiritHealerTime and GetAreaSpiritHealerTime()
  if t and t > 0 then
    S.areaWave = GetTime() + t
    local g = S:Nearest()
    if g then g.anchor, g.own = S.areaWave, true end
  end
end, true)

B:On("AREA_SPIRIT_HEALER_OUT_OF_RANGE", function() S.areaWave = nil end, true)

-- Seconds until the player's next resurrection wave, or nil.
function S:MyWave(now)
  if self.areaWave and self.areaWave > now then return self.areaWave - now end
  local g = self:Nearest()
  if g then return self:Remaining(g, now) end
  return nil
end

-- ---------------------------------------------------------------- objectives

-- nodes[name] = { name, owner, by, ends, dur }
local O = { nodes = {}, order = {} }
TM.obj = O

local AB_NODES = { "Stables", "Gold Mine", "Blacksmith", "Lumber Mill", "Farm" }
local AB_KEYS = { { "stable", "Stables" }, { "farm", "Farm" }, { "smith", "Blacksmith" },
                  { "lumber", "Lumber Mill" }, { "mine", "Gold Mine" } }

local function ABNode(text)
  if not text then return nil end
  for i = 1, table.getn(AB_KEYS) do
    if string.find(text, AB_KEYS[i][1], 1, true) then return AB_KEYS[i][2] end
  end
  return nil
end

function O:Node(name)
  local n = self.nodes[name]
  if not n then
    n = { name = name }
    self.nodes[name] = n
  end
  return n
end

function O:Contest(name, by, dur)
  local n = self:Node(name)
  n.by, n.dur, n.ends = by, dur, GetTime() + dur
end

function O:Own(name, owner)
  local n = self:Node(name)
  n.owner, n.by, n.ends = owner, nil, nil
end

-- "begins in 1 minute" / "begins in 30 seconds" / AV: "1 minute until the battle..."
local function StartCountdown(low)
  local _, _, n, unit = string.find(low, "begins in (%d+) (%a+)")
  if not n then _, _, n, unit = string.find(low, "(%d+) (%a+) until the battle") end
  if n then
    local s = tonumber(n)
    if string.find(unit, "^min") then s = s * 60 end
    O.start = GetTime() + s
    return true
  end
  if string.find(low, "has begun", 1, true) then
    O.start = nil
    return true
  end
  return false
end

-- Arathi Basin lines (BigWigs' AB module, enUS on this client):
--   "<name> has assaulted the <base>!"   "<name> claims the <base>! If left
--   unchallenged, the <faction> will control it in 1 minute!"
--   "<name> has defended the <base>!"    "The <faction> has taken the <base>!"
local function OnBGSystem(ev, msg)
  if not msg then return end
  local low = string.lower(msg)
  if StartCountdown(low) then return end
  if B.zone ~= "AB" then return end
  local fac = EVFAC[ev]
  local _, _, base = string.find(low, "has assaulted the ([^!]+)")
  if base and ABNode(base) and fac then
    O:Contest(ABNode(base), fac, 60)
    return
  end
  _, _, base = string.find(low, "claims the ([^!]+)")
  if base and ABNode(base) then
    local _, _, fw = string.find(low, "the (%a+) will control")
    local by = (fw and FAC[fw]) or fac
    if by then O:Contest(ABNode(base), by, 60) end
    return
  end
  _, _, base = string.find(low, "has defended the ([^!]+)")
  if base and ABNode(base) and fac then
    O:Own(ABNode(base), fac)
    return
  end
  local _, _, fw, tb = string.find(low, "the (%a+) has taken the ([^!]+)")
  if fw and FAC[fw] and ABNode(tb) then
    O:Own(ABNode(tb), FAC[fw])
  end
end

-- Alterac Valley herald yells (BigWigs' AV module): 5 minutes to capture a
-- graveyard or burn a tower.
local function OnYell(ev, msg)
  if not msg then return end
  local low = string.lower(msg)
  if StartCountdown(low) then return end
  if B.zone ~= "AV" then return end
  local _, _, p1, _, p2, fw = string.find(low, "^()(.-)() is under attack! if left unchecked, the (%a+) will")
  if fw and FAC[fw] then
    O:Contest(string.sub(msg, p1, p2 - 1), FAC[fw], 300)
    return
  end
  _, _, p1, _, p2, fw = string.find(low, "^()(.-)() was taken by the (%a+)")
  if fw and FAC[fw] then
    O:Own(string.sub(msg, p1, p2 - 1), FAC[fw])
    return
  end
  _, _, p1, _, p2, fw = string.find(low, "^()(.-)() was destroyed by the (%a+)")
  if fw and FAC[fw] then
    O.nodes[string.sub(msg, p1, p2 - 1)] = nil
  end
end

B:On("CHAT_MSG_BG_SYSTEM_ALLIANCE", OnBGSystem, true)
B:On("CHAT_MSG_BG_SYSTEM_HORDE", OnBGSystem, true)
B:On("CHAT_MSG_BG_SYSTEM_NEUTRAL", OnBGSystem, true)
B:On("CHAT_MSG_MONSTER_YELL", OnYell, true)

-- ---------------------------------------------------------------- AB prediction

-- The world state lines read like "Bases: 3  Resources: 1450/2000". The rate
-- is measured from the numbers since the base count last changed, so no tick
-- table has to be assumed.
local P = { Alliance = {}, Horde = {} }
TM.score = P

function O:ScoreTick()
  if B.zone ~= "AB" or not GetNumWorldStateUI then return end
  local now = GetTime()
  for i = 1, GetNumWorldStateUI() do
    local _, text, icon = GetWorldStateUIInfo(i)
    local _, _, cur, max
    if text then _, _, cur, max = string.find(text, "(%d+)/(%d+)") end
    if cur then
      local li = string.lower(icon or "")
      local fac
      if string.find(li, "alliance", 1, true) then fac = "Alliance"
      elseif string.find(li, "horde", 1, true) then fac = "Horde"
      else fac = (i == 1) and "Alliance" or "Horde" end
      local _, _, bases = string.find(text, "[Bb]ases:?%s*(%d+)")
      local p = P[fac]
      cur, max = tonumber(cur), tonumber(max)
      if bases ~= p.bases or (p.cur and cur < p.cur) then
        p.bases, p.t0, p.r0 = bases, nil, nil
      end
      if not p.t0 then p.t0, p.r0 = now, cur end
      if cur ~= p.cur then p.cur, p.t1 = cur, now end
      p.max = max
      if p.t1 and p.t1 - p.t0 >= 8 and cur > p.r0 then
        p.rate = (cur - p.r0) / (p.t1 - p.t0)
      else
        p.rate = nil
      end
    end
  end
end

-- ---------------------------------------------------------------- rows

-- A row: icon, owner strip (who holds the base / whose graveyard), a bar on a
-- dark track, white label, time on the right. post = the line a click sends
-- to /bg; header = a section title.
local function Entry(n)
  local e = TM.pool[n]
  if not e then
    e = {}
    TM.pool[n] = e
  end
  e.icon, e.coords, e.label, e.text, e.value, e.color = nil, nil, nil, nil, nil, nil
  e.owner, e.labelColor, e.post, e.header, e.hot = nil, nil, nil, nil, nil
  return e
end

-- POI icon of a landmark (cached on the landmark, which Map rebuilds every 2 s).
local function PoiCoords(name)
  local m = M:FindLandmark(name)
  if not m or not m.tex or not WorldMap_GetPOITextureCoords then return nil end
  if not m.coords then
    local l, r, t, b = WorldMap_GetPOITextureCoords(m.tex)
    m.coords = { l, r, t, b }
  end
  return m.coords
end

local GREY = { 0.7, 0.7, 0.7 }
local GOLD = { 1, 0.82, 0 }

function TM:CollectGuides(n, now)
  local list = {}
  for _, g in pairs(S.guides) do
    if g.anchor then table.insert(list, g) end
  end
  if table.getn(list) == 0 then return n end
  local own, near = B.faction, S:Nearest()
  table.sort(list, function(a, b)
    local ao, bo = (a.faction == own) and 0 or 1, (b.faction == own) and 0 or 1
    if ao ~= bo then return ao < bo end
    return S:Label(a, now) < S:Label(b, now)
  end)
  n = n + 1
  local e = Entry(n)
  e.header, e.label = true, "Res waves - click to post"
  for i = 1, math.min(table.getn(list), 8) do
    local g = list[i]
    local rem = S:Remaining(g, now)
    local label = S:Label(g, now)
    n = n + 1
    e = Entry(n)
    e.icon, e.text = ICON_RES, U.Time(rem)
    e.value, e.color, e.owner = 1 - rem / WAVE, U.FACTION[g.faction] or GREY, U.FACTION[g.faction]
    e.hot = rem <= 5
    if g == near then
      e.label, e.labelColor = label .. " (you)", GOLD
    else
      e.label = label
    end
    local enemy = g.faction and own and g.faction ~= own
    e.post = (enemy and "Enemy res at " or "Res wave at ") .. label .. " in " .. U.Time(rem) .. "s"
  end
  return n
end

function TM:Collect(now)
  local n = 0
  local e
  if O.start and O.start > now then
    n = n + 1
    e = Entry(n)
    e.icon, e.label, e.text = ICON_WATCH, "Battle begins", U.Time(O.start - now)
    e.value, e.color = 1 - (O.start - now) / 120, { 0.8, 0.8, 0.8 }
    e.post = "Battle begins in " .. U.Time(O.start - now)
  end

  if B.zone == "AB" then
    for i = 1, table.getn(AB_NODES) do
      local name = AB_NODES[i]
      local node = O.nodes[name]
      n = n + 1
      e = Entry(n)
      e.label = name
      local coords = PoiCoords(name)
      if coords then e.icon, e.coords = POI, coords end
      if node and node.ends and node.ends > now then
        e.text = U.Time(node.ends - now)
        e.value = 1 - (node.ends - now) / node.dur
        e.color = U.FACTION[node.by]
        e.hot = node.ends - now <= 10
        e.post = name .. ": " .. node.by .. " takes it in " .. U.Time(node.ends - now)
      elseif node and node.owner then
        e.post = name .. ": " .. node.owner .. " holds it"
      end
      if node and node.owner then e.owner = U.FACTION[node.owner] end
    end
  else
    for name, node in pairs(O.nodes) do
      if node.ends and node.ends > now and n < MAX_ROWS - 10 then
        n = n + 1
        e = Entry(n)
        e.label, e.text = name, U.Time(node.ends - now)
        e.value, e.color = 1 - (node.ends - now) / node.dur, U.FACTION[node.by]
        e.hot = node.ends - now <= 30
        e.post = name .. ": " .. node.by .. " takes it in " .. U.Time(node.ends - now)
        local coords = PoiCoords(name)
        if coords then e.icon, e.coords = POI, coords end
      end
    end
  end

  if B.db.timers.predict and B.zone == "AB" then
    local best, bestT
    for fac, p in pairs(P) do
      if p.rate and p.rate > 0 and p.max then
        p.eta = (p.max - p.cur) / p.rate
        if not bestT or p.eta < bestT then best, bestT = fac, p.eta end
      else
        p.eta = nil
      end
    end
    for _, fac in ipairs({ "Alliance", "Horde" }) do
      local p = P[fac]
      if p.cur then
        n = n + 1
        e = Entry(n)
        local score = p.cur .. "/" .. (p.max or "?")
        e.icon, e.label, e.owner = U.FLAG[fac], fac .. " " .. score, U.FACTION[fac]
        e.text = p.eta and ((fac == best and "wins " or "") .. U.Time(p.eta)) or ""
        e.value, e.color = p.cur / (p.max or 2000), U.FACTION[fac]
        e.post = fac .. " " .. score
          .. (p.eta and ((fac == best and " - wins in " or " - reaches the end in ") .. U.Time(p.eta)) or "")
      end
    end
  end

  if B.db.timers.spirit then n = self:CollectGuides(n, now) end
  return n
end

-- Sample rows for layout mode.
function TM:Samples(now)
  local n = 0
  local e
  local A, H = U.FACTION.Alliance, U.FACTION.Horde
  local data = {
    { ICON_WATCH, "Battle begins", 45, 120, { 0.8, 0.8, 0.8 } },
    { POI, "Stables", 37, 60, H, A },
    { POI, "Blacksmith", 12, 60, A, H },
    { "header", "Res waves - click to post" },
    { ICON_RES, "Stables (you)", 8, 30, A, A },
    { ICON_RES, "Alliance graveyard", 21, 30, A, A },
    { ICON_RES, "Farm", 14, 30, H, H },
  }
  for i = 1, table.getn(data) do
    local d = data[i]
    n = n + 1
    e = Entry(n)
    if d[1] == "header" then
      e.header, e.label = true, d[2]
    else
      local rem = d[4] - math.mod(now + d[3], d[4])
      e.icon, e.label, e.text = d[1], d[2], U.Time(rem)
      if d[1] == POI and WorldMap_GetPOITextureCoords then
        local l, r, t, b = WorldMap_GetPOITextureCoords(i == 2 and 38 or 27)
        e.coords = { l, r, t, b }
      end
      e.value, e.color, e.owner, e.hot = 1 - rem / d[4], d[5], d[6], rem <= 5
      if i == 5 then e.labelColor = GOLD end
      e.post = d[2] .. " in " .. U.Time(rem)
    end
  end
  return n
end

-- ---------------------------------------------------------------- UI

local BAR_X = ROW_H + 3   -- icon, then the owner strip, then the bar

function TM:Build()
  local f = U.Panel("OctoBGTimers", "timers", "Timers", WIDTH, ROW_H * 5 + 4, "RIGHT", -40, 120)
  U.Backdrop(f, 0.75)
  f:Hide()
  self.frame = f
  local barW = WIDTH - 4 - BAR_X
  for i = 1, MAX_ROWS do
    local r = CreateFrame("Button", nil, f)
    r:SetWidth(WIDTH - 4)
    r:SetHeight(ROW_H - 2)
    r:SetPoint("TOPLEFT", f, "TOPLEFT", 2, -2 - (i - 1) * ROW_H)
    r:RegisterForClicks("LeftButtonUp")
    -- separate draw layers so the stacking is fixed: track < bar < strip/icon < text
    r.track = U.Tex(r, U.WHITE, "BACKGROUND")
    r.track:SetPoint("TOPLEFT", r, "TOPLEFT", BAR_X, 0)
    r.track:SetWidth(barW)
    r.track:SetHeight(ROW_H - 2)
    r.track:SetVertexColor(0.16, 0.16, 0.19, 0.95)
    r.bar = U.Tex(r, BAR_TEX, "BORDER")
    r.bar:SetPoint("TOPLEFT", r, "TOPLEFT", BAR_X, 0)
    r.bar:SetHeight(ROW_H - 2)
    r.owner = U.Tex(r, U.WHITE, "ARTWORK")
    r.owner:SetPoint("TOPLEFT", r, "TOPLEFT", ROW_H - 1, 0)
    r.owner:SetWidth(3)
    r.owner:SetHeight(ROW_H - 2)
    r.icon = U.Tex(r, nil, "ARTWORK")
    r.icon:SetWidth(ROW_H - 3)
    r.icon:SetHeight(ROW_H - 3)
    r.icon:SetPoint("LEFT", r, "LEFT", 0, 0)
    r.label = U.Text(r, 11, U.NARROW)
    r.label:SetPoint("LEFT", r, "LEFT", BAR_X + 4, 0)
    r.label:SetJustifyH("LEFT")
    r.text = U.Text(r, 12)
    r.text:SetPoint("RIGHT", r, "RIGHT", -4, 0)
    r:SetScript("OnClick", function()
      if this.post then U.SendBG(this.post) end
    end)
    r:SetScript("OnEnter", function()
      if not this.post then return end
      GameTooltip:SetOwner(this, "ANCHOR_LEFT")
      GameTooltip:AddLine("Click: post to /bg")
      GameTooltip:AddLine(this.post, 1, 1, 1, 1)
      GameTooltip:Show()
    end)
    r:SetScript("OnLeave", function() GameTooltip:Hide() end)
    r:Hide()
    self.rows[i] = r
  end

  local big = U.Panel("OctoBGRes", "res", "Resurrection timer", 300, 40, "CENTER", 0, 140)
  big:Hide()
  big.text = U.Text(big, 24)
  big.text:SetPoint("CENTER", big, "CENTER", 0, 0)
  self.big = big
end

function TM:PaintRow(r, e, barW)
  r.post = e.post
  if e.header then
    r.icon:Hide()
    r.owner:Hide()
    r.track:Hide()
    r.bar:Hide()
    r.label:SetText(e.label or "")
    r.label:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
    r.text:SetText("")
    r:Show()
    return
  end
  if e.icon then
    r.icon:SetTexture(e.icon)
    if e.coords then
      r.icon:SetTexCoord(e.coords[1], e.coords[2], e.coords[3], e.coords[4])
    else
      r.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    end
    r.icon:Show()
  else
    r.icon:Hide()
  end
  if e.owner then
    r.owner:SetVertexColor(e.owner[1], e.owner[2], e.owner[3], 1)
    r.owner:Show()
  else
    r.owner:Hide()
  end
  r.track:Show()
  r.label:SetText(e.label or "")
  local lc = e.labelColor
  if lc then r.label:SetTextColor(lc[1], lc[2], lc[3]) else r.label:SetTextColor(1, 1, 1) end
  r.text:SetText(e.text or "")
  if e.hot then r.text:SetTextColor(1, 0.82, 0) else r.text:SetTextColor(1, 1, 1) end
  if e.value and e.color then
    local v = math.max(0.01, math.min(1, e.value))
    r.bar:SetWidth(barW * v)
    r.bar:SetTexCoord(0, v, 0, 1)
    r.bar:SetVertexColor(e.color[1], e.color[2], e.color[3], 0.9)
    r.bar:Show()
  else
    r.bar:Hide()
  end
  r:Show()
end

function TM:Paint(now)
  local f = self.frame
  if not f then return end
  local n = 0
  if B.db.timers.enabled then
    if B.test and not B.zone then n = self:Samples(now) else n = self:Collect(now) end
  end
  if n > MAX_ROWS then n = MAX_ROWS end
  if n == 0 then
    if f:IsShown() then f:Hide() end
  else
    f:SetHeight(n * ROW_H + 4)
    if not f:IsShown() then f:Show() end
  end
  local barW = WIDTH - 4 - BAR_X
  for i = 1, MAX_ROWS do
    local r = self.rows[i]
    if i <= n then
      self:PaintRow(r, self.pool[i], barW)
    else
      r.post = nil
      r:Hide()
    end
  end
  -- the big resurrection countdown
  local big = self.big
  local show, msg = false, nil
  if B.db.timers.big then
    if B.test then
      show, msg = true, "Resurrection in |cffffd100" .. U.Time(WAVE - math.mod(now, WAVE)) .. "|r"
    elseif B:IsBG() and UnitIsDeadOrGhost("player") then
      local t = S:MyWave(now)
      if t then
        show = true
        if UnitIsGhost("player") then
          msg = "Resurrection in |cffffd100" .. U.Time(t) .. "|r"
        else
          msg = "Release - next wave in |cffffd100" .. U.Time(t) .. "|r"
        end
      end
    end
  end
  if show then
    big.text:SetText(msg)
    if not big:IsShown() then big:Show() end
  elseif big:IsShown() then
    big:Hide()
  end
end

B:Every(0.1, function() TM:Paint(GetTime()) end, true)
B:Every(1, function()
  local now = GetTime()
  S:Prune(now)
  O:ScoreTick()
end, true)

B:On("OBG_INIT", function() TM:Build() end)

B:On("OBG_ZONE", function()
  S.guides, S.n, S.areaWave = {}, 0, nil
  O.nodes, O.start = {}, nil
  P.Alliance, P.Horde = {}, {}
  TM:Paint(GetTime())
end)

B:On("OBG_LAYOUT", function() TM:Paint(GetTime()) end)
