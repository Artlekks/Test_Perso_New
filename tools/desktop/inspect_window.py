"""Read-only native geometry witness for companion QA; no window mutations."""
import ctypes as c
from ctypes import wintypes as w
import json
import sys
import windows_appbar as native

native.u.SetProcessDpiAwarenessContext.argtypes = [w.HANDLE]
native.u.SetProcessDpiAwarenessContext(c.c_void_p(-4))
target = int(sys.argv[1])
outer, client = w.RECT(), w.RECT()
if not native.u.GetWindowRect(target, c.byref(outer)):
    raise c.WinError(c.get_last_error())
if not native.u.GetClientRect(target, c.byref(client)):
    raise c.WinError(c.get_last_error())
monitor = native.monitor_info(target)
print(json.dumps({"window": native.rect_value(outer),
                 "client": native.rect_value(client),
                 "monitor": native.rect_value(monitor.monitor),
                 "work_area": native.rect_value(monitor.work),
                 "dpi": native.u.GetDpiForWindow(target)}))
