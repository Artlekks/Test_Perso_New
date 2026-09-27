extends RefCounted
class_name LureActionRuntime

var _profile: LureActionProfile = null
var _phase: float = 0.0
var _reel_blend: float = 0.0
var _previous_sample: Vector3 = Vector3.ZERO
var _initialized: bool = false


func configure(profile: LureActionProfile) -> void:
	_profile = profile
	reset()


func reset() -> void:
	_phase = 0.0
	_reel_blend = 0.0
	_previous_sample = Vector3.ZERO
	_initialized = false


func sample_motion_delta(
	delta: float,
	is_reeling: bool
) -> Vector3:
	if _profile == null:
		return Vector3.ZERO

	var safe_delta: float = maxf(delta, 0.0)
	var target_blend: float = 1.0 if is_reeling else 0.0
	var response_speed: float = maxf(
		_profile.transition_response_speed,
		0.01
	)
	var blend_weight: float = clampf(
		1.0 - exp(-response_speed * safe_delta),
		0.0,
		1.0
	)

	_reel_blend = lerpf(
		_reel_blend,
		target_blend,
		blend_weight
	)

	var frequency: float = lerpf(
		_profile.idle_frequency_hz,
		_profile.reel_frequency_hz,
		_reel_blend
	)

	_phase = fmod(
		_phase + TAU * maxf(frequency, 0.0) * safe_delta,
		TAU * 8.0
	)

	var amplitude: Vector3 = Vector3(
		lerpf(
			_profile.idle_lateral_amplitude,
			_profile.reel_lateral_amplitude,
			_reel_blend
		),
		lerpf(
			_profile.idle_vertical_amplitude,
			_profile.reel_vertical_amplitude,
			_reel_blend
		),
		lerpf(
			_profile.idle_forward_amplitude,
			_profile.reel_forward_amplitude,
			_reel_blend
		)
	)

	var next_sample: Vector3 = _sample_at_phase(
		_phase,
		amplitude
	)

	if not _initialized:
		_previous_sample = next_sample
		_initialized = true
		return Vector3.ZERO

	var delta_sample: Vector3 = (
		next_sample - _previous_sample
	)
	_previous_sample = next_sample

	return delta_sample


func get_mode_label() -> String:
	if _profile == null:
		return "NONE"

	if _reel_blend <= 0.05:
		return "IDLE"

	if _reel_blend >= 0.95:
		return "REEL"

	return "BLEND"


func get_profile() -> LureActionProfile:
	return _profile


func _sample_at_phase(
	phase: float,
	amplitude: Vector3
) -> Vector3:
	if _profile == null:
		return Vector3.ZERO

	var lateral: float = 0.0
	var vertical: float = 0.0
	var forward: float = 0.0

	match _profile.motion_style:
		LureActionProfile.MotionStyle.GLIDE:
			lateral = sin(phase)
			vertical = sin(phase * 0.50)
			forward = sin(phase * 0.75)

		LureActionProfile.MotionStyle.BOB:
			lateral = sin(phase * 0.50)
			vertical = sin(phase)
			forward = sin(phase * 0.50)

		LureActionProfile.MotionStyle.POP:
			var pulse: float = maxf(sin(phase), 0.0)
			lateral = sin(phase * 0.50)
			vertical = pulse
			forward = pulse

		LureActionProfile.MotionStyle.SWIM:
			lateral = sin(phase)
			vertical = sin(phase * 2.0) * 0.35
			forward = sin(phase * 0.50)

		LureActionProfile.MotionStyle.WOBBLE:
			lateral = sin(phase)
			vertical = sin(phase * 0.50)
			forward = sin(phase * 2.0) * 0.40

		LureActionProfile.MotionStyle.SPIN:
			lateral = sin(phase)
			vertical = cos(phase)
			forward = sin(phase * 2.0) * 0.25

		LureActionProfile.MotionStyle.SPOON:
			lateral = sin(phase)
			vertical = sin(phase * 2.0) * 0.55
			forward = sin(phase * 0.50)

		_:
			lateral = sin(phase)

	return Vector3(
		lateral * amplitude.x,
		vertical * amplitude.y,
		forward * amplitude.z
	)
