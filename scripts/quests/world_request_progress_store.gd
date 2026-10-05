extends RefCounted
class_name WorldRequestProgressStore

## Tiny generic persistence helper for request acceptance flags.
##
## Request owners keep objective/reward truth in their domain services. This
## helper only persists whether the player accepted a request, using the shared
## PlayerItemInventory metadata/save that already belongs to the session.

const ACCEPTED_PREFIX := "world_request/accepted/"


static func acceptance_key(request_id: StringName) -> String:
	var clean_id := String(request_id).strip_edges()
	if clean_id.is_empty():
		return ""
	return "%s%s" % [ACCEPTED_PREFIX, clean_id]


static func is_accepted(inventory: Node, request_id: StringName) -> bool:
	var key := acceptance_key(request_id)
	if key.is_empty() or inventory == null or not inventory.has_method("get_metadata"):
		return false
	return bool(inventory.call("get_metadata", key, false))


static func mark_accepted(inventory: Node, request_id: StringName) -> bool:
	var key := acceptance_key(request_id)
	if key.is_empty() or inventory == null:
		return false
	if is_accepted(inventory, request_id):
		return true
	if (
		not inventory.has_method("create_transaction_snapshot")
		or not inventory.has_method("set_metadata")
		or not inventory.has_method("commit_changes")
		or not inventory.has_method("restore_transaction_snapshot")
	):
		return false

	var snapshot = inventory.call("create_transaction_snapshot")
	if not (snapshot is Dictionary):
		return false
	inventory.call("set_metadata", key, true, false)
	if bool(inventory.call("commit_changes")):
		return true
	inventory.call("restore_transaction_snapshot", snapshot, false)
	return false


static func reset_acceptance(inventory: Node, request_id: StringName) -> bool:
	var key := acceptance_key(request_id)
	if key.is_empty() or inventory == null:
		return false
	if (
		not inventory.has_method("create_transaction_snapshot")
		or not inventory.has_method("set_metadata")
		or not inventory.has_method("commit_changes")
		or not inventory.has_method("restore_transaction_snapshot")
	):
		return false
	var snapshot = inventory.call("create_transaction_snapshot")
	if not (snapshot is Dictionary):
		return false
	inventory.call("set_metadata", key, false, false)
	if bool(inventory.call("commit_changes")):
		return true
	inventory.call("restore_transaction_snapshot", snapshot, false)
	return false
