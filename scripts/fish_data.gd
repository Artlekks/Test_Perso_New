extends Resource
class_name FishData

@export var fish_name: String = ""

@export var average_size: float = 1.0
@export var king_size: float = 2.0

@export var base_stamina: float = 100.0
@export var base_strength: float = 1.0

@export var preferred_depth_min: float = 0.0
@export var preferred_depth_max: float = 10.0

@export var max_points: int = 100

@export_category("Lure Preferences")

@export var accepts_all_lures: bool = false

@export var preferred_lure_types: Array[LureType.Type] = []

@export var preferred_lure_ids: Array[StringName] = []
@export var locations: Array[StringName] = []

@export_category("Fight Behavior")
@export var behavior_profile: FishBehaviorProfile

@export_category("Endurance")

@export_range(1, 8, 1)
var resistance_rounds: int = 2

@export var recovery_time_min: float = 0.8
@export var recovery_time_max: float = 1.5

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

	if depth_ratio >= preferred_depth_min \
	and depth_ratio <= preferred_depth_max:
		return 1.0

	return 0.2
