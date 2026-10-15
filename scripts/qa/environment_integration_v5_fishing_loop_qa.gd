extends SceneTree
const Isolation = preload("res://scripts/qa/qa_save_isolation.gd")
## Environmental Integration v5 — real Lake/River scene, caster, bite, fight,
## landing and durable catch. Save files are redirected to isolated user://.
## This is deterministic backend integration, not a replacement for hands-on
## casting and bite-timing playtesting.

const FishingController = preload("res://scripts/fishing.gd")
const BaitController = preload("res://scripts/bait_V2.gd")

const LOCATIONS = [
    {"location_id": &"lyp_lake_outpost", "spot_id": &"lake_2", "weather": &"rain"},
    {"location_id": &"river_fishing_outpost", "spot_id": &"river_2", "weather": &"tempest"},
]

var passed: int = 0
var failures: Array[String] = []
var previous_catches: Dictionary = {}


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
        push_error("Environmental Integration v5 QA: " + description)


func frames(count: int = 4) -> void:
    for _i in range(count):
        await process_frame


func _minute_for_weather(weather: Node, target: StringName) -> int:
    var interval: int = maxi(int(weather.get("weather_window_minutes")), 60)
    for window in range(1, 200):
        var minute: int = window * interval + 20
        var snapshot: Dictionary = weather.call("get_snapshot_at_minutes", minute) as Dictionary
        if StringName(snapshot.get("condition_id", "")) == target:
            return minute
    return -1


func _set_clock_minute(clock: Node, minute: int) -> bool:
    if minute < 0:
        return false
    var day: int = int(minute / 1440) + 1
    var in_day: int = minute % 1440
    return bool(clock.call("set_clock", day, int(in_day / 60), in_day % 60))


func _force_auto_rain(node: Node) -> void:
    # The user's saved Rain Preview is an artistic preference, not a QA default.
    if node.name == &"FishingRainVFX" and node.has_method("_poll_weather"):
        node.set("weather_mode", 0)
        node.set("enabled", true)


func _press_shoreline_k() -> void:
    var release := InputEventKey.new()
    release.keycode = KEY_K
    release.physical_keycode = KEY_K
    release.pressed = false
    var press := InputEventKey.new()
    press.keycode = KEY_K
    press.physical_keycode = KEY_K
    press.pressed = true
    Input.parse_input_event(release)
    Input.parse_input_event(press)
    await frames(3)
    Input.parse_input_event(release)


func _exercise(scene: Node3D, location: Resource, spec: Dictionary) -> void:
    var spot_id: String = String(spec["spot_id"])
    var title: String = "%s / %s" % [String(location.get("location_id")), spot_id]
    var mode: Node = scene.get_node_or_null("Game/GameMode")
    var fishing: Node = scene.get_node_or_null("Game/Fishing")
    var zone: Node = scene.get_node_or_null("World/FishZone_V2")
    var player: CharacterBody3D = scene.get_node_or_null("Player/CharacterBody3D") as CharacterBody3D
    check(mode != null and fishing != null and zone != null and player != null, title + ": authored player, fishing, zone, mode loaded")
    if mode == null or fishing == null or zone == null or player == null:
        return

    var spot: FishingSpotData = zone.call("get_fishing_spot") as FishingSpotData
    var population: Array = zone.call("get_fish_population") as Array
    check(spot != null and String(spot.spot_id) == spot_id, title + ": spot bound correctly")
    check(not population.is_empty(), title + ": authored population available")
    if spot == null or population.is_empty():
        return

    var entry: FishSpawnEntry = population[0] as FishSpawnEntry
    check(entry != null and entry.fish != null, title + ": authored first fish usable")
    if entry == null or entry.fish == null:
        return
    var species_id: String = String(entry.fish.get_stable_species_id())

    player.global_position = Vector3(0.0, 0.06, -0.16)
    player.rotation.y = PI
    for _i in range(4):
        await physics_frame
        await process_frame
    check(bool(zone.call("can_player_fish", player)), title + ": shoreline K is legal")
    await _press_shoreline_k()
    check(bool(mode.call("is_fishing")) and mode.get("active_fish_zone") == zone, title + ": K enters correct fishing zone")
    if not bool(mode.call("is_fishing")):
        return

    var caster: Node = fishing.get_node_or_null("Caster")
    var encounter: Node = fishing.get_node_or_null("Encounter")
    var loadout: FishingLoadout = fishing.get("loadout") as FishingLoadout
    var inventory: FishingInventory = fishing.get("fishing_inventory") as FishingInventory
    var repository: FishingCatchRepository = fishing.get("fishing_catch_repository") as FishingCatchRepository
    var outcome: RefCounted = fishing.get("outcome_service") as RefCounted
    check(caster != null and encounter != null and loadout != null and inventory != null and repository != null and outcome != null, title + ": production cast, encounter, tackle and catch services ready")
    if caster == null or encounter == null or loadout == null or inventory == null or repository == null or outcome == null:
        mode.call("exit_fishing")
        return
    # The session must preserve catches from the earlier location visit.
    for previous_species in previous_catches:
        check(int(inventory.call("get_fish_count", String(previous_species))) >= int(previous_catches[previous_species]), title + ": earlier location catch retained in shared inventory")
    var lure: BaitData = loadout.get_selected_lure()
    check(lure != null, title + ": equipped lure available")
    if lure == null:
        mode.call("exit_fishing")
        return

    # The existing runtime lifecycle QA uses this same real Caster path.
    # Only the physical flight and timing are controlled: we put the real
    # bait into water deterministically to exercise the whole backend.
    fishing.set("phase", FishingController.Phase.BAIT_FLYING)
    var bait: Node3D = caster.call("perform_cast", 0.5, Vector3.FORWARD, zone.call("get_water_y"), zone.call("get_bottom_y"), lure, zone.call("get_swim_bounds"), zone.call("get_shore_boundary")) as Node3D
    check(is_instance_valid(bait), title + ": real Caster creates a physical bait")
    if not is_instance_valid(bait):
        mode.call("exit_fishing")
        return
    bait.set_physics_process(false)
    bait.set("state", BaitController.State.IN_WATER)
    var surface: Node3D = zone.get("water_surface") as Node3D
    check(surface != null, title + ": authored water surface available")
    if surface == null:
        mode.call("exit_fishing")
        return
    bait.global_position = surface.global_position
    encounter.call("set_active_bait_data", lure)
    caster.call("_on_bait_landed", bait.global_position)
    check(int(fishing.get("phase")) == FishingController.Phase.IN_WATER, title + ": landed bait enters water phase")
    check(bool(caster.call("is_active_bait_in_water")), title + ": caster owns waterborne bait")
    var initial_serial: int = int((outcome.call("get_debug_snapshot") as Dictionary).get("cast_serial", 0))
    check(initial_serial > 0, title + ": landing opened a real outcome session")
    var context: Dictionary = fishing.call("_build_catch_record_context") as Dictionary
    check(String(context.get("spot_id", "")) == spot_id, title + ": catch context uses current location")
    check(String(context.get("lure_id", "")) == String(lure.lure_id), title + ": catch context records equipped lure")

    var before_count: int = int(inventory.call("get_fish_count", species_id))
    # The lifecycle owns bite-window legality; use an explicit deterministic
    # missed opportunity without inventing a selected fish or a catch.
    check(bool(encounter.get("lifecycle").open_bite_window()), title + ": waiting cast opens bite opportunity")
    encounter.set("bite_active", true)
    check(bool(encounter.call("_resolve_bite_miss", &"late_hook")), title + ": missed bite takes production miss path")
    var miss: Dictionary = fishing.call("get_last_outcome_result") as Dictionary
    check(String(miss.get("outcome", "")) == "miss" and not bool(miss.get("terminal", true)), title + ": miss nonterminal, no fake catch")
    check(int(inventory.call("get_fish_count", species_id)) == before_count, title + ": miss leaves fish inventory unchanged")

    # This fish is selected from the *actual* current zone, never from a global
    # fallback. Confirming a hook invokes the real specimen/fight signal chain.
    encounter.get_node("BiteTimer").stop()
    encounter.set("pending_fish_entry", entry)
    check(bool(encounter.call("_confirm_hit")), title + ": production hook creates a fish and fight")
    check(int(fishing.get("phase")) == FishingController.Phase.FIGHT, title + ": fishing enters FIGHT")
    var hooked: FishInstance = encounter.get("active_fish") as FishInstance
    check(hooked != null and hooked.species != null and String(hooked.species.get_stable_species_id()) == species_id, title + ": hooked species belongs to this location")
    if hooked == null or int(fishing.get("phase")) != FishingController.Phase.FIGHT:
        mode.call("exit_fishing")
        return

    # Complete the legitimate hooked return and await the production landing
    # timer. The catch repository, inventory, progression, and rewards run as
    # in normal play; all durable writes stay inside isolated user://.
    caster.call("_on_bait_returned")
    check(int(fishing.get("phase")) == FishingController.Phase.LANDING, title + ": physical return begins LANDING once")
    await create_timer(float(fishing.get("catch_landing_hold_time")) + 0.18).timeout
    check(int(fishing.get("phase")) == FishingController.Phase.CATCH or int(fishing.get("phase")) == FishingController.Phase.WAIT_RESULT, title + ": landing timer produces CATCH presentation")
    var result: Dictionary = fishing.call("get_last_outcome_result") as Dictionary
    check(String(result.get("outcome", "")) == "catch" and bool(result.get("applied", false)), title + ": authoritative outcome is a single catch")
    check(bool(result.get("backend_ok", false)) and bool(result.get("catch_committed", false)), title + ": catch committed through real repository")
    check(bool(result.get("catch_durable", false)), title + ": catch saved durably in isolated storage")
    check(String(result.get("species_id", "")) == species_id, title + ": committed species is correct")
    var record: Dictionary = result.get("catch_result", {}) as Dictionary
    var snapshot: Dictionary = record.get("catch_snapshot", {}) as Dictionary
    check(String(snapshot.get("spot_id", "")) == spot_id, title + ": durable catch snapshot records this spot")
    check(String(snapshot.get("lure_id", "")) == String(lure.lure_id), title + ": durable catch snapshot records this lure")
    check(int(inventory.call("get_fish_count", species_id)) == before_count + 1, title + ": inventory gains exactly one specimen")

    var rejected: Dictionary = outcome.call("resolve_catch", hooked, context, true) as Dictionary
    check(not bool(rejected.get("applied", true)) and bool(rejected.get("duplicate", false)), title + ": duplicate terminal catch rejected")
    check(int(inventory.call("get_fish_count", species_id)) == before_count + 1, title + ": rejected duplicate did not add inventory")
    check(not bool(repository.call("has_pending_transaction")), title + ": no unfinished catch journal after durable commit")

    # Teardown should clear the old zone's physics/ecology, while leaving the
    # shared global services and the just-saved catch accessible next visit.
    mode.call("exit_fishing")
    await frames(4)
    check(bool(mode.call("is_exploration")), title + ": exit returns to exploration")
    var current: Node = fishing.get("fishing_current_service") as Node
    var environment: Node = fishing.get("fishing_environment_service") as Node
    check(current != null and current.call("get_spot") == null, title + ": exit clears old lure current spot")
    check(environment != null and environment.get("_spot") == null, title + ": exit clears old ecology spot")
    check(int(inventory.call("get_fish_count", species_id)) == before_count + 1, title + ": caught specimen survives fishing exit")
    previous_catches[species_id] = before_count + 1
    print("v5 case completed: ", title, " | ", species_id, " | ", result.get("transaction_id", ""))


func _run() -> void:
    await frames(6)
    if not Isolation.verify_root_clock(self):
        quit(1)
        return
    var locations: Node = root.get_node_or_null("WorldLocations")
    var clock: Node = root.get_node_or_null("GameClock")
    var weather: Node = root.get_node_or_null("GameWeather")
    check(locations != null and clock != null and weather != null, "global location/clock/weather services exist")
    if locations == null or clock == null or weather == null:
        _finish()
        return
    node_added.connect(_force_auto_rain)
    var session_identity: int = 0
    for spec in LOCATIONS:
        var location: Resource = locations.call("get_location", spec["location_id"]) as Resource
        check(location != null, "registered location " + String(spec["location_id"]))
        if location == null:
            continue
        var minute: int = _minute_for_weather(weather, StringName(spec["weather"]))
        check(_set_clock_minute(clock, minute), "scheduled weather window for " + String(spec["weather"]))
        if minute < 0:
            continue
        var packed: PackedScene = load(String(location.get("scene_path"))) as PackedScene
        check(packed != null, "authored scene exists for " + String(spec["location_id"]))
        if packed == null:
            continue
        var scene: Node3D = packed.instantiate() as Node3D
        check(scene != null, "authored scene instantiates for " + String(spec["location_id"]))
        if scene == null:
            continue
        root.add_child(scene)
        current_scene = scene
        await frames(7)
        var session: Node = root.get_node_or_null("FishingSessionServices")
        check(session != null, "session services exist for " + String(spec["location_id"]))
        if session != null:
            if session_identity == 0:
                session_identity = session.get_instance_id()
            check(session.get_instance_id() == session_identity, "same persistent fishing session across Lake/River")
        check(locations.get("current_location") == location, "world bound current location " + String(spec["location_id"]))
        check(StringName((weather.call("get_snapshot") as Dictionary).get("condition_id", "")) == spec["weather"], "weather unchanged after location load")
        await _exercise(scene, location, spec)
        current_scene = null
        scene.queue_free()
        await frames(6)
        check(locations.get("current_location") == null, "old location unbound after visit")
    if node_added.is_connected(_force_auto_rain):
        node_added.disconnect(_force_auto_rain)
    _finish()


func _finish() -> void:
    print("Environmental Integration v5 Fishing Loop QA: %d passed, %d failed" % [passed, failures.size()])
    for failure in failures:
        print("  FAILED: " + failure)
    Isolation.emit_result("environment_integration_v5_fishing_loop_qa", passed, passed + failures.size(),
        failures.size(), Node.get_orphan_node_ids().size())
    quit(0 if failures.is_empty() else 1)

func _finalize() -> void:
    print("QA_PROCESS_FINALIZED")
