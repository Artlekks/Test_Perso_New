extends Resource

@export var profile_id: StringName = &"balanced"
@export var display_name: String = "Balanced"
@export_range(0.0, 300.0, 1.0) var capture_weight: float = 100.0
@export_range(0.0, 300.0, 1.0) var same_trigger_weight: float = 65.0
@export_range(0.0, 300.0, 1.0) var plus_trigger_weight: float = 65.0
@export_range(0.0, 100.0, 1.0) var influence_weight: float = 8.0
## Values pressure on empty cells that constrains the opponent's NEXT placement.
@export_range(0.0, 100.0, 1.0) var future_setup_weight: float = 6.0
## Extra value for capturing an enemy Influence source, whose field flips next action.
@export_range(0.0, 100.0, 1.0) var influence_source_capture_weight: float = 18.0
## Penalizes placements whose exposed sides can immediately be beaten.
@export_range(0.0, 50.0, 0.5) var vulnerability_weight: float = 3.0
@export_range(0.0, 10.0, 0.1) var positional_weight: float = 1.0
@export_range(-5.0, 5.0, 0.05) var card_strength_weight: float = 0.08
## Legacy experimental hook. Shipped profiles use 0: deck cost is not spent in-match.
@export_range(0.0, 10.0, 0.1) var conserve_cost_weight: float = 0.0
@export_range(0.0, 100.0, 1.0) var rotate_spend_penalty: float = 16.0
@export_range(0.0, 50.0, 0.5) var randomness: float = 1.5


## Runtime-only rematch personality hooks. Authored .tres AI profiles leave these
## neutral; TripleTriadOpponentEvolution duplicates the profile and fills them.
@export_category("Signature Card Timing")
@export var signature_card_ids: PackedStringArray = PackedStringArray()
@export_range(0.0, 100.0, 0.5) var signature_early_play_penalty: float = 0.0
@export_range(0.0, 100.0, 0.5) var signature_late_play_bonus: float = 0.0
@export_range(1, 8, 1) var signature_late_empty_cell_threshold: int = 4
