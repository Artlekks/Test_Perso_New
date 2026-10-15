extends SceneTree
const Isolation = preload("res://scripts/qa/qa_save_isolation.gd")
## Environmental Integration v6: Lake/River cast input, bite timing and recovery.
## Additive QA only. Uses real scene/controller and gameplay action events, while
## deliberately controlling animation completion and bait water contact.
## It does not certify physical casting feel, rendered frames or controller latency.

const BaitController = preload("res://scripts/bait_V2.gd")
const FishingController = preload("res://scripts/fishing.gd")
const CASES = [
    {"location_id": &"lyp_lake_outpost", "spot_id": &"lake_2", "weather": &"rain"},
    {"location_id": &"river_fishing_outpost", "spot_id": &"river_2", "weather": &"tempest"},
]

var passed: int = 0
var failures: Array[String] = []
var previous_species: Dictionary = {}


func _initialize() -> void:
    if not Isolation.verify():
        quit(1)
        return
    _run.call_deferred()


func check(ok: bool, description: String) -> void:
    if ok:
        passed += 1
    else:
        failures.append(description)
        push_error("Environmental Integration v6 QA: " + description)


func frames(count: int = 3) -> void:
    for _i in range(count):
        await process_frame


func _force_auto_rain(node: Node) -> void:
    # Preview settings are valid player preferences, not a QA weather source.
    if node.name == &"FishingRainVFX" and node.has_method("_poll_weather"):
        node.set("weather_mode", 0)
        node.set("enabled", true)


func _minute_for_weather(weather: Node, target: StringName) -> int:
    var window_minutes: int = maxi(int(weather.get("weather_window_minutes")), 60)
    for window in range(1, 200):
        var minute: int = window * window_minutes + 20
        var state: Dictionary = weather.call("get_snapshot_at_minutes", minute) as Dictionary
        if StringName(state.get("condition_id", "")) == target:
            return minute
    return -1


func _set_clock_minute(clock: Node, minute: int) -> bool:
    if minute < 0:
        return false
    var within_day: int = minute % 1440
    return bool(clock.call("set_clock", int(minute / 1440) + 1, int(within_day / 60), within_day % 60))


func _physical_k_for_shoreline() -> void:
    # This is a genuine dispatched key event for the exploration interaction.
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


func _action(fishing: Node, name: StringName, pressed: bool) -> void:
    # Route the actual InputMap action through the fishing controller's real
    # _unhandled_input path. Input.action_* keeps held-button state truthful.
    if pressed:
        Input.action_press(name)
    else:
        Input.action_release(name)
    var event := InputEventAction.new()
    event.action = name
    event.pressed = pressed
    fishing.call("_unhandled_input", event)


func _release_inputs(fishing: Node) -> void:
    for name in [&"enter_fishing", &"cancel_fishing", &"ds_left", &"ds_right", &"move_back", &"move_forward"]:
        _action(fishing, name, false)


func _settle_aim(fishing: Node) -> bool:
    # Only the animation/camera-completion notifications are controlled. Cast
    # stage changes below go through real K actions, never direct stage writes.
    await frames(8)
    if int(fishing.get("phase")) == FishingController.Phase.ENTER:
        fishing.call("_on_fishing_view_ready")
    if int(fishing.get("phase")) == FishingController.Phase.PREP:
        fishing.call("_on_animation_finished", &"Prep_Fishing")
    await frames(2)
    return int(fishing.get("phase")) == FishingController.Phase.AIM


func _cast_with_k(fishing: Node, buffered: bool, prefix: String) -> bool:
    check(int(fishing.get("phase")) == FishingController.Phase.AIM, prefix + ": ready to cast")
    if int(fishing.get("phase")) != FishingController.Phase.AIM:
        return false
    _action(fishing, &"enter_fishing", true)
    check(int(fishing.get("phase")) == FishingController.Phase.PREP_THROW, prefix + ": first K starts PREP_THROW")
    _action(fishing, &"enter_fishing", true)
    check(int(fishing.get("phase")) == FishingController.Phase.PREP_THROW, prefix + ": held K does not skip a stage")
    _action(fishing, &"enter_fishing", false)

    if buffered:
        # A second *fresh* K during Prep_Throw is accepted as a buffered power
        # confirm, even before the sprite's animation-finished notification.
        fishing.get_node("Power").set("value", 0.55)
        _action(fishing, &"enter_fishing", true)
        check(int(fishing.get("phase")) == FishingController.Phase.PREP_THROW, prefix + ": early second K waits for animation")
        _action(fishing, &"enter_fishing", false)
        fishing.call("_on_animation_finished", &"Prep_Throw")
        check(int(fishing.get("phase")) == FishingController.Phase.CURVE, prefix + ": buffered second K reaches CURVE")
    else:
        fishing.call("_on_animation_finished", &"Prep_Throw")
        check(int(fishing.get("phase")) == FishingController.Phase.CHARGE, prefix + ": animation enters CHARGE")
        fishing.get_node("Power").set("value", 0.55)
        _action(fishing, &"enter_fishing", true)
        check(int(fishing.get("phase")) == FishingController.Phase.CURVE, prefix + ": second K locks power and enters CURVE")
        _action(fishing, &"enter_fishing", true)
        check(int(fishing.get("phase")) == FishingController.Phase.CURVE, prefix + ": held K cannot immediately throw")
        _action(fishing, &"enter_fishing", false)

    check(bool(fishing.get("cast_power_locked")), prefix + ": power captured before throw")
    _action(fishing, &"enter_fishing", true)
    var cast_ok: bool = int(fishing.get("phase")) == FishingController.Phase.THROW
    check(cast_ok, prefix + ": fresh K commits cast")
    check(is_instance_valid(fishing.get_node("Caster").get("active_bait")), prefix + ": real Caster owns launched bait")
    _action(fishing, &"enter_fishing", false)
    return cast_ok


func _land_cast(fishing: Node, zone: Node, prefix: String) -> bool:
    var caster: Node = fishing.get_node("Caster")
    var bait: Node3D = caster.get("active_bait") as Node3D
    var surface: Node3D = zone.get("water_surface") as Node3D
    if not is_instance_valid(bait) or surface == null:
        check(false, prefix + ": valid bait and zone water surface")
        return false
    bait.set_physics_process(false)
    bait.set("state", BaitController.State.IN_WATER)
    bait.global_position = surface.global_position
    caster.call("_on_bait_landed", bait.global_position)
    if int(fishing.get("phase")) == FishingController.Phase.THROW:
        fishing.call("_on_animation_finished", &"Throw")
    check(int(fishing.get("phase")) == FishingController.Phase.IN_WATER, prefix + ": controlled contact enters real IN_WATER lifecycle")
    check(bool(caster.call("is_active_bait_in_water")), prefix + ": active lure is in the water")
    return int(fishing.get("phase")) == FishingController.Phase.IN_WATER


func _early_miss_then_cancel(fishing: Node, entry: FishSpawnEntry, species_id: String, prefix: String) -> void:
    var encounter: Node = fishing.get_node("Encounter")
    var inventory: FishingInventory = fishing.get("fishing_inventory") as FishingInventory
    var initial_count: int = int(inventory.get_fish_count(species_id))
    encounter.get_node("BiteTimer").stop()
    check(bool(encounter.get("lifecycle").open_bite_window()), prefix + ": opens a controlled early-hook opportunity")
    encounter.set("pending_fish_entry", entry)
    encounter.set("bite_active", true)
    encounter.set("bite_hook_ready", false)
    encounter.set("active_bite_timing", {"active": true, "hook_ready": false, "early_hook_is_miss": true})
    _action(fishing, &"enter_fishing", true)
    check(int(fishing.get("phase")) == FishingController.Phase.IN_WATER, prefix + ": premature K never starts a fight")
    check(not bool(encounter.get("bite_active")), prefix + ": early hook resolves as miss")
    var miss: Dictionary = fishing.call("get_last_outcome_result") as Dictionary
    check(String(miss.get("outcome", "")) == "miss", prefix + ": missed hook uses real outcome service")
    check(int(inventory.get_fish_count(species_id)) == initial_count, prefix + ": miss earns no fish")
    _action(fishing, &"enter_fishing", false)
    _action(fishing, &"cancel_fishing", true)
    _action(fishing, &"cancel_fishing", false)
    check(int(fishing.get("phase")) == FishingController.Phase.AIM, prefix + ": I abandons unhooked cast to AIM")
    check(not is_instance_valid(fishing.get_node("Caster").get("active_bait")), prefix + ": quick cancel releases lure")
    check(not bool(encounter.get("lifecycle").is_waterborne()), prefix + ": aborted lifecycle is no longer waterborne")
    check(int(inventory.get_fish_count(species_id)) == initial_count, prefix + ": cancel never adds a catch")


func _legit_k_hook_and_land(fishing: Node, entry: FishSpawnEntry, species_id: String, prefix: String) -> void:
    var encounter: Node = fishing.get_node("Encounter")
    var caster: Node = fishing.get_node("Caster")
    var inventory: FishingInventory = fishing.get("fishing_inventory") as FishingInventory
    var before: int = int(inventory.get_fish_count(species_id))
    encounter.get_node("BiteTimer").stop()
    check(bool(encounter.get("lifecycle").open_bite_window()), prefix + ": fresh cast opens bite window")
    encounter.set("pending_fish_entry", entry)
    encounter.set("bite_active", true)
    encounter.set("bite_hook_ready", false)
    encounter.set("active_bite_timing", {"active": true, "hook_ready": false})
    encounter.call("_set_bite_hook_ready")
    check(bool(encounter.get("bite_hook_ready")), prefix + ": authoritative hook-ready cue fired")
    _action(fishing, &"enter_fishing", true)
    check(int(fishing.get("phase")) == FishingController.Phase.FIGHT, prefix + ": K hooks through player-facing input path")
    var fish: FishInstance = encounter.get("active_fish") as FishInstance
    check(fish != null and fish.species != null and String(fish.species.get_stable_species_id()) == species_id, prefix + ": hooked fish comes from authored local population")
    if fish == null or int(fishing.get("phase")) != FishingController.Phase.FIGHT:
        _action(fishing, &"enter_fishing", false)
        return

    # The fight's held reel and steering are sampled from real Input actions.
    Input.action_press(&"ds_left")
    fishing.call("_process", 0.016)
    check(bool(encounter.get("player_reeling")), prefix + ": held K sets fight reeling")
    check(float(encounter.get("player_steering")) < -0.1, prefix + ": A steers left during fight")
    Input.action_release(&"ds_left")
    Input.action_press(&"ds_right")
    fishing.call("_process", 0.016)
    check(float(encounter.get("player_steering")) > 0.1, prefix + ": D reverses fight steering")
    Input.action_release(&"ds_right")
    _action(fishing, &"enter_fishing", false)
    fishing.call("_process", 0.016)
    check(not bool(encounter.get("player_reeling")), prefix + ": releasing K stops fight reeling")

    # The physical flight/fight length remains controlled, as in v5. The
    # landing, reward, catch repository and inventory are production code.
    caster.call("_on_bait_returned")
    check(int(fishing.get("phase")) == FishingController.Phase.LANDING, prefix + ": hooked return begins real landing once")
    await create_timer(float(fishing.get("catch_landing_hold_time")) + 0.22).timeout
    var result: Dictionary = fishing.call("get_last_outcome_result") as Dictionary
    check(String(result.get("outcome", "")) == "catch" and bool(result.get("applied", false)), prefix + ": landed catch actually committed")
    check(bool(result.get("catch_durable", false)), prefix + ": landed catch durable in isolated storage")
    check(int(inventory.get_fish_count(species_id)) == before + 1, prefix + ": hooked catch adds exactly one specimen")
    var catch_result: Dictionary = result.get("catch_result", {}) as Dictionary
    var snapshot: Dictionary = catch_result.get("catch_snapshot", {}) as Dictionary
    check(String(snapshot.get("spot_id", "")) == prefix.get_slice(" / ", 0), prefix + ": catch attribution uses current fishing spot")
    previous_species[species_id] = before + 1


func _exercise(scene: Node3D, spot_id: String) -> void:
    var prefix: String = spot_id + " / input"
    var fishing: Node = scene.get_node_or_null("Game/Fishing")
    var mode: Node = scene.get_node_or_null("Game/GameMode")
    var zone: Node = scene.get_node_or_null("World/FishZone_V2")
    var player: CharacterBody3D = scene.get_node_or_null("Player/CharacterBody3D") as CharacterBody3D
    check(fishing != null and mode != null and zone != null and player != null, prefix + ": real scene/input owners are present")
    if fishing == null or mode == null or zone == null or player == null:
        return
    var population: Array = zone.call("get_fish_population") as Array
    check(not population.is_empty(), prefix + ": authored local fish population available")
    if population.is_empty():
        return
    var entry: FishSpawnEntry = population[0] as FishSpawnEntry
    if entry == null or entry.fish == null:
        check(false, prefix + ": valid local fish entry")
        return
    var species_id: String = String(entry.fish.get_stable_species_id())

    player.global_position = Vector3(0.0, 0.06, -0.16)
    player.rotation.y = PI
    for _i in range(4):
        await physics_frame
        await process_frame
    check(bool(zone.call("can_player_fish", player)), prefix + ": shoreline interaction available")
    await _physical_k_for_shoreline()
    check(bool(mode.call("is_fishing")), prefix + ": dispatched physical K enters fishing")
    if not bool(mode.call("is_fishing")):
        return
    var aim_ready: bool = await _settle_aim(fishing)
    check(aim_ready, prefix + ": fishing prep reaches AIM")
    if int(fishing.get("phase")) != FishingController.Phase.AIM:
        mode.call("exit_fishing")
        return

    var gate: RefCounted = fishing.get("cast_input_gate") as RefCounted
    var gate_state: Dictionary = {}
    if gate != null:
        gate_state = gate.call("get_debug_snapshot") as Dictionary
    check(bool(gate_state.get("ready_for_press", false)), prefix + ": released shoreline K is re-armed on AIM")
    var inventory: FishingInventory = fishing.get("fishing_inventory") as FishingInventory
    check(inventory != null, prefix + ": durable inventory bound")
    if inventory == null:
        mode.call("exit_fishing")
        return
    for previous in previous_species:
        check(int(inventory.get_fish_count(String(previous))) >= int(previous_species[previous]), prefix + ": earlier location catch persists")

    if _cast_with_k(fishing, false, prefix + " / normal cast"):
        if _land_cast(fishing, zone, prefix + " / first water contact"):
            _early_miss_then_cancel(fishing, entry, species_id, prefix)
    _release_inputs(fishing)
    await frames(2)
    if int(fishing.get("phase")) == FishingController.Phase.AIM:
        if _cast_with_k(fishing, true, prefix + " / buffered cast"):
            if _land_cast(fishing, zone, prefix + " / second water contact"):
                await _legit_k_hook_and_land(fishing, entry, species_id, prefix)

    _release_inputs(fishing)
    mode.call("exit_fishing")
    await frames(4)
    check(bool(mode.call("is_exploration")), prefix + ": returns to exploration")
    var environment: Node = fishing.get("fishing_environment_service") as Node
    var current: Node = fishing.get("fishing_current_service") as Node
    check(environment != null and environment.get("_spot") == null, prefix + ": no old ecology spot after exit")
    check(current != null and current.call("get_spot") == null, prefix + ": no old current spot after exit")


func _run() -> void:
    await frames(6)
    if not Isolation.verify_root_clock(self):
        quit(1)
        return
    var locations: Node = root.get_node_or_null("WorldLocations")
    var clock: Node = root.get_node_or_null("GameClock")
    var weather: Node = root.get_node_or_null("GameWeather")
    check(locations != null and clock != null and weather != null, "shared location/time/weather services exist")
    if locations == null or clock == null or weather == null:
        _finish()
        return
    node_added.connect(_force_auto_rain)
    for spec in CASES:
        var location: Resource = locations.call("get_location", spec["location_id"]) as Resource
        check(location != null, "registered location: " + String(spec["location_id"]))
        if location == null:
            continue
        var minute: int = _minute_for_weather(weather, spec["weather"])
        check(_set_clock_minute(clock, minute), "scheduled weather: " + String(spec["weather"]))
        if minute < 0:
            continue
        var packed: PackedScene = load(String(location.get("scene_path"))) as PackedScene
        check(packed != null, "location scene loads: " + String(spec["location_id"]))
        if packed == null:
            continue
        var scene: Node3D = packed.instantiate() as Node3D
        if scene == null:
            check(false, "location scene instantiates: " + String(spec["location_id"]))
            continue
        root.add_child(scene)
        current_scene = scene
        await frames(8)
        check(StringName((weather.call("get_snapshot") as Dictionary).get("condition_id", "")) == spec["weather"], "weather survives location start: " + String(spec["location_id"]))
        await _exercise(scene, String(spec["spot_id"]))
        current_scene = null
        scene.queue_free()
        await frames(6)
        check(locations.get("current_location") == null, "travel unbinds old location: " + String(spec["location_id"]))
    if node_added.is_connected(_force_auto_rain):
        node_added.disconnect(_force_auto_rain)
    _finish()


func _finish() -> void:
    print("Environmental Integration v6 Player Input QA: %d passed, %d failed" % [passed, failures.size()])
    for failure in failures:
        print("  FAILED: " + failure)
    Isolation.emit_result("environment_integration_v6_player_input_qa", passed, passed + failures.size(),
        failures.size(), Node.get_orphan_node_ids().size())
    quit(0 if failures.is_empty() else 1)

func _finalize() -> void:
    print("QA_PROCESS_FINALIZED")
