extends Node

signal environment_changed(snapshot: Dictionary)

const ConditionDefinitionScript = preload(
	"res://scripts/database/fishing_environment_condition_definition.gd"
)
const EnvironmentCatalogScript = preload(
	"res://scripts/fishing_environment_catalog.gd"
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
## stacking_group -> condition resource
var _active_by_group: Dictionary = {}


func configure(catalog: EnvironmentCatalogScript) -> void:
	_catalog = catalog
	reset_to_defaults()


func set_spot(spot: FishingSpotData) -> void:
	_spot = spot
	_emit_changed()


func get_spot() -> FishingSpotData:
	return _spot


func reset_to_defaults() -> void:
	_active_by_group.clear()
	if _catalog != null:
		var defaults: PackedStringArray = _catalog.default_condition_ids
		for raw_id in defaults:
			_activate_without_emit(StringName(str(raw_id)))
	_emit_changed()


func activate_condition(condition_id: StringName) -> bool:
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
	if _active_by_group.is_empty():
		return
	_active_by_group.clear()
	_emit_changed()


func get_active_condition_ids() -> PackedStringArray:
	var result: PackedStringArray = PackedStringArray()
	for raw_condition in _active_by_group.values():
		var condition: ConditionDefinitionScript = raw_condition as ConditionDefinitionScript
		if condition != null:
			result.append(str(condition.condition_id))
	result.sort()
	return result


func get_active_tags() -> PackedStringArray:
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


func get_species_selection_multiplier(fish: FishData) -> float:
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
	return clampf(multiplier, 0.0, MAX_SPECIES_WEIGHT_MULTIPLIER)


func get_selection_context(entries: Array = []) -> Dictionary:
	var species_multipliers: Dictionary = {}
	for raw_entry in entries:
		if raw_entry == null or raw_entry.fish == null:
			continue
		var species_id: String = raw_entry.fish.get_stable_species_id().strip_edges().to_lower()
		species_multipliers[species_id] = get_species_selection_multiplier(raw_entry.fish)
	return {
		"active_condition_ids": get_active_condition_ids(),
		"active_environment_tags": get_active_tags(),
		"species_multipliers": species_multipliers,
		"spot_id": _get_spot_id(),
	}


func get_bite_activity_multiplier(current_depth: float, total_depth: float) -> float:
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
		"bite_activity_multiplier": get_bite_activity_multiplier(current_depth, total_depth),
		"quality_bonus_roll_chance": float(generation.get("environment_quality_bonus_chance", 0.0)),
		"quality_bonus_rolls": int(generation.get("environment_quality_bonus_rolls", 0)),
		"fish_pressure_multiplier": float(fight.get("fish_pressure_multiplier", 1.0)),
	}


func _get_spot_id() -> String:
	if _spot == null:
		return ""
	return str(_spot.get("spot_id"))


func _emit_changed() -> void:
	environment_changed.emit(get_debug_snapshot())
