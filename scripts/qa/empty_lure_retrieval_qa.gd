extends SceneTree
## Actual Caster/Bait/input integration, isolated persistence; no combat simulation replacement.
var checks := 0
var failures: Array[String] = []
var fixture: SessionTestFixture
var fishing: Node
var camera: Camera3D
var bait: Node3D
var caster: Node
var zone: Node
var base_pose: Transform3D
const STEP := 1.0 / 60.0

func _initialize() -> void:
	var isolated := "CodexEmptyLureQA-%d" % Time.get_ticks_usec()
	ProjectSettings.set_setting("application/config/use_custom_user_dir", true)
	ProjectSettings.set_setting("application/config/custom_user_dir_name", isolated)
	DirAccess.make_dir_recursive_absolute(OS.get_user_data_dir())
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)

func point_on_water(pixel: Vector2) -> Vector3:
	var origin := camera.project_ray_origin(pixel)
	var direction := camera.project_ray_normal(pixel)
	return origin + direction * ((0.025 - origin.y) / direction.y)

func press(action: StringName, value: bool) -> void:
	if value: Input.action_press(action)
	else: Input.action_release(action)
	var event := InputEventAction.new()
	event.action = action
	event.pressed = value
	fishing._unhandled_input(event)

func spawn(pixel: Vector2) -> void:
	caster.cancel_bait()
	fishing.camera_rig.reset_fishing_follow()
	camera.global_transform = base_pose
	bait = caster.perform_cast(0.5, Vector3.FORWARD, zone.get_water_y(), zone.get_bottom_y(), fishing.loadout.get_selected_lure(), null, zone.get_shore_boundary())
	bait.set_physics_process(false)
	bait.current_service = null
	# Keep authored lure data, but remove independent idle animation displacement
	# for the direction measurement; test contributors separately below.
	bait.lure_action_runtime = null
	bait.state = bait.State.IN_WATER
	bait.global_position = point_on_water(pixel)
	bait.global_position.y = 0.0
	fishing.phase = fishing.Phase.IN_WATER
	fishing.bite_animation_active = false
	fishing.bite_opportunity_animation_active = false
	fishing.encounter.bite_timer.stop()
	fishing.encounter.bite_window_timer.stop()
	var before_camera := camera.global_transform
	fishing._sync_fight_camera_tracking()
	check(camera.global_transform.is_equal_approx(before_camera), "ANCHORED acquisition preserves exact landing shot")

func run() -> void:
	root.size = Vector2i(640,480)
	root.content_scale_size = Vector2i(640,480)
	fixture = SessionTestFixture.new()
	var game := fixture.mount(self)
	for frame in range(12): await process_frame
	fishing = game.get_node("Game/Fishing")
	caster = fishing.caster
	camera = fishing.camera_rig.get_node("Camera3D")
	zone = game.get_node("World/FishZone_V2")
	fishing.player.rotation.y = PI
	fishing.game_mode.enter_fishing(game.get_node("World/FishZone_V2"))
	for frame in range(600):
		if fishing.phase == fishing.Phase.AIM: break
		await process_frame
	check(fishing.phase == fishing.Phase.AIM, "real session enters AIM")
	fishing.set_process(false)
	fishing.camera_rig.set_process(false)
	base_pose = camera.global_transform
	print("CAMERA viewport=",camera.get_viewport().get_visible_rect()," transform=",camera.global_transform)
	for pixel in [Vector2(320,150), Vector2(205,150), Vector2(470,150), Vector2(320,40), Vector2(470,380)]:
		for action in [&"ds_left", &"ds_right"]:
			spawn(pixel)
			var from := bait.global_position
			var target := bait._free_lure_landing_point() as Vector3
			var inward := (target-from).normalized()
			var right := FishingScreenLateralForQA(camera, from, inward)
			var sign_value := -1.0 if action == &"ds_left" else 1.0
			var legal_start: bool = bait._free_lure_screen_region().has_point(pixel/Vector2(640,480))
			press(action, true)
			# Deliberately physics before idle polling: first event must suffice.
			bait._physics_process(STEP)
			var movement := bait.global_position-from
			var screen_delta := camera.unproject_position(bait.get_surface_position())-camera.unproject_position(Vector3(from.x,bait.water_y+0.025,from.z))
			print("FIRST ",action," start=",pixel," world_delta=",movement," screen_delta=",screen_delta," lateral=",movement.dot(right)*sign_value)
			if legal_start:
				check(movement.dot(right)*sign_value > 0.00001, "%s first press at %s follows requested arc" % [action,pixel])
				check(screen_delta.x*sign_value > 0.00001, "first press immediately moves in requested SCREEN direction")
			else:
				var bounds: Rect2 = bait._free_lure_screen_region()
				var before_error: float = bait._free_lure_screen_error(pixel/Vector2(640,480),bounds)
				var after_screen := camera.unproject_position(bait.get_surface_position())/Vector2(640,480)
				check(bait._free_lure_screen_error(after_screen,bounds) <= before_error, "invalid behind-HUD start recovers toward legal visibility")
			check(bait.global_position.distance_to(target) < from.distance_to(target), "first press progresses inward")
			press(action, false)
	for action in [&"ds_left", &"ds_right", &"enter_fishing"]:
		for pixel in [Vector2(320,150),Vector2(100,160),Vector2(550,160)]:
			spawn(pixel)
			var initial_player: Vector3 = fishing.player.global_position
			var target: Vector3 = bait._free_lure_landing_point()
			var initial_camera_player := camera.unproject_position(initial_player)
			var returned := [false]
			bait.returned.connect(func(): returned[0] = true, CONNECT_ONE_SHOT)
			press(action, true)
			var steps := 0
			var near_arc_samples := 0
			var stalled := 0
			while not returned[0] and steps < 4000:
				var before := bait.global_position
				var distance := Vector2(before.x-target.x,before.z-target.z).length()
				bait._physics_process(STEP)
				steps += 1
				if returned[0]: break
				var after := bait.global_position
				var remaining := Vector2(after.x-target.x,after.z-target.z).length()
				if remaining >= distance-0.000001: stalled += 1
				if action != &"enter_fishing" and distance < 1.5:
					var inward := (target-before).normalized()
					var tangent := FishingScreenLateralForQA(camera,before,inward)
					if absf((after-before).dot(tangent)) > 0.00001: near_arc_samples += 1
				fishing.camera_rig._process(STEP)
			check(returned[0], "%s %s completes retrieval rather than sticking at edge" % [action,pixel])
			check(stalled == 0, "%s %s makes inward progress every physics tick" % [action,pixel])
			if action != &"enter_fishing": check(near_arc_samples > 5, "near-shore retrieval retains curved movement")
			check(fishing.player.global_position.is_equal_approx(initial_player), "retrieve cannot move physical player")
			check(camera.unproject_position(initial_player).distance_to(initial_camera_player) < 2.0, "yaw orbit preserves player composition")
			print("RETRIEVE ",action," start=",pixel," steps=",steps," stalls=",stalled," near_arc=",near_arc_samples)
			press(action, false)
			for frame in range(900): fishing.camera_rig._process(STEP)
			check(camera.global_transform.is_equal_approx(base_pose), "completed retrieve restores exact post-aim camera")
	check(fishing.camera_rig.fishing_hud_failures == 0, "retrieves never overlap the live HUD")
	check(fishing.camera_rig.safe_containment_failures == 0, "retrieves remain within actual viewport/HUD guard")
	for action in [&"ds_left", &"ds_right", &"enter_fishing"]:
		spawn(Vector2(320,150))
		bait.lure_action_runtime = preload("res://scripts/lure_action_runtime.gd").new()
		bait._configure_lure_action_runtime()
		bait.current_service = caster.current_service
		var stalled := 0
		press(action,true)
		for frame in range(300):
			if not is_instance_valid(caster.active_bait): break
			var goal: Vector3 = bait._free_lure_landing_point()
			var before := Vector2(bait.global_position.x-goal.x,bait.global_position.z-goal.z).length()
			bait._physics_process(STEP)
			if not is_instance_valid(caster.active_bait): break
			var after := Vector2(bait.global_position.x-goal.x,bait.global_position.z-goal.z).length()
			if after >= before-0.000001: stalled += 1
		check(stalled == 0, "authored action/current contributors cannot reverse active retrieval")
		press(action,false)
	# Repeat with the authored launch/path and actual landed signal rather than
	# injecting a waterborne position. This exercises the water-entry ordering.
	for power in [0.3,0.6,0.9]:
		for action in [&"ds_left",&"ds_right"]:
			caster.cancel_bait()
			fishing.camera_rig.reset_fishing_follow()
			camera.global_transform = base_pose
			fishing.phase = fishing.Phase.BAIT_FLYING
			bait = caster.perform_cast(power,fishing.aim.get_direction(),zone.get_water_y(),zone.get_bottom_y(),fishing.loadout.get_selected_lure(),zone.get_swim_bounds(),zone.get_shore_boundary())
			bait.set_physics_process(false)
			for frame in range(300):
				if bait.state != bait.State.FLYING: break
				bait._physics_process(STEP)
			check(bait.state != bait.State.FLYING and fishing.phase == fishing.Phase.IN_WATER, "authored flight reaches real IN_WATER transition")
			bait.current_service = null
			bait.lure_action_runtime = null
			var before := bait.get_surface_position() as Vector3
			var screen_before := camera.unproject_position(before)
			var camera_before := camera.global_transform
			fishing._sync_fight_camera_tracking()
			check(camera.global_transform.is_equal_approx(camera_before), "real water-entry ownership cannot jump the camera")
			press(action,true)
			bait._physics_process(STEP)
			var displacement := camera.unproject_position(bait.get_surface_position())-screen_before
			print("LANDED FIRST power=",power," action=",action," pixel=",screen_before," delta=",displacement)
			check(displacement.x*(-1.0 if action == &"ds_left" else 1.0) > 0.00001, "first post-LANDED physics step respects screen direction")
			press(action,false)
	for lure in preload("res://data/bof4/catalogs/all_content.tres").tackle.lure_catalog.lures:
		for action in [&"ds_left",&"ds_right"]:
			spawn(Vector2(320,150))
			bait.set_data(lure)
			bait.current_service = caster.current_service
			var stalled := 0
			press(action,true)
			for frame in range(120):
				if not is_instance_valid(caster.active_bait): break
				var goal: Vector3 = bait._free_lure_landing_point()
				var before := Vector2(bait.global_position.x-goal.x,bait.global_position.z-goal.z).length()
				bait._physics_process(STEP)
				if not is_instance_valid(caster.active_bait): break
				var after := Vector2(bait.global_position.x-goal.x,bait.global_position.z-goal.z).length()
				if after >= before-0.000001: stalled += 1
			check(stalled == 0, "authored %s %s action motion preserves inward retrieve" % [lure.lure_id,action])
			press(action,false)
	fixture.release()
	for frame in range(12): await process_frame
	print("EMPTY LURE RETRIEVAL QA: ",checks-failures.size(),"/",checks," failures=",failures)
	quit(0 if failures.is_empty() else 1)

func FishingScreenLateralForQA(active_camera: Camera3D, position_world: Vector3, inward: Vector3) -> Vector3:
	var right: Vector3 = preload("res://scripts/fishing_screen_lateral.gd").right(active_camera,position_world,Vector3.RIGHT)
	return (right-inward*right.dot(inward)).normalized()



