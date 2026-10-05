-- Bookmark navigation also works when the history monitor is stopped.
local directory = debug.getinfo(1, 'S').source:match('^@(.+[\\/])')
local H = dofile(directory .. 'history_core.lua')
local ok, why = H.check()
if not ok then reaper.MB(why, 'Undo/Redo History', 0)
else
  local project = reaper.EnumProjects(-1, '')
  local moved, message = H.navigate(project, H.project_key(project), -1)
  if not moved then reaper.ShowConsoleMsg((message or 'State could not be loaded.') .. '\n') end
end
-- Suppress REAPER's automatic script undo point.
reaper.defer(function() end)
