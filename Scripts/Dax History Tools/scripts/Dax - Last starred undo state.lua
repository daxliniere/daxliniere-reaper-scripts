-- Jump to the latest bookmark, including when the history window is closed.
local directory = debug.getinfo(1, 'S').source:match('^@(.+[\\/])')
local H = dofile(directory .. 'history_core.lua')
local ok, why = H.check()
if not ok then reaper.MB(why, 'Undo/Redo History', 0)
else
  local project = reaper.EnumProjects(-1, '')
  local moved, message = H.navigate_edge(project, H.project_key(project), true)
  if not moved then reaper.ShowConsoleMsg((message or 'State could not be loaded.') .. '\n') end
end
-- Suppress REAPER's automatic script undo point.
reaper.defer(function() end)
