extends RefCounted

## Presentation only. Projection is supplied by the owning camera; no actor is moved.
var yaw := 0.0
var tracking := false
var limited := false
var requested_yaw := 0.0

func reset() -> void:
	yaw = 0.0
	tracking = false
	limited = false
	requested_yaw = 0.0

func inside(point: Vector2, region: Rect2, tolerance := 0.0) -> bool:
	return point.x >= region.position.x - tolerance and point.x <= region.end.x + tolerance \
		and point.y >= region.position.y - tolerance and point.y <= region.end.y + tolerance

func violation(point: Vector2, region: Rect2) -> float:
	var nearest := point.clamp(region.position, region.end)
	return point.distance_squared_to(nearest)

func step(delta: float, project: Callable, outer: Rect2, hysteresis: float,
		max_yaw: float, response: float, _return_response: float, vertical_hysteresis := 0.025) -> float:
	var horizontal_margin := clampf(hysteresis, 0.0, outer.size.x * 0.25)
	var vertical_margin := clampf(vertical_hysteresis, 0.0, outer.size.y * 0.25)
	var margin := Vector2(horizontal_margin,vertical_margin)
	var inner := Rect2(outer.position+margin,outer.size-margin*2.0)
	var point: Vector2 = project.call(yaw)
	if not inside(point, outer, 0.000001):
		tracking = true
	elif tracking and inside(point, inner):
		tracking = false
	limited = false
	requested_yaw = yaw
	if not tracking:
		# Hold the established shot throughout the dead zone. Unwinding here
		# would rotate a comfortably visible bait and re-chase current drift.
		# Retrieve/result return remains owned by CameraRig's existing flow.
		return yaw

	# Search the bounded orbit for the closest safe heading. Projection also
	# checks vertical clearance: a sideways run can descend toward the HUD.
	# This work runs only outside the dead zone, never during other phases.
	var best := yaw
	# Aim a subpixel inside the stop region so exponential convergence actually
	# crosses it, rather than approaching the boundary indefinitely.
	var goal := inner.grow(-0.0001)
	var best_error := violation(point, goal)
	var best_distance := INF
	var found_safe := false
	const SAMPLES := 32
	for index in range(SAMPLES + 1):
		var candidate := lerpf(-max_yaw, max_yaw, float(index) / SAMPLES)
		var projected: Vector2 = project.call(candidate)
		var error := violation(projected, goal)
		var distance := absf(candidate - yaw)
		if error <= 0.00000001:
			if not found_safe or distance < best_distance:
				best = candidate
				best_distance = distance
				found_safe = true
		elif not found_safe and error < best_error:
			best = candidate
			best_error = error
	if found_safe:
		# Refine the first safe boundary, rather than aiming at screen center.
		var unsafe_yaw := yaw
		var safe_yaw := best
		for iteration in range(12):
			var midpoint := (unsafe_yaw + safe_yaw) * 0.5
			if inside(project.call(midpoint), goal):
				safe_yaw = midpoint
			else:
				unsafe_yaw = midpoint
		best = safe_yaw
	limited = not found_safe
	requested_yaw = best
	yaw = clampf(lerpf(yaw, best, 1.0 - exp(-response * delta)), -max_yaw, max_yaw)
	return yaw
