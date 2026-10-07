extends SceneTree

## Save-free executable QA for the real router, not a duplicate input policy.
## godot --headless --path . --script res://scripts/qa/world_interaction_qa.gd
const RouterScript = preload("res://scripts/world_interaction_router.gd")
const GameModeScript = preload("res://scripts/game_mode.gd")
const GatherScene = preload("res://actors/BeachGatheringNode3D.tscn")
const CardMakerScript = preload("res://scripts/economy/fishing_card_maker_npc.gd")

class InteractionTarget:
	extends Node3D
	var in_range: bool = true
	var available: bool = true
	var action_key: int = KEY_K
	var calls: int = 0

	func _ready() -> void:
		add_to_group(&"world_interaction_targets")

	func is_world_interaction_available(event: InputEvent) -> bool:
		return in_range and available and event is InputEventKey and (
			(event as InputEventKey).physical_keycode == action_key
		)

	func interact_from_world(_event: InputEvent) -> void:
		calls += 1

var _tests: int = 0
var _failures := PackedStringArray()


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	# Every facing direction accepts exactly its own and its two neighbors.
	for facing in range(8):
		for direction in range(8):
			var difference := posmod(direction - facing, 8)
			_check(
				RouterScript.facing_allows(_direction(facing), _direction(direction))
				== (difference in [0, 1, 7]),
				"facing %d / target %d" % [facing, direction]
			)
	_check(not RouterScript.facing_allows(Vector3.ZERO, Vector3.FORWARD), "missing facing fails closed")
	_check(not RouterScript.facing_allows(Vector3.BACK, Vector3.ZERO), "coincident target fails closed")

	var fixture := Node3D.new()
	fixture.name = "InteractionQA"
	root.add_child(fixture)
	var player := Node3D.new()
	fixture.add_child(player)
	var mode := GameModeScript.new()
	fixture.add_child(mode)
	var router := RouterScript.new()
	router.configure(player, mode)
	fixture.add_child(router)
	var alpha := InteractionTarget.new()
	alpha.name = "Alpha"
	alpha.position = Vector3(0, 0, 1)
	fixture.add_child(alpha)
	var zulu := InteractionTarget.new()
	zulu.name = "Zulu"
	zulu.position = alpha.position
	fixture.add_child(zulu)
	var press := _key(true)
	var release := _key(false)

	_check(RouterScript.select_target(player, [zulu, alpha], press) == alpha, "stable path breaks ties")
	_check(RouterScript.select_target(player, [alpha, zulu], press) == alpha, "group order cannot change winner")
	zulu.position.z = 0.5
	_check(RouterScript.select_target(player, [alpha, zulu], press) == zulu, "nearest eligible target wins")
	zulu.in_range = false
	_check(RouterScript.select_target(player, [zulu, alpha], press) == alpha, "out of range target excluded")
	zulu.in_range = true
	zulu.available = false
	_check(RouterScript.select_target(player, [zulu, alpha], press) == alpha, "unavailable target excluded")
	zulu.available = true
	zulu.position.z = -0.5
	_check(RouterScript.select_target(player, [zulu, alpha], press) == alpha, "closer target behind player excluded")
	zulu.position.z = 1
	# Equal distance: the more centered target wins before the path tie-break.
	alpha.position = Vector3(3, 0, 4)
	zulu.position = Vector3(0, 0, 5)
	_check(RouterScript.select_target(player, [alpha, zulu], press) == zulu, "alignment breaks equal-distance ties")
	alpha.position = Vector3(0, 0, 1)
	zulu.position = Vector3(0, 0, 1)
	zulu.action_key = KEY_C
	var card_press := _key(true)
	card_press.physical_keycode = KEY_C
	_check(RouterScript.select_target(player, [alpha, zulu], card_press) == zulu, "C targets only actors accepting the card action")
	_check(RouterScript.select_target(player, [zulu, alpha], press) == alpha, "K cannot route to a C-only actor")
	zulu.action_key = KEY_K

	_check(router.handle_event(press), "eligible press is consumed")
	_check(alpha.calls == 1 and zulu.calls == 0, "one target invoked")
	for _iteration in range(64):
		router.handle_event(press)
	_check(alpha.calls == 1 and zulu.calls == 0, "duplicate held presses cannot invoke again")
	router.handle_event(release)
	router.handle_event(_key(true, true))
	_check(alpha.calls == 1, "OS echo cannot invoke a world interaction")
	for _iteration in range(16):
		router.handle_event(press)
		router.handle_event(release)
	_check(alpha.calls == 17 and zulu.calls == 0, "rapid released taps each invoke exactly once")

	paused = true
	_check(not router.handle_event(press), "paused dialogue/menu owns input")
	paused = false
	mode.enter_fishing(null)
	# This tests the mode boundary, not the internals of individual fishing
	# phases. All fishing phases are excluded by the same mode check.
	_check(not router.handle_event(press), "fishing mode retains K")
	_check(alpha.calls == 17, "fishing cannot mutate world targets")
	mode.exit_fishing()
	router.configure(player, null)
	_check(not router.handle_event(press), "missing game mode fails closed")
	var unavailable_mode := Node.new()
	fixture.add_child(unavailable_mode)
	router.configure(player, unavailable_mode)
	_check(not router.handle_event(press), "missing game mode API fails closed")
	router.configure(null, mode)
	_check(not router.handle_event(press), "missing player fails closed")
	router.configure(player, mode)
	alpha.available = false
	zulu.available = false
	_check(not router.handle_event(press), "no eligible target leaves input to exploration")
	alpha.available = true
	alpha.queue_free()
	_check(RouterScript.select_target(player, [alpha, zulu], press) == null, "queued-for-deletion target is unavailable immediately")
	alpha.free()
	zulu.free()
	_check(not router.handle_event(press), "removed targets cannot leave stale selection")

	var gather := GatherScene.instantiate()
	var sprite := gather.get_node("GatherSprite3D") as Sprite3D
	_check(sprite.alpha_cut == SpriteBase3D.ALPHA_CUT_DISABLED and sprite.render_priority < -90, "ground sprite draws before character bodies")
	_check(sprite.position == Vector3(0, -0.004, 0), "ground sprite position preserved")
	gather.free()
	var maker := CardMakerScript.new()
	_check(is_equal_approx(maker.patrol_speed, 0.54), "patrol speed reflects walk cadence")
	_check(not maker.smoke_enabled, "unsafe smoke source is disabled")
	maker.free()
	fixture.free()
	print("World Interaction QA: %d/%d passed" % [_tests - _failures.size(), _tests])
	for failure in _failures:
		push_error(failure)
	quit(0 if _failures.is_empty() else 1)


func _check(condition: bool, label: String) -> void:
	_tests += 1
	if not condition:
		_failures.append(label)


func _direction(index: int) -> Vector3:
	var angle := float(index) * PI / 4.0
	return Vector3(sin(angle), 0, cos(angle))


func _key(pressed: bool, echo: bool = false) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = KEY_K
	event.pressed = pressed
	event.echo = echo
	return event
