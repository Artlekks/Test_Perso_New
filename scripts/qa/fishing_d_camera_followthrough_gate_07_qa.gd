extends SceneTree
## Gate 07: after D crosses the lower-depth-meter boundary, camera yaw
## continues until the physical return ends. Doesn't open user saves.
const CameraRig = preload("res://scripts/camera_rig.gd")
var failures: Array[String] = []
var checks: int = 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error("GATE 07: " + message)

func screen_y_positive(yaw: float) -> Vector2:
	return Vector2(0.56, 0.80 - yaw * 0.65)

func screen_y_negative(yaw: float) -> Vector2:
	return Vector2(0.56, 0.80 + yaw * 0.65)

func left_horizontal_projection(yaw: float) -> Vector2:
	return Vector2(0.16 + 0.65 * yaw, 0.71)

func right_horizontal_projection(yaw: float) -> Vector2:
	return Vector2(0.87 + 0.65 * yaw, 0.71)

func run() -> void:
	# New near-player stage: equal horizontal yaw authority on both sides.
	var rotation_band: Rect2 = CameraRig.free_lure_rotation_region(Rect2(.18,.22,.64,.48), .81, .045)
	check(rotation_band.position.x < .30 and rotation_band.end.x > .77,"real-player band wider than inset")
	check(rotation_band.end.y > .68 and rotation_band.end.y < .81,"real-player lower boundary is below inset but above meter")
	check(CameraRig.free_lure_rotation_turn_direction(0.0,Callable(self,"left_horizontal_projection"),rotation_band) == 1.0,"A-side violation selects a correcting left orbit")
	check(CameraRig.free_lure_rotation_turn_direction(0.0,Callable(self,"right_horizontal_projection"),rotation_band) == -1.0,"D-side violation selects a correcting right orbit")
	check(not CameraRig.free_lure_outside_rotation_region(Vector2(.50,.60),rotation_band),"centered bait causes no extra rotation")
	# Both authored camera directions work: do not hardcode clockwise.
	for sign_case in [1.0, -1.0]:
		var project: Callable = Callable(self, "screen_y_positive") if sign_case > 0.0 else Callable(self, "screen_y_negative")
		var direction: float = CameraRig.free_d_waterline_turn_direction(0.0, project)
		check(direction == sign_case, "camera chooses actual vertical-improving sign")
		var yaw: float = 0.0
		var last_yaw: float = yaw
		var reached_boundary: bool = false
		var advanced_after_safe: int = 0
		# A real held-D return may move above the line after initial correction;
		# the turning must NOT stop when the screen-space error becomes zero.
		for frame in range(600):
			var bait_y: float = 0.80 if frame < 100 else 0.61
			if bait_y >= 0.73:
				reached_boundary = true
			if reached_boundary:
				yaw = CameraRig.advance_free_d_followthrough_yaw(
					yaw, direction, bait_y, 0.73, 0.65,
					1.0 / 60.0, 3.0, 9.0, 70.0
				)
				check((yaw-last_yaw)*direction >= -0.00000001,"D camera does not unwind during the same retrieval")
				if frame >= 100 and absf(yaw-last_yaw) > 0.00000001:
					advanced_after_safe += 1
				last_yaw = yaw
		check(reached_boundary,"D camera orbit was activated")
		check(advanced_after_safe >= 300,"D continues yaw after the bait is above the waterline")
		check(absf(rad_to_deg(yaw)) < 70.0,"D follow-through does not hit safety cap in ordinary 10-second reel")
		check(absf(rad_to_deg(yaw)) > 25.0,"D accumulates useful yaw throughout the return")
		var paused: float = CameraRig.advance_free_d_followthrough_yaw(
			yaw,direction,0.80,0.73,0.65,0.0,3.0,9.0,70.0)
		check(is_equal_approx(paused,yaw),"paused/zero-delta cannot rotate")
		var released: float = CameraRig.advance_free_d_followthrough_yaw(
			yaw,0.0,0.80,0.73,0.65,1.0/60.0,3.0,9.0,70.0)
		check(is_equal_approx(released,yaw),"released D cannot rotate")
		var hard_limit: float = CameraRig.advance_free_d_followthrough_yaw(
			deg_to_rad(69.99)*direction,direction,0.80,0.73,0.65,
			1.0,3.0,9.0,70.0)
		check(absf(rad_to_deg(hard_limit)) <= 70.0001,"hard safety cap remains enforced")
	var source: String = (load("res://scripts/camera_rig.gd") as Script).source_code
	check(source.contains("_free_d_orbit_engaged"),"runtime waterline latch exists")
	check(source.contains("if sign_now != 0.0 and _free_d_orbit_engaged"),"one rotation-only follow-through path handles A and D")
	check(source.contains("_inset_camera_owns_framing()"),"inset camera ownership follows rod visibility rather than return rail")
	print("FISHING D CAMERA FOLLOW-THROUGH GATE 07: %d/%d passed; failures=%s" % [checks-failures.size(),checks,failures])
	quit(0 if failures.is_empty() else 1)
