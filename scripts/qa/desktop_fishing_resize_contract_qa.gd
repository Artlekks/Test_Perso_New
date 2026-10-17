extends SceneTree
## Gate 02: floating window growth must also grow the displayed gameplay
## viewport during an active fishing session. Docking keeps its approved shape.
const Layout = preload("res://scripts/ui/seaside_shell_layout.gd")
var checked: int = 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checked += 1
	if not ok:
		failures.append(label)
		push_error("RESIZE CONTRACT FAIL: " + label)

func run() -> void:
	var widths: Array[int] = [640, 960]
	var shapes: Array[Vector2] = [Vector2(800,560),Vector2(1280,760),Vector2(720,1300),Vector2(1920,1080),Vector2(360,720)]
	for width in widths:
		var previous := Vector2i(width,480)
		for host_size in shapes:
			var floating: Dictionary = Layout.desktop(host_size,previous,false,true)
			var resolution: Vector2i = floating["resolution"]
			var world: Rect2 = floating["world"]
			check(resolution.x == width,"floating cast keeps world width %s %s" % [width,host_size])
			check(resolution.y >= 480,"floating cast retains minimum world height %s" % host_size)
			check(Rect2(Vector2.ZERO,host_size).encloses(world),"floating viewport fits window %s" % host_size)
			check(world.size.x > 0.0 and world.size.y > 0.0,"floating world is visible %s" % host_size)
			var repeat: Dictionary = Layout.desktop(host_size,resolution,false,true)
			check(repeat["resolution"] == resolution,"floating resize idempotent %s" % host_size)
			var docked: Dictionary = Layout.desktop(host_size,previous,true,true)
			check(docked["resolution"] == previous,"existing dock layout unchanged %s" % host_size)
	var short_view: Dictionary = Layout.desktop(Vector2(1128,520),Vector2i(960,480),false,true)
	var tall_view: Dictionary = Layout.desktop(Vector2(1128,1300),Vector2i(960,480),false,true)
	var short_resolution: Vector2i = short_view["resolution"]
	var tall_resolution: Vector2i = tall_view["resolution"]
	check(tall_resolution.y > short_resolution.y,"active fishing reveals more vertical world in a tall floating window")
	check(tall_view["world"].size.y > short_view["world"].size.y,"active fishing consumes the extra physical window height")
	check(Layout.desktop(Vector2(1128,1300),Vector2i(960,480),false,false)["resolution"] == tall_resolution,"fishing and exploration share the tall-world sizing rule")
	print("FISHING STABILIZATION RESIZE GATE 02: %d/%d passed; failures=%s" % [checked-failures.size(),checked,failures])
	quit(0 if failures.is_empty() else 1)
