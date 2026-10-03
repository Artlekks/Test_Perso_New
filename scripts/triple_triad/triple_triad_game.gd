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

const MatchScript = preload("res://scripts/triple_triad/triple_triad_match.gd")
const AIScript = preload("res://scripts/triple_triad/triple_triad_ai.gd")
const OpponentCollectionScript = preload("res://scripts/triple_triad/triple_triad_opponent_collection.gd")
const DefaultOpponentRegistry = preload("res://data/triple_triad/opponents/opponent_registry.tres")
const DefaultAcquisitionRegistry = preload("res://data/triple_triad/acquisition/acquisition_registry.tres")
const DefaultAcquisitionPolicy = preload("res://data/triple_triad/acquisition/default_acquisition_policy.tres")
const StakePolicyScript = preload("res://scripts/triple_triad/triple_triad_stake_policy.gd")
const FishingSalvageBridgeScript = preload("res://scripts/triple_triad/triple_triad_fishing_salvage_bridge.gd")
const DefaultEconomyPolicy = preload("res://data/triple_triad/economy/default_economy_policy.tres")
const MatchResolutionJournalScript = preload("res://scripts/triple_triad/triple_triad_match_resolution_journal.gd")
const SessionControllerScript = preload(
	"res://scripts/triple_triad/triple_triad_session_controller.gd"
)
const MatchFlowControllerScript = preload(
	"res://scripts/triple_triad/triple_triad_match_flow_controller.gd"
)
const MatchResolutionControllerScript = preload(
	"res://scripts/triple_triad/triple_triad_match_resolution_controller.gd"
)
const PresentationControllerScript = preload(
	"res://scripts/triple_triad/triple_triad_presentation_controller.gd"
)
const InputControllerScript = preload(
	"res://scripts/triple_triad/triple_triad_input_controller.gd"
)
const UIFlowControllerScript = preload(
	"res://scripts/triple_triad/triple_triad_ui_flow_controller.gd"
)
const WorldGatewayScript = preload(
	"res://scripts/triple_triad/triple_triad_world_gateway.gd"
)
const CompetitionControllerScript = preload(
	"res://scripts/triple_triad/triple_triad_competition_controller.gd"
)
const RuntimeRecoveryControllerScript = preload(
	"res://scripts/triple_triad/triple_triad_runtime_recovery_controller.gd"
)
const BackendBootstrapScript = preload(
	"res://scripts/triple_triad/triple_triad_backend_bootstrap.gd"
)
const DeveloperToolsControllerScript = preload(
	"res://scripts/triple_triad/triple_triad_developer_tools_controller.gd"
)
const MatchContextControllerScript = preload(
	"res://scripts/triple_triad/triple_triad_match_context_controller.gd"
)
const RuntimeStateControllerScript = preload(
	"res://scripts/triple_triad/triple_triad_runtime_state_controller.gd"
)
const LiveMatchControllerScript = preload(
	"res://scripts/triple_triad/triple_triad_live_match_controller.gd"
)
const MatchOrchestratorScript = preload(
	"res://scripts/triple_triad/triple_triad_match_orchestrator.gd"
)

const BACKEND_VERSION := "2.16.0"

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

var _match = null
var _ai = null
var _rng := RandomNumberGenerator.new()
var _session = SessionControllerScript.new()
var _match_flow = MatchFlowControllerScript.new()
var _presentation = PresentationControllerScript.new()
var _input_controller = InputControllerScript.new()
var _ui_flow = UIFlowControllerScript.new()
var _world_gateway = WorldGatewayScript.new()
var _competition = CompetitionControllerScript.new()
var _runtime_recovery = RuntimeRecoveryControllerScript.new()
var _collection_backend = null
var _opponent_collection_backend = null
var _card_economy = null
var _progression = null
var _save_integrity = null
var _acquisition_tracker = null
var _acquisition_service = null
var _encounter_records = null
var _state_api = null
var _stake_policy = StakePolicyScript.new()
var _backend_ready: bool = false
var _backend_errors: PackedStringArray = PackedStringArray()
var _fishing_salvage_bridge: Node = null
var _world_acquisition_catalog = null
var _world_reward_ledger = null
var _competition_catalog = null
var _competition_service = null
var _completion_tracker = null
var _world_progression_director = null
var _match_resolution_journal = MatchResolutionJournalScript.new()
var _match_resolution = MatchResolutionControllerScript.new()
var _backend_bootstrap = BackendBootstrapScript.new()
var _developer_tools = DeveloperToolsControllerScript.new()
var _match_context = MatchContextControllerScript.new()
var _runtime_state = RuntimeStateControllerScript.new()
var _live_match = LiveMatchControllerScript.new()
var _match_orchestrator = MatchOrchestratorScript.new()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_runtime_state.initialize({
		"backend_version": BACKEND_VERSION,
		"developer_tools": _developer_tools,
		"session": _session,
		"match_context": _match_context,
		"presentation": _presentation,
		"event_capacity": 32,
	})
	_developer_tools.initialize(
		self,
		card_catalog,
		opponent_registry,
		BACKEND_VERSION,
		{
			&"is_backend_ready": Callable(self, "is_backend_ready"),
			&"is_card_game_unlocked": Callable(self, "is_card_game_unlocked"),
			&"get_player_snapshot": Callable(self, "get_player_snapshot"),
			&"get_acquisition_snapshot": Callable(self, "get_acquisition_snapshot"),
			&"get_collection_completion_snapshot": Callable(self, "get_collection_completion_snapshot"),
			&"get_runtime_recovery_snapshot": Callable(self, "get_runtime_recovery_snapshot"),
			&"get_backend_health": Callable(self, "get_backend_health"),
			&"get_global_triple_triad_snapshot": Callable(self, "get_global_triple_triad_snapshot"),
			&"get_pending_gameplay_events": Callable(self, "get_pending_gameplay_events"),
			&"open_active_competition_match": Callable(self, "open_active_competition_match"),
			&"reconcile_runtime_state": Callable(self, "reconcile_runtime_state"),
		}
	)
	_ui_flow.initialize({
		"root": root,
		"backdrop": backdrop,
		"grid_artwork": grid_artwork,
		"opponent_score_digits": opponent_score_label,
		"player_score_digits": player_score_label,
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
		"debug_menu": debug_menu,
		"deck_setup": deck_setup,
		"player_hand_container": player_hand_container,
	})
	_ui_flow.prepare_closed_state()
	_match = MatchScript.new()
	_ai = AIScript.new()
	_rng.randomize()
	_match_flow.initialize(_match, _ai, _rng, _session)
	_match_resolution_journal.initialize()

	_presentation.initialize(
		root,
		opponent_hand_container,
		board_container,
		player_hand_container
	)
	ai_timer.timeout.connect(_on_ai_timer_timeout)
	reward_view.reward_selected.connect(_on_reward_selected)
	reward_view.completed.connect(_on_reward_completed)
	debug_menu.apply_requested.connect(_on_qa_profile_apply_requested)
	deck_setup.deck_confirmed.connect(_on_deck_confirmed)
	deck_setup.cancelled.connect(_on_deck_cancelled)

	var bootstrap_result: Dictionary = _backend_bootstrap.bootstrap({
		"card_catalog": card_catalog,
		"rule_set": rule_set,
		"region_profile": region_profile,
		"opponent_registry": opponent_registry,
		"acquisition_policy": acquisition_policy,
		"acquisition_registry": acquisition_registry,
		"player_deck_budget": player_deck_budget,
	})
	var services: Dictionary = bootstrap_result.get("services", {})
	_world_acquisition_catalog = services.get("world_acquisition_catalog")
	_competition_catalog = services.get("competition_catalog")
	_save_integrity = services.get("save_integrity")
	_collection_backend = services.get("collection_backend")
	_acquisition_tracker = services.get("acquisition_tracker")
	_acquisition_service = services.get("acquisition_service")
	_progression = services.get("progression")
	_world_reward_ledger = services.get("world_reward_ledger")
	_encounter_records = services.get("encounter_records")
	_competition_service = services.get("competition_service")
	_completion_tracker = services.get("completion_tracker")
	_world_progression_director = services.get("world_progression_director")
	_card_economy = services.get("card_economy")
	_state_api = services.get("state_api")

	_backend_errors.clear()
	for raw_error in bootstrap_result.get("errors", []):
		_backend_errors.append(str(raw_error))
	for raw_warning in bootstrap_result.get("warnings", []):
		push_warning("TripleTriadGame backend: %s" % str(raw_warning))
	if not bool(bootstrap_result.get("success", false)):
		for error_text in _backend_errors:
			push_error("TripleTriadGame backend: %s" % error_text)
		push_error("TripleTriadGame: backend bootstrap failed; backend disabled for this session.")
		return

	_match_context.initialize(
		card_catalog,
		_rng,
		_encounter_records,
		{
			"region_profile": region_profile,
			"ai_profile": ai_profile,
			"rule_set": rule_set,
			"deck_budget": deck_budget,
			"min_level": prototype_min_level,
			"max_level": prototype_max_level,
		}
	)

	_live_match.initialize(
		_match,
		_match_flow,
		_match_context,
		_rng
	)

	_world_gateway.initialize(
		card_catalog,
		_acquisition_service,
		_world_acquisition_catalog,
		_world_reward_ledger,
		_collection_backend,
		_progression,
		_encounter_records,
		opponent_registry,
		_rng,
		player_card_rank
	)
	_world_gateway.acquisition_completed.connect(_on_acquisition_bundle_claimed)
	_world_gateway.card_game_unlock_changed.connect(_on_card_game_unlock_changed)
	_world_gateway.gameplay_event_requested.connect(_queue_gameplay_event)
	_world_gateway.save_checkpoint_requested.connect(_checkpoint_save_integrity)
	_world_gateway.backend_state_change_requested.connect(_publish_backend_state_change)

	_completion_tracker.milestone_reached.connect(_on_collection_milestone_reached)
	_completion_tracker.collection_completed.connect(_on_collection_completed)

	_match_resolution.initialize(
		card_catalog,
		_collection_backend,
		_progression,
		_encounter_records,
		_competition_service,
		_card_economy,
		_acquisition_tracker,
		_match_resolution_journal,
		_stake_policy,
		DefaultEconomyPolicy,
		DefaultAcquisitionPolicy
	)

	_competition.initialize(
		_competition_service,
		card_catalog,
		_collection_backend,
		_progression,
		_encounter_records,
		acquisition_policy,
		_world_gateway,
		_world_reward_ledger,
		opponent_registry,
		player_card_rank
	)
	_competition.competition_state_changed.connect(_on_competition_controller_state_changed)
	_competition.gameplay_event_requested.connect(_queue_gameplay_event)
	_competition.backend_state_change_requested.connect(_publish_backend_state_change)

	_match_orchestrator.initialize({
		"match_flow": _match_flow,
		"live_match": _live_match,
		"presentation": _presentation,
		"ui_flow": _ui_flow,
		"animation_director": animation_director,
		"ai_timer": ai_timer,
		"session": _session,
		"match_context": _match_context,
		"competition": _competition,
		"match_resolution": _match_resolution,
		"message_label": message_label,
		"transition_fade": transition_fade,
		"root": root,
		"ai_delay_seconds": ai_delay_seconds,
		"is_open": Callable(self, "is_open"),
		"refresh_views": Callable(self, "_refresh_views"),
		"refresh_ui_flow": Callable(self, "_refresh_ui_flow"),
		"finish_match": Callable(self, "_finish_match"),
		"close_game": Callable(self, "close_game"),
	})

	_runtime_recovery.initialize(
		_competition,
		card_catalog,
		_world_gateway,
		_world_reward_ledger,
		_match_resolution,
		_match_resolution_journal,
		deck_setup,
		opponent_registry
	)
	_runtime_recovery.gameplay_event_requested.connect(_queue_gameplay_event)
	_runtime_recovery.checkpoint_requested.connect(_checkpoint_save_integrity)
	_runtime_recovery.backend_state_change_requested.connect(_publish_backend_state_change)

	_runtime_state.initialize({
		"backend_version": BACKEND_VERSION,
		"state_api": _state_api,
		"completion_tracker": _completion_tracker,
		"world_progression_director": _world_progression_director,
		"world_gateway": _world_gateway,
		"competition": _competition,
		"runtime_recovery": _runtime_recovery,
		"developer_tools": _developer_tools,
		"session": _session,
		"match_context": _match_context,
		"presentation": _presentation,
		"save_integrity": _save_integrity,
		"collection_backend": _collection_backend,
		"match_resolution": _match_resolution,
		"encounter_records": _encounter_records,
		"event_capacity": 32,
	})
	_runtime_state.gameplay_event_queued.connect(_on_runtime_gameplay_event_queued)
	_runtime_state.backend_state_changed.connect(_on_runtime_backend_state_changed)
	_runtime_state.world_progression_changed.connect(_on_runtime_world_progression_changed)

	_checkpoint_save_integrity("boot")

	_backend_ready = true
	_world_gateway.set_backend_ready(true)
	_install_fishing_salvage_bridge()
	_developer_tools.bind_runtime(_world_reward_ledger)
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

func run_backend_qa() -> Dictionary:
	return _developer_tools.run_backend_qa()


func run_balance_simulation(
	games_per_matchup: int = 40,
	simulation_seed: int = 1337
) -> Dictionary:
	return _developer_tools.run_balance_simulation(
		games_per_matchup,
		simulation_seed
	)


func is_backend_ready() -> bool:
	return _backend_ready


func get_backend_health() -> Dictionary:
	return _runtime_state.get_backend_health(_backend_ready, _backend_errors)


func get_pending_gameplay_events() -> Array:
	return _runtime_state.get_pending_gameplay_events()


func pop_next_gameplay_event() -> Dictionary:
	return _runtime_state.pop_next_gameplay_event()


func clear_gameplay_events() -> void:
	_runtime_state.clear_gameplay_events()


func _queue_gameplay_event(
	event_type: StringName,
	title: String,
	detail: String = "",
	payload: Dictionary = {},
	priority: int = 0
) -> Dictionary:
	return _runtime_state.queue_gameplay_event(
		event_type,
		title,
		detail,
		payload,
		priority
	)


func get_state_api():
	return _runtime_state.get_state_api()


func get_player_snapshot() -> Dictionary:
	return _runtime_state.get_player_snapshot()


func get_collection_snapshot() -> Array:
	return _runtime_state.get_collection_snapshot()


func get_card_acquisition_sources(card_id: StringName) -> Array:
	return _world_gateway.get_card_acquisition_sources(card_id)


func get_acquisition_source_snapshot(
	source_type: StringName,
	source_id: StringName
) -> Dictionary:
	return _world_gateway.get_acquisition_source_snapshot(
		source_type,
		source_id
	)


func get_world_acquisition_sources() -> Array:
	return _world_gateway.get_world_acquisition_sources()


func claim_world_source_card(
	source_type: StringName,
	source_id: StringName,
	card_id: StringName,
	source_context: StringName = &""
) -> Dictionary:
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
	return _world_gateway.claim_fishing_salvage_reward(
		source_id,
		source_context
	)


func claim_treasure_cache_reward(
	source_id: StringName,
	cache_event_id: StringName,
	source_context: StringName = &""
) -> Dictionary:
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
	return _world_gateway.claim_tournament_card_reward(
		source_id,
		tournament_event_id,
		source_context,
		one_shot
	)


func advance_world_reward_counter(counter_id: StringName) -> int:
	return _world_gateway.advance_world_reward_counter(counter_id)


func get_world_reward_delivery_snapshot() -> Dictionary:
	return _world_gateway.get_world_reward_delivery_snapshot()


func has_world_reward_event_claimed(event_id: StringName) -> bool:
	return _world_gateway.has_world_reward_event_claimed(event_id)


func get_deck_profiles_snapshot() -> Array:
	return _runtime_state.get_deck_profiles_snapshot()


func get_opponent_snapshot(opponent_id: StringName) -> Dictionary:
	return _runtime_state.get_opponent_snapshot(opponent_id)


func get_opponents_snapshot() -> Array:
	return _runtime_state.get_opponents_snapshot()


func get_collection_completion_snapshot() -> Dictionary:
	return _runtime_state.get_collection_completion_snapshot()


func get_missing_card_diagnostics() -> Array:
	return _runtime_state.get_missing_card_diagnostics()


func get_source_completion_snapshot() -> Array:
	return _runtime_state.get_source_completion_snapshot()


func get_global_triple_triad_snapshot() -> Dictionary:
	return _runtime_state.get_global_snapshot()


func get_world_progression_snapshot() -> Dictionary:
	return _runtime_state.get_world_progression_snapshot()


func get_runtime_ui_snapshot() -> Dictionary:
	return _runtime_state.get_runtime_ui_snapshot(
		_match,
		_live_match.selected_hand_index,
		_live_match.selected_cell_index
	)


func _invalidate_state_api(reason: String = "") -> void:
	_runtime_state.invalidate_state_api(reason)


func _publish_backend_state_change(reason: String) -> void:
	_runtime_state.publish_backend_state_change(reason)


func is_open() -> bool:
	return _session.is_open()


func is_card_game_unlocked() -> bool:
	return _world_gateway.is_card_game_unlocked()


func get_acquisition_snapshot() -> Dictionary:
	return _world_gateway.get_acquisition_snapshot()


func claim_acquisition_bundle(
	bundle_id: StringName,
	source_context: StringName = &""
) -> Dictionary:
	return _world_gateway.claim_acquisition_bundle(
		bundle_id,
		source_context
	)


## Stable bridge for the fishing/exploration layer. Triple Triad owns bundle
## contents, one-shot persistence, collection writes, and unlock state.
func claim_salvaged_card_case(
	source_context: StringName = &"sea_salvage"
) -> Dictionary:
	return _world_gateway.claim_salvaged_card_case(source_context)


func get_onboarding_snapshot() -> Dictionary:
	return _world_gateway.get_onboarding_snapshot()


func _install_fishing_salvage_bridge() -> void:
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
	return _competition.get_competitive_snapshot()


func get_circuit_snapshot(circuit_id: StringName) -> Dictionary:
	return _competition.get_circuit_snapshot(circuit_id)


func get_competition_snapshot(competition_id: StringName) -> Dictionary:
	return _competition.get_competition_snapshot(competition_id)


func start_competition(competition_id: StringName) -> Dictionary:
	if not _backend_ready:
		return {"success": false, "reason": "backend_not_ready"}
	if not is_card_game_unlocked():
		return {"success": false, "reason": "card_game_locked"}
	return _competition.start_competition(competition_id)


func start_competition_and_open(competition_id: StringName) -> bool:
	var result: Dictionary = start_competition(competition_id)
	if not bool(result.get("success", false)):
		return false
	return open_active_competition_match()


func open_active_competition_match() -> bool:
	if is_open():
		return false
	var open_request: Dictionary = _competition.prepare_active_match_open()
	if not bool(open_request.get("success", false)):
		return false

	var opponent_id := StringName(str(open_request.get("opponent_id", "")))
	var locked_cards: Array = open_request.get("locked_cards", [])
	if not open_game_by_id(opponent_id):
		return false

	_competition.set_match_active(true)
	if locked_cards.size() == 5:
		_live_match.set_active_player_deck(locked_cards)
		_ui_flow.close_deck_setup()
		_start_new_match(_live_match.get_active_player_deck())
	return true


func abandon_active_competition() -> Dictionary:
	return _competition.abandon_active_competition()


func get_opponent_evolution_snapshot(
	opponent_id: StringName
) -> Dictionary:
	if (
		opponent_registry == null
		or not opponent_registry.has_method("get_opponent")
	):
		return {}
	var profile = opponent_registry.call("get_opponent", opponent_id)
	if profile == null:
		return {}
	return _match_context.build_opponent_evolution_snapshot(profile)


func get_active_opponent_evolution_snapshot() -> Dictionary:
	return _match_context.get_active_evolution_snapshot()


func get_opponent_availability(opponent_id: StringName) -> Dictionary:
	return _world_gateway.get_opponent_availability(opponent_id)


func get_available_card_player_ids(
	region_id: StringName = &"",
	required_tag: StringName = &""
) -> PackedStringArray:
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
	_checkpoint_save_integrity("close_game")
	_invalidate_state_api("close_game")
	_opponent_collection_backend = null
	var tree: SceneTree = get_tree()
	if tree != null:
		tree.paused = restore_pause
	closed.emit()


func _input(event: InputEvent) -> void:
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
	var score: Dictionary = _match.get_score()

	var resolution: Dictionary = _match_resolution.record_match_result(
		_session.result_winner,
		_session.result_reason,
		_session.surrendered,
		_match_context.active_opponent_profile,
		_match_context.active_opponent_id(),
		_match_context.qa_profile_override != null,
		_competition.is_match_active(),
		_live_match.get_starting_player_cards(),
		_live_match.get_starting_opponent_cards(),
		_opponent_collection_backend
	)
	var progression_change: Dictionary = (
		resolution.get("progression", {}) as Dictionary
	).duplicate(true)
	var competition_change: Dictionary = (
		_competition.apply_match_resolution(resolution)
	)

	if bool(progression_change.get("rank_up", false)):
		_queue_gameplay_event(
			&"duel_rank_up",
			"Duel Rank %d" % int(progression_change.get("rank_after", 1)),
			str(progression_change.get("rank_name", "")),
			progression_change,
			2
		)

	_ui_flow.show_result(_session.result_winner, _session.surrendered)
	match_finished.emit({
		"winner": _session.result_winner,
		"score": score,
		"progression": progression_change,
		"competition": competition_change,
		"reason": String(_session.result_reason),
		"surrendered": _session.surrendered,
	})
	_publish_backend_state_change("match_result")


func _begin_result_transition() -> void:
	_match_orchestrator.begin_result_transition(
		_opponent_collection_backend
	)


func get_runtime_recovery_snapshot() -> Dictionary:
	return _runtime_recovery.get_runtime_snapshot()


func reconcile_runtime_state() -> Dictionary:
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
	if card_definition == null:
		_ui_flow.resolve_reward_transfer(false)
		return

	var transfer_result: Dictionary = _match_resolution.commit_reward_transfer(
		card_definition,
		_session.result_winner,
		_match_context.active_opponent_id(),
		_opponent_collection_backend
	)
	if not bool(transfer_result.get("success", false)):
		var failure_reason: String = str(
			transfer_result.get("reason", "unknown")
		)
		match failure_reason:
			"economy_unavailable":
				push_error(
					"TripleTriadGame: card economy is unavailable during reward transfer."
				)
			"journal_selection_failed":
				push_error(
					"TripleTriadGame: could not journal the mandatory card selection."
				)
			"transfer_failed":
				push_error(
					"TripleTriadGame: failed to commit the mandatory card transfer."
				)
			_:
				push_error(
					"TripleTriadGame: reward transfer rejected (%s)."
					% failure_reason
				)
		_ui_flow.resolve_reward_transfer(false)
		return

	var metadata_ok: bool = bool(
		transfer_result.get("metadata_ok", false)
	)
	if _session.result_winner == OWNER_PLAYER:
		card_reward_selected.emit(card_definition)
		_queue_gameplay_event(
			&"opponent_card_won",
			str(card_definition.display_name),
			"Won from %s."
			% _match_context.active_opponent_display_name(),
			{
				"card_id": String(card_definition.card_id),
				"opponent_id": String(_match_context.active_opponent_id()),
			}
		)
	elif _session.result_winner == OWNER_OPPONENT:
		_queue_gameplay_event(
			&"card_lost",
			str(card_definition.display_name),
			"Lost to %s. Win it back in a rematch."
			% _match_context.active_opponent_display_name(),
			{
				"card_id": String(card_definition.card_id),
				"opponent_id": String(_match_context.active_opponent_id()),
			}
		)

		if bool(transfer_result.get("remove_from_decks", false)):
			deck_setup.remove_card_from_all_profiles(
				StringName(card_definition.card_id)
			)
			_live_match.remove_card_from_active_deck(
				StringName(card_definition.card_id)
			)

	if not metadata_ok:
		push_warning(
			"TripleTriadGame: ownership transfer succeeded but reward metadata reconciliation reported a problem."
		)

	_checkpoint_save_integrity("reward_transfer")
	_publish_backend_state_change("card_transfer")
	_ui_flow.resolve_reward_transfer(true)


func _checkpoint_save_integrity(reason: String) -> void:
	if _save_integrity == null:
		return
	if card_catalog == null or _collection_backend == null or _progression == null:
		return

	var report: Dictionary = _save_integrity.audit_and_checkpoint(
		card_catalog,
		_collection_backend,
		_progression,
		player_deck_budget,
		reason,
		acquisition_policy
	)
	if not bool(report.get("valid", true)):
		push_warning(
			"TripleTriadGame: save integrity checkpoint '%s' reported: %s"
			% [reason, str(report.get("warnings", []))]
		)
	_invalidate_state_api("integrity_checkpoint")



func _on_reward_completed() -> void:
	_ui_flow.close_reward()
	if _match_resolution_journal != null:
		_match_resolution_journal.clear()
	_checkpoint_save_integrity("reward_resolution_complete")
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


func _on_collection_milestone_reached(
	unique_card_count: int,
	snapshot: Dictionary
) -> void:
	_queue_gameplay_event(
		&"collection_milestone",
		"%d Cards Collected" % unique_card_count,
		"Collection progress: %.1f%%"
		% float(snapshot.get("completion_percent", 0.0)),
		{
			"unique_card_count": unique_card_count,
			"completion": snapshot,
		},
		1
	)


func _on_collection_completed(snapshot: Dictionary) -> void:
	_queue_gameplay_event(
		&"collection_complete",
		"179 / 179 Cards",
		"Card collection complete.",
		snapshot,
		3
	)


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
