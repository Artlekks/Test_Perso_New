extends SceneTree
## Environmental Integration v7 — live weather transitions DURING a Lake/River cast
## and fight. Additive, isolated QA: no production script/scene changes.
## Real location, controller, action input, ecology, weather and catch services.
## Deterministic animation-completion and bait-contact shortcuts remain explicit.

const FishingController = preload("res://scripts/fishing.gd")
const BaitController = preload("res://scripts/bait_V2.gd")
const CASES = [
	{"location_id": &"lyp_lake_outpost", "spot_id": &"lake_2"},
	{"location_id": &"river_fishing_outpost", "spot_id": &"river_2"},
]

var passed: int = 0
var failures: Array[String] = []
var previous_counts: Dictionary = {}


func _initialize() -> void:
	ProjectSettings.set_setting("application/config/use_custom_user_dir", true)
	var directory: String = "EnvironmentalIntegrationV7QA-%d" % Time.get_ticks_usec()
	ProjectSettings.set_setting("application/config/custom_user_dir_name", directory)
	if not OS.get_user_data_dir().ends_with(directory) or DirAccess.make_dir_recursive_absolute(OS.get_user_data_dir()) != OK:
		push_error("Environmental Integration v7: save isolation failed; aborting before gameplay.")
		quit(1)
		return
	print("Environmental Integration v7 isolated user data: ", OS.get_user_data_dir())
	_run.call_deferred()


func check(ok: bool, message: String) -> void:
	if ok:
		passed += 1
	else:
		failures.append(message)
		push_error("Environmental Integration v7 QA: " + message)


func frames(count: int = 3) -> void:
	for _i in range(count):
		await process_frame


func _force_auto_rain(node: Node) -> void:
	# Scene preview modes must not override scheduled weather in automated QA.
	if node.name == &"FishingRainVFX" and node.has_method("_poll_weather"):
		node.set("weather_mode", 0)
		node.set("enabled", true)


func _minute_for(weather: Node, condition: StringName) -> int:
	var interval: int = maxi(int(weather.get("weather_window_minutes")), 60)
	for window in range(1, 240):
		var minute: int = window * interval + 20
		var state: Dictionary = weather.call("get_snapshot_at_minutes", minute) as Dictionary
		if StringName(state.get("condition_id", "")) == condition:
			return minute
	return -1


func _set_condition(clock: Node, weather: Node, condition: StringName) -> bool:
	var minute: int = _minute_for(weather, condition)
	if minute < 0:
		return false
	var time_of_day: int = minute % 1440
	return bool(clock.call("set_clock", int(minute / 1440) + 1, int(time_of_day / 60), time_of_day % 60))


func _visible_water_contact(fishing: Node, zone: Node) -> Variant:
	# Choose an actual lake/river water point, not the intersection of the
	# camera ray with an *infinite* horizontal plane. An infinite-plane hit
	# may be over dry sand/behind the shoreline and is then moved by the
	# production water/shore constraints during the test, causing the bait
	# to slide into the HUD even though its initial projected pixel was safe.
	var rig: Node = fishing.get("camera_rig") as Node
	if rig == null:
		return null
	var camera: Camera3D = rig.get_node_or_null("Camera3D") as Camera3D
	if camera == null or not camera.current:
		return null
	var swim: Node = zone.call("get_swim_bounds") as Node
	if swim == null or not swim.has_method("normalized_uv_to_world"):
		return null
	var shore: Node = zone.call("get_shore_boundary") as Node
	var size: Vector2 = camera.get_viewport().get_visible_rect().size
	if size.x <= 0.0 or size.y <= 0.0:
		return null
	var screen_region: Rect2 = rig.call("free_lure_viewport_region") as Rect2
	# Use a cushion from the edge; no part of this QA fixture should require
	# the camera's water-tracking rescue or HUD containment grace period.
	var region: Rect2 = screen_region.grow(-0.055)
	var hud: Array = rig.call("fishing_hud_regions_pixels") as Array
	var water_y: float = float(zone.call("get_water_y"))
	var chosen: Variant = null
	var best_score: float = INF
	# The fish-swim volume is authored in each location. Searching its real
	# footprint preserves the shoreline and avoids arbitrary magic world coords.
	for iy in range(15):
		for ix in range(15):
			var uv := Vector2((float(ix) + 0.5) / 15.0, (float(iy) + 0.5) / 15.0)
			var point: Vector3 = swim.call("normalized_uv_to_world", uv, water_y) as Vector3
			if swim.has_method("contains_horizontal") and not bool(swim.call("contains_horizontal", point)):
				continue
			if shore != null and shore.has_method("get_water_side_projection"):
				var shore_safe: Vector3 = shore.call("get_water_side_projection", point) as Vector3
				if Vector2(shore_safe.x, shore_safe.z).distance_to(Vector2(point.x, point.z)) > 0.015:
					continue
			var surface_point := point + Vector3(0.0, 0.025, 0.0)
			if camera.is_position_behind(surface_point):
				continue
			var pixel: Vector2 = camera.unproject_position(surface_point)
			var normalized: Vector2 = pixel / size
			if not region.has_point(normalized):
				continue
			var blocked := false
			for rect in hud:
				if (rect as Rect2).grow(12.0).has_point(pixel):
					blocked = true
					break
			if blocked:
				continue
			# Prefer the upper-middle of the physical water picture, with enough
			# clearance for small current drift while the weather transitions.
			var score: float = normalized.distance_squared_to(Vector2(0.49, 0.32))
			if score < best_score:
				best_score = score
				chosen = point
	return chosen

func _wait_for_visible_fade_out(rain: Node, before: float) -> bool:
	# Weather state/target become authoritative before GPU/VFX frames blend.
	# Waiting a fixed 0.6 seconds from the clock change is not sufficient:
	# polling can occur at the end of that timer on a busy/headless engine.
	# Observe subsequent real process frames instead of manually calling the
	# VFX update (which would stop this being an integration test).
	var started: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < 800:
		await frames(2)
		if float(rain.get("_rain_level")) < before - 0.001:
			return true
	return false


func _release_input(fishing: Node, name: StringName) -> void:
	Input.action_release(name)
	var event := InputEventAction.new()
	event.action = name
	event.pressed = false
	if is_instance_valid(fishing):
		fishing.call("_unhandled_input", event)


func _action(fishing: Node, name: StringName, pressed: bool) -> void:
	if pressed:
		Input.action_press(name)
	else:
		Input.action_release(name)
	var event := InputEventAction.new()
	event.action = name
	event.pressed = pressed
	fishing.call("_unhandled_input", event)


func _release_all(fishing: Node) -> void:
	for name in [&"enter_fishing", &"cancel_fishing", &"ds_left", &"ds_right", &"move_back", &"move_forward"]:
		_release_input(fishing, name)


func _enter_shoreline() -> void:
	var press := InputEventKey.new()
	press.keycode = KEY_K
	press.physical_keycode = KEY_K
	press.pressed = true
	var release := InputEventKey.new()
	release.keycode = KEY_K
	release.physical_keycode = KEY_K
	release.pressed = false
	Input.parse_input_event(release)
	Input.parse_input_event(press)
	await frames(3)
	Input.parse_input_event(release)
	await frames(2)


func _settle_aim(fishing: Node) -> bool:
	# enter_fishing_view() has a real 0.7-second camera tween. Let the
	# *production* tween finish before testing casting/water composition.
	# Calling _on_fishing_view_ready after eight frames starts AIM while the
	# camera is still changing, and a synthetic landing then freezes an
	# intermediate shot as the water-tracking camera base.
	await create_timer(0.85).timeout
	await frames(2)
	if int(fishing.get("phase")) == FishingController.Phase.ENTER:
		# Only a fallback: on the normal path fishing_view_ready fired already.
		fishing.call("_on_fishing_view_ready")
	if int(fishing.get("phase")) == FishingController.Phase.PREP:
		fishing.call("_on_animation_finished", &"Prep_Fishing")
	await frames(2)
	return int(fishing.get("phase")) == FishingController.Phase.AIM

func _cast_to_water(fishing: Node, zone: Node, prefix: String) -> bool:
	# Exercise the actual K gate / cast phases, not direct phase assignments.
	if int(fishing.get("phase")) != FishingController.Phase.AIM:
		check(false, prefix + ": cast starts from AIM")
		return false
	_action(fishing, &"enter_fishing", true)
	check(int(fishing.get("phase")) == FishingController.Phase.PREP_THROW, prefix + ": K enters preparation")
	_action(fishing, &"enter_fishing", false)
	fishing.call("_on_animation_finished", &"Prep_Throw")
	check(int(fishing.get("phase")) == FishingController.Phase.CHARGE, prefix + ": power stage reached")
	if int(fishing.get("phase")) != FishingController.Phase.CHARGE:
		return false
	fishing.get_node("Power").set("value", 0.55)
	_action(fishing, &"enter_fishing", true)
	check(int(fishing.get("phase")) == FishingController.Phase.CURVE, prefix + ": power confirmed")
	_action(fishing, &"enter_fishing", false)
	_action(fishing, &"enter_fishing", true)
	check(int(fishing.get("phase")) == FishingController.Phase.THROW, prefix + ": K commits throw")
	_action(fishing, &"enter_fishing", false)
	var caster: Node = fishing.get_node("Caster")
	var bait: Node3D = caster.get("active_bait") as Node3D
	var surface: Node3D = zone.get("water_surface") as Node3D
	check(is_instance_valid(bait) and surface != null, prefix + ": active bait and water exist")
	if not is_instance_valid(bait) or surface == null:
		return false
	# Physics collision and sprite completion are the ONLY controlled shortcuts.
	var contact: Variant = _visible_water_contact(fishing, zone)
	check(contact is Vector3, prefix + ": valid lake/river water contact is visible and HUD-free")
	if not (contact is Vector3):
		return false
	bait.set_physics_process(false)
	bait.set("state", BaitController.State.IN_WATER)
	bait.global_position = contact
	caster.call("_on_bait_landed", bait.global_position)
	if int(fishing.get("phase")) == FishingController.Phase.THROW:
		fishing.call("_on_animation_finished", &"Throw")
	check(int(fishing.get("phase")) == FishingController.Phase.IN_WATER, prefix + ": real waterborne lifecycle")
	return int(fishing.get("phase")) == FishingController.Phase.IN_WATER


func _check_shared_weather(clock: Node, weather: Node, rain: Node, environment: Node, condition: StringName, prefix: String) -> void:
	var state: Dictionary = weather.call("get_snapshot") as Dictionary
	var world: Dictionary = environment.call("get_world_snapshot") as Dictionary
	var tags: PackedStringArray = environment.call("get_active_tags") as PackedStringArray
	check(StringName(state.get("condition_id", "")) == condition, prefix + ": clock-derived weather is " + String(condition))
	check(StringName((world.get("weather", {}) as Dictionary).get("condition_id", "")) == condition, prefix + ": gameplay/UI snapshot matches")
	check(tags.has(String(condition)), prefix + ": ecology has active weather tag")
	check(int((world.get("clock", {}) as Dictionary).get("total_minutes", -1)) == int((clock.call("get_snapshot") as Dictionary).get("total_minutes", -2)), prefix + ": world uses same clock")
	check(bool(rain.call("is_raining")) == (condition != &"calm"), prefix + ": precipitation state matches gameplay")
	check(is_equal_approx(float(rain.get("_target_rain_level")), 0.0 if condition == &"calm" else 1.0), prefix + ": rain target matches weather")
	check(is_equal_approx(float(rain.get("_target_storm_level")), 1.0 if condition == &"tempest" else 0.0), prefix + ": storm target matches weather")


func _transition(clock: Node, weather: Node, rain: Node, environment: Node, condition: StringName, prefix: String) -> void:
	check(_set_condition(clock, weather, condition), prefix + ": scheduled weather window found")
	# Wait for the normal rain polling and gameplay signals (not a manual poll).
	await create_timer(0.60).timeout
	_check_shared_weather(clock, weather, rain, environment, condition, prefix)


func _test_location(scene: Node3D, spot_id: String, clock: Node, weather: Node) -> void:
	var prefix: String = spot_id + " / live weather"
	var mode: Node = scene.get_node_or_null("Game/GameMode")
	var fishing: Node = scene.get_node_or_null("Game/Fishing")
	var zone: Node = scene.get_node_or_null("World/FishZone_V2")
	var rain: Node = scene.get_node_or_null("World/FishingRainVFX")
	var wind: Node = scene.get_node_or_null("World/FishingWindVFX")
	var current_vfx: Node = scene.get_node_or_null("World/FishingCurrentVFX")
	var player: CharacterBody3D = scene.get_node_or_null("Player/CharacterBody3D") as CharacterBody3D
	check(mode != null and fishing != null and zone != null and rain != null and player != null, prefix + ": production scene services present")
	check(wind != null and current_vfx != null, prefix + ": approved wind/current modules remain mounted")
	if mode == null or fishing == null or zone == null or rain == null or player == null:
		return
	var environment: Node = fishing.get("fishing_environment_service") as Node
	var current: Node = fishing.get("fishing_current_service") as Node
	var inventory: FishingInventory = fishing.get("fishing_inventory") as FishingInventory
	check(environment != null and current != null and inventory != null, prefix + ": ecology, current and inventory are live")
	if environment == null or current == null or inventory == null:
		return
	check(int(rain.get("weather_mode")) == 0, prefix + ": temporary test mode is Auto")
	_check_shared_weather(clock, weather, rain, environment, &"calm", prefix + " / initial clear")
	check(is_zero_approx(float(rain.get("_rain_level"))), prefix + ": clear scene starts with no visible rain")

	var population: Array = zone.call("get_fish_population") as Array
	check(not population.is_empty(), prefix + ": authored local population exists")
	if population.is_empty():
		return
	var entry: FishSpawnEntry = population[0] as FishSpawnEntry
	check(entry != null and entry.fish != null, prefix + ": valid local fish entry")
	if entry == null or entry.fish == null:
		return
	var species_id: String = String(entry.fish.get_stable_species_id())
	var before: int = inventory.get_fish_count(species_id)
	for id in previous_counts:
		check(inventory.get_fish_count(String(id)) >= int(previous_counts[id]), prefix + ": previous catches survive travel")

	player.global_position = Vector3(0.0, 0.06, -0.16)
	player.rotation.y = PI
	for _i in range(4):
		await physics_frame
		await process_frame
	check(bool(zone.call("can_player_fish", player)), prefix + ": shoreline interaction available")
	await _enter_shoreline()
	check(bool(mode.call("is_fishing")), prefix + ": physical K enters fishing")
	if not bool(mode.call("is_fishing")):
		return
	var aim_ready: bool = await _settle_aim(fishing)
	check(aim_ready, prefix + ": reaches AIM")
	var camera_rig: Node = fishing.get("camera_rig") as Node
	var hud_failures_before: int = int(camera_rig.get("fishing_hud_failures")) if camera_rig != null else 0
	if int(fishing.get("phase")) != FishingController.Phase.AIM:
		mode.call("exit_fishing")
		return
	var session_spot: Variant = current.call("get_spot")
	check(session_spot == zone.call("get_fishing_spot"), prefix + ": current bound to local fishing spot")

	# Calm -> Rain during the cast setup. The precipitation should gradually
	# appear, while the player remains in AIM, not reset the fishing session.
	await _transition(clock, weather, rain, environment, &"rain", prefix + " / AIM clear-to-rain")
	var rain_level: float = float(rain.get("_rain_level"))
	check(rain_level > 0.0 and rain_level < 0.95, prefix + ": transition visibly fades in rather than popping")
	check(int(fishing.get("phase")) == FishingController.Phase.AIM, prefix + ": weather change keeps AIM")
	check(current.call("get_spot") == session_spot, prefix + ": weather change preserves cast current binding")
	if not _cast_to_water(fishing, zone, prefix):
		_release_all(fishing)
		mode.call("exit_fishing")
		return

	# Rain -> Tempest while the lure is waiting. A storm updates game ecology
	# without manufacturing a bite/catch or changing the active bait.
	var caster: Node = fishing.get_node("Caster")
	var active_bait: Variant = caster.get("active_bait")
	await _transition(clock, weather, rain, environment, &"tempest", prefix + " / IN_WATER rain-to-tempest")
	check(int(fishing.get("phase")) == FishingController.Phase.IN_WATER, prefix + ": storm does not cancel waiting lure")
	check(is_instance_valid(active_bait) and caster.get("active_bait") == active_bait, prefix + ": storm preserves active bait")
	check(float(rain.get("_storm_level")) > 0.0 and float(rain.get("_storm_level")) < 0.95, prefix + ": tempest emphasis transitions smoothly")
	check(current.call("get_spot") == session_spot, prefix + ": current remains location-owned in storm")
	check(inventory.get_fish_count(species_id) == before, prefix + ": weather change creates no catch")

	# Real K hook path; only the specific bite-ready cue is controlled.
	var encounter: Node = fishing.get_node("Encounter")
	encounter.get_node("BiteTimer").stop()
	check(bool(encounter.get("lifecycle").open_bite_window()), prefix + ": bite window opens during storm")
	encounter.set("pending_fish_entry", entry)
	encounter.set("bite_active", true)
	encounter.set("bite_hook_ready", false)
	encounter.set("active_bite_timing", {"active": true, "hook_ready": false})
	encounter.call("_set_bite_hook_ready")
	_action(fishing, &"enter_fishing", true)
	check(int(fishing.get("phase")) == FishingController.Phase.FIGHT, prefix + ": player K hooks fish in storm")
	var hooked: FishInstance = encounter.get("active_fish") as FishInstance
	check(hooked != null and hooked.species != null, prefix + ": hooked specimen exists")
	_action(fishing, &"enter_fishing", false)
	if hooked == null or int(fishing.get("phase")) != FishingController.Phase.FIGHT:
		_release_all(fishing)
		mode.call("exit_fishing")
		return

	# Tempest -> Calm WHILE a fish is hooked. Fade-out must not abruptly
	# terminate the fight, change species, or commit an unsolicited catch.
	var before_fade: float = float(rain.get("_rain_level"))
	await _transition(clock, weather, rain, environment, &"calm", prefix + " / FIGHT tempest-to-calm")
	# Don't confuse a clock/poll boundary with a renderer regression. After
	# confirming the target is Clear, give the real VFX process a few frames
	# to advance and require an actual downward change.
	var did_fade: bool = await _wait_for_visible_fade_out(rain, before_fade)
	check(int(fishing.get("phase")) == FishingController.Phase.FIGHT, prefix + ": clear transition keeps the ongoing fight")
	check(encounter.get("active_fish") == hooked, prefix + ": hooked specimen survives weather change")
	check(did_fade, prefix + ": existing rain fades downward (before=%.3f after=%.3f target=%.3f processing=%s paused=%s)" % [
		before_fade, float(rain.get("_rain_level")), float(rain.get("_target_rain_level")),
		str(rain.can_process()), str(paused)])
	check(float(rain.get("_rain_level")) > 0.0, prefix + ": clearing rain does not instantly vanish")
	if camera_rig != null:
		var camera := camera_rig.get_node_or_null("Camera3D") as Camera3D
		var surface_pixel := Vector2.INF
		if camera != null and is_instance_valid(active_bait) and active_bait.has_method("get_surface_position"):
			surface_pixel = camera.unproject_position(active_bait.call("get_surface_position") as Vector3)
		check(int(camera_rig.get("fishing_hud_failures")) == hud_failures_before,
			prefix + ": waterborne bait stays clear of HUD (projected=%s, count=%d, previous=%d, world=%s)" % [
				surface_pixel, int(camera_rig.get("fishing_hud_failures")), hud_failures_before,
				active_bait.global_position if is_instance_valid(active_bait) else Vector3.ZERO
			])
	check(inventory.get_fish_count(species_id) == before, prefix + ": weather does not give free fish")
	check(current.call("get_spot") == session_spot, prefix + ": current still belongs to the active spot")

	# Production bait-return/landing/repository path, as proven in v5/v6.
	caster.call("_on_bait_returned")
	check(int(fishing.get("phase")) == FishingController.Phase.LANDING, prefix + ": legitimate fight enters landing")
	await create_timer(float(fishing.get("catch_landing_hold_time")) + 0.25).timeout
	var result: Dictionary = fishing.call("get_last_outcome_result") as Dictionary
	check(String(result.get("outcome", "")) == "catch" and bool(result.get("applied", false)), prefix + ": catch resolves after changing weather")
	check(bool(result.get("catch_durable", false)), prefix + ": catch is durably committed")
	check(inventory.get_fish_count(species_id) == before + 1, prefix + ": exactly one fish added")
	var catch_result: Dictionary = result.get("catch_result", {}) as Dictionary
	var snapshot: Dictionary = catch_result.get("catch_snapshot", {}) as Dictionary
	check(String(snapshot.get("spot_id", "")) == spot_id, prefix + ": catch attributed to current location")
	previous_counts[species_id] = before + 1

	_release_all(fishing)
	mode.call("exit_fishing")
	await frames(4)
	check(bool(mode.call("is_exploration")), prefix + ": returns to exploration after a weather-shifted catch")
	check(current.call("get_spot") == null, prefix + ": active lure-current spot released")
	check(environment.get("_spot") == null, prefix + ": ecology spot released")
	check(inventory.get_fish_count(species_id) == before + 1, prefix + ": catch persists after session exit")
	# Verify weather can still change when no fishing session is active.
	await _transition(clock, weather, rain, environment, &"rain", prefix + " / exploration weather")
	check(bool(mode.call("is_exploration")), prefix + ": world weather does not force fishing mode")


func _run() -> void:
	await frames(6)
	var locations: Node = root.get_node_or_null("WorldLocations")
	var clock: Node = root.get_node_or_null("GameClock")
	var weather: Node = root.get_node_or_null("GameWeather")
	check(locations != null and clock != null and weather != null, "global location, clock and weather providers exist")
	if locations == null or clock == null or weather == null:
		_finish()
		return
	node_added.connect(_force_auto_rain)
	for spec in CASES:
		var prefix: String = String(spec["spot_id"])
		check(_set_condition(clock, weather, &"calm"), prefix + ": clear window selected before location load")
		var location: Resource = locations.call("get_location", spec["location_id"]) as Resource
		check(location != null, prefix + ": registered location available")
		if location == null:
			continue
		var packed: PackedScene = load(String(location.get("scene_path"))) as PackedScene
		check(packed != null, prefix + ": real location scene loaded")
		if packed == null:
			continue
		var scene: Node3D = packed.instantiate() as Node3D
		check(scene != null, prefix + ": real location scene instantiated")
		if scene == null:
			continue
		root.add_child(scene)
		current_scene = scene
		await frames(8)
		await _test_location(scene, String(spec["spot_id"]), clock, weather)
		current_scene = null
		scene.queue_free()
		await frames(6)
		check(locations.get("current_location") == null, prefix + ": location authority released after travel")
	if node_added.is_connected(_force_auto_rain):
		node_added.disconnect(_force_auto_rain)
	_finish()


func _finish() -> void:
	print("Environmental Integration v7 Live Weather QA: %d passed, %d failed" % [passed, failures.size()])
	for failure in failures:
		print("  FAILED: " + failure)
	quit(0 if failures.is_empty() else 1)
