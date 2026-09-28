extends Resource

## Data-only contract for what each fishing outcome is allowed to change.
## Presentation (textures/animations) is deliberately not owned here.

@export_category("Miss")
@export var miss_ends_cast: bool = false
@export var miss_consumes_lure: bool = false

@export_category("Hook Off")
@export var hook_off_ends_cast: bool = true
@export var hook_off_consumes_lure: bool = false

@export_category("Line Break")
@export var line_break_ends_cast: bool = true
@export var line_break_consumes_lure: bool = true

@export_category("Catch")
@export var catch_ends_cast: bool = true
@export var catch_consumes_lure: bool = false
@export var catch_records_progress: bool = true
@export var catch_evaluates_rewards: bool = true

@export_category("Cancel")
@export var cancel_ends_cast: bool = true
@export var cancel_consumes_lure: bool = false

@export_category("Safety")
## Until shops/gathering can replenish bait, never let a line break consume the
## final owned lure and soft-lock the fishing loop.
@export var protect_last_owned_lure: bool = true


func is_valid_policy() -> bool:
	return (
		not miss_ends_cast
		and not miss_consumes_lure
		and hook_off_ends_cast
		and line_break_ends_cast
		and catch_ends_cast
		and cancel_ends_cast
		and catch_records_progress
	)


func get_rule(outcome: StringName) -> Dictionary:
	match outcome:
		&"miss":
			return {
				"terminal": miss_ends_cast,
				"consume_lure": miss_consumes_lure,
				"record_catch": false,
				"evaluate_rewards": false,
			}
		&"hook_off":
			return {
				"terminal": hook_off_ends_cast,
				"consume_lure": hook_off_consumes_lure,
				"record_catch": false,
				"evaluate_rewards": false,
			}
		&"line_break":
			return {
				"terminal": line_break_ends_cast,
				"consume_lure": line_break_consumes_lure,
				"record_catch": false,
				"evaluate_rewards": false,
			}
		&"catch":
			return {
				"terminal": catch_ends_cast,
				"consume_lure": catch_consumes_lure,
				"record_catch": catch_records_progress,
				"evaluate_rewards": catch_evaluates_rewards,
			}
		&"cancelled":
			return {
				"terminal": cancel_ends_cast,
				"consume_lure": cancel_consumes_lure,
				"record_catch": false,
				"evaluate_rewards": false,
			}
		_:
			return {
				"terminal": false,
				"consume_lure": false,
				"record_catch": false,
				"evaluate_rewards": false,
			}
