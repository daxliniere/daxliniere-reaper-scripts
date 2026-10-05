-- Run ONLY in the isolated resource directory created by tools/host-smoke.ps1.
local directory = debug.getinfo(1, 'S').source:match('^@(.+[\\/])')
local root = directory .. '../'
local report_path = root .. '.tools/reaper-test/result.txt'
local messages = {}
local original_mb = reaper.MB
reaper.MB = function(message, title) messages[#messages + 1] = title .. ': ' .. message; return 0 end
local function report(message)
  local file = assert(io.open(report_path, 'w')); file:write(message); file:close()
end
local project = reaper.EnumProjects(-1, '')
local function finish(message)
  report(message)
  reaper.MB = original_mb
  reaper.Main_SaveProjectEx(project, root .. '.tools/reaper-test/host-test.rpp', 0)
  reaper.Main_OnCommand(40004, 0) -- Quit this isolated test instance.
end
local success, err = xpcall(function()
  assert(reaper.GetResourcePath():find('reaper-test', 1, true), 'Refusing to test in the user resource directory')
  local H = dofile(root .. 'scripts/history_core.lua')
  assert(H.check())
  reaper.Undo_BeginBlock2(project)
  reaper.InsertTrackAtIndex(0, true)
  local track = reaper.GetTrack(project, 0)
  reaper.GetSetMediaTrackInfo_String(track, 'P_NAME', 'Smoke vocal', true)
  reaper.Undo_EndBlock2(project, 'Test track added', -1)
  reaper.Undo_BeginBlock2(project)
  reaper.SetMediaTrackInfo_Value(track, 'D_VOL', 0.5)
  reaper.Undo_EndBlock2(project, 'Volume adjusted', -1)
  reaper.Undo_BeginBlock2(project)
  reaper.SetMediaTrackInfo_Value(track, 'D_VOL', 0.25)
  reaper.Undo_EndBlock2(project, 'Volume adjusted again', -1)
  local key = H.project_key(project)
  local ledger, current = H.refresh(project, key)
  assert(#ledger.rows >= 3, 'Native history should contain test edits')
  assert(ledger.rows[current + 1].desc == 'Volume adjusted again', 'Native index mapping is incorrect')
  local selected = ledger.rows[current].id
  local ok, message = H.inspect(project, key, selected)
  assert(ok, message)
  assert(reaper.Undo_GetCurEntry(project) == current, 'Original state was not restored')
  assert(math.abs(reaper.GetMediaTrackInfo_Value(reaper.GetTrack(project, 0), 'D_VOL') - 0.25) < 1e-8)
  ledger = H.refresh(project, key)
  assert(ledger.rows[current].details:find('-6.02', 1, true), 'Native detail capture missed volume delta')
  H.star(project, key, selected)
  assert(H.navigate(project, key, -1))
  assert(math.abs(reaper.GetMediaTrackInfo_Value(reaper.GetTrack(project, 0), 'D_VOL') - 0.5) < 1e-8)
  assert(H.jump(project, key, ledger.rows[current + 1].id))
  dofile(root .. 'scripts/Dax - Undo Redo History.lua')
end, debug.traceback)
if not success then finish('FAIL\n' .. err); return end
local frames = 0
local function wait_for_ui()
  frames = frames + 1
  if frames < 12 then reaper.defer(wait_for_ui)
  else
    if #messages > 0 then finish('FAIL\n' .. table.concat(messages, '\n'))
    else finish('PASS: native history enumeration, indices, volume inspection/restoration, star navigation and 12 UI frames in REAPER ' .. reaper.GetAppVersion()) end
  end
end
reaper.defer(wait_for_ui)
