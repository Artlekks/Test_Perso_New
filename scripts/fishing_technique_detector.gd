extends Node
class_name FishingTechniqueDetector

signal technique_triggered(level: int)

const DefaultTechniqueCatalog: FishingTechniqueCatalog = preload(
	"res://data/bof4/techniques/all_techniques.tres"
)

var technique_catalog: FishingTechniqueCatalog = (
	DefaultTechniqueCatalog
)

var _pulse_times: Array[float] = []
var _pending_level: int = 0
var _pending_deadline: float = 0.0

var _last_triggered_level: int = 0
var _last_input_source: StringName = &""
var _last_input_interval: float = 0.0


func _ready() -> void:
	set_process(false)


func configure(
	new_catalog: FishingTechniqueCatalog
) -> void:
	if (
		new_catalog == null
		or not new_catalog.is_valid_catalog()
	):
		return

	technique_catalog = new_catalog
	reset()


func _process(_delta: float) -> void:
	if _pending_level <= 0:
		set_process(false)
		return

	var now: float = _now_seconds()

	if now < _pending_deadline:
		return

	var level: int = _pending_level

	_pending_level = 0
	_pending_deadline = 0.0
	_pulse_times.clear()
	set_process(false)

	_emit_technique(level)


func record_pulse(
	input_source: StringName = &""
) -> void:
	if technique_catalog == null:
		return

	var now: float = _now_seconds()

	if not _pulse_times.is_empty():
		var gap: float = (
			now - _pulse_times[-1]
		)
		_last_input_interval = gap

		if (
			gap
			< technique_catalog.minimum_input_interval
		):
			return

		if (
			gap
			> technique_catalog.sequence_reset_gap
		):
			reset()

	_pending_level = 0
	_pending_deadline = 0.0
	set_process(false)

	_last_input_source = input_source
	_pulse_times.append(now)

	var max_pulses: int = maxi(
		technique_catalog.get_max_required_pulses(),
		1
	)

	while _pulse_times.size() > max_pulses:
		_pulse_times.pop_front()

	var definition: FishingTechniqueDefinition = (
		_match_highest_complete_definition()
	)

	if definition == null:
		return

	var extension_wait: float = (
		technique_catalog.get_extension_wait_seconds(
			definition
		)
	)

	if extension_wait > 0.0:
		_pending_level = definition.level
		_pending_deadline = (
			now + extension_wait
		)
		set_process(true)
		return

	_pulse_times.clear()
	_emit_technique(
		definition.level
	)


func reset() -> void:
	_pulse_times.clear()
	_pending_level = 0
	_pending_deadline = 0.0
	_last_input_interval = 0.0
	set_process(false)


func get_debug_snapshot() -> Dictionary:
	return {
		"pulse_count": _pulse_times.size(),
		"pending_level": _pending_level,
		"last_triggered_level": _last_triggered_level,
		"last_input_source": str(_last_input_source),
		"last_input_interval": _last_input_interval,
	}


func _match_highest_complete_definition() -> FishingTechniqueDefinition:
	for definition in technique_catalog.get_techniques_descending():
		if _matches_tail(definition):
			return definition

	return null


func _matches_tail(
	definition: FishingTechniqueDefinition
) -> bool:
	if definition == null:
		return false

	var pattern: PackedInt32Array = (
		definition.get_interval_pattern()
	)
	var required_pulses: int = (
		pattern.size() + 1
	)

	if _pulse_times.size() < required_pulses:
		return false

	var start_index: int = (
		_pulse_times.size()
		- required_pulses
	)

	for interval_index in range(pattern.size()):
		var a: float = _pulse_times[
			start_index + interval_index
		]
		var b: float = _pulse_times[
			start_index + interval_index + 1
		]
		var interval: float = b - a
		var kind: int = int(
			pattern[interval_index]
		)

		if not technique_catalog.interval_matches(
			interval,
			kind
		):
			return false

	return true


func _emit_technique(
	level: int
) -> void:
	var definition: FishingTechniqueDefinition = (
		technique_catalog.get_technique(level)
	)

	if definition == null:
		return

	_last_triggered_level = level
	technique_triggered.emit(level)


func _now_seconds() -> float:
	return (
		Time.get_ticks_msec()
		/ 1000.0
	)
