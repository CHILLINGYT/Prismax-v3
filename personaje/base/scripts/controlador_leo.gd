class_name ControladorLeo
extends CharacterBody3D

# Jugador principal del mundo: Leo (forma humana) <-> Velocista (transformación).
#
# Un ÚNICO CharacterBody3D sostiene las dos formas. Sólo cambia lo que se ve
# (modelo humano o modelo velocista) y las capacidades asociadas. La posición,
# el cuerpo físico, la colisión y la cámara son los mismos en ambas formas.
#
# La forma VELOCISTA reutiliza TAL CUAL los sistemas ya existentes de
# personaje/transformaciones/velocidad/: EfectosVelocidad, CapaVelocidad (shader), SistemaCombate,
# TrazadorRuta, RayosVelocidad y la cámara CamaraZiba. La lógica de estados
# (dash, caída-dash, carga de poder, supervelocidad, combate, emote) es la del
# prototipo ziba/scripts/jugador.gd, portada aquí sin cambiar su comportamiento.
#
# La forma HUMANA usa el modelo y las animaciones propias de Leo
# (personaje/transformaciones/humano/), con movimiento/correr/salto y las acciones del proyecto.

enum Forma { HUMANO, VELOCISTA, ACUATICO, FUERZA, COMBATE }

# Estados del sistema de supervelocidad (idénticos a ziba/scripts/jugador.gd).
enum Estado { NORMAL, DASH, CAIDA_DASH, CARGA, PREPARADO, EJECUCION }

## Emitida al cambiar de forma, con el id de la nueva forma (&"humano"/&"velocista").
## El HUD la usa para actualizar el icono central; el resto del juego no cambia.
signal forma_cambiada(id: StringName)

# ------------------------------------------------------------------ Leo: forma humana
const H_VEL_CAMINAR := 3.0
const H_VEL_CORRER := 5.5
const H_ACELERACION := 40.0
const H_DESACELERACION := 50.0
const H_GRAVEDAD := 24.0
const H_SALTO := 7.5
# A partir de esta velocidad horizontal el salto usa el clip "en carrera".
const H_VELOCIDAD_SALTO_CORRIENDO := 3.5
const H_UMBRAL_MOVIMIENTO := 0.15
const H_MEZCLA := 0.15
# Agacharse (misma mecánica que el Leo original de personaje/transformaciones/humano/escenas/leo.tscn):
# velocidad reducida, no se puede correr ni saltar, y la cámara baja un poco.
const H_VEL_AGACHADO := 2.5
const H_ALTURA_AGACHADO := 0.7
const H_MEZCLA_AGACHARSE := 0.25
# Subida de bordillos de acera: escalón bajo (~15 cm). Altura máxima que el
# controlador intenta subir y avance del sondeo de paso libre (metros).
const ALTURA_ESCALON := 0.26
const AVANCE_ESCALON := 0.40

# --- AGUA (una sola forma nada; las demás se frenan en la orilla) -------------
# La profundidad NO se saca de ninguna superficie ni de un valor fijo: se pide a
# `Relieve.profundidad_agua()`, que la calcula como el nivel del mar menos la cota
# del terreno, es decir, con la MISMA función que genera el mundo. Así el límite
# vale igual en la playa de la ciudad, en una bahía o en cualquier tramo de costa.
## Profundidad (m) de agua que una forma TERRESTRE puede vadear (andar por el
## fondo mojándose los tobillos o las rodillas). Más honda que esto, el fondo ya no
## es transitable a pie: sólo la forma ACUÁTICA puede seguir nadando.
const PROFUNDIDAD_VADEO := 0.55
## Profundidad (m) a partir de la cual la forma ACUÁTICA nada en vez de vadear. Es
## algo mayor que el límite terrestre para que pueda entrar y salir del agua
## caminando por la playa (vadea antes de ponerse a nadar).
const PROFUNDIDAD_NADO := 0.95
## Cota (m) de la superficie VISIBLE del océano: es la del plano de
## res://Agua/Scenes/Ocean.tscn (-2.05), 5 cm por debajo de Relieve.NIVEL_MAR para
## que la línea de costa no quede coplanaria con la malla del terreno. El nado usa
## ESTA cota, de modo que el cuerpo flota donde se ve el agua.
const SUPERFICIE_MAR := -2.05
## Fundido de los clips de agua (entrar/salir) y del nado.
const BLEND_AGUA := 0.22
## Velocidad (m/s) de nado horizontal en superficie y bajo el agua.
const A_VEL_NADO := 4.6
## Aceleración (m/s²) del nado: da inercia de pez, no un cambio de dirección seco.
const A_ACEL_NADO := 6.0
## Velocidad (m/s) de subida/bajada al sumergirse con las teclas de flotar/bucear.
const A_VEL_VERTICAL_NADO := 3.2
## Empuje (m/s²) con el que el agua devuelve el cuerpo a la superficie: es lo que
## hace que el personaje flote y pueda nadar sin hundirse solo.
const A_FLOTABILIDAD := 9.0
## Altura (m) sobre la superficie a la que el cuerpo se estabiliza al flotar: con el
## origen en los pies, deja el agua a la altura del pecho (no "de pie" sobre ella).
const A_CALADO_FLOTANDO := 1.05
## Amortiguación vertical bajo el agua: evita oscilar alrededor de la superficie.
const A_AMORTIGUA_VERTICAL := 4.0
## Velocidad (m/s) de nado RÁPIDO, con SHIFT mantenido mientras se nada de verdad:
## el DOBLE exacto de A_VEL_NADO (4,6 -> 9,2), que es lo que pide un pez que se
## lanza. Afecta SÓLO al nado (y sólo en horizontal), así que en cuanto el cuerpo
## sale del agua SHIFT recupera su significado de siempre (correr en tierra, dash
## en el velocista).
const A_VEL_NADO_RAPIDO := 9.2
## Aceleración (m/s²) del nado rápido: algo mayor que la normal para que el
## empujón del aleteo entre y salga con inercia de pez (ni tirón ni frenada seca).
const A_ACEL_NADO_RAPIDO := 9.0
## Velocidad de frenado (m/s²) al soltar SHIFT nadando: vuelve al nado normal
## desacelerando, no de golpe.
const A_FRENO_NADO_RAPIDO := 6.5
## Golpe acuático (el MISMO botón de ataque, clic izquierdo) mientras se nada o se
## está sumergido: alcance (m) desde el centro del cuerpo, radio (m) de detección,
## daño, empuje y fracción del clip `attack` en la que el golpe conecta de verdad.
## Reutiliza el contrato de daño que ya usan las habilidades de agua.
const A_GOLPE_ALCANCE := 1.1
const A_GOLPE_RADIO := 0.7
const A_GOLPE_DANIO := 10.0
const A_GOLPE_EMPUJE := 4.0
const A_GOLPE_IMPACTO_U := 0.35
## Duración (s) de los clips de entrada y salida del agua (miden 1,90 s en la
## librería). Sólo son transiciones visuales: la lógica de nado manda desde el
## primer fotograma.
const A_T_ENTRADA_AGUA := 1.50
const A_T_SALIDA_AGUA := 1.40
## ESCALERA: velocidad (m/s) a la que la forma acuática trepa. La fase del clip de
## trepada (climb_ladder) va ATADA al progreso del recorrido, así que la animación
## acompaña al movimiento y pies y manos caen siempre en los mismos peldaños.
const E_VEL_ESCALERA := 1.35
## ESCALERA: el avance por ciclo ya NO es una constante del controlador. Cada
## escalera (EscaleraBarco) declara la separación REAL de sus peldaños y cuántos
## avanza el clip por ciclo, y con eso se ata la animación al movimiento; el mismo
## código sirve para la escalera del barco y para la del muelle.
##
## AVISO DE AGUA: texto EXACTO que se muestra cuando una forma terrestre intenta
## meterse en el agua honda y el límite de la orilla la frena (el HUD reutiliza el
## mismo aviso contextual que los mensajes de "Presioná E").
const TEXTO_SIN_AGUA := "Solo puedes ingresar al agua con el personaje acuatico"
## Segundos que permanece el aviso en pantalla. Un intento = un aviso: para que
## vuelva a salir hay que soltar el movimiento y empujar otra vez (así mantener la
## tecla contra la orilla no suelta decenas de mensajes iguales).
const AVISO_AGUA_DURACION := 2.5
# Metro extra de avance sobre el radio de la cápsula: garantiza que el centro del
# cuerpo quede claramente encima de la superficie de destino (no justo en el canto).
const MARGEN_ESCALON := 0.12
# Desnivel mínimo para considerar que hay un escalón real: un borde que sigue a la
# misma cota (la propia calzada) NO es un escalón y no debe subirse.
const DESNIVEL_MINIMO := 0.02

# Clips de la librería de Leo (personaje/transformaciones/humano/animations/leo_animations.tres).
const ANIM_H_IDLE := "idle"
const ANIM_H_WALK := "walk"
const ANIM_H_RUN := "fast_run"
const ANIM_H_SALTO := "jump_up"
const ANIM_H_SALTO_CORRIENDO := "running_jump"
# Clips de agachado: "crouch_walk" ya existe en leo_animations.tres (no se crea nada).
# "crouch_idle" todavía no existe; si falta, se congela la pose de crouch_walk (como en leo.gd).
const ANIM_H_CROUCH_WALK := "crouch_walk"
const ANIM_H_CROUCH_IDLE := "crouch_idle"

# ------------------------------------------- Acuático / Pes: clips propios
# La librería acuática (personaje/transformaciones/acuatica/animations/player_animations.tres)
# se carga como librería "por defecto" del AnimationPlayer del modelo acuático, así
# que sus clips se reproducen por su nombre simple (idle, walk, run, ...). Son los
# clips originales del módulo acuático: NO se renombran ni se sustituyen por los de Leo.
const ANIM_A_IDLE := "idle_stand"
## El reposo TERRESTRE de la forma acuática es ahora "Standing Idle" (clip nuevo,
## aportado en la carpeta temporal "New Animations" y ya integrado en la librería
## definitiva). El antiguo "idle" sigue en la librería, pero ya no es el reposo:
## sólo se usa como último recurso si el clip nuevo faltara.
const ANIM_A_IDLE_RESPALDO := "idle"
const ANIM_A_WALK := "walk"
const ANIM_A_RUN := "run"
const ANIM_A_WALK_BACK := "walk_back"
const ANIM_A_JUMP := "jump"
const ANIM_A_FALL := "fall"
const ANIM_A_CROUCH_IDLE := "crouch_idle"
const ANIM_A_CROUCH_WALK := "crouch_walk"
const ANIM_A_ATTACK := "attack"
# Clips de NATACIÓN del módulo acuático. Ya existían importados en
# personaje/transformaciones/acuatica/animations/player_animations.tres (el
# AnimationPlayer del modelo acuático los carga por su nombre simple, igual que
# los de tierra); antes no se usaban en el juego. Nombres REALES verificados.
const ANIM_A_SWIM_IDLE := "swim_idle"
const ANIM_A_SWIM_FORWARD := "swim_forward"
const ANIM_A_SWIM_BACK := "swim_back"
const ANIM_A_SWIM_UP := "swim_up"
const ANIM_A_SWIM_DOWN := "swim_down"
const ANIM_A_ENTER_WATER := "enter_water"
const ANIM_A_EXIT_WATER := "exit_water"
## TREPADA POR LA ESCALERA (barco y muelle): clip nuevo ("Climbing Ladder" de la
## carpeta temporal "New Animations", ya integrado como climb_ladder.tres en la
## librería acuática). Es un ciclo de trepada EN EL SITIO: el avance lo pone el
## recorrido de la escalera (ver EscaleraBarco) y la fase del clip lo sigue.
const ANIM_A_CLIMB := "climb_ladder"

# ------------------------------------------- Acuático / Pes: 4 habilidades (1-4)
# Tabla única de las cuatro habilidades acuáticas. Reutiliza TAL CUAL los objetos
# de habilidad del módulo (abilities/*.gd): viajan, chocan y hacen daño de verdad a
# cualquier nodo del grupo "damageable", sin depender del Player del módulo.
#   release   segundo del clip en el que sale el efecto (coincide con la pista de
#             método de la animación; aquí sólo es el seguro anti-atasco)
#   carga     radio (m) del agua que se junta en las manos al cargar
const ABIL_AGUA := [
	{
		"nombre": "Proyectil de agua",
		"script": preload("res://personaje/transformaciones/acuatica/abilities/water_projectile.gd"),
		"cooldown": 1.0, "release": 1.3, "carga": 0.34,
		"damage": 12.0, "hit_radius": 0.55, "speed": 18.0, "lifetime": 2.5,
		"knockback": 3.0, "kind": &"light",
	},
	{
		"nombre": "Esfera de agua",
		"script": preload("res://personaje/transformaciones/acuatica/abilities/water_burst.gd"),
		"cooldown": 3.0, "release": 1.85, "carga": 0.42,
		"damage": 8.0, "hit_radius": 0.7, "speed": 12.0, "lifetime": 4.0,
		"knockback": 5.0, "kind": &"heavy",
		"field_radius": 3.2, "field_duration": 2.6,
	},
	{
		"nombre": "Prision de agua",
		"script": preload("res://personaje/transformaciones/acuatica/abilities/water_prison.gd"),
		"cooldown": 5.0, "release": 1.5, "carga": 0.3,
		"damage": 10.0, "hit_radius": 0.9, "speed": 14.0, "lifetime": 3.0,
		"knockback": 0.0, "kind": &"light",
		"trap_duration": 3.0,
	},
	{
		"nombre": "Oleada de agua",
		"script": preload("res://personaje/transformaciones/acuatica/abilities/water_surge.gd"),
		"cooldown": 8.0, "release": 1.62, "carga": 0.55,
		"damage": 45.0, "hit_radius": 2.4, "speed": 7.0, "lifetime": 2.6,
		"knockback": 9.0, "kind": &"heavy",
	},
]

# ------------------------------------------- Fuerza: movimiento y habilidades
# La forma Fuerza reutiliza los scripts/efectos de res://Fuerza/ (Combat, Vfx,
# Rock, Shockwave). En vez de un segundo CharacterBody3D, la lógica vive aquí y
# comparte cuerpo, colisión, cámara y inputs.
# PESADO: anda y corre despacio, con inercia (coincide con el diseño del paquete).
const F_VEL_CAMINAR := 1.6
const F_VEL_CORRER := 4.0
const F_ACELERACION := 12.0
const F_DESACELERACION := 16.0
const F_GRAVEDAD := 25.0
const F_SALTO := 6.5
# Supersalto con carga (mantener ESPACIO en el suelo). Un toque corto conserva
# el salto normal de siempre. Valores heredados del paquete original de Fuerza
# (su gravedad es la MISMA: F_GRAVEDAD = 25, así que el rango 8..21 m/s da las
# mismas alturas de diseño: ~1.3 m al mínimo y ~8.8 m con la carga al tope).
const F_SUPER_CARGA_MIN := 0.25     # s: por debajo, toque corto = salto normal
const F_SUPER_CARGA_MAX := 1.4      # s: carga completa
const F_SUPER_VEL_MIN := 8.0        # m/s al soltar justo pasado el mínimo
const F_SUPER_VEL_MAX := 21.0       # m/s con la carga al tope
const F_SUPER_IMPULSO := 2.0        # empuje horizontal mínimo del despegue
const F_SUPER_SACUDIDA := 0.45      # sacudida de cámara al despegar
const F_SUPER_CAIDA_CAMARA := 0.28  # la cámara baja mientras se carga
const F_SUPER_TEMBLOR := 0.035      # temblor del cuerpo mientras se carga
const F_SUPER_BARRA_LARGO := 220.0  # tamaño del indicador de carga en pantalla
const F_SUPER_BARRA_ALTO := 16.0
# Embestida con el hombro (R).
const F_EMBESTIDA_VEL := 7.0
const F_EMBESTIDA_DUR := 0.5
const F_EMBESTIDA_DANIO := 35.0
const F_EMBESTIDA_RADIO := 1.6
const F_EMBESTIDA_RECUP := 0.3
# Supersalto / pisotón aéreo (E en el aire) con onda expansiva al aterrizar.
const F_SLAM_VEL := 45.0
const F_SLAM_DANIO := 60.0
const F_SLAM_RADIO := 4.5
# Cuerpo a cuerpo (clic izq. = puñetazo / combo, clic der. = patada).
## Daño de referencia del Tanque: la mitad de la vida máxima (60 PV) del enemigo
## estándar de la partida (`EnemigoPrueba`), medido EN EL JUEGO. El golpe básico
## reparte su daño con caída por distancia dentro de su radio (FuerzaCombat:
## lerp(1.0 -> 0.4) según lo lejos del puño que esté el enemigo), así que la
## constante nominal es la que hace llegar ~30 a la distancia de combate normal
## (30 / 0.61 ≈ 49, medido con el enemigo estándar a 1,2 m). No se toca la vida de
## ningún enemigo: uno resistente aguanta más golpes y uno frágil, menos.
const F_DANIO_ENTREGADO := 30.0
const F_CAIDA_IMPACTO := 0.61
const F_DANIO_ESTANDAR := F_DANIO_ENTREGADO / F_CAIDA_IMPACTO
const F_PUNIO_DANIO := F_DANIO_ESTANDAR           # entrega ~30 de 60 PV (la mitad)
const F_PATADA_DANIO := F_DANIO_ESTANDAR * 1.2    # ~36 entregados: algo más
const F_GOLPE_ALCANCE := 1.1
const F_GOLPE_RADIO := 0.7
const F_GOLPE_ALTURA := 1.2
const F_PATADA_ALTURA := 0.9
const F_COMBO_VENTANA := 0.45
# u (fracción del clip) en la que el puño/el pie alcanzan su extensión MÁXIMA,
# medida sobre el propio esqueleto con los clips reales: mano izquierda al
# frente en Punch_Left u=0.23, mano derecha (cross) en Punch_Right u=0.30 y
# pie al frente en Kick u=0.375. El daño de un golpe cae en ese instante.
const F_IMPACTO_U := {
	"Punch_Left": 0.23,
	"Punch_Right": 0.30,
	"Kick": 0.375,
}
# Roca (Q la arranca del suelo frente al personaje / clic izq. la lanza).
const F_ROCA_TAM := 0.8
const F_ROCA_VEL := 17.0
const F_ROCA_DANIO := 80.0
const F_ROCA_RADIO := 3.0
# Agarre de la roca. Estos valores DEBEN coincidir con el horneado de los
# clips de la roca (animations/libraries/FuerzaUniversal.tres: RockLift,
# RockCarry, RockCarryWalk, RockThrow): animación e IK usan exactamente la
# misma fórmula de trayectoria y de puntos de agarre, así que nunca se pelean.
const F_ROCA_CARRY_H := 1.13   # altura del centro sobre la cabeza, en radios
const F_ROCA_Z0 := 0.62        # dónde nace/apoya la roca (esp. esqueleto, +adelante)
const F_ROCA_U_SUBIDA := 0.55  # fase del levantamiento en la que la roca empieza a subir
const F_ROCA_U_FIN := 0.90     # fase en la que termina de subir
const F_ROCA_GUARDA := 0.25    # margen extra alrededor de la cabeza (en radios)
const F_ROCA_SWAY := 0.008     # balanceo lateral al caminar cargada (esp. esqueleto)
const F_ROCA_POLO_SALIDA := 2.2
const F_ROCA_POLO_ABAJO := 0.0
const F_ROCA_POLO_ATRAS := 0.2
# Mira (crosshair) del modo apuntado de la roca: cruz fina con contorno en el
# centro exacto de la pantalla mientras la piedra está arriba, lista para
# lanzar. El punto objetivo sale de un raycast desde el centro de la cámara.
const F_MIRA_LARGO := 11.0        # longitud de cada brazo de la cruz (px)
const F_MIRA_GROSOR := 2.0        # grosor de cada brazo (px)
const F_MIRA_HUECO := 5.0         # hueco central alrededor del punto (px)
const F_MIRA_PUNTO := 3.0         # tamaño del punto central (px)
const F_MIRA_ALCANCE := 60.0      # alcance máximo del raycast de apuntado (m)
const F_MIRA_COLOR := Color(1.0, 1.0, 1.0, 0.92)
const F_MIRA_SOMBRA := Color(0.0, 0.0, 0.0, 0.55)

# Clips de la nueva librería de Fuerza (UniversalLibrary -> FuerzaUniversal.tres).
# Se reproducen por su nombre simple sobre el AnimationPlayer del nodo $Fuerza.
const ANIM_F_IDLE := "Idle"
const ANIM_F_WALK := "Walk"
const ANIM_F_RUN := "Run"
const ANIM_F_JUMP := "Jump"
const ANIM_F_FALL := "Fall"
const ANIM_F_CROUCH := "Crouch"
const ANIM_F_CROUCHWALK := "CrouchWalk"
const ANIM_F_PUNCH_L := "Punch_Left"
const ANIM_F_PUNCH_R := "Punch_Right"
const ANIM_F_KICK := "Kick"
const ANIM_F_AIRSLAM := "AirSlam"
const ANIM_F_SLAMIMPACT := "SlamImpact"
const ANIM_F_ROCKLIFT := "RockLift"
const ANIM_F_ROCKCARRY := "RockCarry"
const ANIM_F_ROCKCARRYWALK := "RockCarryWalk"
const ANIM_F_ROCKTHROW := "RockThrow"
const ANIM_F_CARGA := "Charge"
const ANIM_F_SUPERJUMP := "SuperJump"
const ANIM_F_SHOULDERPREP := "ShoulderPrep"
const ANIM_F_SHOULDERRUN := "ShoulderRun"
const ANIM_F_SHOULDERECOVER := "ShoulderRecover"

# ------------------------------------------- Velocista: supervelocidad (ziba/)
# Animaciones existentes (librerías del AnimationPlayer del modelo velocista).
const ANIM_INACTIVO := "inactivo"
const ANIM_ADELANTE := "caminar_hacia_adelante"
const ANIM_ATRAS := "caminar_hacia_atras"
const ANIM_CARGA := "cargar_poder_click-derecho"
const ANIM_DASH := "dash-con-shift"
const ANIM_SALTO := "jumping up(1)"
const ANIM_SUPERVELOCIDAD := "superduper_velocidad"
const ANIM_INACTIVO_VELOCIDAD := "inactivo_despues-despues-de-30s-velocidad"
const ANIM_COMBO_1 := "combo-1"
const ANIM_COMBO_2 := "combo-2"
const ANIM_COMBO_3 := "combo-3"
const ANIM_COMBO_4 := "combo-4"
const ANIM_MODO_ATAQUE := "inactivo_modo_ataque"
const ANIM_EMOTE := "calentamiento_ataque"

# ------------------------------------------- Combate / Ataque: clips propios
# La forma Combate usa el modelo y las animaciones del módulo de ataque
# (personaje/transformaciones/transformacion ataque/): sus clips originales,
# sin renombrar. El sistema de ataque FreeFlow (SPRINT, ventana de impacto,
# selector contextual de objetivo y buffer de entrada) se reutiliza TAL CUAL
# desde los scripts del módulo: aquí no se copia ni se reinventa nada.
const ANIM_C_IDLE := "combat_idle"
const ANIM_C_IDLE_ALT := "idle"
const ANIM_C_WALK := "walk"
const ANIM_C_JUMP := "jump"
# Movimiento de la forma Combate: constantes REALES del módulo de ataque (su
# scripts/player.gd: walk_speed, acceleration, deceleration, jump_velocity,
# gravity y turn_speed). No se inventan valores nuevos.
const C_VEL_CAMINAR := 6.0
const C_ACELERACION := 30.0
const C_DESACELERACION := 40.0
const C_GRAVEDAD := 22.0
const C_SALTO := 7.0
## Segundo impulso aéreo de la forma Combate (doble salto): algo más suave que
## el salto de suelo, para que no se sienta como un salto infinito.
const C_DOBLE_SALTO := 6.0
const C_GIRO := 14.0
const C_MEZCLA := 0.18
const C_MEZCLA_SALTO := 0.10
const C_UMBRAL_MOVIMIENTO := 0.15
# Referencia de la animación de caminar del módulo (walk_reference_speed, la
# calibración MEDIDA del propio clip: 2.95 m/s) y límites de su escalado (el
# tope 1.4 es el moderado que ya usa la partida para que se vea natural).
const C_REF_VEL_CAMINAR := 2.95
const C_ESCALA_MIN := 0.8
const C_ESCALA_MAX := 1.4

const PlayerAtaque := preload("res://personaje/transformaciones/transformacion ataque/scripts/player.gd")
const CombatTargeting := preload("res://personaje/transformaciones/transformacion ataque/scripts/combat/combat_targeting.gd")
const AttackData := preload("res://personaje/transformaciones/transformacion ataque/scripts/combat/attack_data.gd")
const ComboSystem := preload("res://personaje/transformaciones/transformacion ataque/scripts/combat/combo_system.gd")
## Config por defecto del módulo: se usa cuando la partida no tiene un gestor
## de encuentro (el combate funciona igual, con los MISMOS valores del módulo).
const CONFIG_ATAQUE := preload("res://personaje/transformaciones/transformacion ataque/resources/combat_config.tres")

# Estados del ataque de la forma Combate: los mismos pasos que el módulo
# (FREE/APPROACH/WINDUP/ACTIVE/RECOVERY), integrados en este controlador.
enum C_E { LIBRE, ACERCARSE, PREPARAR, ACTIVO, RECUPERAR }

# Tiempos de blending (idénticos al prototipo).
const BLEND_MARCHA := 0.25
const BLEND_MARCHA_FIN := 0.30
const BLEND_CAMBIO_MARCHA := 0.18
const BLEND_SALTO := 0.10
const BLEND_POST_SALTO := 0.15
const BLEND_DASH := 0.06
const BLEND_POST_DASH := 0.12
const BLEND_CARGA := 0.10
const BLEND_LIBERACION := 0.08
const BLEND_FIN_VELOCIDAD := 0.22
const BLOQUEO_FIN_VELOCIDAD := 0.12
const BLEND_ATAQUE := 0.08
const BLEND_POST_ATAQUE := 0.16
const BLEND_EMOTE := 0.12
# Fundido al entrar/salir de la transformación.
const BLEND_TRANSFORMACION := 0.15

# --- SONIDOS de las acciones del velocista (carga, trazado, dash, golpe) ---
# Offsets MEDIDOS (s) para saltar el silencio DIGITAL de cabecera de los WAV y no
# meter retardo al empezar: golpe ≈0,136 s, trazado ≈0,133 s. Carga y dash no
# tienen silencio de cabeza (arrancan en 0). El archivo original NO se toca.
const AUD_INICIO_TRAZADO := 0.133
const AUD_INICIO_GOLPE := 0.136
# Fin del contenido útil del trazado (sin el silencio de cola), para el bucle.
const AUD_FIN_TRAZADO := 5.477

# --- SONIDOS de las habilidades de FUERZA ---
# Offsets MEDIDOS (s) para saltar el silencio DIGITAL de cabecera de los mp3 y no
# meter retardo al empezar. Medidos reproduciendo cada archivo por el bus
# "Efectos" con captura: salto 0.10, impacto 0.06, agarrapiedra 0.22, piedratirada
# 0.24, golpe 0.06, patada 0.05. El archivo original NO se toca.
const AUD_F_SALTO := 0.10
const AUD_F_IMPACTO := 0.06
const AUD_F_AGARRE := 0.21
const AUD_F_TIRADA := 0.23
const AUD_F_GOLPE := 0.06
const AUD_F_PATADA := 0.05

# Colores del efecto visual de transformación existente.
const COLORES_TRANSFORMACION := {
	&"combate": Color(0.6, 0.1, 1.0, 1.0),
	&"velocista": Color(1.0, 0.035, 0.025, 1.0),
	&"pes": Color(0.015, 0.12, 0.72, 1.0),
	&"tanque": Color(1.0, 0.82, 0.015, 1.0),
	&"aguila": Color(0.22, 0.82, 1.0, 1.0),
}

const TIEMPO_MODO_ATAQUE := 10.0
const FACTOR_MOVILIDAD_ATAQUE := 0.35
const IMPULSO_AVANCE := 4.5
# Ataque del Velocista (antes sólo había animación y afterimages: no quitaba vida).
# Balance de la fase intermedia: el golpe normal quita 7 y el remate del combo algo
# más, nunca el valor antiguo (28). El daño de la supervelocidad es APARTE y no se
# toca en este ajuste. Valores configurables aquí, en un único sitio.
const VEL_ATAQUE_DANIO := 7.0
const VEL_ATAQUE_DANIO_REMATE := VEL_ATAQUE_DANIO * 1.6
const VEL_ATAQUE_IMPACTO := 0.10      # s desde el inicio de la animación al contacto
const VEL_ATAQUE_ALCANCE := 1.9       # m por delante del cuerpo
const VEL_ATAQUE_RADIO := 1.0         # m alrededor del punto de impacto
const VEL_ATAQUE_ALTURA := 1.5        # m de margen vertical
const VEL_ATAQUE_DOT_MIN := 0.15      # sólo golpea lo que tiene delante
const VEL_ATAQUE_EMPUJE := 5.0
## Bit de la capa 5 ("enemigos"): la usan SÓLO los enemigos. La supervelocidad la
## quita TEMPORALMENTE de la máscara del jugador para atravesarlos sin dejar de
## respetar paredes, suelo y límites del mapa (capas 1 y 2).
const CAPA_ENEMIGOS := 16
const VEL_SUPER_DANIO := 5.0
const VEL_SUPER_RADIO := 1.3          # m de barrido alrededor de la trayectoria
const VEL_SUPER_EMPUJE := 18.0
## Aturdimiento de la arremetida: suficiente para que el enemigo no pueda
## contraatacar mientras el Velocista lo atraviesa (estado ya existente).
const VEL_SUPER_ATURDIMIENTO := 0.8
## Indicador del objetivo del FreeFlow: una bolita sobre la cabeza del enemigo
## seleccionado. Un único nodo, creado a demanda y colgado del mundo.
const INDICADOR_RADIO := 0.11
const INDICADOR_COLOR := Color(0.35, 0.95, 1.0, 1.0)
const INDICADOR_ALTURA := 1.45        # m sobre el centro de golpe del enemigo
const INDICADOR_ALTURA_BASE := 2.45   # m sobre su base (si no expone centro de golpe)
const INDICADOR_SUAVIZADO := 14.0     # suavizado del seguimiento (por segundo)
const VENTANA_CONTINUACION := 0.5

@export_group("Forma humana")
@export var h_vel_caminar: float = H_VEL_CAMINAR
@export var h_vel_correr: float = H_VEL_CORRER

@export_group("Movimiento velocista")
@export var velocidad_max: float = 7.0
@export var aceleracion: float = 45.0
@export var desaceleracion: float = 55.0
@export var gravedad: float = 24.0
@export var fuerza_salto: float = 7.5

@export_group("Dash")
@export var distancia_dash: float = 10.0
@export var duracion_dash: float = 0.09
@export var distancia_objetivo_dash: float = 9.0

@export_group("Poder supervelocidad")
@export var vel_trayecto_max: float = 60.0
@export var vel_trayecto_min: float = 34.0

# --- Recorrido del poder (clic derecho) ---
## Radio (m) con el que se da por alcanzado un punto de la ruta.
const TRAYECTO_RADIO_PUNTO := 1.2
## Altura (m) a la que se sondea si hay un muro real delante: a esa altura un
## edificio bloquea, pero un bordillo o un desnivel pequeño no.
const TRAYECTO_ALTURA_MURO := 1.4

var forma: int = Forma.HUMANO
var estado: int = Estado.NORMAL
# Verdadero mientras corre la transición visual al cambiar de forma.
var _transformando: bool = false
# Verdadero mientras el menú radial de transformaciones (F) está abierto.
var _menu_abierto: bool = false

@onready var humano: Node3D = $Humano
@onready var anim_humano: AnimationPlayer = $Humano/Animador
@onready var acuatico: Node3D = $Acuatico
@onready var anim_acuatico: AnimationPlayer = $Acuatico/AnimadorAcuatico
@onready var fuerza: Node3D = $Fuerza
@onready var anim_fuerza: AnimationPlayer = $Fuerza/AnimadorFuerza
@onready var vel_modelo: Node3D = $Visual/Pose/Volteo/Modelo
@onready var visual: Node3D = $Visual
@onready var pose: Node3D = $Visual/Pose
@onready var pivote: CamaraZiba = $PivoteCamara
@onready var trazador: TrazadorRuta = $Trazador
@onready var efectos: EfectosVelocidad = $Efectos
@onready var combate: SistemaCombate = $Combate
@onready var efecto_transf: EfectoTransformacion = $EfectoTransformacion
@onready var menu_transf: MenuTransformaciones = $MenuTransformaciones
@onready var estadisticas: EstadisticasJugador = $Estadisticas
# Forma Combate: el nodo "Ataque" es la representación del módulo ataque (su
# modelo y su AnimationPlayer), hermana de las demás representaciones.
@onready var ataque_visual: Node3D = $Ataque
@onready var anim_ataque: AnimationPlayer = $Ataque/AnimadorAtaque
# Reproductores de las acciones del Velocista (carga, trazado, dash y golpe).
# Son AudioStreamPlayer hijos del jugador, en el bus "Efectos" (igual que el de
# transformación), así que respetan el volumen general y el de efectos.
@onready var _sfx_carga: AudioStreamPlayer = $AudioCarga
@onready var _sfx_trazado: AudioStreamPlayer = $AudioTrazado
@onready var _sfx_dash: AudioStreamPlayer = $AudioDash
@onready var _sfx_golpe: AudioStreamPlayer = $AudioGolpe
# Reproductores de las HABILIDADES de FUERZA (salto, impacto en el suelo, agarre y
# tirada de roca, puñetazo y patada). Son AudioStreamPlayer hijos del jugador, en
# el bus "Efectos". Son INDEPENDIENTES entre sí y de los del velocista y de la
# transformación: uno no detiene a otro.
@onready var _sfx_f_salto: AudioStreamPlayer = $AudioFuerzaSalto
@onready var _sfx_f_impacto: AudioStreamPlayer = $AudioFuerzaImpacto
@onready var _sfx_f_agarre: AudioStreamPlayer = $AudioFuerzaAgarre
@onready var _sfx_f_tirada: AudioStreamPlayer = $AudioFuerzaTirada
@onready var _sfx_f_golpe: AudioStreamPlayer = $AudioFuerzaGolpe
@onready var _sfx_f_patada: AudioStreamPlayer = $AudioFuerzaPatada

# --- Estado forma humana ---
var h_salto_aire: bool = false
var h_anim_salto: String = ANIM_H_SALTO
var h_agachado: bool = false
var h_pivote_y_base: float = 1.6
var h_espera_congelar: float = 0.0

# --- Estado acuático (Pes) ---
var a_salto_aire: bool = false
var a_agachado: bool = false
var a_ataque_activo: bool = false
var a_t_ataque: float = 0.0
# Duración (s) del clip de ataque acuático en curso y si su golpe ya ha conectado:
# se golpea UNA sola vez, cuando el brazo llega a su extensión dentro del clip.
var a_ataque_dur: float = 0.0
var a_golpe_dado: bool = false
# NATACIÓN: true mientras el cuerpo está en agua honda y nada en vez de andar.
var a_nadando: bool = false
# Tiempo (s) que le queda al clip de transición de entrar o salir del agua.
var a_t_transicion: float = 0.0
## Clip de transición en curso ("" = ninguna).
var a_clip_transicion: String = ""
# ESCALERA: true mientras la forma acuática trepa (sube o baja) por una escalera.
# Lo manda _procesar_trepada (no la lógica de nado). Sólo la forma acuática la usa;
# ninguna otra forma puede agarrarse.
var a_subiendo_escalera: bool = false
# La escalera (EscaleraBarco) que se está trepando, o null.
var _escalera_actual: EscaleraBarco = null
# Progreso de la trepada: 0 = en el agua al pie, 1 = de pie sobre la superficie.
# Manda la posición del cuerpo Y la fase del clip (así no hay desfase posible).
var _escalera_u: float = 0.0
# true = se está BAJANDO (el recorrido va de 1 a 0 y el clip se reproduce al revés).
var _escalera_bajando: bool = false
# AVISO DE AGUA ("Solo puedes ingresar..."): segundos que le quedan en pantalla y
# si el intento en curso ya lo mostró (se rearma al soltar el movimiento).
var _aviso_agua_t: float = 0.0
var _aviso_agua_armado: bool = true
# Último punto firme sobre suelo transitable (no agua honda): ahí se devuelve a una
# forma terrestre que acabe dentro del agua (p. ej. cayendo desde el muelle).
var _punto_seguro := Vector3.ZERO
## Relieve compartido: ÚNICA fuente de verdad de dónde empieza el agua y de cuánto
## honda es en cada punto (lo usan el límite de las formas terrestres y el nado).
var _relieve := Relieve.new()
# Habilidades acuáticas (teclas 1-4): bloqueo de acción, enfriamientos y carga.
var a_en_habilidad: bool = false
var a_t_habilidad: float = 0.0
var a_pendiente: int = 0
var a_pendiente_t: float = 0.0
var a_cooldowns: Dictionary = {}
var a_carga: Node3D = null
# Dirección (horizontal, mundo) capturada al pulsar una habilidad acuática. Se fija
# en ese instante y NO cambia aunque después se mueva la cámara.
var a_dir_ataque: Vector3 = Vector3.ZERO

# --- Mano de lanzamiento de las habilidades acuáticas ---
# Las cuatro habilidades nacen en la MANO que sostiene el agua, no en el centro
# del cuerpo. Se reutiliza el mismo sistema del módulo acuático original (hueso
# del esqueleto + ligero desplazamiento), pero sobre el modelo integrado de Leo.
# El hueso se busca por nombre en el esqueleto REALMENTE importado: en
# models/futuristic_armor_character.tscn la mano derecha es "mixamorig_RightHand".
const MANO_AGUA := &"RightHand"
# Desplazamiento (m) del agua respecto a la muñeca, EN EL ESPACIO DEL HUESO (no del
# mundo): la lleva a la palma y hace que acompañe al brazo mire donde mire.
const DESPLAZAMIENTO_MANO_AGUA := Vector3(0.0, 0.03, 0.0)
# Cuánto (m) por delante de la mano nace el efecto, en la dirección del ataque:
# evita que la bola quede DENTRO de la mano o del brazo y la deja proyectada.
const ADELANTE_MANO_AGUA := 0.30
# Esqueleto del modelo acuático (cacheado: se pide en cada fotograma).
var _esqueleto_agua: Skeleton3D = null

# --- Estado Fuerza ---
var f_salto_aire: bool = false
var f_agachado: bool = false
var f_embestiendo: bool = false
var f_t_embestida: float = 0.0
var f_embestida_dir: Vector3 = Vector3.ZERO
var f_embestida_golpeados: Array = []
var f_recuperacion: float = 0.0
var f_slam: bool = false
var f_cargando_roca: bool = false
var f_roca: FuerzaRock = null
# IK de agarre de la roca: se crea una sola vez, la primera vez que se pulsa Q.
var _f_ik: FuerzaBrazosIK = null
var _f_esqueleto: Skeleton3D = null
var _f_idx_cabeza: int = -1
var _f_idx_cabeza_top: int = -1
# Supersalto con carga (ESPACIO mantenido en el suelo): estado de la carga,
# indicador visual (reutiliza el anillo del HUD, mismo estilo) y la posición
# base del nodo del modelo para el temblor de esfuerzo.
var f_super_cargando: bool = false
var f_super_carga: float = 0.0
var _f_fondo: ColorRect = null
var _f_relleno: ColorRect = null
var _f_flash_indicador: float = 0.0
var _f_fuerza_pos_base: Vector3 = Vector3.ZERO
# El levantamiento de la roca ha TERMINADO de verdad (fin del clip RockLift):
# sólo entonces se puede apuntar/lanzar.
var f_roca_lista: bool = false
# Última piedra LANZADA: sigue existiendo en el mundo hasta desvanecerse.
# Mientras siga ahí no se puede arrancar otra del suelo.
var _f_roca_lanzada: FuerzaRock = null
var f_ataque: bool = false
# Ventana de combo: instante en el que TERMINÓ el último golpe (no aquel en el
# que empezó): el encadenado 1-2 se mide desde el fin real de la animación.
var f_ultimo_golpe: float = 0.0
# --- Animación Fuerza (librería UniversalLibrary: FuerzaUniversal.tres) ---
var _f_anim_actual: String = ""
var _f_ataque_clip: String = ""
var _f_ataque_dur: float = 0.0
var _f_ataque_impacto_u: float = 0.29
var _f_ataque_golpeado: bool = false
var _f_clip_terminado: String = ""
var _f_combo_pedido: bool = false
var _f_bloqueo_anim: float = 0.0
# Mira del apuntado de la roca (cruz fina en el centro de la pantalla).
var _f_mira: Control = null

# --- Estado velocista ---
var _dir_dash: Vector3 = Vector3.ZERO
var _pos_dash_inicio: Vector3 = Vector3.ZERO
var _objetivo_dash: Vector3 = Vector3.ZERO
var _t_dash: float = 0.0
var _t_carga: float = 0.0
var _t_preparado: float = 0.0
var _puntos: Array[Vector3] = []
var _idx: int = 0
var _vel_trayecto: float = 0.0
var _hubo_combo_atras: bool = false
var _en_ventana_atras: bool = false
var _t_ventana: float = 0.0
var _dir_orient_ventana: Vector3 = Vector3.ZERO
var _ultimo_dir_movimiento: Vector3 = Vector3.ZERO
var _anim: AnimationPlayer = null
var _anim_nombres: Dictionary = {}
var _anim_actual: String = ""
var _bloqueo_anim: float = 0.0
var _ataque_activo: bool = false
var _t_ataque: float = 0.0
## Ataque del velocista: identificador del golpe en curso (invalida el impacto
## pendiente si se cancela o si empieza otro) y enemigos ya embestidos por la
## supervelocidad actual (para no repetir el daño cada fotograma).
var _vel_golpe_id: int = 0
var _super_golpeados: Dictionary = {}
## Máscara de colisión guardada mientras dura la arremetida (-1 = ninguna activa).
var _mascara_guardada: int = -1
## Indicador del FreeFlow sobre el objetivo activo (uno solo, creado a demanda).
var _indicador_objetivo: MeshInstance3D = null
var _emote_activo: bool = false
var _t_emote: float = 0.0
var _en_modo_ataque: bool = false
var _t_modo_ataque: float = 0.0
var _salto_forzado: bool = false
# Fundido de salida del sonido del trazado (para un final limpio, sin chasquido).
var _fade_trazado: Tween

# --- Estado forma Combate (módulo ataque) ---
var c_salto_aire: bool = false
# Verdadero cuando ya se usó el impulso aéreo (doble salto) desde el último
# toque de suelo: impide un tercer salto antes de aterrizar.
var c_doble_usado: bool = false
# --- Ataque FreeFlow de la forma Combate (módulo ataque, integrado) ---
# Estado del combo, objetivo actual, golpe en curso y su fase. El objetivo se
# REELIGE al comenzar cada golpe: ninguna referencia antigua bloquea el cambio.
var c_estado: int = C_E.LIBRE
var c_objetivo: Node3D = null
var c_cadena: int = 0
var c_golpe: AttackData = null
var c_fase: float = 0.0
var c_golpe_hecho: bool = false
var c_acercar_t: float = 0.0
# Cadena construida una vez a partir de SPRINT del módulo y del config vigente.
var _c_cadena_datos: Array = []
# Gestor del encuentro resuelto por grupo "combat_manager" (si la partida tiene
# enemigos registrados). Sin gestor, el combate usa el buffer y el config del
# propio módulo: misma mecánica, sin depender de escenas externas.
var _gestor_combate: Node = null
var _c_combo: ComboSystem = null

func _exit_tree() -> void:
	# El indicador del objetivo cuelga del mundo, no del jugador: se retira con él
	# para no dejar nodos huérfanos ni referencias a enemigos liberados.
	if _indicador_objetivo != null and is_instance_valid(_indicador_objetivo):
		_indicador_objetivo.queue_free()
	_indicador_objetivo = null

func _ready() -> void:
	# El personaje jugable se identifica con el grupo "player": lo esperan el
	# módulo de NPC de la partida (peatones que reaccionan a Leo, director que no
	# siembra gente encima del punto de inicio), el gestor del encuentro y el
	# gerente de enemigos. Es la MISMA convención que usan los jugadores de los
	# módulos, así que aquí no se crea ningún sistema nuevo.
	add_to_group("player")
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	# Sigue el bordillo hacia abajo (0.153 m) sin despegarse del suelo al bajar de
	# la acera a la calzada. Es un ajuste pequeño y localizado (por defecto 0.1).
	floor_snap_length = 0.2
	_configurar_animaciones()
	_configurar_sonidos_velocista()
	combate.golpe_realizado.connect(_on_golpe_realizado)
	# Atacar también corta la regeneración de resistencia (sistema de daño/HUD):
	# se reutiliza la señal de combate existente, sin crear un segundo sistema.
	combate.golpe_realizado.connect(estadisticas.notificar_ataque)
	# El menú radial (F) es sólo una NUEVA forma de elegir la transformación:
	# emite qué transformación eligió el jugador y aquí se reutiliza el sistema
	# que ya existía. También avisa al abrir/cerrar para congelar el control.
	menu_transf.menu_abierto.connect(_on_menu_transformaciones_abierto)
	menu_transf.menu_cerrado.connect(_on_menu_transformaciones_cerrado)
	menu_transf.transformacion_elegida.connect(_on_transformacion_elegida)
	# Altura base del pivote de cámara, para bajarla al agacharse y restaurarla después.
	h_pivote_y_base = pivote.position.y
	# Iguala la altura visual de la forma velocista a la de Leo humano.
	_ajustar_escala_velocista()
	# Iguala la altura visual de la forma acuática (Pes) a la de Leo humano.
	_ajustar_escala_acuatico()
	# Iguala la altura visual de la forma Fuerza a la de Leo humano.
	_ajustar_escala_fuerza()
	# Iguala la altura visual de la forma Combate (módulo ataque) a la de Leo humano.
	_ajustar_escala_ataque()
	# El fin REAL del clip de levantar la roca (señal del propio AnimationPlayer,
	# no un temporizador paralelo) es lo que habilita apuntar y lanzar.
	anim_fuerza.animation_finished.connect(_on_animacion_fuerza_terminada)
	# Indicador de carga del supersalto: se reutiliza el anillo del HUD para que
	# quede en el mismo estilo que el resto de la interfaz.
	_preparar_indicador_super()
	# Mira del apuntado de la piedra (se enciende sólo con la roca lista).
	_preparar_mira_roca()
	_f_fuerza_pos_base = fuerza.position
	# Enfriamientos de las 4 habilidades acuáticas (arrancan listas).
	for i in ABIL_AGUA.size():
		a_cooldowns[i + 1] = 0.0
	# La partida arranca SIEMPRE en la forma humana (Leo).
	forma = Forma.HUMANO
	visual.visible = false
	acuatico.visible = false
	fuerza.visible = false
	ataque_visual.visible = false
	humano.visible = true
	_reproducir_humano(ANIM_H_IDLE, 0.0)

# Fuerza usada por herramientas/diagnóstico (igual que el prototipo).
func forma_actual() -> int:
	return forma

func esta_transformado() -> bool:
	return forma != Forma.HUMANO

# Id lógico de la forma actual, para sistemas externos (el HUD). Escalable:
# una forma futura sólo añade su caso aquí y su icono en HUDCircular.ICONOS.
func id_forma() -> StringName:
	match forma:
		Forma.VELOCISTA:
			return &"velocista"
		Forma.ACUATICO:
			return &"pes"
		Forma.FUERZA:
			return &"tanque"
		Forma.COMBATE:
			return &"combate"
		_:
			return &"humano"

func _unhandled_input(event: InputEvent) -> void:
	# Con el menú de transformaciones abierto el ratón debe quedar libre para
	# pulsar los iconos: se anula el "clic para recapturar" durante ese tiempo.
	if _menu_abierto:
		return
	# El cambio de forma se hace EXCLUSIVAMENTE con el menú radial (F). El antiguo
	# interruptor directo humano <-> velocista se eliminó del juego.
	# K (sólo para probar el HUD): aplica daño al personaje.
	if event.is_action_pressed("dano_prueba"):
		estadisticas.recibir_danio(25.0)
		return
	# Pes (forma acuática): las acciones de agua 1-4 lanzan sus 4 habilidades.
	# Son acciones del Input Map (reasignables desde CONFIGURACIÓN > CONTROLES) y
	# sólo se atienden en esta forma, así que en las demás conservan su sentido.
	# is_action_pressed(action) sobre el PROPIO evento respeta la pulsación única
	# (ignora los eventos "echo" de la tecla mantenida) igual que antes.
	if forma == Forma.ACUATICO:
		for i in ABIL_AGUA.size():
			var accion_agua := StringName("agua_habilidad_%d" % (i + 1))
			if event.is_action_pressed(accion_agua):
				_intentar_habilidad_agua(i + 1)
				get_viewport().set_input_as_handled()
				return
	# Fuerza: embestida (R), pisotón (E, sólo en el aire) y arrancar roca (Q).
	# Igual que las habilidades de agua: acciones del Input Map, reasignables.
	if forma == Forma.FUERZA:
		if event.is_action_pressed("fuerza_embestida"):
			_iniciar_embestida_fuerza()
			get_viewport().set_input_as_handled()
			return
		elif event.is_action_pressed("fuerza_slam"):
			_intentar_slam_fuerza()
			get_viewport().set_input_as_handled()
			return
		elif event.is_action_pressed("fuerza_roca"):
			_intentar_roca_fuerza()
			get_viewport().set_input_as_handled()
			return
	if event is InputEventKey and event.pressed and (event as InputEventKey).keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _physics_process(delta: float) -> void:
	# Indicador del objetivo del FreeFlow: se recoloca (o se oculta) en cada
	# fotograma, así sigue al enemigo y desaparece solo si deja de ser válido.
	_actualizar_indicador_objetivo(delta)
	# Con el menú radial de transformaciones abierto (F): se congela el control
	# de movimiento (sin tocar la cámara ni la posición de forma brusca) hasta
	# que el menú se cierra. El propio menú gestiona la tecla F.
	if _menu_abierto:
		_congelar_por_menu(delta)
		return

	# Durante la transición visual no hay control horizontal ni nuevas acciones:
	# sólo actúa la gravedad (para no quedar flotando) y se mueve el cuerpo.
	if _transformando:
		velocity.x = 0.0
		velocity.z = 0.0
		if not is_on_floor():
			velocity.y -= gravedad * delta
		elif velocity.y < 0.0:
			velocity.y = -0.1
		move_and_slide()
		return

	# Cuenta atrás del aviso de agua ("Solo puedes ingresar al agua..."): el HUD lo lee
	# a través de texto_interaccion(), así que basta con mantenerlo aquí.
	if _aviso_agua_t > 0.0:
		_aviso_agua_t = maxf(_aviso_agua_t - delta, 0.0)

	# Posición ANTES de mover: la usa el límite de agua de más abajo para deshacer
	# el desplazamiento de este fotograma si el cuerpo acaba sobre agua honda.
	var antes := global_position
	# Último punto FIRME (de pie, sobre cualquier superficie transitable: arena, calle,
	# tablones del muelle o cubierta del barco). Allí se devuelve a una forma terrestre
	# que acabe dentro del agua. Basta con is_on_floor(): una cubierta sobre agua honda
	# es suelo firme igual que la orilla.
	if is_on_floor():
		_punto_seguro = global_position
	if forma == Forma.HUMANO:
		_procesar_humano(delta)
	elif forma == Forma.ACUATICO:
		_procesar_acuatico(delta)
	elif forma == Forma.FUERZA:
		_procesar_fuerza(delta)
		_actualizar_anim_fuerza(delta)
	elif forma == Forma.COMBATE:
		_procesar_combate(delta)
	else:
		match estado:
			Estado.NORMAL:
				_procesar_normal(delta)
			Estado.DASH:
				_procesar_dash(delta)
			Estado.CAIDA_DASH:
				_procesar_caida_dash()
			Estado.CARGA:
				_procesar_carga(delta)
			Estado.PREPARADO:
				_procesar_preparado(delta)
			Estado.EJECUCION:
				_procesar_ejecucion(delta)
		_actualizar_animaciones(delta)
		_actualizar_pose(delta)

	# LÍMITE DE AGUA: sólo la forma acuática puede nadar. Las formas terrestres
	# (humano, velocista y fuerza) se frenan en la orilla.
	if forma != Forma.ACUATICO:
		_restringir_agua(antes)

	# Subida natural de bordillos para locomoción normal. Durante EJECUCION el
	# recorrido gestiona el bloqueo en _procesar_ejecucion(): ahí primero distingue
	# pared/escalón y, si corresponde, llama a _salvar_escalon(). No ejecutar ambos
	# solucionadores en el mismo fotograma.
	# Subida natural de los bordillos de las aceras (~15 cm): común a las cuatro
	# formas, se ejecuta una vez por frame tras el move_and_slide() de cada una.
	# Durante la EJECUCIÓN del trazado del Velocista NO se ejecuta aquí: ese estado
	# usa _intentar_escalon_ejecucion() sobre su propia colisión con move_and_collide,
	# y encadenar ambos podría provocar dobles ascensos o saltos de posición.
	if estado != Estado.EJECUCION and not a_subiendo_escalera:
		_resolver_escalon()

# Menú abierto: sin control horizontal, sólo gravedad y pose quieta, para que
# el personaje no se mueva ni quede flotando. La cámara no se modifica.
func _congelar_por_menu(delta: float) -> void:
	velocity.x = 0.0
	velocity.z = 0.0
	if not is_on_floor():
		velocity.y -= gravedad * delta
	elif velocity.y < 0.0:
		velocity.y = -0.1
	move_and_slide()
	if forma == Forma.HUMANO:
		_reproducir_humano(ANIM_H_IDLE)
	elif forma == Forma.ACUATICO:
		_reproducir_acuatico(ANIM_A_IDLE)
	elif forma == Forma.FUERZA:
		_reproducir_fuerza(ANIM_F_IDLE)
	elif forma == Forma.COMBATE:
		_reproducir_combate(ANIM_C_IDLE)
	else:
		_reproducir_anim(ANIM_INACTIVO, BLEND_MARCHA)

## Sube el bordillo de una acera (escalón bajo, ~15 cm) sin tocar move_and_slide
## ni la gravedad. Se llama una vez por frame, tras el movimiento de cada forma,
## así que sirve igual a Humano, Velocista, Acuático y Fuerza.
##
## Clave: la dirección de ascenso NO se toma de 'velocity' después de
## move_and_slide(), porque el deslizamiento proyecta esa velocidad A LO LARGO del
## bordillo; sondear con ella hacía que el personaje avanzara en paralelo (el
## deslizamiento lateral observado). En su lugar se usa la INTENCIÓN de movimiento
## del jugador y, para el avance, la normal de la pared real (≈ perpendicular al
## bordillo), de modo que el sondeo CRUZA el escalón.
##
## Sólo actúa contra una pared compatible con un escalón bajo: hay hueco por
## encima, paso libre a esa altura y una superficie transitable más alta (dentro
## del escalón) al otro lado. Un muro alto (un edificio) no supera el sondeo de
## avance y no se sube; un borde que sigue a la misma cota (la propia calzada) se
## rechaza, así que no se produce avance lateral.
func _resolver_escalon() -> void:
	if not is_on_floor() or not is_on_wall():
		return
	# Intención de movimiento horizontal del jugador (no la velocidad tras slide).
	var intencion := _direccion_entrada()
	if intencion.length_squared() < 0.04:
		return
	intencion = intencion.normalized()

	# Dirección de avance: perpendicular a la pared si la conocemos; si no, la
	# intención del jugador. La intención decide SI se sube (hay que empujar hacia
	# la pared), no la dirección exacta del sondeo.
	var normal := _normal_pared()
	var dir := intencion
	if normal != Vector3.ZERO:
		if intencion.dot(normal) > -0.15:
			return
		dir = -normal

	var altura := ALTURA_ESCALON
	# Avance suficiente para que el centro de la cápsula quede sobre el destino.
	var avance_dist := maxf(AVANCE_ESCALON, _radio_capsula() + MARGEN_ESCALON)

	# 1) ¿Cabe la subida? (si hay techo bajo, no)
	if test_move(global_transform, Vector3.UP * altura):
		return

	# 2) ¿Hay paso libre a la altura del escalón? (muro alto -> no es un escalón)
	var elevado := global_transform
	elevado.origin.y += altura
	if test_move(elevado, dir * avance_dist):
		return

	# 3) Suelo de destino: superficie transitable, más alta que la actual pero
	#    dentro del escalón. Distingue calzada (misma cota -> rechazar), escalón
	#    (subir), pared/edificio y ausencia de suelo.
	var desde := elevado.origin + dir * avance_dist + Vector3.UP * 0.05
	var golpe := _rayo_suelo(desde, altura + 0.25)
	if golpe.is_empty():
		return
	var normal_suelo: Vector3 = golpe.get("normal", Vector3.UP)
	if normal_suelo.dot(Vector3.UP) < cos(floor_max_angle):
		return
	var desnivel: float = (golpe["position"] as Vector3).y - global_position.y
	if desnivel <= DESNIVEL_MINIMO or desnivel > altura + 0.03:
		return

	# 4) Ejecuta la subida con movimiento real (sin teletransporte): elevar,
	#    avanzar y volver a apoyarse sobre la superficie de destino.
	move_and_collide(Vector3.UP * (desnivel + 0.03))
	move_and_collide(dir * avance_dist)
	move_and_collide(Vector3.DOWN * (desnivel + 0.08))


## Normal horizontal de la pared en la que se apoya el cuerpo (de las colisiones
## del último move_and_slide), o Vector3.ZERO si no hay pared. Los suelos y techos
## se descartan por su componente vertical.
func _normal_pared() -> Vector3:
	for i in get_slide_collision_count():
		var col := get_slide_collision(i)
		if col == null:
			continue
		var n := col.get_normal()
		if absf(n.y) < 0.7:
			var horiz := Vector3(n.x, 0.0, n.z)
			if horiz.length_squared() > 0.0001:
				return horiz.normalized()
	return Vector3.ZERO


## Rayo hacia abajo limitado a la máscara del jugador; devuelve {} si no hay
## impacto. Permite conocer la altura y la normal del suelo de destino.
func _rayo_suelo(desde: Vector3, largo: float) -> Dictionary:
	var mundo := get_world_3d()
	if mundo == null:
		return {}
	var q := PhysicsRayQueryParameters3D.create(desde, desde + Vector3.DOWN * largo)
	q.collision_mask = collision_mask
	q.exclude = [get_rid()]
	q.collide_with_areas = false
	q.collide_with_bodies = true
	return mundo.direct_space_state.intersect_ray(q)


## Radio de la cápsula de colisión del jugador (0.4 m por defecto).
func _radio_capsula() -> float:
	var capsula := get_node_or_null("Colision") as CollisionShape3D
	if capsula != null and capsula.shape is CapsuleShape3D:
		return (capsula.shape as CapsuleShape3D).radius
	return 0.4


## Ascenso de bordillos durante la EJECUCIÓN del trazado del Velocista. Usa el
## MISMO criterio y los MISMOS límites que _resolver_escalon() del movimiento
## normal (ALTURA_ESCALON / AVANCE_ESCALON / MARGEN_ESCALON / DESNIVEL_MINIMO),
## pero se dispara con la colisión real del move_and_collide() de la trayectoria
## en lugar de is_on_wall(), porque la ejecución no usa move_and_slide() para
## avanzar. Devuelve true si el obstáculo era un escalón transitable y se subió
## (el recorrido continúa); false si no lo es (pared, edificio, desnivel
## excesivo o ausencia de suelo válido) y debe cancelarse como antes.
func _intentar_escalon_ejecucion(col: KinematicCollision3D, dir_mov: Vector3) -> bool:
	if col == null:
		return false
	# Sólo se sube contra una cara vertical (un bordillo). Un suelo o techo
	# (normal casi vertical) no es un escalón.
	var normal := col.get_normal()
	if absf(normal.y) >= 0.7:
		return false
	var horizontal := Vector3(normal.x, 0.0, normal.z)
	if horizontal.length_squared() < 0.0001:
		return false
	horizontal = horizontal.normalized()

	# Dirección de avance real: perpendicular a la pared. Se exige además que el
	# desplazamiento previsto de la trayectoria apunte hacia la pared (no de lado
	# ni en sentido contrario), para no escalar un borde que sólo roza de refilón.
	var dir := -horizontal
	var intencion := Vector3(dir_mov.x, 0.0, dir_mov.z)
	if intencion.length_squared() > 0.0001 and intencion.normalized().dot(dir) < 0.2:
		return false

	var altura := ALTURA_ESCALON
	# Avance suficiente para que el centro de la cápsula quede sobre el destino.
	var avance_dist := maxf(AVANCE_ESCALON, _radio_capsula() + MARGEN_ESCALON)

	# 1) ¿Cabe la elevación de la cápsula completa? (si hay techo bajo, no)
	if test_move(global_transform, Vector3.UP * altura):
		return false

	# 2) ¿Hay paso libre por encima del borde? (muro/edificio alto -> no es un
	#    escalón y no se intenta subir)
	var elevado := global_transform
	elevado.origin.y += altura
	if test_move(elevado, dir * avance_dist):
		return false

	# 3) Superficie de destino: debe ser transitable, estar más alta que la actual
	#    pero dentro del escalón. Distingue calzada a la misma cota (rechazar) de
	#    bordillo (subir), y descarta pared/edificio o ausencia de suelo.
	var desde := elevado.origin + dir * avance_dist + Vector3.UP * 0.05
	var golpe := _rayo_suelo(desde, altura + 0.25)
	if golpe.is_empty():
		return false
	var normal_suelo: Vector3 = golpe.get("normal", Vector3.UP)
	if normal_suelo.dot(Vector3.UP) < cos(floor_max_angle):
		return false
	var desnivel: float = (golpe["position"] as Vector3).y - global_position.y
	if desnivel <= DESNIVEL_MINIMO or desnivel > altura + 0.03:
		return false

	# 4) Ascenso con movimiento real (sin teletransporte): elevar, avanzar y
	#    volver a apoyarse sobre la superficie de destino.
	move_and_collide(Vector3.UP * (desnivel + 0.03))
	move_and_collide(dir * avance_dist)
	move_and_collide(Vector3.DOWN * (desnivel + 0.08))
	return true


# ------------------------------------------------ AGUA: dónde se puede pisar
## Profundidad REAL (m) de agua sobre el fondo en un punto del mapa: el nivel del
## mar menos la cota del terreno. La responde `Relieve` con la MISMA función que
## genera el mundo, así que vale en cualquier punto de la costa y no depende de
## ningún valor fijo: 0 o menos = tierra seca, 1.2 = metro y medio de agua.
func profundidad_agua(x: float, z: float) -> float:
	return _relieve.profundidad_agua(x, z)


## true si en ese punto el agua es demasiado honda para caminar (sólo se nada).
func agua_no_pisable(x: float, z: float) -> bool:
	return profundidad_agua(x, z) > PROFUNDIDAD_VADEO


## true si el cuerpo, en esa posición, NO puede seguir sin ser la forma acuática:
## fondo intransitable Y, además, o está ya a la altura del mar (dentro del agua) o
## está colgando sin superficie firme bajo los pies (acaba de salirse de la cubierta
## del barco o de la punta del muelle). Las dos condiciones de altura son necesarias:
## sin la primera se podría caminar por el fondo hacia el fondo del mar, y sin la
## segunda quedaría clavado cualquier cuerpo que pisara el muelle o el barco, cuyo
## fondo también es hondo pero va MUY por encima del agua (medido con el arnés).
func en_agua_honda(punto: Vector3) -> bool:
	if not agua_no_pisable(punto.x, punto.z):
		return false
	return punto.y <= SUPERFICIE_MAR + 0.05 or not is_on_floor()


## Frena a las formas TERRESTRES en la orilla. Se llama una vez por fotograma,
## después de que la forma haya movido el cuerpo, con la posición previa al
## movimiento ([param antes]).
##
## POR QUÉ ASÍ: comprobar el agua ANTES de moverse obligaría a meter el control en
## los ocho caminos de movimiento (andar, correr, dash, embestida, pisotón, salto,
## carga y ejecución del trazado). Mirando el resultado, una sola comprobación
## cubre todos los casos, incluidos los que llevan mucha inercia o una habilidad
## activa: si el cuerpo terminó sobre agua honda se deshace EL DESPLAZAMIENTO
## HORIZONTAL DE ESTE FOTOGRAMA y se anula la velocidad. La corrección es como
## mucho la distancia de un fotograma (un paso corto) y no se repite: en cuanto la
## velocidad es 0 no hay nada que deshacer, así que el personaje se queda quieto en
## la arena, sin vibrar ni retroceder en cadena.
func _restringir_agua(antes: Vector3) -> void:
	if not en_agua_honda(global_position):
		_aviso_agua_armado = true
		return
	# Se deshace EL DESPLAZAMIENTO DEL FOTOGRAMA ENTERO (horizontal y vertical): así
	# el cuerpo se queda del lado transitable aunque el intento sea un salto, un dash
	# o una habilidad con mucha inercia, y no acaba ni flotando sobre el agua ni
	# caminando por el fondo.
	global_position = antes
	velocity.x = 0.0
	velocity.z = 0.0
	# Si además ya está por debajo de la superficie (se cayó desde el muelle o desde
	# la cubierta), se le devuelve al último punto FIRME: nunca se queda en el agua
	# sin ser la forma acuática.
	if global_position.y < SUPERFICIE_MAR - 0.1:
		global_position = _punto_seguro
		velocity = Vector3.ZERO
	# AVISO: un intento = un mensaje. Sólo aparece si el jugador está EMPUJANDO hacia
	# el agua (quieto en la orilla no sale) y no se repite mientras mantenga la tecla;
	# al soltar el movimiento el aviso se rearma, así que un intento nuevo sí lo
	# vuelve a mostrar.
	if _direccion_entrada().length() <= 0.05:
		_aviso_agua_armado = true
	elif _aviso_agua_armado:
		_aviso_agua_t = AVISO_AGUA_DURACION
		_aviso_agua_armado = false
	# Si el recorrido del velocista llegara al agua (una ruta vieja, un salto de
	# terreno), la habilidad se cierra de forma ordenada en vez de quedarse
	# empujando contra la orilla para siempre.
	if estado == Estado.EJECUCION:
		_terminar_ejecucion()


func _on_menu_transformaciones_abierto() -> void:
	_menu_abierto = true
	# Cargar el supersalto y abrir el menú a la vez dejaría la carga a medias:
	# se cancela sin salto (nada se dispara solo al cerrar el menú).
	_cancelar_super()
	# Si la mole está a MEDIO levantar, se cancela limpiamente: con el control
	# congelado el clip no puede completarse y la piedra acabaría colocada mal.
	if _esta_levantando_roca():
		_soltar_roca_interrumpida()

func _on_menu_transformaciones_cerrado() -> void:
	_menu_abierto = false

# Punto único donde el menú conecta con el sistema de transformación existente.
# Añadir una transformación futura = añadir su caso aquí (y marcarla como
# desbloqueada en MenuTransformaciones.TRANSFORMACIONES). El menú no cambia.
func _on_transformacion_elegida(id: StringName) -> void:
	match id:
		&"velocista":
			_cambiar_forma_con_efecto(Forma.VELOCISTA)
		&"pes":
			_cambiar_forma_con_efecto(Forma.ACUATICO)
		&"tanque":
			_cambiar_forma_con_efecto(Forma.FUERZA)
		&"combate":
			_cambiar_forma_con_efecto(Forma.COMBATE)
		_:
			pass

# =============================================================== TRANSFORMACIÓN
# Transición visual al cambiar de forma. Reproduce el efecto de EfectoTransformacion
# (el MISMO de la transformación velocista), cambia de forma en su pico y espera a
# que el efecto termine antes de devolver el control. No duplica el sistema de efectos.
func _transicionar(destino: int) -> void:
	if _transformando:
		return
	# Bajo el agua honda sólo se puede seguir siendo la forma acuática: cambiar a una
	# forma terrestre dejaría al personaje atrapado en el fondo (no puede nadar ni
	# salir). El cambio se rechaza hasta que vuelva a aguas transitables; volver a la
	# forma acuática sí se permite, y es la salida natural si el cambio fue forzado.
	if destino != Forma.ACUATICO and a_nadando:
		print("[Leo] No se puede transformar bajo el agua: vuelve a la superficie o a la orilla.")
		return
	_transformando = true
	var id_destino: StringName = _id_forma(destino)
	if COLORES_TRANSFORMACION.has(id_destino):
		efecto_transf.establecer_color(COLORES_TRANSFORMACION[id_destino])
	efecto_transf.reproducir()
	await efecto_transf.pico_alcanzado
	match destino:
		Forma.VELOCISTA:
			_entrar_velocista()
		Forma.ACUATICO:
			_entrar_acuatico()
		Forma.FUERZA:
			_entrar_fuerza()
		Forma.COMBATE:
			_entrar_combate()
		_:
			_entrar_humano()
	await efecto_transf.terminado
	_transformando = false

func _id_forma(id: int) -> StringName:
	match id:
		Forma.VELOCISTA:
			return &"velocista"
		Forma.ACUATICO:
			return &"pes"
		Forma.FUERZA:
			return &"tanque"
		Forma.COMBATE:
			return &"combate"
		_:
			return &"humano"

# Elige una forma desde el menú radial (F): si ya se está en esa forma, vuelve
# a humano. Así cualquier transformación se puede "desactivar" desde el HUD.
func _cambiar_forma_con_efecto(destino: int) -> void:
	# Mientras se trepa por una escalera NO se atiende ningún cambio de forma: el
	# cuerpo está en el aire, entre peldaños, y soltar la escalera a medias lo
	# dejaría cayendo dentro del casco. La petición se ignora.
	if a_subiendo_escalera:
		return
	if forma == destino:
		destino = Forma.HUMANO
	_transicionar(destino)

func _entrar_velocista() -> void:
	forma = Forma.VELOCISTA
	_detener_acuatico()
	_detener_fuerza()
	_detener_combate()
	h_salto_aire = false
	h_agachado = false
	pivote.position.y = h_pivote_y_base
	estado = Estado.NORMAL
	velocity = Vector3.ZERO
	# La representación cambia; el cuerpo, la colisión y la cámara no.
	humano.visible = false
	acuatico.visible = false
	fuerza.visible = false
	ataque_visual.visible = false
	visual.visible = true
	_anim_actual = ""
	_salto_forzado = false
	_ataque_activo = false
	_emote_activo = false
	_bloqueo_anim = 0.0
	_reproducir_anim(ANIM_INACTIVO, BLEND_TRANSFORMACION, true)
	estadisticas.aplicar_forma(id_forma())
	forma_cambiada.emit(id_forma())

func _entrar_acuatico() -> void:
	forma = Forma.ACUATICO
	_detener_velocista()
	_detener_fuerza()
	_detener_combate()
	a_salto_aire = false
	a_agachado = false
	a_ataque_activo = false
	a_t_ataque = 0.0
	a_ataque_dur = 0.0
	a_golpe_dado = false
	a_subiendo_escalera = false
	_escalera_actual = null
	pivote.position.y = h_pivote_y_base
	estado = Estado.NORMAL
	velocity = Vector3.ZERO
	# La representación cambia; el cuerpo, la colisión y la cámara no.
	humano.visible = false
	visual.visible = false
	fuerza.visible = false
	ataque_visual.visible = false
	acuatico.visible = true
	if anim_acuatico != null:
		anim_acuatico.speed_scale = 1.0
	_reproducir_acuatico(ANIM_A_IDLE, BLEND_TRANSFORMACION, true)
	estadisticas.aplicar_forma(id_forma())
	forma_cambiada.emit(id_forma())

func _entrar_humano() -> void:
	forma = Forma.HUMANO
	_detener_velocista()
	_detener_acuatico()
	_detener_fuerza()
	_detener_combate()
	visual.visible = false
	acuatico.visible = false
	fuerza.visible = false
	ataque_visual.visible = false
	humano.visible = true
	h_salto_aire = false
	_reproducir_humano(ANIM_H_IDLE, BLEND_TRANSFORMACION)
	estadisticas.aplicar_forma(id_forma())
	forma_cambiada.emit(id_forma())

# Limpia el estado de la forma acuática al salir de ella.
func _detener_acuatico() -> void:
	a_salto_aire = false
	a_agachado = false
	a_ataque_activo = false
	a_t_ataque = 0.0
	a_ataque_dur = 0.0
	a_golpe_dado = false
	# Natación: al salir de la forma no queda anotado que estaba nadando.
	a_nadando = false
	a_t_transicion = 0.0
	a_clip_transicion = ""
	# Cancela cualquier habilidad en curso y su carga (no debe quedar nada activo).
	a_en_habilidad = false
	a_t_habilidad = 0.0
	a_pendiente = 0
	a_pendiente_t = 0.0
	a_dir_ataque = Vector3.ZERO
	_cancelar_carga_agua()
	if anim_acuatico != null:
		anim_acuatico.speed_scale = 1.0

func _entrar_fuerza() -> void:
	forma = Forma.FUERZA
	_detener_velocista()
	_detener_acuatico()
	_detener_combate()
	f_salto_aire = false
	f_agachado = false
	f_embestiendo = false
	f_slam = false
	f_ataque = false
	f_recuperacion = 0.0
	f_super_cargando = false
	f_super_carga = 0.0
	f_roca_lista = false
	_limpiar_efectos_carga()
	pivote.position.y = h_pivote_y_base
	estado = Estado.NORMAL
	velocity = Vector3.ZERO
	# La representación cambia; el cuerpo, la colisión y la cámara no.
	humano.visible = false
	visual.visible = false
	acuatico.visible = false
	ataque_visual.visible = false
	fuerza.visible = true
	_f_anim_actual = ""
	_f_ataque_clip = ""
	_f_bloqueo_anim = 0.0
	_reproducir_fuerza(ANIM_F_IDLE, BLEND_TRANSFORMACION, true)
	estadisticas.aplicar_forma(id_forma())
	forma_cambiada.emit(id_forma())

# Limpia el estado de la forma Fuerza al salir de ella: cancela embestida,
# pisotón y una roca todavía sujeta (no deja estados activos al cambiar).
func _detener_fuerza() -> void:
	f_embestiendo = false
	f_t_embestida = 0.0
	f_slam = false
	f_ataque = false
	_f_ataque_clip = ""
	_f_combo_pedido = false
	_actualizar_mira_roca(false)
	f_recuperacion = 0.0
	f_embestida_golpeados.clear()
	if f_roca != null and is_instance_valid(f_roca):
		if not f_roca.volando:
			f_roca.queue_free()
	f_roca = null
	f_cargando_roca = false
	f_roca_lista = false
	_f_bloqueo_anim = 0.0
	# Cargar el supersalto no cruza de forma: se cancela sin salto.
	_cancelar_super()
	# El IK de la roca se apaga sin dejar nada activo al cambiar de forma.
	if _f_ik != null:
		_f_ik.peso_objetivo = 0.0
		_f_ik.peso_actual = 0.0
		_f_ik.soltar_roca()
	if anim_fuerza != null:
		anim_fuerza.speed_scale = 1.0
	_f_anim_actual = ""

# Entra en la forma Combate (módulo ataque): se muestra el modelo del módulo y
# se reproducen SUS animaciones; el cuerpo, la colisión y la cámara no cambian.
func _entrar_combate() -> void:
	forma = Forma.COMBATE
	_detener_velocista()
	_detener_acuatico()
	_detener_fuerza()
	# Deja limpio cualquier golpe a medias de una entrada anterior a esta forma.
	_detener_combate()
	pivote.position.y = h_pivote_y_base
	# FOV: MISMA configuración central que las demás formas (CamaraZiba:
	# fov_base 70, suavizado 5/s). Se devuelve el objetivo a la base al entrar,
	# así no queda ningún aumento previo (p. ej. el +20 de la supervelocidad) ni
	# la cámara da ningún salto.
	pivote.objetivo_fov = pivote.fov_base
	pivote.objetivo_largo = pivote.largo_base
	velocity = Vector3.ZERO
	# La representación cambia; el cuerpo, la colisión y la cámara no.
	humano.visible = false
	visual.visible = false
	acuatico.visible = false
	fuerza.visible = false
	ataque_visual.visible = true
	_reproducir_combate(ANIM_C_IDLE, BLEND_TRANSFORMACION, true)
	estadisticas.aplicar_forma(id_forma())
	forma_cambiada.emit(id_forma())

# Limpia el estado de la forma Combate al salir de ella (incluido un golpe a
# medias: ni el estado ni el objetivo sobreviven al cambio de forma).
func _detener_combate() -> void:
	c_salto_aire = false
	c_doble_usado = false
	c_estado = C_E.LIBRE
	c_objetivo = null
	c_cadena = 0
	c_golpe = null
	c_fase = 0.0
	c_golpe_hecho = false
	c_acercar_t = 0.0
	# El buffer propio se descarta entero (se recrea con la vida completa la
	# próxima vez): un clic de una forma anterior no puede disparar nada aquí.
	_c_combo = null
	if anim_ataque != null:
		anim_ataque.speed_scale = 1.0
		# Vuelve al clip de reposo para que, si se entra otra vez, no conserve
		# una pose de una acción anterior.
		if anim_ataque.has_animation(ANIM_C_IDLE):
			anim_ataque.stop()

# Apaga y limpia todo lo que la forma velocista pudiera tener activo, para que
# al volver a humano no quede ningún efecto a medias.
func _detener_velocista() -> void:
	estado = Estado.NORMAL
	velocity = Vector3.ZERO
	_parar_carga()
	_parar_trazado()
	efectos.terminar_dash()
	efectos.terminar_carga()
	efectos.terminar_ejecucion()
	efectos.cancelar_ataque()
	trazador.limpiar()
	_restaurar_mascara()
	combate.cancelar_combo()
	pivote.vibracion = 0.0
	pivote.permitir_look = true
	pivote.objetivo_largo = pivote.largo_base
	pivote.objetivo_fov = pivote.fov_base
	pivote.definir_pitch(-0.25)
	pivote.position.y = h_pivote_y_base

# --- SONIDOS de las acciones del velocista (carga, trazado, dash, golpe) -------
# Cada sonido se dispara desde la función REAL que arranca o termina su acción,
# no desde la lectura de un botón: así no suena si la acción no llega a ocurrir y
# no se repite cada fotograma. Todos salen por los AudioStreamPlayer del jugador
# (bus "Efectos").

## Prepara el sonido del TRAZADO para cubrir un recorrido más largo que el propio
## archivo: trabaja sobre una COPIA en memoria del WAV (no toca el recurso original
## ni su importación) y le fija un bucle recortado al tramo útil medido, para que no
## haya pausa de silencio al repetir.
func _configurar_sonidos_velocista() -> void:
	if _sfx_trazado == null:
		return
	var st := _sfx_trazado.stream
	if st is AudioStreamWAV:
		var w := (st as AudioStreamWAV).duplicate() as AudioStreamWAV
		var sr := float(w.mix_rate)
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = int(AUD_INICIO_TRAZADO * sr)
		w.loop_end = int(AUD_FIN_TRAZADO * sr)
		_sfx_trazado.stream = w

func _sonar_carga() -> void:
	if _sfx_carga != null and _sfx_carga.stream != null:
		_sfx_carga.play()

func _parar_carga() -> void:
	if _sfx_carga != null and _sfx_carga.playing:
		_sfx_carga.stop()

func _sonar_trazado() -> void:
	if _sfx_trazado == null or _sfx_trazado.stream == null:
		return
	if _fade_trazado != null and _fade_trazado.is_valid():
		_fade_trazado.kill()
	_sfx_trazado.volume_db = 0.0
	_sfx_trazado.play(AUD_INICIO_TRAZADO)

## Detiene el TRAZADO con un fundido muy breve para que el final (o una
## interrupción) no chasquee. No sincroniza nada: sólo limpia el corte; el arranque
## y el fin los marcan las funciones reales del recorrido.
func _parar_trazado() -> void:
	if _sfx_trazado == null or not _sfx_trazado.playing:
		return
	if _fade_trazado != null and _fade_trazado.is_valid():
		_fade_trazado.kill()
	_fade_trazado = create_tween()
	_fade_trazado.tween_property(_sfx_trazado, "volume_db", -40.0, 0.12)
	_fade_trazado.tween_callback(_detener_trazado_ya)

func _detener_trazado_ya() -> void:
	if _sfx_trazado != null and is_instance_valid(_sfx_trazado):
		_sfx_trazado.stop()
		_sfx_trazado.volume_db = 0.0

func _sonar_dash() -> void:
	if _sfx_dash != null and _sfx_dash.stream != null:
		_sfx_dash.stop()
		_sfx_dash.play()

func _sonar_golpe() -> void:
	if _sfx_golpe != null and _sfx_golpe.stream != null:
		_sfx_golpe.stop()
		_sfx_golpe.play(AUD_INICIO_GOLPE)

# --- SONIDOS de las habilidades de FUERZA -------------------------------------
# Cada sonido se dispara desde la función REAL del evento (no al leer el botón) y
# en su propio reproductor: uno no corta a otro. `stop()`+`play()` garantiza UNA
# emisión por acción aunque la función se llame más de una vez.
func _sonar_fuerza_salto() -> void:
	if _sfx_f_salto != null and _sfx_f_salto.stream != null:
		_sfx_f_salto.stop()
		_sfx_f_salto.play(AUD_F_SALTO)

func _sonar_fuerza_impacto() -> void:
	if _sfx_f_impacto != null and _sfx_f_impacto.stream != null:
		_sfx_f_impacto.stop()
		_sfx_f_impacto.play(AUD_F_IMPACTO)

func _sonar_fuerza_agarre() -> void:
	if _sfx_f_agarre != null and _sfx_f_agarre.stream != null:
		_sfx_f_agarre.stop()
		_sfx_f_agarre.play(AUD_F_AGARRE)

func _sonar_fuerza_tirada() -> void:
	if _sfx_f_tirada != null and _sfx_f_tirada.stream != null:
		_sfx_f_tirada.stop()
		_sfx_f_tirada.play(AUD_F_TIRADA)

func _sonar_fuerza_golpe(es_patada: bool) -> void:
	var p: AudioStreamPlayer = _sfx_f_patada if es_patada else _sfx_f_golpe
	if p == null or p.stream == null:
		return
	p.stop()
	p.play(AUD_F_PATADA if es_patada else AUD_F_GOLPE)

# ============================================================== FORMA HUMANA (Leo)
func _direccion_entrada() -> Vector3:
	var base := pivote.global_transform.basis
	var adelante := -base.z
	adelante.y = 0.0
	adelante = adelante.normalized()
	var derecha := base.x
	derecha.y = 0.0
	derecha = derecha.normalized()
	var v := Vector2.ZERO
	if Input.is_action_pressed("mover_adelante"):
		v.y -= 1.0
	if Input.is_action_pressed("mover_atras"):
		v.y += 1.0
	if Input.is_action_pressed("mover_izquierda"):
		v.x -= 1.0
	if Input.is_action_pressed("mover_derecha"):
		v.x += 1.0
	if v == Vector2.ZERO:
		return Vector3.ZERO
	v = v.normalized()
	return (adelante * (-v.y) + derecha * v.x).normalized()

func _procesar_humano(delta: float) -> void:
	if h_salto_aire and is_on_floor():
		h_salto_aire = false

	# Agacharse (acción "agacharse", reasignable desde CONTROLES; antes leía CTRL
	# directo): no mientras salta.
	h_agachado = Input.is_action_pressed("agacharse") and not h_salto_aire

	var dir := _direccion_entrada()
	var corriendo := Input.is_action_pressed("correr") and not h_agachado
	var vel_objetivo := h_vel_caminar
	if h_agachado:
		vel_objetivo = H_VEL_AGACHADO
	elif corriendo:
		vel_objetivo = h_vel_correr

	var horiz := Vector3(velocity.x, 0.0, velocity.z)
	if dir.length() > 0.05:
		horiz = horiz.move_toward(dir * vel_objetivo, H_ACELERACION * delta)
	else:
		horiz = horiz.move_toward(Vector3.ZERO, H_DESACELERACION * delta)
	velocity.x = horiz.x
	velocity.z = horiz.z

	if not is_on_floor():
		velocity.y -= H_GRAVEDAD * delta
	elif velocity.y < 0.0:
		velocity.y = -0.1

	# No se puede saltar agachado.
	if is_on_floor() and Input.is_action_just_pressed("saltar") and not h_agachado:
		velocity.y = H_SALTO
		_iniciar_salto_humano()

	move_and_slide()
	_orientar_humano(delta, dir)
	_actualizar_altura_camara(delta)
	_actualizar_anim_humano(delta)

func _orientar_humano(delta: float, dir: Vector3) -> void:
	if dir.length() < 0.05:
		return
	var objetivo := atan2(-dir.x, -dir.z)
	humano.rotation.y = lerp_angle(humano.rotation.y, objetivo, 12.0 * delta)

func _iniciar_salto_humano() -> void:
	h_salto_aire = true
	var rapidez := Vector2(velocity.x, velocity.z).length()
	h_anim_salto = ANIM_H_SALTO_CORRIENDO if rapidez > H_VELOCIDAD_SALTO_CORRIENDO else ANIM_H_SALTO
	_reproducir_humano(h_anim_salto)

func _actualizar_anim_humano(delta: float) -> void:
	if anim_humano == null:
		return
	if h_salto_aire:
		anim_humano.speed_scale = 1.0
		_reproducir_humano(h_anim_salto)
		return
	var rapidez := Vector2(velocity.x, velocity.z).length()
	if h_agachado:
		if rapidez < H_UMBRAL_MOVIMIENTO:
			_animar_agachado_quieto(delta)
		else:
			_reproducir_humano(ANIM_H_CROUCH_WALK, H_MEZCLA_AGACHARSE)
			anim_humano.speed_scale = clampf(rapidez / H_VEL_AGACHADO, 0.4, 1.8)
		return
	anim_humano.speed_scale = 1.0
	if rapidez < H_UMBRAL_MOVIMIENTO:
		_reproducir_humano(ANIM_H_IDLE)
	elif Input.is_action_pressed("correr"):
		_reproducir_humano(_clip_humano([ANIM_H_RUN, ANIM_H_WALK]))
	else:
		_reproducir_humano(ANIM_H_WALK)

# Reproduce un clip humano sólo si no está ya sonando (no lo reinicia cada frame).
func _reproducir_humano(nombre: String, mezcla: float = H_MEZCLA) -> void:
	if anim_humano == null or not anim_humano.has_animation(nombre):
		return
	if anim_humano.current_animation != nombre or not anim_humano.is_playing():
		anim_humano.speed_scale = 1.0
		anim_humano.play(nombre, mezcla)

# Devuelve el primer clip de la lista que exista en la librería de Leo.
func _clip_humano(opciones: Array) -> String:
	for opcion in opciones:
		if anim_humano.has_animation(opcion):
			return opcion
	return ANIM_H_IDLE

# Baja el pivote de la cámara al agacharse y lo devuelve a su altura al levantarse.
func _actualizar_altura_camara(delta: float) -> void:
	var objetivo := h_pivote_y_base - (H_ALTURA_AGACHADO if h_agachado else 0.0)
	pivote.position.y = lerpf(pivote.position.y, objetivo, 8.0 * delta)

# Agachado y quieto: si existe "crouch_idle" se reproduce; si no, se usa el ciclo de
# crouch_walk y, tras el fundido de entrada, se congela la pose (igual que el Leo humano).
func _animar_agachado_quieto(delta: float) -> void:
	if anim_humano.has_animation(ANIM_H_CROUCH_IDLE):
		anim_humano.speed_scale = 1.0
		_reproducir_humano(ANIM_H_CROUCH_IDLE, H_MEZCLA_AGACHARSE)
		return
	if anim_humano.current_animation != ANIM_H_CROUCH_WALK or not anim_humano.is_playing():
		_reproducir_humano(ANIM_H_CROUCH_WALK, H_MEZCLA_AGACHARSE)
		anim_humano.speed_scale = 1.0
		h_espera_congelar = H_MEZCLA_AGACHARSE
		return
	if h_espera_congelar > 0.0:
		h_espera_congelar -= delta
		return
	anim_humano.speed_scale = 0.0

# ============================================================== FORMA ACUÁTICA (Pes)
# Misma mecánica de locomoción que la forma humana (mismo cuerpo, colisión y cámara),
# pero reproduciendo los clips ORIGINALES del módulo acuático (sin renombrarlos).
# Además es la ÚNICA forma que puede nadar: en agua honda el cuerpo flota, se
# desplaza en 3D y puede sumergirse (ver _procesar_nado).
func _procesar_acuatico(delta: float) -> void:
	# ESCALERA: mientras se trepa (subiendo o bajando), manda la escalera y no el
	# agua, así el cuerpo recorre la estructura sin que la flotabilidad lo mueva.
	if a_subiendo_escalera:
		_procesar_trepada(delta)
		return
	_tick_cooldowns_agua(delta)
	# 1) ¿Nadar o andar? Lo decide la profundidad REAL del agua bajo los pies.
	_actualizar_estado_agua(delta)

	# 1b) Interacción con la escalera: INTERACTUAR (E) agarra la escalera que haya a
	# mano. Nadando junto al casco sirve para SUBIR a cubierta; de pie arriba, junto
	# a la boca de salida, sirve para BAJAR al agua. Sólo la forma acuática llega aquí.
	if not a_en_habilidad and Input.is_action_just_pressed("interactuar"):
		_intentar_agarrar_escalera()
		if a_subiendo_escalera:
			_procesar_trepada(delta)
			return

	# 2) Mientras corre una habilidad acuática (1-4): sin movimiento horizontal; la
	# animación la manda la habilidad, no se sobrescribe. La vertical sí responde al
	# medio: flotando en la superficie si está nadando, con gravedad si hace pie.
	if a_en_habilidad:
		_actualizar_habilidad_agua(delta)
		velocity.x = 0.0
		velocity.z = 0.0
		# NADANDO, lanzar una habilidad NO saca el cuerpo a flote: se mantiene la cota
		# a la que estaba, así que un hechizo lanzado sumergido sale sumergido. Con
		# "saltar" o CTRL sí se sube o se bucea, como siempre. Haciendo pie, la
		# vertical es la de siempre (flotar/bucear sobre el suelo).
		if a_nadando and not _tecla_vertical_agua():
			velocity.y = move_toward(velocity.y, 0.0, A_AMORTIGUA_VERTICAL * delta)
		else:
			_aplicar_vertical_acuatico(delta)
		move_and_slide()
		return

	# 3) Nado: movimiento en 3D.
	if a_nadando:
		_procesar_nado(delta)
		return

	# 4) Tierra o agua somera: locomoción igual que la forma humana.
	if a_salto_aire and is_on_floor():
		a_salto_aire = false

	a_agachado = Input.is_action_pressed("agacharse") and not a_salto_aire

	var dir := _direccion_entrada()
	var corriendo := Input.is_action_pressed("correr") and not a_agachado
	var vel_objetivo := h_vel_caminar
	if a_agachado:
		vel_objetivo = H_VEL_AGACHADO
	elif corriendo:
		vel_objetivo = h_vel_correr

	var horiz := Vector3(velocity.x, 0.0, velocity.z)
	if dir.length() > 0.05:
		horiz = horiz.move_toward(dir * vel_objetivo, H_ACELERACION * delta)
	else:
		horiz = horiz.move_toward(Vector3.ZERO, H_DESACELERACION * delta)
	velocity.x = horiz.x
	velocity.z = horiz.z

	if not is_on_floor():
		velocity.y -= H_GRAVEDAD * delta
	elif velocity.y < 0.0:
		velocity.y = -0.1

	if is_on_floor() and Input.is_action_just_pressed("saltar") and not a_agachado:
		velocity.y = H_SALTO
		a_salto_aire = true
		_reproducir_acuatico(ANIM_A_JUMP, H_MEZCLA, true)

	# Ataque propio del personaje acuático: reproduce SU animación y aplica su golpe
	# corto por delante (grupo "damageable"), sin crear un sistema de combate nuevo.
	# No se solapa con las habilidades 1-4.
	if is_on_floor() and Input.is_action_just_pressed("atacar") and not a_ataque_activo \
			and not a_agachado and not a_en_habilidad:
		_iniciar_ataque_acuatico()

	move_and_slide()
	# Se orienta TODO el cuerpo hacia la dirección de desplazamiento, igual que la
	# forma Fuerza: hacia atrás (S, S+A, S+D) se camina con el MISMO clip de caminar
	# hacia adelante, girando el cuerpo; no hace falta un clip de retroceso ni se
	# queda postura de guardia. El giro es sobre el nodo visual (Acuatico), así que
	# ni la cámara, ni las colisiones, ni el movimiento general se ven afectados.
	_orientar_acuatico(delta, dir)
	_actualizar_anim_acuatico(delta)

# --- Natación (sólo la forma acuática) ---------------------------------------
## Comprueba si el cuerpo está en agua honda y cambia entre andar y nadar, con su
## clip de transición. La profundidad se mide con `profundidad_agua()`, es decir con
## el fondo REAL del terreno (no con la superficie del agua, que no es una colisión).
func _actualizar_estado_agua(delta: float) -> void:
	# NO basta con que el fondo sea hondo: el cuerpo tiene que estar DE VERDAD dentro
	# del agua. Antes sólo se miraba la profundidad del terreno (x, z), así que si el
	# cuerpo subía por encima de la superficie el estado seguía siendo "nadando" y el
	# personaje quedaba volando fuera del mar sin que nada lo devolviera. Con esta
	# comprobación, en cuanto el cuerpo asoma a la superficie el nado termina y vuelve
	# a valer la gravedad/el suelo: nunca se nada en el aire.
	var en_agua := global_position.y <= SUPERFICIE_MAR + 0.05
	var honda := en_agua and profundidad_agua(global_position.x, global_position.z) > PROFUNDIDAD_NADO
	if honda != a_nadando:
		a_nadando = honda
		a_clip_transicion = ANIM_A_ENTER_WATER if honda else ANIM_A_EXIT_WATER
		if not anim_acuatico_has(a_clip_transicion):
			a_clip_transicion = ""
		a_t_transicion = A_T_ENTRADA_AGUA if honda else A_T_SALIDA_AGUA
		if honda:
			# Al entrar al agua se cancelan los estados de tierra que ya no valen.
			a_salto_aire = false
			a_agachado = false
		if a_clip_transicion != "":
			_reproducir_acuatico(a_clip_transicion, BLEND_AGUA, true)
	if a_t_transicion > 0.0:
		a_t_transicion = maxf(a_t_transicion - delta, 0.0)
		if a_t_transicion <= 0.0:
			a_clip_transicion = ""


## ¿Existe ese clip en la librería del modelo acuático? Evita pedir animaciones que
## no estén importadas.
func anim_acuatico_has(nombre: String) -> bool:
	return anim_acuatico != null and anim_acuatico.has_animation(nombre)


## Cota de flotación (m) en la posición actual: el cuerpo se estabiliza con el agua
## a la altura del pecho, pero nunca por debajo del fondo (en agua somera se apoya
## en el terreno, que es lo que permite salir a la playa caminando).
func _cota_flotacion() -> float:
	var fondo := _relieve.altura(global_position.x, global_position.z)
	return maxf(SUPERFICIE_MAR - A_CALADO_FLOTANDO, fondo)


## Vertical del medio acuático (flotar, subir con "saltar", bucear con CTRL). Se
## usa tanto nadando como durante una habilidad lanzada desde el agua, para que el
## personaje no se hunda mientras la reproduce.
func _aplicar_vertical_acuatico(delta: float) -> void:
	if Input.is_action_pressed("agacharse"):
		velocity.y = move_toward(velocity.y, -A_VEL_VERTICAL_NADO, A_ACEL_NADO * 2.0 * delta)
		return
	# "Saltar" bajo el agua ES nadar hacia arriba, pero ACOTADO a la cota de
	# flotación: en cuanto el cuerpo llega a la superficie deja de empujar y pasa a
	# la flotabilidad de abajo. Antes empujaba siempre a 3,2 m/s sin límite, así que
	# mantener la tecla sacaba al personaje del agua y seguía subiendo (el "vuelo").
	var objetivo := _cota_flotacion()
	if Input.is_action_pressed("saltar") and global_position.y < objetivo - 0.02:
		velocity.y = move_toward(velocity.y, A_VEL_VERTICAL_NADO, A_ACEL_NADO * 2.0 * delta)
		return
	# Flotabilidad: empuja hacia la cota de flotación y amortigua el movimiento, así
	# el cuerpo se queda quieto flotando en vez de oscilar alrededor de la superficie.
	var empuje := clampf((objetivo - global_position.y) * A_FLOTABILIDAD,
			-A_VEL_VERTICAL_NADO, A_VEL_VERTICAL_NADO)
	empuje -= velocity.y * A_AMORTIGUA_VERTICAL
	velocity.y = move_toward(velocity.y, empuje, A_ACEL_NADO * 2.0 * delta)


## NATACIÓN: el agua no es una barrera, es un medio en el que la forma acuática se
## mueve en 3D. Horizontal respecto a la cámara con inercia de pez; vertical con
## flotabilidad (arriba), y buceo con CTRL. Al soltar, el cuerpo vuelve solo a la
## superficie. La colisión sigue siendo la del terreno, así que puede salir a la
## playa caminando sin atravesar el suelo.
func _procesar_nado(delta: float) -> void:
	a_salto_aire = false
	a_agachado = false
	var dir := _direccion_entrada()
	# Mantener "correr" nadando = NADO RÁPIDO. Sólo cambia el horizontal: la vertical
	# la siguen mandando flotar (saltar) y bucear (agacharse), así que no se
	# despega del agua.
	var rapido := Input.is_action_pressed("correr")
	var vel_nado := A_VEL_NADO_RAPIDO if rapido else A_VEL_NADO
	var acel_nado := A_ACEL_NADO_RAPIDO if rapido else A_ACEL_NADO
	# Al SOLTAR SHIFT el cuerpo no vuelve de golpe al nado normal: desacelera con
	# una tasa propia hasta la velocidad de crucero (sensación de pez que se deja
	# llevar). Al acelerar sí se usa la tasa del tramo que se está pidiendo.
	if not rapido and Vector2(velocity.x, velocity.z).length() > A_VEL_NADO + 0.05:
		acel_nado = A_FRENO_NADO_RAPIDO
	var horiz := Vector3(velocity.x, 0.0, velocity.z)
	if dir.length() > 0.05:
		horiz = horiz.move_toward(dir * vel_nado, acel_nado * delta)
	else:
		horiz = horiz.move_toward(Vector3.ZERO, acel_nado * 0.7 * delta)
	velocity.x = horiz.x
	velocity.z = horiz.z

	_aplicar_vertical_acuatico(delta)

	# Ataque cuerpo a cuerpo con el botón de SIEMPRE, también nadando o sumergido. No
	# se solapa con las habilidades 1-4: si hay una en curso, el clic no hace nada.
	if not a_ataque_activo and not a_en_habilidad and Input.is_action_just_pressed("atacar"):
		_iniciar_ataque_acuatico()

	move_and_slide()
	_orientar_acuatico(delta, dir)
	_actualizar_anim_acuatico(delta)


# --- Escalera del barco y del muelle (sólo la forma acuática) -------------------
## INTERACTUAR (E): agarra la escalera que tenga a mano, para SUBIR desde el agua o
## para BAJAR desde la superficie. Las dos comprobaciones son excluyentes (una pide
## estar a la altura del agua y la otra estar de pie arriba), así que nunca se
## solapan ni se puede activar una mientras la otra está en curso.
func _intentar_agarrar_escalera() -> void:
	if escalera_a_mano() != null:
		_intentar_subir_escalera()
	elif escalera_para_bajar() != null:
		_intentar_bajar_escalera()


func _intentar_subir_escalera() -> void:
	var esc := escalera_a_mano()
	if esc == null:
		return
	_iniciar_trepada(esc, false)


func _intentar_bajar_escalera() -> void:
	var esc := escalera_para_bajar()
	if esc == null:
		return
	_iniciar_trepada(esc, true)


## Arranca la trepada. El cuerpo se COLOCA en el recorrido de la escalera (no donde
## estuviera nadando) y se ORIENTA antes de empezar: así el primer fotograma del
## clip ya coincide con la estructura, sin salto ni desalineación.
func _iniciar_trepada(esc: EscaleraBarco, bajando: bool) -> void:
	_escalera_actual = esc
	_escalera_bajando = bajando
	a_subiendo_escalera = true
	_escalera_u = 1.0 if bajando else 0.0
	a_nadando = false
	a_en_habilidad = false
	a_ataque_activo = false
	a_agachado = false
	a_salto_aire = false
	a_t_ataque = 0.0
	velocity = Vector3.ZERO
	_cancelar_carga_agua()
	global_position = esc.punto_trepada(_escalera_u)
	_orientar_al_casco(esc, 1.0)
	_arrancar_clip_trepada(esc, bajando)


## La escalera de barco que el cuerpo tiene a mano AHORA MISMO para SUBIR (o null).
## Es el ÚNICO criterio de interacción: lo usan tanto el agarre con E como el aviso
## "Presioná E para subir al barco" del HUD, así que el mensaje aparece exactamente
## cuando la tecla funciona y desaparece en cuanto deja de funcionar.
func escalera_a_mano() -> EscaleraBarco:
	if forma != Forma.ACUATICO or a_subiendo_escalera:
		return null
	for nodo_arbol in get_tree().get_nodes_in_group("escalera_barco"):
		var esc := nodo_arbol as EscaleraBarco
		if esc != null and esc.puede_subir(global_position):
			return esc
	return null


## La escalera por la que el cuerpo puede BAJAR ahora mismo (de pie arriba, junto a
## la boca de salida), o null. Mismo criterio único que la subida.
func escalera_para_bajar() -> EscaleraBarco:
	if forma != Forma.ACUATICO or a_subiendo_escalera:
		return null
	for nodo_arbol in get_tree().get_nodes_in_group("escalera_barco"):
		var esc := nodo_arbol as EscaleraBarco
		if esc != null and esc.puede_bajar(global_position):
			return esc
	return null


## Texto del aviso contextual que debe mostrar el HUD ("" = ninguno). El HUD lo
## sondea cada fotograma; devolver el mismo texto no reinicia nada, así que el
## mensaje se queda fijo mientras se esté en la zona (sin parpadeos).
func texto_interaccion() -> String:
	# Prioridad 1: el aviso de agua. Explica por qué el cuerpo se ha frenado, así
	# que manda sobre cualquier invitación a pulsar una tecla.
	if _aviso_agua_t > 0.0:
		return TEXTO_SIN_AGUA
	var esc := escalera_a_mano()
	if esc != null:
		return esc.texto_prompt
	var esc_bajar := escalera_para_bajar()
	if esc_bajar != null:
		return esc_bajar.texto_prompt_bajada
	return ""


## Orienta el cuerpo hacia el casco (dirección de mirada de la escalera), con el
## giro extra que necesita cada escalera: el clip de trepada se retargeteó desde FBX
## Mixamo y mira al lado contrario que el resto de la librería acuática, así que sin
## ese giro el cuerpo trepa DE ESPALDAS y las manos quedan del lado del mar, lejos
## de los peldaños (medido con el arnés de diagnóstico).
func _orientar_al_casco(esc: EscaleraBarco, peso: float) -> void:
	var dir: Vector3 = esc.direccion_mirada()
	if dir.length_squared() <= 0.0001:
		return
	var objetivo := atan2(-dir.x, -dir.z) + esc.giro_cuerpo
	acuatico.rotation.y = lerp_angle(acuatico.rotation.y, objetivo, clampf(peso, 0.0, 1.0))


## Clip de trepada de la librería acuática (o null si no está instalado).
func _clip_trepada() -> Animation:
	if anim_acuatico == null or not anim_acuatico.has_animation(ANIM_A_CLIMB):
		return null
	return anim_acuatico.get_animation(ANIM_A_CLIMB)


## Velocidad VERTICAL (m/s) del tramo pegado a la escalera: el recorrido sube de
## `inicio_local.y` a `tope_local.y` a lo largo de la fracción U_INGRESO del progreso.
func _vel_vertical_trepada() -> float:
	return E_VEL_ESCALERA / maxf(EscaleraBarco.U_INGRESO, 0.05)


## Ritmo del clip (ciclos por segundo) para que UN ciclo completo avance exactamente
## `avance_por_ciclo()` metros de peldaños a la velocidad vertical real del recorrido.
## Así las manos y los pies del clip caen siempre en los mismos peldaños: el número de
## ciclos y los metros trepados son proporcionales, sin desfase acumulado.
func _ciclos_trepada_por_segundo(esc: EscaleraBarco) -> float:
	var avance := esc.avance_por_ciclo()
	if avance <= 0.001:
		return 0.0
	return _vel_vertical_trepada() / avance


## Arranca el clip de trepada REPRODUCIÉNDOLO de verdad (a la velocidad que ata sus
## ciclos a los peldaños). Al BAJAR se entra por el final del clip y se reproduce al
## revés: es la misma animación en reversa, así que el primer fotograma de la bajada
## coincide con el último de la subida y los pies vuelven a caer en los mismos
## peldaños. Es un ciclo (LOOP_LINEAR): la trepada dura varios ciclos y las
## extremidades no se quedan congeladas al terminar el primero.
func _arrancar_clip_trepada(esc: EscaleraBarco, bajando: bool) -> void:
	var anim := _clip_trepada()
	if anim == null:
		return
	anim.loop_mode = Animation.LOOP_LINEAR
	var ciclos := _ciclos_trepada_por_segundo(esc)
	anim_acuatico.play(ANIM_A_CLIMB, BLEND_AGUA)
	if ciclos <= 0.0 or anim.length <= 0.0:
		anim_acuatico.speed_scale = 1.0
		return
	anim_acuatico.speed_scale = ciclos * anim.length
	if bajando:
		# `play()` reinicia en 0, así que el salto al FINAL del clip va después.
		anim_acuatico.seek(maxf(anim.length - 0.001, 0.0), true)
		anim_acuatico.speed_scale = -anim_acuatico.speed_scale


## Trepa por la escalera: el cuerpo recorre el camino que declara la propia escalera
## (subida pegada a los peldaños y paso final hacia dentro por la boca de salida).
## El movimiento es guiado, no física de nado: la escalera es un recorrido, y así el
## cuerpo nunca atraviesa el casco ni se queda colgado de una colisión. Durante la
## trepada NO se leen las entradas de movimiento. CTRL suelta y devuelve el cuerpo
## al agua.
func _procesar_trepada(delta: float) -> void:
	if _escalera_actual == null or not is_instance_valid(_escalera_actual):
		_terminar_trepada(true)
		return
	if Input.is_key_pressed(KEY_CTRL):
		_terminar_trepada(true)
		return
	var altura: float = maxf(_escalera_actual.altura_trepada(), 0.1)
	# El avance del cuerpo se mide en CICLOS del clip (no en segundos sueltos), así el
	# desplazamiento por peldaño y la animación van siempre de la mano: los metros que
	# sube el cuerpo en un fotograma son los que marca el ciclo que está reproduciendo.
	# Un ciclo = avance_por_ciclo() de peldaños, y el tramo pegado a la escalera ocupa
	# la fracción U_INGRESO del recorrido.
	var avance := _vel_vertical_trepada() * delta * EscaleraBarco.U_INGRESO / altura
	_escalera_u = clampf(_escalera_u + (-avance if _escalera_bajando else avance), 0.0, 1.0)
	global_position = _escalera_actual.punto_trepada(_escalera_u)
	velocity = Vector3.ZERO
	_orientar_al_casco(_escalera_actual, 12.0 * delta)
	if _escalera_bajando and _escalera_u <= 0.0:
		_terminar_trepada(false)
	elif not _escalera_bajando and _escalera_u >= 1.0:
		_terminar_trepada(false)


## Cierra la trepada. Si terminó el recorrido, deja el cuerpo en el estado que toca
## según dónde quedó: NADANDO si acabó en el agua (bajada) o de pie sobre la
## superficie (subida). Con [param soltar] (salida con CTRL) sólo suelta el anclaje:
## el cuerpo queda donde esté y la lógica de agua/gravedad se encarga.
func _terminar_trepada(soltar: bool) -> void:
	a_subiendo_escalera = false
	_escalera_actual = null
	_escalera_bajando = false
	velocity = Vector3.ZERO
	if anim_acuatico != null:
		anim_acuatico.speed_scale = 1.0
	if soltar:
		a_nadando = false
		return
	var en_agua := global_position.y <= SUPERFICIE_MAR + 0.05 \
			and profundidad_agua(global_position.x, global_position.z) > PROFUNDIDAD_NADO
	a_nadando = en_agua
	if en_agua:
		_reproducir_acuatico(ANIM_A_SWIM_IDLE, BLEND_AGUA, true)
	else:
		# Ya en cubierta: el reposo es el TERRESTRE (Standing Idle), no un clip de
		# agua, y la escala vuelve a 1 para no dejar el ciclo de trepada acelerado.
		_reproducir_acuatico(ANIM_A_IDLE, BLEND_TRANSFORMACION, true)


func _iniciar_ataque_acuatico() -> void:
	# Trepando por la escalera no se ataca (el cuerpo va por un recorrido guiado).
	if a_subiendo_escalera:
		return
	a_ataque_activo = true
	a_ataque_dur = _duracion_clip_acuatico(ANIM_A_ATTACK)
	a_t_ataque = a_ataque_dur
	a_golpe_dado = false
	# El golpe sale hacia donde mira la CÁMARA (la misma dirección que usan las
	# habilidades 1-4), así que el cuerpo se orienta ahí: la animación, el alcance y
	# el daño coinciden aunque se esté nadando de lado.
	var adelante := _direccion_camara_horizontal()
	acuatico.rotation.y = atan2(-adelante.x, -adelante.z)
	_reproducir_acuatico(ANIM_A_ATTACK, BLEND_ATAQUE, true)

func _duracion_clip_acuatico(nombre: String) -> float:
	if anim_acuatico == null or not anim_acuatico.has_animation(nombre):
		return 0.3
	var a := anim_acuatico.get_animation(nombre)
	return a.length if a != null else 0.3


## ¿El jugador está pidiendo subir o bucear? (misma pareja de teclas que gobierna la
## vertical acuática). Se usa para no sacar el cuerpo a flote, sin querer, mientras
## lanza una habilidad nadando.
func _tecla_vertical_agua() -> bool:
	return Input.is_action_pressed("saltar") or Input.is_action_pressed("agacharse")


## Daño del golpe acuático (clic). Es un golpe corto por DELANTE del cuerpo contra el
## grupo "damageable", con el mismo contrato de daño que las habilidades de agua
## (apply_damage y, si el objetivo habla el del paquete Fuerza, take_damage). Vale
## igual en tierra, nadando y sumergido: por eso la comprobación es horizontal, como
## la del golpe del propio módulo acuático, con un margen vertical para alcanzar a
## quien esté de pie justo en la orilla o en el fondo.
func _aplicar_impacto_golpe_acuatico() -> void:
	var adelante := -acuatico.global_transform.basis.z
	adelante.y = 0.0
	adelante = adelante.normalized() if adelante.length_squared() > 0.0001 else Vector3.FORWARD
	var centro := global_position + adelante * A_GOLPE_ALCANCE
	var empuje_dir := Vector3(adelante.x, 0.0, adelante.z)
	for nodo_arbol in get_tree().get_nodes_in_group("damageable"):
		var objetivo := nodo_arbol as Node3D
		if objetivo == null or objetivo == self or not objetivo.is_inside_tree():
			continue
		var radio := A_GOLPE_RADIO
		if objetivo.has_method("get_hit_radius"):
			radio += float(objetivo.call("get_hit_radius"))
		var plano := Vector3(objetivo.global_position.x - centro.x, 0.0,
				objetivo.global_position.z - centro.z)
		if plano.length() > radio:
			continue
		if absf(objetivo.global_position.y - global_position.y) > A_GOLPE_ALCANCE + 1.0:
			continue
		if objetivo.has_method("apply_damage"):
			objetivo.call("apply_damage", A_GOLPE_DANIO, centro, &"melee")
		elif objetivo.has_method("take_damage"):
			var dir := plano
			dir = dir.normalized() if dir.length_squared() > 0.0001 else empuje_dir
			objetivo.call("take_damage", A_GOLPE_DANIO, centro,
					(dir + Vector3.UP * 0.3).normalized() * A_GOLPE_EMPUJE)

func _orientar_acuatico(delta: float, dir: Vector3) -> void:
	if dir.length() < 0.05:
		return
	var objetivo := atan2(-dir.x, -dir.z)
	acuatico.rotation.y = lerp_angle(acuatico.rotation.y, objetivo, 12.0 * delta)

func _actualizar_anim_acuatico(delta: float) -> void:
	if anim_acuatico == null:
		return
	if a_ataque_activo:
		a_t_ataque -= delta
		anim_acuatico.speed_scale = 1.0
		_reproducir_acuatico(ANIM_A_ATTACK)
		# El daño cae en la EXTENSIÓN REAL del brazo dentro del clip (u medida sobre
		# el propio clip), una sola vez por golpe; no en el primer fotograma.
		if not a_golpe_dado and a_ataque_dur > 0.0 \
				and anim_acuatico.current_animation == ANIM_A_ATTACK \
				and anim_acuatico.current_animation_position >= a_ataque_dur * A_GOLPE_IMPACTO_U:
			a_golpe_dado = true
			_aplicar_impacto_golpe_acuatico()
		# Al acabar el clip el golpe se cierra solo y el estado vuelve a ser el que
		# toque: nadando si sigue en el agua, o de pie si está en tierra.
		if a_t_ataque <= 0.0:
			a_ataque_activo = false
			a_ataque_dur = 0.0
		return
	# NATACIÓN: la animación la manda la velocidad REAL (horizontal y vertical), así
	# el personaje no nada quieto ni se desliza por el agua con un clip de caminar.
	if a_nadando:
		if a_t_transicion > 0.0 and anim_acuatico_has(a_clip_transicion):
			anim_acuatico.speed_scale = 1.0
			_reproducir_acuatico(a_clip_transicion)
			return
		var vel := Vector2(velocity.x, velocity.z).length()
		anim_acuatico.speed_scale = 1.0
		if velocity.y < -A_VEL_VERTICAL_NADO * 0.45:
			_reproducir_acuatico(ANIM_A_SWIM_DOWN)
		elif velocity.y > A_VEL_VERTICAL_NADO * 0.45:
			_reproducir_acuatico(ANIM_A_SWIM_UP)
		elif vel > 0.7:
			var avance := Vector3(velocity.x, 0.0, velocity.z).normalized()
			if avance.dot(_direccion_camara_horizontal()) < -0.4:
				_reproducir_acuatico(ANIM_A_SWIM_BACK)
			else:
				_reproducir_acuatico(ANIM_A_SWIM_FORWARD)
				# El clip de avance sigue la velocidad REAL, y con el nado rápido llega
				# a 1,8x: el aleteo se ve claramente más rápido (no hay clip de nado
				# veloz en la librería, así que no se inventa ninguno).
				anim_acuatico.speed_scale = clampf(vel / A_VEL_NADO, 0.6, 2.0)
		else:
			_reproducir_acuatico(ANIM_A_SWIM_IDLE)
		return
	if a_salto_aire:
		anim_acuatico.speed_scale = 1.0
		if velocity.y > 0.0:
			_reproducir_acuatico(ANIM_A_JUMP)
		else:
			_reproducir_acuatico(ANIM_A_FALL)
		return
	var rapidez := Vector2(velocity.x, velocity.z).length()
	if a_agachado:
		anim_acuatico.speed_scale = 1.0
		if rapidez < H_UMBRAL_MOVIMIENTO:
			_reproducir_acuatico(ANIM_A_CROUCH_IDLE)
		else:
			_reproducir_acuatico(ANIM_A_CROUCH_WALK)
		return
	anim_acuatico.speed_scale = 1.0
	if rapidez < H_UMBRAL_MOVIMIENTO:
		_reproducir_acuatico(ANIM_A_IDLE)
	elif Input.is_action_pressed("correr"):
		_reproducir_acuatico(ANIM_A_RUN)
	else:
		_reproducir_acuatico(ANIM_A_WALK)

# Reproduce un clip acuático por su nombre si no está ya sonando (no lo reinicia cada frame).
func _reproducir_acuatico(nombre: String, mezcla: float = H_MEZCLA, forzar: bool = false) -> void:
	if anim_acuatico == null or not anim_acuatico.has_animation(nombre):
		return
	if forzar or anim_acuatico.current_animation != nombre or not anim_acuatico.is_playing():
		anim_acuatico.speed_scale = 1.0
		anim_acuatico.play(nombre, mezcla)

# ------------------------------------------------ Habilidades acuáticas (1-4)
func _tick_cooldowns_agua(delta: float) -> void:
	for key in a_cooldowns.keys():
		if a_cooldowns[key] > 0.0:
			a_cooldowns[key] = maxf(a_cooldowns[key] - delta, 0.0)

# Arranca la habilidad [param idx] (1..4): enfriamiento, animación y carga en la mano.
func _intentar_habilidad_agua(idx: int) -> void:
	# Trepando por la escalera no se lanzan habilidades: el cuerpo va por un
	# recorrido guiado y la animación la manda la escalera, no la habilidad.
	if forma != Forma.ACUATICO or _transformando or a_subiendo_escalera:
		return
	if idx < 1 or idx > ABIL_AGUA.size():
		return
	if a_en_habilidad or a_pendiente > 0 or a_ataque_activo:
		return
	if float(a_cooldowns.get(idx, 0.0)) > 0.0:
		return
	# En tierra hace falta estar de pie; NADANDO (o sumergido) también se puede lanzar:
	# es justo lo que pide el combate en el agua. El resto del lanzamiento (mano,
	# dirección de la cámara, carga, cooldown, animación) es exactamente el de siempre.
	if not is_on_floor() and not a_nadando:
		return
	var nombre_estado := "ability_%d" % idx
	if anim_acuatico == null or not anim_acuatico.has_animation(nombre_estado):
		return
	a_en_habilidad = true
	a_t_habilidad = _duracion_clip_acuatico(nombre_estado) + 0.15
	a_pendiente = idx
	a_pendiente_t = 0.0
	# La dirección se fija AQUÍ (instante de la pulsación), desde la cámara actual.
	# Queda congelada para este lanzamiento: mover la cámara después no la cambia.
	a_dir_ataque = _direccion_camara_horizontal()
	# El personaje se orienta hacia donde va a salir la habilidad (coherente con la cámara).
	acuatico.rotation.y = atan2(-a_dir_ataque.x, -a_dir_ataque.z)
	anim_acuatico.speed_scale = 1.0
	anim_acuatico.play(nombre_estado, BLEND_ATAQUE)
	_iniciar_carga_agua(idx)

# Dirección horizontal (sin componente Y) hacia la que mira la cámara ahora mismo.
# Es la base de la dirección de las habilidades acuáticas y del movimiento.
func _direccion_camara_horizontal() -> Vector3:
	var f := -pivote.global_transform.basis.z
	f.y = 0.0
	if f.length_squared() < 0.0001:
		return Vector3.FORWARD
	return f.normalized()

func _actualizar_habilidad_agua(delta: float) -> void:
	a_t_habilidad -= delta
	if a_pendiente > 0:
		a_pendiente_t += delta
		# Seguro anti-atasco: si la pista de método no llegara, se libera igual.
		if a_pendiente_t > float(ABIL_AGUA[a_pendiente - 1]["release"]) + 0.35:
			_liberar_habilidad_agua(a_pendiente)
	if a_t_habilidad <= 0.0 and a_pendiente <= 0:
		a_en_habilidad = false

# La pista de método de las animaciones ability_N (nodo Acuatico) llama aquí.
func _notificar_liberacion_agua(nombre_estado: String) -> void:
	if a_pendiente <= 0:
		return
	if nombre_estado != "ability_%d" % a_pendiente:
		return
	_liberar_habilidad_agua(a_pendiente)

# Crea el objeto de la habilidad en la mano, mirando hacia donde mira el personaje.
# Reutiliza el objeto del módulo acuático: vuela, choca y hace daño solo.
func _liberar_habilidad_agua(idx: int) -> void:
	if idx < 1 or idx > ABIL_AGUA.size():
		a_pendiente = 0
		return
	a_pendiente = 0
	a_cooldowns[idx] = float(ABIL_AGUA[idx - 1]["cooldown"])
	_release_charge_agua()
	var def: Dictionary = ABIL_AGUA[idx - 1]
	var ability: WaterAbility = (def["script"] as GDScript).new() as WaterAbility
	if ability == null:
		return
	# Dirección capturada al pulsar la habilidad (no la del cuerpo, que no gira).
	var forward := a_dir_ataque
	if forward.length_squared() < 0.0001:
		forward = _direccion_camara_horizontal()
	forward = forward.normalized()
	# ORIGEN: la mano que lanza, ligeramente por delante de ella y alineada con la
	# dirección del ataque. Sigue la animación (si el clip sube o adelanta la mano,
	# el efecto sube o se adelanta con ella). Si el modelo no tuviera el hueso, cae
	# al plan B de siempre para no perder la habilidad.
	var origin := _origen_ataque_agua(forward)
	ability.damage = float(def["damage"])
	ability.hit_radius = float(def["hit_radius"])
	ability.speed = float(def["speed"])
	ability.lifetime = float(def["lifetime"])
	ability.knockback = float(def["knockback"])
	ability.damage_kind = def["kind"]
	if def.has("field_radius"):
		ability.set("field_radius", float(def["field_radius"]))
	if def.has("field_duration"):
		ability.set("field_duration", float(def["field_duration"]))
	if def.has("trap_duration"):
		ability.set("trap_duration", float(def["trap_duration"]))
	var host := get_parent()
	if host == null:
		host = self
	host.add_child(ability)
	ability.setup(self, origin, forward)
	# Orienta el objeto con la dirección de salida (la oleada arma su muro en
	# local, así que su rotación importa; los proyectiles esféricos no se ven afectados).
	ability.rotation.y = atan2(-forward.x, -forward.z)

# Agua que se junta en las manos mientras carga (reutiliza el VFX del módulo).
func _iniciar_carga_agua(idx: int) -> void:
	_cancelar_carga_agua()
	var host := get_parent()
	if host == null:
		return
	var carga: Node3D = preload("res://personaje/transformaciones/acuatica/vfx/water_charge.gd").new() as Node3D
	if carga == null:
		return
	carga.set("player", self)
	carga.set("duration", float(ABIL_AGUA[idx - 1]["release"]))
	# El VFX del módulo sabe verse bajo el agua: se le dice si toca, para que la carga
	# lanzada sumergida se dibuje como tal (mismo efecto, sin duplicarlo).
	carga.set("underwater", a_nadando and global_position.y < SUPERFICIE_MAR - 0.25)
	carga.set("radius", float(ABIL_AGUA[idx - 1]["carga"]))
	host.add_child(carga)
	a_carga = carga

func _release_charge_agua() -> void:
	if a_carga != null and is_instance_valid(a_carga):
		a_carga.call("release")
	a_carga = null

func _cancelar_carga_agua() -> void:
	if a_carga != null and is_instance_valid(a_carga):
		a_carga.queue_free()
	a_carga = null

# --- Mano de lanzamiento (agua) --------------------------------------------
# Esqueleto del modelo acuático (cacheado). Se busca dentro del nodo Visual, que
# es el "slot" del modelo, para no depender de una ruta fija si el modelo cambia.
func _skeleton_agua() -> Skeleton3D:
	if _esqueleto_agua != null and is_instance_valid(_esqueleto_agua):
		return _esqueleto_agua
	var modelo := acuatico.get_node_or_null("Visual")
	if modelo != null:
		_esqueleto_agua = _buscar_esqueleto(modelo)
	return _esqueleto_agua

func _buscar_esqueleto(nodo: Node) -> Skeleton3D:
	for hijo in nodo.get_children():
		if hijo is Skeleton3D:
			return hijo as Skeleton3D
		var profundo := _buscar_esqueleto(hijo)
		if profundo != null:
			return profundo
	return null

# Índice del hueso de una mano, probando los nombres que usan los modelos
# importados (Mixamo con "_" o ":"). -1 si no existe.
func _hueso_mano_agua(esqueleto: Skeleton3D, mano: StringName) -> int:
	if esqueleto == null:
		return -1
	var hueso := esqueleto.find_bone(mano)
	if hueso < 0:
		hueso = esqueleto.find_bone(StringName("mixamorig:" + String(mano)))
	if hueso < 0:
		hueso = esqueleto.find_bone(StringName("mixamorig_" + String(mano)))
	return hueso

# Posición de MUNDO del hueso de una mano. Vector3.INF si no hay esqueleto/hueso.
func _posicion_mano_agua(mano: StringName) -> Vector3:
	var esqueleto := _skeleton_agua()
	var hueso := _hueso_mano_agua(esqueleto, mano)
	if hueso < 0:
		return Vector3.INF
	return esqueleto.global_transform * esqueleto.get_bone_global_pose(hueso).origin

# Sitio del agua que el personaje SOSTIENE en la mano: es el ancla del balón y de
# las cargas de los hechizos. Lo pide water_charge.gd por este nombre.
func get_water_ball_position() -> Vector3:
	var esqueleto := _skeleton_agua()
	var hueso := _hueso_mano_agua(esqueleto, MANO_AGUA)
	if hueso < 0:
		return get_hand_center()
	var ancla: Transform3D = esqueleto.global_transform * esqueleto.get_bone_global_pose(hueso)
	return ancla.origin + ancla.basis * DESPLAZAMIENTO_MANO_AGUA

# Punto medio de las dos manos (plan B / compatibilidad con water_charge.gd).
func get_hand_center() -> Vector3:
	var der := _posicion_mano_agua(&"RightHand")
	var izq := _posicion_mano_agua(&"LeftHand")
	var ok_d := der.is_finite()
	var ok_i := izq.is_finite()
	if ok_d and ok_i:
		return (der + izq) * 0.5
	if ok_d:
		return der
	if ok_i:
		return izq
	return global_position + Vector3.UP * 1.25 + (-global_transform.basis.z) * 0.5

# Origen del proyectil: la mano que lanza, un poco por delante de ella (en la
# dirección del ataque). Si el modelo no tuviera el hueso, plan B: delante del
# pecho, para no romper la habilidad.
func _origen_ataque_agua(adelante: Vector3) -> Vector3:
	var mano := get_water_ball_position()
	if mano.is_finite():
		return mano + adelante * ADELANTE_MANO_AGUA
	return global_position + Vector3.UP * 1.25 + adelante * 0.5

# ============================================================== FORMA FUERZA
# Forma pesada: movimiento lento con inercia + 5 habilidades. Reutiliza los
# scripts/efectos del paquete res://Fuerza/ (FuerzaCombat, FuerzaVfx, FuerzaRock,
# FuerzaShockwave) sobre el MISMO cuerpo, colisión y cámara de Leo.
#
# OJO: el paquete Fuerza no trae su librería de animaciones en este proyecto
# (falta animations/FuerzaUniversal.tres), así que las habilidades se ejecutan a
# nivel de movimiento + efectos + daño, sin clips propios. Ver informe final.
func _procesar_fuerza(delta: float) -> void:
	# El ataque lo gobierna su clip real: dura lo que dura la animación y el
	# daño cae en su extensión (ver _procesar_ataque_fuerza).
	if f_ataque:
		_procesar_ataque_fuerza()
	f_recuperacion = maxf(f_recuperacion - delta, 0.0)

	if f_embestiendo:
		_procesar_embestida_fuerza(delta)
		return
	if f_slam:
		_procesar_slam_fuerza(delta)
		return

	if f_salto_aire and is_on_floor():
		f_salto_aire = false

	f_agachado = Input.is_action_pressed("agacharse") and not f_salto_aire
	var dir := _direccion_entrada()
	var corriendo := Input.is_action_pressed("correr") and not f_agachado
	var vel := F_VEL_CAMINAR
	if f_agachado:
		vel = F_VEL_CAMINAR * 0.6
	elif corriendo:
		vel = F_VEL_CORRER
	if f_cargando_roca:
		vel *= 0.65
	# Freno corto mientras el golpe va camino del impacto; después el clip sólo
	# acompaña la recuperación y el control se alivia (Kick dura 1.6 s).
	if f_ataque:
		vel *= 0.2 if not _f_ataque_golpeado else 0.55
	elif f_recuperacion > 0.0:
		vel *= 0.2

	var horiz := Vector3(velocity.x, 0.0, velocity.z)
	if dir.length() > 0.05:
		horiz = horiz.move_toward(dir * vel, F_ACELERACION * delta)
	else:
		horiz = horiz.move_toward(Vector3.ZERO, F_DESACELERACION * delta)
	velocity.x = horiz.x
	velocity.z = horiz.z

	if not is_on_floor():
		velocity.y -= F_GRAVEDAD * delta
	elif velocity.y < 0.0:
		velocity.y = -0.1

	# --- Supersalto con carga (ESPACIO mantenido en el suelo) ---
	# Mantener ESPACIO carga el salto; un toque corto sigue siendo el salto
	# normal de siempre. Durante el levantamiento de la roca el salto se ignora
	# (la mole a medio camino no debe quedar colgada en el aire). La carga se
	# cancela sin salto si algo la rompe: perder el suelo, agacharse, empezar
	# otra habilidad u abrir el menú.
	if f_super_cargando:
		if not is_on_floor() or f_agachado or f_embestiendo or f_slam or f_cargando_roca:
			_cancelar_super()
		elif not Input.is_action_pressed("saltar"):
			_ejecutar_super()
		else:
			f_super_carga = minf(f_super_carga + delta, F_SUPER_CARGA_MAX)
			_actualizar_carga_super()
	elif is_on_floor() and Input.is_action_just_pressed("saltar") and not f_agachado \
			and not _esta_levantando_roca():
		if _puede_cargar_super():
			f_super_cargando = true
			f_super_carga = 0.0
			_f_flash_indicador = 0.0
			_actualizar_carga_super()
		else:
			# Con otra habilidad en curso, el toque de ESPACIO salta como antes.
			velocity.y = F_SALTO
			f_salto_aire = true
			_reproducir_fuerza(ANIM_F_JUMP, BLEND_SALTO, true)
			_sonar_fuerza_salto()

	# El indicador de carga se queda un instante a tope tras el supersalto.
	if _f_flash_indicador > 0.0 and not f_super_cargando:
		_f_flash_indicador = maxf(_f_flash_indicador - delta, 0.0)
		_actualizar_indicador_super(1.0, _f_flash_indicador > 0.0)

	move_and_slide()
	_orientar_fuerza(delta, dir)
	_actualizar_roca_fuerza()

	# Con la roca en las manos (Q), el clic IZQUIERDO lanza; no pega. Hasta que
	# el clip de levantamiento no ha TERMINADO de verdad (señal del
	# AnimationPlayer, con el selector de clips como red de seguridad) no se
	# atiende ningún clic: la mole tiene que estar arriba antes de apuntar.
	if f_cargando_roca and f_roca != null:
		if not f_roca_lista and (anim_fuerza == null \
				or anim_fuerza.current_animation != ANIM_F_ROCKLIFT):
			f_roca_lista = true
		# Modo apuntado: con la mole ya arriba, el crosshair marca el centro de
		# la pantalla y el lanzamiento sale hacia ese punto objetivo.
		_actualizar_mira_roca(f_roca_lista)
		if f_roca_lista and is_on_floor() and Input.is_action_just_pressed("atacar"):
			_lanzar_roca_fuerza()
		return
	if f_ataque or f_recuperacion > 0.0:
		return
	# Cuerpo a cuerpo: clic izquierdo = puñetazo (doble = combo 1-2), derecho = patada.
	# Golpear cancela una carga de supersalto a medias: la carga nunca decide
	# por el jugador ni se dispara sola más tarde.
	# Regla aérea común: los golpes sólo se INICIAN con los pies en el suelo
	# (el pisotón E y el supersalto siguen siendo acciones aéreas legítimas).
	if is_on_floor() and Input.is_action_just_pressed("atacar"):
		if f_super_cargando:
			_cancelar_super()
		_golpe_fuerza(false)
	elif is_on_floor() and Input.is_action_just_pressed("cargar_poder"):
		if f_super_cargando:
			_cancelar_super()
		_golpe_fuerza(true)

func _orientar_fuerza(delta: float, dir: Vector3) -> void:
	if dir.length() < 0.05:
		return
	var objetivo := atan2(-dir.x, -dir.z)
	fuerza.rotation.y = lerp_angle(fuerza.rotation.y, objetivo, 8.0 * delta)

# --- Animación Fuerza (librería UniversalLibrary -> FuerzaUniversal.tres) ---
# Reproduce los clips del AnimationPlayer del nodo $Fuerza por su nombre simple.
# La elección del clip sólo refleja el estado que ya calcula la lógica de arriba:
# NO cambia la velocidad, los controles ni las habilidades de la transformación.
func _reproducir_fuerza(nombre: String, mezcla: float = H_MEZCLA, forzar: bool = false) -> void:
	if anim_fuerza == null or not anim_fuerza.has_animation(nombre):
		return
	if forzar or _f_anim_actual != nombre:
		_f_anim_actual = nombre
		anim_fuerza.speed_scale = 1.0
		anim_fuerza.play(nombre, mezcla)

# Elige cada fotograma el clip de Fuerza que corresponde al estado. Los clips de
# golpe/roca/pisotón se sostienen un instante (_f_bloqueo_anim) para que lleguen a
# verse, pero ese bloqueo sólo afecta a la animación: el movimiento nunca se frena.
func _actualizar_anim_fuerza(delta: float) -> void:
	if anim_fuerza == null:
		return
	if _f_bloqueo_anim > 0.0:
		_f_bloqueo_anim = maxf(_f_bloqueo_anim - delta, 0.0)
		return
	_reproducir_fuerza(_clip_fuerza())

func _clip_fuerza() -> String:
	# Cargando el supersalto (ESPACIO mantenido en el suelo): flexión de carga.
	if f_super_cargando:
		return ANIM_F_CARGA
	# Cuerpo a cuerpo: manda el clip fijado al golpear (jab / cross / patada).
	if f_ataque and not _f_ataque_clip.is_empty():
		return _f_ataque_clip
	# Embestida con el hombro, pisotón aéreo y su recuperación.
	if f_embestiendo:
		return ANIM_F_SHOULDERRUN
	if f_slam:
		return ANIM_F_AIRSLAM
	if f_recuperacion > 0.0:
		return ANIM_F_SHOULDERECOVER
	# Llevar la roca (Q): sostenerla quieto o andar con ella.
	if f_cargando_roca:
		return ANIM_F_ROCKCARRYWALK if _rapidez_horizontal() > H_UMBRAL_MOVIMIENTO else ANIM_F_ROCKCARRY
	# En el aire: subir = salto, caer = caída.
	if f_salto_aire:
		return ANIM_F_JUMP if velocity.y > 0.0 else ANIM_F_FALL
	# Agachado: quieto o andando agachado.
	if f_agachado:
		return ANIM_F_CROUCHWALK if _rapidez_horizontal() > H_UMBRAL_MOVIMIENTO else ANIM_F_CROUCH
	# Locomoción normal.
	if _rapidez_horizontal() < H_UMBRAL_MOVIMIENTO:
		return ANIM_F_IDLE
	return ANIM_F_RUN if Input.is_action_pressed("correr") else ANIM_F_WALK

func _rapidez_horizontal() -> float:
	return Vector2(velocity.x, velocity.z).length()

# --- Embestida con el hombro (R) ---
func _iniciar_embestida_fuerza() -> void:
	# Cargar el supersalto ocupa la habilidad igual que la roca: nada la
	# interrumpe a medias (se suelta ESPACIO y ya se decide).
	if f_embestiendo or f_cargando_roca or f_super_cargando or not is_on_floor():
		return
	f_embestiendo = true
	f_t_embestida = 0.0
	f_embestida_golpeados.clear()
	var d := _direccion_entrada()
	if d.length() < 0.05:
		d = -pivote.global_transform.basis.z
		d.y = 0.0
	f_embestida_dir = d.normalized() if d.length_squared() > 0.0001 else Vector3.FORWARD
	_reproducir_fuerza(ANIM_F_SHOULDERPREP, BLEND_ATAQUE, true)
	_f_bloqueo_anim = 0.18
	FuerzaVfx.polvo(get_parent(), global_position, 1.2, 16, Color(0.62, 0.55, 0.45), 0.7, 2.6)

func _procesar_embestida_fuerza(delta: float) -> void:
	f_t_embestida += delta
	velocity.x = f_embestida_dir.x * F_EMBESTIDA_VEL
	velocity.z = f_embestida_dir.z * F_EMBESTIDA_VEL
	if not is_on_floor():
		velocity.y -= F_GRAVEDAD * delta
	elif velocity.y < 0.0:
		velocity.y = -0.1
	move_and_slide()
	_orientar_fuerza(delta, f_embestida_dir)
	# Golpea a lo que pille delante, una sola vez por oponente.
	var punto := global_position + Vector3.UP * 1.1 + f_embestida_dir * 0.6
	for objetivo in _objetivos_en_esfera(punto, F_EMBESTIDA_RADIO):
		if f_embestida_golpeados.has(objetivo):
			continue
		f_embestida_golpeados.append(objetivo)
		_golpear_objetivo_fuerza(objetivo, punto, F_EMBESTIDA_DANIO, 14.0)
		FuerzaVfx.chispas(get_parent(), punto, 0.9, 20, Color(1.0, 0.8, 0.4), 0.5, 6.0)
	if f_t_embestida >= F_EMBESTIDA_DUR or is_on_wall():
		f_embestiendo = false
		f_recuperacion = F_EMBESTIDA_RECUP
		velocity.x = 0.0
		velocity.z = 0.0

# --- Supersalto con golpe: pisotón aéreo (E en el aire) ---
func _intentar_slam_fuerza() -> void:
	if f_slam or is_on_floor():
		return
	f_slam = true

func _procesar_slam_fuerza(_delta: float) -> void:
	velocity.x = 0.0
	velocity.z = 0.0
	velocity.y = -F_SLAM_VEL
	move_and_slide()
	if is_on_floor():
		f_slam = false
		f_salto_aire = false
		_reproducir_fuerza(ANIM_F_SLAMIMPACT, BLEND_ATAQUE, true)
		_sonar_fuerza_impacto()
		_f_bloqueo_anim = 0.6
		var onda := FuerzaShockwave.new()
		onda.radius = F_SLAM_RADIO
		onda.damage = F_SLAM_DANIO
		onda.autor = self
		var host := get_parent()
		if host == null:
			host = self
		host.add_child(onda)
		# La onda lee su posición al final del fotograma (call_deferred en su
		# _ready), ya con este global_position aplicado: el impacto cae en el
		# punto real del aterrizaje. La normal del suelo tumba la onda en las
		# pendientes en lugar de dejarla flotando.
		onda.normal_suelo = get_floor_normal()
		onda.global_position = global_position + Vector3.UP * 0.05

# --- Arrancar piedra del suelo (Q) ---
# La roca NACE EN EL SUELO delante del personaje: el clip RockLift horneado
# (agacharse, agarrarla, tirón y alzarla sobre la cabeza) recorre con los
# brazos la misma trayectoria que aquí usa el IK, así que las manos acaban
# siempre sobre la superficie de la piedra y la subida sale de una pieza.
func _intentar_roca_fuerza() -> void:
	if f_roca != null or f_super_cargando or not is_on_floor():
		return
	# Mientras la última piedra LANZADA siga existiendo en el mundo no se
	# arranca otra: soltarla de las manos no significa que haya desaparecido.
	if not _puede_levantar_roca():
		return
	if _f_ik == null:
		_preparar_ik_roca()
	var roca := FuerzaRock.new()
	roca.radius = F_ROCA_TAM
	roca.damage = F_ROCA_DANIO
	roca.impact_radius = F_ROCA_RADIO
	roca.autor = self
	var host := get_parent()
	if host == null:
		host = self
	host.add_child(roca)
	roca.global_position = _posicion_roca_nace()
	roca.sujetar()
	_sonar_fuerza_agarre()
	f_roca = roca
	f_cargando_roca = true
	f_roca_lista = false
	_reproducir_fuerza(ANIM_F_ROCKLIFT, H_MEZCLA, true)
	# El levantamiento ocupa el clip ENTERO: es el fin real del clip (señal del
	# AnimationPlayer) lo que habilita apuntar y lanzar después.
	_f_bloqueo_anim = maxf(_duracion_fuerza(ANIM_F_ROCKLIFT), 0.2)

func _lanzar_roca_fuerza() -> void:
	# Defensa en profundidad: el tiro sólo existe con el levantamiento TERMINADO
	# (el llamador ya lo comprueba).
	if not f_roca_lista:
		return
	if f_roca == null or not is_instance_valid(f_roca):
		f_roca = null
		f_cargando_roca = false
		f_roca_lista = false
		return
	# El IK suelta primero: la roca sale volando desde donde la dejaron las
	# manos y el clip de lanzamiento recupera los brazos con su mezcla corta.
	if _f_ik != null:
		_f_ik.peso_objetivo = 0.0
		_f_ik.soltar_roca()
	# El tiro sale hacia el PUNTO OBJETIVO de la mira (raycast desde el centro
	# de la cámara), resolviendo el ángulo balístico con la gravedad y la
	# velocidad REALES de la piedra: cae donde apunta el crosshair.
	var objetivo := _punto_objetivo_mira()
	var gravedad_efectiva := float(ProjectSettings.get_setting(
		"physics/3d/default_gravity", 9.8)) * f_roca.gravity_scale
	var dir := _direccion_lanzamiento_roca(
		f_roca.global_position, objetivo, F_ROCA_VEL, gravedad_efectiva)
	f_roca.lanzar(dir, F_ROCA_VEL)
	_sonar_fuerza_tirada()
	# La piedra lanzada SIGUE existiendo (vuela, impacta y se desvanece sola):
	# se conserva la referencia hasta que salga del árbol de escena; mientras
	# exista, Q no puede arrancar otra del suelo.
	_f_roca_lanzada = f_roca
	if not _f_roca_lanzada.tree_exited.is_connected(_on_piedra_lanzada_fuera):
		_f_roca_lanzada.tree_exited.connect(_on_piedra_lanzada_fuera)
	f_roca = null
	f_cargando_roca = false
	f_roca_lista = false
	_actualizar_mira_roca(false)
	_reproducir_fuerza(ANIM_F_ROCKTHROW, BLEND_ATAQUE, true)
	_f_bloqueo_anim = maxf(_duracion_fuerza(ANIM_F_ROCKTHROW) - 0.05, 0.2)

# --- Agarre de la roca (trayectoria + IK, compartidos con el horneado) ---
# Mientras la roca está en las manos, cada fotograma se recoloca sobre la
# trayectoria del clip (suelo -> arco por delante -> centrada sobre la cabeza)
# en el espacio del esqueleto, y el IK de brazos lleva las manos a la
# superficie de la piedra. El peso del IK sigue la MISMA curva con la que se
# hornearon los brazos de los clips: cero pelea entre animación e IK.
func _actualizar_roca_fuerza() -> void:
	if f_roca == null or not is_instance_valid(f_roca) or f_roca.volando:
		return
	if _f_ik == null or _f_esqueleto == null:
		return
	var escala := _escala_esqueleto()
	if escala <= 0.0001:
		return
	var r_sk := F_ROCA_TAM / escala
	var c := _centro_roca_sk(r_sk)
	f_roca.global_position = _f_esqueleto.global_transform * c
	_f_ik.peso_objetivo = _peso_ik_roca()
	_f_ik.fijar_roca(c, r_sk)

func _escala_esqueleto() -> float:
	if _f_esqueleto == null:
		return 1.0
	return _f_esqueleto.global_transform.basis.get_scale().x

func _smooth_fuerza(t: float) -> float:
	t = clampf(t, 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)

## Fase (0..1) del levantamiento mientras suena RockLift; 1 en cualquier otro
## momento (roca ya arriba, en el carry).
func _fase_roca() -> float:
	if anim_fuerza == null:
		return 1.0
	if anim_fuerza.current_animation == ANIM_F_ROCKLIFT and anim_fuerza.current_animation_length > 0.0:
		return clampf(anim_fuerza.current_animation_position / anim_fuerza.current_animation_length,
			0.0, 1.0)
	return 1.0

## Peso del IK: durante el levantamiento sube con la misma curva que los brazos
## horneados (0 mientras el personaje se agacha, 1 al agarrar) y luego se queda.
func _peso_ik_roca() -> float:
	var u := _fase_roca()
	if u < 0.12:
		return 0.0
	if u < 0.46:
		return _smooth_fuerza((u - 0.12) / 0.34)
	return 1.0

## Centro de la roca en el espacio del esqueleto. MISMA trayectoria que el
## horneado: sube por delante mientras el cuerpo se yergue y una guarda la
## aparta de la cabeza en el tramo final. Termina centrada encima de ella.
func _centro_roca_sk(r_sk: float) -> Vector3:
	var u := _fase_roca()
	var ht := _altura_cabeza_sk()
	var fy := _smooth_fuerza((u - F_ROCA_U_SUBIDA) / (F_ROCA_U_FIN - F_ROCA_U_SUBIDA))
	var c := Vector3(0.0, lerpf(r_sk * 0.94, ht + r_sk * F_ROCA_CARRY_H + 0.005, fy),
		lerpf(F_ROCA_Z0, 0.02, fy))
	var hc := _centro_cabeza_sk()
	var min_dist := r_sk * (1.0 + F_ROCA_GUARDA)
	var d := c - hc
	if d.length_squared() > 0.000001 and d.length() < min_dist:
		var w_g := _smooth_fuerza((u - 0.58) / 0.10) * (1.0 - _smooth_fuerza((u - 0.86) / 0.14))
		c = c.lerp(hc + d.normalized() * min_dist, w_g)
	# Balanceo corto y contenido al caminar con la piedra (sólo en el carry).
	if u >= 0.999 and anim_fuerza != null and anim_fuerza.current_animation_length > 0.0 \
			and _rapidez_horizontal() > H_UMBRAL_MOVIMIENTO:
		var uw := anim_fuerza.current_animation_position / anim_fuerza.current_animation_length
		c.x += F_ROCA_SWAY * sin(uw * TAU)
	return c

func _altura_cabeza_sk() -> float:
	if _f_esqueleto == null or _f_idx_cabeza_top < 0:
		return 0.0
	return _f_esqueleto.get_bone_global_pose(_f_idx_cabeza_top).origin.y

func _centro_cabeza_sk() -> Vector3:
	if _f_esqueleto == null or _f_idx_cabeza < 0 or _f_idx_cabeza_top < 0:
		return Vector3.ZERO
	return (_f_esqueleto.get_bone_global_pose(_f_idx_cabeza).origin
		+ _f_esqueleto.get_bone_global_pose(_f_idx_cabeza_top).origin) * 0.5

func _duracion_fuerza(nombre: String) -> float:
	if anim_fuerza != null and anim_fuerza.has_animation(nombre):
		return anim_fuerza.get_animation(nombre).length
	return 0.0

## Dónde nace la roca: en el suelo, delante, justo bajo las manos del primer
## fotograma del levantamiento (mismo sitio que el clip horneado).
func _posicion_roca_nace() -> Vector3:
	if _f_esqueleto == null:
		return global_position + Vector3.UP * F_ROCA_TAM
	var r_sk := F_ROCA_TAM / maxf(_escala_esqueleto(), 0.0001)
	return _f_esqueleto.global_transform * Vector3(0.0, r_sk * 0.94, F_ROCA_Z0)

## Crea (una sola vez, la primera vez que se pulsa Q) el modificador de
## esqueleto que recoloca los brazos para agarrar la piedra. Los huesos y la
## escala se leen del propio rig.
func _preparar_ik_roca() -> void:
	_f_esqueleto = _buscar_esqueleto_fuerza()
	if _f_esqueleto == null:
		return
	_f_ik = FuerzaBrazosIK.new()
	_f_ik.name = "BrazosIKRoca"
	var objetivo_izq := Node3D.new()
	objetivo_izq.name = "LeftHandTarget"
	_f_ik.add_child(objetivo_izq)
	var objetivo_der := Node3D.new()
	objetivo_der.name = "RightHandTarget"
	_f_ik.add_child(objetivo_der)
	_f_ik.polo_salida = F_ROCA_POLO_SALIDA
	_f_ik.polo_abajo = F_ROCA_POLO_ABAJO
	_f_ik.polo_atras = F_ROCA_POLO_ATRAS
	_f_ik.peso_objetivo = 0.0
	_f_ik.peso_actual = 0.0
	_f_esqueleto.add_child(_f_ik)
	_f_idx_cabeza = _f_esqueleto.find_bone(&"mixamorig_Head")
	_f_idx_cabeza_top = _f_esqueleto.find_bone(&"mixamorig_HeadTop_End")
	if _f_idx_cabeza_top < 0:
		_f_idx_cabeza_top = _f_idx_cabeza

func _buscar_esqueleto_fuerza() -> Skeleton3D:
	if fuerza == null:
		return null
	var lista := fuerza.find_children("*", "Skeleton3D", true, false)
	if lista.is_empty():
		return null
	return lista[0] as Skeleton3D

# --- Supersalto con carga: lógica y presentación ------------------------------
# Mantener SPACE en el suelo junta fuerza (clip Charge + cámara que baja +
# temblor creciente, como el paquete original); al soltar, la potencia acumulada
# decide entre el salto normal (toque corto) y el supersalto (8..21 m/s con la
# gravedad real de la forma: F_GRAVEDAD = 25). El indicador reutiliza el mismo
# anillo del HUD, colocado abajo en el centro de la pantalla.

func _puede_cargar_super() -> bool:
	return not f_embestiendo and not f_slam and not f_cargando_roca \
		and not f_ataque and f_recuperacion <= 0.0

func _esta_levantando_roca() -> bool:
	return f_cargando_roca and not f_roca_lista

func _actualizar_carga_super() -> void:
	var fr := clampf(f_super_carga / F_SUPER_CARGA_MAX, 0.0, 1.0)
	# La cámara baja con la flexión y el cuerpo tiembla: se le ve juntando fuerza.
	pivote.position.y = h_pivote_y_base - F_SUPER_CAIDA_CAMARA * fr
	pivote.vibracion = lerpf(0.12, 0.6, fr)
	var t := F_SUPER_TEMBLOR * (0.35 + 0.65 * fr)
	fuerza.position = _f_fuerza_pos_base + Vector3(
		randf_range(-t, t), 0.0, randf_range(-t, t))
	_actualizar_indicador_super(fr, true)

func _cancelar_super() -> void:
	f_super_cargando = false
	f_super_carga = 0.0
	_f_flash_indicador = 0.0
	_limpiar_efectos_carga()

## Devuelve cámara, vibración, temblor e indicador a su sitio. Es seguro
## llamarla aunque no haya carga en curso (todo queda como estaba).
func _limpiar_efectos_carga() -> void:
	pivote.position.y = h_pivote_y_base
	pivote.vibracion = 0.0
	fuerza.position = _f_fuerza_pos_base
	_actualizar_indicador_super(0.0, false)

func _ejecutar_super() -> void:
	var cargado := f_super_carga
	f_super_cargando = false
	f_super_carga = 0.0
	_limpiar_efectos_carga()
	if not is_on_floor():
		# Red de seguridad: sin suelo no hay despegue.
		return
	if cargado < F_SUPER_CARGA_MIN:
		# Toque corto: el salto NORMAL de siempre, sin ceremonial.
		velocity.y = F_SALTO
		f_salto_aire = true
		_reproducir_fuerza(ANIM_F_JUMP, BLEND_SALTO, true)
		_sonar_fuerza_salto()
		return
	var fr := clampf(inverse_lerp(F_SUPER_CARGA_MIN, F_SUPER_CARGA_MAX, cargado), 0.0, 1.0)
	velocity.y = lerpf(F_SUPER_VEL_MIN, F_SUPER_VEL_MAX, fr)
	f_salto_aire = true
	# La carrerilla se conserva tal cual; si salía casi parado, empujón mínimo
	# hacia donde apunta la entrada (o donde mira el modelo).
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	if horizontal.length() < F_SUPER_IMPULSO:
		var rumbo := _direccion_entrada()
		if rumbo.length() < 0.05:
			rumbo = -fuerza.global_transform.basis.z
			rumbo.y = 0.0
			rumbo = rumbo.normalized() if rumbo.length_squared() > 0.0001 else Vector3.FORWARD
		velocity.x = rumbo.x * F_SUPER_IMPULSO
		velocity.z = rumbo.z * F_SUPER_IMPULSO
	_reproducir_fuerza(ANIM_F_SUPERJUMP, BLEND_SALTO, true)
	_f_bloqueo_anim = maxf(_duracion_fuerza(ANIM_F_SUPERJUMP), 0.2)
	_sonar_fuerza_salto()
	# El indicador se queda un momento a tope: se ve la fuerza que llevaba.
	_f_flash_indicador = 0.35
	_actualizar_indicador_super(1.0, true)
	# El suelo se agrieta bajo los pies y la cámara lo nota.
	FuerzaVfx.polvo(get_parent(), global_position, 1.5 + fr, 20,
		Color(0.62, 0.55, 0.45), 0.9, 2.6 + fr * 2.0)
	FuerzaCombat.sacudir_camara(get_tree(), F_SUPER_SACUDIDA * (0.45 + 0.55 * fr))

func _preparar_indicador_super() -> void:
	if _f_relleno != null:
		return
	# Se cuelga del CanvasLayer del HUD que el jugador ya usa (mismo estilo que
	# los anillos de vida/escudo). Dos ColorRect DIRECTOS al HUD: el fondo
	# oscuro de la interfaz y el relleno dorado que crece con la carga.
	var capa := get_node_or_null("HUD") as CanvasLayer
	if capa == null:
		capa = CanvasLayer.new()
		capa.name = "HUDSuperSalto"
		capa.layer = 2
		add_child(capa)
	_f_fondo = ColorRect.new()
	_f_fondo.name = "BarraCargaFondo"
	_f_fondo.color = Color(0.08, 0.09, 0.12, 0.7)
	_f_fondo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_f_fondo.size = Vector2(F_SUPER_BARRA_LARGO + 12.0, F_SUPER_BARRA_ALTO + 12.0)
	capa.add_child(_f_fondo)
	_f_relleno = ColorRect.new()
	_f_relleno.name = "BarraCargaRelleno"
	_f_relleno.color = Color(1.0, 0.78, 0.35, 1.0)
	_f_relleno.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_f_relleno.size = Vector2(0.0, F_SUPER_BARRA_ALTO)
	capa.add_child(_f_relleno)
	_posicionar_indicador_super()
	_actualizar_indicador_super(0.0, false)

func _posicionar_indicador_super() -> void:
	if _f_fondo == null or _f_relleno == null:
		return
	var vp := get_viewport().get_visible_rect().size
	# Esquina inferior izquierda: zona siempre libre de la pantalla (el jugador
	# se ve centrado y el HUD de vida está en la derecha).
	var x := 52.0
	var y := vp.y - F_SUPER_BARRA_ALTO - 56.0
	_f_fondo.position = Vector2(x - 6.0, y - 6.0)
	_f_relleno.position = Vector2(x, y)

func _actualizar_indicador_super(valor: float, mostrar: bool) -> void:
	if _f_fondo == null or _f_relleno == null:
		return
	_f_fondo.visible = mostrar
	_f_relleno.visible = mostrar
	if not mostrar:
		return
	_posicionar_indicador_super()
	_f_relleno.size = Vector2(F_SUPER_BARRA_LARGO * clampf(valor, 0.0, 1.0),
		F_SUPER_BARRA_ALTO)
	# Al tope la barra late: avisa de que el salto saldrá a máxima potencia.
	var brillo := 0.0
	if valor >= 1.0:
		brillo = 0.25 + 0.25 * sin(Time.get_ticks_msec() / 1000.0 * 8.0)
	_f_relleno.color = Color(1.0, 0.78, 0.35).lerp(Color(1.0, 0.95, 0.7), brillo)

# --- Mira del apuntado de la roca ---------------------------------------------
# Cruz fina con contorno en el centro EXACTO de la pantalla. Vive en el
# CanvasLayer del HUD, así que queda fija aunque la cámara se mueva; sólo se
# enciende mientras la piedra está arriba, lista para apuntar y lanzar.
func _preparar_mira_roca() -> void:
	if _f_mira != null:
		return
	var capa := get_node_or_null("HUD") as CanvasLayer
	if capa == null:
		capa = CanvasLayer.new()
		capa.name = "HUDMiraRoca"
		capa.layer = 2
		add_child(capa)
	_f_mira = Control.new()
	_f_mira.name = "MiraRoca"
	_f_mira.mouse_filter = Control.MOUSE_FILTER_IGNORE
	capa.add_child(_f_mira)
	# Brazos de la cruz + punto central: [desplazamiento, tamaño] desde (0,0).
	var piezas: Array = [
		[Vector2(-F_MIRA_HUECO - F_MIRA_LARGO, -F_MIRA_GROSOR * 0.5),
			Vector2(F_MIRA_LARGO, F_MIRA_GROSOR)],
		[Vector2(F_MIRA_HUECO, -F_MIRA_GROSOR * 0.5),
			Vector2(F_MIRA_LARGO, F_MIRA_GROSOR)],
		[Vector2(-F_MIRA_GROSOR * 0.5, -F_MIRA_HUECO - F_MIRA_LARGO),
			Vector2(F_MIRA_GROSOR, F_MIRA_LARGO)],
		[Vector2(-F_MIRA_GROSOR * 0.5, F_MIRA_HUECO),
			Vector2(F_MIRA_GROSOR, F_MIRA_LARGO)],
		[Vector2(-F_MIRA_PUNTO * 0.5, -F_MIRA_PUNTO * 0.5),
			Vector2(F_MIRA_PUNTO, F_MIRA_PUNTO)],
	]
	for pieza in piezas:
		var pos: Vector2 = pieza[0]
		var tam: Vector2 = pieza[1]
		var sombra := ColorRect.new()
		sombra.color = F_MIRA_SOMBRA
		sombra.mouse_filter = Control.MOUSE_FILTER_IGNORE
		sombra.position = pos - Vector2.ONE
		sombra.size = tam + Vector2.ONE * 2.0
		_f_mira.add_child(sombra)
		var luz := ColorRect.new()
		luz.color = F_MIRA_COLOR
		luz.mouse_filter = Control.MOUSE_FILTER_IGNORE
		luz.position = pos
		luz.size = tam
		_f_mira.add_child(luz)
	_actualizar_mira_roca(false)

func _actualizar_mira_roca(mostrar: bool) -> void:
	if _f_mira == null:
		return
	_f_mira.visible = mostrar
	if not mostrar:
		return
	var vp := get_viewport().get_visible_rect().size
	_f_mira.position = (vp * 0.5).round()

## Punto del mundo al que apunta el centro de la cámara: raycast sobre el
## escenario y los cuerpos; si no encuentra superficie, un punto lejano en esa
## misma dirección (alcance máximo razonable).
func _punto_objetivo_mira() -> Vector3:
	var origen := pivote.global_position
	var dir := -pivote.global_transform.basis.z
	var mundo := get_world_3d()
	if mundo != null:
		var consulta := PhysicsRayQueryParameters3D.create(
			origen, origen + dir * F_MIRA_ALCANCE, 1, [get_rid()])
		var golpe: Dictionary = mundo.direct_space_state.intersect_ray(consulta)
		if golpe.has("position"):
			return golpe["position"]
	return origen + dir * F_MIRA_ALCANCE

## Dirección inicial para que la piedra (con su velocidad y su gravedad reales)
## caiga en el punto objetivo: solución balística de ángulo bajo. Fuera de
## alcance, tiro directo (la física hará que caiga donde llegue).
func _direccion_lanzamiento_roca(origen: Vector3, objetivo: Vector3,
		velocidad: float, gravedad_tiro: float) -> Vector3:
	var a_objetivo := objetivo - origen
	var horiz := Vector3(a_objetivo.x, 0.0, a_objetivo.z)
	var d := horiz.length()
	if a_objetivo.length_squared() < 0.0001:
		return -pivote.global_transform.basis.z
	if d < 0.25 or gravedad_tiro <= 0.001 or velocidad <= 0.001:
		return a_objetivo.normalized()
	var v2 := velocidad * velocidad
	var raiz := v2 * v2 - gravedad_tiro * (gravedad_tiro * d * d + 2.0 * a_objetivo.y * v2)
	if raiz < 0.0:
		return a_objetivo.normalized()
	var tan_theta := (v2 - sqrt(raiz)) / (gravedad_tiro * d)
	return (horiz / d + Vector3.UP * tan_theta).normalized()

# --- Piedra lanzada: no se puede arrancar otra mientras siga en el mundo ------
## ¿Está el camino libre para arrancar una piedra nueva?
func _puede_levantar_roca() -> bool:
	if _f_roca_lanzada == null:
		return true
	# El objeto puede haberse liberado ya (is_instance_valid) o estar en cola de
	# liberación este mismo fotograma (is_queued_for_deletion): en ambos casos
	# ya no existe para el mundo y la habilidad vuelve a estar disponible.
	if not is_instance_valid(_f_roca_lanzada) or _f_roca_lanzada.is_queued_for_deletion():
		_f_roca_lanzada = null
		return true
	return false

func _on_piedra_lanzada_fuera() -> void:
	# Señal tree_exited: la piedra salió definitivamente del árbol de escena.
	_f_roca_lanzada = null

## Cancela un levantamiento a medias SIN dejar la piedra en mala posición: la
## piedra se retira (no llegó a levantarse) y el IK se apaga, igual que hace
## _detener_fuerza al cambiar de forma.
func _soltar_roca_interrumpida() -> void:
	if f_roca != null and is_instance_valid(f_roca) and not f_roca.volando:
		f_roca.queue_free()
	f_roca = null
	f_cargando_roca = false
	f_roca_lista = false
	_actualizar_mira_roca(false)
	if _f_ik != null:
		_f_ik.peso_objetivo = 0.0
		_f_ik.peso_actual = 0.0
		_f_ik.soltar_roca()

# --- Señal del AnimationPlayer ------------------------------------------------
func _on_animacion_fuerza_terminada(nombre: StringName) -> void:
	# Fin REAL del clip de levantamiento: desde aquí la roca está arriba de
	# verdad (el fin de RockLift es el primer fotograma de RockCarry) y se puede
	# apuntar, andar con ella y lanzarla.
	if nombre == ANIM_F_ROCKLIFT and f_cargando_roca:
		f_roca_lista = true
	# Fin REAL del clip de golpe: el ataque dura lo que dura la animación.
	if f_ataque and not _f_ataque_clip.is_empty() and nombre == _f_ataque_clip:
		_terminar_ataque_fuerza()

# --- Cuerpo a cuerpo (puñetazo / combo / patada) ---
# La duración de cada golpe es la del CLIP REAL: la animación nunca se corta a
# medias y el personaje sólo vuelve a la locomoción cuando el golpe termina.
func _golpe_fuerza(es_patada: bool) -> void:
	if f_ataque:
		# Un puñetazo pedido durante el jab queda ENCOLADO: el cross sale al
		# terminar el golpe en curso, jamás cortándolo a media animación.
		if not es_patada and _f_ataque_clip == ANIM_F_PUNCH_L:
			_f_combo_pedido = true
		return
	if es_patada:
		_f_combo_pedido = false
		_iniciar_ataque_fuerza(ANIM_F_KICK)
		return
	var ahora := Time.get_ticks_msec() / 1000.0
	var combo := _f_clip_terminado == ANIM_F_PUNCH_L and f_ultimo_golpe > 0.0 \
		and (ahora - f_ultimo_golpe < F_COMBO_VENTANA)
	_iniciar_ataque_fuerza(ANIM_F_PUNCH_R if combo else ANIM_F_PUNCH_L)

## Arranca un golpe completo: clip entero desde el principio y daño pendiente
## hasta la extensión real del puño o del pie.
func _iniciar_ataque_fuerza(clip: String) -> void:
	f_ataque = true
	_f_ataque_clip = clip
	_f_ataque_dur = _duracion_fuerza(clip)
	_f_ataque_impacto_u = float(F_IMPACTO_U.get(clip, 0.29))
	_f_ataque_golpeado = false
	_reproducir_fuerza(clip, BLEND_ATAQUE, true)

## Sigue el golpe por la posición REAL del clip: el daño se aplica cuando el
## puño o el pie alcanzan su extensión (u medida sobre los propios clips) y el
## ataque se cierra cuando la animación termina de verdad (posición o señal).
func _procesar_ataque_fuerza() -> void:
	if anim_fuerza == null or _f_ataque_clip.is_empty() \
			or anim_fuerza.current_animation != _f_ataque_clip:
		# Otra cosa tomó el AnimationPlayer (salto, menú, cambio de forma):
		# el golpe ya no está en curso y se suelta sin dejarlo bloqueado.
		_terminar_ataque_fuerza()
		return
	var pos := anim_fuerza.current_animation_position
	if not _f_ataque_golpeado and _f_ataque_dur > 0.0 \
			and pos >= _f_ataque_dur * _f_ataque_impacto_u:
		_f_ataque_golpeado = true
		_aplicar_impacto_golpe_fuerza()
	if pos >= _f_ataque_dur - 0.02 or not anim_fuerza.is_playing():
		_terminar_ataque_fuerza()

func _aplicar_impacto_golpe_fuerza() -> void:
	var es_patada := _f_ataque_clip == ANIM_F_KICK
	_sonar_fuerza_golpe(es_patada)
	var dano := F_PATADA_DANIO if es_patada else F_PUNIO_DANIO
	var altura := F_PATADA_ALTURA if es_patada else F_GOLPE_ALTURA
	var punto := _punto_golpe_fuerza(altura)
	_golpear_esfera_fuerza(punto, F_GOLPE_RADIO, dano, 6.0)
	FuerzaVfx.chispas(get_parent(), punto, 0.7, 16, Color(1.0, 0.85, 0.5), 0.4, 5.0)

func _terminar_ataque_fuerza() -> void:
	if not f_ataque:
		return
	f_ataque = false
	_f_clip_terminado = _f_ataque_clip
	_f_ataque_clip = ""
	_f_ataque_dur = 0.0
	# La ventana de combo se cuenta desde que el golpe TERMINÓ.
	f_ultimo_golpe = Time.get_ticks_msec() / 1000.0
	# Puñetazo encadenado pedido durante el jab: ahora sí, clip nuevo entero.
	# Si el golpe terminó en el aire (se saltó a mitad), el encadenado se
	# descarta: en el aire no se inicia ninguna animación de ataque nueva, y
	# tampoco queda nada pendiente que se dispare al aterrizar.
	if _f_combo_pedido and _f_clip_terminado == ANIM_F_PUNCH_L and is_on_floor():
		_f_combo_pedido = false
		_iniciar_ataque_fuerza(ANIM_F_PUNCH_R)
	else:
		_f_combo_pedido = false

func _punto_golpe_fuerza(altura: float) -> Vector3:
	var adelante := -fuerza.global_transform.basis.z
	adelante.y = 0.0
	adelante = adelante.normalized() if adelante.length_squared() > 0.0001 else Vector3.FORWARD
	return global_position + Vector3.UP * altura + adelante * F_GOLPE_ALCANCE

# --- Daño (reutiliza el contrato del paquete Fuerza: grupo "damageable" + take_damage) ---
func _golpear_esfera_fuerza(centro: Vector3, radio: float, dano: float, empuje: float) -> void:
	var mundo := get_world_3d()
	if mundo == null:
		return
	var excluir: Array = [get_rid()]
	FuerzaCombat.golpear_esfera(mundo.direct_space_state, centro, radio, dano, empuje, excluir, 0.4, 0.3)

func _golpear_objetivo_fuerza(nodo: Node3D, centro: Vector3, dano: float, empuje: float) -> void:
	if not nodo.has_method("take_damage"):
		return
	var dir := nodo.global_position - centro
	dir.y = 0.0
	dir = dir.normalized() if dir.length_squared() > 0.0001 else Vector3.FORWARD
	nodo.call("take_damage", dano, centro, (dir + Vector3.UP * 0.3).normalized() * empuje)

func _objetivos_en_esfera(centro: Vector3, radio: float) -> Array:
	var out: Array = []
	for n in get_tree().get_nodes_in_group("damageable"):
		var t := n as Node3D
		if t == null or t == self or not t.is_inside_tree():
			continue
		if centro.distance_to(t.global_position) <= radio:
			out.append(t)
	return out

# La forma velocista debe verse EXACTAMENTE del mismo tamaño que Leo humano. La causa
# real de la diferencia NO es un nodo padre ni la importación: son escalas base distintas.
# El FBX de Leo viene en unidades diminutas (leo.tscn lo compensa con escala 200 -> ~1.95 m),
# mientras que el FBX del velocista ya viene en metros (~0.98 m). Se normaliza la escala del
# modelo velocista a la altura real de Leo, en lugar de tocar el CharacterBody3D o la colisión.
func _ajustar_escala_velocista() -> void:
	var h_leo := _altura_visual(humano)
	var h_vel := _altura_visual(vel_modelo)
	if h_leo > 0.001 and h_vel > 0.001:
		var s := h_leo / h_vel
		vel_modelo.scale = Vector3(s, s, s)

# La forma acuática (Pes) también debe verse del mismo tamaño que Leo humano. El
# modelo del módulo acuático ya viene en metros (~1.75 m); se normaliza su escala
# a la altura real de Leo en lugar de tocar el CharacterBody3D o la colisión.
func _ajustar_escala_acuatico() -> void:
	var h_leo := _altura_visual(humano)
	var h_ac := _altura_visual(acuatico)
	if h_leo > 0.001 and h_ac > 0.001:
		var s := h_leo / h_ac
		acuatico.scale = Vector3(s, s, s)

# La forma Fuerza también se normaliza a la altura real de Leo (el FBX trae su
# propia escala); no se toca el CharacterBody3D ni la colisión.
func _ajustar_escala_fuerza() -> void:
	var h_leo := _altura_visual(humano)
	var h_f := _altura_visual(fuerza)
	if h_leo > 0.001 and h_f > 0.001:
		var s := h_leo / h_f
		fuerza.scale = Vector3(s, s, s)

# Altura de la caja envolvente de todas las mallas de un subárbol, medida en el espacio
# local del nodo indicado (incluye su propia escala actual).
func _altura_visual(raiz: Node3D) -> float:
	var inv := raiz.global_transform.affine_inverse()
	var caja := AABB()
	var cont := 0
	for nodo in raiz.find_children("*", "MeshInstance3D", true, false):
		var mi := nodo as MeshInstance3D
		if mi.mesh == null:
			continue
		var c: AABB = (inv * mi.global_transform) * mi.mesh.get_aabb()
		caja = c if cont == 0 else caja.merge(c)
		cont += 1
	return caja.size.y

# ============================================================== FORMA COMBATE (módulo ataque)
# Locomoción de la forma Combate: misma mecánica que la forma humana (mismo
# cuerpo, colisión y cámara), con las constantes de movimiento del módulo ataque
# y reproduciendo sus clips originales (combat_idle/walk/jump).
#
# ATAQUE FreeFlow (recuperado del módulo ataque): el clic izquierdo reproduce su
# sistema completo sobre este cuerpo — selección contextual de objetivo
# (CombatTargeting: intención = dirección de movimiento + cámara + orientación),
# acercamiento si el objetivo está lejos, orientación progresiva (nunca un giro
# seco) y cadena de cuatro golpes (jab/dos/cros/gancho del propio módulo). El
# objetivo se REELIGE al comenzar CADA golpe: girar/moverse hacia otro enemigo y
# volver a pulsar redirige el siguiente ataque sin esperar al final del combo.
# La cadena, la ventana de impacto y el buffer de entrada son los del módulo
# (SPRINT/HIT_WINDOW/combo_system): si la partida tiene gestor de encuentro se
# usan SUS datos (config, amenazas, combo) y, si no lo tiene, los del config del
# propio módulo — el combate funciona igual, sin depender de escenas externas.
#
# REGLA AÉREA (única para todas las formas): sin suelo no se inicia NINGUNA
# acción de combate. El clic EN EL AIRE no llega a encolarse siquiera, así que
# no queda nada pendiente que pueda dispararse al aterrizar.

# La representación de la forma Combate (módulo ataque) se ve del mismo tamaño
# que Leo humano: se normaliza su escala a la altura real de Leo, igual que las
# demás formas (no se toca el CharacterBody3D ni la colisión).
func _ajustar_escala_ataque() -> void:
	var h_leo := _altura_visual(humano)
	var h_c := _altura_visual(ataque_visual)
	if h_leo > 0.001 and h_c > 0.001:
		var s := h_leo / h_c
		ataque_visual.scale = Vector3(s, s, s)

func _procesar_combate(delta: float) -> void:
	if c_salto_aire and is_on_floor():
		c_salto_aire = false
		c_doble_usado = false

	var dir := _direccion_entrada()
	# El clic se encola CON SUELO (también durante un golpe en curso: así el
	# siguiente golpe de la cadena sale al empezar la recuperación, FreeFlow).
	# En el aire NO se encola nada: ningún clic aéreo puede quedar pendiente.
	var combo: Variant = _combo_combate()
	if combo != null:
		if _gestor_encuentro() == null:
			# Sin gestor en la escena, el buffer es el propio y lo avanza este
			# controlador (el gestor, si existe, lo actualiza él mismo).
			combo.update(delta)
		if is_on_floor() and Input.is_action_just_pressed("atacar"):
			combo.push_input("attack", dir, 10)
	match c_estado:
		C_E.ACERCARSE:
			_c_estado_acercarse(delta)
		C_E.PREPARAR:
			_c_estado_preparar(delta)
		C_E.ACTIVO:
			_c_estado_activo(delta)
		C_E.RECUPERAR:
			_c_estado_recuperar(delta)
		_:
			_c_locomocion_combate(delta, dir)

	move_and_slide()
	# Fuera del estado libre la orientación la lleva el propio golpe (hacia el
	# objetivo, a ritmo limitado); la locomoción solo orienta al caminar.
	if c_estado == C_E.LIBRE:
		_orientar_combate(delta, dir)
	_actualizar_anim_combate()

func _orientar_combate(delta: float, dir: Vector3) -> void:
	if dir.length() < 0.05:
		return
	var objetivo := atan2(-dir.x, -dir.z)
	ataque_visual.rotation.y = lerp_angle(ataque_visual.rotation.y, objetivo, C_GIRO * delta)

## Locomoción libre de la forma Combate + lectura y encolado del golpe.
func _c_locomocion_combate(delta: float, dir: Vector3) -> void:
	var horiz := Vector3(velocity.x, 0.0, velocity.z)
	if dir.length() > 0.05:
		horiz = horiz.move_toward(dir * C_VEL_CAMINAR, C_ACELERACION * delta)
	else:
		horiz = horiz.move_toward(Vector3.ZERO, C_DESACELERACION * delta)
	velocity.x = horiz.x
	velocity.z = horiz.z

	if not is_on_floor():
		velocity.y -= C_GRAVEDAD * delta
	elif velocity.y < 0.0:
		velocity.y = -0.1

	# Salto: el de suelo y, si aún no se usó, un segundo impulso en el aire
	# (doble salto). Al aterrizar se recuperan los dos: no hay tercer salto.
	if Input.is_action_just_pressed("saltar"):
		if is_on_floor():
			velocity.y = C_SALTO
			c_salto_aire = true
			c_doble_usado = false
			# _reproducir_combate con forzar REINICIA el clip si ya sonaba: el
			# doble salto vuelve a empezar la animación desde el principio.
			_reproducir_combate(ANIM_C_JUMP, C_MEZCLA_SALTO, true)
		elif not c_doble_usado:
			c_doble_usado = true
			c_salto_aire = true
			velocity.y = C_DOBLE_SALTO
			_reproducir_combate(ANIM_C_JUMP, C_MEZCLA_SALTO, true)

	# Ataque: se consume lo que ya haya encolado (el encolado ocurre una vez por
	# frame en _procesar_combate, y sólo desde el suelo).
	var combo: Variant = _combo_combate()
	if combo != null:
		var act: Dictionary = combo.pop_valid(_puede_iniciar_golpe)
		if not act.is_empty():
			_iniciar_golpe_combate()

## Regla aérea del módulo: sin suelo no se inicia ninguna acción de combate (y
## por tanto no se selecciona objetivo). El clic en el aire no llega a encolarse.
func _puede_iniciar_golpe(action: String) -> bool:
	if not is_on_floor():
		return false
	return action == "attack"

## Gestor del encuentro (si la partida lo tiene): aporta config, amenazas y la
## lista de enemigos activos, igual que para los enemigos registrados.
func _gestor_encuentro() -> Node:
	if _gestor_combate == null or not is_instance_valid(_gestor_combate):
		_gestor_combate = get_tree().get_first_node_in_group("combat_manager")
		# El gestor ya avisa cuando un enemigo muere: con eso el objetivo se suelta
		# al instante y nunca queda una referencia a un nodo liberado.
		if _gestor_combate != null and _gestor_combate.has_signal("enemy_died") \
				and not _gestor_combate.enemy_died.is_connected(_on_enemigo_combate_muerto):
			_gestor_combate.enemy_died.connect(_on_enemigo_combate_muerto)
	return _gestor_combate

## Enemigo del encuentro que acaba de morir: si era el objetivo del FreeFlow se
## suelta la referencia (y se apaga el indicador) sin esperar al siguiente fotograma.
func _on_enemigo_combate_muerto(enemigo: Node3D) -> void:
	if enemigo == c_objetivo:
		c_objetivo = null
		_actualizar_indicador_objetivo()

## Config vigente: la del gestor si existe; si no, la del propio módulo de
## ataque (los MISMOS valores del sistema FreeFlow: no se inventa ninguno).
func _cfg_encuentro() -> Variant:
	var gestor: Variant = _gestor_encuentro()
	if gestor != null and gestor.config != null:
		return gestor.config
	return CONFIG_ATAQUE

## Buffer/combo vigente: el del gestor si existe; si no, uno propio del mismo
## sistema del módulo (ComboSystem), creado con los tiempos de su config.
func _combo_combate() -> Variant:
	var gestor: Variant = _gestor_encuentro()
	if gestor != null and gestor.combo != null:
		return gestor.combo
	if _c_combo == null:
		var cfg: Variant = _cfg_encuentro()
		var keep := 2.0 if cfg == null else float(cfg.combo_keep_time)
		var buf := 0.2 if cfg == null else float(cfg.input_buffer_time)
		_c_combo = ComboSystem.new(keep, buf)
	return _c_combo

## Enemigos del banco de encuentro (vacío si la partida aún no registra ninguno:
## el golpe sale igual y conecta con lo que alcance en el mundo).
func _enemigos_combate() -> Array:
	var gestor: Variant = _gestor_encuentro()
	if gestor != null:
		return gestor.get_active_enemies()
	return []

## Amenazas activas del gestor (para el contraataque contextual del targeting).
func _amenazas_combate() -> Variant:
	var gestor: Variant = _gestor_encuentro()
	return gestor.threats if gestor != null else null

## Arranca un golpe del combo FreeFlow. La cadena y las ventanas salen TODAS del
## módulo (SPRINT/HIT_WINDOW) con el config vigente; el objetivo se elige cada
## vez con la intención actual (nunca queda fijado por una referencia vieja).
func _iniciar_golpe_combate() -> void:
	if not is_on_floor():
		return
	var cfg: Variant = _cfg_encuentro()
	if cfg == null:
		return
	var previo: Node3D = c_objetivo if is_instance_valid(c_objetivo) else null
	# La orientación de esta forma vive en el nodo visual (el cuerpo no gira):
	# se le pasa a la selección para que "hacia dónde miro" cuente como en el módulo.
	c_objetivo = CombatTargeting.select_target(ataque_visual, _direccion_entrada(), _direccion_camara_horizontal(), _enemigos_combate(), cfg, c_objetivo, _amenazas_combate())
	# Cambiar de objetivo es INMEDIATO y NO reinicia la cadena: el golpe en curso
	# conserva su clip y la secuencia sigue por donde iba (el siguiente golpe sale
	# ya hacia el enemigo nuevo). Ver `target_switch_threshold` del config.
	if c_objetivo != previo:
		_actualizar_indicador_objetivo()
	var cadena := _cadena_combate(cfg)
	if cadena.is_empty():
		return
	c_cadena = clampi(c_cadena, 0, cadena.size() - 1)
	c_golpe = cadena[c_cadena]
	if c_objetivo != null and is_instance_valid(c_objetivo) and _dist_plana(c_objetivo) > c_golpe.ideal_distance:
		c_estado = C_E.ACERCARSE
		c_acercar_t = float(cfg.approach_max_time)
		return
	_c_iniciar_fase_golpe()

## Cadena de golpes: se construye EXACTAMENTE como la del módulo (mismos datos
## SPRINT y mismo config), sin duplicar valores.
func _cadena_combate(cfg: Variant) -> Array:
	if _c_cadena_datos.is_empty():
		for row in PlayerAtaque.SPRINT:
			var a: AttackData = AttackData.new()
			a.id = String(row.id)
			a.animation = String(row.anim)
			a.damage = float(cfg.attack_damage) * float(row.damage)
			a.attack_range = float(cfg.attack_range)
			a.ideal_distance = float(cfg.attack_ideal_distance)
			a.approach_speed = float(cfg.approach_speed)
			a.windup = float(row.impact)
			a.active = PlayerAtaque.HIT_WINDOW
			a.recovery = maxf(0.05, float(row.clip) - float(row.impact) - PlayerAtaque.HIT_WINDOW)
			a.cancel_window = float(cfg.attack_cancel_window)
			a.knockback = float(cfg.attack_knockback) * float(row.knockback)
			a.stun = 0.0
			_c_cadena_datos.append(a)
	return _c_cadena_datos

func _c_iniciar_fase_golpe() -> void:
	c_estado = C_E.PREPARAR
	c_fase = c_golpe.windup
	c_golpe_hecho = false
	# El clip del golpe se reproduce desde el principio y manda sobre la
	# locomoción hasta que termina la recuperación.
	_reproducir_combate(c_golpe.animation, C_MEZCLA, true)

func _c_estado_acercarse(delta: float) -> void:
	if not _objetivo_valido():
		# Objetivo desaparecido o muerto: se abandona con seguridad (el próximo
		# clic vuelve a elegir; nada queda bloqueado por una referencia antigua).
		c_objetivo = null
		c_estado = C_E.LIBRE
		return
	_c_girar_hacia_objetivo(delta)
	var spd := c_golpe.approach_speed if c_golpe != null else C_VEL_CAMINAR
	var dirn := _dir_plana(c_objetivo)
	velocity.x = move_toward(velocity.x, dirn.x * spd, C_ACELERACION * delta)
	velocity.z = move_toward(velocity.z, dirn.z * spd, C_ACELERACION * delta)
	if not is_on_floor():
		velocity.y -= C_GRAVEDAD * delta
	elif velocity.y < 0.0:
		velocity.y = -0.1
	c_acercar_t -= delta
	if _dist_plana(c_objetivo) <= c_golpe.ideal_distance:
		_c_iniciar_fase_golpe()
	elif c_acercar_t <= 0.0:
		c_estado = C_E.LIBRE

func _c_estado_preparar(delta: float) -> void:
	_c_decelerar_combate(delta)
	_c_girar_hacia_objetivo(delta)
	_c_fase_golpe(delta)

func _c_estado_activo(delta: float) -> void:
	_c_decelerar_combate(delta)
	_c_girar_hacia_objetivo(delta)
	if not c_golpe_hecho:
		if _objetivo_valido() and _dist_plana(c_objetivo) <= c_golpe.attack_range \
				and _objetivo_al_frente(c_objetivo):
			_c_aplicar_golpe(c_objetivo)
		elif not _objetivo_valido():
			# Sin objetivo del banco de encuentro (la partida todavía no tiene
			# enemigos registrados): el golpe conecta con lo que alcance usando
			# el contrato de daño ya existente del proyecto (grupo "damageable"
			# + take_damage, el mismo que usa la forma Fuerza).
			_c_golpe_esfera()
	_c_fase_golpe(delta)

func _c_estado_recuperar(delta: float) -> void:
	_c_decelerar_combate(delta)
	# La recuperación es cancelable: si hay otro clic encolado, encadena YA
	# (posiblemente contra otro enemigo) en vez de esperar al final del golpe.
	if _c_encadenar_si_hay():
		return
	c_fase -= delta
	if c_fase <= 0.0:
		if _c_encadenar_si_hay():
			return
		c_cadena = 0
		c_estado = C_E.LIBRE

func _c_fase_golpe(delta: float) -> void:
	c_fase -= delta
	if c_fase > 0.0:
		return
	match c_estado:
		C_E.PREPARAR:
			c_estado = C_E.ACTIVO
			c_fase = c_golpe.active
		C_E.ACTIVO:
			c_estado = C_E.RECUPERAR
			c_fase = c_golpe.recovery

func _c_aplicar_golpe(objetivo: Node3D) -> void:
	c_golpe_hecho = true
	var dir := _dir_plana(objetivo)
	if objetivo.has_method("take_hit"):
		objetivo.take_hit(c_golpe.damage, dir, c_golpe.knockback, c_golpe.stun)
	var combo: Variant = _combo_combate()
	if combo != null:
		combo.register_hit()

## Golpe sin objetivo de encuentro: esfera delante del personaje con el MISMO
## contrato de daño que ya usa la partida (grupo "damageable" + take_damage).
func _c_golpe_esfera() -> void:
	c_golpe_hecho = true
	var adelante := -ataque_visual.global_transform.basis.z
	adelante.y = 0.0
	adelante = adelante.normalized() if adelante.length_squared() > 0.0001 else Vector3.FORWARD
	var centro := global_position + Vector3.UP * 1.2 + adelante * (c_golpe.attack_range * 0.5)
	var radio := maxf(0.6, c_golpe.attack_range * 0.5)
	for t in _objetivos_en_esfera(centro, radio):
		_golpear_objetivo_fuerza(t, centro, c_golpe.damage, c_golpe.knockback)
	var combo: Variant = _combo_combate()
	if combo != null:
		combo.register_hit()

func _c_encadenar_si_hay() -> bool:
	var combo: Variant = _combo_combate()
	if combo == null:
		return false
	var act: Dictionary = combo.pop_valid(_puede_iniciar_golpe)
	if act.is_empty():
		return false
	# Encadena al siguiente golpe de la cadena; el objetivo se reelige dentro de
	# _iniciar_golpe_combate (puede ser OTRO enemigo).
	c_cadena = (c_cadena + 1) % maxi(1, _cadena_combate(_cfg_encuentro()).size())
	_iniciar_golpe_combate()
	return true

func _c_decelerar_combate(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, C_DESACELERACION * delta)
	velocity.z = move_toward(velocity.z, 0.0, C_DESACELERACION * delta)
	if not is_on_floor():
		velocity.y -= C_GRAVEDAD * delta
	elif velocity.y < 0.0:
		velocity.y = -0.1

## Giro hacia el objetivo a ritmo limitado (rad/s), como el módulo: rápido pero
## nunca un giro seco de 180°.
func _c_girar_hacia_objetivo(delta: float) -> void:
	if not _objetivo_valido():
		return
	var cfg: Variant = _cfg_encuentro()
	var ritmo := C_GIRO if cfg == null else float(cfg.player_turn_speed)
	_c_girar_hacia(_dir_plana(c_objetivo), delta, ritmo)

func _c_girar_hacia(dir: Vector3, delta: float, ritmo: float) -> void:
	dir.y = 0.0
	if dir.length() < 0.001:
		return
	var meta := atan2(-dir.x, -dir.z)
	var dif := wrapf(meta - ataque_visual.rotation.y, -PI, PI)
	var paso := maxf(0.0001, ritmo) * delta
	ataque_visual.rotation.y = wrapf(ataque_visual.rotation.y + clampf(dif, -paso, paso), -PI, PI)

# ------------------------------------------------- Indicador del FreeFlow (objetivo)
## Crea la bolita del objetivo si no existe. Es UN solo nodo y cuelga del mundo (no
## del enemigo): sirve para cualquier enemigo —los de ahora y los de la Fase 3— sin
## tocar su escena, no se duplica nunca y no guarda referencias a enemigos liberados.
func _crear_indicador_objetivo() -> void:
	if _indicador_objetivo != null and is_instance_valid(_indicador_objetivo):
		return
	var malla := SphereMesh.new()
	malla.radius = INDICADOR_RADIO
	malla.height = INDICADOR_RADIO * 2.0
	malla.radial_segments = 12
	malla.rings = 6
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = INDICADOR_COLOR
	mat.emission_enabled = true
	mat.emission = INDICADOR_COLOR
	mat.emission_energy_multiplier = 2.0
	var nodo := MeshInstance3D.new()
	nodo.name = "IndicadorObjetivoFreeFlow"
	nodo.mesh = malla
	nodo.material_override = mat
	nodo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	nodo.top_level = true          # no hereda el transform del jugador
	nodo.visible = false
	_indicador_objetivo = nodo
	var padre: Node = get_parent()
	if padre == null and is_inside_tree():
		padre = get_tree().current_scene
	if padre != null:
		padre.add_child(nodo)
	else:
		add_child(nodo)

## Coloca el indicador sobre el objetivo activo del FreeFlow (o lo oculta). Lo llama
## el cambio de objetivo —para que se note al instante— y también cada fotograma.
func _actualizar_indicador_objetivo(delta: float = 0.0) -> void:
	# Un enemigo puede morir y liberarse mientras era el objetivo: se limpia AQUÍ,
	# antes de que nadie más lea la referencia, para que no quede una colgada (con
	# ella el siguiente ataque fallaba al convertirla a Node3D).
	if not is_instance_valid(c_objetivo):
		c_objetivo = null
	if forma != Forma.COMBATE or not _objetivo_valido():
		if _indicador_objetivo != null and is_instance_valid(_indicador_objetivo):
			_indicador_objetivo.visible = false
		return
	if _indicador_objetivo == null or not is_instance_valid(_indicador_objetivo):
		_crear_indicador_objetivo()
	if _indicador_objetivo == null or not is_instance_valid(_indicador_objetivo):
		return
	var destino: Vector3 = c_objetivo.global_position + Vector3.UP * INDICADOR_ALTURA_BASE
	if c_objetivo.has_method("get_hit_center"):
		var centro: Vector3 = c_objetivo.call("get_hit_center")
		destino = centro + Vector3.UP * INDICADOR_ALTURA
	_indicador_objetivo.visible = true
	if delta > 0.0 and _indicador_objetivo.is_inside_tree():
		var t := clampf(INDICADOR_SUAVIZADO * delta, 0.0, 1.0)
		_indicador_objetivo.global_position = _indicador_objetivo.global_position.lerp(destino, t)
	else:
		_indicador_objetivo.global_position = destino

func _objetivo_valido() -> bool:
	if c_objetivo == null or not is_instance_valid(c_objetivo):
		return false
	if c_objetivo.has_method("is_alive") and not c_objetivo.is_alive():
		return false
	return true

func _dir_plana(n: Node3D) -> Vector3:
	var to := n.global_position - global_position
	to.y = 0.0
	return to.normalized() if to.length() > 0.001 else Vector3.ZERO

func _dist_plana(n: Node3D) -> float:
	var to := n.global_position - global_position
	to.y = 0.0
	return to.length()

func _objetivo_al_frente(n: Node3D) -> bool:
	var fwd := -ataque_visual.global_transform.basis.z
	fwd.y = 0.0
	if fwd.length() < 0.001:
		return false
	fwd = fwd.normalized()
	var d := _dir_plana(n)
	var cfg: Variant = _cfg_encuentro()
	var arco := 0.3 if cfg == null else float(cfg.attack_hit_arc)
	return d.length() > 0.001 and fwd.dot(d) >= arco

func _actualizar_anim_combate() -> void:
	if anim_ataque == null:
		return
	# Durante un golpe manda el clip de la acción: la locomoción no lo pisa
	# (igual que el módulo, que solo actualiza la locomoción en FREE/APPROACH).
	if c_estado == C_E.PREPARAR or c_estado == C_E.ACTIVO or c_estado == C_E.RECUPERAR:
		anim_ataque.speed_scale = 1.0
		return
	if c_salto_aire:
		anim_ataque.speed_scale = 1.0
		_reproducir_combate(ANIM_C_JUMP)
		return
	var rapidez := Vector2(velocity.x, velocity.z).length()
	if rapidez < C_UMBRAL_MOVIMIENTO:
		anim_ataque.speed_scale = 1.0
		_reproducir_combate(_clip_combate([ANIM_C_IDLE, ANIM_C_IDLE_ALT]))
	else:
		_reproducir_combate(ANIM_C_WALK)
		# Igual que el módulo: el ciclo se escala con la velocidad real para que
		# los pies no patinen, con el tope moderado 1.4 (caminata más lenta).
		anim_ataque.speed_scale = clampf(rapidez / C_REF_VEL_CAMINAR, C_ESCALA_MIN, C_ESCALA_MAX)

# Reproduce un clip de la forma Combate. Igual que play_action del módulo:
#  - si el clip no es el actual (o ya terminó), se reproduce;
#  - si YA es el actual y se pide "forzar", se REINICIA de verdad desde el
#    fotograma 0 (seek): es lo que hace que el doble salto reproduzca la
#    animación de salto desde el principio.
func _reproducir_combate(nombre: String, mezcla: float = C_MEZCLA, forzar: bool = false) -> void:
	if anim_ataque == null or not anim_ataque.has_animation(nombre):
		return
	if anim_ataque.current_animation == nombre and anim_ataque.is_playing():
		if forzar:
			anim_ataque.speed_scale = 1.0
			anim_ataque.seek(0.0, true)
		return
	anim_ataque.speed_scale = 1.0
	anim_ataque.play(nombre, mezcla)

# Devuelve el primer clip de la lista que exista en la librería del ataque.
func _clip_combate(opciones: Array) -> String:
	for opcion in opciones:
		if anim_ataque != null and anim_ataque.has_animation(opcion):
			return opcion
	return ANIM_C_IDLE

# ============================================================ VELOCISTA (ziba/)
# A partir de aquí el comportamiento es el del prototipo de supervelocidad
# (ziba/scripts/jugador.gd). Los nodos Efectos/Trazador/Combate/CapaVelocidad y
# la cámara CamaraZiba se reutilizan sin cambios.
func _procesar_normal(delta: float) -> void:
	var dir := _direccion_entrada()
	_actualizar_logica_atras(delta, dir)

	var vel_objetivo := velocidad_max
	if _ataque_activo:
		vel_objetivo *= FACTOR_MOVILIDAD_ATAQUE

	var horiz := Vector3(velocity.x, 0.0, velocity.z)
	if dir.length() > 0.05:
		horiz = horiz.move_toward(dir * vel_objetivo, aceleracion * delta)
	else:
		horiz = horiz.move_toward(Vector3.ZERO, desaceleracion * delta)
	velocity.x = horiz.x
	velocity.z = horiz.z

	if not is_on_floor():
		velocity.y -= gravedad * delta
	elif velocity.y < 0.0:
		velocity.y = -0.1

	if is_on_floor() and Input.is_action_just_pressed("saltar"):
		if _ataque_activo:
			_cancelar_ataque_por_salto()
		velocity.y = fuerza_salto

	move_and_slide()

	if _en_ventana_atras:
		_orientar(delta, _dir_orient_ventana)
	else:
		var retrocede := Input.is_action_pressed("mover_atras") and not Input.is_action_pressed("mover_adelante")
		_orientar(delta, -dir if retrocede else dir)

	if is_on_floor() and Input.is_action_just_pressed("atacar"):
		combate.intentar_golpe()
	if Input.is_action_just_pressed("emote"):
		_intentar_emote()
	if Input.is_action_just_pressed("dash"):
		_intentar_dash()
	if Input.is_action_just_pressed("cargar_poder"):
		_iniciar_carga()

func _on_golpe_realizado(indice: int) -> void:
	_sonar_golpe()
	_en_modo_ataque = true
	_t_modo_ataque = TIEMPO_MODO_ATAQUE
	_emote_activo = false
	_t_emote = 0.0
	_ataque_activo = true
	var clave := _clave_combo(indice)
	_t_ataque = _duracion_anim(clave)
	_reproducir_anim(clave, BLEND_ATAQUE, true)
	efectos.golpe_ataque(indice)
	var adelante := -visual.global_transform.basis.z
	adelante.y = 0.0
	if adelante.length() > 0.001:
		adelante = adelante.normalized()
		var horiz := Vector3(velocity.x, 0.0, velocity.z) + adelante * IMPULSO_AVANCE
		if horiz.length() > velocidad_max:
			horiz = horiz.normalized() * velocidad_max
		velocity.x = horiz.x
		velocity.z = horiz.z
	# El daño del combo llega al contacto de la animación (no en el primer
	# fotograma); `_programar_impacto_velocista` lo aplica UNA vez y lo invalida
	# si el golpe se cancela, se encadena otro o se sale de la forma.
	_programar_impacto_velocista(indice)

## Daño real del golpe del Velocista, en el fotograma del contacto de la animación.
## Va por el identificador del golpe: si se cancela (salto, dash, otra forma) o
## empieza otro golpe, el impacto pendiente se descarta.
func _programar_impacto_velocista(indice: int) -> void:
	_vel_golpe_id += 1
	var id := _vel_golpe_id
	await get_tree().create_timer(VEL_ATAQUE_IMPACTO).timeout
	if not is_inside_tree() or id != _vel_golpe_id:
		return
	if not _ataque_activo or forma != Forma.VELOCISTA:
		return
	_aplicar_impacto_velocista(indice)

## Golpe corto por DELANTE del cuerpo contra el grupo "damageable". Reutiliza los
## contratos de daño que ya usa la partida (take_hit del módulo de combate,
## take_damage del paquete Fuerza y apply_damage de las habilidades de agua): no
## hay sistema de daño nuevo. El jugador no está en ese grupo, así que no hay
## fuego amigo, y el arco frontal evita golpear lo que queda a la espalda.
func _aplicar_impacto_velocista(indice: int) -> void:
	var base: Node3D = visual if visual != null else self
	var adelante := -base.global_transform.basis.z
	adelante.y = 0.0
	if adelante.length_squared() < 0.0001:
		return
	adelante = adelante.normalized()
	var centro := global_position + adelante * VEL_ATAQUE_ALCANCE
	var dano := VEL_ATAQUE_DANIO_REMATE if indice >= 4 else VEL_ATAQUE_DANIO
	for nodo_arbol in get_tree().get_nodes_in_group("damageable"):
		var objetivo := nodo_arbol as Node3D
		if objetivo == null or objetivo == self or not objetivo.is_inside_tree():
			continue
		var radio := VEL_ATAQUE_RADIO
		if objetivo.has_method("get_hit_radius"):
			radio += float(objetivo.call("get_hit_radius"))
		var plano := Vector3(objetivo.global_position.x - centro.x, 0.0,
				objetivo.global_position.z - centro.z)
		if plano.length() > radio:
			continue
		if absf(objetivo.global_position.y - global_position.y) > VEL_ATAQUE_ALTURA:
			continue
		var hacia := Vector3(objetivo.global_position.x - global_position.x, 0.0,
				objetivo.global_position.z - global_position.z)
		if hacia.length_squared() > 0.0001 and hacia.normalized().dot(adelante) < VEL_ATAQUE_DOT_MIN:
			continue
		var dir := plano.normalized() if plano.length_squared() > 0.0001 else adelante
		_aplicar_dano_a(objetivo, dano, centro, dir, VEL_ATAQUE_EMPUJE, 0.25, &"melee")

## Aplica daño con el contrato más completo que entienda el objetivo, en este
## orden: take_hit (módulo de combate) -> take_damage (paquete Fuerza) ->
## apply_damage (habilidades de agua). Lo comparten el golpe del Velocista y la
## supervelocidad.
func _aplicar_dano_a(objetivo: Node, dano: float, centro: Vector3, dir: Vector3,
		empuje: float, aturde: float, etiqueta: StringName) -> void:
	var empuje_vec := (dir + Vector3.UP * 0.3).normalized() * empuje
	if objetivo.has_method("take_hit"):
		objetivo.call("take_hit", dano, dir, empuje, aturde)
	elif objetivo.has_method("take_damage"):
		objetivo.call("take_damage", dano, centro, empuje_vec)
	elif objetivo.has_method("apply_damage"):
		objetivo.call("apply_damage", dano, centro, etiqueta)

## Devuelve a la máscara de colisión su valor normal. Idempotente: si no hay
## ninguna arremetida en curso, no toca nada.
func _restaurar_mascara() -> void:
	if _mascara_guardada < 0:
		return
	collision_mask = _mascara_guardada
	_mascara_guardada = -1

## Enemigos que la supervelocidad se lleva por delante: se mide el TRAMO recorrido
## en el fotograma (no sólo la posición final), así que a 60 m/s no se escapa
## nadie; cada enemigo recibe daño UNA sola vez por habilidad.
func _comprobar_arremetida_super(desde: Vector3, hasta: Vector3) -> void:
	var tramo := Vector3(hasta.x - desde.x, 0.0, hasta.z - desde.z)
	var largo_cuad := tramo.length_squared()
	var dir := tramo.normalized() if largo_cuad > 0.0001 else Vector3.ZERO
	for nodo_arbol in get_tree().get_nodes_in_group("damageable"):
		var objetivo := nodo_arbol as Node3D
		if objetivo == null or objetivo == self or not objetivo.is_inside_tree():
			continue
		if _super_golpeados.has(objetivo.get_instance_id()):
			continue
		var radio := VEL_SUPER_RADIO
		if objetivo.has_method("get_hit_radius"):
			radio += float(objetivo.call("get_hit_radius"))
		var p := Vector3(objetivo.global_position.x - desde.x, 0.0,
				objetivo.global_position.z - desde.z)
		var t := 0.0 if largo_cuad <= 0.0001 else clampf(p.dot(tramo) / largo_cuad, 0.0, 1.0)
		var punto := tramo * t
		var fuera := p - punto
		if fuera.length() > radio:
			continue
		if absf(objetivo.global_position.y - global_position.y) > VEL_ATAQUE_ALTURA:
			continue
		_super_golpeados[objetivo.get_instance_id()] = true
		var empuje_dir := dir if dir.length_squared() > 0.0001 else fuera.normalized()
		_aplicar_dano_a(objetivo, VEL_SUPER_DANIO, objetivo.global_position, empuje_dir,
				VEL_SUPER_EMPUJE, VEL_SUPER_ATURDIMIENTO, &"supervelocidad")

func _cancelar_ataque_por_salto() -> void:
	_ataque_activo = false
	_t_ataque = 0.0
	_salto_forzado = true
	efectos.cancelar_ataque()
	combate.cancelar_combo()
	_reproducir_anim(ANIM_SALTO, BLEND_SALTO, true)

func _intentar_emote() -> void:
	if _ataque_activo:
		return
	_emote_activo = true
	_t_emote = _duracion_anim(ANIM_EMOTE)
	_reproducir_anim(ANIM_EMOTE, BLEND_EMOTE, true)

func _clave_combo(indice: int) -> String:
	match indice:
		1:
			return ANIM_COMBO_1
		2:
			return ANIM_COMBO_2
		3:
			return ANIM_COMBO_3
		4:
			return ANIM_COMBO_4
	return ANIM_COMBO_1

func _duracion_anim(clave: String) -> float:
	var nombre := String(_anim_nombres.get(clave, ""))
	if _anim == null or nombre.is_empty():
		return 0.3
	var anim := _anim.get_animation(nombre)
	return anim.length if anim != null else 0.3

func _actualizar_logica_atras(delta: float, dir: Vector3) -> void:
	var s := Input.is_action_pressed("mover_atras")
	var w := Input.is_action_pressed("mover_adelante")
	var a := Input.is_action_pressed("mover_izquierda")
	var d := Input.is_action_pressed("mover_derecha")

	if not s or w:
		_hubo_combo_atras = false
		_en_ventana_atras = false
		_t_ventana = 0.0
		if dir.length() > 0.05:
			_ultimo_dir_movimiento = dir
		return

	if a or d:
		_hubo_combo_atras = true
		_en_ventana_atras = false
		_t_ventana = 0.0
		_ultimo_dir_movimiento = dir
		return

	if _en_ventana_atras:
		_t_ventana += delta
		if _t_ventana >= VENTANA_CONTINUACION:
			_en_ventana_atras = false
		return

	if _hubo_combo_atras:
		_en_ventana_atras = true
		_t_ventana = 0.0
		_dir_orient_ventana = -_ultimo_dir_movimiento
		_hubo_combo_atras = false

# ---------------- Dash ----------------
func _intentar_dash() -> void:
	var dir := _direccion_entrada()
	if dir.length() < 0.05:
		dir = -pivote.global_transform.basis.z
		dir.y = 0.0
		dir = dir.normalized()
	if is_on_floor():
		_iniciar_dash(dir)
	else:
		estado = Estado.CAIDA_DASH
		_dir_dash = dir
		velocity = Vector3(0.0, -35.0, 0.0)
		efectos.iniciar_caida_dash()

func _iniciar_dash(dir: Vector3) -> void:
	estado = Estado.DASH
	_dir_dash = dir
	_orientar_instant(dir)
	_objetivo_dash = global_position + dir * distancia_objetivo_dash
	_objetivo_dash.y = global_position.y
	_pos_dash_inicio = global_position
	_t_dash = 0.0
	_bloqueo_anim = 0.0
	efectos.iniciar_dash(dir)
	_sonar_dash()

func _procesar_dash(delta: float) -> void:
	_t_dash += delta
	var to := _objetivo_dash - global_position
	to.y = 0.0
	if to.length() < 0.4 or _t_dash > 0.5:
		_terminar_dash()
		return
	var dir := to.normalized()
	var col := move_and_collide(dir * (distancia_dash / duracion_dash) * delta)
	if col != null:
		_terminar_dash()
		return
	efectos.actualizar_ejecucion(global_position, dir)

func _terminar_dash() -> void:
	estado = Estado.NORMAL
	velocity = _dir_dash * velocidad_max
	print("[Leo] dash recorrido: ", snappedf((global_position - _pos_dash_inicio).length(), 0.01), " m")
	efectos.terminar_dash()

func _procesar_caida_dash() -> void:
	velocity.x = 0.0
	velocity.z = 0.0
	velocity.y = -35.0
	move_and_slide()
	if is_on_floor():
		_iniciar_dash(_dir_dash)

# ---------------- Carga / trazado ----------------
func _iniciar_carga() -> void:
	estado = Estado.CARGA
	_t_carga = 0.0
	_bloqueo_anim = 0.0
	var cam_fwd := -pivote.global_transform.basis.z
	cam_fwd.y = 0.0
	if cam_fwd.length() > 0.001:
		_orientar_instant(cam_fwd.normalized())
	pivote.permitir_look = false
	pivote.definir_pitch(-0.32)
	pivote.objetivo_largo = pivote.largo_base * 0.6
	pivote.objetivo_fov = pivote.fov_base + 6.0
	var cam := pivote.get_node_or_null("Brazo/Camara") as Camera3D
	trazador.iniciar(global_position, cam, 0.0)
	efectos.iniciar_carga()
	_sonar_carga()

func _procesar_carga(delta: float) -> void:
	_t_carga += delta
	velocity = velocity.move_toward(Vector3.ZERO, desaceleracion * delta)
	if not is_on_floor():
		velocity.y -= gravedad * delta
	move_and_slide()

	var t := clampf(_t_carga / 1.8, 0.0, 1.0)
	efectos.actualizar_carga(t)
	pivote.vibracion = lerpf(0.15, 1.0, t)
	pivote.objetivo_largo = pivote.largo_base * lerpf(0.6, 0.42, t)

	if Input.is_action_just_released("cargar_poder"):
		_soltar_carga()

func _soltar_carga() -> void:
	_parar_carga()
	pivote.permitir_look = true
	pivote.vibracion = 0.0
	pivote.objetivo_largo = pivote.largo_base
	pivote.objetivo_fov = pivote.fov_base
	pivote.definir_pitch(-0.25)
	var muestras := trazador.finalizar()
	efectos.terminar_carga()
	if muestras.size() >= 2:
		_puntos = muestras
		_idx = 0
		_vel_trayecto = vel_trayecto_min
		_t_preparado = 0.0
		estado = Estado.PREPARADO
		pivote.objetivo_largo = pivote.largo_base * 0.7
		pivote.objetivo_fov = pivote.fov_base + 12.0
		pivote.vibracion = 0.5
	else:
		trazador.limpiar()
		estado = Estado.NORMAL

func _procesar_preparado(delta: float) -> void:
	_t_preparado += delta
	velocity = velocity.move_toward(Vector3.ZERO, desaceleracion * delta)
	if not is_on_floor():
		velocity.y -= gravedad * delta
	move_and_slide()
	if _t_preparado >= 0.12:
		_iniciar_recorrido()

func _iniciar_recorrido() -> void:
	estado = Estado.EJECUCION
	_super_golpeados.clear()
	# La arremetida NO se detiene con los enemigos: se les retira de la máscara
	# SÓLO a ellos (capa 5). Paredes, suelo y límites del mapa siguen bloqueando,
	# porque van en otras capas. La máscara se restaura al terminar.
	_mascara_guardada = collision_mask
	collision_mask = collision_mask & ~CAPA_ENEMIGOS
	trazador.set_ejecucion(true)
	efectos.iniciar_ejecucion()
	pivote.objetivo_largo = pivote.largo_base * 0.9
	pivote.objetivo_fov = pivote.fov_base + 20.0
	pivote.vibracion = 0.6
	_sonar_trazado()

# ---------------- Ejecución de la trayectoria ----------------
# El recorrido se apoya en el terreno REAL de la isla. Antes se hacía con un
# avance horizontal puro (move_and_collide con la Y a cero) y se cancelaba la
# habilidad ante CUALQUIER contacto: en cuanto el suelo subía un centímetro
# dentro del paso del fotograma, la habilidad interpretaba la cuesta como un
# muro y terminaba. Ahora se avanza con move_and_slide (que sube y baja por el
# relieve respetando el límite de inclinación del cuerpo) y sólo se cancela ante
# un obstáculo de verdad sondeado a la altura del pecho; los escalones los sigue
# subiendo _resolver_escalon(), igual que al caminar.
func _procesar_ejecucion(delta: float) -> void:
	if _idx >= _puntos.size():
		_terminar_ejecucion()
		return
	var objetivo := _puntos[_idx]
	var to := objetivo - global_position
	to.y = 0.0
	# A 60 m/s se cruzan varios puntos por fotograma: si sólo se avanzase uno, el
	# personaje acabaría persiguiendo un punto que ya tiene a su espalda (zigzag).
	var guardas := 0
	while _idx < _puntos.size() - 1 and to.length() < TRAYECTO_RADIO_PUNTO and guardas < 64:
		_idx += 1
		guardas += 1
		objetivo = _puntos[_idx]
		to = objetivo - global_position
		to.y = 0.0
	# Se llegó al final de la ruta: la habilidad termina de forma ordenada (antes
	# se exigía una precisión de milímetros sobre el último punto y el personaje
	# se quedaba girando a su alrededor sin acabar nunca).
	if _idx >= _puntos.size() - 1 and to.length() < TRAYECTO_RADIO_PUNTO:
		_terminar_ejecucion()
		return
	if to.length_squared() < 0.0001:
		_idx += 1
		return
	var dir := to.normalized()
	_vel_trayecto = move_toward(_vel_trayecto, vel_trayecto_max, 220.0 * delta)

	velocity.x = dir.x * _vel_trayecto
	velocity.z = dir.z * _vel_trayecto
	if not is_on_floor():
		velocity.y -= gravedad * delta
	elif velocity.y < 0.0:
		velocity.y = -0.1
	var antes := global_position
	move_and_slide()
	_orientar_instant(dir)
	# Barrido de la arremetida: quien se cruce en la trayectoria sale empujado y
	# recibe daño una sola vez por habilidad (nunca cada fotograma).
	_comprobar_arremetida_super(antes, global_position)

	var avance := global_position - antes
	avance.y = 0.0
	var paso := _vel_trayecto * delta
	# Sólo una corrección por fotograma: primero medimos el avance REAL tras
	# move_and_slide. El contacto en sí (incluido un contacto con el suelo) no
	# termina la habilidad; sólo el avance horizontal insuficiente puede hacerlo.
	if paso > 0.001 and avance.length() < paso * 0.35:
		if _muro_al_frente(dir):
			_terminar_ejecucion()
			return
		# Sin pared a la altura del pecho: intentamos resolver únicamente un
		# desnivel bajo. _resolver_escalon() se omite durante EJECUCION para no
		# duplicar esta corrección en el mismo movimiento.
		_salvar_escalon(dir)

	efectos.actualizar_ejecucion(global_position, dir)
	trazador.agregar_estela(global_position)

## ¿Lo que frena el recorrido es un obstáculo real? Se sondea a la altura del
## pecho con el propio cuerpo (misma collision_mask que al caminar): un edificio,
## un muro o un acantilado bloquean ahí; una cuesta, un bordillo o un desnivel
## transitable, no. _terminar_ejecucion() cierra la habilidad de forma ordenada.
func _muro_al_frente(dir: Vector3) -> bool:
	var pecho := global_transform
	pecho.origin.y += TRAYECTO_ALTURA_MURO
	return test_move(pecho, dir * (AVANCE_ESCALON * 2.0))


## Sube a mano un escalón bajo (el bordillo de una acera, ~15 cm) cuando frena el
## recorrido a gran velocidad: eleva el cuerpo ALTURA_ESCALON, avanza un poco y
## vuelve a apoyarse. Sólo lo hace si hay hueco por encima, paso libre a esa altura
## y suelo al otro lado; un muro de verdad ya lo ha descartado _muro_al_frente().
## (Caminando esto lo hace _resolver_escalon(), pero a 34-60 m/s el contacto se
## resuelve dentro del fotograma y move_and_slide no sube el escalón.)
func _salvar_escalon(dir: Vector3) -> void:
	if test_move(global_transform, Vector3.UP * ALTURA_ESCALON):
		return
	var elevado := global_transform
	elevado.origin.y += ALTURA_ESCALON
	var avance := dir * AVANCE_ESCALON
	if test_move(elevado, avance):
		return
	var destino := elevado
	destino.origin += avance
	if not test_move(destino, Vector3.DOWN * (ALTURA_ESCALON + 0.1)):
		return
	global_position.y += ALTURA_ESCALON
	move_and_collide(avance)
	move_and_collide(Vector3.DOWN * (ALTURA_ESCALON + 0.1))

func _terminar_ejecucion() -> void:
	estado = Estado.NORMAL
	velocity = Vector3.ZERO
	_restaurar_mascara()
	pivote.objetivo_largo = pivote.largo_base
	pivote.objetivo_fov = pivote.fov_base
	pivote.vibracion = 0.0
	efectos.terminar_ejecucion()
	trazador.finalizar_ejecucion()
	_super_golpeados.clear()
	_bloqueo_anim = BLOQUEO_FIN_VELOCIDAD
	_reproducir_anim(ANIM_INACTIVO, BLEND_FIN_VELOCIDAD)
	_parar_trazado()

# ---------------- Animaciones (velocista) ----------------
func _configurar_animaciones() -> void:
	_anim = get_node_or_null("Visual/Pose/Volteo/Modelo/AnimadorVelocista") as AnimationPlayer
	if _anim == null:
		push_warning("[Leo] Sin AnimationPlayer en el modelo velocista: la forma velocista se movera sin animaciones.")
		return
	for lib_nombre in _anim.get_animation_library_list():
		var clave := String(lib_nombre)
		if clave.is_empty():
			continue
		var lib: AnimationLibrary = _anim.get_animation_library(lib_nombre)
		if lib == null or lib.get_animation_list().is_empty():
			continue
		var clip := lib.get_animation_list()[0]
		_anim_nombres[clave] = "%s/%s" % [clave, clip]
		_preparar_bucle(clave, lib.get_animation(clip))

func _preparar_bucle(clave: String, anim: Animation) -> void:
	match clave:
		ANIM_INACTIVO, ANIM_ADELANTE, ANIM_ATRAS, ANIM_SUPERVELOCIDAD, ANIM_MODO_ATAQUE:
			anim.loop_mode = Animation.LOOP_LINEAR
		ANIM_CARGA:
			anim.loop_mode = Animation.LOOP_PINGPONG
		ANIM_COMBO_1, ANIM_COMBO_2, ANIM_COMBO_3, ANIM_COMBO_4, ANIM_EMOTE:
			anim.loop_mode = Animation.LOOP_NONE

func _reproducir_anim(clave: String, blend: float, forzar: bool = false) -> void:
	if _anim == null:
		return
	if clave == _anim_actual and not forzar:
		return
	var nombre := String(_anim_nombres.get(clave, ""))
	if nombre.is_empty():
		return
	_anim_actual = clave
	_anim.play(nombre, blend)

func _blend_para(clave: String) -> float:
	match clave:
		ANIM_SALTO:
			return BLEND_SALTO
		ANIM_DASH:
			return BLEND_DASH
		ANIM_CARGA:
			return BLEND_CARGA
		ANIM_SUPERVELOCIDAD:
			return BLEND_LIBERACION
	match _anim_actual:
		ANIM_DASH:
			return BLEND_POST_DASH
		ANIM_SALTO:
			return BLEND_POST_SALTO
		ANIM_SUPERVELOCIDAD:
			return BLEND_FIN_VELOCIDAD
		ANIM_ADELANTE, ANIM_ATRAS:
			return BLEND_MARCHA_FIN if clave == ANIM_INACTIVO else BLEND_CAMBIO_MARCHA
	return BLEND_MARCHA

func _actualizar_animaciones(delta: float) -> void:
	if _anim == null:
		return
	_bloqueo_anim = maxf(0.0, _bloqueo_anim - delta)
	if _ataque_activo:
		_t_ataque -= delta
		if _t_ataque <= 0.0:
			_ataque_activo = false
	if _emote_activo:
		_t_emote -= delta
		if _t_emote <= 0.0:
			_emote_activo = false
	if _en_modo_ataque:
		_t_modo_ataque -= delta
		if _t_modo_ataque <= 0.0:
			_en_modo_ataque = false
	match estado:
		Estado.NORMAL:
			if _ataque_activo:
				pass
			elif _emote_activo:
				pass
			elif not is_on_floor():
				_reproducir_anim(ANIM_SALTO, _blend_para(ANIM_SALTO))
			elif _salto_forzado:
				_salto_forzado = false
				_reproducir_anim(ANIM_SALTO, BLEND_SALTO)
			elif _bloqueo_anim > 0.0:
				_reproducir_anim(ANIM_INACTIVO, _blend_para(ANIM_INACTIVO))
			elif _en_ventana_atras:
				_reproducir_anim(ANIM_ADELANTE, _blend_para(ANIM_ADELANTE))
			elif Input.is_action_pressed("mover_atras") and not Input.is_action_pressed("mover_adelante"):
				_reproducir_anim(ANIM_ATRAS, _blend_para(ANIM_ATRAS))
			elif _direccion_entrada().length() > 0.05:
				_reproducir_anim(ANIM_ADELANTE, _blend_para(ANIM_ADELANTE))
			elif _en_modo_ataque:
				_reproducir_anim(ANIM_MODO_ATAQUE, BLEND_POST_ATAQUE)
			else:
				_reproducir_anim(ANIM_INACTIVO, _blend_para(ANIM_INACTIVO))
		Estado.DASH, Estado.CAIDA_DASH:
			_reproducir_anim(ANIM_DASH, _blend_para(ANIM_DASH))
		Estado.CARGA:
			_reproducir_anim(ANIM_CARGA, _blend_para(ANIM_CARGA))
		Estado.PREPARADO, Estado.EJECUCION:
			_reproducir_anim(ANIM_SUPERVELOCIDAD, _blend_para(ANIM_SUPERVELOCIDAD))

# ---------------- Pose procedural (velocista) ----------------
func _actualizar_pose(delta: float) -> void:
	var vel_h := Vector3(velocity.x, 0.0, velocity.z).length()
	var inclinacion := 0.0
	var altura := 0.0
	match estado:
		Estado.CARGA:
			inclinacion = -0.55
			altura = 0.0
		Estado.DASH, Estado.EJECUCION:
			inclinacion = -0.6
			altura = -0.05
		_:
			inclinacion = -clampf(vel_h / velocidad_max, 0.0, 1.0) * 0.18
	pose.rotation.x = lerp_angle(pose.rotation.x, inclinacion, 10.0 * delta)
	pose.position.y = lerpf(pose.position.y, altura, 10.0 * delta)

# ---------------- Orientación del modelo (velocista) ----------------
func _orientar(delta: float, dir: Vector3) -> void:
	if dir.length() < 0.05:
		return
	var objetivo := atan2(-dir.x, -dir.z)
	visual.rotation.y = lerp_angle(visual.rotation.y, objetivo, 12.0 * delta)

func _orientar_instant(dir: Vector3) -> void:
	if dir.length() < 0.05:
		return
	visual.rotation.y = atan2(-dir.x, -dir.z)
