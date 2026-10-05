extends RefCounted
class_name FishingMasterDeepwaterVeteranPolicy

## Pure lesson policy for Master Deep-Water Veteran.
##
## The lesson never grants a temporary mastery capability and never edits the
## encounter's tension/fish state. It observes the existing deep-water event:
## 1. Yield to the initial DIVE by releasing K.
## 2. When the real delayed load arrives, recover the lesson input with K + S.
## 3. Hold that response for the same 0.16 s used by Deep-Water Control v1.
##
## Once the demonstration succeeds, the NPC teaches the canonical mastery.

const DeepWaterPolicy = preload(
    "res://scripts/fishing_deep_water_control_policy.gd"
)

const INTENT_DIVE: StringName = &"dive"


static func is_initial_yield(
    intent: Dictionary,
    player_reeling: bool
) -> bool:
    return (
        StringName(str(intent.get("intent_id", "unknown"))) == INTENT_DIVE
        and not bool(intent.get("thrashing", false))
        and not player_reeling
    )


static func is_qualifying_load(snapshot: Dictionary) -> bool:
    return (
        StringName(str(snapshot.get("intent_id", "unknown"))) == INTENT_DIVE
        and float(snapshot.get("load_impulse", 0.0)) > 0.0
        and float(snapshot.get("total_depth_m", 0.0))
            >= DeepWaterPolicy.MIN_TOTAL_DEPTH_METERS
        and float(snapshot.get("depth_ratio", 0.0))
            >= DeepWaterPolicy.MIN_EFFECTIVE_DEPTH_RATIO
    )


static func get_response_window_seconds(snapshot: Dictionary) -> float:
    var intent := {
        "intensity": clampf(float(snapshot.get("intensity", 0.0)), 0.0, 1.0),
    }
    return DeepWaterPolicy.get_recovery_window_seconds(intent)


static func is_recovery_response_matching(
    player_reeling: bool,
    player_tension_bias: float
) -> bool:
    return DeepWaterPolicy.is_recovery_response_matching(
        player_reeling,
        player_tension_bias
    )


static func advance_match_time(
    current_time: float,
    player_reeling: bool,
    player_tension_bias: float,
    delta: float
) -> float:
    return DeepWaterPolicy.advance_match_time(
        current_time,
        is_recovery_response_matching(player_reeling, player_tension_bias),
        delta
    )


static func is_recovery_complete(match_time: float) -> bool:
    return DeepWaterPolicy.is_recovery_complete(match_time)


static func get_hold_required_seconds() -> float:
    return DeepWaterPolicy.RECOVERY_HOLD_SECONDS
