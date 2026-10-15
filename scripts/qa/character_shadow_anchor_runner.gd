extends SceneTree
const Isolation = preload("res://scripts/qa/qa_save_isolation.gd")
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	if not Isolation.verify():
		quit(1)
		return
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)

func settle() -> void:
	for frame in range(8): await process_frame

func check_contact(p: GroundPresentation, label: String) -> void:
	var actor := p.get_parent() as Node3D
	var shadow := p.shadow
	var expected := actor.global_position + Vector3(0, shadow.ground_offset, 0)
	check(shadow.global_position.is_equal_approx(expected), label + " shadow centered at physical feet")
	check(shadow.global_basis.is_equal_approx(Basis.IDENTITY), label + " shadow stays flat in world space")
	check(shadow.top_level and shadow.get_parent().get_parent() == p, label + " shadow independent of billboard")
	check(actor.find_children("*", "WorldBlobShadow", true, false).size() == 1, label + " has one blob shadow")
	var family := p.profile.resolved_shadow_family()
	check(is_equal_approx(shadow.width, family.width * p.profile.shadow_scale_multiplier)
		and is_equal_approx(shadow.depth, family.depth * p.profile.shadow_scale_multiplier)
		and is_equal_approx(shadow.opacity, family.opacity), label + " keeps authored family size and opacity")
	check(p.sprite == null or p.sprite.position.is_zero_approx(), label + " sprite feet registration preserved")

func turn(exploration: Node, key: Key) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = key
	event.pressed = true
	exploration._unhandled_input(event)
	await create_timer(0.4).timeout
	await settle()

func run() -> void:
	await settle()
	if not Isolation.verify_root_clock(self):
		quit(1)
		return
	var scene: Node = load("res://actors/FishingTestScene_V2.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await settle()
	var exploration: Node = scene.get_node("Game/Exploration")
	var rig: Node3D = scene.get_node("CameraRig")
	var names := ["CharacterBody3D", "BeachMerchantNPC", "BeachCrafterNPC", "FishingCardMakerNPC",
		"TripleTriadOpponentNPC", "FishingMasterCurrentReaderNPC", "FishingMasterStillWaterNPC",
		"FishingMasterWeatherWatcherNPC", "BeachCritter"]
	for actor in scene.get_node("World").get_children():
		if actor.name.begins_with("FishingMaster") and not names.has(actor.name):
			names.append(actor.name)
	var presentations: Array[GroundPresentation] = []
	for name in names:
		var actor := scene.find_child(name, true, false) as Node3D
		check(actor != null, name + " appears in playable scene")
		if actor == null: continue
		var p := actor.get_node("GroundPresentation") as GroundPresentation
		# Patrol and roaming are tested separately from camera motion below.
		actor.set_physics_process(false)
		presentations.append(p)
		check(p.profile.shadow_offset_x == 0.0 and p.profile.shadow_offset_z == 0.0,
			name + " has no authored sideways shadow compensation")
		check_contact(p, name)
	var baseline: Dictionary = {}
	for p in presentations: baseline[p.get_parent().name] = [p.get_parent().global_transform, p.shadow.global_transform]
	var start_yaw := rig.rotation.y
	for key in [KEY_Q, KEY_Q, KEY_Q, KEY_Q, KEY_E, KEY_E, KEY_E, KEY_E]:
		var previous_yaw := rig.rotation.y
		await turn(exploration, key)
		check(absf(wrapf(rig.rotation.y - previous_yaw, -PI, PI)) > 0.1, "Q/E input rotates the actual camera rig")
		for p in presentations:
			var name := String(p.get_parent().name)
			check_contact(p, name)
			check(p.get_parent().global_transform.is_equal_approx(baseline[name][0]), name + " camera turn leaves actor fixed")
			check(p.shadow.global_transform.is_equal_approx(baseline[name][1]), name + " camera turn leaves shadow fixed")
	check(absf(wrapf(rig.rotation.y - start_yaw, -PI, PI)) < 0.02, "Q/E orbit returns to starting yaw")
	for p in presentations:
		var actor := p.get_parent() as Node3D
		var origin := actor.global_position
		actor.global_position += Vector3(0.37, 0, -0.21)
		await settle()
		check_contact(p, "moving " + actor.name)
		check(p.shadow.global_position.distance_to(baseline[actor.name][1].origin + Vector3(0.37, 0, -0.21)) < 0.001,
			actor.name + " shadow follows actor movement in ground coordinates")
		actor.global_position = origin
		await settle()
	var moving := presentations[1]
	var moving_actor := moving.get_parent() as Node3D
	var original_profile := moving.profile
	moving.profile = original_profile.duplicate()
	moving.profile.shadow_offset_x = 0.035
	moving.profile.shadow_offset_z = -0.045
	moving.profile.shadow_scale_multiplier = 1.1
	moving.apply_profile()
	await settle()
	var edited_offset := moving.shadow.global_position - moving_actor.global_position
	check(edited_offset.is_equal_approx(Vector3(0.035, moving.shadow.ground_offset, -0.045)),
		"Inspector X/Z offsets use world ground coordinates")
	check(is_equal_approx(moving.shadow.width, moving.profile.resolved_shadow_family().width * 1.1),
		"Inspector scale multiplier changes shadow footprint")
	await turn(exploration, KEY_Q)
	check((moving.shadow.global_position - moving_actor.global_position).is_equal_approx(edited_offset),
		"Inspector ground offset remains fixed through Q turn")
	moving.profile = original_profile
	moving.apply_profile()
	await settle()
	check_contact(moving, "merchant restored profile")
	current_scene = null
	scene.queue_free()
	await settle()
	var orphans := Node.get_orphan_node_ids()
	print("CHARACTER SHADOW ANCHOR: %d/%d %s" % [checks - failures.size(), checks, failures])
	Isolation.emit_result("character_shadow_anchor_runner", checks - failures.size(), checks, failures.size(), orphans.size())
	quit(0 if failures.is_empty() and orphans.is_empty() else 1)

func _finalize() -> void:
	print("QA_PROCESS_FINALIZED")
