extends SceneTree
## Gate 08: D followthrough retained, completed-return easing bounded to
## 1.5 seconds, hooked-fish top-safe optical correction. No save operations.
const Rig = preload("res://scripts/camera_rig.gd")
var count: int = 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func require(condition: bool, description: String) -> void:
	count += 1
	if not condition:
		failures.append(description)
		push_error("GATE 08: " + description)

func run() -> void:
	for duration in [0.85,1.5,2.0]:
		require(is_equal_approx(Rig.completed_reel_return_ease(0.0,duration),0.0),"zero elapsed leaves starting pose")
		require(is_equal_approx(Rig.completed_reel_return_ease(duration,duration),1.0),"duration exactly reaches the authored home pose")
		var last: float = 0.0
		for frame in range(1,121):
			var t: float = float(frame)/120.0 * duration
			var eased: float = Rig.completed_reel_return_ease(t,duration)
			require(eased >= last and eased <= 1.0,"return easing monotonic and bounded")
			last = eased
	for screen_y in [20.0,46.0,85.0,106.0,180.0]:
		for slope in [4.0,20.0,60.0,120.0]:
			var shift: float = Rig.hooked_top_lens_target(screen_y,110.0,slope,4.0)
			require(shift >= 0.0 and shift <= 4.0,"hooked fish lens target remains bounded")
			if screen_y >= 110.0:
				require(is_zero_approx(shift),"already-safe hooked fish is never pushed lower")
			elif shift < 4.0:
				require(absf((screen_y + slope*shift)-110.0) < 0.0001,"unclamped target places fish on safe edge")
	var code: String = (load("res://scripts/camera_rig.gd") as Script).source_code
	require(code.contains("_update_hooked_fish_top_clearance(camera,physical,delta)"),"hooked presentation branch applies top safety")
	require(code.contains("_update_free_lure_camera_tracking(delta)"),"free D arc branch remains intact")
	require(code.contains("advance_free_d_followthrough_yaw("),"D continuous followthrough remains intact")
	require(code.contains("_retrieve_yaw_return_elapsed >= completed_reel_camera_return_seconds"),"completed retrieval terminates its camera return")
	print("FISHING STABILIZATION GATE 08: %d/%d passed; failures=%s" % [count-failures.size(),count,failures])
	quit(0 if failures.is_empty() else 1)
