extends SceneTree
## Explicit suite entry point; production startup never invokes these contracts.
func _initialize() -> void:
	var isolated := "CodexSessionContractsQA-%d" % Time.get_ticks_usec()
	ProjectSettings.set_setting("application/config/use_custom_user_dir", true)
	ProjectSettings.set_setting("application/config/custom_user_dir_name", isolated)
	DirAccess.make_dir_recursive_absolute(OS.get_user_data_dir())
	call_deferred("run")

func run() -> void:
	var fixture := SessionTestFixture.new()
	var game := fixture.mount(self)
	for frame in range(12): await process_frame
	var qa := FishingSessionQA.reports(fixture.session)
	var failed := not bool(qa.get_debug_qa_dependency_health().get("ready", false))
	for property in qa.get_property_list():
		if not str(property.name).ends_with("qa_report"): continue
		var report = qa.get(property.name)
		if not report is Dictionary or report.is_empty():
			push_error("Explicit QA report missing: %s" % property.name)
			failed = true
		elif int(report.get("passed_count", 0)) != int(report.get("test_count", 0)):
			failed = true
	var cards := game.get_node("UI/TripleTriadGame")
	var triad: Dictionary = cards.run_backend_qa()
	failed = failed or not bool(triad.passed)
	var regression = load("res://scripts/fishing_regression_harness.gd").new()
	var result: Dictionary = regression.run_all()
	print("EXPLICIT FULL FISHING: ", result.summary)
	failed = failed or int(result.failed) > 0
	fixture.release()
	for frame in range(12): await process_frame
	var orphans := Node.get_orphan_node_ids()
	if not orphans.is_empty(): push_error("Explicit contract fixture retained orphan nodes: %s" % orphans)
	failed = failed or not orphans.is_empty()
	print("SESSION CONTRACT RUNNER: ", "FAIL" if failed else "PASS", "; orphan nodes=", orphans.size())
	quit(1 if failed else 0)
