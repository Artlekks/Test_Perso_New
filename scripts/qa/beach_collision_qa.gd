extends SceneTree

## Save-free physics regression against the current beach scene and real movers.
## godot --headless --path . --script res://scripts/qa/beach_collision_qa.gd
var _checks: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _isolate_collision_fixture(node: Node) -> void:
	# Retain the Card Maker's typed menu/request dependencies. Remove unrelated
	# gameplay scripts before _ready so this fixture cannot load/save a session.
	if node.name == &"FishingCardMakerNPC":
		return
	for child: Node in node.get_children():
		_isolate_collision_fixture(child)
	if node.name not in [
		&"BeachCritter", &"BeachCritter2", &"WorldActorPresentation", &"DepthFloor"
	]:
		node.set_script(null)


func _check(passed: bool, label: String) -> void:
	_checks += 1
	if not passed:
		_failures.append(label)
		push_error(label)


func _settle() -> void:
	for i in range(3):
		await physics_frame


func _body_at(body: PhysicsBody3D, point: Vector3, space: PhysicsDirectSpaceState3D) -> bool:
	var sphere := SphereShape3D.new()
	sphere.radius = 0.01
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = sphere
	query.transform = Transform3D(Basis.IDENTITY, point)
	query.collision_mask = 1
	query.collide_with_areas = false
	for hit: Dictionary in space.intersect_shape(query, 64):
		if hit.get("collider") == body:
			return true
	return false


func _run() -> void:
	var scene: Node3D = load("res://actors/FishingTestScene_V2.tscn").instantiate()
	_isolate_collision_fixture(scene)
	root.add_child(scene)
	current_scene = scene
	await _settle()
	var world := scene.get_node("World") as Node3D
	var maker := world.get_node("FishingCardMakerNPC") as FishingCardMakerNPC
	var body := maker.get_node("BodyCollider") as AnimatableBody3D
	var shape := body.get_node("CollisionShape3D") as CollisionShape3D
	var sprite := maker.get_node("AnimatedSprite3D") as AnimatedSprite3D
	var home_center := shape.global_position
	var space := world.get_world_3d().direct_space_state
	var area := maker.get_node("InteractionArea") as Area3D
	var area_offset := area.get_node("CollisionShape3D").position as Vector3
	_check(not body.sync_to_physics, "parent-driven body receives inherited transforms")
	_check(body.position.is_zero_approx(), "body shares the actor root horizontally")
	_check(maker.find_children("*", "PhysicsBody3D", true, false).size() == 1, "exactly one Card Maker body")
	_check(is_equal_approx((area.get_node("CollisionShape3D").shape as SphereShape3D).radius, 0.48), "Card Maker interaction radius unchanged")
	_check(area.collision_layer == 0 and area.collision_mask == 3, "Card Maker interaction layers unchanged")
	maker.set_physics_process(false)
	# Exercise actual movement and synchronization through every authored leg.
	for leg in range(5):
		maker._begin_next_patrol_leg()
		for step in range(120):
			if not maker._moving:
				break
			maker._process_patrol_leg(1.0 / 60.0)
		await _settle()
		var physical: Transform3D = PhysicsServer3D.body_get_state(body.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM)
		_check(physical.origin.distance_to(maker.global_position) < 0.0001, "physics follows visible root on leg %d" % leg)
		_check(is_equal_approx(sprite.global_position.x, maker.global_position.x) and is_equal_approx(sprite.global_position.z, maker.global_position.z), "sprite shares root on leg %d" % leg)
		_check(_body_at(body, shape.global_position, space), "current body position collides on leg %d" % leg)
		_check(area.get_node("CollisionShape3D").position.is_equal_approx(area_offset), "interaction area offset unchanged on leg %d" % leg)
		if leg == 1:
			_check(not _body_at(body, home_center, space), "no ghost body remains at home after leaving its footprint")
			var player := scene.get_node("Player/CharacterBody3D") as CharacterBody3D
			var from := Transform3D(Basis.IDENTITY, maker.global_position + Vector3(-0.45, 0.0, 0.0))
			var collision := KinematicCollision3D.new()
			_check(player.test_move(from, Vector3(0.45, 0.0, 0.0), collision), "real player capsule blocked at current Card Maker position")
			_check(collision.get_collider() == body, "player hits Card Maker rather than another system")
	maker.set_physics_process(true)
	for name: String in ["BeachCritter", "BeachCritter2"]:
		var crab := world.get_node(name) as BeachFishingCritter
		var crab_shape := crab.get_node("CollisionShape3D") as CollisionShape3D
		_check(is_equal_approx((crab_shape.shape as SphereShape3D).radius, 0.075), "%s keeps its authored radius" % name)
		_check(not crab.sync_to_physics, "%s allows component-wise scripted movement" % name)
		crab.set_physics_process(false)
		var previous := crab.position
		crab._walk_direction = Vector2(1.0, 1.0).normalized()
		crab._update_walk(0.1)
		await _settle()
		_check(crab.position.x > previous.x and crab.position.z > previous.z, "%s retains both movement components" % name)
		var physical: Transform3D = PhysicsServer3D.body_get_state(crab.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM)
		_check(physical.origin.distance_to(crab.global_position) < 0.0001, "%s physics follows sprite root" % name)
		_check(crab.get_node("AnimatedSprite3D").global_position.is_equal_approx(crab.global_position), "%s visible and body positions agree" % name)
	var circuit := world.get_node("BeachGatheringCircuit")
	_check(circuit.find_children("*", "PhysicsBody3D", true, false).is_empty(), "all gathering objects remain non-blocking")
	_check(circuit.get_child_count() == 12, "all twelve gathering objects inspected")
	for gather: Node in circuit.get_children():
		var interaction := gather.get_node("InteractionArea") as Area3D
		var interaction_shape := interaction.get_node("CollisionShape3D") as CollisionShape3D
		_check(interaction.collision_layer == 0 and interaction.collision_mask == 3, "%s interaction layers unchanged" % gather.name)
		_check(is_equal_approx((interaction_shape.shape as SphereShape3D).radius, 0.65), "%s interaction radius unchanged" % gather.name)
	_check((world.get_node("DepthFloor") as PhysicsBody3D).collision_layer == 2048, "DepthFloor excluded from player mask 1")
	print("Beach collision QA: %d checks, %d failures" % [_checks, _failures.size()])
	scene.queue_free()
	await process_frame
	quit(0 if _failures.is_empty() else 1)
