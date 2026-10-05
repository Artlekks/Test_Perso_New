extends FishingMasterLessonNPCBase
class_name FishingMasterSignReaderNPC

const LessonPolicy = preload(
	"res://scripts/mastery/fishing_master_sign_reader_policy.gd"
)
const FishSignPolicy = preload(
	"res://scripts/fishing_fish_sign_policy.gd"
)

const TECHNIQUE_ID: StringName = &"read_fish_sign"
const TEACHER_ID: StringName = &"master_sign_reader"

enum LessonPhase {
	INACTIVE,
	OBSERVING,
	COMPLETE,
}

var _phase: LessonPhase = LessonPhase.INACTIVE
var _fish_presence: Node = null
var _stable_seconds: float = 0.0
var _tracked_sign: StringName = &"none"
var _latest_snapshot: Dictionary = {}


func get_technique_id() -> StringName:
	return TECHNIQUE_ID


func get_teacher_id() -> StringName:
	return TEACHER_ID


func get_known_message() -> String:
	return "Sign Reader: Good. You stopped looking for fish and started looking for what fish leave behind."


func get_unavailable_message() -> String:
	return "Sign Reader: I need living water with visible fish activity before I can teach this lesson."


func _process(delta: float) -> void:
	if _phase != LessonPhase.OBSERVING:
		return
	if is_technique_known():
		_phase = LessonPhase.COMPLETE
		return
	if not _bind_fish_presence():
		return

	_latest_snapshot = _build_lesson_snapshot()
	var advanced := LessonPolicy.advance_observation(
		_stable_seconds,
		_tracked_sign,
		_latest_snapshot,
		delta
	)
	_stable_seconds = float(advanced.get("stable_seconds", 0.0))
	_tracked_sign = StringName(str(advanced.get("tracked_sign", &"none")))


func _on_lesson_interaction() -> void:
	if not _bind_fish_presence():
		_show_message(get_unavailable_message(), 3.0)
		return

	match _phase:
		LessonPhase.INACTIVE:
			_begin_lesson()
		LessonPhase.OBSERVING:
			_try_report_sign()
		LessonPhase.COMPLETE:
			pass


func _begin_lesson() -> void:
	if _mastery_service == null:
		_show_message(get_unavailable_message(), 2.4)
		return

	var quote := _mastery_service.can_learn(TECHNIQUE_ID, TEACHER_ID)
	if not bool(quote.get("can_learn", false)):
		_show_message(
			"Sign Reader: The lesson isn't available yet.",
			3.0
		)
		return

	_phase = LessonPhase.OBSERVING
	_stable_seconds = 0.0
	_tracked_sign = &"none"
	_latest_snapshot = {}
	_play_animation(talk_animation)
	_show_message(
		"Sign Reader: Don't stare at the fish. Read the water around them. When one sign stays clear, press K and call it.",
		6.0
	)


func _try_report_sign() -> void:
	if not LessonPolicy.has_clear_sign(_latest_snapshot):
		_show_message(
			"Sign Reader: Not yet. The water isn't giving you a clear sign. Keep watching.",
			3.2
		)
		return

	if not LessonPolicy.is_observation_complete(_stable_seconds):
		_show_message(
			"Sign Reader: You noticed something, but too quickly. Let the pattern hold. %d%%"
			% int(round(LessonPolicy.get_progress_ratio(_stable_seconds) * 100.0)),
			3.2
		)
		return

	var learned := try_learn_technique(true)
	if not bool(learned.get("success", false)):
		_show_message(
			"Sign Reader: Hold that thought. The lesson couldn't be recorded yet.",
			3.0
		)
		return

	_phase = LessonPhase.COMPLETE
	_play_animation(talk_animation)
	_show_message(
		"Sign Reader: Yes. %s. That's a fish sign. Learn the pattern, and the water starts speaking before the bite."
		% LessonPolicy.get_sign_label(_tracked_sign).capitalize(),
		6.0
	)


func _bind_fish_presence() -> bool:
	if is_instance_valid(_fish_presence):
		return true
	var world := get_parent()
	if world == null:
		return false
	var fish_zone := world.get_node_or_null("FishZone_V2")
	if fish_zone == null:
		return false
	_fish_presence = fish_zone.get_node_or_null("FishShadowPresence")
	if _fish_presence == null:
		_fish_presence = fish_zone.find_child("FishShadowPresence", true, false)
	return is_instance_valid(_fish_presence)


func _build_lesson_snapshot() -> Dictionary:
	if not is_instance_valid(_fish_presence):
		return {
			"available": false,
			"sign_count": 0,
			"dominant_sign": &"none",
		}

	var observations: Array = []
	for shadow in _fish_presence.get_children():
		if not is_instance_valid(shadow):
			continue
		if (
			shadow.has_method("is_hooked_tracking")
			and bool(shadow.call("is_hooked_tracking"))
		):
			continue
		if not shadow.has_method("get_fish_data"):
			continue
		var fish = shadow.call("get_fish_data")
		if fish == null:
			continue

		var pre_bite_state := "ROAM"
		if shadow.has_method("get_pre_bite_state_name"):
			pre_bite_state = str(shadow.call("get_pre_bite_state_name"))
		var readable := true
		if shadow.has_method("is_ambient_readable"):
			readable = bool(shadow.call("is_ambient_readable"))

		observations.append(
			FishSignPolicy.build_observation(
				fish,
				pre_bite_state,
				readable
			)
		)

	return FishSignPolicy.build_read_snapshot(observations)
