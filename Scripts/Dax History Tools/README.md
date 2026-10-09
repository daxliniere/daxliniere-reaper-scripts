# Undo History+

A searchable REAPER history window with starred states and four shortcut actions and a separate always-on monitor.
Requires **REAPER 7.79+** and **ReaImGui 0.9+** (available through ReaPack).
Uses the live undo API. It never reads or writes `.RPP-UNDO`.

## Installation

1. Run `!install.bat` to copy the scripts to your REAPER resource directory.
2. In REAPER, choose Actions > Show action list > New action > Load ReaScript and load `Register History Tools.lua` from `Scripts/Dax History Tools`.
3. Run that registration action once. It adds all six actions to the Main section.
4. Run `Dax - Undo Redo History`. Assign shortcuts or toolbar buttons to the Previous, Next, First and Last starred undo state actions.

You can also load the six `Dax - ...` scripts directly from this repository. Keep `history_core.lua` beside them.

## Use

1. Search matches every space-separated word against action names and captured details, including track/item names. Toggle Starred only to filter bookmarks. Click any column header to sort; click again to reverse it. Time sorts newest first by default, with history order resolving equal timestamps.
2. Click the star column to mark a state. Double-click anywhere on its row (apart from the star button), or select it and click Load selected state, to return to that state. Only the star cell and its button have yellow backgrounds for bookmarks. Current is highlighted; redo action labels are dimmed. Load selected state is disabled when no state is selected or the selected state is already current.
3. Previous/Next star choose the nearest marked state on either side of the current undo position. They work with the window and monitor closed, ignore the search filter, and do not wrap.
   First/Last starred undo state jump to the earliest/latest available bookmark, regardless of the current position. Run the registration action again after upgrading to add these two actions.
4. Refresh reads the complete currently available history, including edits made while the tool was stopped. Auto-refresh polls the live API every 250 ms. No project save is needed. Switch project tabs to view that project's history.
5. The GUI silently launches `Dax - Undo History+ monitor` as a separate REAPER action if it is not running. Closing the GUI only stops the GUI. The monitor remains active until REAPER exits or you terminate its action, and monitors all open project tabs. It checks lightweight change counters every 250 ms and reads full history/snapshots only when a project changes. You can run the monitor action independently, including from your preferred REAPER startup-action setup, to capture before first opening the GUI. Existing history and bookmarks do not require the GUI to stay open. Rerun Register History Tools after upgrading to register the new monitor action.
6. Read selected details compares the preceding and selected undo states while stopped, allowing a main-loop cycle after each load before reading values, then restores your original undo position. The window pauses its own refresh and interaction during this short inspection. This temporarily loads project states and may reload FX. Refresh itself never moves the undo position.
7. Observed project-save states show Saved in the State column and a blue background. A starred saved state keeps its blue row and Saved label, with yellow confined to its star cell. The tool records named projects' clean states when it sees them; it cannot reconstruct historical save points from before monitoring, and a save followed by an edit between polls can be missed.

## Details and limits

Supported values are track/master volume, pan, mute, solo and selection; item volume, position, length, mute, selection and fade lengths; track/item additions, removals and names. Volume displays before/after dB and the dB delta, pan displays signed percentages (negative = left), and item timing displays seconds. Solo values are REAPER's numeric modes.

The API provides entry descriptions and timestamps, but no direct historical value records. The monitor captures a delta only when it observes one new history entry, and accumulates coalesced drag adjustments from their starting values. If multiple edits arrive between polls, entries remain available but uncertain details are left empty. Use Read selected details to recover supported values for older or missed entries. FX parameter, MIDI and envelope changes are not decoded. This is not a promise of details for every REAPER action.

Stars and details are stored through REAPER ExtState separately from project undo data; adding stars does not dirty the project or create undo points. They are identified using a reconciled entry ledger, descriptions and timestamps. Replaced redo branches drop their metadata. Unique surviving entries retain metadata after history trimming. Indistinguishable replacement entries with identical timestamps and descriptions cannot be proven distinct by the API. Alternate redo branches are indicated in tooltips; switch branches using REAPER's native history window, then refresh.

A star does not protect an entry from REAPER's memory limit. If REAPER discards an entry, it can no longer be loaded. For stars to remain usable after restarting REAPER, REAPER itself must retain/reload the underlying undo history; that is independent of this tool. Saved projects are identified by their file path; unsaved tabs use their master-track GUID. Save As starts a separate metadata ledger.

## Development

1. Run `!bump-version.bat` after logic changes and before verification.
2. Run `!verify.bat`. It compiles every Lua file and executes behavior tests using Lua 5.4 through `lupa`. If needed: `python -m pip install --target .tools lupa`.
3. Run `!github-sync.bat` for a full local version snapshot and push to origin. The helper bumps the version if committing changes under the same version as HEAD. No remote is configured in the initial repository.

There is no compilation/build pipeline for these ReaScripts. The automated tests simulate REAPER's API, including execution of the complete window script, standalone navigation, and the independent background monitor. An isolated native smoke test is provided in `tools/host-smoke.ps1`; the initial native test attempt timed out before producing a result in this environment. Interactive testing in REAPER is still needed for layout and host-specific undo/FX behavior.
