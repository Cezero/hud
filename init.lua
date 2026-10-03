local mq = require('mq')
local logger = require('knightlinc.Write')
local plugins = require('plugins')

logger.prefix = string.format("\at%s\ax", "[HUD]")
logger.postfix = function () return string.format(" %s", os.date("%X")) end

plugins.EnsureAnyIsLoaded({ "charinfo", "mqcharinfo" })

local dataSource = require('data_source')
local settingsOpt = require('settings')
local hudInit = require('hud')

local settings = settingsOpt.LoadConfig()
logger.loglevel = settings.loglevel

local hud = hudInit(settings)

while not hud.ShouldTerminate() do
  dataSource.Process(settings)
  hud.Update()
  hud.ShouldDrawGui()
  settingsOpt.SaveIfChanged()
  mq.delay(settings.update_frequency)
end

hud.FlushColumnWidths()
settingsOpt.SaveIfChanged()

