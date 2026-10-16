-- THERMAL - Assistant thermique plein ecran pour EdgeTX 2.11 / TX16S
-- Version 0.5 - cartes multiples choisies depuis THMCFG
-- Sources attendues : Alt, VSpd, GPS, GSpd, Hdg, GAlt, Sats

local NAME = "Thermal"
local PI = math.pi
local DEG = PI / 180
local EARTH_R = 6371000
local SECTORS = 16
local MAP_TILE = 210
local MAP_SIZES = { 315, 630, 1260, 2520 }

local options = {
  { "HomeSw",   SWITCH, 0 },
  { "MinSats",  VALUE, 4, 4, 20 },
  { "Chrono",   TIMER, 2 },
  { "TrackPts", VALUE, 140, 30, 240 },
  { "TrackStep",VALUE, 3, 1, 30 },
  { "TurnRate", VALUE, 6, 2, 30 },
  { "VarioMax", VALUE, 5, 1, 10 },
  { "Entree",   FILE, "", "SOUNDS" },
  { "Sortie",   FILE, "", "SOUNDS" },
  { "ResetSw",  SWITCH, 0 }
}

local function clamp(v, lo, hi)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

local function round(v)
  if v >= 0 then return math.floor(v + 0.5) end
  return math.ceil(v - 0.5)
end

local function wrap180(v)
  while v > 180 do v = v - 360 end
  while v < -180 do v = v + 360 end
  return v
end

local function sourceId(name)
  local info = getFieldInfo(name)
  return info and info.id or nil
end

local function trianglePath()
  local info = model.getInfo()
  local name = info and info.name or "default"
  name = string.sub(string.gsub(name, "[^%w%-%_]", "_"), 1, 12)
  if name == "" then name = "default" end
  return "/WIDGETS/THERMAL/" .. name .. ".tri"
end

local function mapSelectionPath()
  return string.gsub(trianglePath(), "%.tri$", ".map")
end

local function loadMapSelection(w)
  local maps = {}
  local file = io.open("/WIDGETS/THERMAL/MAPS/index.csv", "r")
  if file then
    local data = io.read(file, 8192)
    io.close(file)
    for line in string.gmatch(data or "", "[^\r\n]+") do
      local slug, label, lat, lon, area = string.match(line,
        "^([^,]+),([^,]+),([^,]+),([^,]+),([^,]+)")
      lat, lon, area = tonumber(lat), tonumber(lon), tonumber(area)
      if slug and lat and lon and area then
        maps[#maps + 1] = { slug=slug, label=label, lat=lat, lon=lon,
          area=area, cos=math.cos(lat * DEG) }
      end
    end
  end
  local wanted
  file = io.open(mapSelectionPath(), "r")
  if file then
    wanted = io.read(file, 32)
    io.close(file)
  end
  local chosen = maps[1]
  for i = 1, #maps do
    if maps[i].slug == wanted then chosen = maps[i] break end
  end
  if not chosen then
    chosen = { slug="", label="CARTE ABSENTE", lat=46.2949984,
      lon=6.9727851, area=5000, cos=math.cos(46.2949984 * DEG) }
  end
  if not w.mapDef or w.mapDef.slug ~= chosen.slug then
    w.mapDef = chosen
    w.mapX, w.mapY = 0, 0
    w.mapCache = {}
    w.mapCacheLevel = 0
    w.mapCacheCount = 0
    w.track = {}
  end
end

local function defaultPoint(name)
  return { name=name, lat=nil, lon=nil, radius=100, minAlt=-1000, maxAlt=10000 }
end

local function loadTriangle(w)
  w.points = { defaultPoint("A"), defaultPoint("B"), defaultPoint("C") }
  local file = io.open(trianglePath(), "r")
  if not file then return end
  local data = io.read(file, 512)
  io.close(file)
  local lineNumber = 0
  for line in string.gmatch(data or "", "[^\r\n]+") do
    lineNumber = lineNumber + 1
    if lineNumber <= 3 then
      local values = {}
      for value in string.gmatch(line, "[^,]+") do values[#values + 1] = tonumber(value) end
      if #values == 5 then
        local p = w.points[lineNumber]
        p.lat, p.lon, p.radius, p.minAlt, p.maxAlt =
          values[1], values[2], values[3], values[4], values[5]
      end
    end
  end
end

local function saveTriangle(w)
  local file = io.open(trianglePath(), "w")
  if not file then return end
  for i = 1, 3 do
    local p = w.points[i]
    if p.lat and p.lon then
      io.write(file, string.format("%.7f,%.7f,%.0f,%.1f,%.1f", p.lat, p.lon,
        p.radius, p.minAlt, p.maxAlt))
    else
      io.write(file, "0,0,100,-1000,10000")
    end
    if i < 3 then io.write(file, "\n") end
  end
  io.close(file)
end

local function toMapLocal(w, lat, lon)
  local m = w.mapDef
  local north = (lat - m.lat) * DEG * EARTH_R
  local east = (lon - m.lon) * DEG * EARTH_R * m.cos
  return east, north
end

local function mapLocalToGPS(w, east, north)
  local m = w.mapDef
  return m.lat + north / EARTH_R / DEG,
    m.lon + east / (EARTH_R * m.cos) / DEG
end

local function acquireIds(w)
  w.ids.Alt = sourceId("Alt")
  w.ids.VSpd = sourceId("VSpd")
  w.ids.GPS = sourceId("GPS")
  w.ids.GSpd = sourceId("GSpd")
  w.ids.Hdg = sourceId("Hdg")
  w.ids.GAlt = sourceId("GAlt")
  w.ids.Sats = sourceId("Sats")
end

local function readSource(id)
  if not id then return nil, false, false end
  if getSourceValue then
    local value, current, fresh = getSourceValue(id)
    return value, current == true, fresh == true
  end
  local value = getValue(id)
  return value, value ~= nil, true
end

local function clearBins(w, keepPrevious)
  if not keepPrevious then w.previous = {} end
  w.sums = {}
  w.counts = {}
  w.current = {}
  for i = 1, SECTORS do
    w.sums[i] = 0
    w.counts[i] = 0
  end
  w.turnTotal = 0
  w.turnDir = 0
end

local function resetFlight(w)
  w.homeLat = nil
  w.homeLon = nil
  w.homeCos = 1
  w.x = 0
  w.y = 0
  w.distance = 0
  w.track = {}
  w.filteredVspd = nil
  w.lastHdg = nil
  w.lastHdgTime = nil
  w.lastTurnAt = nil
  w.thermalActive = false
  w.gainStartAlt = nil
  w.gain = 0
  clearBins(w, false)
end

local function setHome(w, lat, lon)
  w.homeLat = lat
  w.homeLon = lon
  w.homeCos = math.cos(lat * DEG)
  w.x, w.y, w.distance = 0, 0, 0
  w.track = { { x = 0, y = 0 } }
  w.lastHdg = nil
  w.lastHdgTime = nil
  w.lastTurnAt = nil
  w.thermalActive = false
  w.gainStartAlt = w.alt
  w.gain = 0
  clearBins(w, false)
  w.pendingHome = false
end

local function toLocal(w, lat, lon)
  local north = (lat - w.homeLat) * DEG * EARTH_R
  local east = (lon - w.homeLon) * DEG * EARTH_R * w.homeCos
  return east, north
end

local function appendTrack(w, x, y)
  local last = w.track[#w.track]
  local step = w.options.TrackStep
  if last then
    local dx, dy = x - last.x, y - last.y
    if dx * dx + dy * dy < step * step then return end
  end
  w.track[#w.track + 1] = { x = x, y = y }
  local limit = w.options.TrackPts
  if #w.track > limit then table.remove(w.track, 1) end
end

local function finishTurn(w)
  local completed = {}
  for i = 1, SECTORS do
    if w.counts[i] > 0 then completed[i] = w.sums[i] / w.counts[i] end
  end
  w.previous = completed
  clearBins(w, true)
end

local function addThermalSample(w, heading, vspd, delta, now)
  local dt = (now - w.lastHdgTime) / 100
  if dt <= 0 or dt > 2 then return end
  local rate = math.abs(delta) / dt

  if rate >= w.options.TurnRate and math.abs(delta) < 90 then
    local direction = delta >= 0 and 1 or -1
    if w.turnDir ~= 0 and direction ~= w.turnDir then
      clearBins(w, true)
    end
    w.turnDir = direction
    w.turnTotal = w.turnTotal + math.abs(delta)
    w.lastTurnAt = now

    if not w.thermalActive then
      w.thermalActive = true
      w.gainStartAlt = w.alt
    end

    local sector = math.floor((heading % 360) / (360 / SECTORS)) + 1
    w.sums[sector] = w.sums[sector] + vspd
    w.counts[sector] = w.counts[sector] + 1
    w.current[sector] = w.sums[sector] / w.counts[sector]

    if w.turnTotal >= 345 then finishTurn(w) end
  elseif w.lastTurnAt and now - w.lastTurnAt > 600 then
    w.thermalActive = false
    w.turnDir = 0
    w.turnTotal = 0
    w.lastTurnAt = nil
  end
end

local function create(zone, opts)
  local w = {
    zone = zone,
    options = opts,
    ids = {},
    lastIdCheck = 0,
    lastTriangleLoad = 0,
    lastProcess = 0,
    lastHomeSwitch = false,
    lastResetSwitch = false,
    pendingHome = false,
    validGPS = false,
    validVario = false,
    alt = 0,
    vspd = 0,
    gspd = 0,
    heading = 0,
    galt = 0,
    sats = 0,
    mapX = 0,
    mapY = 0,
    zoom = 1,
    zoomEdit = false,
    mapCache = {},
    mapCacheLevel = 0,
    mapCacheCount = 0,
    lastTouchAt = -100,
    editPoint = 0,
    activePoint = 1,
    pointInside = false,
    pointValid = false,
    returnAInside = false,
    returnAValid = false,
    raceState = 0,
    raceStart = nil,
    splitB = nil,
    splitC = nil,
    raceTotal = nil
  }
  acquireIds(w)
  w.logo = Bitmap.open("/WIDGETS/THERMAL/logo.png")
  loadMapSelection(w)
  loadTriangle(w)
  resetFlight(w)
  return w
end

local function update(w, opts)
  w.options = opts
  acquireIds(w)
  loadMapSelection(w)
  loadTriangle(w)
  w.lastTriangleLoad = getTime()
end

local function playSelectedSound(filename)
  if type(filename) == "string" and filename ~= "" then playFile(filename) end
end

local function timerIndex(w)
  return w.options.Chrono or 0
end

local function timerValue(w)
  local timer = model.getTimer(timerIndex(w))
  return timer and math.max(0, timer.value or 0) or 0
end

local function startInternalTimer(w)
  local index = timerIndex(w)
  model.setTimer(index, { mode=0, start=0, value=0 })
  model.resetTimer(index)
  model.setTimer(index, { mode=1, start=0, value=0, name="TRI" })
end

local function stopInternalTimer(w)
  local index = timerIndex(w)
  local value = timerValue(w)
  model.setTimer(index, { mode=0, value=value })
  return value
end

local function clearInternalTimer(w)
  local index = timerIndex(w)
  model.setTimer(index, { mode=0, start=0, value=0 })
  model.resetTimer(index)
end

local function resetRace(w)
  w.raceState = 0       -- attente d'une entree puis d'une sortie de A
  w.raceStart = nil
  w.splitB = nil
  w.splitC = nil
  w.raceTotal = nil
  w.activePoint = 1
  w.pointInside = false
  w.pointValid = false
  w.returnAInside = false
  w.returnAValid = false
  clearInternalTimer(w)
end

local function elapsedSinceStart(w, now)
  if not w.raceStart then return nil end
  return timerValue(w)
end

local function pointGeometry(w, index)
  local p = w.points and w.points[index]
  if not p or not p.lat or not p.lon or p.lat == 0 or p.lon == 0 then return nil, false end
  local px, py = toMapLocal(w, p.lat, p.lon)
  local dx, dy = w.mapX - px, w.mapY - py
  return p, dx * dx + dy * dy <= p.radius * p.radius
end

local function altitudeValid(w, p)
  return w.validVario and w.alt >= p.minAlt and w.alt <= p.maxAlt
end

local function updateTurnPoint(w)
  local now = getTime()
  local p, inside = pointGeometry(w, w.activePoint)
  if not p then
    w.pointInside = false
    return
  end

  if inside and not w.pointInside then
    w.pointInside = true
    w.pointValid = altitudeValid(w, p)
    playSelectedSound(w.options.Entree)
    if w.pointValid then
      if w.raceState == 1 and w.activePoint == 2 and not w.splitB then
        w.splitB = elapsedSinceStart(w, now)
      elseif w.raceState == 2 and w.activePoint == 3 and not w.splitC then
        w.splitC = elapsedSinceStart(w, now)
      elseif w.raceState == 3 and w.activePoint == 1 then
        w.raceTotal = stopInternalTimer(w)
        w.raceState = 4
      end
    end
  elseif not inside and w.pointInside then
    playSelectedSound(w.options.Sortie)
    w.pointInside = false
    if w.pointValid then
      if w.raceState == 0 and w.activePoint == 1 then
        w.raceStart = now
        w.splitB, w.splitC, w.raceTotal = nil, nil, nil
        startInternalTimer(w)
        w.raceState, w.activePoint = 1, 2
      elseif w.raceState == 1 and w.activePoint == 2 and w.splitB then
        w.raceState, w.activePoint = 2, 3
      elseif w.raceState == 2 and w.activePoint == 3 and w.splitC then
        w.raceState, w.activePoint = 3, 1
      end
    end
    w.pointValid = false
  elseif inside and altitudeValid(w, p) then
    w.pointValid = true
    if w.raceState == 1 and w.activePoint == 2 and not w.splitB then
      w.splitB = elapsedSinceStart(w, now)
    elseif w.raceState == 2 and w.activePoint == 3 and not w.splitC then
      w.splitC = elapsedSinceStart(w, now)
    elseif w.raceState == 3 and w.activePoint == 1 then
      w.raceTotal = stopInternalTimer(w)
      w.raceState = 4
    end
  end

  -- Retour premature dans A : la prochaine sortie valide de A devient un
  -- nouveau depart et efface les temps du parcours abandonne.
  if w.raceState == 1 or w.raceState == 2 then
    local pointA, insideA = pointGeometry(w, 1)
    if pointA then
      if insideA and not w.returnAInside then
        w.returnAInside = true
        w.returnAValid = altitudeValid(w, pointA)
      elseif insideA and altitudeValid(w, pointA) then
        w.returnAValid = true
      elseif not insideA and w.returnAInside then
        w.returnAInside = false
        if w.returnAValid then
          w.raceStart = now
          w.splitB, w.splitC, w.raceTotal = nil, nil, nil
          startInternalTimer(w)
          w.raceState, w.activePoint = 1, 2
          w.pointInside, w.pointValid = false, false
        end
        w.returnAValid = false
      end
    end
  end
end

local function process(w)
  local now = getTime()
  if now - w.lastProcess < 4 then return end
  w.lastProcess = now

  if now - w.lastIdCheck > 200 then
    acquireIds(w)
    w.lastIdCheck = now
  end

  -- Un outil autonome suspend les widgets sans forcement recreer leur instance.
  -- Relire le fichier permet donc de recuperer A/B/C apres Reglages Triangle.
  if now - w.lastTriangleLoad > 200 then
    loadMapSelection(w)
    loadTriangle(w)
    w.lastTriangleLoad = now
  end

  local alt, altCurrent = readSource(w.ids.Alt)
  local vs, vsCurrent = readSource(w.ids.VSpd)
  local gps, gpsCurrent, gpsFresh = readSource(w.ids.GPS)
  local speed, speedCurrent = readSource(w.ids.GSpd)
  local heading, headingCurrent, headingFresh = readSource(w.ids.Hdg)
  local galt, galtCurrent = readSource(w.ids.GAlt)
  local sats, satsCurrent = readSource(w.ids.Sats)

  if altCurrent and type(alt) == "number" then w.alt = alt end
  if vsCurrent and type(vs) == "number" then
    w.vspd = vs
    if w.filteredVspd == nil then
      w.filteredVspd = vs
    else
      w.filteredVspd = w.filteredVspd + 0.25 * (vs - w.filteredVspd)
    end
  end
  if speedCurrent and type(speed) == "number" then w.gspd = speed end
  if headingCurrent and type(heading) == "number" then w.heading = heading % 360 end
  if galtCurrent and type(galt) == "number" then w.galt = galt end
  if satsCurrent and type(sats) == "number" then w.sats = sats end

  w.validVario = altCurrent and vsCurrent
  local lat, lon
  if gpsCurrent and type(gps) == "table" then
    lat = gps.lat
    lon = gps.lon or gps.lng
  end
  w.validGPS = type(lat) == "number" and type(lon) == "number"
    and lat ~= 0 and lon ~= 0 and w.sats >= w.options.MinSats

  local switchOn = false
  local homeSwitch = w.options.HomeSw
  if homeSwitch and homeSwitch ~= 0 then
    switchOn = getSwitchValue(homeSwitch) == true
  end
  if switchOn and not w.lastHomeSwitch then w.pendingHome = true end
  w.lastHomeSwitch = switchOn

  local resetOn = false
  local resetSwitch = w.options.ResetSw
  if resetSwitch and resetSwitch ~= 0 then
    resetOn = getSwitchValue(resetSwitch) == true
  end
  if resetOn and not w.lastResetSwitch then resetRace(w) end
  w.lastResetSwitch = resetOn

  if w.validGPS and (w.pendingHome or not w.homeLat) then
    setHome(w, lat, lon)
  end

  if w.validGPS and w.homeLat and gpsFresh then
    w.x, w.y = toLocal(w, lat, lon)
    w.mapX, w.mapY = toMapLocal(w, lat, lon)
    w.distance = math.sqrt(w.x * w.x + w.y * w.y)
    appendTrack(w, w.mapX, w.mapY)
    updateTurnPoint(w)
  end

  if w.validGPS and headingCurrent and w.filteredVspd ~= nil and (headingFresh or gpsFresh) then
    if w.lastHdg ~= nil and w.lastHdgTime ~= nil then
      local delta = wrap180(w.heading - w.lastHdg)
      addThermalSample(w, w.heading, w.filteredVspd, delta, now)
    end
    w.lastHdg = w.heading
    w.lastHdgTime = now
  end

  if w.gainStartAlt and w.validVario then w.gain = w.alt - w.gainStartAlt end
end

local function centered(x, y, width, text, flags)
  local tw = lcd.sizeText(text, flags)
  lcd.drawText(x + (width - tw) / 2, y, text, flags)
end

local function drawMap(w, x, y, width, height, colors)
  lcd.drawFilledRectangle(x, y, width, height, colors.mapBg)
  local level = clamp(w.zoom or 1, 1, 4)
  local size = MAP_SIZES[level]
  local anchorX, anchorY = width * 0.50, height * 0.667
  local area = w.mapDef.area
  local aircraftWorldX = size * 0.5 + w.mapX / area * size
  local aircraftWorldY = size * (2 / 3) - w.mapY / area * size
  local left, top = aircraftWorldX - anchorX, aircraftWorldY - anchorY
  local firstCol = math.floor(left / MAP_TILE)
  local lastCol = math.floor((left + width) / MAP_TILE)
  local firstRow = math.floor(top / MAP_TILE)
  local lastRow = math.floor((top + height) / MAP_TILE)
  local maxTile = math.ceil(size / MAP_TILE) - 1
  if w.mapCacheLevel ~= level then
    w.mapCache = {}
    w.mapCacheLevel = level
    w.mapCacheCount = 0
  end
  for row = firstRow, lastRow do
    for col = firstCol, lastCol do
      if col >= 0 and row >= 0 and col <= maxTile and row <= maxTile then
        local key = tostring(col) .. "_" .. tostring(row)
        local bitmap = w.mapCache[key]
        if not bitmap then
          if w.mapCacheCount >= 12 then
            w.mapCache = {}
            w.mapCacheCount = 0
          end
          bitmap = Bitmap.open("/WIDGETS/THERMAL/MAPS/" .. w.mapDef.slug
            .. "/Z" .. tostring(level - 1) .. "/" .. key .. ".png")
          w.mapCache[key] = bitmap
          w.mapCacheCount = w.mapCacheCount + 1
        end
        lcd.drawBitmap(bitmap, x + col * MAP_TILE - left, y + row * MAP_TILE - top)
      end
    end
  end
  lcd.drawFilledRectangle(x + 3, y + 3, 100, 18, lcd.RGB(245, 245, 235))
  lcd.drawText(x + 6, y + 5, w.mapDef.label, SMLSIZE + colors.text)

  local function project(px, py)
    local wx = size * 0.5 + px / area * size
    local wy = size * (2 / 3) - py / area * size
    return x + wx - left, y + wy - top
  end

  -- Triangle FAI et zones des trois points.
  local pointScreen = {}
  for i = 1, 3 do
    local p = w.points[i]
    if p.lat and p.lon and p.lat ~= 0 and p.lon ~= 0 then
      local px, py = toMapLocal(w, p.lat, p.lon)
      pointScreen[i] = { project(px, py) }
    end
  end
  for i = 1, 3 do
    local j = i % 3 + 1
    if pointScreen[i] and pointScreen[j] then
      lcd.drawLine(pointScreen[i][1] - 1, pointScreen[i][2], pointScreen[j][1] - 1, pointScreen[j][2], SOLID, colors.text)
      lcd.drawLine(pointScreen[i][1] + 2, pointScreen[i][2], pointScreen[j][1] + 2, pointScreen[j][2], SOLID, colors.text)
      lcd.drawLine(pointScreen[i][1], pointScreen[i][2], pointScreen[j][1], pointScreen[j][2], SOLID, colors.triangle)
      lcd.drawLine(pointScreen[i][1] + 1, pointScreen[i][2], pointScreen[j][1] + 1, pointScreen[j][2], SOLID, colors.triangle)
    end
  end
  for i = 1, 3 do
    if pointScreen[i] then
      local sx, sy = pointScreen[i][1], pointScreen[i][2]
      local radiusPx = math.max(3, w.points[i].radius / area * size)
      local color = i == w.activePoint and colors.activePoint or colors.point
      lcd.drawCircle(sx, sy, radiusPx, color)
      lcd.drawFilledCircle(sx, sy, 9, color)
      centered(sx - 8, sy - 6, 16, w.points[i].name, SMLSIZE + BOLD + WHITE)
    end
  end

  local lastX, lastY
  for i = 1, #w.track do
    local p = w.track[i]
    local sx, sy = project(p.x, p.y)
    if lastX and sx >= x and sx <= x + width and sy >= y and sy <= y + height
      and lastX >= x and lastX <= x + width and lastY >= y and lastY <= y + height then
      lcd.drawLine(lastX, lastY, sx, sy, SOLID, colors.track)
    end
    lastX, lastY = sx, sy
  end

  if w.homeLat then
    local homeX, homeY = toMapLocal(w, w.homeLat, w.homeLon)
    local hx, hy = project(homeX, homeY)
    if hx >= x + 5 and hx <= x + width - 5 and hy >= y + 5 and hy <= y + height - 5 then
      lcd.drawFilledCircle(hx, hy, 7, colors.home)
      centered(hx - 8, hy - 6, 16, "H", SMLSIZE + WHITE)
    end
  end

  local cx, cy = x + anchorX, y + anchorY
  local a = w.heading * DEG
  local tipX, tipY = cx + math.sin(a) * 15, cy - math.cos(a) * 15
  local leftX, leftY = cx + math.sin(a + 2.45) * 10, cy - math.cos(a + 2.45) * 10
  local rightX, rightY = cx + math.sin(a - 2.45) * 10, cy - math.cos(a - 2.45) * 10
  lcd.drawFilledTriangle(tipX, tipY, leftX, leftY, rightX, rightY, colors.aircraft)

  lcd.drawFilledRectangle(x + 2, y + 2, 128, 18, lcd.RGB(245, 245, 235))
  lcd.drawText(x + 5, y + 4, "GPS " .. tostring(round(w.sats)) .. "  Z" .. tostring(level), SMLSIZE + colors.text)
  if w.zoomEdit then
    lcd.drawFilledRectangle(x + 133, y + 2, 105, 18, colors.activePoint)
    centered(x + 133, y + 4, 105, "ZOOM ACTIF", SMLSIZE + BOLD + WHITE)
  end
  local zoomFill = w.zoomEdit and colors.activePoint or lcd.RGB(245, 245, 235)
  local zoomText = w.zoomEdit and WHITE or colors.text
  lcd.drawFilledRectangle(x + width - 73, y + 27, 68, 43, zoomFill)
  lcd.drawRectangle(x + width - 73, y + 27, 68, 43, colors.text)
  centered(x + width - 73, y + 34, 68, "ZOOM", SMLSIZE + BOLD + zoomText)
  centered(x + width - 73, y + 50, 68, "Z" .. tostring(level), SMLSIZE + BOLD + zoomText)
  lcd.drawFilledRectangle(x + 2, y + height - 17, 78, 15, lcd.RGB(245, 245, 235))
  lcd.drawText(x + 4, y + height - 16, "(c) swisstopo", SMLSIZE + colors.text)
end

local function radialPoint(cx, cy, radius, sector, value, maxV)
  local angle = ((sector - 1) / SECTORS * 360 - 90) * DEG
  local normalized = clamp((value + 2) / (maxV + 2), 0, 1)
  local r = radius * (0.25 + 0.70 * normalized)
  return cx + math.cos(angle) * r, cy + math.sin(angle) * r
end

local function drawPolarLine(values, cx, cy, radius, maxV, color, variableColor, colors)
  local firstX, firstY, lastX, lastY, firstValue
  for i = 1, SECTORS do
    local value = values[i]
    if value ~= nil then
      local px, py = radialPoint(cx, cy, radius, i, value, maxV)
      if not firstX then firstX, firstY, firstValue = px, py, value end
      if lastX then
        local lineColor = color
        if variableColor then
          lineColor = value > 0.10 and colors.lift or (value < -0.10 and colors.sink or colors.neutral)
        end
        lcd.drawLine(lastX, lastY, px, py, SOLID, lineColor)
        lcd.drawLine(lastX + 1, lastY, px + 1, py, SOLID, lineColor)
      end
      lastX, lastY = px, py
    else
      lastX, lastY = nil, nil
    end
  end
  if firstX and lastX and values[1] ~= nil and values[SECTORS] ~= nil then
    local lineColor = color
    if variableColor then
      lineColor = firstValue > 0.10 and colors.lift or (firstValue < -0.10 and colors.sink or colors.neutral)
    end
    lcd.drawLine(lastX, lastY, firstX, firstY, SOLID, lineColor)
  end
end

local function drawThermal(w, cx, cy, radius, colors)
  centered(cx - radius, cy - radius - 22, radius * 2, "THERMIQUE", SMLSIZE + BOLD + colors.text)
  lcd.drawFilledCircle(cx, cy, radius, colors.wheelBg)
  lcd.drawCircle(cx, cy, radius, colors.text)
  lcd.drawCircle(cx, cy, radius * 0.25, colors.grid)
  lcd.drawCircle(cx, cy, radius * 0.60, colors.grid)

  for i = 1, SECTORS do
    local angle = ((i - 1) / SECTORS * 360 - 90) * DEG
    lcd.drawLine(cx + math.cos(angle) * radius * 0.20,
      cy + math.sin(angle) * radius * 0.20,
      cx + math.cos(angle) * radius * 0.95,
      cy + math.sin(angle) * radius * 0.95,
      SOLID, colors.grid)
  end

  lcd.drawText(cx - 3, cy - radius - 1, "N", SMLSIZE + colors.text)
  lcd.drawText(cx + radius - 9, cy - 4, "E", SMLSIZE + colors.text)
  lcd.drawText(cx - 3, cy + radius - 13, "S", SMLSIZE + colors.text)
  lcd.drawText(cx - radius + 2, cy - 4, "O", SMLSIZE + colors.text)

  drawPolarLine(w.previous, cx, cy, radius, w.options.VarioMax, colors.previous, false, colors)
  drawPolarLine(w.current, cx, cy, radius, w.options.VarioMax, colors.lift, true, colors)

  local bestSector, bestValue
  for i = 1, SECTORS do
    local v = w.current[i] or w.previous[i]
    if v ~= nil and (bestValue == nil or v > bestValue) then
      bestValue, bestSector = v, i
    end
  end
  if bestSector then
    local bx, by = radialPoint(cx, cy, radius, bestSector, bestValue, w.options.VarioMax)
    lcd.drawFilledCircle(bx, by, 4, colors.maximum)
  end

  local headingAngle = (w.heading - 90) * DEG
  local markerX = cx + math.cos(headingAngle) * (radius + 2)
  local markerY = cy + math.sin(headingAngle) * (radius + 2)
  lcd.drawFilledCircle(markerX, markerY, 4, colors.aircraft)

  local centerText = w.validVario and string.format("%+.1f", w.vspd) or "---"
  centered(cx - 32, cy - 11, 64, centerText, MIDSIZE + BOLD + colors.text)
  centered(cx - 25, cy + 13, 50, "m/s", SMLSIZE + colors.text)
end

local function drawTile(x, y, width, height, label, value, unit, colors)
  lcd.drawFilledRectangle(x, y, width, height, colors.tileBg)
  lcd.drawRectangle(x, y, width, height, colors.border)
  centered(x, y + 2, width, label, SMLSIZE + colors.text)
  centered(x, y + 19, width, value, MIDSIZE + BOLD + colors.text)
  centered(x, y + height - 14, width, unit, SMLSIZE + colors.text)
end

local function formatDistance(meters)
  if meters >= 1000 then return string.format("%.1f", meters / 1000), "km" end
  return tostring(round(meters)), "m"
end

local function formatRaceTime(seconds)
  if seconds == nil then return "--:--" end
  seconds = math.max(0, math.floor(seconds + 0.5))
  local minutes = math.floor(seconds / 60)
  return string.format("%d:%02d", minutes, seconds % 60)
end

local function drawFullScreen(w)
  local colors = {
    mapBg = lcd.RGB(250, 248, 207),
    wheelBg = lcd.RGB(255, 255, 244),
    tileBg = lcd.RGB(250, 249, 231),
    grid = lcd.RGB(190, 194, 184),
    border = lcd.RGB(8, 31, 65),
    text = lcd.RGB(5, 28, 61),
    track = lcd.RGB(0, 190, 210),
    home = lcd.RGB(15, 62, 112),
    aircraft = lcd.RGB(4, 25, 60),
    lift = lcd.RGB(40, 190, 30),
    sink = lcd.RGB(225, 25, 30),
    neutral = lcd.RGB(100, 105, 105),
    previous = lcd.RGB(0, 185, 205),
    maximum = lcd.RGB(255, 220, 0),
    triangle = lcd.RGB(255, 225, 0),
    point = lcd.RGB(30, 110, 230),
    activePoint = lcd.RGB(235, 55, 35)
  }

  local width, height = LCD_W, LCD_H
  local tileH = 62
  local mapH = height - tileH
  drawMap(w, 0, 0, 315, mapH, colors)
  lcd.drawFilledRectangle(315, 0, width - 315, mapH, colors.mapBg)
  drawThermal(w, 398, 108, 72, colors)

  if not w.validGPS then
    centered(55, 84, 205, "GPS INVALIDE", MIDSIZE + BOLD + colors.sink)
  elseif w.pendingHome then
    centered(55, 84, 205, "ATTENTE HOME", MIDSIZE + BOLD + colors.text)
  end

  local runningTime = (w.raceState >= 1 and w.raceState <= 3) and timerValue(w) or w.raceTotal
  local values = {
    { "VARIO", w.validVario and string.format("%+.1f", w.vspd) or "---", "m/s" },
    { "ALT", w.validVario and tostring(round(w.alt)) or "---", "m" },
    { "V.SOL", w.validGPS and tostring(round(w.gspd)) or "---", "km/h" },
    { "PASSAGE B", formatRaceTime(w.splitB), "depuis A" },
    { "PASSAGE C", formatRaceTime(w.splitC), "depuis A" },
    { w.raceState == 4 and "TOTAL" or "CHRONO", formatRaceTime(runningTime),
      w.raceState == 0 and "attente A" or (w.raceState == 4 and "termine" or "en cours") }
  }
  local tileW = width / 6
  for i = 1, 6 do
    drawTile((i - 1) * tileW, mapH, tileW, tileH,
      values[i][1], values[i][2], values[i][3], colors)
  end
end

local function drawCompact(w)
  local z = w.zone
  local bg = lcd.RGB(250, 248, 207)
  local textColor = lcd.RGB(5, 28, 61)
  lcd.drawFilledRectangle(z.x, z.y, z.w, z.h, bg)
  lcd.drawRectangle(z.x, z.y, z.w, z.h, textColor)
  local textX, textW = z.x, z.w
  if w.logo and z.w >= 180 and z.h >= 72 then
    lcd.drawBitmap(w.logo, z.x + 5, z.y + math.max(4, (z.h - 64) / 2))
    textX, textW = z.x + 70, z.w - 72
  end
  centered(textX, z.y + z.h * 0.18, textW, "THERMAL", DBLSIZE + BOLD + textColor)
  centered(textX, z.y + z.h * 0.52, textW, "Ouvrir en plein ecran", SMLSIZE + textColor)
  local status = w.validGPS and ("GPS " .. tostring(round(w.sats))) or "GPS ---"
  centered(textX, z.y + z.h * 0.70, textW, status, SMLSIZE + textColor)
end

local function placePointFromTouch(w, screenX, screenY)
  local size = MAP_SIZES[w.zoom]
  local anchorX, anchorY = 315 * 0.50, 210 * 0.667
  local area = w.mapDef.area
  local aircraftWorldX = size * 0.5 + w.mapX / area * size
  local aircraftWorldY = size * (2 / 3) - w.mapY / area * size
  local worldX = aircraftWorldX - anchorX + screenX
  local worldY = aircraftWorldY - anchorY + screenY
  local east = (worldX - size * 0.5) / size * area
  local north = (size * (2 / 3) - worldY) / size * area
  local lat, lon = mapLocalToGPS(w, east, north)
  local p = w.points[w.editPoint]
  p.lat, p.lon = lat, lon
  saveTriangle(w)
  w.editPoint = w.editPoint < 3 and w.editPoint + 1 or 0
end

local function handleFullScreenEvent(w, event, touchState)
  if (event == EVT_TOUCH_FIRST or event == EVT_TOUCH_TAP) and touchState
    and getTime() - w.lastTouchAt > 30 then
    w.lastTouchAt = getTime()
    local tx, ty = touchState.x, touchState.y
    if tx >= 242 and tx <= 310 and ty >= 27 and ty <= 70 then
      w.zoomEdit = not w.zoomEdit
    end
  elseif w.zoomEdit and (event == EVT_VIRTUAL_INC or event == EVT_VIRTUAL_INC_REPT
    or event == EVT_VIRTUAL_NEXT or event == EVT_VIRTUAL_NEXT_REPT) then
    w.zoom = math.min(4, w.zoom + 1)
    w.mapCacheLevel = 0
  elseif w.zoomEdit and (event == EVT_VIRTUAL_DEC or event == EVT_VIRTUAL_DEC_REPT
    or event == EVT_VIRTUAL_PREV or event == EVT_VIRTUAL_PREV_REPT) then
    w.zoom = math.max(1, w.zoom - 1)
    w.mapCacheLevel = 0
  end
end

local function refresh(w, event, touchState)
  process(w)
  -- En plein ecran EdgeTX fournit event (0 si aucune touche). Dans une case
  -- normale event et touchState valent nil.
  if event ~= nil or (w.zone.w >= LCD_W - 4 and w.zone.h >= LCD_H - 4) then
    handleFullScreenEvent(w, event, touchState)
    drawFullScreen(w)
  else
    drawCompact(w)
  end
end

local function background(w)
  process(w)
end

return {
  name = NAME,
  options = options,
  create = create,
  update = update,
  refresh = refresh,
  background = background
}
