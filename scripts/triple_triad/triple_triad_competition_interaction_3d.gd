extends Node3D
class_name TripleTriadCompetitionInteraction3D

signal competition_started(competition_id: StringName)
signal competition_resumed(competition_id: StringName)
signal competition_blocked(competition_id: StringName, reason: String)

@export var competition_id: StringName = &"regional_championship"
@export var enter_prompt: String = "K : Enter Card Tournament"
@export var resume_prompt: String = "K : Continue Card Tournament"
@export var locked_prompt: String = "Cards : Tournament Locked"

@onready var prompt_label: Label3D = $PromptLabel3D
@onready var interaction_area: Area3D = $InteractionArea

var _player_in_range: bool = false
var _game: Node = null


func _ready() -> void:
	prompt_label.visible = false
	interaction_area.body_entered.connect(_on_body_entered)
	interaction_area.body_exited.connect(_on_body_exited)


func interact() -> bool:
	var game: Node = _find_game()
	if game == null:
		competition_blocked.emit(
			competition_id,
			"Triple Triad backend unavailable."
		)
		return false

	var competitive: Dictionary = {}
	if game.has_method("get_competitive_snapshot"):
		competitive = game.call("get_competitive_snapshot")
	var active: Dictionary = {}
	var raw_active = competitive.get("active", {})
	if raw_active is Dictionary:
		active = raw_active

	if bool(active.get("active", false)):
		var active_id := StringName(str(active.get("competition_id", "")))
		if active_id != competition_id:
			competition_blocked.emit(
				competition_id,
				"Another card tournament is already active."
			)
			_refresh_prompt()
			return false
		if game.has_method("open_active_competition_match"):
			var resumed: bool = bool(
				game.call("open_active_competition_match")
			)
			if resumed:
				competition_resumed.emit(competition_id)
			return resumed
		return false

	if not game.has_method("get_competition_snapshot"):
		return false
	var snapshot: Dictionary = game.call(
		"get_competition_snapshot",
		competition_id
	)
	if not bool(snapshot.get("available", false)):
		competition_blocked.emit(
			competition_id,
			str(snapshot.get("reason", "Tournament locked."))
		)
		_refresh_prompt()
		return false

	if game.has_method("start_competition_and_open"):
		var started: bool = bool(
			game.call("start_competition_and_open", competition_id)
		)
		if started:
			competition_started.emit(competition_id)
		return started
	return false


func _input(event: InputEvent) -> void:
	if not _player_in_range:
		return
	var tree: SceneTree = get_tree()
	if tree == null or tree.paused:
		return
	if not _is_confirm(event):
		return
	interact()
	get_viewport().set_input_as_handled()


func _on_body_entered(body: Node) -> void:
	if not _is_player_body(body):
		return
	_player_in_range = true
	_refresh_prompt()
	prompt_label.visible = true


func _on_body_exited(body: Node) -> void:
	if not _is_player_body(body):
		return
	_player_in_range = false
	prompt_label.visible = false


func _refresh_prompt() -> void:
	var game: Node = _find_game()
	if game == null:
		prompt_label.text = locked_prompt
		return

	var competitive: Dictionary = {}
	if game.has_method("get_competitive_snapshot"):
		competitive = game.call("get_competitive_snapshot")
	var active: Dictionary = {}
	var raw_active = competitive.get("active", {})
	if raw_active is Dictionary:
		active = raw_active

	if bool(active.get("active", false)):
		if str(active.get("competition_id", "")) == String(competition_id):
			prompt_label.text = resume_prompt
		else:
			prompt_label.text = locked_prompt
		return

	var snapshot: Dictionary = {}
	if game.has_method("get_competition_snapshot"):
		snapshot = game.call("get_competition_snapshot", competition_id)
	if bool(snapshot.get("available", false)):
		prompt_label.text = enter_prompt
	else:
		prompt_label.text = locked_prompt


func _find_game() -> Node:
	if is_instance_valid(_game):
		return _game
	var tree: SceneTree = get_tree()
	if tree == null or tree.current_scene == null:
		return null
	_game = tree.current_scene.find_child("TripleTriadGame", true, false)
	if _game != null:
		_bind_game_signal("backend_state_changed")
		_bind_game_signal("competition_state_changed")
		_bind_game_signal("closed")
	return _game


func _bind_game_signal(signal_name: StringName) -> void:
	if _game == null or not _game.has_signal(signal_name):
		return
	var callback := Callable(self, "_on_game_state_changed")
	if not _game.is_connected(signal_name, callback):
		_game.connect(signal_name, callback)


func _on_game_state_changed(_arg = null) -> void:
	if _player_in_range:
		_refresh_prompt()


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
