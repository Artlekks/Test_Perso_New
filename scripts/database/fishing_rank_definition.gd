extends Resource
class_name FishingRankDefinition

@export_category("Identity")
@export var rank_id: StringName = &""
@export var display_name: String = ""

@export_category("Threshold")
## Inclusive lower bound used by the current project.
@export_range(0, 9999, 1)
var min_points: int = 0


func is_valid_definition() -> bool:
	return (
		rank_id != &""
		and not display_name.strip_edges().is_empty()
		and min_points >= 0
	)
