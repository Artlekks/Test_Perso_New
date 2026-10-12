extends SceneTree
## Run using Godot: --headless --path PROJECT --script res://scripts/qa/exploration_hud_anchor_qa.gd
## Verifies stable bottom margin as gameplay viewport height changes.
const HudScript = preload("res://scripts/exploration_hud.gd")
var checks: int = 0
var failures: int = 0

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("Exploration HUD anchor QA: " + description)

func _run() -> void:
	# The original menu artwork is 45 high, at 2x scale.
	for height in [480.0, 600.0, 720.0, 900.0]:
		var top: float = HudScript.help_menu_top_for_height(height, 45.0, 2.0)
		_check(is_equal_approx(top + 90.0 + 25.0, height), "fixed bottom margin at %.0f" % height)
	_check(is_equal_approx(HudScript.help_menu_top_for_height(480.0,45.0,2.0),365.0), "original 480px scene placement preserved")
	_check(is_equal_approx(HudScript.help_menu_top_for_height(720.0,45.0,2.0),605.0), "tall camera panel moves 240px down")
	_check(is_equal_approx(HudScript.help_menu_top_for_height(90.0,45.0,2.0),0.0), "small view cannot position artwork above origin")
	print("Exploration HUD anchor QA: %d/%d checks passed" % [checks - failures,checks])
	quit(0 if failures == 0 else 1)
