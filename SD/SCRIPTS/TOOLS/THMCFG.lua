-- toolName = TNS|Reglages Triangle|TNE
-- Configuration separee du triangle THERMAL - EdgeTX 2.11 / TX16S

local PI = math.pi
local DEG = PI / 180
local EARTH_R = 6371000
local TILE = 210
local SIZES = { 315, 630, 1260, 2520 }

local points
local maps = {}
local mapIndex = 1
local selected = 1
local zoom = 1
local cache = {}
local cacheLevel = 0
local cacheCount = 0
local savedAt = nil
local savedMessage = "TRIANGLE ENREGISTRE"
local errorMessage = nil
local lastTouchAt = -100
local zoomEdit = false

local function activeMap()
  return maps[mapIndex]
end

local function loadMaps()
  maps = {}
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
  if #maps == 0 then
    maps[1] = { slug="", label="CARTE ABSENTE", lat=46.2949984,
      lon=6.9727851, area=5000, cos=math.cos(46.2949984 * DEG) }
  end
end

local function clamp(v, lo, hi)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

local function centered(x, y, width, value, flags)
  local tw = lcd.sizeText(value, flags)
  lcd.drawText(x + (width - tw) / 2, y, value, flags)
end

local function path()
  local info = model.getInfo()
  local name = info and info.name or "default"
  name = string.sub(string.gsub(name, "[^%w%-%_]", "_"), 1, 12)
  if name == "" then name = "default" end
  return "/WIDGETS/THERMAL/" .. name .. ".tri"
end

local function mapPath()
  return string.gsub(path(), "%.tri$", ".map")
end

local function saveMapSelection()
  local file = io.open(mapPath(), "w")
  if not file then return end
  io.write(file, activeMap().slug)
  io.close(file)
end

local function loadMapSelection()
  local file = io.open(mapPath(), "r")
  if not file then return false end
  local slug = io.read(file, 32)
  io.close(file)
  for i = 1, #maps do
    if maps[i].slug == slug then mapIndex = i return true end
  end
  return false
end

local function newPoint(name)
  return { name=name, lat=nil, lon=nil, radius=100, minAlt=0, maxAlt=1000 }
end

local function loadPoints()
  points = { newPoint("A"), newPoint("B"), newPoint("C") }
  local file = io.open(path(), "r")
  if not file then return end
  local data = io.read(file, 512)
  io.close(file)
  local n = 0
  for line in string.gmatch(data or "", "[^\r\n]+") do
    n = n + 1
    if n <= 3 then
      local v = {}
      for item in string.gmatch(line, "[^,]+") do v[#v + 1] = tonumber(item) end
      if #v == 5 and v[1] ~= 0 and v[2] ~= 0 then
        points[n].lat, points[n].lon, points[n].radius,
          points[n].minAlt, points[n].maxAlt = v[1], v[2], v[3], v[4], v[5]
      end
    end
  end
end

local function savePoints(message)
  local file = io.open(path(), "w")
  if not file then
    errorMessage = "ERREUR CARTE SD"
    return
  end
  for i = 1, 3 do
    local p = points[i]
    if p.lat and p.lon then
      io.write(file, string.format("%.7f,%.7f,%.0f,%.1f,%.1f",
        p.lat, p.lon, p.radius, p.minAlt, p.maxAlt))
    else
      io.write(file, "0,0,100,0,1000")
    end
    if i < 3 then io.write(file, "\n") end
  end
  io.close(file)
  savedMessage = message or "TRIANGLE ENREGISTRE"
  savedAt = getTime()
  errorMessage = nil
end

local function toLocal(lat, lon)
  local m = activeMap()
  return (lon - m.lon) * DEG * EARTH_R * m.cos,
    (lat - m.lat) * DEG * EARTH_R
end

local function toGPS(east, north)
  local m = activeMap()
  return m.lat + north / EARTH_R / DEG,
    m.lon + east / (EARTH_R * m.cos) / DEG
end

local function chooseNearestMap()
  local lat, lon
  if points and points[1] and points[1].lat then
    lat, lon = points[1].lat, points[1].lon
  else
    local gps = getValue("GPS")
    if type(gps) == "table" then lat, lon = gps.lat, gps.lon end
  end
  if not lat or not lon then return end
  local best, bestD = 1, nil
  for i = 1, #maps do
    local east = (lon - maps[i].lon) * DEG * EARTH_R * maps[i].cos
    local north = (lat - maps[i].lat) * DEG * EARTH_R
    local d = east * east + north * north
    if not bestD or d < bestD then best, bestD = i, d end
  end
  mapIndex = best
end

local function viewPosition()
  local size = SIZES[zoom]
  if zoom == 1 then return size, 0, 0 end
  local p = points[selected]
  local east, north = 0, 0
  if p.lat and p.lon then east, north = toLocal(p.lat, p.lon) end
  local area = activeMap().area
  local wx = size * 0.5 + east / area * size
  local wy = size * (2 / 3) - north / area * size
  return size, wx - 157.5, wy - 136
end

local function drawMap()
  local size, left, top = viewPosition()
  lcd.drawFilledRectangle(0, 0, 315, 272, lcd.RGB(35, 50, 40))
  local firstCol, lastCol = math.floor(left / TILE), math.floor((left + 315) / TILE)
  local firstRow, lastRow = math.floor(top / TILE), math.floor((top + 272) / TILE)
  local maxTile = math.ceil(size / TILE) - 1
  if cacheLevel ~= zoom then
    cache = {}
    cacheLevel = zoom
    cacheCount = 0
  end
  for row = firstRow, lastRow do
    for col = firstCol, lastCol do
      if row >= 0 and col >= 0 and row <= maxTile and col <= maxTile then
        local tileKey = tostring(col) .. "_" .. tostring(row)
        if not cache[tileKey] then
          if cacheCount >= 16 then
            cache = {}
            cacheCount = 0
          end
          cache[tileKey] = Bitmap.open("/WIDGETS/THERMAL/MAPS/" .. activeMap().slug
            .. "/Z" .. tostring(zoom - 1) .. "/" .. tileKey .. ".png")
          cacheCount = cacheCount + 1
        end
        lcd.drawBitmap(cache[tileKey], col * TILE - left, row * TILE - top)
      end
    end
  end

  local screen = {}
  for i = 1, 3 do
    local p = points[i]
    if p.lat and p.lon then
      local east, north = toLocal(p.lat, p.lon)
      screen[i] = {
        size * 0.5 + east / activeMap().area * size - left,
        size * (2 / 3) - north / activeMap().area * size - top
      }
    end
  end
  for i = 1, 3 do
    local j = i % 3 + 1
    if screen[i] and screen[j] then
      lcd.drawLine(screen[i][1], screen[i][2], screen[j][1], screen[j][2], SOLID, lcd.RGB(255, 225, 0))
      lcd.drawLine(screen[i][1] + 1, screen[i][2], screen[j][1] + 1, screen[j][2], SOLID, lcd.RGB(255, 225, 0))
    end
  end
  for i = 1, 3 do
    if screen[i] then
      local color = i == selected and lcd.RGB(235, 55, 35) or lcd.RGB(25, 105, 225)
      local rp = math.max(3, points[i].radius / activeMap().area * size)
      lcd.drawCircle(screen[i][1], screen[i][2], rp, color)
      lcd.drawFilledCircle(screen[i][1], screen[i][2], 10, color)
      centered(screen[i][1] - 9, screen[i][2] - 6, 18, points[i].name, SMLSIZE + BOLD + WHITE)
    end
  end
  lcd.drawFilledRectangle(3, 250, 144, 19, lcd.RGB(245, 245, 235))
  lcd.drawText(6, 252, "Z" .. tostring(zoom) .. "  (c) swisstopo", SMLSIZE + lcd.RGB(5, 28, 61))
end

local function drawButton(x, y, width, height, label, fill, textColor)
  lcd.drawFilledRectangle(x, y, width, height, fill)
  lcd.drawRectangle(x, y, width, height, lcd.RGB(5, 28, 61))
  centered(x, y + math.floor((height - 18) / 2), width, label, SMLSIZE + BOLD + textColor)
end

local function drawPanel()
  local navy, white = lcd.RGB(5, 28, 61), WHITE
  local pale, blue = lcd.RGB(242, 244, 236), lcd.RGB(35, 105, 180)
  lcd.drawFilledRectangle(315, 0, 165, 272, pale)
  drawButton(319, 3, 157, 24, "CARTE: " .. activeMap().label, blue, white)
  for i = 1, 3 do
    drawButton(321 + (i - 1) * 52, 31, 46, 32, points[i].name,
      i == selected and lcd.RGB(235, 55, 35) or blue, white)
  end
  local p = points[selected]
  local rows = {
    { y=70, label="Rayon", value=tostring(math.floor(p.radius + 0.5)) .. " m" },
    { y=111, label="Alt min", value=tostring(math.floor(p.minAlt + 0.5)) .. " m" },
    { y=152, label="Alt max", value=tostring(math.floor(p.maxAlt + 0.5)) .. " m" }
  }
  for _, row in ipairs(rows) do
    lcd.drawText(321, row.y, row.label, SMLSIZE + navy)
    centered(365, row.y, 48, row.value, SMLSIZE + BOLD + navy)
    drawButton(416, row.y - 5, 27, 30, "-", blue, white)
    drawButton(447, row.y - 5, 27, 30, "+", blue, white)
  end
  drawButton(321, 193, 153, 32,
    zoomEdit and ("ZOOM ACTIF  Z" .. tostring(zoom)) or ("ZOOM  Z" .. tostring(zoom)),
    zoomEdit and lcd.RGB(235, 55, 35) or blue, white)
  drawButton(321, 233, 73, 34, "EFFACER", lcd.RGB(205, 30, 35), white)
  drawButton(400, 233, 74, 34, "SAUVER", lcd.RGB(20, 145, 70), white)
end

local function drawScreen()
  drawMap()
  drawPanel()
  if savedAt then
    lcd.drawFilledRectangle(75, 95, 330, 75, lcd.RGB(20, 145, 70))
    centered(75, 119, 330, savedMessage, MIDSIZE + BOLD + WHITE)
  elseif errorMessage then
    lcd.drawFilledRectangle(75, 95, 330, 75, lcd.RGB(205, 30, 35))
    centered(75, 119, 330, errorMessage, MIDSIZE + BOLD + WHITE)
  end
end

local function adjust(row, direction)
  local p = points[selected]
  if row == 1 then p.radius = clamp(p.radius + direction * 10, 10, 2000)
  elseif row == 2 then
    p.minAlt = clamp(p.minAlt + direction * 50, -1000, 10000)
    if p.minAlt > p.maxAlt then p.maxAlt = p.minAlt end
  elseif row == 3 then
    p.maxAlt = clamp(p.maxAlt + direction * 50, -1000, 10000)
    if p.maxAlt < p.minAlt then p.minAlt = p.maxAlt end
  end
end

local function placePoint(tx, ty)
  local size, left, top = viewPosition()
  local wx, wy = left + tx, top + ty
  local east = (wx - size * 0.5) / size * activeMap().area
  local north = (size * (2 / 3) - wy) / size * activeMap().area
  points[selected].lat, points[selected].lon = toGPS(east, north)
end

local function init()
  loadMaps()
  loadPoints()
  if not loadMapSelection() then chooseNearestMap() end
end

local function run(event, touchState)
  if savedAt then
    drawScreen()
    if getTime() - savedAt > 100 then return 1 end
    return 0
  end
  if (event == EVT_TOUCH_FIRST or event == EVT_TOUCH_TAP) and touchState
    and getTime() - lastTouchAt > 30 then
    lastTouchAt = getTime()
    local x, y = touchState.x, touchState.y
    if x < 315 then
      placePoint(x, y)
    elseif y >= 3 and y <= 27 then
      mapIndex = mapIndex % #maps + 1
      saveMapSelection()
      cache = {}
      cacheLevel = 0
      cacheCount = 0
    elseif y >= 31 and y <= 63 then
      if x >= 321 and x < 369 then selected = 1
      elseif x >= 373 and x < 421 then selected = 2
      elseif x >= 425 and x <= 474 then selected = 3 end
    elseif x >= 416 and x <= 474 then
      local direction = x >= 447 and 1 or -1
      if y >= 65 and y <= 95 then adjust(1, direction)
      elseif y >= 106 and y <= 136 then adjust(2, direction)
      elseif y >= 147 and y <= 177 then adjust(3, direction) end
    elseif x >= 321 and x <= 474 and y >= 193 and y <= 225 then
      zoomEdit = not zoomEdit
    elseif x >= 321 and x <= 394 and y >= 233 and y <= 267 then
      points = { newPoint("A"), newPoint("B"), newPoint("C") }
      savePoints("POINTS A-B-C EFFACES")
    elseif x >= 400 and x <= 474 and y >= 233 and y <= 267 then
      saveMapSelection()
      savePoints()
    end
  elseif event == EVT_VIRTUAL_EXIT then
    return 1
  elseif event == EVT_VIRTUAL_MENU then
    savePoints()
  elseif zoomEdit and (event == EVT_VIRTUAL_INC or event == EVT_VIRTUAL_INC_REPT
    or event == EVT_VIRTUAL_NEXT or event == EVT_VIRTUAL_NEXT_REPT) then
    zoom = math.min(4, zoom + 1)
    cacheLevel = 0
  elseif zoomEdit and (event == EVT_VIRTUAL_DEC or event == EVT_VIRTUAL_DEC_REPT
    or event == EVT_VIRTUAL_PREV or event == EVT_VIRTUAL_PREV_REPT) then
    zoom = math.max(1, zoom - 1)
    cacheLevel = 0
  end
  drawScreen()
  return 0
end

return { init=init, run=run }
