extends Node
class_name WorldActorPresentation

## Runtime presentation/collision polish for billboard-style world actors.
##
## Actor scenes own ActorRoot/GroundPresentation/ShadowAnchor/WorldBlobShadow.
## The shared component owns feet alignment and the root-relative world shadow.
## Sprite ordering and existing collision-footprint behavior stay separate.

@export var world_root: Node3D
@export var player: CharacterBody3D
@export var camera: Camera3D

@export_category("Sprite Sorting")
@export_range(-120, -1, 1) var far_render_priority: int = -90
@export_range(1, 120, 1) var near_render_priority: int = 90

@export_category("NPC Footprints")
@export_range(0.12, 0.40, 0.01) var minimum_npc_radius: float = 0.24
@export_range(0.30, 0.80, 0.01) var minimum_npc_height: float = 0.52

const IGNORED_WORLD_ROOTS: Array[StringName] = [
	&"FishZone_V2",
	&"beach",
	&"DepthFloor",
	&"ShoreBlocker",
	&"BeachGatheringCircuit",
]

var _sort_entries: Array[Dictionary] = []


func _ready() -> void:
	process_priority = 200
	call_deferred("_setup_actor_presentation")


func _process(_delta: float) -> void:
	_update_render_priorities()


func _setup_actor_presentation() -> void:
	_sort_entries.clear()

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


func _register_actor(anchor: Node3D) -> void:
	var sprites: Array[Node] = anchor.find_children("*", "AnimatedSprite3D", true, false)
	if sprites.is_empty():
		return

	for node: Node in sprites:
		var sprite := node as AnimatedSprite3D
		if sprite == null:
			continue
		sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
		sprite.transparent = true
		sprite.no_depth_test = false
		_sort_entries.append({"anchor": anchor, "sprite": sprite})

	# GroundPresentation owns root-relative feet/shadow placement. Do not project
	# shadows onto a mesh node origin (which is not necessarily its surface).


func _update_render_priorities() -> void:
	if not is_instance_valid(camera):
		return
	var viewport := get_viewport()
	if viewport == null:
		return
	var viewport_height: float = maxf(float(viewport.get_visible_rect().size.y), 1.0)

	for entry: Dictionary in _sort_entries:
		var anchor_ref = entry.get("anchor")
		var sprite_ref = entry.get("sprite")
		if not is_instance_valid(anchor_ref) or not is_instance_valid(sprite_ref):
			continue
		var anchor := anchor_ref as Node3D
		var sprite := sprite_ref as AnimatedSprite3D
		var screen_position: Vector2 = camera.unproject_position(anchor.global_position)
		var normalized_y: float = clampf(screen_position.y / viewport_height, 0.0, 1.0)
		sprite.render_priority = int(round(lerpf(
			float(far_render_priority),
			float(near_render_priority),
			normalized_y
		)))


func _expand_actor_footprint(actor: Node3D) -> void:
	# Every instance keeps its authored crab-sized body, including renamed ones.
	if actor is BeachFishingCritter:
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
