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
	var positional_weight: float = 0.0
	var card_strength_weight: float = 0.0
	var conserve_cost_weight: float = 0.0
	var rotate_spend_penalty: float = 0.0
	var randomness: float = 0.0


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


func _slot(card, owner: int, rotation: int = 0) -> Dictionary:
	return {
		"card": card,
		"owner": owner,
		"rotation": rotation,
	}


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
