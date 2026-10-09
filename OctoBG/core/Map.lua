-- OctoBG :: map
-- Battleground map geometry: world <-> map coordinates, the player's facing,
-- landmarks, and plain-words descriptions of a position ("Horde flag room",
-- "midfield (west)", "near Stables").
--
-- World coordinates: x points north, y points west (server convention, what
-- SuperWoW's UnitPosition returns). Map coordinates: 0..1, x left->right,
-- y top->bottom (GetPlayerMapPosition, GetBattlefieldFlagPosition,
-- GetMapLandmarkInfo).

local B = OctoBG
local U = B.U
local M = {}
B.Map = M

local sqrt, atan2, abs = math.sqrt, math.atan2, math.abs
local PI = U.PI

-- World bounds of each map, read from the client's WorldMapArea.dbc
-- (patch-4.mpq): L/R are world y at the map's left/right edge, T/Bo world x
-- at its top/bottom edge. file = the map's texture folder.
M.DATA = {
  WSG = { file = "WarsongGulch",  L = 2041.67, R = 895.83,   T = 1627.08, Bo = 862.5 },
  AB  = { file = "ArathiBasin",   L = 1858.33, R = 102.08,   T = 1508.33, Bo = 337.5 },
  AV  = { file = "AlteracValley", L = 1781.25, R = -2456.25, T = 1085.42, Bo = -1739.58 },
  TG  = { file = "ThornGorge",    L = 2105,    R = 1058,     T = 2522,    Bo = 1828 },
}

-- Open-world zones from the same file, keyed by the map file name that
-- GetMapInfo returns: { L, R, T, Bo }. Used when the HUD and map run outside
-- battlegrounds (generated from WorldMapArea.dbc, continents left out).
local WORLD = {
  Durotar = { -1962.5, -7250, 1808.33, -1716.67 },
  Mulgore = { 2047.92, -3089.58, -272.92, -3697.92 },
  Barrens = { 2622.92, -7510.42, 1612.5, -5143.75 },
  Alterac = { 783.33, -2016.67, 1500, -366.67 },
  Arathi = { -866.67, -4466.67, -133.33, -2533.33 },
  Badlands = { -2079.17, -4566.67, -5889.58, -7547.92 },
  BlastedLands = { -1241.67, -4591.67, -10566.67, -12800 },
  Tirisfal = { 3033.33, -1485.42, 3837.5, 825 },
  Silverpine = { 3450, -750, 1666.67, -1133.33 },
  WesternPlaguelands = { 416.67, -3883.33, 3366.67, 500 },
  EasternPlaguelands = { -2185.42, -6056.25, 3800, 1218.75 },
  Hilsbrad = { 1066.67, -2133.33, 400, -1733.33 },
  Hinterlands = { -1575, -5425, 1466.67, -1100 },
  DunMorogh = { 1802.08, -3122.92, -3877.08, -7160.42 },
  SearingGorge = { -322.92, -2554.17, -6100, -7587.5 },
  BurningSteppes = { -266.67, -3195.83, -7031.25, -8983.33 },
  Elwynn = { 1535.42, -1935.42, -7939.58, -10254.17 },
  DeadwindPass = { -833.33, -3333.33, -9866.67, -11533.33 },
  Duskwood = { 833.33, -1866.67, -9716.67, -11516.67 },
  LochModan = { -1993.75, -4752.08, -4487.5, -6327.08 },
  Redridge = { -1570.83, -3741.67, -8575, -10022.92 },
  Stranglethorn = { 2220.83, -4160.42, -11168.75, -15422.92 },
  SwampOfSorrows = { -2222.92, -4516.67, -9620.83, -11150 },
  Westfall = { 3016.67, -483.33, -9400, -11733.33 },
  Wetlands = { -389.58, -4525, -2147.92, -4904.17 },
  Teldrassil = { 3814.58, -1277.08, 11831.25, 8437.5 },
  Darkshore = { 2941.67, -3608.33, 8333.33, 3966.67 },
  Ashenvale = { 1700, -4066.67, 4672.92, 829.17 },
  ThousandNeedles = { -433.33, -4833.33, -3966.67, -6900 },
  StonetalonMountains = { 3949, -2069, 3441, -569 },
  Desolace = { 4233.33, -262.5, 452.08, -2545.83 },
  Feralas = { 5441.67, -1508.33, -2366.67, -7000 },
  Dustwallow = { -975, -6225, -2033.33, -5533.33 },
  Tanaris = { -218.75, -7118.75, -5875, -10475 },
  Aszhara = { -3277.08, -8347.92, 5341.67, 1960.42 },
  Felwood = { 1641.67, -4108.33, 7133.33, 3300 },
  UngoroCrater = { 533.33, -3166.67, -5966.67, -8433.33 },
  Moonglade = { -1381.25, -3689.58, 8491.67, 6952.08 },
  Silithus = { 2537.5, -945.83, -5958.33, -8281.25 },
  Winterspring = { -316.67, -7416.67, 8533.33, 3800 },
  Stormwind = { 1722.92, -14.58, -7995.83, -9154.17 },
  Orgrimmar = { -3680.6, -5083.21, 2273.88, 1338.46 },
  Ironforge = { -713.59, -1504.22, -4569.24, -5096.85 },
  ThunderBluff = { 516.67, -527.08, -850, -1545.83 },
  Darnassus = { 2938.36, 1880.03, 10238.32, 9532.59 },
  Undercity = { 873.19, -86.18, 1877.95, 1237.84 },
  GMIsland = { 16748, 15920, 16525, 15984 },
  Hyjal = { -1080, -4286, 6125, 3983 },
  ScarletEnclave = { -4050, -7209, 3087, 979 },
  Sunnyglade = { 1013, -435, 1823, 858 },
  Lapidis = { 4933.33, 2031.88, -11043.48, -12959.42 },
  Gillijim = { 4436.22, 1344.12, -12528.71, -14575.72 },
  TelAbim = { -5179, -8406, -7184, -9371 },
  AlahThalas = { -2169, -3637, 4907, 3931 },
  Gilneas = { 3253, -413, -359, -2801 },
  Icepoint = { -5595, -7203, 14405, 13330 },
  BlackstoneIsland = { -6274, -8746, 799, -866 },
  ThalassianHighlands = { -1005, -4087, 4952, 2891 },
  DeadminesEntrance = { 1793.18, 1343.29, -11054.94, -11354.86 },
  WailingCavernsEntrance = { -1900.87, -2473.65, -488.64, -870.49 },
  MaraudonEntrance = { 3208, 2384, -1096, -1646 },
  GnomereganEntrance = { 1027.64, 456.45, -4806.32, -5185.46 },
  BlackrockMountain = { -760.94, -1472.5, -7327.82, -7796.5 },
  ScarletMonasteryEntrance = { -659.96, -863.62, 2947.37, 2812.33 },
  UldamanEntrance = { -2747.15, -3310.46, -5953.41, -6329.51 },
  AhnQirajEntrance = { 3932.67, -206.35, -8005.2, -10951.25 },
  CavernsOfTime = { -3695.85, -5044.09, -8023.09, -8911.18 },
  WinterVeilVale = { 1916, 484, -2332, -3309 },
  Ragefire = { 452.87, -285.99, 39.62, -452.95 },
  ZulFarrak = { 1625, 241.67, 2052.08, 1129.17 },
  TheTempleOfAtalHakkar = { 442.76, -252.27, -255.17, -718.52 },
  BlackFathomDeeps = { 485.41, -736.46, -107.91, -914.33 },
  TheStockade = { 189.82, -188.33, 220.63, -31.47 },
  Gnomeregan = { 863, -262, -245, -985 },
  Uldaman = { 645.12, -248.55, 204.31, -391.47 },
  MoltenCore = { -11, -1506, 1439, 456 },
  ZulGurub = { -612.5, -2733.33, -11225, -12639.58 },
  DireMaul = { 1007, -912, 955, -295 },
  BlackrockDepths = { 875, -1110, 1513, 245 },
  RuinsofAhnQiraj = { 3035.42, 522.92, -8233.33, -9908.33 },
  OnyxiasLair = { 155, -366, 86, -262 },
  BlackrockSpire = { 10.59, -876.25, 304.4, -286.83 },
  WailingCaverns = { 790, -380, 215, -570 },
  Maraudon = { 485.41, -1626.68, 1199.76, -211.13 },
  BlackwingLair = { -645, -1422, -7255, -7760 },
  TheDeadmines = { -322.94, -979.53, 36.93, -398.04 },
  RazorfenDowns = { 1271, 390, 2683, 2094 },
  RazorfenKraul = { 2058.92, 1322.47, 2349.64, 1858.68 },
  ScarletMonastery = { 1567.97, 947.99, 2030.18, 1616.86 },
  ScarletMonastery2f = { -162.27, -482.46, 307.37, 93.91 },
  ScarletMonastery3f = { 50.27, -562.42, 2009.1, 1600.64 },
  ScarletMonastery4f = { 1743.99, 1040.69, 1281.29, 812.42 },
  Scholomance = { 251.41, -68.64, 317.7, 104.33 },
  ShadowfangKeep = { 2436, 2055, -61, -315 },
  Stratholme = { -2639.83, -3825.18, 4163.9, 3374.04 },
  AhnQiraj = { 2515.63, 1538.07, -8051.8, -8703.5 },
  AhnQiraj2f = { 2915.62, 138.08, -7659.29, -9510.98 },
  Karazhan = { -1546, -2165, -10789, -11199 },
  DeeprunTram = { 2623.5, 2311.5, 95.5, -112.5 },
  BlackMorass = { 7338.47, 6066.48, -1247.55, -2093.03 },
  BlackMorass2f = { 7651.85, 6565.99, -1500.47, -2227.08 },
  GilneasCity = { 3290.32, 2040.14, -760.72, -1598.16 },
  Naxxramas = { -2375.27, -4366.96, 3656.7, 2338.28 },
  Naxxramas2f = { -4869.36, -5521.46, 3816.56, 3376.89 },
  CrescentGrove = { 1207.72, -1435.49, 882.98, -868.18 },
  HateforgeQuarry = { -3024.33, -3776.45, -7888.28, -8398.61 },
  KarazhanCrypt = { -1302.51, -1849.26, -10916.17, -11308.14 },
  StormwindVault = { 314.34, -40.16, 89.3, -145.44 },
  EmeraldSanctum = { 3939.1, 2666, 3519.72, 2666 },
  Moomoo = { 17296.3, 16288.62, 17158.52, 16486.73 },
  UpperKarazhan = { -1378, -2201, -10887, -11436 },
  UpperKarazhan2f = { -1483, -4283, -5800, -7668 },
  GrimReaches = { -2072, -7459, -2904, -6488 },
  Balor = { 4728, 1630, -7577, -9645 },
  Northwind = { 2258, -983, -6327, -8484 },
  DireMaulEntrance = { 2014, 690, -3401, -4270 },
  DragonmawRetreat = { -3428, -5062, -5599, -6672 },
  StormwroughtRuins = { -3365, -5345, -5424, -6774 },
  Timbermaw = { -2991, -4416, -7195, -8157 },
  WindhornCanyon = { -3184, -4418, -7163, -7992 },
  Moonwhisper = { -1354, -9210, 10204, 4963 },
  TimbermawTunnels = { -1862, -2723, 7395, 6788 },
  TimbermawEntrance = { -4646, -5993, 5175, 4204 },
  FrostmaneHollow = { -3157, -4168, -7453, -8106 },
  WindhornCanyonEntrance = { -3231, -3671, -5053, -5332 },
}

-- Bounds of the map in use: the battleground's, else the open-world zone's.
function M:Cur()
  if B.zone then return self.DATA[B.zone] end
  return self.world
end

function M:SetWorld(f)
  local w = f and WORLD[f]
  if w and not w.file then w.file, w.L, w.R, w.T, w.Bo = f, w[1], w[2], w[3], w[4] end
  self.world = w
  self.worldZone = w and GetRealZoneText() or nil
end

-- Find the open-world zone the player is in: once per zone (zones without a
-- map, like dungeons, are not asked again), never while the world map is open.
function M:RefreshWorld()
  if B.zone then
    self.world = nil
    return
  end
  local zone = GetRealZoneText()
  if zone == self.checkedZone then return end
  if WorldMapFrame and WorldMapFrame:IsVisible() then return end
  SetMapToCurrentZone()
  self:SetWorld(GetMapInfo())
  self.checkedZone = zone
end

B:Every(2, function() M:RefreshWorld() end, true)
B:On("OBG_ZONE", function() M.world, M.checkedZone = nil, nil end)
B:On("OBG_ACTIVE", function(ev, on)
  if not on then M.world, M.checkedZone = nil, nil end
end)

function M:ToMap(x, y)
  local d = self:Cur()
  if not d or not x or not y then return nil end
  return (d.L - y) / (d.L - d.R), (d.T - x) / (d.T - d.Bo)
end

function M:ToWorld(mx, my)
  local d = self:Cur()
  if not d or not mx or not my then return nil end
  return d.T - my * (d.T - d.Bo), d.L - mx * (d.L - d.R)
end

-- Make sure the world map shows the current zone, so the map-coordinate APIs
-- answer for it. SetMapToCurrentZone fires WORLD_MAP_UPDATE (pfQuest, Spy
-- redraw on it), so it runs only when the map shows something else, never
-- while the player has the world map open, and at most once a second.
local lastSet = 0
function M:EnsureMap()
  local d = self:Cur()
  if not d then return false end
  if GetMapInfo() == d.file then return true end
  if WorldMapFrame and WorldMapFrame:IsVisible() then return false end
  local now = GetTime()
  if now - lastSet < 1 then return false end
  lastSet = now
  SetMapToCurrentZone()
  local f = GetMapInfo()
  if B.zone then
    if f and f ~= d.file then d.file = f end   -- battleground: trust the client's own name
    return true
  end
  self:SetWorld(f)                             -- open world: may have walked into another zone
  return self.world ~= nil and f == self.world.file
end

-- Map position of a unit token (player / raidN / partyN), or nil.
function M:UnitMap(unit)
  if not self:EnsureMap() then return nil end
  local x, y = GetPlayerMapPosition(unit)
  if not x or (x == 0 and y == 0) then return nil end
  return x, y
end

-- World position of a friendly unit token: SuperWoW first, then the map.
function M:UnitWorld(unit)
  local x, y, z = U.Position(unit)
  if x then return x, y, z end
  local mx, my = self:UnitMap(unit)
  if mx then
    local wx, wy = self:ToWorld(mx, my)
    return wx, wy, nil
  end
  return nil
end

function M:PlayerWorld()
  return self:UnitWorld("player")
end

-- Yards between two world points (2D).
function M.Dist(x1, y1, x2, y2)
  local dx, dy = x2 - x1, y2 - y1
  return sqrt(dx * dx + dy * dy)
end

-- ---------------------------------------------------------------- facing

-- The minimap's player arrow is an unnamed Model child of Minimap whose
-- GetFacing() is the player's facing in radians (pfQuest and TabTarget read
-- it the same way). ClassicAPI may provide GetPlayerFacing instead.
local arrow
local function FindArrow()
  local kids = { Minimap:GetChildren() }
  for i = 1, table.getn(kids) do
    local v = kids[i]
    if v:IsObjectType("Model") and not v:GetName() then
      local m = v:GetModel()
      if m and string.find(string.lower(m), "minimaparrow", 1, true) then
        arrow = v
        return
      end
    end
  end
end

function M:RawFacing()
  if GetPlayerFacing then
    local f = GetPlayerFacing()
    if f then return f end
  end
  if not arrow then FindArrow() end
  if arrow then return arrow:GetFacing() end
  return nil
end

-- Facing in world terms: 0 = north, increasing towards west.
function M:Facing()
  local f = self:RawFacing()
  if not f then return nil end
  if B.db.facingSign == -1 then return -f end
  return f
end

-- Screen-space offset of a world point relative to the player:
-- right/forward in yards (rotate = true) or east/north (rotate = false).
function M.Relative(px, py, f, x, y, rotate)
  local dx, dy = x - px, y - py
  if rotate then
    local s, c = math.sin(f), math.cos(f)
    return dx * s - dy * c, dx * c + dy * s
  end
  return -dy, dx
end

-- ---------------------------------------------------------------- calibration

-- Two things are learned from the player's own running, once, then saved:
--   * does UnitPosition return (x, y) or (y, x)?
--   * does the arrow's facing grow towards west (+1) or east (-1)?
-- While running forward the direction of movement equals the facing, so each
-- sample votes for one of four hypotheses. Strafing and backpedalling give
-- off-axis samples; those are skipped when ambiguous and outvoted otherwise.
local cal = { votes = { 0, 0, 0, 0 } }

local function AngleDiff(a, b)
  local d = math.mod(abs(a - b), 2 * PI)
  if d > PI then d = 2 * PI - d end
  return d
end

function M:CalibrationDone()
  return B.db.facingSign ~= 0 and B.db.swapXY ~= nil
end

function M:ResetCalibration()
  B.db.facingSign = 0
  B.db.swapXY = nil
  cal.votes = { 0, 0, 0, 0 }
  cal.lx = nil
end

function M:CalibrateTick()
  if self:CalibrationDone() then return end
  local f = self:RawFacing()
  if not f then return end
  -- Without SuperWoW the map gives true world axes: only the sign is unknown.
  local x, y = U.RawPosition("player")
  local fromMap = false
  if not x then
    local mx, my = self:UnitMap("player")
    if not mx then cal.lx = nil return end
    x, y = self:ToWorld(mx, my)
    fromMap = true
  end
  local now = GetTime()
  if cal.lx and now - cal.lt < 0.7 then
    local dx, dy = x - cal.lx, y - cal.ly
    local dt = now - cal.lt
    local speed = sqrt(dx * dx + dy * dy) / dt
    if speed > 5.5 and speed < 15 then
      local h = atan2(dy, dx)
      local cand = { f, -f, PI / 2 - f, PI / 2 + f }
      local best, bestD, second = nil, 99, 99
      for i = 1, 4 do
        if not (fromMap and i > 2) then
          local d = AngleDiff(h, cand[i])
          if d < bestD then
            second = bestD
            best, bestD = i, d
          elseif d < second then
            second = d
          end
        end
      end
      if best and bestD < 0.35 and second > 0.8 then
        cal.votes[best] = cal.votes[best] + 1
      end
    end
  end
  cal.lx, cal.ly, cal.lt = x, y, now

  local top, topV, rest = nil, 0, 0
  for i = 1, 4 do
    if cal.votes[i] > topV then
      rest = rest + topV
      top, topV = i, cal.votes[i]
    else
      rest = rest + cal.votes[i]
    end
  end
  if top and topV >= 8 and topV >= 4 * rest then
    B.db.swapXY = (top >= 3)
    B.db.facingSign = (top == 1 or top == 3) and 1 or -1
    B:Print("calibrated: facing " .. (B.db.facingSign == 1 and "+" or "-")
      .. (B.db.swapXY and ", position axes swapped" or ""))
  end
end

B:Every(0.25, function() M:CalibrateTick() end, true)

-- ---------------------------------------------------------------- landmarks

-- Landmarks of the current map (AB bases, AV towers and graveyards), refreshed
-- every 2 seconds: { name, desc, tex, mx, my, wx, wy }.
M.marks = {}
local marksAt = 0
function M:Landmarks()
  local now = GetTime()
  if now - marksAt < 2 then return self.marks end
  marksAt = now
  if not self:EnsureMap() then return self.marks end
  local list = {}
  local n = GetNumMapLandmarks() or 0
  for i = 1, n do
    local name, desc, tex, x, y = GetMapLandmarkInfo(i)
    if name and x and y then
      local wx, wy = self:ToWorld(x, y)
      table.insert(list, { name = name, desc = desc, tex = tex, mx = x, my = y, wx = wx, wy = wy })
    end
  end
  self.marks = list
  return list
end

function M:FindLandmark(name)
  if not name then return nil end
  local low = string.lower(name)
  local list = self:Landmarks()
  for i = 1, table.getn(list) do
    if string.lower(list[i].name) == low then return list[i] end
  end
  return nil
end

function M:NearestLandmark(x, y, filter)
  local list = self:Landmarks()
  local best, bestD = nil, nil
  for i = 1, table.getn(list) do
    local m = list[i]
    if m.wx and (not filter or filter(m)) then
      local d = M.Dist(x, y, m.wx, m.wy)
      if not bestD or d < bestD then best, bestD = m, d end
    end
  end
  return best, bestD
end

-- ---------------------------------------------------------------- Warsong Gulch

-- Object positions from the server's WSG setup (flag stands, graveyard spirit
-- guides, power-ups). The flag rooms anchor everything else.
M.WSG = {
  Alliance = { flag = { 1540.42, 1481.33, 351.83 }, gy = { 1423.22, 1554.66 } },
  Horde    = { flag = { 916.02, 1434.41, 345.41 },  gy = { 1032.64, 1388.32 } },
  spots = {
    { 1449.93, 1470.71, "Alliance speed buff", 14 },
    { 1005.17, 1447.95, "Horde speed buff", 14 },
    { 1317.51, 1550.85, "heal buff (Alliance side)", 16 },
    { 1110.45, 1353.66, "heal buff (Horde side)", 16 },
    { 1320.09, 1378.79, "berserk buff (Alliance side)", 16 },
    { 1139.69, 1560.29, "berserk buff (Horde side)", 16 },
  },
}

-- Height relative to the flag stand: only known while the unit is in sight
-- range (SuperWoW position), never from the map. Heuristic thresholds.
local function Level(z, flagZ)
  if not z then return "" end
  if z > flagZ + 9 then return " - roof" end
  if z < flagZ - 6 then return " - lower level" end
  return ""
end

function M:DescribeWSG(x, y, z)
  local W = self.WSG
  local a, h = W.Alliance.flag, W.Horde.flag
  if M.Dist(x, y, a[1], a[2]) < 24 then return "Alliance flag room" .. Level(z, a[3]) end
  if M.Dist(x, y, h[1], h[2]) < 24 then return "Horde flag room" .. Level(z, h[3]) end
  if M.Dist(x, y, W.Alliance.gy[1], W.Alliance.gy[2]) < 28 then return "Alliance graveyard" end
  if M.Dist(x, y, W.Horde.gy[1], W.Horde.gy[2]) < 28 then return "Horde graveyard" end
  for i = 1, table.getn(W.spots) do
    local s = W.spots[i]
    if M.Dist(x, y, s[1], s[2]) < s[4] then return "at " .. s[3] end
  end
  -- progress along the line between the flag stands (0 = Horde, 1 = Alliance)
  -- and the sideways offset from it (negative = west)
  local vx, vy = a[1] - h[1], a[2] - h[2]
  local len = sqrt(vx * vx + vy * vy)
  local t = ((x - h[1]) * vx + (y - h[2]) * vy) / (len * len)
  local side = ((x - h[1]) * vy - (y - h[2]) * vx) / len
  local where
  if t > 0.84 then
    where = "Alliance base" .. Level(z, a[3])
  elseif t < 0.16 then
    where = "Horde base" .. Level(z, h[3])
  elseif t >= 0.4 and t <= 0.6 then
    where = "midfield"
  elseif t > 0.6 then
    where = "Alliance half"
  else
    where = "Horde half"
  end
  if t >= 0.16 and t <= 0.84 and abs(side) > 35 then
    where = where .. (side < 0 and " (west)" or " (east)")
  end
  return where
end

-- Plain words for a world position on the current map.
function M:Describe(x, y, z)
  if not x then return nil end
  if B.zone == "WSG" then return self:DescribeWSG(x, y, z) end
  local m, d = self:NearestLandmark(x, y)
  if m then
    if d < 60 then return m.name end
    return "near " .. m.name
  end
  return nil
end
