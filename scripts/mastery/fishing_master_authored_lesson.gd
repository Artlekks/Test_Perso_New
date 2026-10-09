extends FishingMasterLessonNPCBase
## Instruction-only delivery of an existing authored technique. The mastery
## service remains the authority for teacher, prerequisites and persistence.
@export var technique: FishingMasteryTechniqueDefinition
var _phase := 0

func get_technique_id() -> StringName:
	return technique.technique_id if technique != null else &""

func get_teacher_id() -> StringName:
	return technique.teacher_id if technique != null else &""

func get_known_message() -> String:
	return "You know %s. %s" % [technique.display_name, technique.description]

func _on_lesson_interaction() -> void:
	var result := try_learn_technique(true)
	if bool(result.get("success", false)):
		_interaction_dialogue_state = MasterDialogueProfilesScript.STATE_LEARNED
		_show_message("Learned %s. %s" % [technique.display_name, technique.description])
	elif result.get("reason") == "missing_prerequisite":
		var prerequisite := _mastery_service.get_catalog().get_technique(StringName(result.missing_technique_id))
		_show_message("First learn %s, then return for %s." % [prerequisite.display_name, technique.display_name])
	else:
		_show_message(get_unavailable_message())
