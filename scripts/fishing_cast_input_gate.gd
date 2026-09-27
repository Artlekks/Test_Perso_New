extends RefCounted
class_name FishingCastInputGate

enum Stage {
	NONE,
	AIM,
	PREP_THROW,
	CHARGE,
	CURVE,
}

enum PressResult {
	IGNORED,
	CONSUMED,
	BUFFERED,
}

var ready_for_press: bool = true
var prep_confirm_buffered: bool = false
var prep_buffer_released: bool = false


func reset(
	input_currently_pressed: bool = false
) -> void:
	ready_for_press = not input_currently_pressed
	prep_confirm_buffered = false
	prep_buffer_released = false


func release(
	stage: Stage
) -> void:
	if (
		stage == Stage.PREP_THROW
		and prep_confirm_buffered
	):
		prep_buffer_released = true

	ready_for_press = true


func press(
	stage: Stage,
	is_echo: bool = false
) -> PressResult:
	if is_echo:
		return PressResult.IGNORED

	if not ready_for_press:
		return PressResult.IGNORED

	match stage:
		Stage.PREP_THROW:
			ready_for_press = false
			prep_confirm_buffered = true
			prep_buffer_released = false
			return PressResult.BUFFERED

		Stage.AIM, Stage.CHARGE, Stage.CURVE:
			ready_for_press = false
			return PressResult.CONSUMED

		_:
			return PressResult.IGNORED


func take_prep_buffer() -> bool:
	if not prep_confirm_buffered:
		return false

	prep_confirm_buffered = false

	# If that buffered physical press was already released while the animation
	# was still in PREP_THROW, the next fresh K press is allowed immediately.
	ready_for_press = prep_buffer_released
	prep_buffer_released = false
	return true


func get_debug_snapshot() -> Dictionary:
	return {
		"ready_for_press": ready_for_press,
		"prep_confirm_buffered": prep_confirm_buffered,
		"prep_buffer_released": prep_buffer_released,
	}
