extends Resource

## Definition of a single attack in the player's combo chain.
## Phases are represented with timers - MEJORA #4: 5-hit combo con finisher

@export var id: String = "attack"
@export var animation: String = ""
@export var damage: float = 20.0
@export var attack_range: float = 2.4
@export var ideal_distance: float = 1.7
@export var approach_speed: float = 9.0
@export var windup: float = 0.12
@export var active: float = 0.12
@export var recovery: float = 0.30
@export var cancel_window: float = 0.12
@export var knockback: float = 3.0
@export var stun: float = 0.0
@export var speed: float = 1.0

# --- MEJORA #4: Nuevos campos para 5-hit combo ---
@export var stamina_cost: float = 5.0 ## Costo de estamina de este golpe
@export var attack_type: String = "light" ## light/medium/heavy/finisher
@export var is_finisher: bool = false ## True si es el remate final (slowmo, VFX grande)
@export var hitstop_duration: float = 0.05 ## Duración del hitstop para este golpe
@export var camera_shake: float = 0.3 ## Intensidad del shake de cámara