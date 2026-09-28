extends Node

signal modifiers_changed(snapshot: Dictionary)
signal modifier_applied(effect_id: StringName, source_kind: StringName, source_id: String)
signal modifier_expired(effect_id: StringName)

const ModifierDefinitionScript = preload(
	"res://scripts/database/fishing_session_modifier_definition.gd"
)

const MIN_MULTIPLIER: float = 0.50
const MAX_ASSIST_MULTIPLIER: float = 1.75
const MAX_BITE_MULTIPLIER: float = 2.0
const MAX_PRESSURE_MULTIPLIER: float = 1.50
const MAX_QUALITY_CHANCE: float = 0.50
const MAX_QUALITY_ROLLS: int = 2

var _catalog = null
## stacking_group -> {definition, remaining_seconds, source_kind, source_id}
var _active: Dictionary = {}


func configure(catalog) -> void:
	_catalog = catalog
	set_process(true)


func _process(delta: float) -> void:
	advance(delta)


func advance(delta: float) -> void:
	if delta <= 0.0 or _active.is_empty():
		return

	var expired_groups: Array[StringName] = []
	for raw_group in _active.keys():
		var group := StringName(str(raw_group))
		var entry: Dictionary = _active[raw_group]
		var remaining := maxf(float(entry.get("remaining_seconds", 0.0)) - delta, 0.0)
		entry["remaining_seconds"] = remaining
		_active[raw_group] = entry
		if remaining <= 0.0:
			expired_groups.append(group)

	if expired_groups.is_empty():
		return

	for group in expired_groups:
		var entry: Dictionary = _active.get(str(group), {})
		var definition := entry.get("definition", null) as ModifierDefinitionScript
		_active.erase(str(group))
		if definition != null:
			modifier_expired.emit(definition.effect_id)

	_emit_changed()


func apply_modifier(
	definition,
	source_kind: StringName = &"system",
	source_id: String = ""
) -> Dictionary:
	var effect := definition as ModifierDefinitionScript
	var result := {
		"success": false,
		"effect_id": "",
		"display_name": "",
		"duration_seconds": 0.0,
		"replaced_effect_id": "",
		"cleared_effect_ids": PackedStringArray(),
		"active": false,
	}

	if effect == null or not effect.is_valid_definition():
		result["reason"] = "invalid_effect"
		return result

	result["effect_id"] = str(effect.effect_id)
	result["display_name"] = effect.display_name
	result["duration_seconds"] = effect.duration_seconds

	var cleared := PackedStringArray()
	if effect.clear_positive_modifiers:
		_append_unique_strings(cleared, _clear_polarities([0]))
	if effect.clear_negative_modifiers:
		_append_unique_strings(cleared, _clear_polarities([1, 2]))
	result["cleared_effect_ids"] = cleared

	if effect.has_runtime_modifier():
		var group_key := str(effect.stacking_group)
		if _active.has(group_key):
			var previous: Dictionary = _active[group_key]
			var previous_definition := previous.get("definition", null) as ModifierDefinitionScript
			if previous_definition != null:
				result["replaced_effect_id"] = str(previous_definition.effect_id)

		_active[group_key] = {
			"definition": effect,
			"remaining_seconds": maxf(effect.duration_seconds, 0.0),
			"source_kind": source_kind,
			"source_id": source_id,
		}
		result["active"] = true

	result["success"] = true
	modifier_applied.emit(effect.effect_id, source_kind, source_id)
	_emit_changed()
	return result


func clear_all() -> void:
	if _active.is_empty():
		return
	_active.clear()
	_emit_changed()


func get_composite_snapshot() -> Dictionary:
	var bite_multiplier := 1.0
	var stamina_drain_multiplier := 1.0
	var hook_delay_multiplier := 1.0
	var line_tolerance_multiplier := 1.0
	var counter_steer_multiplier := 1.0
	var fish_pressure_multiplier := 1.0
	var quality_chance := 0.0
	var quality_rolls := 0
	var active_effect_ids := PackedStringArray()

	for entry_value in _active.values():
		var entry: Dictionary = entry_value
		var effect := entry.get("definition", null) as ModifierDefinitionScript
		if effect == null:
			continue
		active_effect_ids.append(str(effect.effect_id))
		bite_multiplier *= maxf(effect.bite_attraction_multiplier, 0.01)
		stamina_drain_multiplier *= maxf(effect.stamina_drain_multiplier, 0.01)
		hook_delay_multiplier *= maxf(effect.hook_off_delay_multiplier, 0.01)
		line_tolerance_multiplier *= maxf(effect.line_tolerance_multiplier, 0.01)
		counter_steer_multiplier *= maxf(effect.counter_steer_multiplier, 0.01)
		fish_pressure_multiplier *= maxf(effect.fish_pressure_multiplier, 0.01)
		quality_chance += maxf(effect.quality_bonus_roll_chance, 0.0)
		quality_rolls += maxi(effect.quality_bonus_rolls, 0)

	return {
		"bite_attraction_multiplier": clampf(
			bite_multiplier,
			MIN_MULTIPLIER,
			MAX_BITE_MULTIPLIER
		),
		"stamina_drain_multiplier": clampf(
			stamina_drain_multiplier,
			MIN_MULTIPLIER,
			MAX_ASSIST_MULTIPLIER
		),
		"hook_off_delay_multiplier": clampf(
			hook_delay_multiplier,
			MIN_MULTIPLIER,
			MAX_ASSIST_MULTIPLIER
		),
		"line_tolerance_multiplier": clampf(
			line_tolerance_multiplier,
			MIN_MULTIPLIER,
			MAX_ASSIST_MULTIPLIER
		),
		"counter_steer_multiplier": clampf(
			counter_steer_multiplier,
			MIN_MULTIPLIER,
			MAX_ASSIST_MULTIPLIER
		),
		"fish_pressure_multiplier": clampf(
			fish_pressure_multiplier,
			MIN_MULTIPLIER,
			MAX_PRESSURE_MULTIPLIER
		),
		"quality_bonus_roll_chance": clampf(
			quality_chance,
			0.0,
			MAX_QUALITY_CHANCE
		),
		"quality_bonus_rolls": clampi(
			quality_rolls,
			0,
			MAX_QUALITY_ROLLS
		),
		"active_effect_ids": active_effect_ids,
		"active_count": active_effect_ids.size(),
	}


func get_bite_attraction_multiplier() -> float:
	return float(get_composite_snapshot().get("bite_attraction_multiplier", 1.0))


func get_specimen_generation_context() -> Dictionary:
	var composite := get_composite_snapshot()
	var chance := float(composite.get("quality_bonus_roll_chance", 0.0))
	var rolls := int(composite.get("quality_bonus_rolls", 0))
	return {
		"session_quality_active": chance > 0.0 and rolls > 0,
		"session_quality_bonus_chance": chance,
		"session_quality_bonus_rolls": rolls,
		"session_effect_ids": composite.get("active_effect_ids", PackedStringArray()),
	}


func get_fight_modifiers() -> Dictionary:
	var composite := get_composite_snapshot()
	return {
		"stamina_drain_multiplier": composite.get("stamina_drain_multiplier", 1.0),
		"hook_off_delay_multiplier": composite.get("hook_off_delay_multiplier", 1.0),
		"line_tolerance_multiplier": composite.get("line_tolerance_multiplier", 1.0),
		"counter_steer_multiplier": composite.get("counter_steer_multiplier", 1.0),
		"fish_pressure_multiplier": composite.get("fish_pressure_multiplier", 1.0),
		"session_effect_ids": composite.get("active_effect_ids", PackedStringArray()),
	}


func get_active_effects() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry_value in _active.values():
		var entry: Dictionary = entry_value
		var effect := entry.get("definition", null) as ModifierDefinitionScript
		if effect == null:
			continue
		result.append({
			"effect_id": str(effect.effect_id),
			"display_name": effect.display_name,
			"description": effect.description,
			"stacking_group": str(effect.stacking_group),
			"polarity": int(effect.polarity),
			"remaining_seconds": maxf(float(entry.get("remaining_seconds", 0.0)), 0.0),
			"source_kind": str(entry.get("source_kind", "")),
			"source_id": str(entry.get("source_id", "")),
		})
	result.sort_custom(Callable(self, "_active_effect_less"))
	return result


func create_runtime_snapshot() -> Dictionary:
	var entries: Array[Dictionary] = []
	for raw_group in _active.keys():
		var entry: Dictionary = _active[raw_group]
		var effect := entry.get("definition", null) as ModifierDefinitionScript
		if effect == null:
			continue
		entries.append({
			"stacking_group": str(raw_group),
			"effect_id": str(effect.effect_id),
			"remaining_seconds": maxf(float(entry.get("remaining_seconds", 0.0)), 0.0),
			"source_kind": str(entry.get("source_kind", "")),
			"source_id": str(entry.get("source_id", "")),
		})
	return {"entries": entries}


func restore_runtime_snapshot(snapshot: Dictionary) -> void:
	_active.clear()
	if _catalog == null:
		_emit_changed()
		return

	var raw_entries = snapshot.get("entries", [])
	if not (raw_entries is Array):
		_emit_changed()
		return

	for raw_entry in raw_entries:
		if not (raw_entry is Dictionary):
			continue
		var entry: Dictionary = raw_entry
		var effect = _catalog.get_effect_by_id(StringName(str(entry.get("effect_id", ""))))
		if effect == null or not effect.is_valid_definition():
			continue
		var remaining := maxf(float(entry.get("remaining_seconds", 0.0)), 0.0)
		if remaining <= 0.0 or not effect.has_runtime_modifier():
			continue
		_active[str(effect.stacking_group)] = {
			"definition": effect,
			"remaining_seconds": remaining,
			"source_kind": StringName(str(entry.get("source_kind", "system"))),
			"source_id": str(entry.get("source_id", "")),
		}
	_emit_changed()


func _clear_polarities(polarities: Array) -> PackedStringArray:
	var removed := PackedStringArray()
	var groups_to_remove: Array[String] = []
	for raw_group in _active.keys():
		var entry: Dictionary = _active[raw_group]
		var effect := entry.get("definition", null) as ModifierDefinitionScript
		if effect == null or not polarities.has(int(effect.polarity)):
			continue
		removed.append(str(effect.effect_id))
		groups_to_remove.append(str(raw_group))
	for group in groups_to_remove:
		_active.erase(group)
	return removed


func _append_unique_strings(target: PackedStringArray, source: PackedStringArray) -> void:
	for value in source:
		if not target.has(value):
			target.append(value)


func _active_effect_less(a: Dictionary, b: Dictionary) -> bool:
	return str(a.get("effect_id", "")).naturalnocasecmp_to(str(b.get("effect_id", ""))) < 0


func _emit_changed() -> void:
	modifiers_changed.emit(get_composite_snapshot())
