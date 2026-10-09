-- Execute the complete window script with the documented ImGui return shapes.
-- This checks integration between the UI, shared model and single-string APIs.
local store, queue, messages = {}, {}, {}
local current, tick, text_calls, stars_clicked = 1, 0, 0, false
local clipper_creations, attached_clipper = 0, nil
local row_selectable_drawn, yellow_cells = false, 0
local submitted_id, disabled = nil, false
local selectable_count = 0
local monitor_launches = 0
local entries = {{desc = 'Initial', time = 1}, {desc = 'Volume adjusted', time = 2}}
local I = setmetatable({}, {__index = function(t, name)
  local value
  if name:find('Flags_') or name:find('Col_') or name:find('Cond_') or name:find('TableBgTarget_') then value = 1
  else value = function() end end
  rawset(t, name, value); return value
end})
I.CreateContext = function() return {} end
I.GetFontSize = function() return 14 end
I.Begin = function()
  if monitor_launches > 0 then store['DaxHistoryTools_v1monitor_heartbeat'] = tostring(tick) end
  return true, true
end
I.BeginDisabled = function(_, value) disabled = value end
I.EndDisabled = function() disabled = false end
I.Button = function(_, label)
  if label == 'Load selected state' then assert(disabled, 'Load button must be disabled with no selection or the current state selected') end
  return false
end
I.TableNeedSort = function() return false end
I.PushID = function(_, id) submitted_id = id end
I.InputText = function(_, _, value) return false, value end
I.Checkbox = function(_, label, value)
  if label == 'Keep capturing when window is closed' then
    assert(value == false, 'Background history polling must be off by default')
  end
  return false, value
end
I.IsItemHovered = function() return false end
I.GetContentRegionAvail = function() return 900, 600 end
I.BeginTable = function() return true end
I.SelectableFlags_SpanAllColumns = 2
I.SelectableFlags_AllowOverlap = 4
I.TableNextRow = function() row_selectable_drawn = false end
I.TableBgTarget_CellBg = 2
I.TableSetBgColor = function(_, target, color, column)
  if color == 0xBFA13BFF then
    assert(target == 2 and column == 0, 'Yellow highlight must be confined to the star cell')
    yellow_cells = yellow_cells + 1
  end
end
I.CreateListClipper = function()
  clipper_creations = clipper_creations + 1
  assert(clipper_creations == 1, 'Repeated clipper allocation would exhaust ReaImGui resources')
  return {}
end
I.Attach = function(_, resource) attached_clipper = resource end
I.ListClipper_Begin = function(c, count)
  assert(c == attached_clipper, 'Clipper lifetime must be attached to the window context')
  c.count = count; c.done = false
end
I.ListClipper_Step = function(c) if not c.done then c.done = true; return true end; return false end
I.ListClipper_GetDisplayRange = function(c) return 0, c.count end
I.SmallButton = function()
  assert(row_selectable_drawn, 'Star button must be submitted after the spanning row target')
  if not stars_clicked and submitted_id == 1 then stars_clicked = true; return true end
  return false
end
I.Selectable = function(_, _, _, flags)
  assert(flags & 2 ~= 0, 'Selection must span the entire table row')
  assert(flags & 4 ~= 0, 'Selection must allow the star button to handle its own clicks')
  row_selectable_drawn = true
  selectable_count = selectable_count + 1
  if selectable_count == 1 then
    assert(submitted_id == 2, 'Newest state must appear first by default')
    return true -- Select the current state; the load button must stay disabled.
  end
  return false
end
I.Text = function(_, text) assert(type(text) == 'string'); text_calls = text_calls + 1 end
package.preload.imgui = function() return function() return I end end
reaper = {
  APIExists = function() return true end,
  AddRemoveReaScript = function(_, _, path) assert(path:find('monitor.lua',1,true)); return 500 end,
  Main_OnCommand = function(action)
    assert(action == 500); monitor_launches = monitor_launches + 1
    store['DaxHistoryTools_v1monitor_heartbeat'] = tostring(tick)
  end,
  IsProjectDirty = function() return 0 end,
  GetExtState = function(s, k) return store[s .. k] or '' end,
  SetExtState = function(s, k, v) store[s .. k] = v end,
  DeleteExtState = function(s, k) store[s .. k] = nil end,
  EnumProjects = function() return 'project', 'C:/Music/Test.rpp' end,
  GetProjectName = function() return 'Test.rpp' end, -- One return value, not bool+name.
  Undo_GetNumEntries = function() return #entries end,
  Undo_GetCurEntry = function() return current end,
  Undo_GetEntryDesc = function(_, i) return entries[i + 1].desc end,
  Undo_GetEntryTime = function(_, i) return entries[i + 1].time end,
  Undo_IsEntryAltTree = function() return 0 end,
  Undo_SetCurPos = function(_, i) current = i end,
  ImGui_GetBuiltinPath = function() return '.' end,
  time_precise = function() tick = tick + 0.1; return tick end,
  get_action_context = function() return false, '', 0, 100 end,
  SetToggleCommandState = function() end,
  RefreshToolbar2 = function() end,
  atexit = function() end,
  defer = function(f) queue[#queue + 1] = f end,
  CountTracks = function() return 0 end,
  GetMasterTrack = function() return {} end,
  GetTrackName = function() return true, 'Master' end,
  GetTrackGUID = function() return '{master}' end,
  GetMediaTrackInfo_Value = function(_, p) return p == 'D_VOL' and 1 or 0 end,
  CountMediaItems = function() return 0 end,
  MB = function(message) messages[#messages + 1] = message end,
  ShowConsoleMsg = function(message) messages[#messages + 1] = message end,
  UpdateArrange = function() end,
}
dofile(window_path)
for _ = 1, 599 do assert(#queue > 0, 'Window stopped deferring'); table.remove(queue, 1)() end
assert(#messages == 0, table.concat(messages, '\n'))
assert(text_calls >= 4200, 'Expected rendered project and history rows across 600 frames')
assert(clipper_creations == 1, 'The complete window must reuse one clipper for every frame')
assert(monitor_launches == 1, 'GUI must silently start one separate monitor, without repeated launches')
assert(store['DaxHistoryTools_v1monitor_heartbeat'], 'Closing the GUI must not clear the separate monitor heartbeat')
assert(yellow_cells >= 599, 'Starred cells must receive the yellow background')
I.Begin = function() return true, false end
local queued_before_close = #queue
table.remove(queue, 1)()
assert(#queue == queued_before_close - 1, 'Closing the window must stop the polling loop by default')
dofile(previous_path)
assert(current == 0, 'Standalone previous-star action should navigate to UI-starred entry')
print('PASS: complete window rendered 600 frames with one attached clipper; UI star and standalone action shared metadata')
