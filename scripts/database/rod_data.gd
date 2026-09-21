extends Resource
class_name RodData

@export_category("Identity")
@export var rod_id: StringName = &""
@export var rod_name: String = ""
@export var power_level_label: String = ""
@export_multiline var description: String = ""
@export_multiline var acquisition_method: String = ""

@export_category("Gameplay")
## Multiplies the cast launch speed. 1.0 = current baseline.
@export_range(0.5, 2.0, 0.01)
var cast_speed_multiplier: float = 1.0

## Multiplies lure reel speed for both free reel and fish-fight reel states.
@export_range(0.5, 2.0, 0.01)
var reel_speed_multiplier: float = 1.0

## Multiplies the amount of time the tension gauge may remain overloaded
## before the line breaks.
@export_range(0.5, 2.0, 0.01)
var line_tolerance_multiplier: float = 1.0

## Multiplies the stamina-drain bonus when the player steers against
## the fish's lateral run. Higher = easier/more effective handling.
@export_range(0.5, 2.0, 0.01)
var counter_steer_multiplier: float = 1.0
