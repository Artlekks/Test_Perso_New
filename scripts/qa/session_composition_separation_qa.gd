extends SceneTree
var checks := 0
var failures := PackedStringArray()
var core_names: PackedStringArray

func _initialize() -> void:
	var isolated := "CodexSessionCompositionQA-%d" % Time.get_ticks_usec()
	ProjectSettings.set_setting("application/config/use_custom_user_dir", true)
	ProjectSettings.set_setting("application/config/custom_user_dir_name", isolated)
	DirAccess.make_dir_recursive_absolute(OS.get_user_data_dir())
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); push_error(label)

func settle(frames := 12) -> void:
	for frame in range(frames): await process_frame

func names(session: Node) -> PackedStringArray:
	var result := PackedStringArray()
	for child in session.get_children():
		if not child is CanvasLayer and child.name not in ["DevelopmentLayer", "SessionQA"]: result.append(child.name)
	result.sort()
	return result

func run() -> void:
	var fixture := SessionTestFixture.new()
	var scene := fixture.mount(self)
	var session := fixture.session
	await settle()
	core_names = names(session)
	check(session.is_ready(), "production readiness without development/QA")
	check(session == SessionComposition.acquire(self), "canonical acquisition reuses same owner")
	check(RuntimeAccessPolicy.current() == null and not RuntimeAccessPolicy.allows(&"cards"), "absent override defaults to authored policy")
	check(session.get_node_or_null("DevelopmentLayer") == null and session.get_node_or_null("SessionQA") == null, "no development or QA session children")
	check(not ResourceLoader.has_cached("res://scripts/triple_triad/triple_triad_backend_qa.gd") and not ResourceLoader.has_cached("res://scripts/fishing_regression_harness.gd"), "cold production does not load regression scripts")
	check(not ResourceLoader.has_cached("res://actors/TripleTriadDebugMenu.tscn"), "production packed scene has no required debug overlay dependency")
	check(scene.get_node("Game/Fishing").debug_controller == null, "F10 absent while fishing runtime remains ready")
	check(scene.get_node("UI/TripleTriadGame").is_backend_ready(), "cards compose without debug menu")
	var sentinel := Node.new()
	sentinel.name = "UnownedSentinel"
	root.add_child(sentinel)
	fixture.release()
	await settle()
	check(is_instance_valid(sentinel), "fixture does not scavenge foreign nodes")
	sentinel.free()
	check(Node.get_orphan_node_ids().is_empty(), "cold production strict teardown")
	# Alternate order on successive cycles; both hosts use the same runtime graph.
	for cycle in range(6):
		for mobile in ([true, false] if cycle % 2 == 0 else [false, true]):
			fixture = SessionTestFixture.new()
			scene = fixture.mount(self, mobile, not mobile)
			session = fixture.session
			await settle(20)
			check(names(session) == core_names, "identical desktop/mobile core service graph")
			check(session.is_ready() and session == SessionComposition.acquire(self), "one ready canonical session across host order")
			var developer := RuntimeAccessPolicy.current()
			check(developer != null and developer.enabled == mobile, "desktop OFF/mobile ON defaults")
			var tools := session.get_node("DevelopmentLayer")
			check(tools.telemetry == null, "telemetry OFF has no instantiated recorder")
			developer.set_enabled(false)
			check(session.is_ready() and not RuntimeAccessPolicy.allows(&"travel"), "disabled developer cannot break runtime")
			# Explicit QA preserves provider state and shared authored data.
			if cycle == 0 and not mobile:
				developer.set_enabled(true)
				var ids_before = session.mastery_service._catalog.get_technique_ids().duplicate()
				var qa := FishingSessionQA.reports(session)
				check(qa.system_stability_qa_report.passed_count == qa.system_stability_qa_report.test_count, "explicit integration QA green")
				check(qa.fresh_save_rehearsal_qa_report.valid, "explicit fresh-save QA green")
				check(developer.enabled, "QA restores previous developer state")
				check(session.mastery_service._catalog.get_technique_ids() == ids_before, "QA does not mutate production catalogue")
				qa.free()
				check(session.is_ready() and session.get_node_or_null("SessionQA") == null, "QA removal retains runtime readiness")
			tools.queue_free()
			await settle()
			check(session.is_ready() and RuntimeAccessPolicy.current() == null, "development removal leaves production healthy")
			fixture.release()
			await settle()
			check(Node.get_orphan_node_ids().is_empty(), "repeated fixture releases only owned hierarchy")
	var borrowed := SessionComposition.acquire(self)
	await settle()
	fixture = SessionTestFixture.new()
	fixture.mount(self)
	check(not fixture.owns_session and fixture.session == borrowed, "fixture marks borrowed session explicitly")
	fixture.release()
	await settle()
	check(is_instance_valid(borrowed) and borrowed.is_ready(), "fixture leaves borrowed canonical session alive")
	borrowed.queue_free()
	await settle()
	check(Node.get_orphan_node_ids().is_empty(), "borrowed session released only by its actual owner")
	print("Session Composition Separation QA: %d/%d; 12 alternating host lifetimes; failures=%s" % [checks - failures.size(), checks, failures])
	quit(0 if failures.is_empty() else 1)
