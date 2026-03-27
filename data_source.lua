local mq = require('mq')
local logger = require('knightlinc.Write')
local adapter = require('charinfo_adapter')

local charinfo = require('plugin.charinfo')

---@type table<string, HUDInfo>
local hudData = {}

---@param settings HUDSettings
local function cleanup(settings)
  for name, data in pairs(hudData) do
    if mq.gettime() - (data.LastUpdated or 0) > settings.stale_data_timer * 60000 then
      logger.Debug("Stale data for %s, last updated %s (ms) ago", name, mq.gettime() - (data.LastUpdated or 0))
      hudData[name] = nil
    end
  end
end

---@param settings HUDSettings
local function process(settings)
  cleanup(settings)

  if mq.TLO.EverQuest.GameState() ~= 'INGAME' then
    return
  end

  local peerNames = charinfo.GetPeers() or {}
  for _, name in ipairs(peerNames) do
    local peer = charinfo.GetInfo(name)
    if peer then
      hudData[name] = adapter.ToHUDInfo(peer)
    end
  end
end

return {
  Process = process,
  Data = hudData,
}
