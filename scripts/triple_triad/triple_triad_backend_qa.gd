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
	_run("Influence snapshot attributes its source", _test_influence_source_attribution)
	_run("Preview exposes Influence deltas", _test_preview_influence_deltas)
	_run("Unsupported rules are rejected", _test_unsupported_rule_guard)
	_run("Authored opponent ladder is legal", _test_authored_opponent_ladder)

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

	var profiles: Array = DefaultOpponentRegistry.get_all_opponents()
	if profiles.size() != 5:
		return _ok(false, "Expected exactly five authored opponent archetypes.")

	var previous_duel_rank: int = 0
	var archetypes: Dictionary = {}
	for profile in profiles:
		if profile == null:
			return _ok(false, "Opponent ladder contains a null profile.")
		var opponent_id: String = String(profile.opponent_id)
		if profile.duel_rank < previous_duel_rank:
			return _ok(false, "Opponent ladder is not ordered by Duel Rank.")
		previous_duel_rank = profile.duel_rank

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
