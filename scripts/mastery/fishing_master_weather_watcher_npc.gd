extends FishingMasterLessonNPCBase
class_name FishingMasterWeatherWatcherNPC

const LessonPolicy = preload(
	"res://scripts/mastery/fishing_master_weather_watcher_policy.gd"
)

const TECHNIQUE_ID: StringName = &"weather_sense"
const TEACHER_ID: StringName = &"master_weather_watcher"

enum LessonPhase {
	INACTIVE,
	WAITING_FOR_CAST,
	READING_WEATHER,
	COMPLETE,
}

var _phase: LessonPhase = LessonPhase.INACTIVE
var _environment_service: Node = null
var _caster: Node = null
var _target_band: StringName = &"even"
var _condition_signature: String = ""
var _condition_description: String = "the current weather"
var _hold_seconds: float = 0.0
var _had_active_bait: bool = false
var _wrong_depth_warning_shown: bool = false
var _shallow_water_warning_shown: bool = false


func get_technique_id() -> StringName:
	return TECHNIQUE_ID


func get_teacher_id() -> StringName:
	return TEACHER_ID


func get_known_message() -> String:
	return "Weather Watcher: Good. You read what the sky is doing to the water instead of treating weather like scenery."


func get_unavailable_message() -> String:
	return "Weather Watcher: I need live weather and a fishing cast to teach this lesson."


func _process(delta: float) -> void:
	if _phase == LessonPhase.INACTIVE or _phase == LessonPhase.COMPLETE:
		return
	if is_technique_known():
		_phase = LessonPhase.COMPLETE
		return
	if not _bind_lesson_runtime():
		return

	var weather_changed := _refresh_weather_target()
	if weather_changed and _phase == LessonPhase.READING_WEATHER:
		_hold_seconds = 0.0
		_wrong_depth_warning_shown = false
		_show_message(
			"Weather Watcher: Conditions changed. Read them again — %s now favors %s."
			% [_condition_description, LessonPolicy.get_band_label(_target_band)],
			4.0
		)

	if _phase == LessonPhase.WAITING_FOR_CAST:
		_try_begin_weather_read()
		return
	if _phase == LessonPhase.READING_WEATHER:
		_update_weather_read(delta)


func _on_lesson_interaction() -> void:
	if not _bind_lesson_runtime():
		_show_message(get_unavailable_message(), 2.4)
		return

	match _phase:
		LessonPhase.INACTIVE:
			_begin_lesson()
		LessonPhase.WAITING_FOR_CAST:
			_show_message(
				"Weather Watcher: %s favors %s. Cast and hold the lure in that layer."
				% [_condition_description, LessonPolicy.get_band_label(_target_band)],
				4.2
			)
		LessonPhase.READING_WEATHER:
			_show_message(
				"Weather Watcher: Hold %s. %d%%"
				% [
					LessonPolicy.get_band_label(_target_band),
					int(round(LessonPolicy.get_progress_ratio(_hold_seconds) * 100.0)),
				],
				3.0
			)
		LessonPhase.COMPLETE:
			pass


func _begin_lesson() -> void:
	if _mastery_service == null:
		_show_message(get_unavailable_message(), 2.4)
		return
	var quote := _mastery_service.can_learn(TECHNIQUE_ID, TEACHER_ID)
	if not bool(quote.get("can_learn", false)):
		_show_message("Weather Watcher: The lesson isn't available yet.", 3.0)
		return

	_refresh_weather_target()
	_hold_seconds = 0.0
	_had_active_bait = false
	_wrong_depth_warning_shown = false
	_shallow_water_warning_shown = false
	_phase = LessonPhase.WAITING_FOR_CAST
	_play_animation(talk_animation)
	_show_message(
		"Weather Watcher: Weather changes more than the view. %s is pushing activity toward %s. Put the lure there and hold it long enough to feel the pattern."
		% [_condition_description, LessonPolicy.get_band_label(_target_band)],
		6.5
	)


func _try_begin_weather_read() -> void:
	if _caster == null or not _caster.has_method("has_active_bait"):
		return
	if not bool(_caster.call("has_active_bait")):
		_had_active_bait = false
		return
	if not _caster.has_method("is_active_bait_in_water"):
		return
	if not bool(_caster.call("is_active_bait_in_water")):
		_had_active_bait = true
		return

	_hold_seconds = 0.0
	_had_active_bait = true
	_wrong_depth_warning_shown = false
	_shallow_water_warning_shown = false
	_phase = LessonPhase.READING_WEATHER
	_show_message(
		"Weather Watcher: Good. Work the lure into %s and keep it there."
		% LessonPolicy.get_band_label(_target_band),
		3.5
	)


func _update_weather_read(delta: float) -> void:
	if _caster == null:
		return
	if not _caster.has_method("has_active_bait"):
		return
	var has_bait := bool(_caster.call("has_active_bait"))
	var in_water := (
		has_bait
		and _caster.has_method("is_active_bait_in_water")
		and bool(_caster.call("is_active_bait_in_water"))
	)
	if not in_water:
		if _had_active_bait:
			_phase = LessonPhase.WAITING_FOR_CAST
			_hold_seconds = 0.0
			_had_active_bait = false
			_show_message(
				"Weather Watcher: Again. Read the conditions, then place the next cast in the favored layer.",
				3.5
			)
		return

	if not _caster.has_method("get_current_bait_depth"):
		return
	if not _caster.has_method("get_current_total_depth"):
		return

	var current_depth := float(_caster.call("get_current_bait_depth"))
	var total_depth := float(_caster.call("get_current_total_depth"))
	var result := LessonPolicy.advance_hold(
		_hold_seconds,
		_target_band,
		current_depth,
		total_depth,
		delta
	)
	_hold_seconds = float(result.get("hold_seconds", 0.0))
	_had_active_bait = true

	var valid_water := bool(result.get("valid_water", false))
	if not valid_water and not _shallow_water_warning_shown:
		_shallow_water_warning_shown = true
		_show_message(
			"Weather Watcher: Too little water here to read the column. Cast into a deeper pocket.",
			3.0
		)
	elif valid_water:
		_shallow_water_warning_shown = false

	var matching := bool(result.get("matching", false))
	if valid_water and not matching and not _wrong_depth_warning_shown:
		_wrong_depth_warning_shown = true
		_show_message(
			"Weather Watcher: Not that layer. Under %s, hold %s."
			% [_condition_description, LessonPolicy.get_band_label(_target_band)],
			3.2
		)
	elif matching:
		_wrong_depth_warning_shown = false

	if bool(result.get("complete", false)):
		_complete_lesson()


func _complete_lesson() -> void:
	var learned := try_learn_technique(true)
	if bool(learned.get("success", false)):
		_phase = LessonPhase.COMPLETE
		_play_animation(talk_animation)
		_show_message(
			"Technique learned — Weather Sense. You can now read how active conditions shift feeding, depth, specimen opportunity and fight risk.",
			6.0
		)
		return
	_show_message(
		"Weather Watcher: The read was right, but the lesson could not be saved yet.",
		3.4
	)


func _bind_lesson_runtime() -> bool:
	if not _bind_runtime():
		return false
	var tree := get_tree()
	if _environment_service == null and tree != null:
		var services := tree.root.get_node_or_null("FishingSessionServices")
		if services != null:
			if services.has_method("get_fishing_environment_service"):
				var raw_environment = services.call("get_fishing_environment_service")
				if raw_environment is Node:
					_environment_service = raw_environment
			if _environment_service == null:
				var raw_environment_property = services.get("environment_service")
				if raw_environment_property is Node:
					_environment_service = raw_environment_property
	if _caster == null:
		var fishing := _find_fishing_root()
		if fishing != null:
			var raw_caster = fishing.get("caster")
			if raw_caster is Node:
				_caster = raw_caster
			if _caster == null:
				_caster = fishing.find_child("Caster", true, false)
	return _environment_service != null and _caster != null


func _refresh_weather_target() -> bool:
	if _environment_service == null:
		return false
	if not _environment_service.has_method("get_depth_activity_profile"):
		return false
	var new_signature := _build_condition_signature()
	var profile: Dictionary = _environment_service.call("get_depth_activity_profile")
	var new_target := LessonPolicy.get_target_band(
		float(profile.get("surface", 1.0)),
		float(profile.get("mid", 1.0)),
		float(profile.get("deep", 1.0))
	)
	var changed := (
		new_signature != _condition_signature
		or new_target != _target_band
	)
	_condition_signature = new_signature
	_target_band = new_target
	_condition_description = _build_condition_description()
	return changed


func _build_condition_signature() -> String:
	if (
		_environment_service == null
		or not _environment_service.has_method("get_active_condition_ids")
	):
		return ""
	var ids: PackedStringArray = _environment_service.call("get_active_condition_ids")
	var signature := ""
	for raw_id in ids:
		if not signature.is_empty():
			signature += "|"
		signature += str(raw_id)
	return signature


func _build_condition_description() -> String:
	if (
		_environment_service == null
		or not _environment_service.has_method("get_active_condition_display_names")
	):
		return "the current weather"
	var names: PackedStringArray = _environment_service.call(
		"get_active_condition_display_names"
	)
	if names.is_empty():
		return "the current weather"
	var description := ""
	for raw_name in names:
		if not description.is_empty():
			description += " + "
		description += str(raw_name)
	return description
