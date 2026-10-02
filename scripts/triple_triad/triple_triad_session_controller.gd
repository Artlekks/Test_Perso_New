extends RefCounted

# Pure session-state machine for the Triple Triad scene coordinator.
# It deliberately owns no UI nodes, save services, match rules, or animation.
# TripleTriadGame performs side effects; this object owns lifecycle state.

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
const PHASE_SURRENDER_CONFIRM := 9

var phase: int = PHASE_CLOSED
var previous_pause: bool = false
var match_started: bool = false
var surrendered: bool = false
var result_reason: StringName = &""
var result_winner: int = OWNER_NONE
var round_number: int = 1
var surrender_resume_phase: int = PHASE_CLOSED


func is_open() -> bool:
	return phase != PHASE_CLOSED


func open_deck_setup(was_paused: bool) -> void:
	previous_pause = was_paused
	round_number = 1
	surrender_resume_phase = PHASE_CLOSED
	phase = PHASE_DECK_SETUP


func close_session() -> void:
	match_started = false
	surrendered = false
	result_reason = &""
	surrender_resume_phase = PHASE_CLOSED
	phase = PHASE_CLOSED


func prepare_new_match() -> void:
	result_winner = OWNER_NONE
	result_reason = &""
	surrendered = false
	match_started = false
	surrender_resume_phase = PHASE_CLOSED


func begin_dealing() -> void:
	phase = PHASE_DEALING


func complete_deal(starting_owner: int) -> void:
	match_started = true
	phase = PHASE_SELECT_CARD if starting_owner == OWNER_PLAYER else PHASE_AI


func begin_player_cell_selection() -> bool:
	if phase != PHASE_SELECT_CARD:
		return false
	phase = PHASE_SELECT_CELL
	return true


func cancel_player_cell_selection() -> bool:
	if phase != PHASE_SELECT_CELL:
		return false
	phase = PHASE_SELECT_CARD
	return true


func begin_animation() -> void:
	phase = PHASE_ANIMATING


func begin_ai_turn() -> void:
	phase = PHASE_AI


func begin_player_turn() -> void:
	phase = PHASE_SELECT_CARD


func request_surrender() -> bool:
	if not match_started:
		return false
	if phase not in [PHASE_SELECT_CARD, PHASE_AI]:
		return false
	surrender_resume_phase = phase
	phase = PHASE_SURRENDER_CONFIRM
	return true


func confirm_surrender() -> void:
	surrender_resume_phase = PHASE_CLOSED
	surrendered = true


func cancel_surrender() -> int:
	var resume_phase: int = surrender_resume_phase
	surrender_resume_phase = PHASE_CLOSED
	if resume_phase not in [PHASE_SELECT_CARD, PHASE_AI]:
		resume_phase = PHASE_SELECT_CARD
	phase = resume_phase
	return resume_phase


func finish_match(winner: int, reason: StringName) -> void:
	match_started = false
	phase = PHASE_RESULT
	result_winner = winner
	result_reason = reason


func begin_result_transition() -> bool:
	if phase != PHASE_RESULT:
		return false
	phase = PHASE_ANIMATING
	return true


func begin_reward() -> void:
	phase = PHASE_REWARD


func increment_round() -> int:
	round_number += 1
	return round_number


func reset_round() -> void:
	round_number = 1


func recover_reward_session(
	was_paused: bool,
	winner: int,
	reason: StringName,
	was_surrendered: bool
) -> void:
	previous_pause = was_paused
	round_number = 1
	match_started = false
	result_winner = winner
	result_reason = reason
	surrendered = was_surrendered
	surrender_resume_phase = PHASE_CLOSED
	phase = PHASE_REWARD


func snapshot() -> Dictionary:
	return {
		"phase": phase,
		"previous_pause": previous_pause,
		"match_started": match_started,
		"surrendered": surrendered,
		"result_reason": String(result_reason),
		"result_winner": result_winner,
		"round_number": round_number,
		"surrender_resume_phase": surrender_resume_phase,
	}
