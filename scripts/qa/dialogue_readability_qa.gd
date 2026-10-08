extends SceneTree

const View = preload("res://actors/DialogueView.tscn")
const Catalog = preload("res://data/dialogue/all_dialogues.tres")
const MasterProfiles = preload("res://scripts/mastery/fishing_master_dialogue_profiles.gd")
var checks := 0
var failures: Array[String] = []
var rendered := false
var capture_dir := ""

func _initialize() -> void:
	rendered = OS.get_cmdline_user_args().has("--rendered")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir="):
			capture_dir = arg.trim_prefix("--capture-dir=")
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)

func settle() -> void:
	for frame in range(4):
		await process_frame

func run() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(640, 480)
	viewport.world_2d = World2D.new()
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var view = View.instantiate()
	viewport.add_child(view)
	await settle()
	check(view.body_label.get_theme_font_size("font_size") == 18 and view.choice_label.get_theme_font_size("font_size") == 16, "shared dialogue baseline doubles body/choice sizes")
	check(view.body_label.get_theme_font("font").resource_path == "res://assets/fonts/BOF_Font_Refined.fnt", "existing bitmap font retained")
	check(view.root.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST and view.body_label.autowrap_mode == TextServer.AUTOWRAP_WORD_SMART, "nearest bitmap and smart wrapping")
	for height in [480, 751]:
		viewport.size.y = height
		for definition in Catalog.dialogues:
			for line in definition.lines:
				var choices: Array = []
				for choice in line.choices:
					choices.append({"text": choice.text, "enabled": true})
				view.present({"active": true, "speaker_name": line.speaker_name, "portrait": line.portrait, "text": line.text, "choices": choices, "selected_choice_index": 0})
				await settle()
				check(Rect2(Vector2.ZERO, Vector2(viewport.size)).encloses(view.dialogue_panel.get_rect()), "authored dialogue panel contained %s/%d" % [definition.dialogue_id, height])
				check(view.content_scroll.size.y >= view.body_label.size.y + (view.choice_label.size.y + 8.0 if view.choice_label.visible else 0.0), "authored dialogue/choices fit %s/%d" % [definition.dialogue_id, height])
		for profile in MasterProfiles.PROFILES.values():
			for state in ["intro", "active", "learned", "revisit"]:
				view.present({"active": true, "speaker_name": profile.speaker_name, "text": profile[state], "choices": [], "portrait": preload("res://data/dialogue/portraits/master_gyosil.tres")})
				await settle()
				check(view.content_scroll.size.y >= view.body_label.size.y and Rect2(Vector2.ZERO, Vector2(viewport.size)).encloses(view.dialogue_panel.get_rect()), "master dialogue wraps and fits %s/%s/%d" % [profile.speaker_name, state, height])
		view.present({"active": true, "speaker_name": "Merchant", "text": "Take a look. Trade your fish for supplies, or sell your catch to earn Zenny.", "choices": [{"text": "Buy fishing supplies", "enabled": true}, {"text": "Sell fish", "enabled": true}, {"text": "Leave", "enabled": true}], "selected_choice_index": 1})
		await settle()
		check(view.choice_label.text.contains("> Sell fish"), "choice selector survives reflow %d" % height)
		if rendered:
			get_root().size = Vector2i(640, height)
			var image := TextureRect.new()
			image.texture = viewport.get_texture()
			image.size = Vector2(viewport.size)
			image.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			root.add_child(image)
			DirAccess.make_dir_recursive_absolute(capture_dir)
			for frame in range(3):
				await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(capture_dir.path_join("dialogue-%d.png" % height))
			image.free()
	view.present({"active": true, "text": "A long help paragraph that should wrap without escaping the dialogue box. ".repeat(60), "choices": [], "speaker_name": "Help"})
	await settle()
	check(Rect2(Vector2.ZERO, Vector2(viewport.size)).encloses(view.dialogue_panel.get_rect()) and view.content_scroll.get_v_scroll_bar().max_value > view.content_scroll.size.y, "oversize future help stays contained with a scrollable overflow")
	view.hide_dialogue()
	check(not view.root.visible, "closing dialogue still hides shared view")
	viewport.free()
	print("DIALOGUE READABILITY QA: %d/%d" % [checks - failures.size(), checks])
	quit(0 if failures.is_empty() else 1)
