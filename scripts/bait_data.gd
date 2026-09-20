extends Resource
class_name BaitData

@export_category("Identity")
@export var lure_id: StringName = &""
@export var display_name: String = ""
@export var lure_type: LureType.Type = LureType.Type.WORM

@export_range(1, 3, 1)
var level: int = 1

@export_multiline var description: String = ""

@export_category("Water Movement")
## Normalized target depth: 0.0 = water surface, 1.0 = local bottom.
@export_range(0.0, 1.0, 0.01) var sink_depth: float = 1.0
@export var sink_speed: float = 0.2

@export_category("Reeling")
@export var reel_speed: float = 0.05
@export var reel_rise_speed: float = 0.5
@export var reel_steer_strength: float = 0.8

@export_category("Casting")
@export var cast_weight: float = 1.0


func get_type_label() -> String:
	match lure_type:
		LureType.Type.WORM:
			return "Worm"
		LureType.Type.FROG:
			return "Frog"
		LureType.Type.TOPPER:
			return "Topper"
		LureType.Type.MINNOW:
			return "Minnow"
		LureType.Type.WINDER:
			return "Winder"
		LureType.Type.SPINNER:
			return "Spinner"
		LureType.Type.SPOON:
			return "Spoon"
		_:
			return "Unknown"
