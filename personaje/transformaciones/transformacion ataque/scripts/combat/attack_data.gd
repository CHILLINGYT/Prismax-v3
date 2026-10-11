extends Resource

## Definition of a single attack in the player's combo chain.
## Phases are represented with timers (no real animations yet).

@export var id: String = "attack"
## Clip played while this attack runs (empty = keep whatever is playing). The
## animation is presentation only: damage is still resolved by the timers below.
@export var animation: String = ""
@export var damage: float = 20.0
@export var attack_range: float = 2.4
@export var ideal_distance: float = 1.7
@export var approach_speed: float = 9.0
@export var windup: float = 0.12
@export var active: float = 0.12
@export var recovery: float = 0.30
## Portion of the recovery during which the attack may be cancelled into the next.
@export var cancel_window: float = 0.12
@export var knockback: float = 3.0
@export var stun: float = 0.0