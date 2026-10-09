extends SceneTree

## Hard humanoid safety physics. Ambient critters have their own v2 QA.
## Optional --rendered saves contact frames while running at normal time scale.
const ActorPolicy = preload("res://scripts/world/autonomous_world_actor.gd")
const PlayerScene = preload("res://actors/ExplorationPlayer_V2.tscn")
const MakerScene = preload("res://actors/FishingCardMakerNPC.tscn")
const EPSILON := 0.00001
var capture_directory := OS.get_environment("TEMP").path_join("godot-actor-contact-qa")
var checks := 0
var failures: Array[String] = []
var fixture: Node3D
var camera: Camera3D
var max_player_displacement := 0.0
var rendered := false

func _initialize() -> void:
	rendered = OS.get_cmdline_user_args().has("--rendered")
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-dir="):
			capture_directory = argument.trim_prefix("--capture-dir=")
	if rendered and DirAccess.make_dir_recursive_absolute(capture_directory) != OK:
		push_error("Cannot create rendered QA capture directory")
		quit(1)
		return
	Engine.time_scale = 1.0 if rendered else 8.0
	Engine.physics_ticks_per_second = 60 if rendered else 240
	if not rendered:
		ProjectSettings.set_setting("application/config/use_custom_user_dir", true)
		var isolated := "CodexActorCollisionQA-%d-%d" % [Time.get_unix_time_from_system(), Time.get_ticks_usec()]
		ProjectSettings.set_setting("application/config/custom_user_dir_name", isolated)
		if not OS.get_user_data_dir().ends_with(isolated) or DirAccess.make_dir_recursive_absolute(OS.get_user_data_dir()) != OK:
			push_error("Refusing runtime QA without isolated userdata")
			quit(1)
			return
		print("ISOLATED USERDATA: ", OS.get_user_data_dir())
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)

func make_player() -> CharacterBody3D:
	var player: CharacterBody3D = PlayerScene.instantiate()
	fixture.add_child(player)
	player.collision_layer = 1
	player.movement_enabled = false
	return player

func make_actor(kind: String, start: Vector3) -> CharacterBody3D:
	assert(kind == "npc", "Ambient critters belong to world_actor_policy_v2_qa")
	var actor: CharacterBody3D = MakerScene.instantiate()
	actor.position = start
	fixture.add_child(actor)
	actor.set_physics_process(false)
	actor.avoidance_sensor.monitoring = false
	return actor

func arm_contact(actor: CharacterBody3D, kind: String) -> void:
	actor._moving = true
	actor._target_position = actor.position + Vector3(2.55, 0, 0)

func contact_step(actor: CharacterBody3D, kind: String) -> void:
	if actor._moving:
		actor._process_patrol_leg(1.0 / 60.0)

func contact_case(kind: String, state: String, player_layer := 1, legacy_platforms := false) -> void:
	var player := make_player()
	player.collision_layer = player_layer
	player.movement_enabled = state == "exploration_idle"
	if legacy_platforms:
		# Prove actor ownership is the primary fix, independently of Ryu's guard.
		player.platform_floor_layers = 0xFFFFFFFF
	var actor := make_actor(kind, Vector3(-0.55, 0, 0))
	arm_contact(actor, kind)
	var anchor := player.global_position
	var maximum := 0.0
	var platform_maximum := 0.0
	for frame in range(240):
		await physics_frame
		contact_step(actor, kind)
		maximum = maxf(maximum, player.global_position.distance_to(anchor))
		platform_maximum = maxf(platform_maximum, player.get_platform_velocity().length())
	max_player_displacement = maxf(max_player_displacement, maximum)
	check(maximum <= EPSILON, "%s/%s preserves player anchor across 240 contact ticks" % [kind, state])
	check(platform_maximum <= EPSILON, "%s/%s transfers no platform velocity" % [kind, state])
	check(actor.global_position.x < player.global_position.x, "%s/%s cannot pass through Ryu" % [kind, state])
	check(not actor._moving, "%s/%s stops in existing idle/repath state" % [kind, state])
	var collision := KinematicCollision3D.new()
	check(actor.test_move(actor.global_transform, Vector3(0.05, 0, 0), collision) and collision.get_collider() == player,
		"%s/%s player remains the physical blocker" % [kind, state])
	var area := Area3D.new()
	area.collision_layer = 0
	area.collision_mask = 3
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.75
	shape.shape = sphere
	area.add_child(shape)
	fixture.add_child(area)
	for frame in range(3):
		await physics_frame
	check(area.get_overlapping_bodies().has(player) and not area.get_overlapping_bodies().has(actor), "player-only interaction Areas ignore autonomous %s body" % kind)
	area.free()
	print("CONTACT ", kind, "/", state, " layer=", player_layer, " legacy_platforms=", legacy_platforms,
		" max_player_delta=", maximum, " platform_velocity=", platform_maximum, " actor=", actor.global_position)
	if rendered:
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(capture_directory.path_join("actor-contact-%s.png" % kind))
	actor.free()
	player.free()
	await physics_frame

func walking_case(kind: String) -> void:
	var player := make_player()
	player.position = Vector3(-0.75, 0, 0)
	player.move_speed = 0.7
	player.movement_enabled = true
	var actor := make_actor(kind, Vector3.ZERO)
	var initial := actor.global_position
	Input.action_press("move_right")
	for frame in range(90):
		await physics_frame
	Input.action_release("move_right")
	check(actor.global_position.distance_to(initial) <= EPSILON, "player walking cannot shove stationary %s" % kind)
	check(player.global_position.x < actor.global_position.x, "player walking is blocked by %s" % kind)
	check(player.get_slide_collision_count() > 0, "real player move_and_slide reports %s collision" % kind)
	actor.free()
	player.free()
	await physics_frame

func roaming_case(kind: String) -> void:
	var actor := make_actor(kind, Vector3(1.5, 0, 0))
	actor._rng.seed = 2468
	var initial := actor.global_position
	actor._pause_remaining = 0.0
	actor.set_physics_process(true)
	var traveled := 0.0
	var previous := initial
	for frame in range(240):
		await physics_frame
		traveled += actor.global_position.distance_to(previous)
		previous = actor.global_position
	check(traveled > 0.1, "%s still roams through its actual physics callback" % kind)
	check(is_equal_approx(actor.position.y, initial.y), "%s stays at its authored stance height" % kind)
	check(actor is ActorPolicy and actor.velocity.is_zero_approx(), "%s shares collision policy without platform locomotion velocity" % kind)
	print("ROAM ", kind, " total_distance=", traveled)
	actor.free()
	await physics_frame

func native_contact_case(kind: String) -> void:
	var player := make_player()
	player.sprite_director.play(&"Fishing_Idle")
	var actor := make_actor(kind, Vector3(-0.55, 0, -0.55))
	actor._rng.seed = 2468
	arm_contact(actor, kind)
	actor._target_position = Vector3(2, 0, 2)
	actor.set_physics_process(true)
	var anchor := player.global_position
	var maximum := 0.0
	var contacted := false
	for frame in range(240):
		await physics_frame
		maximum = maxf(maximum, player.global_position.distance_to(anchor))
		var stopped: bool = not actor._moving
		if stopped and not contacted:
			var collision := KinematicCollision3D.new()
			contacted = actor.test_move(actor.global_transform, Vector3(0.05, 0, 0), collision) and collision.get_collider() == player
			if contacted and rendered:
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png(capture_directory.path_join("actor-contact-%s.png" % kind))
	max_player_displacement = maxf(max_player_displacement, maximum)
	check(contacted, "%s actual roaming callback reaches and stops at Ryu" % kind)
	check(maximum <= EPSILON, "%s native contact/idle/repath cycle never moves Ryu" % kind)
	print("NATIVE CONTACT ", kind, " contacted=", contacted, " max_player_delta=", maximum)
	actor.free()
	player.free()
	await physics_frame

func runtime_contact(player: CharacterBody3D, kind: String, label: String) -> void:
	# While a real modal owns pause, place the fixture at the established contact
	# footprint rather than expecting a paused roaming actor to approach it.
	var distance := 0.258 if paused else 0.55
	var actor := make_actor(kind, player.global_position + Vector3(-distance, 0, 0))
	arm_contact(actor, kind)
	var anchor := player.global_position
	var maximum := 0.0
	for frame in range(180):
		await physics_frame
		contact_step(actor, kind)
		maximum = maxf(maximum, player.global_position.distance_to(anchor))
	check(maximum <= EPSILON, "real beach %s/%s preserves player anchor" % [label, kind])
	check(actor.global_position.x < player.global_position.x, "real beach %s/%s cannot pass through player" % [label, kind])
	var contact := KinematicCollision3D.new()
	check(actor.test_move(actor.global_transform, Vector3(0.05, 0, 0), contact) and contact.get_collider() == player,
		"real beach %s/%s retains physical player contact" % [label, kind])
	print("ACTUAL STATE ", label, "/", kind, " max_player_delta=", maximum, " paused=", paused)
	actor.free()
	await physics_frame

func test_runtime_modes() -> void:
	fixture = load("res://actors/FishingTestScene_V2.tscn").instantiate()
	root.add_child(fixture)
	current_scene = fixture
	for frame in range(8):
		await process_frame
	var player: CharacterBody3D = fixture.get_node("Player/CharacterBody3D")
	# Isolate contacts from the beach's unrelated static blockers, without
	# changing any authored actor positions/resources or the normal save.
	player.global_position = Vector3(100, 0, 100)
	var fishing = fixture.get_node("Game/Fishing")
	var mode = fixture.get_node("Game/GameMode")
	var zone = fixture.get_node("World/FishZone_V2")
	mode.enter_fishing(zone)
	fishing.set_process(false)
	fishing.sprite_director.play(&"Fishing_Idle")
	for phase in [fishing.Phase.IN_WATER, fishing.Phase.FIGHT, fishing.Phase.LANDING, fishing.Phase.WAIT_RESULT]:
		fishing.phase = phase
		fishing.encounter.lifecycle.finish_cast()
		fishing.encounter.lifecycle.begin_cast()
		if phase in [fishing.Phase.FIGHT, fishing.Phase.LANDING, fishing.Phase.WAIT_RESULT]:
			fishing.encounter.lifecycle.confirm_hook()
		if phase in [fishing.Phase.LANDING, fishing.Phase.WAIT_RESULT]:
			fishing.encounter.begin_catch_landing()
		if phase == fishing.Phase.WAIT_RESULT:
			var caught := FishInstance.new()
			caught.species = load("res://data/bof4/fish/sea_bream.tres")
			caught.size = 20
			fishing.fishing_catch_view.show_catch(caught)
		check(mode.is_fishing() and not player.movement_enabled, "production fishing phase %d locks player input" % phase)
		for kind in ["npc"]:
			await runtime_contact(player, kind, "phase_%d" % phase)
		var ambient: BeachFishingCritter = load("res://actors/BeachFishingCritter.tscn").instantiate()
		ambient.position = player.global_position + Vector3(0, -0.055645, 0)
		fixture.add_child(ambient)
		var anchor := player.global_position
		var initial := ambient.global_position
		for frame in range(90):
			await physics_frame
		check(player.global_position.distance_to(anchor) <= EPSILON, "ambient overlap preserves real fishing anchor in phase %d" % phase)
		check(ambient.find_children("*", "PhysicsBody3D", true, false).is_empty(), "ambient cannot become fishing floor/body")
		check(ambient.global_position.distance_to(initial) > 0.001, "ambient still responds/roams while fishing")
		ambient.free()
	fishing.fishing_catch_view.hide_catch()
	mode.exit_fishing()
	var merchant = fixture.get_node("World/BeachMerchantNPC")
	merchant._start_interaction()
	check(paused and merchant._dialogue_bridge.has_pending_interaction(), "real merchant dialogue opens and owns pause")
	for kind in ["npc"]:
		await runtime_contact(player, kind, "dialogue_open")
	var session := root.get_node("FishingSessionServices")
	session.dialogue_service.cancel(&"qa_finished")
	check(not paused, "dialogue correctly releases pause")
	var menu = fishing.fishing_economy_menu
	check(menu.open_merchant_menu(merchant.economy_context, merchant, menu.MODE_TRADE) and paused, "real contextual merchant/trade UI opens")
	for kind in ["npc"]:
		await runtime_contact(player, kind, "trade_ui_open")
	menu.close_menu()
	check(not paused, "trade UI correctly releases pause")
	for property in ["presentation_qa_report", "system_stability_qa_report"]:
		var report: Dictionary = session.get(property)
		print(property, ": ", report.passed_count, "/", report.test_count)
		check(report.passed_count == report.test_count, property)
	fixture.queue_free()
	session.queue_free()
	for frame in range(3):
		await process_frame

func run() -> void:
	var orphan_before := Node.get_orphan_node_ids()
	fixture = Node3D.new()
	fixture.name = "WorldActorCollisionQA"
	root.add_child(fixture)
	current_scene = fixture
	if rendered:
		camera = Camera3D.new()
		fixture.add_child(camera)
		camera.position = Vector3(0, 1.8, 2.4)
		camera.look_at(Vector3(0, 0.15, 0))
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		camera.size = 2.2
		camera.current = true
		var ground := MeshInstance3D.new()
		var mesh := PlaneMesh.new()
		mesh.size = Vector2(3, 3)
		ground.mesh = mesh
		ground.position.y = -0.012
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_color = Color(0.62, 0.52, 0.3)
		ground.material_override = material
		fixture.add_child(ground)
	for kind in ["npc"]:
		if rendered:
			await native_contact_case(kind)
		else:
			for state in ["exploration_idle", "fishing_in_water", "fishing_fight", "landing", "catch_result", "dialogue", "merchant_trade"]:
				await contact_case(kind, state)
			await contact_case(kind, "primary_fix_without_player_guard", 2, true)
			await walking_case(kind)
			await roaming_case(kind)
			await native_contact_case(kind)
	fixture.free()
	if not rendered:
		await test_runtime_modes()
	for id in Node.get_orphan_node_ids():
		if not orphan_before.has(id):
			check(false, "collision fixture leaked orphan node %d" % id)
	print("WORLD ACTOR COLLISION QA: %d/%d; max passive player displacement=%s; epsilon=%s" % [checks - failures.size(), checks, max_player_displacement, EPSILON])
	quit(0 if failures.is_empty() else 1)
