-- toolName = TNS|Reglages Triangle|TNE
-- Configuration separee du triangle THERMAL - EdgeTX 2.11 / TX16S

local PI = math.pi
local DEG = PI / 180
local EARTH_R = 6371000
local TILE = 210
local LEGACY_SIZES = { 315, 630, 1260 }
local SIZES_480 = { 480, 960, 1920 }
local SIZES_800 = { 800, 1600, 3200 }
local SIZES = LEGACY_SIZES
local MAP_FOLDER = ""

local points
local maps = {}
local mapIndex = 1
local selected = 1
local zoom = 1
local cache = {}
local missing = {}
local cacheLevel = 0
local cacheCount = 0
local savedAt = nil
local savedMessage = "TRIANGLE ENREGISTRE"
local errorMessage = nil
local lastTouchAt = -100
local zoomEdit = false
local ui = {}

local function rect(x, y, w, h)
  return { x=x, y=y, w=w, h=h }
end

local function hit(r, x, y)
  return r and x >= r.x and x <= r.x + r.w
    and y >= r.y and y <= r.y + r.h
end

local function activeMap()
  return maps[mapIndex]
end

local function configureMapProfile()
  local profile = LCD_W > 500 and "800" or "480"
  local wantedSizes = LCD_W > 500 and SIZES_800 or SIZES_480
  local probe = "/WIDGETS/THERMAL/MAPS/" .. activeMap().slug
    .. "/" .. profile .. "/Z0/0_0.png"
  local file = io.open(probe, "r")
  if file then
    io.close(file)
    MAP_FOLDER = profile .. "/"
    SIZES = wantedSizes
    TILE = profile == "800" and 400 or 210
  else
    MAP_FOLDER = ""
    SIZES = LEGACY_SIZES
    TILE = 210
  end
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

local function updateLayout()
  local width, height = LCD_W, LCD_H
  local mapW
  if width <= 500 then mapW = 315 else mapW = math.floor(width * 0.66) end
  mapW = clamp(mapW, 315, width - 165)
  ui.width, ui.height = width, height
  ui.mapW, ui.mapH = mapW, height
  ui.panelX, ui.panelW = mapW, width - mapW
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
  local p = points[selected]
  local east, north = 0, 0
  if p.lat and p.lon then east, north = toLocal(p.lat, p.lon) end
  local area = activeMap().area
  local wx = size * 0.5 + east / area * size
  local wy = size * (2 / 3) - north / area * size
  return size, wx - ui.mapW * 0.5, wy - ui.mapH * 0.5
end

local function drawMap()
  local size, left, top = viewPosition()
  lcd.drawFilledRectangle(0, 0, ui.mapW, ui.mapH, lcd.RGB(35, 50, 40))
  local firstCol, lastCol = math.floor(left / TILE), math.floor((left + ui.mapW) / TILE)
  local firstRow, lastRow = math.floor(top / TILE), math.floor((top + ui.mapH) / TILE)
  local maxTile = math.ceil(size / TILE) - 1
  if cacheLevel ~= zoom then
    cache = {}
    missing = {}
    cacheLevel = zoom
    cacheCount = 0
    collectgarbage("collect")
  end
  local visible = {}
  for row = firstRow, lastRow do
    for col = firstCol, lastCol do
      if row >= 0 and col >= 0 and row <= maxTile and col <= maxTile then
        visible[tostring(col) .. "_" .. tostring(row)] = true
      end
    end
  end
  for key in pairs(cache) do
    if not visible[key] then cache[key] = nil end
  end
  cacheCount = 0
  for _ in pairs(cache) do cacheCount = cacheCount + 1 end
  local newLoads = 0
  local missingFiles = 0
  local loadingFiles = 0
  for row = firstRow, lastRow do
    for col = firstCol, lastCol do
      if row >= 0 and col >= 0 and row <= maxTile and col <= maxTile then
        local tileKey = tostring(col) .. "_" .. tostring(row)
        if not cache[tileKey] and not missing[tileKey] and newLoads < 1 then
          local path = "/WIDGETS/THERMAL/MAPS/" .. activeMap().slug
            .. "/" .. MAP_FOLDER .. "Z" .. tostring(zoom - 1) .. "/" .. tileKey .. ".png"
          local file = io.open(path, "r")
          if file then
            io.close(file)
            cache[tileKey] = Bitmap.open(path)
            cacheCount = cacheCount + 1
            newLoads = newLoads + 1
          else
            missing[tileKey] = true
          end
        end
        if cache[tileKey] then
          lcd.drawBitmap(cache[tileKey], col * TILE - left, row * TILE - top)
        elseif missing[tileKey] then
          missingFiles = missingFiles + 1
        else
          loadingFiles = loadingFiles + 1
        end
      end
    end
  end
  if loadingFiles > 0 and missingFiles == 0 then
    lcd.drawFilledRectangle(0, 0, ui.mapW, ui.mapH, lcd.RGB(35, 50, 40))
    centered(0, ui.mapH * 0.43, ui.mapW,
      "CHARGEMENT Z" .. tostring(zoom), MIDSIZE + BOLD + WHITE)
    return
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
  lcd.drawFilledRectangle(3, ui.mapH - 22, 144, 19, lcd.RGB(245, 245, 235))
  lcd.drawText(6, ui.mapH - 20, "Z" .. tostring(zoom) .. "  (c) swisstopo", SMLSIZE + lcd.RGB(5, 28, 61))
  if missingFiles > 0 then
    lcd.drawFilledRectangle(155, ui.mapH - 22, 150, 19, lcd.RGB(205, 30, 35))
    centered(155, ui.mapH - 20, 150, "TUILES ABSENTES", (TINSIZE or 0) + WHITE)
  elseif MAP_FOLDER == "" and LCD_W > 500 then
    lcd.drawFilledRectangle(155, ui.mapH - 22, 180, 19, lcd.RGB(255, 220, 0))
    centered(155, ui.mapH - 20, 180, "CARTE A REGENERER",
      (TINSIZE or 0) + lcd.RGB(5, 28, 61))
  end
end

local function drawButton(x, y, width, height, label, fill, textColor)
  local font = TINSIZE or 0
  local _, textH = lcd.sizeText(label, font)
  lcd.drawFilledRectangle(x, y, width, height, fill)
  lcd.drawRectangle(x, y, width, height, lcd.RGB(5, 28, 61))
  centered(x, y + math.max(1, math.floor((height - textH) / 2)), width,
    label, font + textColor)
end

local function drawPanel()
  local navy, white = lcd.RGB(5, 28, 61), WHITE
  local pale, blue = lcd.RGB(242, 244, 236), lcd.RGB(35, 105, 180)
  local x, width, height = ui.panelX, ui.panelW, ui.height
  local pad = clamp(math.floor(width * 0.025), 4, 8)
  local innerX, innerW = x + pad, width - pad * 2
  local mapButtonH = height <= 300 and 24 or 38
  local pointsY = mapButtonH + pad * 2
  local pointH = height <= 300 and 32 or 44
  local pointGap = pad
  local pointW = (innerW - pointGap * 2) / 3
  local bottomH = height <= 300 and 34 or 46
  local bottomY = height - bottomH - pad
  local zoomH = height <= 300 and 32 or 46
  local zoomY = bottomY - zoomH - pad * 2
  local rowsTop = pointsY + pointH + pad * 2
  local rowsBottom = zoomY - pad
  local rowStep = (rowsBottom - rowsTop) / 3
  local adjustW = clamp(math.floor(innerW * 0.17), 27, 44)
  local adjustH = clamp(math.floor(rowStep * 0.66), 30, 42)
  local valueX = innerX + math.floor(innerW * 0.32)
  local valueW = innerW - (valueX - innerX) - adjustW * 2 - pad * 2

  lcd.drawFilledRectangle(x, 0, width, height, pale)
  ui.mapButton = rect(innerX, pad, innerW, mapButtonH)
  drawButton(ui.mapButton.x, ui.mapButton.y, ui.mapButton.w, ui.mapButton.h,
    "CARTE: " .. activeMap().label, blue, white)
  ui.pointButtons = {}
  for i = 1, 3 do
    local bx = innerX + (i - 1) * (pointW + pointGap)
    ui.pointButtons[i] = rect(bx, pointsY, pointW, pointH)
    drawButton(bx, pointsY, pointW, pointH, points[i].name,
      i == selected and lcd.RGB(235, 55, 35) or blue, white)
  end
  local p = points[selected]
  local rows = {
    { label="Rayon", value=tostring(math.floor(p.radius + 0.5)) .. " m" },
    { label="Alt min", value=tostring(math.floor(p.minAlt + 0.5)) .. " m" },
    { label="Alt max", value=tostring(math.floor(p.maxAlt + 0.5)) .. " m" }
  }
  ui.minusButtons, ui.plusButtons = {}, {}
  for i, row in ipairs(rows) do
    local rowY = rowsTop + (i - 1) * rowStep
    local buttonY = rowY + (rowStep - adjustH) * 0.5
    local plusX = innerX + innerW - adjustW
    local minusX = plusX - pad - adjustW
    local rowFont = TINSIZE or 0
    local _, rowTextH = lcd.sizeText(row.label, rowFont)
    local textY = rowY + math.max(0, (rowStep - rowTextH) * 0.5)
    lcd.drawText(innerX, textY, row.label, rowFont + navy)
    centered(valueX, textY, valueW, row.value, rowFont + navy)
    ui.minusButtons[i] = rect(minusX, buttonY, adjustW, adjustH)
    ui.plusButtons[i] = rect(plusX, buttonY, adjustW, adjustH)
    drawButton(minusX, buttonY, adjustW, adjustH, "-", blue, white)
    drawButton(plusX, buttonY, adjustW, adjustH, "+", blue, white)
  end
  ui.zoomButton = rect(innerX, zoomY, innerW, zoomH)
  drawButton(innerX, zoomY, innerW, zoomH,
    zoomEdit and ("ZOOM ACTIF  Z" .. tostring(zoom)) or ("ZOOM  Z" .. tostring(zoom)),
    zoomEdit and lcd.RGB(235, 55, 35) or blue, white)
  local actionGap = pad * 2
  local actionW = (innerW - actionGap) / 2
  ui.clearButton = rect(innerX, bottomY, actionW, bottomH)
  ui.saveButton = rect(innerX + actionW + actionGap, bottomY, actionW, bottomH)
  drawButton(ui.clearButton.x, ui.clearButton.y, ui.clearButton.w, ui.clearButton.h,
    "EFFACER", lcd.RGB(205, 30, 35), white)
  drawButton(ui.saveButton.x, ui.saveButton.y, ui.saveButton.w, ui.saveButton.h,
    "SAUVER", lcd.RGB(20, 145, 70), white)
end

local function drawScreen()
  updateLayout()
  drawMap()
  drawPanel()
  if savedAt then
    local boxW, boxH = ui.width * 0.68, clamp(ui.height * 0.28, 75, 120)
    local boxX, boxY = (ui.width - boxW) / 2, (ui.height - boxH) / 2
    lcd.drawFilledRectangle(boxX, boxY, boxW, boxH, lcd.RGB(20, 145, 70))
    centered(boxX, boxY + boxH * 0.36, boxW, savedMessage, SMLSIZE + WHITE)
  elseif errorMessage then
    local boxW, boxH = ui.width * 0.68, clamp(ui.height * 0.28, 75, 120)
    local boxX, boxY = (ui.width - boxW) / 2, (ui.height - boxH) / 2
    lcd.drawFilledRectangle(boxX, boxY, boxW, boxH, lcd.RGB(205, 30, 35))
    centered(boxX, boxY + boxH * 0.36, boxW, errorMessage, SMLSIZE + WHITE)
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
  updateLayout()
  if LCD_W > 500 then zoom = 2 end
  loadMaps()
  loadPoints()
  if not loadMapSelection() then chooseNearestMap() end
  configureMapProfile()
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
    if x < ui.mapW then
      placePoint(x, y)
    elseif hit(ui.mapButton, x, y) then
      mapIndex = mapIndex % #maps + 1
      saveMapSelection()
      configureMapProfile()
      cache = {}
      missing = {}
      cacheLevel = 0
      cacheCount = 0
    elseif hit(ui.pointButtons[1], x, y) then selected = 1
    elseif hit(ui.pointButtons[2], x, y) then selected = 2
    elseif hit(ui.pointButtons[3], x, y) then selected = 3
    elseif hit(ui.minusButtons[1], x, y) then adjust(1, -1)
    elseif hit(ui.plusButtons[1], x, y) then adjust(1, 1)
    elseif hit(ui.minusButtons[2], x, y) then adjust(2, -1)
    elseif hit(ui.plusButtons[2], x, y) then adjust(2, 1)
    elseif hit(ui.minusButtons[3], x, y) then adjust(3, -1)
    elseif hit(ui.plusButtons[3], x, y) then adjust(3, 1)
    elseif hit(ui.zoomButton, x, y) then
      zoomEdit = not zoomEdit
    elseif hit(ui.clearButton, x, y) then
      points = { newPoint("A"), newPoint("B"), newPoint("C") }
      savePoints("POINTS A-B-C EFFACES")
    elseif hit(ui.saveButton, x, y) then
      saveMapSelection()
      savePoints()
    end
  elseif event == EVT_VIRTUAL_EXIT then
    return 1
  elseif event == EVT_VIRTUAL_MENU then
    savePoints()
  elseif zoomEdit and (event == EVT_VIRTUAL_INC or event == EVT_VIRTUAL_INC_REPT
    or event == EVT_VIRTUAL_NEXT or event == EVT_VIRTUAL_NEXT_REPT) then
    zoom = math.min(3, zoom + 1)
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
