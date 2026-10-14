extends Node

signal environment_changed(snapshot: Dictionary)

const ConditionDefinitionScript = preload(
	"res://scripts/database/fishing_environment_condition_definition.gd"
)
const EnvironmentCatalogScript = preload(
	"res://scripts/fishing_environment_catalog.gd"
)
const FishingWeatherSensePolicyScript = preload(
	"res://scripts/fishing_weather_sense_policy.gd"
)
const FishingTideSensePolicyScript = preload(
	"res://scripts/fishing_tide_sense_policy.gd"
)
const FishingHabitatPresentationPolicyScript = preload(
	"res://scripts/fishing_habitat_presentation_policy.gd"
)
const FishingEcologyPolicyScript = preload(
	"res://scripts/fishing_ecology_policy.gd"
)

const MAX_BITE_MULTIPLIER: float = 2.50
const MAX_QUALITY_CHANCE: float = 0.50
const MAX_QUALITY_ROLLS: int = 2
const MIN_FIGHT_MULTIPLIER: float = 0.50
const MAX_ASSIST_MULTIPLIER: float = 1.75
const MAX_PRESSURE_MULTIPLIER: float = 1.50
const MAX_SPECIES_WEIGHT_MULTIPLIER: float = 4.0

var _catalog: EnvironmentCatalogScript = null
var _spot: FishingSpotData = null
var _mastery_service: Node = null
var _tide_service: Node = null
var _current_service: Node = null
## stacking_group -> condition resource
var _active_by_group: Dictionary = {}
var _last_synced_clock_minute: int = -1
var _connected_clock: Node = null
var _live_weather_enabled: bool = false
var _weather_source: Node = null
var _weather_manual_override: bool = false
var _weather_connect_retry_seconds: float = 0.0


func _process(delta: float) -> void:
	if not _live_weather_enabled or is_instance_valid(_weather_source):
		return
	_weather_connect_retry_seconds -= maxf(delta, 0.0)
	if _weather_connect_retry_seconds <= 0.0:
		_weather_connect_retry_seconds = 1.0
		_bind_world_weather()


func _exit_tree() -> void:
	_disconnect_weather_source()


## Opt-in ONLY for the actual fishing session. Detached QA fixtures and
## authored/manual condition editing retain their original semantics.
func enable_live_weather(enabled: bool = true) -> void:
	_live_weather_enabled = enabled
	if not enabled:
		_disconnect_weather_source()
		set_process(false)
		return
	set_process(true)
	_bind_world_weather()


func _bind_world_weather() -> void:
	if not _live_weather_enabled:
		return
	var weather: Node = _get_global_environment_node("GameWeather")
	if weather != null and weather.has_method("get_snapshot"):
		set_weather_source(weather)


func set_weather_source(source: Node) -> void:
	# Explicit injection supports isolated tests and alternate world providers.
	if _weather_source != source:
		_weather_manual_override = false
		_disconnect_weather_source()
		_weather_source = source
	if not is_instance_valid(_weather_source):
		return
	var callback: Callable = Callable(self, "_on_world_weather_changed")
	if _weather_source.has_signal("weather_changed") and not _weather_source.is_connected("weather_changed", callback):
		_weather_source.connect("weather_changed", callback)
	if _sync_weather_condition_from_source():
		_emit_changed()


func _disconnect_weather_source() -> void:
	if is_instance_valid(_weather_source):
		var callback: Callable = Callable(self, "_on_world_weather_changed")
		if _weather_source.has_signal("weather_changed") and _weather_source.is_connected("weather_changed", callback):
			_weather_source.disconnect("weather_changed", callback)
	_weather_source = null


func _on_world_weather_changed(_snapshot: Dictionary) -> void:
	# A developer's manual condition preview lasts until the next weather
	# window; it must not accidentally become a permanent world override.
	_weather_manual_override = false
	if _sync_weather_condition_from_source():
		_emit_changed()


func _sync_weather_condition_from_source() -> bool:
	if _weather_manual_override or _catalog == null or not is_instance_valid(_weather_source):
		return false
	if not _weather_source.has_method("get_snapshot"):
		return false
	var weather: Dictionary = _weather_source.call("get_snapshot") as Dictionary
	if not bool(weather.get("available", false)):
		return false
	var condition_id: StringName = StringName(weather.get("condition_id", ""))
	var authored: ConditionDefinitionScript = _catalog.get_condition_by_id(condition_id)
	if authored == null or authored.stacking_group != &"weather":
		return false
	if _active_by_group.get("weather") == authored:
		return false
	_active_by_group["weather"] = authored
	return true


## Read-only state for UI, VFX and external environment consumers.
## All physical ecology, lure drift and fish modifiers remain in their
## existing services; nothing here applies another weather multiplier.
func get_world_snapshot() -> Dictionary:
	_sync_weather_condition_from_source()
	_sync_time_condition_from_clock()
	var clock_state: Dictionary = {}
	var wind_state: Dictionary = {}
	var weather_state: Dictionary = {}
	var tide_state: Dictionary = {}
	var clock: Node = _get_global_environment_node("GameClock")
	var wind: Node = _get_global_environment_node("GameWind")
	if clock != null and clock.has_method("get_snapshot"):
		clock_state = clock.call("get_snapshot") as Dictionary
	if wind != null and wind.has_method("get_snapshot"):
		wind_state = wind.call("get_snapshot") as Dictionary
	if is_instance_valid(_weather_source) and _weather_source.has_method("get_snapshot"):
		weather_state = _weather_source.call("get_snapshot") as Dictionary
	if is_instance_valid(_tide_service) and _tide_service.has_method("get_snapshot"):
		tide_state = _tide_service.call("get_snapshot") as Dictionary
	var active_weather: ConditionDefinitionScript = _active_by_group.get("weather", null) as ConditionDefinitionScript
	if active_weather != null:
		weather_state["condition_id"] = active_weather.condition_id
		weather_state["display"] = active_weather.display_name
	# Preview the authored location while the player is exploring. Do NOT call
	# set_spot(): changing it would mutate lure physics and active encounters.
	var current_state: Dictionary = {"available": false}
	var current_spot: FishingSpotData = _spot
	if current_spot == null:
		var locations: Node = _get_global_environment_node("WorldLocations")
		if locations != null:
			var location: Variant = locations.get("current_location")
			if location != null:
				current_spot = location.get("fishing_spot") as FishingSpotData
	if is_instance_valid(_current_service) and current_spot != null:
		if _current_service.has_method("sample_spot_at_uv"):
			var velocity: Vector2 = _current_service.call(
				"sample_spot_at_uv", current_spot, Vector2(0.5, 0.5)
			)
			current_state = {
				"available": true,
				"velocity_xz": velocity,
				"speed_mps": velocity.length(),
				"scope": "spot_center",
			}
	return {
		"clock": clock_state,
		"wind": wind_state,
		"weather": weather_state,
		"tide": tide_state,
		"current": current_state,
		"active_condition_ids": get_active_condition_ids(),
		"active_tags": get_active_tags(),
		"spot_id": _get_spot_id(),
	}


func _sync_time_condition_from_clock() -> bool:
	# If GameClock is unavailable (e.g. isolated QA), authored/manual conditions
	# retain their existing behavior. Never manufacture a time state.
	if _catalog == null:
		return false
	var clock: Node = _get_global_environment_node("GameClock")
	if clock == null or not clock.has_method("get_snapshot"):
		return false
	if _connected_clock != clock:
		var callback: Callable = Callable(self, "_on_game_clock_changed")
		if is_instance_valid(_connected_clock) and _connected_clock.is_connected("clock_changed", callback):
			_connected_clock.disconnect("clock_changed", callback)
		_connected_clock = clock
		if clock.has_signal("clock_changed") and not clock.is_connected("clock_changed", callback):
			clock.connect("clock_changed", callback)
		_last_synced_clock_minute = -1
	var snapshot: Dictionary = clock.call("get_snapshot") as Dictionary
	if not snapshot.has("total_minutes"):
		return false
	var minute: int = int(snapshot.get("total_minutes", 0))
	if minute == _last_synced_clock_minute:
		return false
	_last_synced_clock_minute = minute
	var hour: int = floori(float(posmod(minute, 1440)) / 60.0)
	var wanted: StringName = &""
	if hour >= 20 or hour < 5:
		wanted = &"night"
	elif hour < 8:
		wanted = &"dawn"
	var previous: ConditionDefinitionScript = _active_by_group.get("time", null) as ConditionDefinitionScript
	if wanted == &"" and previous == null:
		return false
	if previous != null and previous.condition_id == wanted:
		return false
	_active_by_group.erase("time")
	if wanted != &"":
		var authored: ConditionDefinitionScript = _catalog.get_condition_by_id(wanted)
		if authored != null:
			_active_by_group["time"] = authored
	return true


func _on_game_clock_changed(_snapshot: Dictionary) -> void:
	if _sync_time_condition_from_clock():
		_emit_changed()


func configure(catalog: EnvironmentCatalogScript) -> void:
	_catalog = catalog
	reset_to_defaults()
	_sync_weather_condition_from_source()


func set_spot(spot: FishingSpotData) -> void:
	_spot = spot
	if _tide_service != null and _tide_service.has_method("set_spot"):
		_tide_service.call("set_spot", spot)
	_emit_changed()


func set_tide_service(service: Node) -> void:
	var callback := Callable(self, "_on_tide_changed")
	if (
		_tide_service != null
		and _tide_service.has_signal("tide_changed")
		and _tide_service.is_connected("tide_changed", callback)
	):
		_tide_service.disconnect("tide_changed", callback)

	_tide_service = service
	if (
		_tide_service != null
		and _tide_service.has_signal("tide_changed")
		and not _tide_service.is_connected("tide_changed", callback)
	):
		_tide_service.connect("tide_changed", callback)
	if _tide_service != null and _tide_service.has_method("set_spot"):
		_tide_service.call("set_spot", _spot)
	_emit_changed()


func set_current_service(service: Node) -> void:
	# The existing fishing-current service is the ONLY source of water velocity.
	# Do not independently combine tide/wind here and count flow twice.
	_current_service = service


## Optional lure position uses the existing current service's spatial map.
## Null remains the original center-of-spot behavior for every old caller.
## At runtime (-1), sample the same live current phase as physical lure drift.
## Explicit time_seconds is for deterministic previews and regression tests.
func get_ecology_snapshot(
	world_position: Variant = null,
	time_seconds: float = -1.0
) -> Dictionary:
	var clock_state: Dictionary = {}
	var wind_state: Dictionary = {}
	var tide_state: Dictionary = {}
	var sampled_current: Vector2 = Vector2.ZERO
	# FishingSessionServices can request ecology before this Node has been
	# attached to the active SceneTree. Absolute get_node() calls on a detached
	# Node emit engine errors even when the global service actually exists.
	var clock: Node = _get_global_environment_node("GameClock")
	if clock != null and clock.has_method("get_snapshot"):
		clock_state = clock.call("get_snapshot") as Dictionary
	var wind: Node = _get_global_environment_node("GameWind")
	if wind != null and wind.has_method("get_snapshot"):
		wind_state = wind.call("get_snapshot") as Dictionary
	if _tide_service != null and _tide_service.has_method("get_snapshot"):
		tide_state = _tide_service.call("get_snapshot") as Dictionary
	if _current_service != null and _spot != null:
		if typeof(world_position) == TYPE_VECTOR3 and _current_service.has_method("sample_current_velocity"):
			# Use the current service's live phase (or caller-supplied test phase).
			# No independent gust or wind is added here.
			var local_velocity: Variant = _current_service.call(
				"sample_current_velocity", world_position, time_seconds
			)
			if typeof(local_velocity) == TYPE_VECTOR3:
				sampled_current = Vector2(local_velocity.x, local_velocity.z)
		elif _current_service.has_method("sample_current_at_uv"):
			var sample: Variant = _current_service.call(
				"sample_current_at_uv", Vector2(0.5, 0.5), time_seconds
			)
			if typeof(sample) == TYPE_VECTOR2:
				sampled_current = sample
	var ecology: Dictionary = FishingEcologyPolicyScript.build_snapshot(
		clock_state, wind_state, tide_state, sampled_current, get_active_tags(), _get_spot_id()
	)
	ecology["current_available"] = _spot != null and is_instance_valid(_current_service)
	ecology["current_sample_scope"] = "local_lure" if typeof(world_position) == TYPE_VECTOR3 else "spot_center"
	return ecology


## Environmental lure feedback is independent of baseline input cadence.
## This single read-only service is used by encounter bite rolls; no movement,
## camera, casting power or weather/tide state is written here.
func get_lure_environment_presentation_snapshot(
	bait: BaitData,
	lure_position: Vector3,
	rod_position: Vector3,
	presentation: Dictionary,
	current_depth: float,
	total_depth: float,
	time_seconds: float = -1.0
) -> Dictionary:
	if bait == null:
		return {"multiplier": 1.0, "available": false, "label": "NEUTRAL"}
	var action: LureActionProfile = bait.get_action_profile()
	return FishingHabitatPresentationPolicyScript.evaluate(
		action, presentation, get_ecology_snapshot(lure_position, time_seconds),
		lure_position, rod_position, current_depth, total_depth
	)


func _get_global_environment_node(service_name: String) -> Node:
	# The SceneTree is available even if this service has not been added to
	# the tree yet. Resolve from its root, not from the detached instance.
	var scene_tree: SceneTree = Engine.get_main_loop() as SceneTree
	if scene_tree == null or scene_tree.root == null:
		return null
	return scene_tree.root.get_node_or_null(NodePath(service_name))


func set_mastery_service(service: Node) -> void:
	var old_callback := Callable(self, "_on_mastery_changed")
	if (
		_mastery_service != null
		and _mastery_service.has_signal("mastery_changed")
		and _mastery_service.is_connected("mastery_changed", old_callback)
	):
		_mastery_service.disconnect("mastery_changed", old_callback)

	_mastery_service = service
	if (
		_mastery_service != null
		and _mastery_service.has_signal("mastery_changed")
		and not _mastery_service.is_connected("mastery_changed", old_callback)
	):
		_mastery_service.connect("mastery_changed", old_callback)

	_emit_changed()


func has_weather_sense() -> bool:
	return (
		_mastery_service != null
		and _mastery_service.has_method("has_capability")
		and bool(_mastery_service.call("has_capability", &"weather_sense"))
	)


func has_tide_sense() -> bool:
	return (
		_mastery_service != null
		and _mastery_service.has_method("has_capability")
		and bool(_mastery_service.call("has_capability", &"tide_sense"))
	)


func get_spot() -> FishingSpotData:
	return _spot


func reset_to_defaults() -> void:
	_weather_manual_override = false
	_active_by_group.clear()
	if _catalog != null:
		var defaults: PackedStringArray = _catalog.default_condition_ids
		for raw_id in defaults:
			_activate_without_emit(StringName(str(raw_id)))
	_emit_changed()


func activate_condition(condition_id: StringName) -> bool:
	# Direct weather activation is an explicit debug/preview choice. Keep it
	# until the authoritative world provider reports its next change.
	if is_instance_valid(_weather_source) and _catalog != null:
		var selected: ConditionDefinitionScript = _catalog.get_condition_by_id(condition_id)
		if selected != null and selected.stacking_group == &"weather":
			_weather_manual_override = true
	var changed: bool = _activate_without_emit(condition_id)
	if changed:
		_emit_changed()
	return changed


func _activate_without_emit(condition_id: StringName) -> bool:
	if _catalog == null or condition_id == &"":
		return false
	var condition: ConditionDefinitionScript = _catalog.get_condition_by_id(condition_id)
	if condition == null:
		return false
	var group_key: String = str(condition.stacking_group).strip_edges().to_lower()
	if group_key.is_empty():
		return false
	var previous: ConditionDefinitionScript = _active_by_group.get(group_key, null) as ConditionDefinitionScript
	if previous == condition:
		return false
	_active_by_group[group_key] = condition
	return true


func deactivate_condition(condition_id: StringName) -> bool:
	var key: String = str(condition_id).strip_edges().to_lower()
	if key.is_empty():
		return false
	for raw_group in _active_by_group.keys():
		var condition: ConditionDefinitionScript = _active_by_group[raw_group] as ConditionDefinitionScript
		if condition == null:
			continue
		if str(condition.condition_id).strip_edges().to_lower() != key:
			continue
		var removed_group: String = str(raw_group)
		_active_by_group.erase(raw_group)
		_restore_default_for_group(removed_group)
		_emit_changed()
		return true
	return false


func _restore_default_for_group(group_key: String) -> void:
	if _catalog == null or group_key.is_empty():
		return
	for raw_default in _catalog.default_condition_ids:
		var condition: ConditionDefinitionScript = _catalog.get_condition_by_id(
			StringName(str(raw_default))
		)
		if condition == null:
			continue
		if str(condition.stacking_group).strip_edges().to_lower() != group_key:
			continue
		_active_by_group[group_key] = condition
		return


func clear_conditions() -> void:
	_weather_manual_override = false
	if _active_by_group.is_empty():
		return
	_active_by_group.clear()
	_emit_changed()


func get_active_condition_ids() -> PackedStringArray:
	_sync_weather_condition_from_source()
	_sync_time_condition_from_clock()
	var result: PackedStringArray = PackedStringArray()
	for raw_condition in _active_by_group.values():
		var condition: ConditionDefinitionScript = raw_condition as ConditionDefinitionScript
		if condition != null:
			result.append(str(condition.condition_id))
	result.sort()
	return result


func get_active_tags() -> PackedStringArray:
	_sync_weather_condition_from_source()
	_sync_time_condition_from_clock()
	var result: PackedStringArray = PackedStringArray()
	for raw_condition in _active_by_group.values():
		var condition: ConditionDefinitionScript = raw_condition as ConditionDefinitionScript
		if condition == null:
			continue
		for raw_tag in condition.tags:
			var tag: String = str(raw_tag).strip_edges().to_lower()
			if not tag.is_empty() and not result.has(tag):
				result.append(tag)
	result.sort()
	return result


func get_active_condition_display_names() -> PackedStringArray:
	_sync_weather_condition_from_source()
	_sync_time_condition_from_clock()
	var result := PackedStringArray()
	for raw_condition in _active_by_group.values():
		var condition: ConditionDefinitionScript = raw_condition as ConditionDefinitionScript
		if condition == null:
			continue
		var display_name := condition.display_name.strip_edges()
		if display_name.is_empty():
			display_name = str(condition.condition_id)
		result.append(display_name)
	result.sort()
	return result


func get_depth_activity_profile() -> Dictionary:
	_sync_time_condition_from_clock()
	var profile := _get_weather_depth_activity_profile()
	var tide_profile := _get_tide_depth_activity_profile()
	return {
		"surface": float(profile.get("surface", 1.0)) * float(tide_profile.get("surface", 1.0)),
		"mid": float(profile.get("mid", 1.0)) * float(tide_profile.get("mid", 1.0)),
		"deep": float(profile.get("deep", 1.0)) * float(tide_profile.get("deep", 1.0)),
	}


func _get_weather_depth_activity_profile() -> Dictionary:
	var surface := 1.0
	var mid := 1.0
	var deep := 1.0
	for raw_condition in _active_by_group.values():
		var condition: ConditionDefinitionScript = raw_condition as ConditionDefinitionScript
		if condition == null:
			continue
		surface *= maxf(float(condition.surface_activity_multiplier), 0.01)
		mid *= maxf(float(condition.mid_activity_multiplier), 0.01)
		deep *= maxf(float(condition.deep_activity_multiplier), 0.01)
	return {
		"surface": surface,
		"mid": mid,
		"deep": deep,
	}


func _get_tide_depth_activity_profile() -> Dictionary:
	if _tide_service == null or not _tide_service.has_method("get_depth_activity_profile"):
		return {"surface": 1.0, "mid": 1.0, "deep": 1.0}
	return _tide_service.call("get_depth_activity_profile") as Dictionary


func get_tier_activity_profile() -> PackedFloat32Array:
	_sync_time_condition_from_clock()
	var result := PackedFloat32Array([1.0, 1.0, 1.0, 1.0, 1.0])
	for raw_condition in _active_by_group.values():
		var condition: ConditionDefinitionScript = raw_condition as ConditionDefinitionScript
		if condition == null:
			continue
		for index in range(5):
			result[index] *= condition.get_tier_selection_multiplier(index + 1)
	return result


func get_weather_sense_snapshot(
	current_depth: float = 0.0,
	total_depth: float = 1.0
) -> Dictionary:
	var condition_ids := get_active_condition_ids()
	var condition_names := get_active_condition_display_names()
	if not has_weather_sense():
		return {
			"available": false,
			"reason": "weather_sense_not_learned",
			# Weather itself is visible to the player; the technique gates the fishing
			# interpretation, not the existence/name of the current conditions.
			"condition_ids": condition_ids,
			"condition_names": condition_names,
		}

	var depth_profile := _get_weather_depth_activity_profile()
	var generation := get_specimen_generation_context()
	var fight := get_fight_modifiers()
	return FishingWeatherSensePolicyScript.build_read_snapshot(
		condition_ids,
		condition_names,
		_get_weather_bite_activity_multiplier(current_depth, total_depth),
		float(depth_profile.get("surface", 1.0)),
		float(depth_profile.get("mid", 1.0)),
		float(depth_profile.get("deep", 1.0)),
		float(generation.get("environment_quality_bonus_chance", 0.0)),
		int(generation.get("environment_quality_bonus_rolls", 0)),
		float(fight.get("fish_pressure_multiplier", 1.0)),
		float(fight.get("line_tolerance_multiplier", 1.0)),
		float(fight.get("hook_off_delay_multiplier", 1.0)),
		float(fight.get("counter_steer_multiplier", 1.0)),
		get_tier_activity_profile()
	)


func get_tide_sense_snapshot() -> Dictionary:
	if _tide_service == null or not _tide_service.has_method("get_snapshot"):
		return {
			"available": false,
			"reason": "tide_service_unavailable",
		}

	var tide_snapshot := _tide_service.call("get_snapshot") as Dictionary
	if not bool(tide_snapshot.get("active", false)):
		return {
			"available": false,
			"reason": "tide_not_applicable",
			"active": false,
		}
	if not has_tide_sense():
		return {
			"available": false,
			"reason": "tide_sense_not_learned",
			"active": true,
		}
	return FishingTideSensePolicyScript.build_read_snapshot(tide_snapshot)


func get_species_selection_multiplier(fish: FishData, ecology_snapshot: Dictionary = {}) -> float:
	_sync_time_condition_from_clock()
	if fish == null:
		return 0.0
	var species_id: String = fish.get_stable_species_id().strip_edges().to_lower()
	var tier: int = 1
	if fish.behavior_profile != null:
		tier = clampi(int(fish.behavior_profile.difficulty_tier), 1, 5)
	var multiplier: float = 1.0
	for raw_condition in _active_by_group.values():
		var condition: ConditionDefinitionScript = raw_condition as ConditionDefinitionScript
		if condition == null:
			continue
		if condition.is_species_blocked(species_id):
			return 0.0
		multiplier *= condition.get_tier_selection_multiplier(tier)
		multiplier *= condition.get_species_selection_multiplier(species_id)
	if _tide_service != null and _tide_service.has_method("get_species_selection_multiplier"):
		multiplier *= maxf(
			float(_tide_service.call("get_species_selection_multiplier", fish)),
			0.0
		)
	# Opt-in ecology refines a species' own opportunity, without introducing
	# another universal rain/storm bite or quality multiplier.
	multiplier *= FishingEcologyPolicyScript.species_activity_multiplier(
		fish, ecology_snapshot if not ecology_snapshot.is_empty() else get_ecology_snapshot()
	)
	return clampf(multiplier, 0.0, MAX_SPECIES_WEIGHT_MULTIPLIER)


func get_selection_context(
	entries: Array = [],
	world_position: Variant = null,
	time_seconds: float = -1.0
) -> Dictionary:
	var species_multipliers: Dictionary = {}
	var ecology: Dictionary = get_ecology_snapshot(world_position, time_seconds)
	for raw_entry in entries:
		if raw_entry == null or raw_entry.fish == null:
			continue
		var species_id: String = raw_entry.fish.get_stable_species_id().strip_edges().to_lower()
		species_multipliers[species_id] = get_species_selection_multiplier(raw_entry.fish, ecology)
	var tide_snapshot: Dictionary = {}
	if _tide_service != null and _tide_service.has_method("get_snapshot"):
		tide_snapshot = _tide_service.call("get_snapshot") as Dictionary
	return {
		"active_condition_ids": get_active_condition_ids(),
		"active_environment_tags": get_active_tags(),
		"ecology_current_sample_scope": ecology.get("current_sample_scope", "spot_center"),
		"species_multipliers": species_multipliers,
		"spot_id": _get_spot_id(),
		"tide_phase_id": tide_snapshot.get("phase_id", &"none"),
		"tide_zone_multipliers": tide_snapshot.get("zone_multipliers", {}).duplicate(true) if tide_snapshot.has("zone_multipliers") else {},
	}


func get_bite_activity_multiplier(current_depth: float, total_depth: float) -> float:
	_sync_time_condition_from_clock()
	var depth_ratio: float = 0.5
	if total_depth > 0.0:
		depth_ratio = clampf(current_depth / total_depth, 0.0, 1.0)
	var multiplier := _get_weather_bite_activity_multiplier(current_depth, total_depth)
	if _tide_service != null and _tide_service.has_method("get_bite_activity_multiplier"):
		multiplier *= maxf(
			float(_tide_service.call("get_bite_activity_multiplier", depth_ratio)),
			0.01
		)
	return clampf(multiplier, 0.25, MAX_BITE_MULTIPLIER)


func _get_weather_bite_activity_multiplier(current_depth: float, total_depth: float) -> float:
	var depth_ratio: float = 0.5
	if total_depth > 0.0:
		depth_ratio = clampf(current_depth / total_depth, 0.0, 1.0)
	var multiplier: float = 1.0
	for raw_condition in _active_by_group.values():
		var condition: ConditionDefinitionScript = raw_condition as ConditionDefinitionScript
		if condition == null:
			continue
		multiplier *= maxf(float(condition.bite_activity_multiplier), 0.01)
		multiplier *= maxf(float(condition.get_depth_activity_multiplier(depth_ratio)), 0.01)
	return clampf(multiplier, 0.25, MAX_BITE_MULTIPLIER)


func get_specimen_generation_context() -> Dictionary:
	_sync_time_condition_from_clock()
	var chance: float = 0.0
	var rolls: int = 0
	for raw_condition in _active_by_group.values():
		var condition: ConditionDefinitionScript = raw_condition as ConditionDefinitionScript
		if condition == null:
			continue
		chance += maxf(float(condition.quality_bonus_roll_chance), 0.0)
		rolls += maxi(int(condition.quality_bonus_rolls), 0)
	chance = clampf(chance, 0.0, MAX_QUALITY_CHANCE)
	rolls = clampi(rolls, 0, MAX_QUALITY_ROLLS)
	return {
		"environment_quality_active": chance > 0.0 and rolls > 0,
		"environment_quality_bonus_chance": chance,
		"environment_quality_bonus_rolls": rolls,
		"environment_condition_ids": get_active_condition_ids(),
	}


func get_fight_modifiers() -> Dictionary:
	_sync_time_condition_from_clock()
	var stamina_drain: float = 1.0
	var hook_delay: float = 1.0
	var line_tolerance: float = 1.0
	var counter_steer: float = 1.0
	var fish_pressure: float = 1.0
	for raw_condition in _active_by_group.values():
		var condition: ConditionDefinitionScript = raw_condition as ConditionDefinitionScript
		if condition == null:
			continue
		stamina_drain *= maxf(float(condition.stamina_drain_multiplier), 0.01)
		hook_delay *= maxf(float(condition.hook_off_delay_multiplier), 0.01)
		line_tolerance *= maxf(float(condition.line_tolerance_multiplier), 0.01)
		counter_steer *= maxf(float(condition.counter_steer_multiplier), 0.01)
		fish_pressure *= maxf(float(condition.fish_pressure_multiplier), 0.01)
	return {
		"stamina_drain_multiplier": clampf(stamina_drain, MIN_FIGHT_MULTIPLIER, MAX_ASSIST_MULTIPLIER),
		"hook_off_delay_multiplier": clampf(hook_delay, MIN_FIGHT_MULTIPLIER, MAX_ASSIST_MULTIPLIER),
		"line_tolerance_multiplier": clampf(line_tolerance, MIN_FIGHT_MULTIPLIER, MAX_ASSIST_MULTIPLIER),
		"counter_steer_multiplier": clampf(counter_steer, MIN_FIGHT_MULTIPLIER, MAX_ASSIST_MULTIPLIER),
		"fish_pressure_multiplier": clampf(fish_pressure, MIN_FIGHT_MULTIPLIER, MAX_PRESSURE_MULTIPLIER),
		"environment_condition_ids": get_active_condition_ids(),
	}


func get_debug_snapshot(current_depth: float = 0.0, total_depth: float = 1.0) -> Dictionary:
	var generation: Dictionary = get_specimen_generation_context()
	var fight: Dictionary = get_fight_modifiers()
	return {
		"spot_id": _get_spot_id(),
		"active_condition_ids": get_active_condition_ids(),
		"active_tags": get_active_tags(),
		"ecology": get_ecology_snapshot(),
		"bite_activity_multiplier": get_bite_activity_multiplier(current_depth, total_depth),
		"quality_bonus_roll_chance": float(generation.get("environment_quality_bonus_chance", 0.0)),
		"quality_bonus_rolls": int(generation.get("environment_quality_bonus_rolls", 0)),
		"fish_pressure_multiplier": float(fight.get("fish_pressure_multiplier", 1.0)),
		"weather_sense": get_weather_sense_snapshot(current_depth, total_depth),
		"tide_sense": get_tide_sense_snapshot(),
		"tide": _tide_service.call("get_snapshot") if _tide_service != null and _tide_service.has_method("get_snapshot") else {},
	}


func _get_spot_id() -> String:
	if _spot == null:
		return ""
	return str(_spot.get("spot_id"))


func _on_mastery_changed(_snapshot: Dictionary) -> void:
	# Weather/Tide Sense change only what the player can read.
	_emit_changed()


func _on_tide_changed(_snapshot: Dictionary) -> void:
	# Tide itself changes fishing math independently of mastery. Reuse the
	# environment signal so concentration fields and future presentation refresh.
	_emit_changed()


func _emit_changed() -> void:
	environment_changed.emit(get_debug_snapshot())
