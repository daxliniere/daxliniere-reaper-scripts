-- Shared model for the window and standalone navigation actions.
-- Metadata uses REAPER's ExtState; project undo files are never accessed.
local M = {section = 'DaxHistoryTools_v1'}
local required = {'Undo_GetNumEntries', 'Undo_GetCurEntry', 'Undo_GetEntryDesc',
  'Undo_GetEntryTime', 'Undo_SetCurPos', 'Undo_IsEntryAltTree',
  'EnumProjects', 'GetMasterTrack', 'GetTrackGUID', 'IsProjectDirty'}

function M.check()
  for _, name in ipairs(required) do
    if not reaper.APIExists(name) then
      return false, 'REAPER 7.79 or newer is required. Missing API: ' .. name
    end
  end
  return true
end

local function encode(s)
  return tostring(s):gsub('[%%\t\r\n]', function(c) return ('%%%02X'):format(c:byte()) end)
end
local function decode(s)
  return s:gsub('%%(%x%x)', function(v) return string.char(tonumber(v, 16)) end)
end
local function signature(row) return ('%.9f\t%s'):format(row.time, row.desc) end
M.signature = signature

function M.project_key(proj)
  -- Saved projects use their path. The master-track GUID distinguishes unsaved tabs.
  local active, path = reaper.EnumProjects(-1, '')
  if proj ~= 0 and proj ~= active then
    local index = 0
    while true do
      local candidate, candidate_path = reaper.EnumProjects(index, '')
      assert(candidate, 'Project is no longer open.')
      if candidate == proj then path = candidate_path; break end
      index = index + 1
    end
  end
  -- Escape characters that could break an INI key (valid Windows names can include '=').
  local identity = path ~= '' and ('saved:' .. path)
    or ('unsaved:' .. reaper.GetTrackGUID(reaper.GetMasterTrack(proj)))
  identity = identity:gsub('[%%=%c%[%]]', function(c) return ('%%%02X'):format(c:byte()) end)
  return 'project:' .. identity
end

function M.load(key)
  local data = reaper.GetExtState(M.section, key)
  local ledger = {next_id = 1, rows = {}, raw = data}
  -- Persistent ExtState is one INI line. Decode the outer envelope first.
  local payload = data:sub(1, 3) == 'v1:' and decode(data:sub(4)) or data
  for line in payload:gmatch('[^\n]+') do
    local n = line:match('^next=(%d+)$')
    if n then ledger.next_id = tonumber(n)
    else
      local id, time, marks, desc, details = line:match('^(%d+)\t([^\t]+)\t([01][01]?)\t([^\t]*)\t(.*)$')
      if id and tonumber(time) then
        ledger.rows[#ledger.rows + 1] = {id = tonumber(id), time = tonumber(time),
          star = marks:sub(1, 1) == '1', saved = marks:sub(2, 2) == '1',
          desc = decode(desc), details = decode(details)}
      end
    end
  end
  return ledger
end

function M.save(key, ledger)
  local lines = {'next=' .. ledger.next_id}
  for _, row in ipairs(ledger.rows) do
    lines[#lines + 1] = ('%d\t%.9f\t%d%d\t%s\t%s'):format(row.id, row.time,
      row.star and 1 or 0, row.saved and 1 or 0, encode(row.desc), encode(row.details or ''))
  end
  local data = 'v1:' .. encode(table.concat(lines, '\n'))
  if data ~= ledger.raw then
    reaper.SetExtState(M.section, key, data, true)
    ledger.raw = data
  end
end

function M.read(proj)
  local rows = {}
  for index = 0, reaper.Undo_GetNumEntries(proj) - 1 do
    rows[#rows + 1] = {index = index, desc = reaper.Undo_GetEntryDesc(proj, index) or '',
      time = reaper.Undo_GetEntryTime(proj, index),
      branches = reaper.Undo_IsEntryAltTree(proj, index)}
  end
  return rows, reaper.Undo_GetCurEntry(proj)
end

function M.reconcile(ledger, rows)
  local old, prefix = ledger.rows, 0
  while old[prefix + 1] and rows[prefix + 1]
    and signature(old[prefix + 1]) == signature(rows[prefix + 1]) do prefix = prefix + 1 end
  local lookup, counts = {}, {}
  -- If the beginning disappeared (memory trimming), retain uniquely matching entries.
  -- On a replaced redo branch, retain only the common prefix, never stale suffix stars.
  if prefix == 0 and old[1] and rows[1] and signature(old[1]) ~= signature(rows[1]) then
    for _, row in ipairs(old) do
      local sig = signature(row)
      lookup[sig] = lookup[sig] == nil and row or false
    end
    for _, row in ipairs(rows) do
      local sig = signature(row); counts[sig] = (counts[sig] or 0) + 1
    end
  end
  for i, row in ipairs(rows) do
    local prior = i <= prefix and old[i] or nil
    if not prior and counts[signature(row)] == 1 then prior = lookup[signature(row)] end
    if prior then
      row.id, row.star, row.saved, row.details = prior.id, prior.star, prior.saved, prior.details
    else
      row.id, row.star, row.details = ledger.next_id, false, ''
      ledger.next_id = ledger.next_id + 1
    end
  end
  ledger.rows = rows
  return prefix
end

function M.refresh(proj, key)
  local ledger = M.load(key)
  local rows, current = M.read(proj)
  local prefix = M.reconcile(ledger, rows)
  -- A clean state of a named project is its saved state. Record the points we
  -- actually observe; native history does not expose older project-save markers.
  if key:sub(1, 14) == 'project:saved:' and reaper.IsProjectDirty(proj) == 0 then
    local row = rows[current + 1]
    if row then row.saved = true end
  end
  M.save(key, ledger)
  return ledger, current, prefix
end

function M.matches(row, query)
  local haystack = (row.desc .. ' ' .. (row.details or '')):lower()
  -- Every space-separated word must match; punctuation is literal, never a Lua pattern.
  for word in query:lower():gmatch('%S+') do
    if not haystack:find(word, 1, true) then return false end
  end
  return true
end

function M.star(proj, key, id)
  local ledger = M.refresh(proj, key)
  for _, row in ipairs(ledger.rows) do
    if row.id == id then row.star = not row.star; M.save(key, ledger); return true end
  end
  return false
end

function M.jump(proj, key, id)
  local ledger = M.refresh(proj, key)
  for _, row in ipairs(ledger.rows) do
    if row.id == id then
      reaper.Undo_SetCurPos(proj, row.index, 0)
      reaper.UpdateArrange()
      return reaper.Undo_GetCurEntry(proj) == row.index
    end
  end
  return false
end

function M.navigate(proj, key, direction)
  local ledger, current = M.refresh(proj, key)
  local target
  for _, row in ipairs(ledger.rows) do
    if row.star and ((direction < 0 and row.index < current) or (direction > 0 and row.index > current)) then
      if not target or (direction < 0 and row.index > target.index)
        or (direction > 0 and row.index < target.index) then target = row end
    end
  end
  if not target then return false, 'No ' .. (direction < 0 and 'previous' or 'next') .. ' starred state.' end
  return M.jump(proj, key, target.id)
end

function M.navigate_edge(proj, key, last)
  local ledger = M.refresh(proj, key)
  local target
  for _, row in ipairs(ledger.rows) do
    if row.star then
      target = row
      if not last then break end
    end
  end
  if not target then return false, 'No starred states in this project.' end
  return M.jump(proj, key, target.id)
end

function M.snapshot(proj)
  local state = {tracks = {}, items = {}}
  for i = -1, reaper.CountTracks(proj) - 1 do
    local track = i == -1 and reaper.GetMasterTrack(proj) or reaper.GetTrack(proj, i)
    local _, name = reaper.GetTrackName(track)
    state.tracks[reaper.GetTrackGUID(track)] = {name = name,
      volume = reaper.GetMediaTrackInfo_Value(track, 'D_VOL'),
      pan = reaper.GetMediaTrackInfo_Value(track, 'D_PAN'),
      mute = reaper.GetMediaTrackInfo_Value(track, 'B_MUTE'),
      solo = reaper.GetMediaTrackInfo_Value(track, 'I_SOLO'),
      selected = reaper.GetMediaTrackInfo_Value(track, 'I_SELECTED')}
  end
  for i = 0, reaper.CountMediaItems(proj) - 1 do
    local item = reaper.GetMediaItem(proj, i)
    local _, guid = reaper.GetSetMediaItemInfo_String(item, 'GUID', '', false)
    local take = reaper.GetActiveTake(item)
    local _, track_name = reaper.GetTrackName(reaper.GetMediaItemTrack(item))
    state.items[guid] = {name = track_name .. ' / ' .. (take and reaper.GetTakeName(take) or 'Empty item'),
      position = reaper.GetMediaItemInfo_Value(item, 'D_POSITION'),
      length = reaper.GetMediaItemInfo_Value(item, 'D_LENGTH'),
      volume = reaper.GetMediaItemInfo_Value(item, 'D_VOL'),
      mute = reaper.GetMediaItemInfo_Value(item, 'B_MUTE'),
      selected = reaper.GetMediaItemInfo_Value(item, 'B_UISEL'),
      fade_in = reaper.GetMediaItemInfo_Value(item, 'D_FADEINLEN'),
      fade_out = reaper.GetMediaItemInfo_Value(item, 'D_FADEOUTLEN')}
  end
  return state
end

local function db(v) return v > 0 and 20 * math.log(v, 10) or -math.huge end
local function volume_change(a, b)
  local x, y = db(a), db(b)
  local function label(v) return v == -math.huge and '-inf' or ('%.2f'):format(v) end
  local delta = x ~= -math.huge and y ~= -math.huge and (' (%+.2f dB)'):format(y - x) or ''
  return label(x) .. ' -> ' .. label(y) .. ' dB' .. delta
end
local function format_change(prop, a, b)
  if prop == 'selected' then return (a ~= 0 and 'selected' or 'unselected') .. ' -> ' .. (b ~= 0 and 'selected' or 'unselected') end
  if prop == 'volume' then return volume_change(a, b) end
  if prop == 'pan' then return ('%+.1f%% -> %+.1f%% (%+.1f%%)'):format(a * 100, b * 100, (b - a) * 100) end
  if prop == 'mute' then return (a ~= 0 and 'muted' or 'unmuted') .. ' -> ' .. (b ~= 0 and 'muted' or 'unmuted') end
  if prop == 'solo' then return tostring(a) .. ' -> ' .. tostring(b) end
  return ('%.3f -> %.3f s (%+.3f s)'):format(a, b, b - a)
end

function M.diff(before, after)
  local changes = {}
  for _, kind in ipairs({'tracks', 'items'}) do
    local props = kind == 'tracks' and {'volume', 'pan', 'mute', 'solo', 'selected'}
      or {'volume', 'position', 'length', 'mute', 'selected', 'fade_in', 'fade_out'}
    for guid, b in pairs(after[kind]) do
      local a = before[kind][guid]
      if not a then changes[#changes + 1] = b.name .. ': added'
      else
        if a.name ~= b.name then changes[#changes + 1] = a.name .. ': renamed to ' .. b.name end
        for _, prop in ipairs(props) do
          local old_value, new_value = a[prop] or 0, b[prop] or 0
          if math.abs(old_value - new_value) > 1e-9 then
            changes[#changes + 1] = b.name .. ': ' .. prop .. ' ' .. format_change(prop, old_value, new_value)
          end
        end
      end
    end
    for guid, a in pairs(before[kind]) do
      if not after[kind][guid] then changes[#changes + 1] = a.name .. ': removed' end
    end
  end
  table.sort(changes)
  return table.concat(changes, '; ')
end

function M.topology(rows)
  local signatures = {}
  for _, row in ipairs(rows) do signatures[#signatures + 1] = signature(row) end
  return table.concat(signatures, '\n')
end

function M.inspect(proj, key, id)
  if reaper.GetPlayStateEx(proj) ~= 0 then return false, 'Stop playback/recording before reading historical details.' end
  local ledger, original = M.refresh(proj, key)
  local selected
  for _, row in ipairs(ledger.rows) do if row.id == id then selected = row end end
  if not selected then return false, 'This state is no longer in the history.' end
  if selected.index == 0 then return false, 'The first state has no preceding state to compare.' end
  local topology = M.topology(ledger.rows)
  local details
  reaper.PreventUIRefresh(1)
  local ok, err = xpcall(function()
    reaper.Undo_SetCurPos(proj, selected.index - 1, 0)
    assert(reaper.Undo_GetCurEntry(proj) == selected.index - 1, 'Could not load preceding state.')
    local before = M.snapshot(proj)
    reaper.Undo_SetCurPos(proj, selected.index, 0)
    assert(reaper.Undo_GetCurEntry(proj) == selected.index, 'Could not load selected state.')
    details = M.diff(before, M.snapshot(proj))
  end, debug.traceback)
  -- Always attempt restoration, including when snapshots or state loading fail.
  local restore_index = original
  local restoration_rows = M.read(proj)
  if M.topology(restoration_rows) ~= topology then
    -- If the host changes history during a load, the original index may refer to a
    -- different state. Restore by a unique original signature instead of guessing.
    restore_index = nil
    local original_row = ledger.rows[original + 1]
    if original_row then
      for _, row in ipairs(restoration_rows) do
        if signature(row) == signature(original_row) then
          if restore_index ~= nil then restore_index = nil; break end
          restore_index = row.index
        end
      end
    end
  end
  local restore_ok, restore_err = false, 'Original state could not be uniquely identified.'
  if restore_index ~= nil then restore_ok, restore_err = pcall(reaper.Undo_SetCurPos, proj, restore_index, 0) end
  reaper.PreventUIRefresh(-1)
  reaper.UpdateArrange()
  if not restore_ok or reaper.Undo_GetCurEntry(proj) ~= restore_index then
    return false, 'Could not restore original undo position. ' .. tostring(restore_err or '')
  end
  if not ok then return false, err end
  local rows = M.read(proj)
  if M.topology(rows) ~= topology then return false, 'History changed during inspection; details were not saved.' end
  selected.details = details ~= '' and details or 'No supported value changes (FX, MIDI and envelopes are not decoded).'
  M.save(key, ledger)
  return true, 'Details read; original undo position restored.'
end

-- Capture only a single new undo entry observed between snapshots. Multiple missed
-- states cannot be assigned a trustworthy delta and remain available for inspection.
function M.observe(session, rows, current, snapshot, prefix)
  local previous = session.rows
  if previous and #rows == #previous + 1 and prefix == #previous
    and current == #rows - 1 and session.current == #previous - 1 then
    session.origin = session.snapshot
    session.origin_id = rows[#rows].id
  elseif not previous or current ~= session.current or M.topology(previous) ~= M.topology(rows) then
    session.origin, session.origin_id = nil, nil
  end
  local row = rows[current + 1]
  if row and session.origin_id == row.id and session.origin then
    local details = M.diff(session.origin, snapshot)
    if details ~= '' then row.details = details end
  end
  session.rows, session.current, session.snapshot = rows, current, snapshot
end


function M.sort_rows(rows, column, descending, current)
  local function value(row)
    if column == 0 then return row.star and 1 or 0 end
    if column == 1 then return (row.index == current and 'Current' or (row.index > current and 'Redo' or 'Undo')) .. (row.saved and ' / Saved' or '') end
    if column == 2 then return row.time end
    if column == 3 then return row.desc:lower() end
    return (row.details or ''):lower()
  end
  table.sort(rows, function(a, b)
    local av, bv = value(a), value(b)
    if av == bv then return descending and a.index > b.index or (not descending and a.index < b.index) end
    if descending then return av > bv end
    return av < bv
  end)
end

function M.can_load(rows, id, current)
  for _, row in ipairs(rows) do if row.id == id then return row.index ~= current end end
  return false
end

-- Deferred inspection gives REAPER a main-loop cycle to apply each undo state.
-- No UI-refresh lock is held across frames, and restoration runs on every failure.
function M.inspect_async(proj, key, id, done)
  if reaper.GetPlayStateEx(proj) ~= 0 then done(false, 'Stop playback/recording before reading details.'); return end
  local ledger, original = M.refresh(proj, key)
  local selected
  for _, row in ipairs(ledger.rows) do if row.id == id then selected = row end end
  if not selected or selected.index == 0 then done(false, 'Select a state with a preceding state to compare.'); return end
  local topology = M.topology(ledger.rows)
  local before, details, restoring = nil, nil, false
  local function restore(ok, message)
    if restoring then return end
    restoring = true
    local success, err = pcall(function()
      local rows = M.read(proj)
      local restore_index = original
      if M.topology(rows) ~= topology then
        restore_index = nil
        local original_row = ledger.rows[original + 1]
        for _, row in ipairs(rows) do
          if original_row and signature(row) == signature(original_row) then
            assert(restore_index == nil, 'Original state is ambiguous after history changed.')
            restore_index = row.index
          end
        end
      end
      assert(restore_index ~= nil, 'Original state is no longer available.')
      reaper.Undo_SetCurPos(proj, restore_index, 0)
      reaper.UpdateArrange()
      reaper.defer(function()
        local restored, problem = xpcall(function()
          assert(reaper.Undo_GetCurEntry(proj) == restore_index, 'Could not restore original undo position.')
          assert(M.topology(M.read(proj)) == topology, 'History changed during inspection; details not saved.')
          if ok then
            -- Reload metadata so concurrent bookmark actions cannot be overwritten.
            local latest = M.refresh(proj, key)
            for _, row in ipairs(latest.rows) do
              if row.id == id then row.details = details ~= '' and details or 'No supported changes found (FX, MIDI and envelopes are not decoded).' end
            end
            M.save(key, latest)
          end
        end, debug.traceback)
        done(ok and restored, not restored and problem or message)
      end)
    end)
    if not success then done(false, 'Could not restore original state: ' .. tostring(err)) end
  end
  local function stage(index, callback)
    local ok, err = pcall(reaper.Undo_SetCurPos, proj, index, 0)
    if not ok then restore(false, tostring(err)); return end
    reaper.UpdateArrange()
    reaper.defer(function()
      local success, problem = xpcall(function()
        assert(reaper.GetPlayStateEx(proj) == 0, 'Playback started during inspection.')
        assert(reaper.Undo_GetCurEntry(proj) == index, 'REAPER did not load the requested state.')
        assert(M.topology(M.read(proj)) == topology, 'History changed during inspection.')
        callback()
      end, debug.traceback)
      if not success then restore(false, problem) end
    end)
  end
  stage(selected.index - 1, function()
    before = M.snapshot(proj)
    stage(selected.index, function()
      details = M.diff(before, M.snapshot(proj))
      restore(true, 'Details read; original undo position restored.')
    end)
  end)
end

return M
