extends Node
## Rendered integration fixture. No phase assignments or animation shortcuts.
var checks := 0
var failures: Array[String] = []
var shell: Node
var fishing: Node
var finished_animations: Array[StringName] = []
var casts := 0
@export var companion := false
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
	var until := Time.get_ticks_msec() + int(seconds * 1000)
	while not predicate.call() and Time.get_ticks_msec() < until:
		await get_tree().process_frame
	var ok: bool = predicate.call()
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
	if not await wait_for(func(): return fishing.phase == fishing.Phase.AIM, "entry reaches AIM through camera and animation callbacks"): return finish()
	await get_tree().create_timer(0.15).timeout
	for cycle in range(3):
		print("ACCEPTANCE CYCLE ", cycle)
		if not await cast(): return finish()
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
			if not await wait_for(func(): return fishing.encounter.bite_active, "real bite timer opens opportunity"): return finish()
			check(fishing.caster.active_bait.ripple_view.active, "opportunity ripple active")
			if cycle == 1:
				if not await wait_for(func(): return not fishing.encounter.bite_active, "missed opportunity resolves by timer"): return finish()
				check(not fishing.bite_opportunity_animation_active, "miss releases opportunity animation")
			else:
				if not await wait_for(func(): return fishing.encounter.bite_hook_ready, "hook timing becomes ready"): return finish()
				await tap("A")
				check(fishing.phase == fishing.Phase.FIGHT, "touch hooks through production path")
				# Deterministic landing fixture uses the real returned-bait boundary;
				# this validates result animations/ownership, not fight balancing.
				fishing.caster._on_bait_returned()
				if not await wait_for(func(): return fishing.phase == fishing.Phase.WAIT_RESULT, "landing and catch animations reach result", 15.0): return finish()
				check(fishing.last_outcome_result.get("catch_committed", false), "catch commits through existing persistence boundary")
				if not companion: check(is_zero_approx(shell._surface_scroll), "real catch-result header is not cropped")
				await tap("A")
				if not await wait_for(func(): return fishing.phase == fishing.Phase.AIM, "touch dismisses catch through existing return"): return finish()
				continue
		if not await retrieve(): return finish()
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
	finish()
func finish() -> void:
	var report := {"passed": checks - failures.size(), "total": checks, "failures": failures, "casts": casts, "renderer": DisplayServer.get_name()}
	print("PORTRAIT FISHING ACCEPTANCE: ", JSON.stringify(report))
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.portraitFishingReport=" + JSON.stringify(report), true)
	else: get_tree().quit(0 if failures.is_empty() else 1)
