extends Node
const GameplaySceneRoot = preload("res://scripts/gameplay_scene_root.gd")

signal location_changed(location: Resource)
signal access_changed
const ContextScript = preload("res://scripts/world/playable_location_context.gd")
const LOCATIONS = [
	preload("res://data/world/locations/beach.tres"),
	preload("res://data/world/locations/wyndia_ocean_outpost.tres"),
	preload("res://data/world/locations/lyp_lake_outpost.tres"),
	preload("res://data/world/locations/river_fishing_outpost.tres"),
	preload("res://data/world/locations/chiqua_supply_outpost.tres"),
]
var current_location: ContextScript = null
var _scene_ref: WeakRef
var transitioning := false
var _progress_inventory: FishingInventory
var _unlocks: FishingUnlockState

func get_all_locations() -> Array:
	return LOCATIONS.duplicate()

func configure_developer_access(service: Node) -> void:
	if not service.mode_changed.is_connected(_on_developer_mode_changed):
		service.mode_changed.connect(_on_developer_mode_changed)

func _on_developer_mode_changed(_enabled: bool) -> void:
	access_changed.emit()

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
	access_changed.emit()

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
	# Explicit inventory snapshots are progression queries, including the flag
	# discovery loop above. A runtime access override must never grant flags.
	if inventory == null and RuntimeAccessPolicy.allows(&"travel"):
		return {"location_id": id, "unlocked": true, "missing_item_ids": PackedStringArray(), "unlock_hint": location.unlock_hint, "developer_access": true}
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
	for index in range(current_location.economy_contexts.size()):
		if current_location.economy_contexts[index] == context and index < current_location.economy_provider_paths.size():
			var path: String = current_location.economy_provider_paths[index].strip_edges()
			if not path.is_empty() and scene.get_node_or_null(NodePath(path)) == provider:
				return true
	return false

func get_unlocked_destinations(location_id: StringName = &"", inventory = null) -> PackedStringArray:
	var destinations := PackedStringArray()
	var location = current_location if location_id == &"" else get_location(location_id)
	if location == null:
		return destinations
	var candidates: PackedStringArray = location.destinations
	if inventory == null and RuntimeAccessPolicy.allows(&"travel"):
		candidates = PackedStringArray()
		for authored in LOCATIONS:
			if authored.location_id != location.location_id: candidates.append(String(authored.location_id))
	for destination in candidates:
		var target := get_location(StringName(destination))
		if target != null and not target.scene_path.is_empty() and not destinations.has(destination) and get_access_snapshot(target.location_id, inventory).get("unlocked", false):
			destinations.append(destination)
	return destinations


func get_reachable_world_data(inventory = null) -> Dictionary:
	var sources: Array = []
	var spots: Array = []
	var visited := PackedStringArray()
	var source_issues: Array[Dictionary] = []
	var snapshot := {"sources": sources, "spots": spots, "location_ids": visited, "destination_ids": PackedStringArray(), "source_issues": source_issues}
	# A missing/transitioning context has no implied destination or fallback.
	if current_location == null or transitioning or get_location(current_location.location_id) == null:
		return snapshot
	snapshot.destination_ids = get_unlocked_destinations(current_location.location_id, inventory)
	var pending: Array[StringName] = [current_location.location_id]
	while not pending.is_empty():
		var id: StringName = pending.pop_front()
		if visited.has(String(id)) or not get_access_snapshot(id, inventory).get("unlocked", false):
			continue
		visited.append(String(id))
		var location := get_location(id)
		if location.fishing_spot != null:
			spots.append(location.fishing_spot)
		for index in range(location.economy_contexts.size()):
			# Malformed parallel source metadata must never invent a provider.
			if index >= location.economy_provider_paths.size() or location.economy_provider_paths[index].strip_edges().is_empty() or location.economy_contexts[index] == null:
				source_issues.append({"location_id": id, "context_index": index, "reason": "missing_economy_provider"})
				continue
			sources.append({"context": location.economy_contexts[index], "path": "%s:%s" % [id, location.economy_provider_paths[index]]})
		for destination in get_unlocked_destinations(id, inventory):
			pending.append(StringName(destination))
	# Packed arrays use value semantics; publish the populated visited array.
	snapshot.location_ids = visited
	return snapshot

func request_travel(destination: StringName) -> Dictionary:
	if transitioning or current_location == null or get_tree().paused:
		return {"success": false, "reason": "busy"}
	var target := get_location(destination)
	if target == null or target.scene_path.is_empty() or not ResourceLoader.exists(target.scene_path):
		return {"success": false, "reason": "scene_unavailable"}
	if not current_location.destinations.has(String(destination)) and not RuntimeAccessPolicy.allows(&"travel"):
		return {"success": false, "reason": "no_route"}
	if not get_access_snapshot(destination).get("unlocked", false):
		return {"success": false, "reason": "destination_locked"}
	var scene = _scene_ref.get_ref()
	var game = scene.get_node_or_null("Game/GameMode") if is_instance_valid(scene) else null
	if game == null or not game.is_exploration():
		return {"success": false, "reason": "fishing_owns_input"}
	transitioning = true
	_clear_economy_access()
	var error := GameplaySceneRoot.change_scene_to_file(get_tree(), get_location(destination).scene_path)
	if error != OK:
		transitioning = false
		return {"success": false, "reason": "scene_unavailable"}
	return {"success": true, "reason": "travel_started"}

func _clear_economy_access() -> void:
	var session := get_node_or_null("/root/FishingSessionServices")
	if session != null and session.economy_access != null:
		session.economy_access.clear_access_context()
