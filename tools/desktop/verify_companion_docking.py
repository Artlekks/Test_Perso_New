"""Disposable Windows integration QA: normal/maximized window + crash cleanup.
Runs only the isolated Godot docking fixture, never terminates an existing game.
"""
import argparse
import ctypes as c
from ctypes import wintypes as w
import json
from pathlib import Path
import subprocess
import time
import windows_appbar as native

def wait_for(predicate, seconds=20):
    end = time.monotonic()+seconds
    while time.monotonic()<end:
        result = predicate()
        if result:
            return result
        time.sleep(.05)
    raise AssertionError("Timed out waiting for native QA state")

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--godot", type=Path, required=True)
    options = parser.parse_args()
    project = Path(__file__).resolve().parents[2]
    output = project/"build/desktop-docking"
    output.mkdir(parents=True,exist_ok=True)
    fixture = output/"native-fixture.json"
    if fixture.exists():
        fixture.unlink()
    native.u.SetProcessDpiAwarenessContext.argtypes = [w.HANDLE]
    native.u.SetProcessDpiAwarenessContext(c.c_void_p(-4))
    process = subprocess.Popen([str(options.godot),"--path",str(project),"--rendering-method","gl_compatibility",
        "--script","res://scripts/qa/desktop_companion_docking_qa.gd","--log-file",
        "res://build/desktop-docking/witness-game.log","--","--hold-docked"],creationflags=subprocess.CREATE_NO_WINDOW)
    witness = None
    checks = []
    try:
        info = wait_for(lambda: json.loads(fixture.read_text()) if fixture.exists() else None)
        status_path = Path(info["status"])
        def active():
            try:
                state = json.loads(status_path.read_text())
                ready = "DOCK QA HOLD READY" in (output/"witness-game.log").read_text(errors="replace")
                return state if ready and state.get("registered") and state.get("edge") == "right" else None
            except (FileNotFoundError,json.JSONDecodeError,PermissionError):
                return None
        state = wait_for(active,120)
        witness = native.u.CreateWindowExW(0,"STATIC","Companion QA Normal Window",0x00CF0000,
            state["work_area"][0]+20,state["work_area"][1]+20,600,400,None,None,None,None)
        assert witness
        native.u.ShowWindow(witness,3)  # SW_MAXIMIZE: ordinary OS maximization
        time.sleep(.5)
        native.u.GetClientRect.argtypes = [w.HWND,c.POINTER(w.RECT)]
        native.u.ClientToScreen.argtypes = [w.HWND,c.POINTER(w.POINT)]
        client = w.RECT()
        native.u.GetClientRect(witness,c.byref(client))
        corner = w.POINT(client.right,client.bottom)
        native.u.ClientToScreen(witness,c.byref(corner))
        assert corner.x == state["work_area"][2],(corner.x,state)
        checks.append({"check":"ordinary maximized client respects AppBar", "client_right":corner.x,
                       "work_area":state["work_area"],"reservation":state["reservation"]})
        baseline = info["baseline"]
        # Abnormal exit: bypasses Godot _exit_tree, proving sidecar watchdog.
        process.terminate()
        process.wait(timeout=8)
        def restored():
            current = native.monitor_info(witness)
            return native.rect_value(current.work)==baseline
        wait_for(restored,8)
        checks.append({"check":"terminated game releases AppBar", "restored_work_area":baseline})
        process = subprocess.Popen([str(options.godot),"--path",str(project),"--rendering-method","gl_compatibility",
            "--script","res://scripts/qa/desktop_companion_docking_qa.gd","--log-file",
            "res://build/desktop-docking/normal-close-game.log"],creationflags=subprocess.CREATE_NO_WINDOW)
        assert process.wait(timeout=120) == 0
        wait_for(restored,8)
        checks.append({"check":"normal docked game close releases AppBar", "restored_work_area":baseline})
        (output/"native-witness-report.json").write_text(json.dumps(checks,indent=2))
        print("Windows AppBar Witness QA: 3/3")
        print(json.dumps(checks))
    finally:
        if process.poll() is None:
            process.terminate()
            process.wait(timeout=8)
        if witness:
            native.u.DestroyWindow(witness)

if __name__ == "__main__":
    main()
