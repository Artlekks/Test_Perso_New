extends SceneTree
## Desktop Pass 4: four always-visible bands and an aspect-safe protected game.
const Layout = preload("res://scripts/ui/seaside_shell_layout.gd")
var count := 0
var failures: Array[String] = []
func verify(ok: bool, name: String) -> void:
	count += 1
	if not ok: failures.append(name); push_error(name)
func _initialize() -> void:
	run.call_deferred()
func run() -> void:
	for dimension in [Vector2(320,400),Vector2(320,1528),Vector2(480,1528),Vector2(900,1528),Vector2(800,560),Vector2(1536,864),Vector2(1920,1080)]:
		var docked := int(dimension.x) in [320,480,900]
		var geometry: Dictionary = Layout.desktop(dimension,Vector2i(640,480),docked)
		var bounds := Rect2(Vector2.ZERO,dimension)
		var world: Rect2 = geometry.world
		var bands: Rect2 = geometry.dashboard
		var menu: Rect2 = geometry.menu
		verify(bounds.encloses(world),"world remains in window "+str(dimension))
		verify(is_equal_approx(world.size.x / world.size.y,float(geometry.resolution.x) / float(geometry.resolution.y)),"world is not stretched "+str(dimension))
		verify(bounds.encloses(bands),"bottom bands always in window "+str(dimension))
		verify(is_equal_approx(bands.size.y,Layout.DESKTOP_DASHBOARD_HEIGHT),"two bands always present "+str(dimension))
		verify(geometry.info.end.y <= geometry.toolbar.position.y,"environment precedes controls "+str(dimension))
		verify(geometry.toolbar.end.y <= world.position.y,"gameplay below top bars "+str(dimension))
		verify(not world.intersects(bands),"summary never obscures gameplay "+str(dimension))
		verify(not world.intersects(menu),"contextual menu never obscures gameplay "+str(dimension))
		verify(bands.end.y <= menu.position.y,"expanded menu appears under both banners "+str(dimension))
		verify(not geometry.lower_menu_available or menu.size.y >= Layout.DESKTOP_MENU_MIN_HEIGHT,"lower menu has sufficient height "+str(dimension))
		if dimension.x == 320:
			verify(not geometry.lower_menu_available,"minimum dock uses game overlay for menu")
		if dimension == Vector2(800,560):
			verify(not geometry.lower_menu_available,"short floating window uses game overlay")
		if dimension.x == 480 and dimension.y == 1528:
			verify(geometry.lower_menu_available,"tall dock has lower menu area")
			verify(world.position.y > geometry.toolbar.end.y,"tall dock balances the game")
	print("DESKTOP PASS 4 LAYOUT QA: ",count-failures.size(),"/",count," failures: ",failures)
	quit(0 if failures.is_empty() else 1)
