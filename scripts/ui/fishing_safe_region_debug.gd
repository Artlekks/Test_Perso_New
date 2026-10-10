extends Control
## Scene-owned, read-only projection guide on the canonical world surface.
var rig: Node
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
func _process(_delta: float) -> void:
	visible = OS.is_debug_build() and is_instance_valid(rig) and rig.fishing_safe_debug_visible and rig._fight_tracking_active
	if visible: queue_redraw()
func _draw() -> void:
	if is_instance_valid(rig):
		var size: Vector2 = rig.get_node("Camera3D").get_viewport().get_visible_rect().size
		var frames: Array[Rect2] = rig.fishing_safe_frames()
		var active: int = 0 if rig.fishing_camera_state == rig.FishingCameraPresentationState.TRAVEL else 1
		var other := frames[1-active]
		draw_rect(Rect2(other.position*size,other.size*size),Color(0,1,1,0.5),false,1.0,false)
		draw_rect(rig.fishing_safe_region_pixels(),Color.YELLOW,false,3.0,false)
		var anchor: Rect2 = rig.player_anchor_region()
		draw_rect(Rect2(anchor.position*size,anchor.size*size),Color(0.4,1,0.5,0.7),false,1.0,false)
		draw_string(ThemeDB.fallback_font,Vector2(260,24),"TRAVEL" if active == 0 else "ANCHORED",HORIZONTAL_ALIGNMENT_LEFT,-1,16,Color.YELLOW)
		var camera: Camera3D = rig.get_node("Camera3D")
		if is_instance_valid(rig._fight_tracking_target): draw_circle(camera.unproject_position(rig._fight_tracking_target.global_position),3,Color.YELLOW)
		if is_instance_valid(rig.target): draw_circle(camera.unproject_position(rig.target.global_position),3,Color.GREEN)
