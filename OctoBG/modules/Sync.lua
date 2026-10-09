-- OctoBG :: raid sharing
-- OctoBG users in the same battleground share what their own client sees,
-- over hidden addon messages (prefix "OctoBG"; BATTLEGROUND in a
-- battleground, RAID or PARTY in the open world):
--   P  enemy positions: each client sends the enemies in its own object list,
--      6 per message, one message a second, taking turns through the list
--   S  an enemy going into stealth (where), D  that stealth ending
--   G  spirit guide waves (seconds to the next one) and where the guide stands
--   C  "I called this stealth out in /bg", so one client shouts, not all
-- Only first-hand data is sent, so nothing echoes from client to client.
--
-- Stealth callouts (db.stealth.shout, asked before switching on): a stealth
-- this client saw is posted to /bg after a random 0.2-1.2 s wait, unless
-- another OctoBG user's C for it arrives first; once per enemy per 20 s.
--
-- Eviction: pending callouts go when sent or cancelled; called[] and peers[]
-- entries older than 60 s are dropped every 10 s; everything clears on zone change.

local B = OctoBG
local U = B.U
local M = B.Map
local SY = { pending = {}, called = {}, peers = {}, rr = 0 }
B.Sync = SY

local PREFIX = "OctoBG"
local PER_MSG = 6
local CALL_EVERY = 20
local GUID_HEAD = "0x00000000"   -- player GUIDs: the top half is zero

local CLASSES = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }
local KINDS = { "Stealth", "Prowl", "Vanish", "Shadowmeld", "Invisibility", "Sap", "Pick Pocket" }
local FACS = { "Alliance", "Horde" }
local CLASS_ID, KIND_ID, FAC_ID = {}, {}, {}
for i = 1, table.getn(CLASSES) do CLASS_ID[CLASSES[i]] = i end
for i = 1, table.getn(KINDS) do KIND_ID[KINDS[i]] = i end
for i = 1, table.getn(FACS) do FAC_ID[FACS[i]] = i end

-- ---------------------------------------------------------------- wire format

local function Pack(guid)
  if string.sub(guid, 1, 10) == GUID_HEAD and string.len(guid) == 18 then return string.sub(guid, 11) end
  return guid
end

local function Unpack(s)
  if string.find(s, "^%x%x%x%x%x%x%x%x$") then return GUID_HEAD .. s end
  return s
end

local function Split(s, sep)
  local out, n, pos = {}, 0, 1
  while true do
    local a = string.find(s, sep, pos, true)
    n = n + 1
    if not a then
      out[n] = string.sub(s, pos)
      return out, n
    end
    out[n] = string.sub(s, pos, a - 1)
    pos = a + 1
  end
end

local function Round(v)
  return math.floor(v + 0.5)
end

local function Channel()
  if B:IsBG() then return "BATTLEGROUND" end
  if GetNumRaidMembers() > 0 then return "RAID" end
  if GetNumPartyMembers() > 0 then return "PARTY" end
  return nil
end

local function Send(msg)
  if not B.db.sync.enabled or not SendAddonMessage then return end
  local ch = Channel()
  if not ch then return end
  local ok, err = pcall(SendAddonMessage, PREFIX, msg, ch)
  if not ok then B:Debug("sync: " .. tostring(err)) end
end

-- ---------------------------------------------------------------- sending

function SY:SendPositions(now)
  local list, n = {}, 0
  for _, u in pairs(B.Tracker.units) do
    if u.visible and not u.fake and u.x and u.name and u.class and now - (u.posAt or 0) < 1 then
      n = n + 1
      list[n] = u
    end
  end
  if n == 0 then return end
  table.sort(list, function(a, b) return a.guid < b.guid end)
  local parts, k = {}, 0
  local start = math.mod(self.rr, n)
  for i = 0, math.min(n, PER_MSG) - 1 do
    local u = list[math.mod(start + i, n) + 1]
    local hp = 99
    if u.dead then
      hp = 0
    elseif u.hp and u.hpmax and u.hpmax > 0 then
      hp = math.max(1, Round(u.hp / u.hpmax * 99))
    end
    k = k + 1
    parts[k] = Pack(u.guid) .. "," .. (CLASS_ID[u.class] or 0) .. "," .. Round(u.x) .. "," .. Round(u.y)
      .. "," .. hp .. "," .. u.name
  end
  self.rr = self.rr + k
  Send("P~" .. table.concat(parts, "~"))
end

function SY:SendGuides(now)
  local S = B.Timers.spirit
  local parts, k = {}, 0
  for guid, g in pairs(S.guides) do
    if g.own and g.anchor and k < 5 then
      k = k + 1
      parts[k] = guid .. "," .. (FAC_ID[g.faction or ""] or 0) .. "," .. Round(S:Remaining(g, now) * 10)
        .. "," .. (g.x and Round(g.x) or "") .. "," .. (g.y and Round(g.y) or "")
    end
  end
  if k > 0 then Send("G~" .. table.concat(parts, "~")) end
end

-- ---------------------------------------------------------------- stealth callouts

local function ClassName(token)
  if not token then return nil end
  return string.sub(token, 1, 1) .. string.lower(string.sub(token, 2))
end

function SY:CallText(m)
  local cls = ClassName(m.class)
  local who = m.name or ("unseen " .. string.lower(cls or "enemy"))
  if cls and m.name then who = who .. " (" .. cls .. ")" end
  local where = m.x and M:Describe(m.x, m.y, m.z)
  return m.kind .. ": " .. who .. (where and (" - " .. where) or "")
end

-- quiet = a mark moved (Tracker:Touch): shared again, not called out again.
B:On("OBG_STEALTH", function(ev, key, m, quiet)
  if not m or m.remote then return end
  if m.x and KIND_ID[m.kind] and string.sub(key, 1, 5) ~= "name:" then
    Send("S~" .. Pack(key) .. "," .. (CLASS_ID[m.class or ""] or 0) .. "," .. KIND_ID[m.kind] .. ","
      .. Round(m.x) .. "," .. Round(m.y) .. "," .. (m.name or ""))
  end
  if B.db.stealth.shout and B:IsBG() and not quiet then
    local now = GetTime()
    if now - (SY.called[key] or 0) >= CALL_EVERY and not SY.pending[key] then
      SY.pending[key] = { at = now + 0.2 + math.random() }
    end
  end
end)

B:On("BUFF_REMOVED_OTHER", function(ev, guid, a2, spell)
  local kind = B.Tracker.STEALTH[spell]
  if kind and kind ~= "Vanish" and type(guid) == "string" and B.Tracker.units[guid] then
    Send("D~" .. Pack(guid))
  end
end, true)

function SY:Callouts(now)
  for key, p in pairs(self.pending) do
    if now >= p.at then
      self.pending[key] = nil
      local m = B.Tracker.stealth[key]
      if m and now - (self.called[key] or 0) >= CALL_EVERY and U.SendBG(self:CallText(m)) then
        self.called[key] = now
        if string.sub(key, 1, 5) ~= "name:" then Send("C~" .. Pack(key)) end
      end
    end
  end
end

-- ---------------------------------------------------------------- receiving

local function OnPositions(body, from)
  local T = B.Tracker
  local entries, ne = Split(body, "~")
  for i = 1, ne do
    local f, nf = Split(entries[i], ",")
    local x, y, hp = tonumber(f[3]), tonumber(f[4]), tonumber(f[5])
    if nf >= 6 and x and y and hp then
      T:Remote(Unpack(f[1]), f[6] ~= "" and f[6] or nil, CLASSES[tonumber(f[2]) or 0], x, y, hp, from)
    end
  end
end

local function OnStealth(body)
  local f, nf = Split(body, ",")
  local x, y, kind = tonumber(f[4]), tonumber(f[5]), KINDS[tonumber(f[3]) or 0]
  if nf >= 6 and x and y and kind then
    local name = f[6] ~= "" and f[6] or nil
    B.Tracker:RemoteStealth(Unpack(f[1]), name, CLASSES[tonumber(f[2]) or 0] or B.Tracker.KIND_CLASS[kind], kind, x, y)
  end
end

local function OnGuides(body)
  local S = B.Timers.spirit
  local entries, ne = Split(body, "~")
  for i = 1, ne do
    local f, nf = Split(entries[i], ",")
    local rem = tonumber(f[3])
    if nf >= 5 and rem and f[1] ~= "" then
      S:Remote(f[1], FACS[tonumber(f[2]) or 0], rem / 10, tonumber(f[4]), tonumber(f[5]))
    end
  end
end

B:On("CHAT_MSG_ADDON", function(ev, prefix, msg, ch, from)
  if prefix ~= PREFIX or not msg or not B.db.sync.enabled then return end
  if from == UnitName("player") then return end
  local now = GetTime()
  SY.peers[from or "?"] = now
  local t, body = string.sub(msg, 1, 1), string.sub(msg, 3)
  if t == "P" then
    OnPositions(body, from)
  elseif t == "S" then
    OnStealth(body)
  elseif t == "D" then
    local guid = Unpack(body)
    local m = B.Tracker.stealth[guid]
    if m and m.remote then B.Tracker:DropStealth(guid) end
  elseif t == "G" then
    OnGuides(body)
  elseif t == "C" then
    local key = Unpack(body)
    SY.pending[key] = nil
    SY.called[key] = now
  end
end, true)

-- ---------------------------------------------------------------- tickers

B:Every(1, function()
  if B.db.sync.enabled then SY:SendPositions(GetTime()) end
end, true)

B:Every(0.1, function() SY:Callouts(GetTime()) end, true)

local guideAt = 0
B:Every(2, function()
  local now = GetTime()
  if B.db.sync.enabled and B:IsBG() and now - guideAt >= 10 then
    guideAt = now
    SY:SendGuides(now)
  end
  for k, t in pairs(SY.called) do
    if now - t > 60 then SY.called[k] = nil end
  end
  for k, t in pairs(SY.peers) do
    if now - t > 60 then SY.peers[k] = nil end
  end
end, true)

B:On("OBG_ZONE", function()
  SY.pending, SY.called, SY.peers, SY.rr = {}, {}, {}, 0
end)

-- OctoBG users heard from in the last minute.
function SY:PeerList()
  local names, n = {}, 0
  for name in pairs(self.peers) do
    n = n + 1
    names[n] = name
  end
  table.sort(names)
  return names, n
end
