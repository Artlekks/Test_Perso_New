extends Node
class_name WorldActorPresentation

## Runtime presentation/collision polish for billboard-style world actors.
##
## v2 shadow rule:
## - Actor sprites keep the existing screen-feet render ordering.
## - Old per-sprite ShadowSprite3D nodes are hidden.
## - Every actor receives one horizontal blob shadow locked to the BEACH GROUND,
##   following X/Z only. The shadow therefore never rotates, flips, or drifts when
##   the AnimatedSprite3D changes animation/direction.

@export var world_root: Node3D
@export var player: CharacterBody3D
@export var camera: Camera3D

@export_category("Sprite Sorting")
@export_range(-120, -1, 1) var far_render_priority: int = -90
@export_range(1, 120, 1) var near_render_priority: int = 90

@export_category("NPC Footprints")
@export_range(0.12, 0.40, 0.01) var minimum_npc_radius: float = 0.24
@export_range(0.30, 0.80, 0.01) var minimum_npc_height: float = 0.52

@export_category("Ground Blob Shadows")
@export var player_shadow_size: Vector2 = Vector2(0.36, 0.17)
@export var npc_shadow_size: Vector2 = Vector2(0.40, 0.18)
@export var critter_shadow_size: Vector2 = Vector2(0.22, 0.10)
@export_range(0.001, 0.03, 0.001) var shadow_ground_lift: float = 0.006

const BLOB_SHADOW_SCENE: PackedScene = preload("res://actors/WorldBlobShadow.tscn")
const IGNORED_WORLD_ROOTS: Array[StringName] = [
	&"FishZone_V2",
	&"beach",
	&"DepthFloor",
	&"ShoreBlocker",
	&"BeachGatheringCircuit",
]

var _sort_entries: Array[Dictionary] = []
var _shadow_entries: Array[Dictionary] = []
var _shadow_ground_y: float = 0.0


func _ready() -> void:
	process_priority = 200
	call_deferred("_setup_actor_presentation")


func _process(_delta: float) -> void:
	_update_render_priorities()
	_update_blob_shadows()


func _setup_actor_presentation() -> void:
	_sort_entries.clear()
	_clear_blob_shadows()
	_shadow_ground_y = _resolve_shadow_ground_y()

	if is_instance_valid(world_root):
		for child: Node in world_root.get_children():
			if not (child is Node3D):
				continue
			var actor := child as Node3D
			if StringName(actor.name) in IGNORED_WORLD_ROOTS:
				continue
			_register_actor(actor)
			_expand_actor_footprint(actor)

	if is_instance_valid(player):
		_register_actor(player)

	_update_render_priorities()
	_update_blob_shadows()


func _register_actor(anchor: Node3D) -> void:
	var sprites: Array[Node] = anchor.find_children("*", "AnimatedSprite3D", true, false)
	if sprites.is_empty():
		return

	_disable_authored_shadows(anchor)

	for node: Node in sprites:
		var sprite := node as AnimatedSprite3D
		if sprite == null:
			continue
		sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
		sprite.transparent = true
		sprite.no_depth_test = false
		_sort_entries.append({"anchor": anchor, "sprite": sprite})

	_create_blob_shadow(anchor)


func _disable_authored_shadows(anchor: Node3D) -> void:
	for node: Node in anchor.find_children("*", "Sprite3D", true, false):
		var sprite := node as Sprite3D
		if sprite == null:
			continue
		if String(sprite.name).to_lower().contains("shadow"):
			sprite.visible = false


func _create_blob_shadow(anchor: Node3D) -> void:
	if not is_instance_valid(world_root) or BLOB_SHADOW_SCENE == null:
		return
	var shadow := BLOB_SHADOW_SCENE.instantiate() as MeshInstance3D
	if shadow == null:
		return
	shadow.name = "%sBlobShadow" % String(anchor.name)
	world_root.add_child(shadow)

	var shadow_size: Vector2 = npc_shadow_size
	if anchor == player:
		shadow_size = player_shadow_size
	elif anchor.name == &"BeachCritter":
		shadow_size = critter_shadow_size
	shadow.scale = Vector3(shadow_size.x, 1.0, shadow_size.y)

	_shadow_entries.append({"anchor": anchor, "shadow": shadow})


func _resolve_shadow_ground_y() -> float:
	if is_instance_valid(world_root):
		var beach_surface := world_root.get_node_or_null("beach/Beach") as Node3D
		if beach_surface != null:
			return beach_surface.global_position.y + shadow_ground_lift
	# Fallback is intentionally conservative. In the current Ocean Spot scene,
	# beach/Beach exists, so this path is only for future test scenes.
	if is_instance_valid(player):
		return player.global_position.y - 0.08 + shadow_ground_lift
	return shadow_ground_lift


func _update_blob_shadows() -> void:
	for entry: Dictionary in _shadow_entries:
		var anchor := entry.get("anchor") as Node3D
		var shadow := entry.get("shadow") as MeshInstance3D
		if not is_instance_valid(shadow):
			continue
		if not is_instance_valid(anchor):
			shadow.queue_free()
			continue
		var actor_position: Vector3 = anchor.global_position
		shadow.global_position = Vector3(actor_position.x, _shadow_ground_y, actor_position.z)


func _clear_blob_shadows() -> void:
	for entry: Dictionary in _shadow_entries:
		var shadow := entry.get("shadow") as MeshInstance3D
		if is_instance_valid(shadow):
			shadow.queue_free()
	_shadow_entries.clear()


func _update_render_priorities() -> void:
	if not is_instance_valid(camera):
		return
	var viewport := get_viewport()
	if viewport == null:
		return
	var viewport_height: float = maxf(float(viewport.get_visible_rect().size.y), 1.0)

	for entry: Dictionary in _sort_entries:
		var anchor := entry.get("anchor") as Node3D
		var sprite := entry.get("sprite") as AnimatedSprite3D
		if not is_instance_valid(anchor) or not is_instance_valid(sprite):
			continue
		var screen_position: Vector2 = camera.unproject_position(anchor.global_position)
		var normalized_y: float = clampf(screen_position.y / viewport_height, 0.0, 1.0)
		sprite.render_priority = int(round(lerpf(
			float(far_render_priority),
			float(near_render_priority),
			normalized_y
		)))


func _expand_actor_footprint(actor: Node3D) -> void:
	if actor.name == &"BeachCritter":
		return

	var collision_shape: CollisionShape3D = _find_primary_body_shape(actor)
	if collision_shape == null or collision_shape.shape == null:
		if actor.find_child("AnimatedSprite3D", true, false) == null:
			return
		if actor.find_child("InteractionArea", true, false) == null:
			return
		_create_fallback_body(actor)
		return

	var shape: Shape3D = collision_shape.shape.duplicate()
	if shape is CapsuleShape3D:
		var capsule := shape as CapsuleShape3D
		capsule.radius = maxf(capsule.radius, minimum_npc_radius)
		capsule.height = maxf(capsule.height, minimum_npc_height)
		collision_shape.shape = capsule
	elif shape is SphereShape3D:
		var sphere := shape as SphereShape3D
		sphere.radius = maxf(sphere.radius, minimum_npc_radius)
		collision_shape.shape = sphere


func _find_primary_body_shape(actor: Node3D) -> CollisionShape3D:
	var direct: Node = actor.get_node_or_null("BodyCollider/CollisionShape3D")
	if direct is CollisionShape3D:
		return direct as CollisionShape3D
	for node: Node in actor.find_children("*", "CollisionShape3D", true, false):
		var shape_node := node as CollisionShape3D
		if shape_node == null:
			continue
		var parent := shape_node.get_parent()
		if parent is PhysicsBody3D:
			return shape_node
	return null


func _create_fallback_body(actor: Node3D) -> void:
	var body := StaticBody3D.new()
	body.name = "PresentationBodyCollider"
	body.collision_layer = 1
	body.collision_mask = 1

	var collision := CollisionShape3D.new()
	collision.name = "CollisionShape3D"
	collision.position = Vector3(0.0, minimum_npc_height * 0.5, 0.0)

	var capsule := CapsuleShape3D.new()
	capsule.radius = minimum_npc_radius
	capsule.height = minimum_npc_height
	collision.shape = capsule

	body.add_child(collision)
	actor.add_child(body)
