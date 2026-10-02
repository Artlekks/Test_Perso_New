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
const CollectionScript = preload("res://scripts/triple_triad/triple_triad_collection.gd")
const OpponentCollectionScript = preload("res://scripts/triple_triad/triple_triad_opponent_collection.gd")
const CardEconomyScript = preload("res://scripts/triple_triad/triple_triad_card_economy.gd")
const ProgressionScript = preload("res://scripts/triple_triad/triple_triad_progression.gd")
const SaveIntegrityScript = preload("res://scripts/triple_triad/triple_triad_save_integrity.gd")
const DefaultOpponentRegistry = preload("res://data/triple_triad/opponents/opponent_registry.tres")
const AcquisitionTrackerScript = preload("res://scripts/triple_triad/triple_triad_acquisition_tracker.gd")
const AcquisitionServiceScript = preload("res://scripts/triple_triad/triple_triad_acquisition_service.gd")
const DefaultAcquisitionRegistry = preload("res://data/triple_triad/acquisition/acquisition_registry.tres")
const DefaultAcquisitionPolicy = preload("res://data/triple_triad/acquisition/default_acquisition_policy.tres")
const EncounterRecordsScript = preload("res://scripts/triple_triad/triple_triad_encounter_records.gd")
const StateAPIScript = preload("res://scripts/triple_triad/triple_triad_state_api.gd")
const StakePolicyScript = preload("res://scripts/triple_triad/triple_triad_stake_policy.gd")
const BalanceSimulatorScript = preload("res://scripts/triple_triad/triple_triad_balance_simulator.gd")
const FishingSalvageBridgeScript = preload("res://scripts/triple_triad/triple_triad_fishing_salvage_bridge.gd")
const WorldAcquisitionCatalogScript = preload("res://scripts/triple_triad/triple_triad_world_acquisition_catalog.gd")
const WorldRewardLedgerScript = preload("res://scripts/triple_triad/triple_triad_world_reward_ledger.gd")
const DefaultEconomyPolicy = preload("res://data/triple_triad/economy/default_economy_policy.tres")
const CompetitionCatalogScript = preload("res://scripts/triple_triad/triple_triad_competition_catalog.gd")
const CompetitionServiceScript = preload("res://scripts/triple_triad/triple_triad_competition_service.gd")
const CompletionTrackerScript = preload("res://scripts/triple_triad/triple_triad_completion_tracker.gd")
const WorldProgressionDirectorScript = preload("res://scripts/triple_triad/triple_triad_world_progression_director.gd")
const OpponentEvolutionScript = preload("res://scripts/triple_triad/triple_triad_opponent_evolution.gd")
const GameplayEventFeedScript = preload("res://scripts/triple_triad/triple_triad_gameplay_event_feed.gd")
const MatchResolutionJournalScript = preload("res://scripts/triple_triad/triple_triad_match_resolution_journal.gd")
const CampaignQAHarnessScript = preload("res://scripts/triple_triad/triple_triad_campaign_qa_harness.gd")
const CampaignQAMenuScene = preload("res://actors/TripleTriadCampaignQAMenu.tscn")
const PlaytestRecorderScript = preload("res://scripts/triple_triad/triple_triad_playtest_recorder.gd")
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

const BACKEND_VERSION := "2.9.0"

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

const HAND_STEP_Y := 47.0
const CAPTURE_SETTLE_SECONDS := 0.24
const RESULT_FADE_IN_SECONDS := 0.24
const RESULT_FADE_OUT_SECONDS := 0.30

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
var _selected_hand_index: int = 0
var _selected_cell_index: int = 4
var _starting_player_cards: Array = []
var _starting_opponent_cards: Array = []
var _last_info_name: String = ""
var _active_opponent_profile: Resource = null
var _active_region_profile: Resource = null
var _active_ai_profile: Resource = null
var _active_rule_set: Resource = null
var _active_deck_budget: int = 30
var _active_min_level: int = 1
var _active_max_level: int = 3
var _qa_profile_override: Resource = null
var _qa_forced_starting_owner: int = OWNER_NONE
var _qa_hand_seed: int = 0
var _qa_base_summary: Dictionary = {}
var _active_player_deck: Array = []
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
var _competition_match_active: bool = false
var _completion_tracker = null
var _world_progression_director = null
var _opponent_evolution = OpponentEvolutionScript.new()
var _active_opponent_evolution: Dictionary = {}
var _gameplay_event_feed = GameplayEventFeedScript.new()
var _match_resolution_journal = MatchResolutionJournalScript.new()
var _match_resolution = MatchResolutionControllerScript.new()
var _last_runtime_recovery: Dictionary = {}
var _pending_competition_change: Dictionary = {}
var _campaign_qa_harness = CampaignQAHarnessScript.new()
var _campaign_qa_menu: CanvasLayer = null
var _qa_playtest_recorder = PlaytestRecorderScript.new()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_campaign_qa_menu()
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
	_gameplay_event_feed.initialize(32)
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

	_world_acquisition_catalog = WorldAcquisitionCatalogScript.new()
	_world_acquisition_catalog.initialize(
		card_catalog,
		opponent_registry,
		acquisition_registry
	)

	_competition_catalog = CompetitionCatalogScript.new()
	_competition_catalog.initialize(
		opponent_registry,
		_world_acquisition_catalog
	)

	# Validate authored/static data before any subsystem is allowed to mutate a
	# persistent save. A broken catalog must never be able to sanitize good saves.
	if not _validate_static_backend():
		return

	_save_integrity = SaveIntegrityScript.new()
	var preflight_report: Dictionary = _save_integrity.preflight_restore_backups()
	if not bool(preflight_report.get("valid", true)):
		_backend_errors.append(
			"One or more Triple Triad saves are corrupt and have no valid backup: %s"
			% str(preflight_report.get("failed", []))
		)
		push_error(
			"TripleTriadGame: save preflight failed; backend disabled to avoid overwriting recoverable data."
		)
		return

	_collection_backend = CollectionScript.new()
	_collection_backend.initialize(card_catalog, acquisition_policy)

	_acquisition_tracker = AcquisitionTrackerScript.new()
	_acquisition_tracker.initialize(card_catalog)

	_acquisition_service = AcquisitionServiceScript.new()
	_acquisition_service.initialize(
		card_catalog,
		_collection_backend,
		_acquisition_tracker,
		acquisition_registry
	)
	_progression = ProgressionScript.new()
	_progression.initialize()

	_world_reward_ledger = WorldRewardLedgerScript.new()
	_world_reward_ledger.initialize()

	_encounter_records = EncounterRecordsScript.new()
	_encounter_records.initialize()

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
	_world_gateway.acquisition_completed.connect(
		_on_acquisition_bundle_claimed
	)
	_world_gateway.card_game_unlock_changed.connect(
		_on_card_game_unlock_changed
	)
	_world_gateway.gameplay_event_requested.connect(
		_queue_gameplay_event
	)
	_world_gateway.save_checkpoint_requested.connect(
		_checkpoint_save_integrity
	)
	_world_gateway.backend_state_change_requested.connect(
		_publish_backend_state_change
	)

	_competition_service = CompetitionServiceScript.new()
	_competition_service.initialize(_competition_catalog)

	_completion_tracker = CompletionTrackerScript.new()
	_completion_tracker.initialize(
		card_catalog,
		_collection_backend,
		_world_acquisition_catalog,
		_encounter_records,
		_progression,
		_competition_service,
		opponent_registry
	)
	_completion_tracker.milestone_reached.connect(
		_on_collection_milestone_reached
	)
	_completion_tracker.collection_completed.connect(
		_on_collection_completed
	)

	_world_progression_director = WorldProgressionDirectorScript.new()

	# Transfer journal recovery happens before the global save audit. If recovery
	# is still pending after the attempt, opening a new match would risk stacking
	# a second transaction on top of an unresolved one, so backend startup stops.
	_card_economy = CardEconomyScript.new()
	var recovery_ok: bool = _card_economy.recover_pending(
		card_catalog,
		_collection_backend
	)
	if (
		not recovery_ok
		and _card_economy.has_method("has_pending_transfer")
		and bool(_card_economy.call("has_pending_transfer"))
	):
		_backend_errors.append("A card-transfer recovery is still pending.")
		push_error("TripleTriadGame: unresolved card-transfer recovery; backend disabled for this session.")
		return

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

	_checkpoint_save_integrity("boot")

	_state_api = StateAPIScript.new()
	_state_api.initialize(
		card_catalog,
		_collection_backend,
		_progression,
		opponent_registry,
		_encounter_records,
		_acquisition_tracker,
		_acquisition_service,
		acquisition_policy,
		_world_acquisition_catalog,
		player_deck_budget
	)

	_backend_ready = true
	_world_gateway.set_backend_ready(true)
	_install_fishing_salvage_bridge()
	_last_runtime_recovery = reconcile_runtime_state()
	if OS.is_debug_build():
		_qa_playtest_recorder.append(
			&"session_start",
			{
				"backend_version": BACKEND_VERSION,
				"recovery": _last_runtime_recovery.duplicate(true),
			}
		)
	if bool(_last_runtime_recovery.get("requires_reward_ui", false)):
		call_deferred("_resume_pending_match_resolution")
	if OS.is_debug_build() and run_backend_qa_on_startup:
		_run_backend_qa()
	if OS.is_debug_build() and run_balance_simulation_on_startup:
		call_deferred(
			"run_balance_simulation",
			balance_games_per_matchup,
			balance_simulation_seed
		)


func _build_campaign_qa_menu() -> void:
	if not OS.is_debug_build() or _campaign_qa_menu != null:
		return
	_campaign_qa_menu = CampaignQAMenuScene.instantiate() as CanvasLayer
	add_child(_campaign_qa_menu)
	if _campaign_qa_menu.has_method("configure"):
		_campaign_qa_menu.call(
			"configure",
			_campaign_qa_harness
		)
	_campaign_qa_menu.connect(
		"scenario_requested",
		Callable(self, "_on_campaign_qa_scenario_requested")
	)
	_campaign_qa_menu.connect(
		"action_requested",
		Callable(self, "_on_campaign_qa_action_requested")
	)


func _campaign_qa_snapshot() -> Dictionary:
	return {
		"player": get_player_snapshot() if _backend_ready else {},
		"acquisition": get_acquisition_snapshot() if _backend_ready else {},
		"completion": (
			get_collection_completion_snapshot()
			if _backend_ready
			else {}
		),
		"recovery": _last_runtime_recovery.duplicate(true),
		"qa_snapshot": _campaign_qa_harness.get_qa_snapshot_info(),
		"playtest_log": _qa_playtest_recorder.get_info(),
	}


func _toggle_campaign_qa_menu() -> void:
	if _campaign_qa_menu == null:
		return
	if bool(_campaign_qa_menu.call("is_open")):
		_campaign_qa_menu.call("close_menu")
	else:
		_campaign_qa_menu.call(
			"open_menu",
			_campaign_qa_snapshot()
		)


func _on_campaign_qa_scenario_requested(
	scenario_id: StringName
) -> void:
	if not OS.is_debug_build():
		return
	var result: Dictionary = _campaign_qa_harness.apply_scenario(
		scenario_id,
		card_catalog
	)
	if not bool(result.get("success", false)):
		if _campaign_qa_menu != null:
			_campaign_qa_menu.call(
				"set_status",
				"FAILED: %s"
				% str(result.get("reason", "unknown"))
			)
		return
	_qa_playtest_recorder.append(
		&"qa_scenario_applied",
		result
	)
	_reload_scene_after_campaign_qa()


func _on_campaign_qa_action_requested(
	action_id: StringName
) -> void:
	if not OS.is_debug_build():
		return
	match action_id:
		&"arm_next_coast_salvage":
			if not _backend_ready or _world_reward_ledger == null:
				_campaign_qa_status("Backend unavailable.")
				return
			if not is_card_game_unlocked():
				_campaign_qa_status(
					"Card game is locked. Use Fresh / Undiscovered and catch the starter case first."
				)
				return
			var counter_id := StringName(
				"fishing_salvage:coast_shallows"
			)
			_world_reward_ledger.call(
				"reset_counter",
				counter_id
			)
			for _index in range(3):
				_world_reward_ledger.call(
					"increment_counter",
					counter_id
				)
			_campaign_qa_status(
				"Armed: next eligible Ocean 2 catch grants Coast Shallows salvage."
			)
		&"resume_active_tournament":
			if open_active_competition_match():
				_campaign_qa_menu.call("close_menu")
			else:
				_campaign_qa_status(
					"No resumable tournament round is active."
				)
		&"save_qa_snapshot":
			var save_result: Dictionary = (
				_campaign_qa_harness.save_qa_snapshot()
			)
			_campaign_qa_status(
				"QA Snapshot A saved (%d files)."
				% int(save_result.get("file_count", 0))
				if bool(save_result.get("success", false))
				else "QA Snapshot save FAILED."
			)
		&"restore_qa_snapshot":
			var restore_result: Dictionary = (
				_campaign_qa_harness.restore_qa_snapshot()
			)
			if bool(restore_result.get("success", false)):
				_qa_playtest_recorder.append(
					&"qa_snapshot_restored",
					restore_result
				)
				_reload_scene_after_campaign_qa()
			else:
				_campaign_qa_status(
					"Restore FAILED: %s"
					% str(restore_result.get("reason", "unknown"))
				)
		&"delete_qa_snapshot":
			var delete_result: Dictionary = (
				_campaign_qa_harness.delete_qa_snapshot()
			)
			_campaign_qa_status(
				"QA Snapshot A deleted."
				if bool(delete_result.get("success", false))
				else "QA Snapshot delete FAILED."
			)
		&"reset_decks":
			var result: Dictionary = (
				_campaign_qa_harness.reset_decks_only()
			)
			if bool(result.get("success", false)):
				_reload_scene_after_campaign_qa()
			else:
				_campaign_qa_status("Could not reset decks.")
		&"reconcile":
			var recovery: Dictionary = reconcile_runtime_state()
			_campaign_qa_status(
				"Reconcile: %s"
				% (
					"clean"
					if bool(recovery.get("valid", true))
					else "attention required"
				)
			)
		&"capture_qa_report":
			var report_result: Dictionary = _capture_campaign_qa_report()
			_campaign_qa_status(
				"Diagnostic report captured."
				if bool(report_result.get("success", false))
				else "Diagnostic report FAILED."
			)
		&"clear_playtest_log":
			_campaign_qa_status(
				"Playtest log cleared."
				if _qa_playtest_recorder.clear()
				else "Could not clear playtest log."
			)
		&"run_backend_qa":
			var report: Dictionary = run_backend_qa()
			_campaign_qa_status(
				"Backend QA: %d / %d passed"
				% [
					int(report.get("passed_count", 0)),
					int(report.get("test_count", 0)),
				]
			)


func _capture_campaign_qa_report() -> Dictionary:
	const REPORT_PATH := "user://triple_triad_qa_report.json"
	var tree: SceneTree = get_tree()
	var report := {
		"generated_time": Time.get_datetime_string_from_system(),
		"generated_unix": int(Time.get_unix_time_from_system()),
		"backend_version": BACKEND_VERSION,
		"engine": Engine.get_version_info(),
		"scene": (
			str(tree.current_scene.scene_file_path)
			if tree != null and tree.current_scene != null
			else ""
		),
		"tree_paused": tree.paused if tree != null else false,
		"backend_health": get_backend_health(),
		"global": (
			get_global_triple_triad_snapshot()
			if _backend_ready
			else {}
		),
		"recovery": get_runtime_recovery_snapshot(),
		"pending_gameplay_events": get_pending_gameplay_events(),
		"campaign_qa": _campaign_qa_snapshot(),
		"qa_snapshot": _campaign_qa_harness.get_qa_snapshot_info(),
		"playtest_log": _qa_playtest_recorder.get_info(),
	}
	var file := FileAccess.open(REPORT_PATH, FileAccess.WRITE)
	if file == null:
		return {
			"success": false,
			"reason": "report_open_failed",
		}
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	_qa_playtest_recorder.append(
		&"diagnostic_report_captured",
		{"path": REPORT_PATH}
	)
	return {
		"success": true,
		"path": REPORT_PATH,
	}


func _campaign_qa_status(text: String) -> void:
	if _campaign_qa_menu != null:
		_campaign_qa_menu.call("set_status", text)


func _reload_scene_after_campaign_qa() -> void:
	var tree: SceneTree = get_tree()
	if tree == null:
		return
	tree.paused = false
	tree.reload_current_scene()


func run_backend_qa() -> Dictionary:
	return _run_backend_qa()


func run_balance_simulation(
	games_per_matchup: int = 40,
	simulation_seed: int = 1337
) -> Dictionary:
	if card_catalog == null or opponent_registry == null:
		return {
			"valid": false,
			"errors": ["Card catalog or opponent registry is unavailable."],
		}
	var simulator = BalanceSimulatorScript.new()
	var report: Dictionary = simulator.run_registry_suite(
		card_catalog,
		opponent_registry,
		maxi(1, games_per_matchup),
		simulation_seed,
		true
	)
	if bool(report.get("valid", false)):
		var global: Dictionary = report.get("global", {})
		print(
			"TripleTriad Balance: %d games, first-player %.1f%% / second-player %.1f%% of decisive games, draw %.1f%%. Report: %s"
			% [
				int(global.get("games", 0)),
				float(global.get("first_player_win_rate", 0.0)) * 100.0,
				float(global.get("second_player_win_rate", 0.0)) * 100.0,
				float(global.get("draw_rate", 0.0)) * 100.0,
				str(report.get("report_path", "")),
			]
		)
		for raw_check in report.get("ladder_checks", []):
			var check: Dictionary = raw_check
			print(
				"  Ladder %s -> %s: %.1f%% decisive wins (%s)"
				% [
					str(check.get("lower_name", "?")),
					str(check.get("higher_name", "?")),
					float(check.get("higher_decisive_win_rate", 0.0)) * 100.0,
					str(check.get("status", "")),
				]
			)
	else:
		push_error(
			"TripleTriad Balance simulation failed: %s"
			% str(report.get("errors", []))
		)
	return report


func _run_backend_qa() -> Dictionary:
	# QA is deliberately loaded only when invoked. Shipping/runtime gameplay does
	# not have a hard preload dependency on the regression harness.
	var qa_script = load("res://scripts/triple_triad/triple_triad_backend_qa.gd")
	if qa_script == null:
		var missing_report := {
			"passed": false,
			"test_count": 0,
			"passed_count": 0,
			"failed_count": 1,
			"failures": ["QA harness missing"],
		}
		push_error("TripleTriadGame: backend QA harness could not be loaded.")
		return missing_report

	var qa_runner = qa_script.new()
	var report: Dictionary = qa_runner.run_all()
	if bool(report.get("passed", false)):
		print(
			"TripleTriad QA: %d/%d backend tests passed."
			% [
				int(report.get("passed_count", 0)),
				int(report.get("test_count", 0)),
			]
		)
	else:
		push_error(
			"TripleTriad QA: %d/%d tests failed: %s"
			% [
				int(report.get("failed_count", 0)),
				int(report.get("test_count", 0)),
				str(report.get("failures", [])),
			]
		)
		for result in report.get("results", []):
			if not bool(result.get("passed", false)):
				push_error(
					"  QA FAIL — %s: %s"
					% [
						str(result.get("name", "unknown")),
						str(result.get("error", "")),
					]
				)
	return report


func is_backend_ready() -> bool:
	return _backend_ready


func get_backend_health() -> Dictionary:
	return {
		"backend_version": BACKEND_VERSION,
		"ready": _backend_ready,
		"errors": _backend_errors.duplicate(),
		"save_integrity": (
			_save_integrity.get_last_report()
			if _save_integrity != null
			and _save_integrity.has_method("get_last_report")
			else {}
		),
	}


func _validate_static_backend() -> bool:
	_backend_ready = false
	_backend_errors.clear()

	if card_catalog == null:
		_backend_errors.append("Card catalog is missing.")
	elif card_catalog.has_method("validate_catalog"):
		var catalog_audit: Dictionary = card_catalog.call("validate_catalog")
		if not bool(catalog_audit.get("valid", false)):
			_backend_errors.append(
				"Invalid card catalog: %s" % str(catalog_audit.get("errors", []))
			)

	if region_profile != null and region_profile.has_method("validate_profile"):
		var default_region_audit: Dictionary = region_profile.call("validate_profile")
		if not bool(default_region_audit.get("valid", false)):
			_backend_errors.append(
				"Invalid default region profile: %s"
				% str(default_region_audit.get("errors", []))
			)
	if rule_set != null and rule_set.has_method("validate_runtime_support"):
		var default_rule_audit: Dictionary = rule_set.call("validate_runtime_support")
		if not bool(default_rule_audit.get("valid", false)):
			_backend_errors.append(
				"Invalid default rule set: %s"
				% str(default_rule_audit.get("errors", []))
			)

	if opponent_registry == null:
		_backend_errors.append("Opponent registry is missing.")
	elif opponent_registry.has_method("validate_registry"):
		var registry_audit: Dictionary = opponent_registry.call(
			"validate_registry",
			card_catalog
		)
		if not bool(registry_audit.get("valid", false)):
			_backend_errors.append(
				"Invalid opponent registry: %s"
				% str(registry_audit.get("errors", []))
			)
		for warning in registry_audit.get("warnings", []):
			push_warning("TripleTriadGame: %s" % str(warning))

	if acquisition_policy == null:
		_backend_errors.append("Acquisition policy is missing.")
	else:
		for required_method in [
			"can_use_card",
			"build_starting_collection",
			"get_card_lock_reason",
		]:
			if not acquisition_policy.has_method(required_method):
				_backend_errors.append(
					"Acquisition policy does not expose %s()." % required_method
				)

		if acquisition_policy.has_method("build_starting_collection") and card_catalog != null:
			var starter_cards: Array = acquisition_policy.call(
				"build_starting_collection",
				card_catalog
			)
			if starter_cards.size() < 5:
				_backend_errors.append(
					"Acquisition policy cannot build a five-card starter collection."
				)
			else:
				var starter_costs: Array[int] = []
				for card in starter_cards:
					if card != null:
						starter_costs.append(maxi(0, int(card.deck_cost)))
				starter_costs.sort()
				if starter_costs.size() < 5:
					_backend_errors.append("Starter collection contains invalid cards.")
				else:
					var cheapest_starter_deck: int = 0
					for index in range(5):
						cheapest_starter_deck += starter_costs[index]
					if cheapest_starter_deck > player_deck_budget:
						_backend_errors.append(
							"Starter collection cannot form a legal deck under the base player budget."
						)

	if acquisition_registry == null:
		_backend_errors.append("Acquisition registry is missing.")
	elif acquisition_registry.has_method("validate_registry"):
		var acquisition_audit: Dictionary = acquisition_registry.call(
			"validate_registry",
			card_catalog
		)
		if not bool(acquisition_audit.get("valid", false)):
			_backend_errors.append(
				"Invalid acquisition registry: %s"
				% str(acquisition_audit.get("errors", []))
			)
		for warning in acquisition_audit.get("warnings", []):
			push_warning("TripleTriadGame acquisition: %s" % str(warning))


	if _competition_catalog == null:
		_backend_errors.append("Competition catalog is missing.")
	elif _competition_catalog.has_method("validate_catalog"):
		var competition_audit: Dictionary = _competition_catalog.call(
			"validate_catalog"
		)
		if not bool(competition_audit.get("valid", false)):
			_backend_errors.append(
				"Invalid competition catalog: %s"
				% str(competition_audit.get("errors", []))
			)
		for warning in competition_audit.get("warnings", []):
			push_warning(
				"TripleTriadGame competition: %s" % str(warning)
			)

	if _world_acquisition_catalog == null:
		_backend_errors.append("World acquisition catalog is missing.")
	elif _world_acquisition_catalog.has_method("validate_map"):
		var world_acquisition_audit: Dictionary = _world_acquisition_catalog.call(
			"validate_map"
		)
		if not bool(world_acquisition_audit.get("valid", false)):
			_backend_errors.append(
				"Invalid world acquisition map: %s"
				% str(world_acquisition_audit.get("errors", []))
			)
		for warning in world_acquisition_audit.get("warnings", []):
			push_warning("TripleTriadGame acquisition map: %s" % str(warning))

	var progression_probe = ProgressionScript.new()
	if (
		progression_probe.progression_catalog == null
		or not progression_probe.progression_catalog.is_valid_catalog()
	):
		_backend_errors.append("Progression catalog is invalid.")

	for error_text in _backend_errors:
		push_error("TripleTriadGame backend: %s" % error_text)
	return _backend_errors.is_empty()


func get_pending_gameplay_events() -> Array:
	return _gameplay_event_feed.get_pending_events()


func pop_next_gameplay_event() -> Dictionary:
	return _gameplay_event_feed.pop_next_event()


func clear_gameplay_events() -> void:
	_gameplay_event_feed.clear()


func _queue_gameplay_event(
	event_type: StringName,
	title: String,
	detail: String = "",
	payload: Dictionary = {},
	priority: int = 0
) -> Dictionary:
	var event: Dictionary = _gameplay_event_feed.push_event(
		event_type,
		title,
		detail,
		payload,
		priority
	)
	gameplay_event_queued.emit(event.duplicate(true))
	if OS.is_debug_build():
		_qa_playtest_recorder.append(
			&"gameplay_event",
			event
		)
	return event


func get_state_api():
	return _state_api


func get_player_snapshot() -> Dictionary:
	return _state_api.get_player_snapshot() if _state_api != null else {}


func get_collection_snapshot() -> Array:
	return _state_api.get_collection_snapshot() if _state_api != null else []



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
	return _state_api.get_deck_profiles() if _state_api != null else []


func get_opponent_snapshot(opponent_id: StringName) -> Dictionary:
	return _state_api.get_opponent_snapshot(opponent_id) if _state_api != null else {}


func get_opponents_snapshot() -> Array:
	return _state_api.get_all_opponents_snapshot() if _state_api != null else []


func get_collection_completion_snapshot() -> Dictionary:
	if _completion_tracker == null:
		return {}
	return _completion_tracker.call("get_snapshot")


func get_missing_card_diagnostics() -> Array:
	var snapshot: Dictionary = get_collection_completion_snapshot()
	return snapshot.get("missing_cards", []).duplicate(true)


func get_source_completion_snapshot() -> Array:
	var snapshot: Dictionary = get_collection_completion_snapshot()
	return snapshot.get("source_progress", []).duplicate(true)


func get_global_triple_triad_snapshot() -> Dictionary:
	var snapshot: Dictionary = (
		_state_api.get_global_snapshot()
		if _state_api != null
		else {}
	)
	snapshot["runtime"] = {
		"backend_version": BACKEND_VERSION,
		"is_open": is_open(),
		"phase": _session.phase,
		"active_opponent_id": String(_active_opponent_id()) if is_open() else "",
	}
	snapshot["completion"] = get_collection_completion_snapshot()
	snapshot["competitive"] = get_competitive_snapshot()
	snapshot["world_progression"] = get_world_progression_snapshot()
	snapshot["recovery"] = get_runtime_recovery_snapshot()
	return snapshot


func get_world_progression_snapshot() -> Dictionary:
	if _world_progression_director == null:
		return {}
	return _world_progression_director.call(
		"build_snapshot",
		get_player_snapshot(),
		get_onboarding_snapshot(),
		get_competitive_snapshot(),
		get_collection_completion_snapshot(),
		get_available_card_player_ids()
	)


func get_runtime_ui_snapshot() -> Dictionary:
	var selected_card = null
	var selected_rotation: int = 0
	if (
		_match != null
		and _selected_hand_index >= 0
		and _selected_hand_index < _match.player_hand.size()
	):
		selected_card = _match.player_hand[_selected_hand_index]
		selected_rotation = _match.get_hand_rotation(
			OWNER_PLAYER,
			_selected_hand_index
		)

	var player_hand_snapshot: Array = []
	var opponent_hand_snapshot: Array = []
	if _match != null:
		for hand_index in range(_match.player_hand.size()):
			player_hand_snapshot.append(
				_runtime_card_snapshot(
					_match.player_hand[hand_index],
					_match.get_hand_rotation(OWNER_PLAYER, hand_index)
				)
			)
		var reveal_opponent: bool = (
			_active_rule_set == null
			or bool(_active_rule_set.open_rule)
		)
		for hand_index in range(_match.opponent_hand.size()):
			if reveal_opponent:
				opponent_hand_snapshot.append(
					_runtime_card_snapshot(
						_match.opponent_hand[hand_index],
						_match.get_hand_rotation(
							OWNER_OPPONENT,
							hand_index
						)
					)
				)
			else:
				opponent_hand_snapshot.append({"hidden": true})

	return {
		"schema_version": 2,
		"backend_version": BACKEND_VERSION,
		"is_open": is_open(),
		"phase": _session.phase,
		"phase_name": _phase_name(_session.phase),
		"round_number": _session.round_number,
		"match_started": _session.match_started,
		"current_owner": (
			int(_match.current_owner)
			if _match != null
			else OWNER_NONE
		),
		"selected_hand_index": _selected_hand_index,
		"selected_cell_index": _selected_cell_index,
		"selected_rotation": selected_rotation,
		"selected_card": (
			_runtime_card_snapshot(selected_card, selected_rotation)
			if selected_card != null
			else {}
		),
		"player_hand": player_hand_snapshot,
		"opponent_hand": opponent_hand_snapshot,
		"opponent_hand_count": (
			_match.opponent_hand.size()
			if _match != null
			else 0
		),
		"score": _match.get_score() if _match != null else {},
		"board_influence": (
			_match.get_influence_board_snapshot()
			if _match != null
			and _match.has_method("get_influence_board_snapshot")
			else []
		),
		"placement_preview": _presentation.get_placement_preview(
			_match,
			_session.phase,
			_selected_hand_index,
			_selected_cell_index
		),
		"can_surrender": (
			_session.match_started
			and _session.phase in [PHASE_SELECT_CARD, PHASE_AI]
		),
	}


func _runtime_card_snapshot(card, rotation_quarters: int = 0) -> Dictionary:
	if card == null:
		return {}
	var ranks: Array[int] = []
	for side in range(4):
		if card.has_method("rank_for_side_rotated"):
			ranks.append(int(card.call("rank_for_side_rotated", side, rotation_quarters)))
		else:
			ranks.append(int(card.call("rank_for_side", side)))
	return {
		"card_id": String(card.get("card_id")),
		"display_name": str(card.get("display_name")),
		"rotation": posmod(rotation_quarters, 4),
		"ranks": ranks,
		"deck_cost": int(card.get("deck_cost")),
		"influence": (
			card.call("get_influence_snapshot", rotation_quarters)
			if card.has_method("get_influence_snapshot")
			else {
				"mode": "none",
				"strength": 0,
				"display_name": "None",
				"description": "This card does not project Influence.",
				"rotation_quarters": posmod(rotation_quarters, 4),
				"offsets": [],
				"grid": {
					"width": 1,
					"height": 1,
					"origin": [0, 0],
					"cells": [[2]],
				},
			}
		),
	}


func _phase_name(phase_value: int) -> String:
	match phase_value:
		PHASE_CLOSED:
			return "closed"
		PHASE_DEALING:
			return "dealing"
		PHASE_SELECT_CARD:
			return "select_card"
		PHASE_SELECT_CELL:
			return "select_cell"
		PHASE_ANIMATING:
			return "animating"
		PHASE_AI:
			return "ai"
		PHASE_RESULT:
			return "result"
		PHASE_REWARD:
			return "reward"
		PHASE_DECK_SETUP:
			return "deck_setup"
		_:
			return "unknown"


func _invalidate_state_api(reason: String = "") -> void:
	if _state_api != null and _state_api.has_method("invalidate"):
		_state_api.call("invalidate", reason)


func _publish_backend_state_change(reason: String) -> void:
	if _completion_tracker != null:
		_completion_tracker.call("refresh", reason, true)
	_invalidate_state_api(reason)
	backend_state_changed.emit(reason)
	if _world_progression_director != null:
		world_progression_changed.emit(
			get_world_progression_snapshot()
		)


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
	if _competition_service == null:
		return {}
	var player_rank: int = (
		_progression.get_rank_number()
		if _progression != null
		else maxi(1, player_card_rank)
	)
	var beaten_ids := PackedStringArray()
	if _encounter_records != null:
		beaten_ids = _encounter_records.call("get_beaten_opponent_ids")
	return _competition_service.call("get_snapshot", player_rank, beaten_ids)


func get_circuit_snapshot(circuit_id: StringName) -> Dictionary:
	if _competition_service == null:
		return {}
	var player_rank: int = (
		_progression.get_rank_number()
		if _progression != null
		else maxi(1, player_card_rank)
	)
	var beaten_ids := PackedStringArray()
	if _encounter_records != null:
		beaten_ids = _encounter_records.call("get_beaten_opponent_ids")
	return _competition_service.call(
		"get_circuit_snapshot",
		circuit_id,
		player_rank,
		beaten_ids
	)


func get_competition_snapshot(competition_id: StringName) -> Dictionary:
	if _competition_service == null:
		return {}
	var player_rank: int = (
		_progression.get_rank_number()
		if _progression != null
		else maxi(1, player_card_rank)
	)
	var beaten_ids := PackedStringArray()
	if _encounter_records != null:
		beaten_ids = _encounter_records.call("get_beaten_opponent_ids")
	return _competition_service.call(
		"get_competition_snapshot",
		competition_id,
		player_rank,
		beaten_ids
	)


func start_competition(competition_id: StringName) -> Dictionary:
	if not _backend_ready:
		return {"success": false, "reason": "backend_not_ready"}
	if not is_card_game_unlocked():
		return {"success": false, "reason": "card_game_locked"}
	if _competition_service == null:
		return {"success": false, "reason": "competition_service_unavailable"}

	var player_rank: int = (
		_progression.get_rank_number()
		if _progression != null
		else maxi(1, player_card_rank)
	)
	var beaten_ids := PackedStringArray()
	if _encounter_records != null:
		beaten_ids = _encounter_records.call("get_beaten_opponent_ids")

	var result: Dictionary = _competition_service.call(
		"start_competition",
		competition_id,
		player_rank,
		beaten_ids
	)
	if bool(result.get("success", false)):
		var snapshot: Dictionary = get_competitive_snapshot()
		competition_state_changed.emit(snapshot.duplicate(true))
		_publish_backend_state_change("competition_started")
	return result


func start_competition_and_open(competition_id: StringName) -> bool:
	var result: Dictionary = start_competition(competition_id)
	if not bool(result.get("success", false)):
		return false
	return open_active_competition_match()


func open_active_competition_match() -> bool:
	if _competition_service == null or is_open():
		return false
	var opponent_id: StringName = _competition_service.call(
		"get_active_opponent_id"
	)
	if opponent_id == &"":
		return false

	var locked_cards: Array = _get_competition_locked_deck_cards()
	var opened_ok: bool = open_game_by_id(opponent_id)
	if not opened_ok:
		return false

	_competition_match_active = true
	if locked_cards.size() == 5:
		_active_player_deck = locked_cards.duplicate()
		_ui_flow.close_deck_setup()
		_start_new_match(_active_player_deck)
	return true


func abandon_active_competition() -> Dictionary:
	if _competition_service == null:
		return {"success": false, "reason": "competition_service_unavailable"}
	var result: Dictionary = _competition_service.call(
		"abandon_active_competition"
	)
	if bool(result.get("success", false)):
		_competition_match_active = false
		competition_state_changed.emit(get_competitive_snapshot())
		_publish_backend_state_change("competition_abandoned")
	return result


func _get_competition_locked_deck_cards() -> Array:
	var result: Array = []
	if _competition_service == null:
		return result
	var raw_ids = _competition_service.call("get_locked_deck_ids")
	if not (raw_ids is PackedStringArray or raw_ids is Array):
		return result
	if raw_ids.size() != 5:
		return result

	var player_rank: int = (
		_progression.get_rank_number()
		if _progression != null
		else maxi(1, player_card_rank)
	)
	for raw_id in raw_ids:
		var card_id := StringName(str(raw_id))
		var card = null
		if card_catalog != null:
			card = card_catalog.get_card_by_id(card_id)
		if card == null:
			return []
		if (
			_collection_backend == null
			or _collection_backend.get_quantity_by_id(card_id) <= 0
		):
			return []
		if (
			acquisition_policy != null
			and acquisition_policy.has_method("can_use_card")
			and not bool(
				acquisition_policy.call(
					"can_use_card",
					card,
					player_rank
				)
			)
		):
			return []
		result.append(card)
	return result


func _lock_active_competition_deck(cards: Array) -> bool:
	if _competition_service == null or cards.size() != 5:
		return false
	if bool(_competition_service.call("has_locked_deck")):
		return true
	var ids := PackedStringArray()
	for card in cards:
		if card == null:
			return false
		var card_id: String = str(card.get("card_id"))
		if card_id.is_empty() or ids.has(card_id):
			return false
		ids.append(card_id)
	return bool(
		_competition_service.call(
			"set_locked_deck_ids",
			ids
		)
	)


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
	var encounter_snapshot: Dictionary = {}
	if _encounter_records != null:
		encounter_snapshot = _encounter_records.get_snapshot(opponent_id)
	return _opponent_evolution.build_snapshot(
		profile,
		encounter_snapshot
	)


func get_active_opponent_evolution_snapshot() -> Dictionary:
	return _active_opponent_evolution.duplicate(true)


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


func _on_acquisition_bundle_claimed(result: Dictionary) -> void:
	acquisition_completed.emit(result.duplicate(true))


func _on_card_game_unlock_changed(unlocked: bool) -> void:
	card_game_unlock_changed.emit(unlocked)


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

	if _competition_service != null:
		var active_competition: Dictionary = _competition_service.call(
			"get_active_snapshot"
		)
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
	if _qa_profile_override == null and not is_card_game_unlocked():
		push_warning("TripleTriadGame: card game is locked until the first card bundle is acquired.")
		return
	if _qa_profile_override == null and opponent_profile_override != null:
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
	_resolve_active_configuration(opponent_profile_override)
	_opponent_collection_backend = OpponentCollectionScript.new()
	_opponent_collection_backend.initialize(
		card_catalog,
		_active_opponent_id(),
		_active_min_level,
		_active_max_level,
		_active_deck_budget,
		_active_opponent_profile
	)
	_invalidate_state_api("opponent_loaded")
	_ui_flow.open_deck_setup(
		card_catalog,
		_progression.get_deck_budget(player_deck_budget) if _progression != null else player_deck_budget,
		_progression.get_rank_number() if _progression != null else player_card_rank,
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
		_toggle_campaign_qa_menu()
		_accept_input()
		return

	if (
		_campaign_qa_menu != null
		and bool(_campaign_qa_menu.call("is_open"))
	):
		if action != InputControllerScript.ACTION_NONE:
			var close_requested: bool = bool(
				_campaign_qa_menu.call(
					"handle_input",
					event
				)
			)
			if close_requested:
				_campaign_qa_menu.call("close_menu")
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

	if action == InputControllerScript.ACTION_DEBUG and _session.phase in [PHASE_SELECT_CARD, PHASE_SELECT_CELL, PHASE_RESULT]:
		debug_menu.open_menu(_qa_base_summary, _qa_profile_override)
		_accept_input()


func _unhandled_input(event: InputEvent) -> void:
	var action: StringName = _input_controller.action_for_event(event, OS.is_debug_build())
	if not is_open() or action == InputControllerScript.ACTION_NONE:
		return

	if _session.phase == PHASE_DECK_SETUP:
		return

	# The reward view owns input while it is active and enforces mandatory stake
	# resolution. It cannot be bypassed with Back/Escape.
	if _session.phase == PHASE_REWARD:
		return

	if _session.phase == PHASE_RESULT:
		if action == InputControllerScript.ACTION_CONFIRM or action == InputControllerScript.ACTION_BACK:
			_begin_result_transition()
			_accept_input()
		return

	# Before the deal is complete the player can still leave freely. Once the
	# live match begins, leaving from a stable gameplay phase is a surrender.
	if _session.phase == PHASE_DEALING:
		if action == InputControllerScript.ACTION_BACK:
			close_game()
			_accept_input()
		return

	# Placement/capture animation is transactional. Ignore leave input until a
	# stable phase instead of interrupting a move half-way through.
	if _session.phase == PHASE_ANIMATING:
		if action == InputControllerScript.ACTION_BACK:
			_accept_input()
		return

	if _session.phase == PHASE_AI:
		if action == InputControllerScript.ACTION_BACK:
			_request_surrender()
			_accept_input()
		return

	if _session.phase == PHASE_SELECT_CARD:
		var hand_step: int = _input_controller.hand_step(action)
		if hand_step != 0:
			_selected_hand_index = clampi(
				_selected_hand_index + hand_step,
				0,
				maxi(_match.player_hand.size() - 1, 0)
			)
			_refresh_views()
			_accept_input()
			return
		if action == InputControllerScript.ACTION_ROTATE:
			_try_rotate_selected_card()
			_accept_input()
			return
		if action == InputControllerScript.ACTION_CONFIRM and not _match.player_hand.is_empty():
			_session.begin_player_cell_selection()
			_selected_cell_index = _find_nearest_empty_cell(_selected_cell_index)
			_refresh_views()
			_accept_input()
			return
		if action == InputControllerScript.ACTION_BACK:
			_request_surrender()
			_accept_input()
			return

	if _session.phase == PHASE_SELECT_CELL:
		var moved: bool = false
		if action == InputControllerScript.ACTION_LEFT:
			_selected_cell_index = _input_controller.move_board_cursor(_selected_cell_index, action)
			moved = true
		elif action == InputControllerScript.ACTION_RIGHT:
			_selected_cell_index = _input_controller.move_board_cursor(_selected_cell_index, action)
			moved = true
		elif action == InputControllerScript.ACTION_UP:
			_selected_cell_index = _input_controller.move_board_cursor(_selected_cell_index, action)
			moved = true
		elif action == InputControllerScript.ACTION_DOWN:
			_selected_cell_index = _input_controller.move_board_cursor(_selected_cell_index, action)
			moved = true
		if moved:
			_refresh_views()
			_accept_input()
			return
		if action == InputControllerScript.ACTION_ROTATE:
			_try_rotate_selected_card()
			_accept_input()
			return
		if action == InputControllerScript.ACTION_CONFIRM:
			_try_player_move()
			_accept_input()
			return
		if action == InputControllerScript.ACTION_BACK:
			# First Back cancels the board preview and returns to the hand. A second
			# Back from card selection is the deliberate surrender action.
			_session.cancel_player_cell_selection()
			_refresh_views()
			_accept_input()


func _start_new_match(player_cards_override: Array = []) -> void:
	ai_timer.stop()
	_ui_flow.prepare_new_match()
	_pending_competition_change.clear()
	_last_info_name = ""

	if _qa_hand_seed > 0:
		_rng.seed = _qa_hand_seed

	var player_cards: Array = []
	if player_cards_override.size() == 5:
		player_cards = player_cards_override.duplicate()
	elif _active_player_deck.size() == 5:
		player_cards = _active_player_deck.duplicate()
	else:
		player_cards = _build_budgeted_hand(_active_min_level, _active_max_level)
	var opponent_cards: Array = []
	if _opponent_collection_backend != null:
		opponent_cards = _opponent_collection_backend.build_match_deck(
			5,
			_active_deck_budget,
			_active_opponent_evolution
		)
	if opponent_cards.size() != 5:
		push_error("TripleTriadGame: opponent %s has no legal persistent deck." % String(_active_opponent_id()))
		message_label.text = "Opponent deck is invalid."
		close_game()
		return

	var starting_owner: int
	match _qa_forced_starting_owner:
		OWNER_PLAYER:
			starting_owner = OWNER_PLAYER
		OWNER_OPPONENT:
			starting_owner = OWNER_OPPONENT
		_:
			starting_owner = OWNER_PLAYER if _rng.randi_range(0, 1) == 0 else OWNER_OPPONENT
	var flow: Dictionary = _match_flow.prepare_match(
		player_cards, opponent_cards, starting_owner, _active_rule_set, _active_region_profile
	)
	if not bool(flow.get("success", false)):
		push_error("TripleTriadGame: match flow setup failed: %s" % str(flow.get("reason", "unknown")))
		close_game()
		return
	_starting_player_cards = player_cards.duplicate()
	_starting_opponent_cards = opponent_cards.duplicate()
	_selected_hand_index = int(flow.get("selected_hand_index", 0))
	_selected_cell_index = int(flow.get("selected_cell_index", 4))
	_refresh_views()
	_run_deal_sequence(int(flow.get("starting_owner", starting_owner)))

func _run_deal_sequence(starting_owner: int) -> void:
	await animation_director.deal_hands(
		_presentation.get_player_views(),
		_presentation.get_opponent_views(),
		HAND_STEP_Y
	)
	if not is_open() or _session.phase != PHASE_DEALING:
		return
	var flow_result: Dictionary = _match_flow.complete_deal(starting_owner)
	if not bool(flow_result.get("success", false)):
		return
	message_label.text = ""
	_refresh_views()
	if bool(flow_result.get("schedule_ai", false)):
		_schedule_ai()

func _try_player_move() -> void:
	var flow: Dictionary = _match_flow.commit_player_move(
		_selected_hand_index,
		_selected_cell_index
	)
	if not bool(flow.get("success", false)):
		message_label.text = "That space is occupied." if str(flow.get("reason", "")) == "occupied" else "Invalid move."
		return

	var hand_index: int = int(flow.get("hand_index", 0))
	var cell_index: int = int(flow.get("cell_index", 0))
	var played_card = flow.get("played_card")
	var result: Dictionary = flow.get("result", {})
	_selected_hand_index = int(flow.get("next_hand_index", _selected_hand_index))
	_last_info_name = str(played_card.display_name)
	_refresh_ui_flow()
	await animation_director.animate_placement(
		root, _presentation.get_player_view(hand_index), _presentation.get_board_view(cell_index), played_card,
		OWNER_PLAYER, int(flow.get("played_rotation", 0)), int(flow.get("placement_rank_modifier", 0))
	)
	if not is_open():
		return

	message_label.text = _capture_message(result)
	var captured_cells: Array = result.get("captured", [])
	_refresh_views(captured_cells)
	if not captured_cells.is_empty():
		await animation_director.wait_for_settle(CAPTURE_SETTLE_SECONDS)
		if not is_open():
			return

	match _match_flow.complete_player_move(result):
		&"finish":
			_finish_match()
		&"schedule_ai":
			_refresh_views()
			_schedule_ai()

func _on_ai_timer_timeout() -> void:
	if not _match_flow.can_run_ai_timer():
		return
	_run_ai_turn()

func _run_ai_turn() -> void:
	var flow: Dictionary = _match_flow.commit_ai_move(_active_ai_profile)
	if not bool(flow.get("success", false)):
		if bool(flow.get("finish", false)):
			_finish_match()
		return

	var hand_index: int = int(flow.get("hand_index", 0))
	var cell_index: int = int(flow.get("cell_index", 0))
	var played_card = flow.get("played_card")
	var result: Dictionary = flow.get("result", {})
	_last_info_name = str(played_card.display_name)
	_refresh_ui_flow()
	await animation_director.animate_placement(
		root, _presentation.get_opponent_view(hand_index), _presentation.get_board_view(cell_index), played_card,
		OWNER_OPPONENT, int(flow.get("played_rotation", 0)), int(flow.get("placement_rank_modifier", 0))
	)
	if not is_open():
		return

	message_label.text = _capture_message(result)
	var captured_cells: Array = result.get("captured", [])
	_refresh_views(captured_cells)
	if not captured_cells.is_empty():
		await animation_director.wait_for_settle(CAPTURE_SETTLE_SECONDS)
		if not is_open():
			return

	var next_step: Dictionary = _match_flow.complete_ai_move(
		result, _selected_hand_index, _selected_cell_index
	)
	if StringName(next_step.get("action", &"")) == &"finish":
		_finish_match()
		return
	_selected_hand_index = int(next_step.get("selected_hand_index", _selected_hand_index))
	_selected_cell_index = int(next_step.get("selected_cell_index", _selected_cell_index))
	_refresh_views()

func _request_surrender() -> void:
	match _match_flow.request_surrender():
		&"close":
			close_game()
		&"confirm":
			ai_timer.stop()
			if not _ui_flow.open_surrender_confirm():
				_cancel_surrender_confirmation()

func _handle_surrender_confirm_input(action: StringName) -> void:
	if not _ui_flow.has_surrender_confirm():
		_cancel_surrender_confirmation()
		return

	if _input_controller.is_direction(action):
		_ui_flow.move_surrender_selection()
		return

	if action == InputControllerScript.ACTION_BACK:
		_cancel_surrender_confirmation()
		return

	if action == InputControllerScript.ACTION_CONFIRM:
		if _ui_flow.is_surrender_yes_selected():
			_confirm_surrender()
		else:
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
		_active_opponent_profile,
		_active_opponent_id(),
		_qa_profile_override != null,
		_competition_match_active,
		_starting_player_cards,
		_starting_opponent_cards,
		_opponent_collection_backend
	)
	var progression_change: Dictionary = (
		resolution.get("progression", {}) as Dictionary
	).duplicate(true)
	var competition_change: Dictionary = (
		resolution.get("competition", {}) as Dictionary
	).duplicate(true)
	_competition_match_active = bool(
		resolution.get(
			"competition_match_active",
			_competition_match_active
		)
	)
	if bool(resolution.get("competition_state_changed", false)):
		competition_state_changed.emit(get_competitive_snapshot())

	if bool(competition_change.get("completed", false)):
		competition_change["tournament_reward"] = (
			_resolve_pending_competition_reward()
		)

	_pending_competition_change = competition_change.duplicate(true)
	if bool(competition_change.get("round_won", false)):
		_queue_gameplay_event(
			&"tournament_round_won",
			"Round Won",
			"Next opponent: %s"
			% str(competition_change.get("next_opponent_id", "")),
			competition_change
		)
	elif bool(competition_change.get("failed", false)):
		_queue_gameplay_event(
			&"tournament_failed",
			"Tournament Attempt Ended",
			"Return when you are ready to try again.",
			competition_change
		)
	elif bool(competition_change.get("completed", false)):
		_queue_gameplay_event(
			&"tournament_cleared",
			"Tournament Cleared",
			str(competition_change.get("title_awarded", "")),
			competition_change,
			2
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
	var flow_result: Dictionary = _match_flow.begin_result_transition()
	if not bool(flow_result.get("accepted", false)):
		return
	_ui_flow.begin_result_transition_ui()
	_run_result_transition(int(flow_result.get("winner", OWNER_NONE)))

func _run_result_transition(winner: int) -> void:
	await animation_director.fade_to_cover(
		transition_fade,
		RESULT_FADE_IN_SECONDS
	)
	if not is_open():
		return

	_ui_flow.hide_result_overlay()
	var destination: StringName = _match_flow.prepare_result_destination(winner)
	if destination == &"replay":
		# A draw is a replay, not an exit. Re-deal behind the black result fade,
		# then reveal the fresh match using the same active QA/opponent profile.
		_start_new_match(_active_player_deck)
		await animation_director.fade_from_cover(
			transition_fade,
			RESULT_FADE_OUT_SECONDS
		)
		if not is_open():
			return
		return
	if destination != &"reward":
		return

	var reward_presentation: Dictionary = (
		_match_resolution.prepare_reward_presentation(
			winner,
			_active_opponent_profile,
			_active_opponent_id(),
			_starting_player_cards,
			_starting_opponent_cards,
			_opponent_collection_backend
		)
	)
	var opponent_take_index: int = int(
		reward_presentation.get("opponent_take_index", -1)
	)
	var eligible_reward_ids := PackedStringArray()
	var raw_eligible = reward_presentation.get(
		"eligible_reward_ids",
		PackedStringArray()
	)
	if raw_eligible is PackedStringArray or raw_eligible is Array:
		for raw_id in raw_eligible:
			eligible_reward_ids.append(str(raw_id))
	_ui_flow.open_reward(
		_starting_opponent_cards,
		_starting_player_cards,
		winner,
		true,
		opponent_take_index,
		eligible_reward_ids,
		true
	)
	_refresh_ui_flow()

	# Reveal the result screen while both card rows begin sliding into place.
	await animation_director.fade_from_cover(
		transition_fade,
		RESULT_FADE_OUT_SECONDS
	)
	if not is_open():
		return

func _cards_from_ids(card_ids) -> Array:
	var result: Array = []
	if card_catalog == null:
		return result
	if not (card_ids is PackedStringArray or card_ids is Array):
		return result
	for raw_id in card_ids:
		var card = card_catalog.get_card_by_id(
			StringName(str(raw_id))
		)
		if card == null:
			return []
		result.append(card)
	return result


func _reconcile_pending_world_reward_deliveries() -> Dictionary:
	var report := {
		"pending_before": 0,
		"resolved": 0,
		"failed": 0,
	}
	if _world_reward_ledger == null:
		return report
	var deliveries: Array = _world_reward_ledger.call(
		"get_pending_deliveries"
	)
	report["pending_before"] = deliveries.size()
	for raw_delivery in deliveries:
		if not (raw_delivery is Dictionary):
			report["failed"] = int(report["failed"]) + 1
			continue
		var delivery: Dictionary = raw_delivery
		var event_id := StringName(
			str(delivery.get("event_id", ""))
		)
		var source_type := StringName(
			str(delivery.get("source_type", ""))
		)
		var source_id := StringName(
			str(delivery.get("source_id", ""))
		)
		var source_context := StringName(
			str(delivery.get("source_context", ""))
		)
		if (
			String(event_id).is_empty()
			or String(source_type).is_empty()
			or String(source_id).is_empty()
		):
			report["failed"] = int(report["failed"]) + 1
			continue

		var result: Dictionary = claim_world_source_reward(
			source_type,
			source_id,
			source_context,
			event_id,
			true
		)
		if (
			bool(result.get("success", false))
			or str(result.get("reason", ""))
			== "event_already_claimed"
		):
			report["resolved"] = int(report["resolved"]) + 1
		else:
			report["failed"] = int(report["failed"]) + 1
	return report


func _resolve_pending_competition_reward() -> Dictionary:
	if _competition_service == null:
		return {}
	var pending: Dictionary = _competition_service.call(
		"get_pending_reward"
	)
	if pending.is_empty():
		return {}

	var event_id := StringName(
		str(pending.get("reward_event_id", ""))
	)
	var source_id := StringName(
		str(pending.get("reward_source_id", ""))
	)
	if String(event_id).is_empty():
		return {
			"success": false,
			"reason": "pending_reward_missing_event_id",
		}

	if has_world_reward_event_claimed(event_id):
		_competition_service.call(
			"acknowledge_pending_reward",
			event_id
		)
		return {
			"success": true,
			"reason": "event_already_claimed",
			"event_id": String(event_id),
		}

	if String(source_id).is_empty():
		_competition_service.call(
			"acknowledge_pending_reward",
			event_id
		)
		return {
			"success": true,
			"reason": "competition_has_no_reward_source",
			"event_id": String(event_id),
		}

	var result: Dictionary = claim_tournament_card_reward(
		source_id,
		event_id,
		StringName(
			"competition:%s"
			% str(pending.get("competition_id", ""))
		),
		true
	)
	var reason: String = str(result.get("reason", ""))
	var resolved: bool = (
		bool(result.get("success", false))
		or reason == "event_already_claimed"
		or reason == "source_complete"
	)
	if resolved:
		if (
			reason == "source_complete"
			and _world_reward_ledger != null
		):
			_world_reward_ledger.call(
				"mark_claimed",
				event_id
			)
		_competition_service.call(
			"acknowledge_pending_reward",
			event_id
		)
		competition_state_changed.emit(
			get_competitive_snapshot()
		)
	return result


func get_runtime_recovery_snapshot() -> Dictionary:
	var pending_resolution: Dictionary = {}
	if _match_resolution_journal != null:
		pending_resolution = (
			_match_resolution_journal.get_snapshot()
		)
	var pending_competition_reward: Dictionary = {}
	if _competition_service != null:
		pending_competition_reward = (
			_competition_service.call(
				"get_pending_reward"
			)
		)
	var pending_world_deliveries: Array = []
	if _world_reward_ledger != null:
		pending_world_deliveries = _world_reward_ledger.call(
			"get_pending_deliveries"
		)
	return {
		"last_recovery": _last_runtime_recovery.duplicate(true),
		"pending_match_resolution": pending_resolution,
		"pending_competition_reward": pending_competition_reward,
		"pending_world_deliveries": pending_world_deliveries,
	}


func reconcile_runtime_state() -> Dictionary:
	var report := {
		"repaired": false,
		"requires_reward_ui": false,
		"resolution_repaired": false,
		"world_rewards_repaired": 0,
		"competition_reward_repaired": false,
		"stale_tournament_abandoned": false,
		"warnings": [],
	}

	var delivery_report: Dictionary = (
		_reconcile_pending_world_reward_deliveries()
	)
	var delivery_resolved: int = int(
		delivery_report.get("resolved", 0)
	)
	if delivery_resolved > 0:
		report["repaired"] = true
		report["world_rewards_repaired"] = delivery_resolved
	if int(delivery_report.get("failed", 0)) > 0:
		report["warnings"].append(
			"One or more pending world card rewards could not be reconciled."
		)

	var pending_reward_before: Dictionary = {}
	if _competition_service != null:
		pending_reward_before = _competition_service.call(
			"get_pending_reward"
		)
	if not pending_reward_before.is_empty():
		var reward_result: Dictionary = (
			_resolve_pending_competition_reward()
		)
		var reward_reason: String = str(
			reward_result.get("reason", "")
		)
		if (
			bool(reward_result.get("success", false))
			or reward_reason in [
				"event_already_claimed",
				"source_complete",
				"competition_has_no_reward_source",
			]
		):
			report["repaired"] = true
			report["competition_reward_repaired"] = true
		else:
			report["warnings"].append(
				"Pending tournament reward could not be reconciled."
			)

	var pending: Dictionary = {}
	if _match_resolution_journal != null:
		pending = _match_resolution_journal.get_snapshot()
	if bool(pending.get("pending", false)):
		var selected_id: String = str(
			pending.get("selected_card_id", "")
		)
		var winner: int = int(
			pending.get("winner", OWNER_NONE)
		)
		var forced_loss_id: String = str(
			pending.get("forced_loss_card_id", "")
		)

		if not selected_id.is_empty():
			var reconcile_result: Dictionary = (
				_match_resolution.reconcile_selected_pending_resolution(
					pending
				)
			)
			if bool(reconcile_result.get("success", false)):
				if bool(reconcile_result.get("remove_from_decks", false)):
					deck_setup.remove_card_from_all_profiles(
						StringName(str(reconcile_result.get("card_id", "")))
					)
				_match_resolution_journal.clear()
				report["repaired"] = true
				report["resolution_repaired"] = true
				_queue_gameplay_event(
					&"match_resolution_recovered",
					"Card Result Recovered",
					"An interrupted card transfer was completed safely.",
					pending,
					2
				)
			else:
				report["warnings"].append(
					"Selected card resolution could not be reconciled."
				)
		elif (
			winner == OWNER_OPPONENT
			and forced_loss_id.is_empty()
		):
			# Minimum-deck protection meant this result required no ownership
			# transfer. There is nothing unsafe to resume after a reload.
			_match_resolution_journal.clear()
			report["repaired"] = true
			report["resolution_repaired"] = true
		else:
			report["requires_reward_ui"] = true

	if _competition_service != null:
		var active: Dictionary = _competition_service.call(
			"get_active_snapshot"
		)
		if (
			bool(active.get("active", false))
			and bool(active.get("deck_locked", false))
			and _get_competition_locked_deck_cards().size() != 5
		):
			_competition_service.call(
				"abandon_active_competition"
			)
			report["repaired"] = true
			report["stale_tournament_abandoned"] = true
			report["warnings"].append(
				"An invalid persisted tournament deck was abandoned safely."
			)
			_queue_gameplay_event(
				&"tournament_recovered",
				"Tournament Reset",
				"The saved tournament deck was no longer legal.",
				active,
				2
			)

	if bool(report["repaired"]):
		_checkpoint_save_integrity(
			"runtime_reconcile"
		)
		_publish_backend_state_change(
			"runtime_reconcile"
		)
	_last_runtime_recovery = report.duplicate(true)
	return report


func _resume_pending_match_resolution() -> void:
	if (
		not _backend_ready
		or is_open()
		or _match_resolution_journal == null
	):
		return
	var pending: Dictionary = (
		_match_resolution_journal.get_snapshot()
	)
	if not bool(pending.get("pending", false)):
		return
	if not str(
		pending.get("selected_card_id", "")
	).is_empty():
		return

	var opponent_id := StringName(
		str(pending.get("opponent_id", ""))
	)
	var winner: int = int(
		pending.get("winner", OWNER_NONE)
	)
	if (
		String(opponent_id).is_empty()
		or winner not in [OWNER_PLAYER, OWNER_OPPONENT]
	):
		_match_resolution_journal.clear()
		return

	var profile = null
	if opponent_registry != null:
		profile = opponent_registry.call(
			"get_opponent",
			opponent_id
		)
	var player_cards: Array = _cards_from_ids(
		pending.get(
			"player_card_ids",
			PackedStringArray()
		)
	)
	var opponent_cards: Array = _cards_from_ids(
		pending.get(
			"opponent_card_ids",
			PackedStringArray()
		)
	)
	if (
		profile == null
		or player_cards.size() != 5
		or opponent_cards.size() != 5
	):
		_match_resolution_journal.clear()
		if _competition_service != null:
			var active: Dictionary = (
				_competition_service.call(
					"get_active_snapshot"
				)
			)
			if bool(active.get("active", false)):
				_competition_service.call(
					"abandon_active_competition"
				)
		_queue_gameplay_event(
			&"recovery_warning",
			"Card Result Reset",
			"An invalid interrupted result was cleared safely.",
			pending,
			3
		)
		return

	var tree: SceneTree = get_tree()
	if tree == null:
		return
	var recovered_reason := StringName(
		str(pending.get("result_reason", "recovered"))
	)
	var recovered_surrendered: bool = bool(
		pending.get("surrendered", false)
	)
	_session.recover_reward_session(
		tree.paused,
		winner,
		recovered_reason,
		recovered_surrendered
	)
	_resolve_active_configuration(profile)
	_opponent_collection_backend = OpponentCollectionScript.new()
	_opponent_collection_backend.initialize(
		card_catalog,
		opponent_id,
		_active_min_level,
		_active_max_level,
		_active_deck_budget,
		_active_opponent_profile
	)

	_starting_player_cards = player_cards.duplicate()
	_starting_opponent_cards = opponent_cards.duplicate()
	_active_player_deck = player_cards.duplicate()
	_pending_competition_change = (
		(pending.get("competition_change", {}) as Dictionary)
		.duplicate(true)
	)

	var opponent_take_index: int = -1
	var forced_loss_id: String = str(
		pending.get("forced_loss_card_id", "")
	)
	if winner == OWNER_OPPONENT and not forced_loss_id.is_empty():
		for index in range(player_cards.size()):
			var card = player_cards[index]
			if card != null and String(card.card_id) == forced_loss_id:
				opponent_take_index = index
				break

	_ui_flow.show_recovery_surface()
	var eligible_reward_ids := PackedStringArray()
	var raw_eligible = pending.get(
		"eligible_reward_ids",
		PackedStringArray()
	)
	if raw_eligible is PackedStringArray or raw_eligible is Array:
		for raw_id in raw_eligible:
			eligible_reward_ids.append(str(raw_id))
	_ui_flow.open_reward(
		opponent_cards,
		player_cards,
		winner,
		false,
		opponent_take_index,
		eligible_reward_ids,
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
	var minimum_unique: int = 5
	var protect_collection: bool = true
	var stolen_recoverable: bool = true
	if DefaultEconomyPolicy != null:
		minimum_unique = maxi(
			5,
			int(DefaultEconomyPolicy.minimum_playable_unique_cards)
		)
		protect_collection = bool(
			DefaultEconomyPolicy.protect_minimum_playable_collection
		)
		stolen_recoverable = bool(
			DefaultEconomyPolicy.stolen_cards_recoverable
		)

	var unique_owned: int = 0
	var total_owned: int = 0
	if _collection_backend != null:
		if _collection_backend.has_method("unique_owned_count"):
			unique_owned = int(
				_collection_backend.call("unique_owned_count")
			)
		if _collection_backend.has_method("total_owned_count"):
			total_owned = int(
				_collection_backend.call("total_owned_count")
			)

	var playable_unique: int = _match_resolution.get_playable_owned_cards().size()
	var stolen_total: int = 0
	var stolen_by_opponent: Array = []
	if _encounter_records != null:
		for raw_id in _encounter_records.get_all_recorded_ids():
			var opponent_id := StringName(str(raw_id))
			var encounter: Dictionary = _encounter_records.get_snapshot(
				opponent_id
			)
			var opponent_stolen: int = int(
				encounter.get("stolen_total", 0)
			)
			if opponent_stolen <= 0:
				continue
			stolen_total += opponent_stolen
			stolen_by_opponent.append({
				"opponent_id": String(opponent_id),
				"stolen_total": opponent_stolen,
				"stolen_quantities": (
					encounter.get(
						"stolen_quantities",
						{}
					) as Dictionary
				).duplicate(true),
			})

	return {
		"minimum_playable_unique_cards": minimum_unique,
		"protect_minimum_playable_collection": protect_collection,
		"stolen_cards_recoverable": stolen_recoverable,
		"unique_owned_count": unique_owned,
		"total_owned_count": total_owned,
		"playable_unique_count": playable_unique,
		"minimum_deck_protection_active": (
			protect_collection
			and playable_unique <= minimum_unique
		),
		"stolen_total": stolen_total,
		"stolen_by_opponent": stolen_by_opponent,
	}


func _schedule_ai() -> void:
	ai_timer.start(maxf(ai_delay_seconds, 0.01))


func _refresh_views(captured_cells: Array = []) -> void:
	if _match == null:
		return
	_presentation.refresh(
		_match,
		_session.phase,
		_active_rule_set,
		_selected_hand_index,
		_selected_cell_index,
		captured_cells
	)
	_refresh_ui_flow()
	runtime_state_changed.emit(get_runtime_ui_snapshot())


func _refresh_ui_flow() -> void:
	if _match == null:
		return
	_selected_hand_index = _ui_flow.refresh_match_state(
		_session.phase,
		_session.round_number,
		_match,
		_selected_hand_index,
		message_label.text,
		_region_trait_text(),
		_current_help_entries(),
		_match.get_score()
	)


func _capture_message(result: Dictionary) -> String:
	var combo_captured: Array = result.get("combo_captured", [])
	var same_triggered: bool = bool(result.get("same_triggered", false))
	var plus_triggered: bool = bool(result.get("plus_triggered", false))

	var special_text: String = ""
	if same_triggered and plus_triggered:
		special_text = "SAME + PLUS!"
	elif same_triggered:
		special_text = "SAME!"
	elif plus_triggered:
		special_text = "PLUS!"

	if special_text.is_empty():
		return ""
	if not combo_captured.is_empty():
		return "%s  COMBO x%d" % [special_text, combo_captured.size()]
	return special_text


func _on_reward_selected(card_definition) -> void:
	if card_definition == null:
		_ui_flow.resolve_reward_transfer(false)
		return

	_last_info_name = str(card_definition.display_name)
	var transfer_result: Dictionary = _match_resolution.commit_reward_transfer(
		card_definition,
		_session.result_winner,
		_active_opponent_id(),
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
			% str(_active_opponent_profile.get("display_name")),
			{
				"card_id": String(card_definition.card_id),
				"opponent_id": String(_active_opponent_id()),
			}
		)
	elif _session.result_winner == OWNER_OPPONENT:
		_queue_gameplay_event(
			&"card_lost",
			str(card_definition.display_name),
			"Lost to %s. Win it back in a rematch."
			% str(_active_opponent_profile.get("display_name")),
			{
				"card_id": String(card_definition.card_id),
				"opponent_id": String(_active_opponent_id()),
			}
		)

		if bool(transfer_result.get("remove_from_decks", false)):
			deck_setup.remove_card_from_all_profiles(
				StringName(card_definition.card_id)
			)
			var filtered_active_deck: Array = []
			for card in _active_player_deck:
				if (
					card != null
					and String(card.card_id)
					!= String(card_definition.card_id)
				):
					filtered_active_deck.append(card)
			_active_player_deck = filtered_active_deck

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
		bool(_pending_competition_change.get("round_won", false))
		and _continue_active_competition_round()
	):
		return
	_pending_competition_change.clear()
	close_game()



func _continue_active_competition_round() -> bool:
	if _competition_service == null:
		return false
	var next_opponent_id: StringName = _competition_service.call(
		"get_active_opponent_id"
	)
	if next_opponent_id == &"":
		return false

	var locked_cards: Array = _get_competition_locked_deck_cards()
	if locked_cards.size() != 5:
		push_warning(
			"TripleTriadGame: tournament deck lock is no longer legal; ending the attempt."
		)
		abandon_active_competition()
		return false

	var profile = null
	if opponent_registry != null:
		profile = opponent_registry.call(
			"get_opponent",
			next_opponent_id
		)
	if profile == null:
		push_error(
			"TripleTriadGame: tournament next opponent '%s' is missing."
			% String(next_opponent_id)
		)
		abandon_active_competition()
		return false

	_session.reset_round()
	_resolve_active_configuration(profile)
	_opponent_collection_backend = OpponentCollectionScript.new()
	_opponent_collection_backend.initialize(
		card_catalog,
		_active_opponent_id(),
		_active_min_level,
		_active_max_level,
		_active_deck_budget,
		_active_opponent_profile
	)
	_active_player_deck = locked_cards.duplicate()
	_competition_match_active = true
	_pending_competition_change.clear()
	_queue_gameplay_event(
		&"tournament_next_round",
		"Next Round",
		str(profile.get("display_name")),
		{
			"opponent_id": String(next_opponent_id),
			"competition": get_competitive_snapshot(),
		}
	)
	_publish_backend_state_change("competition_next_round")
	_start_new_match(_active_player_deck)
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
	_active_player_deck = cards.duplicate()
	if _competition_match_active:
		if not _lock_active_competition_deck(_active_player_deck):
			push_error(
				"TripleTriadGame: could not lock the tournament deck."
			)
			abandon_active_competition()
			close_game()
			return
	_ui_flow.close_deck_setup()
	_publish_backend_state_change("deck_selected")
	_start_new_match(_active_player_deck)


func _on_deck_cancelled() -> void:
	if _session.phase != PHASE_DECK_SETUP:
		return
	if _competition_match_active and _competition_service != null:
		abandon_active_competition()
	close_game()


func _resolve_active_configuration(opponent_profile_override: Resource) -> void:
	_active_opponent_profile = opponent_profile_override
	_active_region_profile = region_profile
	_active_ai_profile = ai_profile
	_active_rule_set = rule_set
	_active_deck_budget = deck_budget
	_active_min_level = prototype_min_level
	_active_max_level = prototype_max_level

	if _active_opponent_profile != null:
		var profile_region = _active_opponent_profile.get("region_profile")
		if profile_region != null:
			_active_region_profile = profile_region
		var profile_ai = _active_opponent_profile.get("ai_profile")
		if profile_ai != null:
			_active_ai_profile = profile_ai
		var min_level_value = _active_opponent_profile.get("min_card_level")
		var max_level_value = _active_opponent_profile.get("max_card_level")
		if min_level_value != null:
			_active_min_level = clampi(int(min_level_value), 1, 10)
		if max_level_value != null:
			_active_max_level = clampi(int(max_level_value), _active_min_level, 10)

	if _active_region_profile != null:
		var region_rules = _active_region_profile.get("rule_set")
		if region_rules != null:
			_active_rule_set = region_rules
		var region_budget = _active_region_profile.get("deck_budget")
		if region_budget != null:
			_active_deck_budget = maxi(5, int(region_budget))

	if _active_opponent_profile != null:
		var profile_rules = _active_opponent_profile.get("rule_set_override")
		if profile_rules != null:
			_active_rule_set = profile_rules
		var budget_override = _active_opponent_profile.get("deck_budget_override")
		if budget_override != null and int(budget_override) > 0:
			_active_deck_budget = int(budget_override)

	_active_opponent_evolution = {}
	if _qa_profile_override == null and _active_opponent_profile != null:
		var encounter_snapshot: Dictionary = {}
		if _encounter_records != null:
			encounter_snapshot = _encounter_records.get_snapshot(
				_active_opponent_id()
			)
		_active_opponent_evolution = _opponent_evolution.build_snapshot(
			_active_opponent_profile,
			encounter_snapshot
		)
		_active_deck_budget += maxi(
			0,
			int(_active_opponent_evolution.get("budget_bonus", 0))
		)
		_active_ai_profile = _opponent_evolution.build_adapted_ai(
			_active_ai_profile,
			_active_opponent_evolution
		)

	# Keep the evolved NPC configuration as the debug menu's CURRENT/NPC baseline,
	# then layer any temporary QA profile over it.
	_qa_base_summary = _configuration_summary()
	_apply_qa_profile_override()


func _apply_qa_profile_override() -> void:
	_qa_forced_starting_owner = OWNER_NONE
	_qa_hand_seed = 0
	if _qa_profile_override == null:
		return
	# QA profiles are controlled experiments. They intentionally bypass persistent
	# rematch evolution so the debug profile remains reproducible.
	_active_opponent_evolution = {}

	var qa_region: Resource = _qa_profile_override.get("region_profile")
	if qa_region != null:
		_active_region_profile = qa_region
		var region_rules = qa_region.get("rule_set")
		if region_rules != null:
			_active_rule_set = region_rules
		var region_budget = qa_region.get("deck_budget")
		if region_budget != null:
			_active_deck_budget = maxi(5, int(region_budget))

	var qa_ai: Resource = _qa_profile_override.get("ai_profile")
	if qa_ai != null:
		_active_ai_profile = qa_ai

	var qa_rules: Resource = _qa_profile_override.get("rule_set_override")
	if qa_rules != null:
		_active_rule_set = qa_rules

	var qa_budget: int = int(_qa_profile_override.get("deck_budget_override"))
	if qa_budget > 0:
		_active_deck_budget = qa_budget

	_active_min_level = clampi(int(_qa_profile_override.get("min_card_level")), 1, 10)
	_active_max_level = clampi(
		int(_qa_profile_override.get("max_card_level")),
		_active_min_level,
		10
	)
	_qa_forced_starting_owner = clampi(
		int(_qa_profile_override.get("starting_owner")),
		OWNER_NONE,
		OWNER_OPPONENT
	)
	_qa_hand_seed = maxi(0, int(_qa_profile_override.get("hand_seed")))


func _on_qa_profile_apply_requested(selected_profile: Resource) -> void:
	_qa_profile_override = selected_profile
	if _qa_profile_override == null:
		_rng.randomize()
	_resolve_active_configuration(_active_opponent_profile)
	_start_new_match(_active_player_deck)


func _active_opponent_id() -> StringName:
	if _active_opponent_profile != null:
		var raw_id = _active_opponent_profile.get("opponent_id")
		if raw_id != null and not str(raw_id).is_empty():
			return StringName(str(raw_id))
	return &"default_opponent"


func _configuration_summary() -> Dictionary:
	return {
		"opponent_id": String(_active_opponent_id()),
		"opponent": _resource_display_name(_active_opponent_profile, "Default Opponent"),
		"opponent_rank": (
			int(_active_opponent_profile.get("duel_rank"))
			if _active_opponent_profile != null
			else 1
		),
		"region": _resource_display_name(_active_region_profile, "Default"),
		"ai": _resource_display_name(_active_ai_profile, "Default"),
		"budget": _active_deck_budget,
		"min_level": _active_min_level,
		"max_level": _active_max_level,
		"rules": _rules_summary(_active_rule_set, _active_region_profile),
		"rematch_stage": int(_active_opponent_evolution.get("stage", 0)),
		"rematch_stage_label": str(
			_active_opponent_evolution.get("stage_label", "Baseline")
		),
		"rematch_evolution": _active_opponent_evolution.duplicate(true),
	}


func _rules_summary(active_rules: Resource, active_region: Resource) -> String:
	var labels: PackedStringArray = PackedStringArray()
	if active_rules != null:
		if bool(active_rules.get("same_rule")):
			labels.append("Same")
		if bool(active_rules.get("plus_rule")):
			labels.append("Plus")
		if bool(active_rules.get("combo_rule")):
			labels.append("Combo")
		if bool(active_rules.get("influence_rule")):
			labels.append("Influence")
	if active_region != null and bool(active_region.get("allow_rotate")):
		labels.append("Rotate x1")
	if labels.is_empty():
		return "Normal capture"
	return " + ".join(labels)


func _resource_display_name(resource: Resource, fallback: String) -> String:
	if resource == null:
		return fallback
	var display_name = resource.get("display_name")
	if display_name != null and not str(display_name).is_empty():
		return str(display_name)
	return resource.resource_path.get_file().get_basename()


func _build_budgeted_hand(min_level: int, max_level: int) -> Array:
	if card_catalog.has_method("build_budgeted_hand"):
		return card_catalog.build_budgeted_hand(_rng, min_level, max_level, 5, _active_deck_budget)
	return card_catalog.build_random_hand(_rng, min_level, max_level, 5)


func _try_rotate_selected_card() -> void:
	if _selected_hand_index < 0 or _selected_hand_index >= _match.player_hand.size():
		return
	if _match.rotate_hand_card(OWNER_PLAYER, _selected_hand_index):
		message_label.text = "ROTATE! One use spent."
	else:
		message_label.text = "Rotate already used."
	_refresh_views()


func _player_help_text(board_selection: bool) -> String:
	var rotate_text: String = "   R: Rotate" if _match != null and _match.can_rotate(OWNER_PLAYER) else ""
	if board_selection:
		return "W/A/S/D: Move   K: Place%s   I: Back" % rotate_text
	return "W/S: Card   K: Select%s   I: Surrender" % rotate_text


func _current_help_entries() -> Array:
	var entries: Array = []
	match _session.phase:
		PHASE_SELECT_CARD:
			entries.append({"key": "W/S", "action": "Card"})
			entries.append({"key": "K", "action": "Select"})
			if _match != null and _match.can_rotate(OWNER_PLAYER):
				entries.append({"key": "R", "action": "Rotate"})
			entries.append({"key": "I", "action": "Surrender"})
		PHASE_SELECT_CELL:
			entries.append({"key": "WASD", "action": "Move"})
			entries.append({"key": "K", "action": "Place"})
			if _match != null and _match.can_rotate(OWNER_PLAYER):
				entries.append({"key": "R", "action": "Rotate"})
			entries.append({"key": "I", "action": "Back"})
		PHASE_AI:
			entries.append({"key": "I", "action": "Surrender"})
		PHASE_RESULT:
			entries.append({"key": "K", "action": "Continue"})
		PHASE_REWARD:
			entries.append({"key": "K", "action": "Continue"})
	return entries


func _region_trait_text() -> String:
	if _active_region_profile == null:
		return ""
	var description = _active_region_profile.get("board_trait_description")
	if description == null:
		return ""
	return str(description)


func _find_nearest_empty_cell(preferred: int) -> int:
	return _match_flow.nearest_empty_cell(preferred)


func _accept_input() -> void:
	var viewport: Viewport = get_viewport()
	if viewport != null:
		viewport.set_input_as_handled()
