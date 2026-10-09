-- Exercise real model code against a small, deterministic native-history adapter.
local store, entries, current, loaded, playing, refresh_balance = {}, {}, 0, {}, 0, 0
local project = {}
local fail_snapshot = false
local dirty = 1
local function entry(desc, time, volume)
  return {desc = desc, time = time, volume = volume or 1}
end
reaper = {
  APIExists = function() return true end,
  IsProjectDirty = function() return dirty end,
  GetExtState = function(section, key) return store[section .. key] or '' end,
  SetExtState = function(section, key, value)
    assert(not value:find('[\r\n]'), 'Persistent ExtState must not contain raw newlines')
    store[section .. key] = value
  end,
  EnumProjects = function() return project, 'C:/Music/Test.rpp' end,
  Undo_GetNumEntries = function() return #entries end,
  Undo_GetCurEntry = function() return current end,
  Undo_GetEntryDesc = function(_, index) return entries[index + 1].desc end,
  Undo_GetEntryTime = function(_, index) return entries[index + 1].time end,
  Undo_IsEntryAltTree = function() return 0 end,
  Undo_SetCurPos = function(_, index) current = index; loaded[#loaded + 1] = index end,
  UpdateArrange = function() end,
  GetPlayStateEx = function() return playing end,
  PreventUIRefresh = function(n) refresh_balance = refresh_balance + n end,
  CountTracks = function() return 0 end,
  GetMasterTrack = function() return {} end,
  GetTrackName = function() return true, 'Master' end,
  GetTrackGUID = function() return '{master}' end,
  GetMediaTrackInfo_Value = function(_, prop)
    if fail_snapshot then error('simulated snapshot failure') end
    return prop == 'D_VOL' and entries[current + 1].volume or 0
  end,
  CountMediaItems = function() return 0 end,
}
local H = dofile(core_path)
local key = H.project_key(project)
local count = 0
local function check(condition, message)
  assert(condition, message); count = count + 1
end
check(reaper.GetProjectGUID == nil and key == 'project:saved:C:/Music/Test.rpp',
  'Project identity must work without the nonexistent GetProjectGUID API')
local native_enum, native_master, native_guid = reaper.EnumProjects, reaper.GetMasterTrack, reaper.GetTrackGUID
reaper.EnumProjects = function(index)
  if index == -1 then return project, '' end
  if index == 0 then return project, '' end
  if index == 1 then return 'other', 'C:/Music/Other=take.rpp' end
end
reaper.GetMasterTrack = function(proj) return proj end
reaper.GetTrackGUID = function(track) return track == project and '{master-one}' or '{master-two}' end
check(H.project_key(project) == 'project:unsaved:{master-one}', 'Unsaved tabs must use their master-track identity')
check(H.project_key('other') == 'project:saved:C:/Music/Other%3Dtake.rpp',
  'A nonactive project must use its own path and escape INI key characters')
reaper.EnumProjects, reaper.GetMasterTrack, reaper.GetTrackGUID = native_enum, native_master, native_guid
entries = {entry('Initial', 1), entry('Volume adjusted', 2, 0.5), entry('Pan adjusted', 3), entry('Volume adjusted', 4)}
current = 2
local ledger = H.refresh(project, key)
check(#ledger.rows == 4 and #loaded == 0, 'Refresh must load complete history without navigating')
check(not ledger.rows[current + 1].saved, 'Dirty edits must not be labelled as project-save states')
dirty = 0
ledger = H.refresh(project, key)
check(ledger.rows[current + 1].saved and #loaded == 0, 'Refresh must mark an observed saved state without navigation')
dirty = 1
ledger = H.refresh(project, key)
check(ledger.rows[3].saved, 'Recorded save points must survive later edits and metadata reload')
local legacy_data = 'next=2\n1\t1\t1\tOld bookmark\tOld details'
store[H.section .. 'legacy'] = legacy_data
check(H.load('legacy').rows[1].star and not H.load('legacy').rows[1].saved,
  'Old bookmark metadata must still load after adding save markers')
local first, last = ledger.rows[1].id, ledger.rows[4].id
H.star(project, key, first); H.star(project, key, last)
check(#loaded == 0, 'Starring must not navigate')
check(H.navigate(project, key, -1) and current == 0, 'Previous star must choose closest earlier star')
check(not H.navigate(project, key, -1) and current == 0, 'Previous star must stop without wrapping')
check(H.navigate(project, key, 1) and current == 3, 'Next star must navigate into redo states')
check(not H.navigate(project, key, 1), 'Next star must stop without wrapping')
check(H.navigate_edge(project, key, false) and current == 0, 'First star must jump to the earliest bookmark')
check(H.navigate_edge(project, key, true) and current == 3, 'Last star must jump to the latest bookmark')
check(H.navigate_edge(project, key, true) and current == 3, 'Last star must succeed when already at that bookmark')
local empty_key = 'empty-stars'
check(not H.navigate_edge(project, empty_key, false) and current == 3,
  'First-star navigation without bookmarks must leave the current state alone')
local fresh_module = dofile(core_path)
check(fresh_module.navigate(project, key, -1) and current == 0, 'Standalone actions must reload persistent stars')
local row = {desc = 'Volume adjusted', details = 'Lead vocal: -6 -> -3.5 dB (+2.5 dB)'}
check(H.matches(row, 'vocal +2.5') and not H.matches(row, '[vocal]'), 'Search must be literal and include details')
local encoded = {next_id = 2, rows = {{id = 1, time = 1.123456789, star = true,
  desc = 'Vocals\t\n100% \u{2605}', details = '\u{2192} -6.0\r\n+2.5%'}}}
H.save('roundtrip', encoded)
local decoded = H.load('roundtrip')
check(decoded.rows[1].desc == encoded.rows[1].desc and decoded.rows[1].details == encoded.rows[1].details,
  'Metadata must round-trip UTF-8, newlines, tabs and percent signs')
check(decoded.rows[1].star and math.abs(decoded.rows[1].time - 1.123456789) < 1e-10, 'Metadata must retain stars and timestamp precision')

-- Discarded redo entries may not donate their bookmark to replacement branches.
current = 1
entries = {entries[1], entries[2], entry('New edit', 5)}
ledger = H.refresh(project, key)
check(ledger.rows[1].star and not ledger.rows[3].star, 'Branch replacement must preserve only surviving stars')
check(not H.jump(project, key, last), 'A stale selection must not navigate')
H.star(project, key, ledger.rows[2].id)
entries = {entries[2], entries[3]}; current = 0
ledger = H.refresh(project, key)
check(ledger.rows[1].star, 'Unique surviving star must follow history memory trimming')

-- Inspect the selected transition and always restore the user's original position.
entries = {entry('Initial', 10), entry('Volume adjusted', 11, 10 ^ (-3.5 / 20)), entry('Later', 12)}
current = 2
ledger = H.refresh(project, key)
local id = ledger.rows[2].id
local success, message = H.inspect(project, key, id)
check(success and current == 2 and refresh_balance == 0, 'Inspection must restore original position and refresh balance')
ledger = H.refresh(project, key)
check(ledger.rows[2].details:find('-3.50 dB', 1, true), 'Volume details must contain the numeric delta')
playing = 1; local loads_before = #loaded
check(not H.inspect(project, key, id) and #loaded == loads_before, 'Inspection must refuse playback without navigation')
playing = 0; fail_snapshot = true
check(not H.inspect(project, key, id) and current == 2 and refresh_balance == 0, 'Snapshot errors must restore original position')
fail_snapshot = false
local native_set = reaper.Undo_SetCurPos
local changed_during_load = false
reaper.Undo_SetCurPos = function(proj, index)
  native_set(proj, index)
  if not changed_during_load then
    changed_during_load = true
    table.insert(entries, 1, entry('Inserted by host', 9))
    current = current + 1
  end
end
check(not H.inspect(project, key, id) and current == 3 and refresh_balance == 0,
  'Changed history must restore the uniquely identified original state, not its stale index')
reaper.Undo_SetCurPos = native_set
local function state(volume)
  return {tracks = {t = {name = 'Vocal', volume = volume, pan = 0, mute = 0, solo = 0}}, items = {}}
end
check(H.diff(state(0), state(1)):find('-inf -> 0.00 dB', 1, true), 'Zero volume must produce a finite readable transition')
local s = {rows = {{id = 1, desc = 'Initial', time = 1}}, current = 0, snapshot = state(1)}
local new_rows = {{id = 1, desc = 'Initial', time = 1}, {id = 2, desc = 'Volume adjusted', time = 2}}
H.observe(s, new_rows, 1, state(0.5), 1)
check(new_rows[2].details:find('-6.02', 1, true), 'Single new entry must capture volume delta')
H.observe(s, new_rows, 1, state(0.25), 2)
check(new_rows[2].details:find('-12.04', 1, true), 'Coalesced drag must retain its original baseline')
local missed = {{id = 1, desc = 'Initial', time = 1}, new_rows[2], {id = 3, desc = 'A', time = 3}, {id = 4, desc = 'B', time = 4}}
H.observe(s, missed, 3, state(1), 2)
check(not missed[4].details, 'Multiple missed edits must not receive an invented per-entry delta')

local sort_sample = {{id=1,index=0,time=20,desc='Zulu',details='B',star=false},
  {id=2,index=1,time=20,desc='Alpha',details='A',star=true},
  {id=3,index=2,time=30,desc='Beta',details='C',star=false}}
H.sort_rows(sort_sample, 2, true, 2)
check(sort_sample[1].id == 3 and sort_sample[2].id == 2, 'Newest-first sort must resolve tied timestamps by undo index')
H.sort_rows(sort_sample, 2, false, 2)
check(sort_sample[1].id == 1, 'Second header click must invert time order')
H.sort_rows(sort_sample, 3, false, 2)
check(sort_sample[1].id == 2, 'Action column must sort alphabetically')
H.sort_rows(sort_sample, 0, true, 2)
check(sort_sample[1].star, 'Star column must sort bookmarks')
check(not H.can_load(sort_sample, 3, 2) and H.can_load(sort_sample, 1, 2) and not H.can_load(sort_sample, nil, 2), 'Current and missing selections must not be loadable')
-- Model a host which applies undo changes on the NEXT main-loop cycle.
local callbacks, pending_index = {}, nil
entries = {entry('Initial', 50, 1), entry('Selection', 51, 1), entry('Volume', 52, 0.5), entry('Later', 53, 0.25)}
entries[1].selected=0; entries[2].selected=1; entries[3].selected=1; entries[4].selected=0
current=3
reaper.defer = function(f) callbacks[#callbacks+1]=f end
reaper.Undo_SetCurPos = function(_, index) pending_index=index end
local getter = reaper.GetMediaTrackInfo_Value
reaper.GetMediaTrackInfo_Value = function(track, prop)
  if fail_snapshot then error('simulated deferred snapshot failure') end
  if prop == 'I_SELECTED' then return entries[current+1].selected end
  return getter(track, prop)
end
local function drain()
  local steps=0
  while #callbacks > 0 do
    steps=steps+1; assert(steps<10)
    if pending_index ~= nil then current=pending_index; pending_index=nil end
    table.remove(callbacks,1)()
  end
end
ledger=H.refresh(project,key)
local completion
H.inspect_async(project,key,ledger.rows[3].id,function(ok) completion=ok end)
check(completion == nil and current == 3, 'Detail capture must wait for the host to apply the requested state')
drain()
check(completion and current == 3, 'Deferred volume inspection must restore the original position')
ledger=H.refresh(project,key)
check(ledger.rows[3].details:find('-6.02',1,true), 'Deferred volume inspection must read actual historical values')
H.inspect_async(project,key,ledger.rows[2].id,function(ok) completion=ok end)
drain()
ledger=H.refresh(project,key)
check(completion and ledger.rows[2].details:find('unselected -> selected',1,true), 'Historical track-selection changes must be captured')
fail_snapshot=true
H.inspect_async(project,key,ledger.rows[3].id,function(ok) completion=ok end)
drain()
check(not completion and current==3, 'Deferred snapshot errors must restore the original state')
fail_snapshot=false
local before_item={tracks={},items={i={name='Clip',volume=1,position=0,length=1,mute=0,selected=0,fade_in=0,fade_out=0}}}
local after_item={tracks={},items={i={name='Clip',volume=1,position=0,length=1,mute=0,selected=1,fade_in=0.2,fade_out=0}}}
local item_details=H.diff(before_item,after_item)
check(item_details:find('unselected -> selected',1,true) and item_details:find('fade_in',1,true), 'Item selection and fades must be captured')
print('PASS: ' .. count .. ' model assertions (refresh, stars, branches, trimming, search, UTF-8, capture and restoration)')
