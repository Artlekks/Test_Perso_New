extends Node
class_name CardMakerFishingRequestSource
const GameplaySceneRoot = preload("res://scripts/gameplay_scene_root.gd")

## Fishing-backed request composed under the existing Card Maker NPC.
##
## The request source owns presentation/routing only. Acceptance persists through
## WorldRequestProgressStore, catch truth comes from FishingJournalService through
## FishingCatchCountRequestObjective, and the reward remains behind the existing
## TripleTriadQuestRewardAdapter/world-reward ledger.

const WorldRequestStateScript = preload("res://scripts/quests/world_request_state.gd")
const WorldRequestRegistryScript = preload("res://scripts/quests/world_request_registry.gd")
const WorldRequestProgressStoreScript = preload("res://scripts/quests/world_request_progress_store.gd")
const WorldObjectiveTrackerScene = preload("res://actors/WorldObjectiveTracker.tscn")

signal return_to_services_requested
signal idle_requested

const PARENT_ACTION_CHOOSE_SERVICE: StringName = &"choose_card_maker_service"
const CHOICE_REQUEST: StringName = &"request"
const CHOICE_JOURNAL: StringName = &"journal"

const ACTION_REQUEST_AVAILABLE: StringName = &"card_maker_fishing_request_available"
const ACTION_REQUEST_ACCEPTED: StringName = &"card_maker_fishing_request_accepted"
const ACTION_REQUEST_READY: StringName = &"card_maker_fishing_request_ready"
const ACTION_REQUEST_ACCEPT_CONFIRM: StringName = &"card_maker_fishing_request_accept_confirm"
const ACTION_REQUEST_REVIEW: StringName = &"card_maker_fishing_request_review"
const ACTION_REQUEST_REWARD: StringName = &"card_maker_fishing_request_reward"
const ACTION_REQUEST_COMPLETED: StringName = &"card_maker_fishing_request_completed"
const ACTION_REQUEST_FAILURE: StringName = &"card_maker_fishing_request_failure"

@export var request_id: StringName = &"beach_demo_card_maker_sea_bass_01"
@export var request_title: String = "Coastal Catch"
@export var speaker_name: String = "Card Maker"
@export var speaker_id: StringName = &"card_maker"

@export_category("Objective")
@export var required_species_id: StringName = &"sea_bass"
@export var required_species_name: String = "Sea Bass"
@export var required_catch_count: int = 3
@export var active_objective_template: String = "Catch Sea Bass along the coast. %d/%d recorded."
@export var ready_objective_text: String = "Return to the Card Maker after recording 3 Sea Bass catches."
@export var completed_objective_text: String = "Coastal Catch completed."

@export_category("Choice Text")
@export var available_choice_text: String = "Coastal Catch"
@export var accepted_choice_text: String = "Review Coastal Catch"
@export var ready_choice_text: String = "Turn In Coastal Catch"
@export var completed_choice_text: String = "Coastal Catch Complete"
@export var journal_choice_text: String = "View Requests"

@onready var reward_adapter: Node = $QuestRewardAdapter
@onready var catch_objective: FishingCatchCountRequestObjective = $CatchObjective
@onready var request_marker: Node = get_node_or_null("../RequestMarker")

var _dialogue_bridge: DialogueNPCBridge = null
var _portrait: Texture2D = null
var _fishing_journal: Node = null
var _player_item_inventory: Node = null
var _objective_tracker: Node = null
var _card_game: Node = null
var _claim_in_progress: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_apply_catalog_definition()
	catch_objective.species_id = required_species_id
	catch_objective.required_count = required_catch_count
	catch_objective.progress_changed.connect(_on_objective_progress_changed)
	call_deferred("_bind_dependencies")


func _apply_catalog_definition() -> void:
	var definition := WorldRequestRegistryScript.definition_snapshot(request_id)
	if definition.is_empty():
		return
	request_title = str(definition.get("title", request_title))
	active_objective_template = str(definition.get("active_objective", active_objective_template))
	ready_objective_text = str(definition.get("ready_objective", ready_objective_text))
	completed_objective_text = str(definition.get("completed_objective", completed_objective_text))
	var raw_metadata = definition.get("objective_metadata", {})
	if raw_metadata is Dictionary:
		var objective_metadata: Dictionary = raw_metadata as Dictionary
		var species_id := StringName(str(objective_metadata.get("species_id", required_species_id)))
		if species_id != &"":
			required_species_id = species_id
		var species_name := str(objective_metadata.get("species_name", required_species_name))
		if not species_name.strip_edges().is_empty():
			required_species_name = species_name
		required_catch_count = maxi(
			1,
			int(objective_metadata.get("required_count", required_catch_count))
		)
	if reward_adapter != null:
		var reward_source_id := StringName(str(definition.get("reward_source_id", &"")))
		var reward_event_id := StringName(str(definition.get("reward_event_id", &"")))
		if reward_source_id != &"":
			reward_adapter.set("source_id", reward_source_id)
		if reward_event_id != &"":
			reward_adapter.set("quest_event_id", reward_event_id)


func configure(dialogue_bridge: DialogueNPCBridge, portrait: Texture2D) -> void:
	if _dialogue_bridge != dialogue_bridge:
		_disconnect_dialogue_bridge()
		_dialogue_bridge = dialogue_bridge
		_connect_dialogue_bridge()
	_portrait = portrait
	_bind_dependencies()
	_refresh_request_state()


func augment_service_choices(base_choices: Array) -> Array:
	var choices: Array = base_choices.duplicate(true)
	var state := _resolve_request_state()
	var state_id := WorldRequestStateScript.state_id(state)
	var request_text := main_choice_text_for_state(
		state_id,
		available_choice_text,
		accepted_choice_text,
		ready_choice_text,
		completed_choice_text
	)
	if not request_text.is_empty():
		var request_choice := {
			"choice_id": CHOICE_REQUEST,
			"text": request_text,
			"enabled": true,
			"metadata": {
				"route": "request",
				"request_id": String(request_id),
				"state_id": String(state_id),
			},
		}
		# Keep the workshop as the first Card Maker service, then the request.
		var insert_index := mini(1, choices.size())
		choices.insert(insert_index, request_choice)

	if _journal_available():
		var journal_choice := {
			"choice_id": CHOICE_JOURNAL,
			"text": journal_choice_text,
			"enabled": true,
			"metadata": {"route": "request_journal"},
		}
		var leave_index := _find_choice_index(choices, &"leave")
		if leave_index < 0:
			choices.append(journal_choice)
		else:
			choices.insert(leave_index, journal_choice)
	return choices


func refresh() -> void:
	_bind_dependencies()
	_refresh_request_state()


func get_state_id() -> StringName:
	return WorldRequestStateScript.state_id(_resolve_request_state())


func get_progress_snapshot() -> Dictionary:
	if catch_objective == null:
		return FishingCatchCountRequestObjective.progress_snapshot_for_count(
			0,
			required_catch_count
		)
	return catch_objective.get_progress_snapshot()


static func main_choice_text_for_state(
	state_id: StringName,
	available_text: String = "Coastal Catch",
	accepted_text: String = "Review Coastal Catch",
	ready_text: String = "Turn In Coastal Catch",
	completed_text: String = "Coastal Catch Complete"
) -> String:
	match state_id:
		&"available":
			return available_text
		&"accepted":
			return accepted_text
		&"ready_to_turn_in":
			return ready_text
		&"completed":
			return completed_text
	return ""


static func build_available_choices() -> Array:
	return [
		{"choice_id": &"accept", "text": "Accept Challenge"},
		{"choice_id": &"later", "text": "Not Now"},
	]


static func build_accepted_choices() -> Array:
	return [
		{"choice_id": &"review", "text": "Review Progress"},
		{"choice_id": &"back", "text": "Back"},
	]


static func build_ready_choices() -> Array:
	return [
		{"choice_id": &"turn_in", "text": "Claim Reward"},
		{"choice_id": &"not_yet", "text": "Not Yet"},
	]


func _bind_dependencies() -> bool:
	var services := _find_session_services()
	if services == null:
		return false
	var raw_journal = services.get("journal_service")
	var raw_player = services.get("player_item_inventory")
	if raw_journal is Node:
		_fishing_journal = raw_journal as Node
	if raw_player is Node:
		_player_item_inventory = raw_player as Node
	if _fishing_journal != null and catch_objective != null:
		catch_objective.configure(_fishing_journal)
	_find_card_game()
	return _fishing_journal != null and _player_item_inventory != null


func _connect_dialogue_bridge() -> void:
	if _dialogue_bridge == null:
		return
	if not _dialogue_bridge.choice_made.is_connected(_on_dialogue_choice_made):
		_dialogue_bridge.choice_made.connect(_on_dialogue_choice_made)
	if not _dialogue_bridge.interaction_finished.is_connected(_on_dialogue_interaction_finished):
		_dialogue_bridge.interaction_finished.connect(_on_dialogue_interaction_finished)


func _disconnect_dialogue_bridge() -> void:
	if _dialogue_bridge == null or not is_instance_valid(_dialogue_bridge):
		_dialogue_bridge = null
		return
	if _dialogue_bridge.choice_made.is_connected(_on_dialogue_choice_made):
		_dialogue_bridge.choice_made.disconnect(_on_dialogue_choice_made)
	if _dialogue_bridge.interaction_finished.is_connected(_on_dialogue_interaction_finished):
		_dialogue_bridge.interaction_finished.disconnect(_on_dialogue_interaction_finished)
	_dialogue_bridge = null


func _on_dialogue_choice_made(
	action_id: StringName,
	choice_id: StringName,
	_choice_metadata: Dictionary
) -> void:
	if action_id == PARENT_ACTION_CHOOSE_SERVICE:
		match choice_id:
			CHOICE_REQUEST:
				call_deferred("_start_request_dialogue")
			CHOICE_JOURNAL:
				call_deferred("_open_request_journal")
		return

	match action_id:
		ACTION_REQUEST_AVAILABLE:
			if choice_id == &"accept":
				call_deferred("_handle_accept")
			elif choice_id == &"later":
				return_to_services_requested.emit()
		ACTION_REQUEST_ACCEPTED:
			if choice_id == &"review":
				call_deferred("_show_progress_details")
			elif choice_id == &"back":
				return_to_services_requested.emit()
		ACTION_REQUEST_READY:
			if choice_id == &"turn_in":
				call_deferred("_handle_turn_in")
			elif choice_id == &"not_yet":
				return_to_services_requested.emit()


func _on_dialogue_interaction_finished(
	action_id: StringName,
	reason: StringName
) -> void:
	if reason == &"choice_selected":
		return
	if action_id in [
		ACTION_REQUEST_ACCEPT_CONFIRM,
		ACTION_REQUEST_REVIEW,
		ACTION_REQUEST_REWARD,
		ACTION_REQUEST_COMPLETED,
		ACTION_REQUEST_FAILURE,
	]:
		if reason == &"completed":
			return_to_services_requested.emit()
		else:
			idle_requested.emit()
		return
	if action_id in [
		ACTION_REQUEST_AVAILABLE,
		ACTION_REQUEST_ACCEPTED,
		ACTION_REQUEST_READY,
	]:
		idle_requested.emit()


func _start_request_dialogue() -> void:
	_bind_dependencies()
	var state := _resolve_request_state()
	match state:
		WorldRequestStateScript.State.AVAILABLE:
			_start_choice_prompt(
				&"card_maker_coastal_catch_available",
				ACTION_REQUEST_AVAILABLE,
				"Before I turn rare catches into cards, show me you can work the coast. Record %d %s catches in your fishing journal. I don't need the fish themselves." % [required_catch_count, required_species_name],
				build_available_choices()
			)
		WorldRequestStateScript.State.ACCEPTED:
			var progress := get_progress_snapshot()
			_start_choice_prompt(
				&"card_maker_coastal_catch_active",
				ACTION_REQUEST_ACCEPTED,
				"The coastal challenge is still open. Your journal shows %d of %d %s catches." % [int(progress.get("current", 0)), int(progress.get("required", required_catch_count)), required_species_name],
				build_accepted_choices()
			)
		WorldRequestStateScript.State.READY_TO_TURN_IN:
			_start_choice_prompt(
				&"card_maker_coastal_catch_ready",
				ACTION_REQUEST_READY,
				"Your journal has enough %s catches. That's the proof I wanted." % required_species_name,
				build_ready_choices()
			)
		WorldRequestStateScript.State.COMPLETED:
			_start_lines(
				&"card_maker_coastal_catch_complete",
				ACTION_REQUEST_COMPLETED,
				[
					"You know how to work the coast now. Keep building that fishing record.",
					"A good card maker watches catches, but a good angler learns why they happened.",
				]
			)
		WorldRequestStateScript.State.SOURCE_COMPLETE:
			_start_lines(
				&"card_maker_coastal_catch_source_complete",
				ACTION_REQUEST_FAILURE,
				["I've got no unclaimed Town Request card left to set aside for that challenge."]
			)
		_:
			idle_requested.emit()


func _handle_accept() -> void:
	if not _bind_dependencies() or not WorldRequestProgressStoreScript.mark_accepted(
		_player_item_inventory,
		request_id
	):
		_start_lines(
			&"card_maker_coastal_catch_accept_failed",
			ACTION_REQUEST_FAILURE,
			["I couldn't record the challenge right now. Try again in a moment."]
		)
		return

	_refresh_request_state()
	var lines: Array = ["Coastal Catch accepted."]
	if _objective_complete():
		lines.append(
			"Your journal already shows enough %s catches. The challenge is ready to turn in." % required_species_name
		)
	else:
		lines.append(
			"Record %d %s catches in your fishing journal, then come back." % [required_catch_count, required_species_name]
		)
	_start_lines(
		&"card_maker_coastal_catch_accept_confirm",
		ACTION_REQUEST_ACCEPT_CONFIRM,
		lines
	)


func _show_progress_details() -> void:
	var progress := get_progress_snapshot()
	_start_lines(
		&"card_maker_coastal_catch_progress",
		ACTION_REQUEST_REVIEW,
		[
			"Challenge: record %d %s catches." % [required_catch_count, required_species_name],
			"Progress: %d/%d. The journal record is what matters; keep your fish." % [int(progress.get("current", 0)), int(progress.get("required", required_catch_count))],
		]
	)


func _handle_turn_in() -> void:
	if _claim_in_progress:
		return
	if _resolve_request_state() != WorldRequestStateScript.State.READY_TO_TURN_IN:
		_refresh_request_state()
		return
	if reward_adapter == null or not reward_adapter.has_method("grant_reward"):
		_start_lines(
			&"card_maker_coastal_catch_reward_missing",
			ACTION_REQUEST_FAILURE,
			["I can't get your reward sorted out right now."]
		)
		return

	_claim_in_progress = true
	var raw_result = reward_adapter.call("grant_reward")
	_claim_in_progress = false
	var result: Dictionary = {}
	if raw_result is Dictionary:
		result = (raw_result as Dictionary).duplicate(true)
	else:
		result = {"success": false, "reason": "invalid_quest_reward_result"}

	if bool(result.get("success", false)):
		var reward_name := str(result.get("display_name", result.get("card_id", "card reward")))
		_refresh_request_state()
		_start_lines(
			&"card_maker_coastal_catch_reward",
			ACTION_REQUEST_REWARD,
			[
				"Challenge complete. The fish stay with you; your journal was proof enough.",
				"Reward received: %s." % reward_name,
			]
		)
		return

	var reason := str(result.get("reason", "reward_unavailable"))
	var message := "I can't deliver the challenge reward right now."
	match reason:
		"source_complete":
			message = "I've got no unclaimed Town Request cards left to give you."
		"event_already_claimed":
			message = "You've already collected the reward for this challenge."
		"duel_rank_too_low":
			message = "That card reward isn't available at your current duel rank yet."
		"triple_triad_backend_not_ready":
			message = "The card ledger isn't ready yet. Try again in a moment."
	_start_lines(
		&"card_maker_coastal_catch_reward_failed",
		ACTION_REQUEST_FAILURE,
		[message]
	)
	_refresh_request_state()


func _start_choice_prompt(
	dialogue_id: StringName,
	action_id: StringName,
	text: String,
	choices: Array
) -> bool:
	if _dialogue_bridge == null:
		return false
	return _dialogue_bridge.start_choice_prompt(
		dialogue_id,
		action_id,
		speaker_id,
		speaker_name,
		text,
		choices,
		_portrait,
		true,
		{"request_id": String(request_id), "source": "card_maker"}
	)


func _start_lines(
	dialogue_id: StringName,
	action_id: StringName,
	texts: Array
) -> bool:
	if _dialogue_bridge == null or texts.is_empty():
		return false
	var lines: Array = []
	for raw_text in texts:
		lines.append({
			"speaker_id": speaker_id,
			"speaker_name": speaker_name,
			"portrait": _portrait,
			"text": str(raw_text),
		})
	return _dialogue_bridge.start_lines(
		dialogue_id,
		action_id,
		lines,
		true,
		{"request_id": String(request_id), "source": "card_maker"}
	)


func _resolve_request_state() -> int:
	var game := _find_card_game()
	return WorldRequestStateScript.resolve(
		_request_unlocked(game),
		_request_accepted(),
		_objective_complete(),
		_reward_claimed(game),
		_source_complete(game)
	)


func _request_unlocked(game: Node) -> bool:
	if _fishing_journal == null or _player_item_inventory == null:
		return false
	if not _card_backend_ready(game):
		return false
	if not game.has_method("is_card_game_unlocked"):
		return false
	return bool(game.call("is_card_game_unlocked"))


func _card_backend_ready(game: Node) -> bool:
	if game == null:
		return false
	if game.has_method("is_backend_ready"):
		return bool(game.call("is_backend_ready"))
	return true


func _request_accepted() -> bool:
	return WorldRequestProgressStoreScript.is_accepted(
		_player_item_inventory,
		request_id
	)


func _objective_complete() -> bool:
	return catch_objective != null and catch_objective.is_complete()


func _reward_claimed(game: Node) -> bool:
	if not _card_backend_ready(game):
		return false
	return (
		reward_adapter != null
		and reward_adapter.has_method("is_claimed")
		and bool(reward_adapter.call("is_claimed"))
	)


func _source_complete(game: Node) -> bool:
	if reward_adapter == null or not _card_backend_ready(game):
		return false
	if not game.has_method("get_source_completion_snapshot"):
		return false
	var source_id := str(reward_adapter.get("source_id"))
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


func _refresh_request_state() -> void:
	if not is_inside_tree():
		return
	_bind_dependencies()
	var state := _resolve_request_state()
	var state_id := WorldRequestStateScript.state_id(state)
	if request_marker != null and request_marker.has_method("set_request_state"):
		request_marker.call("set_request_state", state_id)

	if state == WorldRequestStateScript.State.ACCEPTED:
		var progress := get_progress_snapshot()
		_register_tracker(
			state_id,
			active_objective_template % [
				int(progress.get("current", 0)),
				int(progress.get("required", required_catch_count)),
			],
			progress
		)
		return
	if state == WorldRequestStateScript.State.READY_TO_TURN_IN:
		_register_tracker(state_id, ready_objective_text, get_progress_snapshot())
		return
	if state == WorldRequestStateScript.State.COMPLETED:
		_register_tracker(state_id, completed_objective_text, get_progress_snapshot())
		return
	if is_instance_valid(_objective_tracker) and _objective_tracker.has_method("remove_request"):
		_objective_tracker.call("remove_request", request_id)


func _register_tracker(
	state_id: StringName,
	objective_text: String,
	progress: Dictionary
) -> void:
	var tracker := _ensure_objective_tracker()
	if tracker == null:
		return
	var metadata := {
		"source": "card_maker",
		"objective_type": "fish_catch_count",
		"species_id": String(required_species_id),
		"species_name": required_species_name,
		"required_count": required_catch_count,
		"current_count": int(progress.get("current", 0)),
	}
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
	if tree == null or GameplaySceneRoot.resolve(tree) == null:
		return null
	var existing := GameplaySceneRoot.resolve(tree).find_child("WorldObjectiveTracker", true, false)
	if existing != null and existing.has_method("register_request"):
		_objective_tracker = existing
		return _objective_tracker
	var tracker = WorldObjectiveTrackerScene.instantiate()
	if tracker == null:
		return null
	GameplaySceneRoot.resolve(tree).add_child(tracker)
	_objective_tracker = tracker
	return _objective_tracker


func _journal_available() -> bool:
	var tracker := _find_existing_objective_tracker()
	return (
		tracker != null
		and tracker.has_method("has_journal_entries")
		and bool(tracker.call("has_journal_entries"))
	)


func _open_request_journal() -> void:
	var tracker := _ensure_objective_tracker()
	if tracker == null or not tracker.has_method("open_journal"):
		idle_requested.emit()
		return
	tracker.call("open_journal")
	idle_requested.emit()


func _find_existing_objective_tracker() -> Node:
	if is_instance_valid(_objective_tracker):
		return _objective_tracker
	if not is_inside_tree():
		return null
	var tree := get_tree()
	if tree == null or GameplaySceneRoot.resolve(tree) == null:
		return null
	var existing := GameplaySceneRoot.resolve(tree).find_child("WorldObjectiveTracker", true, false)
	if existing != null and existing.has_method("register_request"):
		_objective_tracker = existing
	return _objective_tracker


func _find_session_services() -> Node:
	var tree := get_tree()
	if tree == null:
		return null
	var services := tree.root.get_node_or_null("FishingSessionServices")
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


func _find_card_game() -> Node:
	if is_instance_valid(_card_game):
		return _card_game
	if not is_inside_tree():
		return null
	var tree := get_tree()
	if tree == null or GameplaySceneRoot.resolve(tree) == null:
		return null
	_card_game = GameplaySceneRoot.resolve(tree).find_child("TripleTriadGame", true, false)
	if _card_game != null and _card_game.has_signal("backend_state_changed"):
		var callback := Callable(self, "_on_card_backend_state_changed")
		if not _card_game.is_connected("backend_state_changed", callback):
			_card_game.connect("backend_state_changed", callback)
	return _card_game


func _on_objective_progress_changed(
	_current_count: int,
	_required_count: int,
	_complete: bool
) -> void:
	_refresh_request_state()


func _on_card_backend_state_changed(_reason: String) -> void:
	_refresh_request_state()


func _find_choice_index(choices: Array, choice_id: StringName) -> int:
	for index in range(choices.size()):
		var raw_choice = choices[index]
		if raw_choice is Dictionary:
			var current_id := StringName(str((raw_choice as Dictionary).get("choice_id", "")))
			if current_id == choice_id:
				return index
	return -1


func _exit_tree() -> void:
	_disconnect_dialogue_bridge()
	if is_instance_valid(_objective_tracker) and _objective_tracker.has_method("remove_request"):
		_objective_tracker.call("remove_request", request_id)
