extends Resource
class_name FishData

@export var fish_name: String = ""

@export_category("Size / King")
@export var average_size: float = 1.0
@export var king_size: float = 2.0

## Chance that a newly created FishInstance rolls in the crown/king band.
## Gameplay tuning only; this is not claimed to reproduce original BOF4 RNG.
@export_range(0.0, 1.0, 0.005)
var king_chance: float = 0.015

## A king can roll from king_size up to king_size * this multiplier.
@export_range(1.0, 1.25, 0.01)
var king_max_size_multiplier: float = 1.05

@export_category("Size Distribution")

## Chance for a non-king catch to roll directly in the near-record band.
## This probability is evaluated alongside king_chance, so 0.06 means
## approximately six catches in one hundred before species/spot selection.
@export_range(0.0, 0.50, 0.005)
var near_record_chance: float = 0.06

## Near-record fish begin at this fraction of king_size and remain below crown.
@export_range(0.75, 0.99, 0.01)
var near_record_min_size_ratio: float = 0.90

## Lowest ordinary size relative to average_size. 0.80 works well with the
## authored BOF4 data because average_size is usually about 75% of king_size.
@export_range(0.25, 1.0, 0.05)
var normal_min_average_multiplier: float = 0.80

## Averaging several random samples makes ordinary catches cluster around the
## species average instead of distributing uniformly from tiny to near-record.
@export_range(1, 6, 1)
var normal_roll_samples: int = 3

## Near-record sizes are biased toward the bottom of their band, so a fish one
## centimetre below crown is rarer than simply entering the near-record band.
@export_range(1, 5, 1)
var near_record_roll_samples: int = 2

@export_category("Fight Stats")
@export var base_stamina: float = 100.0
@export var base_strength: float = 1.0

@export_category("Depth Preference")

## Normalized lure depth. 0.0 = surface, 1.0 = bottom.
@export_range(0.0, 1.0, 0.01)
var preferred_depth_min: float = 0.0

## Normalized lure depth. 0.0 = surface, 1.0 = bottom.
@export_range(0.0, 1.0, 0.01)
var preferred_depth_max: float = 1.0

## Distance outside the preferred band over which attraction falls from
## perfect to the minimum multiplier.
@export_range(0.01, 1.0, 0.01)
var depth_falloff_width: float = 0.25

## Fish are still possible outside their ideal depth; they are simply much
## less likely to be attracted/selected.
@export_range(0.0, 1.0, 0.01)
var out_of_depth_multiplier: float = 0.15

@export var max_points: int = 100

@export_category("Lure Preferences")

@export var accepts_all_lures: bool = false

@export var preferred_lure_types: Array[LureType.Type] = []

@export var preferred_lure_ids: Array[StringName] = []

@export_category("Fight Behavior")
@export var behavior_profile: FishBehaviorProfile

@export_category("Endurance")

@export_range(1, 8, 1)
var resistance_rounds: int = 2

@export var recovery_time_min: float = 0.8
@export var recovery_time_max: float = 1.5

@export_category("Shadow Presentation")

## Selects the visual family used by the reusable fish-shadow presence system.
## Profiles may point to different FishShadowActor scenes while sharing the
## same pre-bite, fight-tracking, and encounter logic.
enum ShadowVisualProfile {
	LONG_FISH,
	ROUND,
	WIDE,
	SQUID,
	JELLY,
}

@export var shadow_visual_profile: ShadowVisualProfile = ShadowVisualProfile.LONG_FISH

@export_category("Presentation")

@export var portrait: Texture2D

func get_lure_match_multiplier(bait: BaitData) -> float:
	if bait == null:
		return 1.0

	if bait.lure_id != &"" and preferred_lure_ids.has(bait.lure_id):
		return 1.5

	if accepts_all_lures:
		return 1.0

	if preferred_lure_types.has(bait.lure_type):
		return 1.0

	return 0.15

func get_depth_match_multiplier(
	current_depth: float,
	total_depth: float
) -> float:
	if total_depth <= 0.0:
		return 1.0

	var depth_ratio := clampf(
		current_depth / total_depth,
		0.0,
		1.0
	)

	var band_min := clampf(
		minf(
			preferred_depth_min,
			preferred_depth_max
		),
		0.0,
		1.0
	)

	var band_max := clampf(
		maxf(
			preferred_depth_min,
			preferred_depth_max
		),
		0.0,
		1.0
	)

	if (
		depth_ratio >= band_min
		and depth_ratio <= band_max
	):
		return 1.0

	var distance_from_band := 0.0

	if depth_ratio < band_min:
		distance_from_band = (
			band_min - depth_ratio
		)
	else:
		distance_from_band = (
			depth_ratio - band_max
		)

	var falloff := maxf(
		depth_falloff_width,
		0.01
	)

	var t := clampf(
		distance_from_band / falloff,
		0.0,
		1.0
	)

	# Smoothstep keeps attraction from changing abruptly as the lure crosses
	# the edge of a preferred depth band.
	var eased := t * t * (3.0 - 2.0 * t)

	return lerpf(
		1.0,
		clampf(
			out_of_depth_multiplier,
			0.0,
			1.0
		),
		eased
	)
