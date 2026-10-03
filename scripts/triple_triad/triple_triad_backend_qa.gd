extends RefCounted

const MatchScript = preload("res://scripts/triple_triad/triple_triad_match.gd")
const AIScript = preload("res://scripts/triple_triad/triple_triad_ai.gd")
const AcquisitionPolicyScript = preload(
	"res://scripts/triple_triad/triple_triad_acquisition_policy.gd"
)
const OpponentProfileScript = preload(
	"res://scripts/triple_triad/triple_triad_opponent_profile.gd"
)
const OpponentRegistryScript = preload(
	"res://scripts/triple_triad/triple_triad_opponent_registry.gd"
)
const RuleSetScript = preload(
	"res://scripts/triple_triad/triple_triad_rule_set.gd"
)
const StakePolicyScript = preload("res://scripts/triple_triad/triple_triad_stake_policy.gd")
const DefaultCardCatalog = preload("res://data/triple_triad/card_catalog.tres")
const DefaultOpponentRegistry = preload("res://data/triple_triad/opponents/opponent_registry.tres")
const DefaultAcquisitionRegistry = preload("res://data/triple_triad/acquisition/acquisition_registry.tres")
const WorldAcquisitionCatalogScript = preload("res://scripts/triple_triad/triple_triad_world_acquisition_catalog.gd")
const CompetitionCatalogScript = preload("res://scripts/triple_triad/triple_triad_competition_catalog.gd")
const CompetitionServiceScript = preload("res://scripts/triple_triad/triple_triad_competition_service.gd")
const CompletionTrackerScript = preload("res://scripts/triple_triad/triple_triad_completion_tracker.gd")
const WorldProgressionDirectorScript = preload("res://scripts/triple_triad/triple_triad_world_progression_director.gd")
const OpponentEvolutionScript = preload("res://scripts/triple_triad/triple_triad_opponent_evolution.gd")
const GameplayEventFeedScript = preload("res://scripts/triple_triad/triple_triad_gameplay_event_feed.gd")
const MatchResolutionJournalScript = preload("res://scripts/triple_triad/triple_triad_match_resolution_journal.gd")
const WorldRewardLedgerScript = preload("res://scripts/triple_triad/triple_triad_world_reward_ledger.gd")
const SessionControllerScript = preload("res://scripts/triple_triad/triple_triad_session_controller.gd")
const MatchFlowControllerScript = preload("res://scripts/triple_triad/triple_triad_match_flow_controller.gd")
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
const BackendValidatorScript = preload(
	"res://scripts/triple_triad/triple_triad_backend_validator.gd"
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
const PersistenceControllerScript = preload(
	"res://scripts/triple_triad/triple_triad_persistence_controller.gd"
)
const CompositionRootScript = preload(
	"res://scripts/triple_triad/triple_triad_composition_root.gd"
)
const RegionProfileScript = preload(
	"res://scripts/triple_triad/triple_triad_region_profile.gd"
)
const QAProfileScript = preload(
	"res://scripts/triple_triad/triple_triad_qa_profile.gd"
)
const AIProfileScript = preload(
	"res://scripts/triple_triad/triple_triad_ai_profile.gd"
)
const DefaultAcquisitionPolicy = preload(
	"res://data/triple_triad/acquisition/default_acquisition_policy.tres"
)
const DefaultRuleSet = preload("res://data/triple_triad/basic_rules.tres")
const DefaultRegionProfile = preload(
	"res://data/triple_triad/regions/prototype_coast.tres"
)

const OWNER_NONE := 0
const OWNER_PLAYER := 1
const OWNER_OPPONENT := 2


class MockCard:
	extends RefCounted

	var card_id: StringName = &"qa_card"
	var display_name: String = "QA Card"
	var deck_cost: int = 1
	var top_rank: int = 1
	var right_rank: int = 1
	var bottom_rank: int = 1
	var left_rank: int = 1
	var required_player_rank: int = 1
	var influence_mode: StringName = &"none"
	var influence_strength: int = 0
	var influence_offsets: Array[Vector2i] = []

	func _init(
		id_value: StringName,
		top_value: int,
		right_value: int,
		bottom_value: int,
		left_value: int,
		cost_value: int = 1
	) -> void:
		card_id = id_value
		top_rank = top_value
		right_rank = right_value
		bottom_rank = bottom_value
		left_rank = left_value
		deck_cost = cost_value

	func rank_for_side(side: int) -> int:
		match side:
			0:
				return top_rank
			1:
				return right_rank
			2:
				return bottom_rank
			3:
				return left_rank
			_:
				return 0

	func rank_for_side_rotated(side: int, quarter_turns_clockwise: int) -> int:
		var source_side: int = posmod(
			side - posmod(quarter_turns_clockwise, 4),
			4
		)
		return rank_for_side(source_side)

	func has_influence() -> bool:
		return (
			String(influence_mode) == "pressure"
			and influence_strength > 0
			and not influence_offsets.is_empty()
		)

	func get_influence_offsets_rotated(quarter_turns_clockwise: int) -> Array[Vector2i]:
		var result: Array[Vector2i] = []
		var turns: int = posmod(quarter_turns_clockwise, 4)
		for authored_offset in influence_offsets:
			var offset: Vector2i = authored_offset
			for _turn in range(turns):
				offset = Vector2i(-offset.y, offset.x)
			result.append(offset)
		return result

	func rank_total() -> int:
		return top_rank + right_rank + bottom_rank + left_rank

	func is_usable_at_player_rank(player_rank: int) -> bool:
		return maxi(1, player_rank) >= required_player_rank


class MockRuleSet:
	extends Resource

	var open_rule: bool = true
	var same_rule: bool = false
	var plus_rule: bool = false
	var combo_rule: bool = false
	var influence_rule: bool = false


class MockRegion:
	extends Resource

	var allow_rotate: bool = true
	var boosted_cell: int = -1
	var bonus: int = 0

	func rank_bonus_for_cell(cell_index: int) -> int:
		return bonus if cell_index == boosted_cell else 0


class MockAIProfile:
	extends Resource

	var capture_weight: float = 1000.0
	var same_trigger_weight: float = 100.0
	var plus_trigger_weight: float = 100.0
	var influence_weight: float = 0.0
	var positional_weight: float = 0.0
	var card_strength_weight: float = 0.0
	var conserve_cost_weight: float = 0.0
	var rotate_spend_penalty: float = 0.0
	var randomness: float = 0.0


class MockQuantityStore:
	extends RefCounted

	var quantities: Dictionary = {}

	func _init(initial_quantities: Dictionary = {}) -> void:
		quantities = initial_quantities.duplicate(true)

	func get_quantity_by_id(card_id: StringName) -> int:
		return maxi(0, int(quantities.get(String(card_id), 0)))

	func unique_owned_count() -> int:
		var total: int = 0
		for raw_value in quantities.values():
			if int(raw_value) > 0:
				total += 1
		return total


class MockGatewayCardCatalog:
	extends RefCounted

	var cards: Dictionary = {}

	func _init(initial_cards: Array = []) -> void:
		for card in initial_cards:
			if card != null:
				cards[String(card.get("card_id"))] = card

	func get_card_by_id(card_id: StringName):
		return cards.get(String(card_id), null)


class MockGatewayAcquisitionService:
	extends RefCounted

	signal bundle_claimed(result: Dictionary)
	signal unlock_changed(unlocked: bool)

	var unlocked: bool = false
	var collection = null

	func _init(collection_backend = null) -> void:
		collection = collection_backend

	func is_card_game_unlocked() -> bool:
		return unlocked

	func get_snapshot() -> Dictionary:
		return {
			"card_game_unlocked": unlocked,
			"claimed_bundle_ids": (
				PackedStringArray(["salvaged_card_case"])
				if unlocked
				else PackedStringArray()
			),
			"available_bundle_ids": PackedStringArray(),
		}

	func claim_bundle(
		bundle_id: StringName,
		source_context: StringName = &""
	) -> Dictionary:
		var newly_unlocked: bool = not unlocked
		unlocked = true
		var result := {
			"success": true,
			"reason": "ok",
			"bundle_id": String(bundle_id),
			"display_name": "QA Bundle",
			"source_context": String(source_context),
			"granted_cards": 2,
			"unlocked_card_game": newly_unlocked,
		}
		bundle_claimed.emit(result.duplicate(true))
		if newly_unlocked:
			unlock_changed.emit(true)
		return result

	func grant_card(
		card_id: StringName,
		source_type: StringName,
		source_context: StringName = &"",
		amount: int = 1
	) -> Dictionary:
		var before: int = 0
		if collection != null:
			before = collection.get_quantity_by_id(card_id)
			collection.quantities[String(card_id)] = (
				before + maxi(1, amount)
			)
		var after: int = (
			collection.get_quantity_by_id(card_id)
			if collection != null
			else before
		)
		return {
			"success": after > before,
			"reason": "ok" if after > before else "not_granted",
			"card_id": String(card_id),
			"display_name": String(card_id),
			"source_type": String(source_type),
			"source_context": String(source_context),
			"quantity_before": before,
			"quantity_after": after,
			"granted": maxi(0, after - before),
		}


class MockGatewayWorldCatalog:
	extends RefCounted

	var source_cards: Array = []

	func _init(cards: Array = []) -> void:
		source_cards = cards.duplicate()

	func get_sources_for_card(card_id: StringName) -> Array:
		return [{
			"source_type": "quest_reward",
			"source_id": "qa_source",
			"card_id": String(card_id),
		}]

	func get_source_snapshot(
		source_type: StringName,
		source_id: StringName
	) -> Dictionary:
		if source_type == &"" or source_id == &"":
			return {}
		return {
			"source_type": String(source_type),
			"source_id": String(source_id),
			"display_name": "QA Source",
			"min_duel_rank": 1,
		}

	func get_all_source_snapshots() -> Array:
		return [get_source_snapshot(&"quest_reward", &"qa_source")]

	func validate_claim(
		source_type: StringName,
		source_id: StringName,
		card_id: StringName,
		player_rank: int
	) -> Dictionary:
		return {
			"valid": (
				not String(source_type).is_empty()
				and not String(source_id).is_empty()
				and not String(card_id).is_empty()
				and player_rank >= 1
			),
			"reason": "ok",
			"required_duel_rank": 1,
		}

	func can_direct_claim_source(source_type: StringName) -> bool:
		return source_type in [
			&"quest_reward",
			&"treasure_cache",
			&"tournament_reward",
			&"fishing_salvage",
		]

	func get_cards_for_source(
		source_type: StringName,
		source_id: StringName,
		player_rank: int
	) -> Array:
		if (
			String(source_type).is_empty()
			or String(source_id).is_empty()
			or player_rank < 1
		):
			return []
		return source_cards.duplicate()


class MockGatewayProgression:
	extends RefCounted

	var rank_number: int = 1

	func _init(value: int = 1) -> void:
		rank_number = maxi(1, value)

	func get_rank_number() -> int:
		return rank_number


class MockGatewayEncounterRecords:
	extends RefCounted

	var beaten_ids := PackedStringArray(["rookie"])
	var total_wins: int = 3

	func get_beaten_opponent_ids() -> PackedStringArray:
		return beaten_ids.duplicate()

	func get_total_player_wins() -> int:
		return total_wins


class MockGatewayOpponentProfile:
	extends RefCounted

	var opponent_id: StringName = &"qa_opponent"

	func _init(value: StringName = &"qa_opponent") -> void:
		opponent_id = value


class MockGatewayOpponentRegistry:
	extends RefCounted

	var last_rank: int = 0
	var last_context: Dictionary = {}

	func get_availability(
		opponent_id: StringName,
		player_rank: int,
		_region_id: StringName = &"",
		_required_tag: StringName = &"",
		context: Dictionary = {}
	) -> Dictionary:
		last_rank = player_rank
		last_context = context.duplicate(true)
		return {
			"available": (
				opponent_id == &"qa_opponent"
				and player_rank >= 4
				and bool(context.get("card_game_unlocked", false))
				and int(context.get("total_player_wins", 0)) == 3
			),
			"reason": "",
			"required_player_rank": 4,
		}

	func get_available_opponents(
		player_rank: int,
		_region_id: StringName = &"",
		_required_tag: StringName = &"",
		context: Dictionary = {}
	) -> Array:
		last_rank = player_rank
		last_context = context.duplicate(true)
		if (
			player_rank >= 4
			and bool(context.get("card_game_unlocked", false))
			and int(context.get("total_player_wins", 0)) == 3
		):
			return [MockGatewayOpponentProfile.new(&"qa_opponent")]
		return []


class MockMatchContextEncounterRecords:
	extends RefCounted

	var wins: int = 0

	func _init(wins_value: int = 0) -> void:
		wins = maxi(0, wins_value)

	func get_snapshot(_opponent_id: StringName) -> Dictionary:
		return {"wins": wins}


class MockRuntimeMatchContext:
	extends RefCounted

	var active_rule_set = null
	var opponent_id: StringName = &"qa_runtime_opponent"

	func active_opponent_id() -> StringName:
		return opponent_id


class MockLiveMatchContext:
	extends RefCounted

	var qa_hand_seed: int = 0
	var qa_forced_starting_owner: int = OWNER_PLAYER
	var active_deck_budget: int = 30
	var active_opponent_evolution: Dictionary = {}
	var active_rule_set = null
	var active_region_profile = null
	var budgeted_hand: Array = []

	func build_budgeted_hand() -> Array:
		return budgeted_hand.duplicate()


class MockLiveOpponentCollection:
	extends RefCounted

	var cards: Array = []

	func _init(initial_cards: Array = []) -> void:
		cards = initial_cards.duplicate()

	func build_match_deck(
		_count: int,
		_budget: int,
		_evolution: Dictionary
	) -> Array:
		return cards.duplicate()


class MockPersistenceMatchContext:
	extends RefCounted

	var qa_profile_override = null
	var active_opponent_profile = null
	var opponent_id: StringName = &"persistence_opponent"
	var opponent_name: String = "Persistence Opponent"

	func active_opponent_id() -> StringName:
		return opponent_id

	func active_opponent_display_name() -> String:
		return opponent_name


class MockPersistenceMatchResolution:
	extends RefCounted

	var last_winner: int = OWNER_NONE
	var last_reason: StringName = &""
	var transfer_result: Dictionary = {
		"success": true,
		"metadata_ok": true,
		"remove_from_decks": false,
	}

	func record_match_result(
		winner: int,
		result_reason: StringName,
		_surrendered: bool,
		_opponent_profile,
		_opponent_id: StringName,
		_qa_match: bool,
		_competition_match_active: bool,
		_starting_player_cards: Array,
		_starting_opponent_cards: Array,
		_opponent_collection_backend
	) -> Dictionary:
		last_winner = winner
		last_reason = result_reason
		return {
			"progression": {
				"rank_up": true,
				"rank_after": 4,
				"rank_name": "QA Rank",
			},
		}

	func commit_reward_transfer(
		_card_definition,
		_winner: int,
		_opponent_id: StringName,
		_opponent_collection_backend
	) -> Dictionary:
		return transfer_result.duplicate(true)


class MockPersistenceCompetition:
	extends RefCounted

	var resolution_applied: bool = false

	func is_match_active() -> bool:
		return true

	func apply_match_resolution(_resolution: Dictionary) -> Dictionary:
		resolution_applied = true
		return {"round_advanced": true}


class MockPersistenceDeckSetup:
	extends RefCounted

	var removed_ids := PackedStringArray()

	func remove_card_from_all_profiles(card_id: StringName) -> void:
		removed_ids.append(String(card_id))


class MockPersistenceLiveMatch:
	extends RefCounted

	var removed_ids := PackedStringArray()

	func remove_card_from_active_deck(card_id: StringName) -> Array:
		removed_ids.append(String(card_id))
		return []


class MockPersistenceSaveIntegrity:
	extends RefCounted

	var reasons: Array[String] = []

	func audit_and_checkpoint(
		_catalog,
		_collection,
		_progression,
		_budget: int,
		reason: String,
		_policy
	) -> Dictionary:
		reasons.append(reason)
		return {"valid": true, "reason": reason}


class MockPersistenceJournal:
	extends RefCounted

	var clear_count: int = 0

	func clear() -> void:
		clear_count += 1


class MockCompositionPersistence:
	extends RefCounted

	var reasons: Array[String] = []

	func checkpoint(reason: String) -> Dictionary:
		reasons.append(reason)
		return {"valid": true, "reason": reason}


var _results: Array[Dictionary] = []


func run_all() -> Dictionary:
	_results.clear()

	_run("basic capture", _test_basic_capture)
	_run("Same capture", _test_same_capture)
	_run("Plus capture", _test_plus_capture)
	_run("Same -> Combo chain", _test_same_combo_chain)
	_run("Rotate once per player", _test_rotate_once)
	_run("Region rank bonus", _test_region_bonus)
	_run("Match state invariant", _test_state_invariant)
	_run("AI prefers available capture", _test_ai_prefers_capture)
	_run("Card Duel Rank gate", _test_card_rank_gate)
	_run("Opponent registry duplicate guard", _test_registry_duplicate_id)
	_run("Board rows do not wrap", _test_row_boundary_no_wrap)
	_run("Preview is immutable", _test_preview_is_immutable)
	_run("Plus -> Combo chain", _test_plus_combo_chain)
	_run("Region can disable Rotate", _test_region_disables_rotate)
	_run("Opponent Duel Rank availability", _test_registry_rank_availability)
	_run("Influence can manufacture Same", _test_influence_enables_same)
	_run("Influence pattern rotates with card", _test_influence_pattern_rotation)
	_run("Influence snapshot stays stable during Combo", _test_influence_snapshot_stable)
	_run("Captured Influence changes allegiance next action", _test_influence_changes_allegiance)
	_run("Stake policy takes strongest card", _test_stake_policy_strongest)
	_run("Stake policy protects last playable deck", _test_stake_policy_minimum_deck)
	_run("Influence snapshot attributes its source", _test_influence_source_attribution)
	_run("Preview exposes Influence deltas", _test_preview_influence_deltas)
	_run("Unsupported rules are rejected", _test_unsupported_rule_guard)
	_run("Authored opponent ladder is legal", _test_authored_opponent_ladder)
	_run("Acquisition registry is legal", _test_acquisition_registry)
	_run("Card-game discovery gates opponents", _test_card_game_discovery_gate)
	_run("World acquisition map covers all cards", _test_world_acquisition_map)
	_run("World delivery source contract is legal", _test_world_delivery_contract)
	_run("Competition catalog is legal", _test_competition_catalog)
	_run("Competitive progression reaches Card Master", _test_competitive_progression_flow)
	_run("Collection tracker covers all 179 cards", _test_collection_completion_tracker)
	_run("World progression prioritizes discovery and active tournaments", _test_world_progression_priority)
	_run("World progression enters collection cleanup after Card Master", _test_world_progression_collection_cleanup)
	_run("Opponent rematch evolution advances at authored wins", _test_opponent_rematch_evolution)
	_run("Opponent adapted AI preserves signature personality", _test_opponent_adapted_ai)
	_run("Tournament deck remains locked across rounds", _test_competition_locked_deck)
	_run("Gameplay event feed preserves bounded FIFO order", _test_gameplay_event_feed)
	_run("Competition completion reward remains pending until acknowledged", _test_competition_pending_reward)
	_run("Match-resolution journal survives interrupted reward choice", _test_match_resolution_journal)
	_run("World reward delivery journal prevents duplicate one-shot rewards", _test_world_reward_delivery_journal)
	_run("Session lifecycle transitions are explicit", _test_session_lifecycle_controller)
	_run("Session surrender resumes the interrupted turn", _test_session_surrender_resume)
	_run("Session result and recovery state remain deterministic", _test_session_result_recovery)
	_run("Match flow owns setup and deal handoff", _test_match_flow_setup_and_deal)
	_run("Match flow owns player-to-AI turn handoff", _test_match_flow_turn_handoff)
	_run("Match flow owns surrender and result destinations", _test_match_flow_surrender_and_result)
	_run("Match resolution filters reward candidates", _test_match_resolution_reward_candidates)
	_run("Match resolution reuses persisted reward choice", _test_match_resolution_reward_presentation)
	_run("Match resolution builds deterministic transfer state", _test_match_resolution_transfer_state)
	_run("Presentation marks player cards as blue-owned", _test_presentation_player_outline)
	_run("Presentation marks opponent cards as red-owned", _test_presentation_opponent_outline)
	_run("Presentation leaves empty slots without ownership", _test_presentation_empty_outline)
	_run("Input controller maps gameplay keys", _test_input_controller_key_mapping)
	_run("Input controller isolates Shift+F10 campaign QA", _test_input_controller_campaign_qa)
	_run("Input controller clamps board navigation", _test_input_controller_board_navigation)
	_run("Input controller routes stable gameplay phases", _test_input_controller_phase_routing)
	_run("Input controller protects transactional phases", _test_input_controller_transaction_guard)
	_run("Input controller owns surrender confirmation routing", _test_input_controller_surrender_routing)
	_run("UI flow owns result copy", _test_ui_flow_result_copy)
	_run("UI flow maps phases to HUD turn state", _test_ui_flow_turn_text)
	_run("UI flow limits player selection markers to player phases", _test_ui_flow_selection_phase)
	_run("World gateway rejects writes before backend readiness", _test_world_gateway_backend_guard)
	_run("World gateway preserves one-shot reward delivery", _test_world_gateway_one_shot_reward)
	_run("World gateway owns opponent discovery context", _test_world_gateway_opponent_context)
	_run("Competition controller owns tournament deck locking", _test_competition_controller_deck_lock)
	_run("Competition controller owns post-match round state", _test_competition_controller_resolution_state)
	_run("Runtime recovery abandons stale tournament decks", _test_runtime_recovery_stale_tournament)
	_run("Backend validator accepts authored defaults", _test_backend_validator_defaults)
	_run("Backend validator rejects missing catalog", _test_backend_validator_missing_catalog)
	_run("Backend validator enforces starter deck budget", _test_backend_validator_starter_budget)
	_run("Match context resolves authored precedence", _test_match_context_authored_precedence)
	_run("Match context isolates QA overrides", _test_match_context_qa_override)
	_run("Match context applies rematch evolution", _test_match_context_rematch_evolution)
	_run("Runtime state feed owns public gameplay events", _test_runtime_state_event_feed)
	_run("Runtime state card snapshots preserve rotation", _test_runtime_state_card_snapshot)
	_run("Runtime state UI snapshot respects hidden hands", _test_runtime_state_hidden_hand)
	_run("Live match runtime owns prepared hands", _test_live_match_runtime_setup)
	_run("Live match runtime owns selection cursors", _test_live_match_runtime_selection)
	_run("Live match runtime owns active deck mutations", _test_live_match_runtime_deck_state)
	_run("Match orchestrator preserves placement payload", _test_match_orchestrator_move_plan)
	_run("Match orchestrator marks capture settle", _test_match_orchestrator_capture_settle)
	_run("Match orchestrator normalizes reward candidates", _test_match_orchestrator_reward_ids)
	_run("Persistence controller owns match-result bookkeeping", _test_persistence_match_outcome)
	_run("Persistence controller owns reward deck cleanup", _test_persistence_reward_transfer)
	_run("Persistence controller owns save checkpoints", _test_persistence_checkpoint)
	_run("Composition root accepts the complete scene contract", _test_composition_contract_complete)
	_run("Composition root rejects incomplete scene wiring", _test_composition_contract_guard)
	_run("Composition root filters bootstrap and service boundaries", _test_composition_boundary_maps)
	_run("Composition activation defers boot side effects", _test_composition_activation_phase)

	var passed: int = 0
	var failed: int = 0
	var failures: Array[String] = []
	for result in _results:
		if bool(result.get("passed", false)):
			passed += 1
		else:
			failed += 1
			failures.append(str(result.get("name", "unknown")))

	return {
		"passed": failed == 0,
		"test_count": _results.size(),
		"passed_count": passed,
		"failed_count": failed,
		"failures": failures,
		"results": _results.duplicate(true),
	}


func _run(test_name: String, test_callable: Callable) -> void:
	var error_text: String = ""
	var passed: bool = false

	var raw_result = test_callable.call()
	if raw_result is Dictionary:
		passed = bool(raw_result.get("passed", false))
		error_text = str(raw_result.get("error", ""))
	else:
		passed = bool(raw_result)

	_results.append({
		"name": test_name,
		"passed": passed,
		"error": error_text,
	})


func _ok(condition: bool, error_text: String = "") -> Dictionary:
	return {
		"passed": condition,
		"error": "" if condition else error_text,
	}


func _new_match(
	rules: Resource = null,
	region: Resource = null
):
	var state = MatchScript.new()
	state.reset_match(
		_filler_hand(&"p"),
		_filler_hand(&"o"),
		OWNER_PLAYER,
		rules,
		region
	)
	return state


func _filler_hand(prefix: StringName) -> Array:
	var result: Array = []
	for index in range(5):
		result.append(
			MockCard.new(
				StringName("%s_%d" % [String(prefix), index]),
				1,
				1,
				1,
				1
			)
		)
	return result


func _test_acquisition_registry() -> Dictionary:
	var audit: Dictionary = DefaultAcquisitionRegistry.validate_registry(DefaultCardCatalog)
	if not bool(audit.get("valid", false)):
		return _ok(
			false,
			"Acquisition registry failed validation: %s"
			% str(audit.get("errors", []))
		)
	var starter = DefaultAcquisitionRegistry.get_bundle(&"salvaged_card_case")
	return _ok(
		starter != null
		and bool(starter.unlocks_card_game)
		and starter.card_ids.size() == 10,
		"Expected a ten-card one-shot salvage bundle that unlocks Triple Triad."
	)


func _test_card_game_discovery_gate() -> Dictionary:
	var locked_context := {
		"card_game_unlocked": false,
		"beaten_opponent_ids": PackedStringArray(),
		"total_player_wins": 0,
	}
	var unlocked_context := {
		"card_game_unlocked": true,
		"beaten_opponent_ids": PackedStringArray(),
		"total_player_wins": 0,
	}

	var locked: Dictionary = DefaultOpponentRegistry.get_availability(
		&"beach_trader",
		1,
		&"",
		&"",
		locked_context
	)
	var unlocked: Dictionary = DefaultOpponentRegistry.get_availability(
		&"beach_trader",
		1,
		&"",
		&"",
		unlocked_context
	)

	return _ok(
		not bool(locked.get("available", true))
		and bool(unlocked.get("available", false)),
		"Beach Trader must stay locked before discovery and unlock after the starter case."
	)


func _test_world_acquisition_map() -> Dictionary:
	var world_catalog = WorldAcquisitionCatalogScript.new()
	world_catalog.initialize(
		DefaultCardCatalog,
		DefaultOpponentRegistry,
		DefaultAcquisitionRegistry
	)
	var audit: Dictionary = world_catalog.validate_map()
	return _ok(
		bool(audit.get("valid", false))
		and int(audit.get("card_count", 0)) == 179
		and int(audit.get("covered_card_count", 0)) == 179,
		"All 179 cards must have a valid acquisition source: %s"
		% str(audit.get("errors", []))
	)


func _test_world_delivery_contract() -> Dictionary:
	var world_catalog = WorldAcquisitionCatalogScript.new()
	world_catalog.initialize(
		DefaultCardCatalog,
		DefaultOpponentRegistry,
		DefaultAcquisitionRegistry
	)

	var direct_types := PackedStringArray([
		"fishing_salvage",
		"treasure_cache",
		"quest_reward",
		"tournament_reward",
	])
	for type_name in direct_types:
		if not bool(
			world_catalog.can_direct_claim_source(
				StringName(type_name)
			)
		):
			return _ok(
				false,
				"World delivery source type %s is not direct-claimable."
				% type_name
			)

	var required_sources := [
		[&"fishing_salvage", &"coast_shallows"],
		[&"treasure_cache", &"harbor_lockbox"],
		[&"quest_reward", &"town_requests"],
		[&"tournament_reward", &"regional_circuit"],
	]
	for pair in required_sources:
		var source_type: StringName = pair[0]
		var source_id: StringName = pair[1]
		var snapshot: Dictionary = world_catalog.get_source_snapshot(
			source_type,
			source_id
		)
		if snapshot.is_empty():
			return _ok(
				false,
				"Missing runtime world reward source %s:%s."
				% [String(source_type), String(source_id)]
			)

	return _ok(
		true,
		"Runtime world reward source contract is valid."
	)


func _slot(card, owner: int, rotation: int = 0) -> Dictionary:
	return {
		"card": card,
		"owner": owner,
		"rotation": rotation,
	}


func _test_competition_catalog() -> Dictionary:
	var world_catalog = WorldAcquisitionCatalogScript.new()
	world_catalog.initialize(
		DefaultCardCatalog,
		DefaultOpponentRegistry,
		DefaultAcquisitionRegistry
	)
	var competition_catalog = CompetitionCatalogScript.new()
	var audit: Dictionary = competition_catalog.initialize(
		DefaultOpponentRegistry,
		world_catalog
	)
	return _ok(
		bool(audit.get("valid", false))
		and int(audit.get("circuit_count", 0)) == 3
		and int(audit.get("competition_count", 0)) == 2,
		"Competition catalog must contain three valid circuits and two tournaments."
	)


func _test_competitive_progression_flow() -> Dictionary:
	var world_catalog = WorldAcquisitionCatalogScript.new()
	world_catalog.initialize(
		DefaultCardCatalog,
		DefaultOpponentRegistry,
		DefaultAcquisitionRegistry
	)
	var competition_catalog = CompetitionCatalogScript.new()
	var catalog_audit: Dictionary = competition_catalog.initialize(
		DefaultOpponentRegistry,
		world_catalog
	)
	if not bool(catalog_audit.get("valid", false)):
		return _ok(false, "Competition catalog failed before progression flow test.")

	var service = CompetitionServiceScript.new()
	service.initialize(competition_catalog, false)
	var beaten := PackedStringArray([
		"pier_apprentice",
		"beach_trader",
		"dock_bruiser",
		"gearwright",
		"marsh_keeper",
		"highland_keeper",
		"lantern_gambler",
		"tide_oracle",
	])

	var regional: Dictionary = service.get_competition_snapshot(
		&"regional_championship",
		3,
		beaten
	)
	if not bool(regional.get("available", false)):
		return _ok(false, "Regional Championship should unlock after all circuits.")

	var regional_start: Dictionary = service.start_competition(
		&"regional_championship",
		3,
		beaten
	)
	if (
		not bool(regional_start.get("success", false))
		or String(regional_start.get("next_opponent_id", "")) != "gearwright"
	):
		return _ok(false, "Regional Championship did not start on Gearwright.")

	var regional_rounds = [
		&"gearwright",
		&"marsh_keeper",
		&"tide_oracle",
	]
	for index in range(regional_rounds.size()):
		var result: Dictionary = service.record_match_result(
			regional_rounds[index],
			OWNER_PLAYER,
			OWNER_PLAYER
		)
		if index < regional_rounds.size() - 1:
			if not bool(result.get("round_won", false)):
				return _ok(false, "Regional Championship failed to advance.")
		else:
			if not bool(result.get("completed", false)):
				return _ok(false, "Regional Championship did not complete.")

	var regional_pending: Dictionary = service.get_pending_reward()
	if regional_pending.is_empty():
		return _ok(false, "Regional Championship reward was not persisted as pending.")
	if not service.acknowledge_pending_reward(
		StringName(str(regional_pending.get("reward_event_id", "")))
	):
		return _ok(false, "Regional pending reward could not be acknowledged.")

	var masters: Dictionary = service.get_competition_snapshot(
		&"masters_cup",
		5,
		beaten
	)
	if not bool(masters.get("available", false)):
		return _ok(false, "Masters' Cup should unlock after a Regional clear at Rank 5.")

	var masters_start: Dictionary = service.start_competition(
		&"masters_cup",
		5,
		beaten
	)
	if not bool(masters_start.get("success", false)):
		return _ok(false, "Masters' Cup did not start.")

	var final_result: Dictionary = {}
	for opponent_id in [
		&"lantern_gambler",
		&"wandering_sage",
		&"storm_captain",
		&"ash_champion",
	]:
		final_result = service.record_match_result(
			opponent_id,
			OWNER_PLAYER,
			OWNER_PLAYER
		)

	var snapshot: Dictionary = service.get_snapshot(5, beaten)
	return _ok(
		bool(final_result.get("completed", false))
		and bool(final_result.get("card_game_completed", false))
		and String(final_result.get("title_awarded", "")) == "Card Master"
		and bool(snapshot.get("card_master", false))
		and bool(snapshot.get("card_game_completed", false)),
		"First Masters' Cup clear must award Card Master and complete the card-game campaign."
	)


func _test_collection_completion_tracker() -> Dictionary:
	var world_catalog = WorldAcquisitionCatalogScript.new()
	world_catalog.initialize(
		DefaultCardCatalog,
		DefaultOpponentRegistry,
		DefaultAcquisitionRegistry
	)
	var competition_catalog = CompetitionCatalogScript.new()
	var competition_audit: Dictionary = competition_catalog.initialize(
		DefaultOpponentRegistry,
		world_catalog
	)
	if not bool(competition_audit.get("valid", false)):
		return _ok(false, "Competition catalog failed before collection tracking QA.")

	var competition_service = CompetitionServiceScript.new()
	competition_service.initialize(competition_catalog, false)

	var tracker = CompletionTrackerScript.new()
	tracker.initialize(
		DefaultCardCatalog,
		null,
		world_catalog,
		null,
		null,
		competition_service,
		DefaultOpponentRegistry,
		false
	)
	var snapshot: Dictionary = tracker.get_snapshot()
	var missing_cards: Array = snapshot.get("missing_cards", [])
	if int(snapshot.get("catalog_total_unique", 0)) != 179:
		return _ok(false, "Collection tracker must cover exactly 179 authored cards.")
	if int(snapshot.get("missing_unique", 0)) != 179:
		return _ok(false, "Empty QA collection must report all 179 cards missing.")
	if missing_cards.size() != 179:
		return _ok(false, "Missing-card diagnostics must contain all 179 cards.")
	for diagnostic in missing_cards:
		if not (diagnostic is Dictionary):
			return _ok(false, "Missing-card diagnostic is malformed.")
		if (diagnostic as Dictionary).get("sources", []).is_empty():
			return _ok(false, "Every missing card must expose at least one acquisition source.")
	var expected_source_count: int = (
		world_catalog.get_all_source_snapshots().size()
		if world_catalog != null
		else 0
	)
	return _ok(
		expected_source_count > 0
		and int(snapshot.get("sources_total", 0)) == expected_source_count,
		"Collection tracker must expose all %d authored acquisition sources."
		% expected_source_count
	)


func _test_world_progression_priority() -> Dictionary:
	var director = WorldProgressionDirectorScript.new()
	var completion := {
		"collection_complete": false,
		"campaign_complete": false,
		"full_card_game_completion": false,
		"owned_unique": 60,
		"catalog_total_unique": 179,
		"missing_unique": 119,
		"source_progress": [],
	}
	var competitive := {
		"active": {
			"active": true,
			"competition_id": "regional_championship",
			"display_name": "Regional Card Championship",
			"next_opponent_id": "gearwright",
		},
		"circuits": [],
		"competitions": [],
	}

	var locked: Dictionary = director.build_snapshot(
		{"duel_rank": 4},
		{"card_game_unlocked": false},
		competitive,
		completion,
		PackedStringArray()
	)
	if str(locked.get("phase", "")) != "discover_cards":
		return _ok(
			false,
			"Card discovery must remain the first world objective while locked."
		)

	var active: Dictionary = director.build_snapshot(
		{"duel_rank": 4},
		{"card_game_unlocked": true},
		competitive,
		completion,
		PackedStringArray(["gearwright"])
	)
	var next_ids = active.get("next_opponent_ids", PackedStringArray())
	return _ok(
		str(active.get("phase", "")) == "active_competition"
		and str(active.get("next_competition_id", "")) == "regional_championship"
		and next_ids.has("gearwright"),
		"An active tournament must override normal regional progression."
	)


func _test_world_progression_collection_cleanup() -> Dictionary:
	var director = WorldProgressionDirectorScript.new()
	var snapshot: Dictionary = director.build_snapshot(
		{"duel_rank": 6},
		{"card_game_unlocked": true},
		{
			"active": {"active": false},
			"circuits": [],
			"competitions": [],
		},
		{
			"collection_complete": false,
			"campaign_complete": true,
			"full_card_game_completion": false,
			"owned_unique": 170,
			"catalog_total_unique": 179,
			"missing_unique": 9,
			"source_progress": [
				{
					"source_type": "fishing_salvage",
					"source_id": "deep_water",
					"display_name": "Deep Water Salvage",
					"missing_count": 3,
					"complete": false,
					"rank_available": true,
				},
			],
		},
		PackedStringArray()
	)
	var suggestions: Array = snapshot.get("available_collection_sources", [])
	return _ok(
		str(snapshot.get("phase", "")) == "collection_cleanup"
		and int(snapshot.get("collection_missing_unique", 0)) == 9
		and suggestions.size() == 1
		and str(suggestions[0].get("source_id", "")) == "deep_water",
		"After Card Master, missing cards must become the next world objective."
	)


func _test_opponent_rematch_evolution() -> Dictionary:
	var profile = DefaultOpponentRegistry.get_opponent(&"beach_trader")
	if profile == null:
		return _ok(false, "Beach Trader profile is missing.")
	var evolution = OpponentEvolutionScript.new()
	var expected_stages := [0, 1, 2, 3]
	var wins := [0, 1, 3, 6]
	var previous_budget_bonus: int = -1
	for index in range(wins.size()):
		var snapshot: Dictionary = evolution.build_snapshot(
			profile,
			{"wins": wins[index]}
		)
		if int(snapshot.get("stage", -1)) != expected_stages[index]:
			return _ok(
				false,
				"Beach Trader rematch stage did not match the authored win threshold."
			)
		var bonus: int = int(snapshot.get("budget_bonus", 0))
		if bonus < previous_budget_bonus:
			return _ok(
				false,
				"Rematch budget bonus must not decrease at a later stage."
			)
		previous_budget_bonus = bonus
	var veteran: Dictionary = evolution.build_snapshot(
		profile,
		{"wins": 6}
	)
	return _ok(
		(veteran.get("forced_card_ids", PackedStringArray()) as PackedStringArray).size() >= 3
		and not (
			veteran.get("signature_card_ids", PackedStringArray())
			as PackedStringArray
		).is_empty(),
		"Veteran rematch should promote reserve cards and expose a signature card."
	)


func _test_opponent_adapted_ai() -> Dictionary:
	var profile = DefaultOpponentRegistry.get_opponent(&"dock_bruiser")
	if profile == null:
		return _ok(false, "Dock Bruiser profile is missing.")
	var base_ai: Resource = profile.get("ai_profile")
	if base_ai == null:
		return _ok(false, "Dock Bruiser AI profile is missing.")

	var evolution = OpponentEvolutionScript.new()
	var snapshot: Dictionary = evolution.build_snapshot(
		profile,
		{"wins": 3}
	)
	var adapted: Resource = evolution.build_adapted_ai(
		base_ai,
		snapshot
	)
	if adapted == null or adapted == base_ai:
		return _ok(
			false,
			"An evolved opponent must use a duplicated runtime AI profile."
		)
	return _ok(
		float(adapted.get("capture_weight")) > float(base_ai.get("capture_weight"))
		and float(adapted.get("randomness")) < float(base_ai.get("randomness"))
		and not (
			adapted.get("signature_card_ids")
			as PackedStringArray
		).is_empty()
		and float(adapted.get("signature_early_play_penalty")) > 0.0,
		"Aggressive rematch AI must learn while preserving deliberate signature-card timing."
	)


func _test_competition_locked_deck() -> Dictionary:
	var world_catalog = WorldAcquisitionCatalogScript.new()
	world_catalog.initialize(
		DefaultCardCatalog,
		DefaultOpponentRegistry,
		DefaultAcquisitionRegistry
	)
	var competition_catalog = CompetitionCatalogScript.new()
	var audit: Dictionary = competition_catalog.initialize(
		DefaultOpponentRegistry,
		world_catalog
	)
	if not bool(audit.get("valid", false)):
		return _ok(false, "Competition catalog invalid in deck-lock test.")

	var service = CompetitionServiceScript.new()
	service.initialize(competition_catalog, false)
	var beaten := PackedStringArray([
		"pier_apprentice",
		"beach_trader",
		"dock_bruiser",
		"gearwright",
		"marsh_keeper",
		"highland_keeper",
		"lantern_gambler",
		"tide_oracle",
	])
	var started: Dictionary = service.start_competition(
		&"regional_championship",
		3,
		beaten
	)
	if not bool(started.get("success", false)):
		return _ok(false, "Regional Championship did not start.")

	var locked := PackedStringArray([
		"mugshot_153",
		"mugshot_156",
		"mugshot_157",
		"mugshot_161",
		"mugshot_162",
	])
	if not service.set_locked_deck_ids(locked):
		return _ok(false, "Tournament deck could not be locked.")

	var round_result: Dictionary = service.record_match_result(
		&"gearwright",
		OWNER_PLAYER,
		OWNER_PLAYER
	)
	if not bool(round_result.get("round_won", false)):
		return _ok(false, "Tournament did not advance after round win.")
	if service.get_locked_deck_ids() != locked:
		return _ok(false, "Locked deck changed while tournament advanced.")

	service.record_match_result(
		&"marsh_keeper",
		OWNER_OPPONENT,
		OWNER_PLAYER
	)
	return _ok(
		not service.has_locked_deck()
		and not bool(service.get_active_snapshot().get("active", false)),
		"A tournament loss must clear the active attempt and its locked deck."
	)


func _test_gameplay_event_feed() -> Dictionary:
	var feed = GameplayEventFeedScript.new()
	feed.initialize(3)
	for index in range(5):
		feed.push_event(
			StringName("event_%d" % index),
			"Event %d" % index
		)

	var pending: Array = feed.get_pending_events()
	if pending.size() != 3:
		return _ok(false, "Event feed did not enforce its capacity.")
	if (
		int(pending[0].get("sequence", -1)) != 3
		or int(pending[2].get("sequence", -1)) != 5
	):
		return _ok(false, "Event feed did not retain FIFO order.")

	var popped: Dictionary = feed.pop_next_event()
	return _ok(
		str(popped.get("type", "")) == "event_2"
		and feed.size() == 2,
		"Event feed pop must return the oldest retained event."
	)


func _test_competition_pending_reward() -> Dictionary:
	var world_catalog = WorldAcquisitionCatalogScript.new()
	world_catalog.initialize(
		DefaultCardCatalog,
		DefaultOpponentRegistry,
		DefaultAcquisitionRegistry
	)
	var competition_catalog = CompetitionCatalogScript.new()
	var audit: Dictionary = competition_catalog.initialize(
		DefaultOpponentRegistry,
		world_catalog
	)
	if not bool(audit.get("valid", false)):
		return _ok(false, "Competition catalog invalid in pending reward test.")

	var service = CompetitionServiceScript.new()
	service.initialize(competition_catalog, false)
	var beaten := PackedStringArray([
		"pier_apprentice",
		"beach_trader",
		"dock_bruiser",
		"gearwright",
		"marsh_keeper",
		"highland_keeper",
		"lantern_gambler",
		"tide_oracle",
	])
	var started: Dictionary = service.start_competition(
		&"regional_championship",
		3,
		beaten
	)
	if not bool(started.get("success", false)):
		return _ok(false, "Regional Championship did not start.")

	for opponent_id in [
		&"gearwright",
		&"marsh_keeper",
		&"tide_oracle",
	]:
		service.record_match_result(
			opponent_id,
			OWNER_PLAYER,
			OWNER_PLAYER
		)

	var pending: Dictionary = service.get_pending_reward()
	if pending.is_empty():
		return _ok(
			false,
			"Completed tournament must keep its card reward pending until delivery is acknowledged."
		)

	var blocked: Dictionary = service.start_competition(
		&"regional_championship",
		3,
		beaten
	)
	if str(blocked.get("reason", "")) != "pending_competition_reward":
		return _ok(
			false,
			"A new tournament must not start while a completion reward is unresolved."
		)

	var event_id := StringName(str(pending.get("reward_event_id", "")))
	return _ok(
		service.acknowledge_pending_reward(event_id)
		and service.get_pending_reward().is_empty(),
		"Acknowledging the tournament reward must release the competition service."
	)


func _test_match_resolution_journal() -> Dictionary:
	var qa_path := "user://triple_triad_match_resolution_qa.cfg"
	var journal = MatchResolutionJournalScript.new()
	journal.initialize(qa_path)
	journal.clear()

	var started: bool = journal.begin_resolution({
		"opponent_id": "beach_trader",
		"winner": OWNER_PLAYER,
		"result_reason": "qa",
		"surrendered": false,
		"player_card_ids": PackedStringArray([
			"mugshot_153",
			"mugshot_156",
			"mugshot_157",
			"mugshot_161",
			"mugshot_162",
		]),
		"opponent_card_ids": PackedStringArray([
			"mugshot_047",
			"mugshot_053",
			"mugshot_071",
			"mugshot_054",
			"mugshot_181",
		]),
		"eligible_reward_ids": PackedStringArray([
			"mugshot_047",
			"mugshot_053",
		]),
		"forced_loss_card_id": "",
		"competition_change": {},
	})
	if not started or not journal.has_pending():
		journal.clear()
		return _ok(false, "Match-resolution journal could not start.")

	var transfer_state := {
		"card_id": "mugshot_047",
		"winner": OWNER_PLAYER,
		"opponent_id": "beach_trader",
		"desired_player": 1,
		"desired_opponent": 0,
	}
	if not journal.record_selection(
		&"mugshot_047",
		transfer_state
	):
		journal.clear()
		return _ok(false, "Match-resolution journal could not persist the chosen card.")

	var snapshot: Dictionary = journal.get_snapshot()
	var valid: bool = (
		str(snapshot.get("selected_card_id", "")) == "mugshot_047"
		and not bool(snapshot.get("transfer_committed", true))
		and (
			snapshot.get("transfer_state", {})
			as Dictionary
		).get("desired_player", -1) == 1
	)
	valid = (
		valid
		and journal.mark_transfer_committed()
		and journal.mark_metadata_committed()
	)
	var committed: Dictionary = journal.get_snapshot()
	valid = (
		valid
		and bool(committed.get("transfer_committed", false))
		and bool(committed.get("metadata_committed", false))
	)
	journal.clear()
	return _ok(
		valid and not journal.has_pending(),
		"Match-resolution journal must round-trip selection and commit state without leaving stale data."
	)


func _test_world_reward_delivery_journal() -> Dictionary:
	var qa_path := "user://triple_triad_world_delivery_qa.cfg"
	var ledger = WorldRewardLedgerScript.new()
	ledger.initialize(qa_path)

	var event_id := StringName("qa_one_shot_reward")
	ledger.reset_event(event_id)
	var chosen_id := StringName("mugshot_153")
	if not ledger.begin_delivery(
		event_id,
		&"treasure_cache",
		&"harbor_lockbox",
		chosen_id,
		&"qa",
		0
	):
		return _ok(
			false,
			"World reward ledger could not begin a one-shot delivery."
		)

	var pending: Dictionary = ledger.get_pending_delivery(event_id)
	if str(pending.get("card_id", "")) != String(chosen_id):
		ledger.clear_pending_delivery(event_id)
		return _ok(
			false,
			"World reward ledger did not preserve the chosen card."
		)

	var reloaded = WorldRewardLedgerScript.new()
	reloaded.initialize(qa_path)
	var recovered: Dictionary = reloaded.get_pending_delivery(event_id)
	var valid: bool = (
		str(recovered.get("card_id", "")) == String(chosen_id)
		and not reloaded.has_claimed(event_id)
		and reloaded.complete_delivery(event_id)
		and reloaded.has_claimed(event_id)
		and reloaded.get_pending_delivery(event_id).is_empty()
	)
	# Reinitialize the QA file to a harmless empty state.
	var cleanup = WorldRewardLedgerScript.new()
	cleanup.initialize(qa_path)
	cleanup.reset_event(event_id)
	return _ok(
		valid,
		"One-shot reward delivery must survive reload with the same chosen card and complete exactly once."
	)


func _test_basic_capture() -> Dictionary:
	var state = _new_match()
	state.board[3] = _slot(
		MockCard.new(&"enemy_left", 1, 2, 1, 1),
		OWNER_OPPONENT
	)
	var placed = MockCard.new(&"placed", 1, 1, 1, 5)
	var preview: Dictionary = state.preview_move(
		placed,
		OWNER_PLAYER,
		4
	)
	return _ok(
		int(preview.get("capture_count", 0)) == 1
		and (preview.get("basic_captured", []) as Array).has(3),
		"Expected a normal left-side capture."
	)


func _test_same_capture() -> Dictionary:
	var rules := MockRuleSet.new()
	rules.same_rule = true

	var state = _new_match(rules)
	state.board[1] = _slot(
		MockCard.new(&"same_top", 1, 1, 5, 1),
		OWNER_OPPONENT
	)
	state.board[3] = _slot(
		MockCard.new(&"same_left", 1, 4, 1, 1),
		OWNER_OPPONENT
	)
	var placed = MockCard.new(&"same_placed", 5, 1, 1, 4)
	var preview: Dictionary = state.preview_move(
		placed,
		OWNER_PLAYER,
		4
	)
	var same_captured: Array = preview.get("same_captured", [])
	return _ok(
		bool(preview.get("same_triggered", false))
		and same_captured.has(1)
		and same_captured.has(3),
		"Expected Same to trigger on cells 1 and 3."
	)


func _test_plus_capture() -> Dictionary:
	var rules := MockRuleSet.new()
	rules.plus_rule = true

	var state = _new_match(rules)
	# Center top 3 + neighbor bottom 2 = 5.
	state.board[1] = _slot(
		MockCard.new(&"plus_top", 1, 1, 2, 1),
		OWNER_OPPONENT
	)
	# Center left 4 + neighbor right 1 = 5.
	state.board[3] = _slot(
		MockCard.new(&"plus_left", 1, 1, 1, 1),
		OWNER_OPPONENT
	)
	var placed = MockCard.new(&"plus_placed", 3, 1, 1, 4)
	var preview: Dictionary = state.preview_move(
		placed,
		OWNER_PLAYER,
		4
	)
	var plus_captured: Array = preview.get("plus_captured", [])
	return _ok(
		bool(preview.get("plus_triggered", false))
		and plus_captured.has(1)
		and plus_captured.has(3),
		"Expected Plus to trigger on equal sums."
	)


func _test_same_combo_chain() -> Dictionary:
	var rules := MockRuleSet.new()
	rules.same_rule = true
	rules.combo_rule = true

	var state = _new_match(rules)

	# Same seed above center. Its left value then beats cell 0's right value,
	# which must be captured by Combo.
	state.board[1] = _slot(
		MockCard.new(&"combo_seed", 1, 1, 5, 6),
		OWNER_OPPONENT
	)
	state.board[3] = _slot(
		MockCard.new(&"same_second", 1, 4, 1, 1),
		OWNER_OPPONENT
	)
	state.board[0] = _slot(
		MockCard.new(&"combo_target", 1, 2, 1, 1),
		OWNER_OPPONENT
	)

	var placed = MockCard.new(&"combo_placed", 5, 1, 1, 4)
	var preview: Dictionary = state.preview_move(
		placed,
		OWNER_PLAYER,
		4
	)
	var combo: Array = preview.get("combo_captured", [])
	return _ok(
		bool(preview.get("same_triggered", false))
		and combo.has(0),
		"Expected a Same capture to seed Combo into cell 0."
	)


func _test_rotate_once() -> Dictionary:
	var state = _new_match()
	var first_ok: bool = state.rotate_hand_card(OWNER_PLAYER, 0)
	var second_ok: bool = state.rotate_hand_card(OWNER_PLAYER, 0)
	return _ok(
		first_ok
		and not second_ok
		and state.player_rotate_used,
		"Rotate should be spendable once per player per match."
	)


func _test_region_bonus() -> Dictionary:
	var region := MockRegion.new()
	region.boosted_cell = 4
	region.bonus = 1

	var state = _new_match(null, region)
	var card = MockCard.new(&"region_card", 4, 4, 4, 4)
	return _ok(
		state.effective_rank_for_card(card, 0, 0, 4) == 5
		and state.effective_rank_for_card(card, 0, 0, 0) == 4,
		"Expected +1 only on the configured region cell."
	)


func _test_state_invariant() -> Dictionary:
	var state = _new_match()
	if not state.validate_state():
		return _ok(false, "Fresh match state is invalid.")

	var move: Dictionary = state.place_card(
		OWNER_PLAYER,
		0,
		4
	)
	return _ok(
		bool(move.get("success", false))
		and state.validate_state(),
		"State invariant failed after a legal placement."
	)


func _test_ai_prefers_capture() -> Dictionary:
	var state = _new_match()
	state.board[4] = _slot(
		MockCard.new(&"ai_target", 1, 1, 1, 1),
		OWNER_PLAYER
	)

	state.opponent_hand.clear()
	state.opponent_hand_rotations.clear()
	state.opponent_hand.append(
		MockCard.new(&"ai_capture", 9, 9, 9, 9)
	)
	state.opponent_hand_rotations.append(0)

	var ai = AIScript.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	var profile := MockAIProfile.new()
	var choice: Dictionary = ai.choose_move(
		state,
		OWNER_OPPONENT,
		rng,
		profile
	)
	if not bool(choice.get("valid", false)):
		return _ok(false, "AI returned no move.")

	var chosen_card = state.opponent_hand[int(choice["hand_index"])]
	var preview: Dictionary = state.preview_move(
		chosen_card,
		OWNER_OPPONENT,
		int(choice["cell_index"]),
		1 if bool(choice.get("rotate", false)) else 0
	)
	return _ok(
		int(preview.get("capture_count", 0)) >= 1,
		"AI ignored a deterministic capture with capture weight dominant."
	)


func _test_card_rank_gate() -> Dictionary:
	var policy = AcquisitionPolicyScript.new()
	policy.enforce_card_rank_for_decks = true

	var card = MockCard.new(&"rank_gate", 1, 1, 1, 1)
	card.required_player_rank = 3
	return _ok(
		not policy.can_use_card(card, 2)
		and policy.can_use_card(card, 3),
		"Card rank gate should unlock exactly at required Duel Rank."
	)


func _test_registry_duplicate_id() -> Dictionary:
	var first = OpponentProfileScript.new()
	first.opponent_id = &"qa_duplicate"
	first.display_name = "QA One"

	var second = OpponentProfileScript.new()
	second.opponent_id = &"qa_duplicate"
	second.display_name = "QA Two"

	var registry = OpponentRegistryScript.new()
	registry.opponents.append(first)
	registry.opponents.append(second)

	var audit: Dictionary = registry.validate_registry(null)
	return _ok(
		not bool(audit.get("valid", true)),
		"Registry should reject duplicate opponent IDs."
	)


func _test_row_boundary_no_wrap() -> Dictionary:
	var state = _new_match()
	# Cells 2 and 3 are adjacent in the flat array but sit on different rows.
	# A right-facing value from cell 2 must never capture cell 3.
	state.board[3] = _slot(
		MockCard.new(&"wrap_target", 1, 1, 1, 1),
		OWNER_OPPONENT
	)
	var placed = MockCard.new(&"wrap_source", 1, 9, 1, 1)
	var preview: Dictionary = state.preview_move(
		placed,
		OWNER_PLAYER,
		2
	)
	return _ok(
		int(preview.get("capture_count", 0)) == 0,
		"Board-neighbor logic wrapped from cell 2 into cell 3."
	)


func _test_preview_is_immutable() -> Dictionary:
	var state = _new_match()
	state.board[3] = _slot(
		MockCard.new(&"preview_target", 1, 2, 1, 1),
		OWNER_OPPONENT
	)
	var placed = MockCard.new(&"preview_source", 1, 1, 1, 5)
	var player_hand_before: int = state.player_hand.size()
	var opponent_hand_before: int = state.opponent_hand.size()
	var current_owner_before: int = state.current_owner
	var turn_before: int = state.turn_number

	var preview: Dictionary = state.preview_move(
		placed,
		OWNER_PLAYER,
		4
	)
	var target: Dictionary = state.board[3]
	return _ok(
		int(preview.get("capture_count", 0)) == 1
		and state.board[4] == null
		and int(target.get("owner", OWNER_NONE)) == OWNER_OPPONENT
		and state.player_hand.size() == player_hand_before
		and state.opponent_hand.size() == opponent_hand_before
		and state.current_owner == current_owner_before
		and state.turn_number == turn_before,
		"preview_move() mutated live match state."
	)


func _test_plus_combo_chain() -> Dictionary:
	var rules := MockRuleSet.new()
	rules.plus_rule = true
	rules.combo_rule = true
	var state = _new_match(rules)

	# Center top 3 + top-neighbor bottom 2 = 5.
	# Center left 4 + left-neighbor right 1 = 5, triggering Plus.
	# The top Plus seed then beats cell 0 to prove Plus can seed Combo.
	state.board[1] = _slot(
		MockCard.new(&"plus_combo_seed", 1, 1, 2, 6),
		OWNER_OPPONENT
	)
	state.board[3] = _slot(
		MockCard.new(&"plus_combo_second", 1, 1, 1, 1),
		OWNER_OPPONENT
	)
	state.board[0] = _slot(
		MockCard.new(&"plus_combo_target", 1, 2, 1, 1),
		OWNER_OPPONENT
	)

	var placed = MockCard.new(&"plus_combo_placed", 3, 1, 1, 4)
	var preview: Dictionary = state.preview_move(
		placed,
		OWNER_PLAYER,
		4
	)
	var combo: Array = preview.get("combo_captured", [])
	return _ok(
		bool(preview.get("plus_triggered", false))
		and combo.has(0),
		"Expected a Plus capture to seed Combo into cell 0."
	)


func _test_region_disables_rotate() -> Dictionary:
	var region := MockRegion.new()
	region.allow_rotate = false
	var state = _new_match(null, region)
	return _ok(
		not state.can_rotate(OWNER_PLAYER, 0)
		and not state.rotate_hand_card(OWNER_PLAYER, 0)
		and not state.player_rotate_used,
		"Region allow_rotate=false did not disable Rotate."
	)


func _test_registry_rank_availability() -> Dictionary:
	var profile = OpponentProfileScript.new()
	profile.opponent_id = &"qa_rank_gate"
	profile.display_name = "QA Rank Gate"
	profile.required_player_rank = 3

	var registry = OpponentRegistryScript.new()
	registry.opponents.append(profile)
	var locked: Dictionary = registry.get_availability(
		&"qa_rank_gate",
		2
	)
	var open: Dictionary = registry.get_availability(
		&"qa_rank_gate",
		3
	)
	return _ok(
		not bool(locked.get("available", true))
		and bool(open.get("available", false)),
		"Opponent availability did not unlock exactly at required Duel Rank."
	)


func _test_influence_enables_same() -> Dictionary:
	var rules := MockRuleSet.new()
	rules.same_rule = true
	rules.combo_rule = true
	rules.influence_rule = true
	var state = _new_match(rules)

	# The top enemy would normally be 6 vs the placed card's 5. The placed
	# card projects -1 pressure upward, turning that comparison into 5 == 5.
	# The left comparison is already 4 == 4, so Influence manufactures Same.
	state.board[1] = _slot(
		MockCard.new(&"influence_top", 1, 1, 6, 1),
		OWNER_OPPONENT
	)
	state.board[3] = _slot(
		MockCard.new(&"influence_left", 1, 4, 1, 1),
		OWNER_OPPONENT
	)
	var placed = MockCard.new(&"influence_placed", 5, 1, 1, 4)
	placed.influence_mode = &"pressure"
	placed.influence_strength = 1
	placed.influence_offsets.append(Vector2i(0, -1))

	var preview: Dictionary = state.preview_move(
		placed,
		OWNER_PLAYER,
		4
	)
	var same_captured: Array = preview.get("same_captured", [])
	return _ok(
		bool(preview.get("same_triggered", false))
		and same_captured.has(1)
		and same_captured.has(3)
		and int(preview.get("influence_modifiers", {}).get(1, 0)) == -1,
		"Influence failed to lower the top enemy and manufacture Same."
	)


func _test_influence_pattern_rotation() -> Dictionary:
	var rules := MockRuleSet.new()
	rules.influence_rule = true
	var state = _new_match(rules)
	var placed = MockCard.new(&"rotate_influence", 1, 1, 1, 1)
	placed.influence_mode = &"pressure"
	placed.influence_strength = 1
	placed.influence_offsets.append(Vector2i(0, -1))

	var preview: Dictionary = state.preview_move(
		placed,
		OWNER_PLAYER,
		4,
		1
	)
	var cells: Array = preview.get("influence_cells", [])
	return _ok(
		cells.size() == 1 and cells.has(5) and not cells.has(1),
		"Clockwise rotation did not rotate upward Influence to the right."
	)


func _test_influence_snapshot_stable() -> Dictionary:
	var rules := MockRuleSet.new()
	rules.same_rule = true
	rules.combo_rule = true
	rules.influence_rule = true
	var state = _new_match(rules)

	# Player pressure lowers the top enemy from 6 to 5 and manufactures Same.
	# Once that enemy flips, its left side must stay at the pre-capture effective
	# value 5 for this entire resolution. If pressure were recomputed immediately
	# from its new owner, it would jump back to 6 and incorrectly Combo-capture
	# cell 0. Influence allegiance changes only for the next action.
	state.board[1] = _slot(
		MockCard.new(&"snapshot_top", 1, 1, 6, 6),
		OWNER_OPPONENT
	)
	state.board[3] = _slot(
		MockCard.new(&"snapshot_left", 1, 4, 1, 1),
		OWNER_OPPONENT
	)
	state.board[0] = _slot(
		MockCard.new(&"snapshot_combo_target", 9, 5, 9, 9),
		OWNER_OPPONENT
	)

	var placed = MockCard.new(&"snapshot_placed", 5, 1, 1, 4)
	placed.influence_mode = &"pressure"
	placed.influence_strength = 1
	placed.influence_offsets.append(Vector2i(0, -1))

	var preview: Dictionary = state.preview_move(
		placed,
		OWNER_PLAYER,
		4
	)
	var combo: Array = preview.get("combo_captured", [])
	return _ok(
		bool(preview.get("same_triggered", false))
		and not combo.has(0),
		"A Same-flipped card changed its Influence modifier during the same resolution."
	)


func _test_influence_changes_allegiance() -> Dictionary:
	var rules := MockRuleSet.new()
	rules.influence_rule = true
	var state = _new_match(rules)

	# Keep the overall card-count invariant valid while pre-populating the board.
	state.opponent_hand.pop_back()
	state.opponent_hand_rotations.pop_back()

	var source = MockCard.new(&"allegiance_source", 1, 1, 1, 1)
	source.influence_mode = &"pressure"
	source.influence_strength = 1
	source.influence_offsets.append(Vector2i(0, 1))
	state.board[1] = _slot(source, OWNER_OPPONENT)

	var capturing = MockCard.new(&"allegiance_capture", 1, 1, 1, 5)
	state.player_hand[0] = capturing
	var result: Dictionary = state.place_card(OWNER_PLAYER, 0, 2)
	if not bool(result.get("success", false)):
		return _ok(false, "Could not execute the allegiance-change setup move.")

	var captured_slot: Dictionary = state.board[1]
	return _ok(
		int(captured_slot.get("owner", OWNER_NONE)) == OWNER_PLAYER
		and state.get_cell_influence_modifier(4, OWNER_PLAYER) == 0
		and state.get_cell_influence_modifier(4, OWNER_OPPONENT) == -1,
		"Captured Influence did not change allegiance for the next action."
	)


func _test_stake_policy_strongest() -> Dictionary:
	var cheap_high_ranks = MockCard.new(&"z_card", 9, 9, 9, 9, 5)
	var expensive_low_ranks = MockCard.new(&"b_card", 1, 1, 1, 1, 6)
	var expensive_tie_high = MockCard.new(&"a_card", 2, 2, 2, 2, 6)
	var expensive_tie_high_later_id = MockCard.new(&"c_card", 2, 2, 2, 2, 6)
	var cards: Array = [
		cheap_high_ranks,
		expensive_low_ranks,
		expensive_tie_high_later_id,
		expensive_tie_high,
	]
	var policy = StakePolicyScript.new()
	return _ok(
		policy.choose_lost_card_index(cards) == 3,
		"Stake policy must prefer points, then rank total, then stable card_id."
	)


func _test_stake_policy_minimum_deck() -> Dictionary:
	var cards: Array = [
		MockCard.new(&"stake_a", 2, 2, 2, 2, 2),
		MockCard.new(&"stake_b", 3, 3, 3, 3, 3),
		MockCard.new(&"stake_c", 4, 4, 4, 4, 4),
		MockCard.new(&"stake_d", 5, 5, 5, 5, 5),
		MockCard.new(&"stake_e", 6, 6, 6, 6, 6),
	]
	var quantities: Dictionary = {}
	for card in cards:
		quantities[String(card.card_id)] = 1

	var policy = StakePolicyScript.new()
	var protected_index: int = policy.choose_lost_card_index(
		cards,
		cards,
		quantities,
		5
	)
	if protected_index != -1:
		return _ok(
			false,
			"Exactly five playable unique cards must be protected from stake loss."
		)

	# A duplicate copy is safe to stake because one copy remains in the collection.
	quantities["stake_e"] = 2
	var duplicate_safe_index: int = policy.choose_lost_card_index(
		cards,
		cards,
		quantities,
		5
	)
	return _ok(
		duplicate_safe_index == 4,
		"A duplicate of the strongest card should remain a legal stake at the minimum deck size."
	)


func _test_influence_source_attribution() -> Dictionary:
	var rules = MockRuleSet.new()
	rules.influence_rule = true
	var state = _new_match(rules)
	var source = MockCard.new(&"source", 4, 4, 4, 4)
	source.influence_mode = &"pressure"
	source.influence_strength = 1
	source.influence_offsets.append(Vector2i(1, 0))
	var target = MockCard.new(&"target", 6, 6, 6, 6)
	state.board[4] = _slot(source, OWNER_PLAYER)
	state.board[5] = _slot(target, OWNER_OPPONENT)

	var snapshot: Array = state.get_influence_board_snapshot()
	var target_cell: Dictionary = snapshot[5]
	var sources: Array = target_cell.get("opposing_sources", [])
	return _ok(
		int(target_cell.get("influence_modifier", 0)) == -1
		and sources.size() == 1
		and int((sources[0] as Dictionary).get("source_cell", -1)) == 4
		and str((sources[0] as Dictionary).get("card_id", "")) == "source",
		"Expected cell 5 to attribute -1 Pressure to the source card at cell 4."
	)


func _test_preview_influence_deltas() -> Dictionary:
	var rules = MockRuleSet.new()
	rules.influence_rule = true
	var state = _new_match(rules)
	var target = MockCard.new(&"target", 6, 6, 6, 6)
	state.board[5] = _slot(target, OWNER_OPPONENT)
	var pressure = MockCard.new(&"pressure", 4, 4, 4, 4)
	pressure.influence_mode = &"pressure"
	pressure.influence_strength = 1
	pressure.influence_offsets.append(Vector2i(1, 0))

	var preview: Dictionary = state.preview_move(
		pressure,
		OWNER_PLAYER,
		4
	)
	var found_target_delta: bool = false
	for raw_delta in preview.get("influence_deltas", []):
		var delta: Dictionary = raw_delta
		if int(delta.get("cell_index", -1)) != 5:
			continue
		found_target_delta = (
			int(delta.get("before_modifier", 0)) == 0
			and int(delta.get("after_modifier", 0)) == -1
			and int(delta.get("modifier_delta", 0)) == -1
		)
	return _ok(
		bool(preview.get("valid", false))
		and found_target_delta
		and state.board[4] == null
		and int((state.board[5] as Dictionary).get("owner", OWNER_NONE)) == OWNER_OPPONENT,
		"Expected preview to expose the -1 delta without mutating match state."
	)


func _test_unsupported_rule_guard() -> Dictionary:
	var rules = RuleSetScript.new()
	rules.same_wall_rule = true
	var audit: Dictionary = rules.validate_runtime_support()
	return _ok(
		not bool(audit.get("valid", true))
		and not audit.get("errors", []).is_empty(),
		"Unimplemented rule toggles must fail validation instead of silently running."
	)


func _test_authored_opponent_ladder() -> Dictionary:
	var registry_audit: Dictionary = DefaultOpponentRegistry.validate_registry(
		DefaultCardCatalog
	)
	if not bool(registry_audit.get("valid", false)):
		return _ok(
			false,
			"Opponent registry failed validation: %s"
			% str(registry_audit.get("errors", []))
		)

	var all_profiles: Array = DefaultOpponentRegistry.get_all_opponents()
	if all_profiles.size() < 11:
		return _ok(false, "Expected the authored card-player ecosystem to contain at least eleven opponents.")
	var profiles: Array = DefaultOpponentRegistry.get_progression_spine()
	if profiles.size() != 6:
		return _ok(false, "Expected exactly six progression-spine opponents.")

	var previous_duel_rank: int = 0
	var expected_duel_rank: int = 1
	var archetypes: Dictionary = {}
	for profile in profiles:
		if profile == null:
			return _ok(false, "Opponent ladder contains a null profile.")
		var opponent_id: String = String(profile.opponent_id)
		if profile.duel_rank < previous_duel_rank:
			return _ok(false, "Opponent ladder is not ordered by Duel Rank.")
		if profile.duel_rank != expected_duel_rank:
			return _ok(
				false,
				"Opponent ladder is missing Duel Rank %d." % expected_duel_rank
			)
		previous_duel_rank = profile.duel_rank
		expected_duel_rank += 1

		var archetype_id: String = String(profile.archetype_id)
		if archetypes.has(archetype_id):
			return _ok(false, "Duplicate opponent archetype: %s" % archetype_id)
		archetypes[archetype_id] = true

		if profile.content_revision < 1:
			return _ok(false, "%s has no authored content revision." % opponent_id)
		if profile.preferred_deck_ids.size() != 5:
			return _ok(false, "%s does not have a five-card preferred deck." % opponent_id)
		if profile.reward_card_ids.is_empty():
			return _ok(false, "%s has no authored reward pool." % opponent_id)

		var budget: int = int(profile.deck_budget_override)
		if budget <= 0 and profile.region_profile != null:
			budget = int(profile.region_profile.deck_budget)
		budget = maxi(5, budget)
		var deck_cost: int = 0
		for raw_id in profile.preferred_deck_ids:
			var card = DefaultCardCatalog.get_card_by_id(StringName(str(raw_id)))
			if card == null:
				return _ok(false, "%s references a missing preferred card." % opponent_id)
			deck_cost += int(card.deck_cost)
		if deck_cost > budget:
			return _ok(
				false,
				"%s preferred deck costs %d over budget %d."
				% [opponent_id, deck_cost, budget]
			)

		for raw_reward_id in profile.reward_card_ids:
			if not profile.preferred_deck_ids.has(raw_reward_id):
				return _ok(
					false,
					"%s reward card %s is not guaranteed to appear in its authored deck."
					% [opponent_id, str(raw_reward_id)]
				)

	return _ok(true)


func _test_session_lifecycle_controller() -> Dictionary:
	var session = SessionControllerScript.new()
	if session.is_open():
		return _ok(false, "A new session must start closed.")
	session.open_deck_setup(false)
	if session.phase != SessionControllerScript.PHASE_DECK_SETUP:
		return _ok(false, "Opening must enter deck setup.")
	session.prepare_new_match()
	session.begin_dealing()
	session.complete_deal(OWNER_PLAYER)
	if (
		not session.match_started
		or session.phase != SessionControllerScript.PHASE_SELECT_CARD
	):
		return _ok(false, "Player-start deal must enter card selection.")
	if not session.begin_player_cell_selection():
		return _ok(false, "Card selection must be allowed to enter cell selection.")
	if not session.cancel_player_cell_selection():
		return _ok(false, "Cell selection must return to card selection.")
	session.close_session()
	return _ok(
		not session.is_open()
		and not session.match_started
		and session.phase == SessionControllerScript.PHASE_CLOSED,
		"Closing must leave no live match phase."
	)


func _test_session_surrender_resume() -> Dictionary:
	var session = SessionControllerScript.new()
	session.open_deck_setup(false)
	session.prepare_new_match()
	session.begin_dealing()
	session.complete_deal(OWNER_OPPONENT)
	if not session.request_surrender():
		return _ok(false, "AI turn should allow a surrender request.")
	if session.phase != SessionControllerScript.PHASE_SURRENDER_CONFIRM:
		return _ok(false, "Surrender request must enter confirmation.")
	var resume_phase: int = session.cancel_surrender()
	if (
		resume_phase != SessionControllerScript.PHASE_AI
		or session.phase != SessionControllerScript.PHASE_AI
	):
		return _ok(false, "Cancelled surrender must resume the interrupted AI turn.")
	if not session.request_surrender():
		return _ok(false, "Resumed AI turn should still allow surrender.")
	session.confirm_surrender()
	return _ok(
		session.surrendered
		and session.surrender_resume_phase == SessionControllerScript.PHASE_CLOSED,
		"Confirmed surrender must clear its resume phase and mark the result."
	)


func _test_session_result_recovery() -> Dictionary:
	var session = SessionControllerScript.new()
	session.open_deck_setup(false)
	session.prepare_new_match()
	session.begin_dealing()
	session.complete_deal(OWNER_PLAYER)
	session.finish_match(OWNER_PLAYER, &"board_complete")
	if (
		session.phase != SessionControllerScript.PHASE_RESULT
		or session.result_winner != OWNER_PLAYER
		or session.result_reason != &"board_complete"
	):
		return _ok(false, "Finished match state was not captured deterministically.")
	if not session.begin_result_transition():
		return _ok(false, "Result phase must be allowed to begin its transition.")
	session.begin_reward()
	if session.phase != SessionControllerScript.PHASE_REWARD:
		return _ok(false, "Resolved result must enter reward phase.")
	session.recover_reward_session(true, OWNER_OPPONENT, &"recovered", true)
	return _ok(
		session.previous_pause
		and session.phase == SessionControllerScript.PHASE_REWARD
		and session.result_winner == OWNER_OPPONENT
		and session.result_reason == &"recovered"
		and session.surrendered
		and not session.match_started,
		"Recovered reward state must be complete and self-consistent."
	)

func _test_match_flow_setup_and_deal() -> Dictionary:
	var match_state = MatchScript.new()
	var ai = AIScript.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 101
	var session = SessionControllerScript.new()
	var flow = MatchFlowControllerScript.new()
	flow.initialize(match_state, ai, rng, session)
	session.open_deck_setup(false)

	var player_cards: Array = []
	var opponent_cards: Array = []
	for index in range(5):
		player_cards.append(
			MockCard.new(StringName("flow_p_%d" % index), 3, 3, 3, 3)
		)
		opponent_cards.append(
			MockCard.new(StringName("flow_o_%d" % index), 2, 2, 2, 2)
		)

	var prepared: Dictionary = flow.prepare_match(
		player_cards,
		opponent_cards,
		OWNER_PLAYER,
		MockRuleSet.new(),
		MockRegion.new()
	)
	if (
		not bool(prepared.get("success", false))
		or session.phase != SessionControllerScript.PHASE_DEALING
		or match_state.player_hand.size() != 5
		or match_state.opponent_hand.size() != 5
		or int(prepared.get("selected_hand_index", -1)) != 0
		or int(prepared.get("selected_cell_index", -1)) != 4
	):
		return _ok(false, "Flow setup did not establish the canonical fresh-match state.")

	var completed: Dictionary = flow.complete_deal(OWNER_PLAYER)
	return _ok(
		bool(completed.get("success", false))
		and not bool(completed.get("schedule_ai", true))
		and session.match_started
		and session.phase == SessionControllerScript.PHASE_SELECT_CARD,
		"Player-start deal must hand control to player card selection."
	)


func _test_match_flow_turn_handoff() -> Dictionary:
	var match_state = MatchScript.new()
	var ai = AIScript.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 202
	var session = SessionControllerScript.new()
	var flow = MatchFlowControllerScript.new()
	flow.initialize(match_state, ai, rng, session)
	session.open_deck_setup(false)

	var player_cards: Array = []
	var opponent_cards: Array = []
	for index in range(5):
		player_cards.append(
			MockCard.new(StringName("turn_p_%d" % index), 5, 5, 5, 5)
		)
		opponent_cards.append(
			MockCard.new(StringName("turn_o_%d" % index), 2, 2, 2, 2)
		)
	flow.prepare_match(
		player_cards,
		opponent_cards,
		OWNER_PLAYER,
		MockRuleSet.new(),
		MockRegion.new()
	)
	flow.complete_deal(OWNER_PLAYER)

	var player_move: Dictionary = flow.commit_player_move(0, 4)
	if (
		not bool(player_move.get("success", false))
		or session.phase != SessionControllerScript.PHASE_ANIMATING
	):
		return _ok(false, "Player move was not committed through the flow controller.")
	var player_result: Dictionary = player_move.get("result", {})
	if flow.complete_player_move(player_result) != &"schedule_ai":
		return _ok(false, "Completed player move did not hand control to AI.")
	if session.phase != SessionControllerScript.PHASE_AI:
		return _ok(false, "Player-to-AI handoff did not enter AI phase.")

	var ai_move: Dictionary = flow.commit_ai_move(null)
	if not bool(ai_move.get("success", false)):
		return _ok(false, "AI flow could not produce a legal reply move.")
	var ai_result: Dictionary = ai_move.get("result", {})
	var handoff: Dictionary = flow.complete_ai_move(ai_result, 0, 4)
	return _ok(
		StringName(handoff.get("action", &"")) == &"player_turn"
		and session.phase == SessionControllerScript.PHASE_SELECT_CARD
		and match_state.turn_number == 2,
		"AI completion must return cleanly to the next player turn."
	)


func _test_match_flow_surrender_and_result() -> Dictionary:
	var match_state = MatchScript.new()
	var ai = AIScript.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 303
	var session = SessionControllerScript.new()
	var flow = MatchFlowControllerScript.new()
	flow.initialize(match_state, ai, rng, session)
	session.open_deck_setup(false)

	var player_cards: Array = []
	var opponent_cards: Array = []
	for index in range(5):
		player_cards.append(
			MockCard.new(StringName("result_p_%d" % index), 4, 4, 4, 4)
		)
		opponent_cards.append(
			MockCard.new(StringName("result_o_%d" % index), 4, 4, 4, 4)
		)
	flow.prepare_match(
		player_cards,
		opponent_cards,
		OWNER_PLAYER,
		MockRuleSet.new(),
		MockRegion.new()
	)
	flow.complete_deal(OWNER_PLAYER)

	if flow.request_surrender() != &"confirm":
		return _ok(false, "Live player turn should enter surrender confirmation.")
	var cancelled: Dictionary = flow.cancel_surrender()
	if (
		int(cancelled.get("resume_phase", -1))
		!= SessionControllerScript.PHASE_SELECT_CARD
		or session.phase != SessionControllerScript.PHASE_SELECT_CARD
	):
		return _ok(false, "Cancelled surrender did not restore player turn.")
	if flow.request_surrender() != &"confirm":
		return _ok(false, "Surrender could not be requested after cancellation.")
	flow.confirm_surrender()
	if not session.surrendered:
		return _ok(false, "Confirmed surrender was not recorded by session state.")

	flow.finish_match(OWNER_OPPONENT, &"surrender")
	var decisive: Dictionary = flow.begin_result_transition()
	if (
		not bool(decisive.get("accepted", false))
		or int(decisive.get("winner", OWNER_NONE)) != OWNER_OPPONENT
		or flow.prepare_result_destination(OWNER_OPPONENT) != &"reward"
		or session.phase != SessionControllerScript.PHASE_REWARD
	):
		return _ok(false, "Decisive result did not route to reward resolution.")

	var draw_match = MatchScript.new()
	var draw_session = SessionControllerScript.new()
	var draw_flow = MatchFlowControllerScript.new()
	draw_flow.initialize(draw_match, ai, rng, draw_session)
	draw_session.open_deck_setup(false)
	draw_flow.prepare_match(
		player_cards,
		opponent_cards,
		OWNER_PLAYER,
		MockRuleSet.new(),
		MockRegion.new()
	)
	draw_flow.complete_deal(OWNER_PLAYER)
	draw_flow.finish_match(OWNER_NONE, &"board_complete")
	if not bool(draw_flow.begin_result_transition().get("accepted", false)):
		return _ok(false, "Draw result transition was rejected.")
	return _ok(
		draw_flow.prepare_result_destination(OWNER_NONE) == &"replay"
		and draw_session.round_number == 2,
		"Draw result must increment the round and route to replay."
	)



func _test_match_resolution_reward_candidates() -> Dictionary:
	var resolver = MatchResolutionControllerScript.new()
	var profile = OpponentProfileScript.new()
	profile.reward_card_ids = PackedStringArray([
		"reward_b",
		"reward_missing",
	])
	var opponent_cards: Array = [
		MockCard.new(&"reward_a", 2, 2, 2, 2),
		MockCard.new(&"reward_b", 3, 3, 3, 3),
		MockCard.new(&"reward_c", 4, 4, 4, 4),
		MockCard.new(&"reward_d", 5, 5, 5, 5),
		MockCard.new(&"reward_e", 6, 6, 6, 6),
	]
	var candidate_ids: PackedStringArray = resolver.player_reward_candidate_ids(
		profile,
		null,
		opponent_cards
	)
	return _ok(
		candidate_ids.size() == 1
		and candidate_ids[0] == "reward_b",
		"Reward candidates must stay limited to authored cards actually present in the opponent hand."
	)


func _test_match_resolution_reward_presentation() -> Dictionary:
	var qa_path := "user://triple_triad_match_resolution_controller_qa.cfg"
	var journal = MatchResolutionJournalScript.new()
	journal.initialize(qa_path)
	journal.clear()

	var player_cards: Array = []
	var opponent_cards: Array = []
	var player_ids := PackedStringArray()
	var opponent_ids := PackedStringArray()
	for index in range(5):
		var player_id := StringName("stake_%d" % index)
		var opponent_id := StringName("reward_%d" % index)
		player_cards.append(MockCard.new(player_id, 3, 3, 3, 3))
		opponent_cards.append(MockCard.new(opponent_id, 3, 3, 3, 3))
		player_ids.append(String(player_id))
		opponent_ids.append(String(opponent_id))

	var started: bool = journal.begin_resolution({
		"opponent_id": "beach_trader",
		"winner": OWNER_OPPONENT,
		"result_reason": "qa",
		"surrendered": false,
		"player_card_ids": player_ids,
		"opponent_card_ids": opponent_ids,
		"eligible_reward_ids": PackedStringArray(),
		"forced_loss_card_id": "stake_2",
		"competition_change": {},
	})
	if not started:
		journal.clear()
		return _ok(false, "Resolution controller QA journal could not start.")

	var resolver = MatchResolutionControllerScript.new()
	resolver.initialize(
		null,
		null,
		null,
		null,
		null,
		null,
		null,
		journal,
		StakePolicyScript.new(),
		null,
		null
	)
	var presentation: Dictionary = resolver.prepare_reward_presentation(
		OWNER_OPPONENT,
		null,
		&"beach_trader",
		player_cards,
		opponent_cards,
		null
	)
	var valid: bool = (
		bool(presentation.get("used_journal", false))
		and int(presentation.get("opponent_take_index", -1)) == 2
	)
	journal.clear()
	return _ok(
		valid,
		"Persisted mandatory loss selection must survive into reward presentation."
	)


func _test_match_resolution_transfer_state() -> Dictionary:
	var player_store = MockQuantityStore.new({"transfer_card": 2})
	var opponent_store = MockQuantityStore.new({"transfer_card": 1})
	var resolver = MatchResolutionControllerScript.new()
	resolver.initialize(
		null,
		player_store,
		null,
		null,
		null,
		null,
		null,
		null,
		StakePolicyScript.new(),
		null,
		null
	)
	var card = MockCard.new(&"transfer_card", 5, 5, 5, 5)
	var state: Dictionary = resolver.prepare_reward_transfer_state(
		card,
		OWNER_PLAYER,
		&"qa_opponent",
		opponent_store
	)
	return _ok(
		str(state.get("card_id", "")) == "transfer_card"
		and int(state.get("player_before", -1)) == 2
		and int(state.get("opponent_before", -1)) == 1
		and int(state.get("desired_player", -1)) == 3
		and int(state.get("desired_opponent", -1)) == 0
		and int(state.get("desired_acquired", -1)) == 1
		and int(state.get("desired_cards_won", -1)) == 1,
		"Reward transfer state must describe the exact post-win ownership target before mutation."
	)

func _test_presentation_player_outline() -> Dictionary:
	var presenter = PresentationControllerScript.new()
	return _ok(
		presenter.owner_outline_visible_for(OWNER_PLAYER, true)
		and presenter.owner_outline_kind(OWNER_PLAYER, true) == &"player",
		"Player-owned cards must expose the player ownership outline."
	)


func _test_presentation_opponent_outline() -> Dictionary:
	var presenter = PresentationControllerScript.new()
	return _ok(
		presenter.owner_outline_visible_for(OWNER_OPPONENT, true)
		and presenter.owner_outline_kind(OWNER_OPPONENT, true) == &"opponent",
		"Opponent-owned cards must expose the opponent ownership outline."
	)


func _test_presentation_empty_outline() -> Dictionary:
	var presenter = PresentationControllerScript.new()
	return _ok(
		not presenter.owner_outline_visible_for(OWNER_NONE, false)
		and presenter.owner_outline_kind(OWNER_NONE, false) == &"none",
		"Empty board slots must not display an ownership outline."
	)

func _qa_key(key: Key, shift_pressed: bool = false) -> InputEventKey:
	var event := InputEventKey.new()
	event.pressed = true
	event.keycode = key
	event.physical_keycode = key
	event.shift_pressed = shift_pressed
	return event


func _test_input_controller_key_mapping() -> Dictionary:
	var controller = InputControllerScript.new()
	return _ok(
		controller.action_for_event(_qa_key(KEY_K), true) == InputControllerScript.ACTION_CONFIRM
		and controller.action_for_event(_qa_key(KEY_I), true) == InputControllerScript.ACTION_BACK
		and controller.action_for_event(_qa_key(KEY_R), true) == InputControllerScript.ACTION_ROTATE
		and controller.hand_step(InputControllerScript.ACTION_UP) == -1
		and controller.hand_step(InputControllerScript.ACTION_DOWN) == 1,
		"Input controller must preserve the authored confirm/back/rotate and hand-navigation bindings."
	)


func _test_input_controller_campaign_qa() -> Dictionary:
	var controller = InputControllerScript.new()
	var shifted_f10 := _qa_key(KEY_F10, true)
	return _ok(
		controller.action_for_event(shifted_f10, true) == InputControllerScript.ACTION_CAMPAIGN_QA
		and controller.action_for_event(shifted_f10, false) == InputControllerScript.ACTION_DEBUG,
		"Shift+F10 must route to campaign QA only in debug-capable builds without stealing normal F10 elsewhere."
	)


func _test_input_controller_board_navigation() -> Dictionary:
	var controller = InputControllerScript.new()
	return _ok(
		controller.move_board_cursor(0, InputControllerScript.ACTION_LEFT) == 0
		and controller.move_board_cursor(0, InputControllerScript.ACTION_UP) == 0
		and controller.move_board_cursor(4, InputControllerScript.ACTION_RIGHT) == 5
		and controller.move_board_cursor(4, InputControllerScript.ACTION_DOWN) == 7
		and controller.move_board_cursor(8, InputControllerScript.ACTION_RIGHT) == 8,
		"Board navigation must stay inside the 3x3 grid while preserving directional movement."
	)

func _test_input_controller_phase_routing() -> Dictionary:
	var controller = InputControllerScript.new()
	var hand_route: Dictionary = controller.route_gameplay_action(
		SessionControllerScript.PHASE_SELECT_CARD,
		InputControllerScript.ACTION_DOWN,
		false
	)
	var cell_route: Dictionary = controller.route_gameplay_action(
		SessionControllerScript.PHASE_SELECT_CELL,
		InputControllerScript.ACTION_LEFT,
		false
	)
	var result_route: Dictionary = controller.route_gameplay_action(
		SessionControllerScript.PHASE_RESULT,
		InputControllerScript.ACTION_CONFIRM,
		false
	)
	return _ok(
		StringName(hand_route.get("command", &"")) == InputControllerScript.COMMAND_MOVE_HAND
		and int(hand_route.get("step", 0)) == 1
		and StringName(cell_route.get("command", &"")) == InputControllerScript.COMMAND_MOVE_BOARD
		and StringName(cell_route.get("action", &"")) == InputControllerScript.ACTION_LEFT
		and StringName(result_route.get("command", &"")) == InputControllerScript.COMMAND_RESULT_TRANSITION,
		"Input routing must translate stable match phases into deterministic scene commands."
	)


func _test_input_controller_transaction_guard() -> Dictionary:
	var controller = InputControllerScript.new()
	var animation_back: Dictionary = controller.route_gameplay_action(
		SessionControllerScript.PHASE_ANIMATING,
		InputControllerScript.ACTION_BACK,
		false
	)
	var reward_back: Dictionary = controller.route_gameplay_action(
		SessionControllerScript.PHASE_REWARD,
		InputControllerScript.ACTION_BACK,
		false
	)
	var deal_back: Dictionary = controller.route_gameplay_action(
		SessionControllerScript.PHASE_DEALING,
		InputControllerScript.ACTION_BACK,
		false
	)
	return _ok(
		StringName(animation_back.get("command", &"")) == InputControllerScript.COMMAND_CONSUME
		and StringName(reward_back.get("command", &"")) == InputControllerScript.COMMAND_NONE
		and StringName(deal_back.get("command", &"")) == InputControllerScript.COMMAND_CLOSE,
		"Input routing must consume Back during transactional animation, leave reward input modal, and allow pre-deal exit."
	)


func _test_input_controller_surrender_routing() -> Dictionary:
	var controller = InputControllerScript.new()
	return _ok(
		controller.route_surrender_confirmation(
			InputControllerScript.ACTION_LEFT, true, false
		) == InputControllerScript.COMMAND_SURRENDER_MOVE
		and controller.route_surrender_confirmation(
			InputControllerScript.ACTION_CONFIRM, true, true
		) == InputControllerScript.COMMAND_SURRENDER_CONFIRM
		and controller.route_surrender_confirmation(
			InputControllerScript.ACTION_CONFIRM, true, false
		) == InputControllerScript.COMMAND_SURRENDER_CANCEL
		and controller.route_surrender_confirmation(
			InputControllerScript.ACTION_BACK, true, true
		) == InputControllerScript.COMMAND_SURRENDER_CANCEL
		and controller.route_surrender_confirmation(
			InputControllerScript.ACTION_CONFIRM, false, true
		) == InputControllerScript.COMMAND_SURRENDER_CANCEL,
		"Surrender confirmation routing must keep modal navigation, confirm, cancellation, and missing-surface recovery deterministic."
	)


func _test_ui_flow_result_copy() -> Dictionary:
	var controller = UIFlowControllerScript.new()
	return _ok(
		controller.result_text_for(OWNER_PLAYER, false) == "YOU WIN!"
		and controller.result_text_for(OWNER_OPPONENT, false) == "YOU LOSE..."
		and controller.result_text_for(OWNER_OPPONENT, true) == "YOU SURRENDER..."
		and controller.result_text_for(OWNER_NONE, false) == "DRAW",
		"UI flow must own deterministic result copy for win/loss/surrender/draw states."
	)


func _test_ui_flow_turn_text() -> Dictionary:
	var controller = UIFlowControllerScript.new()
	return _ok(
		controller.turn_text_for_phase(SessionControllerScript.PHASE_SELECT_CARD) == "Your Turn"
		and controller.turn_text_for_phase(SessionControllerScript.PHASE_SELECT_CELL) == "Your Turn"
		and controller.turn_text_for_phase(SessionControllerScript.PHASE_AI) == "Opponent Turn"
		and controller.turn_text_for_phase(SessionControllerScript.PHASE_DEALING) == "Dealing"
		and controller.turn_text_for_phase(SessionControllerScript.PHASE_RESULT) == "Result",
		"UI flow must map session phases to the authored match HUD turn labels."
	)


func _test_ui_flow_selection_phase() -> Dictionary:
	var controller = UIFlowControllerScript.new()
	return _ok(
		controller.phase_uses_player_selection(SessionControllerScript.PHASE_SELECT_CARD)
		and controller.phase_uses_player_selection(SessionControllerScript.PHASE_SELECT_CELL)
		and not controller.phase_uses_player_selection(SessionControllerScript.PHASE_AI)
		and not controller.phase_uses_player_selection(SessionControllerScript.PHASE_RESULT),
		"Player selection markers must remain scoped to hand/cell selection phases."
	)



func _test_world_gateway_backend_guard() -> Dictionary:
	var gateway = WorldGatewayScript.new()
	gateway.initialize(
		null,
		null,
		null,
		null,
		null,
		null,
		null,
		null,
		RandomNumberGenerator.new(),
		1
	)
	var bundle_result: Dictionary = gateway.claim_acquisition_bundle(
		&"qa_bundle",
		&"qa"
	)
	var card_result: Dictionary = gateway.claim_world_source_card(
		&"quest_reward",
		&"qa_source",
		&"qa_card",
		&"qa"
	)
	return _ok(
		not bool(bundle_result.get("success", true))
		and str(bundle_result.get("reason", "")) == "backend_unavailable"
		and not bool(card_result.get("success", true))
		and str(card_result.get("reason", "")) == "backend_not_ready",
		"World-facing writes must stay closed until the Triple Triad backend is fully ready."
	)


func _test_world_gateway_one_shot_reward() -> Dictionary:
	var owned_card = MockCard.new(&"world_owned", 2, 2, 2, 2)
	owned_card.display_name = "Owned"
	var new_card = MockCard.new(&"world_new", 3, 3, 3, 3)
	new_card.display_name = "New"
	var catalog = MockGatewayCardCatalog.new([
		owned_card,
		new_card,
	])
	var collection = MockQuantityStore.new({
		"world_owned": 1,
		"world_new": 0,
	})
	var acquisition = MockGatewayAcquisitionService.new(collection)
	acquisition.unlocked = true
	var world_catalog = MockGatewayWorldCatalog.new([
		owned_card,
		new_card,
	])
	var ledger = WorldRewardLedgerScript.new()
	var ledger_path := "user://triple_triad_world_gateway_qa.cfg"
	ledger.initialize(ledger_path)
	ledger.reset_event(&"qa_world_event")

	var gateway = WorldGatewayScript.new()
	gateway.initialize(
		catalog,
		acquisition,
		world_catalog,
		ledger,
		collection,
		MockGatewayProgression.new(4),
		MockGatewayEncounterRecords.new(),
		MockGatewayOpponentRegistry.new(),
		RandomNumberGenerator.new(),
		1
	)
	gateway.set_backend_ready(true)
	var first: Dictionary = gateway.claim_world_source_reward(
		&"quest_reward",
		&"qa_source",
		&"qa_context",
		&"qa_world_event",
		true
	)
	var second: Dictionary = gateway.claim_world_source_reward(
		&"quest_reward",
		&"qa_source",
		&"qa_context",
		&"qa_world_event",
		true
	)
	var valid: bool = (
		bool(first.get("success", false))
		and str(first.get("card_id", "")) == "world_new"
		and collection.get_quantity_by_id(&"world_new") == 1
		and ledger.has_claimed(&"qa_world_event")
		and not bool(second.get("success", true))
		and str(second.get("reason", "")) == "event_already_claimed"
	)
	ledger.reset_event(&"qa_world_event")
	return _ok(
		valid,
		"One-shot world rewards must choose an unowned card, journal it, and reject duplicate delivery."
	)


func _test_world_gateway_opponent_context() -> Dictionary:
	var acquisition = MockGatewayAcquisitionService.new()
	acquisition.unlocked = true
	var encounters = MockGatewayEncounterRecords.new()
	var registry = MockGatewayOpponentRegistry.new()
	var gateway = WorldGatewayScript.new()
	gateway.initialize(
		null,
		acquisition,
		null,
		null,
		null,
		MockGatewayProgression.new(4),
		encounters,
		registry,
		RandomNumberGenerator.new(),
		1
	)
	gateway.set_backend_ready(true)
	var availability: Dictionary = gateway.get_opponent_availability(
		&"qa_opponent"
	)
	var available_ids: PackedStringArray = (
		gateway.get_available_card_player_ids()
	)
	var beaten = registry.last_context.get(
		"beaten_opponent_ids",
		PackedStringArray()
	)
	return _ok(
		bool(availability.get("available", false))
		and registry.last_rank == 4
		and bool(
			registry.last_context.get(
				"card_game_unlocked",
				false
			)
		)
		and int(
			registry.last_context.get(
				"total_player_wins",
				0
			)
		) == 3
		and beaten is PackedStringArray
		and beaten.has("rookie")
		and available_ids.size() == 1
		and available_ids[0] == "qa_opponent",
		"World gateway must provide one consistent unlock/rank/encounter context to card-player discovery."
	)


func _test_competition_controller_deck_lock() -> Dictionary:
	var world_catalog = WorldAcquisitionCatalogScript.new()
	world_catalog.initialize(
		DefaultCardCatalog,
		DefaultOpponentRegistry,
		DefaultAcquisitionRegistry
	)
	var competition_catalog = CompetitionCatalogScript.new()
	var audit: Dictionary = competition_catalog.initialize(
		DefaultOpponentRegistry,
		world_catalog
	)
	if not bool(audit.get("valid", false)):
		return _ok(false, "Competition catalog invalid in controller deck-lock test.")

	var service = CompetitionServiceScript.new()
	service.initialize(competition_catalog, false)
	var beaten := PackedStringArray([
		"pier_apprentice",
		"beach_trader",
		"dock_bruiser",
		"gearwright",
		"marsh_keeper",
		"highland_keeper",
		"lantern_gambler",
		"tide_oracle",
	])
	var started: Dictionary = service.start_competition(
		&"regional_championship",
		3,
		beaten
	)
	if not bool(started.get("success", false)):
		return _ok(false, "Regional Championship did not start for controller test.")

	var locked_ids := PackedStringArray([
		"mugshot_153",
		"mugshot_156",
		"mugshot_157",
		"mugshot_161",
		"mugshot_162",
	])
	var cards: Array = []
	var quantities: Dictionary = {}
	for raw_id in locked_ids:
		var card = DefaultCardCatalog.get_card_by_id(StringName(raw_id))
		if card == null:
			return _ok(false, "Controller deck-lock QA card is missing from the authored catalog.")
		cards.append(card)
		quantities[String(raw_id)] = 1

	var controller = CompetitionControllerScript.new()
	controller.initialize(
		service,
		DefaultCardCatalog,
		MockQuantityStore.new(quantities),
		MockGatewayProgression.new(3),
		MockGatewayEncounterRecords.new(),
		null,
		null,
		null,
		DefaultOpponentRegistry,
		3
	)
	return _ok(
		controller.lock_active_deck(cards)
		and controller.get_locked_deck_cards().size() == 5
		and service.get_locked_deck_ids() == locked_ids,
		"Competition controller must own the tournament deck lock and resolve it back to five legal owned cards."
	)


func _test_competition_controller_resolution_state() -> Dictionary:
	var controller = CompetitionControllerScript.new()
	controller.initialize(
		null,
		null,
		null,
		null,
		null,
		null,
		null,
		null,
		null,
		1
	)
	controller.set_match_active(true)
	var change: Dictionary = controller.apply_match_resolution({
		"competition": {
			"round_won": true,
			"next_opponent_id": "qa_next",
		},
		"competition_match_active": false,
		"competition_state_changed": false,
	})
	return _ok(
		bool(change.get("round_won", false))
		and controller.should_continue_after_reward()
		and not controller.is_match_active()
		and str(controller.get_pending_change().get("next_opponent_id", "")) == "qa_next",
		"Competition controller must retain the post-match round handoff while ending ownership of the completed match."
	)


func _test_runtime_recovery_stale_tournament() -> Dictionary:
	var world_catalog = WorldAcquisitionCatalogScript.new()
	world_catalog.initialize(
		DefaultCardCatalog,
		DefaultOpponentRegistry,
		DefaultAcquisitionRegistry
	)
	var competition_catalog = CompetitionCatalogScript.new()
	var audit: Dictionary = competition_catalog.initialize(
		DefaultOpponentRegistry,
		world_catalog
	)
	if not bool(audit.get("valid", false)):
		return _ok(false, "Competition catalog invalid in runtime-recovery test.")

	var service = CompetitionServiceScript.new()
	service.initialize(competition_catalog, false)
	var beaten := PackedStringArray([
		"pier_apprentice",
		"beach_trader",
		"dock_bruiser",
		"gearwright",
		"marsh_keeper",
		"highland_keeper",
		"lantern_gambler",
		"tide_oracle",
	])
	var started: Dictionary = service.start_competition(
		&"regional_championship",
		3,
		beaten
	)
	if not bool(started.get("success", false)):
		return _ok(false, "Regional Championship did not start for runtime-recovery test.")

	var locked_ids := PackedStringArray([
		"mugshot_153",
		"mugshot_156",
		"mugshot_157",
		"mugshot_161",
		"mugshot_162",
	])
	if not service.set_locked_deck_ids(locked_ids):
		return _ok(false, "Runtime-recovery test could not persist its locked deck.")

	# Deliberately omit one locked card from the owned collection. The recovery
	# controller must treat the persisted tournament as stale and abandon it.
	var quantities := {
		"mugshot_153": 1,
		"mugshot_156": 1,
		"mugshot_157": 1,
		"mugshot_161": 1,
		"mugshot_162": 0,
	}
	var competition = CompetitionControllerScript.new()
	competition.initialize(
		service,
		DefaultCardCatalog,
		MockQuantityStore.new(quantities),
		MockGatewayProgression.new(3),
		MockGatewayEncounterRecords.new(),
		null,
		null,
		null,
		DefaultOpponentRegistry,
		3
	)
	var recovery = RuntimeRecoveryControllerScript.new()
	recovery.initialize(
		competition,
		DefaultCardCatalog,
		null,
		null,
		null,
		null,
		null,
		DefaultOpponentRegistry
	)
	var report: Dictionary = recovery.reconcile_runtime_state()
	return _ok(
		bool(report.get("repaired", false))
		and bool(report.get("stale_tournament_abandoned", false))
		and not bool(service.get_active_snapshot().get("active", false)),
		"Runtime recovery must abandon an active tournament when its persisted locked deck is no longer legal."
	)


func _make_backend_validation_context(player_budget: int = 30) -> Dictionary:
	var world_catalog = WorldAcquisitionCatalogScript.new()
	world_catalog.initialize(
		DefaultCardCatalog,
		DefaultOpponentRegistry,
		DefaultAcquisitionRegistry
	)
	var competition_catalog = CompetitionCatalogScript.new()
	competition_catalog.initialize(
		DefaultOpponentRegistry,
		world_catalog
	)
	return {
		"card_catalog": DefaultCardCatalog,
		"region_profile": DefaultRegionProfile,
		"rule_set": DefaultRuleSet,
		"opponent_registry": DefaultOpponentRegistry,
		"acquisition_policy": DefaultAcquisitionPolicy,
		"acquisition_registry": DefaultAcquisitionRegistry,
		"competition_catalog": competition_catalog,
		"world_acquisition_catalog": world_catalog,
		"player_deck_budget": player_budget,
	}


func _test_backend_validator_defaults() -> Dictionary:
	var validator = BackendValidatorScript.new()
	var report: Dictionary = validator.validate(
		_make_backend_validation_context(30)
	)
	return _ok(
		bool(report.get("valid", false))
		and report.get("errors", []).is_empty(),
		"Backend validator must accept the authored default catalogs and policies before persistent services boot."
	)


func _test_backend_validator_missing_catalog() -> Dictionary:
	var context: Dictionary = _make_backend_validation_context(30)
	context["card_catalog"] = null
	var validator = BackendValidatorScript.new()
	var report: Dictionary = validator.validate(context)
	var errors = report.get("errors", PackedStringArray())
	var found_missing_catalog: bool = false
	for raw_error in errors:
		if str(raw_error) == "Card catalog is missing.":
			found_missing_catalog = true
			break
	return _ok(
		not bool(report.get("valid", true)) and found_missing_catalog,
		"Backend validator must stop bootstrap when the canonical card catalog is absent."
	)


func _test_backend_validator_starter_budget() -> Dictionary:
	var validator = BackendValidatorScript.new()
	var report: Dictionary = validator.validate(
		_make_backend_validation_context(1)
	)
	var found_budget_error: bool = false
	for raw_error in report.get("errors", []):
		if "Starter collection cannot form a legal deck" in str(raw_error):
			found_budget_error = true
			break
	return _ok(
		not bool(report.get("valid", true)) and found_budget_error,
		"Backend validator must reject a player deck budget that cannot field the five-card starter collection."
	)

func _make_match_context_controller(
	encounter_records = null,
	default_region: Resource = null,
	default_ai: Resource = null,
	default_rules: Resource = null,
	default_budget: int = 30
):
	var rng := RandomNumberGenerator.new()
	rng.seed = 424242
	var controller = MatchContextControllerScript.new()
	controller.initialize(
		DefaultCardCatalog,
		rng,
		encounter_records,
		{
			"region_profile": default_region,
			"ai_profile": default_ai,
			"rule_set": default_rules,
			"deck_budget": default_budget,
			"min_level": 1,
			"max_level": 3,
		}
	)
	return controller


func _test_match_context_authored_precedence() -> Dictionary:
	var base_rules = RuleSetScript.new()
	base_rules.same_rule = true

	var region_rules = RuleSetScript.new()
	region_rules.plus_rule = true
	var region = RegionProfileScript.new()
	region.region_id = &"qa_region"
	region.display_name = "QA Region"
	region.rule_set = region_rules
	region.deck_budget = 22
	region.allow_rotate = false

	var opponent_rules = RuleSetScript.new()
	opponent_rules.combo_rule = true
	var opponent_ai = AIProfileScript.new()
	opponent_ai.display_name = "QA Context AI"
	var opponent = OpponentProfileScript.new()
	opponent.opponent_id = &"qa_context"
	opponent.display_name = "QA Context Opponent"
	opponent.region_profile = region
	opponent.ai_profile = opponent_ai
	opponent.rule_set_override = opponent_rules
	opponent.min_card_level = 2
	opponent.max_card_level = 4
	opponent.deck_budget_override = 27
	opponent.rematch_evolution_enabled = false

	var controller = _make_match_context_controller(
		null,
		DefaultRegionProfile,
		null,
		base_rules,
		30
	)
	controller.resolve(opponent)
	var summary: Dictionary = controller.configuration_summary()
	return _ok(
		controller.active_opponent_profile == opponent
		and controller.active_region_profile == region
		and controller.active_ai_profile == opponent_ai
		and controller.active_rule_set == opponent_rules
		and controller.active_deck_budget == 27
		and controller.active_min_level == 2
		and controller.active_max_level == 4
		and String(controller.active_opponent_id()) == "qa_context"
		and str(summary.get("rules", "")) == "Combo",
		"Match context must apply opponent region/defaults first, then explicit opponent rule and budget overrides."
	)


func _test_match_context_qa_override() -> Dictionary:
	var opponent = OpponentProfileScript.new()
	opponent.opponent_id = &"qa_context_override"
	opponent.display_name = "QA Context Override"
	opponent.deck_budget_override = 28
	opponent.min_card_level = 2
	opponent.max_card_level = 5
	opponent.rematch_evolution_enabled = false

	var qa_rules = RuleSetScript.new()
	qa_rules.same_rule = true
	qa_rules.plus_rule = true
	var qa_region = RegionProfileScript.new()
	qa_region.region_id = &"qa_override_region"
	qa_region.display_name = "QA Override Region"
	qa_region.deck_budget = 19
	qa_region.allow_rotate = true
	var qa_ai = AIProfileScript.new()
	qa_ai.display_name = "QA Override AI"
	var qa_profile = QAProfileScript.new()
	qa_profile.region_profile = qa_region
	qa_profile.ai_profile = qa_ai
	qa_profile.rule_set_override = qa_rules
	qa_profile.deck_budget_override = 21
	qa_profile.min_card_level = 4
	qa_profile.max_card_level = 6
	qa_profile.starting_owner = OWNER_OPPONENT
	qa_profile.hand_seed = 777

	var controller = _make_match_context_controller()
	controller.resolve(opponent)
	controller.set_qa_profile(qa_profile)
	var qa_ok: bool = (
		controller.has_qa_override()
		and controller.active_region_profile == qa_region
		and controller.active_ai_profile == qa_ai
		and controller.active_rule_set == qa_rules
		and controller.active_deck_budget == 21
		and controller.active_min_level == 4
		and controller.active_max_level == 6
		and controller.qa_forced_starting_owner == OWNER_OPPONENT
		and controller.qa_hand_seed == 777
		and controller.active_opponent_evolution.is_empty()
	)
	controller.set_qa_profile(null)
	var restore_ok: bool = (
		not controller.has_qa_override()
		and controller.active_deck_budget == 28
		and controller.active_min_level == 2
		and controller.active_max_level == 5
		and controller.qa_forced_starting_owner == OWNER_NONE
		and controller.qa_hand_seed == 0
	)
	return _ok(
		qa_ok and restore_ok,
		"QA match context must override the active experiment deterministically and restore authored opponent settings when cleared."
	)


func _test_match_context_rematch_evolution() -> Dictionary:
	var region = RegionProfileScript.new()
	region.region_id = &"qa_evolution_region"
	region.display_name = "QA Evolution Region"
	region.deck_budget = 20
	var opponent_ai = AIProfileScript.new()
	opponent_ai.display_name = "QA Evolution AI"
	opponent_ai.randomness = 2.0
	var opponent = OpponentProfileScript.new()
	opponent.opponent_id = &"qa_evolution"
	opponent.display_name = "QA Evolution Opponent"
	opponent.region_profile = region
	opponent.ai_profile = opponent_ai
	opponent.rematch_evolution_enabled = true
	opponent.rematch_win_thresholds = PackedInt32Array([1, 3, 6])
	opponent.rematch_budget_bonuses = PackedInt32Array([0, 1, 2, 3])
	opponent.adaptive_style_id = &"aggressive"

	var controller = _make_match_context_controller(
		MockMatchContextEncounterRecords.new(3)
	)
	controller.resolve(opponent)
	var evolution: Dictionary = controller.get_active_evolution_snapshot()
	return _ok(
		int(evolution.get("stage", 0)) == 2
		and int(evolution.get("budget_bonus", 0)) == 2
		and controller.active_deck_budget == 22
		and controller.active_ai_profile != opponent_ai
		and float(controller.active_ai_profile.get("randomness")) < 2.0,
		"Match context must fold persistent rematch evolution into the active deck budget and adapted AI when no QA override is active."
	)



func _test_runtime_state_event_feed() -> Dictionary:
	var controller = RuntimeStateControllerScript.new()
	controller.initialize({
		"backend_version": "qa",
		"event_capacity": 2,
	})
	controller.queue_gameplay_event(&"first", "First")
	controller.queue_gameplay_event(&"second", "Second", "detail", {"value": 2}, 1)
	controller.queue_gameplay_event(&"third", "Third")
	var pending: Array = controller.get_pending_gameplay_events()
	var first_kept: Dictionary = {}
	if pending.size() > 0:
		first_kept = pending[0]
	var popped: Dictionary = controller.pop_next_gameplay_event()
	return _ok(
		pending.size() == 2
		and str(first_kept.get("type", "")) == "second"
		and int(first_kept.get("payload", {}).get("value", 0)) == 2
		and str(popped.get("type", "")) == "second"
		and controller.get_pending_gameplay_events().size() == 1,
		"Runtime state controller must own the bounded public gameplay-event queue without changing FIFO semantics."
	)


func _test_runtime_state_card_snapshot() -> Dictionary:
	var controller = RuntimeStateControllerScript.new()
	controller.initialize({"backend_version": "qa"})
	var card = MockCard.new(&"runtime_rotate", 1, 2, 3, 4, 5)
	card.display_name = "Runtime Rotate"
	var snapshot: Dictionary = controller.runtime_card_snapshot(card, 1)
	var ranks: Array = snapshot.get("ranks", [])
	return _ok(
		String(snapshot.get("card_id", "")) == "runtime_rotate"
		and int(snapshot.get("rotation", -1)) == 1
		and ranks == [4, 1, 2, 3]
		and int(snapshot.get("deck_cost", 0)) == 5,
		"Runtime state card snapshots must preserve rotated rank order and stable public card metadata."
	)


func _test_runtime_state_hidden_hand() -> Dictionary:
	var session = SessionControllerScript.new()
	session.open_deck_setup(false)
	session.prepare_new_match()
	session.begin_dealing()
	session.complete_deal(OWNER_PLAYER)

	var rules = MockRuleSet.new()
	rules.open_rule = false
	var match_context = MockRuntimeMatchContext.new()
	match_context.active_rule_set = rules

	var player_cards: Array = []
	var opponent_cards: Array = []
	for index in range(5):
		player_cards.append(MockCard.new(
			StringName("player_%d" % index),
			1 + index,
			2,
			3,
			4,
			1
		))
		opponent_cards.append(MockCard.new(
			StringName("opponent_%d" % index),
			4,
			3,
			2,
			1 + index,
			1
		))

	var match_state = MatchScript.new()
	match_state.reset_match(
		player_cards,
		opponent_cards,
		OWNER_PLAYER,
		rules,
		null
	)

	var controller = RuntimeStateControllerScript.new()
	controller.initialize({
		"backend_version": "qa",
		"session": session,
		"match_context": match_context,
	})
	var snapshot: Dictionary = controller.get_runtime_ui_snapshot(
		match_state,
		1,
		4
	)
	var opponent_hand: Array = snapshot.get("opponent_hand", [])
	var all_hidden: bool = opponent_hand.size() == 5
	for card_snapshot in opponent_hand:
		all_hidden = all_hidden and bool(card_snapshot.get("hidden", false))
	return _ok(
		all_hidden
		and str(snapshot.get("phase_name", "")) == "select_card"
		and bool(snapshot.get("can_surrender", false))
		and String(snapshot.get("selected_card", {}).get("card_id", "")) == "player_1",
		"Runtime UI snapshots must hide closed-rule opponent cards while preserving selected-card and phase state."
	)

func _make_live_match_runtime_fixture() -> Dictionary:
	var player_cards: Array = []
	var opponent_cards: Array = []
	for index in range(5):
		player_cards.append(MockCard.new(
			StringName("live_player_%d" % index),
			1 + index,
			2,
			3,
			4,
			1
		))
		opponent_cards.append(MockCard.new(
			StringName("live_opponent_%d" % index),
			4,
			3,
			2,
			1 + index,
			1
		))

	var match_state = MatchScript.new()
	var ai = AIScript.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var session = SessionControllerScript.new()
	session.open_deck_setup(false)
	var flow = MatchFlowControllerScript.new()
	flow.initialize(match_state, ai, rng, session)

	var context = MockLiveMatchContext.new()
	context.qa_forced_starting_owner = OWNER_OPPONENT
	context.active_rule_set = MockRuleSet.new()
	context.active_region_profile = MockRegion.new()
	context.budgeted_hand = player_cards.duplicate()

	var runtime = LiveMatchControllerScript.new()
	runtime.initialize(match_state, flow, context, rng)
	var opponent_collection = MockLiveOpponentCollection.new(opponent_cards)
	return {
		"runtime": runtime,
		"match": match_state,
		"session": session,
		"context": context,
		"opponent_collection": opponent_collection,
		"player_cards": player_cards,
		"opponent_cards": opponent_cards,
	}


func _test_live_match_runtime_setup() -> Dictionary:
	var fixture: Dictionary = _make_live_match_runtime_fixture()
	var runtime = fixture.get("runtime")
	var session = fixture.get("session")
	var setup: Dictionary = runtime.prepare_new_match(
		[],
		fixture.get("opponent_collection")
	)
	return _ok(
		bool(setup.get("success", false))
		and int(setup.get("starting_owner", OWNER_NONE)) == OWNER_OPPONENT
		and runtime.get_starting_player_cards().size() == 5
		and runtime.get_starting_opponent_cards().size() == 5
		and runtime.selected_hand_index == 0
		and runtime.selected_cell_index == 4
		and session.phase == SessionControllerScript.PHASE_DEALING,
		"Live match runtime must own deterministic hand preparation, starting-owner choice, and initial selection state."
	)


func _test_live_match_runtime_selection() -> Dictionary:
	var fixture: Dictionary = _make_live_match_runtime_fixture()
	var runtime = fixture.get("runtime")
	var setup: Dictionary = runtime.prepare_new_match(
		[],
		fixture.get("opponent_collection")
	)
	if not bool(setup.get("success", false)):
		return _ok(false, "Live match runtime fixture failed to prepare a match.")

	runtime.move_hand_selection(3)
	runtime.move_hand_selection(10)
	var input = InputControllerScript.new()
	runtime.move_board_selection(InputControllerScript.ACTION_LEFT, input)
	runtime.move_board_selection(InputControllerScript.ACTION_UP, input)
	return _ok(
		runtime.selected_hand_index == 4
		and runtime.selected_cell_index == 0,
		"Live match runtime must clamp hand selection and own board-cursor navigation."
	)


func _test_live_match_runtime_deck_state() -> Dictionary:
	var fixture: Dictionary = _make_live_match_runtime_fixture()
	var runtime = fixture.get("runtime")
	var player_cards: Array = fixture.get("player_cards", [])
	runtime.set_active_player_deck(player_cards)
	var removed_id := StringName(player_cards[2].card_id)
	var filtered: Array = runtime.remove_card_from_active_deck(removed_id)
	var removed_still_present: bool = false
	for card in filtered:
		if card != null and String(card.card_id) == String(removed_id):
			removed_still_present = true
			break

	var opponent_cards: Array = fixture.get("opponent_cards", [])
	runtime.install_recovery_state(player_cards, opponent_cards)
	return _ok(
		filtered.size() == 4
		and not removed_still_present
		and runtime.get_active_player_deck().size() == 5
		and runtime.get_starting_player_cards().size() == 5
		and runtime.get_starting_opponent_cards().size() == 5,
		"Live match runtime must own active-deck filtering and deterministic recovery state without leaking scene-owned arrays."
	)

func _test_match_orchestrator_move_plan() -> Dictionary:
	var orchestrator = MatchOrchestratorScript.new()
	var card = MockCard.new(&"orchestrated", 4, 3, 2, 1)
	var flow := {
		"success": true,
		"hand_index": 2,
		"cell_index": 7,
		"played_card": card,
		"played_rotation": 3,
		"placement_rank_modifier": 2,
		"result": {"captured": []},
	}
	var plan: Dictionary = orchestrator.build_move_animation_plan(
		flow,
		OWNER_PLAYER
	)
	return _ok(
		bool(plan.get("valid", false))
		and int(plan.get("owner", OWNER_NONE)) == OWNER_PLAYER
		and int(plan.get("hand_index", -1)) == 2
		and int(plan.get("cell_index", -1)) == 7
		and plan.get("played_card") == card
		and int(plan.get("played_rotation", -1)) == 3
		and int(plan.get("placement_rank_modifier", -1)) == 2,
		"Match orchestration must preserve the deterministic placement payload handed off by match flow."
	)


func _test_match_orchestrator_capture_settle() -> Dictionary:
	var orchestrator = MatchOrchestratorScript.new()
	var plan: Dictionary = orchestrator.build_move_animation_plan(
		{
			"success": true,
			"result": {"captured": [1, 5]},
		},
		OWNER_OPPONENT
	)
	var captured: Array = plan.get("captured_cells", [])
	return _ok(
		bool(plan.get("requires_capture_settle", false))
		and captured == [1, 5]
		and int(plan.get("owner", OWNER_NONE)) == OWNER_OPPONENT,
		"Match orchestration must explicitly wait for capture presentation before handing the turn onward."
	)


func _test_match_orchestrator_reward_ids() -> Dictionary:
	var orchestrator = MatchOrchestratorScript.new()
	var normalized: PackedStringArray = orchestrator.normalize_reward_ids(
		[&"card_a", &"card_b", "card_c"]
	)
	return _ok(
		normalized == PackedStringArray(["card_a", "card_b", "card_c"])
		and orchestrator.move_failure_message({"reason": "occupied"}) == "That space is occupied."
		and orchestrator.move_failure_message({"reason": "other"}) == "Invalid move.",
		"Match orchestration must normalize reward candidates and own live move-failure presentation policy."
	)



func _test_persistence_match_outcome() -> Dictionary:
	var resolution = MockPersistenceMatchResolution.new()
	var competition = MockPersistenceCompetition.new()
	var context = MockPersistenceMatchContext.new()
	var controller = PersistenceControllerScript.new()
	controller.initialize({
		"match_resolution": resolution,
		"competition": competition,
		"match_context": context,
	})
	var event_types: Array[StringName] = []
	controller.gameplay_event_requested.connect(
		func(event_type, _title, _detail, _payload, _priority):
			event_types.append(StringName(event_type))
	)
	var payload: Dictionary = controller.record_match_outcome(
		{"player": 6, "opponent": 4},
		OWNER_PLAYER,
		&"board_complete",
		false,
		[],
		[],
		null
	)
	return _ok(
		bool(payload.get("success", false))
		and resolution.last_winner == OWNER_PLAYER
		and resolution.last_reason == &"board_complete"
		and competition.resolution_applied
		and int(payload.get("progression", {}).get("rank_after", 0)) == 4
		and bool(payload.get("competition", {}).get("round_advanced", false))
		and event_types == [&"duel_rank_up"],
		"Persistence controller must own persistent result bookkeeping, competition handoff, and rank-up event publication."
	)


func _test_persistence_reward_transfer() -> Dictionary:
	var resolution = MockPersistenceMatchResolution.new()
	resolution.transfer_result = {
		"success": true,
		"metadata_ok": true,
		"remove_from_decks": true,
	}
	var context = MockPersistenceMatchContext.new()
	var deck_setup = MockPersistenceDeckSetup.new()
	var live_match = MockPersistenceLiveMatch.new()
	var controller = PersistenceControllerScript.new()
	controller.initialize({
		"match_resolution": resolution,
		"match_context": context,
		"deck_setup": deck_setup,
		"live_match": live_match,
	})
	var card = MockCard.new(&"lost_persistence_card", 1, 2, 3, 4, 2)
	card.display_name = "Lost Persistence Card"
	var result: Dictionary = controller.commit_reward_transfer(
		card,
		OWNER_OPPONENT,
		MockQuantityStore.new()
	)
	return _ok(
		bool(result.get("success", false))
		and deck_setup.removed_ids == PackedStringArray(["lost_persistence_card"])
		and live_match.removed_ids == PackedStringArray(["lost_persistence_card"]),
		"Persistence controller must remove a permanently lost card from saved and active deck state after a committed transfer."
	)


func _test_persistence_checkpoint() -> Dictionary:
	var save_integrity = MockPersistenceSaveIntegrity.new()
	var journal = MockPersistenceJournal.new()
	var controller = PersistenceControllerScript.new()
	controller.initialize({
		"save_integrity": save_integrity,
		"card_catalog": RefCounted.new(),
		"collection_backend": RefCounted.new(),
		"progression": RefCounted.new(),
		"match_resolution_journal": journal,
		"player_deck_budget": 30,
	})
	var first: Dictionary = controller.checkpoint("qa_checkpoint")
	var second: Dictionary = controller.complete_reward_resolution()
	return _ok(
		bool(first.get("valid", false))
		and bool(second.get("valid", false))
		and save_integrity.reasons == ["qa_checkpoint", "reward_resolution_complete"]
		and journal.clear_count == 1,
		"Persistence controller must centralize save-integrity checkpoints and clear the resolution journal before the final reward checkpoint."
	)

func _composition_qa_callback() -> void:
	pass


func _composition_contract_fixture() -> Dictionary:
	var nodes: Dictionary = {}
	for key in CompositionRootScript.REQUIRED_NODE_KEYS:
		nodes[key] = self
	var callbacks: Dictionary = {}
	var callback := Callable(self, "_composition_qa_callback")
	for key in CompositionRootScript.REQUIRED_CALLBACK_KEYS:
		callbacks[key] = callback
	return {
		"nodes": nodes,
		"callbacks": callbacks,
	}


func _test_composition_contract_complete() -> Dictionary:
	var root = CompositionRootScript.new()
	var fixture: Dictionary = _composition_contract_fixture()
	var report: Dictionary = root.validate_contract(
		fixture.get("nodes", {}),
		fixture.get("callbacks", {})
	)
	var missing_nodes: PackedStringArray = report.get(
		"missing_nodes",
		PackedStringArray()
	)
	var missing_callbacks: PackedStringArray = report.get(
		"missing_callbacks",
		PackedStringArray()
	)
	return _ok(
		bool(report.get("valid", false))
		and missing_nodes.is_empty()
		and missing_callbacks.is_empty(),
		"The composition root should accept the complete scene/controller contract."
	)


func _test_composition_contract_guard() -> Dictionary:
	var root = CompositionRootScript.new()
	var fixture: Dictionary = _composition_contract_fixture()
	var nodes: Dictionary = fixture.get("nodes", {}).duplicate()
	var callbacks: Dictionary = fixture.get("callbacks", {}).duplicate()
	nodes.erase("root")
	callbacks.erase("close_game")
	var report: Dictionary = root.validate_contract(nodes, callbacks)
	var missing_nodes: PackedStringArray = report.get(
		"missing_nodes",
		PackedStringArray()
	)
	var missing_callbacks: PackedStringArray = report.get(
		"missing_callbacks",
		PackedStringArray()
	)
	return _ok(
		not bool(report.get("valid", true))
		and missing_nodes.has("root")
		and missing_callbacks.has("close_game"),
		"Composition must fail fast when a required node or callback is missing."
	)


func _test_composition_boundary_maps() -> Dictionary:
	var root = CompositionRootScript.new()
	var request: Dictionary = root.build_bootstrap_request({
		"card_catalog": self,
		"rule_set": self,
		"region_profile": self,
		"opponent_registry": self,
		"acquisition_policy": self,
		"acquisition_registry": self,
		"player_deck_budget": 27,
		"rogue_value": 999,
	})
	var services: Dictionary = root.extract_services({
		"collection_backend": self,
		"progression": self,
		"state_api": self,
		"rogue_service": self,
	})
	return _ok(
		int(request.get("player_deck_budget", 0)) == 27
		and not request.has("rogue_value")
		and services.get("collection_backend") == self
		and services.get("progression") == self
		and services.get("state_api") == self
		and not services.has("rogue_service")
		and services.size() == CompositionRootScript.SERVICE_KEYS.size(),
		"Composition should expose only the authored bootstrap/service boundary."
	)

func _test_composition_activation_phase() -> Dictionary:
	var root = CompositionRootScript.new()
	var persistence = MockCompositionPersistence.new()
	root.activate_after_install({
		"success": false,
		"components": {"persistence": persistence},
	})
	var stayed_idle: bool = persistence.reasons.is_empty()
	var activation_report: Dictionary = root.activate_after_install({
		"success": true,
		"components": {"persistence": persistence},
	})
	return _ok(
		stayed_idle
		and persistence.reasons == ["boot"]
		and bool(activation_report.get("valid", false)),
		"Composition must not run effectful boot work until the host has installed the composed controller graph."
	)

