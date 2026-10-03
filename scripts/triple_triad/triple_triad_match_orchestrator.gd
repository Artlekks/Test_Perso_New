extends RefCounted

const SessionControllerScript = preload(
	"res://scripts/triple_triad/triple_triad_session_controller.gd"
)

# Scene-level live-match orchestrator for Triple Triad.
# Owns the asynchronous sequence that joins deterministic match flow to
# presentation: deal -> placement -> capture settle -> turn handoff -> result
# transition. It deliberately does not own persistence, progression, reward
# transfer, input policy, or card-rule resolution.

const OWNER_NONE := 0
const OWNER_PLAYER := 1
const OWNER_OPPONENT := 2
const PHASE_DEALING := SessionControllerScript.PHASE_DEALING

const HAND_STEP_Y := 47.0
const CAPTURE_SETTLE_SECONDS := 0.24
const RESULT_FADE_IN_SECONDS := 0.24
const RESULT_FADE_OUT_SECONDS := 0.30

var _match_flow = null
var _live_match = null
var _presentation = null
var _ui_flow = null
var _animation_director = null
var _ai_timer: Timer = null
var _session = null
var _match_context = null
var _competition = null
var _match_resolution = null
var _message_label: Label = null
var _transition_fade: ColorRect = null
var _root: Control = null
var _ai_delay_seconds: float = 0.75

var _is_open: Callable = Callable()
var _refresh_views: Callable = Callable()
var _refresh_ui_flow: Callable = Callable()
var _finish_match: Callable = Callable()
var _close_game: Callable = Callable()


func initialize(config: Dictionary) -> void:
	_match_flow = config.get("match_flow")
	_live_match = config.get("live_match")
	_presentation = config.get("presentation")
	_ui_flow = config.get("ui_flow")
	_animation_director = config.get("animation_director")
	_ai_timer = config.get("ai_timer")
	_session = config.get("session")
	_match_context = config.get("match_context")
	_competition = config.get("competition")
	_match_resolution = config.get("match_resolution")
	_message_label = config.get("message_label")
	_transition_fade = config.get("transition_fade")
	_root = config.get("root")
	_ai_delay_seconds = float(config.get("ai_delay_seconds", 0.75))
	_is_open = config.get("is_open", Callable())
	_refresh_views = config.get("refresh_views", Callable())
	_refresh_ui_flow = config.get("refresh_ui_flow", Callable())
	_finish_match = config.get("finish_match", Callable())
	_close_game = config.get("close_game", Callable())


func is_ready() -> bool:
	return (
		_match_flow != null
		and _live_match != null
		and _presentation != null
		and _ui_flow != null
		and _animation_director != null
		and _ai_timer != null
		and _session != null
		and _match_context != null
		and _competition != null
		and _match_resolution != null
		and _message_label != null
		and _transition_fade != null
		and _root != null
		and _is_open.is_valid()
		and _refresh_views.is_valid()
		and _refresh_ui_flow.is_valid()
		and _finish_match.is_valid()
		and _close_game.is_valid()
	)


func start_new_match(
	player_cards_override: Array,
	opponent_collection_backend
) -> Dictionary:
	if not is_ready():
		return {"success": false, "reason": "orchestrator_not_initialized"}

	_ai_timer.stop()
	_ui_flow.prepare_new_match()
	_competition.clear_pending_change()

	var setup: Dictionary = _live_match.prepare_new_match(
		player_cards_override,
		opponent_collection_backend
	)
	if not bool(setup.get("success", false)):
		_handle_setup_failure(str(setup.get("reason", "unknown")))
		return setup

	_refresh_views.call()
	_run_deal_sequence(int(setup.get("starting_owner", OWNER_PLAYER)))
	return setup


func try_player_move() -> void:
	if not is_ready():
		return
	var flow: Dictionary = _match_flow.commit_player_move(
		_live_match.selected_hand_index,
		_live_match.selected_cell_index
	)
	if not bool(flow.get("success", false)):
		_message_label.text = move_failure_message(flow)
		return

	_live_match.apply_player_move_result(flow)
	_refresh_ui_flow.call()
	_animate_player_move(flow)


func on_ai_timer_timeout() -> void:
	if not is_ready() or not _match_flow.can_run_ai_timer():
		return
	run_ai_turn()


func run_ai_turn() -> void:
	if not is_ready():
		return
	var flow: Dictionary = _match_flow.commit_ai_move(
		_match_context.active_ai_profile
	)
	if not bool(flow.get("success", false)):
		if bool(flow.get("finish", false)):
			_finish_match.call()
		return

	_refresh_ui_flow.call()
	_animate_ai_move(flow)


func schedule_ai() -> void:
	if _ai_timer == null:
		return
	_ai_timer.start(maxf(_ai_delay_seconds, 0.01))


func begin_result_transition(opponent_collection_backend) -> void:
	if not is_ready():
		return
	var flow_result: Dictionary = _match_flow.begin_result_transition()
	if not bool(flow_result.get("accepted", false)):
		return
	_ui_flow.begin_result_transition_ui()
	_run_result_transition(
		int(flow_result.get("winner", OWNER_NONE)),
		opponent_collection_backend
	)


func build_move_animation_plan(flow: Dictionary, owner: int) -> Dictionary:
	if not bool(flow.get("success", false)):
		return {"valid": false, "owner": owner}
	var result: Dictionary = flow.get("result", {})
	var captured_cells: Array = result.get("captured", [])
	return {
		"valid": true,
		"owner": owner,
		"hand_index": int(flow.get("hand_index", 0)),
		"cell_index": int(flow.get("cell_index", 0)),
		"played_card": flow.get("played_card"),
		"played_rotation": int(flow.get("played_rotation", 0)),
		"placement_rank_modifier": int(flow.get("placement_rank_modifier", 0)),
		"result": result,
		"captured_cells": captured_cells.duplicate(),
		"requires_capture_settle": not captured_cells.is_empty(),
	}


func move_failure_message(flow: Dictionary) -> String:
	if str(flow.get("reason", "")) == "occupied":
		return "That space is occupied."
	return "Invalid move."


func normalize_reward_ids(raw_ids) -> PackedStringArray:
	var result := PackedStringArray()
	if raw_ids is PackedStringArray or raw_ids is Array:
		for raw_id in raw_ids:
			result.append(str(raw_id))
	return result


func _run_deal_sequence(starting_owner: int) -> void:
	await _animation_director.deal_hands(
		_presentation.get_player_views(),
		_presentation.get_opponent_views(),
		HAND_STEP_Y
	)
	if not bool(_is_open.call()) or _session.phase != PHASE_DEALING:
		return
	var flow_result: Dictionary = _match_flow.complete_deal(starting_owner)
	if not bool(flow_result.get("success", false)):
		return
	_message_label.text = ""
	_refresh_views.call()
	if bool(flow_result.get("schedule_ai", false)):
		schedule_ai()


func _animate_player_move(flow: Dictionary) -> void:
	var plan: Dictionary = build_move_animation_plan(flow, OWNER_PLAYER)
	if not bool(plan.get("valid", false)):
		return
	await _animation_director.animate_placement(
		_root,
		_presentation.get_player_view(int(plan.get("hand_index", 0))),
		_presentation.get_board_view(int(plan.get("cell_index", 0))),
		plan.get("played_card"),
		OWNER_PLAYER,
		int(plan.get("played_rotation", 0)),
		int(plan.get("placement_rank_modifier", 0))
	)
	if not bool(_is_open.call()):
		return

	var result: Dictionary = plan.get("result", {})
	_message_label.text = _live_match.capture_message(result)
	var captured_cells: Array = plan.get("captured_cells", [])
	_refresh_views.call(captured_cells)
	if bool(plan.get("requires_capture_settle", false)):
		await _animation_director.wait_for_settle(CAPTURE_SETTLE_SECONDS)
		if not bool(_is_open.call()):
			return

	match _match_flow.complete_player_move(result):
		&"finish":
			_finish_match.call()
		&"schedule_ai":
			_refresh_views.call()
			schedule_ai()


func _animate_ai_move(flow: Dictionary) -> void:
	var plan: Dictionary = build_move_animation_plan(flow, OWNER_OPPONENT)
	if not bool(plan.get("valid", false)):
		return
	await _animation_director.animate_placement(
		_root,
		_presentation.get_opponent_view(int(plan.get("hand_index", 0))),
		_presentation.get_board_view(int(plan.get("cell_index", 0))),
		plan.get("played_card"),
		OWNER_OPPONENT,
		int(plan.get("played_rotation", 0)),
		int(plan.get("placement_rank_modifier", 0))
	)
	if not bool(_is_open.call()):
		return

	var result: Dictionary = plan.get("result", {})
	_message_label.text = _live_match.capture_message(result)
	var captured_cells: Array = plan.get("captured_cells", [])
	_refresh_views.call(captured_cells)
	if bool(plan.get("requires_capture_settle", false)):
		await _animation_director.wait_for_settle(CAPTURE_SETTLE_SECONDS)
		if not bool(_is_open.call()):
			return

	var next_step: Dictionary = _match_flow.complete_ai_move(
		result,
		_live_match.selected_hand_index,
		_live_match.selected_cell_index
	)
	if StringName(next_step.get("action", &"")) == &"finish":
		_finish_match.call()
		return
	_live_match.apply_ai_move_result(next_step)
	_refresh_views.call()


func _run_result_transition(
	winner: int,
	opponent_collection_backend
) -> void:
	await _animation_director.fade_to_cover(
		_transition_fade,
		RESULT_FADE_IN_SECONDS
	)
	if not bool(_is_open.call()):
		return

	_ui_flow.hide_result_overlay()
	var destination: StringName = _match_flow.prepare_result_destination(winner)
	if destination == &"replay":
		start_new_match(
			_live_match.get_active_player_deck(),
			opponent_collection_backend
		)
		await _animation_director.fade_from_cover(
			_transition_fade,
			RESULT_FADE_OUT_SECONDS
		)
		return
	if destination != &"reward":
		return

	var reward_presentation: Dictionary = (
		_match_resolution.prepare_reward_presentation(
			winner,
			_match_context.active_opponent_profile,
			_match_context.active_opponent_id(),
			_live_match.get_starting_player_cards(),
			_live_match.get_starting_opponent_cards(),
			opponent_collection_backend
		)
	)
	var eligible_reward_ids: PackedStringArray = normalize_reward_ids(
		reward_presentation.get("eligible_reward_ids", PackedStringArray())
	)
	_ui_flow.open_reward(
		_live_match.get_starting_opponent_cards(),
		_live_match.get_starting_player_cards(),
		winner,
		true,
		int(reward_presentation.get("opponent_take_index", -1)),
		eligible_reward_ids,
		true
	)
	_refresh_ui_flow.call()

	await _animation_director.fade_from_cover(
		_transition_fade,
		RESULT_FADE_OUT_SECONDS
	)


func _handle_setup_failure(reason: String) -> void:
	if reason == "invalid_opponent_deck":
		push_error(
			"TripleTriadGame: opponent %s has no legal persistent deck."
			% String(_match_context.active_opponent_id())
		)
		_message_label.text = "Opponent deck is invalid."
	else:
		push_error("TripleTriadGame: live match setup failed: %s" % reason)
	_close_game.call()
