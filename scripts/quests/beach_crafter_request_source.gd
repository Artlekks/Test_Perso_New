extends Node
class_name BeachCrafterRequestSource

## Second live request source: a material-count beach survey owned by the Crafter.
##
## This node proves that the shared request marker/tracker/journal stack is not
## coupled to Triple Triad objectives. Acceptance persists through the generic
## PlayerItemInventory metadata helper, objective truth comes from the gathering
## inventory, and the reward still goes through the canonical quest-card adapter.

const WorldRequestStateScript = preload("res://scripts/quests/world_request_state.gd")
const WorldRequestProgressStoreScript = preload("res://scripts/quests/world_request_progress_store.gd")
const WorldObjectiveTrackerScene = preload("res://actors/WorldObjectiveTracker.tscn")

signal return_to_services_requested
signal idle_requested

const PARENT_ACTION_CHOOSE_SERVICE: StringName = &"choose_crafter_service"
const CHOICE_REQUEST: StringName = &"request"
const CHOICE_JOURNAL: StringName = &"journal"

const ACTION_REQUEST_AVAILABLE: StringName = &"crafter_request_available"
const ACTION_REQUEST_ACCEPTED: StringName = &"crafter_request_accepted"
const ACTION_REQUEST_READY: StringName = &"crafter_request_ready"
const ACTION_REQUEST_ACCEPT_CONFIRM: StringName = &"crafter_request_accept_confirm"
const ACTION_REQUEST_REVIEW: StringName = &"crafter_request_review"
const ACTION_REQUEST_REWARD: StringName = &"crafter_request_reward"
const ACTION_REQUEST_COMPLETED: StringName = &"crafter_request_completed"
const ACTION_REQUEST_FAILURE: StringName = &"crafter_request_failure"

@export var request_id: StringName = &"beach_demo_crafter_sea_glass_01"
@export var request_title: String = "Sea Glass Survey"
@export var speaker_name: String = "Crafter"
@export var speaker_id: StringName = &"beach_crafter"

@export_category("Objective")
@export var required_material_id: StringName = &"sea_glass"
@export var required_material_name: String = "Sea Glass"
@export var required_material_count: int = 3
@export var active_objective_template: String = "Find Sea Glass along the beach. %d/%d found."
@export var ready_objective_text: String = "Return to the Beach Crafter with your Sea Glass survey."
@export var completed_objective_text: String = "Sea Glass survey completed."

@export_category("Choice Text")
@export var available_choice_text: String = "Sea Glass Survey"
@export var accepted_choice_text: String = "Review Sea Glass Survey"
@export var ready_choice_text: String = "Turn In Sea Glass Survey"
@export var completed_choice_text: String = "Sea Glass Survey Complete"
@export var journal_choice_text: String = "View Requests"

@onready var reward_adapter: Node = $QuestRewardAdapter
@onready var material_objective: MaterialCountRequestObjective = $MaterialObjective
@onready var request_marker: Node = get_node_or_null("../RequestMarker")

var _dialogue_bridge: DialogueNPCBridge = null
var _portrait: Texture2D = null
var _gathering_inventory: Node = null
var _player_item_inventory: Node = null
var _objective_tracker: Node = null
var _card_game: Node = null
var _claim_in_progress: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	material_objective.material_id = required_material_id
	material_objective.required_count = required_material_count
	material_objective.progress_changed.connect(_on_objective_progress_changed)
	call_deferred("_bind_dependencies")


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
	var state_id: StringName = WorldRequestStateScript.state_id(state)
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
		# Keep Craft first, then surface the request before help/card options.
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
	if material_objective == null:
		return MaterialCountRequestObjective.progress_snapshot_for_count(
			0,
			required_material_count
		)
	return material_objective.get_progress_snapshot()


static func main_choice_text_for_state(
	state_id: StringName,
	available_text: String = "Sea Glass Survey",
	accepted_text: String = "Review Sea Glass Survey",
	ready_text: String = "Turn In Sea Glass Survey",
	completed_text: String = "Sea Glass Survey Complete"
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
		{"choice_id": &"accept", "text": "Accept Survey"},
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

	var raw_gathering = services.get("beach_gathering_inventory")
	var raw_player = services.get("player_item_inventory")
	if raw_gathering is Node:
		_gathering_inventory = raw_gathering as Node
	if raw_player is Node:
		_player_item_inventory = raw_player as Node

	if _gathering_inventory != null and material_objective != null:
		material_objective.configure(_gathering_inventory)
	_find_card_game()
	return _gathering_inventory != null and _player_item_inventory != null


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
				&"crafter_sea_glass_available",
				ACTION_REQUEST_AVAILABLE,
				"I'm keeping an eye on what the tide is washing in. Find %d pieces of %s and show me what you've found. You can keep the pieces afterward." % [required_material_count, required_material_name],
				build_available_choices()
			)
		WorldRequestStateScript.State.ACCEPTED:
			var progress := get_progress_snapshot()
			_start_choice_prompt(
				&"crafter_sea_glass_active",
				ACTION_REQUEST_ACCEPTED,
				"The survey is still open. You've found %d of %d %s pieces." % [int(progress.get("current", 0)), int(progress.get("required", required_material_count)), required_material_name],
				build_accepted_choices()
			)
		WorldRequestStateScript.State.READY_TO_TURN_IN:
			_start_choice_prompt(
				&"crafter_sea_glass_ready",
				ACTION_REQUEST_READY,
				"That's enough %s for the survey. I only needed to see what the tide was bringing in, so keep the pieces." % required_material_name,
				build_ready_choices()
			)
		WorldRequestStateScript.State.COMPLETED:
			_start_lines(
				&"crafter_sea_glass_complete",
				ACTION_REQUEST_COMPLETED,
				[
					"That survey helped. Good beachcombing tells you what materials are worth watching for.",
					"Keep an eye on the tide. Useful things have a habit of turning up when you're not looking for them.",
				]
			)
		WorldRequestStateScript.State.SOURCE_COMPLETE:
			_start_lines(
				&"crafter_sea_glass_source_complete",
				ACTION_REQUEST_FAILURE,
				["I've got nothing else set aside for that survey right now."]
			)
		_:
			idle_requested.emit()


func _handle_accept() -> void:
	if not _bind_dependencies() or not WorldRequestProgressStoreScript.mark_accepted(
		_player_item_inventory,
		request_id
	):
		_start_lines(
			&"crafter_sea_glass_accept_failed",
			ACTION_REQUEST_FAILURE,
			["I couldn't record the survey right now. Try again in a moment."]
		)
		return

	_refresh_request_state()
	var lines: Array = [
		"Sea Glass Survey accepted.",
	]
	if _objective_complete():
		lines.append(
			"You've already found enough %s. The survey is ready to turn in." % required_material_name
		)
	else:
		lines.append(
			"Find %d pieces of %s around the beach, then come back and show me." % [required_material_count, required_material_name]
		)
	_start_lines(
		&"crafter_sea_glass_accept_confirm",
		ACTION_REQUEST_ACCEPT_CONFIRM,
		lines
	)


func _show_progress_details() -> void:
	var progress := get_progress_snapshot()
	_start_lines(
		&"crafter_sea_glass_progress",
		ACTION_REQUEST_REVIEW,
		[
			"Survey: find %d pieces of %s along the beach." % [required_material_count, required_material_name],
			"Progress: %d/%d. I only need to see that you've found them; the materials stay with you." % [int(progress.get("current", 0)), int(progress.get("required", required_material_count))],
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
			&"crafter_sea_glass_reward_missing",
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
			&"crafter_sea_glass_reward",
			ACTION_REQUEST_REWARD,
			[
				"Survey complete. Keep the %s—you'll get more use out of it than I will." % required_material_name,
				"Reward received: %s." % reward_name,
			]
		)
		return

	var reason := str(result.get("reason", "reward_unavailable"))
	var message := "I can't deliver the survey reward right now."
	match reason:
		"source_complete":
			message = "I've got no unclaimed Town Request cards left to give you."
		"event_already_claimed":
			message = "You've already collected the reward for this survey."
		"duel_rank_too_low":
			message = "That card reward isn't available at your current duel rank yet."
	_start_lines(
		&"crafter_sea_glass_reward_failed",
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
		{"request_id": String(request_id), "source": "beach_crafter"}
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
		{"request_id": String(request_id), "source": "beach_crafter"}
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
	# TripleTriadGame is composed in stages. Its public unlock/source queries
	# depend on the world gateway, so never call them until the backend facade
	# reports that composition is complete. This keeps request presentation
	# decoupled from Triple Triad startup order.
	if not _card_backend_ready(game):
		return false
	if not game.has_method("is_card_game_unlocked"):
		return false
	return bool(game.call("is_card_game_unlocked"))


func _card_backend_ready(game: Node) -> bool:
	if game == null:
		return false
	# Current TripleTriadGame exposes an explicit readiness contract. Respect it
	# instead of assuming a node found in the scene tree is already composed.
	if game.has_method("is_backend_ready"):
		return bool(game.call("is_backend_ready"))
	# Compatibility for older builds that predate is_backend_ready().
	return true


func _request_accepted() -> bool:
	return WorldRequestProgressStoreScript.is_accepted(
		_player_item_inventory,
		request_id
	)


func _objective_complete() -> bool:
	return material_objective != null and material_objective.is_complete()


func _reward_claimed(game: Node) -> bool:
	# Reward claim truth lives behind Triple Triad's world gateway. The adapter is
	# now defensive too, but keep the request consumer honest: a scene-tree node
	# existing does not mean its backend composition has completed yet.
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
	var state_id: StringName = WorldRequestStateScript.state_id(state)
	if request_marker != null and request_marker.has_method("set_request_state"):
		request_marker.call("set_request_state", state_id)

	if state == WorldRequestStateScript.State.ACCEPTED:
		var progress := get_progress_snapshot()
		_register_tracker(
			state_id,
			active_objective_template % [
				int(progress.get("current", 0)),
				int(progress.get("required", required_material_count)),
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
	tracker.call(
		"register_request",
		request_id,
		request_title,
		objective_text,
		state_id,
		{
			"source": "beach_crafter",
			"objective_type": "material_count",
			"material_id": String(required_material_id),
			"required_count": required_material_count,
			"current_count": int(progress.get("current", 0)),
		}
	)


func _ensure_objective_tracker() -> Node:
	if is_instance_valid(_objective_tracker):
		return _objective_tracker
	if not is_inside_tree():
		return null
	var tree := get_tree()
	if tree == null or tree.current_scene == null:
		return null
	var existing := tree.current_scene.find_child("WorldObjectiveTracker", true, false)
	if existing != null and existing.has_method("register_request"):
		_objective_tracker = existing
		return _objective_tracker
	var tracker = WorldObjectiveTrackerScene.instantiate()
	if tracker == null:
		return null
	tree.current_scene.add_child(tracker)
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
	if tree == null or tree.current_scene == null:
		return null
	var existing := tree.current_scene.find_child("WorldObjectiveTracker", true, false)
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
	var scene := tree.current_scene
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
	if tree == null or tree.current_scene == null:
		return null
	_card_game = tree.current_scene.find_child("TripleTriadGame", true, false)
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
		if raw_choice is Dictionary and StringName(str((raw_choice as Dictionary).get("choice_id", ""))) == choice_id:
			return index
	return -1


func _exit_tree() -> void:
	_disconnect_dialogue_bridge()
	if is_instance_valid(_objective_tracker) and _objective_tracker.has_method("remove_request"):
		_objective_tracker.call("remove_request", request_id)
