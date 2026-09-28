extends Resource
class_name FishingTensionProfile

@export_category("Free Reel")
@export_range(0.0, 1.0, 0.01)
var free_reel_start: float = 0.05

@export_range(0.0, 1.0, 0.01)
var free_reel_max: float = 0.18

@export var free_reel_gain_speed: float = 0.08
@export var free_reel_loss_speed: float = 0.10

@export_category("Safe Zone")
@export_range(0.0, 1.0, 0.01)
var safe_min: float = 0.35

@export_range(0.0, 1.0, 0.01)
var safe_max: float = 0.55

@export_category("Fight Response")
## Current project feel value. Exact original-engine numeric tuning is unknown.
@export var tension_response_speed: float = 0.36

## Current project feel value. Exact original-engine numeric tuning is unknown.
@export var release_tension_speed: float = 0.30

@export var reel_target_offset: float = 0.03
@export var passive_resistance_offset: float = 0.08
@export var directional_tension_speed: float = 0.035

@export_range(0.0, 1.0, 0.05)
var thrash_threshold: float = 0.70

@export var thrash_target_offset: float = 0.25

@export_category("Failure")
## Seconds continuously above safe_max before the line snaps.
@export var line_break_delay: float = 1.50

## Tension value at/below which the hook-off timer can run. A small readable
## slack band is easier to understand than failing on one exact zero value.
@export_range(0.0, 1.0, 0.01)
var hook_off_threshold: float = 0.08

## Continuous slack grace before the fish escapes. This prevents one-frame or
## frame-rate-sensitive hook-off while still punishing sustained loose line.
@export var hook_off_delay: float = 0.80


func is_valid_profile() -> bool:
	return (
		free_reel_max >= 0.0
		and safe_min >= 0.0
		and safe_max <= 1.0
		and safe_min < safe_max
		and tension_response_speed >= 0.0
		and release_tension_speed >= 0.0
		and line_break_delay >= 0.0
		and hook_off_delay >= 0.0
	)


func get_safe_center() -> float:
	return (
		clampf(safe_min, 0.0, 1.0)
		+ clampf(safe_max, 0.0, 1.0)
	) * 0.5


func get_debug_summary() -> String:
	return (
		"safe %.2f-%.2f | response %.2f/%.2f | "
		+ "snap %.2fs | escape <=%.2f %.2fs"
	) % [
		safe_min,
		safe_max,
		tension_response_speed,
		release_tension_speed,
		line_break_delay,
		hook_off_threshold,
		hook_off_delay,
	]
