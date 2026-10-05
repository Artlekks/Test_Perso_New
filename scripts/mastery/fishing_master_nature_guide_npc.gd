extends FishingMasterLessonNPCBase
class_name FishingMasterNatureGuideNPC

const LessonPolicy = preload(
	"res://scripts/mastery/fishing_master_nature_guide_policy.gd"
)

const TECHNIQUE_ID: StringName = &"one_with_nature"
const TEACHER_ID: StringName = &"master_nature_guide"

enum LessonPhase {
	INACTIVE,
	SETTLING,
	PRESENTING,
	COMPLETE,
}

var _phase: LessonPhase = LessonPhase.INACTIVE
var _fish_zone: Node = null
var _fish_presence: Node = null
var _settle_seconds: float = 0.0
var _presentation_seconds: float = 0.0
var _was_settled: bool = false
var _latest_presentation: float = 0.0
var _latest_target: Dictionary = {}
var _latest_sign_snapshot: Dictionary = {}


func get_technique_id() -> StringName:
	return TECHNIQUE_ID


func get_teacher_id() -> StringName:
	return TEACHER_ID


func get_known_message() -> String:
	return "Nature Guide: Good. Now the bank, the fish, and the lure are one conversation."


func get_unavailable_message() -> String:
	return "Nature Guide: First learn Quiet Approach and Read Fish Sign. Then come back and we will put them together."


func _process(delta: float) -> void:
	if _phase == LessonPhase.INACTIVE or _phase == LessonPhase.COMPLETE:
		return
	if is_technique_known():
		_phase = LessonPhase.COMPLETE
		return
	if not _bind_lesson_runtime():
		return

	var disturbance := _get_player_disturbance()
	_settle_seconds = LessonPolicy.advance_settle_time(
		_settle_seconds,
		disturbance,
		delta
	)
	var settled := LessonPolicy.is_settled(_settle_seconds)

	if not settled:
		if _was_settled:
			_presentation_seconds = 0.0
			_show_message(
				"Nature Guide: You broke the stillness. Settle again before you present the lure.",
				3.0
			)
		_phase = LessonPhase.SETTLING
		_was_settled = false
		return

	if not _was_settled:
		_was_settled = true
		_phase = LessonPhase.PRESENTING
		_show_message(
			"Nature Guide: Now read the water. Place a natural lure presentation close to a wary fish without disturbing the bank.",
			5.0
		)

	_update_presentation(delta)


func _on_lesson_interaction() -> void:
	if not _bind_lesson_runtime():
		_show_message(get_unavailable_message(), 3.0)
		return

	match _phase:
		LessonPhase.INACTIVE:
			_begin_lesson()
		LessonPhase.SETTLING:
			_show_message(
				"Nature Guide: Stop moving and let the bank forget you are here. %d%%"
				% int(round(LessonPolicy.get_settle_progress_ratio(_settle_seconds) * 100.0)),
				3.0
			)
		LessonPhase.PRESENTING:
			_show_presentation_status()
		LessonPhase.COMPLETE:
			pass


func _begin_lesson() -> void:
	if _mastery_service == null:
		_show_message(get_unavailable_message(), 2.6)
		return

	var availability := _mastery_service.can_learn(TECHNIQUE_ID, TEACHER_ID)
	if not bool(availability.get("can_learn", false)):
		_show_message(get_unavailable_message(), 4.2)
		return

	_reset_lesson_progress()
	_phase = LessonPhase.SETTLING
	_play_animation(talk_animation)
	_show_message(
		"Nature Guide: You already know stillness, and you already know fish sign. Now combine them. Settle completely. Then make one natural presentation to a wary fish the water has revealed.",
		7.0
	)


func _update_presentation(delta: float) -> void:
	var bait := _get_active_bait()
	_latest_sign_snapshot = _get_fish_sign_snapshot()
	_latest_target = {}
	_latest_presentation = 0.0

	if not is_instance_valid(bait):
		_presentation_seconds = 0.0
		return
	if not bait.has_method("get_presentation_attraction_multiplier"):
		_presentation_seconds = 0.0
		return

	_latest_presentation = clampf(
		float(bait.call("get_presentation_attraction_multiplier")),
		0.25,
		2.0
	)
	_latest_target = _find_wary_target(bait)
	var has_target := bool(_latest_target.get("found", false))
	var has_clear_sign := (
		bool(_latest_sign_snapshot.get("available", false))
		and int(_latest_sign_snapshot.get("sign_count", 0)) > 0
	)

	_presentation_seconds = LessonPolicy.advance_presentation_time(
		_presentation_seconds,
		_settle_seconds,
		_latest_presentation,
		float(_latest_target.get("wariness", 0.0)) if has_target else 0.0,
		float(_latest_target.get("distance", 999.0)) if has_target else 999.0,
		bool(_latest_target.get("readable", false)) if has_target else false,
		has_clear_sign,
		delta
	)

	if LessonPolicy.is_complete(_settle_seconds, _presentation_seconds):
		_complete_lesson()


func _complete_lesson() -> void:
	var learned := try_learn_technique(true)
	if bool(learned.get("success", false)):
		_phase = LessonPhase.COMPLETE
		_play_animation(talk_animation)
		_show_message(
			"Technique learned — One With Nature. Settle, read the fish, and let a natural presentation do the work instead of forcing the water.",
			6.0
		)
		return
	_show_message(
		"Nature Guide: That was the right lesson, but it could not be saved yet.",
		3.2
	)


func _show_presentation_status() -> void:
	var bait := _get_active_bait()
	if not is_instance_valid(bait):
		_show_message(
			"Nature Guide: You are settled. Now cast without rushing the retrieve.",
			3.2
		)
		return
	if not bool(_latest_sign_snapshot.get("available", false)) or int(_latest_sign_snapshot.get("sign_count", 0)) <= 0:
		_show_message(
			"Nature Guide: The lure is out, but the water is not giving you a readable fish sign yet.",
			3.2
		)
		return
	if not LessonPolicy.is_natural_presentation(_latest_presentation):
		_show_message(
			"Nature Guide: Too forced. Let the lure move naturally before asking the fish to trust it.",
			3.2
		)
		return
	if not bool(_latest_target.get("found", false)):
		_show_message(
			"Nature Guide: Read the sign and bring that natural presentation close to a wary visible fish.",
			3.2
		)
		return
	_show_message(
		"Nature Guide: Hold it. Don't add anything. %d%%"
		% int(round(LessonPolicy.get_presentation_progress_ratio(_presentation_seconds) * 100.0)),
		3.0
	)


func _bind_lesson_runtime() -> bool:
	if not _bind_runtime():
		return false
	if is_instance_valid(_fish_zone) and is_instance_valid(_fish_presence):
		return true

	var world := get_parent()
	if world == null:
		return false
	_fish_zone = world.get_node_or_null("FishZone_V2")
	if _fish_zone == null:
		_fish_zone = world.find_child("FishZone_V2", true, false)
	if _fish_zone == null:
		return false
	_fish_presence = _fish_zone.get_node_or_null("FishShadowPresence")
	if _fish_presence == null:
		_fish_presence = _fish_zone.find_child("FishShadowPresence", true, false)
	return is_instance_valid(_fish_presence)


func _get_player_disturbance() -> float:
	if not is_instance_valid(_player):
		_player = _find_player()
	if not is_instance_valid(_player):
		return 1.0
	if not _player.has_method("get_fishing_disturbance_strength"):
		return 1.0
	return clampf(
		float(_player.call("get_fishing_disturbance_strength")),
		0.0,
		1.0
	)


func _get_active_bait() -> Node3D:
	var tree := get_tree()
	if tree == null:
		return null
	var bait := tree.get_first_node_in_group("bait")
	return bait as Node3D


func _get_fish_sign_snapshot() -> Dictionary:
	if not is_instance_valid(_fish_zone):
		return {"available": false, "sign_count": 0}
	if not _fish_zone.has_method("get_fish_sign_snapshot"):
		return {"available": false, "sign_count": 0}
	var snapshot = _fish_zone.call("get_fish_sign_snapshot")
	if snapshot is Dictionary:
		return (snapshot as Dictionary).duplicate(true)
	return {"available": false, "sign_count": 0}


func _find_wary_target(bait: Node3D) -> Dictionary:
	if not is_instance_valid(_fish_presence) or not is_instance_valid(bait):
		return {"found": false}

	var best := {
		"found": false,
		"wariness": 0.0,
		"distance": 999.0,
		"readable": false,
		"species_name": "",
	}
	for child in _fish_presence.get_children():
		var shadow := child as Node3D
		if not is_instance_valid(shadow):
			continue
		if shadow.has_method("is_hooked_tracking") and bool(shadow.call("is_hooked_tracking")):
			continue
		if not shadow.has_method("get_fish_data"):
			continue
		var fish = shadow.call("get_fish_data")
		if fish == null:
			continue
		var readable := true
		if shadow.has_method("is_ambient_readable"):
			readable = bool(shadow.call("is_ambient_readable"))
		var wariness := clampf(float(fish.get("approach_wariness")), 0.0, 1.0)
		var offset: Vector3 = shadow.global_position - bait.global_position
		offset.y = 0.0
		var distance: float = offset.length()
		if not LessonPolicy.is_wary_target(wariness, distance, readable):
			continue
		if distance >= float(best.get("distance", 999.0)):
			continue
		var species_name := "fish"
		if fish.has_method("get_journal_name"):
			species_name = str(fish.call("get_journal_name"))
		best = {
			"found": true,
			"wariness": wariness,
			"distance": distance,
			"readable": readable,
			"species_name": species_name,
		}
	return best


func _reset_lesson_progress() -> void:
	_settle_seconds = 0.0
	_presentation_seconds = 0.0
	_was_settled = false
	_latest_presentation = 0.0
	_latest_target = {}
	_latest_sign_snapshot = {}
