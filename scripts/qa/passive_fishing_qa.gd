extends SceneTree
var checks := 0
var failures: Array[String] = []
var shell: Node
var fishing: Node
class InputWitness extends Node:
	var presses := 0
	func _input(event: InputEvent) -> void:
		if event.is_action_pressed("enter_fishing") and not event.is_echo(): presses += 1

class ForcedFish extends RefCounted:
	func get_forced_fish(): return load("res://data/bof4/fish/sea_bream.tres")
func _initialize() -> void:
	ProjectSettings.set_setting("application/config/use_custom_user_dir",true)
	ProjectSettings.set_setting("application/config/custom_user_dir_name","PassiveFishingQA-%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(OS.get_user_data_dir())
	call_deferred("run")
func check(ok: bool,label: String) -> void:
	checks += 1
	if not ok: failures.append(label); push_error(label)
func wait_for(predicate: Callable,label: String,seconds := 15.0) -> bool:
	var until := Time.get_ticks_msec()+int(seconds*1000)
	while not predicate.call() and Time.get_ticks_msec()<until: await process_frame
	var ok: bool = predicate.call()
	check(ok,label)
	return ok
func run() -> void:
	shell = load("res://actors/desktop/DesktopCompanion.tscn").instantiate()
	root.add_child(shell)
	shell.passive.require_focus_confirmation = false
	current_scene = shell
	await create_timer(1).timeout
	fishing = shell.game.get_node("Game/Fishing")
	fishing.encounter.debug_settings = ForcedFish.new()
	var session: Node = root.get_node("FishingSessionServices")
	var session_id := session.get_instance_id()
	var geometry := Rect2i(root.position,root.size)
	var casts := [0]
	fishing.cast_started.connect(func(): casts[0]+=1)
	shell.passive.focus_seconds = 1.0
	shell.passive.opportunity_seconds = 0.3
	shell.passive.rng.seed = 75
	shell.set_mode(shell.Mode.PASSIVE)
	check(shell.mode == shell.Mode.PASSIVE,"Passive accepted at legal shoreline")
	check(Rect2i(root.position,root.size)==geometry,"Mode never changes floating geometry")
	if not await wait_for(func(): return shell.passive.state==shell.passive.State.FOCUS,"real entry/cast reaches focus through production callbacks"): shell.queue_free(); quit(1); return
	check(casts[0]==1,"one physical cast")
	check(shell.passive.scheduled_at>=1 and shell.passive.scheduled_at<=1.3,"seeded opportunity inside configured window")
	check(not fishing.encounter.bite_active and fishing.encounter.bite_timer.is_stopped(),"normal bite scheduler suppressed")
	# A stale/explicit normal timer callback must not bypass the lease.
	fishing.encounter._on_bite_timer_timeout()
	check(not fishing.encounter.bite_active,"ordinary callback cannot create early bite")
	var bait_id: int = fishing.caster.active_bait.get_instance_id()
	shell.toggle_collapse()
	await create_timer(.25).timeout
	check(not fishing.encounter.bite_active,"no bite before focus duration")
	check(shell.mode==shell.Mode.PASSIVE and fishing.caster.active_bait.get_instance_id()==bait_id,"collapse preserves activity and bait")
	if not await wait_for(func(): return shell.passive.is_ready(),"exactly one ready opportunity"): quit(1); return
	check(shell.mode==shell.Mode.ACTIVE,"timer completion automatically transfers Active while collapsed")
	check(shell.passive.opportunities==1 and fishing.encounter.bite_hook_ready,"one production hook-ready opportunity")
	check(shell.status.visible and shell.status.text == "!" and shell.buttons.Collapse.tooltip_text.contains("FISH READY"),"collapsed strip signals readiness")
	await create_timer(2.0).timeout
	check(fishing.encounter.bite_active and fishing.encounter.bite_window_timer.is_stopped(),"readiness survives multiple normal bite-window durations")
	check(shell.passive.opportunities==1,"no duplicate opportunity")
	var before_expand: int = shell.mode
	shell.toggle_collapse()
	check(shell.mode==before_expand,"expand never changes activity")
	await wait_for(func(): return not shell._request_pending and not shell._pending_float_decoration and Rect2i(root.position,root.size)==geometry,"expand completes ordered native restoration")
	shell.set_mode(shell.Mode.ACTIVE)
	check(Rect2i(root.position,root.size)==geometry,"Active preserves geometry")
	check(fishing.encounter.bite_active,"handoff retains persistent opportunity")
	check(session.save_all_fishing_state().get("durable",false),"normal save during ready state remains durable")
	var before_load: Dictionary = session.inventory.get_all_fish_counts()
	check(session.inventory.load_from_disk() and session.progress.load_from_disk(),"production inventory/progress load during ready state")
	check(session.inventory.get_all_fish_counts()==before_load,"loading ready save grants no fish")
	check(shell.passive.is_ready() and fishing.caster.active_bait.get_instance_id()==bait_id,"load does not duplicate runtime opportunity or bait")
	check(fishing.encounter.active_fish==null,"no fish/reward before user response")
	var event := InputEventAction.new()
	event.action = &"enter_fishing"
	event.pressed = true
	fishing._unhandled_input(event)
	check(fishing.phase==fishing.Phase.FIGHT,"existing confirm hooks and starts ordinary fight")
	fishing.caster._on_bait_returned() # Production landing boundary, no fight balance shortcut claim.
	if not await wait_for(func(): return fishing.phase==fishing.Phase.WAIT_RESULT,"ordinary landing/catch pipeline resolves",20): quit(1); return
	check(fishing.last_outcome_result.get("catch_committed",false),"existing catch/reward persistence commits")
	var saved_catches: Dictionary = session.inventory.get_all_fish_counts()
	check(session.inventory.load_from_disk() and session.inventory.get_all_fish_counts()==saved_catches,"production catch survives save/load exactly")
	fishing._unhandled_input(event)
	if not await wait_for(func(): return fishing.phase==fishing.Phase.AIM,"ordinary result dismissal returns aim"): quit(1); return
	for cycle in range(4):
		shell.set_window_state(shell.WindowState.FLOATING if cycle == 0 else (shell.WindowState.DOCK_LEFT if cycle == 1 else shell.WindowState.DOCK_RIGHT))
		await create_timer(.2).timeout
		shell.passive.focus_seconds = 30
		shell.set_mode(shell.Mode.PASSIVE)
		await wait_for(func(): return shell.passive.state==shell.passive.State.FOCUS,"repeated passive cast settles")
		if cycle==0: await passive_camera_drift()
		if cycle == 3: shell.toggle_collapse(); await create_timer(.2).timeout
		var window_before: int = shell.window_state
		var width_before: int = shell.dock_width
		var session_before: int = fishing.get_instance_id()
		var bait_before: int = fishing.caster.active_bait.get_instance_id()
		fishing.technique_detector.reset()
		var pulses_before: int = fishing.technique_detector._pulse_times.size()
		var witness := InputWitness.new()
		shell.gameplay_viewport.add_child(witness)
		var takeover := InputEventKey.new()
		takeover.physical_keycode = KEY_K
		takeover.keycode = KEY_K
		takeover.pressed = true
		Input.parse_input_event(takeover)
		await process_frame
		check(shell.mode == shell.Mode.ACTIVE,"fresh K immediately transfers Active")
		check(fishing.get_instance_id() == session_before and fishing.caster.active_bait.get_instance_id() == bait_before,"K retains same session and physical bait")
		check(shell.window_state == window_before and shell.dock_width == width_before,"K preserves Float/Dock/Collapsed geometry ownership")
		check(witness.presses == 1 and fishing.technique_detector._pulse_times.size() == pulses_before + 1 and fishing.caster.is_active_bait_reeling(),"K forwarded to normal reel exactly once")
		takeover.pressed = false
		Input.parse_input_event(takeover)
		await process_frame
		check(not fishing.caster.is_active_bait_reeling(),"K release reaches normal owner")
		witness.queue_free()
		check(shell.passive.state==shell.passive.State.IDLE,"early Active cancels schedule")
		check(not fishing.encounter.bite_active,"cancel awards no opportunity")
		fishing._cancel_water_cast_to_aim()
		await create_timer(.25).timeout
	if shell.window_state == shell.WindowState.COLLAPSED: shell.toggle_collapse()
	shell.set_window_state(shell.WindowState.FLOATING)
	await create_timer(.25).timeout
	check(session.get_instance_id()==session_id,"no duplicate session")
	check(shell.find_children("PassiveFishingController","",true,false).size()==1,"one passive orchestrator")
	shell.set_mode(shell.Mode.PASSIVE)
	await wait_for(func(): return shell.passive.state==shell.passive.State.FOCUS,"travel starts with active focus")
	shell.load_gameplay_scene("res://actors/FishingTestScene_V2.tscn")
	await create_timer(1).timeout
	check(shell.mode==shell.Mode.ACTIVE and shell.passive.state==shell.passive.State.IDLE,"travel invalidates old schedule")
	check(not shell.game.get_node("Game/Fishing").encounter.bite_active,"replacement runtime has no stale opportunity")
	check(root.get_node("FishingSessionServices").get_instance_id()==session_id,"travel keeps authoritative session")
	shell.queue_free()
	session.queue_free()
	await create_timer(.5).timeout
	check(Node.get_orphan_node_ids().is_empty(),"no orphan timers/controllers")
	shell = load("res://actors/desktop/DesktopCompanion.tscn").instantiate()
	root.add_child(shell)
	current_scene=shell
	await create_timer(1).timeout
	check(shell.mode==shell.Mode.ACTIVE and shell.passive.state==shell.passive.State.IDLE,"restart cannot restore a passive timer/opportunity")
	check(root.get_node("FishingSessionServices").inventory.get_all_fish_counts()==saved_catches,"restart restores only authoritative catch inventory")
	check(not is_instance_valid(shell.game.get_node("Game/Fishing").caster.active_bait),"restart has no old physical bait")
	shell.queue_free()
	root.get_node("FishingSessionServices").queue_free()
	await create_timer(.5).timeout
	check(Node.get_orphan_node_ids().is_empty(),"restart teardown leaves no orchestrator orphans")
	print("Passive Fishing QA: %d/%d; failures=%s" % [checks-failures.size(),checks,failures])
	quit(0 if failures.is_empty() else 1)

class DriftCurrent extends FishingCurrentService:
	var velocity := Vector3.ZERO
	func smooth_current_velocity(_previous: Vector3, _world: Vector3, _delta: float) -> Vector3:
		return velocity

func water_point(camera: Camera3D, bait: Node3D, pixel: Vector2) -> Vector3:
	var origin := camera.project_ray_origin(pixel)
	var direction := camera.project_ray_normal(pixel)
	var point: Vector3 = origin+direction*((bait.water_y+0.025-origin.y)/direction.y)
	point.y = bait.global_position.y
	return point

func passive_camera_drift() -> void:
	var bait: Node3D = fishing.caster.active_bait
	var rig: Node3D = fishing.camera_rig
	var camera: Camera3D = rig.get_node("Camera3D")
	var original := bait.global_transform
	var original_mode := bait.process_mode
	var original_current = bait.current_service
	var original_action = bait.lure_action_runtime
	bait.process_mode = Node.PROCESS_MODE_DISABLED
	bait.lure_action_runtime = null
	var size := Vector2(shell.gameplay_viewport.size)
	rig.fight_camera_tracking.reset()
	camera.transform = rig._fight_base_camera_transform
	var shot := camera.global_transform
	# Empty-lure camera comfort/physical visibility differ from hooked-fish
	# framing. Use points on the actual water plane, not aerial depth-12 rays.
	for side in [-1,1]:
		for frame in range(60):
			var x: float = (.23 if side<0 else .60)+sin(frame*.1)*.02
			bait.global_position = water_point(camera,bait,Vector2(x,.4)*size)
			await process_frame
		check(shell.mode==shell.Mode.PASSIVE and shell.passive.state==shell.passive.State.FOCUS,"Passive drift retains activity/focus")
		check(rig._fight_tracking_active and not rig.fight_camera_tracking.tracking,"Passive water owner remains active without dead-zone correction")
		check(camera.global_transform.is_equal_approx(shot),"real Passive physical drift does not micro-rotate side %d" % side)
	for side in [-1,1]:
		var held := camera.global_transform
		var held_offsets := Vector2(camera.h_offset,camera.v_offset)
		for x in ([.5,.25,.18] if side<0 else [.5,.60,.65]):
			bait.global_position = water_point(camera,bait,Vector2(x,.45)*size)
			for frame in range(3): await process_frame
			check(camera.global_transform==held and Vector2(camera.h_offset,camera.v_offset).is_equal_approx(held_offsets),"Passive safe journey holds yaw and optical framing")
		var drift := DriftCurrent.new()
		fishing.add_child(drift)
		bait.current_service = drift
		bait.global_position = water_point(camera,bait,Vector2(.12 if side<0 else .84,.45)*size)
		var before_yaw: float = rig.fight_camera_tracking.yaw
		var escaped := false
		for frame in range(90):
			drift.velocity = preload("res://scripts/fishing_screen_lateral.gd").right(camera,bait.get_surface_position(),Vector3.RIGHT)*float(side)*0.35
			bait._physics_process(1.0/60.0)
			await process_frame
			var pixel := camera.unproject_position(bait.get_surface_position())/size
			if not rig.free_lure_viewport_region().has_point(pixel): escaped = true
		check((rig.fight_camera_tracking.yaw-before_yaw)*side<0 if side>0 else is_equal_approx(rig.fight_camera_tracking.yaw,before_yaw),"Passive uses modest right yaw and retains quiet left framing")
		check(not escaped,"Passive current cannot push physical lure out of viewport/HUD guard")
		bait.current_service = original_current
		drift.free()
		var panned := camera.global_transform
		var panned_offsets := Vector2(camera.h_offset,camera.v_offset)
		for x in [.18,.5,.65]:
			bait.global_position = water_point(camera,bait,Vector2(x,.45)*size)
			for frame in range(3): await process_frame
			check(camera.global_transform==panned and Vector2(camera.h_offset,camera.v_offset).is_equal_approx(panned_offsets),"Passive safe reentry and cross-center freeze yaw/framing immediately")
	check(not fishing.encounter.bite_active,"drift test cannot bypass focus opportunity timer")
	bait.current_service = original_current
	bait.lure_action_runtime = original_action
	bait.global_transform = original
	bait.process_mode = original_mode
