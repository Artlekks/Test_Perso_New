extends SceneTree
## Godot 4.7.2 regression for world-owned wind/current, rain assets and impacts.
const WindScene = preload("res://actors/FishingWindVFX.tscn")
const RainScene = preload("res://actors/FishingRainVFX.tscn")
const Atlas = preload("res://assets/ui/environment/RainImpact.png")
var checks: int = 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures.append(description)
		push_error("AMBIENT VFX QA: " + description)

func run() -> void:
	var bootstrap: String = FileAccess.get_file_as_string("res://scripts/world/playable_location_scene.gd")
	for key in ["FishingCurrentVFX", "FishingWindVFX", "FishingRainVFX"]:
		check(bootstrap.contains('"' + key + '"'), key + " is mounted by world scene bootstrap")
	check(Atlas.get_width() == 142 and Atlas.get_height() == 66, "original supplied rain sprite sheet kept intact")
	var scene: Node3D = Node3D.new()
	scene.name = "GameForQa"
	root.add_child(scene)
	var world: Node3D = Node3D.new()
	world.name = "World"
	scene.add_child(world)
	var beach: Node3D = Node3D.new()
	beach.name = "beach"
	world.add_child(beach)
	var sea: MeshInstance3D = MeshInstance3D.new()
	sea.name = "Sea"
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = Vector3(20.0, 0.1, 16.0)
	sea.mesh = mesh
	beach.add_child(sea)
	var camera: Camera3D = Camera3D.new()
	camera.name = "Camera3D"
	camera.position = Vector3(0, 5, 8)
	camera.look_at(Vector3.ZERO, Vector3.UP)
	scene.add_child(camera)
	camera.current = true
	var wind: Node3D = WindScene.instantiate() as Node3D
	world.add_child(wind)
	var effect: Node3D = wind.get_node_or_null("NolkaWindLines") as Node3D
	check(effect != null, "purchased Nolka Breeze instantiates")
	wind.call("_update_from_snapshot", {"available": true, "speed_mps": 3.0, "velocity_xz": Vector2.RIGHT * 3.0})
	check(bool(wind.call("is_wind_display_running")), "world wind emits independently of fishing")
	check(absf(float(wind.get("line_width")) - 0.14) < 0.001, "existing approved wind trail size preserved")
	check(absf(float(wind.get("opacity")) - 0.18) < 0.001, "existing approved wind opacity preserved")
	var area: Vector3 = effect.get("area") as Vector3
	check(area.x <= 14.0 and area.z <= 12.0, "wind covers camera area instead of entire sea")
	var rain: Node3D = RainScene.instantiate() as Node3D
	world.add_child(rain)
	check(not bool(rain.call("is_raining")), "rain is off in clear automatic conditions")
	var frames: SpriteFrames = rain.get("_splash_frames") as SpriteFrames
	check(frames != null, "rain sprite animation resource generated")
	if frames != null:
		check(frames.get_frame_count(&"ground") == 5, "five original ground-impact frames")
		check(frames.get_frame_count(&"water") == 5, "five original water-impact frames")
		check(frames.get_frame_texture(&"ground", 0).get_width() == 18, "ground frames exclude pink sprite-sheet grid")
		check(frames.get_frame_texture(&"water", 0).get_width() == 26, "water frames exclude pink sprite-sheet grid")
	check(rain.call("_resolve_weather", PackedStringArray(["rain"])) == "rain", "rain service condition activates rain")
	check(rain.call("_resolve_weather", PackedStringArray(["tempest"])) == "storm", "storm condition activates strong rain")
	rain.set("weather_mode", 2)
	rain.call("_poll_weather")
	check(bool(rain.call("is_raining")), "Rain Preview allows visual inspection without changing gameplay weather")
	rain.call("_spawn_splash", Vector3.ZERO, &"ground")
	rain.call("_spawn_splash", Vector3(1, 0, 0), &"water")
	check(int(rain.call("get_active_splash_count")) == 2, "two independently animated one-shot splash actors")
	print("ENVIRONMENT AMBIENT VFX QA: %d checks, %d failed" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
