extends RefCounted
class_name FishingMasterLessonPolicy

const STILLNESS_DURATION_SECONDS: float = 4.0
const STILLNESS_DISTURBANCE_THRESHOLD: float = 0.08


static func advance_stillness(
	current_progress: float,
	disturbance: float,
	delta: float
) -> float:
	if clampf(disturbance, 0.0, 1.0) > STILLNESS_DISTURBANCE_THRESHOLD:
		return 0.0
	return minf(
		maxf(current_progress, 0.0) + maxf(delta, 0.0),
		STILLNESS_DURATION_SECONDS
	)


static func is_stillness_complete(progress: float) -> bool:
	return progress >= STILLNESS_DURATION_SECONDS


static func get_stillness_ratio(progress: float) -> float:
	return clampf(
		progress / maxf(STILLNESS_DURATION_SECONDS, 0.001),
		0.0,
		1.0
	)
