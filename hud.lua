local mq = require('mq')
local imgui = require('ImGui')
local logger = require('knightlinc.Write')
local hudBot = require('hudbot')
local dataSource = require('data_source')
local settingsUI = require('ui.settings')

--- First `count % columns` columns receive one extra item.
---@param count integer
---@param columns integer
---@return integer[]
local function columnCounts(count, columns)
  local counts = {}
  if columns < 1 then
    columns = 1
  end
  local base = math.floor(count / columns)
  local extra = count % columns
  for i = 1, columns do
    counts[i] = base + ((i <= extra) and 1 or 0)
  end
  return counts
end

--- Split a list into contiguous columns. Empty columns are omitted.
---@generic T
---@param list T[]
---@param columns integer
---@return T[][]
local function splitIntoColumns(list, columns)
  local counts = columnCounts(#list, columns)
  local slices = {}
  local index = 1
  for _, count in ipairs(counts) do
    if count > 0 then
      local slice = {}
      for _ = 1, count do
        table.insert(slice, list[index])
        index = index + 1
      end
      table.insert(slices, slice)
    end
  end
  return slices
end

local function init(settings)
  settingsUI.Init(settings)
  ---@type table<string, HUDBot>
  local hudData = {}

  -- GUI Control variables
  local openGUI = true
  local shouldDrawGUI = true
  local terminate = false
  local windowFlags = bit32.bor(ImGuiWindowFlags.NoResize, ImGuiWindowFlags.NoScrollbar, ImGuiWindowFlags.NoDocking, ImGuiWindowFlags.AlwaysAutoResize, ImGuiWindowFlags.NoFocusOnAppearing, ImGuiWindowFlags.NoNav)
  local tableFlags = bit32.bor(ImGuiTableFlags.PadOuterX, ImGuiTableFlags.Hideable)

  ---@param hudItem HUDItem
  local function renderItem(hudItem)
    imgui.PushStyleVar(ImGuiStyleVar.ItemInnerSpacing, 2, 2)
    if hudItem.Text == "" then
      imgui.Text("")
    else
      imgui.PushStyleColor(ImGuiCol.Text, hudItem.Color)
      imgui.Text(hudItem.Text)
      if hudItem.Strikethrough then
        local minX, minY = imgui.GetItemRectMin()
        local maxX, maxY = imgui.GetItemRectMax()
        local midY = (minY + maxY) * 0.5
        imgui.GetWindowDrawList():AddLine(ImVec2(minX, midY), ImVec2(maxX, midY), imgui.GetColorU32(hudItem.Color), 1)
      end
      imgui.PopStyleColor(1)
    end

    imgui.PopStyleVar(1)
  end

  ---@param hudBot HUDBot
  local function renderHutBot(hudBot)
    imgui.TableNextColumn()
    renderItem(hudBot.Name)
    if imgui.IsItemClicked(ImGuiMouseButton.Left) then
      mq.cmdf("/mqtarget %s", hudBot.Name.Text)
    end
    imgui.TableNextColumn()
    renderItem(hudBot.Level)
    imgui.TableNextColumn()
    renderItem(hudBot.PctHP)
    imgui.TableNextColumn()
    renderItem(hudBot.PctMana)
    imgui.TableNextColumn()
    renderItem(hudBot.PctExp)
    imgui.TableNextColumn()
    renderItem(hudBot.AA)
    imgui.TableNextColumn()
    renderItem(hudBot.Distance)
    imgui.TableNextColumn()
    renderItem(hudBot.Target)
    imgui.TableNextColumn()
    renderItem(hudBot.Pet)
    imgui.TableNextColumn()
    renderItem(hudBot.Casting)
    imgui.TableNextColumn()
    renderItem(hudBot.PIDs)
  end

  local function PushStyleCompact()
    local style = imgui.GetStyle()
    imgui.PushStyleVar(ImGuiStyleVar.WindowPadding, 0, 0)
  end

  local function PopStyleCompact()
    imgui.PopStyleVar(1)
  end

  local ColumnID_Name = 0
  local ColumnID_Level = 1
  local ColumnID_HP = 2
  local ColumnID_MP = 3
  local ColumnID_XP = 4
  local ColumnID_AA = 10
  local ColumnID_Distance = 5
  local ColumnID_Target = 6
  local ColumnID_Pet = 7
  local ColumnID_Casting = 8
  local ColumnID_PIDs = 9
  local columnWidthSaveInterval = 10000
  local statColumns = {
    { label = 'Name', id = ColumnID_Name, field = 'Name' },
    { label = 'Lvl', id = ColumnID_Level, field = 'Level' },
    { label = 'HP', id = ColumnID_HP, field = 'PctHP' },
    { label = 'MP', id = ColumnID_MP, field = 'PctMana' },
    { label = 'XP', id = ColumnID_XP, field = 'PctExp' },
    { label = 'AA', id = ColumnID_AA, field = 'AA' },
    { label = 'Dist', id = ColumnID_Distance, field = 'Distance' },
    { label = 'Tar', id = ColumnID_Target, field = 'Target' },
    { label = 'Pet', id = ColumnID_Pet, field = 'Pet' },
    { label = 'Cast', id = ColumnID_Casting, field = 'Casting' },
    { label = 'PIDs', id = ColumnID_PIDs, field = 'PIDs' },
  }
  ---@type table<string, number>
  local columnContentWidth = {}
  local columnWidthsDirty = false
  local lastColumnWidthCopy = mq.gettime()

  local savedColumnWidths = settings.ui.columnWidths
  if type(savedColumnWidths) == "table" then
    for _, column in ipairs(statColumns) do
      local width = savedColumnWidths[column.label]
      if type(width) == "number" and width > 0 then
        columnContentWidth[column.label] = width
      end
    end
  end

  local function fontScale()
    local scale = settings.ui.scale
    if type(scale) ~= "number" or scale <= 0 then
      return 1
    end
    return scale
  end

  ---@param label string
  ---@param text string|nil
  local function noteColumnText(label, text)
    if type(text) ~= "string" or text == "" then
      return
    end
    local pixelWidth = imgui.CalcTextSize(text)
    local unscaled = math.ceil(pixelWidth / fontScale())
    if unscaled > (columnContentWidth[label] or 0) then
      columnContentWidth[label] = unscaled
      columnWidthsDirty = true
    end
  end

  ---@param bot HUDBot
  local function noteBotColumns(bot)
    for _, column in ipairs(statColumns) do
      local item = bot[column.field]
      if item then
        noteColumnText(column.label, item.Text)
      end
    end
  end

  ---@param slices (HUDBot[]|HUDGroup[])[]
  ---@param groupLayout boolean
  local function noteVisibleColumns(slices, groupLayout)
    for _, column in ipairs(statColumns) do
      noteColumnText(column.label, column.label)
    end
    for _, slice in ipairs(slices) do
      if groupLayout then
        for _, group in ipairs(slice) do
          for _, name in ipairs(group.members or {}) do
            local bot = hudData[name]
            if bot then
              noteBotColumns(bot)
            end
          end
        end
      else
        for _, bot in ipairs(slice) do
          noteBotColumns(bot)
        end
      end
    end
  end

  ---@param label string
  ---@return number
  local function columnInitWidth(label)
    local stored = columnContentWidth[label]
    if type(stored) ~= "number" or stored <= 0 then
      return -1.0
    end
    return stored * fontScale()
  end

  local function columnWidthsMatchSettings()
    local saved = settings.ui.columnWidths
    if type(saved) ~= "table" then
      return false
    end
    for _, column in ipairs(statColumns) do
      local live = columnContentWidth[column.label]
      local stored = saved[column.label]
      if live == nil then
        if type(stored) == "number" and stored > 0 then
          return false
        end
      elseif stored ~= live then
        return false
      end
    end
    return true
  end

  ---@param force boolean
  local function flushColumnWidths(force)
    if not columnWidthsDirty then
      return
    end
    if columnWidthsMatchSettings() then
      columnWidthsDirty = false
      return
    end
    if not force and mq.gettime() - lastColumnWidthCopy < columnWidthSaveInterval then
      return
    end

    local saved = {}
    for _, column in ipairs(statColumns) do
      local width = columnContentWidth[column.label]
      if type(width) == "number" and width > 0 then
        saved[column.label] = width
      end
    end
    settings.ui.columnWidths = saved
    columnWidthsDirty = false
    lastColumnWidthCopy = mq.gettime()
  end

  -- Shared visibility across side-by-side tables. ImGui commits a menu toggle on the next frame,
  -- so this only pushes a change onto a table that has not already adopted it.
  local sharedColumnEnabled = nil
  local observedColumnEnabled = {}
  local requestedColumnEnabled = {}

  local function readColumnEnabled()
    local enabled = {}
    for statColumn = 0, 10 do
      local columnFlags = imgui.TableGetColumnFlags(statColumn)
      enabled[statColumn] = bit32.band(columnFlags, ImGuiTableColumnFlags.IsEnabled) ~= 0
    end
    return enabled
  end

  local function copyColumnEnabled(enabled)
    local copy = {}
    for statColumn = 0, 10 do
      copy[statColumn] = enabled[statColumn]
    end
    return copy
  end

  local function sameColumnEnabled(a, b)
    if a == nil or b == nil then
      return false
    end
    for statColumn = 0, 10 do
      if a[statColumn] ~= b[statColumn] then
        return false
      end
    end
    return true
  end

  local function syncColumnEnabled(tableId)
    local now = readColumnEnabled()
    local previous = observedColumnEnabled[tableId]
    local requested = requestedColumnEnabled[tableId]
    if previous and not sameColumnEnabled(now, previous) and not sameColumnEnabled(now, requested) then
      sharedColumnEnabled = copyColumnEnabled(now)
    end
    if sharedColumnEnabled == nil then
      sharedColumnEnabled = copyColumnEnabled(now)
    end
    observedColumnEnabled[tableId] = copyColumnEnabled(now)
    if not sameColumnEnabled(now, sharedColumnEnabled) then
      for statColumn = 0, 10 do
        imgui.TableSetColumnEnabled(statColumn, sharedColumnEnabled[statColumn])
      end
      requestedColumnEnabled[tableId] = copyColumnEnabled(sharedColumnEnabled)
    else
      requestedColumnEnabled[tableId] = nil
    end
  end

  local eq_path = mq.TLO.EverQuest.Path()
  eq_path = eq_path:gsub('.*%\\', '') -- https://stackoverflow.com/questions/74408159/lua-help-to-get-an-end-of-string-after-last-special-character

  local function clampedColumnCount()
    local columns = math.floor(settings.ui.columns or 1)
    if columns < 1 then
      return 1
    end
    if columns > 8 then
      return 8
    end
    return columns
  end

  local function sortedBots()
    local bots = {}
    for _, bot in pairs(hudData) do
      table.insert(bots, bot)
    end
    table.sort(bots, function(a, b)
      return a.Name.Text:lower() < b.Name.Text:lower()
    end)
    return bots
  end

  ---@param groups HUDGroup[]
  ---@return HUDGroup[]
  local function visibleGroups(groups)
    local visible = {}
    for _, group in ipairs(groups) do
      if type(group) == "table" and group.enabled ~= false then
        table.insert(visible, group)
      end
    end
    return visible
  end

  ---@param group HUDGroup
  ---@param index integer
  ---@return string
  local function groupLabel(group, index)
    if type(group.name) == "string" and group.name ~= "" then
      return group.name
    end
    return "Group " .. index
  end

  ---@param groups HUDGroup[]
  local function renderGroupSlice(groups)
    local renderedAny = false
    for _, group in ipairs(groups) do
      local renderGroupSpacing = renderedAny
      for _, name in ipairs(group.members or {}) do
        local hudBotData = hudData[name]
        if hudBotData then
          if renderGroupSpacing then
            imgui.TableNextRow()
            imgui.TableNextRow()
            imgui.TableNextRow()
          end
          renderHutBot(hudBotData)
          renderGroupSpacing = false
          renderedAny = true
        end
      end
    end
  end

  ---@param tableId string
  ---@param renderRows function
  local function renderStatTable(tableId, renderRows)
    local flags = bit32.bor(tableFlags, ImGuiTableFlags.SizingFixedFit, ImGuiTableFlags.NoHostExtendX)
    if not imgui.BeginTable(tableId, 11, flags) then
      return
    end

    for _, column in ipairs(statColumns) do
      imgui.TableSetupColumn(column.label, ImGuiTableColumnFlags.WidthFixed, columnInitWidth(column.label), column.id)
    end
    imgui.TableHeadersRow()
    renderRows()

    for statColumn = 0, 10 do
      imgui.PushID(tableId .. statColumn)
      if imgui.TableGetHoveredColumn() > 0 and imgui.IsMouseReleased(1) then
        imgui.OpenPopup("TablePopup", ImGuiPopupFlags.NoOpenOverExistingPopup)
      end
      if imgui.BeginPopup("TablePopup") then
        imgui.Text("Settings")
        if imgui.IsItemClicked(ImGuiMouseButton.Left) then
          settingsUI.OpenSettings()
          imgui.CloseCurrentPopup()
        end
        if next(settings.groups) then
          imgui.Separator()
          for groupIndex, group in ipairs(settings.groups) do
            local activated, selected = imgui.MenuItem(groupLabel(group, groupIndex) .. "##hudgroup" .. groupIndex, nil, group.enabled ~= false)
            if activated then
              if type(selected) == "boolean" then
                group.enabled = selected
              else
                group.enabled = group.enabled == false
              end
            end
          end
        end
        imgui.EndPopup()
      end
      imgui.PopID()
    end

    syncColumnEnabled(tableId)
    imgui.EndTable()
  end

  -- ImGui main function for rendering the UI window
  local hud = function()
    if not openGUI then
      flushColumnWidths(false)
      return
    end
    local flags = windowFlags
    if settings.ui.locked then
      flags = bit32.bor(flags, ImGuiWindowFlags.NoMove)
    end
    if not settings.ui.showNavBar then
      flags = bit32.bor(flags, ImGuiWindowFlags.NoTitleBar, ImGuiWindowFlags.NoCollapse)
    end

    imgui.SetNextWindowBgAlpha(settings.ui.opacity)
    PushStyleCompact()
    openGUI, shouldDrawGUI = imgui.Begin(('HUD###hud_%s'):format(eq_path), openGUI, flags) -- https://discord.com/channels/511690098136580097/866047684242309140/1268289663546949773
    PopStyleCompact()
    if shouldDrawGUI then
      imgui.SetWindowFontScale(settings.ui.scale)
      local groupLayout = settings.ui.layoutType == 2
      local slices
      if groupLayout then
        slices = splitIntoColumns(visibleGroups(settings.groups), clampedColumnCount())
      else
        slices = splitIntoColumns(sortedBots(), clampedColumnCount())
      end
      if #slices == 0 then
        slices = {{}}
      end
      noteVisibleColumns(slices, groupLayout)

      -- Place stat tables beside each other. Nesting them in a parent table clips each one to an unresolved cell.
      local columnRects = {}
      for i, slice in ipairs(slices) do
        if i > 1 then
          imgui.SameLine()
        end
        local tableId = (i == 1) and 'hud_table' or ('hud_table_' .. i)
        renderStatTable(tableId, function()
          if groupLayout then
            renderGroupSlice(slice)
          else
            for _, bot in ipairs(slice) do
              renderHutBot(bot)
            end
          end
        end)
        local minX, minY = imgui.GetItemRectMin()
        local maxX, maxY = imgui.GetItemRectMax()
        columnRects[i] = { minX = minX, minY = minY, maxX = maxX, maxY = maxY }
      end

      if #columnRects > 1 then
        local spacing = imgui.GetStyle().ItemSpacing.x
        local drawList = imgui.GetWindowDrawList()
        local color = imgui.GetColorU32(0.22, 0.22, 0.22, 1)
        for i = 1, #columnRects - 1 do
          local left = columnRects[i]
          local right = columnRects[i + 1]
          local x = left.maxX + spacing * 0.5
          local y1 = math.min(left.minY, right.minY)
          local y2 = math.max(left.maxY, right.maxY)
          drawList:AddLine(ImVec2(x, y1), ImVec2(x, y2), color, 1)
        end
      end
    elseif not settings.ui.showNavBar then
      settings.ui.showNavBar = true
    end

    flushColumnWidths(false)
    imgui.End()
    if not openGUI then
        terminate = true
    end
  end

  mq.imgui.init('hud', hud)

  local function updateHudData()
    for name, _ in pairs(hudData) do
      if not dataSource.Data[name] then
        logger.Debug("<HudBot data for %s not found, removing from HUD...", name)
        hudData[name] = nil
      end
    end

    for name, data in pairs(dataSource.Data) do
      if not hudData[name] then
        hudData[name] = hudBot:New(data)
      else
        hudData[name]:Update(data)
      end
    end
  end

  ---@return boolean
  local function shouldTerminate()
      return terminate
  end

  local function shouldDrawGui()
    if settings.ui.foregroundOnly then
      openGUI = mq.TLO.EverQuest.Foreground()
    else
      openGUI = true
    end
  end

  return {
    ShouldDrawGui = shouldDrawGui,
    ShouldTerminate = shouldTerminate,
    Update = updateHudData,
    FlushColumnWidths = function()
      flushColumnWidths(true)
    end,
  }

end

mq.bind("/hudsettings", settingsUI.OpenSettings)

return init