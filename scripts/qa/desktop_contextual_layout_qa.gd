extends SceneTree
## Desktop layout regression after retiring the duplicate Equipment/Records
## dashboard. The genuine J menu overlays the protected gameplay viewport.
const Layout = preload("res://scripts/ui/seaside_shell_layout.gd")
var count := 0
var failures: Array[String] = []

func verify(ok: bool, name: String) -> void:
	count += 1
	if not ok:
		failures.append(name)
		push_error(name)

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	for dimension in [Vector2(320,400),Vector2(320,1528),Vector2(480,1528),Vector2(900,1528),Vector2(800,560),Vector2(1536,864),Vector2(1920,1080)]:
		var docked := int(dimension.x) in [320,480,900]
		var geometry: Dictionary = Layout.desktop(dimension,Vector2i(640,480),docked)
		var bounds := Rect2(Vector2.ZERO,dimension)
		var world: Rect2 = geometry.world
		var dashboard: Rect2 = geometry.dashboard
		var menu: Rect2 = geometry.menu
		verify(bounds.encloses(world),"world remains in window " + str(dimension))
		verify(is_equal_approx(world.size.x / world.size.y,float(geometry.resolution.x) / float(geometry.resolution.y)),
			"world is not stretched " + str(dimension))
		verify(is_zero_approx(dashboard.size.y),"no duplicate desktop Equipment/Records footer " + str(dimension))
		verify(geometry.info.size == Vector2.ZERO,"no beige environment band " + str(dimension))
		verify(geometry.toolbar.end.y <= world.position.y,"gameplay beneath shell toolbar " + str(dimension))
		verify(menu == world and not geometry.lower_menu_available,
			"authored J menu uses its existing viewport overlay " + str(dimension))
		if dimension.x in [320,480]:
			verify(is_equal_approx(world.position.y,geometry.toolbar.end.y+3.0),
				"tall narrow window puts gameplay directly below toolbar " + str(dimension))
	print("DESKTOP RESPONSIVE LAYOUT QA: ",count-failures.size(),"/",count," failures: ",failures)
	quit(0 if failures.is_empty() else 1)
