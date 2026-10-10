"""Windows-only companion AppBar sidecar. Never changes SPI_SETWORKAREA.

Owns shell registration for the companion HWND and a sidecar message pump; watches the game
process handle so a crashed/terminated game releases the reservation as well.
Commands/status are atomic JSON files, scoped to one game PID. No game data.
"""
import argparse
import ctypes as c
from ctypes import wintypes as w
import json
import os
from pathlib import Path
import time
import msvcrt

COMMAND_POLL_SECONDS = 0.008 # Respond within one 60 Hz drag frame; no game-side interpolation.

u = c.WinDLL("user32", use_last_error=True)
s = c.WinDLL("shell32", use_last_error=True)
k = c.WinDLL("kernel32", use_last_error=True)
LRESULT = c.c_ssize_t
WNDPROC = c.WINFUNCTYPE(LRESULT, w.HWND, w.UINT, w.WPARAM, w.LPARAM)

class AppData(c.Structure):
    _fields_ = [("cbSize", w.DWORD), ("hWnd", w.HWND), ("callback", w.UINT),
                ("edge", w.UINT), ("rect", w.RECT), ("param", w.LPARAM)]

class Monitor(c.Structure):
    _fields_ = [("size", w.DWORD), ("monitor", w.RECT), ("work", w.RECT), ("flags", w.DWORD)]

class WindowClass(c.Structure):
    _fields_ = [("style", w.UINT), ("proc", WNDPROC), ("extra", c.c_int),
                ("window_extra", c.c_int), ("instance", w.HINSTANCE), ("icon", w.HICON),
                ("cursor", w.HANDLE), ("brush", w.HBRUSH), ("menu", w.LPCWSTR), ("name", w.LPCWSTR)]

u.DefWindowProcW.restype = LRESULT
u.DefWindowProcW.argtypes = [w.HWND, w.UINT, w.WPARAM, w.LPARAM]
u.CreateWindowExW.restype = w.HWND
u.CreateWindowExW.argtypes = [w.DWORD, w.LPCWSTR, w.LPCWSTR, w.DWORD, c.c_int, c.c_int, c.c_int, c.c_int, w.HWND, w.HMENU, w.HINSTANCE, c.c_void_p]
u.MonitorFromWindow.restype = w.HANDLE
u.MonitorFromWindow.argtypes = [w.HWND, w.DWORD]
u.GetMonitorInfoW.argtypes = [w.HANDLE, c.POINTER(Monitor)]
u.SetWindowPos.argtypes = [w.HWND, w.HWND, c.c_int, c.c_int, c.c_int, c.c_int, w.UINT]
u.GetWindowLongPtrW.argtypes = [w.HWND, c.c_int]
u.GetWindowLongPtrW.restype = c.c_ssize_t
u.SetWindowLongPtrW.argtypes = [w.HWND, c.c_int, c.c_ssize_t]
u.SetWindowLongPtrW.restype = c.c_ssize_t
u.GetWindowRect.argtypes = [w.HWND, c.POINTER(w.RECT)]
u.IsWindow.argtypes = [w.HWND]
u.DestroyWindow.argtypes = [w.HWND]
u.ShowWindow.argtypes = [w.HWND, c.c_int]
u.SetLayeredWindowAttributes.argtypes = [w.HWND, w.DWORD, w.BYTE, w.DWORD]
s.SHAppBarMessage.argtypes = [w.DWORD, c.POINTER(AppData)]
s.SHAppBarMessage.restype = c.c_size_t
k.OpenProcess.argtypes = [w.DWORD, w.BOOL, w.DWORD]
k.OpenProcess.restype = w.HANDLE
k.WaitForSingleObject.argtypes = [w.HANDLE, w.DWORD]
k.CloseHandle.argtypes = [w.HANDLE]
k.CreateFileW.argtypes = [w.LPCWSTR, w.DWORD, w.DWORD, c.c_void_p, w.DWORD, w.DWORD, w.HANDLE]
k.CreateFileW.restype = w.HANDLE

def read_command(path):
    # Allow atomic replacement while this read is open. Ordinary Python CRT
    # reads can deny FILE_SHARE_DELETE and sporadically reject Godot's rename.
    handle = k.CreateFileW(str(path), 0x80000000, 7, None, 3, 0x80, None)
    if handle == c.c_void_p(-1).value:
        raise FileNotFoundError(path)
    descriptor = msvcrt.open_osfhandle(handle, os.O_RDONLY)
    with os.fdopen(descriptor, encoding="utf-8") as stream:
        return json.load(stream)

def rect_value(r):
    return [r.left, r.top, r.right, r.bottom]

def monitor_info(hwnd):
    info = Monitor(size=c.sizeof(Monitor))
    if not u.GetMonitorInfoW(u.MonitorFromWindow(hwnd, 2), c.byref(info)):
        raise c.WinError(c.get_last_error())
    return info

def atomic_json(path, payload):
    temp = path.with_suffix(".tmp")
    temp.write_text(json.dumps(payload), encoding="utf-8")
    # Godot may hold the old status file briefly while reading it. Windows
    # denies replacement during that read; retry this transient sharing lock
    # without tearing down a healthy AppBar. Permanent failures still raise.
    for attempt in range(25):
        try:
            os.replace(temp, path)
            return
        except PermissionError:
            if attempt == 24:
                raise
            time.sleep(.01)

class AppBar:
    def __init__(self):
        self.registered = False
        self.dirty = False
        self.command = {}
        self.baseline = None
        self.target_style = None
        self.callback = u.RegisterWindowMessageW("FishingCompanionAppBar")
        self.proc = WNDPROC(self.window_proc)
        self.cls = WindowClass(proc=self.proc, name="FishingCompanionReservation")
        if not u.RegisterClassW(c.byref(self.cls)):
            raise c.WinError(c.get_last_error())
        # Invisible visual, but a real visible tool window for shell registration.
        self.hwnd = u.CreateWindowExW(0x80000 | 0x80 | 0x08000000,
            self.cls.name, "Fishing Companion Reservation", 0x80000000,
            0, 0, 1, 1, None, None, None, None)
        if not self.hwnd:
            raise c.WinError(c.get_last_error())
        u.SetLayeredWindowAttributes(self.hwnd, 0, 0, 2)
        self.data = AppData(cbSize=c.sizeof(AppData), hWnd=self.hwnd,
                            callback=self.callback, edge=2)

    def window_proc(self, hwnd, msg, wp, lp):
        if msg == self.callback and wp == 1:  # ABN_POSCHANGED
            self.dirty = True
        if msg in (0x7E, 0x2E0, 0x1A):  # display/DPI/work-area changed
            self.dirty = True
        return u.DefWindowProcW(hwnd, msg, wp, lp)

    def release(self):
        if self.registered:
            s.SHAppBarMessage(1, c.byref(self.data))
            self.registered = False
        u.ShowWindow(self.hwnd, 0)

    def apply(self, command):
        self.command = command
        target = int(command["hwnd"])
        if not u.IsWindow(target):
            raise RuntimeError("Companion HWND is no longer valid")
        if not command.get("docked", False):
            self.release()
            if command.get("widget", False):
                info = monitor_info(target)
                width, height = int(command["width"]), int(command["height"])
                left = command.get("edge") == "left"
                x = info.monitor.left if left else info.monitor.right - width
                y = info.work.top + (info.work.bottom - info.work.top - height) // 2
                # A tiny topmost overlay, not a full-height shell reservation.
                u.SetWindowPos(target, w.HWND(-1), x, y, width, height, 0x10)
            else:
                if self.target_style is not None:
                    u.SetWindowLongPtrW(target, -20, self.target_style)
                # Float releases ownership without restoring a historic rectangle.
                u.SetWindowPos(target, w.HWND(-2), 0, 0, 0, 0, 0x13)
                if command.get("restore_rect"):
                    x, y, width, height = map(int, command["restore_rect"])
                    # Ordered with widget commands, avoiding a late widget resize
                    # overwriting a Godot-side floating expansion.
                    u.SetWindowPos(target, None, x, y, width, height, 0x14)
            return self.status(target)
        info = monitor_info(target)
        if self.target_style is None:
            self.target_style = u.GetWindowLongPtrW(target, -20)
        # Dock/widget chrome is a tool window. Desktop work-area rearrangement
        # applies to ordinary application windows, not floating tool surfaces.
        u.SetWindowLongPtrW(target, -20, self.target_style | 0x80)
        if not self.registered:
            self.baseline = rect_value(info.work)
            # Register the visible companion, not the message-pump window.
            # Otherwise Windows treats the game as an ordinary window and
            # moves it into the newly reduced work area during ABM_SETPOS,
            # creating a visible intermediate jump before SetWindowPos.
            self.data.hWnd = target
            if not s.SHAppBarMessage(0, c.byref(self.data)):
                raise RuntimeError("Shell rejected ABM_NEW")
            self.registered = True
        width = max(48, min(int(command["width"]), info.monitor.right-info.monitor.left))
        r = info.monitor
        left = command.get("edge", "right") == "left"
        self.data.edge = 0 if left else 2
        self.data.rect = w.RECT(r.left, r.top, r.left+width, r.bottom) if left else w.RECT(r.right-width, r.top, r.right, r.bottom)
        s.SHAppBarMessage(2, c.byref(self.data))  # shell respects taskbar/other bars
        if left:
            self.data.rect.right = self.data.rect.left + width
        else:
            self.data.rect.left = self.data.rect.right - width
        s.SHAppBarMessage(3, c.byref(self.data))
        r = self.data.rect
        height = min(int(command["height"]), r.bottom-r.top)
        # Borderless Godot client = full native outer footprint. No DPI conversion
        # guess: both processes are per-monitor aware and operate in physical px.
        u.SetWindowPos(target, None, r.left, r.top+(r.bottom-r.top-height)//2,
                       width, height, 0x14)
        self.dirty = False  # ignore notifications from our own negotiation
        return self.status(target)

    def status(self, target):
        info = monitor_info(target)
        actual = w.RECT()
        u.GetWindowRect(target, c.byref(actual))
        return {"registered": self.registered, "work_area": rect_value(info.work),
                "monitor": rect_value(info.monitor), "reservation": rect_value(self.data.rect),
                "window": rect_value(actual), "baseline": self.baseline,
                "sequence": self.command.get("sequence", 0), "edge":self.command.get("edge","right"), "error": ""}

def main():
    args = argparse.ArgumentParser()
    args.add_argument("--pid", type=int, required=True)
    args.add_argument("--command", type=Path, required=True)
    args.add_argument("--status", type=Path, required=True)
    options = args.parse_args()
    # Per-monitor-v2: do not virtualize native coordinates on mixed-DPI screens.
    u.SetProcessDpiAwarenessContext.argtypes = [w.HANDLE]
    u.SetProcessDpiAwarenessContext(c.c_void_p(-4))
    process = k.OpenProcess(0x100000, False, options.pid)
    if not process:
        raise c.WinError(c.get_last_error())
    bar = AppBar()
    last = None
    try:
        message = w.MSG()
        while k.WaitForSingleObject(process, 0) == 258:
            while u.PeekMessageW(c.byref(message), None, 0, 0, 1):
                u.TranslateMessage(c.byref(message))
                u.DispatchMessageW(c.byref(message))
            try:
                command = read_command(options.command)
            except (FileNotFoundError, json.JSONDecodeError, PermissionError):
                time.sleep(COMMAND_POLL_SECONDS)
                continue
            if command.get("close"):
                break
            if command != last or bar.dirty:
                atomic_json(options.status, bar.apply(command))
                last = command
            time.sleep(COMMAND_POLL_SECONDS)
    except Exception as error:
        options.status.with_suffix(".error.txt").write_text(repr(error), encoding="utf-8")
        atomic_json(options.status, {"registered": False, "error": str(error)})
        raise
    finally:
        bar.release()
        if bar.command and u.IsWindow(int(bar.command["hwnd"])):
            atomic_json(options.status, bar.status(int(bar.command["hwnd"])))
        u.DestroyWindow(bar.hwnd)
        k.CloseHandle(process)

if __name__ == "__main__":
    main()
