-- Load this file once via Actions > New action > Load ReaScript, then run it.
local directory = debug.getinfo(1, 'S').source:match('^@(.+[\\/])')
local names = {'Dax - Undo Redo History.lua', 'Dax - Previous starred undo state.lua',
  'Dax - Next starred undo state.lua', 'Dax - First starred undo state.lua',
  'Dax - Last starred undo state.lua', 'Dax - Undo History+ monitor.lua'}
for _, name in ipairs(names) do
  if reaper.AddRemoveReaScript(true, 0, directory .. name, true) == 0 then
    reaper.MB('Could not register ' .. name, 'History Tools', 0)
    reaper.defer(function() end); return
  end
end
reaper.MB('Six History Tools actions are registered. Run Dax - Undo Redo History.\n\nAssign shortcuts to Previous/Next/First/Last starred undo state in the Action List.', 'History Tools', 0)
reaper.defer(function() end)
