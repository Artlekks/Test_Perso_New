extends FishingMasterLessonNPCBase
class_name FishingMasterDeepwaterVeteranNPC

const LessonPolicy = preload(
    "res://scripts/mastery/fishing_master_deepwater_veteran_policy.gd"
)

const TECHNIQUE_ID: StringName = &"deep_water_control"
const TEACHER_ID: StringName = &"master_deepwater_veteran"


enum LessonPhase {
    INACTIVE,
    WAITING_FOR_HOOK,
    READING_DIVE,
    RESPONSE_WINDOW,
    COMPLETE,
}


var _phase: LessonPhase = LessonPhase.INACTIVE
var _encounter: Node = null
var _load_signal_connected: bool = false

var _current_dive_yielded: bool = false
var _last_intent_id: StringName = &"unknown"
var _response_window_left: float = 0.0
var _response_match_time: float = 0.0
var _response_snapshot: Dictionary = {}


func get_technique_id() -> StringName:
    return TECHNIQUE_ID


func get_teacher_id() -> StringName:
    return TEACHER_ID


func get_known_message() -> String:
    return "Deep-Water Veteran: Good. You know when to follow the dive and when to lift into the load."


func get_unavailable_message() -> String:
    return "Deep-Water Veteran: I need the live fishing fight to teach this lesson."


func _process(delta: float) -> void:
    if _phase == LessonPhase.INACTIVE or _phase == LessonPhase.COMPLETE:
        return
    if is_technique_known():
        _phase = LessonPhase.COMPLETE
        return
    if not _bind_lesson_runtime():
        return

    var fight_state := _get_fight_state()
    if _phase == LessonPhase.WAITING_FOR_HOOK:
        if fight_state != &"NONE":
            _phase = LessonPhase.READING_DIVE
            _reset_dive_read()
            _show_message(
                "Deep-Water Veteran: Wait for a real DIVE. Yield first. The second beat comes from below.",
                4.0
            )
        return

    if fight_state == &"NONE":
        _reset_attempt()
        _phase = LessonPhase.WAITING_FOR_HOOK
        _show_message(
            "Deep-Water Veteran: That fish is gone. Hook another and read the two beats again.",
            3.4
        )
        return

    if _phase == LessonPhase.READING_DIVE:
        _update_dive_read()
        return

    if _phase == LessonPhase.RESPONSE_WINDOW:
        _update_response_window(delta)


func _on_lesson_interaction() -> void:
    if not _bind_lesson_runtime():
        _show_message(get_unavailable_message(), 2.4)
        return

    match _phase:
        LessonPhase.INACTIVE:
            _begin_lesson()
        LessonPhase.WAITING_FOR_HOOK:
            _show_message(
                "Deep-Water Veteran: Hook a fish in deep water. On DIVE, release K. When the delayed load hits, answer with K + S.",
                5.0
            )
        LessonPhase.READING_DIVE:
            _show_message(
                "Deep-Water Veteran: First beat: follow the DIVE by releasing K. Don't lift until you feel the delayed load.",
                4.4
            )
        LessonPhase.RESPONSE_WINDOW:
            _show_message(
                "Deep-Water Veteran: Second beat NOW — K + S, high rod, keep contact.",
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
        if str(quote.get("reason", "")) == "missing_prerequisite":
            _show_message(
                "Deep-Water Veteran: Not yet. Learn Line Feel and Read the Depth first — then come back to deep water.",
                5.0
            )
            return
        _show_message(
            "Deep-Water Veteran: The lesson isn't available yet.",
            3.0
        )
        return

    _reset_attempt()
    _phase = LessonPhase.WAITING_FOR_HOOK
    _play_animation(talk_animation)
    _show_message(
        "Deep-Water Veteran: Deep fish have two beats. On the DIVE, yield — release K. When the delayed load comes back up the line, recover with K + S. Show me once.",
        7.0
    )


func _update_dive_read() -> void:
    if _encounter == null or not _encounter.has_method("get_fish_debug_snapshot"):
        return
    var fight_snapshot: Dictionary = _encounter.call("get_fish_debug_snapshot")
    if StringName(str(fight_snapshot.get("fight_state", "NONE"))) != &"RESISTING":
        return

    var intent: Dictionary = fight_snapshot.get("fight_intent", {})
    var intent_id := StringName(str(intent.get("intent_id", "unknown")))
    if intent_id != _last_intent_id:
        if intent_id == LessonPolicy.INTENT_DIVE:
            _current_dive_yielded = false
        _last_intent_id = intent_id

    if intent_id != LessonPolicy.INTENT_DIVE:
        return

    var player_reeling := bool(_encounter.get("player_reeling"))
    if (
        not _current_dive_yielded
        and LessonPolicy.is_initial_yield(intent, player_reeling)
    ):
        _current_dive_yielded = true
        _show_message(
            "Deep-Water Veteran: Good. Follow the dive. Now wait for the load from below.",
            3.0
        )


func _on_deep_water_load_started(snapshot: Dictionary) -> void:
    if _phase != LessonPhase.READING_DIVE:
        return
    if not LessonPolicy.is_qualifying_load(snapshot):
        return

    if not _current_dive_yielded:
        _reset_dive_read()
        _show_message(
            "Deep-Water Veteran: You felt the load, but you fought the DIVE first. Next one: release K before the second beat.",
            4.4
        )
        return

    _response_snapshot = snapshot.duplicate(true)
    _response_window_left = LessonPolicy.get_response_window_seconds(snapshot)
    _response_match_time = 0.0
    _phase = LessonPhase.RESPONSE_WINDOW
    _show_message(
        "Deep-Water Veteran: There — the load. K + S. High rod, keep contact!",
        3.0
    )


func _update_response_window(delta: float) -> void:
    if _encounter == null:
        return

    var player_reeling := bool(_encounter.get("player_reeling"))
    var tension_bias := float(_encounter.get("player_tension_bias"))
    _response_match_time = LessonPolicy.advance_match_time(
        _response_match_time,
        player_reeling,
        tension_bias,
        delta
    )

    if LessonPolicy.is_recovery_complete(_response_match_time):
        _complete_lesson()
        return

    _response_window_left = maxf(
        _response_window_left - maxf(delta, 0.0),
        0.0
    )
    if _response_window_left <= 0.0:
        _phase = LessonPhase.READING_DIVE
        _reset_dive_read()
        _show_message(
            "Deep-Water Veteran: Too late. Let the next fish dive, then answer the load with K + S.",
            3.8
        )


func _complete_lesson() -> void:
    var learned := try_learn_technique(true)
    if bool(learned.get("success", false)):
        _phase = LessonPhase.COMPLETE
        _play_animation(talk_animation)
        _show_message(
            "Technique learned — Deep-Water Control. Yield to the dive, then recover the delayed load with K + S.",
            5.6
        )
        return

    _phase = LessonPhase.READING_DIVE
    _reset_dive_read()
    _show_message(
        "Deep-Water Veteran: The read was right, but the lesson could not be saved yet.",
        3.4
    )


func _bind_lesson_runtime() -> bool:
    if not _bind_runtime():
        return false
    if _encounter == null:
        var fishing := _find_fishing_root()
        if fishing != null:
            var raw_encounter = fishing.get("encounter")
            if raw_encounter is Node:
                _encounter = raw_encounter
            if _encounter == null:
                _encounter = fishing.find_child("Encounter", true, false)

    if _encounter != null and not _load_signal_connected:
        if _encounter.has_signal("deep_water_load_started"):
            _encounter.connect(
                "deep_water_load_started",
                Callable(self, "_on_deep_water_load_started")
            )
            _load_signal_connected = true

    return _encounter != null and _load_signal_connected


func _get_fight_state() -> StringName:
    if _encounter == null or not _encounter.has_method("get_fish_debug_snapshot"):
        return &"NONE"
    var snapshot: Dictionary = _encounter.call("get_fish_debug_snapshot")
    return StringName(str(snapshot.get("fight_state", "NONE")))


func _reset_dive_read() -> void:
    _current_dive_yielded = false
    _last_intent_id = &"unknown"
    _response_window_left = 0.0
    _response_match_time = 0.0
    _response_snapshot.clear()


func _reset_attempt() -> void:
    _reset_dive_read()
