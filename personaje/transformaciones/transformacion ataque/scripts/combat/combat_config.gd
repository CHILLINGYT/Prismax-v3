extends Resource

## Central, tunable configuration for the FreeFlow combat prototype.
## One instance is owned by the CombatManager and shared by every system.

@export_group("Targeting")
## Maximum distance at which an enemy can be picked as a target.
@export var target_radius: float = 9.0
## Total width of the selection cone around the player's intent direction.
@export var target_max_angle_deg: float = 140.0
## Intent weights: how much each input signal shapes the desired direction.
@export var weight_move_direction: float = 4.0
@export var weight_camera: float = 2.5
@export var weight_facing: float = 1.0
## Direction priority inside the score (kept above the distance influence).
@export var weight_alignment: float = 3.0
@export var weight_distance: float = 1.0
@export var weight_threat: float = 1.2
## Small bonus for the enemy already targeted. Never a lock.
## Pequeña ventaja del objetivo actual: sólo desempata, no impide cambiar.
@export var current_target_bonus: float = 0.05
## A challenger must beat the current target by this margin to steal it, so
## near-equal candidates do not flip-flop. A clear intent still wins at once.
## 0 = el objetivo cambia en cuanto otro candidato puntúa más (cambio inmediato,
## como pide el FreeFlow); con un margen mayor el objetivo se quedaría "pegado".
@export var target_switch_threshold: float = 0.0

@export_group("Player attack")
@export var attack_windup: float = 0.12
@export var attack_active: float = 0.12
@export var attack_recovery: float = 0.30
@export var attack_cancel_window: float = 0.12
@export var attack_range: float = 2.4
@export var attack_ideal_distance: float = 1.7
@export var attack_damage: float = 20.0
@export var attack_knockback: float = 3.0
## Minimum dot between facing and target for a hit to land (~72 degree half cone).
@export var attack_hit_arc: float = 0.3
@export var approach_speed: float = 9.0
@export var approach_max_time: float = 1.5

@export_group("Tokens")
@export var max_attackers: int = 2

@export_group("Formation")
@export var formation_radius: float = 2.2
@export var formation_min_separation: float = 1.3

@export_group("Combo & input buffer")
@export var combo_keep_time: float = 2.0
@export var input_buffer_time: float = 0.2

@export_group("Enemy")
@export var enemy_max_health: float = 100.0
@export var enemy_damage: float = 10.0
@export var enemy_detection_range: float = 12.0
@export var enemy_move_speed: float = 3.5
@export var enemy_attack_range: float = 1.8
@export var enemy_windup: float = 0.5
@export var enemy_active: float = 0.15
@export var enemy_recovery: float = 0.8
@export var enemy_hit_stun: float = 0.25
@export var enemy_death_linger: float = 0.5

@export_group("Counter")
@export var counter_range: float = 2.8
@export var counter_arc: float = 0.2
@export var counter_duration: float = 0.45
@export var counter_stun: float = 1.2

@export_group("Evade")
@export var evade_duration: float = 0.35
@export var evade_speed: float = 10.0
@export var evade_iframes: float = 0.25
@export var evade_recovery: float = 0.15

@export_group("Stun / takedown")
@export var stun_attack_damage: float = 8.0
@export var stun_attack_stun: float = 1.6
@export var stun_windup: float = 0.18
@export var stun_active: float = 0.12
@export var stun_recovery: float = 0.35
@export var takedown_range: float = 2.6
@export var takedown_windup: float = 0.3
@export var takedown_recovery: float = 0.4

@export_group("Special / gadget")
@export var special_damage: float = 40.0
@export var special_min_combo: int = 2
@export var special_windup: float = 0.35
@export var special_active: float = 0.18
@export var special_recovery: float = 0.5
@export var gadget_radius: float = 4.5
@export var gadget_damage: float = 5.0
@export var gadget_stun: float = 1.2
@export var gadget_cooldown: float = 6.0

@export_group("Fluidity")
## Player turn rate (rad/s) while correcting towards a target: fast, but never
## an instant 180 degree snap.
@export var player_turn_speed: float = 14.0
## Seconds an enemy waits for a turn before sidestepping to a new angle.
@export var wait_patience: float = 1.2
## Seconds without making progress before an enemy walks around a blocker.
@export var stall_time: float = 0.4
## How long a sidestep (go-around / reposition) lasts.
@export var sidestep_time: float = 0.55