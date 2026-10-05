-- Searchable native history with bookmarks and supported value differences.
local directory = debug.getinfo(1, 'S').source:match('^@(.+[\\/])')
local H = dofile(directory .. 'history_core.lua')
local ok, why = H.check()
if not ok then reaper.MB(why, 'Undo/Redo History', 0); reaper.defer(function() end); return end
if not reaper.APIExists('ImGui_GetBuiltinPath') then
  reaper.MB('Install ReaImGui through ReaPack, then run this action again.', 'Undo/Redo History', 0)
  reaper.defer(function() end); return
end
local section = H.section
local now = reaper.time_precise()
local heartbeat = tonumber(reaper.GetExtState(section, 'heartbeat')) or -10
if now >= heartbeat and now - heartbeat < 2 then
  reaper.SetExtState(section, 'show', tostring(now), false)
  reaper.defer(function() end); return
end
package.path = reaper.ImGui_GetBuiltinPath() .. '/?.lua;' .. package.path
local loaded, ImGui = pcall(function() return require('imgui')('0.9') end)
if not loaded then reaper.MB(tostring(ImGui), 'ReaImGui 0.9+ required', 0); reaper.defer(function() end); return end
local ctx = ImGui.CreateContext('Dax Undo/Redo History')
-- Reuse one clipper and keep it alive while the window is hidden or collapsed.
local clipper = ImGui.CreateListClipper(ctx)
ImGui.Attach(ctx, clipper)
local _, _, action_section, command = reaper.get_action_context()
local function toolbar(on)
  if command > 0 then reaper.SetToggleCommandState(action_section, command, on); reaper.RefreshToolbar2(action_section, command) end
end
toolbar(1)
reaper.atexit(function()
  reaper.DeleteExtState(section, 'heartbeat', false)
  toolbar(0)
end)

local sessions = {}
local project, key, ledger, current, selected
local search, only_stars, auto_refresh, keep_capture = '', false, true, false
local shown, running, last_poll, show_request = true, true, -10, reaper.GetExtState(section, 'show')
local status = 'Double-click an action to load that state. Stars are bookmarks.'
local pending
local version_file = io.open(directory .. 'VERSION', 'r') or io.open(directory .. '../VERSION', 'r')
local version = version_file and version_file:read('*l') or '?'
if version_file then version_file:close() end

local function refresh(capture)
  local active = reaper.EnumProjects(-1, '')
  local active_key = H.project_key(active)
  if project ~= active or key ~= active_key then selected = nil end
  project, key = active, active_key
  local prefix
  ledger, current, prefix = H.refresh(project, key)
  local session = sessions[key] or {}; sessions[key] = session
  if capture then
    H.observe(session, ledger.rows, current, H.snapshot(project), prefix)
    H.save(key, ledger)
  end
end

local function tip(text)
  if ImGui.IsItemHovered(ctx) then ImGui.SetTooltip(ctx, text) end
end
local function navigate(direction)
  local success, message = H.navigate(project, key, direction)
  status = success and 'Loaded starred state.' or (message or 'State could not be loaded.')
  refresh(true)
end

local function render()
  local em = ImGui.GetFontSize(ctx)
  ImGui.SetNextWindowSize(ctx, 78 * em, 44 * em, ImGui.Cond_FirstUseEver)
  local visible, open = ImGui.Begin(ctx, 'Undo / Redo History  ' .. version, true)
  if visible then
    ImGui.SetNextItemWidth(ctx, 24 * em)
    local changed
    changed, search = ImGui.InputText(ctx, 'Search', search)
    tip('Search action names and captured details. Every word must match.')
    ImGui.SameLine(ctx)
    if ImGui.Button(ctx, 'Refresh') then refresh(true); status = 'History refreshed from REAPER.' end
    ImGui.SameLine(ctx); changed, auto_refresh = ImGui.Checkbox(ctx, 'Auto-refresh', auto_refresh)
    ImGui.SameLine(ctx); changed, only_stars = ImGui.Checkbox(ctx, 'Starred only', only_stars)
    changed, keep_capture = ImGui.Checkbox(ctx, 'Keep capturing when window is closed', keep_capture)
    tip('Run this action again to reopen. Turn this off before closing to stop the background monitor.')
    ImGui.SameLine(ctx)
    if ImGui.Button(ctx, 'Previous star') then navigate(-1) end
    ImGui.SameLine(ctx)
    if ImGui.Button(ctx, 'Next star') then navigate(1) end
    ImGui.SameLine(ctx)
    if ImGui.Button(ctx, 'Stop monitor') then running = false end
    if ImGui.Button(ctx, 'Load selected state') and selected then pending = {'jump', selected} end
    ImGui.SameLine(ctx)
    if ImGui.Button(ctx, 'Read selected details') and selected then pending = {'inspect', selected} end
    tip('While stopped, temporarily load the preceding and selected states, compare values, then restore your original position. This can reload FX.')
    local name = reaper.GetProjectName(project)
    ImGui.Text(ctx, (name ~= '' and name or 'Unsaved project') .. '  |  ' .. #ledger.rows .. ' states')
    ImGui.TextWrapped(ctx, status)
    local flags = ImGui.TableFlags_Borders | ImGui.TableFlags_RowBg | ImGui.TableFlags_Resizable
      | ImGui.TableFlags_ScrollY | ImGui.TableFlags_SizingStretchProp
    local _, height = ImGui.GetContentRegionAvail(ctx)
    if ImGui.BeginTable(ctx, 'history', 5, flags, 0, math.max(height, 8 * em)) then
      ImGui.TableSetupColumn(ctx, 'Star', ImGui.TableColumnFlags_WidthFixed, 3 * em)
      ImGui.TableSetupColumn(ctx, 'State', ImGui.TableColumnFlags_WidthFixed, 8 * em)
      ImGui.TableSetupColumn(ctx, 'Time', ImGui.TableColumnFlags_WidthFixed, 6 * em)
      ImGui.TableSetupColumn(ctx, 'Action', ImGui.TableColumnFlags_WidthStretch, 2)
      ImGui.TableSetupColumn(ctx, 'Details', ImGui.TableColumnFlags_WidthStretch, 4)
      ImGui.TableSetupScrollFreeze(ctx, 0, 1)
      ImGui.TableHeadersRow(ctx)
      -- Clip only matching rows so long project histories remain responsive.
      local filtered = {}
      for _, row in ipairs(ledger.rows) do
        if (not only_stars or row.star) and H.matches(row, search) then filtered[#filtered + 1] = row end
      end
      ImGui.ListClipper_Begin(clipper, #filtered)
      while ImGui.ListClipper_Step(clipper) do
        local start, finish = ImGui.ListClipper_GetDisplayRange(clipper)
        for i = start + 1, finish do
          local row = filtered[i]
          ImGui.PushID(ctx, row.id)
          ImGui.TableNextRow(ctx)
          if row.saved then ImGui.TableSetBgColor(ctx, ImGui.TableBgTarget_RowBg0, 0x274C70FF)
          elseif row.index == current then ImGui.TableSetBgColor(ctx, ImGui.TableBgTarget_RowBg0, 0x315646FF) end
          -- Submit the spanning selectable first so the later star button retains
          -- its own hit target instead of being covered by the row selection.
          ImGui.TableSetColumnIndex(ctx, 3)
          if row.index > current then ImGui.PushStyleColor(ctx, ImGui.Col_Text, 0xAAAAAAFF) end
          local row_flags = ImGui.SelectableFlags_AllowDoubleClick
            | ImGui.SelectableFlags_SpanAllColumns | ImGui.SelectableFlags_AllowOverlap
          if ImGui.Selectable(ctx, row.desc .. '##entry', selected == row.id, row_flags) then
            selected = row.id
            if ImGui.IsMouseDoubleClicked(ctx, 0) then pending = {'jump', row.id} end
          end
          tip(row.desc .. (row.branches > 0 and ('\nAlternate redo paths: ' .. row.branches .. ' (use native history to switch branches)') or ''))
          if row.index > current then ImGui.PopStyleColor(ctx) end
          ImGui.TableSetColumnIndex(ctx, 0)
          if row.star then
            ImGui.TableSetBgColor(ctx, ImGui.TableBgTarget_CellBg, 0xBFA13BFF, 0)
            ImGui.PushStyleColor(ctx, ImGui.Col_Text, 0x211B06FF)
            ImGui.PushStyleColor(ctx, ImGui.Col_Button, 0xF2CB4AFF)
            ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered, 0xFFE07AFF)
            ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive, 0xDAB029FF)
          end
          if ImGui.SmallButton(ctx, row.star and '\u{2605}' or '\u{2606}') then pending = {'star', row.id} end
          if row.star then ImGui.PopStyleColor(ctx, 4) end
          tip(row.star and 'Remove bookmark' or 'Bookmark this state')
          ImGui.TableSetColumnIndex(ctx, 1)
          local state_label = row.index == current and 'Current' or (row.index > current and 'Redo' or 'Undo')
          ImGui.Text(ctx, state_label .. (row.saved and ' / Saved' or ''))
          ImGui.TableSetColumnIndex(ctx, 2)
          ImGui.Text(ctx, row.time > 0 and os.date('%H:%M:%S', math.floor(row.time)) or '-')
          tip(row.time > 0 and os.date('%Y-%m-%d %H:%M:%S', math.floor(row.time)) or 'No timestamp')
          ImGui.TableSetColumnIndex(ctx, 4)
          local details = row.details ~= '' and row.details or 'Not captured - select and read details'
          ImGui.Text(ctx, details)
          tip(details)
          ImGui.PopID(ctx)
        end
      end
      ImGui.EndTable(ctx)
    end
    ImGui.End(ctx)
  end
  if not open then shown = false; if not keep_capture then running = false end end
end

local function loop()
  local tick = reaper.time_precise()
  reaper.SetExtState(section, 'heartbeat', tostring(tick), false)
  local requested = reaper.GetExtState(section, 'show')
  if requested ~= show_request then shown = true; show_request = requested end
  local active = reaper.EnumProjects(-1, '')
  if not ledger or active ~= project or ((auto_refresh or not shown) and tick - last_poll >= 0.25) then
    refresh(true); last_poll = tick
  end
  -- Keep the ImGui context alive when monitoring without a visible window.
  ImGui.GetFrameCount(ctx)
  if shown then render() end
  if pending then
    local operation, id = pending[1], pending[2]; pending = nil
    if operation == 'star' then H.star(project, key, id)
    elseif operation == 'jump' then status = H.jump(project, key, id) and 'Loaded selected state.' or 'State no longer available.'
    else
      local success, message = H.inspect(project, key, id)
      status = message or (success and 'Details read.' or 'Could not read details.')
      -- Inspection is navigation, not a new edit. Reset passive capture baseline.
      sessions[key] = nil
    end
    refresh(true)
  end
  if running then reaper.defer(function()
    local success, err = xpcall(loop, debug.traceback)
    if not success then reaper.MB(err, 'History window error', 0) end
  end) end
end
local success, err = xpcall(loop, debug.traceback)
if not success then reaper.MB(err, 'History window error', 0) end
