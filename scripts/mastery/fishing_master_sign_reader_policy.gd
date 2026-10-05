extends RefCounted
class_name FishingMasterSignReaderPolicy

const REQUIRED_STABLE_SECONDS: float = 1.25
const SIGN_NONE: StringName = &"none"


static func get_sign_id(snapshot: Dictionary) -> StringName:
	return StringName(str(snapshot.get("dominant_sign", SIGN_NONE)))


static func has_clear_sign(snapshot: Dictionary) -> bool:
	return (
		bool(snapshot.get("available", false))
		and int(snapshot.get("sign_count", 0)) > 0
		and get_sign_id(snapshot) != SIGN_NONE
	)


static func advance_observation(
	stable_seconds: float,
	tracked_sign: StringName,
	snapshot: Dictionary,
	delta: float
) -> Dictionary:
	if not has_clear_sign(snapshot):
		return {
			"stable_seconds": 0.0,
			"tracked_sign": SIGN_NONE,
		}

	var sign_id := get_sign_id(snapshot)
	var next_seconds := maxf(stable_seconds, 0.0)
	if tracked_sign != sign_id:
		next_seconds = 0.0

	next_seconds += maxf(delta, 0.0)
	return {
		"stable_seconds": next_seconds,
		"tracked_sign": sign_id,
	}


static func is_observation_complete(stable_seconds: float) -> bool:
	return stable_seconds >= REQUIRED_STABLE_SECONDS


static func get_progress_ratio(stable_seconds: float) -> float:
	return clampf(stable_seconds / REQUIRED_STABLE_SECONDS, 0.0, 1.0)


static func get_sign_label(sign_id: StringName) -> String:
	match sign_id:
		&"feeding_turn":
			return "feeding turn"
		&"surface_boil":
			return "surface boil"
		&"baitfish_scatter":
			return "baitfish scatter"
		&"deep_bubbles":
			return "deep bubbles"
		&"shadow_track":
			return "shadow track"
	return "no clear sign"
