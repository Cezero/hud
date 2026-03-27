local mq = require('mq')
local logger = require('knightlinc.Write')

local function isArray(t)
  local i = 0
  for _ in pairs(t) do
    i = i + 1
    if t[i] == nil then return false end
  end
  return true
end

local function iterator(table)
  if isArray(table) then
    return ipairs(table)
  end

  return pairs(table)
end

---@param node table
local function toString(node)
  local cache, stack, output = {},{},{}
  local depth = 1
  local output_str = "return {\n"

  while true do
    local size = 0
    for k,v in iterator(node) do
      size = size + 1
    end

    local cur_index = 1
    for k,v in iterator(node) do
      if (cache[node] == nil) or (cur_index >= cache[node]) then
        if (string.find(output_str,"}",output_str:len())) then
          output_str = output_str .. ",\n"
        elseif not (string.find(output_str,"\n",output_str:len())) then
          output_str = output_str .. "\n"
        end

        -- This is necessary for working with HUGE tables otherwise we run out of memory using concat on huge strings
        table.insert(output,output_str)
        output_str = ""

        local key
        if (type(k) == "number" or type(k) == "boolean") then
          key = "["..tostring(k).."]"
        else
          key = "['"..tostring(k).."']"
        end

        if (type(v) == "number" or type(v) == "boolean") then
          output_str = output_str .. string.rep('\t',depth) .. key .. " = "..tostring(v)
        elseif (type(v) == "table") then
          output_str = output_str .. string.rep('\t',depth) .. key .. " = {\n"
          table.insert(stack,node)
          table.insert(stack,v)
          cache[node] = cur_index+1
          break
        else
          output_str = output_str .. string.rep('\t',depth) .. key .. " = '"..tostring(v).."'"
        end

        if (cur_index == size) then
          output_str = output_str .. "\n" .. string.rep('\t',depth-1) .. "}"
        else
          output_str = output_str .. ","
        end
      else
        -- close the table
        if (cur_index == size) then
          output_str = output_str .. "\n" .. string.rep('\t',depth-1) .. "}"
        end
      end

      cur_index = cur_index + 1
    end

    if (size == 0) then
      output_str = output_str .. "\n" .. string.rep('\t',depth-1) .. "}"
    end

    if (#stack > 0) then
      node = stack[#stack]
      stack[#stack] = nil
      depth = cache[node] == nil and depth + 1 or depth - 1
    else
      break
    end
  end

  -- This is necessary for working with HUGE tables otherwise we run out of memory using concat on huge strings
  table.insert(output,output_str)
  output_str = table.concat(output)

  return output_str
end

---@generic T : table
---@param default T
---@param loaded T
---@return T
local function leftJoin(default, loaded)
  local config = {}
  for key, value in pairs(default) do
    config[key] = value
    local loadedValue = loaded[key]
    if type(value) == "table" then
      if type(loadedValue or false) == "table" then
        if next(value) then
          config[key] = leftJoin(default[key] or {}, loadedValue or {})
        else
          config[key] = loadedValue
        end
      end
    elseif type(value) == type(loadedValue) then
      config[key] = loadedValue
    end
  end

  return config
end

---@alias LayoutTypes 1|2|3

---@class UISettings
---@field locked boolean
---@field showNavBar boolean
---@field layoutType LayoutTypes
---@field scale number
---@field opacity number

---@class HUDSettings
---@field groups table
---@field update_frequency number
---@field stale_data_timer number
---@field loglevel string
---@field ui UISettings
local settings = {
  groups = {},
  loglevel = 'info',
  update_frequency = 300,
  stale_data_timer = 0.1,
  ui = {
    locked = true,
    showNavBar = false,
    layoutType = 1,
    scale = 1.0,
    opacity = 0.3
  }
}

---@param filePath string
---@return boolean
local function fileExists(filePath)
  local f = io.open(filePath, "r")
  if f ~= nil then io.close(f) return true else return false end
end

---@param filePath string
---@return table
local function loadConfig (filePath)
  local loaded, err = loadfile(filePath)
  if not loaded then
    logger.Error("Unable to load config '%s': %s", filePath, tostring(err))
    return {}
  end

  local ok, result = pcall(loaded)
  if not ok then
    logger.Error("Config execution failed for '%s': %s", filePath, tostring(result))
    return {}
  end

  if type(result) ~= "table" then
    logger.Error("Config '%s' did not return a table", filePath)
    return {}
  end

  return result
end

-- https://stackoverflow.com/questions/295052/how-can-i-determine-the-os-of-the-system-from-within-a-lua-script
local pathSep = package.config:sub(1,1)
local configDir = mq.configDir
local serverName = mq.TLO.MacroQuest.Server()
local configFilePath = string.format("%s/hud/%s/%s", configDir, serverName, "settings.lua")
if pathSep ~= "/" then
  configFilePath = configFilePath:gsub("/", "\\")
end

if fileExists(configFilePath) then
  logger.Info("Loading config from '%s'", configFilePath)
  local loadedSettings = loadConfig(configFilePath)
  settings = leftJoin(settings, loadedSettings)
end

---@param filePath string
---@return string
local function directoryFromPath(filePath)
  local i = filePath:match("^.*()[/\\]")
  if i then
    return filePath:sub(1, i - 1)
  end
  return "."
end

---@param dirPath string
---@return boolean
local function directoryExists(dirPath)
  local ok, _, code = os.rename(dirPath, dirPath)
  if ok then
    return true
  end

  -- Permission denied can still mean the path exists.
  return code == 13
end

---@param dirPath string
---@return boolean
local function ensureDirectory(dirPath)
  if directoryExists(dirPath) then
    return true
  end

  local normalizedDir = dirPath:gsub("[/\\]", pathSep)
  local segments = {}
  for segment in normalizedDir:gmatch("[^/\\]+") do
    table.insert(segments, segment)
  end

  local currentPath = ""
  local drive = normalizedDir:match("^([A-Za-z]:)")
  local startIndex = 1
  if drive then
    currentPath = drive .. pathSep
    startIndex = 2
  elseif normalizedDir:sub(1, 1) == pathSep then
    currentPath = pathSep
  end

  for i = startIndex, #segments do
    local segment = segments[i]
    if currentPath == "" or currentPath:sub(-1) == pathSep then
      currentPath = currentPath .. segment
    else
      currentPath = currentPath .. pathSep .. segment
    end

    if not directoryExists(currentPath) then
      local cmd
      if pathSep == "\\" then
        cmd = string.format('mkdir "%s" >nul 2>nul', currentPath)
      else
        cmd = string.format('mkdir -p "%s" >/dev/null 2>&1', currentPath)
      end
      os.execute(cmd)

      if not directoryExists(currentPath) then
        return false
      end
    end
  end

  return directoryExists(dirPath)
end

local function saveConfig(newSettings)
  local configDirPath = directoryFromPath(configFilePath)
  if not ensureDirectory(configDirPath) then
    logger.Error("Unable to create HUD config directory: '%s'", configDirPath)
    return false
  end

  local file, err = io.open(configFilePath, "w")
  if not file then
    logger.Error("Unable to open HUD config for write '%s': %s", configFilePath, tostring(err))
    return false
  end

  file:write(toString(newSettings))
  file:close()
  settings = newSettings
  return true
end

return {
  LoadConfig = function() return settings end,
  SaveConfig = saveConfig
}