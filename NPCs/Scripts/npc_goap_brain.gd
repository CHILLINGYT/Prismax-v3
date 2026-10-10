class_name NPCGoapBrain
extends GdPAIAgent

## Capa de decisión con planificador por objetivos (addon GdPlanningAI) para los ciudadanos.
##
## La máquina de estados del ciudadano (IDLE / WALK / PAUSE / TURN / NOTICE / REACT) sigue
## haciendo lo mismo de siempre: moverse, animarse y reaccionar. Lo que aporta esta capa es
## DECIDIR qué conviene hacer a continuación valorando recompensa y coste, en vez de sortear
## entre "pasear" y "quedarse quieto" con un dado:
##
##   - Pasear: recompensa fija.
##   - Descansar: recompensa que SUBE con el cansancio acumulado (que crece al caminar).
##   - Curiosear: recompensa alta si el jugador está cerca y el ciudadano no está ocupado,
##     con coste proporcional a la distancia que le separa de él.
##
## No hay ningún modelo de lenguaje ni servicio externo: es un planificador clásico por estados
## y acciones que corre en local.
##
## Coste: el planificador por agente no es barato, así que sólo se monta en el nivel de detalle
## NEAR (los ciudadanos que están cerca del jugador) y con estrategia ON_INTERVAL, que reparte el
## trabajo entre fotogramas en vez de planificar cada frame.

# Propiedades de la pizarra (nombres en castellano, como el resto del proyecto).
const PROP_TIRED := "cansancio"
const PROP_PLAYER_NEAR := "jugador_cerca"
const PROP_WANDERING := "paseando"
const PROP_RESTING := "descansando"
const PROP_SEEKING := "buscando_jugador"
const PROP_CAN_SEEK := "puede_curiosear"

## Distancia a la que un ciudadano se considera "cerca del jugador".
const PLAYER_NEAR_DISTANCE := 14.0
## Distancia a la que deja de acercarse cuando va a curiosear.
const STOP_DISTANCE := 2.6
## Metros de caminata que hacen falta para estar "cansado del todo".
const TIRED_DISTANCE := 55.0
## Cada cuánto se replantea sus objetivos.
const PLANNING_INTERVAL := 1.5


## Monta el cerebro para un ciudadano concreto. Llamar ANTES de añadirlo al árbol.
func setup(citizen: NPCCitizen) -> void:
	entity = citizen
	name = "GoapBrain"
	var agent_config := GdPAIAgentConfig.new()
	agent_config.planning_strategy = GdPAIAgentConfig.PlanningStrategy.ON_INTERVAL
	agent_config.planning_interval = PLANNING_INTERVAL
	agent_config.max_recursion = 3
	agent_config.use_multithreading = false
	var plan := GdPAIBlackboardPlan.new()
	plan.blackboard_backend = {
		PROP_TIRED: 0.0,
		PROP_PLAYER_NEAR: false,
		PROP_WANDERING: false,
		PROP_RESTING: true,
		PROP_SEEKING: false,
		PROP_CAN_SEEK: false,
	}
	agent_config.blackboard_plan = plan
	agent_config.behavior_configs = [NPCGoapBehavior.new()]
	config = agent_config


## El addon serializa el estado de cada agente para su depurador de editor; en el juego no hace
## falta y cuesta, así que se deja vacío.
func _update_debugger_info() -> void:
	pass


## Objetivo alcanzado cuando el ciudadano está paseando.
class GoalWander extends Goal:
	func compute_reward(_agent: GdPAIAgent) -> float:
		return 1.2

	func get_desired_state(_agent: GdPAIAgent) -> Array[Precondition]:
		return [Precondition.agent_property_equal_to(NPCGoapBrain.PROP_WANDERING, true)]

	func get_title() -> String:
		return "Pasear"

	func get_description() -> String:
		return "Da un paseo hasta un destino nuevo."


## Objetivo de descansar: cuanto más cansado, más apetece.
class GoalRest extends Goal:
	func compute_reward(agent: GdPAIAgent) -> float:
		var tired := float(agent.blackboard.get_property(NPCGoapBrain.PROP_TIRED, 0.0))
		return 0.5 + tired

	func get_desired_state(_agent: GdPAIAgent) -> Array[Precondition]:
		return [Precondition.agent_property_equal_to(NPCGoapBrain.PROP_RESTING, true)]

	func get_title() -> String:
		return "Descansar"

	func get_description() -> String:
		return "Parado un rato hasta recuperarse."


## Objetivo de acercarse a mirar al jugador.
class GoalSeekPlayer extends Goal:
	func compute_reward(agent: GdPAIAgent) -> float:
		if not bool(agent.blackboard.get_property(NPCGoapBrain.PROP_CAN_SEEK, false)):
			return -1.0
		return 2.0

	func get_desired_state(_agent: GdPAIAgent) -> Array[Precondition]:
		return [Precondition.agent_property_equal_to(NPCGoapBrain.PROP_SEEKING, true)]

	func get_title() -> String:
		return "Curiosear"

	func get_description() -> String:
		return "Se acerca al jugador a mirarlo."


## Acción de pasear: elige un destino válido y anda hasta él.
class ActionWander extends Action:
	func get_preconditions() -> Array[Precondition]:
		return [Precondition.agent_property_equal_to(NPCGoapBrain.PROP_WANDERING, false)]

	func get_action_cost(_agent_blackboard: GdPAIBlackboard, _world_state: GdPAIBlackboard) -> float:
		return 1.0

	func simulate_effect(agent_blackboard: GdPAIBlackboard, _world_state: GdPAIBlackboard) -> void:
		agent_blackboard.set_property(NPCGoapBrain.PROP_WANDERING, true)
		agent_blackboard.set_property(NPCGoapBrain.PROP_RESTING, false)
		agent_blackboard.set_property(NPCGoapBrain.PROP_SEEKING, false)

	func perform_action(agent: GdPAIAgent, _delta: float) -> Status:
		var citizen := agent.entity as NPCCitizen
		if citizen == null:
			return Status.FAILURE
		# Primera llamada: se le ordena pasear. Después sólo se espera a que llegue.
		if not citizen.goap_is_walking():
			if not citizen.wander_to_new_destination():
				return Status.FAILURE
			return Status.RUNNING
		return Status.SUCCESS if not citizen.goap_is_walking() else Status.RUNNING

	func get_title() -> String:
		return "Andar"

	func get_description() -> String:
		return "Camina hasta un destino nuevo."


## Acción de descansar: parado un rato.
class ActionRest extends Action:
	func get_preconditions() -> Array[Precondition]:
		return [Precondition.agent_property_equal_to(NPCGoapBrain.PROP_RESTING, false)]

	func get_action_cost(_agent_blackboard: GdPAIBlackboard, _world_state: GdPAIBlackboard) -> float:
		return 0.5

	func simulate_effect(agent_blackboard: GdPAIBlackboard, _world_state: GdPAIBlackboard) -> void:
		agent_blackboard.set_property(NPCGoapBrain.PROP_RESTING, true)
		agent_blackboard.set_property(NPCGoapBrain.PROP_WANDERING, false)
		agent_blackboard.set_property(NPCGoapBrain.PROP_SEEKING, false)
		agent_blackboard.set_property(NPCGoapBrain.PROP_TIRED, 0.0)

	func perform_action(agent: GdPAIAgent, _delta: float) -> Status:
		var citizen := agent.entity as NPCCitizen
		if citizen == null:
			return Status.FAILURE
		if citizen.goap_is_resting():
			return Status.SUCCESS
		citizen.rest_for(randf_range(2.5, 5.0))
		return Status.RUNNING

	func get_title() -> String:
		return "Descansar"

	func get_description() -> String:
		return "Se queda quieto un rato."


## Acción de curiosear: se acerca al jugador y lo mira (la mirada y las reacciones las sigue
## llevando el propio ciudadano; aquí sólo se le pide que se acerque).
class ActionSeekPlayer extends Action:
	func get_preconditions() -> Array[Precondition]:
		return [
			Precondition.agent_property_equal_to(NPCGoapBrain.PROP_SEEKING, false),
			Precondition.agent_property_equal_to(NPCGoapBrain.PROP_CAN_SEEK, true),
		]

	func get_action_cost(agent_blackboard: GdPAIBlackboard, _world_state: GdPAIBlackboard) -> float:
		# Cuanto más lejos esté el jugador, más cuesta ir a mirarlo.
		return 0.8 + float(agent_blackboard.get_property(NPCGoapBrain.PROP_PLAYER_NEAR, false)) * 0.0

	func simulate_effect(agent_blackboard: GdPAIBlackboard, _world_state: GdPAIBlackboard) -> void:
		agent_blackboard.set_property(NPCGoapBrain.PROP_SEEKING, true)
		agent_blackboard.set_property(NPCGoapBrain.PROP_WANDERING, false)
		agent_blackboard.set_property(NPCGoapBrain.PROP_RESTING, false)

	func perform_action(agent: GdPAIAgent, _delta: float) -> Status:
		var citizen := agent.entity as NPCCitizen
		if citizen == null:
			return Status.FAILURE
		if citizen.goap_is_walking():
			return Status.RUNNING
		if citizen.goap_is_seeking():
			return Status.SUCCESS
		if not citizen.approach_player(NPCGoapBrain.STOP_DISTANCE):
			# Ya estaba cerca: se da por hecho y se queda mirando desde donde está.
			return Status.SUCCESS
		return Status.RUNNING

	func get_title() -> String:
		return "Acercarse al jugador"

	func get_description() -> String:
		return "Camina hacia el jugador para mirarlo."


## Configuración de comportamiento: enlaza los objetivos y acciones de arriba, y mantiene la
## pizarra al día con lo que le pasa al ciudadano (cansancio, distancia al jugador...).
class NPCGoapBehavior extends GdPAIBehaviorConfig:
	func _self_init() -> void:
		super()
		goals = [GoalWander.new(), GoalRest.new(), GoalSeekPlayer.new()]
		self_actions = [ActionWander.new(), ActionRest.new(), ActionSeekPlayer.new()]
		property_updaters = [CitizenUpdater.new()]


## Vuelca el estado real del ciudadano en su pizarra.
class CitizenUpdater extends PropertyUpdater:
	var _travelled := 0.0
	var _last_position := Vector3.ZERO

	func initialize(agent: GdPAIAgent) -> void:
		var citizen := agent.entity as NPCCitizen
		if citizen != null:
			_last_position = citizen.global_position

	func update_properties(agent: GdPAIAgent, _delta: float) -> void:
		var citizen := agent.entity as NPCCitizen
		if citizen == null:
			return
		var position := citizen.global_position
		if citizen.goap_is_walking():
			_travelled += position.distance_to(_last_position)
		_last_position = position
		agent.blackboard.set_property(
			NPCGoapBrain.PROP_TIRED,
			clampf(_travelled / NPCGoapBrain.TIRED_DISTANCE, 0.0, 1.0)
		)
		agent.blackboard.set_property(NPCGoapBrain.PROP_CAN_SEEK, citizen.goap_can_seek())
		if not citizen.has_player():
			agent.blackboard.set_property(NPCGoapBrain.PROP_PLAYER_NEAR, false)
			return
		var distance := position.distance_to(citizen.player_position())
		agent.blackboard.set_property(
			NPCGoapBrain.PROP_PLAYER_NEAR,
			distance <= NPCGoapBrain.PLAYER_NEAR_DISTANCE
		)