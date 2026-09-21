extends Node
class_name FishingTechniqueDetector

signal technique_triggered(level: int)

enum IntervalKind {
	SHORT,
	PAUSE
}

# First-pass timing windows.
# These are authored feel values, NOT claimed original-engine timings.
@export var minimum_input_interval: float = 0.06
@export var short_interval_min: float = 0.08
@export var short_interval_max: float = 0.30
@export var pause_interval_min: float = 0.34
@export var pause_interval_max: float = 0.75
@export var sequence_reset_gap: float = 0.95

# Pattern groups are based on the documented BOF IV lure rhythms:
# Tec 1 = 1 / 1 / 1
# Tec 2 = 1 / 2 / 1
# Tec 3 = 1 / 2 / 2
# Tec 4 = 3 / 2 / 1
#
# Converted to interval kinds:
# Tec 1: P P
# Tec 2: P S P
# Tec 3: P S P S
# Tec 4: S S P S P
const TECH_PATTERNS := {
	1: [
		IntervalKind.PAUSE,
		IntervalKind.PAUSE
	],
	2: [
		IntervalKind.PAUSE,
		IntervalKind.SHORT,
		IntervalKind.PAUSE
	],
	3: [
		IntervalKind.PAUSE,
		IntervalKind.SHORT,
		IntervalKind.PAUSE,
		IntervalKind.SHORT
	],
	4: [
		IntervalKind.SHORT,
		IntervalKind.SHORT,
		IntervalKind.PAUSE,
		IntervalKind.SHORT,
		IntervalKind.PAUSE
	]
}

var _pulse_times: Array[float] = []
var _pending_level: int = 0
var _pending_deadline: float = 0.0


func _process(_delta: float) -> void:
	if _pending_level <= 0:
		return

	var now := _now_seconds()

	if now < _pending_deadline:
		return

	var level := _pending_level
	_pending_level = 0
	_pending_deadline = 0.0
	_pulse_times.clear()

	technique_triggered.emit(level)


func record_pulse() -> void:
	var now := _now_seconds()

	if not _pulse_times.is_empty():
		var gap := now - _pulse_times[-1]

		if gap < minimum_input_interval:
			return

		if gap > sequence_reset_gap:
			reset()

	# If Tec 2 was waiting to see whether it would extend into Tec 3,
	# a new pulse means the longer sequence gets a chance first.
	_pending_level = 0
	_pending_deadline = 0.0

	_pulse_times.append(now)

	while _pulse_times.size() > 6:
		_pulse_times.pop_front()

	var level := _match_highest_complete_pattern()

	if level <= 0:
		return

	# Tec 2 is a prefix of Tec 3. Delay Tec 2 very briefly so a final
	# short pulse can promote it to Tec 3 instead of firing too early.
	if level == 2 and _can_extend_to_tech_3():
		_pending_level = 2
		_pending_deadline = now + short_interval_max
		return

	_pulse_times.clear()
	technique_triggered.emit(level)


func reset() -> void:
	_pulse_times.clear()
	_pending_level = 0
	_pending_deadline = 0.0


func _match_highest_complete_pattern() -> int:
	for level in [4, 3, 2, 1]:
		var pattern: Array = TECH_PATTERNS[level]

		if _matches_tail(pattern):
			return level

	return 0


func _matches_tail(pattern: Array) -> bool:
	var required_pulses := pattern.size() + 1

	if _pulse_times.size() < required_pulses:
		return false

	var start_index := _pulse_times.size() - required_pulses

	for interval_index in pattern.size():
		var a: float = _pulse_times[
			start_index + interval_index
		]
		var b: float = _pulse_times[
			start_index + interval_index + 1
		]

		var interval := b - a
		var kind: int = pattern[interval_index]

		if not _interval_matches(interval, kind):
			return false

	return true


func _interval_matches(
	interval: float,
	kind: int
) -> bool:
	match kind:
		IntervalKind.SHORT:
			return (
				interval >= short_interval_min
				and interval <= short_interval_max
			)
		IntervalKind.PAUSE:
			return (
				interval >= pause_interval_min
				and interval <= pause_interval_max
			)

	return false


func _can_extend_to_tech_3() -> bool:
	var tech_3_pattern: Array = TECH_PATTERNS[3]
	var tech_2_pattern: Array = TECH_PATTERNS[2]

	if tech_3_pattern.size() != tech_2_pattern.size() + 1:
		return false

	for index in tech_2_pattern.size():
		if tech_2_pattern[index] != tech_3_pattern[index]:
			return false

	return true


func _now_seconds() -> float:
	return Time.get_ticks_msec() / 1000.0
