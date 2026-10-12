extends RefCounted
## Wind Gameplay v1: perturb only the AIRBORNE cast arc.
## The first/last points stay EXACTLY the same, so target previews,
## landing checks, camera, underwater current and retrieval do not change.
## The signed X/Z offset follows GameWind.velocity_xz (direction TOWARDS).

const MAX_AIR_BOW_METERS: float = 0.35
const REFERENCE_WIND_MPS: float = 7.0

static func bend_path(path: PackedVector3Array, wind_velocity_xz: Vector2) -> PackedVector3Array:
	var output: PackedVector3Array = path.duplicate()
	if output.size() < 3:
		return output
	var speed: float = wind_velocity_xz.length()
	if speed < 0.05 or is_nan(speed) or is_inf(speed):
		return output
	var displacement: Vector2 = wind_velocity_xz.normalized() * (
		MAX_AIR_BOW_METERS * clampf(speed / REFERENCE_WIND_MPS, 0.0, 1.0)
	)
	var final_index: int = output.size() - 1
	for index in range(1, final_index):
		var fraction: float = float(index) / float(final_index)
		var bow: float = sin(PI * fraction)
		var point: Vector3 = output[index]
		point.x += displacement.x * bow
		point.z += displacement.y * bow
		output[index] = point
	return output
