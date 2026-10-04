extends Resource
class_name FishingMasteryTechniqueDefinition

@export_category("Identity")
@export var technique_id: StringName = &""
@export var display_name: String = ""
@export var category: StringName = &"observation"
@export_multiline var description: String = ""

@export_category("Teaching")
## Stable future NPC/master id. Techniques are taught, not rank-granted.
@export var teacher_id: StringName = &""
@export var prerequisite_ids: PackedStringArray = PackedStringArray()

@export_category("Runtime Capabilities")
## Gameplay systems query capabilities instead of hard-coding technique ids.
@export var capability_tags: PackedStringArray = PackedStringArray()


func is_valid_definition() -> bool:
	if technique_id == &"" or display_name.strip_edges().is_empty():
		return false
	if teacher_id == &"":
		return false
	var seen: Dictionary = {}
	for raw_tag in capability_tags:
		var tag := str(raw_tag).strip_edges().to_lower()
		if tag.is_empty() or seen.has(tag):
			return false
		seen[tag] = true
	return true


func has_capability(capability: StringName) -> bool:
	var key := str(capability).strip_edges().to_lower()
	if key.is_empty():
		return false
	for raw_tag in capability_tags:
		if str(raw_tag).strip_edges().to_lower() == key:
			return true
	return false
