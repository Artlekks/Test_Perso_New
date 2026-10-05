extends RefCounted
class_name FishingMasterNatureGuidePolicy

## Nature Guide lesson policy.
##
## The capstone lesson mirrors the real One With Nature requirements before the
## technique is learned: settle completely, read a real fish sign, then sustain
## a natural presentation close to a genuinely wary visible fish. It never
## changes fish population, wariness, bite odds, presentation, or fight tuning.

const CapstonePolicy = preload("res://scripts/fishing_one_with_nature_policy.gd")

const REQUIRED_SETTLE_SECONDS: float = CapstonePolicy.SETTLE_SECONDS
const MAX_SETTLED_DISTURBANCE: float = CapstonePolicy.MAX_SETTLED_DISTURBANCE
const MIN_NATURAL_PRESENTATION: float = CapstonePolicy.MIN_NATURAL_PRESENTATION
const MIN_WARY_WARINESS: float = 0.48
const MAX_TARGET_DISTANCE_METERS: float = 1.75
const REQUIRED_PRESENTATION_SECONDS: float = 0.75


static func advance_settle_time(
	current_seconds: float,
	disturbance: float,
	delta: float
) -> float:
	return CapstonePolicy.advance_settle_time(
		current_seconds,
		disturbance,
		delta,
		true
	)


static func is_settled(settle_seconds: float) -> bool:
	return CapstonePolicy.is_attuned(true, settle_seconds)


static func is_natural_presentation(presentation_multiplier: float) -> bool:
	return presentation_multiplier >= MIN_NATURAL_PRESENTATION


static func is_wary_target(
	wariness: float,
	distance_meters: float,
	readable: bool
) -> bool:
	return (
		readable
		and clampf(wariness, 0.0, 1.0) >= MIN_WARY_WARINESS
		and maxf(distance_meters, 0.0) <= MAX_TARGET_DISTANCE_METERS
	)


static func advance_presentation_time(
	current_seconds: float,
	settle_seconds: float,
	presentation_multiplier: float,
	wariness: float,
	distance_meters: float,
	readable: bool,
	has_clear_sign: bool,
	delta: float
) -> float:
	if not is_settled(settle_seconds):
		return 0.0
	if not has_clear_sign:
		return 0.0
	if not is_natural_presentation(presentation_multiplier):
		return 0.0
	if not is_wary_target(wariness, distance_meters, readable):
		return 0.0
	return minf(
		maxf(current_seconds, 0.0) + maxf(delta, 0.0),
		REQUIRED_PRESENTATION_SECONDS
	)


static func is_complete(
	settle_seconds: float,
	presentation_seconds: float
) -> bool:
	return (
		is_settled(settle_seconds)
		and presentation_seconds >= REQUIRED_PRESENTATION_SECONDS - 0.001
	)


static func get_settle_progress_ratio(settle_seconds: float) -> float:
	return clampf(
		maxf(settle_seconds, 0.0) / maxf(REQUIRED_SETTLE_SECONDS, 0.001),
		0.0,
		1.0
	)


static func get_presentation_progress_ratio(presentation_seconds: float) -> float:
	return clampf(
		maxf(presentation_seconds, 0.0) / maxf(REQUIRED_PRESENTATION_SECONDS, 0.001),
		0.0,
		1.0
	)
