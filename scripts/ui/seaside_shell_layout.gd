extends RefCounted
## View geometry only. The world remains the same uncropped 640x480 surface.
const DESKTOP_WIDE_BREAKPOINT := 900.0
static func fit_world(box: Rect2) -> Rect2:
	var s := minf(box.size.x / 640.0, box.size.y / 480.0)
	var footprint := Vector2(640,480) * maxf(0,s)
	return Rect2(box.position + (box.size-footprint)*0.5,footprint)
static func mobile(area: Rect2) -> Dictionary:
	var w := area.size.x
	var h := area.size.y
	var o := area.position
	if w > h:
		var header := minf(h*0.17,76.0)
		var side := w*0.17
		var box := Rect2(o+Vector2(side,header),Vector2(w-side*2,h-header))
		var world := fit_world(box.grow(-6))
		side = world.position.x-o.x-6
		return {"variant":"mobile_landscape","info":Rect2(o+Vector2(w*.14,0),Vector2(w*.48,header)),"world":world,"frame":world.grow(6),"controls":area,"left":Rect2(o+Vector2(0,header),Vector2(side,h-header)),"right":Rect2(o+Vector2(w-side,header),Vector2(side,h-header)),"gear":Rect2(o+Vector2(w*.62,0),Vector2(w*.24,header)),"safe":area}
	var header := minf(w*.27,maxf(54,h-(w-12)*.75-248))
	var world := Rect2(o+Vector2(6,header+6),Vector2(w-12,(w-12)*.75))
	var controls := Rect2(o+Vector2(0,world.end.y-o.y+6),Vector2(w,maxf(0,area.end.y-world.end.y-6)))
	return {"variant":"mobile_portrait","info":Rect2(o,Vector2(w*.55,header)),"gear":Rect2(o+Vector2(w*.55,0),Vector2(w*.45,header)),"world":world,"frame":world.grow(6),"controls":controls,"safe":area}
static func desktop(view: Vector2) -> Dictionary:
	var w := view.x
	var h := view.y
	var header := Rect2(6,6,w-12,42)
	if w >= DESKTOP_WIDE_BREAKPOINT:
		var side := w*.28
		var left := w-side-18
		var frame := Rect2(8,54,left,h-62-150)
		var x := w-side-4
		return {"variant":"desktop_wide","header":header,"frame":frame,"world":fit_world(frame.grow(-8)),"info":Rect2(x,54,side-4,112),"modes":Rect2(x,170,side-4,76),"docks":Rect2(x,250,side-4,42),"gear":Rect2(x,298,side-4,180),"menus":Rect2(x,484,side-4,maxf(120,h-492)),"controls":Rect2(8,frame.end.y+6,left,142)}
	var top := 106.0
	var frame := Rect2(8,54+top,w-16,minf((w-32)*.75+16,maxf(80,h-54-top-200)))
	var bottom := Rect2(8,frame.end.y+6,w-16,maxf(80,h-frame.end.y-14))
	return {"variant":"desktop_narrow","header":header,"frame":frame,"world":fit_world(frame.grow(-8)),"info":Rect2(8,54,w*.45-8,top-6),"modes":Rect2(w*.45+4,54,w*.55-12,58),"docks":Rect2(w*.45+4,116,w*.55-12,38),"controls":Rect2(bottom.position,Vector2(bottom.size.x*.49,bottom.size.y)),"gear":Rect2(bottom.position+Vector2(bottom.size.x*.51,0),Vector2(bottom.size.x*.49,bottom.size.y*.58)),"menus":Rect2(bottom.position+Vector2(bottom.size.x*.51,bottom.size.y*.60),Vector2(bottom.size.x*.49,bottom.size.y*.40))}
