extends Resource
class_name BaitData

@export_category("Identity")
@export var lure_id: StringName = &""
@export var display_name: String = ""
@export var lure_type: LureType.Type = LureType.Type.WORM

@export_range(1, 3, 1)
var level: int = 1

@export_multiline var description: String = ""

@export_category("Presentation")
## Temporary family color used by the articulated pixel lure.
## This lives in lure data so future per-lure sprite/art passes do not require
## hardcoded visual rules in the renderer.
@export var visual_tint: Color = Color.WHITE

@export_category("Action")
@export var action_profile: LureActionProfile

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

@export_category("Hooked Fish")
## Designer-facing fight role. Attraction/depth still determine how the lure gets
## the bite; these values only matter after a fish is actually hooked.
@export var fight_role_label: String = "BALANCED"

## Multiplies fish stamina drain while the player is safely reeling. High-action
## lures can exhaust fish faster, but are intentionally not always secure hooks.
@export_range(0.80, 1.20, 0.01)
var fight_fatigue_multiplier: float = 1.0

## Multiplies sustained-slack grace before Hook Off. This lets frog/worm-style
## lures feel secure while aggressive surface/spinner lures trade security for pace.
@export_range(0.80, 1.20, 0.01)
var hook_security_multiplier: float = 1.0

@export_category("Snag Profile")
## 0.0 = no protection, 1.0 = completely ignores bottom snag pressure.
## This changes only how quickly snag risk builds; it does not prevent the
## lure from physically reaching the bottom.
@export_range(0.0, 0.9, 0.05)
var bottom_snag_resistance: float = 0.0

## 0.0 = no protection, 1.0 = completely ignores reusable obstacle snag
## volumes. Kept below 1.0 in current data so no lure is fully immune.
@export_range(0.0, 0.9, 0.05)
var obstacle_snag_resistance: float = 0.0


func get_bottom_snag_multiplier() -> float:
	return 1.0 - clampf(
		bottom_snag_resistance,
		0.0,
		0.9
	)


func get_obstacle_snag_multiplier() -> float:
	return 1.0 - clampf(
		obstacle_snag_resistance,
		0.0,
		0.9
	)


func get_type_label() -> String:
	match lure_type:
		LureType.Type.WORM:
			return "Worm"
		LureType.Type.FROG:
			return "Frogger"
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


func get_action_profile() -> LureActionProfile:
	return action_profile


func get_action_attraction_multiplier(
	is_reeling: bool
) -> float:
	if action_profile == null:
		return 1.0

	return action_profile.get_attraction_multiplier(
		is_reeling
	)


func has_universal_compatibility() -> bool:
	return (
		action_profile != null
		and action_profile.universal_compatibility
	)


func get_action_debug_summary() -> String:
	if action_profile == null:
		return "NO ACTION PROFILE"

	return "%s/%s  ATTR %.2f idle / %.2f reel  FIGHT %s %.2f/%.2f%s" % [
		action_profile.display_name,
		action_profile.get_style_label(),
		action_profile.idle_attraction_multiplier,
		action_profile.reel_attraction_multiplier,
		fight_role_label,
		fight_fatigue_multiplier,
		hook_security_multiplier,
		("  UNIVERSAL" if action_profile.universal_compatibility else ""),
	]
