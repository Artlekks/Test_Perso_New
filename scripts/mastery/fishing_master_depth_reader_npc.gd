extends FishingMasterLessonNPCBase
class_name FishingMasterDepthReaderNPC

const LessonPolicy = preload(
	"res://scripts/mastery/fishing_master_depth_reader_policy.gd"
)

const TECHNIQUE_ID: StringName = &"read_depth"
const TEACHER_ID: StringName = &"master_depth_reader"

enum LessonPhase {
	INACTIVE,
	WAITING_FOR_CAST,
	READING_DEPTH,
	COMPLETE,
}

var _phase: LessonPhase = LessonPhase.INACTIVE
var _caster: Node = null
var _observation_seconds: float = 0.0
var _seen_shallow: bool = false
var _seen_mid: bool = false
var _seen_deep: bool = false
var _had_active_bait: bool = false
var _reeling_warning_shown: bool = false
var _shallow_water_warning_shown: bool = false
var _last_announced_band: StringName = &""


func get_technique_id() -> StringName:
	return TECHNIQUE_ID


func get_teacher_id() -> StringName:
	return TEACHER_ID


func get_known_message() -> String:
	return "Depth Reader: Surface, middle, bottom. Read the whole column before deciding where the lure belongs."


func get_unavailable_message() -> String:
	return "Depth Reader: I need a live cast to teach this lesson."


func _process(delta: float) -> void:
	if _phase == LessonPhase.INACTIVE or _phase == LessonPhase.COMPLETE:
		return
	if is_technique_known():
		_phase = LessonPhase.COMPLETE
		return
	if not _bind_lesson_runtime():
		return

	if _phase == LessonPhase.WAITING_FOR_CAST:
		_try_begin_depth_read()
		return
	if _phase == LessonPhase.READING_DEPTH:
		_update_depth_read(delta)


func _on_lesson_interaction() -> void:
	if not _bind_lesson_runtime():
		_show_message(get_unavailable_message(), 2.4)
		return

	match _phase:
		LessonPhase.INACTIVE:
			_begin_lesson()
		LessonPhase.WAITING_FOR_CAST:
			_show_message(
				"Depth Reader: Cast into water with some depth. Once the lure lands, release K and let it fall naturally.",
				4.0
			)
		LessonPhase.READING_DEPTH:
			_show_message(
				"Depth Reader: Follow the lure through the water column. %d%%"
				% int(round(LessonPolicy.get_progress_ratio(
					_observation_seconds,
					_seen_shallow,
					_seen_mid,
					_seen_deep
				) * 100.0)),
				3.0
			)
		LessonPhase.COMPLETE:
			pass


func _begin_lesson() -> void:
	_reset_observation()
	_phase = LessonPhase.WAITING_FOR_CAST
	_play_animation(talk_animation)
	_show_message(
		"Depth Reader: Don't guess from the surface. Cast, leave the reel alone, and watch the lure pass through shallow, middle, then deep water.",
		5.2
	)


func _try_begin_depth_read() -> void:
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

	_reset_observation()
	_had_active_bait = true
	_phase = LessonPhase.READING_DEPTH
	_show_message(
		"Depth Reader: Good. No reeling. Watch how much water is above the lure and how much remains below it.",
		3.6
	)


func _update_depth_read(delta: float) -> void:
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
			_reset_observation()
			_show_message(
				"Depth Reader: Again. Let one cast fall through the whole water column without reeling.",
				3.3
			)
		return

	if not _caster.has_method("get_current_bait_depth"):
		return
	if not _caster.has_method("get_current_total_depth"):
		return

	var current_depth := float(_caster.call("get_current_bait_depth"))
	var total_depth := float(_caster.call("get_current_total_depth"))
	var reeling := (
		_caster.has_method("is_active_bait_reeling")
		and bool(_caster.call("is_active_bait_reeling"))
	)
	var result := LessonPolicy.advance_observation(
		_observation_seconds,
		_seen_shallow,
		_seen_mid,
		_seen_deep,
		current_depth,
		total_depth,
		reeling,
		delta
	)
	_observation_seconds = float(result.get("observation_seconds", 0.0))
	_seen_shallow = bool(result.get("seen_shallow", false))
	_seen_mid = bool(result.get("seen_mid", false))
	_seen_deep = bool(result.get("seen_deep", false))
	_had_active_bait = true

	if reeling and not _reeling_warning_shown:
		_reeling_warning_shown = true
		_show_message(
			"Depth Reader: You're changing the lure's depth yourself. Release K and let it sink naturally.",
			2.9
		)
	elif not reeling:
		_reeling_warning_shown = false

	var valid_water := bool(result.get("valid_water", false))
	if not valid_water and not _shallow_water_warning_shown:
		_shallow_water_warning_shown = true
		_show_message(
			"Depth Reader: Too little water here. Cast farther into a deeper pocket.",
			2.8
		)
	elif valid_water:
		_shallow_water_warning_shown = false

	var band: StringName = result.get("depth_band", &"invalid")
	if valid_water and not reeling and band != _last_announced_band:
		_last_announced_band = band
		match band:
			&"shallow":
				_show_message("Depth Reader: Shallow water. Keep watching.", 1.8)
			&"mid":
				_show_message("Depth Reader: Mid-water. Notice how much column remains.", 2.0)
			&"deep":
				_show_message("Depth Reader: Deep water. That's the full read.", 2.0)

	if bool(result.get("complete", false)):
		_complete_lesson()


func _complete_lesson() -> void:
	var learned := try_learn_technique(true)
	if bool(learned.get("success", false)):
		_phase = LessonPhase.COMPLETE
		_play_animation(talk_animation)
		_show_message(
			"Technique learned — Read the Depth. You can now interpret shelves, drop-offs and the water column before committing the cast.",
			5.0
		)
		return
	_show_message(
		"Depth Reader: You read the column correctly, but the lesson could not be saved yet.",
		3.2
	)


func _bind_lesson_runtime() -> bool:
	if not _bind_runtime():
		return false
	if _caster == null:
		var fishing := _find_fishing_root()
		if fishing != null:
			var raw_caster = fishing.get("caster")
			if raw_caster is Node:
				_caster = raw_caster
			if _caster == null:
				_caster = fishing.find_child("Caster", true, false)
	return _caster != null


func _reset_observation() -> void:
	_observation_seconds = 0.0
	_seen_shallow = false
	_seen_mid = false
	_seen_deep = false
	_had_active_bait = false
	_reeling_warning_shown = false
	_shallow_water_warning_shown = false
	_last_announced_band = &""
