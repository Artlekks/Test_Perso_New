extends Node

signal location_changed(location: Resource)
const ContextScript = preload("res://scripts/world/playable_location_context.gd")
const LOCATIONS = [
	preload("res://data/world/locations/beach.tres"),
	preload("res://data/world/locations/wyndia_ocean_outpost.tres"),
	preload("res://data/world/locations/lyp_lake_outpost.tres"),
]
var current_location: ContextScript = null
var _scene_ref: WeakRef
var transitioning := false
var _progress_inventory: FishingInventory
var _unlocks: FishingUnlockState

func configure_progression(inventory: FishingInventory, unlocks: FishingUnlockState) -> void:
	if is_instance_valid(_progress_inventory) and _progress_inventory.changed.is_connected(_refresh_unlocks):
		_progress_inventory.changed.disconnect(_refresh_unlocks)
	_progress_inventory = inventory
	_unlocks = unlocks
	_progress_inventory.changed.connect(_refresh_unlocks)
	_refresh_unlocks()

func _refresh_unlocks() -> void:
	if not is_instance_valid(_progress_inventory) or not is_instance_valid(_unlocks):
		return
	for location in LOCATIONS:
		if location.unlock_flag != &"" and get_access_snapshot(location.location_id, _progress_inventory).unlocked:
			_unlocks.grant_flag(location.unlock_flag)

func get_location(id: StringName) -> ContextScript:
	for location in LOCATIONS:
		if location.location_id == id:
			return location
	return null

func _inventory():
	var session := get_node_or_null("/root/FishingSessionServices")
	return session.inventory if session != null else null

func get_access_snapshot(id: StringName, inventory = null) -> Dictionary:
	var location := get_location(id)
	if location == null:
		return {"unlocked": false, "reason": "unknown_location"}
	if inventory == null and is_instance_valid(_unlocks) and location.unlock_flag != &"" and _unlocks.has_flag(location.unlock_flag):
		return {"location_id": id, "unlocked": true, "missing_item_ids": PackedStringArray(), "unlock_hint": location.unlock_hint}
	if inventory == null:
		inventory = _inventory()
	var missing := PackedStringArray()
	for item_id in location.required_lure_ids:
		if inventory == null or not inventory.owns_lure(StringName(item_id)):
			missing.append(item_id)
	for item_id in location.required_rod_ids:
		if inventory == null or not inventory.owns_rod(StringName(item_id)):
			missing.append(item_id)
	return {"location_id": id, "unlocked": missing.is_empty(), "missing_item_ids": missing, "unlock_hint": location.unlock_hint}

func is_current_scene(scene: Node) -> bool:
	return _scene_ref != null and _scene_ref.get_ref() == scene and current_location != null

func bind_location(location: ContextScript, scene: Node) -> void:
	current_location = location
	_scene_ref = weakref(scene)
	transitioning = false
	_clear_economy_access()
	location_changed.emit(location)

func unbind_location(scene: Node) -> void:
	if not is_current_scene(scene):
		return
	current_location = null
	_scene_ref = null
	_clear_economy_access()
	location_changed.emit(null)

func context_belongs_here(context: MerchantEconomyContext, provider: Node) -> bool:
	if current_location == null or _scene_ref == null or transitioning:
		return false
	var scene = _scene_ref.get_ref()
	if not is_instance_valid(scene) or not scene.is_ancestor_of(provider):
		return false
	return current_location.economy_contexts.has(context)

func get_reachable_world_data(inventory = null) -> Dictionary:
	var sources: Array = []
	var spots: Array = []
	var visited := PackedStringArray()
	var pending: Array[StringName] = [&"beach"]
	while not pending.is_empty():
		var id: StringName = pending.pop_front()
		if visited.has(String(id)) or not get_access_snapshot(id, inventory).get("unlocked", false):
			continue
		visited.append(String(id))
		var location := get_location(id)
		spots.append(location.fishing_spot)
		for index in range(location.economy_contexts.size()):
			sources.append({"context": location.economy_contexts[index], "path": "%s:%s" % [id, location.economy_provider_paths[index]]})
		for destination in location.destinations:
			pending.append(StringName(destination))
	return {"sources": sources, "spots": spots, "location_ids": visited}

func request_travel(destination: StringName) -> Dictionary:
	if transitioning or current_location == null or get_tree().paused:
		return {"success": false, "reason": "busy"}
	if not current_location.destinations.has(String(destination)):
		return {"success": false, "reason": "no_route"}
	if not get_access_snapshot(destination).get("unlocked", false):
		return {"success": false, "reason": "destination_locked"}
	var scene = _scene_ref.get_ref()
	var game = scene.get_node_or_null("Game/GameMode") if is_instance_valid(scene) else null
	if game == null or not game.is_exploration():
		return {"success": false, "reason": "fishing_owns_input"}
	transitioning = true
	_clear_economy_access()
	var error := get_tree().change_scene_to_file(get_location(destination).scene_path)
	if error != OK:
		transitioning = false
		return {"success": false, "reason": "scene_unavailable"}
	return {"success": true, "reason": "travel_started"}

func _clear_economy_access() -> void:
	var session := get_node_or_null("/root/FishingSessionServices")
	if session != null and session.economy_access != null:
		session.economy_access.clear_access_context()
