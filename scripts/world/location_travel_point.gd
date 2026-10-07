extends Node3D

@export var destination_id: StringName
@onready var area: Area3D = $InteractionArea
@onready var label: Label3D = $Label3D
var _locations: Node

func _ready() -> void:
	add_to_group(&"world_interaction_targets")
	var service := get_node("/root/WorldLocations")
	_locations = service
	service.location_changed.connect(_refresh_label)
	service.access_changed.connect(_refresh_label)
	_refresh_label()

func _refresh_label(_location: Resource = null) -> void:
	if not is_inside_tree() or is_queued_for_deletion():
		return
	var service := get_node("/root/WorldLocations")
	var destination = service.get_location(destination_id)
	if destination == null or service.current_location == null or not service.current_location.destinations.has(String(destination_id)):
		label.text = "Route unavailable"
	elif service.get_unlocked_destinations().has(String(destination_id)):
		label.text = "K: Travel to %s" % destination.display_name
	else:
		label.text = "Locked: %s\n%s" % [destination.display_name, destination.unlock_hint]

func _exit_tree() -> void:
	if is_instance_valid(_locations):
		if _locations.location_changed.is_connected(_refresh_label):
			_locations.location_changed.disconnect(_refresh_label)
		if _locations.access_changed.is_connected(_refresh_label):
			_locations.access_changed.disconnect(_refresh_label)

func is_world_interaction_available(event: InputEvent) -> bool:
	if not (event is InputEventKey) or not event.pressed or event.echo or event.keycode not in [KEY_K, KEY_ENTER]:
		return false
	var service := get_node("/root/WorldLocations")
	if service.transitioning or not service.get_unlocked_destinations().has(String(destination_id)):
		return false
	for body in area.get_overlapping_bodies():
		if body is CharacterBody3D:
			return true
	return false

func interact_from_world(event: InputEvent) -> void:
	if not is_world_interaction_available(event):
		return
	var service := get_node("/root/WorldLocations")
	var result: Dictionary = service.request_travel(destination_id)
	if not result.success:
		label.text = "Cannot travel: %s\n%s" % [result.reason.replace("_", " "), service.get_access_snapshot(destination_id).get("unlock_hint", "")]
