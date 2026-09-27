extends Resource
class_name RodData

enum PowerTier {
	LEVEL_1,
	LEVEL_2,
	LEVEL_3,
	MAX,
}

@export_category("Identity")
@export var rod_id: StringName = &""
@export var rod_name: String = ""
@export var power_level_label: String = ""
@export var power_tier: PowerTier = PowerTier.LEVEL_1
@export_multiline var description: String = ""
@export_multiline var acquisition_method: String = ""

@export_category("Casting")
## Multiplies launch speed and therefore practical cast range.
@export_range(0.5, 2.0, 0.01)
var cast_speed_multiplier: float = 1.0

@export_category("Retrieve")
## Multiplies lure reel speed for free retrieve and fish-fight retrieve.
@export_range(0.5, 2.0, 0.01)
var reel_speed_multiplier: float = 1.0

## Multiplies the distance queued by one discrete S rod-pull input.
@export_range(0.5, 2.0, 0.01)
var manual_pull_distance_multiplier: float = 1.0

## Multiplies acceleration/deceleration response of the S pull.
@export_range(0.5, 2.0, 0.01)
var manual_pull_response_multiplier: float = 1.0

@export_category("Handling")
## Multiplies how much A/D can bend the retrieve path sideways.
@export_range(0.5, 2.0, 0.01)
var steering_strength_multiplier: float = 1.0

## Multiplies how quickly digital A/D input eases into/out of steering.
@export_range(0.5, 2.0, 0.01)
var steering_response_multiplier: float = 1.0

## Multiplies the physical side twitch produced by an A/D tap.
@export_range(0.5, 2.0, 0.01)
var twitch_strength_multiplier: float = 1.0

@export_category("Fight")
## Multiplies how long the tension gauge may remain overloaded before break.
@export_range(0.5, 2.0, 0.01)
var line_tolerance_multiplier: float = 1.0

## Multiplies stamina-drain bonus when steering against a fish's lateral run.
@export_range(0.5, 2.0, 0.01)
var counter_steer_multiplier: float = 1.0


func get_debug_summary() -> String:
	return (
		"cast %.2f | reel %.2f | line %.2f | "
		+ "steer %.2f/%.2f | twitch %.2f | pull %.2f/%.2f"
	) % [
		cast_speed_multiplier,
		reel_speed_multiplier,
		line_tolerance_multiplier,
		steering_strength_multiplier,
		steering_response_multiplier,
		twitch_strength_multiplier,
		manual_pull_distance_multiplier,
		manual_pull_response_multiplier,
	]
