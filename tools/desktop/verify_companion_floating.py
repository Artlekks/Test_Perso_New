"""Disposable native Float ownership witness; never operates on an existing app."""
import sys,subprocess,time,json,ctypes as c, argparse
from pathlib import Path
sys.path.insert(0,str(Path('tools/desktop').resolve()))
import windows_appbar as n
n.u.SetProcessDpiAwarenessContext.argtypes=[n.w.HANDLE]
n.u.SetProcessDpiAwarenessContext(c.c_void_p(-4))
project=Path(__file__).resolve().parents[2]
import os
os.chdir(project)
out=Path('build/mobile-web/safe-rectangle');out.mkdir(parents=True,exist_ok=True); info=out/'floating-witness.json'; done=out/'floating-witness.done'
for p in [info,done]:
 if p.exists(): p.unlink()
parser=argparse.ArgumentParser()
parser.add_argument('--godot',default=r'C:\Users\Alucard7th\Desktop\_Projects\Fishing Game\Godot_v4.7.2-stable_win64.exe')
gd=parser.parse_args().godot
log=(out/'floating.log').open('w')
p=subprocess.Popen([gd,'--path','.', '--rendering-method','gl_compatibility','--script','res://scripts/qa/desktop_floating_qa.gd','--','--witness'],stdout=log,stderr=subprocess.STDOUT)
checks=[]
witness=None
callback=None
def check(ok,label,data=None):
 checks.append({'pass':bool(ok),'check':label,'data':data})
def rect(hwnd):
 r=n.w.RECT();n.u.GetWindowRect(hwnd,c.byref(r));return n.rect_value(r)
try:
 deadline=time.monotonic()+35
 while not info.exists() and p.poll() is None and time.monotonic()<deadline: time.sleep(.1)
 if not info.exists(): raise RuntimeError('Fixture did not reach native witness: '+(out/'floating.log').read_text(errors='replace')[-2000:])
 data=json.loads(info.read_text());hwnd=int(data['hwnd']); style=n.u.GetWindowLongPtrW(hwnd,-16);ex=n.u.GetWindowLongPtrW(hwnd,-20)
 check(style & 0x00CF0000 == 0x00CF0000,'Float has caption/system menu/thick frame/minimize/maximize',hex(style))
 check(not ex & 0x08000080,'Float is neither tool-window nor non-activating',hex(ex))
 status=json.loads(Path(data['status']).read_text());check(not status['registered'],'No AppBar reservation')
 before=rect(hwnd);mtime=Path(data['status']).stat().st_mtime_ns
 n.u.SendMessageW.argtypes=[n.w.HWND,n.w.UINT,n.w.WPARAM,n.w.LPARAM]
 n.u.SendMessageW.restype=n.LRESULT
 def hit(x,y): return n.u.SendMessageW(hwnd,0x84,0,(y<<16)|(x&0xffff))
 check(hit((before[0]+before[2])//2,before[1]+15)==2,'Native title bar is HTCAPTION (Windows drag/restore path)')
 check(hit(before[2]-3,before[3]-3)==17,'Native corner is HTBOTTOMRIGHT (Windows resize path)')
 work=n.monitor_info(hwnd).work; half=(work.right-work.left)//2
 for side in ['left','right']:
  x=work.left if side=='left' else work.left+half
  n.u.SetWindowPos(hwnd,None,x,work.top,half,work.bottom-work.top,0x14)
  immediate=rect(hwnd);time.sleep(.6)
  check(rect(hwnd)==immediate,'Windows/manual side placement is not overwritten: '+side,rect(hwnd))
 callback=n.WNDPROC(lambda h,m,wp,lp:n.u.DefWindowProcW(h,m,wp,lp))
 cls=n.WindowClass(proc=callback,name='FishingFloatingQAWitness')
 n.u.RegisterClassW(c.byref(cls))
 witness=n.u.CreateWindowExW(0x40000,cls.name,'Disposable ordinary-window QA witness',0x10CF0000,work.left,work.top,half,work.bottom-work.top,None,None,None,None)
 check(bool(witness),'Ordinary side-by-side witness created')
 if witness:
  time.sleep(.5)
  check(rect(witness)[2]<=rect(hwnd)[0]+2,'Two ordinary windows can occupy independent monitor halves')
 n.u.SetWindowPos(hwnd,None,*[before[0],before[1],before[2]-before[0],before[3]-before[1]],0x14)
 n.u.ShowWindow(hwnd,3);time.sleep(.5)
 n.u.IsZoomed.argtypes=[n.w.HWND]
 check(n.u.IsZoomed(hwnd),'Native maximize works')
 n.u.ShowWindow(hwnd,9);time.sleep(.5)
 check(not n.u.IsZoomed(hwnd),'Native restore works')
 check(Path(data['status']).stat().st_mtime_ns==mtime,'Floating helper stops publishing/replaying geometry')
 done.write_text('done')
 p.wait(timeout=15)
 check(p.returncode==0,'Godot transition fixture passes')
finally:
 if witness:n.u.DestroyWindow(witness)
 if p.poll() is None: p.terminate();p.wait(timeout=10)
 log.close()
(out/'floating-native.json').write_text(json.dumps(checks,indent=2))
print(json.dumps(checks,indent=2));print((out/'floating.log').read_text(errors='replace')[-1000:])
raise SystemExit(0 if all(x['pass'] for x in checks) else 1)
