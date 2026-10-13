extends AnimatedSprite3D
## Bite recognition cue above the fisherman. Uses the six ORIGINAL frames of
## assets/ui/Exclamation.png, not a generated/repainted asset.
## Player-relative placement follows heading while billboard faces the camera.

const EXCLAMATION_SHEET: Texture2D = preload("res://assets/ui/Exclamation.png")
const FRAME_COUNT: int = 6
const FRAME_WIDTH: int = 32
const FRAME_HEIGHT: int = 33

@export var height_above_player: float = 0.91
@export var heading_offset: float = 0.02
@export var alert_pixel_size: float = 0.003
@export var alert_fps: float = 11.0

func _ready() -> void:
    visible = false
    billboard = BaseMaterial3D.BILLBOARD_ENABLED
    texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
    shaded = false
    no_depth_test = true
    double_sided = true
    fixed_size = true
    pixel_size = alert_pixel_size
    centered = true
    offset = Vector2.ZERO
    cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    # The fishing player's local forward is basis.z in this project.
    position = Vector3(0.0, height_above_player, heading_offset)
    var frames: SpriteFrames = SpriteFrames.new()
    frames.add_animation(&"Alert")
    frames.set_animation_speed(&"Alert", alert_fps)
    frames.set_animation_loop(&"Alert", false)
    for index in range(FRAME_COUNT):
        var atlas_frame: AtlasTexture = AtlasTexture.new()
        atlas_frame.atlas = EXCLAMATION_SHEET
        atlas_frame.region = Rect2(FRAME_WIDTH * index, 0, FRAME_WIDTH, FRAME_HEIGHT)
        frames.add_frame(&"Alert", atlas_frame)
    sprite_frames = frames
    animation = &"Alert"
    stop()


func show_bite_window() -> void:
    visible = true
    stop()
    frame = 0
    play(&"Alert")


func hide_bite_window() -> void:
    visible = false
    stop()
    frame = 0
