extends SceneTree
const Isolation = preload("res://scripts/qa/qa_save_isolation.gd")
## Explicit suite entry point; production startup never invokes these contracts.
func _initialize() -> void:
	if not Isolation.verify():
		quit(1)
		return
	call_deferred("run")

func run() -> void:
	for frame in range(2):
		await process_frame
	if not Isolation.verify_root_clock(self):
		quit(1)
		return
	var fixture := SessionTestFixture.new()
	var game := fixture.mount(self)
	for frame in range(12): await process_frame
	var qa := FishingSessionQA.reports(fixture.session)
	var failed := not bool(qa.get_debug_qa_dependency_health().get("ready", false))
	var total_assertions := 1
	var failed_assertions := 1 if failed else 0
	for property in qa.get_property_list():
		if not str(property.name).ends_with("qa_report"): continue
		var report = qa.get(property.name)
		if not report is Dictionary or report.is_empty():
			push_error("Explicit QA report missing: %s" % property.name)
			failed = true
			total_assertions += 1
			failed_assertions += 1
		elif int(report.get("passed_count", 0)) != int(report.get("test_count", 0)):
			failed = true
			total_assertions += int(report.get("test_count", 0))
			failed_assertions += maxi(1, int(report.get("test_count", 0)) - int(report.get("passed_count", 0)))
		else:
			total_assertions += int(report.get("test_count", 0))
	var cards := game.get_node("UI/TripleTriadGame")
	var triad: Dictionary = cards.run_backend_qa()
	failed = failed or not bool(triad.passed)
	total_assertions += 1
	if not bool(triad.passed): failed_assertions += 1
	var regression = load("res://scripts/fishing_regression_harness.gd").new()
	var result: Dictionary = regression.run_all()
	print("EXPLICIT FULL FISHING: ", result.summary)
	failed = failed or int(result.failed) > 0
	total_assertions += int(result.passed) + int(result.failed)
	failed_assertions += int(result.failed)
	fixture.release()
	for frame in range(12): await process_frame
	var orphans := Node.get_orphan_node_ids()
	if not orphans.is_empty(): push_error("Explicit contract fixture retained orphan nodes: %s" % orphans)
	failed = failed or not orphans.is_empty()
	print("SESSION CONTRACT RUNNER: ", "FAIL" if failed else "PASS", "; orphan nodes=", orphans.size())
	Isolation.emit_result("session_contract_runner", total_assertions - failed_assertions,
		total_assertions, failed_assertions, orphans.size())
	quit(1 if failed else 0)

func _finalize() -> void:
	print("QA_PROCESS_FINALIZED")
