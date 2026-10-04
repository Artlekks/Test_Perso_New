extends RefCounted
class_name FishingBiteTimingPolicy

## Bite Recognition + Hook-Set Timing v1
##
## This policy only owns the pre-hook read: how long a fish telegraphs before
## the hook-set becomes valid. Encounter remains authoritative for bite rolls,
## fish selection, hook confirmation, fight state and misses.

const MIN_TOTAL_WINDOW: float = 0.20
const MIN_HOOK_WINDOW: float = 0.18


static func resolve_for_profile(
	profile: FishBehaviorProfile,
	total_window: float,
	direct_commit: bool
) -> Dictionary:
	var safe_total: float = maxf(total_window, MIN_TOTAL_WINDOW)
	var style: int = FishBehaviorProfile.BiteTimingStyle.NIBBLE
	var delay_multiplier: float = 1.0

	if profile != null:
		style = profile.get_resolved_bite_timing_style()
		delay_multiplier = maxf(profile.bite_commit_delay_multiplier, 0.05)

	var base_ratio: float = _get_commit_ratio(style)
	var commit_delay: float = 0.0

	if not direct_commit:
		commit_delay = safe_total * base_ratio * delay_multiplier
		commit_delay = clampf(
			commit_delay,
			0.0,
			maxf(safe_total - MIN_HOOK_WINDOW, 0.0)
		)

	var hook_window: float = maxf(safe_total - commit_delay, 0.05)
	var requires_wait: bool = commit_delay > 0.001

	return {
		"style": style,
		"style_label": get_style_label(style),
		"direct_commit": direct_commit,
		"requires_wait": requires_wait,
		"early_hook_is_miss": requires_wait,
		"total_window": safe_total,
		"commit_delay": commit_delay,
		"hook_window": hook_window,
		"commit_ratio": 0.0 if direct_commit else base_ratio,
		"telegraph_cue": _get_telegraph_cue(style, direct_commit),
		"hook_ready_cue": &"strong_take",
	}


static func get_style_label(style: int) -> String:
	match style:
		FishBehaviorProfile.BiteTimingStyle.STRIKE:
			return "STRIKE"
		FishBehaviorProfile.BiteTimingStyle.LOAD:
			return "LOAD"
		FishBehaviorProfile.BiteTimingStyle.FEINT:
			return "FEINT"
		_:
			return "NIBBLE"


static func _get_commit_ratio(style: int) -> float:
	match style:
		FishBehaviorProfile.BiteTimingStyle.STRIKE:
			# Fast fish are readable, but only barely tentative unless the bite
			# rolled as a fully committed take.
			return 0.12
		FishBehaviorProfile.BiteTimingStyle.LOAD:
			# Heavy fish lean on the lure before the line truly loads.
			return 0.52
		FishBehaviorProfile.BiteTimingStyle.FEINT:
			# Erratic fish sell the false start longest and leave a shorter real
			# hook-set window at the end.
			return 0.58
		_:
			# Steady/default fish give a conventional nibble-then-take read.
			return 0.38


static func _get_telegraph_cue(style: int, direct_commit: bool) -> StringName:
	if direct_commit:
		return &"strong_take"

	match style:
		FishBehaviorProfile.BiteTimingStyle.STRIKE:
			return &"quick_tug"
		FishBehaviorProfile.BiteTimingStyle.LOAD:
			return &"heavy_load"
		FishBehaviorProfile.BiteTimingStyle.FEINT:
			return &"false_start"
		_:
			return &"nibble"
