extends CanvasLayer

signal opened
signal closed
signal match_finished(result: Dictionary)
signal card_reward_selected(card_definition)
signal backend_state_changed(reason: String)
signal runtime_state_changed(snapshot: Dictionary)
signal acquisition_completed(result: Dictionary)
signal card_game_unlock_changed(unlocked: bool)

const MatchScript = preload("res://scripts/triple_triad/triple_triad_match.gd")
const AIScript = preload("res://scripts/triple_triad/triple_triad_ai.gd")
const CardViewScene = preload("res://actors/TripleTriadCardView.tscn")
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
const MatchHUDScene = preload("res://actors/TripleTriadMatchHUD.tscn")
const BalanceSimulatorScript = preload("res://scripts/triple_triad/triple_triad_balance_simulator.gd")
const FishingSalvageBridgeScript = preload("res://scripts/triple_triad/triple_triad_fishing_salvage_bridge.gd")
const WorldAcquisitionCatalogScript = preload("res://scripts/triple_triad/triple_triad_world_acquisition_catalog.gd")
const WorldRewardLedgerScript = preload("res://scripts/triple_triad/triple_triad_world_reward_ledger.gd")
const DefaultEconomyPolicy = preload("res://data/triple_triad/economy/default_economy_policy.tres")

const BACKEND_VERSION := "1.9.0"

const OWNER_NONE := 0
const OWNER_PLAYER := 1
const OWNER_OPPONENT := 2

const PHASE_CLOSED := 0
const PHASE_DEALING := 1
const PHASE_SELECT_CARD := 2
const PHASE_SELECT_CELL := 3
const PHASE_ANIMATING := 4
const PHASE_AI := 5
const PHASE_RESULT := 6
const PHASE_REWARD := 7
const PHASE_DECK_SETUP := 8

const HAND_STEP_Y := 47.0
const HAND_SELECTED_X_OFFSET := -8.0
const CAPTURE_SETTLE_SECONDS := 0.24
const RESULT_FADE_IN_SECONDS := 0.24
const RESULT_FADE_OUT_SECONDS := 0.30
const PREVIEW_GHOST_ALPHA := 0.72
const PREVIEW_INFLUENCE_COLOR := Color(1.0, 0.76, 0.18, 0.28)
const PREVIEW_PRESSURE_COLOR := Color(1.0, 0.24, 0.20, 0.34)
const ACTIVE_INFLUENCE_PLAYER_FILL := Color(0.18, 0.48, 1.0, 0.13)
const ACTIVE_INFLUENCE_PLAYER_BORDER := Color(0.28, 0.68, 1.0, 0.90)
const ACTIVE_INFLUENCE_OPPONENT_FILL := Color(1.0, 0.18, 0.16, 0.13)
const ACTIVE_INFLUENCE_OPPONENT_BORDER := Color(1.0, 0.34, 0.24, 0.90)
const ACTIVE_INFLUENCE_BOTH_FILL := Color(0.78, 0.34, 0.92, 0.14)
const ACTIVE_INFLUENCE_BOTH_BORDER := Color(0.96, 0.62, 1.0, 0.92)
const RESULT_DIM_COLOR := Color(0.0, 0.0, 0.0, 0.56)

const CARD_GAME_BACKGROUND = preload(
	"res://assets/ui/triple_triad/card_game/CardGame_Background.png"
)
# The new UI artwork is authored at the project's native 640x480 canvas.
# CardView's sacred internal layout stays 116x132; the presentation layer scales
# complete views to the new 74x88 card footprint instead of rewriting rank layout.
const CARD_BASE_SIZE := Vector2(116.0, 132.0)
const CARD_VISUAL_SIZE := Vector2(74.0, 88.0)
const CARD_VISUAL_SCALE := Vector2(
	CARD_VISUAL_SIZE.x / CARD_BASE_SIZE.x,
	CARD_VISUAL_SIZE.y / CARD_BASE_SIZE.y
)

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
var _phase: int = PHASE_CLOSED
var _selected_hand_index: int = 0
var _selected_cell_index: int = 4
var _previous_pause: bool = false
var _player_views: Array = []
var _opponent_views: Array = []
var _board_views: Array = []
var _starting_player_cards: Array = []
var _starting_opponent_cards: Array = []
var _last_info_name: String = ""
var _result_winner: int = OWNER_NONE
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
var _match_started: bool = false
var _surrendered: bool = false
var _result_reason: StringName = &""
var _preview_ghost: Control = null
var _influence_preview_overlays: Array[ColorRect] = []
var _active_influence_overlays: Array[Panel] = []
var _match_hud: Control = null
var _default_backdrop_texture: Texture2D = null
var _result_dim: ColorRect = null
var _round_number: int = 1
var _fishing_salvage_bridge: Node = null
var _world_acquisition_catalog = null
var _world_reward_ledger = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_default_backdrop_texture = backdrop.texture
	_apply_card_game_visual_layout()
	_build_match_hud()
	_build_result_overlay()
	_set_match_skin_visible(false)
	root.visible = false
	transition_fade.visible = false
	transition_fade.modulate = Color(1, 1, 1, 0)
	_match = MatchScript.new()
	_ai = AIScript.new()
	_rng.randomize()

	_build_views()
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
	_acquisition_service.bundle_claimed.connect(_on_acquisition_bundle_claimed)
	_acquisition_service.unlock_changed.connect(_on_card_game_unlock_changed)

	_progression = ProgressionScript.new()
	_progression.initialize()

	_world_reward_ledger = WorldRewardLedgerScript.new()
	_world_reward_ledger.initialize()

	_encounter_records = EncounterRecordsScript.new()
	_encounter_records.initialize()

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
	_install_fishing_salvage_bridge()
	if OS.is_debug_build() and run_backend_qa_on_startup:
		_run_backend_qa()
	if OS.is_debug_build() and run_balance_simulation_on_startup:
		call_deferred(
			"run_balance_simulation",
			balance_games_per_matchup,
			balance_simulation_seed
		)


func _apply_card_game_visual_layout() -> void:
	# The supplied card-game background now contains the hand slots, board backs,
	# frame, and lower information shell as one authored texture. Runtime UI only
	# adds live cards/text on top; no second slot-guide texture is composited.
	grid_artwork.visible = false
	# Board/OpponentHand/PlayerHand layout now lives in TripleTriadGame.tscn.
	# Move those nodes directly in the 2D editor; runtime no longer overwrites
	# their positions/board scale here.

	# Retire the old prototype HUD pieces. The dedicated match HUD owns scores,
	# turn status, region trait, and selected-card information.
	info_panel.visible = false
	info_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	opponent_score_label.get_parent().visible = false
	player_score_label.get_parent().visible = false
	message_label.visible = false
	help_label.visible = false

	backdrop.z_index = -100


func _build_match_hud() -> void:
	if _match_hud != null:
		return
	_match_hud = MatchHUDScene.instantiate() as Control
	_match_hud.z_index = 580
	root.add_child(_match_hud)
	_match_hud.visible = false


func _build_result_overlay() -> void:
	if _result_dim != null:
		return
	_result_dim = ColorRect.new()
	_result_dim.name = "ResultDim"
	_result_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_result_dim.color = RESULT_DIM_COLOR
	_result_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_result_dim.z_index = 790
	_result_dim.visible = false
	root.add_child(_result_dim)

	# Keep the authored result label in the center, but make it read more strongly
	# against the dimmed board.
	result_label.add_theme_font_size_override("font_size", 40)
	result_label.add_theme_constant_override("outline_size", 7)


func _set_match_skin_visible(enabled: bool) -> void:
	if backdrop != null:
		if enabled:
			backdrop.texture = CARD_GAME_BACKGROUND
		else:
			backdrop.texture = _default_backdrop_texture
	if _match_hud != null:
		_match_hud.visible = enabled
	if not enabled and _result_dim != null:
		_result_dim.visible = false


func _board_cell_visual_rect(cell_index: int) -> Rect2:
	if cell_index < 0 or cell_index >= _board_views.size():
		return Rect2()
	var view: Control = _board_views[cell_index]
	return Rect2(
		board_container.position + view.position * board_container.scale,
		view.size * board_container.scale
	)


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


func get_state_api():
	return _state_api


func get_player_snapshot() -> Dictionary:
	return _state_api.get_player_snapshot() if _state_api != null else {}


func get_collection_snapshot() -> Array:
	return _state_api.get_collection_snapshot() if _state_api != null else []



func get_card_acquisition_sources(card_id: StringName) -> Array:
	if _world_acquisition_catalog == null:
		return []
	return _world_acquisition_catalog.call("get_sources_for_card", card_id)


func get_acquisition_source_snapshot(
	source_type: StringName,
	source_id: StringName
) -> Dictionary:
	if _world_acquisition_catalog == null:
		return {}
	return _world_acquisition_catalog.call(
		"get_source_snapshot",
		source_type,
		source_id
	)


func get_world_acquisition_sources() -> Array:
	if _world_acquisition_catalog == null:
		return []
	return _world_acquisition_catalog.call("get_all_source_snapshots")


func claim_world_source_card(
	source_type: StringName,
	source_id: StringName,
	card_id: StringName,
	source_context: StringName = &""
) -> Dictionary:
	if not _backend_ready:
		return {"success": false, "reason": "backend_not_ready"}
	if _world_acquisition_catalog == null or _acquisition_service == null:
		return {"success": false, "reason": "acquisition_backend_unavailable"}
	var player_rank: int = 1
	if _progression != null and _progression.has_method("get_rank_number"):
		player_rank = int(_progression.call("get_rank_number"))
	var validation: Dictionary = _world_acquisition_catalog.call(
		"validate_claim",
		source_type,
		source_id,
		card_id,
		player_rank
	)
	if not bool(validation.get("valid", false)):
		return {
			"success": false,
			"reason": str(validation.get("reason", "invalid_source_claim")),
			"required_duel_rank": int(validation.get("required_duel_rank", 1)),
		}
	var context_text: String = String(source_context)
	if context_text.is_empty():
		context_text = "%s:%s" % [String(source_type), String(source_id)]
	var result: Dictionary = _acquisition_service.call(
		"grant_card",
		card_id,
		source_type,
		StringName(context_text),
		1
	)
	if bool(result.get("success", false)):
		_checkpoint_save_integrity("world_card_acquired")
		acquisition_completed.emit(result.duplicate(true))
		_publish_backend_state_change("world_card_acquired")
	return result


func claim_world_source_reward(
	source_type: StringName,
	source_id: StringName,
	source_context: StringName = &"",
	event_id: StringName = &"",
	one_shot: bool = false
) -> Dictionary:
	if not _backend_ready:
		return {
			"success": false,
			"reason": "backend_not_ready",
		}
	if _world_acquisition_catalog == null:
		return {
			"success": false,
			"reason": "acquisition_catalog_unavailable",
		}
	if not bool(
		_world_acquisition_catalog.call(
			"can_direct_claim_source",
			source_type
		)
	):
		return {
			"success": false,
			"reason": "source_owned_by_other_system",
		}
	if (
		one_shot
		and not String(event_id).is_empty()
		and has_world_reward_event_claimed(event_id)
	):
		return {
			"success": false,
			"reason": "event_already_claimed",
			"event_id": String(event_id),
		}

	var source: Dictionary = get_acquisition_source_snapshot(
		source_type,
		source_id
	)
	if source.is_empty():
		return {
			"success": false,
			"reason": "unknown_source",
		}

	var player_rank: int = 1
	if _progression != null and _progression.has_method("get_rank_number"):
		player_rank = int(_progression.call("get_rank_number"))
	var required_rank: int = maxi(
		1,
		int(source.get("min_duel_rank", 1))
	)
	if player_rank < required_rank:
		return {
			"success": false,
			"reason": "duel_rank_too_low",
			"required_duel_rank": required_rank,
		}

	var source_cards: Array = _world_acquisition_catalog.call(
		"get_cards_for_source",
		source_type,
		source_id,
		player_rank
	)
	if source_cards.is_empty():
		return {
			"success": false,
			"reason": "source_has_no_eligible_cards",
		}

	var unowned_cards: Array = []
	for card in source_cards:
		if card == null:
			continue
		var card_id := StringName(str(card.get("card_id")))
		var quantity: int = 0
		if (
			_collection_backend != null
			and _collection_backend.has_method("get_quantity_by_id")
		):
			quantity = int(
				_collection_backend.call(
					"get_quantity_by_id",
					card_id
				)
			)
		if quantity <= 0:
			unowned_cards.append(card)

	if unowned_cards.is_empty():
		return {
			"success": false,
			"reason": "source_complete",
			"source_type": String(source_type),
			"source_id": String(source_id),
			"source_display_name": str(
				source.get("display_name", "")
			),
		}

	var chosen_index: int = _rng.randi_range(
		0,
		unowned_cards.size() - 1
	)
	var chosen_card = unowned_cards[chosen_index]
	var chosen_id := StringName(
		str(chosen_card.get("card_id"))
	)

	var resolved_context: StringName = source_context
	if String(resolved_context).is_empty():
		resolved_context = StringName(
			"%s:%s"
			% [
				String(source_type),
				String(source_id),
			]
		)

	var result: Dictionary = claim_world_source_card(
		source_type,
		source_id,
		chosen_id,
		resolved_context
	)
	result["source_id"] = String(source_id)
	result["source_display_name"] = str(
		source.get("display_name", "")
	)
	result["event_id"] = String(event_id)
	result["remaining_unowned_before_claim"] = unowned_cards.size()

	if (
		bool(result.get("success", false))
		and one_shot
		and not String(event_id).is_empty()
		and _world_reward_ledger != null
	):
		_world_reward_ledger.call(
			"mark_claimed",
			event_id
		)

	return result


func claim_fishing_salvage_reward(
	source_id: StringName,
	source_context: StringName = &""
) -> Dictionary:
	return claim_world_source_reward(
		&"fishing_salvage",
		source_id,
		source_context
	)


func claim_treasure_cache_reward(
	source_id: StringName,
	cache_event_id: StringName,
	source_context: StringName = &""
) -> Dictionary:
	return claim_world_source_reward(
		&"treasure_cache",
		source_id,
		source_context,
		cache_event_id,
		true
	)


func claim_quest_card_reward(
	source_id: StringName,
	quest_event_id: StringName,
	source_context: StringName = &""
) -> Dictionary:
	return claim_world_source_reward(
		&"quest_reward",
		source_id,
		source_context,
		quest_event_id,
		true
	)


func claim_tournament_card_reward(
	source_id: StringName,
	tournament_event_id: StringName,
	source_context: StringName = &"",
	one_shot: bool = true
) -> Dictionary:
	return claim_world_source_reward(
		&"tournament_reward",
		source_id,
		source_context,
		tournament_event_id,
		one_shot
	)


func advance_world_reward_counter(counter_id: StringName) -> int:
	if _world_reward_ledger == null:
		return 0
	return int(
		_world_reward_ledger.call(
			"increment_counter",
			counter_id
		)
	)


func get_world_reward_delivery_snapshot() -> Dictionary:
	if _world_reward_ledger == null:
		return {}
	return _world_reward_ledger.call("get_snapshot")


func has_world_reward_event_claimed(event_id: StringName) -> bool:
	if _world_reward_ledger == null:
		return false
	return bool(
		_world_reward_ledger.call(
			"has_claimed",
			event_id
		)
	)


func get_deck_profiles_snapshot() -> Array:
	return _state_api.get_deck_profiles() if _state_api != null else []


func get_opponent_snapshot(opponent_id: StringName) -> Dictionary:
	return _state_api.get_opponent_snapshot(opponent_id) if _state_api != null else {}


func get_opponents_snapshot() -> Array:
	return _state_api.get_all_opponents_snapshot() if _state_api != null else []


func get_global_triple_triad_snapshot() -> Dictionary:
	var snapshot: Dictionary = (
		_state_api.get_global_snapshot()
		if _state_api != null
		else {}
	)
	snapshot["runtime"] = {
		"backend_version": BACKEND_VERSION,
		"is_open": is_open(),
		"phase": _phase,
		"active_opponent_id": String(_active_opponent_id()) if is_open() else "",
	}
	return snapshot


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
		"phase": _phase,
		"phase_name": _phase_name(_phase),
		"round_number": _round_number,
		"match_started": _match_started,
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
		"placement_preview": _preview_for_current_selection(),
		"can_surrender": (
			_match_started
			and _phase in [PHASE_SELECT_CARD, PHASE_AI]
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
	_invalidate_state_api(reason)
	backend_state_changed.emit(reason)


func is_open() -> bool:
	return _phase != PHASE_CLOSED


func is_card_game_unlocked() -> bool:
	if _acquisition_service == null:
		return false
	return bool(_acquisition_service.call("is_card_game_unlocked"))


func get_acquisition_snapshot() -> Dictionary:
	if _acquisition_service == null:
		return {
			"card_game_unlocked": false,
			"claimed_bundle_ids": PackedStringArray(),
			"available_bundle_ids": PackedStringArray(),
		}
	return _acquisition_service.call("get_snapshot")


func claim_acquisition_bundle(
	bundle_id: StringName,
	source_context: StringName = &""
) -> Dictionary:
	if not _backend_ready or _acquisition_service == null:
		return {
			"success": false,
			"reason": "backend_unavailable",
			"bundle_id": String(bundle_id),
		}
	var result: Dictionary = _acquisition_service.call(
		"claim_bundle",
		bundle_id,
		source_context
	)
	if bool(result.get("success", false)):
		_checkpoint_save_integrity("acquisition_bundle")
		_publish_backend_state_change("acquisition_bundle")
	return result


## Stable bridge for the fishing/exploration layer. The fishing game only needs
## to call this when its salvage/object event resolves; Triple Triad owns the
## contents, one-shot persistence, collection write, and unlock state.
func claim_salvaged_card_case(
	source_context: StringName = &"sea_salvage"
) -> Dictionary:
	return claim_acquisition_bundle(
		&"salvaged_card_case",
		source_context
	)


func get_onboarding_snapshot() -> Dictionary:
	var acquisition: Dictionary = get_acquisition_snapshot()
	var collection_unique_count: int = 0
	if (
		_collection_backend != null
		and _collection_backend.has_method("unique_owned_count")
	):
		collection_unique_count = int(
			_collection_backend.call("unique_owned_count")
		)

	var starter_case_claimed: bool = false
	var raw_claimed_ids = acquisition.get(
		"claimed_bundle_ids",
		PackedStringArray()
	)
	if raw_claimed_ids is PackedStringArray or raw_claimed_ids is Array:
		for raw_id in raw_claimed_ids:
			if str(raw_id) == "salvaged_card_case":
				starter_case_claimed = true
				break

	var bridge_snapshot: Dictionary = {}
	if (
		is_instance_valid(_fishing_salvage_bridge)
		and _fishing_salvage_bridge.has_method("get_debug_snapshot")
	):
		bridge_snapshot = _fishing_salvage_bridge.call(
			"get_debug_snapshot"
		)

	return {
		"card_game_unlocked": bool(
			acquisition.get("card_game_unlocked", false)
		),
		"starter_case_claimed": starter_case_claimed,
		"collection_unique_count": collection_unique_count,
		"available_card_player_ids": get_available_card_player_ids(),
		"fishing_salvage_bridge": bridge_snapshot,
	}


func _install_fishing_salvage_bridge() -> void:
	if is_instance_valid(_fishing_salvage_bridge):
		return

	var bridge = FishingSalvageBridgeScript.new()
	bridge.name = "TripleTriadFishingSalvageBridge"
	add_child(bridge)
	_fishing_salvage_bridge = bridge

	if bridge.has_method("configure"):
		bridge.call(
			"configure",
			self,
			PackedStringArray(["ocean_2"]),
			true
		)


func get_opponent_availability(opponent_id: StringName) -> Dictionary:
	if opponent_registry == null or not opponent_registry.has_method("get_availability"):
		return {
			"available": false,
			"reason": "Opponent registry unavailable.",
			"required_player_rank": 1,
		}
	var player_rank: int = (
		_progression.get_rank_number()
		if _progression != null
		else maxi(1, player_card_rank)
	)
	return opponent_registry.call(
		"get_availability",
		opponent_id,
		player_rank,
		&"",
		&"",
		_opponent_availability_context()
	)


func get_available_card_player_ids(
	region_id: StringName = &"",
	required_tag: StringName = &""
) -> PackedStringArray:
	var result := PackedStringArray()
	if opponent_registry == null or not opponent_registry.has_method("get_available_opponents"):
		return result
	var player_rank: int = (
		_progression.get_rank_number()
		if _progression != null
		else maxi(1, player_card_rank)
	)
	var profiles: Array = opponent_registry.call(
		"get_available_opponents",
		player_rank,
		region_id,
		required_tag,
		_opponent_availability_context()
	)
	for profile in profiles:
		if profile != null:
			result.append(String(profile.get("opponent_id")))
	return result


func _opponent_availability_context() -> Dictionary:
	var beaten_ids := PackedStringArray()
	var total_wins: int = 0
	if _encounter_records != null:
		if _encounter_records.has_method("get_beaten_opponent_ids"):
			beaten_ids = _encounter_records.call("get_beaten_opponent_ids")
		if _encounter_records.has_method("get_total_player_wins"):
			total_wins = int(_encounter_records.call("get_total_player_wins"))
	return {
		"card_game_unlocked": is_card_game_unlocked(),
		"beaten_opponent_ids": beaten_ids,
		"total_player_wins": total_wins,
	}


func _on_acquisition_bundle_claimed(result: Dictionary) -> void:
	acquisition_completed.emit(result.duplicate(true))


func _on_card_game_unlock_changed(unlocked: bool) -> void:
	card_game_unlock_changed.emit(unlocked)


func open_game_by_id(opponent_id: StringName) -> bool:
	if not _backend_ready:
		push_warning("TripleTriadGame: backend is not ready; match open rejected.")
		return false
	if opponent_registry == null or not opponent_registry.has_method("get_opponent"):
		push_error("TripleTriadGame: opponent registry is unavailable.")
		return false

	var profile = opponent_registry.call("get_opponent", opponent_id)
	if profile == null:
		push_error(
			"TripleTriadGame: unknown opponent_id '%s'."
			% String(opponent_id)
		)
		return false

	if opponent_registry.has_method("get_availability"):
		var player_rank: int = (
			_progression.get_rank_number()
			if _progression != null
			else maxi(1, player_card_rank)
		)
		var availability: Dictionary = opponent_registry.call(
			"get_availability",
			opponent_id,
			player_rank,
			&"",
			&"",
			_opponent_availability_context()
		)
		if not bool(availability.get("available", false)):
			push_warning(
				"TripleTriadGame: opponent '%s' is locked: %s"
				% [String(opponent_id), str(availability.get("reason", "Unavailable."))]
			)
			return false

	open_game(profile)
	return is_open()


func open_game(opponent_profile_override: Resource = null) -> void:
	if not _backend_ready or is_open() or card_catalog == null:
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
	_previous_pause = tree.paused
	_round_number = 1
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
	root.visible = true
	_set_match_skin_visible(false)
	_phase = PHASE_DECK_SETUP
	deck_setup.open_setup(
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
	ai_timer.stop()
	reward_view.close_reward()
	debug_menu.close_menu()
	deck_setup.close_setup()
	transition_fade.visible = false
	transition_fade.modulate = Color(1, 1, 1, 0)
	if _result_dim != null:
		_result_dim.visible = false
	_hide_preview_visuals()
	_match_started = false
	_surrendered = false
	_result_reason = &""
	_phase = PHASE_CLOSED
	_set_match_skin_visible(false)
	root.visible = false
	_checkpoint_save_integrity("close_game")
	_invalidate_state_api("close_game")
	_opponent_collection_backend = null
	var tree: SceneTree = get_tree()
	if tree != null:
		tree.paused = _previous_pause
	closed.emit()


func _input(event: InputEvent) -> void:
	if not is_open() or not _pressed(event):
		return

	if _phase == PHASE_DECK_SETUP:
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

	if _is_debug_toggle(event) and _phase in [PHASE_SELECT_CARD, PHASE_SELECT_CELL, PHASE_RESULT]:
		debug_menu.open_menu(_qa_base_summary, _qa_profile_override)
		_accept_input()


func _unhandled_input(event: InputEvent) -> void:
	if not is_open() or not _pressed(event):
		return

	if _phase == PHASE_DECK_SETUP:
		return

	# The reward view owns input while it is active and enforces mandatory stake
	# resolution. It cannot be bypassed with Back/Escape.
	if _phase == PHASE_REWARD:
		return

	if _phase == PHASE_RESULT:
		if _is_confirm(event) or _is_back(event):
			_begin_result_transition()
			_accept_input()
		return

	# Before the deal is complete the player can still leave freely. Once the
	# live match begins, leaving from a stable gameplay phase is a surrender.
	if _phase == PHASE_DEALING:
		if _is_back(event):
			close_game()
			_accept_input()
		return

	# Placement/capture animation is transactional. Ignore leave input until a
	# stable phase instead of interrupting a move half-way through.
	if _phase == PHASE_ANIMATING:
		if _is_back(event):
			_accept_input()
		return

	if _phase == PHASE_AI:
		if _is_back(event):
			_request_surrender()
			_accept_input()
		return

	if _phase == PHASE_SELECT_CARD:
		var hand_step: int = _hand_step(event)
		if hand_step != 0:
			_selected_hand_index = clampi(
				_selected_hand_index + hand_step,
				0,
				maxi(_match.player_hand.size() - 1, 0)
			)
			_refresh_views()
			_accept_input()
			return
		if _is_rotate(event):
			_try_rotate_selected_card()
			_accept_input()
			return
		if _is_confirm(event) and not _match.player_hand.is_empty():
			_phase = PHASE_SELECT_CELL
			_selected_cell_index = _find_nearest_empty_cell(_selected_cell_index)
			_refresh_views()
			_accept_input()
			return
		if _is_back(event):
			_request_surrender()
			_accept_input()
			return

	if _phase == PHASE_SELECT_CELL:
		var moved: bool = false
		if _is_left(event):
			_selected_cell_index = _move_board_cursor(_selected_cell_index, -1, 0)
			moved = true
		elif _is_right(event):
			_selected_cell_index = _move_board_cursor(_selected_cell_index, 1, 0)
			moved = true
		elif _is_up(event):
			_selected_cell_index = _move_board_cursor(_selected_cell_index, 0, -1)
			moved = true
		elif _is_down(event):
			_selected_cell_index = _move_board_cursor(_selected_cell_index, 0, 1)
			moved = true
		if moved:
			_refresh_views()
			_accept_input()
			return
		if _is_rotate(event):
			_try_rotate_selected_card()
			_accept_input()
			return
		if _is_confirm(event):
			_try_player_move()
			_accept_input()
			return
		if _is_back(event):
			# First Back cancels the board preview and returns to the hand. A second
			# Back from card selection is the deliberate surrender action.
			_phase = PHASE_SELECT_CARD
			_refresh_views()
			_accept_input()


func _start_new_match(player_cards_override: Array = []) -> void:
	ai_timer.stop()
	_set_match_skin_visible(true)
	reward_view.close_reward()
	result_label.visible = false
	if _result_dim != null:
		_result_dim.visible = false
	transition_fade.visible = false
	transition_fade.modulate = Color(1, 1, 1, 0)
	_result_winner = OWNER_NONE
	_result_reason = &""
	_surrendered = false
	_match_started = false
	message_label.text = ""
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
		opponent_cards = _opponent_collection_backend.build_match_deck(5, _active_deck_budget)
	if opponent_cards.size() != 5:
		push_error("TripleTriadGame: opponent %s has no legal persistent deck." % String(_active_opponent_id()))
		message_label.text = "Opponent deck is invalid."
		close_game()
		return
	_starting_player_cards = player_cards.duplicate()
	_starting_opponent_cards = opponent_cards.duplicate()
	var starting_owner: int
	match _qa_forced_starting_owner:
		OWNER_PLAYER:
			starting_owner = OWNER_PLAYER
		OWNER_OPPONENT:
			starting_owner = OWNER_OPPONENT
		_:
			starting_owner = OWNER_PLAYER if _rng.randi_range(0, 1) == 0 else OWNER_OPPONENT
	_match.reset_match(player_cards, opponent_cards, starting_owner, _active_rule_set, _active_region_profile)
	_selected_hand_index = 0
	_selected_cell_index = 4
	_phase = PHASE_DEALING
	_refresh_views()
	_run_deal_sequence(starting_owner)


func _run_deal_sequence(starting_owner: int) -> void:
	await animation_director.deal_hands(_player_views, _opponent_views, HAND_STEP_Y)
	if not is_open() or _phase != PHASE_DEALING:
		return
	_match_started = true
	_phase = PHASE_SELECT_CARD if starting_owner == OWNER_PLAYER else PHASE_AI
	message_label.text = ""
	_refresh_views()
	if _phase == PHASE_AI:
		_schedule_ai()


func _try_player_move() -> void:
	if _selected_hand_index < 0 or _selected_hand_index >= _match.player_hand.size():
		return
	if _selected_cell_index < 0 or _selected_cell_index >= 9:
		return
	if _match.board[_selected_cell_index] != null:
		message_label.text = "That space is occupied."
		return

	var played_card = _match.player_hand[_selected_hand_index]
	var played_rotation: int = _match.get_hand_rotation(OWNER_PLAYER, _selected_hand_index)
	var target_rank_bonus: int = _match.get_cell_rank_bonus(_selected_cell_index)
	var source_view: Control = _player_views[_selected_hand_index]
	var target_view: Control = _board_views[_selected_cell_index]
	var result: Dictionary = _match.place_card(OWNER_PLAYER, _selected_hand_index, _selected_cell_index)
	if not bool(result.get("success", false)):
		message_label.text = "Invalid move."
		return

	# place_card() removes the played card from the hand. Clamp immediately so the
	# lower information panel advances straight to the next remaining card instead
	# of flashing empty during the placement animation/opponent turn.
	_selected_hand_index = clampi(
		_selected_hand_index,
		0,
		maxi(_match.player_hand.size() - 1, 0)
	)
	_phase = PHASE_ANIMATING
	_last_info_name = str(played_card.display_name)
	_refresh_phase_ui()
	var placement_rank_modifier: int = int(result.get("placed_total_modifier", target_rank_bonus))
	await animation_director.animate_placement(root, source_view, target_view, played_card, OWNER_PLAYER, played_rotation, placement_rank_modifier)
	if not is_open():
		return

	message_label.text = _capture_message(result)
	var captured_cells: Array = result.get("captured", [])
	_refresh_views(captured_cells)
	if not captured_cells.is_empty():
		await get_tree().create_timer(CAPTURE_SETTLE_SECONDS, true).timeout
		if not is_open():
			return

	if bool(result.get("game_over", false)):
		_finish_match()
	else:
		_phase = PHASE_AI
		_refresh_views()
		_schedule_ai()


func _on_ai_timer_timeout() -> void:
	if _phase != PHASE_AI or _match.game_over:
		return
	_run_ai_turn()


func _run_ai_turn() -> void:
	var move: Dictionary = _ai.choose_move(_match, OWNER_OPPONENT, _rng, _active_ai_profile)
	if not bool(move.get("valid", false)):
		_finish_match()
		return

	var hand_index: int = int(move.get("hand_index", 0))
	var cell_index: int = int(move.get("cell_index", 0))
	if hand_index < 0 or hand_index >= _match.opponent_hand.size():
		_finish_match()
		return

	if bool(move.get("rotate", false)):
		_match.rotate_hand_card(OWNER_OPPONENT, hand_index)
	var played_card = _match.opponent_hand[hand_index]
	var played_rotation: int = _match.get_hand_rotation(OWNER_OPPONENT, hand_index)
	var target_rank_bonus: int = _match.get_cell_rank_bonus(cell_index)
	var source_view: Control = _opponent_views[hand_index]
	var target_view: Control = _board_views[cell_index]
	var result: Dictionary = _match.place_card(OWNER_OPPONENT, hand_index, cell_index)
	if not bool(result.get("success", false)):
		_finish_match()
		return

	_phase = PHASE_ANIMATING
	_last_info_name = str(played_card.display_name)
	_refresh_phase_ui()
	var placement_rank_modifier: int = int(result.get("placed_total_modifier", target_rank_bonus))
	await animation_director.animate_placement(root, source_view, target_view, played_card, OWNER_OPPONENT, played_rotation, placement_rank_modifier)
	if not is_open():
		return

	message_label.text = _capture_message(result)
	var captured_cells: Array = result.get("captured", [])
	_refresh_views(captured_cells)
	if not captured_cells.is_empty():
		await get_tree().create_timer(CAPTURE_SETTLE_SECONDS, true).timeout
		if not is_open():
			return

	if bool(result.get("game_over", false)):
		_finish_match()
	else:
		_phase = PHASE_SELECT_CARD
		_selected_hand_index = clampi(_selected_hand_index, 0, maxi(_match.player_hand.size() - 1, 0))
		_selected_cell_index = _find_nearest_empty_cell(_selected_cell_index)
		_refresh_views()


func _request_surrender() -> void:
	if not _match_started:
		close_game()
		return
	if _phase not in [PHASE_SELECT_CARD, PHASE_AI]:
		return
	_surrendered = true
	message_label.text = "SURRENDER"
	_finish_match(OWNER_OPPONENT, &"surrender")


func _finish_match(
	forced_winner: int = OWNER_NONE,
	reason: StringName = &"board_complete"
) -> void:
	ai_timer.stop()
	_match_started = false
	_phase = PHASE_RESULT
	_hide_preview_visuals()
	_refresh_views()
	var score: Dictionary = _match.get_score()
	_result_winner = (
		forced_winner
		if forced_winner in [OWNER_PLAYER, OWNER_OPPONENT]
		else _match.get_winner()
	)
	_result_reason = reason

	var progression_change: Dictionary = {}
	# QA/debug matches must never mutate permanent progression. Campaign points
	# are first-clear rewards by default; rematches still count in match records
	# and can award a separately-authored rematch value if desired.
	if _progression != null and _qa_profile_override == null:
		var already_beaten: bool = false
		if _encounter_records != null:
			var previous_record: Dictionary = _encounter_records.get_snapshot(
				_active_opponent_id()
			)
			already_beaten = bool(previous_record.get("beaten_before", false))
		var progression_override: int = -1
		if _result_winner == OWNER_PLAYER and _active_opponent_profile != null:
			var first_win_only_value = _active_opponent_profile.get(
				"first_win_progression_only"
			)
			if bool(first_win_only_value) and already_beaten:
				progression_override = maxi(
					0,
					int(_active_opponent_profile.get(
						"rematch_progression_points_on_win"
					))
				)
		progression_change = _progression.record_result(
			_result_winner,
			OWNER_PLAYER,
			_active_opponent_profile,
			progression_override
		)
		if _encounter_records != null:
			_encounter_records.record_result(
				_active_opponent_id(),
				_result_winner,
				OWNER_PLAYER,
				OWNER_OPPONENT
			)

	match _result_winner:
		OWNER_PLAYER:
			result_label.text = "YOU WIN!"
		OWNER_OPPONENT:
			result_label.text = "YOU SURRENDER..." if _surrendered else "YOU LOSE..."
		_:
			result_label.text = "DRAW"
	if _result_dim != null:
		_result_dim.visible = true
	result_label.visible = true
	turn_label.text = ""
	help_label.text = "K: Continue"
	selection_arrow.visible = false
	turn_arrow.visible = false
	match_finished.emit({
		"winner": _result_winner,
		"score": score,
		"progression": progression_change,
		"reason": String(_result_reason),
		"surrendered": _surrendered,
	})
	_publish_backend_state_change("match_result")


func _begin_result_transition() -> void:
	if _phase != PHASE_RESULT:
		return
	_phase = PHASE_ANIMATING
	help_label.text = ""
	_run_result_transition(_result_winner)


func _run_result_transition(winner: int) -> void:
	transition_fade.visible = true
	transition_fade.modulate = Color(1, 1, 1, 0)
	var fade_in: Tween = transition_fade.create_tween()
	fade_in.set_trans(Tween.TRANS_QUAD)
	fade_in.set_ease(Tween.EASE_IN_OUT)
	fade_in.tween_property(transition_fade, "modulate", Color.WHITE, RESULT_FADE_IN_SECONDS)
	await fade_in.finished
	if not is_open():
		return

	result_label.visible = false
	if _result_dim != null:
		_result_dim.visible = false
	if winner not in [OWNER_PLAYER, OWNER_OPPONENT]:
		# A draw is a replay, not an exit. Re-deal behind the black result fade,
		# then reveal the fresh match using the same active QA/opponent profile.
		_round_number += 1
		_start_new_match(_active_player_deck)
		transition_fade.visible = true
		transition_fade.modulate = Color.WHITE
		var replay_fade: Tween = transition_fade.create_tween()
		replay_fade.set_trans(Tween.TRANS_QUAD)
		replay_fade.set_ease(Tween.EASE_IN_OUT)
		replay_fade.tween_property(transition_fade, "modulate", Color(1, 1, 1, 0), RESULT_FADE_OUT_SECONDS)
		await replay_fade.finished
		if not is_open():
			return
		transition_fade.visible = false
		return

	_phase = PHASE_REWARD
	var opponent_take_index: int = -1
	if winner == OWNER_OPPONENT:
		opponent_take_index = _choose_safe_player_stake_index()
	var eligible_reward_ids := PackedStringArray()
	if winner == OWNER_PLAYER:
		eligible_reward_ids = _player_reward_candidate_ids()
	reward_view.open_reward(
		_starting_opponent_cards,
		_starting_player_cards,
		winner,
		true,
		opponent_take_index,
		eligible_reward_ids
	)
	_refresh_phase_ui()

	# Reveal the result screen while both card rows begin sliding into place.
	reward_view.start_entrance()
	var fade_out: Tween = transition_fade.create_tween()
	fade_out.set_trans(Tween.TRANS_QUAD)
	fade_out.set_ease(Tween.EASE_IN_OUT)
	fade_out.tween_property(transition_fade, "modulate", Color(1, 1, 1, 0), RESULT_FADE_OUT_SECONDS)
	await fade_out.finished
	if not is_open():
		return
	transition_fade.visible = false


func _choose_safe_player_stake_index() -> int:
	var minimum_unique: int = 5
	var protect_collection: bool = true
	if DefaultEconomyPolicy != null:
		minimum_unique = maxi(
			5,
			int(DefaultEconomyPolicy.minimum_playable_unique_cards)
		)
		protect_collection = bool(
			DefaultEconomyPolicy.protect_minimum_playable_collection
		)

	if not protect_collection:
		return _stake_policy.choose_lost_card_index(
			_starting_player_cards
		)

	var playable_cards: Array = _get_playable_owned_cards()
	var quantities: Dictionary = {}
	if (
		_collection_backend != null
		and _collection_backend.has_method("get_quantities_snapshot")
	):
		quantities = _collection_backend.call(
			"get_quantities_snapshot"
		)

	return _stake_policy.choose_lost_card_index(
		_starting_player_cards,
		playable_cards,
		quantities,
		minimum_unique
	)


func _get_playable_owned_cards() -> Array:
	var result: Array = []
	if _collection_backend == null:
		return result
	if not _collection_backend.has_method("get_owned_cards"):
		return result

	var player_rank: int = 1
	if _progression != null and _progression.has_method("get_rank_number"):
		player_rank = maxi(
			1,
			int(_progression.call("get_rank_number"))
		)

	for card in _collection_backend.call("get_owned_cards"):
		if card == null:
			continue
		var usable: bool = true
		if (
			DefaultAcquisitionPolicy != null
			and DefaultAcquisitionPolicy.has_method("can_use_card")
		):
			usable = bool(
				DefaultAcquisitionPolicy.call(
					"can_use_card",
					card,
					player_rank
				)
			)
		if usable:
			result.append(card)
	return result


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

	var playable_unique: int = _get_playable_owned_cards().size()
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


func _player_reward_candidate_ids() -> PackedStringArray:
	if _active_opponent_profile == null:
		return PackedStringArray()

	var raw_reward_ids = _active_opponent_profile.get("reward_card_ids")
	var reward_ids: Dictionary = {}
	if raw_reward_ids is PackedStringArray or raw_reward_ids is Array:
		for raw_id in raw_reward_ids:
			reward_ids[str(raw_id)] = true

	# Priority cards are cards this opponent previously won from the player.
	# They are always valid reward choices so rematches can recover stolen cards.
	var priority_ids: Dictionary = {}
	if (
		_opponent_collection_backend != null
		and _opponent_collection_backend.has_method("get_priority_ids")
	):
		for raw_id in _opponent_collection_backend.call("get_priority_ids"):
			priority_ids[str(raw_id)] = true

	if reward_ids.is_empty() and priority_ids.is_empty():
		return PackedStringArray()

	var result := PackedStringArray()
	for card in _starting_opponent_cards:
		if card == null:
			continue
		var card_id: String = String(card.card_id)
		if reward_ids.has(card_id) or priority_ids.has(card_id):
			result.append(card_id)

	# Empty means "all cards eligible" in RewardView. This safety fallback avoids
	# a mandatory-stake soft lock if authored content and a migrated save drift.
	return result


func _schedule_ai() -> void:
	ai_timer.start(maxf(ai_delay_seconds, 0.01))


func _build_views() -> void:
	for index in range(5):
		var opponent_view: Control = CardViewScene.instantiate() as Control
		opponent_hand_container.add_child(opponent_view)
		# CardView centers its pivot for flip animations. Hand cards are scaled, so
		# reset the pivot here to keep their visible top-left aligned to the baked
		# card backs instead of shrinking inward by ~20 px.
		opponent_view.pivot_offset = Vector2.ZERO
		opponent_view.position = Vector2(0.0, float(index) * HAND_STEP_Y)
		opponent_view.scale = CARD_VISUAL_SCALE
		opponent_view.z_index = index
		_opponent_views.append(opponent_view)
	for _index in range(9):
		var board_view: Control = CardViewScene.instantiate() as Control
		board_container.add_child(board_view)
		_board_views.append(board_view)
	for index in range(5):
		var player_view: Control = CardViewScene.instantiate() as Control
		player_hand_container.add_child(player_view)
		player_view.pivot_offset = Vector2.ZERO
		player_view.position = Vector2(0.0, float(index) * HAND_STEP_Y)
		player_view.scale = CARD_VISUAL_SCALE
		player_view.z_index = index
		_player_views.append(player_view)
	_build_preview_visuals()


func _build_preview_visuals() -> void:
	_preview_ghost = CardViewScene.instantiate() as Control
	root.add_child(_preview_ghost)
	_preview_ghost.visible = false
	_preview_ghost.pivot_offset = Vector2.ZERO
	_preview_ghost.modulate = Color(1, 1, 1, PREVIEW_GHOST_ALPHA)
	_preview_ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_preview_ghost.z_index = 620

	_influence_preview_overlays.clear()
	for _cell_index in range(9):
		var overlay := ColorRect.new()
		overlay.visible = false
		overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
		overlay.z_index = 610
		root.add_child(overlay)
		_influence_preview_overlays.append(overlay)

	_active_influence_overlays.clear()
	for _cell_index in range(9):
		var active_overlay := Panel.new()
		active_overlay.visible = false
		active_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
		active_overlay.z_index = 608
		root.add_child(active_overlay)
		_active_influence_overlays.append(active_overlay)


func _hide_preview_visuals() -> void:
	if is_instance_valid(_preview_ghost):
		_preview_ghost.visible = false
	for overlay in _influence_preview_overlays:
		if is_instance_valid(overlay):
			overlay.visible = false


func _refresh_active_influence_visuals() -> void:
	for overlay in _active_influence_overlays:
		if is_instance_valid(overlay):
			overlay.visible = false
	if _match == null or not _match.has_method("get_influence_board_snapshot"):
		return

	var influence_snapshot: Array = _match.call("get_influence_board_snapshot")
	for cell_index in range(mini(influence_snapshot.size(), _active_influence_overlays.size())):
		var cell_state: Dictionary = influence_snapshot[cell_index]
		var player_pressure: int = int(cell_state.get("player_pressure", 0))
		var opponent_pressure: int = int(cell_state.get("opponent_pressure", 0))
		if player_pressure <= 0 and opponent_pressure <= 0:
			continue

		var overlay: Panel = _active_influence_overlays[cell_index]
		var board_rect: Rect2 = _board_cell_visual_rect(cell_index)
		overlay.position = board_rect.position
		overlay.size = board_rect.size
		overlay.add_theme_stylebox_override(
			"panel",
			_active_influence_style(player_pressure > 0, opponent_pressure > 0)
		)
		overlay.visible = true


func _active_influence_style(has_player_pressure: bool, has_opponent_pressure: bool) -> StyleBoxFlat:
	var fill: Color = ACTIVE_INFLUENCE_PLAYER_FILL
	var border: Color = ACTIVE_INFLUENCE_PLAYER_BORDER
	if has_player_pressure and has_opponent_pressure:
		fill = ACTIVE_INFLUENCE_BOTH_FILL
		border = ACTIVE_INFLUENCE_BOTH_BORDER
	elif has_opponent_pressure:
		fill = ACTIVE_INFLUENCE_OPPONENT_FILL
		border = ACTIVE_INFLUENCE_OPPONENT_BORDER

	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.set_corner_radius_all(2)
	return style


func _preview_for_current_selection() -> Dictionary:
	if (
		_phase != PHASE_SELECT_CELL
		or _match == null
		or _selected_hand_index < 0
		or _selected_hand_index >= _match.player_hand.size()
		or _selected_cell_index < 0
		or _selected_cell_index >= 9
		or _match.board[_selected_cell_index] != null
	):
		return {}
	var card = _match.player_hand[_selected_hand_index]
	var rotation_quarters: int = _match.get_hand_rotation(OWNER_PLAYER, _selected_hand_index)
	return _match.preview_move(card, OWNER_PLAYER, _selected_cell_index, rotation_quarters)


func _refresh_preview_visuals(preview: Dictionary) -> void:
	_hide_preview_visuals()
	if preview.is_empty() or not bool(preview.get("valid", false)):
		return
	if _selected_hand_index < 0 or _selected_hand_index >= _match.player_hand.size():
		return

	var card = _match.player_hand[_selected_hand_index]
	var rotation_quarters: int = _match.get_hand_rotation(OWNER_PLAYER, _selected_hand_index)
	var target_view: Control = _board_views[_selected_cell_index]
	var target_rect: Rect2 = _board_cell_visual_rect(_selected_cell_index)
	_preview_ghost.visible = true
	_preview_ghost.modulate = Color(1, 1, 1, PREVIEW_GHOST_ALPHA)
	_preview_ghost.position = target_rect.position
	_preview_ghost.size = target_view.size
	_preview_ghost.scale = board_container.scale
	_preview_ghost.configure(
		card,
		OWNER_PLAYER,
		false,
		false,
		rotation_quarters,
		int(preview.get("placed_total_modifier", 0))
	)
	_preview_ghost.set_owner_outline_visible(false)
	_preview_ghost.set_selected(false)

	for raw_cell in preview.get("influence_cells", []):
		var cell_index: int = int(raw_cell)
		if cell_index < 0 or cell_index >= _influence_preview_overlays.size():
			continue
		var overlay: ColorRect = _influence_preview_overlays[cell_index]
		var board_rect: Rect2 = _board_cell_visual_rect(cell_index)
		overlay.position = board_rect.position
		overlay.size = board_rect.size
		var slot_variant = _match.board[cell_index]
		var pressures_enemy: bool = false
		if slot_variant != null:
			var preview_slot: Dictionary = slot_variant
			pressures_enemy = int(preview_slot.get("owner", OWNER_NONE)) == OWNER_OPPONENT
		overlay.color = PREVIEW_PRESSURE_COLOR if pressures_enemy else PREVIEW_INFLUENCE_COLOR
		overlay.visible = true


func _refresh_views(captured_cells: Array = []) -> void:
	if _match == null:
		return
	var show_opponent_cards: bool = _active_rule_set == null or bool(_active_rule_set.open_rule)
	var active_preview: Dictionary = _preview_for_current_selection()
	var preview_modifiers: Dictionary = active_preview.get("influence_modifiers", {})
	# Build current board pressure once per UI refresh. Input-driven refreshes are
	# cheap and deterministic; we never rebuild influence state per frame.
	var current_influence_modifiers: Dictionary = (
		{}
		if not active_preview.is_empty()
		else _match.get_current_influence_modifiers()
	)

	for index in range(_opponent_views.size()):
		var view: Control = _opponent_views[index]
		view.modulate = Color.WHITE
		view.scale = CARD_VISUAL_SCALE
		if index < _match.opponent_hand.size():
			view.visible = true
			view.configure(_match.opponent_hand[index], OWNER_OPPONENT, not show_opponent_cards, false, _match.get_hand_rotation(OWNER_OPPONENT, index), 0)
			view.set_owner_outline_visible(false)
			view.set_selected(false)
			view.position = Vector2(0.0, float(index) * HAND_STEP_Y)
			view.z_index = index
		else:
			view.visible = false

	for index in range(_player_views.size()):
		var view: Control = _player_views[index]
		view.modulate = Color.WHITE
		view.scale = CARD_VISUAL_SCALE
		if index < _match.player_hand.size():
			view.visible = true
			view.configure(_match.player_hand[index], OWNER_PLAYER, false, false, _match.get_hand_rotation(OWNER_PLAYER, index), 0)
			view.set_owner_outline_visible(false)
			var is_selected: bool = (
				_phase in [PHASE_SELECT_CARD, PHASE_SELECT_CELL]
				and index == _selected_hand_index
			)
			# Selection is communicated by the side arrow + a small left nudge.
			# The ownership border remains blue instead of changing to yellow.
			view.set_selected(false)
			view.position = Vector2(
				HAND_SELECTED_X_OFFSET if is_selected else 0.0,
				float(index) * HAND_STEP_Y
			)
			view.z_index = index
		else:
			view.visible = false

	for cell_index in range(_board_views.size()):
		var board_view: Control = _board_views[cell_index]
		var slot_variant = _match.board[cell_index]
		if slot_variant == null:
			board_view.configure(null, OWNER_NONE, false)
		else:
			var slot: Dictionary = slot_variant
			var slot_owner: int = int(slot["owner"])
			var influence_modifier: int = (
				int(preview_modifiers.get(cell_index, 0))
				if not active_preview.is_empty()
				else int(current_influence_modifiers.get(cell_index, 0))
			)
			board_view.configure(
				slot["card"],
				slot_owner,
				false,
				captured_cells.has(cell_index),
				int(slot.get("rotation", 0)),
				_match.get_cell_rank_bonus(cell_index) + influence_modifier
			)
		board_view.set_owner_outline_visible(false)
		board_view.set_selected(_phase == PHASE_SELECT_CELL and cell_index == _selected_cell_index)

	_refresh_active_influence_visuals()
	_refresh_preview_visuals(active_preview)
	var score: Dictionary = _match.get_score()
	if _match_hud != null:
		_match_hud.call("set_scores", int(score["opponent"]), int(score["player"]))
	_refresh_phase_ui()
	runtime_state_changed.emit(get_runtime_ui_snapshot())


func _set_score_digits(target: Control, value: int) -> void:
	if target == null:
		return
	var score_text := str(value)
	target.call("set_text", score_text)
	var score_parent := target.get_parent() as Control
	if score_parent == null:
		return
	var glyph_count: int = score_text.length()
	var unscaled_width := float(glyph_count * 16)
	var scaled_width := unscaled_width * target.scale.x
	var scaled_height := 16.0 * target.scale.y
	target.position = Vector2(
		(score_parent.size.x - scaled_width) * 0.5,
		(score_parent.size.y - scaled_height) * 0.5
	)


func _refresh_phase_ui() -> void:
	selection_arrow.visible = false
	turn_arrow.visible = false
	# The old beige prototype InfoPanel is retired. Keep its labels empty so no
	# legacy text can leak over the authored background.
	info_panel.visible = false
	turn_label.text = ""
	info_label.text = ""

	match _phase:
		PHASE_DEALING:
			help_label.text = ""
		PHASE_SELECT_CARD:
			help_label.text = ""
			_update_player_selection_markers()
		PHASE_SELECT_CELL:
			help_label.text = ""
			_update_player_selection_markers()
		PHASE_AI:
			help_label.text = ""
			_turn_arrow_for_owner(OWNER_OPPONENT)
		PHASE_ANIMATING:
			help_label.text = ""
		PHASE_RESULT:
			help_label.text = ""
		PHASE_REWARD:
			help_label.text = ""

	_refresh_match_hud()


func _refresh_match_hud() -> void:
	if _match_hud == null:
		return

	var turn_text: String = ""
	match _phase:
		PHASE_SELECT_CARD, PHASE_SELECT_CELL:
			turn_text = "Your Turn"
		PHASE_AI:
			turn_text = "Opponent Turn"
		PHASE_DEALING:
			turn_text = "Dealing"
		PHASE_RESULT:
			turn_text = "Result"
	_match_hud.call("set_turn_text", turn_text)
	var top_info_text: String = message_label.text.strip_edges()
	if top_info_text.is_empty():
		top_info_text = _region_trait_text()
	_match_hud.call("set_top_info_text", top_info_text)
	_match_hud.call("set_round_number", _round_number)
	_match_hud.call("set_help_entries", _current_help_entries())

	if (
		_match != null
		and _phase not in [PHASE_RESULT, PHASE_REWARD, PHASE_CLOSED]
		and not _match.player_hand.is_empty()
	):
		_selected_hand_index = clampi(
			_selected_hand_index,
			0,
			_match.player_hand.size() - 1
		)
		var selected_card = _match.player_hand[_selected_hand_index]
		var selected_rotation: int = _match.get_hand_rotation(
			OWNER_PLAYER,
			_selected_hand_index
		)
		_match_hud.call("set_card_info", selected_card, selected_rotation)
	else:
		_match_hud.call("clear_card_info")


func _update_player_selection_markers() -> void:
	if _match.player_hand.is_empty():
		return
	selection_arrow.visible = true
	selection_arrow.position = Vector2(
		player_hand_container.position.x - 16.0,
		player_hand_container.position.y + float(_selected_hand_index) * HAND_STEP_Y + 44.0
	)
	_turn_arrow_for_owner(OWNER_PLAYER)


func _turn_arrow_for_owner(turn_owner: int) -> void:
	turn_arrow.visible = true
	turn_arrow.position = Vector2(58.0, 31.0) if turn_owner == OWNER_OPPONENT else Vector2(574.0, 31.0)


func _update_selected_card_info() -> void:
	_refresh_match_hud()


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
	var transfer_success: bool = false
	if card_definition == null:
		reward_view.resolve_transfer_request(false)
		return

	_last_info_name = str(card_definition.display_name)
	if _card_economy == null or _opponent_collection_backend == null:
		push_error("TripleTriadGame: card economy is unavailable during reward transfer.")
		reward_view.resolve_transfer_request(false)
		return

	if _result_winner == OWNER_PLAYER:
		transfer_success = _card_economy.transfer_opponent_to_player(
			card_definition,
			_collection_backend,
			_opponent_collection_backend
		)
		if transfer_success:
			if _acquisition_tracker != null:
				_acquisition_tracker.record_acquisition(
					card_definition,
					&"opponent_win",
					_active_opponent_id()
				)
			if _encounter_records != null:
				_encounter_records.record_card_recovered(
					_active_opponent_id(),
					StringName(card_definition.card_id)
				)
			card_reward_selected.emit(card_definition)
		else:
			push_error("TripleTriadGame: failed to transfer mandatory reward card to player.")

	elif _result_winner == OWNER_OPPONENT:
		transfer_success = _card_economy.transfer_player_to_opponent(
			card_definition,
			_collection_backend,
			_opponent_collection_backend
		)
		if transfer_success:
			if _acquisition_tracker != null:
				_acquisition_tracker.record_loss(
					card_definition,
					&"opponent_loss",
					_active_opponent_id()
				)
			if _encounter_records != null:
				_encounter_records.record_card_stolen(
					_active_opponent_id(),
					StringName(card_definition.card_id)
				)

			if not _collection_backend.owns_card(card_definition):
				deck_setup.remove_card_from_all_profiles(StringName(card_definition.card_id))
				var filtered_active_deck: Array = []
				for card in _active_player_deck:
					if card != null and String(card.card_id) != String(card_definition.card_id):
						filtered_active_deck.append(card)
				_active_player_deck = filtered_active_deck
		else:
			push_error("TripleTriadGame: failed to transfer mandatory lost card to opponent.")

	if transfer_success:
		_checkpoint_save_integrity("reward_transfer")
		_publish_backend_state_change("card_transfer")
	reward_view.resolve_transfer_request(transfer_success)


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
	reward_view.close_reward()
	close_game()



func _on_deck_confirmed(cards: Array) -> void:
	if _phase != PHASE_DECK_SETUP or cards.size() != 5:
		return
	_active_player_deck = cards.duplicate()
	deck_setup.close_setup()
	_publish_backend_state_change("deck_selected")
	_start_new_match(_active_player_deck)


func _on_deck_cancelled() -> void:
	if _phase != PHASE_DECK_SETUP:
		return
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

	# Keep the NPC configuration as the debug menu's CURRENT/NPC baseline, then
	# layer any temporary QA profile over it.
	_qa_base_summary = _configuration_summary()
	_apply_qa_profile_override()


func _apply_qa_profile_override() -> void:
	_qa_forced_starting_owner = OWNER_NONE
	_qa_hand_seed = 0
	if _qa_profile_override == null:
		return

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
	match _phase:
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
	if preferred >= 0 and preferred < 9 and _match.board[preferred] == null:
		return preferred
	var empty_cells: Array[int] = _match.get_empty_cells()
	if empty_cells.is_empty():
		return 0
	return empty_cells[0]


func _move_board_cursor(current: int, dx: int, dy: int) -> int:
	var row: int = floori(float(current) / 3.0)
	var column: int = current % 3
	column = clampi(column + dx, 0, 2)
	row = clampi(row + dy, 0, 2)
	return row * 3 + column


func _accept_input() -> void:
	var viewport: Viewport = get_viewport()
	if viewport != null:
		viewport.set_input_as_handled()


func _pressed(event: InputEvent) -> bool:
	return event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo


func _is_confirm(event: InputEvent) -> bool:
	return _key_matches(event, KEY_K) or _key_matches(event, KEY_ENTER)


func _is_back(event: InputEvent) -> bool:
	return _key_matches(event, KEY_I) or _key_matches(event, KEY_ESCAPE)


func _is_left(event: InputEvent) -> bool:
	return _key_matches(event, KEY_A) or _key_matches(event, KEY_LEFT)


func _is_right(event: InputEvent) -> bool:
	return _key_matches(event, KEY_D) or _key_matches(event, KEY_RIGHT)


func _is_up(event: InputEvent) -> bool:
	return _key_matches(event, KEY_W) or _key_matches(event, KEY_UP)


func _is_down(event: InputEvent) -> bool:
	return _key_matches(event, KEY_S) or _key_matches(event, KEY_DOWN)


func _is_rotate(event: InputEvent) -> bool:
	return _key_matches(event, KEY_R)


func _is_debug_toggle(event: InputEvent) -> bool:
	return _key_matches(event, KEY_F10)


func _hand_step(event: InputEvent) -> int:
	if _is_up(event):
		return -1
	if _is_down(event):
		return 1
	return 0


func _key_matches(event: InputEvent, key: Key) -> bool:
	if not (event is InputEventKey):
		return false
	var key_event := event as InputEventKey
	return key_event.keycode == key or key_event.physical_keycode == key
