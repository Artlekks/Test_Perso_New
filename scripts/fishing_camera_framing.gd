extends RefCounted
## Fixed-orientation ground-plane pan. Perspective screen constraints are linear
## half-planes in world X/Z, so intersect them rather than iterating camera pitch.
static func clip_polygon(polygon: Array[Vector2], normal: Vector2, limit: float) -> Array[Vector2]:
	var result: Array[Vector2] = []
	if polygon.is_empty(): return result
	var previous := polygon[-1]
	var previous_distance := previous.dot(normal)-limit
	for point in polygon:
		var distance := point.dot(normal)-limit
		if (distance <= 0.0) != (previous_distance <= 0.0):
			result.append(previous.lerp(point,previous_distance/(previous_distance-distance)))
		if distance <= 0.0: result.append(point)
		previous = point
		previous_distance = distance
	return result

static func screen_constraints(polygon: Array[Vector2], optical: Transform3D,
		projection: Projection, world: Vector3, region: Rect2, vertical_only := false) -> Array[Vector2]:
	var inverse := optical.affine_inverse()
	var local := inverse*world
	var origin := projection*Vector4(local.x,local.y,local.z,1.0)
	var dx := inverse.basis*Vector3.LEFT
	var dz := inverse.basis*Vector3.FORWARD
	var cx := projection*Vector4(dx.x,dx.y,dx.z,0.0)
	var cz := projection*Vector4(dz.x,dz.y,dz.z,0.0)
	var planes := [Vector4(-1,0,0,region.position.x*2-1),
		Vector4(1,0,0,1-region.end.x*2),
		Vector4(0,1,0,region.position.y*2-1),
		Vector4(0,-1,0,1-region.end.y*2),Vector4(0,0,0,-1)]
	if vertical_only: planes = planes.slice(2)
	for plane: Vector4 in planes:
		var margin := 0.05 if plane == Vector4(0,0,0,-1) else 0.0
		polygon = clip_polygon(polygon,Vector2(plane.dot(cx),plane.dot(cz)),-plane.dot(origin)-margin)
	return polygon

static func nearest(polygon: Array[Vector2], wanted := Vector2.ZERO) -> Vector2:
	var best := polygon[0]
	var distance := INF
	# If wanted is inside the convex polygon, no camera correction is necessary.
	var inside := true
	var sign_value := 0.0
	var area := 0.0
	for index in range(polygon.size()):
		var a := polygon[index]
		var b := polygon[(index+1)%polygon.size()]
		area += a.cross(b)
		var cross := (b-a).cross(wanted-a)
		if absf(cross)>0.000001:
			if sign_value == 0.0: sign_value = signf(cross)
			elif signf(cross) != sign_value: inside = false
		var edge := b-a
		var t := clampf((wanted-a).dot(edge)/maxf(edge.length_squared(),0.000001),0.0,1.0)
		var candidate := a+edge*t
		if candidate.distance_squared_to(wanted)<distance:
			best = candidate
			distance = candidate.distance_squared_to(wanted)
	return wanted if inside and polygon.size()>=3 and absf(area)>0.0000001 else best
