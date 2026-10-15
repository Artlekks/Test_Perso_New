extends SceneTree

const Isolation = preload("res://scripts/qa/qa_save_isolation.gd")
const CraftingQA = preload("res://scripts/beach_crafting_qa.gd")
const BeachCatalog = preload("res://data/crafting/beach/beach_vertical_slice_catalog.tres")
const TackleCatalog = preload("res://data/bof4/tackle/all_tackle.tres")

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
	fixture.mount(self)
	for frame in range(12):
		await process_frame
	var report: Dictionary = CraftingQA.run(BeachCatalog,
		fixture.session.beach_crafting_service, TackleCatalog)
	for failure in report.get("failures", []):
		print("CRAFTING_FAILURE ", failure)
	fixture.release()
	for frame in range(12):
		await process_frame
	var orphans := Node.get_orphan_node_ids().size()
	Isolation.emit_result("fishing_crafting_runner", int(report.passed_count),
		int(report.test_count), int(report.test_count) - int(report.passed_count), orphans)
	quit(0 if report.passed_count == report.test_count and orphans == 0 else 1)

func _finalize() -> void:
	print("QA_PROCESS_FINALIZED")
