extends Resource

@export var profile_id: StringName = &"balanced"
@export var display_name: String = "Balanced"
@export_range(0.0, 300.0, 1.0) var capture_weight: float = 100.0
@export_range(0.0, 300.0, 1.0) var same_trigger_weight: float = 65.0
@export_range(0.0, 300.0, 1.0) var plus_trigger_weight: float = 65.0
@export_range(0.0, 10.0, 0.1) var positional_weight: float = 1.0
@export_range(-5.0, 5.0, 0.05) var card_strength_weight: float = 0.08
@export_range(0.0, 10.0, 0.1) var conserve_cost_weight: float = 0.3
@export_range(0.0, 100.0, 1.0) var rotate_spend_penalty: float = 16.0
@export_range(0.0, 50.0, 0.5) var randomness: float = 1.5
