extends Resource
class_name FishingRecordMercyPolicy

## Invisible anti-bad-luck policy for specimen records.
##
## This policy never guarantees a record and never changes authored fish size
## bands. After several completed catches of the same species fail to improve
## its record, it grants a capped chance for ONE additional normal specimen
## roll. The larger of the normal roll and bonus roll is kept.
##
## Keeping the help as an extra roll means authored king/near-record chances
## remain the source distribution. Mercy only gives the player a second chance
## to sample that same distribution.

@export_category("Activation")
@export var enabled: bool = true

## Number of consecutive non-record catches before assistance can begin.
@export_range(1, 20, 1)
var failures_before_help: int = 3

@export_category("Bonus Roll")
## Added chance for each eligible failed record catch.
@export_range(0.0, 1.0, 0.01)
var bonus_roll_chance_per_failure: float = 0.10

## Hard ceiling. Even a very long dry streak never guarantees a bonus roll.
@export_range(0.0, 0.95, 0.01)
var max_bonus_roll_chance: float = 0.65

## Extension point for future difficulty/event rules. Default gameplay uses one
## possible bonus roll, keeping the system subtle and cheap.
@export_range(1, 3, 1)
var max_bonus_rolls: int = 1

@export_category("Persistence Safety")
## Stored streaks are capped so corrupted/ancient saves cannot grow forever.
@export_range(1, 999, 1)
var tracked_streak_cap: int = 99


func is_valid_policy() -> bool:
	return (
		failures_before_help >= 1
		and bonus_roll_chance_per_failure >= 0.0
		and bonus_roll_chance_per_failure <= 1.0
		and max_bonus_roll_chance >= 0.0
		and max_bonus_roll_chance <= 0.95
		and max_bonus_rolls >= 1
		and max_bonus_rolls <= 3
		and tracked_streak_cap >= 1
	)


func get_next_miss_streak(
	previous_streak: int,
	record_improved: bool,
	record_complete: bool
) -> int:
	if record_improved or record_complete:
		return 0

	return clampi(
		maxi(previous_streak, 0) + 1,
		0,
		maxi(tracked_streak_cap, 1)
	)


func build_generation_context(
	miss_streak: int,
	best_points: int,
	max_points: int
) -> Dictionary:
	var safe_streak: int = clampi(
		maxi(miss_streak, 0),
		0,
		maxi(tracked_streak_cap, 1)
	)
	var safe_best: int = maxi(best_points, 0)
	var safe_max: int = maxi(max_points, 0)
	var record_complete: bool = (
		safe_max > 0
		and safe_best >= safe_max
	)
	var eligible_failures: int = maxi(
		safe_streak - maxi(failures_before_help, 1) + 1,
		0
	)
	var bonus_chance: float = 0.0

	if (
		enabled
		and not record_complete
		and eligible_failures > 0
	):
		bonus_chance = clampf(
			float(eligible_failures)
			* clampf(bonus_roll_chance_per_failure, 0.0, 1.0),
			0.0,
			clampf(max_bonus_roll_chance, 0.0, 0.95)
		)

	return {
		"active": bonus_chance > 0.0,
		"miss_streak": safe_streak,
		"failures_before_help": maxi(failures_before_help, 1),
		"eligible_failures": eligible_failures,
		"bonus_roll_chance": bonus_chance,
		"max_bonus_rolls": clampi(max_bonus_rolls, 1, 3),
		"record_complete": record_complete,
		"best_points": safe_best,
		"max_points": safe_max,
	}
