extends Node3D

@export var development_tools_enabled := true

@export var location_context: PlayableLocationContext

func _enter_tree() -> void:
	preload("res://scripts/ui/canonical_game_surface.gd").prepare(self)
	if location_context == null:
		return
	get_node("/root/WorldLocations").bind_location(location_context, self)
	# The location is bound before the zone's _ready(), so its fish population
	# can read the authored context. Do not access child nodes here: some
	# runtime scene compositions add them after this parent's _enter_tree().

func _ready() -> void:
	_bind_fishing_spot_after_children_are_ready()
	_mount_ambient_vfx()
	if OS.is_debug_build() and development_tools_enabled:
		var tools = load("res://scripts/development/fishing_development_layer.gd")
		tools.ensure(SessionComposition.acquire(get_tree())).mount_game(self)
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

## Ambient effects belong to the location World, NOT fishing mode.
## Explicitly avoids modifying the authored scene or camera configuration.
func _mount_ambient_vfx() -> void:
	var world: Node3D = get_node_or_null("World") as Node3D
	if world == null:
		return
	for entry in [
		["FishingCurrentVFX", "res://actors/FishingCurrentVFX.tscn"],
		["FishingWindVFX", "res://actors/FishingWindVFX.tscn"],
		["FishingRainVFX", "res://actors/FishingRainVFX.tscn"]
	]:
		var node_name: String = entry[0]
		if world.has_node(NodePath(node_name)):
			continue
		var scene: PackedScene = load(entry[1]) as PackedScene
		if scene == null:
			push_warning("Ambient VFX scene unavailable: " + String(entry[1]))
			continue
		var effect: Node3D = scene.instantiate() as Node3D
		if effect == null:
			continue
		effect.name = node_name
		world.add_child(effect)


func _bind_fishing_spot_after_children_are_ready() -> void:
	if location_context == null or location_context.fishing_spot == null:
		return

	# Prefer the authored path. On alternate location scenes the zone may
	# live elsewhere, but must still belong to *this* location scene.
	var fish_zone: Node = get_node_or_null("World/FishZone_V2")
	if fish_zone == null:
		for candidate in get_tree().get_nodes_in_group("world_fishing_spots"):
			if is_ancestor_of(candidate):
				fish_zone = candidate
				break

	if fish_zone == null:
		push_warning("PlayableLocationScene: No fishing zone was found in '%s'. Check this scene's FishZone_V2 instance; fishing requires a configured zone." % name)
		return
	if not fish_zone.has_method("get_fishing_spot"):
		push_warning("PlayableLocationScene: '%s' is not a valid fishing zone; the location's fishing spot was not applied." % fish_zone.get_path())
		return

	# Set the authored property directly, preserving the existing behavior.
	# Calling set_fishing_spot() here would incorrectly enable debug override.
	fish_zone.set("fishing_spot", location_context.fishing_spot)


func _exit_tree() -> void:
	get_node("/root/WorldLocations").unbind_location(self)
