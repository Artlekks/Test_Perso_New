extends SceneTree
## In-engine perspective acceptance for the desktop 480px bottom composition.
## Render-size changes are presentation only; no bait, saves, or fish data.
const CameraRigScript = preload("res://scripts/camera_rig.gd")
var checks: int = 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error("DESKTOP CAMERA ANCHOR FAIL: " + label)

func run() -> void:
	var surface := SubViewport.new()
	surface.size = Vector2i(960,480)
	surface.world_3d = World3D.new()
	root.add_child(surface)
	var player := Node3D.new()
	surface.add_child(player)
	var rig := CameraRigScript.new()
	rig.target = player
	var camera := Camera3D.new()
	camera.name = "Camera3D"
	rig.add_child(camera)
	surface.add_child(rig)
	rig.set_process(false)
	camera.position = Vector3(0,7,12)
	camera.look_at(Vector3.ZERO,Vector3.UP)
	camera.current = true
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.fov = 75.0
	await process_frame
	rig.set_desktop_vertical_composition_height(480)
	var initial_y: float = camera.unproject_position(player.global_position).y
	check(is_equal_approx(rig._desktop_vertical_extra_offset,0.0),"reference viewport applies zero extra vertical offset")
	for height in [600,720,900,1100,1280,480,900]:
		surface.size = Vector2i(960,height)
		camera.fov = rad_to_deg(2.0*atan(tan(deg_to_rad(75.0)*0.5)*float(height)/480.0))
		await process_frame
		rig.set_desktop_vertical_composition_height(height)
		var actual_y: float = camera.unproject_position(player.global_position).y
		var expected_y: float = initial_y + float(height-480)
		check(absf(actual_y-expected_y) <= 3.0,"authored frame bottom-anchors after resizing to %d (got %.2f, wanted %.2f)" % [height,actual_y,expected_y])
		var previous_offset: float = camera.v_offset
		rig.set_desktop_vertical_composition_height(height)
		check(is_equal_approx(camera.v_offset, previous_offset),"camera anchor idempotent at %d" % height)
	print("FISHING STABILIZATION CAMERA GATE 03: %d/%d passed; failures=%s" % [checks-failures.size(),checks,failures])
	quit(0 if failures.is_empty() else 1)
