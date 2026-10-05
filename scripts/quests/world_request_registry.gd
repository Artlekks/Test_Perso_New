extends RefCounted
class_name WorldRequestRegistry

## Canonical read-only access point for authored world requests.
##
## Request sources provide runtime state/objective truth. This registry provides
## stable ids, titles, giver metadata, reward identities, ordering, and default
## objective copy so UI layers no longer need request-specific knowledge.

const DEFAULT_CATALOG: Resource = preload("res://data/requests/request_catalog.tres")


static func definition_snapshot(request_id: StringName) -> Dictionary:
	if DEFAULT_CATALOG == null or not DEFAULT_CATALOG.has_method("get_definition"):
		return {}
	var definition = DEFAULT_CATALOG.call("get_definition", request_id)
	if definition == null:
		return {}
	if definition.has_method("snapshot"):
		var raw_snapshot = definition.call("snapshot")
		if raw_snapshot is Dictionary:
			return (raw_snapshot as Dictionary).duplicate(true)
	return {}


static func has_definition(request_id: StringName) -> bool:
	return not definition_snapshot(request_id).is_empty()


static func presentation_for(
	request_id: StringName,
	state_id: StringName,
	objective_override: String = ""
) -> Dictionary:
	var snapshot := definition_snapshot(request_id)
	if snapshot.is_empty():
		return {
			"request_id": request_id,
			"title": "",
			"objective": objective_override,
			"state_id": state_id,
			"sort_order": 1000,
			"metadata": {},
		}

	var objective := objective_override
	if objective.strip_edges().is_empty():
		match state_id:
			&"accepted":
				objective = str(snapshot.get("active_objective", ""))
			&"ready_to_turn_in":
				objective = str(snapshot.get("ready_objective", ""))
			&"completed":
				objective = str(snapshot.get("completed_objective", ""))

	var objective_metadata: Dictionary = {}
	var raw_objective_metadata = snapshot.get("objective_metadata", {})
	if raw_objective_metadata is Dictionary:
		objective_metadata = (raw_objective_metadata as Dictionary).duplicate(true)
	var tags: Array = []
	var raw_tags = snapshot.get("tags", [])
	if raw_tags is Array:
		tags = (raw_tags as Array).duplicate()

	return {
		"request_id": request_id,
		"title": str(snapshot.get("title", "Request")),
		"objective": objective,
		"state_id": state_id,
		"sort_order": int(snapshot.get("sort_order", 1000)),
		"metadata": {
			"giver_id": snapshot.get("giver_id", &""),
			"giver_name": snapshot.get("giver_name", ""),
			"objective_type": snapshot.get("objective_type", &""),
			"objective_metadata": objective_metadata,
			"reward_source_id": snapshot.get("reward_source_id", &""),
			"reward_event_id": snapshot.get("reward_event_id", &""),
			"tags": tags,
		},
	}


static func audit() -> Dictionary:
	if DEFAULT_CATALOG == null or not DEFAULT_CATALOG.has_method("audit"):
		return {
			"definition_count": 0,
			"errors": PackedStringArray(["Default request catalog is unavailable."]),
		}
	var raw_audit = DEFAULT_CATALOG.call("audit")
	if raw_audit is Dictionary:
		return (raw_audit as Dictionary).duplicate(true)
	return {
		"definition_count": 0,
		"errors": PackedStringArray(["Default request catalog returned an invalid audit result."]),
	}
