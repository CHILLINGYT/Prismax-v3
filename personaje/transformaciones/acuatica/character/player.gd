class_name Player
extends CharacterBody3D
## =============================================================================
##  JUGADOR 3D (logica de movimiento + estado)
## =============================================================================
##  Este script NO sabe nada del modelo visual: solo mueve el CharacterBody3D,
##  decide el estado y se lo pide al PlayerAnimationController. Por eso puedes
##  cambiar el personaje por otro sin tocar este archivo.
##
##  Estructura de la escena:
##      Player (CharacterBody3D, este script)
##      ├── CollisionShape3D        capsula de colision (se acorta al agacharse)
##      ├── Visual (CharacterModel) SLOT del modelo visual (reemplazable)
##      ├── AnimationPlayer         clips generados desde los dos packs
##      ├── AnimationTree           maquina de estados con crossfades
##      ├── AnimationController     puente entre estado del jugador y animacion
##      └── CameraPivot (PlayerCameraRig) -> SpringArm3D -> Camera3D
##
##  CONTROLES
##      WASD        moverse (relativo a la camara)
##      Raton       girar la camara (solo la camara)
##      Espacio     saltar
##      Shift       en tierra: correr; si lo mantienes, CORRE MÁS RÁPIDO (mismo
##                  clip de correr, acelerado: no hay segunda animación de carrera).
##                  en el agua: NADO RÁPIDO (misma brazada, acelerada).
##      Ctrl o C    agacharse
##      Clic izq.   atacar (nunca automatico). Si vuelves a hacer clic mientras
##                  estas golpeando, el COMBO encadena el siguiente golpe en vez
##                  de reiniciar el primero a mitad.
##      Q           esquivar (voltereta en la direccion en la que te mueves)
##      F (mantener) apuntar con el balon de agua: PREPARAR -> FORMAR -> APUNTAR.
##                  Aparece una reticula en el centro; el raton gira el cuerpo y
##                  se selecciona/marca al enemigo apuntado. Las habilidades
##                  (1-4) salen del balon hacia donde apunta la reticula.
##      H / G / J / U / K / L   (pruebas) golpe leve / lateral / fuerte /
##                              cabeza / derribo / muerte
##
##  EN EL AGUA (ver la seccion "Agua" mas abajo)
##      WASD        nadar (relativo a la camara)
##      Espacio     subir a la superficie
##      Ctrl        hundirse
##      E           caminar SOBRE la superficie del agua (alterna; antes era F)
##      Todo lo demas (salto, agacharse, ataque, esquiva) se desactiva solo: en el
##      agua el personaje no hace pie, asi que no tiene sentido.
##    Con el agua por debajo de la cintura NO se nada: se vadea, mas despacio y
##    con los pies en el fondo.
##
##  HABILIDADES DE AGUA (teclas 1, 2, 3 y 4)
##      1   Proyectil de agua    enfria 1 s   bola rapida; revienta al chocar
##      2   Esfera de agua       enfria 3 s   explota y deja una zona que dura
##      3   Prision de agua      enfria 5 s   encierra al objetivo unos segundos
##      4   Oleada de agua       enfria 8 s   muro que arrolla: la mas fuerte
##    Funcionan EN TIERRA Y EN EL AGUA. Y el efecto no sale al pulsar la tecla:
##    sale cuando lo pide la animacion (pista de metodo del AnimationTree), o sea
##    justo en el fotograma en el que el personaje termina de cargar el hechizo.
##    Ver water_ability_manager.gd.
##
##  SEPARACION DE CONTROLES (importante):
##    * WASD mueve el CharacterBody3D. NO mueve ni gira la camara: el nodo
##      CameraPivot es "top_level", asi que no hereda el giro del personaje.
##    * El raton rota SOLO la camara (PlayerCameraRig).
##    * El personaje se desplaza segun la orientacion de la camara y gira
##      suavemente hacia su direccion de movimiento.
##
##  COMO SE ELIGE EL ESTADO DE LOCOMOCION
##    No se elige por la tecla pulsada, sino por la VELOCIDAD REAL: segun sube o
##    baja, el personaje pasa por idle -> walk -> run (y al reves). Mantener Shift
##    NO cambia de animacion: corre MAS RAPIDO sobre el mismo clip de correr.
##    Como la velocidad cambia con aceleracion y frenado, la progresion es
##    continua y no hay saltos. Ademas, cada clip se reproduce a
##    velocidad_real / velocidad_natural_del_clip, asi que los pies no patinan a
##    ninguna velocidad intermedia.
##
##  CADENA DE DAÑO (sin recuperacion instantanea)
##    Golpe leve/cabeza/fuerte -> recovery (queda aturdido un momento) -> moverse
##    Golpe -> stagger -> knockdown -> ground (en el suelo) -> get_up -> moverse
##    Cualquier cosa -> death (estado final)
## =============================================================================

## Se emite cada vez que el personaje cambia de estado.
signal state_changed(state: StringName)

## Se emite cuando el cuerpo entra o sale del agua con fuerza. [param strength] es
## la velocidad del golpe (m/s): sirve para escalar la salpicadura (tirarse desde
## lo alto tiene que notarse mucho más que meter un pie).
signal water_splash(position: Vector3, strength: float)

const STATE_IDLE := &"idle"
const STATE_WALK := &"walk"
const STATE_RUN := &"run"
## OJO: NO hay estado "sprint". Esprintar es IR MAS RAPIDO con el MISMO clip de
## correr (ver sprint_speed / is_sprinting): el factor de velocidad de
## reproduccion lo acelera solo. Antes habia un clip de sprint aparte y al
## mantener Shift se veian DOS animaciones de carrera consecutivas (recorrer
## medio ciclo de correr y saltar a otra), que es justo lo que no se quiere.
const STATE_WALK_BACK := &"walk_back"
## Apuntando con el agua en la mano (modo F) y parado: en vez del reposo normal,
## el personaje SOSTIENE el balón y apunta. Con el clip de reposo el brazo cuelga y
## el agua se iría con él a la cadera.
const STATE_AIM_HOLD := &"aim_hold"

## --- Locomocion CON LA BOLA EN LA MANO (modo Water Aim) -----------------------
## Los clips que EXISTEN en el pack de ataques para desplazarse sin soltar el
## agua. Cada nombre dice su direccion. Los que faltan (caminar hacia adelante,
## caminar hacia la izquierda, correr hacia la derecha) se resuelven con el
## FALLBACK declarado en _aim_locomotion_state(): no se inventa ningun clip.
const AIM_WALK_BACK := &"aim_walk_back"
const AIM_WALK_FORWARD := &"aim_walk_forward"
const AIM_WALK_RIGHT := &"aim_walk_right"
const AIM_RUN_FORWARD := &"aim_run_forward"
const AIM_RUN_BACK := &"aim_run_back"
const AIM_RUN_LEFT := &"aim_run_left"
const AIM_RUN_RIGHT := &"aim_run_right"
const AIM_CROUCH_FORWARD := &"aim_crouch_forward"
const AIM_CROUCH_BACK := &"aim_crouch_back"

const STATE_CROUCH_IDLE := &"crouch_idle"
const STATE_CROUCH_WALK := &"crouch_walk"
const STATE_JUMP := &"jump"
const STATE_FALL := &"fall"
const STATE_LANDING := &"landing"
const STATE_ATTACK := &"attack"
## Segundo golpe del combo (ver request_attack).
const STATE_ATTACK_2 := &"attack_2"
const STATE_DODGE := &"dodge"
const STATE_RECOVERY := &"recovery"
const STATE_HIT_LIGHT := &"hit_light"
const STATE_HIT_HEAD := &"hit_head"
const STATE_HIT_SIDE := &"hit_side"
const STATE_HIT_HEAVY := &"hit_heavy"
const STATE_STAGGER := &"stagger"
const STATE_KNOCKDOWN := &"knockdown"
const STATE_GROUND := &"ground"
const STATE_GET_UP := &"get_up"
const STATE_DEATH := &"death"

## --- Estados del sistema acuático ------------------------------------------
## Natación. Se eligen por el movimiento REAL del cuerpo (igual que la
## locomoción de tierra), no por la tecla pulsada.
const STATE_SWIM_IDLE := &"swim_idle"
const STATE_SWIM_FORWARD := &"swim_forward"
const STATE_SWIM_BACK := &"swim_back"
const STATE_SWIM_UP := &"swim_up"
const STATE_SWIM_DOWN := &"swim_down"
## Transiciones de entrada/salida del agua: evitan el salto brusco de "andar" a
## "nadar" (y al revés).
const STATE_ENTER_WATER := &"enter_water"
const STATE_EXIT_WATER := &"exit_water"

## Las cuatro habilidades acuaticas. El nombre coincide con el estado de animacion
## que genera tools/pack_animation_builder.gd, que es el que lleva la pista de
## metodo que avisa cuando hay que soltar el efecto.
const STATE_ABILITY_1 := &"ability_1"
const STATE_ABILITY_2 := &"ability_2"
const STATE_ABILITY_3 := &"ability_3"
const STATE_ABILITY_4 := &"ability_4"
const ABILITY_STATES: Array[StringName] = [
	STATE_ABILITY_1, STATE_ABILITY_2, STATE_ABILITY_3, STATE_ABILITY_4,
]

## Estados en los que el personaje nada de verdad (sin contar las transiciones).
const SWIM_STATES: Array[StringName] = [
	STATE_SWIM_IDLE, STATE_SWIM_FORWARD, STATE_SWIM_BACK, STATE_SWIM_UP,
	STATE_SWIM_DOWN,
]
## Todos los estados de agua: en ellos manda la física del agua (sin gravedad y
## sin aterrizajes).
const WATER_STATES: Array[StringName] = [
	STATE_SWIM_IDLE, STATE_SWIM_FORWARD, STATE_SWIM_BACK, STATE_SWIM_UP,
	STATE_SWIM_DOWN, STATE_ENTER_WATER, STATE_EXIT_WATER,
]

## Tipos de daño que se le pueden pedir al personaje con request_damage().
const DAMAGE_LIGHT := &"light"
const DAMAGE_HEAD := &"head"
const DAMAGE_SIDE := &"side"
const DAMAGE_HEAVY := &"heavy"
const DAMAGE_STAGGER := &"stagger"
const DAMAGE_KNOCKDOWN := &"knockdown"
const DAMAGE_DEATH := &"death"

## Estados en los que el personaje esta de pie y controla sus pies: son los
## unicos en los que se corrige la altura para clavar el pie en el suelo.
const FOOT_LOCK_STATES: Array[StringName] = [
	STATE_IDLE, STATE_WALK, STATE_RUN, STATE_WALK_BACK,
	STATE_CROUCH_IDLE, STATE_CROUCH_WALK,
	STATE_AIM_HOLD,
]

## Script del gestor de habilidades. Se preloadea para poder usarlo como TIPO en
## el export de abajo sin depender de que el class_name este en la cache del
## editor (una carpeta recien creada tarda un reescaneo en registrarse).
const AbilityManagerScript := preload("res://personaje/transformaciones/acuatica/abilities/water_ability_manager.gd")

## Balón de agua que el personaje junta en las manos al apuntar (misma agua que la
## carga de las habilidades: crece, sigue las manos y se suelta con un estallido).
const ChargeBallScript := preload("res://personaje/transformaciones/acuatica/vfx/water_charge.gd")

@export_group("Referencias")
@export var model: CharacterModel
@export var animation_controller: PlayerAnimationController
@export var camera_rig: PlayerCameraRig

@export_group("Apuntado con balón de agua")
## Cuánto (s) tarda la PREPARACIÓN: el personaje sube las manos y empieza a
## juntar agua (la retícula todavía no sale).
@export var aim_prepare_time := 0.45
## Cuánto (s) tarda la FORMACIÓN: el balón crece entre las manos hasta estar
## completo. Al acabar empieza el apuntado propiamente dicho.
@export var aim_form_time := 0.55
## Radio (m) del balón ya formado entre las manos.
## Radio (m) de la bola de agua que el personaje sostiene en la mano. Tiene que
## caber EN LA MANO: con 0.42 la esfera medía 84 cm de diámetro y atravesaba el
## pecho y el brazo, así que parecía una esfera pegada al cuerpo y no algo que se
## sostiene. Con 0.18 (36 cm) se ve bien y no toca el torso.
@export var aim_ball_radius := 0.18
## Grados por segundo máximos al girar el cuerpo hacia donde apunta el ratón.
@export var aim_turn_rate := 720.0
## Suavizado del giro al apuntar (1/s).
@export var aim_turn_smoothing := 16.0
## Alcance (m) para seleccionar un objetivo con la retícula.
@export var aim_range := 45.0
## Coseno mínimo del ángulo entre la mirada y el objetivo para seleccionarlo
## (0.9 ≈ 25°). Cuanto más alto, más hay que apuntar de cerca.
@export var aim_target_cone := 0.9

## A partir de qué componente del input (en el sistema local del personaje) se
## considera que se anda HACIA ATRÁS. 0.35 = unos 20° fuera del eje lateral.
@export var aim_back_threshold := 0.35
## A partir de qué componente lateral del input se considera que se anda DE LADO
## (a derecha o a izquierda). 0.45 = unos 27° fuera del eje de avance.
@export var aim_side_threshold := 0.45

## Cuánto se frena la locomoción (andar/correr y nadar) mientras se lleva el balón
## de agua en las manos. La velocidad de tierra se multiplica por esto para que
## cargar el hechizo no sea gratis.
##
## 0.8 y NO menos: los clips de desplazamiento con la bola (aim_walk_*,
## aim_run_*) son de andar/correr normal, así que con una frenada mayor el clip se
## reproducía a la mitad de su velocidad natural y los pasos se veían
## ARRASTRADOS (a cámara lenta). Con 0.8 el paso sigue clavado en el suelo y el
## personaje va claramente más lento que sin la bola, que es lo que se busca.
@export var aim_move_factor := 0.8

## Hueso de la mano que SOSTIENE el agua (el balón de apuntado y las cargas de los
## hechizos). Se busca por nombre en el esqueleto del modelo.
@export var water_hand := &"RightHand"
## Desplazamiento (m) del agua desde la muñeca, EN EL ESPACIO DEL HUESO de la mano
## (no del mundo): es lo que la lleva un poco hacia la palma y hace que acompañe al
## brazo mire donde mire el personaje. Al ir en el sistema local del hueso vale con
## cualquier rig, al contrario que una posición puesta "a mano" en el mundo.
@export var water_hand_offset := Vector3(0.0, 0.03, 0.0)

@export_group("Movimiento")
## Velocidad al caminar (m/s). Es la velocidad REAL del CharacterBody3D.
## Los valores por defecto estan puestos para que coincidan con la velocidad
## natural de cada clip (ver clip_speeds), asi que se reproducen a ~1:1.
@export var walk_speed := 1.3
## Velocidad al correr (m/s). Shift mantenido. Subida en la etapa de pulido: el
## personaje acuatico es agil en tierra y la carrera tiene que notarse claramente
## por encima del paseo.
@export var run_speed := 3.4
## Velocidad al esprintar (m/s). Se alcanza tras mantener Shift sprint_delay
## segundos, asi que la progresion caminar -> correr -> esprintar es continua.
@export var sprint_speed := 4.5
## Velocidad al moverse agachado (m/s).
@export var crouch_speed := 0.9
## Cuanto hay que mantener Shift para pasar de correr a esprintar. Corto, para
## que el esprint entre enseguida: antes habia que aguantar Shift mas de un
## segundo y el personaje se quedaba "pesado" en velocidad de correr.
@export var sprint_delay := 0.6
## Velocidad (m/s) a la que cada clip de locomocion queda "clavado" en el suelo.
## Son las velocidades MEDIDAS en los clips (tools/pack_animation_builder.gd las
## imprime). Con esto el personaje reproduce el clip a velocidad_real / esta, y
## los pies no patinan ni a velocidad intermedia. Si cambias un clip, actualiza
## su valor aqui.
@export var clip_speeds: Dictionary = {
	# Locomocion ACTUALIZADA (etapa de pulido): velocidades MEDIDAS de los clips
	# nuevos al hornearlos (Mutant Walking y Running). Con estos valores el
	# personaje reproduce cada clip a velocidad_real / esto, asi que los pies no
	# patinan. Si vuelves a cambiar un clip, remide y actualiza aqui.
	"walk": 1.01,
	"run": 2.62,
	"walk_back": 0.67,
	"crouch_walk": 0.52,
	# Locomoción CON LA BOLA EN LA MANO (modo F). Son las velocidades MEDIDAS al
	# hornear los clips del pack de ataques. OJO con los LATERALES: el medidor mide
	# el desplazamiento del pie sobre el eje de AVANCE del clip, y un paso lateral
	# no avanza por ahí (aim_walk_right salía 0.10 m/s y aim_run_left 0.35, que no
	# sirven). Para esos dos se usa la velocidad del clip del mismo pack, mismo
	# paso y misma duración que va en la misma dirección real de marcha: es el
	# stride que de verdad recorre la pierna. Si vuelves a cambiar un clip,
	# remide y actualiza aquí.
	"aim_walk_back": 1.40,
	"aim_walk_forward": 1.24,
	"aim_walk_right": 1.40,
	"aim_run_forward": 2.54,
	"aim_run_back": 2.08,
	"aim_run_left": 2.08,
	"aim_run_right": 2.08,
	"aim_crouch_forward": 1.27,
	"aim_crouch_back": 1.39,
	# Natación: misma idea. swim_forward es "Swimming" (0.47 m/s medidos) y
	# swim_back es ese mismo clip al revés. swim_idle (flotar quieto) no se toca:
	# no es locomoción, así que va a 1:1.
	"swim_forward": 0.47,
	"swim_back": 0.47,
	"swim_down": 0.47,
}
## Aceleracion al empezar a moverse (m/s²) y al frenar. La aceleracion sube en la
## etapa de pulido: recuperar velocidad tras un golpe o un cambio de direccion es
## parte de la agilidad del personaje.
@export var acceleration := 26.0
## Frenado de uso general (m/s²). Es el que usa el agua y el de caminar sobre la
## superficie: ahi SI interesa que el personaje se clave casi en seco.
@export var deceleration := 28.0
## Frenado EN TIERRA (m/s²), mas suave que el general a proposito. Al soltar los
## controles el personaje tiene que DECELERAR y acabar el paso que lleva
## empezado, no quedarse clavado. Con 28 m/s² un paseo a 1.8 m/s se paraba en
## 0.06 s (fotograma y medio): el clip de andar se quedaba a medias y el frenazo
## se veia. Con 9 m/s² el frenado dura ~0.2 s, el clip se va ralentizando solo
## (se reproduce a velocidad/ciclo) y el pie de apoyo llega al suelo antes de
## pasar a la postura de parado.
@export var land_deceleration := 9.0
## Aceleracion reducida en el aire (control aereo).
@export var air_acceleration := 7.0
## Velocidad maxima de giro del personaje (grados por segundo). Es lo que evita
## que un cambio de direccion de 90 o 180 grados se vea instantaneo.
@export var turn_rate := 720.0
## Suavizado del giro (1/s). Mas alto = alcanza antes la direccion pedida.
@export var turn_smoothing := 16.0
## Velocidad por debajo de la cual se considera que el personaje esta quieto.
@export var idle_speed_threshold := 0.25
## Diferencia (m/s) que hay que cruzar para cambiar de estado de locomocion. Evita
## que el estado parpadee cuando la velocidad esta justo en el limite.
@export var locomotion_hysteresis := 0.15
## false = Shift mantenido para correr. true = Shift alterna caminar/correr.
@export var run_toggle_mode := false

@export_group("Salto y gravedad")
@export var gravity := 22.0
## Altura aproximada del salto en metros.
@export var jump_height := 1.15
@export var max_fall_speed := 35.0
## Margen para saltar justo despues de dejar el suelo.
@export var coyote_time := 0.12
## Margen para que un salto pulsado antes de tocar suelo no se pierda.
@export var jump_buffer_time := 0.15
## Tiempo minimo en el aire para que al aterrizar suene el estado "landing".
@export var min_air_time_for_landing := 0.12
## Duracion de "landing" si no se encuentra ese clip.
@export var fallback_landing_duration := 0.3
## Tiempo minimo (s) que se ve la animacion de aterrizaje antes de poder cortarla
## con el movimiento. Lo justo para que el golpe del pie se lea, pero sin obligar
## a esperar a que acabe el clip entero.
@export var landing_min_time := 0.25

@export_group("Agua")
## Detección de agua montada en el jugador (el Area3D hijo "WaterDetection").
## Si falta, el sistema acuático simplemente no se activa.
@export var water_detection: WaterDetection
## Velocidad de nado hacia delante (m/s). Más lenta que andar: nadar cuesta.
@export var swim_speed := 2.1
## Velocidad nadando hacia atrás (m/s).
@export var swim_back_speed := 1.0
## Multiplicador de velocidad al NADAR RÁPIDO (mantener Shift). No hay clip nuevo
## de nado rápido: se reusa el mismo de brazada, que se acelera SOLO, porque la
## velocidad de reproducción sigue siendo velocidad_real / velocidad_del_clip
## (ver _update_animation_speed). Así el gesto acompaña al aumento de velocidad.
@export var swim_sprint_factor := 2.2
## Velocidad de subida con ESPACIO (m/s).
@export var swim_vertical_speed := 1.3
## Velocidad de bajada con CTRL (m/s).
@export var dive_speed := 1.8
## Aceleración dentro del agua (m/s²). Baja a propósito: en el agua no se arranca
## en seco, y eso ya es media sensación de estar nadando.
@export var swim_acceleration := 4.0
## Frenado por resistencia del agua (m/s²) al soltar los controles. También bajo:
## es lo que hace que el personaje SIGA avanzando un poco después de dejar de
## nadar (inercia) en vez de quedarse clavado como en tierra.
@export var swim_deceleration := 1.4
## Empuje de flotación (m/s²): devuelve el cuerpo a su profundidad de flotación.
@export var buoyancy_accel := 5.0
## Amortiguación de la flotación (1/s). Sin ella el cuerpo rebotaría arriba y
## abajo como un corcho; con ella se acomoda y se queda.
@export var buoyancy_damping := 4.2
## Margen (m) por encima de la profundidad de flotación al que el cuerpo todavía
## puede subir. Es el "techo" del agua: nadando hacia arriba el personaje se para
## ahí en vez de salir disparado.
@export var swim_surface_margin := 0.1
## Fracción de la velocidad de nado que se conserva durante las transiciones de
## entrada/salida del agua, para no quedarse parado a mitad de camino.
@export var water_transition_speed_factor := 0.6
## Duración (s) de las transiciones de agua si no se encuentran sus clips.
@export var fallback_water_transition_time := 1.2
## Tiempo (s) MÍNIMO que se reproduce la animación de SALIR del agua antes de
## devolver el control a la locomoción terrestre. El clip de salida dura casi 2 s
## (incluye el tramo en el que el personaje ya está de pie en la orilla), así que
## sin este corte se quedaba "trabada" reproduciendo el final del clip acuático
## una vez fuera. En cuanto el personaje hace pie en tierra y ya no está mojado,
## pasados estos segundos recupera de inmediato walk / run / idle.
@export var exit_water_cut_time := 0.5
## Velocidad (m/s) por debajo de la cual el personaje "flota quieto" (swim_idle).
@export var swim_idle_threshold := 0.25
## Histéresis (m) del umbral de nado: una vez nadando hace falta bajar de
## swim_depth - esto para volver a andar. Evita que el estado parpadee justo en
## el borde del agua.
@export var swim_depth_margin := 0.07
## Profundidad (m) de agua necesaria para ponerse a NADAR. Con 0.77 m (más o
## menos la cintura) el personaje anda por el fondo en aguas someras y solo se
## pone a nadar cuando no hace pie. Es lo que pide el punto de "no nadar estando
## en el suelo".
@export var swim_depth := 0.77
## Profundidad (m) a la que queda el ORIGEN del personaje (los pies) al flotar,
## según el estado. NO es la misma al nadar tumbado que al flotar vertical,
## porque las dos posturas colocan el cuerpo a distinta altura respecto al
## origen: con esto el agua le pasa al cuerpo por el mismo sitio en las dos.
@export var float_depths: Dictionary = {
	"swim_idle": 1.30,
	"swim_up": 1.30,
	"swim_forward": 0.80,
	"swim_back": 0.80,
	"swim_down": 0.80,
	"enter_water": 1.20,
	"exit_water": 1.20,
}
## Profundidad de flotación si el estado no está en float_depths.
@export var float_depth_default := 1.0
## Fracción de la velocidad de tierra que se conserva al VADEAR (agua por debajo
## de la cintura). El agua frena, pero se sigue andando por el fondo.
@export var wade_speed_factor := 0.55

## Velocidad (m/s) de la brazada cuando se nada por DEBAJO de la superficie: bajo
## el agua el personaje va algo mas suelto que en la superficie, donde pelea con
## las olas y con la propia flotabilidad.
@export var swim_speed_underwater := 2.6
## Margen (m) de profundidad SOBRE la altura de flotacion a partir del cual el
## personaje cuenta como SUMERGIDO. Es el paso NADAR EN SUPERFICIE -> NADAR
## SUMERGIDO. Ojo: no se mide por la cabeza, sino por cuanto se ha hundido el
## cuerpo respecto de donde flota, porque nadando tumbado la cabeza va a la misma
## altura que los pies y "cabeza fuera" dejaria de significar nada.
@export var submerge_margin := 0.45
## Histeresis (m) para volver de SUMERGIDO a SUPERFICIE: sin ella, con el cuerpo
## justo en el limite el modo parpadearia cada fotograma.
@export var surface_margin_hysteresis := 0.2
## Profundidad maxima (m) a la que el muelle de flotabilidad neutra puede dejar
## clavado el cuerpo: asi no empuja al personaje contra el fondo.
@export var max_hold_depth := 3.2
## Balanceo vertical (m) y velocidad del mismo cuando el personaje se queda
## flotando sin ordenes. Bajo el agua el cuerpo NO se queda quieto del todo.
@export var neutral_bob_amplitude := 0.05
@export var neutral_bob_speed := 1.2
## true: sumergido, el avance (W/S) sigue la MIRADA de la camara, asi que se puede
## nadar hacia arriba o hacia abajo mirando, y A/D van en horizontal. false: todo
## el movimiento bajo el agua es horizontal (solo ESPACIO y CTRL cambian altura).
@export var free_vertical_swim := true

## --- Caminar por el FONDO -----------------------------------------------
## El personaje hace pie en el fondo y anda como en tierra, con agua hasta
## arriba. Velocidades y estados son exportados a proposito: asi el dia que haya
## animaciones propias de "andar bajo el agua" solo hay que cambiarlos aqui.
@export var floor_walk_speed := 1.5
## Carrera SOBRE EL FONDO (Shift). El fondo es su medio: no esta limitado a
## arrastrarse por el, corre por el fondo como un buceador con lastre controlado.
@export var floor_run_speed := 2.6
@export var floor_acceleration := 14.0
@export var floor_deceleration := 8.0
## Gravedad reducida bajo el agua: empuja al cuerpo contra el fondo, pero mucho
## mas floja que en tierra. El agua NO es gravedad cero.
@export var floor_gravity := 12.0
@export var floor_walk_state: StringName = &"walk"
@export var floor_idle_state: StringName = &"idle"
## Columna de agua minima (m) para poder caminar por el fondo. Con menos agua ya
## se anda de pie normal (vadeando), y no tiene sentido hablar de "fondo".
@export var floor_min_depth := 1.4
## Impulso (m/s) al DESPEGARSE del fondo con ESPACIO.
@export var floor_detach_speed := 2.4
## Tiempo (s) sin tocar el fondo antes de dejar el modo FONDO. Evita que el modo
## parpadee al subir/bajar por una rampa del fondo.
@export var floor_leave_time := 0.18

## --- Salir del agua por el borde ----------------------------------------
## Altura maxima (m) de borde que se puede trepar, medida desde los pies.
@export var climb_height := 2.0
## Distancia (m) a la que se busca el borde por delante.
@export var climb_reach := 1.1
## Tiempo (s) que dura la subida. Se reproduce el clip de salir del agua.
@export var climb_time := 0.9
## Cuanto (m) se avanza por encima del borde al terminar, para no quedarse con
## medio cuerpo colgando.
@export var climb_land_offset := 0.35
## Tiempo (s) de espera entre dos trepadas (si falla, no se reintenta en bucle).
@export var climb_cooldown := 0.6

## --- Caminar SOBRE la superficie -----------------------------------------
## Rigidez (1/s) del muelle que sostiene al personaje sobre la superficie del
## agua: la posicion vertical la controla el sistema, no un suelo falso.
@export var surface_walk_stiffness := 6.0
## Rapidez (1/s) con la que la velocidad vertical del muelle alcanza su objetivo.
@export var surface_walk_damping := 22.0
## Altura (m) a la que se dejan los PIES por encima de la superficie del agua.
@export var surface_walk_offset := 0.02
## Velocidad vertical maxima (m/s) del muelle de superficie. Baja a proposito: con
## un tope alto el muelle sube al personaje de golpe y se pasa de largo por encima
## del agua antes de frenar.
@export var surface_walk_max_speed := 2.5
## Columna de agua minima (m) para poder caminar sobre ella.
@export var surface_walk_min_depth := 1.0

## --- Combate cuerpo a cuerpo ---------------------------------------------
## Alcance (m) y radio (m) del golpe cuerpo a cuerpo.
@export var melee_reach := 1.5
@export var melee_radius := 0.7
## Daño del golpe cuerpo a cuerpo y fraccion del clip en la que impacta.
@export var melee_damage := 6.0
@export var melee_impact_at := 0.45
## Angulo (grados) a cada lado de la mirada dentro del cual el golpe alcanza.
@export var melee_arc := 75.0

@export_group("Habilidades de agua")
## Gestor de las cuatro habilidades acuaticas: mira los enfriamientos y crea el
## efecto. Es un nodo hijo del jugador (Player/AbilityManager).
##
## Se declara con el preload del script en vez de con su class_name a proposito:
## un class_name recien creado no esta en la cache de clases del editor hasta que
## este reescanea la carpeta, y entonces el proyecto no compilaria.
@export var ability_manager: AbilityManagerScript

@export_group("Agacharse")
## Altura (m) de la capsula de colision agachado. De pie es la del CollisionShape.
@export var crouch_height := 0.95
## Tiempo (s) que tarda la capsula en pasar de una altura a otra.
@export var crouch_transition_time := 0.18
## Si esta activo, no se puede levantar cuando hay algo encima (techo).
@export var block_stand_up_under_ceiling := true

@export_group("Ataque, esquiva y reacciones")
## Estado de animacion del primer golpe del combo.
@export var attack_state: StringName = &"attack"
## Estado de animacion del segundo golpe del combo. Se van alternando: cruzado,
## jab, cruzado... Para anadir un tercer golpe basta con crear el clip, meterlo
## en el arbol y llamar a request_attack(&"punch_3").
@export var attack_state_2: StringName = &"attack_2"
## Multiplicador de velocidad mientras se ejecuta una accion (ataque/golpe).
## 0 = no se puede mover; 0.35 permite atacar andando. Es el valor de los golpes
## NORMALES del combo: el finalizador usa el suyo (finisher_move_multiplier).
@export var attack_move_multiplier := 0.35
@export_group("Combo cuerpo a cuerpo")
## Golpes que tiene el combo antes de reiniciarse: 1-2-3-4 alternando manos.
@export var combo_length := 4
## Desplazamiento del golpe FINAL del combo, mas largo que el de los normales: el
## cierre tiene que notarse en el cuerpo, no solo en el numero de danio.
@export var finisher_move_multiplier := 0.7
## Danio extra del golpe final: cierra el combo pegando mas fuerte.
@export var finisher_damage_multiplier := 1.5
## Velocidad de reproduccion del clip del finalizador. Los golpes normales van
## acelerados (attack_clip_speed) y el cierre va a la velocidad NATURAL del clip:
## se lee como un golpe mas pesado, con su recuperacion completa.
@export var finisher_clip_speed := 1.0
## Fraccion del golpe (0..1) a partir de la cual ya se puede encadenar el
## siguiente. Si el clic llega antes de ese punto se guarda en cola y sale solo
## en cuanto se abre la ventana: asi machacar el boton NO reinicia el golpe a
## mitad, lo encadena. Con 0.45 el segundo golpe entra justo tras el impacto.
@export var combo_window := 0.45
## Velocidad de reproduccion de los clips de golpe (1 = tal cual se hornearon).
## Los dos punyetazos son clips de captura completos, con entrada y recuperacion
## largas: reproducirlos tal cual hace que "clic -> golpe" se sienta lento. A 1.35
## el golpe sale con intencion y sigue pareciendo natural (no se acelera nada mas:
## la locomocion y las habilidades de agua mantienen su velocidad).
@export var attack_clip_speed := 1.35
## Velocidad (m/s) del impulso al esquivar. Va con el clip de voltereta: es un
## desplazamiento largo y rodado, no un tiron corto y seco.
@export var dodge_speed := 3.2
## Cuanto dura el impulso de la esquiva (s). Cubre el tramo de la voltereta en el
## que el personaje avanza rodando por el suelo.
@export var dodge_dash_time := 0.7
## Cuanto dura la accion de esquivar (s). 0 = el clip entero. Se recorta un poco
## para no quedarse esperando al ultimo tramo de la voltereta, que ya no avanza:
## la mezcla con la locomocion cierra ese trozo.
@export var dodge_duration := 1.1
## Multiplicador de velocidad durante una esquiva.
@export var dodge_move_multiplier := 1.0
## Empuje (m/s) que arrastra al personaje segun el tipo de golpe. Es el
## "knockback": un golpe fuerte te desplaza aunque no quieras. Se va frenando
## solo, con una desaceleracion igual a la de andar.
@export var knockback_speeds: Dictionary = {
	"light": 1.6,
	"head": 2.4,
	"side": 2.6,
	"heavy": 3.8,
	"stagger": 2.8,
	"knockdown": 4.4,
	"death": 3.2,
}
## Tiempo (s) que el personaje queda aturdido tras un golpe antes de recuperar el
## control. Es lo que evita la "recuperacion instantanea".
@export var recovery_time := 0.45
## Cuanto mas aturdido queda tras un tambaleo.
@export var stagger_recovery_time := 0.8
## Tiempo minimo (s) que el personaje se queda en el suelo antes de levantarse.
@export var ground_time := 1.2
## Si esta activo, hay que pulsar una tecla para levantarse del suelo.
@export var get_up_on_input := false
## Duracion por defecto de una accion si no se encuentra su clip.
@export var fallback_action_duration := 0.35

## true mientras el personaje corre.
var is_running := false
## true cuando el personaje corre MAS RAPIDO (Shift mantenido un rato). No cambia
## de clip: acelera el mismo clip de correr (ver clip_speeds).
var is_sprinting := false
## true mientras esta agachado.
var is_crouching := false
## true cuando ha muerto: no acepta mas ordenes.
var is_dead := false
## Velocidad horizontal actual (m/s).
var move_speed := 0.0

var _state: StringName = STATE_IDLE
var _input_direction := Vector3.ZERO
var _jump_buffer := 0.0
var _coyote_timer := 0.0
var _air_time := 0.0
var _landing_timer := 0.0
## Accion de un solo tiro en curso (ataque/esquiva/golpe) y su tiempo restante.
var _action_state: StringName = &""
var _action_timer := 0.0
## Duracion total de la accion en curso (para saber por que punto va).
var _action_duration := 0.0
## Cuantos golpes lleva el combo: sirve para ir alternando cruzado y jab.
var _combo_index := 0
## Paso del combo que se esta ejecutando (1..combo_length). 0 = golpe suelto del
## clic derecho, que NO forma parte del combo.
var _combo_step := 0
## true si el golpe en curso es el FINAL del combo (el golpe 4).
var _combo_finisher := false
## true si el jugador ha vuelto a hacer clic y el siguiente golpe esta en cola.
var _attack_queued := false
## Estado del golpe que quedo en cola (attack o attack_2), para respetar si el
## encadenado lo pidio el clic izquierdo o el derecho.
var _queued_attack_state: StringName = &""
## Cuanto lleva corriendo sin parar (para pasar a esprintar).
var _sprint_timer := 0.0
## Tiempo que le queda de aturdimiento tras un golpe.
var _stun_timer := 0.0
## Tiempo que lleva en el suelo.
var _ground_timer := 0.0
## Impulso de esquiva que queda (s).
var _dodge_timer := 0.0
## Direccion del impulso de esquiva.
var _dodge_direction := Vector3.ZERO
## Empuje que arrastra al personaje tras un golpe (m/s). Se frena solo.
var _knockback := Vector3.ZERO
## 0 = de pie, 1 = agachado. La capsula se interpola con esto.
var _crouch_amount := 0.0
var _shape: CollisionShape3D = null
var _standing_height := 0.0
var _standing_center_y := 0.0

## Modo FISICO del agua en el que esta el personaje. Va aparte del estado de
## animacion: el modo decide que fisica manda (gravedad, flotacion, muelle de
## superficie...) y el estado decide que animacion se ve. Varios modos comparten
## estados de tierra (FONDO y SUPERFICIE_ANDAR usan idle/walk/run de siempre).
enum WaterMode {
	NONE,          ## en tierra, seco
	WADING,        ## dentro del agua pero haciendo pie (agua somera)
	ENTERING,      ## entrando: mezcla progresiva de tierra y agua
	SURFACE,       ## nadando en la superficie
	SUBMERGED,     ## nadando por debajo de la superficie
	FLOOR,         ## caminando por el fondo de la piscina
	SURFACE_WALK,  ## caminando SOBRE la superficie del agua
	CLIMBING,      ## trepando para salir por el borde
}

## Fases del modo de apuntado con el balón de agua (tecla de apuntar MANTENIDA).
## Es una capa por encima de la locomoción, no un WaterMode: se puede apuntar de
## pie, andando, nadando o por el fondo, y la locomoción de debajo no cambia.
enum AimPhase {
	OFF,      ## sin apuntar
	PREPARE,  ## el personaje sube las manos y el agua empieza a juntarse
	FORM,     ## el balón se forma y crece entre las manos
	AIM,      ## balón completo: retícula, giro con el ratón y selección de objetivo
}

## true mientras nada de verdad (agua honda). Vadear agua poco profunda NO cuenta.
var _swimming := false
## true si tiene los pies mojados, aunque haga pie y ande por el fondo.
var _in_water := false
## Fracción (0..1) del cuerpo que queda bajo el agua.
var _submersion := 0.0
## -1 = hundiéndose, 0 = sin orden vertical, +1 = subiendo. Lo pone _update_swim y
## lo usa _swim_state para elegir la brazada.
var _swim_vertical := 0.0
## Transición de agua en curso (enter_water / exit_water) o &"".
var _water_transition: StringName = &""
var _water_transition_timer := 0.0
## Modo fisico del agua (ver WaterMode). Se decide en _update_water.
var water_mode: WaterMode = WaterMode.NONE
## Entrada CRUDA del mando (x = derecha, y = adelante). Se guarda aparte de
## _input_direction porque bajo el agua el avance tiene que seguir la MIRADA (con
## su inclinacion), y _input_direction es siempre horizontal.
var _input_raw := Vector2.ZERO
## Reloj propio del agua (s): lo usan el balanceo neutro y los efectos. Es propio
## para que el balanceo empiece en 0 cada vez que se entra al agua.
var _water_time := 0.0
## Profundidad (m) que se mantiene cuando NO se manda en la vertical estando
## sumergido: eso es el flotar neutro (conservar la profundidad al soltar CTRL).
var _hold_depth := -1.0
## true mientras la profundidad la fija _hold_depth (sumergido y sin ordenes).
var _holding_depth := false
## Balanceo neutro actual (m) que se suma al objetivo de profundidad.
var _float_bob := 0.0
## Tiempo (s) sin tocar el fondo: sirve para dejar el modo FONDO sin parpadeos.
var _floor_air_time := 0.0
## true si el jugador quiere caminar SOBRE el agua (se alterna con su tecla).
var _surface_walk_on := false
## --- Apuntado con balón de agua (ver AimPhase) ------------------------------
## true mientras se mantiene la tecla de apuntar.
var _aiming := false
## Fase actual del apuntado (ver AimPhase).
var _aim_phase: int = AimPhase.OFF
## Reloj (s) dentro de la fase actual.
var _aim_time := 0.0
## Agua que el personaje tiene junta en las manos (WaterCharge) o null.
var _aim_ball: Node3D = null
## Objetivo enganchado por la retícula ahora mismo (o null).
var _aim_target: Node3D = null
## Anillo 3D que marca el objetivo seleccionado.
var _aim_marker: MeshInstance3D = null
## Trepada en curso: de donde a donde, cronometro y enfriamiento.
var _climb_from := Vector3.ZERO
var _climb_to := Vector3.ZERO
var _climb_timer := 0.0
var _climb_total := 0.0
var _climb_cooldown := 0.0
## true si el golpe cuerpo a cuerpo de la accion en curso ya ha impactado.
var _melee_done := false
## Vista subacuatica (niebla, velo de pantalla y motas). Es la que decide si la
## CAMARA esta dentro del agua, que no es lo mismo que estar mojado.
var _underwater_view: Node = null


func _ready() -> void:
	# Grupo "player": sirve para que cualquier sistema (enemigos, pruebas) pueda
	# encontrar al jugador sin conocer su ruta en la escena.
	add_to_group(&"player")
	if model == null:
		model = get_node_or_null("Visual") as CharacterModel
	if animation_controller == null:
		animation_controller = get_node_or_null("AnimationController") as PlayerAnimationController
	if camera_rig == null:
		camera_rig = get_node_or_null("CameraPivot") as PlayerCameraRig
	if water_detection == null:
		water_detection = get_node_or_null("WaterDetection") as WaterDetection
	if _underwater_view == null:
		_underwater_view = get_node_or_null("UnderwaterView")
	if ability_manager == null:
		ability_manager = get_node_or_null("AbilityManager") as AbilityManagerScript
	_setup_collision()
	up_direction = Vector3.UP
	_enter_state(STATE_IDLE, true)


## Guarda la capsula original (de pie) para poder encogerla al agacharse sin
## perder la medida: al levantarse se vuelve exactamente a la de antes.
func _setup_collision() -> void:
	_shape = get_node_or_null("CollisionShape3D") as CollisionShape3D
	if _shape == null:
		return
	var capsule := _shape.shape as CapsuleShape3D
	if capsule == null:
		return
	# Copia propia de la capsula: si se modificara el recurso de la escena, el
	# cambio afectaria a TODAS las instancias de player.tscn (los sub-recursos de
	# una escena se comparten entre instancias).
	_shape.shape = capsule.duplicate()
	capsule = _shape.shape as CapsuleShape3D
	# La capsula de Godot mide "height" INCLUYENDO los dos hemisferios, y el
	# centro esta en el punto medio. Se guarda la medida de pie para poder volver
	# exactamente a ella al levantarse.
	_standing_height = capsule.height
	_standing_center_y = _shape.position.y


func _physics_process(delta: float) -> void:
	_read_input()
	_update_timers(delta)
	_update_water(delta)
	# La camara se "moja" cuando hay CAMARA dentro del agua, no cuando el personaje
	# esta mojado: mirando el lago desde la orilla la imagen tiene que ser normal.
	# La vista subacuatica ya lleva su propio suavizado; aqui solo se le pasa.
	if camera_rig != null:
		var cam_water := 1.0 if is_underwater() else 0.0
		if _underwater_view != null and is_instance_valid(_underwater_view):
			cam_water = float(_underwater_view.call("get_underwater_amount"))
		camera_rig.set_underwater(cam_water)
		# Y la camara se va al hombro mientras se apunta (modo F), con transicion
		# suave: la mezcla la lleva el propio rig.
		camera_rig.set_aiming(_aiming)
	# Las acciones de un solo tiro (ataque, esquiva, habilidad) van SIEMPRE, en
	# cualquier modo: si no, una habilidad lanzada nadando se quedaria encallada.
	_update_action(delta)
	_melee_tick()
	_update_aim(delta)
	# Agacharse solo tiene sentido con los pies en el suelo de tierra: en el agua
	# CTRL es "hundirse" y la capsula encogida falsearia la profundidad del cuerpo.
	if water_mode == WaterMode.NONE:
		_update_crouch(delta)
	# --- Fisica: manda el modo de agua ---
	match water_mode:
		WaterMode.ENTERING:
			_update_enter(delta)
		WaterMode.SURFACE, WaterMode.SUBMERGED:
			_update_swim(delta)
		WaterMode.FLOOR:
			_update_floor(delta)
		WaterMode.SURFACE_WALK:
			_update_surface_walk(delta)
		WaterMode.CLIMBING:
			_update_climb(delta)
		_:
			_apply_gravity(delta)
			var rate := acceleration if is_on_floor() else air_acceleration
			var brake := land_deceleration if is_on_floor() else air_acceleration
			_apply_horizontal_movement(delta, rate, brake)
			_try_jump()
	_look_toward_movement(delta)
	move_and_slide()
	_update_state(delta)
	_update_animation_speed()
	if animation_controller != null:
		# el "foot lock" solo actua cuando el personaje esta apoyado y controlando
		# sus pies: no en saltos, golpes, derribos ni flotando. Caminando por el
		# FONDO si: ahi si hay suelo de verdad donde clavar los pies.
		animation_controller.foot_lock_active = FOOT_LOCK_STATES.has(_state) \
			or (water_mode == WaterMode.FLOOR and not is_acting())


# -----------------------------------------------------------------------------
#  Agua
# -----------------------------------------------------------------------------
## Decide si el personaje está en tierra, vadeando o nadando, y avisa cuando entra
## o sale. Se llama al principio de _physics_process, antes que la física, para
## que el agua y el movimiento se lean en el mismo fotograma.
##
## REGLA DE ORO: nadar NO se activa por tocar agua, sino por PROFUNDIDAD. Con el
## agua por debajo de la cintura el personaje sigue andando por el fondo (vadea,
## más lento). Solo cuando no hace pie se pone a nadar. Así no se puede "nadar"
## en un charco ni estando de pie en el suelo.
func _update_water(delta: float) -> void:
	if water_detection != null:
		water_detection.refresh()
		_in_water = water_detection.is_in_water()
		_submersion = water_detection.get_submersion()
	else:
		_in_water = false
		_submersion = 0.0

	_water_time += delta
	_climb_cooldown = maxf(_climb_cooldown - delta, 0.0)
	if _water_transition_timer > 0.0:
		_water_transition_timer = maxf(_water_transition_timer - delta, 0.0)
		if _water_transition_timer <= 0.0:
			_water_transition = &""

	# Derribado, aturdido o muerto no se nada: el agua no resucita a nadie. El
	# cuerpo cae al fondo y alli se queda.
	if is_dead or is_incapacitated():
		_swimming = false
		_surface_walk_on = false
		_holding_depth = false
		_water_transition = &""
		_water_transition_timer = 0.0
		_set_water_mode(WaterMode.WADING if _in_water else WaterMode.NONE)
		return

	# Una trepada en curso manda ella sola hasta terminar.
	if water_mode == WaterMode.CLIMBING:
		return

	# Caminar SOBRE el agua. Va ANTES que el "¿estoy dentro del agua?" a proposito:
	# encima del agua los pies van justo en la superficie (2 cm por encima), asi que
	# el detector puede decir "seco" justo cuando el personaje esta encima del agua.
	# Lo que manda aqui es que siga habiendo columna de agua bastante debajo.
	if _surface_walk_on:
		if _surface_walk_possible():
			_swimming = false
			_holding_depth = false
			_set_water_mode(WaterMode.SURFACE_WALK)
			return
		_surface_walk_on = false

	if not _in_water:
		if _swimming:
			# Se sale del agua: pasa por la animacion de salir (y por su
			# salpicadura) aunque sea saliendo por donde no hay suelo.
			_end_swimming()
		else:
			_swimming = false
			_holding_depth = false
		_surface_walk_on = false
		_set_water_mode(WaterMode.NONE)
		return

	var depth := water_detection.get_depth() if water_detection != null else 0.0

	# --- 1) Caminar por el FONDO ---------------------------------------------
	# Hace pie de verdad y hay columna de agua de sobra: anda. No hay que pulsar
	# nada especial, basta con dejarse caer al fondo.
	if is_on_floor() and depth >= floor_min_depth and velocity.y <= 0.05:
		if water_mode != WaterMode.FLOOR:
			_swimming = false
			_holding_depth = false
			water_splash.emit(global_position, 0.7)
		_floor_air_time = 0.0
		_set_water_mode(WaterMode.FLOOR)
		return

	# Venimos del fondo y acabamos de despegarnos: se aguanta un instante para que
	# un bache del suelo no cambie el modo a nadar y vuelta a empezar.
	if water_mode == WaterMode.FLOOR:
		_floor_air_time += delta
		if _floor_air_time < floor_leave_time:
			return
		# Se deja el fondo del todo: a partir de aqui decide la profundidad.
		_swimming = false
		_holding_depth = false

	# --- 2) Nadar o vadear ----------------------------------------------------
	var deep := _is_deep_water()
	if deep and not _swimming:
		_begin_swimming()
	elif not deep and _swimming:
		_end_swimming()

	if not _swimming:
		# Vadea (o esta de pie en el agua): fisica de tierra, mas lento.
		_holding_depth = false
		_set_water_mode(WaterMode.WADING)
		return

	# --- 3) Superficie o sumergido -------------------------------------------
	# El paso NO se mide por la cabeza, sino por cuanto se ha hundido el cuerpo
	# respecto de su altura de flotacion: nadando tumbado la cabeza va a la misma
	# altura que los pies, asi que "cabeza fuera" no serviria como criterio.
	var line := _float_depth() + submerge_margin
	if water_mode == WaterMode.SUBMERGED:
		line -= surface_margin_hysteresis
	if depth >= line:
		if water_mode != WaterMode.SUBMERGED:
			_set_water_mode(WaterMode.SUBMERGED)
			# Al hundirse por primera vez se fija la profundidad a mantener.
			_hold_depth = clampf(depth, _float_depth(), max_hold_depth)
			_holding_depth = true
	else:
		_set_water_mode(WaterMode.SURFACE)
		_holding_depth = false


## Cambia de modo fisico de agua. Solo contabilidad y los ajustes que no dependen
## del modo anterior.
func _set_water_mode(mode: WaterMode) -> void:
	if mode == water_mode:
		return
	water_mode = mode
	if mode != WaterMode.NONE:
		# En el agua no se agacha: CTRL es "hundirse". Si se venia agachado de
		# tierra se suelta aqui, porque si no el estado se quedaria pegado y
		# bloquearia el ataque (request_attack lo prohibe agachado).
		is_crouching = false
	if mode == WaterMode.FLOOR:
		# En el fondo la capsula encogida falsearia la profundidad del cuerpo.
		is_crouching = false
		_floor_air_time = 0.0
	if mode == WaterMode.NONE:
		_surface_walk_on = false


## Entrar al agua honda. Se pierde la velocidad de caída y, si el golpe contra la
## superficie es fuerte, se pide una salpicadura proporcional (la escucha el
## sistema de efectos).
func _begin_swimming() -> void:
	_swimming = true
	# Agachado no tiene sentido flotando, y además la cápsula encogida daría una
	# altura de cuerpo falsa para calcular la flotación.
	is_crouching = false
	var impact := maxf(-velocity.y, 0.0)
	if impact > 2.0:
		water_splash.emit(global_position, impact)
	# El agua te para: no sigues cayendo al fondo como una piedra. Pero frena, no
	# teletransporta: la entrada la remata una mezcla progresiva (_update_enter).
	velocity.y = maxf(velocity.y, -0.6)
	_begin_water_transition(STATE_ENTER_WATER)


## Salir del agua. Ya se hace pie: el personaje se endereza y vuelve a andar.
func _end_swimming() -> void:
	_swimming = false
	_holding_depth = false
	water_splash.emit(global_position, 1.6)
	_begin_water_transition(STATE_EXIT_WATER)


func _begin_water_transition(state: StringName) -> void:
	_water_transition = state
	_water_transition_timer = _state_length(state, fallback_water_transition_time)


## Cuánto lleva reproducida la transición de salida del agua (s).
func _exit_water_elapsed() -> float:
	if _water_transition != STATE_EXIT_WATER:
		return 0.0
	var total := _state_length(STATE_EXIT_WATER, fallback_water_transition_time)
	return maxf(total - _water_transition_timer, 0.0)


## ¿Hay agua bastante honda como para nadar?
##
## OJO CON LA TRAMPA: "profundidad" aquí es cuánto baja el ORIGEN del personaje
## por debajo de la superficie, y eso significa dos cosas distintas según la
## postura. De pie en el fondo es la profundidad REAL del agua; nadando tumbado
## es solo lo que el cuerpo se hunde (0.67 m), que no tiene nada que ver con el
## fondo. Si se usara el mismo umbral para las dos, al nadar tumbado el personaje
## saldría del agua solo porque su origen no baja lo suficiente.
##
## Por eso, una vez nadando, solo se sale al HACER PIE con el agua ya somera: así
## el nadador puede cruzar agua poco profunda sin ponerse a andar a media brazada.
func _is_deep_water() -> bool:
	if water_detection == null or not water_detection.is_in_water():
		return false
	var depth := water_detection.get_depth()
	if _swimming:
		return not is_on_floor() or depth >= swim_depth - swim_depth_margin
	return depth >= swim_depth


# -----------------------------------------------------------------------------
#  Agua: un modo fisico por situacion
# -----------------------------------------------------------------------------
## ENTRADA al agua: mezcla progresiva entre la fisica de tierra y la del agua. La
## gravedad pierde fuerza poco a poco y la flotacion gana, asi que el personaje se
## frena al tocar el agua en vez de cambiar de fisica de un fotograma al otro.
func _update_enter(delta: float) -> void:
	_air_time = 0.0
	_landing_timer = 0.0
	_swim_vertical = 0.0
	var total := _state_length(_water_transition, fallback_water_transition_time)
	var t := 1.0
	if total > 0.0:
		t = clampf(1.0 - _water_transition_timer / total, 0.0, 1.0)
	if _water_transition_timer <= 0.0 or t >= 1.0:
		# Ya esta dentro: a partir de aqui manda la profundidad.
		_swimming = true
		_set_water_mode(WaterMode.SURFACE)
		return
	# Gravedad cada vez mas floja, flotacion cada vez mas fuerte.
	velocity.y -= gravity * (1.0 - t) * delta
	velocity.y += _buoyancy(delta) * t
	velocity.y = maxf(velocity.y, -max_fall_speed)
	_apply_horizontal_movement(delta, swim_acceleration, swim_deceleration)


## CAMINAR POR EL FONDO. El personaje esta bajo el agua pero hace pie: anda con
## las velocidades de tierra (mas lentas), la gravedad reducida lo mantiene
## pegado al suelo y ESPACIO lo despega para volver a nadar.
func _update_floor(delta: float) -> void:
	_air_time = 0.0
	_landing_timer = 0.0
	_swimming = false
	_swim_vertical = 0.0
	if is_on_floor():
		# Pegado al fondo: un empujon pequeño hacia abajo, no gravedad plena.
		velocity.y = -1.0
	else:
		velocity.y -= floor_gravity * delta
		velocity.y = maxf(velocity.y, -swim_vertical_speed * 2.0)
	# Despegarse: ESPACIO. Se pasa a nadar de inmediato (el impulso se nota).
	if Input.is_action_just_pressed("jump") and is_on_floor() \
			and not _is_ability_action() and not _is_attacking():
		velocity.y = floor_detach_speed
		_floor_air_time = floor_leave_time
		_swimming = false
		_hold_depth = water_detection.get_depth() if water_detection != null else 0.0
		water_splash.emit(global_position, 0.5)
		_set_water_mode(WaterMode.SUBMERGED)
		_holding_depth = true
		return
	# Horizontal: como en tierra, pero con la resistencia del agua (mas frenado).
	_apply_horizontal_movement(delta, floor_acceleration, floor_deceleration)


## CAMINAR SOBRE LA SUPERFICIE DEL AGUA (habilidad). El sistema controla de verdad
## la posicion vertical: un muelle lleva los PIES a la superficie, siguiendo las
## olas, en vez de apoyarse en un colisionador falso.
func _update_surface_walk(delta: float) -> void:
	_air_time = 0.0
	_landing_timer = 0.0
	_swimming = false
	_swim_vertical = 0.0
	# Salto desde la superficie: se deja de caminar sobre el agua.
	if Input.is_action_just_pressed("jump") and not _is_ability_action():
		_surface_walk_on = false
		velocity.y = sqrt(2.0 * gravity * jump_height * 0.55)
		_set_water_mode(WaterMode.SURFACE)
		return
	var error := (_surface_height() + surface_walk_offset) - global_position.y
	var wanted := clampf(error * surface_walk_stiffness,
		-surface_walk_max_speed, surface_walk_max_speed)
	velocity.y = move_toward(velocity.y, wanted, surface_walk_damping * delta)
	# Anda como en tierra (y puede correr): no esta nadando, esta andando encima.
	_apply_horizontal_movement(delta, acceleration, deceleration)


## ¿Tiene sentido poder caminar sobre el agua aqui? Hace falta agua y fondo
## bastante por debajo, si no seria caminar sobre un charco.
##
## Ojo: NO se exige estar "mojado". Caminando por ENCIMA del agua los pies van en
## la superficie, y el muelle que sostiene al personaje puede pasarse unos
## centimetros hacia arriba, asi que el detector puede decir "seco" estando
## literalmente encima del agua. Lo que manda es que haya agua debajo.
func _surface_walk_possible() -> bool:
	if water_detection == null or water_detection.get_zone() == null:
		return false
	return _water_column_depth() >= surface_walk_min_depth


## Altura de la superficie del agua en la posicion del personaje. Si el agua tiene
## olas, esto las sigue: caminar sobre el agua sube y baja con ellas.
func _surface_height() -> float:
	if water_detection == null:
		return global_position.y
	return water_detection.get_surface_height()


## Columna de agua REAL (m) que hay bajo la superficie en la posicion actual: se
## mide con un rayo hasta el fondo, no con la profundidad a la que esta el cuerpo.
## Hace falta para saber, sin tocar el fondo, si el agua es bastante honda.
func _water_column_depth() -> float:
	var surface := _surface_height()
	var from := Vector3(global_position.x, surface - 0.02, global_position.z)
	var to := from - Vector3.UP * 25.0
	var query := PhysicsRayQueryParameters3D.create(from, to, collision_mask, [get_rid()])
	var space := get_world_3d().direct_space_state
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return 25.0
	return maxf(surface - (hit["position"] as Vector3).y, 0.0)


## TREPAR Y SALIR POR EL BORDE. La cadena que pide el diseño es
## SUMERGIDO -> SUPERFICIE -> BORDE -> SALIDA -> TIERRA, y esto la cierra: cuando
## hay un borde a la altura a la que se puede subir y el jugador empuja hacia el,
## el personaje se sube de verdad (posicion controlada, no un teletransporte).
func _start_climb(landing: Vector3) -> bool:
	if water_mode == WaterMode.CLIMBING or _climb_cooldown > 0.0:
		return false
	_climb_from = global_position
	# El destino lleva el cuerpo un poco mas alla del borde, para no quedarse con
	# medio cuerpo colgando en el aire.
	_climb_to = landing
	_climb_timer = 0.0
	_climb_total = maxf(climb_time, 0.15)
	velocity = Vector3.ZERO
	velocity.y = 0.0
	_swimming = false
	_holding_depth = false
	_surface_walk_on = false
	_set_water_mode(WaterMode.CLIMBING)
	_begin_water_transition(STATE_EXIT_WATER)
	water_splash.emit(global_position, 1.2)
	return true


func _update_climb(delta: float) -> void:
	_climb_timer += delta
	var t := clampf(_climb_timer / _climb_total, 0.0, 1.0)
	# La subida va en dos tramos: primero hacia ARRIBA pegado a la pared, luego
	# hacia DELANTE por encima del borde. Asi se lee como salir del agua.
	var up := _ease_out(clampf(t * 1.7, 0.0, 1.0))
	var fwd := _ease_out(clampf((t - 0.45) / 0.55, 0.0, 1.0))
	var pos := _climb_from
	pos.y = lerpf(_climb_from.y, _climb_to.y, up)
	pos.x = lerpf(_climb_from.x, _climb_to.x, fwd)
	pos.z = lerpf(_climb_from.z, _climb_to.z, fwd)
	velocity = Vector3.ZERO
	global_position = pos
	if t >= 1.0:
		global_position = _climb_to
		velocity = Vector3.ZERO
		_climb_cooldown = climb_cooldown
		_set_water_mode(WaterMode.NONE)
		water_splash.emit(global_position, 0.9)


## ¿Hay un borde trepable delante? Devuelve el punto donde quedarian los pies, o
## Vector3.INF si no hay nada. Lo usan la tecla de salto (estando en el agua) para
## salir por el borde, y has_ledge_in_front() para que lo pueda consultar la UI.
##
## Las medidas se ADAPTAN al borde que se encuentre, en vez de buscarlo a una
## altura fija: en esta piscina el borde sobresale 0.3 m del agua, y una pared de
## 2 m tiene que funcionar igual de bien.
func _find_ledge() -> Vector3:
	if water_detection == null or not water_detection.is_in_water():
		return Vector3.INF
	# Solo se trepa FLOTANDO. Vadeando (agua somera) el salto sigue siendo un
	# salto, aunque haya una rampa delante.
	if water_mode != WaterMode.SURFACE and water_mode != WaterMode.SUBMERGED:
		return Vector3.INF
	# Y hay que estar EN LA SUPERFICIE: desde el fondo no se sube.
	if water_detection.get_depth() > _float_depth() + 0.35:
		return Vector3.INF
	var dir := _facing_direction()
	dir.y = 0.0
	if dir.length_squared() < 0.001:
		return Vector3.INF
	dir = dir.normalized()
	var space := get_world_3d().direct_space_state
	var feet := global_position
	var exclude: Array[RID] = [get_rid()]

	# 1) Se busca SUELO transitable por delante y por encima del agua, cayendo desde
	# arriba: el primer sitio donde el personaje se podria poner de pie. El rayo
	# empieza 0.6 m POR ENCIMA de la altura maxima de trepada a proposito: si
	# empezara justo a esa altura, con el cuerpo hundido arrancaria pegado a la
	# superficie del borde y el roce haria que no detectara nada.
	var top := feet + Vector3.UP * (climb_height + 0.6) + dir * climb_reach
	var q1 := PhysicsRayQueryParameters3D.create(top,
		top - Vector3.UP * (climb_height + 1.6), collision_mask, exclude)
	var ground := space.intersect_ray(q1)
	if ground.is_empty():
		return Vector3.INF
	if (ground["normal"] as Vector3).y < 0.6:
		return Vector3.INF
	var landing: Vector3 = ground["position"]
	# El borde tiene que estar POR ENCIMA del agua (si esta sumergido se sale
	# nadando, no trepando) y no mas alto de lo que se puede subir.
	if landing.y < _surface_height() + 0.05:
		return Vector3.INF
	if landing.y - feet.y > climb_height:
		return Vector3.INF

	# 2) Entre los pies y el borde tiene que haber PARED. El sondeo va a media
	# altura entre los dos: asi vale lo mismo para un borde que apenas asoma del
	# agua que para una pared alta.
	var mid := feet
	mid.y = lerpf(feet.y, landing.y, 0.5)
	var q2 := PhysicsRayQueryParameters3D.create(mid, mid + dir * climb_reach,
		collision_mask, exclude)
	if space.intersect_ray(q2).is_empty():
		return Vector3.INF

	# 3) Por ENCIMA del borde tiene que haber AIRE, si no seria una pared sin fin.
	var high := landing + Vector3.UP * 1.1
	var q3 := PhysicsRayQueryParameters3D.create(high - dir * 0.05,
		high + dir * climb_reach, collision_mask, exclude)
	if not space.intersect_ray(q3).is_empty():
		return Vector3.INF

	# 4) Y que quepa DE PIE donde va a quedar.
	var target := landing + dir * climb_land_offset
	var q4 := PhysicsRayQueryParameters3D.create(target + Vector3.UP * 0.08,
		target + Vector3.UP * (_standing_height + 0.3), collision_mask, exclude)
	if not space.intersect_ray(q4).is_empty():
		return Vector3.INF
	return target


## ¿Hay un borde del que se pueda salir ahora mismo? Lo puede consultar la UI.
func has_ledge_in_front() -> bool:
	return _find_ledge().is_finite()


static func _ease_out(t: float) -> float:
	return 1.0 - (1.0 - t) * (1.0 - t)


# -----------------------------------------------------------------------------
#  Combate cuerpo a cuerpo
# -----------------------------------------------------------------------------
## Comprueba si el golpe en curso tiene que impactar ya (una sola vez por golpe).
func _melee_tick() -> void:
	if _melee_done or _action_timer <= 0.0 or not _is_attacking():
		return
	if _attack_elapsed() < _action_duration * melee_impact_at:
		return
	_melee_done = true
	_melee_hit()


## Golpe cuerpo a cuerpo: cono por delante, contra todo lo que sea "damageable".
## Funciona en tierra Y EN EL AGUA (tambien sumergido), que es justo lo que pide
## el diseño: el combate bajo el agua tiene que responder igual.
func _melee_hit() -> void:
	const GROUP := &"damageable"
	var facing := -global_transform.basis.z
	facing.y = 0.0
	if facing.length_squared() < 0.001:
		return
	facing = facing.normalized()
	var cos_limit := cos(deg_to_rad(melee_arc))
	var origin := global_position + Vector3.UP * 1.0
	for node in get_tree().get_nodes_in_group(GROUP):
		if node == self or not (node is Node3D):
			continue
		var target := node as Node3D
		if not target.has_method("apply_damage"):
			continue
		var radius := melee_radius
		if target.has_method("get_hit_radius"):
			radius = float(target.call("get_hit_radius"))
		var offset := target.global_position - origin
		var flat := Vector3(offset.x, 0.0, offset.z)
		if flat.length() > melee_reach + radius:
			continue
		if flat.length() > 0.05 and flat.normalized().dot(facing) < cos_limit:
			continue
		target.call("apply_damage", get_melee_damage(), global_position, DAMAGE_LIGHT)
		_reaction_at(target.global_position + Vector3.UP * 1.0, 0.45)


## Reaccion del agua en un punto: en la superficie es un golpe de agua, y debajo
## del agua es un remolino de burbujas. Lo comparten los golpes y las habilidades.
func _reaction_at(point: Vector3, strength: float) -> void:
	var effects := get_node_or_null("WaterEffects")
	if effects == null:
		return
	# El PRIMER argumento de estos efectos es DONDE se cuelgan (el mundo), no el
	# punto: por eso se pasa aparte.
	var host := get_parent() as Node3D
	if host == null:
		host = get_tree().current_scene as Node3D
	if host == null:
		return
	if is_underwater():
		effects.call("bubbles", host, point, int(10.0 * strength), 0.5 * strength, strength)
	else:
		effects.call("burst", host, point, 0.6 * strength, strength)


# -----------------------------------------------------------------------------
#  Manos y apuntado (para el agua que se junta en las manos y los hechizos)
# -----------------------------------------------------------------------------
## Hueso de una mano en coordenadas de MUNDO. Devuelve Vector3.INF si el modelo no
## tiene esqueleto o el hueso no existe: quien lo llame tiene que tener un plan B.
func get_hand_position(hand: StringName) -> Vector3:
	var skeleton := _skeleton()
	var bone := _hand_bone(skeleton, hand)
	if bone < 0:
		return Vector3.INF
	return skeleton.global_transform * skeleton.get_bone_global_pose(bone).origin


## Indice del hueso de una mano en el esqueleto, probando los nombres que usan los
## modelos importados (Mixamo, maya...). -1 si no esta.
func _hand_bone(skeleton: Skeleton3D, hand: StringName) -> int:
	if skeleton == null:
		return -1
	var bone := skeleton.find_bone(hand)
	if bone < 0:
		bone = skeleton.find_bone(StringName("mixamorig:" + String(hand)))
	if bone < 0:
		bone = skeleton.find_bone(StringName("mixamorig_" + String(hand)))
	return bone


## true si el modelo tiene el hueso de la mano que sostiene el agua.
func has_water_hand() -> bool:
	return _hand_bone(_skeleton(), water_hand) >= 0


## SITIO del agua que el personaje SOSTIENE en la mano: es el ancla (socket) del
## balón y de las cargas de los hechizos.
##
## Sale del HUESO de la mano, no del centro del cuerpo: antes se usaba el punto
## medio de las dos manos, y con los brazos bajados ese punto cae en el eje del
## personaje, así que el balón aparecía flotando DENTRO del cuerpo. Al salir del
## hueso, el agua acompaña al brazo (andar, correr, agacharse, girar) y no hay
## ninguna posición puesta a mano que se rompa al mover al personaje.
func get_water_ball_position() -> Vector3:
	var skeleton := _skeleton()
	var bone := _hand_bone(skeleton, water_hand)
	if bone < 0:
		# Plan B (modelo sin esqueleto): delante del pecho, como antes.
		return get_hand_center()
	var socket: Transform3D = skeleton.global_transform * skeleton.get_bone_global_pose(bone)
	return socket.origin + socket.basis * water_hand_offset


## Punto medio de las dos manos: es donde se junta el agua al cargar una habilidad.
func get_hand_center() -> Vector3:
	var right := get_hand_position(&"RightHand")
	var left := get_hand_position(&"LeftHand")
	var ok_r := right.is_finite()
	var ok_l := left.is_finite()
	if ok_r and ok_l:
		return (right + left) * 0.5
	if ok_r:
		return right
	if ok_l:
		return left
	return global_position + Vector3.UP * 1.25 + (-global_transform.basis.z) * 0.5


## Esqueleto del modelo (cacheado: se pide en cada fotograma desde el agua).
## [!] La variable va aqui y no arriba porque es cache interna del modelo, no
## configuracion.
var _skeleton_cache: Skeleton3D = null


func _skeleton() -> Skeleton3D:
	if _skeleton_cache != null and is_instance_valid(_skeleton_cache):
		return _skeleton_cache
	if model == null:
		return null
	_skeleton_cache = _find_skeleton(model)
	return _skeleton_cache


func _find_skeleton(node: Node) -> Skeleton3D:
	for child in node.get_children():
		if child is Skeleton3D:
			return child as Skeleton3D
		var deep := _find_skeleton(child)
		if deep != null:
			return deep
	return null


## Direccion en la que apunta el jugador (la camara), en 3D y sin aplanar. Es la
## que usan las habilidades cuando se lanzan desde el agua: sumergido se apunta a
## cualquier parte, no siempre hacia delante en horizontal.
func get_aim_direction() -> Vector3:
	if camera_rig != null:
		var dir := camera_rig.get_look_direction()
		if dir.length_squared() > 0.001:
			return dir.normalized()
	var forward := -global_transform.basis.z
	return forward.normalized()


## true si el personaje esta SUMERGIDO (cabeza debajo). No cuenta flotar en la
## superficie ni vadear.
func is_underwater() -> bool:
	return water_mode == WaterMode.SUBMERGED or water_mode == WaterMode.FLOOR \
		or (water_mode == WaterMode.CLIMBING and _water_transition_timer > 0.0)


## true si el agua manda en la fisica ahora mismo (nadando, en el fondo o sobre la
## superficie). Es el equivalente ampliado del antiguo is_swimming().
func is_in_water_physics() -> bool:
	return water_mode != WaterMode.NONE and water_mode != WaterMode.WADING


## Modo fisico del agua actual (ver WaterMode).
func get_water_mode() -> WaterMode:
	return water_mode


## Nombre legible del modo de agua, para HUD y para las pruebas.
func get_water_mode_name() -> String:
	match water_mode:
		WaterMode.WADING:
			return "wading"
		WaterMode.ENTERING:
			return "entering"
		WaterMode.SURFACE:
			return "surface"
		WaterMode.SUBMERGED:
			return "submerged"
		WaterMode.FLOOR:
			return "floor"
		WaterMode.SURFACE_WALK:
			return "surface_walk"
		WaterMode.CLIMBING:
			return "climbing"
		_:
			return "none"


## Física de la natación: aquí NO hay gravedad. Manda la flotación, y el jugador
## empuja con WASD (relativo a la cámara), ESPACIO para subir y CTRL para bajar.
##
## Tres cosas son las que dan la sensación de estar en agua y no en el aire:
##   * ACELERACIÓN baja (swim_acceleration): no se arranca en seco.
##   * FRENADO bajo (swim_deceleration): al soltar los controles el personaje
##     SIGUE avanzando y se va frenando solo. Eso es la inercia.
##   * FLOTACIÓN (buoyancy_accel): el cuerpo tiende a quedarse a la altura del
##     agua, y vuelve a ella poco a poco si lo hunden.
##
## Hay DOS maneras de nadar y por eso el código se abre en dos ramas:
##   * EN LA SUPERFICIE: el avance es horizontal puro y en la vertical pelea la
##     flotación (el cuerpo se queda a su altura de flotación). Si el jugador
##     empuja con ESPACIO/CTRL, manda él.
##   * SUMERGIDO: el avance sigue la MIRADA (se nada hacia arriba o hacia abajo
##     mirando) y, mientras no se mande en la vertical, la profundidad se
##     MANTIENE: ni flota hacia arriba ni se hunde. Eso es la flotabilidad neutra.
func _update_swim(delta: float) -> void:
	# Dentro del agua no hay aterrizajes. Si se sale del agua en pleno salto, la
	# gravedad normal vuelve sola en cuanto este estado deja de mandar.
	_air_time = 0.0
	_landing_timer = 0.0

	var vertical := 0.0
	var transition := _water_transition_timer > 0.0
	# Durante una transición (meterse/salir) no se manda en la vertical: el cuerpo
	# está colocándose, y si además se pudiera empujar hacia arriba el personaje
	# saldría volando del agua a media animación.
	if not transition:
		if Input.is_action_pressed("jump"):
			vertical += 1.0
		elif Input.is_action_pressed("crouch"):
			vertical -= 1.0
	_swim_vertical = vertical

	var submerged := water_mode == WaterMode.SUBMERGED
	var desired := _swim_desired_direction()
	# Lanzando una habilidad no se nada: el cuerpo se queda en la postura del
	# hechizo y el agua lo va frenando sola. Si se pudiera nadar a la vez, la
	# animacion (que es de pie) se deslizaria por el agua como un patin.
	if _is_ability_action():
		desired = Vector3.ZERO
	var speed := swim_back_speed if _swim_moving_backwards() else swim_speed
	if submerged:
		speed = swim_speed_underwater
	if _aiming:
		# Locomoción CON BALÓN también en el agua: se nada más despacio mientras se
		# lleva el agua cargada en las manos.
		speed *= aim_move_factor
	if transition:
		# Cambiando de postura (meterse o salir): se sigue avanzando, pero más
		# despacio, para no cruzar el lago mientras el cuerpo se endereza.
		desired = _facing_direction()
		if desired.length_squared() < 0.001:
			desired = -global_transform.basis.z
		speed *= water_transition_speed_factor
	else:
		# Nado RÁPIDO (Shift): se nada más fuerte y la brazada se acelera sola.
		# No se aplica durante las transiciones de agua (ahí manda el factor de
		# transición) ni lanzando una habilidad (el cuerpo va en la postura del
		# hechizo, no brazando).
		if is_running and not _is_ability_action():
			speed *= swim_sprint_factor

	if _knockback.length_squared() > 0.0004:
		# Un golpe que te tira al agua sigue empujando, pero el agua lo frena
		# antes que el aire.
		_knockback = _knockback.move_toward(Vector3.ZERO, deceleration * 1.5 * delta)
		velocity.x = _knockback.x
		velocity.z = _knockback.z
		velocity.y = move_toward(velocity.y, 0.0, deceleration * delta)
	elif submerged:
		# --- Nado libre 3D -----------------------------------------------------
		# El avance sigue la mirada, asi que la velocidad objetivo es un vector
		# 3D; ESPACIO y CTRL se SUMAN a la vertical (para subir recto sin tener
		# que mirar arriba). Con inercia, en las tres direcciones.
		#
		# La profundidad que se MANTIENE es la que se tiene AHORA MISMO, no la que
		# se tenia al hundirse: asi, soltar CTRL deja el cuerpo donde esta (se
		# desliza un poco y se para) en vez de devolverlo a la superficie. Eso es
		# la flotabilidad neutra: no subes si no nadas hacia arriba.
		if water_detection != null:
			_hold_depth = clampf(water_detection.get_depth(), _float_depth(), max_hold_depth)
			_holding_depth = true
		var wanted := desired * speed
		wanted.y += vertical * (swim_vertical_speed if vertical >= 0.0 else dive_speed)
		if wanted.length_squared() > 0.0004:
			velocity = velocity.move_toward(wanted, swim_acceleration * delta)
		else:
			# Sin ordenes: flotabilidad neutra (MANTIENE la profundidad) y la
			# resistencia del agua frenando el avance poco a poco.
			velocity.y += _buoyancy(delta)
			velocity.x = move_toward(velocity.x, 0.0, swim_deceleration * delta)
			velocity.z = move_toward(velocity.z, 0.0, swim_deceleration * delta)
	else:
		# --- Nado en la superficie --------------------------------------------
		var horizontal := Vector3(velocity.x, 0.0, velocity.z)
		if desired.length_squared() > 0.001:
			var target := Vector3(desired.x, 0.0, desired.z).normalized() * speed
			horizontal = horizontal.move_toward(target, swim_acceleration * delta)
		else:
			# Sin controles: solo la resistencia del agua. El personaje se desliza
			# y se va frenando poco a poco, en vez de quedarse clavado.
			horizontal = horizontal.move_toward(Vector3.ZERO, swim_deceleration * delta)
		velocity.x = horizontal.x
		velocity.z = horizontal.z

	# La vertical en la SUPERFICIE se lleva APARTE, y esto es importante: si se
	# metiera en el mismo move_toward que la horizontal, el objetivo tendria y = 0
	# y estaria frenando la subida/bajada todo el rato, anulando la flotacion. O
	# manda el jugador (ESPACIO / CTRL) o manda la flotacion, nunca los dos.
	if not submerged:
		if absf(vertical) > 0.01:
			var target_y := vertical * (swim_vertical_speed if vertical > 0.0 else dive_speed)
			velocity.y = move_toward(velocity.y, target_y, swim_acceleration * delta)
		else:
			velocity.y += _buoyancy(delta)

	# Techo de la superficie: nadando hacia arriba el cuerpo se PARA al llegar a
	# su altura de flotacion. Sin esto, mantener ESPACIO sacaba al personaje
	# disparado del lago como un tapon (y encima en postura de nadar).
	if water_detection != null and velocity.y > 0.0:
		if water_detection.get_depth() < _float_depth() - swim_surface_margin:
			velocity.y = 0.0

	move_speed = Vector3(velocity.x, 0.0, velocity.z).length()


## Direccion en la que el jugador quiere nadar. En la superficie es horizontal
## (relativa a la camara, como en tierra). SUMERGIDO, si free_vertical_swim esta
## activo, el avance (W/S) sigue la MIRADA de la camara con su inclinacion y A/D
## van en horizontal: asi se puede nadar en cualquier direccion del espacio, no
## solo hacia delante en horizontal.
func _swim_desired_direction() -> Vector3:
	if _input_direction.length_squared() < 0.001:
		return Vector3.ZERO
	if water_mode != WaterMode.SUBMERGED or not free_vertical_swim:
		return _input_direction
	if _input_raw.length_squared() < 0.001:
		return _input_direction
	var look := get_aim_direction()
	var right := global_transform.basis.x
	if camera_rig != null:
		right = camera_rig.global_transform.basis.x
	right.y = 0.0
	if right.length_squared() > 0.001:
		right = right.normalized()
	var dir := look * _input_raw.y + right * _input_raw.x
	if dir.length_squared() < 0.0001:
		return _input_direction
	return dir.normalized()


## Empuje vertical de flotación (m/s ganados en este frame).
##
## Es un muelle AMORTIGUADO hacia una profundidad OBJETIVO:
##   * Flotando en la superficie, la del estado actual (float_depths).
##   * SUMERGIDO, la profundidad fijada al hundirse: eso es la flotabilidad
##     NEUTRA, el cuerpo se queda donde estaba en vez de subir solo.
##
## El signo es la clave: [code]error[/code] es POSITIVO cuando hay MÁS agua de la
## que toca (el cuerpo está demasiado hundido), y entonces hay que subir. Por eso
## la resta es depth - objetivo y no al revés.
func _buoyancy(delta: float) -> float:
	if water_detection == null:
		return 0.0
	# Si el jugador está mandando en la vertical (ESPACIO / CTRL), manda él.
	# Durante una transición de agua no manda nadie: solo la flotación.
	if _water_transition_timer <= 0.0 \
			and (Input.is_action_pressed("jump") or Input.is_action_pressed("crouch")):
		return 0.0
	# Balanceo: el agua nunca deja el cuerpo completamente quieto.
	_float_bob = sin(_water_time * neutral_bob_speed) * neutral_bob_amplitude
	var target := _float_depth() + _float_bob
	if _holding_depth and _hold_depth > 0.0:
		target = clampf(_hold_depth + _float_bob, _float_depth(), max_hold_depth)
	var error := water_detection.get_depth() - target
	var accel := error * buoyancy_accel - velocity.y * buoyancy_damping
	return clampf(accel, -25.0, 25.0) * delta


## Profundidad (m) a la que debe quedar el ORIGEN del personaje (los pies)
## mientras flota en el estado actual. Sale de float_depths.
func _float_depth() -> float:
	return float(float_depths.get(String(_state), float_depth_default))


## true si el jugador está pidiendo ir hacia atrás respecto a su mirada (tecla S).
## En el agua se mira el INPUT y no la velocidad: nadando hacia atrás el personaje
## NO se gira, así que mirando la velocidad nunca se detectaría.
func _swim_moving_backwards() -> bool:
	if _input_direction.length_squared() < 0.001:
		return false
	var forward := -global_transform.basis.z
	return _input_direction.normalized().dot(forward.normalized()) < -0.35


## Estado que toca mientras el personaje está en el agua.
func _update_water_state() -> void:
	# 1) Una accion de un solo tiro manda: ataque, esquiva o habilidad de agua. El
	#    personaje hace la postura aunque este nadando o andando por el fondo.
	if _action_timer > 0.0 \
			and (_is_ability_action() or _is_attacking() or _action_state == STATE_DODGE):
		_enter_state(_action_state)
		return
	# 2) Transicion de entrada/salida en curso. La SALIDA se acorta en cuanto el
	#    personaje ya esta de pie en tierra y no esta mojado: el clip de salir del
	#    agua dura casi 2 s y, sin esto, seguia reproduciendose fuera del agua y
	#    parecia quedarse trabado antes de recuperar la locomocion terrestre.
	if _water_transition_timer > 0.0:
		if _water_transition == STATE_EXIT_WATER and water_mode == WaterMode.NONE \
				and is_on_floor() and not _in_water \
				and _exit_water_elapsed() >= exit_water_cut_time:
			_water_transition = &""
			_water_transition_timer = 0.0
		else:
			_enter_state(_water_transition)
			return
	# 3) Cada modo tiene su animacion. El fondo y caminar sobre el agua usan la
	#    locomocion de tierra: son andar, solo que con agua alrededor.
	match water_mode:
		WaterMode.FLOOR:
			_enter_state(_floor_locomotion_state())
		WaterMode.SURFACE_WALK:
			_enter_state(_ground_locomotion_state())
		_:
			_enter_state(_swim_state())


## Estado de andar por el FONDO. A proposito es configurable (floor_idle_state y
## floor_walk_state): hoy usa los clips de tierra, y el dia que haya animaciones
## propias de andar bajo el agua solo hay que cambiar esos dos exports.
func _floor_locomotion_state() -> StringName:
	if move_speed < idle_speed_threshold:
		return floor_idle_state
	return floor_walk_state


## Estado de natación según el movimiento REAL, igual que en tierra: no se elige
## por la tecla pulsada, sino por la velocidad que lleva el cuerpo.
##
## La excepción es la vertical, y a propósito: ahí manda la ORDEN del jugador y no
## la velocidad. Si se mirara la velocidad, cualquier subida por flotación (al
## pasar de la postura de entrar al agua a la de nadar tumbado el cuerpo sube)
## cambiaba la animación a "subir" un instante. Con la orden, la brazada es la que
## pide el jugador y no parpadea.
func _swim_state() -> StringName:
	if _swim_vertical > 0.0:
		return STATE_SWIM_UP
	if _swim_vertical < 0.0:
		return STATE_SWIM_DOWN
	if move_speed < swim_idle_threshold:
		return STATE_SWIM_IDLE
	return STATE_SWIM_BACK if _swim_moving_backwards() else STATE_SWIM_FORWARD


## true si el personaje está nadando (agua honda). Vadear no cuenta.
func is_swimming() -> bool:
	return _swimming


## true si tiene los pies mojados, aunque haga pie y ande por el fondo.
func is_in_water() -> bool:
	return _in_water


## Fracción (0..1) del cuerpo que queda bajo el agua.
func get_submersion() -> float:
	return _submersion


# -----------------------------------------------------------------------------
#  Acciones de un solo tiro (ataque / esquiva / golpe)
# -----------------------------------------------------------------------------
## Arranca una accion de un solo tiro. La duracion sale del propio clip, asi que
## si cambias la animacion el tiempo se ajusta solo.
## [param forced_duration] si es mayor que 0, se usa en vez de la del clip.
func start_action(state: StringName, forced_duration := 0.0) -> void:
	if animation_controller != null:
		# La velocidad del golpe se fija ANTES de medir su clip: la duracion tiene
		# que salir ya con el factor del golpe que arranca (si no, el primer golpe
		# duraba el clip entero y la ventana de encadenado se abria tarde). El
		# finalizador va a la velocidad natural de su clip (mas pesado, con su
		# recuperacion entera); los golpes normales, acelerados.
		animation_controller.set_action_speed(finisher_clip_speed if _combo_finisher else attack_clip_speed)
	var length := forced_duration
	if length <= 0.0 and animation_controller != null:
		length = animation_controller.get_state_length(state)
	_action_state = state
	_action_duration = length if length > 0.0 else fallback_action_duration
	_action_timer = _action_duration
	# Accion nueva = golpe nuevo: vuelve a poder impactar (lo mira _melee_tick).
	_melee_done = false
	_enter_state(state, true)


## API publica para el input y para el sistema de combate.
## Devuelve true si el golpe ha arrancado (o si ha quedado encolado en el combo).
##
## COMBO: si ya estas golpeando, el clic NO se pierde ni reinicia la animacion.
##   - Si el golpe en curso ya ha pasado su ventana (combo_window), el siguiente
##     golpe entra YA, mezclado con el anterior.
##   - Si todavia es pronto, se queda en cola y entra solo en cuanto se abre la
##     ventana.
## Asi, machacar el boton encadena golpes de forma fluida en vez de reiniciar el
## primer golpe a mitad y cortarlo.
func request_attack(state: StringName = &"") -> bool:
	if is_dead or is_crouching:
		return false
	# Hacer pie NO es obligatorio en el agua: el combate bajo el agua (nadando o
	# andando por el fondo) tiene que responder igual, es parte del diseño.
	if not is_on_floor() and not is_in_water_physics():
		return false
	if _is_attacking():
		_attack_queued = true
		_queued_attack_state = state
		_try_chain_attack()
		return true
	if _action_timer > 0.0:
		# Otra accion en curso (una esquiva, por ejemplo): ahora no se ataca.
		return false
	_start_attack(state)
	return true


## Arranca el siguiente golpe del combo. Sin estado, va alternando los dos golpes:
## es lo que hace que el combo parezca un combo y no el mismo golpe repetido.
## CON estado (lo que manda el input): izquierdo -> attack (Punching), derecho ->
## attack_2 (Cross Punch), cada clic con SU golpe, sin alternar.
func _start_attack(state: StringName = &"") -> void:
	var next := state
	# SIN estado = clic izquierdo: avanza el combo y alterna las manos solo.
	# CON estado = clic derecho (cruzado suelto): no toca la cuenta del combo, para
	# no descolocarlo: despues del cruzado, el siguiente clic izquierdo sigue en el
	# paso donde estaba.
	if next == &"":
		next = attack_state if _combo_index % 2 == 0 else attack_state_2
		_combo_index += 1
		_combo_step = ((_combo_index - 1) % combo_length) + 1
		_combo_finisher = _combo_step == combo_length
	else:
		_combo_step = 0
		_combo_finisher = false
	start_action(next)


## Encadena el golpe encolado si el que esta en curso ya llego a su ventana.
func _try_chain_attack() -> void:
	if not _attack_queued or not _is_attacking():
		return
	if _attack_elapsed() < _action_duration * combo_window:
		return
	_attack_queued = false
	_start_attack(_queued_attack_state)
	_queued_attack_state = &""


## true mientras se ejecuta un golpe (cualquiera de los del combo).
func _is_attacking() -> bool:
	return _action_timer > 0.0 and _is_attack_state(_action_state)


func _is_attack_state(state: StringName) -> bool:
	return state == attack_state or state == attack_state_2


## true si la accion de un solo tiro en curso es una habilidad de agua.
func _is_ability_action() -> bool:
	return ability_manager != null and ability_manager.is_ability_state(_action_state)


## Cuanto lleva reproducido el golpe en curso (s).
func _attack_elapsed() -> float:
	return maxf(_action_duration - _action_timer, 0.0)


## Danio del golpe que toca AHORA: el finalizador del combo pega mas fuerte.
func get_melee_damage() -> float:
	return melee_damage * (finisher_damage_multiplier if _combo_finisher else 1.0)


## Paso del combo en curso (1..combo_length; 0 = golpe suelto del clic derecho).
func get_combo_step() -> int:
	return _combo_step


## true si el golpe en curso es el finalizador del combo (el cuarto).
func is_combo_finisher() -> bool:
	return _combo_finisher


## Esquivar. Si no se le da direccion, se esquiva hacia donde mira el personaje.
func request_dodge(direction: Vector3 = Vector3.ZERO) -> bool:
	if is_dead or _action_timer > 0.0 or not is_on_floor() or is_crouching:
		return false
	var dir := direction
	if dir.length_squared() < 0.001:
		dir = _input_direction
	if dir.length_squared() < 0.001:
		dir = -global_transform.basis.z
	_dodge_direction = Vector3(dir.x, 0.0, dir.z).normalized()
	_dodge_timer = dodge_dash_time
	start_action(STATE_DODGE, dodge_duration)
	return true


## Lanzar una habilidad acuatica (1..4).
##
## OJO: esto NO crea el efecto. Solo comprueba el enfriamiento y arranca la
## animacion; el objeto de la habilidad nace cuando la propia animacion lo pide
## (ver notify_ability_release). Si el efecto saliera aqui, se veria salir de la
## nada antes de que el personaje termine de cargar el hechizo.
func request_ability(index: int) -> bool:
	if ability_manager == null:
		return false
	# El hechizo SALE del balón que el personaje ya tiene en las manos: el gestor
	# no crea un agua aparte mientras se apunta, y al liberar el clip suelta ESE
	# balón (release_aim_ball) y lo vuelve a juntar para seguir apuntando.
	var started := ability_manager.try_cast(index)
	return started


## Suelta el balón que el personaje tiene entre las manos (se abre y desaparece)
## y lo vuelve a juntar enseguida para poder seguir apuntando. Lo llama el gestor
## de habilidades en el fotograma EXACTO en que el hechizo sale, para que el
## hechizo use el agua que se tenía cargada en las manos.
func release_aim_ball() -> void:
	if not _aiming:
		return
	_clear_aim_ball()
	# El agua se ha IDO de la mano con el hechizo: el personaje se queda sin bola y
	# vuelve a juntarla pasando otra vez por la preparacion (PREPARE -> FORM). NO se
	# rearma al instante: si se creara aqui, se veria una bola nueva en la mano
	# mientras la animacion del ataque todavia esta soltando el hechizo.
	_aim_phase = AimPhase.PREPARE
	_aim_time = 0.0


## La llama una PISTA DE METODO de la animacion (ver tools/pack_animation_builder.gd)
## en el fotograma exacto en el que la habilidad tiene que salir.
## [param state] el estado de animacion de la habilidad, que es lo que identifica
## cual de las cuatro es.
func notify_ability_release(state: StringName) -> void:
	if ability_manager != null:
		ability_manager.release_for_state(state)


## Enfriamiento restante (s) de una habilidad, y su fraccion 0..1 para una barra.
func get_ability_cooldown(index: int) -> float:
	if ability_manager == null:
		return 0.0
	return ability_manager.cooldown_left(index)


func get_ability_cooldown_ratio(index: int) -> float:
	if ability_manager == null:
		return 0.0
	return ability_manager.cooldown_ratio(index)


func get_ability_name(index: int) -> String:
	if ability_manager == null:
		return ""
	return ability_manager.ability_name(index)


# -----------------------------------------------------------------------------
#  Apuntado con balón de agua (MANTENER F)
# -----------------------------------------------------------------------------
## true mientras se apunta (MANTENER la tecla F).
func is_aiming() -> bool:
	return _aiming


## Fase del apuntado (ver AimPhase): OFF / PREPARE / FORM / AIM.
func get_aim_phase() -> int:
	return _aim_phase


## Objetivo que tiene enganchado la retícula ahora mismo (o null). Lo usan la
## retícula y las habilidades para saber a quién se está apuntando.
func get_aim_target() -> Node3D:
	return _aim_target


## Empieza a apuntar: el personaje junta agua en las manos. Se puede apuntar de
## pie, andando, nadando o por el fondo; lo que no se puede es apuntar muerto,
## aturdido o en mitad de otra acción.
func request_aim() -> bool:
	if _aiming or is_dead or is_incapacitated():
		return false
	if _action_timer > 0.0 and not _is_ability_action():
		return false
	_aiming = true
	_aim_phase = AimPhase.PREPARE
	_aim_time = 0.0
	return true


## Deja de apuntar. El agua que estaba junta se deshace sin más (no se lanza).
func stop_aim() -> void:
	if not _aiming:
		return
	_aiming = false
	_aim_phase = AimPhase.OFF
	_aim_time = 0.0
	_clear_aim_ball()
	_set_aim_target(null)


## Avanza PREPARE -> FORM -> AIM y, ya apuntando, engancha el objetivo de la
## retícula. La llamada cada frame desde _physics_process.
func _update_aim(delta: float) -> void:
	if not _aiming:
		return
	# Si algo corta el apuntado (te derriban, mueres), se deshace solo.
	if is_dead or is_incapacitated():
		stop_aim()
		return
	_aim_time += delta
	match _aim_phase:
		AimPhase.PREPARE:
			# Mientras la animacion del hechizo sigue, el agua NO se junta todavia:
			# el personaje acaba de soltarla y tiene que verse que se ha ido de la
			# mano. La preparacion espera a que el ataque termine.
			if _is_ability_action():
				_aim_time = 0.0
			elif _aim_time >= aim_prepare_time:
				_aim_phase = AimPhase.FORM
				_aim_time = 0.0
				# El agua se forma AQUI: es la creación acompasada con la animación
				# (preparación -> formacion), no en el mismo fotograma de pulsar F.
				_spawn_aim_ball()
		AimPhase.FORM:
			if _aim_time >= aim_form_time:
				_aim_phase = AimPhase.AIM
				_aim_time = 0.0
	if _aim_phase == AimPhase.AIM:
		_update_aim_target()


## El cuerpo gira hacia donde apunta el ratón (la mirada de la cámara, aplanada):
## así el personaje "mira" hacia donde va a salir la habilidad.
func _look_toward_aim(delta: float) -> void:
	var dir := get_aim_direction()
	dir.y = 0.0
	if dir.length_squared() < 0.001:
		return
	dir = dir.normalized()
	var target_yaw := atan2(-dir.x, -dir.z)
	var difference := wrapf(target_yaw - rotation.y, -PI, PI)
	var max_step := deg_to_rad(aim_turn_rate) * delta
	var step := clampf(difference * (1.0 - exp(-aim_turn_smoothing * delta)), -max_step, max_step)
	rotation.y = wrapf(rotation.y + step, -PI, PI)


## Elige el objetivo más alineado con la mirada dentro del alcance y marca ese.
func _update_aim_target() -> void:
	# El origen de la mirada es DONDE ESTA EL AGUA (la mano), no el centro del
	# cuerpo: es de donde sale de verdad el hechizo.
	var origin := get_water_ball_position()
	var dir := get_aim_direction().normalized()
	var best: Node3D = null
	var best_score := -1.0
	for node in get_tree().get_nodes_in_group(WaterAbility.TARGET_GROUP):
		var target := node as Node3D
		if target == null or target == self or not target.is_inside_tree():
			continue
		var center := _aim_center_of(target)
		var to := center - origin
		var distance := to.length()
		if distance > aim_range:
			continue
		var dot := to.normalized().dot(dir)
		if dot < aim_target_cone:
			continue
		# Prefiere lo más alineado; a igualdad, lo más cerca.
		var score := dot - distance * 0.001
		if score > best_score:
			best_score = score
			best = target
	_set_aim_target(best)


func _set_aim_target(target: Node3D) -> void:
	_aim_target = target
	if target == null:
		if _aim_marker != null and is_instance_valid(_aim_marker):
			_aim_marker.visible = false
		return
	_ensure_aim_marker()
	if _aim_marker == null or not is_instance_valid(_aim_marker):
		return
	_aim_marker.global_position = _aim_center_of(target)
	_aim_marker.visible = true


func _aim_center_of(target: Node3D) -> Vector3:
	if target.has_method("get_hit_center"):
		var center: Variant = target.call("get_hit_center")
		if center is Vector3 and (center as Vector3).is_finite():
			return center
	return target.global_position + Vector3.UP * 1.0


## Anillo naranja que flota sobre el objetivo enganchado. Se crea una sola vez.
func _ensure_aim_marker() -> void:
	if _aim_marker != null and is_instance_valid(_aim_marker):
		return
	var marker := MeshInstance3D.new()
	var ring := TorusMesh.new()
	ring.inner_radius = 0.30
	ring.outer_radius = 0.42
	marker.mesh = ring
	marker.rotation_degrees.x = 90.0
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.95, 0.35, 0.22)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.42, 0.25)
	mat.emission_energy_multiplier = 2.0
	marker.material_override = mat
	marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	marker.visible = false
	var host := get_parent()
	if host == null:
		host = self
	host.add_child(marker)
	_aim_marker = marker


## Crea el agua que se junta en la MANO durante el apuntado (fase FORM).
##
## [o] NO se crea al pedir el apuntado: si se creara en el mismo fotograma en que
## se pulsa F, el balón aparecería de golpe, sin animación. Primero el personaje
## se prepara (PREPARE) y solo cuando empieza a formarse el agua (FORM) nace el
## balón, que termina de crecer justo cuando empieza a apuntar (AIM). Así la
## creación va acompasada con la animación en vez de ser instantánea.
func _spawn_aim_ball() -> void:
	_clear_aim_ball()
	if not is_inside_tree():
		return
	var host := get_parent()
	if host == null:
		host = self
	var node := ChargeBallScript.new() as Node3D
	if node == null:
		return
	node.set("player", self)
	# Crece durante FORM: acaba justo al empezar a apuntar.
	node.set("duration", maxf(aim_form_time, 0.05))
	node.set("underwater", is_underwater())
	node.set("radius", aim_ball_radius)
	host.add_child(node)
	_aim_ball = node


## Suelta el agua que estaba junta (el balón se abre y desaparece).
func _clear_aim_ball() -> void:
	if _aim_ball != null and is_instance_valid(_aim_ball):
		_aim_ball.call("release")
	_aim_ball = null


## Posición del agua junta en las manos (para que las habilidades nazcan ahí).
## ORIGEN de todo lo que el personaje lanza: la MANO que sostiene el agua.
##
## [!] No es la posicion del nodo del agua, es el HUESO. El nodo es solo el
## dibujo: se crea sin colocar (en el origen del mundo) y se coloca en su primer
## fotograma, asi que leer su transform el mismo fotograma en que nace devuelve
## (0,0,0). Como el gestor de habilidades suelta el hechizo en ese mismo
## fotograma, las habilidades nacian en el origen del mundo: parecia que salian
## del suelo en vez de la mano. El hueso siempre esta bien.
func get_aim_origin() -> Vector3:
	return get_water_ball_position()


## Punto del mundo al que apunta la reticula: donde tiene que caer la habilidad.
##
## CAMARA -> CENTRO DE PANTALLA -> RAYCAST -> PUNTO. Si hay un objetivo marcado,
## el punto es EL OBJETIVO (apuntar a un enemigo tiene que dar en el enemigo);
## si no, el rayo de la camara visto por el centro de la pantalla.
func get_aim_point() -> Vector3:
	if _aim_target != null and is_instance_valid(_aim_target):
		return _aim_center_of(_aim_target)
	var from := global_position + Vector3.UP * 1.4
	if camera_rig != null:
		# El pivote de la camara esta sobre el mismo eje que la camara, asi que el
		# rayo desde aqui y el que sale por el centro de la pantalla son LA MISMA
		# recta: no hace falta ir a buscar el nodo de la camara.
		from = camera_rig.global_position
	var dir := get_aim_direction().normalized()
	var space := get_world_3d().direct_space_state
	if space != null:
		var query := PhysicsRayQueryParameters3D.create(from, from + dir * aim_range)
		query.exclude = [get_rid()]
		query.collide_with_areas = false
		var hit := space.intersect_ray(query)
		if hit.has("position"):
			return hit["position"] as Vector3
	return from + dir * aim_range


## DIRECCION del hechizo: desde la MANO hasta el punto apuntado. La camara decide
## HACIA DONDE se apunta; la habilidad sale de la mano. No es la direccion de la
## camara a secas: apuntando a un enemigo cercano, esa pasaba por encima o por
## debajo de el.
func get_aim_shot_direction() -> Vector3:
	var to := get_aim_point() - get_aim_origin()
	if to.length_squared() < 0.0001:
		return get_aim_direction()
	return to.normalized()


## SITIO de la bola que el personaje sostiene: es el mismo ancla de la mano.
func get_aim_ball_position() -> Vector3:
	return get_water_ball_position()


## true si el personaje tiene AHORA MISMO la bola de agua en la mano. Sirve para
## saber si el agua se ha ido con un hechizo (no queda bola residual) sin tener que
## contar efectos por el mundo.
func has_aim_ball() -> bool:
	return _aim_ball != null and is_instance_valid(_aim_ball)


## Recibir daño. Esta es la funcion que llamara el sistema de combate.
##   DAMAGE_LIGHT / DAMAGE_HEAD / DAMAGE_SIDE / DAMAGE_HEAVY -> reaccion + aturdimiento
##   DAMAGE_STAGGER     -> tambaleo (aturdimiento largo)
##   DAMAGE_KNOCKDOWN   -> derribo: acaba en el suelo y hay que levantarse
##   DAMAGE_DEATH       -> estado final
## [param from_position] posicion del atacante: el golpe empuja al personaje justo
## en direccion contraria (el "knockback"). Si no se pasa, empuja hacia atras.
## Devuelve true si el golpe ha entrado.
func request_damage(kind: StringName = DAMAGE_LIGHT, from_position: Vector3 = Vector3.INF) -> bool:
	if is_dead:
		return false
	# Ya en el suelo: un golpe normal no vuelve a derribarte; solo el remate.
	if _state == STATE_GROUND:
		if kind == DAMAGE_DEATH:
			_die()
			_apply_knockback(kind, from_position)
			return true
		return false
	match kind:
		DAMAGE_DEATH:
			_die()
		DAMAGE_KNOCKDOWN:
			_stun_timer = 0.0
			start_action(STATE_KNOCKDOWN)
		DAMAGE_STAGGER:
			start_action(STATE_STAGGER)
		DAMAGE_HEAVY:
			start_action(STATE_HIT_HEAVY)
		DAMAGE_SIDE:
			start_action(STATE_HIT_SIDE)
		DAMAGE_HEAD:
			start_action(STATE_HIT_HEAD)
		_:
			start_action(STATE_HIT_LIGHT)
	_apply_knockback(kind, from_position)
	return true


## Empuje del golpe: aleja al personaje de donde vino. Es la mitad de la
## sensacion de un combate: si un golpe no te desplaza, no pesa.
func _apply_knockback(kind: StringName, from_position: Vector3) -> void:
	var speed := float(knockback_speeds.get(String(kind), 0.0))
	if speed <= 0.0:
		return
	var direction := Vector3.ZERO
	if from_position.is_finite():
		direction = global_position - from_position
		direction.y = 0.0
	if direction.length_squared() < 0.0001:
		# Sin atacante (o golpe justo encima): empuja hacia atras.
		direction = global_transform.basis.z
		direction.y = 0.0
	if direction.length_squared() < 0.0001:
		return
	_knockback = direction.normalized() * speed


## Quita el empuje de un golpe (por ejemplo al reaparecer).
func clear_knockback() -> void:
	_knockback = Vector3.ZERO


## Levantarse tras un derribo. Con get_up_on_input = true hay que llamarla.
func request_get_up() -> bool:
	if _state != STATE_GROUND or _action_timer > 0.0:
		return false
	start_action(STATE_GET_UP)
	return true


func _die() -> void:
	is_dead = true
	_action_state = &""
	_action_timer = 0.0
	_stun_timer = 0.0
	_enter_state(STATE_DEATH, true)


## true mientras se ejecuta una accion de un solo tiro.
func is_acting() -> bool:
	return _action_timer > 0.0


## true si el personaje no puede recibir ordenes de movimiento (aturdido, en el
## suelo, levantandose o muerto).
func is_incapacitated() -> bool:
	return is_dead or _stun_timer > 0.0 or _state == STATE_GROUND \
		or _state == STATE_KNOCKDOWN or _state == STATE_GET_UP


func _update_action(delta: float) -> void:
	if _action_timer <= 0.0:
		return
	# Combo: si hay un golpe encolado y el golpe en curso ya ha llegado a su
	# ventana, entra ahora y la cuenta atras se reinicia con el golpe nuevo.
	_try_chain_attack()
	if _action_timer <= 0.0:
		return
	_action_timer -= delta
	if _action_timer > 0.0:
		return
	# La accion ha terminado: se decide que pasa despues.
	var finished := _action_state
	_action_state = &""
	# Un golpe encolado que llego justo al final del anterior tampoco se pierde:
	# sale como siguiente golpe del combo. Si no hay nada encolado, el combo
	# termina y el proximo clic vuelve a empezar por el primer golpe.
	if _is_attack_state(finished) and _attack_queued:
		_attack_queued = false
		_start_attack(_queued_attack_state)
		_queued_attack_state = &""
		return
	_attack_queued = false
	_queued_attack_state = &""
	_combo_index = 0
	if finished == STATE_KNOCKDOWN:
		_ground_timer = 0.0
	elif _is_damage_state(finished):
		# Tras un golpe el personaje queda aturdido: la recuperacion no es
		# instantanea, tiene que pasar por el estado "recovery".
		_stun_timer = maxf(_stun_timer, stagger_recovery_time if finished == STATE_STAGGER else recovery_time)


func _is_damage_state(state: StringName) -> bool:
	return state == STATE_HIT_LIGHT or state == STATE_HIT_HEAD \
		or state == STATE_HIT_SIDE or state == STATE_HIT_HEAVY or state == STATE_STAGGER


# -----------------------------------------------------------------------------
#  Agacharse
# -----------------------------------------------------------------------------
## Agacharse y levantarse, con la capsula de colision acompasada.
##
## Si hay algo encima (un techo), al soltar la tecla NO se levanta: se queda
## agachado hasta que haya sitio. Es lo que pide el punto de "no poder levantarse
## con un obstaculo encima".
func _update_crouch(delta: float) -> void:
	# Nadando no se agacha: CTRL sirve para hundirse. Si se venia agachado, esto
	# devuelve la capsula a su altura normal.
	var wants := Input.is_action_pressed("crouch") and not is_dead \
		and not is_incapacitated() and not is_in_water_physics()
	if not wants and is_crouching and not _can_stand_up():
		wants = true
	is_crouching = wants
	var target := 1.0 if is_crouching else 0.0
	_crouch_amount = move_toward(_crouch_amount, target, delta / maxf(crouch_transition_time, 0.0001))
	_apply_crouch_shape()


func _apply_crouch_shape() -> void:
	if _shape == null:
		return
	var capsule := _shape.shape as CapsuleShape3D
	if capsule == null:
		return
	# El radio y los dos hemisferios no se tocan; lo que se acorta es el cilindro
	# central, que es lo que hace la capsula "mas baja" sin cambiar de forma.
	var crouched := maxf(crouch_height, capsule.radius * 2.0 + 0.01)
	var height := lerpf(_standing_height, crouched, _crouch_amount)
	if not is_equal_approx(capsule.height, height):
		capsule.height = height
	# Los pies se quedan donde estaban (el origen del jugador esta en el suelo),
	# asi que el centro de la capsula baja la mitad de lo que se ha acortado.
	_shape.position.y = _standing_center_y - (_standing_height - height) * 0.5


## true si hay sitio para ponerse de pie. Se comprueba con un rayo hacia arriba
## de la altura que tendria la capsula de pie.
func _can_stand_up() -> bool:
	if not block_stand_up_under_ceiling or _shape == null or not is_inside_tree():
		return true
	var space := get_world_3d().direct_space_state
	if space == null:
		return true
	var from := global_position + Vector3.UP * 0.05
	var to := global_position + Vector3.UP * _standing_height
	var query := PhysicsRayQueryParameters3D.create(from, to, collision_mask, [get_rid()])
	return space.intersect_ray(query).is_empty()


## Estado actual del personaje (idle/walk/run/jump/fall/landing/crouch/...
## y los de daño: hit_light, stagger, knockdown, ground, get_up, death).
func get_state() -> StringName:
	return _state


## Cambia el modelo visual en caliente y vuelve a conectar las animaciones.
## Ejemplo:  player.swap_model(tu_modelo.instantiate())   # tu_modelo se carga con load()
func swap_model(new_model: Node3D) -> void:
	if model == null or new_model == null:
		return
	model.set_model(new_model)
	if animation_controller != null:
		animation_controller.refresh_after_model_change()


# -----------------------------------------------------------------------------
#  Movimiento
# -----------------------------------------------------------------------------
func _read_input() -> void:
	var raw := Input.get_vector("move_left", "move_right", "move_back", "move_forward")
	_input_raw = raw
	if camera_rig != null:
		# Movimiento relativo a la camara: "adelante" es hacia donde mira.
		_input_direction = camera_rig.get_movement_direction(raw)
	else:
		var body_basis := global_transform.basis
		var forward := -body_basis.z
		var right := body_basis.x
		forward.y = 0.0
		right.y = 0.0
		_input_direction = (right.normalized() * raw.x + forward.normalized() * raw.y).normalized()

	if run_toggle_mode:
		# Alternar: cada pulsacion cambia entre caminar y correr.
		if Input.is_action_just_pressed("run"):
			is_running = not is_running
	else:
		# Mantener: correr solo mientras Shift este pulsado.
		is_running = Input.is_action_pressed("run")

	# Levantarse del suelo. Se mira ANTES que nada porque tumbado el personaje
	# esta "incapacitado" y no lee el resto de las ordenes.
	if _state == STATE_GROUND:
		if Input.is_action_just_pressed("jump") or Input.is_action_just_pressed("dodge"):
			request_get_up()
		return

	# Aturdido, derribado, levantandose o muerto: no acepta ordenes.
	if is_incapacitated():
		return

	# Ataque basico: CLIC IZQUIERDO -> attack (Punching), CLIC DERECHO -> attack_2
	# (Cross Punch). Cada boton lanza SIEMPRE su golpe (no alternan), y si ya
	# estabas golpeando el siguiente se encadena respetando ese mismo boton.
	# CLIC IZQUIERDO: inicia y ENCADENA el combo. A proposito NO manda un golpe
	# concreto: el sistema elige la mano que toca segun el paso del combo (ver
	# _start_attack), asi que dar clics seguidos da golpe 1 -> 2 -> 3 -> 4
	# alternando manos, sin que el jugador tenga que saber cual toca.
	if Input.is_action_just_pressed("attack"):
		request_attack()
	# CLIC DERECHO: NO es "la otra mano" del combo (eso lo decide el paso actual).
	# Queda reservado al golpe cruzado suelto, para lanzarlo a proposito.
	if Input.is_action_just_pressed("attack_right"):
		request_attack(attack_state_2)
	if Input.is_action_just_pressed("dodge"):
		request_dodge()

	# Habilidades de agua (teclas 1, 2, 3 y 4). Funcionan EN TIERRA Y EN EL AGUA:
	# es justo lo que pide el diseño del personaje acuatico. Quien decide si se
	# puede lanzar es el gestor (enfriamientos y estados), no esto.
	for i in ABILITY_STATES.size():
		if Input.is_action_just_pressed("ability_%d" % (i + 1)):
			request_ability(i + 1)

	# --- Apuntado con balón de agua (MANTENER F) -----------------------------
	# Al mantener: PREPARAR (sube las manos) -> FORMAR (crece el agua) -> APUNTAR
	# (retícula, giro con el ratón, selección de objetivo). Al soltar se deshace
	# sin lanzar nada. Se usan los FLANCOS (pulsar / soltar), no el estado
	# "mantenido": así apuntar sigue en pie aunque se pida por código (pruebas).
	if Input.is_action_just_pressed("aim"):
		request_aim()
	if Input.is_action_just_released("aim"):
		stop_aim()

	# --- Teclas propias del AGUA --------------------------------------------
	# Caminar SOBRE la superficie: se alterna, y solo tiene sentido desde el agua
	# (nadando). El sistema mantiene al personaje encima de la superficie.
	if Input.is_action_just_pressed("surface_walk"):
		if _surface_walk_on:
			_surface_walk_on = false
		elif water_mode == WaterMode.SURFACE or water_mode == WaterMode.SUBMERGED:
			if _water_column_depth() >= surface_walk_min_depth:
				_surface_walk_on = true
	# Salir del agua por el BORDE: ESPACIO cuando hay un borde delante al que se
	# puede subir. Completa la cadena SUMERGIDO -> SUPERFICIE -> BORDE -> SALIDA ->
	# TIERRA sin depender de una rampa.
	if Input.is_action_just_pressed("jump") and water_detection != null \
			and water_detection.is_in_water() and _climb_cooldown <= 0.0 \
			and water_mode != WaterMode.FLOOR and water_mode != WaterMode.SURFACE_WALK \
			and water_mode != WaterMode.CLIMBING:
		var ledge := _find_ledge()
		if ledge.is_finite():
			_start_climb(ledge)

	# Teclas de prueba del sistema de daño (ver los controles en la cabecera).
	if Input.is_action_just_pressed("debug_hit"):
		request_damage(DAMAGE_LIGHT)
	if Input.is_action_just_pressed("debug_side"):
		# Golpe lateral: se simula un atacante justo al lado.
		request_damage(DAMAGE_SIDE, global_position + global_transform.basis.x * -1.2)
	if Input.is_action_just_pressed("debug_heavy"):
		request_damage(DAMAGE_HEAVY)
	if Input.is_action_just_pressed("debug_head"):
		request_damage(DAMAGE_HEAD)
	if Input.is_action_just_pressed("debug_knockdown"):
		request_damage(DAMAGE_KNOCKDOWN)
	if Input.is_action_just_pressed("debug_death"):
		request_damage(DAMAGE_DEATH)


func _update_timers(delta: float) -> void:
	if Input.is_action_just_pressed("jump"):
		_jump_buffer = jump_buffer_time
	else:
		_jump_buffer = maxf(_jump_buffer - delta, 0.0)

	if is_on_floor():
		_coyote_timer = coyote_time
		_air_time = 0.0
	else:
		_coyote_timer = maxf(_coyote_timer - delta, 0.0)
		_air_time += delta

	# Esprintar: mantener Shift. Se pasa a esprintar despues de sprint_delay
	# segundos corriendo de verdad, asi que la progresion correr -> esprintar es
	# continua y no un cambio brusco al pulsar la tecla.
	if is_running and is_on_floor() and not is_crouching and move_speed > walk_speed + 0.1:
		_sprint_timer += delta
	else:
		_sprint_timer = 0.0
	is_sprinting = is_running and _sprint_timer >= sprint_delay


func _apply_gravity(delta: float) -> void:
	if is_on_floor():
		return
	velocity.y -= gravity * delta
	velocity.y = maxf(velocity.y, -max_fall_speed)


## Mueve la velocidad HORIZONTAL hacia su objetivo. Las dos constantes que
## gobiernan el tacto (aceleracion y frenado) entran por PARAMETRO en vez de
## leerse de las de tierra: asi el mismo bloque sirve para andar por tierra
## (acceleration/deceleration), para el fondo de la piscina (mas frenado, hay
## agua) y para caminar sobre la superficie, sin duplicar la logica de empujones,
## esquivas y ataques.
func _apply_horizontal_movement(delta: float, rate: float, brake: float) -> void:
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)

	# Empuje de un golpe (knockback): arrastra al personaje y se va frenando. El
	# input no lo puede cancelar mientras dura, y eso es justo lo que hace que un
	# golpe fuerte se note.
	if _knockback.length_squared() > 0.0004:
		# El empuje se frena por su cuenta: NO se lee de la velocidad actual, o se
		# alimentaria a si mismo y el personaje se quedaria deslizandose siempre.
		_knockback = _knockback.move_toward(Vector3.ZERO, deceleration * delta)
		horizontal = Vector3(_knockback.x, 0.0, _knockback.z)
		velocity.x = horizontal.x
		velocity.z = horizontal.z
		move_speed = horizontal.length()
		return

	# Impulso de esquiva: mientras dura manda el, no el input.
	if _dodge_timer > 0.0:
		_dodge_timer = maxf(_dodge_timer - delta, 0.0)
		horizontal = _dodge_direction * dodge_speed * dodge_move_multiplier
		velocity.x = horizontal.x
		velocity.z = horizontal.z
		move_speed = horizontal.length()
		return

	var moving := _input_direction.length_squared() > 0.001 and not is_incapacitated()
	if moving:
		var target_speed := _target_move_speed()
		# Durante un ataque/golpe el personaje sigue moviendose, pero mas lento:
		# no se convierte en una imagen estatica.
		if _action_timer > 0.0:
			# El desplazamiento depende del golpe: el cierre del combo empuja mas.
			target_speed *= finisher_move_multiplier if _combo_finisher else attack_move_multiplier
		horizontal = horizontal.move_toward(_input_direction * target_speed, rate * delta)
	else:
		horizontal = horizontal.move_toward(Vector3.ZERO, brake * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z
	move_speed = horizontal.length()


## Velocidad objetivo segun el estado: agachado, andando, corriendo o esprintando,
## y ademas frenada por el agua segun el MODO en el que se este. Cada valor
## coincide con la velocidad natural de su clip (ver clip_speeds).
func _target_move_speed() -> float:
	var speed := walk_speed
	if is_crouching:
		speed = crouch_speed
	elif is_running:
		speed = sprint_speed if is_sprinting else run_speed
	match water_mode:
		WaterMode.WADING:
			# Vadear: el agua por debajo de la cintura no deja nadar, pero frena.
			speed *= wade_speed_factor
		WaterMode.ENTERING, WaterMode.CLIMBING:
			speed *= water_transition_speed_factor
		WaterMode.FLOOR:
			# Sobre el fondo de la piscina el personaje acuatico NO va lastrado:
			# ese es su medio, asi que se mueve mas rapido que un banyista normal
			# y con SHIFT CORRE por el fondo (carrera acuatica) en vez de quedar
			# limitado a un paseo lento.
			speed = floor_run_speed if is_running else floor_walk_speed
	if _aiming and not is_crouching:
		# Locomoción CON BALÓN: mientras se carga el balón de agua en las manos se
		# anda/corre más despacio (se lleva peso en las manos). El balón, en
		# cambio, sigue pegado a las manos, que es la gracia de esta postura.
		#
		# AGACHADO NO SE FRENA: agacharse ya va lento (crouch_speed) y el clip de
		# agachado con bola es un ciclo de 1.3 m/s; multiplicarlo por 0.8 dejaba el
		# clip a la mitad de su velocidad y el paso se arrastraba.
		speed *= aim_move_factor
	return speed


func _try_jump() -> void:
	if is_dead or is_crouching or _stun_timer > 0.0:
		return
	if _state == STATE_GROUND or _state == STATE_KNOCKDOWN or _state == STATE_GET_UP:
		return
	if _jump_buffer <= 0.0:
		return
	if not is_on_floor() and _coyote_timer <= 0.0:
		return
	_jump_buffer = 0.0
	_coyote_timer = 0.0
	velocity.y = sqrt(2.0 * gravity * jump_height)
	_enter_state(STATE_JUMP)


func _look_toward_movement(delta: float) -> void:
	# Tumbado, aturdido o levantandose no se gira: el cuerpo lo manda la animacion.
	if is_incapacitated():
		return
	# Apuntando, el cuerpo mira hacia donde apunta la retícula (manda el ratón),
	# no hacia donde se anda: así las habilidades salen hacia donde se apunta.
	if _aiming and _aim_phase == AimPhase.AIM:
		_look_toward_aim(delta)
		return
	# Nadando hacia atras (tecla S) el personaje NO se gira: se desplaza de
	# espaldas, que es lo natural en el agua. Con A/D si gira, porque ahi el
	# movimiento es lateral y la brazada tiene que acompanarlo.
	if _swimming and _swim_moving_backwards():
		return
	var direction := _facing_direction()
	if direction.length_squared() < 0.001:
		return
	# El personaje mira hacia -Z en su espacio local (forward de Godot).
	var target_yaw := atan2(-direction.x, -direction.z)
	var difference := wrapf(target_yaw - rotation.y, -PI, PI)
	# Suavizado exponencial (independiente del framerate) CON tope de velocidad
	# angular: el giro es progresivo y acompana al movimiento, pero un cambio de
	# 180 grados nunca se resuelve en un fotograma.
	var max_step := deg_to_rad(turn_rate) * delta
	var step := clampf(difference * (1.0 - exp(-turn_smoothing * delta)), -max_step, max_step)
	rotation.y = wrapf(rotation.y + step, -PI, PI)


## Direccion a la que debe mirar el personaje.
## Si ya se esta desplazando usa la direccion REAL del movimiento, asi el giro
## acompana la curva de aceleracion en vez de saltar al cambiar de tecla.
## Parado usa la direccion pedida, para orientarse al arrancar.
func _facing_direction() -> Vector3:
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	if horizontal.length() > 0.5:
		return horizontal.normalized()
	return _input_direction


# -----------------------------------------------------------------------------
#  Estado y animacion
# -----------------------------------------------------------------------------
func _update_state(delta: float) -> void:
	# 0) Muerto: es un estado final, no se sale de el.
	if is_dead:
		_enter_state(STATE_DEATH)
		return

	# 0b) AGUA: mientras la fisica del agua mande (nadar, fondo, superficie) o haya
	#     una transicion de entrada/salida, mandan los estados de agua. Ni
	#     gravedad, ni aterrizaje, ni estados de tierra.
	if is_in_water_physics() or _water_transition_timer > 0.0:
		_update_water_state()
		return

	# 1) Derribado. La animacion de derribo manda mientras dure; al terminar se
	#    queda en el suelo ("ground") hasta que toque levantarse. Nunca se vuelve
	#    a la locomocion directamente: hay que pasar por levantarse.
	if _state == STATE_KNOCKDOWN:
		if _action_timer > 0.0:
			return
		_enter_state(STATE_GROUND, true)
		return
	if _state == STATE_GROUND:
		_ground_timer += delta
		_enter_state(STATE_GROUND)
		if get_up_on_input:
			return
		if _ground_timer >= ground_time:
			request_get_up()
		return
	if _state == STATE_GET_UP and _action_timer > 0.0:
		# Terminando de levantarse: al acabar el clip sigue el flujo normal.
		return

	# 2) Aturdido tras un golpe (o todavia desplazado por su empuje): no recupera
	#    el control hasta que se le pasa. Es lo que evita la recuperacion
	#    instantanea: mientras el golpe te esta moviendo, la animacion de
	#    recuperacion sigue puesta en vez de saltar a andar.
	if _stun_timer > 0.0 or _knockback.length_squared() > 0.0004:
		_stun_timer = maxf(_stun_timer - delta, 0.0)
		if _action_timer <= 0.0:
			_enter_state(STATE_RECOVERY)
		return

	# 3) Accion de un solo tiro en curso (ataque/esquiva/golpe): manda ella.
	if _action_timer > 0.0:
		if not is_on_floor():
			# si se cae mientras actua, manda la fisica
			_action_timer = 0.0
			_action_state = &""
		else:
			_enter_state(_action_state)
			return

	# 4) Aterrizaje en curso. Se respeta su animacion, pero se puede CORTAR: si el
	#    jugador ya esta pidiendo moverse y ha pasado el minimo, el aterrizaje se
	#    cancela y la mezcla entra directa a andar/correr. Sin esto habia que
	#    tragarse media animacion de caida antes de poder andar, y el personaje se
	#    sentia pesado justo al tocar suelo.
	if _landing_timer > 0.0:
		_landing_timer -= delta
		var cut := _landing_timer > 0.0 and is_on_floor() \
			and _landing_elapsed() >= landing_min_time \
			and _input_direction.length_squared() > 0.001
		if _landing_timer > 0.0 and not cut:
			return
		if cut:
			_landing_timer = 0.0

	# 5) En el aire
	if not is_on_floor():
		_enter_state(STATE_JUMP if velocity.y > 0.0 else STATE_FALL)
		return

	# 6) Acaba de tocar el suelo tras una caida o un salto
	if _air_time > min_air_time_for_landing and _landing_timer <= 0.0 and _state != STATE_LANDING:
		_air_time = 0.0
		_landing_timer = _landing_duration()
		_enter_state(STATE_LANDING)
		return

	# 7) En el suelo: idle / walk / run / agachado.
	_air_time = 0.0
	_enter_state(_ground_locomotion_state())


## Estado de locomocion que corresponde a la velocidad REAL del personaje.
##
## Se elige por velocidad y no por la tecla pulsada: asi la progresion
## idle -> walk -> run sale sola de la curva de aceleracion (y al reves al
## frenar). La histeresis evita que el estado parpadee cuando la velocidad se
## queda justo en un limite.
##
## DOS COSAS QUE **NO** SE HACEN AQUI, y son a proposito. Cada una era un estado
## intermedio que se colaba en los cambios de direccion:
##
##  1) NO se vuelve a idle solo porque la velocidad cruce el cero. En CUALQUIER
##     cambio de direccion la velocidad pasa por cero (frena y vuelve a
##     acelerar), asi que mirar solo la velocidad metia un idle de 2-3
##     fotogramas en medio del giro. Se para de verdad solo cuando NO se pide
##     movimiento (soltar las teclas) y el cuerpo ya se ha frenado.
##
##  2) NO hay estado de andar hacia atras EN TIERRA. El personaje gira para
##     encarar su direccion de avance (_look_toward_movement), asi que mientras
##     gira, la velocidad apunta al lado contrario de la mirada: comparar
##     velocidad contra mirada daba "va hacia atras" y metia el clip de retroceso
##     (otro pack, otra postura) justo en mitad de cada giro de 180 grados, que
##     es la "postura de guardia" que se veia un instante. Retroceder en tierra no
##     es un estado: es un giro que se resuelve andando. En el agua SI existe
##     (swim_back: nadar de espaldas), y ese no se toca.
func _ground_locomotion_state() -> StringName:
	var quiere_moverse := _input_direction.length_squared() > 0.001
	# Parado de verdad: ni se pide movimiento ni el cuerpo sigue deslizandose.
	if not quiere_moverse and move_speed < idle_speed_threshold:
		if is_crouching:
			return STATE_CROUCH_IDLE
		# APUNTANDO: en vez del reposo normal, la postura de SOSTENER el agua. Va
		# aqui y no en un caso aparte porque apuntar parado es, para la
		# locomocion, un "reposo" mas: asi entrar y salir del modo F no rompe la
		# eleccion de estado por velocidad (andar apuntando sigue siendo walk/run).
		return STATE_AIM_HOLD if _aiming else STATE_IDLE
	# APUNTANDO Y EN MOVIMIENTO: la locomocion con la bola en la mano se elige por
	# la DIRECCION DEL INPUT RESPECTO AL PERSONAJE, no por velocidad. Estando
	# apuntando el cuerpo sigue encarado al objetivo, asi que lo que hay que saber
	# es hacia donde se desplaza respecto a SU cuerpo (ver _aim_locomotion_state).
	if _aiming:
		return _aim_locomotion_state()
	if is_crouching:
		return STATE_CROUCH_WALK
	var walk_run := (walk_speed + run_speed) * 0.5
	var h := locomotion_hysteresis
	match _state:
		STATE_WALK:
			return STATE_RUN if move_speed > walk_run + h else STATE_WALK
		STATE_RUN:
			return STATE_WALK if move_speed < walk_run - h else STATE_RUN
		_:
			# Desde parado (o desde otro estado): limites normales.
			return STATE_RUN if move_speed >= walk_run else STATE_WALK


## Locomocion CON LA BOLA EN LA MANO (modo F, "Water Aim").
##
## Se elige por la DIRECCION DEL INPUT RELATIVA AL PERSONAJE -- ni por la camara
## ni por la velocidad -- porque mientras apunta el cuerpo esta encarado al
## objetivo MIENTRAS se desplaza: lo que importa no es hacia donde va en el mundo,
## sino hacia donde se mueve RESPECTO A SU CUERPO (andar de lado es un paso
## lateral, no un giro). Por eso la direccion se mide en el sistema local.
##
## MAPA DE CLIPS (solo los que EXISTEN en el pack de ataques; los huecos llevan un
## FALLBACK declarado, sin inventar ningun clip):
##   adelante andando    -> walk               (NO hay clip con bola: el paseo normal)
##   atras andando       -> aim_walk_back      (Standing Walk Back)
##   derecha andando     -> aim_walk_right     (Standing Walk Right)
##   izquierda andando   -> aim_walk_right     (FALLBACK: no hay lateral izquierda;
##                                              el mismo paso lateral hacia el otro
##                                              lado se lee igual)
##   adelante corriendo  -> aim_run_forward    (Standing Sprint Forward)
##   atras corriendo     -> aim_run_back       (Standing Run Back)
##   izquierda corriendo -> aim_run_left       (Standing Run Left)
##   derecha corriendo   -> aim_run_forward    (FALLBACK: no hay carrera lateral derecha)
##   agachado adelante   -> aim_crouch_forward (Crouch Walk Forward)
##   agachado atras      -> aim_crouch_back    (Crouch Walk Back)
##   agachado de lado    -> aim_crouch_forward (FALLBACK: no hay lateral agachado)
##
## La BOLA no depende de nada de esto: va pegada al hueso de la mano, asi que sigue
## en la mano (y apuntando) en todos y cada uno de estos estados.
func _aim_locomotion_state() -> StringName:
	var local := _aim_local_input()
	var atras := local.z > aim_back_threshold
	var derecha := local.x > aim_side_threshold
	var izquierda := local.x < -aim_side_threshold
	if is_crouching:
		return AIM_CROUCH_BACK if atras else AIM_CROUCH_FORWARD
	if is_running:
		if atras:
			return AIM_RUN_BACK
		if izquierda:
			return AIM_RUN_LEFT
		if derecha:
			return AIM_RUN_RIGHT
		return AIM_RUN_FORWARD
	# Andando: los clips que existen, cada uno en su direccion. El orden manda en
	# las DIAGONALES: ir hacia atras tiene prioridad sobre el lateral (retroceder
	# en diagonal es, sobre todo, retroceder), y si no, manda el lateral.
	if atras:
		return AIM_WALK_BACK
	if derecha or izquierda:
		return AIM_WALK_RIGHT
	# HACIA ADELANTE: clip PROPIO del pack (Standing Walk Forward). Ya no hay
	# ningun fallback a la caminata normal: el personaje anda con la bola en la
	# mano con su propia animacion.
	return AIM_WALK_FORWARD


## Direccion del input en el SISTEMA LOCAL DEL PERSONAJE: +x es su derecha, -z es
## hacia donde mira. Normalizada, y Vector3.ZERO si no se pide movimiento. Es la
## base para elegir la animacion de desplazamiento con la bola.
func _aim_local_input() -> Vector3:
	if _input_direction.length_squared() <= 0.001:
		return Vector3.ZERO
	var local: Vector3 = global_transform.basis.inverse() * _input_direction
	local.y = 0.0
	if local.length_squared() <= 0.000001:
		return Vector3.ZERO
	return local.normalized()


func _enter_state(new_state: StringName, force: bool = false) -> void:
	if new_state == _state and not force:
		return
	_state = new_state
	if animation_controller != null:
		animation_controller.play_state(new_state, force)
	state_changed.emit(new_state)


## Mantiene los pasos sincronizados con la velocidad real: la animacion se
## reproduce a velocidad_real / velocidad_natural_del_clip, asi que los pies no
## patinan ni al arrancar, ni a velocidad intermedia, ni al ir a tope.
## Solo se aplica a los estados de locomocion (los demas van a 1:1).
func _update_animation_speed() -> void:
	if animation_controller == null:
		return
	var reference := clip_speed_for(_state)
	animation_controller.set_locomotion_speed_factor(
		move_speed / reference if reference > 0.0 else 1.0
	)


## Velocidad natural (m/s) del clip de un estado. 0.0 si ese estado no es de
## locomocion (entonces no se toca la velocidad de reproduccion).
func clip_speed_for(state: StringName) -> float:
	return float(clip_speeds.get(String(state), 0.0))


func _landing_duration() -> float:
	if animation_controller == null:
		return fallback_landing_duration
	var length := animation_controller.get_state_length(STATE_LANDING)
	return length if length > 0.0 else fallback_landing_duration


## Cuanto lleva reproducido el aterrizaje en curso (s).
func _landing_elapsed() -> float:
	return maxf(_landing_duration() - _landing_timer, 0.0)


## Duracion (s) del clip de un estado, o [param fallback] si no se encuentra.
func _state_length(state: StringName, fallback: float) -> float:
	if animation_controller == null:
		return fallback
	var length := animation_controller.get_state_length(state)
	return length if length > 0.0 else fallback
