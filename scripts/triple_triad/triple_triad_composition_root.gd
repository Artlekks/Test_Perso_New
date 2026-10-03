extends RefCounted
class_name TripleTriadCompositionRoot

const MatchScript = preload("res://scripts/triple_triad/triple_triad_match.gd")
const AIScript = preload("res://scripts/triple_triad/triple_triad_ai.gd")
const StakePolicyScript = preload("res://scripts/triple_triad/triple_triad_stake_policy.gd")
const MatchResolutionJournalScript = preload("res://scripts/triple_triad/triple_triad_match_resolution_journal.gd")
const SessionControllerScript = preload("res://scripts/triple_triad/triple_triad_session_controller.gd")
const MatchFlowControllerScript = preload("res://scripts/triple_triad/triple_triad_match_flow_controller.gd")
const MatchResolutionControllerScript = preload("res://scripts/triple_triad/triple_triad_match_resolution_controller.gd")
const PresentationControllerScript = preload("res://scripts/triple_triad/triple_triad_presentation_controller.gd")
const InputControllerScript = preload("res://scripts/triple_triad/triple_triad_input_controller.gd")
const UIFlowControllerScript = preload("res://scripts/triple_triad/triple_triad_ui_flow_controller.gd")
const WorldGatewayScript = preload("res://scripts/triple_triad/triple_triad_world_gateway.gd")
const CompetitionControllerScript = preload("res://scripts/triple_triad/triple_triad_competition_controller.gd")
const RuntimeRecoveryControllerScript = preload("res://scripts/triple_triad/triple_triad_runtime_recovery_controller.gd")
const BackendBootstrapScript = preload("res://scripts/triple_triad/triple_triad_backend_bootstrap.gd")
const DeveloperToolsControllerScript = preload("res://scripts/triple_triad/triple_triad_developer_tools_controller.gd")
const MatchContextControllerScript = preload("res://scripts/triple_triad/triple_triad_match_context_controller.gd")
const RuntimeStateControllerScript = preload("res://scripts/triple_triad/triple_triad_runtime_state_controller.gd")
const LiveMatchControllerScript = preload("res://scripts/triple_triad/triple_triad_live_match_controller.gd")
const MatchOrchestratorScript = preload("res://scripts/triple_triad/triple_triad_match_orchestrator.gd")
const PersistenceControllerScript = preload("res://scripts/triple_triad/triple_triad_persistence_controller.gd")
const DefaultEconomyPolicy = preload("res://data/triple_triad/economy/default_economy_policy.tres")
const DefaultAcquisitionPolicy = preload("res://data/triple_triad/acquisition/default_acquisition_policy.tres")

const REQUIRED_NODE_KEYS := [
	"root",
	"backdrop",
	"grid_artwork",
	"opponent_hand_container",
	"board_container",
	"player_hand_container",
	"opponent_score_label",
	"player_score_label",
	"turn_label",
	"message_label",
	"help_label",
	"info_panel",
	"info_label",
	"selection_arrow",
	"turn_arrow",
	"result_label",
	"reward_view",
	"transition_fade",
	"animation_director",
	"ai_timer",
	"debug_menu",
	"deck_setup",
]

const REQUIRED_CALLBACK_KEYS := [
	"is_backend_ready",
	"is_card_game_unlocked",
	"get_player_snapshot",
	"get_acquisition_snapshot",
	"get_collection_completion_snapshot",
	"get_runtime_recovery_snapshot",
	"get_backend_health",
	"get_global_triple_triad_snapshot",
	"get_pending_gameplay_events",
	"open_active_competition_match",
	"reconcile_runtime_state",
	"queue_gameplay_event",
	"publish_backend_state_change",
	"invalidate_state_api",
	"on_ai_timer_timeout",
	"on_reward_selected",
	"on_reward_completed",
	"on_qa_profile_apply_requested",
	"on_deck_confirmed",
	"on_deck_cancelled",
	"on_runtime_gameplay_event_queued",
	"on_runtime_backend_state_changed",
	"on_runtime_world_progression_changed",
	"on_acquisition_bundle_claimed",
	"on_card_game_unlock_changed",
	"on_competition_state_changed",
	"on_persistence_card_reward_selected",
	"is_open",
	"refresh_views",
	"refresh_ui_flow",
	"finish_match",
	"close_game",
]

const SERVICE_KEYS := [
	"world_acquisition_catalog",
	"save_integrity",
	"collection_backend",
	"acquisition_tracker",
	"acquisition_service",
	"progression",
	"world_reward_ledger",
	"encounter_records",
	"competition_service",
	"completion_tracker",
	"world_progression_director",
	"card_economy",
	"state_api",
]


func validate_contract(nodes: Dictionary, callbacks: Dictionary) -> Dictionary:
	var missing_nodes := PackedStringArray()
	for key in REQUIRED_NODE_KEYS:
		if not nodes.has(key) or nodes.get(key) == null:
			missing_nodes.append(key)

	var missing_callbacks := PackedStringArray()
	for key in REQUIRED_CALLBACK_KEYS:
		if not callbacks.has(key):
			missing_callbacks.append(key)
			continue
		var callback = callbacks.get(key)
		if typeof(callback) != TYPE_CALLABLE or not callback.is_valid():
			missing_callbacks.append(key)

	return {
		"valid": missing_nodes.is_empty() and missing_callbacks.is_empty(),
		"missing_nodes": missing_nodes,
		"missing_callbacks": missing_callbacks,
	}


func build_bootstrap_request(config: Dictionary) -> Dictionary:
	return {
		"card_catalog": config.get("card_catalog"),
		"rule_set": config.get("rule_set"),
		"region_profile": config.get("region_profile"),
		"opponent_registry": config.get("opponent_registry"),
		"acquisition_policy": config.get("acquisition_policy"),
		"acquisition_registry": config.get("acquisition_registry"),
		"player_deck_budget": int(config.get("player_deck_budget", 30)),
	}


func extract_services(raw_services: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for key in SERVICE_KEYS:
		result[key] = raw_services.get(key)
	return result


func compose(
	host: Node,
	config: Dictionary,
	nodes: Dictionary,
	callbacks: Dictionary
) -> Dictionary:
	var contract: Dictionary = validate_contract(nodes, callbacks)
	if not bool(contract.get("valid", false)):
		var contract_errors := PackedStringArray()
		for node_key in contract.get("missing_nodes", PackedStringArray()):
			contract_errors.append("Missing scene node dependency: %s" % str(node_key))
		for callback_key in contract.get("missing_callbacks", PackedStringArray()):
			contract_errors.append("Missing composition callback: %s" % str(callback_key))
		return {
			"success": false,
			"errors": contract_errors,
			"warnings": PackedStringArray(),
			"components": {},
			"services": {},
			"runtime_recovery": {},
		}

	var match_state = MatchScript.new()
	var ai = AIScript.new()
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var session = SessionControllerScript.new()
	var match_flow = MatchFlowControllerScript.new()
	var presentation = PresentationControllerScript.new()
	var input_controller = InputControllerScript.new()
	var ui_flow = UIFlowControllerScript.new()
	var world_gateway = WorldGatewayScript.new()
	var competition = CompetitionControllerScript.new()
	var runtime_recovery = RuntimeRecoveryControllerScript.new()
	var match_resolution_journal = MatchResolutionJournalScript.new()
	var match_resolution = MatchResolutionControllerScript.new()
	var backend_bootstrap = BackendBootstrapScript.new()
	var developer_tools = DeveloperToolsControllerScript.new()
	var match_context = MatchContextControllerScript.new()
	var runtime_state = RuntimeStateControllerScript.new()
	var live_match = LiveMatchControllerScript.new()
	var match_orchestrator = MatchOrchestratorScript.new()
	var persistence = PersistenceControllerScript.new()
	var stake_policy = StakePolicyScript.new()

	var backend_version: String = str(config.get("backend_version", ""))
	runtime_state.initialize({
		"backend_version": backend_version,
		"developer_tools": developer_tools,
		"session": session,
		"match_context": match_context,
		"presentation": presentation,
		"event_capacity": int(config.get("event_capacity", 32)),
	})
	developer_tools.initialize(
		host,
		config.get("card_catalog"),
		config.get("opponent_registry"),
		backend_version,
		{
			&"is_backend_ready": callbacks["is_backend_ready"],
			&"is_card_game_unlocked": callbacks["is_card_game_unlocked"],
			&"get_player_snapshot": callbacks["get_player_snapshot"],
			&"get_acquisition_snapshot": callbacks["get_acquisition_snapshot"],
			&"get_collection_completion_snapshot": callbacks["get_collection_completion_snapshot"],
			&"get_runtime_recovery_snapshot": callbacks["get_runtime_recovery_snapshot"],
			&"get_backend_health": callbacks["get_backend_health"],
			&"get_global_triple_triad_snapshot": callbacks["get_global_triple_triad_snapshot"],
			&"get_pending_gameplay_events": callbacks["get_pending_gameplay_events"],
			&"open_active_competition_match": callbacks["open_active_competition_match"],
			&"reconcile_runtime_state": callbacks["reconcile_runtime_state"],
		}
	)

	ui_flow.initialize({
		"root": nodes["root"],
		"backdrop": nodes["backdrop"],
		"grid_artwork": nodes["grid_artwork"],
		"opponent_score_digits": nodes["opponent_score_label"],
		"player_score_digits": nodes["player_score_label"],
		"turn_label": nodes["turn_label"],
		"message_label": nodes["message_label"],
		"help_label": nodes["help_label"],
		"info_panel": nodes["info_panel"],
		"info_label": nodes["info_label"],
		"selection_arrow": nodes["selection_arrow"],
		"turn_arrow": nodes["turn_arrow"],
		"result_label": nodes["result_label"],
		"reward_view": nodes["reward_view"],
		"transition_fade": nodes["transition_fade"],
		"animation_director": nodes["animation_director"],
		"debug_menu": nodes["debug_menu"],
		"deck_setup": nodes["deck_setup"],
		"player_hand_container": nodes["player_hand_container"],
	})
	ui_flow.prepare_closed_state()
	match_flow.initialize(match_state, ai, rng, session)
	match_resolution_journal.initialize()
	presentation.initialize(
		nodes["root"],
		nodes["opponent_hand_container"],
		nodes["board_container"],
		nodes["player_hand_container"]
	)

	_connect_once(nodes["ai_timer"].timeout, callbacks["on_ai_timer_timeout"])
	_connect_once(nodes["reward_view"].reward_selected, callbacks["on_reward_selected"])
	_connect_once(nodes["reward_view"].completed, callbacks["on_reward_completed"])
	_connect_once(nodes["debug_menu"].apply_requested, callbacks["on_qa_profile_apply_requested"])
	_connect_once(nodes["deck_setup"].deck_confirmed, callbacks["on_deck_confirmed"])
	_connect_once(nodes["deck_setup"].cancelled, callbacks["on_deck_cancelled"])

	var bootstrap_result: Dictionary = backend_bootstrap.bootstrap(
		build_bootstrap_request(config)
	)
	var services: Dictionary = extract_services(
		bootstrap_result.get("services", {})
	)
	var errors := PackedStringArray()
	for raw_error in bootstrap_result.get("errors", []):
		errors.append(str(raw_error))
	var warnings := PackedStringArray()
	for raw_warning in bootstrap_result.get("warnings", []):
		warnings.append(str(raw_warning))

	var components := {
		"match": match_state,
		"ai": ai,
		"rng": rng,
		"session": session,
		"match_flow": match_flow,
		"presentation": presentation,
		"input_controller": input_controller,
		"ui_flow": ui_flow,
		"world_gateway": world_gateway,
		"competition": competition,
		"runtime_recovery": runtime_recovery,
		"match_resolution_journal": match_resolution_journal,
		"match_resolution": match_resolution,
		"backend_bootstrap": backend_bootstrap,
		"developer_tools": developer_tools,
		"match_context": match_context,
		"runtime_state": runtime_state,
		"live_match": live_match,
		"match_orchestrator": match_orchestrator,
		"persistence": persistence,
		"stake_policy": stake_policy,
	}

	if not bool(bootstrap_result.get("success", false)):
		return {
			"success": false,
			"errors": errors,
			"warnings": warnings,
			"components": components,
			"services": services,
			"runtime_recovery": {},
		}

	match_context.initialize(
		config.get("card_catalog"),
		rng,
		services["encounter_records"],
		{
			"region_profile": config.get("region_profile"),
			"ai_profile": config.get("ai_profile"),
			"rule_set": config.get("rule_set"),
			"deck_budget": int(config.get("deck_budget", 30)),
			"min_level": int(config.get("prototype_min_level", 1)),
			"max_level": int(config.get("prototype_max_level", 3)),
		}
	)
	live_match.initialize(match_state, match_flow, match_context, rng)

	world_gateway.initialize(
		config.get("card_catalog"),
		services["acquisition_service"],
		services["world_acquisition_catalog"],
		services["world_reward_ledger"],
		services["collection_backend"],
		services["progression"],
		services["encounter_records"],
		config.get("opponent_registry"),
		rng,
		int(config.get("player_card_rank", 1))
	)
	_connect_once(world_gateway.acquisition_completed, callbacks["on_acquisition_bundle_claimed"])
	_connect_once(world_gateway.card_game_unlock_changed, callbacks["on_card_game_unlock_changed"])
	_connect_once(world_gateway.gameplay_event_requested, callbacks["queue_gameplay_event"])
	_connect_once(world_gateway.backend_state_change_requested, callbacks["publish_backend_state_change"])

	match_resolution.initialize(
		config.get("card_catalog"),
		services["collection_backend"],
		services["progression"],
		services["encounter_records"],
		services["competition_service"],
		services["card_economy"],
		services["acquisition_tracker"],
		match_resolution_journal,
		stake_policy,
		DefaultEconomyPolicy,
		DefaultAcquisitionPolicy
	)

	competition.initialize(
		services["competition_service"],
		config.get("card_catalog"),
		services["collection_backend"],
		services["progression"],
		services["encounter_records"],
		config.get("acquisition_policy"),
		world_gateway,
		services["world_reward_ledger"],
		config.get("opponent_registry"),
		int(config.get("player_card_rank", 1))
	)
	_connect_once(competition.competition_state_changed, callbacks["on_competition_state_changed"])
	_connect_once(competition.gameplay_event_requested, callbacks["queue_gameplay_event"])
	_connect_once(competition.backend_state_change_requested, callbacks["publish_backend_state_change"])

	persistence.initialize({
		"save_integrity": services["save_integrity"],
		"card_catalog": config.get("card_catalog"),
		"collection_backend": services["collection_backend"],
		"progression": services["progression"],
		"match_resolution": match_resolution,
		"match_resolution_journal": match_resolution_journal,
		"competition": competition,
		"deck_setup": nodes["deck_setup"],
		"live_match": live_match,
		"match_context": match_context,
		"acquisition_policy": config.get("acquisition_policy"),
		"player_deck_budget": int(config.get("player_deck_budget", 30)),
	})
	_connect_once(world_gateway.save_checkpoint_requested, persistence.checkpoint)
	_connect_once(services["completion_tracker"].milestone_reached, persistence.on_collection_milestone_reached)
	_connect_once(services["completion_tracker"].collection_completed, persistence.on_collection_completed)
	_connect_once(persistence.gameplay_event_requested, callbacks["queue_gameplay_event"])
	_connect_once(persistence.backend_state_change_requested, callbacks["publish_backend_state_change"])
	_connect_once(persistence.state_api_invalidation_requested, callbacks["invalidate_state_api"])
	_connect_once(persistence.card_reward_selected, callbacks["on_persistence_card_reward_selected"])

	match_orchestrator.initialize({
		"match_flow": match_flow,
		"live_match": live_match,
		"presentation": presentation,
		"ui_flow": ui_flow,
		"animation_director": nodes["animation_director"],
		"ai_timer": nodes["ai_timer"],
		"session": session,
		"match_context": match_context,
		"competition": competition,
		"match_resolution": match_resolution,
		"message_label": nodes["message_label"],
		"transition_fade": nodes["transition_fade"],
		"root": nodes["root"],
		"ai_delay_seconds": float(config.get("ai_delay_seconds", 0.75)),
		"is_open": callbacks["is_open"],
		"refresh_views": callbacks["refresh_views"],
		"refresh_ui_flow": callbacks["refresh_ui_flow"],
		"finish_match": callbacks["finish_match"],
		"close_game": callbacks["close_game"],
	})

	runtime_recovery.initialize(
		competition,
		config.get("card_catalog"),
		world_gateway,
		services["world_reward_ledger"],
		match_resolution,
		match_resolution_journal,
		nodes["deck_setup"],
		config.get("opponent_registry")
	)
	_connect_once(runtime_recovery.gameplay_event_requested, callbacks["queue_gameplay_event"])
	_connect_once(runtime_recovery.checkpoint_requested, persistence.checkpoint)
	_connect_once(runtime_recovery.backend_state_change_requested, callbacks["publish_backend_state_change"])

	runtime_state.initialize({
		"backend_version": backend_version,
		"state_api": services["state_api"],
		"completion_tracker": services["completion_tracker"],
		"world_progression_director": services["world_progression_director"],
		"world_gateway": world_gateway,
		"competition": competition,
		"runtime_recovery": runtime_recovery,
		"developer_tools": developer_tools,
		"session": session,
		"match_context": match_context,
		"presentation": presentation,
		"save_integrity": services["save_integrity"],
		"collection_backend": services["collection_backend"],
		"match_resolution": match_resolution,
		"encounter_records": services["encounter_records"],
		"event_capacity": int(config.get("event_capacity", 32)),
	})
	_connect_once(runtime_state.gameplay_event_queued, callbacks["on_runtime_gameplay_event_queued"])
	_connect_once(runtime_state.backend_state_changed, callbacks["on_runtime_backend_state_changed"])
	_connect_once(runtime_state.world_progression_changed, callbacks["on_runtime_world_progression_changed"])

	return {
		"success": true,
		"errors": errors,
		"warnings": warnings,
		"components": components,
		"services": services,
		"runtime_recovery": {},
	}


## Phase two of composition. Call only after the host has installed every
## component returned by compose(). This keeps compose() free of callbacks that
## can re-enter the host while its controller references are still null.
func activate_after_install(composition_result: Dictionary) -> Dictionary:
	if not bool(composition_result.get("success", false)):
		return {}
	var components: Dictionary = composition_result.get("components", {})
	var persistence = components.get("persistence")
	if persistence == null:
		return {}
	return persistence.checkpoint("boot")


func _connect_once(signal_value: Signal, callback: Callable) -> void:
	if not callback.is_valid():
		return
	if not signal_value.is_connected(callback):
		signal_value.connect(callback)
