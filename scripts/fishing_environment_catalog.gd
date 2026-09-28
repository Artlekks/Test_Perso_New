extends Resource

const ConditionDefinitionScript = preload(
	"res://scripts/database/fishing_environment_condition_definition.gd"
)

@export var default_condition_ids: PackedStringArray = PackedStringArray()
@export var conditions: Array[Resource] = []


func get_condition_by_id(condition_id: StringName) -> ConditionDefinitionScript:
	if condition_id == &"":
		return null
	var key: String = str(condition_id).strip_edges().to_lower()
	for raw_condition in conditions:
		var condition: ConditionDefinitionScript = raw_condition as ConditionDefinitionScript
		if condition == null:
			continue
		if str(condition.condition_id).strip_edges().to_lower() == key:
			return condition
	return null


func has_condition(condition_id: StringName) -> bool:
	return get_condition_by_id(condition_id) != null


func get_condition_ids() -> PackedStringArray:
	var result: PackedStringArray = PackedStringArray()
	for raw_condition in conditions:
		var condition: ConditionDefinitionScript = raw_condition as ConditionDefinitionScript
		if condition != null:
			result.append(str(condition.condition_id))
	return result


func is_valid_catalog() -> bool:
	if conditions.is_empty():
		return false
	var seen: Dictionary = {}
	for raw_condition in conditions:
		var condition: ConditionDefinitionScript = raw_condition as ConditionDefinitionScript
		if condition == null or not condition.is_valid_definition():
			return false
		var key: String = str(condition.condition_id).strip_edges().to_lower()
		if key.is_empty() or seen.has(key):
			return false
		seen[key] = true
	for raw_default in default_condition_ids:
		if not seen.has(str(raw_default).strip_edges().to_lower()):
			return false
	return true
