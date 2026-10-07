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
		max_yaw: float, response: float, return_response: float) -> float:
	var margin := minf(hysteresis, minf(outer.size.x, outer.size.y) * 0.25)
	var inner := outer.grow(-margin)
	var point: Vector2 = project.call(yaw)
	if not inside(point, outer):
		tracking = true
	elif tracking and inside(point, inner, 0.001):
		tracking = false
	limited = false
	requested_yaw = yaw
	if not tracking:
		# Return only as far as the inner region allows. This cannot restart
		# edge tracking on the next frame, even when the fish rests at an edge.
		var returning := lerpf(yaw, 0.0, 1.0 - exp(-return_response * delta))
		if inside(project.call(returning), inner):
			yaw = returning
		return yaw

	# Search the bounded orbit for the closest safe heading. Projection also
	# checks vertical clearance: a sideways run can descend toward the HUD.
	# This work runs only outside the dead zone, never during other phases.
	var best := yaw
	var best_error := violation(point, inner)
	var best_distance := INF
	var found_safe := false
	const SAMPLES := 32
	for index in range(SAMPLES + 1):
		var candidate := lerpf(-max_yaw, max_yaw, float(index) / SAMPLES)
		var projected: Vector2 = project.call(candidate)
		var error := violation(projected, inner)
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
			if inside(project.call(midpoint), inner):
				safe_yaw = midpoint
			else:
				unsafe_yaw = midpoint
		best = safe_yaw
	limited = not found_safe
	requested_yaw = best
	yaw = clampf(lerpf(yaw, best, 1.0 - exp(-response * delta)), -max_yaw, max_yaw)
	return yaw
