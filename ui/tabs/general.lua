local imgui = require('ImGui')
local logger = require('knightlinc.Write')
local renderCombobox = require('ui/controls/combobox')

---@type string[]
local validLogLevels = {}
for k,v in pairs(logger.loglevels) do
  validLogLevels[v.level] = k
end

---@param settings HUDSettings
local function renderGeneralTab(settings)
  imgui.Text("Lock HUD")
  settings.ui.locked, _ = imgui.Checkbox("##LockHUD", settings.ui.locked)
  imgui.Text("Show NavBar")
  settings.ui.showNavBar, _ = imgui.Checkbox("##SHOWNAVBAR", settings.ui.showNavBar)
  imgui.Text("Only when focused")
  settings.ui.foregroundOnly, _ = imgui.Checkbox("##ForegroundOnly", settings.ui.foregroundOnly)
  imgui.Text("HUD render order")
  settings.ui.layoutType, _ = imgui.RadioButton("Name", settings.ui.layoutType, 1)
  if next(settings.groups) then
    imgui.SameLine()
    settings.ui.layoutType, _ = imgui.RadioButton("Group", settings.ui.layoutType, 2)
  end

  imgui.Text("Columns")
  local columns, _ = imgui.InputInt("##Columns", settings.ui.columns or 1, 1, 1)
  if type(columns) ~= "number" then
    columns = 1
  end
  columns = math.floor(columns)
  if columns < 1 then
    columns = 1
  elseif columns > 8 then
    columns = 8
  end
  settings.ui.columns = columns

  imgui.Text("Update Frequency (ms)")
  settings.update_frequency, _ = imgui.InputInt("##UpdateFrequency", settings.update_frequency, 100, 1000)
  imgui.Text("Stale Data Timeout (m)")
  settings.stale_data_timer, _ = imgui.InputFloat("##StaleDataTimeout", settings.stale_data_timer, 0.1, 1)
  imgui.Text("Opacity")
  settings.ui.opacity, _ = imgui.SliderFloat("##Opacity", settings.ui.opacity, 0.0, 1.0)
  imgui.Text("Scale")
  settings.ui.scale, _ = imgui.SliderFloat("##Scale", settings.ui.scale, 0.7, 1.3)
  settings.loglevel = renderCombobox("Loglevel", settings.loglevel, validLogLevels, function(option) local text = option:gsub("^%l", string.upper); return text end, "Sets the console loglevel for HUD")
end

return renderGeneralTab