local mq = require('mq')

local adapter = {}

---@param value any
---@param fallback number
---@return number
local function asNumber(value, fallback)
  local n = tonumber(value)
  if n == nil then
    return fallback
  end
  return n
end

---@param value any
---@param fallback string
---@return string
local function asString(value, fallback)
  if type(value) == 'string' then
    return value
  end
  return fallback
end

---@param value any
---@return boolean
local function containsFear(value)
  if type(value) ~= 'table' then
    return false
  end

  for _, state in ipairs(value) do
    if type(state) == 'string' and string.find(string.upper(state), 'FEAR', 1, true) then
      return true
    end
  end

  return false
end

---@param peer table
---@return string
local function runningScripts(peer)
  if not peer or not peer.Lua or not peer.Lua.Scripts then
    return ''
  end

  local scriptNames = {}
  for _, script in ipairs(peer.Lua.Scripts) do
    if script and type(script.Name) == 'string' and script.Name ~= 'hud/pids' then
      table.insert(scriptNames, script.Name)
    end
  end

  local names = table.concat(scriptNames, ';')
  if names:len() > 200 then
    names = names:sub(1, 198) .. '++'
  end
  return names
end

---@param spellId number
---@return string|nil
local function castingSpellName(spellId)
  if spellId <= 0 then
    return nil
  end

  local spell = mq.TLO.Spell(spellId)
  if spell and spell() then
    return spell.Name()
  end

  return nil
end

---@param peer table
---@return table
function adapter.ToHUDInfo(peer)
  local zone = peer and peer.Zone or nil
  local target = peer and peer.Target or nil
  local exp = peer and peer.Experience or nil

  local countPoison = asNumber(peer and peer.CountPoison or nil, 0)
  local countDisease = asNumber(peer and peer.CountDisease or nil, 0)
  local countCurse = asNumber(peer and peer.CountCurse or nil, 0)
  local countCorruption = asNumber(peer and peer.CountCorruption or nil, 0)
  local castingSpellID = asNumber(peer and peer.CastingSpellID or nil, 0)

  local inRaid = mq.TLO.Raid.Members() and mq.TLO.Raid.Members() > 0
  local grouped = mq.TLO.Me.Grouped() or false

  return {
    Id = asNumber(peer and peer.ID or nil, 0),
    Name = asString(peer and peer.Name or nil, ''),
    PctHPs = asNumber(peer and peer.PctHPs or nil, 0),
    PctMana = asNumber(peer and peer.PctMana or nil, 0),
    MaxMana = asNumber(peer and peer.MaxMana or nil, 0),
    TargetId = target and asNumber(target.ID, 0) > 0 and asNumber(target.ID, 0) or nil,
    Level = asNumber(peer and peer.Level or nil, 0),
    PctExp = exp and asNumber(exp.PctExp, 100) or 100,
    PetPctHPs = asNumber(peer and peer.PetHP or nil, 0),
    Casting = castingSpellName(castingSpellID),
    ZoneShortName = asString(zone and zone.ShortName or nil, ''),
    InstanceId = asNumber(zone and zone.InstanceID or nil, 0),
    HasCounters = (countPoison + countDisease + countCurse + countCorruption) > 0,
    IsFeared = containsFear(peer and peer.State or nil),
    IsInRaid = inRaid,
    IsGrouped = grouped,
    RunningScripts = runningScripts(peer),
    LastUpdated = mq.gettime(),
  }
end

return adapter
