extends Resource
class_name LureActionProfile

enum MotionStyle {
	GLIDE,
	BOB,
	POP,
	SWIM,
	WOBBLE,
	SPIN,
	SPOON,
}

@export_category("Identity")
@export var action_id: StringName = &""
@export var display_name: String = ""
@export var motion_style: MotionStyle = MotionStyle.GLIDE

@export_category("Idle Action")
@export_range(0.0, 0.20, 0.001)
var idle_lateral_amplitude: float = 0.0
@export_range(0.0, 0.20, 0.001)
var idle_vertical_amplitude: float = 0.0
@export_range(0.0, 0.20, 0.001)
var idle_forward_amplitude: float = 0.0
@export_range(0.0, 8.0, 0.05)
var idle_frequency_hz: float = 0.0

@export_category("Retrieve Action")
@export_range(0.0, 0.20, 0.001)
var reel_lateral_amplitude: float = 0.0
@export_range(0.0, 0.20, 0.001)
var reel_vertical_amplitude: float = 0.0
@export_range(0.0, 0.20, 0.001)
var reel_forward_amplitude: float = 0.0
@export_range(0.0, 8.0, 0.05)
var reel_frequency_hz: float = 0.0

@export_category("Response")
## How quickly the action blends between idle and retrieve values.
## This prevents a visible phase/motion reset when the reel button changes.
@export_range(1.0, 20.0, 0.25)
var transition_response_speed: float = 7.0

@export_category("Attraction")
@export_range(0.10, 2.00, 0.01)
var idle_attraction_multiplier: float = 1.0
@export_range(0.10, 2.00, 0.01)
var reel_attraction_multiplier: float = 1.0
@export var universal_compatibility: bool = false

@export_category("Presentation Hooks")
@export_range(0.0, 1.0, 0.01)
var surface_disturbance: float = 0.0
@export_range(0.0, 1.0, 0.01)
var flash_strength: float = 0.0

@export_category("Documentation")
@export_multiline var tuning_note: String = ""


func get_attraction_multiplier(is_reeling: bool) -> float:
	return (
		reel_attraction_multiplier
		if is_reeling
		else idle_attraction_multiplier
	)


func get_style_label() -> String:
	match motion_style:
		MotionStyle.GLIDE:
			return "GLIDE"
		MotionStyle.BOB:
			return "BOB"
		MotionStyle.POP:
			return "POP"
		MotionStyle.SWIM:
			return "SWIM"
		MotionStyle.WOBBLE:
			return "WOBBLE"
		MotionStyle.SPIN:
			return "SPIN"
		MotionStyle.SPOON:
			return "SPOON"
		_:
			return "UNKNOWN"
