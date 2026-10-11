extends RefCounted
## At least 1/sqrt(17) radial authority is retained when projection opposes input.
const MAX_PROJECTION_COMPENSATION := 4.0
## Resolve A/D as horizontal motion on the *screen*, using a world-plane
## tangent. A tangent around the player is not screen-horizontal when the
## camera travels/yaws: it can send a lure diagonally toward the HUD.
## This helper does not alter the actual lure depth or camera transform.

static func right(camera: Camera3D, world_on_water: Vector3, fallback: Vector3) -> Vector3:
	if camera == null or camera.is_position_behind(world_on_water):
		return fallback
	const SAMPLE := 0.05
	var center := camera.unproject_position(world_on_water)
	var screen_dx := camera.unproject_position(world_on_water+Vector3(SAMPLE,0.0,0.0))-center
	var screen_dz := camera.unproject_position(world_on_water+Vector3(0.0,0.0,SAMPLE))-center
	var side := Vector3(screen_dz.y,0.0,-screen_dx.y)
	if side.length_squared() < 0.000001:
		return fallback
	side = side.normalized()
	var right_screen := side.x*screen_dx.x+side.z*screen_dz.x
	if absf(right_screen)<0.000001:
		return fallback
	return side if right_screen > 0.0 else -side

static func retrieve_direction(camera: Camera3D, surface: Vector3, inward: Vector3,
		steering: float, strength: float) -> Vector3:
	var tangent := Vector3.UP.cross(inward).normalized()
	if camera != null:
		var horizontal := right(camera,surface,tangent)
		tangent = horizontal-inward*horizontal.dot(inward)
		if tangent.length_squared() < 0.000001:
			tangent = Vector3.UP.cross(inward)
		tangent = tangent.normalized()
	var authority := absf(steering)*maxf(strength,0.0)
	if camera != null and not camera.is_position_behind(surface) and authority > 0.001:
		var center := camera.unproject_position(surface)
		var forward_screen := camera.unproject_position(surface+inward*0.05)-center
		var tangent_screen := camera.unproject_position(surface+tangent*0.05)-center
		var signed_lateral := tangent_screen.x
		# The inward component is also projected sideways in the lower-left
		# shot. Merely signing a world tangent can leave D moving LEFT until
		# the geometry changes. Compensate that contribution, keeping inward
		# and tangent orthogonal so positive radial authority always remains.
		if absf(signed_lateral) > 0.00001:
			if signed_lateral < 0.0: tangent = -tangent
			var requested_dx := forward_screen.length()*0.15*absf(steering)
			# Bounded compensation keeps substantial inward authority even when
			# the landing goal and requested screen direction become opposed.
			# The authored arc remains nonzero all the way to the return radius.
			authority = maxf(authority,minf(MAX_PROJECTION_COMPENSATION,(requested_dx-forward_screen.x*signf(steering))/absf(tangent_screen.x)))
	return (inward+tangent*signf(steering)*authority).normalized()
