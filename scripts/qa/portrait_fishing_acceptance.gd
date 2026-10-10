extends Node
## Rendered integration fixture. No phase assignments or animation shortcuts.
var checks := 0
var failures: Array[String] = []
var shell: Node
var fishing: Node
var finished_animations: Array[StringName] = []
var casts := 0
@export var companion := false
@export var test_camera_dead_zone := false
class ForcedFish extends RefCounted:
	func get_forced_fish(): return load("res://data/bof4/fish/sea_bream.tres")
func _ready() -> void:
	ProjectSettings.set_setting("application/config/use_custom_user_dir", true)
	ProjectSettings.set_setting("application/config/custom_user_dir_name", "PortraitFishingAcceptance-%d" % Time.get_ticks_usec())
	check(DirAccess.make_dir_recursive_absolute(OS.get_user_data_dir()) == OK, "isolated save directory exists")
	call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); push_error(label)
func wait_for(predicate: Callable, label: String, seconds := 12.0) -> bool:
	# Web background rendering can throttle frame delivery. Animation contracts
	# use simulation time, with a separate wall watchdog for a genuinely stalled host.
	var remaining := seconds
	var until := Time.get_ticks_msec() + int(seconds * (10.0 if OS.has_feature("web") else 2.0) * 1000)
	while not predicate.call() and remaining > 0 and Time.get_ticks_msec() < until:
		await get_tree().process_frame
		remaining -= get_process_delta_time()
	var ok: bool = predicate.call()
	if not ok and is_instance_valid(fishing):
		var actor: AnimatedSprite3D = fishing.sprite_director.sprite
		print("ACCEPTANCE TIMEOUT: phase=", fishing.phase, " paused=", get_tree().paused,
			" animation=",actor.animation," frame=",actor.frame," playing=",actor.is_playing(),
			" process=",actor.can_process()," completed=",finished_animations)
	check(ok, label)
	return ok
func tap(label: String) -> void:
	press(label, true)
	await get_tree().create_timer(0.10).timeout
	press(label, false)
	await get_tree().create_timer(0.10).timeout
func press(label: String, down: bool) -> void:
	if companion:
		var key := InputEventKey.new()
		key.physical_keycode = KEY_K if label == "A" else KEY_I
		key.keycode = key.physical_keycode
		key.pressed = down
		Input.parse_input_event(key)
	elif down: shell.controls.touch_begin(70, shell.controls.buttons[label].get_center())
	else: shell.controls.touch_end(70)
func cast() -> bool:
	await tap("A")
	if not await wait_for(func(): return fishing.phase == fishing.Phase.CHARGE, "Prep_Throw completes through real animation callback"): return false
	await tap("A")
	check(fishing.phase == fishing.Phase.CURVE, "touch locks power through production input")
	await tap("A")
	if not await wait_for(func(): return fishing.phase == fishing.Phase.IN_WATER, "Throw completes and physical bait reaches water"): return false
	check(finished_animations.has(&"Throw"), "Throw completion signal delivered")
	check(is_instance_valid(fishing.caster.active_bait), "water state owns physical bait")
	check(fishing.camera_rig._fight_tracking_active, "water camera retains tracking ownership")
	return true
func retrieve() -> bool:
	fishing.encounter.bite_timer.stop() # fixture isolates retrieve from random selection
	press("A",true)
	var ok := await wait_for(func(): return fishing.phase == fishing.Phase.AIM, "held touch retrieves physical bait and returns ready", 25.0)
	press("A",false)
	check(not is_instance_valid(fishing.caster.active_bait), "retrieve clears bait")
	return ok
func run() -> void:
	print("ACCEPTANCE START")
	shell = load("res://actors/desktop/DesktopCompanion.tscn" if companion else "res://actors/mobile/MobilePortraitHarness.tscn").instantiate()
	if not companion:
		shell.developer_playtest_default_enabled = false
		shell.isolated_playtest_save = false
	get_tree().root.add_child(shell)
	get_tree().current_scene = shell
	await get_tree().create_timer(1.0).timeout
	fishing = shell.game.get_node("Game/Fishing")
	print("ACCEPTANCE MOUNTED")
	fishing.sprite_director.animation_finished.connect(func(a): finished_animations.append(a))
	fishing.cast_started.connect(func(): casts += 1)
	var session := get_tree().root.get_node("FishingSessionServices")
	var session_id := session.get_instance_id()
	fishing.player.rotation.y = PI
	fishing.game_mode.enter_fishing(shell.game.get_node("World/FishZone_V2"))
	if not await wait_for(func(): return fishing.phase == fishing.Phase.AIM, "entry reaches AIM through camera and animation callbacks"): await finish(); return
	await get_tree().create_timer(0.15).timeout
	for cycle in range(3):
		print("ACCEPTANCE CYCLE ", cycle)
		if not await cast(): await finish(); return
		if test_camera_dead_zone:
			await camera_dead_zone(cycle)
		if not companion and cycle == 0:
			if not OS.has_feature("web"): get_window().size = Vector2i(390,664)
			await get_tree().create_timer(0.12).timeout
			shell._layout()
			var projected: Vector2 = fishing.camera_rig.get_node("Camera3D").unproject_position(fishing.caster.active_bait.global_position)
			var displayed: Vector2 = shell.gameplay_image.global_position + projected * shell.gameplay_image.size / Vector2(shell.gameplay_viewport.size)
			check(shell.gameplay_window.get_global_rect().has_point(displayed), "water target remains inside short-window display")
			check(shell.gameplay_image.size.x == shell.safe_rect.size.x, "live water display uses full width")
			if DisplayServer.get_name() != "headless":
				await RenderingServer.frame_post_draw
				if OS.has_feature("web"):
					print("RENDERED WATER FRAME: ", shell.gameplay_viewport.size, " projected=",projected," display=",displayed)
				else:
					get_window().get_texture().get_image().save_png("res://build/mobile-web/portrait-captures/acceptance-water.png")
		# Resize presentation during a live cast without changing logical surface.
		shell._layout()
		check(not get_tree().paused and fishing.can_process(), "shell layout leaves fishing processing enabled")
		check(session.get_instance_id() == session_id, "shell layout preserves session identity")
		if companion:
			var bait: int = fishing.caster.active_bait.get_instance_id()
			for next in range(3):
				if next < 2: shell.toggle_collapse()
				else: shell.set_mode(shell.Mode.ACTIVE)
				await get_tree().create_timer(0.12).timeout
				check(fishing.can_process() and not get_tree().paused, "companion mode never pauses fishing")
				check(fishing.caster.active_bait.get_instance_id() == bait, "companion mode preserves physical bait")
				check(session.get_instance_id() == session_id, "companion mode preserves session")
				check(shell.gameplay_viewport.size == Vector2i(640,864), "companion mode preserves canonical surface")
		if cycle > 0:
			fishing.encounter.debug_settings = ForcedFish.new()
			fishing.encounter.bite_timer.start(0.05)
			if not await wait_for(func(): return fishing.encounter.bite_active, "real bite timer opens opportunity"): await finish(); return
			check(fishing.caster.active_bait.ripple_view.active, "opportunity ripple active")
			if cycle == 1:
				if not await wait_for(func(): return not fishing.encounter.bite_active, "missed opportunity resolves by timer"): await finish(); return
				check(not fishing.bite_opportunity_animation_active, "miss releases opportunity animation")
			else:
				if not await wait_for(func(): return fishing.encounter.bite_hook_ready, "hook timing becomes ready"): await finish(); return
				await tap("A")
				check(fishing.phase == fishing.Phase.FIGHT, "touch hooks through production path")
				# Deterministic landing fixture uses the real returned-bait boundary;
				# this validates result animations/ownership, not fight balancing.
				fishing.caster._on_bait_returned()
				if not await wait_for(func(): return fishing.phase == fishing.Phase.WAIT_RESULT, "landing and catch animations reach result", 15.0): await finish(); return
				var result_view: Node = fishing.fishing_catch_view
				var result_rect: Rect2 = result_view.composed_result_rect()
				var result_center: Vector2 = result_view.root.position + result_rect.get_center()
				var surface: Rect2 = result_view.get_meta("gameplay_presentation_rect",Rect2(Vector2.ZERO,Vector2(shell.gameplay_viewport.size)))
				check(result_center.distance_to(surface.get_center()) < 0.01,"rendered composed catch group centered in actual gameplay presentation")
				check(fishing.last_outcome_result.get("catch_committed", false), "catch commits through existing persistence boundary")
				if not companion: check(is_zero_approx(shell._surface_scroll), "real catch-result header is not cropped")
				await tap("A")
				if not await wait_for(func(): return fishing.phase == fishing.Phase.AIM, "touch dismisses catch through existing return"): await finish(); return
				continue
		if not await retrieve(): await finish(); return
	check(casts == 3, "exactly one cast-start notification per cast")
	await tap("B")
	await wait_for(func(): return fishing.game_mode.is_exploration(), "normal cancel exits fishing", 15.0)
	check(session.get_instance_id() == session_id, "full lifecycle preserves one session")
	if companion:
		check(shell.find_children("TouchControls", "Control", true, false).is_empty(), "companion has no mobile controls")
		check(not preload("res://scripts/ui/portrait_ui.gd").mobile(fishing), "companion selects keyboard hints")
		for controller in [fishing.fishing_menu, shell.game.get_node("World/BeachCrafterNPC/BeachCraftingMenu"), shell.game.get_node("World/FishingCardMakerNPC/FishingCardMakerMenu")]:
			controller.open_menu()
			check(controller.is_open() and get_tree().paused, "original menu opens after companion restore: " + controller.name)
			controller.close_menu()
			check(not get_tree().paused, "original menu close restores processing")
		var cards: Node = shell.game.get_node("UI/TripleTriadGame")
		DeveloperPlaytestService.current().set_enabled(true)
		check(cards.open_game_by_id(shell.game.get_node("World/TripleTriadOpponentNPC").opponent_id), "card encounter opens after companion restore")
		cards._on_deck_confirmed(cards.deck_setup._deck.duplicate())
		await get_tree().create_timer(2.0).timeout
		check(cards.is_open(), "card match starts after companion restore")
		cards.close_game()
		check(not get_tree().paused, "card close restores pause ownership")
	await finish()
func finish() -> void:
	var report := {"passed": checks - failures.size(), "total": checks, "failures": failures, "casts": casts, "renderer": DisplayServer.get_name()}
	print("PORTRAIT FISHING ACCEPTANCE: ", JSON.stringify(report))
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.portraitFishingReport=" + JSON.stringify(report), true)
	else:
		# Release the disposable host before its session owner, matching travel
		# fixtures; retained session UI must return to a still-live viewport.
		shell.queue_free()
		for frame in range(3): await get_tree().process_frame
		var session := get_node_or_null("/root/FishingSessionServices")
		if session!=null: session.queue_free()
		for frame in range(3): await get_tree().process_frame
		get_tree().quit(0 if failures.is_empty() else 1)

func camera_dead_zone(cycle: int) -> void:
	# Deterministic fixture-only physical target placement. Production casting,
	# movement and camera APIs are unchanged; actual cast/return still run above.
	var bait: Node3D = fishing.caster.active_bait
	var original := bait.global_transform
	var original_mode := bait.process_mode
	bait.process_mode=Node.PROCESS_MODE_DISABLED
	fishing.encounter.bite_timer.stop()
	var rig: Node = fishing.camera_rig
	var camera: Camera3D = rig.get_node("Camera3D")
	for side in [-1,1,1,-1,-1,1]:
		var held := camera.global_transform
		for x in ([0.5,0.20,0.15,0.125] if side<0 else [0.5,0.85,0.89,0.915]):
			bait.global_position=camera.project_position(Vector2(x,.4)*Vector2(shell.gameplay_viewport.size),12)
			await get_tree().create_timer(.12).timeout
			check(not rig.fight_camera_tracking.tracking and camera.global_transform.is_equal_approx(held),"rendered visible drift/old boundary holds shot on side %d" % side)
		bait.global_position=camera.project_position(Vector2(.08 if side<0 else .94,.4)*Vector2(shell.gameplay_viewport.size),12)
		var physical := bait.global_position
		await get_tree().process_frame
		await get_tree().process_frame
		check(rig.fight_camera_tracking.tracking and (rig.fight_camera_tracking.requested_yaw-rig.fight_camera_tracking.yaw)*side<0,"rendered clear outer crossing requests correct yaw")
		check(absf(rig.fight_camera_tracking.yaw)<absf(rig.fight_camera_tracking.requested_yaw),"rendered correction retains slow exponential response")
		bait.global_position=camera.project_position(Vector2(.13 if side<0 else .91,.4)*Vector2(shell.gameplay_viewport.size),12)
		await get_tree().process_frame
		check(rig.fight_camera_tracking.tracking,"rendered slight return keeps latch")
		var edge_pose := camera.global_transform
		bait.global_position=camera.project_position(Vector2(.5,.5)*Vector2(shell.gameplay_viewport.size),12)
		await get_tree().process_frame
		await get_tree().process_frame
		check(not rig.fight_camera_tracking.tracking and camera.global_transform == edge_pose,"rendered active latch stops immediately on central safe-rectangle entry")
		bait.global_position=camera.project_position(Vector2(.5,.4)*Vector2(shell.gameplay_viewport.size),12)
		await get_tree().process_frame
		await get_tree().process_frame
		check(not rig.fight_camera_tracking.tracking,"rendered inner return stops latch")
		var stopped := camera.global_transform
		for frame in range(60):
			bait.global_position=camera.project_position(Vector2(0.5+sin(frame*.1)*.15,.4)*Vector2(shell.gameplay_viewport.size),12)
			await get_tree().process_frame
			check(camera.global_transform == stopped, "central drift frame keeps exact camera transform %d" % frame)
		check(camera.global_transform.is_equal_approx(stopped),"rendered current/passive-style drift holds shot without micro-rotation")
		var projected := camera.unproject_position(bait.global_position)
		var display: Rect2 = shell.gameplay_display_rect() if companion else shell.gameplay_window.get_global_rect()
		var displayed: Vector2 = display.position + projected * display.size / Vector2(shell.gameplay_viewport.size) if companion else shell.gameplay_image.global_position+projected*shell.gameplay_image.size/Vector2(shell.gameplay_viewport.size)
		check(display.has_point(displayed),"rendered physical bait remains inside visible host gameplay after stopping")
		check(physical!=original.origin,"fixture explicitly exercises physical target, not visibility gating")
		print("RENDERED DEAD ZONE: cycle=",cycle," side=",side," yaw=",rig.fight_camera_tracking.yaw," screen=",camera.unproject_position(bait.global_position)/Vector2(shell.gameplay_viewport.size))
	bait.global_transform=original
	bait.process_mode=original_mode
	# Leave a deterministic large left/right yaw for real retrieve/landing below.
	rig.fight_camera_tracking.yaw=deg_to_rad(-45 if cycle%2==0 else 45)
	camera.global_transform=rig._fight_orbit_transform(rig.global_transform*rig._fight_base_camera_transform,rig.target.global_position,rig.fight_camera_tracking.yaw)
