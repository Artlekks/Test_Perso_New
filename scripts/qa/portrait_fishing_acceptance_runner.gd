extends SceneTree
func _initialize() -> void:
	ProjectSettings.set_setting("application/config/use_custom_user_dir", true)
	ProjectSettings.set_setting("application/config/custom_user_dir_name", "PortraitFishingRunner-%d" % Time.get_ticks_usec())
	call_deferred("run")
func run() -> void:
	var fixture = load("res://actors/mobile/PortraitFishingAcceptance.tscn").instantiate()
	fixture.companion = OS.get_cmdline_user_args().has("--companion")
	root.add_child(fixture)
