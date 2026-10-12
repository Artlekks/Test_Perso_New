extends RefCounted
## Shared geometry. World aspect comes from available space; controls never stretch it.
static func fit_world(box: Rect2) -> Rect2:
	var s := minf(box.size.x / 640.0, box.size.y / 480.0)
	var footprint := Vector2(640,480) * maxf(0,s)
	return Rect2(box.position + (box.size-footprint)*0.5,footprint)
const MOBILE_FRAME := 6.0
const LEFT_CONTROL_MIN := 100.0
const RIGHT_CONTROL_MIN := 128.0
const PORTRAIT_CONTROL_MIN := 224.0
const OVERLAY_BREAKPOINT := 700.0
static func mobile(area: Rect2) -> Dictionary:
	var w := area.size.x
	var h := area.size.y
	var o := area.position
	if w > h:
		var header := 40.0
		var overlay := w < OVERLAY_BREAKPOINT
		var usable_width := w-8 if overlay else w-LEFT_CONTROL_MIN-RIGHT_CONTROL_MIN-8
		var world_width := maxf(0,minf(usable_width,(h-header-8)*2.0))
		var footprint := Vector2(world_width,world_width*.5)
		var world := Rect2(o+Vector2((w-world_width)*.5+(0.0 if overlay else (LEFT_CONTROL_MIN-RIGHT_CONTROL_MIN)*.5),header+4+(h-header-8-footprint.y)*.5),footprint)
		var left_x := o.x if overlay else world.position.x-4-LEFT_CONTROL_MIN
		var right_x := area.end.x-RIGHT_CONTROL_MIN if overlay else world.end.x+4
		return {"variant":"mobile_landscape","fallback":"edge_overlay" if overlay else "side_islands","resolution":Vector2i(960,480),"info":Rect2(o,Vector2(w,header)),"world":world,"frame":world.grow(4),"controls":area,"left":Rect2(Vector2(left_x,o.y+header),Vector2(LEFT_CONTROL_MIN,h-header)),"right":Rect2(Vector2(right_x,o.y+header),Vector2(RIGHT_CONTROL_MIN,h-header)),"safe":area}
	var header := 104.0
	# Keep portrait width. Short phones explicitly scroll the lower control
	# surface rather than sacrificing the game or shrinking thumb targets.
	var world := Rect2(o+Vector2(6,header+6),Vector2(w-12,(w-12)*.75))
	var height := maxf(PORTRAIT_CONTROL_MIN,area.end.y-world.end.y-6)
	var controls := Rect2(Vector2(o.x,world.end.y+6),Vector2(w,height))
	return {"variant":"mobile_portrait","fallback":"scroll_controls" if controls.end.y > area.end.y else "none","resolution":Vector2i(640,480),"info":Rect2(o,Vector2(w,header)),"world":world,"frame":world.grow(6),"controls":controls,"left":Rect2(controls.position,Vector2(w*.5,height)),"right":Rect2(controls.position+Vector2(w*.5,0),Vector2(w*.5,height)),"safe":area}

static func landscape_controls(layout: Dictionary) -> Dictionary:
	var left: Rect2 = layout.left
	var right: Rect2 = layout.right
	var portrait: bool = layout.variant == "mobile_portrait"
	var face := clampf(minf((right.size.x-13.68)/2.5591,(right.size.y-101.68)/2.4991),44,84) if portrait else 47.8
	# Adjacent circles, including larger A, retain 4px of clear touch spacing.
	var gap := (face*1.06+4.01)/sqrt(2.0)
	var center := right.get_center()
	center.y = right.position.y+left.size.y*.5
	# A is larger: center the cluster's full visual bounds, not just its
	# button centers. Opposing center-to-center distances remain symmetric.
	center.x -= face*.03
	var hits := {}
	for id in ["X","Y","A","B"]:
		var direction: Vector2 = {"X":Vector2.UP,"Y":Vector2.LEFT,"A":Vector2.RIGHT,"B":Vector2.DOWN}[id]
		var diameter := face*1.12 if id == "A" else face
		hits[id] = Rect2(center+direction*gap-Vector2.ONE*diameter*.5,Vector2.ONE*diameter)
	var shoulder_width := minf(110,left.size.x-8)
	hits["L"] = Rect2(left.position+Vector2((left.size.x-shoulder_width)*.5,4),Vector2(shoulder_width,44))
	hits["R"] = Rect2(right.position+Vector2((right.size.x-shoulder_width)*.5,4),Vector2(shoulder_width,44))
	hits["START"] = Rect2(right.position+Vector2(4,right.size.y-48),Vector2((right.size.x-12)*.5,44))
	var diameter := minf(130,minf(left.size.x,left.size.y-108))
	var stick_center := Vector2(left.get_center().x,center.y)
	return {"buttons":hits,"stick":Rect2(stick_center-Vector2.ONE*diameter*.5,Vector2.ONE*diameter),"settings":Rect2(left.position+Vector2((left.size.x-52)*.5,left.size.y-48),Vector2(52,44)),"select":Rect2(right.position+Vector2(right.size.x*.5+2,right.size.y-48),Vector2((right.size.x-12)*.5,44))}

static func portrait_controls(area: Rect2) -> Dictionary:
	return landscape_controls({"variant":"mobile_portrait","left":Rect2(area.position,Vector2(area.size.x*.5,area.size.y)),"right":Rect2(area.position+Vector2(area.size.x*.5,0),Vector2(area.size.x*.5,area.size.y))})
const DESKTOP_WIDE_ENTER := 1.75
const DESKTOP_WIDE_EXIT := 1.60
static func desktop(view: Vector2, previous := Vector2i(640,480), docked := false, locked := false) -> Dictionary:
	var compact := view.x < 600
	var header_height := 84.0 if compact else 40.0
	var toolbar_height := 72.0 if compact else 36.0
	var available := Rect2(6,header_height+toolbar_height+12,maxf(1,view.x-12),maxf(1,view.y-header_height-toolbar_height-18))
	var ratio := available.size.x/available.size.y
	var resolution := previous
	if not locked:
		if docked: resolution = Vector2i(640,480)
		elif previous.x == 960: resolution = Vector2i(640,480) if ratio < DESKTOP_WIDE_EXIT else previous
		else: resolution = Vector2i(960,480) if ratio > DESKTOP_WIDE_ENTER else previous
	var scale := minf(available.size.x/resolution.x,available.size.y/resolution.y)
	var footprint := Vector2(resolution)*scale
	var world := Rect2(available.position+Vector2((available.size.x-footprint.x)*.5,0),footprint)
	return {"variant":"desktop_compact" if compact else "desktop_expanded" if resolution.x == 960 else "desktop_regular",
		"resolution":resolution,"info":Rect2(0,0,view.x,header_height),"world":world,"frame":world.grow(4),
		"toolbar":Rect2(maxf(4,view.x-404),header_height+4,minf(400,view.x-8),toolbar_height),"dashboard":Rect2(6,world.end.y+8,view.x-12,maxf(0,view.y-world.end.y-14)),"safe":Rect2(Vector2.ZERO,view),"compact":compact}
