extends Node3D
class_name BeachGatheringNode3D
const GameplaySceneRoot = preload("res://scripts/gameplay_scene_root.gd")

signal gathered(
	material_id: StringName,
	amount: int,
	new_count: int
)

@export var material_id: StringName = &"driftwood"
@export_range(1, 9, 1) var amount: int = 1
@export var one_shot_per_scene: bool = true
@export var interaction_prompt: String = "K : Gather"
@export var depleted_prompt: String = "Gathered"
@export var circuit_id: StringName = &""
@export var circuit_node_key: StringName = &""

@export_category("Presentation")
@export var presentation_texture: Texture2D

@onready var prompt_label: Label3D = $PromptLabel3D
@onready var interaction_area: Area3D = $InteractionArea
@onready var placeholder_mesh: MeshInstance3D = $PlaceholderMesh
@onready var gather_sprite: Sprite3D = $GroundPresentation/VisualAnchor/GatherSprite3D

var _player_in_range: bool = false
var _depleted: bool = false
var _inventory: BeachGatheringInventory = null
var _crafting_service: BeachCraftingService = null


func _ready() -> void:
	add_to_group(&"world_interaction_targets")
	prompt_label.visible = false
	interaction_area.body_entered.connect(_on_body_entered)
	interaction_area.body_exited.connect(_on_body_exited)
	call_deferred("_refresh_presentation")


func is_world_interaction_available(event: InputEvent) -> bool:
	return _player_in_range and not _depleted and _is_confirm(event)


func interact_from_world(event: InputEvent) -> void:
	if not _player_in_range or _depleted:
		return
	var tree: SceneTree = get_tree()
	if tree == null or tree.paused:
		return
	if not _is_confirm(event):
		return
	gather()
	get_viewport().set_input_as_handled()


func gather() -> Dictionary:
	var gathered_amount: int = maxi(1, amount)
	var result: Dictionary = {}

	var services := _find_session_services()
	if (
		services != null
		and services.has_method("grant_beach_material")
	):
		result = services.call(
			"grant_beach_material",
			material_id,
			gathered_amount
		)
	else:
		# Compatibility fallback for isolated/debug scenes that do not run the
		# full FishingSessionServices item backbone.
		var inventory := _find_inventory()
		if inventory == null:
			return {
				"success": false,
				"reason": "gathering_inventory_unavailable",
			}
		var fallback_count: int = inventory.grant(
			material_id,
			gathered_amount,
			true
		)
		result = {
			"success": true,
			"material_id": String(material_id),
			"amount": gathered_amount,
			"new_count": fallback_count,
		}

	if not bool(result.get("success", false)):
		return result

	var next_count: int = int(
		result.get("new_count", 0)
	)
	if one_shot_per_scene:
		_depleted = true

	gathered.emit(
		material_id,
		gathered_amount,
		next_count
	)
	_notify_gathering_feedback(
		gathered_amount,
		next_count
	)
	_refresh_presentation()
	return result


func _refresh_presentation() -> void:
	var display_name: String = String(material_id)
	var service := _find_crafting_service()
	if service != null:
		var material: BeachMaterialDefinition = (
			service.get_material_definition(material_id)
		)
		if material != null:
			display_name = material.display_name
			_apply_placeholder_tint(material.visual_tint)

	_apply_authored_sprite()
	var has_authored_sprite: bool = (
		gather_sprite != null
		and gather_sprite.texture != null
	)
	if placeholder_mesh != null:
		placeholder_mesh.visible = (
			not _depleted
			and not has_authored_sprite
		)
	if gather_sprite != null:
		gather_sprite.visible = (
			not _depleted
			and has_authored_sprite
		)

	# Old-school interaction: the resource itself is the affordance.
	# Never display a floating "Press K / Gather" prompt.
	prompt_label.visible = false


func _apply_authored_sprite() -> void:
	if gather_sprite == null:
		return
	gather_sprite.texture = presentation_texture
	var presentation := $GroundPresentation as GroundPresentation
	presentation.apply_profile()
	# Ground pickups are decals/objects on the beach plane, never upright
	# billboards. Keep them a few millimetres above the authored node origin
	# to avoid z-fighting while still reading as physically on the sand.
	gather_sprite.billboard = 0
	# Ground objects share the transparent queue with billboard bodies. Draw
	# before the global character priority range (-90..90), without writing
	# opaque/scissor depth that would cut holes in those bodies.
	gather_sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
	gather_sprite.transparent = true
	gather_sprite.no_depth_test = false
	gather_sprite.render_priority = -110
	gather_sprite.rotation_degrees = Vector3(
		-90.0,
		presentation.profile.ground_yaw_degrees,
		0.0
	)


func configure_circuit(
	new_circuit_id: StringName,
	new_node_key: StringName
) -> void:
	circuit_id = new_circuit_id
	circuit_node_key = new_node_key


func reset_gather_node() -> void:
	_depleted = false
	_refresh_presentation()


func is_depleted() -> bool:
	return _depleted


func _notify_gathering_feedback(
	gathered_amount: int,
	new_count: int
) -> void:
	var services := _find_session_services()
	if services == null:
		return
	if not services.has_method("notify_beach_material_gathered"):
		return
	services.call(
		"notify_beach_material_gathered",
		material_id,
		gathered_amount,
		new_count,
		circuit_id,
		circuit_node_key
	)


func _apply_placeholder_tint(color: Color) -> void:
	if placeholder_mesh == null:
		return
	var material = placeholder_mesh.material_override
	if material is StandardMaterial3D:
		var local_material := (
			material as StandardMaterial3D
		).duplicate() as StandardMaterial3D
		local_material.albedo_color = color
		placeholder_mesh.material_override = local_material


func _find_inventory() -> BeachGatheringInventory:
	if is_instance_valid(_inventory):
		return _inventory
	var services := _find_session_services()
	if services == null:
		return null
	var candidate = services.get("beach_gathering_inventory")
	if candidate is BeachGatheringInventory:
		_inventory = candidate
	return _inventory


func _find_crafting_service() -> BeachCraftingService:
	if is_instance_valid(_crafting_service):
		return _crafting_service
	var services := _find_session_services()
	if services == null:
		return null
	var candidate = services.get("beach_crafting_service")
	if candidate is BeachCraftingService:
		_crafting_service = candidate
	return _crafting_service


func _find_session_services() -> Node:
	var tree := get_tree()
	if tree == null:
		return null
	var services := tree.root.get_node_or_null(
		"FishingSessionServices"
	)
	if services != null:
		return services

	var scene := GameplaySceneRoot.resolve(tree)
	if scene == null:
		return null
	var fishing := scene.find_child("Fishing", true, false)
	if fishing != null:
		var candidate = fishing.get("session_services")
		if candidate is Node:
			return candidate
	return null


func _on_body_entered(body: Node) -> void:
	if not _is_player_body(body):
		return
	_player_in_range = true
	_refresh_presentation()
	prompt_label.visible = false


func _on_body_exited(body: Node) -> void:
	if not _is_player_body(body):
		return
	_player_in_range = false
	prompt_label.visible = false


func _is_player_body(body: Node) -> bool:
	return (
		body != null
		and body is CharacterBody3D
		and body.name == "CharacterBody3D"
	)


func _is_confirm(event: InputEvent) -> bool:
	if not (event is InputEventKey):
		return false
	var key_event := event as InputEventKey
	return (
		key_event.pressed
		and not key_event.echo
		and (
			key_event.keycode == KEY_K
			or key_event.physical_keycode == KEY_K
			or key_event.keycode == KEY_ENTER
			or key_event.physical_keycode == KEY_ENTER
		)
	)
