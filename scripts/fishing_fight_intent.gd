extends RefCounted
class_name FishingFightIntent

## Stable, presentation-friendly vocabulary for what a hooked fish is trying to
## do right now. FishBehavior owns the actual movement; this helper only turns
## that movement choice into a read model that UI, mastery lessons and QA can
## understand without depending on FishBehavior's internal implementation.

const SURGE_AWAY: int = 0
const SIDE_RUN: int = 1
const DIVE: int = 2
const RISE: int = 3
const ERRATIC: int = 4


static func get_id(intent_type: int, thrashing: bool = false) -> StringName:
	if thrashing:
		return &"thrash"

	match intent_type:
		SURGE_AWAY:
			return &"surge_away"
		SIDE_RUN:
			return &"side_run"
		DIVE:
			return &"dive"
		RISE:
			return &"rise"
		ERRATIC:
			return &"erratic"
		_:
			return &"unknown"


static func get_label(
	intent_type: int,
	lateral: float = 0.0,
	thrashing: bool = false
) -> String:
	if thrashing:
		return "THRASH"

	match intent_type:
		SURGE_AWAY:
			return "RUN"
		SIDE_RUN:
			if lateral < -0.05:
				return "RUN LEFT"
			if lateral > 0.05:
				return "RUN RIGHT"
			return "SIDE RUN"
		DIVE:
			return "DIVE"
		RISE:
			return "RISE"
		ERRATIC:
			return "ERRATIC"
		_:
			return "UNKNOWN"


static func build_snapshot(
	intent_type: int,
	intensity: float,
	duration: float,
	lateral: float,
	depth: float,
	pressure: float,
	thrashing: bool = false
) -> Dictionary:
	return {
		"intent_type": intent_type,
		"intent_id": get_id(intent_type, thrashing),
		"label": get_label(intent_type, lateral, thrashing),
		"intensity": clampf(intensity, 0.0, 1.0),
		"duration": maxf(duration, 0.0),
		"lateral": clampf(lateral, -1.0, 1.0),
		"depth": clampf(depth, -1.0, 1.0),
		"pressure": clampf(pressure, 0.0, 1.0),
		"thrashing": thrashing,
	}
