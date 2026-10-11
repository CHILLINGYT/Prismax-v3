extends Node

const CombatConfig = preload("res://personaje/transformaciones/transformacion ataque/scripts/combat/combat_config.gd")
const AttackTokenManager = preload("res://personaje/transformaciones/transformacion ataque/scripts/combat/attack_token_manager.gd")
const CombatFormation = preload("res://personaje/transformaciones/transformacion ataque/scripts/combat/combat_formation.gd")
const ThreatSystem = preload("res://personaje/transformaciones/transformacion ataque/scripts/combat/threat_system.gd")
const ComboSystem = preload("res://personaje/transformaciones/transformacion ataque/scripts/combat/combo_system.gd")

## Coordinates the encounter: keeps the enemy registry and owns the shared
## combat sub-systems. It does NOT run AI, damage or attacks itself.

signal enemy_registered(enemy: Node3D)
signal enemy_died(enemy: Node3D)

@export var config: CombatConfig
## Optional explicit player. Empty = whoever registered with set_player(), or the
## first node in the "player" group as a last resort.
@export var player_path: NodePath

var tokens: AttackTokenManager
var formation: CombatFormation
var threats: ThreatSystem
var combo: ComboSystem

var _enemies: Array = []
var _player: Node3D


func _enter_tree() -> void:
	# Registered early (before any _ready) so enemies/player can find us.
	add_to_group("combat_manager")
	_init_systems()


func _ready() -> void:
	# Safety net in case script defaults were not applied in _enter_tree.
	if tokens == null:
		_init_systems()


func _init_systems() -> void:
	if config == null:
		config = CombatConfig.new()
	tokens = AttackTokenManager.new(config.max_attackers)
	formation = CombatFormation.new()
	threats = ThreatSystem.new()
	combo = ComboSystem.new(config.combo_keep_time, config.input_buffer_time)


func register_enemy(enemy: Node3D) -> void:
	if enemy == null or _enemies.has(enemy):
		return
	_enemies.append(enemy)
	enemy_registered.emit(enemy)


func unregister_enemy(enemy: Node3D) -> void:
	_enemies.erase(enemy)


func notify_enemy_died(enemy: Node3D) -> void:
	unregister_enemy(enemy)
	enemy_died.emit(enemy)


func get_active_enemies() -> Array:
	var out: Array = []
	for e in _enemies:
		if is_instance_valid(e) and (not e.has_method("is_alive") or e.is_alive()):
			out.append(e)
	return out


## The player calls this when it binds, so the manager never has to search the
## whole scene tree for it on every frame.
func set_player(p: Node3D) -> void:
	_player = p


func get_player() -> Node3D:
	if _player != null and is_instance_valid(_player):
		return _player
	if not player_path.is_empty():
		_player = get_node_or_null(player_path) as Node3D
	if _player == null:
		# Last resort only, and cached from then on.
		_player = get_tree().get_first_node_in_group("player") as Node3D
	return _player


func combo_count() -> int:
	return combo.count if combo != null else 0


func _physics_process(delta: float) -> void:
	if config == null or combo == null:
		return
	tokens.prune()
	tokens.update()
	threats.update(delta)
	combo.update(delta)
	var player: Node3D = get_player()
	var center: Vector3 = player.global_position if player != null else Vector3.ZERO
	formation.compute(get_active_enemies(), center, config)