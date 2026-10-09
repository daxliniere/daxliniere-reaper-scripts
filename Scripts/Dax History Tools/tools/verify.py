"""Execute Lua model tests in Lua 5.4; no REAPER project is modified."""
from pathlib import Path
import sys
import re

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / '.tools'))
sys.path.insert(0, str(ROOT / '.tools/testdeps'))
try:
    from lupa.lua54 import LuaRuntime
except ImportError:
    raise SystemExit('Verification needs lupa: python -m pip install --target .tools lupa')

lua = LuaRuntime(unpack_returned_tuples=True)
for path in (ROOT / 'scripts').glob('*.lua'):
    result = lua.eval('function(s, name) local f, err = load(s, name); return f ~= nil, err end')(
        path.read_text(encoding='utf-8'), str(path))
    if not result[0]:
        raise SystemExit(f'{path.name}: {result[1]}')
print('PASS: all action scripts compile in Lua 5.4')
native_doc_path = ROOT / '.tools/reascripthelp.html'
if not native_doc_path.exists():
    import urllib.request
    native_doc_path.parent.mkdir(exist_ok=True)
    native_doc_path.write_bytes(urllib.request.urlopen(
        'https://www.reaper.fm/sdk/reascript/reascripthelp.html', timeout=20).read())
native_doc = native_doc_path.read_text(encoding='utf-8')
documented = set(re.findall(r'\breaper\.(\w+)\s*\(', native_doc))
assert len(documented) > 500, 'Could not parse the native REAPER API reference'
used = set()
for path in (ROOT / 'scripts').glob('*.lua'):
    used.update(re.findall(r'\breaper\.(\w+)\s*\(', path.read_text(encoding='utf-8')))
used = {name for name in used if not name.startswith('ImGui_')}
missing = sorted(used - documented)
if missing:
    raise SystemExit(f'Undocumented native REAPER calls: {missing}')
print(f'PASS: all {len(used)} native REAPER calls exist in the official API reference')
doc_path = Path.home() / 'AppData/Roaming/REAPER/Data/reaper_imgui_doc.html'
# The sandbox account has a different home; use the actual REAPER resource path when present.
if not doc_path.exists():
    doc_path = Path('C:/Users/dax/AppData/Roaming/REAPER/Data/reaper_imgui_doc.html')
if doc_path.exists():
    doc = doc_path.read_text(encoding='utf-8')
    source = (ROOT / 'scripts/Dax - Undo Redo History.lua').read_text(encoding='utf-8')
    names = set(re.findall(r'ImGui\.(\w+)', source))
    missing = [name for name in sorted(names) if f'id="{name}"' not in doc]
    if missing:
        raise SystemExit(f'ReaImGui documentation missing members: {missing}')
    print(f'PASS: {len(names)} ImGui members exist in installed API documentation')
lua.globals().core_path = str(ROOT / 'scripts' / 'history_core.lua')
lua.execute((ROOT / 'tests' / 'history_spec.lua').read_text(encoding='utf-8'))
ui = LuaRuntime(unpack_returned_tuples=True)
ui.globals().window_path = str(ROOT / 'scripts' / 'Dax - Undo Redo History.lua')
ui.globals().previous_path = str(ROOT / 'scripts' / 'Dax - Previous starred undo state.lua')
ui.execute((ROOT / 'tests' / 'window_spec.lua').read_text(encoding='utf-8'))
print(f'PASS: history behavior verified at version {(ROOT / "VERSION").read_text().strip()}')
