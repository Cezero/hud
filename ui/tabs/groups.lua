local imgui = require('ImGui')
local icons = require('mq/icons')


local leftPanelWidth = 200
local selectedGroup = 0

---@param group HUDGroup
---@param index integer
---@return string
local function groupLabel(group, index)
  if type(group.name) == "string" and group.name ~= "" then
    return group.name
  end
  return "Group " .. index
end

local function LeftPaneWindow(groups)
  local x,y = imgui.GetContentRegionAvail()
  if imgui.BeginChild("left", leftPanelWidth, y-21) then
    for k,v in ipairs(groups) do
      if imgui.Button(icons.FA_TRASH.."##delgroup"..k) then
        groups[k] = nil
      end
      imgui.SameLine()
      imgui.BeginDisabled(k == 1)
      if imgui.Button(icons.FA_CARET_UP.."##upgroup"..k) then
        table.remove(groups, k)
        table.insert(groups, k-1, v)
      end
      imgui.EndDisabled()
      imgui.SameLine()
      imgui.BeginDisabled(k == #groups)
      if imgui.Button(icons.FA_CARET_DOWN.."##downgroup"..k) then
        table.remove(groups, k)
        table.insert(groups, k+1, v)
      end
      imgui.EndDisabled()
      imgui.SameLine()
      local selected = imgui.Selectable(groupLabel(v, k) .. "##groupsel" .. k, selectedGroup == k)
      if selected then
        selectedGroup = k
      end
    end
  end
  imgui.EndChild()
end

---@param group HUDGroup
local function RightPaneWindow(group)
  local x,y = imgui.GetContentRegionAvail()
  if imgui.BeginChild("right", x, y-21) then
    if group then
      imgui.Text("Name")
      local newName, _ = imgui.InputText("##groupname", group.name or "")
      group.name = newName

      local members = group.members
      for i, value in ipairs(members) do
        imgui.Text(i..":")
        imgui.SameLine()
        local newValue, _ = imgui.InputText("##"..i, value)
        members[i] = newValue
        imgui.SameLine()
        imgui.BeginDisabled(i == 1)
        if imgui.Button(icons.FA_CARET_UP.."##upmember"..i) then
          table.remove(members, i)
          table.insert(members, i-1, value)
        end
        imgui.EndDisabled()
        imgui.SameLine()
        imgui.BeginDisabled(i == #members)
        if imgui.Button(icons.FA_CARET_DOWN.."##downmember"..i) then
          table.remove(members, i)
          table.insert(members, i+1, value)
        end
        imgui.EndDisabled()
        imgui.SameLine()
        if imgui.Button(icons.FA_TRASH.."##delmember"..i) then
          members[i] = nil
        end
      end

      if imgui.Button("Add member") then
        table.insert(members, "")
      end
    end
  end
  imgui.EndChild()
end

local function renderGroupTab(settings)
  if imgui.Button("Add group") then
    table.insert(settings.groups, { name = "Group " .. (#settings.groups + 1), enabled = true, members = {} })
  end
  LeftPaneWindow(settings.groups)
  imgui.SameLine()
  RightPaneWindow(settings.groups[selectedGroup])
end

return renderGroupTab