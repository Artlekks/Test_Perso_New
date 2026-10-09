extends SceneTree
## Deterministic owner-notification tests: presence polling stays disabled during stress.
var checks := 0
var failures := PackedStringArray()
var casts := 0
var transitions := 0
func _initialize() -> void:
	var isolated := "CodexBaitLifecycleQA-%d" % Time.get_ticks_usec()
	ProjectSettings.set_setting("application/config/use_custom_user_dir", true)
	ProjectSettings.set_setting("application/config/custom_user_dir_name", isolated)
	if not OS.get_user_data_dir().ends_with(isolated) or DirAccess.make_dir_recursive_absolute(OS.get_user_data_dir()) != OK:
		quit(1)
		return
	call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); push_error(label)
func settle(frames: int = 3) -> void:
	for frame in range(frames): await process_frame
func spawn(fishing: Node, zone: Node):
	casts += 1
	fishing.phase = fishing.Phase.BAIT_FLYING
	var bait = fishing.caster.perform_cast(0.5, Vector3.FORWARD, zone.get_water_y(), zone.get_bottom_y(), fishing.loadout.get_selected_lure(), zone.get_swim_bounds(), zone.get_shore_boundary())
	bait.set_physics_process(false)
	bait.state = bait.State.IN_WATER
	bait.global_position = zone.water_surface.global_position
	fishing.caster._on_bait_landed(bait.global_position)
	return bait
func assert_binding(presence: Node, bait: Node3D) -> void:
	check(presence._active_bait == bait, "presence synchronously follows caster owner")
	for shadow in presence.get_shadows():
		if not shadow.is_hooked_tracking(): check(shadow._bait == bait, "ambient actor shares current owner")
func run() -> void:
	for mobile in [false, true]:
		for startup in range(6):
			var host: Node = load("res://actors/mobile/MobilePortraitHarness.tscn" if mobile else "res://actors/FishingTestScene_V2.tscn").instantiate()
			if mobile: host.isolated_playtest_save = false
			root.add_child(host)
			current_scene = host
			await settle(6)
			var game: Node = host.game if mobile else host
			var fishing: Node = game.get_node("Game/Fishing")
			var mode: Node = game.get_node("Game/GameMode")
			var zone: Node = game.get_node("World/FishZone_V2")
			var presence: Node = zone.shadow_presence
			check(presence._bait_owner == fishing.caster, "scene-local owner resolved in desktop/mobile")
			mode.enter_fishing(zone)
			await settle(35)
			presence.set_debug_shadow_count_override(2)
			presence.set_process(false)
			await settle()
			for cycle in range(20):
				var bait = spawn(fishing, zone)
				assert_binding(presence, bait)
				var bait_ref: WeakRef = weakref(bait)
				match cycle % 5:
					0:
						# Old bait remains queued/alive while the replacement owns all consumers.
						var old = bait
						bait = spawn(fishing, zone)
						assert_binding(presence, bait)
						old.returned.emit()
						check(fishing.caster.active_bait == bait, "late old returned event cannot delete successor")
						await settle()
						assert_binding(presence, bait)
						fishing.caster.cancel_bait_to_aim()
					1:
						fishing.caster.cancel_bait_to_aim()
					2:
						# Unexpected immediate destruction also unbinds before the free completes.
						bait.free()
						check(fishing.caster.active_bait == null, "unexpected bait exit clears owner")
					3:
						fishing.caster.cancel_bait_to_aim()
						mode.exit_fishing()
						await settle(35)
						mode.enter_fishing(zone)
						await settle(35)
					4:
						fishing.encounter.lifecycle.open_bite_window()
						check(fishing.encounter._resolve_bite_miss(&"qa_lifecycle"), "missed opportunity uses production cleanup")
						fishing.caster.cancel_bait_to_aim()
				assert_binding(presence, null)
				await settle()
				check(bait_ref.get_ref() == null, "old bait released")
				# Exact original ordering: tide rebuild occurs before any presence poll.
				presence.set_debug_shadow_count_override(2)
				presence.set_environment_context({"qa_lifecycle_cycle": startup * 100 + cycle})
				await settle()
				check(presence.get_population_debug_counts().x == 2, "ambient override count survives rebuild without bait")
			# Replacing a hooked cast invalidates its actor immediately, before free.
			var replaced_hook = spawn(fishing, zone)
			fishing.encounter.pending_fish_entry = zone.get_fish_population()[0]
			check(fishing.encounter._confirm_hit(), "hook before replacement")
			var previous_shadow: Node = presence._fight_shadow
			var successor = spawn(fishing, zone)
			check(previous_shadow._bait != replaced_hook and previous_shadow._fight_bait == null and not previous_shadow.is_hooked_tracking(), "hooked actor releases old generation synchronously on replacement")
			assert_binding(presence, successor)
			fishing.caster.cancel_bait_to_aim()
			await settle()
			check(not is_instance_valid(replaced_hook), "replaced hooked bait freed")
			# Hook/held landing/next cast: actual encounter + landing timer path.
			var hooked = spawn(fishing, zone)
			fishing.encounter.pending_fish_entry = zone.get_fish_population()[0]
			check(fishing.encounter._confirm_hit(), "production hook")
			fishing.caster._on_bait_returned()
			check(is_instance_valid(hooked) and fishing.caster.active_bait == hooked, "landing preserves intentionally held physical bait")
			await create_timer(fishing.catch_landing_hold_time + 0.1).timeout
			check(fishing.phase == fishing.Phase.CATCH and presence._active_bait == null, "landing releases ownership after hold")
			mode.exit_fishing()
			await settle(35)
			mode.enter_fishing(zone)
			await settle(35)
			var next = spawn(fishing, zone)
			assert_binding(presence, next)
			# Travel while waterborne, then return. Services stay session-owned.
			DeveloperPlaytestService.current().set_enabled(true)
			var old_presence: WeakRef = weakref(presence)
			var old_bait: WeakRef = weakref(next)
			check(root.get_node("WorldLocations").request_travel(&"wyndia_ocean_outpost").reason == "fishing_owns_input", "Developer travel respects active fishing owner")
			# Travel is intentionally forbidden during fishing. Release mode, retaining
			# the bait only for this scene-destruction cancellation test.
			mode.exit_fishing()
			await settle(35)
			check(root.get_node("WorldLocations").request_travel(&"wyndia_ocean_outpost").success, "travel destroys scene with pending bait")
			transitions += 1
			await settle(35)
			check(old_presence.get_ref() == null and old_bait.get_ref() == null, "travel releases old presence and bait")
			check(root.get_node("WorldLocations").request_travel(&"beach").success, "return travel")
			transitions += 1
			await settle(35)
			if not mobile: host = current_scene
			host.queue_free()
			current_scene = null
			await settle(5)
			check(Node.get_orphan_node_ids().is_empty(), "startup/teardown has no orphan nodes")
	var services := root.get_node_or_null("FishingSessionServices")
	if services != null: services.queue_free()
	await settle(5)
	check(Node.get_orphan_node_ids().is_empty(), "strict final teardown")
	print("Bait Ownership Lifecycle QA: %d/%d; casts=%d; transitions=%d; host lifetimes=12; failures=%s" % [checks-failures.size(), checks, casts, transitions, failures])
	quit(0 if failures.is_empty() else 1)

