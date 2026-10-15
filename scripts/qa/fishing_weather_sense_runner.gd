extends SceneTree

const Isolation = preload("res://scripts/qa/qa_save_isolation.gd")
const Session = preload("res://scripts/fishing_session_services.gd")
const WeatherQA = preload("res://scripts/fishing_weather_sense_qa.gd")
const EnvironmentScript = preload("res://scripts/fishing_environment_service.gd")
const Mastery = preload("res://scripts/mastery/fishing_mastery_service.gd")
const Unlocks = preload("res://scripts/fishing_unlock_state.gd")

func _initialize() -> void:
	if not Isolation.verify():
		quit(1)
		return
	call_deferred("_run")

func _run() -> void:
	await process_frame
	if not Isolation.verify_root_clock(self):
		quit(1)
		return
	var environment_catalog = Session.FishingEnvironmentCatalogResource.duplicate(true)
	var mastery_catalog = Session.FishingMasteryTechniqueCatalogResource.duplicate(true)
	var report: Dictionary = WeatherQA.run(environment_catalog, mastery_catalog)
	for failure in report.get("failures", PackedStringArray()):
		print("WEATHER_SENSE_FAILURE ", failure)
	var unlock := Unlocks.new()
	unlock.reset_unlocks(false)
	var mastery := Mastery.new()
	mastery.configure(mastery_catalog, unlock)
	var environment := EnvironmentScript.new()
	environment.configure(environment_catalog)
	environment.set_mastery_service(mastery)
	var definition = mastery_catalog.get_technique(&"weather_sense")
	mastery.learn_technique(&"weather_sense", definition.teacher_id, false)
	for id in [&"calm", &"rain", &"tempest"]:
		environment.activate_condition(id)
		var snapshot: Dictionary = environment.get_weather_sense_snapshot(5.0, 10.0)
		print("WEATHER_SENSE_OBSERVED ", JSON.stringify({"condition": str(id),
			"activity": str(snapshot.get("activity", "")),
			"favored_depth": str(snapshot.get("favored_depth", "")),
			"specimen_outlook": str(snapshot.get("specimen_outlook", "")),
			"fight_outlook": str(snapshot.get("fight_outlook", "")),
			"tier_bias": str(snapshot.get("tier_bias", "")),
			"resolved": snapshot.get("resolved", {})}))
	environment.free()
	mastery.free()
	unlock.free()
	var total := int(report.get("test_count", 0))
	var passed := int(report.get("passed_count", 0))
	Isolation.emit_result("fishing_weather_sense_runner", passed, total, total - passed,
		Node.get_orphan_node_ids().size())
	quit(0 if passed == total else 1)

func _finalize() -> void:
	print("QA_PROCESS_FINALIZED")
