extends AnimationPlayer

## Presentation layer for the player's skeletal animations.
##
## It owns exactly one decision: WHICH clip plays and how fast. Movement,
## targeting, damage and the state machine stay in player.gd, so an animation can
## never take over the controls or decide who gets hit.
##
## Owns the combat-idle rule: 10 seconds counted from the last attack START,
## not from when the combat-idle pose started appearing.

const IDLE := "idle"
const WALK := "walk"
const COMBAT_IDLE := "combat_idle"
const JUMP := "jump"

## Every clip is a copy of the animation inside the source FBX, saved once here
## and shared; the FBX meshes/skeletons are never duplicated for this.
const LIBRARY = preload("res://personaje/transformaciones/transformacion ataque/animations/player_anim_library.tres")

@export_group("Blending")
## Cross-fade used between locomotion clips.
@export var locomotion_blend: float = 0.18
## Cross-fade used when an action (Sprint hit, jump) takes over.
@export var action_blend: float = 0.07

@export_group("Walk")
## Horizontal speed (m/s) at which the walk clip's feet do not slide. Measured
## from the clip itself: ~0.92 m step over a 0.533 s cycle.
@export var walk_reference_speed: float = 3.47
@export var walk_min_speed_scale: float = 0.8
@export var walk_max_speed_scale: float = 1.8
## Below this horizontal speed the player counts as standing still.
@export var stand_still_speed: float = 0.15

@export_group("Combat idle")
## Seconds without starting an attack before the normal idle comes back.
@export var combat_idle_timeout: float = 10.0

var _since_attack: float = 0.0


func _ready() -> void:
	# The clip library is registered here because AnimationPlayer.libraries is not
	# assignable from the scene file.
	if not has_animation_library(""):
		add_animation_library("", LIBRARY)
	# Start out of combat, so a fresh session shows the normal idle.
	_since_attack = combat_idle_timeout


func _process(delta: float) -> void:
	if _since_attack < combat_idle_timeout:
		_since_attack += delta


## Called when a new attack starts. This is what the 10 s countdown measures.
func notify_attack_started() -> void:
	_since_attack = 0.0


func in_combat() -> bool:
	return _since_attack < combat_idle_timeout


## Plays a one-shot clip (Sprint hit, jump). If that clip is already the current
## one it is rewound instead of ignored, so two identical hits in a row play
## twice from frame 0.
func play_action(clip: String, blend: float = -1.0, speed: float = 1.0) -> void:
	if clip.is_empty() or not has_animation(clip):
		return
	# The action's own playback speed (per attack). The owner's phase timers divide
	# the clip by the same value, so a sped-up hit still lands on the visual contact.
	speed_scale = maxf(0.05, speed)
	var b: float = action_blend if blend < 0.0 else blend
	if current_animation == clip:
		seek(0.0, true)
	else:
		play(clip, b, 1.0)


## Locomotion is only driven while the player is free to move. During actions the
## player does not call this, so the action clip keeps playing untouched.
func update_locomotion(horizontal_speed: float, on_floor: bool) -> void:
	if not on_floor and current_animation == JUMP:
		# Airborne while the jump clip still runs: let it finish. The controller
		# owns the vertical motion, this only decides what is on screen.
		return
	if horizontal_speed > stand_still_speed:
		if current_animation != WALK:
			play(WALK, locomotion_blend, 1.0)
		# Scale the cycle with the real speed so the feet do not skate.
		speed_scale = clampf(horizontal_speed / maxf(0.01, walk_reference_speed), walk_min_speed_scale, walk_max_speed_scale)
		return
	speed_scale = 1.0
	var idle_clip: String = COMBAT_IDLE if in_combat() else IDLE
	if current_animation != idle_clip:
		play(idle_clip, locomotion_blend, 1.0)