extends Resource
class_name FishBehaviorProfile

@export_category("Movement")
@export_range(0.0, 1.0, 0.05)
var lateral_activity: float = 1.0

@export_range(0.0, 1.0, 0.05)
var vertical_activity: float = 1.0

@export var direction_change_min: float = 0.8
@export var direction_change_max: float = 2.0

@export_category("Behavior Weights")
@export_range(0.0, 5.0, 0.1)
var surge_weight: float = 1.0

@export_range(0.0, 5.0, 0.1)
var side_run_weight: float = 1.0

@export_range(0.0, 5.0, 0.1)
var dive_weight: float = 1.0

@export_range(0.0, 5.0, 0.1)
var rise_weight: float = 1.0

@export_range(0.0, 5.0, 0.1)
var erratic_weight: float = 1.0

@export_category("Thrashing")
@export_range(0.0, 1.0, 0.05)
var thrash_chance: float = 0.20

@export_range(1.0, 2.0, 0.05)
var thrash_multiplier: float = 1.35
