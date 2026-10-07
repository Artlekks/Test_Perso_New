extends Node3D

@export var destination_id: StringName
@onready var area: Area3D = $InteractionArea
@onready var label: Label3D = $Label3D

func _ready() -> void:
	add_to_group(&"world_interaction_targets")
	var service := get_node("/root/WorldLocations")
	var destination = service.get_location(destination_id)
	label.text = "K: Travel to %s\n%s" % [destination.display_name, destination.unlock_hint] if destination != null else "Route unavailable"

func is_world_interaction_available(event: InputEvent) -> bool:
	if not (event is InputEventKey) or not event.pressed or event.echo or event.keycode not in [KEY_K, KEY_ENTER]:
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
