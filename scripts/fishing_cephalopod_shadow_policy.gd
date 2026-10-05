extends RefCounted
class_name FishingCephalopodShadowPolicy

## Presentation-only policy for soft-bodied / tentacled ambient fish.
## It does not change population, bite, fight, depth or reward rules.

const TARGET_SPECIES: Array[String] = [
	"jellyfish",
	"man_o_war",
	"martian_squid",
	"octopus",
]

const RISE_SECONDS: float = 0.55
const SINK_SECONDS: float = 0.65
const DEFAULT_HOLD_SECONDS: float = 1.80
const DEFAULT_HIDDEN_SECONDS: float = 0.90
const MAX_PRESENTATION_ALPHA: float = 0.72
const MIN_VISIBLE_SCALE: float = 0.82


static func uses_animated_shadow(species_id: StringName) -> bool:
	var key := str(species_id).strip_edges().to_lower()
	return TARGET_SPECIES.has(key)


static func get_cycle_duration(
	hold_seconds: float = DEFAULT_HOLD_SECONDS,
	hidden_seconds: float = DEFAULT_HIDDEN_SECONDS
) -> float:
	return (
		RISE_SECONDS
		+ maxf(hold_seconds, 0.0)
		+ SINK_SECONDS
		+ maxf(hidden_seconds, 0.0)
	)


static func get_visibility_envelope(
	cycle_time: float,
	hold_seconds: float = DEFAULT_HOLD_SECONDS,
	hidden_seconds: float = DEFAULT_HIDDEN_SECONDS
) -> float:
	var hold := maxf(hold_seconds, 0.0)
	var hidden := maxf(hidden_seconds, 0.0)
	var duration := get_cycle_duration(hold, hidden)
	if duration <= 0.0001:
		return 1.0

	var t := fposmod(maxf(cycle_time, 0.0), duration)
	if t < RISE_SECONDS:
		return smoothstep(0.0, RISE_SECONDS, t)
	t -= RISE_SECONDS
	if t < hold:
		return 1.0
	t -= hold
	if t < SINK_SECONDS:
		return 1.0 - smoothstep(0.0, SINK_SECONDS, t)
	return 0.0


static func get_presented_alpha(base_alpha: float, envelope: float) -> float:
	return clampf(base_alpha, 0.0, 1.0) * clampf(envelope, 0.0, 1.0) * MAX_PRESENTATION_ALPHA


static func get_presented_scale(envelope: float) -> float:
	return lerpf(MIN_VISIBLE_SCALE, 1.0, clampf(envelope, 0.0, 1.0))


static func get_species_scale_multiplier(species_id: StringName) -> float:
	match str(species_id).strip_edges().to_lower():
		"octopus":
			return 1.18
		"martian_squid":
			return 1.10
		"man_o_war":
			return 1.04
		_:
			return 1.0


static func get_animation_speed_scale(species_id: StringName) -> float:
	match str(species_id).strip_edges().to_lower():
		"octopus":
			return 0.88
		"martian_squid":
			return 1.08
		"man_o_war":
			return 0.82
		_:
			return 0.92
