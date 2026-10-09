local store, queue, exit_handlers = {}, {}, {}
local project, tick, changes, current, snapshots = {}, 1, 0, 0, 0
local entries = {{desc='Initial',time=1,volume=1}}
reaper = {
 APIExists=function() return true end,
 GetExtState=function(s,k) return store[s..k] or '' end,
 SetExtState=function(s,k,v) store[s..k]=v end,
 DeleteExtState=function(s,k) store[s..k]=nil end,
 EnumProjects=function(i) if i == -1 or i == 0 then return project,'C:/Music/Monitor.rpp' end end,
 GetProjectStateChangeCount=function() return changes end,
 IsProjectDirty=function() return 1 end,
 Undo_GetCurEntry=function() return current end,
 Undo_GetNumEntries=function() return #entries end,
 Undo_GetEntryDesc=function(_,i) return entries[i+1].desc end,
 Undo_GetEntryTime=function(_,i) return entries[i+1].time end,
 Undo_IsEntryAltTree=function() return 0 end,
 time_precise=function() tick=tick+0.1; return tick end,
 defer=function(f) queue[#queue+1]=f end,
 atexit=function(f) exit_handlers[#exit_handlers+1]=f end,
 CountTracks=function() snapshots=snapshots+1;return 0 end,
 GetMasterTrack=function() return 'master' end,
 GetTrackGUID=function() return '{master}' end,
 GetTrackName=function() return true,'Master' end,
 GetMediaTrackInfo_Value=function(_,p) return p=='D_VOL' and entries[current+1].volume or 0 end,
 CountMediaItems=function() return 0 end,
 ShowConsoleMsg=function(s) error(s) end,
}
local function frames(n) for _=1,n do assert(#queue>0,'Monitor stopped');table.remove(queue,1)() end end
local H=dofile(core_path)
dofile(monitor_path)
assert(snapshots==1,'Monitor must take an initial baseline')
frames(20)
assert(snapshots==1,'Idle monitor must not reread history snapshots')
local owner=store[H.section..'monitor_owner']
dofile(monitor_path)
assert(store[H.section..'monitor_owner']==owner,'Duplicate monitor must not replace its owner')
entries[2]={desc='Volume',time=2,volume=0.5};current=1;changes=1
local key=H.project_key(project)
H.refresh(project,key) -- GUI wins the refresh race before capture.
frames(10)
local ledger=H.refresh(project,key)
assert(ledger.rows[2].details:find('-6.02',1,true),'GUI refresh must not make background capture miss a new edit')
local baseline=snapshots
store[H.section..'monitor_pause']=tostring(tick+30)
entries[3]={desc='Temporary inspection',time=3,volume=0.25};current=2;changes=2
frames(10)
assert(snapshots==baseline,'Inspection must pause background capture')
store[H.section..'monitor_pause']=''
frames(10)
ledger=H.refresh(project,key)
assert(ledger.rows[3].details=='','Resuming after inspection must reset the baseline')
assert(store[H.section..'monitor_heartbeat'],'Monitor must still be alive after simulated GUI work')
print('PASS: independent monitor singleton, idle gating, GUI-refresh race, inspection pause and baseline reset')
