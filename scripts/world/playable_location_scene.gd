extends Node3D

@export var location_context: PlayableLocationContext

func _enter_tree() -> void:
	if location_context == null:
		return
	get_node("/root/WorldLocations").bind_location(location_context, self)
	# Bind the authored population before zone/ambient/fishing child readiness.
	get_node("World/FishZone_V2").fishing_spot = location_context.fishing_spot

func _ready() -> void:
	if location_context == null:
		return
	var label := Label.new()
	label.text = location_context.display_name
	label.position = Vector2(12, 12)
	label.add_theme_font_size_override("font_size", 16)
	var layer := CanvasLayer.new()
	layer.layer = 5
	add_child(layer)
	layer.add_child(label)

func _exit_tree() -> void:
	get_node("/root/WorldLocations").unbind_location(self)
