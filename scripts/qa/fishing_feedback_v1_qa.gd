extends Node

const Bridge = preload("res://scripts/triple_triad/triple_triad_fishing_salvage_bridge.gd")
var checks := 0
var failures: Array[String] = []
var shell: Control
var game: Node

func _ready() -> void:
	if OS.get_name() != "Web":
		ProjectSettings.set_setting("application/config/use_custom_user_dir", true)
		ProjectSettings.set_setting("application/config/custom_user_dir_name", "CodexFeedbackQA-%d" % Time.get_ticks_usec())
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)

func settle(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout

func run() -> void:
	shell = load("res://actors/mobile/MobilePortraitHarness.tscn").instantiate()
	shell.developer_playtest_default_enabled = false
	shell.isolated_playtest_save = false
	get_tree().root.add_child(shell)
	get_tree().current_scene = shell
	await settle(0.5)
	game = shell.game
	var fishing = game.get_node("Game/Fishing")
	var zone = game.get_node("World/FishZone_V2")
	fishing.player.rotation.y = PI
	fishing.game_mode.enter_fishing(zone)
	for frame in range(600):
		if fishing.phase == fishing.Phase.AIM: break
		await get_tree().process_frame
	check(fishing.phase == fishing.Phase.AIM, "reachability starts from actual cast-ready phase")
	await settle(0.1)
	print("CAST READY center=",fishing.aim.center_yaw," player=",fishing.player.rotation," spawn=",fishing.caster.spawn_point.global_position)
	var caster = fishing.caster
	check(caster.active_rod_data.rod_id == &"wooden_rod", "reachability uses intended starter Wooden Rod")
	var rig = fishing.camera_rig
	var anchor: Vector3 = fishing.player.global_position
	var original_yaw: float = rig.rotation.y
	var original_offset: float = fishing.aim.aim_offset
	# Exhaustively sample ordinary uncurved legal casts using the production
	# predictor and screen-space rod spawn after each settled A/D heading.
	for stance in [Vector3.ZERO, Vector3(-0.8,0,0), Vector3(0.8,0,0)]:
		fishing.player.global_position = anchor + stance
		rig.global_position = fishing.player.global_position
		var best: Array[float] = []
		var evidence: Array[Vector3] = []
		for offset in Bridge.STARTER_SPARKLE_OFFSETS:
			best.append(INF)
			evidence.append(Vector3.ZERO)
		for degrees in range(-60,61,2):
			fishing.aim.aim_offset = deg_to_rad(degrees)
			fishing.aim._emit_aim()
			rig.rotation.y = rig.fishing_aim_target_yaw
			caster.spawn_point._process(0.0)
			for power_index in range(51):
				var path: PackedVector3Array = caster.predict_cast(power_index / 50.0, fishing.aim.get_direction(), zone.get_water_y())
				if path.is_empty(): continue
				var landing := path[path.size()-1]
				for index in best.size():
					var target: Vector3 = zone.water_surface.global_position + Bridge.STARTER_SPARKLE_OFFSETS[index]
					var distance := Vector2(landing.x-target.x, landing.z-target.z).length()
					if distance < best[index]:
						best[index] = distance
						evidence[index] = Vector3(degrees, power_index / 50.0, distance)
		for index in best.size():
			var target: Vector3 = zone.water_surface.global_position + Bridge.STARTER_SPARKLE_OFFSETS[index]
			var marker = load("res://scripts/triple_triad/triple_triad_salvage_sparkle.gd").new()
			game.add_child(marker)
			marker.configure(target, Bridge.STARTER_SPARKLE_TRIGGER_RADIUS)
			# Aim uses atan2(x,z), so use the production direction for this proof.
			fishing.aim.aim_offset = deg_to_rad(evidence[index].x)
			fishing.aim._emit_aim()
			rig.rotation.y = rig.fishing_aim_target_yaw
			caster.spawn_point._process(0.0)
			var path: PackedVector3Array = caster.predict_cast(evidence[index].y, fishing.aim.get_direction(), zone.get_water_y())
			check(best[index] < Bridge.STARTER_SPARKLE_TRIGGER_RADIUS * 0.5, "salvage target %d reachable with comfortable radius margin at stance %s" % [index,stance])
			check(marker.is_cast_near(path[path.size()-1]), "actual salvage trigger accepts legal starter-gear cast")
			print("REACHABILITY stance=",stance," target=",target," aim/power/distance=",evidence[index])
			marker.queue_free()
	fishing.player.global_position = anchor
	rig.global_position = anchor
	fishing.aim.aim_offset = original_offset
	fishing.aim._emit_aim()
	rig.rotation.y = original_yaw
	caster.spawn_point._process(0.0)
	await test_catch_return(fishing)
	await test_ripple(fishing)
	var report := {"passed":checks-failures.size(),"total":checks,"failures":failures,"os":OS.get_name()}
	print("FISHING FEEDBACK QA: ", JSON.stringify(report))
	if OS.get_name() == "Web":
		JavaScriptBridge.eval("window.fishingFeedbackReport=" + JSON.stringify(report), true)
	else:
		get_tree().quit(0 if failures.is_empty() else 1)

func test_catch_return(fishing: Node) -> void:
	var rig = fishing.camera_rig
	var camera: Camera3D = rig.get_node("Camera3D")
	var bait := Node3D.new()
	game.add_child(bait)
	fishing.aim.stop()
	rig.set_fishing_fight_tracking(true, bait)
	var post_aim_base: Transform3D = rig._fight_base_camera_transform
	rig.fight_camera_tracking.yaw = deg_to_rad(45)
	camera.transform = rig._fight_orbit_transform(post_aim_base,Vector3.ZERO,deg_to_rad(45))
	rig.set_fishing_fight_tracking(false)
	rig.set_fishing_camera_frozen(true)
	fishing.phase = fishing.Phase.WAIT_RESULT
	fishing.caught_fish = FishInstance.new()
	var tracked: Transform3D = camera.transform
	var key := InputEventAction.new()
	key.action = &"enter_fishing"
	key.pressed = true
	fishing._unhandled_input(key)
	check(fishing.phase == fishing.Phase.CATCH_DISMISS, "K uses real result dismissal path")
	await settle(fishing.fishing_catch_view.slide_time + 0.05)
	check(fishing.phase == fishing.Phase.AIM and rig._retrieve_yaw_return_active, "catch dismissal starts same slow yaw return")
	check(rig._retrieve_base_transform.is_equal_approx(post_aim_base), "catch return preserves exact post-aim base")
	await settle(0.35)
	check(rig._retrieve_yaw_return_active and not camera.transform.is_equal_approx(post_aim_base), "catch return is still unwinding after old 0.35s cutoff")
	await settle(4.0)
	check(camera.transform.is_equal_approx(post_aim_base) and not rig._retrieve_yaw_return_active, "catch return finishes cleanly at post-aim pose")
	bait.queue_free()

func test_ripple(fishing: Node) -> void:
	var camera: Camera3D = fishing.camera_rig.get_node("Camera3D")
	var physical = load("res://actors/bait_V2.tscn").instantiate()
	game.add_child(physical)
	physical.set_physics_process(false)
	physical.state = physical.State.IN_WATER
	physical.global_position = camera.project_position(Vector2(shell.gameplay_viewport.size) * Vector2(0.55,0.5), 12.0)
	var ripple = physical.ripple_view
	ripple.configure(physical, physical.global_position.y)
	fishing.caster.active_bait = physical
	fishing.phase = fishing.Phase.IN_WATER
	fishing.encounter.active_bite_timing = {"total_window": 0.8}
	fishing._on_bite_opportunity_started()
	check(ripple.ripple_sprite.animation == &"Ripple" and ripple.active, "bite opening starts authored ripple")
	check(is_equal_approx(ripple.get_authored_ripple_duration() / ripple.ripple_sprite.speed_scale, 0.8), "authored 48-frame ripple playback fits authoritative 0.8s opportunity")
	fishing._on_bite_commit_ready({})
	check(ripple.active and ripple.ripple_sprite.animation == &"Ripple", "hook-ready cue does not replace opportunity ripple")
	await settle(0.2)
	check(ripple.active, "ripple remains visible during opportunity")
	if DisplayServer.get_name() != "headless":
		# Freeze scenery and hold one identical frame across captures. Compare
		# pixels only around the effect, not structural visibility flags.
		ripple.ripple_sprite.pause()
		physical.process_mode = Node.PROCESS_MODE_DISABLED
		ripple.process_mode = Node.PROCESS_MODE_ALWAYS
		get_tree().paused = true
		await RenderingServer.frame_post_draw
		var shown: Image = shell.gameplay_viewport.get_texture().get_image()
		ripple.visible = false
		await RenderingServer.frame_post_draw
		var hidden: Image = shell.gameplay_viewport.get_texture().get_image()
		var pixel: Vector2 = camera.unproject_position(physical.global_position)
		var changed := 0
		for y in range(maxi(0,int(pixel.y)-100),mini(shown.get_height(),int(pixel.y)+100)):
			for x in range(maxi(0,int(pixel.x)-100),mini(shown.get_width(),int(pixel.x)+100)):
				var a := shown.get_pixel(x,y)
				var b := hidden.get_pixel(x,y)
				if absf(a.r-b.r)+absf(a.g-b.g)+absf(a.b-b.b)>0.15: changed+=1
		check(changed > 20, "ripple draws measurable visible pixels in rendered mobile/Web viewport")
		print("RIPPLE RENDERED PIXELS: ",changed, " viewport=",shell.gameplay_viewport.size)
		if OS.get_name() != "Web":
			shown.save_png("user://feedback-ripple.png")
		else:
			JavaScriptBridge.eval("window.feedbackRipplePNG='data:image/png;base64," + Marshalls.raw_to_base64(shown.save_png_to_buffer()) + "'", true)
		ripple.visible = true
		get_tree().paused = false
		physical.process_mode = Node.PROCESS_MODE_INHERIT
		physical.set_physics_process(false)
		ripple.ripple_sprite.play()
	await settle(0.75)
	check(not ripple.active, "ripple expires at opportunity duration")
	fishing._on_bite_opportunity_started()
	fishing._on_bite_missed()
	check(not ripple.active, "miss cleans ripple immediately")
	fishing._on_bite_opportunity_started()
	fishing._on_bite_triggered()
	check(ripple.ripple_sprite.animation == &"BiteSplash" and ripple.active, "confirmed hook switches once to stronger splash")
	fishing._on_bite_missed()
	check(not ripple.active, "repeat cycle leaves no stale effect")
	fishing.caster.active_bait = null
	physical.queue_free()
	fishing.phase = fishing.Phase.AIM
	fishing.encounter.active_bite_timing.clear()
