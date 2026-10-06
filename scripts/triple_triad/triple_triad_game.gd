extends CanvasLayer

signal opened
signal closed
signal match_finished(result: Dictionary)
signal card_reward_selected(card_definition)
signal backend_state_changed(reason: String)
signal runtime_state_changed(snapshot: Dictionary)
signal acquisition_completed(result: Dictionary)
signal card_game_unlock_changed(unlocked: bool)
signal competition_state_changed(snapshot: Dictionary)
signal world_progression_changed(snapshot: Dictionary)
signal gameplay_event_queued(event: Dictionary)

const OpponentCollectionScript = preload("res://scripts/triple_triad/triple_triad_opponent_collection.gd")
const DefaultOpponentRegistry = preload("res://data/triple_triad/opponents/opponent_registry.tres")
const DefaultAcquisitionRegistry = preload("res://data/triple_triad/acquisition/acquisition_registry.tres")
const DefaultAcquisitionPolicy = preload("res://data/triple_triad/acquisition/default_acquisition_policy.tres")
const FishingSalvageBridgeScript = preload("res://scripts/triple_triad/triple_triad_fishing_salvage_bridge.gd")
const SessionControllerScript = preload("res://scripts/triple_triad/triple_triad_session_controller.gd")
const InputControllerScript = preload("res://scripts/triple_triad/triple_triad_input_controller.gd")
const CompositionRootScript = preload("res://scripts/triple_triad/triple_triad_composition_root.gd")

const BACKEND_VERSION := "2.18.1"

const OWNER_NONE := 0
const OWNER_PLAYER := 1
const OWNER_OPPONENT := 2

const PHASE_CLOSED := SessionControllerScript.PHASE_CLOSED
const PHASE_DEALING := SessionControllerScript.PHASE_DEALING
const PHASE_SELECT_CARD := SessionControllerScript.PHASE_SELECT_CARD
const PHASE_SELECT_CELL := SessionControllerScript.PHASE_SELECT_CELL
const PHASE_ANIMATING := SessionControllerScript.PHASE_ANIMATING
const PHASE_AI := SessionControllerScript.PHASE_AI
const PHASE_RESULT := SessionControllerScript.PHASE_RESULT
const PHASE_REWARD := SessionControllerScript.PHASE_REWARD
const PHASE_DECK_SETUP := SessionControllerScript.PHASE_DECK_SETUP
const PHASE_SURRENDER_CONFIRM := SessionControllerScript.PHASE_SURRENDER_CONFIRM


@export var card_catalog: Resource
@export var rule_set: Resource
@export var region_profile: Resource
@export var ai_profile: Resource
@export var opponent_registry: Resource = DefaultOpponentRegistry
@export var acquisition_policy: Resource = DefaultAcquisitionPolicy
@export var acquisition_registry: Resource = DefaultAcquisitionRegistry
@export_range(5, 50, 1) var deck_budget: int = 30
@export_range(5, 50, 1) var player_deck_budget: int = 30
@export_range(1, 10, 1) var player_card_rank: int = 6
@export_range(1, 10, 1) var prototype_min_level: int = 1
@export_range(1, 10, 1) var prototype_max_level: int = 3
@export_range(0.0, 2.0, 0.05) var ai_delay_seconds: float = 0.75
## Debug builds only. Pure backend QA; does not touch player save files.
@export var run_backend_qa_on_startup: bool = true

@export_category("Developer Balance")
## Runs an offline AI-vs-AI balance suite after backend startup. Disabled by
## default because a useful sample intentionally runs hundreds of full matches.
@export var run_balance_simulation_on_startup: bool = false
@export_range(1, 500, 1) var balance_games_per_matchup: int = 40
@export var balance_simulation_seed: int = 1337

@onready var root: Control = $Root
@onready var backdrop: TextureRect = $Root/Backdrop
@onready var grid_artwork: TextureRect = $Root/GridArtwork
@onready var opponent_hand_container: Control = $Root/OpponentHand
@onready var board_container: GridContainer = $Root/Board
@onready var player_hand_container: Control = $Root/PlayerHand
@onready var opponent_score_label: Control = $Root/OpponentScoreLabel/Digits
@onready var player_score_label: Control = $Root/PlayerScoreLabel/Digits
@onready var turn_label: Label = $Root/InfoPanel/TurnLabel
@onready var message_label: Label = $Root/MessageLabel
@onready var help_label: Label = $Root/HelpLabel
@onready var info_panel: Control = $Root/InfoPanel
@onready var info_label: Label = $Root/InfoPanel/InfoLabel
@onready var selection_arrow: Polygon2D = $Root/SelectionArrow
@onready var turn_arrow: Polygon2D = $Root/TurnArrow
@onready var result_label: Label = $Root/ResultLabel
@onready var reward_view = $Root/TripleTriadRewardView
@onready var transition_fade: ColorRect = $Root/TransitionFade
@onready var animation_director = $AnimationDirector
@onready var ai_timer: Timer = $AITimer
@onready var debug_menu = $TripleTriadDebugMenu
@onready var deck_setup = $Root/TripleTriadDeckSetup

var _composition_root = CompositionRootScript.new()
var _match = null
var _session = null
var _match_flow = null
var _presentation = null
var _input_controller = null
var _ui_flow = null
var _world_gateway = null
var _competition = null
var _runtime_recovery = null
var _collection_backend = null
var _opponent_collection_backend = null
var _progression = null
var _backend_ready: bool = false
var _backend_errors: PackedStringArray = PackedStringArray()
var _fishing_salvage_bridge: Node = null
var _match_resolution_journal = null
var _match_resolution = null
var _developer_tools = null
var _match_context = null
var _runtime_state = null
var _live_match = null
var _match_orchestrator = null
var _persistence = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var composition_result: Dictionary = _composition_root.compose(
		self,
		_build_composition_config(),
		_build_composition_nodes(),
		_build_composition_callbacks()
	)
	_install_composition_result(composition_result)

	for raw_warning in composition_result.get("warnings", []):
		push_warning("TripleTriadGame backend: %s" % str(raw_warning))
	if not bool(composition_result.get("success", false)):
		for error_text in _backend_errors:
			push_error("TripleTriadGame backend: %s" % error_text)
		push_error("TripleTriadGame: composition/bootstrap failed; backend disabled for this session.")
		return

	# Composition is intentionally two-phase: install references first, then
	# allow effectful startup work to emit callbacks back into this host.
	_composition_root.activate_after_install(composition_result)

	_backend_ready = true
	_world_gateway.set_backend_ready(true)
	_install_fishing_salvage_bridge()
	var services: Dictionary = composition_result.get("services", {})
	_developer_tools.bind_runtime(services.get("world_reward_ledger"))
	var runtime_recovery: Dictionary = reconcile_runtime_state()
	_developer_tools.record_session_start(runtime_recovery)
	if bool(runtime_recovery.get("requires_reward_ui", false)):
		call_deferred("_resume_pending_match_resolution")
	if OS.is_debug_build() and run_backend_qa_on_startup:
		run_backend_qa()
	if OS.is_debug_build() and run_balance_simulation_on_startup:
		call_deferred(
			"run_balance_simulation",
			balance_games_per_matchup,
			balance_simulation_seed
		)


func _build_composition_config() -> Dictionary:
	return {
		"backend_version": BACKEND_VERSION,
		"card_catalog": card_catalog,
		"rule_set": rule_set,
		"region_profile": region_profile,
		"ai_profile": ai_profile,
		"opponent_registry": opponent_registry,
		"acquisition_policy": acquisition_policy,
		"acquisition_registry": acquisition_registry,
		"deck_budget": deck_budget,
		"player_deck_budget": player_deck_budget,
		"player_card_rank": player_card_rank,
		"prototype_min_level": prototype_min_level,
		"prototype_max_level": prototype_max_level,
		"ai_delay_seconds": ai_delay_seconds,
		"event_capacity": 32,
	}


func _build_composition_nodes() -> Dictionary:
	return {
		"root": root,
		"backdrop": backdrop,
		"grid_artwork": grid_artwork,
		"opponent_hand_container": opponent_hand_container,
		"board_container": board_container,
		"player_hand_container": player_hand_container,
		"opponent_score_label": opponent_score_label,
		"player_score_label": player_score_label,
		"turn_label": turn_label,
		"message_label": message_label,
		"help_label": help_label,
		"info_panel": info_panel,
		"info_label": info_label,
		"selection_arrow": selection_arrow,
		"turn_arrow": turn_arrow,
		"result_label": result_label,
		"reward_view": reward_view,
		"transition_fade": transition_fade,
		"animation_director": animation_director,
		"ai_timer": ai_timer,
		"debug_menu": debug_menu,
		"deck_setup": deck_setup,
	}


func _build_composition_callbacks() -> Dictionary:
	return {
		"is_backend_ready": Callable(self, "is_backend_ready"),
		"is_card_game_unlocked": Callable(self, "is_card_game_unlocked"),
		"get_player_snapshot": Callable(self, "get_player_snapshot"),
		"get_acquisition_snapshot": Callable(self, "get_acquisition_snapshot"),
		"get_collection_completion_snapshot": Callable(self, "get_collection_completion_snapshot"),
		"get_runtime_recovery_snapshot": Callable(self, "get_runtime_recovery_snapshot"),
		"get_backend_health": Callable(self, "get_backend_health"),
		"get_global_triple_triad_snapshot": Callable(self, "get_global_triple_triad_snapshot"),
		"get_pending_gameplay_events": Callable(self, "get_pending_gameplay_events"),
		"open_active_competition_match": Callable(self, "open_active_competition_match"),
		"reconcile_runtime_state": Callable(self, "reconcile_runtime_state"),
		"queue_gameplay_event": Callable(self, "_queue_gameplay_event"),
		"publish_backend_state_change": Callable(self, "_publish_backend_state_change"),
		"invalidate_state_api": Callable(self, "_invalidate_state_api"),
		"on_ai_timer_timeout": Callable(self, "_on_ai_timer_timeout"),
		"on_reward_selected": Callable(self, "_on_reward_selected"),
		"on_reward_completed": Callable(self, "_on_reward_completed"),
		"on_qa_profile_apply_requested": Callable(self, "_on_qa_profile_apply_requested"),
		"on_deck_confirmed": Callable(self, "_on_deck_confirmed"),
		"on_deck_cancelled": Callable(self, "_on_deck_cancelled"),
		"on_runtime_gameplay_event_queued": Callable(self, "_on_runtime_gameplay_event_queued"),
		"on_runtime_backend_state_changed": Callable(self, "_on_runtime_backend_state_changed"),
		"on_runtime_world_progression_changed": Callable(self, "_on_runtime_world_progression_changed"),
		"on_acquisition_bundle_claimed": Callable(self, "_on_acquisition_bundle_claimed"),
		"on_card_game_unlock_changed": Callable(self, "_on_card_game_unlock_changed"),
		"on_competition_state_changed": Callable(self, "_on_competition_controller_state_changed"),
		"on_persistence_card_reward_selected": Callable(self, "_on_persistence_card_reward_selected"),
		"is_open": Callable(self, "is_open"),
		"refresh_views": Callable(self, "_refresh_views"),
		"refresh_ui_flow": Callable(self, "_refresh_ui_flow"),
		"finish_match": Callable(self, "_finish_match"),
		"close_game": Callable(self, "close_game"),
	}


func _install_composition_result(result: Dictionary) -> void:
	var components: Dictionary = result.get("components", {})
	_match = components.get("match")
	_session = components.get("session")
	_match_flow = components.get("match_flow")
	_presentation = components.get("presentation")
	_input_controller = components.get("input_controller")
	_ui_flow = components.get("ui_flow")
	_world_gateway = components.get("world_gateway")
	_competition = components.get("competition")
	_runtime_recovery = components.get("runtime_recovery")
	_match_resolution_journal = components.get("match_resolution_journal")
	_match_resolution = components.get("match_resolution")
	_developer_tools = components.get("developer_tools")
	_match_context = components.get("match_context")
	_runtime_state = components.get("runtime_state")
	_live_match = components.get("live_match")
	_match_orchestrator = components.get("match_orchestrator")
	_persistence = components.get("persistence")

	var services: Dictionary = result.get("services", {})
	_collection_backend = services.get("collection_backend")
	_progression = services.get("progression")
	_backend_errors.clear()
	for raw_error in result.get("errors", []):
		_backend_errors.append(str(raw_error))


func run_backend_qa() -> Dictionary:
	if _developer_tools == null:
		return {
			"passed": false,
			"test_count": 0,
			"passed_count": 0,
			"failed_count": 1,
			"failures": ["backend_not_ready"],
			"reason": "backend_not_ready",
		}
	return _developer_tools.run_backend_qa()


func run_balance_simulation(
	games_per_matchup: int = 40,
	simulation_seed: int = 1337
) -> Dictionary:
	if _developer_tools == null:
		return {
			"valid": false,
			"reason": "backend_not_ready",
			"errors": ["backend_not_ready"],
		}
	return _developer_tools.run_balance_simulation(
		games_per_matchup,
		simulation_seed
	)


func is_backend_ready() -> bool:
	return _backend_ready


func _backend_not_ready_result() -> Dictionary:
	return {
		"success": false,
		"reason": "backend_not_ready",
	}


func get_backend_health() -> Dictionary:
	if _runtime_state == null:
		return {
			"backend_version": BACKEND_VERSION,
			"ready": false,
			"errors": _backend_errors.duplicate(),
			"save_integrity": {},
		}
	return _runtime_state.get_backend_health(
		_backend_ready,
		_backend_errors
	)


func get_pending_gameplay_events() -> Array:
	if _runtime_state == null:
		return []
	return _runtime_state.get_pending_gameplay_events()


func pop_next_gameplay_event() -> Dictionary:
	if _runtime_state == null:
		return {}
	return _runtime_state.pop_next_gameplay_event()


func clear_gameplay_events() -> void:
	if _runtime_state == null:
		return
	_runtime_state.clear_gameplay_events()


func _queue_gameplay_event(
	event_type: StringName,
	title: String,
	detail: String = "",
	payload: Dictionary = {},
	priority: int = 0
) -> Dictionary:
	if _runtime_state == null:
		return {}
	return _runtime_state.queue_gameplay_event(
		event_type,
		title,
		detail,
		payload,
		priority
	)


func get_state_api():
	if _runtime_state == null:
		return null
	return _runtime_state.get_state_api()


func get_player_snapshot() -> Dictionary:
	if _runtime_state == null:
		return {}
	return _runtime_state.get_player_snapshot()


func get_collection_snapshot() -> Array:
	if _runtime_state == null:
		return []
	return _runtime_state.get_collection_snapshot()


func get_card_snapshot(card_id: StringName) -> Dictionary:
	var state_api = get_state_api()
	if state_api == null or not state_api.has_method(
		"get_card_snapshot"
	):
		return {}
	return state_api.call("get_card_snapshot", card_id)


func get_card_acquisition_sources(
	card_id: StringName
) -> Array:
	if _world_gateway == null:
		return []
	return _world_gateway.get_card_acquisition_sources(card_id)


func get_acquisition_source_snapshot(
	source_type: StringName,
	source_id: StringName
) -> Dictionary:
	if _world_gateway == null:
		return {}
	return _world_gateway.get_acquisition_source_snapshot(
		source_type,
		source_id
	)


func get_world_acquisition_sources() -> Array:
	if _world_gateway == null:
		return []
	return _world_gateway.get_world_acquisition_sources()


func claim_world_source_card(
	source_type: StringName,
	source_id: StringName,
	card_id: StringName,
	source_context: StringName = &""
) -> Dictionary:
	if _world_gateway == null:
		return _backend_not_ready_result()
	return _world_gateway.claim_world_source_card(
		source_type,
		source_id,
		card_id,
		source_context
	)


func claim_world_source_reward(
	source_type: StringName,
	source_id: StringName,
	source_context: StringName = &"",
	event_id: StringName = &"",
	one_shot: bool = false
) -> Dictionary:
	if _world_gateway == null:
		return _backend_not_ready_result()
	return _world_gateway.claim_world_source_reward(
		source_type,
		source_id,
		source_context,
		event_id,
		one_shot
	)


func claim_fishing_salvage_reward(
	source_id: StringName,
	source_context: StringName = &""
) -> Dictionary:
	if _world_gateway == null:
		return _backend_not_ready_result()
	return _world_gateway.claim_fishing_salvage_reward(
		source_id,
		source_context
	)


func claim_treasure_cache_reward(
	source_id: StringName,
	cache_event_id: StringName,
	source_context: StringName = &""
) -> Dictionary:
	if _world_gateway == null:
		return _backend_not_ready_result()
	return _world_gateway.claim_treasure_cache_reward(
		source_id,
		cache_event_id,
		source_context
	)


func claim_quest_card_reward(
	source_id: StringName,
	quest_event_id: StringName,
	source_context: StringName = &""
) -> Dictionary:
	if _world_gateway == null:
		return _backend_not_ready_result()
	return _world_gateway.claim_quest_card_reward(
		source_id,
		quest_event_id,
		source_context
	)


func claim_tournament_card_reward(
	source_id: StringName,
	tournament_event_id: StringName,
	source_context: StringName = &"",
	one_shot: bool = true
) -> Dictionary:
	if _world_gateway == null:
		return _backend_not_ready_result()
	return _world_gateway.claim_tournament_card_reward(
		source_id,
		tournament_event_id,
		source_context,
		one_shot
	)


func advance_world_reward_counter(
	counter_id: StringName
) -> int:
	if _world_gateway == null:
		return 0
	return _world_gateway.advance_world_reward_counter(counter_id)


func get_world_reward_delivery_snapshot() -> Dictionary:
	if _world_gateway == null:
		return {}
	return _world_gateway.get_world_reward_delivery_snapshot()


func has_world_reward_event_claimed(
	event_id: StringName
) -> bool:
	if _world_gateway == null:
		return false
	return _world_gateway.has_world_reward_event_claimed(event_id)


func get_deck_profiles_snapshot() -> Array:
	if _runtime_state == null:
		return []
	return _runtime_state.get_deck_profiles_snapshot()


func get_opponent_snapshot(
	opponent_id: StringName
) -> Dictionary:
	if _runtime_state == null:
		return {}
	return _runtime_state.get_opponent_snapshot(opponent_id)


func get_opponents_snapshot() -> Array:
	if _runtime_state == null:
		return []
	return _runtime_state.get_opponents_snapshot()


func get_collection_completion_snapshot() -> Dictionary:
	if _runtime_state == null:
		return {}
	return _runtime_state.get_collection_completion_snapshot()


func get_missing_card_diagnostics() -> Array:
	if _runtime_state == null:
		return []
	return _runtime_state.get_missing_card_diagnostics()


func get_source_completion_snapshot() -> Array:
	if _runtime_state == null:
		return []
	return _runtime_state.get_source_completion_snapshot()


func get_global_triple_triad_snapshot() -> Dictionary:
	if _runtime_state == null:
		return {}
	return _runtime_state.get_global_snapshot()


func get_world_progression_snapshot() -> Dictionary:
	if _runtime_state == null:
		return {}
	return _runtime_state.get_world_progression_snapshot()


func get_runtime_ui_snapshot() -> Dictionary:
	if _runtime_state == null or _live_match == null:
		return {}
	return _runtime_state.get_runtime_ui_snapshot(
		_match,
		_live_match.selected_hand_index,
		_live_match.selected_cell_index
	)


func _invalidate_state_api(
	reason: String = ""
) -> void:
	if _runtime_state == null:
		return
	_runtime_state.invalidate_state_api(reason)


func _publish_backend_state_change(
	reason: String
) -> void:
	if _runtime_state == null:
		return
	_runtime_state.publish_backend_state_change(reason)


func is_open() -> bool:
	return _session != null and _session.is_open()


func is_card_game_unlocked() -> bool:
	if _world_gateway == null:
		return false
	return _world_gateway.is_card_game_unlocked()


func get_acquisition_snapshot() -> Dictionary:
	if _world_gateway == null:
		return {}
	return _world_gateway.get_acquisition_snapshot()


func claim_acquisition_bundle(
	bundle_id: StringName,
	source_context: StringName = &""
) -> Dictionary:
	if _world_gateway == null:
		return _backend_not_ready_result()
	return _world_gateway.claim_acquisition_bundle(
		bundle_id,
		source_context
	)


func claim_salvaged_card_case(
	source_context: StringName = &"sea_salvage"
) -> Dictionary:
	if _world_gateway == null:
		return _backend_not_ready_result()
	return _world_gateway.claim_salvaged_card_case(
		source_context
	)


func get_onboarding_snapshot() -> Dictionary:
	if _world_gateway == null:
		return {}
	return _world_gateway.get_onboarding_snapshot()


func _install_fishing_salvage_bridge() -> void:
	if _world_gateway == null:
		return
	if is_instance_valid(_fishing_salvage_bridge):
		return

	var bridge = FishingSalvageBridgeScript.new()
	bridge.name = "TripleTriadFishingSalvageBridge"
	add_child(bridge)
	_fishing_salvage_bridge = bridge
	_world_gateway.set_fishing_salvage_bridge(bridge)

	if bridge.has_method("configure"):
		bridge.call(
			"configure",
			self,
			PackedStringArray(["ocean_2"]),
			true
		)


func get_competitive_snapshot() -> Dictionary:
	if _competition == null:
		return {}
	return _competition.get_competitive_snapshot()


func get_circuit_snapshot(
	circuit_id: StringName
) -> Dictionary:
	if _competition == null:
		return {}
	return _competition.get_circuit_snapshot(circuit_id)


func get_competition_snapshot(
	competition_id: StringName
) -> Dictionary:
	if _competition == null:
		return {}
	return _competition.get_competition_snapshot(
		competition_id
	)


func start_competition(
	competition_id: StringName
) -> Dictionary:
	if not _backend_ready or _competition == null:
		return _backend_not_ready_result()
	if not is_card_game_unlocked():
		return {
			"success": false,
			"reason": "card_game_locked",
		}
	return _competition.start_competition(competition_id)


func start_competition_and_open(
	competition_id: StringName
) -> bool:
	var result: Dictionary = start_competition(
		competition_id
	)
	if not bool(result.get("success", false)):
		return false
	return open_active_competition_match()


func open_active_competition_match() -> bool:
	if not _backend_ready or _competition == null:
		return false
	if is_open():
		return false

	var open_request: Dictionary = (
		_competition.prepare_active_match_open()
	)
	if not bool(open_request.get("success", false)):
		return false

	var opponent_id := StringName(
		str(open_request.get("opponent_id", ""))
	)
	var locked_cards: Array = open_request.get(
		"locked_cards",
		[]
	)
	if not open_game_by_id(opponent_id):
		return false

	_competition.set_match_active(true)
	if locked_cards.size() == 5:
		_live_match.set_active_player_deck(locked_cards)
		_ui_flow.close_deck_setup()
		_start_new_match(
			_live_match.get_active_player_deck()
		)
	return true


func abandon_active_competition() -> Dictionary:
	if _competition == null:
		return _backend_not_ready_result()
	return _competition.abandon_active_competition()


func get_opponent_evolution_snapshot(
	opponent_id: StringName
) -> Dictionary:
	if (
		_match_context == null
		or opponent_registry == null
		or not opponent_registry.has_method("get_opponent")
	):
		return {}

	var profile = opponent_registry.call(
		"get_opponent",
		opponent_id
	)
	if profile == null:
		return {}

	return _match_context.build_opponent_evolution_snapshot(
		profile
	)


func get_active_opponent_evolution_snapshot() -> Dictionary:
	if _match_context == null:
		return {}
	return _match_context.get_active_evolution_snapshot()


func get_opponent_availability(
	opponent_id: StringName
) -> Dictionary:
	if _world_gateway == null:
		return {}
	return _world_gateway.get_opponent_availability(
		opponent_id
	)


func get_available_card_player_ids(
	region_id: StringName = &"",
	required_tag: StringName = &""
) -> PackedStringArray:
	if _world_gateway == null:
		return PackedStringArray()
	return _world_gateway.get_available_card_player_ids(
		region_id,
		required_tag
	)


func _on_runtime_gameplay_event_queued(event: Dictionary) -> void:
	gameplay_event_queued.emit(event.duplicate(true))


func _on_runtime_backend_state_changed(reason: String) -> void:
	backend_state_changed.emit(reason)


func _on_runtime_world_progression_changed(snapshot: Dictionary) -> void:
	world_progression_changed.emit(snapshot.duplicate(true))


func _on_acquisition_bundle_claimed(result: Dictionary) -> void:
	acquisition_completed.emit(result.duplicate(true))


func _on_card_game_unlock_changed(unlocked: bool) -> void:
	card_game_unlock_changed.emit(unlocked)


func _on_competition_controller_state_changed(snapshot: Dictionary) -> void:
	competition_state_changed.emit(snapshot.duplicate(true))


func open_game_by_id(opponent_id: StringName) -> bool:
	if not _backend_ready:
		push_warning("TripleTriadGame: backend is not ready; match open rejected.")
		return false
	if (
		_match_resolution_journal != null
		and _match_resolution_journal.has_pending()
	):
		push_warning(
			"TripleTriadGame: finish the interrupted card result before starting another match."
		)
		call_deferred("_resume_pending_match_resolution")
		return false
	if opponent_registry == null or not opponent_registry.has_method("get_opponent"):
		push_error("TripleTriadGame: opponent registry is unavailable.")
		return false

	var active_competition: Dictionary = _competition.get_active_snapshot()
	if bool(active_competition.get("active", false)):
		var expected_id := StringName(
			str(active_competition.get("next_opponent_id", ""))
		)
		if expected_id != &"" and opponent_id != expected_id:
			push_warning(
				"TripleTriadGame: finish or abandon the active tournament before challenging another opponent."
			)
			return false

	var profile = opponent_registry.call("get_opponent", opponent_id)
	if profile == null:
		push_error(
			"TripleTriadGame: unknown opponent_id '%s'."
			% String(opponent_id)
		)
		return false

	var availability: Dictionary = get_opponent_availability(opponent_id)
	if not bool(availability.get("available", false)):
		push_warning(
			"TripleTriadGame: opponent '%s' is locked: %s"
			% [
				String(opponent_id),
				str(availability.get("reason", "Unavailable.")),
			]
		)
		return false

	open_game(profile)
	return is_open()


func open_game(opponent_profile_override: Resource = null) -> void:
	if not _backend_ready or is_open() or card_catalog == null:
		return
	if (
		_match_resolution_journal != null
		and _match_resolution_journal.has_pending()
	):
		call_deferred("_resume_pending_match_resolution")
		return
	if _match_context.qa_profile_override == null and not is_card_game_unlocked():
		push_warning("TripleTriadGame: card game is locked until the first card bundle is acquired.")
		return
	if _match_context.qa_profile_override == null and opponent_profile_override != null:
		var raw_opponent_id = opponent_profile_override.get("opponent_id")
		if raw_opponent_id != null and String(raw_opponent_id) != "":
			var direct_availability: Dictionary = get_opponent_availability(
				StringName(str(raw_opponent_id))
			)
			if not bool(direct_availability.get("available", false)):
				push_warning(
					"TripleTriadGame: opponent '%s' is locked: %s"
					% [
						str(raw_opponent_id),
						str(direct_availability.get("reason", "Unavailable.")),
					]
				)
				return
	var tree: SceneTree = get_tree()
	if tree == null or tree.paused:
		return
	_session.open_deck_setup(tree.paused)
	_match_context.resolve(opponent_profile_override)
	_opponent_collection_backend = OpponentCollectionScript.new()
	_opponent_collection_backend.initialize(
		card_catalog,
		_match_context.active_opponent_id(),
		_match_context.active_min_level,
		_match_context.active_max_level,
		_match_context.active_deck_budget,
		_match_context.active_opponent_profile
	)
	_invalidate_state_api("opponent_loaded")
	var active_player_budget: int = player_deck_budget
	var active_player_rank: int = player_card_rank
	if _progression != null:
		active_player_budget = int(_progression.get_deck_budget(player_deck_budget))
		active_player_rank = int(_progression.get_rank_number())
	_ui_flow.open_deck_setup(
		card_catalog,
		active_player_budget,
		active_player_rank,
		_collection_backend,
		acquisition_policy
	)
	tree.paused = true
	opened.emit()


func close_game() -> void:
	if not is_open():
		return
	var restore_pause: bool = _session.previous_pause
	ai_timer.stop()
	_ui_flow.close_session_surfaces()
	_presentation.hide_preview_visuals()
	_session.close_session()
	_persistence.checkpoint("close_game")
	_invalidate_state_api("close_game")
	_opponent_collection_backend = null
	var tree: SceneTree = get_tree()
	if tree != null:
		tree.paused = restore_pause
	closed.emit()


func _input(event: InputEvent) -> void:
	if not _backend_ready or _input_controller == null:
		return
	var action: StringName = _input_controller.action_for_event(event, OS.is_debug_build())
	if action == InputControllerScript.ACTION_CAMPAIGN_QA:
		_developer_tools.toggle_campaign_qa_menu()
		_accept_input()
		return

	if _developer_tools.is_campaign_qa_menu_open():
		if action != InputControllerScript.ACTION_NONE:
			_developer_tools.handle_campaign_qa_input(event)
			_accept_input()
		return

	if not is_open() or action == InputControllerScript.ACTION_NONE:
		return

	if _session.phase == PHASE_DECK_SETUP:
		return

	if _session.phase == PHASE_SURRENDER_CONFIRM:
		_handle_surrender_confirm_input(action)
		_accept_input()
		return

	# F10 belongs to the card-game QA overlay while Triple Triad is open. The
	# overlay is intentionally available only in stable phases so applying a
	# profile cannot collide with an in-flight placement/deal coroutine.
	if debug_menu.is_open():
		var close_requested: bool = bool(debug_menu.handle_input(event))
		if close_requested:
			debug_menu.close_menu()
		_accept_input()
		return

	if (
		action == InputControllerScript.ACTION_DEBUG
		and _input_controller.can_open_debug_overlay(_session.phase)
	):
		debug_menu.open_menu(
			_match_context.qa_base_summary,
			_match_context.qa_profile_override
		)
		_accept_input()


func _unhandled_input(event: InputEvent) -> void:
	if not _backend_ready or _input_controller == null:
		return
	var action: StringName = _input_controller.action_for_event(
		event,
		OS.is_debug_build()
	)
	if not is_open() or action == InputControllerScript.ACTION_NONE:
		return
	if _session.phase == PHASE_DECK_SETUP:
		return

	var route: Dictionary = _input_controller.route_gameplay_action(
		_session.phase,
		action,
		_match.player_hand.is_empty()
	)
	var command := StringName(route.get("command", &""))
	if command == InputControllerScript.COMMAND_RESULT_TRANSITION:
		_begin_result_transition()
	elif command == InputControllerScript.COMMAND_CLOSE:
		close_game()
	elif command == InputControllerScript.COMMAND_CONSUME:
		pass
	elif command == InputControllerScript.COMMAND_REQUEST_SURRENDER:
		_request_surrender()
	elif command == InputControllerScript.COMMAND_MOVE_HAND:
		_live_match.move_hand_selection(int(route.get("step", 0)))
		_refresh_views()
	elif command == InputControllerScript.COMMAND_ROTATE:
		_try_rotate_selected_card()
	elif command == InputControllerScript.COMMAND_BEGIN_CELL_SELECTION:
		_session.begin_player_cell_selection()
		_live_match.begin_cell_selection()
		_refresh_views()
	elif command == InputControllerScript.COMMAND_MOVE_BOARD:
		_live_match.move_board_selection(
			StringName(route.get("action", action)),
			_input_controller
		)
		_refresh_views()
	elif command == InputControllerScript.COMMAND_TRY_PLAYER_MOVE:
		_try_player_move()
	elif command == InputControllerScript.COMMAND_CANCEL_CELL_SELECTION:
		_session.cancel_player_cell_selection()
		_refresh_views()
	else:
		return
	_accept_input()


func _start_new_match(player_cards_override: Array = []) -> void:
	_match_orchestrator.start_new_match(
		player_cards_override,
		_opponent_collection_backend
	)


func _try_player_move() -> void:
	_match_orchestrator.try_player_move()


func _on_ai_timer_timeout() -> void:
	_match_orchestrator.on_ai_timer_timeout()


func _request_surrender() -> void:
	match _match_flow.request_surrender():
		&"close":
			close_game()
		&"confirm":
			ai_timer.stop()
			if not _ui_flow.open_surrender_confirm():
				_cancel_surrender_confirmation()


func _handle_surrender_confirm_input(action: StringName) -> void:
	var command: StringName = _input_controller.route_surrender_confirmation(
		action,
		_ui_flow.has_surrender_confirm(),
		_ui_flow.is_surrender_yes_selected()
	)
	if command == InputControllerScript.COMMAND_SURRENDER_MOVE:
		_ui_flow.move_surrender_selection()
	elif command == InputControllerScript.COMMAND_SURRENDER_CONFIRM:
		_confirm_surrender()
	elif command == InputControllerScript.COMMAND_SURRENDER_CANCEL:
		_cancel_surrender_confirmation()


func _confirm_surrender() -> void:
	_ui_flow.close_surrender_confirm()
	_match_flow.confirm_surrender()
	message_label.text = "SURRENDER"
	_finish_match(OWNER_OPPONENT, &"surrender")

func _cancel_surrender_confirmation() -> void:
	_ui_flow.close_surrender_confirm()
	var flow_result: Dictionary = _match_flow.cancel_surrender()
	_refresh_views()
	if bool(flow_result.get("schedule_ai", false)):
		_schedule_ai()

func _finish_match(
	forced_winner: int = OWNER_NONE,
	reason: StringName = &"board_complete"
) -> void:
	ai_timer.stop()
	_match_flow.finish_match(forced_winner, reason)
	_presentation.hide_preview_visuals()
	_refresh_views()
	var result_payload: Dictionary = _persistence.record_match_outcome(
		_match.get_score(),
		_session.result_winner,
		_session.result_reason,
		_session.surrendered,
		_live_match.get_starting_player_cards(),
		_live_match.get_starting_opponent_cards(),
		_opponent_collection_backend
	)

	_ui_flow.show_result(_session.result_winner, _session.surrendered)
	match_finished.emit(result_payload)


func _begin_result_transition() -> void:
	_match_orchestrator.begin_result_transition(
		_opponent_collection_backend
	)


func get_runtime_recovery_snapshot() -> Dictionary:
	if _runtime_recovery == null:
			return {}
	return _runtime_recovery.get_runtime_snapshot()


func reconcile_runtime_state() -> Dictionary:
	if _runtime_recovery == null:
		return {
			"success": false,
			"reason": "backend_not_ready",
		}
	return _runtime_recovery.reconcile_runtime_state()


func _resume_pending_match_resolution() -> void:
	if not _backend_ready or is_open():
		return
	var payload: Dictionary = (
		_runtime_recovery.build_pending_resolution_resume_payload()
	)
	if not bool(payload.get("success", false)):
		return

	var pending: Dictionary = payload.get("pending", {})
	var opponent_id := StringName(str(payload.get("opponent_id", "")))
	var winner: int = int(payload.get("winner", OWNER_NONE))
	var profile = payload.get("profile", null)
	var player_cards: Array = payload.get("player_cards", [])
	var opponent_cards: Array = payload.get("opponent_cards", [])

	var tree: SceneTree = get_tree()
	if tree == null:
		return
	_session.recover_reward_session(
		tree.paused,
		winner,
		StringName(str(payload.get("result_reason", "recovered"))),
		bool(payload.get("surrendered", false))
	)
	_match_context.resolve(profile)
	_opponent_collection_backend = OpponentCollectionScript.new()
	_opponent_collection_backend.initialize(
		card_catalog,
		opponent_id,
		_match_context.active_min_level,
		_match_context.active_max_level,
		_match_context.active_deck_budget,
		_match_context.active_opponent_profile
	)

	_live_match.install_recovery_state(player_cards, opponent_cards)

	_ui_flow.show_recovery_surface()
	_ui_flow.open_reward(
		opponent_cards,
		player_cards,
		winner,
		false,
		int(payload.get("opponent_take_index", -1)),
		payload.get("eligible_reward_ids", PackedStringArray()),
		false
	)
	_refresh_ui_flow()
	tree.paused = true
	opened.emit()
	_queue_gameplay_event(
		&"match_resolution_resumed",
		"Card Result Resumed",
		"Finish the interrupted reward before continuing.",
		pending,
		2
	)


func get_card_economy_snapshot() -> Dictionary:
	if _runtime_state == null:
		return {}
	return _runtime_state.get_card_economy_snapshot()


func _schedule_ai() -> void:
	_match_orchestrator.schedule_ai()


func _refresh_views(captured_cells: Array = []) -> void:
	if _match == null:
		return
	_presentation.refresh(
		_match,
		_session.phase,
		_match_context.active_rule_set,
		_live_match.selected_hand_index,
		_live_match.selected_cell_index,
		captured_cells
	)
	_refresh_ui_flow()
	runtime_state_changed.emit(get_runtime_ui_snapshot())

func _refresh_ui_flow() -> void:
	if _match == null:
		return
	_live_match.set_selected_hand_index(
		_ui_flow.refresh_match_state(
			_session.phase,
			_session.round_number,
			_match,
			_live_match.selected_hand_index,
			message_label.text,
			_match_context.region_trait_text(),
			_current_help_entries(),
			_match.get_score()
		)
	)

func _on_reward_selected(card_definition) -> void:
	var transfer_result: Dictionary = _persistence.commit_reward_transfer(
		card_definition,
		_session.result_winner,
		_opponent_collection_backend
	)
	_ui_flow.resolve_reward_transfer(
		bool(transfer_result.get("success", false))
	)


func _on_persistence_card_reward_selected(card_definition) -> void:
	card_reward_selected.emit(card_definition)



func _on_reward_completed() -> void:
	_ui_flow.close_reward()
	_persistence.complete_reward_resolution()
	if (
		_competition.should_continue_after_reward()
		and _continue_active_competition_round()
	):
		return
	_competition.clear_pending_change()
	close_game()



func _continue_active_competition_round() -> bool:
	var round_request: Dictionary = _competition.prepare_next_round()
	if not bool(round_request.get("success", false)):
		var reason: String = str(round_request.get("reason", ""))
		if reason == "invalid_locked_deck":
			push_warning(
				"TripleTriadGame: tournament deck lock is no longer legal; ending the attempt."
			)
		elif reason == "missing_opponent":
			push_error(
				"TripleTriadGame: tournament next opponent '%s' is missing."
				% str(round_request.get("opponent_id", ""))
			)
		return false

	var profile = round_request.get("profile", null)
	var locked_cards: Array = round_request.get("locked_cards", [])
	_session.reset_round()
	_match_context.resolve(profile)
	_opponent_collection_backend = OpponentCollectionScript.new()
	_opponent_collection_backend.initialize(
		card_catalog,
		_match_context.active_opponent_id(),
		_match_context.active_min_level,
		_match_context.active_max_level,
		_match_context.active_deck_budget,
		_match_context.active_opponent_profile
	)
	_live_match.set_active_player_deck(locked_cards)
	_start_new_match(_live_match.get_active_player_deck())
	return true


func _on_deck_confirmed(cards: Array) -> void:
	if _session.phase != PHASE_DECK_SETUP or cards.size() != 5:
		return
	_live_match.set_active_player_deck(cards)
	if _competition.is_match_active():
		if not _competition.lock_active_deck(
			_live_match.get_active_player_deck()
		):
			push_error(
				"TripleTriadGame: could not lock the tournament deck."
			)
			abandon_active_competition()
			close_game()
			return
	_ui_flow.close_deck_setup()
	_publish_backend_state_change("deck_selected")
	_start_new_match(_live_match.get_active_player_deck())


func _on_deck_cancelled() -> void:
	if _session.phase != PHASE_DECK_SETUP:
		return
	if _competition.is_match_active():
		abandon_active_competition()
	close_game()


func _on_qa_profile_apply_requested(selected_profile: Resource) -> void:
	_match_context.set_qa_profile(selected_profile)
	_start_new_match(_live_match.get_active_player_deck())


func _try_rotate_selected_card() -> void:
	var result: Dictionary = _live_match.try_rotate_selected_card()
	message_label.text = str(result.get("message", ""))
	_refresh_views()

func _current_help_entries() -> Array:
	return _live_match.current_help_entries(_session.phase)

func _accept_input() -> void:
	var viewport: Viewport = get_viewport()
	if viewport != null:
		viewport.set_input_as_handled()
