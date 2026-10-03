extends RefCounted

const SizeRoller = preload(
	"res://scripts/fishing_size_roller.gd"
)

## Authoritative runtime specimen-generation wrapper.
##
## FishingSizeRoller owns the authored base distribution. This wrapper may add
## a bounded anti-bad-luck bonus roll when FishingProgress supplies a mercy
## context. It never edits FishData probabilities and never guarantees a crown
## or record.


static func roll(
	data: FishData,
	king_override: int = -1,
	mercy_context: Dictionary = {}
) -> Dictionary:
	return _roll_internal(
		data,
		king_override,
		mercy_context,
		null
	)


static func roll_with_rng(
	data: FishData,
	rng: RandomNumberGenerator,
	king_override: int = -1,
	mercy_context: Dictionary = {}
) -> Dictionary:
	return _roll_internal(
		data,
		king_override,
		mercy_context,
		rng
	)


static func _roll_internal(
	data: FishData,
	king_override: int,
	mercy_context: Dictionary,
	rng: RandomNumberGenerator
) -> Dictionary:
	var selected: Dictionary = _base_roll(
		data,
		king_override,
		rng
	)

	var candidate_sizes: Array[float] = [
		float(selected.get("size", 0.0))
	]
	var mercy_active: bool = bool(
		mercy_context.get("active", false)
	)
	var bonus_chance: float = clampf(
		float(
			mercy_context.get(
				"bonus_roll_chance",
				0.0
			)
		),
		0.0,
		1.0
	)
	var max_bonus_rolls: int = clampi(
		int(
			mercy_context.get(
				"max_bonus_rolls",
				1
			)
		),
		1,
		3
	)
	var bonus_rolls_used: int = 0
	var mercy_selected_better_candidate: bool = false

	# Explicit QA band overrides own specimen generation. Mercy must never fight
	# FORCE NORMAL / FORCE KING or make deterministic QA nondeterministic.
	if king_override != -1:
		mercy_active = false

	if mercy_active and bonus_chance > 0.0:
		for _bonus_index in range(max_bonus_rolls):
			if _randf(rng) >= bonus_chance:
				continue

			var candidate: Dictionary = _base_roll(
				data,
				-1,
				rng
			)
			var candidate_size: float = float(
				candidate.get("size", 0.0)
			)
			candidate_sizes.append(candidate_size)
			bonus_rolls_used += 1

			if candidate_size > float(selected.get("size", 0.0)):
				selected = candidate
				mercy_selected_better_candidate = true

	var session_quality_active: bool = bool(
		mercy_context.get("session_quality_active", false)
	)
	var session_quality_chance: float = clampf(
		float(mercy_context.get("session_quality_bonus_chance", 0.0)),
		0.0,
		0.50
	)
	var session_quality_rolls: int = clampi(
		int(mercy_context.get("session_quality_bonus_rolls", 0)),
		0,
		2
	)
	var session_bonus_rolls_used: int = 0
	var session_selected_better_candidate: bool = false

	# Explicit QA specimen overrides remain absolute. Temporary session effects
	# are a normal gameplay layer and must never make deterministic QA random.
	if king_override != -1:
		session_quality_active = false

	if session_quality_active and session_quality_chance > 0.0:
		for _session_index in range(session_quality_rolls):
			if _randf(rng) >= session_quality_chance:
				continue

			var session_candidate: Dictionary = _base_roll(
				data,
				-1,
				rng
			)
			var session_candidate_size: float = float(
				session_candidate.get("size", 0.0)
			)
			candidate_sizes.append(session_candidate_size)
			session_bonus_rolls_used += 1

			if session_candidate_size > float(selected.get("size", 0.0)):
				selected = session_candidate
				session_selected_better_candidate = true

	var prepared_bait_quality_active: bool = bool(
		mercy_context.get("prepared_bait_quality_active", false)
	)
	var prepared_bait_quality_chance: float = clampf(
		float(mercy_context.get("prepared_bait_quality_bonus_chance", 0.0)),
		0.0,
		0.75
	)
	var prepared_bait_quality_rolls: int = clampi(
		int(mercy_context.get("prepared_bait_quality_bonus_rolls", 0)),
		0,
		2
	)
	var prepared_bait_bonus_rolls_used: int = 0
	var prepared_bait_selected_better_candidate: bool = false

	# Prepared bait improves specimen odds with extra natural rolls. It never
	# fabricates a size or overrides deterministic QA specimen forcing.
	if king_override != -1:
		prepared_bait_quality_active = false

	if prepared_bait_quality_active and prepared_bait_quality_chance > 0.0:
		for _bait_index in range(prepared_bait_quality_rolls):
			if _randf(rng) >= prepared_bait_quality_chance:
				continue

			var bait_candidate: Dictionary = _base_roll(
				data,
				-1,
				rng
			)
			var bait_candidate_size: float = float(
				bait_candidate.get("size", 0.0)
			)
			candidate_sizes.append(bait_candidate_size)
			prepared_bait_bonus_rolls_used += 1

			if bait_candidate_size > float(selected.get("size", 0.0)):
				selected = bait_candidate
				prepared_bait_selected_better_candidate = true

	var environment_quality_active: bool = bool(
		mercy_context.get("environment_quality_active", false)
	)
	var environment_quality_chance: float = clampf(
		float(mercy_context.get("environment_quality_bonus_chance", 0.0)),
		0.0,
		0.50
	)
	var environment_quality_rolls: int = clampi(
		int(mercy_context.get("environment_quality_bonus_rolls", 0)),
		0,
		2
	)
	var environment_bonus_rolls_used: int = 0
	var environment_selected_better_candidate: bool = false

	# World conditions use the same safe rule as session buffs: extra natural
	# rolls only. Explicit QA specimen overrides remain absolute.
	if king_override != -1:
		environment_quality_active = false

	if environment_quality_active and environment_quality_chance > 0.0:
		for _environment_index in range(environment_quality_rolls):
			if _randf(rng) >= environment_quality_chance:
				continue

			var environment_candidate: Dictionary = _base_roll(
				data,
				-1,
				rng
			)
			var environment_candidate_size: float = float(
				environment_candidate.get("size", 0.0)
			)
			candidate_sizes.append(environment_candidate_size)
			environment_bonus_rolls_used += 1

			if environment_candidate_size > float(selected.get("size", 0.0)):
				selected = environment_candidate
				environment_selected_better_candidate = true

	var result: Dictionary = selected.duplicate(true)
	result["mercy_active"] = mercy_active
	result["mercy_miss_streak"] = maxi(
		int(mercy_context.get("miss_streak", 0)),
		0
	)
	result["mercy_bonus_roll_chance"] = bonus_chance if mercy_active else 0.0
	result["mercy_bonus_rolls_used"] = bonus_rolls_used
	result["mercy_selected_better_candidate"] = mercy_selected_better_candidate
	result["mercy_candidate_sizes"] = candidate_sizes
	result["session_quality_active"] = session_quality_active
	result["session_quality_bonus_chance"] = (
		session_quality_chance if session_quality_active else 0.0
	)
	result["session_quality_bonus_rolls_used"] = session_bonus_rolls_used
	result["session_quality_selected_better_candidate"] = (
		session_selected_better_candidate
	)
	result["prepared_bait_quality_active"] = prepared_bait_quality_active
	result["prepared_bait_quality_bonus_chance"] = (
		prepared_bait_quality_chance if prepared_bait_quality_active else 0.0
	)
	result["prepared_bait_quality_bonus_rolls_used"] = (
		prepared_bait_bonus_rolls_used
	)
	result["prepared_bait_quality_selected_better_candidate"] = (
		prepared_bait_selected_better_candidate
	)
	result["environment_quality_active"] = environment_quality_active
	result["environment_quality_bonus_chance"] = (
		environment_quality_chance if environment_quality_active else 0.0
	)
	result["environment_quality_bonus_rolls_used"] = environment_bonus_rolls_used
	result["environment_quality_selected_better_candidate"] = (
		environment_selected_better_candidate
	)
	result["environment_condition_ids"] = mercy_context.get(
		"environment_condition_ids",
		PackedStringArray()
	)
	result["candidate_sizes"] = candidate_sizes
	result["session_effect_ids"] = mercy_context.get(
		"session_effect_ids",
		PackedStringArray()
	)
	return result


static func _base_roll(
	data: FishData,
	king_override: int,
	rng: RandomNumberGenerator
) -> Dictionary:
	if rng != null:
		return SizeRoller.roll_with_rng(
			data,
			rng,
			king_override
		)

	return SizeRoller.roll(
		data,
		king_override
	)


static func _randf(rng: RandomNumberGenerator) -> float:
	if rng != null:
		return rng.randf()
	return randf()
