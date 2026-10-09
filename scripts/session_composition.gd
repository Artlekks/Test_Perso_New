extends RefCounted
class_name SessionComposition
const Services = preload("res://scripts/fishing_session_services.gd")

static func acquire(tree: SceneTree) -> FishingSessionServices:
	var owner := tree.root.get_node_or_null("FishingSessionServices")
	if owner == null:
		var pending = tree.root.get_meta("pending_fishing_session_services") if tree.root.has_meta("pending_fishing_session_services") else null
		if pending is WeakRef: owner = pending.get_ref()
	if owner != null:
		owner.initialize()
		return owner
	owner = Services.new()
	owner.name = "FishingSessionServices"
	tree.root.set_meta("pending_fishing_session_services", weakref(owner))
	owner.initialize()
	tree.root.add_child.call_deferred(owner)
	return owner
