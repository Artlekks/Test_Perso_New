extends Node3D
class_name TripleTriadHarborRequestBoard

const WorldRequestStateScript = preload("res://scripts/quests/world_request_state.gd")
const WorldRequestRegistryScript = preload("res://scripts/quests/world_request_registry.gd")
const WorldObjectiveTrackerScene = preload("res://actors/WorldObjectiveTracker.tscn")

signal request_accepted(request_id: StringName)
signal request_reward_claimed(result: Dictionary)
signal request_reward_unavailable(result: Dictionary)

@export var request_id: StringName = &"beach_demo_harbor_errand_01"
@export var required_opponent_id: StringName = &"beach_trader"
@export var speaker_name: String = "Harbor Request Board"

@export_category("Request Presentation")
@export var request_title: String = "Harbor Request"
@export var active_objective_text: String = "Defeat Beach Trader in a card duel."
@export var ready_objective_text: String = "Return to the Harbor Request Board."
@export var completed_objective_text: String = "Request completed."

@export_category("World Prompts")
@export var locked_prompt: String = "Cards : Locked"
@export var available_prompt: String = "K : Read Request"
@export var accepted_prompt: String = "K : Request"
@export var turn_in_prompt: String = "K : Turn In Request"
@export var complete_prompt: String = "K : Request Complete"
@export var source_complete_prompt: String = "K : Request Complete"

@onready var prompt_label: Label3D = $PromptLabel3D
@onready var interaction_area: Area3D = $InteractionArea
@onready var reward_adapter: Node = $QuestRewardAdapter
@onready var dialogue_bridge: DialogueNPCBridge = $DialogueBridge as DialogueNPCBridge
@onready var request_marker: Node = $RequestMarker

var _player_in_range: bool = false
var _game: Node = null
var _claim_in_progress: bool = false
var _objective_tracker: Node = null


func _ready() -> void:
	_apply_catalog_definition()
	prompt_label.visible = false
	interaction_area.body_entered.connect(_on_body_entered)
	interaction_area.body_exited.connect(_on_body_exited)
	if dialogue_bridge != null:
		dialogue_bridge.choice_made.connect(_on_dialogue_choice_made)
	call_deferred("_refresh_state")


func _apply_catalog_definition() -> void:
	var definition := WorldRequestRegistryScript.definition_snapshot(request_id)
	if definition.is_empty():
		return
	request_title = str(definition.get("title", request_title))
	active_objective_text = str(definition.get("active_objective", active_objective_text))
	ready_objective_text = str(definition.get("ready_objective", ready_objective_text))
	completed_objective_text = str(definition.get("completed_objective", completed_objective_text))
	var raw_objective_metadata = definition.get("objective_metadata", {})
	if raw_objective_metadata is Dictionary:
		var objective_metadata: Dictionary = raw_objective_metadata as Dictionary
		var opponent_id := StringName(str(objective_metadata.get("opponent_id", required_opponent_id)))
		if opponent_id != &"":
			required_opponent_id = opponent_id
	if reward_adapter != null:
		var reward_source_id := StringName(str(definition.get("reward_source_id", &"")))
		var reward_event_id := StringName(str(definition.get("reward_event_id", &"")))
		if reward_source_id != &"":
			reward_adapter.set("source_id", reward_source_id)
		if reward_event_id != &"":
			reward_adapter.set("quest_event_id", reward_event_id)


func _exit_tree() -> void:
	if is_instance_valid(_objective_tracker) and _objective_tracker.has_method("remove_request"):
		_objective_tracker.call("remove_request", request_id)


func _input(event: InputEvent) -> void:
	if not _player_in_range or _claim_in_progress:
		return
	var tree: SceneTree = get_tree()
	if tree == null or tree.paused:
		return
	if not _is_confirm(event):
		return
	if dialogue_bridge != null:
		if dialogue_bridge.has_pending_interaction():
			return

	var game: Node = _find_game()
	var state: int = _resolve_request_state(game)
	if state == WorldRequestStateScript.State.LOCKED:
		return

	if not _start_state_dialogue(state):
		_fallback_interaction(state)
	_refresh_state()
	get_viewport().set_input_as_handled()


func _start_state_dialogue(state: int) -> bool:
	if dialogue_bridge == null:
		return false
	match state:
		WorldRequestStateScript.State.AVAILABLE:
			return dialogue_bridge.start_choice_prompt(
				&"harbor_request_available",
				&"request_available",
				&"harbor_request_board",
				speaker_name,
				"A harbor request is pinned here: defeat Beach Trader in a card duel.",
				build_available_choices(),
				null,
				true,
				{"request_id": String(request_id)}
			)
		WorldRequestStateScript.State.ACCEPTED:
			return dialogue_bridge.start_choice_prompt(
				&"harbor_request_accepted",
				&"request_accepted",
				&"harbor_request_board",
				speaker_name,
				"The request is still open.",
				build_accepted_choices(),
				null,
				true,
				{"request_id": String(request_id)}
			)
		WorldRequestStateScript.State.READY_TO_TURN_IN:
			return dialogue_bridge.start_choice_prompt(
				&"harbor_request_ready",
				&"request_ready",
				&"harbor_request_board",
				speaker_name,
				"Beach Trader has been defeated. The request is ready to turn in.",
				build_ready_choices(),
				null,
				true,
				{"request_id": String(request_id)}
			)
		WorldRequestStateScript.State.COMPLETED:
			return dialogue_bridge.start_choice_prompt(
				&"harbor_request_completed",
				&"request_completed",
				&"harbor_request_board",
				speaker_name,
				"Request complete. The harbor considers the errand settled.",
				build_completed_choices(),
				null,
				true,
				{"request_id": String(request_id)}
			)
		WorldRequestStateScript.State.SOURCE_COMPLETE:
			return _start_lines(
				&"harbor_request_source_complete",
				&"request_source_complete",
				[
					"There is no unclaimed Harbor Errands card left to award.",
					"The request has nothing further to offer you.",
				]
			)
	return false


func _on_dialogue_choice_made(
	action_id: StringName,
	choice_id: StringName,
	_choice_metadata: Dictionary
) -> void:
	if choice_id == &"journal":
		call_deferred("_open_request_journal")
		_refresh_state()
		return

	match action_id:
		&"request_available":
			if choice_id == &"accept":
				_handle_accept_request()
		&"request_accepted":
			if choice_id == &"review":
				_show_request_details()
		&"request_ready":
			if choice_id == &"turn_in":
				_handle_turn_in()
	_refresh_state()


func _handle_accept_request() -> void:
	var game: Node = _find_game()
	if game == null or not _mark_accepted(game):
		_start_lines(
			&"harbor_request_accept_failed",
			&"request_accept_failed",
			["The request could not be recorded right now."]
		)
		return

	request_accepted.emit(request_id)
	var lines: Array[String] = [
		"Request accepted.",
	]
	if _objective_complete(game):
		lines.append(
			"You've already defeated Beach Trader. The request is ready to turn in."
		)
	else:
		lines.append(
			"Defeat Beach Trader in a card duel, then return here for the reward."
		)
	_start_lines(
		&"harbor_request_accept_confirm",
		&"request_accept_confirm",
		lines
	)


func _show_request_details() -> void:
	_start_lines(
		&"harbor_request_details",
		&"request_details",
		[
			"Request: defeat Beach Trader in a card duel.",
			"Once you've won at least once, return to this board to turn the request in.",
		]
	)


func _handle_turn_in() -> void:
	if _claim_in_progress:
		return
	var game: Node = _find_game()
	if _resolve_request_state(game) != WorldRequestStateScript.State.READY_TO_TURN_IN:
		_refresh_state()
		return

	_claim_in_progress = true
	var raw_result = reward_adapter.call("grant_reward")
	_claim_in_progress = false

	var result: Dictionary = {}
	if raw_result is Dictionary:
		result = (raw_result as Dictionary).duplicate(true)
	else:
		result = {
			"success": false,
			"reason": "invalid_quest_reward_result",
		}

	if bool(result.get("success", false)):
		request_reward_claimed.emit(result.duplicate(true))
		var reward_name: String = str(
			result.get("display_name", result.get("card_id", "card reward"))
		)
		_start_lines(
			&"harbor_request_reward_claimed",
			&"request_reward_claimed",
			[
				"Request complete.",
				"Reward received: %s." % reward_name,
			]
		)
	else:
		request_reward_unavailable.emit(result.duplicate(true))
		_show_reward_failure(str(result.get("reason", "reward_unavailable")))
	_refresh_state()


func _show_reward_failure(reason: String) -> void:
	var message := "The request reward could not be delivered right now."
	match reason:
		"source_complete":
			message = "There is no unclaimed Harbor Errands card left to award."
		"event_already_claimed":
			message = "This request has already been turned in."
		"duel_rank_too_low":
			message = "The reward is not available at your current duel rank."
	_start_lines(
		&"harbor_request_reward_unavailable",
		&"request_reward_unavailable",
		[message]
	)


func _start_lines(
	dialogue_id: StringName,
	action_id: StringName,
	texts: Array
) -> bool:
	if dialogue_bridge == null or texts.is_empty():
		return false
	var lines: Array = []
	for raw_text in texts:
		lines.append({
			"speaker_id": &"harbor_request_board",
			"speaker_name": speaker_name,
			"text": str(raw_text),
		})
	return dialogue_bridge.start_lines(
		dialogue_id,
		action_id,
		lines,
		true,
		{"request_id": String(request_id)}
	)


func _fallback_interaction(state: int) -> void:
	# Dialogue presentation must never strand an otherwise valid request. If the
	# shared dialogue service is unavailable, preserve the minimum legacy path.
	var game: Node = _find_game()
	match state:
		WorldRequestStateScript.State.AVAILABLE:
			if game != null and _mark_accepted(game):
				request_accepted.emit(request_id)
		WorldRequestStateScript.State.READY_TO_TURN_IN:
			_handle_turn_in()


func _resolve_request_state(game: Node) -> int:
	return WorldRequestStateScript.resolve(
		_cards_unlocked(game),
		_is_accepted(game),
		_objective_complete(game),
		_is_reward_claimed(),
		_source_complete(game)
	)


func _cards_unlocked(game: Node) -> bool:
	if game == null:
		return false
	if game.has_method("is_card_game_unlocked"):
		return bool(game.call("is_card_game_unlocked"))
	return false


func _is_reward_claimed() -> bool:
	return (
		reward_adapter != null
		and reward_adapter.has_method("is_claimed")
		and bool(reward_adapter.call("is_claimed"))
	)


func _acceptance_counter_id() -> StringName:
	return StringName("request_accepted:%s" % String(request_id))


func _is_accepted(game: Node) -> bool:
	if game == null or not game.has_method("get_world_reward_delivery_snapshot"):
		return false
	var raw_snapshot = game.call("get_world_reward_delivery_snapshot")
	if not (raw_snapshot is Dictionary):
		return false
	var snapshot: Dictionary = raw_snapshot
	var raw_counters = snapshot.get("counters", {})
	if not (raw_counters is Dictionary):
		return false
	return int(
		(raw_counters as Dictionary).get(
			String(_acceptance_counter_id()),
			0
		)
	) > 0


func _mark_accepted(game: Node) -> bool:
	if game == null:
		return false
	if _is_accepted(game):
		return true
	if not game.has_method("advance_world_reward_counter"):
		return false
	return int(
		game.call(
			"advance_world_reward_counter",
			_acceptance_counter_id()
		)
	) > 0


func _objective_complete(game: Node) -> bool:
	if game == null or not game.has_method("get_opponent_snapshot"):
		return false
	var raw_snapshot = game.call(
		"get_opponent_snapshot",
		required_opponent_id
	)
	if not (raw_snapshot is Dictionary):
		return false
	var snapshot: Dictionary = raw_snapshot
	return bool(snapshot.get("beaten_before", false))


func _source_complete(game: Node) -> bool:
	if game == null or not game.has_method("get_source_completion_snapshot"):
		return false
	var source_id: String = str(reward_adapter.get("source_id"))
	for raw_source in game.call("get_source_completion_snapshot"):
		if not (raw_source is Dictionary):
			continue
		var source: Dictionary = raw_source
		if (
			str(source.get("source_type", "")) == "quest_reward"
			and str(source.get("source_id", "")) == source_id
		):
			return bool(source.get("complete", false))
	return false


func _on_body_entered(body: Node) -> void:
	if not _is_player_body(body):
		return
	_player_in_range = true
	_refresh_state()
	prompt_label.visible = true


func _on_body_exited(body: Node) -> void:
	if not _is_player_body(body):
		return
	_player_in_range = false
	prompt_label.visible = false
	if dialogue_bridge != null:
		dialogue_bridge.cancel_pending()


func _refresh_state() -> void:
	var state: int = _resolve_request_state(_find_game())
	match state:
		WorldRequestStateScript.State.LOCKED:
			prompt_label.text = locked_prompt
		WorldRequestStateScript.State.AVAILABLE:
			prompt_label.text = available_prompt
		WorldRequestStateScript.State.ACCEPTED:
			prompt_label.text = accepted_prompt
		WorldRequestStateScript.State.READY_TO_TURN_IN:
			prompt_label.text = turn_in_prompt
		WorldRequestStateScript.State.COMPLETED:
			prompt_label.text = complete_prompt
		WorldRequestStateScript.State.SOURCE_COMPLETE:
			prompt_label.text = source_complete_prompt

	_sync_request_presentation(state)


func _sync_request_presentation(state: int) -> void:
	var state_id: StringName = WorldRequestStateScript.state_id(state)
	if request_marker != null and request_marker.has_method("set_request_state"):
		request_marker.call("set_request_state", state_id)

	if state == WorldRequestStateScript.State.ACCEPTED:
		var tracker := _ensure_objective_tracker()
		if tracker != null:
			_register_tracker_snapshot(tracker, state_id, active_objective_text)
		return

	if state == WorldRequestStateScript.State.READY_TO_TURN_IN:
		var tracker := _ensure_objective_tracker()
		if tracker != null:
			_register_tracker_snapshot(tracker, state_id, ready_objective_text)
		return

	if state == WorldRequestStateScript.State.COMPLETED:
		var tracker := _ensure_objective_tracker()
		if tracker != null:
			_register_tracker_snapshot(tracker, state_id, completed_objective_text)
		return

	if is_instance_valid(_objective_tracker) and _objective_tracker.has_method("remove_request"):
		_objective_tracker.call("remove_request", request_id)


func _register_tracker_snapshot(
	tracker: Node,
	state_id: StringName,
	objective_text: String
) -> void:
	var metadata := {"source": "harbor_request_board"}
	if tracker.has_method("register_request_state"):
		tracker.call(
			"register_request_state",
			request_id,
			objective_text,
			state_id,
			metadata
		)
		return
	tracker.call(
		"register_request",
		request_id,
		request_title,
		objective_text,
		state_id,
		metadata
	)


func _ensure_objective_tracker() -> Node:
	if is_instance_valid(_objective_tracker):
		return _objective_tracker
	if not is_inside_tree():
		return null
	var tree := get_tree()
	if tree == null or tree.current_scene == null:
		return null

	var existing := tree.current_scene.find_child(
		"WorldObjectiveTracker",
		true,
		false
	)
	if existing != null and existing.has_method("register_request"):
		_objective_tracker = existing
		return _objective_tracker

	var tracker = WorldObjectiveTrackerScene.instantiate()
	if tracker == null:
		return null
	tree.current_scene.add_child(tracker)
	_objective_tracker = tracker
	return _objective_tracker


func _open_request_journal() -> void:
	var tracker := _ensure_objective_tracker()
	if tracker == null or not tracker.has_method("open_journal"):
		return
	tracker.call("open_journal")


func _find_game() -> Node:
	if is_instance_valid(_game):
		return _game
	if not is_inside_tree():
		return null
	var tree: SceneTree = get_tree()
	if tree == null or tree.current_scene == null:
		return null
	_game = tree.current_scene.find_child("TripleTriadGame", true, false)
	if _game != null and _game.has_signal("backend_state_changed"):
		var callback := Callable(self, "_on_backend_state_changed")
		if not _game.is_connected("backend_state_changed", callback):
			_game.connect("backend_state_changed", callback)
	return _game


func _on_backend_state_changed(_reason: String) -> void:
	# Request markers/objective tracking must update even when the player is not
	# standing beside the board. The interaction prompt still remains range-bound.
	_refresh_state()


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


static func build_available_choices() -> Array:
	return [
		{"choice_id": &"accept", "text": "Accept Request"},
		{"choice_id": &"journal", "text": "View Requests"},
		{"choice_id": &"later", "text": "Maybe Later"},
	]


static func build_accepted_choices() -> Array:
	return [
		{"choice_id": &"review", "text": "Review Request"},
		{"choice_id": &"journal", "text": "View Requests"},
		{"choice_id": &"leave", "text": "Leave"},
	]


static func build_ready_choices() -> Array:
	return [
		{"choice_id": &"turn_in", "text": "Turn In"},
		{"choice_id": &"journal", "text": "View Requests"},
		{"choice_id": &"not_yet", "text": "Not Yet"},
	]


static func build_completed_choices() -> Array:
	return [
		{"choice_id": &"journal", "text": "View Requests"},
		{"choice_id": &"leave", "text": "Leave"},
	]
