extends RefCounted
class_name FishingOneWithNaturePolicy

## One With Nature v1
##
## Capstone fieldcraft policy. The skill rewards genuine stillness plus a natural
## lure presentation, especially against wary fish. It never changes ambient
## population, species selection, king chance, specimen size, weather or tide.

const SETTLE_SECONDS: float = 3.50
const MAX_SETTLED_DISTURBANCE: float = 0.06
const MIN_NATURAL_PRESENTATION: float = 0.92
const MAX_APPROACH_MULTIPLIER: float = 1.16
const MAX_STRESS_REDUCTION: float = 0.28


static func advance_settle_time(
	current_seconds: float,
	disturbance: float,
	delta: float,
	has_capstone: bool
) -> float:
	if not has_capstone:
		return 0.0
	if clampf(disturbance, 0.0, 1.0) > MAX_SETTLED_DISTURBANCE:
		return 0.0
	return minf(
		maxf(current_seconds, 0.0) + maxf(delta, 0.0),
		SETTLE_SECONDS
	)


static func get_settle_ratio(settle_seconds: float) -> float:
	return clampf(
		maxf(settle_seconds, 0.0) / SETTLE_SECONDS,
		0.0,
		1.0
	)


static func is_attuned(
	has_capstone: bool,
	settle_seconds: float
) -> bool:
	return has_capstone and settle_seconds >= SETTLE_SECONDS - 0.001


static func get_approach_multiplier(
	wariness: float,
	presentation_multiplier: float,
	attuned: bool
) -> float:
	if not attuned:
		return 1.0
	var presentation := clampf(presentation_multiplier, 0.25, 2.0)
	if presentation < MIN_NATURAL_PRESENTATION:
		return 1.0

	# Bold fish already approach readily. The capstone matters most for fish that
	# normally scrutinize bank movement and presentation.
	var wary_factor := clampf(
		inverse_lerp(0.50, 0.95, clampf(wariness, 0.0, 1.0)),
		0.0,
		1.0
	)
	var presentation_factor := clampf(
		inverse_lerp(
			MIN_NATURAL_PRESENTATION,
			1.35,
			presentation
		),
		0.0,
		1.0
	)
	var bonus := 0.16 * wary_factor * lerpf(0.55, 1.0, presentation_factor)
	return clampf(1.0 + bonus, 1.0, MAX_APPROACH_MULTIPLIER)


static func get_positive_stress_multiplier(
	wariness: float,
	attuned: bool
) -> float:
	if not attuned:
		return 1.0
	var wary_factor := clampf(
		inverse_lerp(0.50, 0.95, clampf(wariness, 0.0, 1.0)),
		0.0,
		1.0
	)
	return clampf(
		1.0 - MAX_STRESS_REDUCTION * wary_factor,
		1.0 - MAX_STRESS_REDUCTION,
		1.0
	)


static func build_snapshot(
	has_capstone: bool,
	settle_seconds: float,
	disturbance: float
) -> Dictionary:
	var ratio := get_settle_ratio(settle_seconds)
	return {
		"available": has_capstone,
		"attuned": is_attuned(has_capstone, settle_seconds),
		"settle_seconds": maxf(settle_seconds, 0.0),
		"settle_ratio": ratio,
		"disturbance": clampf(disturbance, 0.0, 1.0),
		"required_seconds": SETTLE_SECONDS,
		"presentation_floor": MIN_NATURAL_PRESENTATION,
	}
