extends RefCounted
## Pure, reusable presentation policy. Gameplay weather, fish behavior, wind,
## water current, and GameClock are NEVER modified by these calculations.
## New environment effects can adopt the same blend rules later.


static func target_levels(weather_state: String) -> Vector2:
	match weather_state:
		"storm":
			return Vector2(1.0, 1.0)
		"rain":
			return Vector2(1.0, 0.0)
	return Vector2.ZERO


static func step_level(current: float, target: float, delta: float, rise_seconds: float, fall_seconds: float) -> float:
	var from: float = clampf(current, 0.0, 1.0)
	var to: float = clampf(target, 0.0, 1.0)
	if is_equal_approx(from, to):
		return to
	var seconds: float = rise_seconds if to > from else fall_seconds
	if seconds <= 0.0:
		return to
	return move_toward(from, to, maxf(delta, 0.0) / seconds)


static func should_emit(rain_level: float, target_rain_level: float) -> bool:
	return rain_level > 0.001 or target_rain_level > 0.001


static func splash_rate_factor(rain_level: float, storm_level: float) -> float:
	return clampf(rain_level, 0.0, 1.0) * (1.0 + 0.3 * clampf(storm_level, 0.0, 1.0))
