extends Node3D

@export var economy_context: MerchantEconomyContext
@export var trader_name: String = "Manillo trader (development stand-in)"
@onready var area: Area3D = $InteractionArea
var _menu: Node

func _ready() -> void:
	add_to_group(&"world_interaction_targets")
	add_to_group(&"world_economy_sources")
	$PromptLabel3D.visible = true
	$PromptLabel3D.text = trader_name + "\nK: Trade fish"

func is_world_interaction_available(event: InputEvent) -> bool:
	if not (event is InputEventKey) or not event.pressed or event.echo or event.keycode not in [KEY_K, KEY_ENTER]:
		return false
	if not get_node("/root/WorldLocations").context_belongs_here(economy_context, self):
		return false
	for body in area.get_overlapping_bodies():
		if body is CharacterBody3D:
			return true
	return false

func interact_from_world(event: InputEvent) -> void:
	if not is_world_interaction_available(event):
		return
	_menu = get_tree().current_scene.find_child("FishingEconomyMenu", true, false)
	if _menu != null:
		_menu.open_merchant_menu(economy_context, self, _menu.MODE_TRADE)

func _exit_tree() -> void:
	if is_instance_valid(_menu):
		_menu.close_for_merchant(self)
