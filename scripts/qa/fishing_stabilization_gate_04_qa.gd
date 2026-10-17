extends SceneTree
## Gate 04: verify the production bottom-HUD and feedback layout contracts,
## plus water-side inward progress for A/D and K after a blocked screen arc.
## No saves, economy, mastery, camera or scene assets are changed by this QA.
const PowerScript = preload("res://scripts/power_meter_view.gd")
const FeedbackScript = preload("res://scripts/fishing_feedback_view.gd")
const BaitScene = preload("res://actors/bait_V2.tscn")

class TestShore extends Node:
	func get_water_side_projection(point: Vector3) -> Vector3:
		return Vector3(point.x, point.y, maxf(point.z, 0.0))
	func constrain_water_motion(_old: Vector3, point: Vector3) -> Vector3:
		return get_water_side_projection(point)

var checks: int = 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error("FISHING STABILIZATION GATE 04: " + label)

func run() -> void:
	var authored_y: float = 405.0
	var offset_y: float = -12.0
	var target_margin: float = 480.0 - authored_y - offset_y
	for h in [480, 600, 720, 900, 1100, 1280, 480]:
		var rest_y: float = PowerScript.bottom_anchored_rest_y(authored_y, float(h), offset_y)
		check(absf(float(h)-rest_y-target_margin) < 0.001, "power-bar bottom margin fixed at height %d" % h)
		var vp := Vector2(960.0,float(h))
		var image_size := Vector2(267.0,160.0)
		var image_scale := Vector2(2.4,2.4)
		var pos: Vector2 = FeedbackScript.centered_feedback_position(vp,image_size,image_scale,Vector2.ZERO)
		var center: Vector2 = pos + image_size*image_scale*0.5
		check(center.distance_to(vp*0.5) < 0.001, "MISS/HIT centered in viewport height %d" % h)
	var surface := SubViewport.new()
	surface.size = Vector2i(960,480)
	surface.world_3d = World3D.new()
	root.add_child(surface)
	var bait: Node3D = BaitScene.instantiate()
	surface.add_child(bait)
	bait.set_physics_process(false)
	bait.simulation_frozen = true
	bait.state = bait.State.IN_WATER
	var target := Node3D.new()
	surface.add_child(target)
	target.global_position = Vector3(0.0,0.0,-2.0)
	bait.set_reel_target(target)
	var shore := TestShore.new()
	surface.add_child(shore)
	bait.set_shore_boundary(shore)
	await process_frame
	# The previous solver could return precisely the same position for held D.
	# Simulate that failure directly and enforce the post-constraint contract.
	for input_direction in [-1.0,1.0]:
		for height in [480,720,1000]:
			surface.size = Vector2i(960,height)
			bait.global_position = Vector3(4.0,0.0,1.0)
			bait.reel_steering = input_direction
			bait.reeling = false
			var old_distance: float = Vector2(4.0,1.0).length()
			var total_progress: float = 0.0
			var monotonic: bool = true
			var respected_shore: bool = true
			for tick in range(120):
				var previous: Vector3 = bait.global_position
				var previous_distance: float = Vector2(previous.x,previous.z).length()
				bait._guarantee_free_retrieve_progress(previous,1.0/60.0)
				var next_distance: float = Vector2(bait.global_position.x,bait.global_position.z).length()
				if next_distance > previous_distance + 0.00001:
					monotonic = false
				if bait.global_position.z < -0.00001:
					respected_shore = false
				total_progress += maxf(0.0,previous_distance-next_distance)
			check(monotonic, "held A/D return is monotonic at height %d direction %s" % [height,input_direction])
			check(respected_shore, "held A/D stays water-side at height %d direction %s" % [height,input_direction])
			check(total_progress > 0.05 and total_progress <= old_distance, "blocked A/D achieves physical progress at height %d direction %s" % [height,input_direction])
	# A visual resize must not vary the physical correction from the same start.
	var lengths: Array[float] = []
	for height in [480,800,1200]:
		surface.size = Vector2i(960,height)
		bait.global_position = Vector3(4.0,0.0,1.0)
		bait.reel_steering = 1.0
		bait._guarantee_free_retrieve_progress(bait.global_position,1.0/60.0)
		lengths.append(Vector2(bait.global_position.x,bait.global_position.z).length())
	check(absf(lengths[0]-lengths[1]) < 0.000001 and absf(lengths[1]-lengths[2]) < 0.000001, "window height cannot modify physical D step")
	print("FISHING STABILIZATION GATE 04: %d/%d passed; failures=%s" % [checks-failures.size(), checks, failures])
	quit(0 if failures.is_empty() else 1)
