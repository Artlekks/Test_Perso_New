extends SceneTree

var checks := 0
var failures: Array[String] = []
var rendered := false
var capture_dir := OS.get_environment("TEMP").path_join("godot-actor-policy-v2")

func _initialize() -> void:
	rendered = OS.get_cmdline_user_args().has("--rendered")
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-dir="):
			capture_dir = argument.trim_prefix("--capture-dir=")
	ProjectSettings.set_setting("application/config/use_custom_user_dir", true)
	ProjectSettings.set_setting("application/config/custom_user_dir_name", "CodexActorPolicyV2-%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(OS.get_user_data_dir())
	DirAccess.make_dir_recursive_absolute(capture_dir)
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)

func capture(label: String) -> void:
	if rendered:
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(capture_dir.path_join(label + ".png"))

func run() -> void:
	# Use the actual beach, actors, camera and production bootstrap, isolated save.
	var scene: Node3D = load("res://actors/FishingTestScene_V2.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	for i in range(20):
		await physics_frame
	var player: CharacterBody3D = scene.get_node("Player/CharacterBody3D")
	var maker: FishingCardMakerNPC = scene.get_node("World/FishingCardMakerNPC")
	var crab: BeachFishingCritter = scene.get_node("World/BeachCritter")
	var home := maker.global_position
	var stance_y := player.global_position.y
	player.movement_enabled = false
	player.sprite_director.play(&"Fishing_Idle")
	player.global_position = home + Vector3(0.65, 0, 0)
	player.global_position.y = stance_y
	maker._moving = true
	maker._target_position = maker.position + Vector3(1.5, 0, 0)
	var anchor := player.global_position
	var max_delta := 0.0
	var max_lateral := 0.0
	var max_progress := 0.0
	var stagnant_walk := 0
	var worst_stagnant := 0
	var previous := maker.global_position
	for frame in range(600):
		await physics_frame
		max_delta = maxf(max_delta, player.global_position.distance_to(anchor))
		max_lateral = maxf(max_lateral, absf(maker.global_position.z - home.z))
		max_progress = maxf(max_progress, maker.global_position.x - home.x)
		var walk := String(maker.animated_sprite.animation).begins_with("walk")
		stagnant_walk = stagnant_walk + 1 if walk and previous.distance_to(maker.global_position) < 0.00001 else 0
		worst_stagnant = maxi(worst_stagnant, stagnant_walk)
		previous = maker.global_position
		if frame == 90 or frame == 180:
			await capture("card-maker-avoidance-%d" % frame)
	check(max_delta < 0.00001, "avoidance never moves Ryu")
	check(max_lateral > 0.15 and max_progress > 0.85, "Card Maker takes another route around player in open beach space")
	check(worst_stagnant <= 1, "no stationary walk loop")
	check(maker.avoidance_sensor.collision_layer == 0 and maker.avoidance_sensor.collision_mask == 3, "separate player sensor")
	check(player.platform_floor_layers == 0 and player.platform_wall_layers == 0, "platform isolation")
	print("AVOIDANCE max_player_delta=", max_delta, " lateral=", max_lateral, " progress=", max_progress, " stagnant_walk_ticks=", worst_stagnant)
	# The actual former crab footprint is detection-only, including both crabs.
	for name in ["BeachCritter", "BeachCritter2"]:
		var ambient: BeachFishingCritter = scene.get_node("World/" + name)
		check(ambient.find_children("*", "PhysicsBody3D", true, false).is_empty(), name + " has no hard geometry")
		check(ambient.proximity_area.collision_layer == 0 and ambient.proximity_area.collision_mask == 3, name + " detection only")
	maker.patrol_enabled = false
	player.global_position = crab.global_position
	player.global_position.y = stance_y
	anchor = player.global_position
	var crab_start := crab.global_position
	var camera: Camera3D = scene.get_viewport().get_camera_3d()
	# The real camera smooths after the test's relocation. Settle that existing
	# restoration first so it is not attributed to an ambient actor.
	for frame in range(180):
		await physics_frame
	var camera_height := camera.global_position.y
	var floor_before := player.is_on_floor()
	for frame in range(180):
		await physics_frame
		check(player.global_position.distance_to(anchor) < 0.00001, "crab overlap preserves player transform")
	check(crab.global_position.distance_to(crab_start) > 0.01, "crab proximity produces roaming/flee motion")
	check(absf(camera.global_position.y - camera_height) < 0.001, "crab cannot change settled camera height")
	check(player.is_on_floor() == floor_before, "crab creates no new floor")
	await capture("crab-proximity")
	# Walk through an isolated copy of the real crab without beach blockers.
	var test_crab: BeachFishingCritter = load("res://actors/BeachFishingCritter.tscn").instantiate()
	test_crab.position = Vector3(100, 0, 100)
	scene.add_child(test_crab)
	test_crab.set_physics_process(false)
	player.global_position = Vector3(99.65, 0, 100)
	player.camera_reference = null
	player.movement_enabled = true
	Input.action_press("move_right")
	for frame in range(90):
		await physics_frame
	Input.action_release("move_right")
	check(player.global_position.x > 100.15, "player walks through former crab body")
	check(absf(player.global_position.y) < 0.00001 and not player.is_on_floor(), "crab never becomes floor or raises Ryu")
	check(test_crab.position.is_equal_approx(Vector3(100, 0, 100)), "player cannot physically shove ambient critter")
	# Hard-contact fallback uses the actual expanded Card Maker collider and
	# authored vertical stance, with proactive sensing disabled deliberately.
	player.movement_enabled = false
	player.global_position = Vector3(200.5, stance_y, 200)
	maker.global_position = Vector3(200, home.y, 200)
	maker.avoidance_sensor.monitoring = false
	maker.patrol_enabled = true
	maker.idle_pause_min = 10.0
	maker.idle_pause_max = 10.0
	maker._moving = true
	maker._target_position = maker.position + Vector3(2, 0, 0)
	anchor = player.global_position
	for frame in range(180):
		await physics_frame
	check(player.global_position.distance_to(anchor) < 0.00001, "hard NPC contact preserves authored Ryu stance")
	check(not player.is_on_floor() and player.get_platform_velocity().is_zero_approx(), "dynamic NPC does not become floor/platform in ground contact")
	check(maker.locomotion_blocked and not maker._moving and String(maker.animated_sprite.animation).begins_with("idle"), "physical blockage explicitly idles and stops")
	var body_position := maker.global_position
	player.global_position = body_position + Vector3(-0.55, stance_y - body_position.y, 0)
	player.movement_enabled = true
	Input.action_press("move_right")
	for frame in range(60):
		await physics_frame
	Input.action_release("move_right")
	check(player.global_position.x < maker.global_position.x and player.get_slide_collision_count() > 0, "player cannot walk through humanoid safety body")
	check(maker.global_position.distance_to(body_position) < 0.00001 and absf(player.global_position.y - stance_y) < 0.00001, "neither humanoid pushes the other or changes height")
	print("WORLD ACTOR POLICY V2 QA: %d/%d" % [checks - failures.size(), checks])
	scene.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
