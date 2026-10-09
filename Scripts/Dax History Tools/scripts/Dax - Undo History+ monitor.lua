-- Independent, silent background capture; no GUI or ImGui dependency.
local directory = debug.getinfo(1, 'S').source:match('^@(.+[\\/])')
local H = dofile(directory .. 'history_core.lua')
local ok, why = H.check()
if not ok then reaper.ShowConsoleMsg('Undo History+ monitor: ' .. why .. '\n'); reaper.defer(function() end); return end
local section = H.section
local now = reaper.time_precise()
local last = tonumber(reaper.GetExtState(section, 'monitor_heartbeat'))
if last and now >= last and now - last < 2 then reaper.defer(function() end); return end
local owner = tostring(now) .. ':' .. tostring({})
reaper.SetExtState(section, 'monitor_owner', owner, false)
reaper.SetExtState(section, 'monitor_heartbeat', tostring(now), false)
local sessions, last_poll, paused = {}, -10, false
local reset = reaper.GetExtState(section, 'monitor_reset')
reaper.atexit(function()
  if reaper.GetExtState(section, 'monitor_owner') == owner then
    reaper.DeleteExtState(section, 'monitor_heartbeat', false)
    reaper.DeleteExtState(section, 'monitor_owner', false)
  end
end)
local function loop()
  if reaper.GetExtState(section, 'monitor_owner') ~= owner then return end
  local tick = reaper.time_precise()
  reaper.SetExtState(section, 'monitor_heartbeat', tostring(tick), false)
  if tick - last_poll >= 0.25 then
    last_poll = tick
    local pause_until = tonumber(reaper.GetExtState(section, 'monitor_pause')) or 0
    local requested = reaper.GetExtState(section, 'monitor_reset')
    if pause_until > tick then paused = true
    else
      if paused or requested ~= reset then sessions = {}; paused = false; reset = requested end
      local live, index = {}, 0
      while true do
        local project = reaper.EnumProjects(index, '')
        if not project then break end
        index = index + 1
        local key = H.project_key(project)
        live[key] = true
        local session = sessions[key] or {}; sessions[key] = session
        local state = reaper.GetProjectStateChangeCount(project)
        local current = reaper.Undo_GetCurEntry(project)
        local count = reaper.Undo_GetNumEntries(project)
        local dirty = reaper.IsProjectDirty(project)
        -- Full history and track/item snapshots are read only when a project changes.
        if session.change ~= state or session.position ~= current or session.count ~= count or session.dirty ~= dirty then
          local ledger, position = H.refresh(project, key)
          -- Compare against our own baseline: the GUI may already have refreshed
          -- the metadata ledger before the monitor observes a newly added entry.
          local prefix = 0
          while session.rows and session.rows[prefix + 1] and ledger.rows[prefix + 1]
            and H.signature(session.rows[prefix + 1]) == H.signature(ledger.rows[prefix + 1]) do prefix = prefix + 1 end
          H.observe(session, ledger.rows, position, H.snapshot(project), prefix)
          H.save(key, ledger)
          session.change, session.position, session.count, session.dirty = state, current, count, dirty
        end
      end
      for key in pairs(sessions) do if not live[key] then sessions[key] = nil end end
    end
  end
  reaper.defer(function()
    local success, err = xpcall(loop, debug.traceback)
    if not success then reaper.ShowConsoleMsg('Undo History+ monitor stopped: ' .. tostring(err) .. '\n') end
  end)
end
local success, err = xpcall(loop, debug.traceback)
if not success then reaper.ShowConsoleMsg('Undo History+ monitor stopped: ' .. tostring(err) .. '\n') end
