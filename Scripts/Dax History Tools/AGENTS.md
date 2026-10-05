# REAPER History Tools

This repository contains Lua ReaScripts, not a compiled application. No build step is required.
Use UTF-8 for all source and documentation. Preserve comments.
After logic changes run `!bump-version.bat`, then `!verify.bat`.
Back up every even patch version with `!github-sync.bat`; report a missing GitHub remote.
Keep all action scripts beside `history_core.lua`. Require REAPER 7.79+ and ReaImGui 0.9+.
Use the native undo APIs. Do not read or modify `.RPP-UNDO` files.
Never move the undo position during refresh, search, starring, or passive capture.
Only explicit navigation or detail inspection may load undo states. Detail inspection must restore the original state and refuse playback/recording.
Bookmarks are metadata, not protected undo states. Never create undo entries for metadata changes.
Version lives in VERSION; scripts read it rather than duplicate it.
