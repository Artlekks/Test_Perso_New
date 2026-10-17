extends SceneTree
## Checks rendered artwork bounds at native viewport sizes, not only target coords.
## Run only with the isolated QA launcher, never normal F5 saves.
const Isolation = preload("res://scripts/qa/qa_save_isolation.gd")
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	if not Isolation.verify():
		quit(1)
		return
	run.call_deferred()

func verify(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
		push_error(label)

func screen_bounds(canvas: CanvasItem) -> Rect2:
	if canvas is Sprite2D:
		return canvas.get_global_transform_with_canvas() * canvas.get_rect()
	if canvas is Control:
		return canvas.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, canvas.size)
	return Rect2()

func run() -> void:
	await process_frame
	if not Isolation.verify_root_clock(self):
		quit(1)
		return
	for dimensions in [Vector2i(640, 480), Vector2i(960, 480)]:
		var viewport := SubViewport.new()
		viewport.size = dimensions
		root.add_child(viewport)
		var game_scene: PackedScene = load("res://actors/FishingTestScene_V2.tscn") as PackedScene
		if game_scene == null:
			verify(false, "game scene is loadable")
			viewport.queue_free()
			await process_frame
			continue
		var game: Node = game_scene.instantiate()
		viewport.add_child(game)
		for i in range(4): await process_frame
		var fishing: Node = game.get_node("Game/Fishing")
		var power := fishing.get("power_meter_view") as CanvasLayer
		var depth: Control = power.get_node("DepthMeter")
		var inset: Control = power.get_node("../CharacterView")
		var background: Sprite2D = power.get_node("Root/PowerBarBG")
		var frame: Control = depth.get_node("Frame")
		var grid: Control = inset.get_node("Grid")
		# Test the actual resting positions and the wide-inset configuration.
		power.call("_update_viewport_layout", 1.0)
		var bar_rect: Rect2 = screen_bounds(background)
		verify(absf(bar_rect.end.y - screen_bounds(frame).end.y) <= 1.0,
			"depth frame bottom aligns with bar at %s" % dimensions)
		verify(absf(bar_rect.end.y - screen_bounds(grid).end.y) <= 1.0,
			"character frame bottom aligns with bar at %s" % dimensions)
		var original_bar_x: float = bar_rect.position.x
		inset.visible = true
		power.call("_update_viewport_layout", 1.0)
		bar_rect = screen_bounds(background)
		verify(absf(bar_rect.end.y - screen_bounds(frame).end.y) <= 1.0,
			"wide group preserves depth bottom alignment at %s" % dimensions)
		verify(absf(bar_rect.end.y - screen_bounds(grid).end.y) <= 1.0,
			"wide group preserves character bottom alignment at %s" % dimensions)
		if dimensions.x >= float(power.get("wide_inset_layout_min_width")):
			verify(bar_rect.position.x > original_bar_x,
				"wide inset shifts the entire group toward screen center")
		inset.visible = false
		power.call("_update_viewport_layout", 1.0)
		verify(absf(screen_bounds(background).position.x - original_bar_x) < 1.0,
			"inset exit restores authored left gauge position")
		viewport.queue_free()
		await process_frame
	Isolation.emit_result("fishing_bottom_hud_alignment_qa", checks - failures.size(), checks,
		failures.size(), 0)
	quit(0 if failures.is_empty() else 1)
