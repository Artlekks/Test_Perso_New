extends Resource
class_name WorldRequestDefinition

## Canonical descriptive contract for one world request.
##
## This resource owns request identity and presentation metadata only. It does
## not own acceptance, objective truth, rewards, inventory, or save mutations.

@export var request_id: StringName = &""
@export var title: String = "Request"
@export var giver_id: StringName = &""
@export var giver_name: String = ""
@export var objective_type: StringName = &""
@export_multiline var active_objective: String = ""
@export_multiline var ready_objective: String = ""
@export_multiline var completed_objective: String = ""
@export var objective_metadata: Dictionary = {}
@export var reward_source_id: StringName = &""
@export var reward_event_id: StringName = &""
@export var sort_order: int = 100
@export var tags: Array[StringName] = []


func objective_for_state(state_id: StringName) -> String:
	match state_id:
		&"accepted":
			return active_objective
		&"ready_to_turn_in":
			return ready_objective
		&"completed":
			return completed_objective
	return ""


func snapshot() -> Dictionary:
	return {
		"request_id": request_id,
		"title": title,
		"giver_id": giver_id,
		"giver_name": giver_name,
		"objective_type": objective_type,
		"active_objective": active_objective,
		"ready_objective": ready_objective,
		"completed_objective": completed_objective,
		"objective_metadata": objective_metadata.duplicate(true),
		"reward_source_id": reward_source_id,
		"reward_event_id": reward_event_id,
		"sort_order": sort_order,
		"tags": tags.duplicate(),
	}


func audit() -> PackedStringArray:
	var errors := PackedStringArray()
	if request_id == &"":
		errors.append("request_id is empty")
	if title.strip_edges().is_empty():
		errors.append("title is empty for %s" % String(request_id))
	if giver_id == &"":
		errors.append("giver_id is empty for %s" % String(request_id))
	if objective_type == &"":
		errors.append("objective_type is empty for %s" % String(request_id))
	if active_objective.strip_edges().is_empty():
		errors.append("active_objective is empty for %s" % String(request_id))
	if ready_objective.strip_edges().is_empty():
		errors.append("ready_objective is empty for %s" % String(request_id))
	if completed_objective.strip_edges().is_empty():
		errors.append("completed_objective is empty for %s" % String(request_id))
	if reward_source_id == &"":
		errors.append("reward_source_id is empty for %s" % String(request_id))
	if reward_event_id == &"":
		errors.append("reward_event_id is empty for %s" % String(request_id))
	return errors
