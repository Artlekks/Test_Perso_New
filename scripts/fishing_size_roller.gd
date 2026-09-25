extends RefCounted

## Size-generation backend.
##
## Keeping this separate from FishInstance makes the population distribution
## independently tunable/testable and prevents fight setup from owning RNG.
## Returned size is always a whole centimetre.


static func roll(data: FishData, king_override: int = -1) -> Dictionary:
	if data == null:
		return {
			"size": 0.0,
			"is_king": false,
			"band": &"normal",
		}

	# QA overrides remain deterministic: FORCE NORMAL never leaks into the
	# near-record/king bands, while FORCE KING always tests crown behavior.
	if king_override == 1:
		return _roll_king(data)
	if king_override == 0:
		return _roll_normal(data)

	var king_chance: float = clampf(data.king_chance, 0.0, 1.0)
	var near_record_chance: float = clampf(
		data.near_record_chance,
		0.0,
		1.0 - king_chance
	)

	var quality_roll: float = randf()
	if quality_roll < king_chance:
		return _roll_king(data)

	if quality_roll < king_chance + near_record_chance:
		return _roll_near_record(data)

	return _roll_normal(data)


static func _roll_normal(data: FishData) -> Dictionary:
	var safe_average: float = maxf(data.average_size, 1.0)
	var king_cm: int = maxi(ceili(maxf(data.king_size, safe_average)), 1)
	var near_record_min_cm: int = _get_near_record_min_cm(data, king_cm)

	# Ordinary catches stop immediately before the near-record band.
	var normal_max_cm: int = maxi(near_record_min_cm - 1, 1)
	var normal_min_cm: int = clampi(
		roundi(
			safe_average
			* clampf(data.normal_min_average_multiplier, 0.25, 1.0)
		),
		1,
		normal_max_cm
	)

	var sample_count: int = clampi(data.normal_roll_samples, 1, 6)
	var normalized_roll: float = 0.0
	for _sample_index in range(sample_count):
		normalized_roll += randf()
	normalized_roll /= float(sample_count)

	var rolled_cm: int = roundi(lerpf(
		float(normal_min_cm),
		float(normal_max_cm),
		normalized_roll
	))

	return {
		"size": float(clampi(rolled_cm, normal_min_cm, normal_max_cm)),
		"is_king": false,
		"band": &"normal",
	}


static func _roll_near_record(data: FishData) -> Dictionary:
	var safe_average: float = maxf(data.average_size, 1.0)
	var king_cm: int = maxi(ceili(maxf(data.king_size, safe_average)), 1)
	var near_record_min_cm: int = _get_near_record_min_cm(data, king_cm)
	var near_record_max_cm: int = maxi(king_cm - 1, near_record_min_cm)

	# Minimum-of-N biases the band toward its lower end. Entering this band is
	# already uncommon; getting within a centimetre of crown is rarer again.
	var sample_count: int = clampi(data.near_record_roll_samples, 1, 5)
	var normalized_roll: float = 1.0
	for _sample_index in range(sample_count):
		normalized_roll = minf(normalized_roll, randf())

	var rolled_cm: int = roundi(lerpf(
		float(near_record_min_cm),
		float(near_record_max_cm),
		normalized_roll
	))

	return {
		"size": float(clampi(
			rolled_cm,
			near_record_min_cm,
			near_record_max_cm
		)),
		"is_king": false,
		"band": &"near_record",
	}


static func _roll_king(data: FishData) -> Dictionary:
	var safe_average: float = maxf(data.average_size, 1.0)
	var king_threshold: float = maxf(data.king_size, safe_average)
	var king_min_cm: int = maxi(ceili(king_threshold), 1)
	var king_max_cm: int = maxi(
		king_min_cm,
		roundi(
			king_threshold
			* maxf(data.king_max_size_multiplier, 1.0)
		)
	)

	# Bias exceptional sizes toward the crown threshold as well. A maximum-size
	# king therefore remains special even after the crown roll succeeds.
	var normalized_roll: float = minf(randf(), randf())
	var rolled_cm: int = roundi(lerpf(
		float(king_min_cm),
		float(king_max_cm),
		normalized_roll
	))

	return {
		"size": float(clampi(rolled_cm, king_min_cm, king_max_cm)),
		"is_king": true,
		"band": &"king",
	}


static func _get_near_record_min_cm(data: FishData, king_cm: int) -> int:
	if king_cm <= 1:
		return 1

	var ratio: float = clampf(
		data.near_record_min_size_ratio,
		0.75,
		0.99
	)

	return clampi(
		ceili(float(king_cm) * ratio),
		1,
		king_cm - 1
	)
