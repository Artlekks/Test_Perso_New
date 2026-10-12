extends SceneTree
## godot --headless --path PROJECT --script res://scripts/qa/wind_cast_path_qa.gd
const Influence = preload("res://scripts/world/wind_cast_path.gd")
const Wind = preload("res://scripts/world/game_wind_service.gd")
var passed: int = 0
var failed: int = 0

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, label: String) -> void:
	if ok:
		passed += 1
	else:
		failed += 1
		push_error("Wind Cast QA: " + label)

func _run() -> void:
	var base: PackedVector3Array = PackedVector3Array([
		Vector3(0, 1, 0), Vector3(1, 3, 0), Vector3(2, 4, 0),
		Vector3(3, 3, 0), Vector3(4, 0, 0)
	])
	var before: PackedVector3Array = base.duplicate()
	var east: PackedVector3Array = Influence.bend_path(base, Vector2(7, 0))
	_check(east.size() == base.size(), "sample count unchanged")
	_check(east[0] == base[0] and east[-1] == base[-1], "landing target and cast origin exactly preserved")
	_check(east[2].x > base[2].x, "positive X wind bends east")
	_check(is_equal_approx(east[2].z, base[2].z), "no spurious north/south drift")
	_check(east[2].distance_to(base[2]) <= 0.3501, "safe maximum wind bow")
	_check(base == before, "original array is not modified")
	_check(Influence.bend_path(base, Vector2.ZERO) == base, "calm wind is a no-op")
	_check(Influence.bend_path(base, Vector2(0, -7))[2].z < base[2].z, "northbound wind bends north")
	_check(Influence.bend_path(base, Vector2(7, 0)) == east, "deterministic cast path")
	_check(Influence.bend_path(PackedVector3Array([Vector3.ZERO, Vector3.ONE]), Vector2(7,0)).size() == 2, "short paths unchanged")
	var wind: Node = Wind.new()
	root.add_child(wind)
	for minute in [0, 480, 850, 1440, 10000]:
		var snapshot: Dictionary = wind.get_snapshot_at_minutes(minute)
		var velocity: Vector2 = snapshot.get("velocity_xz", Vector2.ZERO)
		var forecast: PackedVector3Array = Influence.bend_path(base, velocity)
		_check(forecast[0] == base[0] and forecast[-1] == base[-1], "time %d landing remains exact" % minute)
		_check(forecast[2].distance_to(base[2]) <= 0.3501, "time %d offset bounded" % minute)
	wind.queue_free()
	print("Wind Cast QA: %d/%d passed" % [passed, passed+failed])
	quit(0 if failed == 0 else 1)
