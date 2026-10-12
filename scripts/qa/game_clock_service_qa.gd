extends SceneTree
## Godot --headless --path PROJECT --script res://scripts/qa/game_clock_service_qa.gd
## Tests are isolated from production user:// save files.

const ClockScript = preload("res://scripts/world/game_clock_service.gd")
const TEST_PATH := "user://qa_game_clock_service_v1.json"
var checks: int = 0
var failed: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failed += 1
		push_error("GameClock QA: " + label)


func _clean() -> void:
	for suffix in ["", ".bak", ".tmp"]:
		var path: String = TEST_PATH + suffix
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _run() -> void:
	_clean()
	var clock = ClockScript.new()
	clock.set_save_path(TEST_PATH)
	root.add_child(clock)
	clock.set_process(false) # Deterministic simulation, not real-time test execution.
	_check(clock.get_day() == 1 and clock.get_hour() == 8 and clock.get_minute() == 0, "fresh Day 1 at 08:00")
	_check(clock.get_clock_text() == "Day 1 · 8:00 AM", "human-readable clock")
	clock.advance_real_seconds(1.5)
	_check(clock.get_hour() == 8 and clock.get_minute() == 0, "sub-minute accumulator")
	clock.advance_real_seconds(0.5)
	_check(clock.get_minute() == 1, "real seconds advance one minute")
	_check(not clock.set_clock(0, 0, 0) and not clock.set_clock(1, 24, 0), "invalid time rejected")
	clock.set_clock(1, 23, 59)
	clock.advance_minutes(1)
	_check(clock.get_day() == 2 and clock.get_hour() == 0 and clock.get_minute() == 0, "midnight rollover")
	clock.advance_real_seconds(1.0)
	_check(clock.save_to_disk(), "save succeeds")
	clock.advance_minutes(5)
	_check(clock.save_to_disk(), "second save creates fallback backup")
	var restored = ClockScript.new()
	restored.set_save_path(TEST_PATH)
	root.add_child(restored)
	restored.set_process(false)
	_check(restored.get_day() == 2 and restored.get_minute() == 5, "reload persisted day/minute")
	restored.advance_real_seconds(1.0)
	_check(restored.get_minute() == 6, "reload preserved fractional minute")
	# Backup should contain previous complete checkpoint (Day 2 00:00).
	var file := FileAccess.open(TEST_PATH, FileAccess.WRITE)
	file.store_string("{corrupt")
	file.close()
	var recovered = ClockScript.new()
	recovered.set_save_path(TEST_PATH)
	root.add_child(recovered)
	recovered.set_process(false)
	_check(recovered.load_from_disk() and recovered.get_minute() == 0, "invalid primary recovers from backup")
	clock.set_process(false)
	restored.set_process(false)
	recovered.set_process(false)
	# Clear dirty before freeing so isolated QA checkpoints are not overwritten.
	clock._dirty = false
	restored._dirty = false
	recovered._dirty = false
	clock.queue_free()
	restored.queue_free()
	recovered.queue_free()
	await process_frame
	_clean()
	print("GameClock QA: %d/%d checks passed" % [checks - failed, checks])
	quit(0 if failed == 0 else 1)
