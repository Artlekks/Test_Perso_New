extends SceneTree
const Isolation = preload("res://scripts/qa/qa_save_isolation.gd")
## Environmental Integration v4 — Lake/River real-scene gameplay handoff.
## No game balance changes. All reads/writes to user:// are isolated to this QA run.
## Required baseline: Environmental Integration v1, v2, v3 + v3 QA repair.

const CASES = [
    {
        "location_id": &"lyp_lake_outpost", "spot_id": &"lake_2",
        "condition": &"rain", "species": ["black_bass", "blue_gill", "piranha"],
    },
    {
        "location_id": &"river_fishing_outpost", "spot_id": &"river_2",
        "condition": &"tempest", "species": ["trout", "rainbow_trout", "salmon"],
    },
    {
        "location_id": &"lyp_lake_outpost", "spot_id": &"lake_2",
        "condition": &"calm", "species": ["black_bass", "blue_gill", "piranha"],
    },
]

var passed: int = 0
var failures: Array[String] = []


func _initialize() -> void:
    if not Isolation.verify():
        quit(1)
        return
    _run.call_deferred()


func check(result: bool, description: String) -> void:
    if result:
        passed += 1
    else:
        failures.append(description)
        push_error("Environmental Integration v4 QA: " + description)


func frames(count: int = 3) -> void:
    for _i in range(count):
        await process_frame


func _force_test_rain_to_auto(node: Node) -> void:
    # Preview modes are valid artist settings. QA forces Auto before _ready,
    # without altering any packed scene/Inspector values on disk.
    if node.name == &"FishingRainVFX" and node.has_method("_poll_weather"):
        node.set("weather_mode", 0)
        node.set("enabled", true)


func _minute_for_weather(weather: Node, target: StringName) -> int:
    var interval: int = maxi(int(weather.get("weather_window_minutes")), 60)
    for window in range(1, 200):
        var minute: int = window * interval + 20
        var state: Dictionary = weather.call("get_snapshot_at_minutes", minute) as Dictionary
        if StringName(state.get("condition_id", "")) == target:
            return minute
    return -1


func _set_minute(clock: Node, minute: int) -> bool:
    if minute < 0:
        return false
    var day: int = int(minute / 1440) + 1
    var in_day: int = minute % 1440
    return bool(clock.call("set_clock", day, int(in_day / 60), in_day % 60))


func _species_ids(population: Array) -> PackedStringArray:
    var ids := PackedStringArray()
    for entry in population:
        if entry == null or entry.fish == null:
            continue
        var id: String = str(entry.fish.get_stable_species_id())
        if not ids.has(id):
            ids.append(id)
    return ids


func _mount_location(path: String) -> Node3D:
    var packed: PackedScene = load(path) as PackedScene
    if packed == null:
        return null
    var scene: Node3D = packed.instantiate() as Node3D
    if scene == null:
        return null
    root.add_child(scene)
    current_scene = scene
    await frames(5)
    return scene


func _unmount_location(scene: Node3D) -> void:
    if is_instance_valid(scene):
        current_scene = null
        scene.queue_free()
        await frames(4)


func _probe_location(scene: Node3D, location: Resource, target_condition: StringName, case_index: int) -> void:
    var prefix: String = "%s (visit %d)" % [str(location.get("location_id")), case_index + 1]
    var locations: Node = root.get_node("WorldLocations")
    var clock: Node = root.get_node("GameClock")
    var wind: Node = root.get_node("GameWind")
    var weather: Node = root.get_node("GameWeather")
    var world: Node = scene.get_node_or_null("World")
    var zone: Node = scene.get_node_or_null("World/FishZone_V2")
    var game_mode: Node = scene.get_node_or_null("Game/GameMode")
    var fishing: Node = scene.get_node_or_null("Game/Fishing")
    var rain: Node = scene.get_node_or_null("World/FishingRainVFX")

    check(locations.get("current_location") == location, prefix + ": location authority bound")
    check(world != null and zone != null and game_mode != null and fishing != null, prefix + ": playable world, zone and mode present")
    check(rain != null and world != null and rain.get_parent() == world, prefix + ": single world-owned rain instance")
    check(scene.get_node_or_null("World/FishingWindVFX") != null and scene.get_node_or_null("World/FishingCurrentVFX") != null, prefix + ": existing wind and current modules mounted")
    if zone == null or game_mode == null or fishing == null or rain == null:
        return

    var expected_spot: FishingSpotData = location.get("fishing_spot") as FishingSpotData
    var zone_spot: FishingSpotData = zone.call("get_fishing_spot") as FishingSpotData
    check(zone_spot == expected_spot and zone_spot != null, prefix + ": zone uses authored spot, not previous location")
    if zone_spot == null:
        return
    check(not bool(zone.get("debug_spot_override")), prefix + ": spot was not installed as developer override")
    var species_ids: PackedStringArray = _species_ids(zone.call("get_fish_population") as Array)
    for id in CASES[case_index]["species"]:
        check(species_ids.has(id), prefix + ": authored population contains " + id)

    var environment: Node = fishing.get("fishing_environment_service") as Node
    var current: Node = fishing.get("fishing_current_service") as Node
    check(environment != null and current != null, prefix + ": shared fishing environment/current services are available")
    if environment == null or current == null:
        return
    var authoritative: Dictionary = weather.call("get_snapshot") as Dictionary
    check(StringName(authoritative.get("condition_id", "")) == target_condition, prefix + ": authoritative weather selected")
    var world_state: Dictionary = environment.call("get_world_snapshot") as Dictionary
    check(StringName((world_state.get("weather", {}) as Dictionary).get("condition_id", "")) == target_condition, prefix + ": exploring shares world weather")
    check((environment.call("get_active_tags") as PackedStringArray).has(String(target_condition)), prefix + ": exploring ecology receives weather tag")
    check(int((world_state.get("clock", {}) as Dictionary).get("total_minutes", -1)) == int((clock.call("get_snapshot") as Dictionary).get("total_minutes", -2)), prefix + ": clock snapshot agrees in exploration")
    check((world_state.get("wind", {}) as Dictionary).get("velocity_xz", Vector2.INF) == (wind.call("get_snapshot") as Dictionary).get("velocity_xz", Vector2.ZERO), prefix + ": wind snapshot agrees in exploration")
    check(current.call("get_spot") == null, prefix + ": lure current not bound during exploration")
    var current_preview: Dictionary = world_state.get("current", {}) as Dictionary
    check(bool(current_preview.get("available", false)), prefix + ": authored current can be previewed without starting fishing")

    rain.call("_poll_weather")
    check(bool(rain.call("is_raining")) == (target_condition != &"calm"), prefix + ": rain follows weather in Auto mode")
    check(bool(game_mode.call("is_exploration")), prefix + ": starts in exploration")
    # Real shoreline interaction, rather than bypassing the input/zone gate.
    # The authored development outpost fishing shoreline is at this point.
    var player: CharacterBody3D = scene.get_node_or_null("Player/CharacterBody3D") as CharacterBody3D
    check(player != null, prefix + ": authored exploration player exists")
    if player == null:
        return
    player.global_position = Vector3(0.0, 0.06, -0.16)
    player.rotation.y = PI
    for _frame in range(4):
        await physics_frame
        await process_frame
    check(bool(zone.call("can_player_fish", player)), prefix + ": shoreline fishing entry is possible")
    var released := InputEventKey.new()
    released.keycode = KEY_K
    released.physical_keycode = KEY_K
    released.pressed = false
    var pressed := InputEventKey.new()
    pressed.keycode = KEY_K
    pressed.physical_keycode = KEY_K
    pressed.pressed = true
    Input.parse_input_event(released)
    Input.parse_input_event(pressed)
    await frames(3)
    Input.parse_input_event(released)
    check(bool(game_mode.call("is_fishing")) and game_mode.get("active_fish_zone") == zone, prefix + ": normal K input entered real fishing zone")
    if not bool(game_mode.call("is_fishing")):
        return
    check(current.call("get_spot") == zone_spot, prefix + ": lure-current uses this location's spot")
    check(current.call("get_swim_bounds") == zone.call("get_swim_bounds"), prefix + ": current uses this zone's swim bounds")
    # Same location, same sample point and same explicit phase: environmental
    # ecology must use the identical current as physical lure drift.
    var water_point: Vector3 = zone.global_position
    var phase_seconds: float = 13.5
    var physical_velocity: Vector3 = current.call("sample_current_velocity", water_point, phase_seconds) as Vector3
    var ecology: Dictionary = environment.call("get_ecology_snapshot", water_point, phase_seconds) as Dictionary
    var ecology_velocity: Vector2 = ecology.get("current_velocity_xz", Vector2.ZERO) as Vector2
    check(ecology_velocity.distance_to(Vector2(physical_velocity.x, physical_velocity.z)) < 0.0001, prefix + ": fish ecology matches physical lure current")
    check(str(ecology.get("current_sample_scope", "")) == "local_lure", prefix + ": current spatial sample has local-lure provenance")
    var context: Dictionary = environment.call("get_selection_context", zone.call("get_fish_population") as Array) as Dictionary
    check(StringName(context.get("spot_id", "")) == zone_spot.spot_id, prefix + ": fish-selection ecology uses correct spot")
    check((context.get("active_environment_tags", PackedStringArray()) as PackedStringArray).has(String(target_condition)), prefix + ": fish selection receives correct weather")
    var multipliers: Dictionary = context.get("species_multipliers", {}) as Dictionary
    for id in CASES[case_index]["species"]:
        check(multipliers.has(id) and float(multipliers.get(id, -1.0)) >= 0.0, prefix + ": fish selection includes " + id)
    var active_snapshot: Dictionary = environment.call("get_world_snapshot") as Dictionary
    check(StringName((active_snapshot.get("weather", {}) as Dictionary).get("condition_id", "")) == target_condition, prefix + ": fishing UI and gameplay use same weather")
    rain.call("_poll_weather")
    check(bool(rain.call("is_raining")) == (target_condition != &"calm"), prefix + ": no rain toggle on entering fishing")
    game_mode.call("exit_fishing")
    await frames(2)
    check(bool(game_mode.call("is_exploration")), prefix + ": returned to exploration")
    check(current.call("get_spot") == null and current.call("get_swim_bounds") == null, prefix + ": lure-current session released on exit")
    check(environment.get("_spot") == null, prefix + ": fish ecology's active spot released on exit")
    var after_exit: Dictionary = environment.call("get_world_snapshot") as Dictionary
    var after_current: Dictionary = after_exit.get("current", {}) as Dictionary
    check(bool(after_current.get("available", false)), prefix + ": read-only current preview still available after fishing exit")


func _run() -> void:
    await frames(6)
    if not Isolation.verify_root_clock(self):
        quit(1)
        return
    var locations: Node = root.get_node_or_null("WorldLocations")
    var clock: Node = root.get_node_or_null("GameClock")
    var weather: Node = root.get_node_or_null("GameWeather")
    var wind: Node = root.get_node_or_null("GameWind")
    check(locations != null and clock != null and weather != null and wind != null, "global clock, wind, weather and locations mounted")
    if locations == null or clock == null or weather == null or wind == null:
        _finish()
        return
    var initial_clock: Node = clock
    var initial_weather: Node = weather
    var initial_wind: Node = wind
    node_added.connect(_force_test_rain_to_auto)
    for i in range(CASES.size()):
        var spec: Dictionary = CASES[i]
        var location: Resource = locations.call("get_location", spec["location_id"]) as Resource
        check(location != null, "registered location " + str(spec["location_id"]))
        if location == null:
            continue
        var target: StringName = StringName(spec["condition"])
        var minute: int = _minute_for_weather(weather, target)
        check(minute >= 0 and _set_minute(clock, minute), "reachable clock window for " + String(target))
        if minute < 0:
            continue
        var expected_weather: Dictionary = weather.call("get_snapshot") as Dictionary
        var expected_wind: Dictionary = wind.call("get_snapshot") as Dictionary
        var scene: Node3D = await _mount_location(str(location.get("scene_path")))
        check(scene != null, "authored scene instantiates for " + str(spec["location_id"]))
        if scene == null:
            continue
        check(root.get_node_or_null("GameClock") == initial_clock and root.get_node_or_null("GameWind") == initial_wind and root.get_node_or_null("GameWeather") == initial_weather, "scene transition retains environment singletons")
        check((weather.call("get_snapshot") as Dictionary).get("condition_id") == expected_weather.get("condition_id"), "world weather survives scene load")
        check((wind.call("get_snapshot") as Dictionary).get("velocity_xz") == expected_wind.get("velocity_xz"), "world wind survives scene load")
        await _probe_location(scene, location, target, i)
        await _unmount_location(scene)
        check(locations.get("current_location") == null, "scene exit unbinds old location")
    if node_added.is_connected(_force_test_rain_to_auto):
        node_added.disconnect(_force_test_rain_to_auto)
    _finish()


func _finish() -> void:
    print("Environmental Integration v4 Lake/River QA: %d passed, %d failed" % [passed, failures.size()])
    for failure in failures:
        print("  FAILED: " + failure)
    Isolation.emit_result("environment_integration_v4_lake_river_qa", passed, passed + failures.size(),
        failures.size(), Node.get_orphan_node_ids().size())
    quit(0 if failures.is_empty() else 1)

func _finalize() -> void:
    print("QA_PROCESS_FINALIZED")
