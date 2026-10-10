extends Node
signal cast_availability_changed(available: bool)

const WorldInteractionRouterScript = preload("res://scripts/world_interaction_router.gd")

@export var game_mode: Node
@export var player: CharacterBody3D
@export var exploration_camera: Camera3D
@export var camera_rig: Node3D
@export var fish_zone: Area3D

var cast_available: bool = false

func _ready() -> void:
	player.camera_reference = exploration_camera
	game_mode.mode_changed.connect(_on_mode_changed)
	_on_mode_changed(game_mode.current_mode)
	var interaction_router := WorldInteractionRouterScript.new()
	interaction_router.name = "WorldInteractionRouter"
	interaction_router.configure(player, game_mode)
	add_child(interaction_router)

func _on_mode_changed(new_mode) -> void:
	set_active(new_mode == game_mode.Mode.EXPLORATION)

func _process(_delta: float) -> void:
	var new_cast_available := false

	if fish_zone != null and player != null:
		new_cast_available = fish_zone.can_player_fish(player)

	if new_cast_available == cast_available:
		return

	cast_available = new_cast_available
	cast_availability_changed.emit(cast_available)
	
func _unhandled_input(event: InputEvent) -> void:
	if not ModalInputOwnership.gameplay_accepts(self, event): return
	if game_mode == null:
		return

	if not game_mode.is_exploration():
		return

	if event.is_action_pressed("enter_fishing"):
		if fish_zone != null and fish_zone.can_player_fish(player):
			game_mode.enter_fishing(fish_zone)

	if event.is_action_pressed("cam_right"):
		camera_rig.rotate_quarter_turn(1)

	if event.is_action_pressed("cam_left"):
		camera_rig.rotate_quarter_turn(-1)

func set_active(active: bool) -> void:
	player.movement_enabled = active
	set_process(active)
	set_process_unhandled_input(active)

	if not active and cast_available:
		cast_available = false
		cast_availability_changed.emit(false)
