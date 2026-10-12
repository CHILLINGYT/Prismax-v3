class_name FuerzaPlayer
extends CharacterBody3D

## =============================================================================
##  Player.gd — Personaje 3D controlable (base reutilizable)
## =============================================================================
##  Este script NO depende del modelo 3D. Toda la geometría visual vive dentro
##  del nodo "Model/CharacterModel", que puedes reemplazar libremente por tu
##  propio archivo .glb / .gltf sin tocar una sola línea de este código.
##
##  DÓNDE TOCAR CADA COSA (todo desde el Inspector)
##  -----------------------------------------------
##  · Velocidad de caminar / correr .... grupo "Movimiento"
##  · Aceleración y frenado suave ...... acceleration / deceleration
##  · Velocidad de giro ................ rotation_speed
##  · Fuerza del salto ................. jump_velocity
##  · Gravedad ......................... gravity
##  · Cámara, sensibilidad y límites ... script PlayerCamera.gd (nodo "Camera3D")
##  · Modelo 3D ........................ model_path  ->  nodo "Model"
##  · Animaciones ...................... grupo "Animaciones"
##
##  CÓMO PONER TU PROPIO MODELO
##  ---------------------------
##  1. Importa tu .glb / .gltf al proyecto (por ejemplo en res://models/).
##  2. Arrástralo DENTRO del nodo "Model/CharacterModel" en Player.tscn.
##  3. Ajusta escala y posición (el pivote del modelo debe quedar a los pies).
##  4. Si trae animaciones, asígnalas al AnimationPlayer con los nombres
##     Idle / Walk / Run / Jump / Fall  (o cambia los nombres en el Inspector).
##  5. Ejecuta el juego. No hace falta modificar este script.
## =============================================================================


# -----------------------------------------------------------------------------
# SEÑALES — útiles para enganchar sonido, efectos, HUD, etc. sin tocar el script.
# -----------------------------------------------------------------------------
## Se emite justo cuando el personaje salta.
signal jumped
## Se emite cuando el personaje vuelve a tocar el suelo.
signal landed
## Se emite cuando empieza o deja de correr (útil para stamina, sonido...).
signal sprint_changed(is_sprinting: bool)
## Se emite al iniciar un ataque. attack_name es "Punch_Left" (jab),
## "Punch_Right" (cross) o "Kick".
signal attack_started(attack_name: StringName)
## Se emite al terminar el ataque (útil para encadenar combos más adelante).
signal attack_finished
## Se emite al agacharse o levantarse.
signal crouch_changed(is_crouching: bool)


# =============================================================================
#  MOVIMIENTO  ← aquí se ajustan velocidades y respuesta del personaje
# =============================================================================
@export_group("Movimiento")
## Velocidad al caminar (unidades por segundo).
## PESADO: un humano anda a ~5; esta transformación a 1.2 (lenta, con masa).
## Está AJUSTADA a la zancada real de la animación "Walk" (1.20 m/s), para que
## los pies no patinen al andar.
@export var walk_speed: float = 1.2
## Velocidad al mantener la tecla de correr (sprint).
## Ajustada a la zancada real de la animación "Run" (3.00 m/s).
@export var sprint_speed: float = 3.0
## Aceleración al empezar a moverse (unidades/segundo²). Bajo = cuesta arrancar.
## PESADO: 4 hace que le cueste ponerse en marcha y transmite inercia.
@export var acceleration: float = 4.0
## Frenado al soltar el movimiento (unidades/segundo²). Bajo = frena más suave.
## PESADO: 5 frena progresivamente, sin clavar los pies de golpe.
@export var deceleration: float = 5.0
## Rapidez con la que el modelo gira hacia la dirección en la que se mueve.
## PESADO: 4 hace que los giros se sientan lentos, como mover una mole.
@export var rotation_speed: float = 4.0
## Cuánto control tienes en el aire (0 = ninguno, 1 = igual que en el suelo).
## Multiplica a air_acceleration y air_friction: con 0.5 el personaje corrige
## la trayectoria del salto con peso, sin volverse un dron.
@export_range(0.0, 1.0, 0.05) var air_control: float = 0.5
## Aceleración horizontal propia del AIRE (unidades/segundo²). En el suelo manda
## `acceleration`; en el aire, ÉSTA × air_control: así se puede corregir la
## trayectoria de un salto (y del pisotón) sin tocar el tacto de tierra.
@export var air_acceleration: float = 16.0
## Frenado horizontal en el aire cuando NO se toca ninguna dirección
## (unidades/segundo²), antes de air_control. Bajísimo a propósito: la inercia
## del salto y del picado se CONSERVA, el personaje sigue avanzando al caer.
@export var air_friction: float = 2.0
## Multiplicador de velocidad horizontal mientras se está en el aire. Algo menos
## que en el suelo: en el aire se va un poco más lento, pero se va.
@export_range(0.1, 1.0, 0.05) var air_speed_multiplier: float = 0.85
## Cuánto puede girar el modelo mientras ataca (0 = nada, 1 = gira normal).
## Evita que un puñetazo se convierta en un giro instantáneo.
@export_range(0.0, 1.0, 0.05) var attack_rotation_control: float = 0.15


# =============================================================================
#  SALTO Y GRAVEDAD
# =============================================================================
@export_group("Salto y Gravedad")
## Impulso vertical del salto (unidades por segundo). Más alto = salto más alto.
@export var jump_velocity: float = 6.0
## Gravedad propia (unidades/segundo²). 9.8 es realista; 25-35 se siente ágil.
## (Si prefieres la gravedad del proyecto, usa get_gravity() en _physics_process).
@export var gravity: float = 25.0
## Límite de velocidad al caer, para no atravesar el suelo a gran velocidad.
@export var max_fall_speed: float = 40.0
## Margen para saltar justo después de salir del borde de una plataforma.
@export var coyote_time: float = 0.12
## Margen para recordar un salto pulsado poco antes de tocar el suelo.
@export var jump_buffer_time: float = 0.15


# =============================================================================
#  AGACHARSE  ← CTRL agacha; la cápsula y la cámara se ajustan solas
# =============================================================================
@export_group("Agacharse")
## Multiplicador de velocidad mientras está agachado (0.6 = 40 % más lento).
## Ajustado a la zancada real de "CrouchWalk" (0.74 m/s ≈ 0.62 × walk_speed).
@export_range(0.1, 1.0, 0.05) var crouch_speed_multiplier: float = 0.6
## Altura de la cápsula de colisión al agacharse (unidades). Menor que de pie,
## para poder pasar por huecos bajos. Está ajustada a la altura REAL que alcanza
## la animación de agachado (la coronilla baja a ≈1.07 m).
@export var crouch_height: float = 1.15
## Rapidez con la que la cápsula y la cámara suben o bajan (unidades/segundo).
@export var crouch_transition_speed: float = 3.0
## Cuánto baja el punto al que mira la cámara al agacharse (unidades).
## La cámara baja COMO CONSECUENCIA de la postura: el torso baja ≈0.80 m, así
## que el punto de mira acompaña bajando 0.65.
@export var crouch_camera_drop: float = 0.65
## Si está activo, no se puede levantar si hay un techo encima.
@export var block_stand_under_ceiling: bool = true
## Si está activo, no se puede agachar mientras se está atacando.
@export var block_crouch_while_attacking: bool = true


# =============================================================================
#  COMBATE  ← clic izq. = jab / 1-2 con doble clic, clic der. = patada
#  Sólo lógica y animación: todavía NO hay daño, enemigos ni hitboxes.
# =============================================================================
@export_group("Combate")
## Duración del puñetazo en segundos. Sólo se usa si el modelo NO trae los
## clips de puñetazo; si los trae, se respeta su duración real.
@export var punch_duration: float = 1.0
## Duración de la patada en segundos (más lenta y pesada que el puñetazo).
@export var kick_duration: float = 1.4
## Multiplicador de velocidad mientras ataca (0 = clavado en el sitio).
@export_range(0.0, 1.0, 0.05) var attack_move_multiplier: float = 0.15
## Ventana de combo (segundos). Si el SEGUNDO clic llega dentro de este margen
## desde que arrancó el jab, se encadena el cross. Si llega más tarde ya no
## cuenta: son dos golpes sueltos, no un 1-2. Súbelo si te cuesta encadenar,
## bájalo si te salen crosses sin querer.
@export var combo_window: float = 0.5
## Punto del jab (fracción de su duración) a partir del cual sale el cross
## encadenado. Con 0.30 el cross entra justo después del impacto del jab, así
## que se come su recuperación y los dos golpes se ven seguidos, sin pausa.
@export_range(0.0, 1.0, 0.05) var combo_cancel_point: float = 0.3
## Duración del estado de aterrizaje al tocar el suelo (segundos).
## Coincide con la parte útil del clip "Land" (absorción + recuperación).
@export var land_duration: float = 0.6
## Multiplicador de velocidad durante el aterrizaje (0.6 = absorbe el impacto).
@export_range(0.0, 1.0, 0.05) var land_move_multiplier: float = 0.6


# =============================================================================
#  HABILIDADES ESPECIALES
#   · Mantén SPACE en el suelo -> SUPER SALTO (carga visible y salto enorme)
#   · E en el aire             -> PISOTÓN (picado + onda expansiva al aterrizar)
#   · Q en el suelo            -> ARRANCAR UNA ROCA y LANZARLA
#  Todas se bloquean entre sí mientras están en marcha.
# =============================================================================
@export_group("Habilidad — super salto (SPACE mantenido)")
## Activa el super salto. Si lo desactivas, SPACE vuelve a ser sólo el salto normal.
@export var super_jump_enabled: bool = true
## Carga mínima (segundos). Un toque más corto que esto sigue siendo el salto normal.
@export var super_jump_min_charge: float = 0.25
## Carga máxima (segundos). A partir de aquí ya no sube más (aunque sigas pulsando).
@export var super_jump_max_charge: float = 1.4
## Velocidad de salida con la carga MÍNIMA (el salto normal es 6).
@export var super_jump_min_velocity: float = 8.0
## Velocidad de salida con la carga MÁXIMA. La altura va con el cuadrado: 21
## supone saltar unos 9 metros de alto con la gravedad por defecto.
@export var super_jump_max_velocity: float = 21.0
## Cuánto baja la cámara mientras carga (acompaña a la flexión de la animación).
@export var charge_camera_drop: float = 0.28
## Temblor del modelo mientras carga (0 = nada). Crece con la carga.
@export var charge_tremor: float = 0.035
## Sacudida de cámara al disparar el super salto.
@export var super_jump_camera_shake: float = 0.45
## Velocidad horizontal MÍNIMA con la que sale el super salto. La carrera se
## CONSERVA entera al despegar (no se pierde nada): esto sólo pone un suelo para
## que un salto cargado desde parado no salga totalmente quieto. Si ya se venía
## a más velocidad, no hace nada.
@export var super_jump_forward_impulse: float = 2.0
## Roce mientras se CARGA el salto (frenado por segundo si no se toca la
## dirección). Mucho más suave que el frenado normal: cargando se conserva la
## carrera y se puede seguir corrigiendo el rumbo, en vez de quedar clavado.
@export var charge_slide_friction: float = 1.0

@export_group("Habilidad — pisotón (E en el aire)")
## Activa el pisotón.
@export var air_slam_enabled: bool = true
## Velocidad de caída en picado (el máximo normal al caer es 40).
@export var air_slam_speed: float = 55.0
## Rapidez con la que entra en picado (cuanto más alto, más seco).
@export var air_slam_accel: float = 160.0
## Altura mínima sobre el suelo para poder usarlo (no vale desde un escalón).
@export var air_slam_min_height: float = 1.2
## DAÑO de la onda. Es independiente del daño de los puñetazos.
@export var air_slam_damage: float = 60.0
## Radio de la onda expansiva (todo lo que esté dentro recibe daño).
@export var air_slam_radius: float = 4.5
## Empuje que se lleva a los enemigos alcanzados.
@export var air_slam_knockback: float = 13.0
## Sacudida de cámara al golpear el suelo.
@export var air_slam_camera_shake: float = 0.55
## Bloqueo extra tras el golpe (no se puede hacer nada mientras se recupera).
@export var air_slam_recovery: float = 0.45

@export_group("Habilidad — lanzamiento de roca (Q)")
## Activa el lanzamiento de roca.
@export var rock_throw_enabled: bool = true
## Radio de la roca. 0.8 ≈ una mole de 1.6 m de diámetro: sigue pareciendo
## enorme entre las manos y cabe SOBRE la cabeza sin taparle la cara al
## personaje (con 1.1 le tapaba la pantalla entera al apuntar).
@export var rock_size: float = 0.8
## Velocidad de lanzamiento.
@export var rock_throw_speed: float = 17.0
## Ángulo hacia arriba del lanzamiento (grados). SÓLO se usa como red de
## seguridad, cuando la roca sale sin apuntado (no debería pasar en el juego
## normal: con Q apuntado la dirección la calcula el tiro al punto de la mira).
@export var rock_throw_angle: float = 11.0
## Escala de la gravedad de la roca (menos de 1 = vuela más lejos).
@export var rock_gravity_scale: float = 0.6
## Daño de la roca al chocar de lleno.
@export var rock_damage: float = 80.0
## Radio del daño en área del impacto de la roca.
@export var rock_impact_radius: float = 3.0
## Punto del clip de lanzamiento (0-1) en el que la roca sale de las manos.
## Con el clip actual (0.62 s) 0.40 deja la roca saliendo en ~0.25 s del clic.
@export_range(0.0, 1.0, 0.01) var rock_release_point: float = 0.40
## Sacudida de cámara al soltar la roca.
@export var rock_release_camera_shake: float = 0.18
## Distancia máxima de apuntado (m): si la mira no topa con nada, el objetivo
## se coloca a esta distancia del personaje.
@export var rock_throw_range: float = 40.0
## Ángulo EXTRA hacia arriba sobre el tiro calculado (grados). 0 = la roca
## viaja exactamente al punto de la retícula; súbelo para lanzarla "en globo"
## (entonces cae un poco más lejos de la retícula).
@export var rock_throw_arc: float = 0.0
## Rapidez con la que el personaje gira hacia la dirección de apuntado.
## 1 = igual que al caminar; 0.6 = giro pesado y progresivo, sin tirones.
@export var rock_aim_turn_speed: float = 0.6
## Cuánto sube la cámara mientras se apunta (unidades del mundo). La mole va
## SOBRE la cabeza, así que ya no tapa el centro de la pantalla: se queda en 0
## para que apuntar no cambie nada de la cámara (súbelo si algún día vuelve a
## sujetarse delante del pecho).
@export var rock_aim_camera_lift: float = 0.0
## Cuánto sube la mole SOBRE las manos mientras se lleva (en radios de la propia
## roca): con 1.03 queda apoyada encima de las dos manos, la base un pelín por
## encima de los nudillos y despejada de la cabeza. Es lo que hace que la roca
## se sujete "con los brazos estirados" y no atraviese al personaje.
@export var rock_carry_lift: float = 1.03
## Multiplicador de velocidad al ANDAR llevando la mole en alto (0.65 = 65 %).
## Cargada no se corre: se anda.
@export_range(0.1, 1.0, 0.05) var rock_carry_speed: float = 0.65
## Velocidad a la que la animación de andar con la roca (RockCarryWalk) va a
## 1.0×, medida sobre el clip ya cocido (su pie apoyado barre el suelo a
## 1.27 m/s). Como al llevar la mole se anda más despacio, el ciclo girará por
## debajo de 1.0× y los pies seguirán cuadrando con el suelo.
@export var rock_carry_walk_speed: float = 1.27
## Distancia a la que la mole espera apoyada en el suelo, delante del personaje,
## antes de levantarla (unidades). Tiene que quedar fuera del alcance del cuerpo
## pero dentro del empujón de los brazos.
@export var rock_lift_floor_distance: float = 1.15
## Punto del levantamiento (0-1) en el que la mole pasa de estar clavada en el
## suelo a ir pegada a las manos (justo cuando el clip la agarra).
@export var rock_lift_push_until: float = 0.42
## Punto del levantamiento (0-1) en el que la mole empieza a despegarse del
## suelo y a arrimarse a las manos que la empujan.
@export var rock_lift_settle_from: float = 0.10
## Punto del levantamiento (0-1) en el que la mole ya va recta sobre las manos,
## por encima de la cabeza; antes de eso va girando desde el suelo.
@export var rock_lift_overhead_at: float = 0.98

@export_group("Habilidad — embestida con el hombro (R)")
## Activa la embestida.
@export var shoulder_charge_enabled: bool = true
## Duración de la preparación (segundos): inclinarse, cargar el hombro y salir.
@export var charge_prep_time: float = 0.16
## Velocidad de la carrera de la embestida. 5.0 NO es un número al azar: es la
## velocidad a la que la animación ShoulderRun queda a 1.0× (su pie apoyado
## barre el suelo a 5 m/s), así que con este valor la zancada y el avance
## cuadran exactos: ni patina ni va en cámara lenta.
@export var charge_speed: float = 5.0
## Duración máxima del dash (segundos). Se corta lo que llegue antes (tiempo,
## distancia o choque). Con 0.6 s da ~2.6 m de carrera: tres zancadas largas.
@export var charge_duration: float = 0.6
## Velocidad a la que ShoulderRun va a 1.0× (m/s), medida sobre el clip ya
## cocido (el pie apoyado barre el suelo a 4.3 m/s). El dash reproduce el ciclo
## a velocidad_real / charge_run_speed, así que la zancada avanza siempre lo
## mismo que el cuerpo y los pies NO patinan.
@export var charge_run_speed: float = 4.3
## Cuánto se queda puesto el gesto de frenazo (ShoulderCharge) después de
## empotrarse con algo, antes de enderezarse con ShoulderRecover (segundos).
@export var charge_impact_hold: float = 0.22
## Distancia máxima recorrida por la embestida (unidades).
@export var charge_distance: float = 4.5
## Aceleración del dash: cuánto tarda en alcanzar charge_speed (con 34 lo coge
## en ~0.26 s, así que se siente con peso, no como un teletransporte).
@export var charge_accel: float = 34.0
## Daño de la embestida al chocar con un oponente.
@export var charge_damage: float = 35.0
## Empuje hacía delante que se lleva el oponente (m/s reales de SU sistema de
## movimiento: las dianas de prueba se deslizan de verdad con esto).
@export var knockback_force: float = 14.0
## Bloqueo tras el dash o el impacto (segundos) antes de recuperar el control.
## Tiene que dar tiempo a verse el frenazo (charge_impact_hold) y la vuelta a la
## calma (ShoulderRecover): con 0.5 se ven los dos sin que se haga pesado.
@export var charge_recovery: float = 0.5
## Sacudida de cámara al embestir.
@export var charge_camera_shake: float = 0.40
## Rapidez con la que el personaje gira hacia la dirección de la embestida.
@export var charge_turn_speed: float = 2.5

@export_group("Combate cuerpo a cuerpo")
## Daño del puñetazo (pequeño a propósito: lo que pega fuerte son las habilidades).
@export var punch_damage: float = 8.0
## Daño de la patada.
@export var kick_damage: float = 14.0
## Alcance del puñetazo desde el centro del personaje.
@export var punch_reach: float = 0.85
## Grosor de la esfera de golpe del puñetazo.
@export var punch_hit_radius: float = 0.55
## Altura a la que golpea el puñetazo.
@export var punch_hit_height: float = 1.35
## Alcance de la patada.
@export var kick_reach: float = 1.15
## Grosor de la esfera de golpe de la patada.
@export var kick_hit_radius: float = 0.7
## Altura a la que golpea la patada.
@export var kick_hit_height: float = 0.95
## Momento del clip en el que impacta el puñetazo (el jab llega en el 25 %).
@export_range(0.0, 1.0, 0.01) var punch_hit_fraction: float = 0.25
## Momento del clip en el que impacta la patada. La patada nueva (Mixamo "Mma
## Kick", clip "Kick") extiende la pierna en t = 0.63 s de 1.60 s -> 0.40.
@export_range(0.0, 1.0, 0.01) var kick_hit_fraction: float = 0.40
## Empuje de los golpes cuerpo a cuerpo.
@export var melee_knockback: float = 4.0


# =============================================================================
#  ANIMACIONES  ← el sistema funciona aunque NO existan animaciones
# =============================================================================
@export_group("Animaciones")
## Si lo desactivas, el script ignora por completo el AnimationPlayer/Tree.
@export var use_animations: bool = true
## Nombre de la animación de reposo dentro del AnimationPlayer.
@export var anim_idle: StringName = &"Idle"
## Nombre de la animación de caminar.
@export var anim_walk: StringName = &"Walk"
## Nombre de la animación de correr.
@export var anim_run: StringName = &"Run"
## Nombre de la animación de subir en el salto.
@export var anim_jump: StringName = &"Jump"
## Nombre de la animación de caída.
@export var anim_fall: StringName = &"Fall"

# --- Estados OPCIONALES -------------------------------------------------------
# El sistema los tiene preparados, pero si el modelo no trae una animación con
# ese nombre el estado simplemente no se reproduce (sin errores ni T-pose).
# En cuanto añadas un clip con ese nombre, se activa solo.
## Nombre de la animación de aterrizaje.
@export var anim_land: StringName = &"Land"
## Clip del golpe recto con la mano IZQUIERDA (jab). Es el PRIMER golpe del combo.
@export var anim_punch_jab: StringName = &"Punch_Left"
## Clip del golpe recto con la mano DERECHA (cross). Es el SEGUNDO golpe del combo.
@export var anim_punch_cross: StringName = &"Punch_Right"
## Nombre de la animación de patada.
@export var anim_kick: StringName = &"Kick"
## Nombre de la animación de agachado (quieto).
@export var anim_crouch: StringName = &"Crouch"
## Nombre de la animación de agachado andando.
@export var anim_crouch_walk: StringName = &"CrouchWalk"
## Clip de la FLEXIÓN de carga del super salto (se queda ahí mientras cargas).
@export var anim_charge: StringName = &"Charge"
## Clip del IMPULSO del super salto.
@export var anim_super_jump: StringName = &"SuperJump"
## Clip de la CAÍDA EN PICADO del pisotón.
@export var anim_air_slam: StringName = &"AirSlam"
## Clip del GOLPE CONTRA EL SUELO al aterrizar de golpe.
@export var anim_slam_impact: StringName = &"SlamImpact"
## Clip de ARRANCAR la roca del suelo. Acaba EXACTAMENTE con la mole sobre la
## cabeza (la postura en la que siguen RockCarry y RockThrow).
@export var anim_rock_lift: StringName = &"RockLift"
## Clip de SOSTENER la roca quieto (bucle), con los brazos por encima.
@export var anim_rock_carry: StringName = &"RockCarry"
## Clip de ANDAR con la roca en alto (bucle). Se reproduce más despacio o más
## rápido según la velocidad real para que los pies no patinen (cuadra con
## rock_carry_walk_speed).
@export var anim_rock_carry_walk: StringName = &"RockCarryWalk"
## Clip del LANZAMIENTO de la roca (a dos manos, desde lo alto).
@export var anim_rock_throw: StringName = &"RockThrow"
## Clip de la CARGA del hombro, al iniciar la embestida (R).
@export var anim_shoulder_prep: StringName = &"ShoulderPrep"
## Clip de la CARRERA de la embestida: bucle de zancadas, hombro por delante.
## Se reproduce a velocidad_real / charge_run_speed para cuadrar el avance.
@export var anim_shoulder_run: StringName = &"ShoulderRun"
## Clip del FRENAZO al empotrarse con algo durante la embestida (R).
@export var anim_shoulder_charge: StringName = &"ShoulderCharge"
## Clip de la RECUPERACIÓN tras la embestida (R): volver a enderezarse.
@export var anim_shoulder_recover: StringName = &"ShoulderRecover"
## Tiempo de mezcla (crossfade) al cambiar de animación con el AnimationPlayer.
@export_range(0.0, 1.0, 0.05) var animation_blend_time: float = 0.2
## Ruta del StateMachinePlayback dentro del AnimationTree (no suele cambiarse).
@export var anim_playback_path: String = "parameters/playback"


# =============================================================================
#  REFERENCIAS A LOS NODOS  ← no suelen cambiarse, pero son editables
# =============================================================================
@export_group("Referencias")
## Contenedor visual que se gira según la dirección de movimiento ("Model").
@export var model_path: NodePath = ^"Model"
## Nodo con las animaciones del modelo.
@export var animation_player_path: NodePath = ^"AnimationPlayer"
## Árbol de animaciones modular (Idle/Walk/Run/Jump/Fall).
@export var animation_tree_path: NodePath = ^"AnimationTree"
## Cámara usada como referencia para mover al personaje en tercera persona.
@export var camera_path: NodePath = ^"Camera3D"
## Forma de colisión que se encoge al agacharse.
@export var collision_shape_path: NodePath = ^"CollisionShape3D"


# =============================================================================
#  HUESOS DE LAS MANOS  ← sólo para sujetar la roca; si no los hay, no pasa nada
# =============================================================================
@export_group("Huesos de las manos")
## Hueso de la mano IZQUIERDA. Se busca solo dentro del modelo. Si tu modelo usa
## otros nombres, cámbialos aquí (o déjalos mal: la roca aparecerá delante del
## pecho en vez de en las manos, sin errores).
@export var hand_bone_left: StringName = &"mixamorig_LeftHand"
## Hueso de la mano DERECHA.
@export var hand_bone_right: StringName = &"mixamorig_RightHand"
## Hueso del BRAZO izquierdo (el hombro, raíz de la cadena). Con el IK de la
## roca encendido sirve para anclar su centro al CUERPO y no a las manos (ver
## _actualizar_ik_roca).
@export var arm_bone_left: StringName = &"mixamorig_LeftArm"
## Hueso del brazo derecho.
@export var arm_bone_right: StringName = &"mixamorig_RightArm"
## Ajuste fino de la roca respecto al punto medio de las manos, en metros
## reales: con la Y la subes o la bajas. (El apoyo grande de llevarla sobre la
## cabeza ya lo pone rock_carry_lift; esto es sólo para descolocarla un dedo.)
@export var rock_hold_offset: Vector3 = Vector3(0.0, 0.02, 0.0)


# --- IK de los brazos al sostener la roca -------------------------------------
# De la carga de la mole se encargan DOS sistemas a la vez, repartidos:
#   · el clip (RockCarry / RockCarryWalk / RockThrow) pone el cuerpo entero,
#     hombro, brazo y antebrazo incluidos;
#   · el modificador BrazosIKRoca, hijo del esqueleto, recoloca EN CALIENTE
#     brazo + antebrazo + MANO para que cada mano llegue a su agarre de la
#     roca con la MUÑECA RECTA (los clips, construidos hueso a hueso, se la
#     dejaban doblada ~55°) y la palma mirando a la piedra.
# El IK se enciende al final del levantamiento y durante toda la carga, y se
# suelta al lanzar o al cancelar: entonces manda otra vez el clip, tal cual.
## Nodo del IK dentro del esqueleto (si no existe, el IK se salta sin errores).
@export var rock_ik_path: NodePath = ^"Model/CharacterModel/FuerzaModel/Skeleton3D/BrazosIKRoca"
## Centro de la roca respecto al punto medio de los dos BRAZOS (espacio del
## esqueleto; medido sobre la pose aprobada de llevar la mole). Con el IK
## encendido la roca va anclada al cuerpo para que los agarres, que van clavados
## a la roca, no se persigan a sí mismos.
@export var rock_ik_center_offset: Vector3 = Vector3(0.000651, 0.667244, 0.048911)
## Punto de agarre IZQUIERDO respecto al centro de la roca (espacio del
## esqueleto, medido sobre la pose aprobada: la muñeca queda 2.3 cm por fuera
## de la piedra, igual que se veía bien).
@export var rock_ik_grip_left: Vector3 = Vector3(0.059396, -0.422612, 0.018709)
## Punto de agarre DERECHO respecto al centro de la roca.
@export var rock_ik_grip_right: Vector3 = Vector3(-0.059396, -0.409711, -0.018709)
## Tramo del levantamiento (0-1) a partir del cual entra el IK, subiendo hasta
## el 100 % cuando la mole ya está arriba: antes de eso manda el clip entero.
@export_range(0.0, 1.0, 0.01) var rock_ik_from: float = 0.62


# -----------------------------------------------------------------------------
# Estado interno (no hace falta tocarlo)
# -----------------------------------------------------------------------------
var _visual: Node3D
var _anim_player: AnimationPlayer
var _anim_tree: AnimationTree
var _camera: Node3D
var _shape: CollisionShape3D

var _coyote_timer: float = 0.0
var _jump_buffer_timer: float = 0.0
var _is_sprinting: bool = false
var _current_animation: StringName = &""
var _has_animations: bool = false

# --- Estado nuevo: agacharse, combate y aterrizaje ---------------------------
var _is_crouching: bool = false
var _crouch_amount: float = 0.0
var _attack_timer: float = 0.0
var _current_attack: StringName = &""
var _land_timer: float = 0.0
var _stand_height: float = 1.8
var _stand_radius: float = 0.4

# --- Estado del combo de puñetazos -------------------------------------------
# _combo_step: 0 = ninguno, 1 = jab (mano izquierda), 2 = cross (mano derecha).
# _attack_length sirve para saber en qué punto del clip vamos.
var _attack_length: float = 0.0
var _combo_step: int = 0
var _combo_queued: bool = false

# --- Estado de las habilidades especiales ------------------------------------
# Se guarda en un enum para que sea imposible que dos habilidades se solapen:
# mientras _habilidad no sea NINGUNA, las demás quedan bloqueadas.
# Flujo de la roca (Q):  ARRANCAR_ROCA -> CARGAR_ROCA -> [clic izquierdo] LANZAR_ROCA
#                        En CARGAR_ROCA la mole va sobre la cabeza y SE PUEDE
#                        ANDAR (despacio): cargar y apuntar son el mismo estado.
#                        (ESC durante la carga cancela y deja la roca en el suelo)
# Flujo de la embestida (R): PREPARAR_EMBESTIDA -> EMBESTIDA -> RECUPERAR_EMBESTIDA
enum Habilidad { NINGUNA, CARGANDO_SALTO, SUPER_SALTO, GOLPE_AEREO, ARRANCAR_ROCA, CARGAR_ROCA, LANZAR_ROCA, PREPARAR_EMBESTIDA, EMBESTIDA, RECUPERAR_EMBESTIDA }

var _habilidad: Habilidad = Habilidad.NINGUNA
var _habilidad_timer: float = 0.0
var _habilidad_largo: float = 0.0
var _carga: float = 0.0
var _temblor: float = 0.0
var _impacto_timer: float = 0.0
## Animación forzada (el golpe contra el suelo), por encima de todo lo demás.
var _anim_especial: StringName = &""
var _roca: FuerzaRock = null
var _sujetando_roca: bool = false
var _roca_soltada: bool = false
var _esqueleto: Skeleton3D = null
## El IK de los brazos al sostener la roca (opcional: si la escena no lo trae,
## se salta sin errores y los brazos se quedan con lo que diga el clip).
var _ik_roca: FuerzaBrazosIK = null
# --- Apuntado de la roca (Q) ---------------------------------------------------
## Punto del mundo al que apunta la retícula (se recalcula cada fotograma).
var _objetivo_roca: Vector3 = Vector3.ZERO
## Punto apuntado CONGELADO al confirmar con el clic izquierdo (ZERO = sin
## apuntado: se lanzará con el tiro de seguridad hacia donde mira el modelo).
var _objetivo_tiro_roca: Vector3 = Vector3.ZERO
## La trayectoria + retícula visual del apuntado (null si no se está apuntando).
var _indicador_roca: FuerzaRockAim = null
# --- Embestida con el hombro (R) ----------------------------------------------
## Dirección de la embestida (se fija con la cámara al salir del preparado).
var _embestida_dir: Vector3 = Vector3.ZERO
## Distancia que le queda por recorrer al dash.
var _embestida_restante: float = 0.0
## Oponentes ya golpeados en esta embestida (no se repiten).
var _embestida_golpeados: Array = []
## Instante de empuje hacia delante tras chocar con un oponente.
var _embestida_empuje_timer: float = 0.0
## Tiempo que se mantiene el gesto de frenazo (ShoulderCharge) tras el impacto.
var _embestida_impacto_timer: float = 0.0
# --- Momento del golpe de los ataques cuerpo a cuerpo -------------------------
var _hit_pendiente: bool = false
var _hit_momento: float = 0.0
## Posición original del nodo visual (el temblor de la carga la desplaza un poco).
var _visual_pos_base: Vector3 = Vector3.ZERO


func _ready() -> void:
	_visual = get_node_or_null(model_path) as Node3D
	if _visual == null:
		# Sin nodo "Model" giramos el propio cuerpo, así el script nunca falla.
		_visual = self

	_anim_player = get_node_or_null(animation_player_path) as AnimationPlayer
	_anim_tree = get_node_or_null(animation_tree_path) as AnimationTree
	_camera = get_node_or_null(camera_path) as Node3D
	_shape = get_node_or_null(collision_shape_path) as CollisionShape3D
	# El esqueleto es OPCIONAL: sólo sirve para que la roca salga de las manos.
	_esqueleto = _buscar_esqueleto(_visual)
	# El IK de los brazos de la roca también es OPCIONAL (ver _actualizar_ik_roca).
	_ik_roca = get_node_or_null(rock_ik_path) as FuerzaBrazosIK
	_visual_pos_base = _visual.position

	_cache_stand_size()
	_setup_animations()


func _physics_process(delta: float) -> void:
	var on_floor_at_start: bool = is_on_floor()

	# --- Temporizadores de salto (coyote time + buffer) -----------------------
	_coyote_timer = coyote_time if on_floor_at_start else maxf(_coyote_timer - delta, 0.0)
	if Input.is_action_just_pressed("jump"):
		_jump_buffer_timer = jump_buffer_time
	else:
		_jump_buffer_timer = maxf(_jump_buffer_timer - delta, 0.0)

	# --- Entrada de teclado ---------------------------------------------------
	var input_dir: Vector2 = Input.get_vector(
		"move_left", "move_right", "move_forward", "move_backward"
	)
	var direction: Vector3 = _direction_from_input(input_dir)

	# --- Ataque, agacharse y aterrizaje ---------------------------------------
	# Se resuelven ANTES de calcular velocidades porque condicionan cuánto y
	# cómo se puede mover el personaje en este frame.
	_update_attack(delta)
	_update_crouch(delta)
	_update_landing(delta)
	# Las habilidades van DESPUÉS de las demás: mandan y pueden bloquearlas.
	_update_ability(delta)

	var attacking: bool = _attack_timer > 0.0

	# --- Correr (no se corre agachado, atacando ni usando una habilidad) ------
	_set_sprinting(
		Input.is_action_pressed("sprint")
		and direction != Vector3.ZERO
		and not _is_crouching
		and not attacking
		and _habilidad == Habilidad.NINGUNA
	)

	# --- Gravedad -------------------------------------------------------------
	velocity.y = maxf(velocity.y - gravity * delta, -max_fall_speed)

	# --- Salto (atacando o usando una habilidad no se puede saltar) -----------
	if _jump_buffer_timer > 0.0 and _coyote_timer > 0.0 and not attacking \
			and _habilidad == Habilidad.NINGUNA:
		velocity.y = jump_velocity
		_jump_buffer_timer = 0.0
		_coyote_timer = 0.0
		jumped.emit()

	# --- La habilidad puede pisar la velocidad (picado, dash, lanzamiento...) -
	_update_ability_velocity(delta)

	# --- Movimiento horizontal (aceleración / frenado suave) ------------------
	# La embestida (R) controla su propia velocidad: este bloque no la toca.
	if not _embestida_en_marcha():
		var target_speed: float = _current_target_speed(attacking)
		var horizontal: Vector3 = Vector3(velocity.x, 0.0, velocity.z)
		# En el AIRE (o cargando el super salto con la carrera ya lanzada) hay
		# ritmo propio: se acelera con air_acceleration × air_control y, si no se
		# toca nada, casi no se frena. Dos reglas para que el salto se sienta con
		# peso y no se pierda NADA de lo que traías:
		#   · el tope de velocidad NUNCA baja de la que ya llevas: la inercia del
		#     despegue se conserva entera (correr -> saltar -> seguir volando
		#     hacia delante) hasta gastarla girando o aterrizar;
		#   · sin dirección el frenado es suave (air_friction en el aire,
		#     charge_slide_friction cargando el salto), así se corrige el rumbo
		#     sin tirones y cargar no clava al personaje en seco.
		var aereo: bool = not on_floor_at_start
		var cargando: bool = _habilidad == Habilidad.CARGANDO_SALTO
		if aereo or cargando:
			var rate: float = air_acceleration * air_control
			if direction == Vector3.ZERO:
				rate = (air_friction if aereo else charge_slide_friction) * air_control
			var tope: float = maxf(target_speed * air_speed_multiplier, horizontal.length())
			horizontal = horizontal.move_toward(direction * tope, rate * delta)
		else:
			var rate_suelo: float = acceleration if direction != Vector3.ZERO else deceleration
			horizontal = horizontal.move_toward(direction * target_speed, rate_suelo * delta)
		velocity.x = horizontal.x
		velocity.z = horizontal.z

	# --- Girar el modelo ------------------------------------------------------
	# Con la carga de la roca (Q) o la embestida (R) en marcha la orientación la
	# manda la habilidad; el resto del tiempo, la dirección de movimiento.
	if _habilidad == Habilidad.CARGAR_ROCA and direction == Vector3.ZERO:
		# Quieto con la mole en alto: el cuerpo gira hacia donde apunta la
		# cámara, que es hacia donde va a salir el tiro. ANDANDO manda la
		# dirección de movimiento (el tiro se recalcula igual con la cámara).
		_rotate_visual_towards(_direccion_apuntado(), delta, false, rock_aim_turn_speed)
	elif _embestida_en_marcha():
		_rotate_visual_towards(_embestida_dir, delta, false, charge_turn_speed)
	else:
		# En el AIRE el cuerpo mira hacia donde VUELA (no hacia donde se pulsa):
		# así el pisotón cae orientado hacia la dirección en la que vas aunque
		# se suelten las teclas a mitad de caída.
		var rumbo: Vector3 = direction
		if not on_floor_at_start:
			var vuelo: Vector3 = Vector3(velocity.x, 0.0, velocity.z)
			if vuelo.length_squared() > 0.04:
				rumbo = vuelo.normalized()
		_rotate_visual_towards(rumbo, delta, attacking)

	# --- Física ---------------------------------------------------------------
	var pos_inicial: Vector3 = global_position
	move_and_slide()

	# --- La embestida mide lo que avanza y resuelve los choques ---------------
	if _habilidad == Habilidad.EMBESTIDA:
		_embestida_avanza(global_position - pos_inicial)

	if not on_floor_at_start and is_on_floor():
		_land_timer = land_duration
		landed.emit()
		# Un pisotón sólo revienta el suelo AL TOCARLO, nunca al pulsar la tecla.
		if _habilidad == Habilidad.GOLPE_AEREO and _impacto_timer <= 0.0:
			_impactar_suelo()

	_aplicar_temblor()
	_actualizar_ik_roca()
	_update_animation_state()
	_sincronizar_ciclos()


# =============================================================================
#  MOVIMIENTO — detalles internos
# =============================================================================

## Convierte la entrada del teclado en una dirección 3D relativa a la cámara.
## Así "adelante" siempre significa "hacia donde mira la cámara".
func _direction_from_input(input_dir: Vector2) -> Vector3:
	if input_dir == Vector2.ZERO:
		return Vector3.ZERO

	var forward: Vector3 = -_get_camera_basis().z
	forward.y = 0.0
	if forward.length_squared() < 0.0001:
		forward = Vector3.FORWARD
	else:
		forward = forward.normalized()

	var right: Vector3 = forward.cross(Vector3.UP).normalized()
	return (right * input_dir.x + forward * -input_dir.y).normalized()


func _get_camera_basis() -> Basis:
	if _camera != null:
		return _camera.global_transform.basis
	return global_transform.basis


## Gira el nodo visual (no la física) hacia la dirección de movimiento.
## speed_scale multiplica la rapidez de giro (1 = la configurada): el apuntado
## de la roca gira más despacio (pesado) y la embestida más rápido (decidida).
func _rotate_visual_towards(direction: Vector3, delta: float,
		attacking: bool = false, speed_scale: float = 1.0) -> void:
	if _visual == null or direction == Vector3.ZERO:
		return
	# En Godot el "frente" de un nodo es -Z.
	var target_yaw: float = atan2(-direction.x, -direction.z)
	# Atacando apenas puede corregir la dirección: el giro se siente pesado.
	var speed: float = rotation_speed * (attack_rotation_control if attacking else 1.0) * speed_scale
	# Peso independiente del framerate, controlado por rotation_speed.
	var weight: float = 1.0 - exp(-speed * delta)
	_visual.rotation.y = lerp_angle(_visual.rotation.y, target_yaw, weight)


func _set_sprinting(value: bool) -> void:
	if value == _is_sprinting:
		return
	_is_sprinting = value
	sprint_changed.emit(_is_sprinting)


# =============================================================================
#  ANIMACIONES — sistema modular, tolerante a que todavía no existan
# =============================================================================

func _setup_animations() -> void:
	_has_animations = false
	if _anim_player != null:
		_has_animations = _anim_player.get_animation_list().size() > 0

	if not use_animations:
		if _anim_tree != null:
			_anim_tree.active = false
		return

	if _anim_tree == null or not (_anim_tree.tree_root is AnimationNodeStateMachine):
		return

	var state_machine: AnimationNodeStateMachine = _anim_tree.tree_root

	# El AnimationTree sólo se activa si existen las animaciones OBLIGATORIAS
	# (la locomoción). De este modo nunca se generan errores mientras no haya un
	# modelo animado: si falta alguna, el script usa el AnimationPlayer directo.
	var can_blend: bool = _anim_player != null
	if can_blend:
		for state_name: StringName in _core_animation_states():
			if not _anim_player.has_animation(state_name) or not state_machine.has_node(state_name):
				can_blend = false
				break

	if not can_blend:
		_anim_tree.active = false
		return

	# Cada estado apunta a su animación real. Los estados OPCIONALES que el
	# modelo todavía no trae se quedan vacíos: siguen existiendo en el sistema
	# (y en el AnimationTree) y en cuanto aparezca un clip con ese nombre se
	# activan solos, sin tocar nada más.
	for state_name: StringName in _all_animation_states():
		if not state_machine.has_node(state_name):
			continue
		var node: AnimationNode = state_machine.get_node(state_name)
		if node is AnimationNodeAnimation:
			(node as AnimationNodeAnimation).animation = (
				state_name if _anim_player.has_animation(state_name) else &""
			)

	# Los clips de la roca en alto y de la embestida son NUEVOS: el grafo de la
	# escena todavía no tiene sus estados, así que se crean aquí (con sus
	# transiciones) la primera vez que se activa el sistema de animaciones.
	# No se toca ningún estado que ya existiera.
	for extra: StringName in [
		anim_rock_lift, anim_rock_carry, anim_rock_carry_walk,
		anim_shoulder_prep, anim_shoulder_run, anim_shoulder_charge, anim_shoulder_recover,
	]:
		_crear_estado_si_falta(state_machine, extra)

	_anim_tree.active = true


## Añade un estado al grafo del AnimationTree si todavía no existe y el modelo
## ya trae el clip. Se conecta con TODO el resto del grafo en ambos sentidos,
## para que travel() siempre encuentre camino y el personaje nunca se quede en
## una pose incongruente. Si el estado ya existe, no se toca nada.
func _crear_estado_si_falta(state_machine: AnimationNodeStateMachine, nombre: StringName) -> void:
	if nombre == &"" or state_machine.has_node(nombre):
		return
	if _anim_player == null or not _anim_player.has_animation(nombre):
		return

	var nodo: AnimationNodeAnimation = AnimationNodeAnimation.new()
	nodo.animation = nombre
	state_machine.add_node(nombre, nodo, Vector2(1560.0, 660.0))

	# Se conecta con todo el grafo en los dos sentidos. OJO: el motor NO admite
	# transiciones que SALGAN de "End" ni que ENTREN en "Start" (son los estados
	# fantasma del grafo), así que esas dos direcciones se saltan.
	for otro: StringName in state_machine.get_node_list():
		if otro == nombre:
			continue
		if otro != &"End":
			var ida: AnimationNodeStateMachineTransition = AnimationNodeStateMachineTransition.new()
			ida.xfade_time = 0.12
			state_machine.add_transition(otro, nombre, ida)
		if otro != &"Start":
			var vuelta: AnimationNodeStateMachineTransition = AnimationNodeStateMachineTransition.new()
			vuelta.xfade_time = 0.12
			state_machine.add_transition(nombre, otro, vuelta)


## Animaciones OBLIGATORIAS: sin las cinco el AnimationTree no se activa.
func _core_animation_states() -> Array[StringName]:
	return [anim_idle, anim_walk, anim_run, anim_jump, anim_fall]


## Todas las animaciones del sistema (obligatorias + opcionales).
func _all_animation_states() -> Array[StringName]:
	return [
		anim_idle, anim_walk, anim_run, anim_jump, anim_fall,
		anim_land, anim_punch_jab, anim_punch_cross, anim_kick, anim_crouch, anim_crouch_walk,
		anim_charge, anim_super_jump, anim_air_slam, anim_slam_impact,
		anim_rock_lift, anim_rock_carry, anim_rock_carry_walk, anim_rock_throw,
		anim_shoulder_prep, anim_shoulder_run, anim_shoulder_charge, anim_shoulder_recover,
	]


## Animación que corresponde a la habilidad en curso (&"" si no hay ninguna).
func _anim_de_habilidad() -> StringName:
	match _habilidad:
		Habilidad.CARGANDO_SALTO:
			return anim_charge
		Habilidad.SUPER_SALTO:
			return anim_super_jump
		Habilidad.GOLPE_AEREO:
			return anim_air_slam
		Habilidad.ARRANCAR_ROCA:
			return anim_rock_lift
		Habilidad.CARGAR_ROCA:
			# Con la mole en alto: quieto la sostiene con los brazos estirados
			# (RockCarry) y andando la lleva (RockCarryWalk). En los dos casos
			# va sobre la cabeza y el clic izquierdo sigue siendo el tiro.
			return anim_rock_carry_walk if get_planar_speed() > 0.15 else anim_rock_carry
		Habilidad.LANZAR_ROCA:
			return anim_rock_throw
		Habilidad.PREPARAR_EMBESTIDA:
			return anim_shoulder_prep
		Habilidad.EMBESTIDA:
			return anim_shoulder_run
		Habilidad.RECUPERAR_EMBESTIDA:
			# Si acaba de empotrarse con algo, primero se ve el frenazo
			# (ShoulderCharge) y sólo después se endereza (ShoulderRecover).
			return anim_shoulder_charge if _embestida_impacto_timer > 0.0 else anim_shoulder_recover
	return &""


func _update_animation_state() -> void:
	if not use_animations or not _has_animations:
		return
	var next_state: StringName = _resolve_animation_state()
	if next_state == _current_animation:
		return
	_current_animation = next_state
	_play_animation(next_state)


## Cuadra la velocidad de reproducción de los clips CÍCLICOS con la velocidad a
## la que se mueve de verdad el personaje. Sin esto, la carrera de la embestida
## patinaría (el clip avanza a su ritmo y el cuerpo al suyo) y andar con la roca
## iría en cámara lenta.
##
##   · ShoulderRun:   su pie apoyado barre el suelo a charge_run_speed m/s con el
##                    clip a 1.0×, así que se reproduce a velocidad_real /
##                    charge_run_speed (así la zancada SIEMPRE cuadra con el
##                    avance, aunque cambies charge_speed).
##   · RockCarryWalk: igual, pero con rock_carry_walk_speed (que cuadra con
##                    walk_speed: al ir más despacio por llevar la mole el ciclo
##                    gira más despacio en vez de patinar).
func _sincronizar_ciclos() -> void:
	_sincronizar_ciclo(anim_shoulder_run, _habilidad == Habilidad.EMBESTIDA, charge_run_speed)
	_sincronizar_ciclo(anim_rock_carry_walk, _habilidad == Habilidad.CARGAR_ROCA,
		rock_carry_walk_speed)


## Pone el multiplicador de velocidad de UN estado cíclico (o lo devuelve a 1.0
## cuando ese estado no está en marcha, para no tocar nada más).
func _sincronizar_ciclo(nombre: StringName, activo: bool, velocidad_base: float) -> void:
	var nodo: AnimationNodeAnimation = _nodo_de_estado(nombre)
	if nodo == null:
		return
	# AnimationNodeAnimation NO tiene "speed": la velocidad de un estado se
	# controla con la línea de tiempo propia del nodo. Con "use_custom_timeline"
	# el estado reparte la animación sobre timeline_length segundos, así que una
	# línea de tiempo más CORTA hace girar el clip más rápido y una igual a la
	# duración del clip lo deja a 1.0×.
	var largo_clip: float = _largo_del_clip(nombre)
	if largo_clip <= 0.0:
		return
	if not activo:
		nodo.use_custom_timeline = false
		nodo.timeline_length = largo_clip
		return
	var factor: float = clampf(get_planar_speed() / maxf(velocidad_base, 0.05), 0.4, 3.0)
	nodo.use_custom_timeline = true
	nodo.timeline_length = largo_clip / factor


## Duración real del clip asociado a un estado (0.0 si no se encuentra).
func _largo_del_clip(nombre: StringName) -> float:
	if _anim_player == null or not _anim_player.has_animation(nombre):
		return 0.0
	return _anim_player.get_animation(nombre).length


## Nodo de animación de un estado del grafo (null si no existe o no es una
## animación simple). Con esto se puede tocar su velocidad de reproducción.
func _nodo_de_estado(nombre: StringName) -> AnimationNodeAnimation:
	if _anim_tree == null or _anim_tree.tree_root == null:
		return null
	var maquina: AnimationNodeStateMachine = _anim_tree.tree_root as AnimationNodeStateMachine
	if maquina == null or not maquina.has_node(nombre):
		return null
	return maquina.get_node(nombre) as AnimationNodeAnimation


## Decide qué animación toca según el estado físico del personaje.
## El orden de las comprobaciones ES la prioridad: el combate manda sobre todo.
func _resolve_animation_state() -> StringName:
	# 0) Habilidades especiales y animaciones forzadas: mandan sobre TODO,
	#    incluido el golpe contra el suelo que cierra el pisotón.
	if _anim_especial != &"":
		return _anim_especial
	var de_habilidad: StringName = _anim_de_habilidad()
	if de_habilidad != &"":
		return de_habilidad

	# 1) Atacando: puñetazo o patada por encima de cualquier otra cosa.
	if _attack_timer > 0.0 and _current_attack != &"":
		return _current_attack

	# 2) En el aire: subiendo = salto, cayendo = caída.
	if not is_on_floor():
		return anim_jump if velocity.y > 0.0 else anim_fall

	# 3) Aterrizaje: estado breve al tocar el suelo.
	if _land_timer > 0.0:
		return anim_land

	# 4) Agachado: quieto o andando agachado.
	if _is_crouching:
		return anim_crouch_walk if get_planar_speed() > 0.15 else anim_crouch

	# 5) Movimiento normal.
	if get_planar_speed() < 0.15:
		return anim_idle
	return anim_run if _is_sprinting else anim_walk


## Sustituto cuando el modelo todavía no trae esa animación. NO se inventa nada:
## se reutiliza el clip de locomoción más parecido, para que el personaje no se
## quede congelado en una pose que no corresponde (p. ej. la de caída).
func _fallback_for(anim_name: StringName) -> StringName:
	if anim_name == anim_crouch_walk:
		return anim_walk
	if anim_name == anim_land:
		return anim_walk if get_planar_speed() > 0.15 else anim_idle
	if anim_name == anim_charge or anim_name == anim_rock_lift:
		# Cargar fuerza y arrancar la roca son flexiones: se agacha y espera.
		return anim_crouch
	if anim_name == anim_rock_throw:
		return anim_punch_cross      # el lanzamiento es un empujón con las dos manos
	if anim_name == anim_super_jump:
		return anim_jump
	if anim_name == anim_air_slam:
		return anim_fall
	if anim_name == anim_slam_impact:
		return anim_land
	if anim_name == anim_shoulder_prep:
		# Sin clip propio, la carga del hombro se parece a agacharse un poco.
		return anim_crouch
	if anim_name == anim_shoulder_run:
		return anim_run               # sin clip de zancadas, al menos corre
	if anim_name == anim_shoulder_charge:
		return anim_run               # la embestida es una carrera
	if anim_name == anim_shoulder_recover:
		return anim_idle
	if anim_name == anim_rock_carry:
		# La mole ya está sobre la cabeza en el último fotograma de RockLift.
		return anim_rock_lift
	if anim_name == anim_rock_carry_walk:
		return anim_walk
	# Puñetazo, patada y agachado quieto: se queda de pie y quieto.
	return anim_idle


## Reproduce una animación usando AnimationTree si está disponible y, si no,
## el AnimationPlayer. Si al modelo le falta el clip, usa un sustituto en vez de
## dejar al personaje en una pose incongruente. Nunca genera errores.
func _play_animation(anim_name: StringName) -> void:
	if not _has_animations or _anim_player == null:
		return

	# Clip real si existe; si no, el sustituto de locomoción más parecido.
	var clip: StringName = anim_name
	if not _anim_player.has_animation(clip):
		clip = _fallback_for(anim_name)
	if not _anim_player.has_animation(clip):
		return

	if _anim_tree != null and _anim_tree.active:
		var playback: AnimationNodeStateMachinePlayback = _anim_tree.get(anim_playback_path) as AnimationNodeStateMachinePlayback
		if playback != null:
			if playback.is_playing():
				playback.travel(clip)
			else:
				playback.start(clip, true)
			return

	_anim_player.play(clip, animation_blend_time)


## Vuelve a evaluar el sistema de animaciones. Útil si cargas las animaciones
## o el modelo 3D en tiempo de ejecución.
func refresh_animations() -> void:
	_setup_animations()
	_current_animation = &""


# =============================================================================
#  AGACHARSE, COMBATE Y ATERRIZAJE — detalles internos
# =============================================================================

## Guarda el tamaño original de la cápsula (de pie) y la duplica para poder
## encogerla sin modificar el recurso guardado en la escena.
func _cache_stand_size() -> void:
	if _shape == null or not (_shape.shape is CapsuleShape3D):
		return
	var capsule: CapsuleShape3D = (_shape.shape as CapsuleShape3D).duplicate()
	_shape.shape = capsule
	_stand_height = capsule.height
	_stand_radius = capsule.radius
	_apply_crouch_shape(0.0)


## Encoge la cápsula según lo agachado que esté (0 = de pie, 1 = agachado).
## El centro se recoloca para que los pies sigan apoyados en el suelo.
func _apply_crouch_shape(amount: float) -> void:
	if _shape == null or not (_shape.shape is CapsuleShape3D):
		return
	var capsule: CapsuleShape3D = _shape.shape
	var min_height: float = _stand_radius * 2.0 + 0.02
	var height: float = lerpf(_stand_height, maxf(crouch_height, min_height), clampf(amount, 0.0, 1.0))
	capsule.height = height
	_shape.position.y = height * 0.5


## ¿Cabe de pie aquí? Lanza una cápsula del tamaño original hacia arriba.
## Devuelve false si hay un techo, así no se puede levantar dentro de un túnel.
func _can_stand_up() -> bool:
	if not block_stand_under_ceiling:
		return true
	var world: World3D = get_world_3d()
	if world == null:
		return true
	var space: PhysicsDirectSpaceState3D = world.direct_space_state
	if space == null:
		return true

	var probe: CapsuleShape3D = CapsuleShape3D.new()
	probe.radius = maxf(_stand_radius - 0.02, 0.05)
	probe.height = maxf(_stand_height - 0.06, probe.radius * 2.0 + 0.02)

	var params: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
	params.shape = probe
	params.transform = Transform3D(
		Basis(), global_position + Vector3.UP * (_stand_height * 0.5 + 0.04)
	)
	params.collision_mask = collision_mask
	params.exclude = [get_rid()]
	params.margin = 0.0

	return space.intersect_shape(params, 1).is_empty()


## Lee el CTRL y aplica o levanta la postura agachada con transición suave.
func _update_crouch(delta: float) -> void:
	var wants_crouch: bool = Input.is_action_pressed("crouch")
	# Durante un ataque no se cambia de postura: se mantiene la que hubiera.
	# Con una habilidad en marcha tampoco (la postura la manda su animación).
	if (_attack_timer > 0.0 and block_crouch_while_attacking) or _habilidad != Habilidad.NINGUNA:
		wants_crouch = _is_crouching

	if wants_crouch and not _is_crouching:
		_is_crouching = true
		crouch_changed.emit(true)
	elif not wants_crouch and _is_crouching and _can_stand_up():
		_is_crouching = false
		crouch_changed.emit(false)

	# Transición suave de la cápsula y de la cámara (nada de saltos bruscos).
	var target: float = 1.0 if _is_crouching else 0.0
	_crouch_amount = move_toward(_crouch_amount, target, crouch_transition_speed * delta)
	_apply_crouch_shape(_crouch_amount)
	if _camera != null and _camera.has_method("set_height_offset"):
		_camera.call("set_height_offset", -crouch_camera_drop * _crouch_amount)


## Lee el ratón y resuelve los ataques y el combo de puñetazos.
##
##   · 1 clic                          -> jab (mano izquierda) y vuelve a lo que hacía.
##   · 2 clics rápidos (dentro de      -> jab + cross encadenados (1-2).
##     combo_window)                       El cross sale en combo_cancel_point,
##                                         comiéndose la recuperación del jab.
##   · 2 clics lentos                  -> dos jabs sueltos (el segundo ya está
##                                         fuera de la ventana de combo).
##
## Nunca se producen dos jabs seguidos por un doble clic: el segundo clic, si
## cae dentro de la ventana, se guarda para el cross en vez de reiniciar el jab.
func _update_attack(delta: float) -> void:
	# --- Ya hay un ataque en curso -------------------------------------------
	if _attack_timer > 0.0:
		_attack_timer = maxf(_attack_timer - delta, 0.0)
		var transcurrido: float = _attack_length - _attack_timer

		# ¿Le toca al golpe? Aquí es donde el puñetazo/patada hace daño de verdad
		# (con la mano o el pie ya extendidos), no al pulsar el botón.
		if _hit_pendiente and transcurrido >= _hit_momento:
			_hit_pendiente = false
			_aplicar_golpe_cuerpo_a_cuerpo()

		# Segundo clic dentro de la ventana del combo: se apunta el cross.
		if _combo_step == 1 and transcurrido <= combo_window \
				and Input.is_action_just_pressed("attack_punch"):
			_combo_queued = true

		# El cross sale en cuanto el jab pasa su punto de cancelación. Así se
		# come su recuperación y los dos golpes se ven seguidos, sin congelarse.
		if _combo_queued and _combo_step == 1 \
				and transcurrido >= _attack_length * combo_cancel_point:
			_start_attack(anim_punch_cross, punch_duration)
			return

		if _attack_timer <= 0.0:
			_current_attack = &""
			_combo_step = 0
			_combo_queued = false
			_hit_pendiente = false
			attack_finished.emit()
		return

	# --- No hay ataque: se puede empezar uno ---------------------------------
	# Sólo se ataca con los pies en el suelo y sin una habilidad en marcha
	# (las habilidades se bloquean entre sí).
	if not is_on_floor() or _habilidad != Habilidad.NINGUNA:
		return

	if Input.is_action_just_pressed("attack_punch"):
		_start_attack(anim_punch_jab, punch_duration)
	elif Input.is_action_just_pressed("attack_kick"):
		_start_attack(anim_kick, kick_duration)


func _start_attack(attack_anim: StringName, fallback_duration: float) -> void:
	_current_attack = attack_anim
	_attack_length = _clip_length(attack_anim, fallback_duration)
	_attack_timer = _attack_length
	# El combo lo forman el jab (paso 1) y el cross (paso 2). La patada no
	# encadena con nada, así que reinicia el contador del combo.
	_combo_queued = false
	if attack_anim == anim_punch_jab:
		_combo_step = 1
	elif attack_anim == anim_punch_cross:
		_combo_step = 2
	else:
		_combo_step = 0
	# Momento exacto del impacto, para aplicar el daño cuando la mano o el pie
	# ya están extendidos (no al pulsar el botón).
	var fraccion: float = kick_hit_fraction if attack_anim == anim_kick else punch_hit_fraction
	_hit_momento = _attack_length * clampf(fraccion, 0.0, 1.0)
	_hit_pendiente = true
	# Se reproduce ya, sin esperar al cambio de estado de este mismo frame.
	_current_animation = attack_anim
	_play_animation(attack_anim)
	attack_started.emit(attack_anim)


## Duración real del clip si el modelo lo trae; si no, la duración de reserva.
func _clip_length(anim_name: StringName, fallback: float) -> float:
	if _anim_player != null and _anim_player.has_animation(anim_name):
		return maxf(_anim_player.get_animation(anim_name).length, 0.05)
	return maxf(fallback, 0.05)


## Cronometra el estado de aterrizaje (al aterrizar se frena un poco).
func _update_landing(delta: float) -> void:
	if _land_timer > 0.0:
		_land_timer = maxf(_land_timer - delta, 0.0)


## Velocidad objetivo teniendo en cuenta correr, agacharse, atacar y aterrizar.
func _current_target_speed(attacking: bool) -> float:
	# Las habilidades que se hacen en el sitio dejan al personaje clavado: así
	# los pies de sus animaciones (que van plantados) no patinan.
	if _esta_en_sitio():
		return 0.0
	if attacking:
		# Atacando apenas se avanza: como mucho un pequeño paso de acometida.
		return walk_speed * attack_move_multiplier
	var speed: float = sprint_speed if _is_sprinting else walk_speed
	if _habilidad == Habilidad.CARGAR_ROCA:
		# Con la mole en alto se anda al 65 % y NO se corre: da igual que el
		# jugador mantenga SHIFT, cargada no hay sprint.
		speed = walk_speed * rock_carry_speed
	if _is_crouching:
		speed *= crouch_speed_multiplier
	if _land_timer > 0.0:
		speed *= land_move_multiplier
	return speed


# =============================================================================
#  HABILIDADES ESPECIALES — super salto, pisotón, roca y embestida
# =============================================================================
#  Cada habilidad es un ESTADO propio (enum Habilidad). Mientras uno está en
#  marcha, los demás quedan bloqueados: es imposible que dos se solapen.
#
#   1) SUPER SALTO — mantén SPACE. La carga se ve: el cuerpo baja con la
#      animación de flexión, tiembla y la cámara acompaña. Al soltar, la
#      velocidad de salida va de super_jump_min_velocity a super_jump_max_velocity
#      según lo que hayas cargado. Un toque rápido = salto NORMAL de siempre.
#   2) PISOTÓN — E en el aire. Entra en picado a air_slam_speed, con el cuerpo
#      orientado hacia abajo, y AL TOCAR EL SUELO (nunca antes) suelta una onda
#      expansiva con polvo, escombros, chispas, sacudida de cámara y daño en
#      área a todo lo que esté dentro de air_slam_radius.
#   3) ROCA — Q en el suelo. La mole se levanta con las DOS manos por encima de
#      la cabeza y ahí se queda mientras la cargas:
#         Q  -> arranca una mole del suelo (RockLift). La roca se ve subir con
#               las manos: NO aparece de golpe ya sobre la cabeza.
#         ...-> LA CARGA (CARGAR_ROCA): la mole va apoyada sobre los brazos
#               estirados, el personaje PUEDE ANDAR (al 65 %, sin correr) y a
#               la vez apuntar: la cámara manda, la trayectoria y la retícula
#               se dibujan cada fotograma, y el cuerpo gira hacia donde apunta
#               cuando está quieto (andando gira hacia donde anda).
#         CLIC IZQUIERDO -> lanza (RockThrow): a dos manos desde lo alto, la
#               roca sale hacia el punto de la retícula con física de verdad
#               (parábola resuelta con su velocidad y su gravedad, ver
#               _direccion_balistica)
#         ESC -> cancela: la roca se cae al suelo y desaparece.
#      Mientras la lleva, el clic izquierdo NO hace el jab: confirma el tiro.
#   4) EMBESTIDA CON EL HOMBRO — R en el suelo:
#         preparación -> CARRERA con zancadas de verdad (ShoulderRun, bucle que
#         se reproduce a velocidad_real / charge_run_speed: la zancada avanza
#         lo mismo que el cuerpo, así que los pies NO patinan) -> impacto.
#         El dash es movimiento de verdad (tope de tiempo y de distancia, sin
#         teletransportes), choca con paredes como cualquier movimiento y al
#         conectar hace daño + empuje real con la API de siempre
#         [take_damage(cantidad, desde, empuje)]. Contra un oponente o un muro
#         se ve el frenazo (ShoulderCharge) y después se endereza
#         (ShoulderRecover) antes de volver a Idle/Walk/Run. La dirección se
#         apunta con la cámara, igual que la roca.
# =============================================================================

## ¿La habilidad en curso deja al personaje clavado en el sitio?
func _esta_en_sitio() -> bool:
	if _anim_especial != &"":
		return true
	# La carga de la roca es la EXCEPCIÓN: con la mole sobre la cabeza se puede
	# andar (más despacio y sin correr). Sus clips llevan los pies bien puestos
	# y sincronizados, así que no patinan aunque el personaje avance.
	if _habilidad == Habilidad.CARGAR_ROCA:
		return false
	# El pisotón (E) TAMPOCO clava al personaje: en el aire conserva la inercia
	# y se puede seguir corrigiendo la caída con la dirección (ver el bloque de
	# movimiento horizontal). Lo único que impone es la velocidad VERTICAL.
	if _habilidad == Habilidad.GOLPE_AEREO:
		return false
	# Cargar el super salto TAMPOCO clava al personaje: la carrera se conserva
	# mientras se carga (con un roce suave, ver el bloque de movimiento) y sale
	# entera en el despegue: correr -> SPACE -> saltar mantiene el avance. Lo
	# único que decide la carga es la velocidad VERTICAL al soltar.
	if _habilidad == Habilidad.CARGANDO_SALTO:
		return false
	return _habilidad != Habilidad.NINGUNA and _habilidad != Habilidad.SUPER_SALTO


## Lee las teclas y lleva la máquina de estados de las habilidades.
func _update_ability(delta: float) -> void:
	# Recuperación tras el pisotón: no se puede hacer nada mientras dura.
	if _impacto_timer > 0.0:
		_impacto_timer = maxf(_impacto_timer - delta, 0.0)
		if _impacto_timer <= 0.0:
			_anim_especial = &""
			if _habilidad == Habilidad.GOLPE_AEREO:
				_habilidad = Habilidad.NINGUNA

	match _habilidad:
		Habilidad.NINGUNA:
			_empezar_segun_entrada()
		Habilidad.CARGANDO_SALTO:
			_actualizar_carga(delta)
		Habilidad.SUPER_SALTO:
			_habilidad_timer = maxf(_habilidad_timer - delta, 0.0)
			if _habilidad_timer <= 0.0:
				_habilidad = Habilidad.NINGUNA
		Habilidad.GOLPE_AEREO:
			pass   # la velocidad la pone _update_ability_velocity()
		Habilidad.ARRANCAR_ROCA:
			_actualizar_arranque_roca(delta)
		Habilidad.CARGAR_ROCA:
			_actualizar_apuntado()
		Habilidad.LANZAR_ROCA:
			_actualizar_lanzamiento(delta)
		Habilidad.PREPARAR_EMBESTIDA:
			_actualizar_preparacion_embestida(delta)
		Habilidad.EMBESTIDA:
			_actualizar_embestida(delta)
		Habilidad.RECUPERAR_EMBESTIDA:
			_actualizar_recuperacion_embestida(delta)


## ¿Qué habilidad quiere empezar el jugador?
func _empezar_segun_entrada() -> void:
	var en_suelo: bool = is_on_floor()

	# 1) SPACE en el suelo -> empieza la carga del super salto.
	if super_jump_enabled and en_suelo and Input.is_action_just_pressed("jump") \
			and not is_attacking() and not _is_crouching:
		_habilidad = Habilidad.CARGANDO_SALTO
		_carga = 0.0
		_jump_buffer_timer = 0.0        # el salto normal NO se dispara
		_temblor = charge_tremor * 0.35
		return

	# 2) E en el aire -> pisotón.
	if air_slam_enabled and not en_suelo and Input.is_action_just_pressed("air_slam") \
			and _altura_sobre_suelo() >= air_slam_min_height:
		_habilidad = Habilidad.GOLPE_AEREO
		_habilidad_timer = 0.0
		_habilidad_largo = 0.0
		return

	# 3) Q en el suelo -> arranca una roca (si no tiene ya una). Al terminar el
	#    levantamiento NO se lanza: pasa a cargarla sobre la cabeza (CARGAR_ROCA)
	#    y espera al clic izquierdo para confirmar el tiro. Mientras la lleva
	#    puede andar (despacio) y apuntar a la vez.
	if rock_throw_enabled and en_suelo and Input.is_action_just_pressed("rock_throw") \
			and not is_attacking() and not _tiene_roca():
		_habilidad = Habilidad.ARRANCAR_ROCA
		_habilidad_largo = _clip_length(anim_rock_lift, 1.26)
		_habilidad_timer = _habilidad_largo
		# La mole nace YA, al pulsar Q: se la ve levantarse con las manos durante
		# todo el clip en vez de aparecer de golpe sobre la cabeza al final.
		_crear_roca()
		# El ESC ya no toca el ratón durante todo el tiro: ni en el levantamiento
		# (esta parte dura más de un segundo y el ratón se quedaba suelto a
		# medias), ni apuntando (donde cancela el tiro), ni al lanzar.
		_bloquear_toggle_captura(true)
		return

	# 4) R en el suelo -> embestida con el hombro (preparación + carrera).
	if shoulder_charge_enabled and en_suelo \
			and Input.is_action_just_pressed("shoulder_charge") \
			and not is_attacking() and not _is_crouching:
		_empezar_embestida()
		return


# --- 1) SUPER SALTO ----------------------------------------------------------
func _actualizar_carga(delta: float) -> void:
	# Si se queda sin suelo (un borde, una rampa) la carga se cancela: no hay
	# forma de salir volando desde el aire.
	if not is_on_floor():
		_habilidad = Habilidad.NINGUNA
		_carga = 0.0
		_temblor = 0.0
		return

	_carga = minf(_carga + delta, super_jump_max_charge)
	var fuerza: float = _carga / maxf(super_jump_max_charge, 0.01)

	# El temblor crece con la carga: se le ve juntando fuerza.
	_temblor = charge_tremor * (0.35 + 0.65 * fuerza)

	# La cámara baja con la flexión. _update_crouch() la recoloca cada frame,
	# así que al soltar la carga todo vuelve a su sitio solo.
	if _camera != null and _camera.has_method("set_height_offset"):
		_camera.call("set_height_offset", -charge_camera_drop * fuerza)

	if not Input.is_action_pressed("jump"):
		_soltar_carga()


func _soltar_carga() -> void:
	var cargado: float = _carga
	_carga = 0.0
	_temblor = 0.0
	_jump_buffer_timer = 0.0

	if cargado < super_jump_min_charge:
		# Toque corto: SALTO NORMAL, exactamente el de siempre.
		velocity.y = jump_velocity
		_habilidad = Habilidad.NINGUNA
		jumped.emit()
		return

	# Super salto: cuanto más ha cargado, más alto sale.
	var fuerza: float = clampf(
		inverse_lerp(super_jump_min_charge, super_jump_max_charge, cargado), 0.0, 1.0)
	velocity.y = lerpf(super_jump_min_velocity, super_jump_max_velocity, fuerza)
	_coyote_timer = 0.0
	jumped.emit()

	_habilidad = Habilidad.SUPER_SALTO
	_habilidad_largo = _clip_length(anim_super_jump, 0.62)
	_habilidad_timer = _habilidad_largo

	# El despegue CONSERVA el movimiento horizontal tal cual (velocidad.x/z no se
	# tocan aquí): si venías corriendo, sigues volando hacia delante. Sólo se
	# asegura un empujón mínimo si se venía casi parado.
	_impulsar_despegue()

	# El suelo se agrieta bajo los pies y la cámara lo nota.
	_polvo_bajo_los_pies(1.5 + fuerza * 1.3)
	FuerzaCombat.sacudir_camara(get_tree(), super_jump_camera_shake * (0.45 + 0.55 * fuerza))


## Empujón horizontal mínimo del despegue del super salto: si ya se venía a más
## velocidad que super_jump_forward_impulse no hace NADA (la carrera se conserva
## entera); si no, se sale en la dirección de entrada (o hacia donde mira el
## modelo) a esa velocidad mínima. La velocidad vertical no se toca aquí: la
## puso _soltar_carga según la carga.
func _impulsar_despegue() -> void:
	var horizontal: Vector3 = Vector3(velocity.x, 0.0, velocity.z)
	if horizontal.length() >= super_jump_forward_impulse:
		return
	var input_dir: Vector2 = Input.get_vector(
		"move_left", "move_right", "move_forward", "move_backward")
	var rumbo: Vector3 = _direction_from_input(input_dir)
	if rumbo == Vector3.ZERO:
		rumbo = _direccion_modelo()
	velocity.x = rumbo.x * super_jump_forward_impulse
	velocity.z = rumbo.z * super_jump_forward_impulse


# --- Velocidad que imponen las habilidades -----------------------------------
## Velocidad que imponen las habilidades que se hacen en el sitio y los dash
## (embestida). Va DESPUÉS de la gravedad a propósito: así el picado del pisotón
## no lo frena el límite normal de caída (max_fall_speed).
func _update_ability_velocity(delta: float) -> void:
	# --- Embestida (R): preparación, dash y frenada ---------------------------
	if _habilidad == Habilidad.PREPARAR_EMBESTIDA:
		# Se clava en el sitio para cargar el hombro: el impulso sale DESPUÉS.
		velocity.x = move_toward(velocity.x, 0.0, charge_accel * delta)
		velocity.z = move_toward(velocity.z, 0.0, charge_accel * delta)
		return

	if _habilidad == Habilidad.RECUPERAR_EMBESTIDA:
		# Frena la carrera de forma progresiva: ni tirón ni patinazo. Si acaba
		# de chocar con alguien, se queda empujando hacia delante un instante.
		var frenado: float = maxf(charge_speed, 1.0) / maxf(charge_recovery, 0.05)
		var arrastre: float = 1.4 if _embestida_empuje_timer > 0.0 else 0.0
		velocity.x = move_toward(velocity.x, _embestida_dir.x * arrastre, frenado * delta)
		velocity.z = move_toward(velocity.z, _embestida_dir.z * arrastre, frenado * delta)
		return

	if _habilidad == Habilidad.EMBESTIDA:
		# El DASH: la velocidad se impone aquí y el movimiento lo sigue
		# resolviendo move_and_slide (paredes, escalones, enemigos...). Sube
		# poco a poco hasta charge_speed: se siente el peso, no un salto.
		var objetivo: Vector3 = _embestida_dir * maxf(charge_speed, 0.5)
		var paso: float = maxf(charge_accel, 1.0) * delta
		velocity.x = move_toward(velocity.x, objetivo.x, paso)
		velocity.z = move_toward(velocity.z, objetivo.z, paso)
		return

	# --- Pisotón (E): sólo el picado -----------------------------------------
	# La X y la Z NO se tocan aquí: el pisotón conserva la velocidad horizontal
	# que traía (y se puede corregir) con el control aéreo de más abajo. Lo
	# único que impone la habilidad es la caída vertical, que además va DESPUÉS
	# de la gravedad para que no la recorte max_fall_speed.
	if _habilidad != Habilidad.GOLPE_AEREO or _impacto_timer > 0.0:
		return
	velocity.y = move_toward(velocity.y, -air_slam_speed, air_slam_accel * delta)


## Al tocar el suelo: onda expansiva, daño en área, efectos y bloqueo breve.
func _impactar_suelo() -> void:
	# El puño es el que golpea, así que la onda nace justo debajo de él y no en
	# el centro del cuerpo: así el efecto se lee como CONSECUENCIA del puñetazo.
	# (La altura sí es la del personaje, que es el nivel del suelo.)
	var punto: Vector3 = _punto_del_puno()
	var centro: Vector3 = global_position
	if punto != Vector3.ZERO:
		centro = Vector3(punto.x, global_position.y, punto.z)

	var onda: FuerzaShockwave = FuerzaShockwave.new()
	onda.name = "OndaPisotón"
	onda.radius = air_slam_radius
	onda.damage = air_slam_damage
	onda.knockback = air_slam_knockback
	onda.autor = self
	onda.position = centro
	_contenedor_efectos().add_child(onda)

	# La animación del golpe contra el suelo manda durante la recuperación.
	_anim_especial = anim_slam_impact
	_impacto_timer = _clip_length(anim_slam_impact, 0.6) + maxf(air_slam_recovery, 0.05)
	FuerzaCombat.sacudir_camara(get_tree(), air_slam_camera_shake)


# --- 3) ROCA -----------------------------------------------------------------
#  Q -> levanta la mole del suelo con las dos manos hasta encima de la cabeza
#  -> CARGA: la sostiene en alto, PUEDE ANDAR despacio y apuntar a la vez (la
#  cámara manda y la trayectoria se dibuja cada fotograma) -> CLIC IZQUIERDO
#  confirma el tiro -> el clip la suelta con física real.
#  ESC durante el levantamiento o la carga CANCELA: la mole se cae al suelo.
func _actualizar_arranque_roca(delta: float) -> void:
	# La mole YA ha nacido (se crea al pulsar Q) y va siguiendo a las dos manos
	# mientras el personaje se agacha a agarrarla y la sube por encima de la
	# cabeza: se la ve levantarse, no aparece de golpe al final del clip.
	_actualizar_roca_sujeta()
	# ESC durante el levantamiento también cancela: la roca se cae al suelo y
	# el personaje vuelve a estar libre.
	if Input.is_action_just_pressed("ui_cancel"):
		_cancelar_apuntado()
		return
	_habilidad_timer = maxf(_habilidad_timer - delta, 0.0)
	if _habilidad_timer > 0.0:
		return
	# Se acabó el levantamiento: la mole queda apoyada sobre las manos y el
	# personaje pasa a cargarla (y apuntar). El tiro NO sale solo: lo confirma
	# el jugador con el clic izquierdo.
	_crear_roca()
	_empezar_apuntado()


## Apuntado: recalcula cada fotograma el punto de la mira, mantiene la roca
## entre las manos y dibuja la trayectoria. Espera confirmación (clic
## izquierdo) o cancelación (ESC).
func _actualizar_apuntado() -> void:
	_actualizar_roca_sujeta()
	# _update_crouch() recoloca la cámara cada fotograma: este offset se aplica
	# después (las habilidades van las últimas) y le gana hasta que se deje de
	# apuntar, momento en el que la propia recolocación lo devuelve a su sitio.
	_bloquear_toggle_captura(true)
	_fijar_altura_camara(rock_aim_camera_lift)

	# Red de seguridad: sin roca en las manos no hay nada que apuntar.
	if not _tiene_roca():
		_terminar_apuntado()
		return

	_objetivo_roca = _calcular_punto_objetivo()
	_mostrar_indicador()

	# ESC cancela el apuntado (mientras se apunta, ESC NO toca el ratón: la
	# cámara lo tiene bloqueado justo para esto).
	if Input.is_action_just_pressed("ui_cancel"):
		_cancelar_apuntado()
		return

	# CLIC IZQUIERDO: confirma el tiro. Ojo: con la habilidad en marcha el clic
	# no dispara el jab (_update_attack() ya lo bloquea), así que no se pisan.
	if Input.is_action_just_pressed("attack_punch"):
		_confirmar_lanzamiento()


## Entra en CARGAR_ROCA con la mole ya sobre las manos: el personaje puede
## andar (más despacio) y apuntar a la vez, y espera al clic izquierdo.
func _empezar_apuntado() -> void:
	_habilidad = Habilidad.CARGAR_ROCA
	_habilidad_largo = 0.0
	_habilidad_timer = 0.0
	_objetivo_tiro_roca = Vector3.ZERO
	_objetivo_roca = _calcular_punto_objetivo()
	# Mientras se apunta, ESC cancela el tiro en vez de liberar el ratón.
	_bloquear_toggle_captura(true)
	_mostrar_indicador()


## CONFIRMA el tiro (clic izquierdo): se congela el punto apuntado y arranca el
## clip de lanzamiento. A partir de aquí el tiro ya no se corrige: la roca sale
## hacia el punto que estaba marcando la retícula en este instante.
func _confirmar_lanzamiento() -> void:
	_objetivo_tiro_roca = _objetivo_roca
	_ocultar_indicador()
	_bloquear_toggle_captura(false)
	_fijar_altura_camara(0.0)
	_habilidad = Habilidad.LANZAR_ROCA
	_habilidad_largo = _clip_length(anim_rock_throw, 0.62)
	_habilidad_timer = _habilidad_largo
	_roca_soltada = false


## CANCELA el apuntado (ESC): la roca se cae al suelo sin más (ni daño ni
## lanzamiento) y desaparece sola a los pocos segundos.
func _cancelar_apuntado() -> void:
	if _tiene_roca():
		_roca.lanzar(Vector3.DOWN * 0.8 + _direccion_modelo() * 0.3, 1.2)
		FuerzaVfx.liberar_mas_tarde(_roca, 3.0)   # no se queda basura por el mapa
	_roca = null
	_sujetando_roca = false
	_roca_soltada = false
	_objetivo_tiro_roca = Vector3.ZERO
	_terminar_apuntado()


## Salida limpia del apuntado (sin lanzar): quita el indicador, devuelve el ESC
## a la cámara y deja la habilidad libre.
func _terminar_apuntado() -> void:
	_ocultar_indicador()
	_bloquear_toggle_captura(false)
	_fijar_altura_camara(0.0)
	_habilidad = Habilidad.NINGUNA
	_habilidad_largo = 0.0
	_habilidad_timer = 0.0


## Altura extra de la cámara del jugador (0 = la normal).
func _fijar_altura_camara(altura: float) -> void:
	if _camera != null and _camera.has_method("set_height_offset"):
		_camera.call("set_height_offset", altura)


func _crear_roca() -> void:
	if is_instance_valid(_roca):
		return
	var r: FuerzaRock = FuerzaRock.new()
	r.name = "Roca"
	r.radius = rock_size
	r.damage = rock_damage
	r.impact_radius = rock_impact_radius
	r.escala_gravedad = rock_gravity_scale
	r.autor = self
	r.sujetar()                    # nace sujeta: sin física hasta que se lance
	_contenedor_efectos().add_child(r)
	_roca = r
	_sujetando_roca = true
	_roca_soltada = false
	_actualizar_roca_sujeta()


func _actualizar_lanzamiento(delta: float) -> void:
	_actualizar_roca_sujeta()
	_habilidad_timer = maxf(_habilidad_timer - delta, 0.0)

	# La roca sale de las manos en el punto exacto del clip.
	if _tiene_roca() and not _roca_soltada:
		var transcurrido: float = _habilidad_largo - _habilidad_timer
		if transcurrido >= _habilidad_largo * clampf(rock_release_point, 0.0, 1.0):
			_soltar_roca()

	if _habilidad_timer <= 0.0:
		if _tiene_roca():
			_soltar_roca()          # red de seguridad: nunca se queda pegada
		_sujetando_roca = false
		_objetivo_tiro_roca = Vector3.ZERO
		_habilidad = Habilidad.NINGUNA
		_bloquear_toggle_captura(false)   # el ESC vuelve a ser cosa del ratón


func _soltar_roca() -> void:
	_sujetando_roca = false
	_roca_soltada = true
	if not is_instance_valid(_roca):
		return
	# Hacia el punto apuntado, con la física de verdad de la roca (velocidad y
	# gravedad que se están dibujando en la trayectoria). Si por lo que sea no
	# hay punto apuntado (Q sin apuntar), tiro de seguridad: recto hacia donde
	# mira el modelo y algo hacia arriba.
	var dir: Vector3 = _direccion_del_tiro(_punto_entre_manos())
	_roca.lanzar(dir, rock_throw_speed)
	_objetivo_tiro_roca = Vector3.ZERO
	FuerzaCombat.sacudir_camara(get_tree(), rock_release_camera_shake)


## Dirección con la que sale la roca desde "desde": al punto apuntado y
## confirmado si lo hay, y si no el tiro de seguridad.
func _direccion_del_tiro(desde: Vector3) -> Vector3:
	if _objetivo_tiro_roca != Vector3.ZERO:
		return _direccion_balistica(desde, _punto_vuelo(_objetivo_tiro_roca),
			rock_throw_speed, _gravedad_roca(), rock_throw_arc)
	return _direccion_tiro_seguridad()


## Tiro de seguridad (sin apuntado): hacia donde mira el modelo, algo arriba.
func _direccion_tiro_seguridad() -> Vector3:
	var angulo: float = deg_to_rad(rock_throw_angle)
	return (_direccion_modelo() * cos(angulo) + Vector3.UP * sin(angulo)).normalized()


## Gravedad efectiva de la roca: la del mundo por su escala (la misma que usa
## el RigidBody3D de la roca, para que la trayectoria dibujada sea la real).
func _gravedad_roca() -> float:
	var g: float = 9.8
	if ProjectSettings.has_setting("physics/3d/default_gravity"):
		g = float(ProjectSettings.get_setting("physics/3d/default_gravity"))
	return maxf(g * rock_gravity_scale, 0.01)


## Punto del mundo al que apunta la cámara: el primer obstáculo que encuentra
## su rayo (el propio jugador y la roca aparte) o, si no topa con nada, un
## punto a rock_throw_range. Es el sitio al que irá la retícula y la roca.
func _calcular_punto_objetivo() -> Vector3:
	var cam: Camera3D = _camara_actual()
	if cam == null:
		# Sin cámara (pruebas sueltas): se apunta hacia donde mira el modelo.
		return global_position + _direccion_modelo() * rock_throw_range \
			+ Vector3.UP * 1.2
	var desde: Vector3 = cam.global_position
	var hacia: Vector3 = -cam.global_transform.basis.z
	var alcance: float = maxf(rock_throw_range, 1.0)
	var mundo: World3D = get_world_3d()
	if mundo == null:
		return desde + hacia * alcance
	var consulta: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		desde, desde + hacia * alcance)
	consulta.exclude = [get_rid()]
	consulta.collision_mask = collision_mask | 1
	var golpe: Dictionary = mundo.direct_space_state.intersect_ray(consulta)
	if golpe.is_empty():
		return desde + hacia * alcance
	return golpe["position"] as Vector3


## Dirección (en horizontal) hacia el punto apuntado: con ella gira el cuerpo.
## Si el objetivo está prácticamente encima, se queda con la mirada del modelo.
func _direccion_apuntado() -> Vector3:
	var d: Vector3 = _objetivo_roca - global_position
	d.y = 0.0
	if d.length_squared() < 0.04:
		return _direccion_modelo()
	return d.normalized()


## La trayectoria que se verá: la curva real de la roca desde las manos hasta
## el punto de la retícula. Se crea el indicador la primera vez y se reutiliza.
func _mostrar_indicador() -> void:
	if _indicador_roca == null or not is_instance_valid(_indicador_roca):
		_indicador_roca = FuerzaRockAim.new()
		_indicador_roca.name = "IndicadorTiro"
		_contenedor_efectos().add_child(_indicador_roca)
	var desde: Vector3 = _punto_entre_manos()
	var punto_vuelo: Vector3 = _punto_vuelo(_objetivo_roca)
	var dir: Vector3 = _direccion_balistica(desde, punto_vuelo, rock_throw_speed,
		_gravedad_roca(), rock_throw_arc)
	_indicador_roca.mostrar(desde, dir * rock_throw_speed, punto_vuelo,
		_gravedad_roca(), _objetivo_roca)


## Punto por el que tiene que pasar el CENTRO de la roca para que su SUPERFICIE
## toque el punto apuntado: se sube el radio. Es imprescindible y no es un
## detalle: la mole mide más de dos metros, así que apuntando a algo bajo (los
## pies de una diana, el suelo) su centro no puede bajar de un metro sin
## chocar antes con el terreno: sin esto el tiro se queda corto siempre.
func _punto_vuelo(punto: Vector3) -> Vector3:
	if punto == Vector3.ZERO:
		return punto
	return punto + Vector3.UP * maxf(rock_size, 0.1)


func _ocultar_indicador() -> void:
	if _indicador_roca != null and is_instance_valid(_indicador_roca):
		_indicador_roca.ocultar()
		_indicador_roca.queue_free()
	_indicador_roca = null


## Resuelve la parábola REAL del tiro: con qué dirección hay que lanzar a
## "velocidad" con gravedad "gravedad" para que pase EXACTAMENTE por
## "objetivo" (la solución tensa, la de vuelo más corto). Si el objetivo está
## fuera de alcance se devuelve el ángulo de máximo alcance: se queda corto,
## que es lo honesto, en vez de disparar a la luna.
static func _direccion_balistica(desde: Vector3, objetivo: Vector3, velocidad: float,
		gravedad: float, arco_grados: float) -> Vector3:
	var delta: Vector3 = objetivo - desde
	var plano: Vector3 = Vector3(delta.x, 0.0, delta.z)
	var x: float = plano.length()
	var y: float = delta.y
	var v: float = maxf(velocidad, 1.0)
	var g: float = maxf(gravedad, 0.01)

	if x < 0.05:
		# Objetivo prácticamente encima: se lanza recto hacia él.
		var recto: Vector3 = delta
		if recto.length_squared() < 0.0001:
			recto = Vector3.FORWARD
		return recto.normalized()

	var disc: float = v * v * v * v - g * (g * x * x + 2.0 * y * v * v)
	var theta: float
	if disc >= 0.0:
		theta = atan2(v * v - sqrt(disc), g * x)
	else:
		theta = atan2(v * v, g * x)
	theta = clampf(theta, deg_to_rad(-70.0), deg_to_rad(70.0))
	theta += deg_to_rad(arco_grados)

	var horizontal: Vector3 = plano.normalized()
	return (horizontal * cos(theta) + Vector3.UP * sin(theta)).normalized()


# --- 4) EMBESTIDA CON EL HOMBRO (R) -------------------------------------------
#  PREPARAR_EMBESTIDA (se clava, carga el hombro) -> EMBESTIDA (carrera de
#  verdad: la velocidad se impone cada fotograma y move_and_slide resuelve los
#  choques) -> RECUPERAR_EMBESTIDA (frena y vuelve a la postura normal).
#
#  Nada de teletransportes: el cuerpo RECORRE la distancia (con tope de tiempo
#  y de metros) y se para contra las paredes como cualquier otro movimiento.
#  La dirección la fija la cámara al salir de la preparación: el jugador apunta
#  la embestida mirando, igual que apunta la roca.
func _empezar_embestida() -> void:
	_habilidad = Habilidad.PREPARAR_EMBESTIDA
	_habilidad_timer = maxf(charge_prep_time, 0.05)
	_habilidad_largo = _clip_length(anim_shoulder_prep, 0.18)
	# La preparación es corta y todavía se puede corregir con la cámara.
	_embestida_dir = _direccion_camara()
	_embestida_restante = 0.0
	_embestida_golpeados.clear()
	_embestida_empuje_timer = 0.0


func _actualizar_preparacion_embestida(delta: float) -> void:
	_habilidad_timer = maxf(_habilidad_timer - delta, 0.0)
	# Mientras carga el hombro, la dirección sigue a la cámara: es el último
	# momento de elegir hacia dónde va.
	_embestida_dir = _direccion_camara()
	if _habilidad_timer > 0.0:
		return

	# ¡Fuera! Se fija la dirección y empieza el dash de verdad.
	_embestida_dir = _direccion_camara()
	_habilidad = Habilidad.EMBESTIDA
	_habilidad_largo = _clip_length(anim_shoulder_run, 0.50)
	_habilidad_timer = 0.0
	_embestida_restante = maxf(charge_distance, 0.1)
	_embestida_golpeados.clear()
	_embestida_empuje_timer = 0.0
	# Sale con polvo y un golpe seco de cámara: se nota el arranque.
	_polvo_bajo_los_pies(1.1)
	FuerzaCombat.sacudir_camara(get_tree(), charge_camera_shake * 0.35)


## Dash: sólo lleva el reloj (la velocidad la pone _update_ability_velocity() y
## la distancia la mide _embestida_avanza() después de moverse).
func _actualizar_embestida(delta: float) -> void:
	_habilidad_timer += delta
	if _habilidad_timer >= maxf(charge_duration, 0.05):
		_terminar_embestida(false)


## Lo que ha avanzado de verdad el cuerpo este fotograma (tras move_and_slide):
## con eso se mide el tope de distancia y se resuelven los choques REALES.
func _embestida_avanza(desplazamiento: Vector3) -> void:
	if _habilidad != Habilidad.EMBESTIDA:
		return
	var avance: Vector3 = Vector3(desplazamiento.x, 0.0, desplazamiento.z)
	_embestida_restante = maxf(_embestida_restante - avance.length(), 0.0)
	_revisar_choques_embestida()
	if _habilidad != Habilidad.EMBESTIDA:
		return                       # un choque ya la ha terminado
	if _embestida_restante <= 0.0:
		_terminar_embestida(false)   # se le acabó la distancia


## Choques del dash: con un oponente (daño + empuje de verdad) o con un muro
## (se para en seco). Se leen de los choques que ya resolvió move_and_slide,
## así que el muro frena al personaje por física: no se atraviesa nada.
func _revisar_choques_embestida() -> void:
	var golpeado_algo: bool = false
	var choco_muro: bool = false
	var punto_muro: Vector3 = Vector3.ZERO

	for i: int in get_slide_collision_count():
		var choque: KinematicCollision3D = get_slide_collision(i)
		if choque == null:
			continue
		var cuerpo: Object = choque.get_collider()
		var normal: Vector3 = choque.get_normal()

		# ¿Oponente? Cualquier cuerpo del grupo "damageable" que no sea yo y al
		# que no le haya dado ya en esta embestida.
		if cuerpo is Node3D and cuerpo != self \
				and (cuerpo as Node3D).is_in_group(FuerzaCombat.GRUPO) \
				and not _embestida_golpeados.has(cuerpo):
			_golpear_con_el_hombro(cuerpo as Node3D, choque.get_position())
			golpeado_algo = true
			continue

		# ¿Muro? Una superficie vertical (el suelo y las rampas no cuentan).
		if normal.dot(Vector3.UP) < 0.6:
			choco_muro = true
			punto_muro = choque.get_position()

	if choco_muro:
		# Hostia contra la pared: se para, con polvo y un golpe de cámara.
		var contenedor: Node = _contenedor_efectos()
		if contenedor is Node3D:
			var donde: Node3D = contenedor
			FuerzaVfx.polvo(donde, punto_muro, 1.0, 16, Color(0.62, 0.55, 0.46), 0.9, 3.0)
			FuerzaVfx.chispas(donde, punto_muro, 0.5, 8, Color(1.0, 0.85, 0.5), 0.3, 5.0)
		FuerzaCombat.sacudir_camara(get_tree(), charge_camera_shake * 0.6)
		_terminar_embestida(false, true)
		return

	if golpeado_algo:
		# El choque corta la carrera: es el momento del impacto.
		_terminar_embestida(true)


## El hombro conecta: daño de verdad y empuje de verdad. El empuje se entrega
## con la misma API que usan los demás ataques [take_damage(cantidad, desde,
## empuje)], así que el oponente se desplaza con SU propio sistema (las dianas
## de prueba se deslizan metros atrás, no es un simple balanceo).
func _golpear_con_el_hombro(cuerpo: Node3D, punto: Vector3) -> void:
	_embestida_golpeados.append(cuerpo)

	# Empuje: hacia donde iba la embestida y algo hacia arriba (que se vea).
	var dir: Vector3 = (_embestida_dir + Vector3.UP * 0.22).normalized()
	var empuje: Vector3 = dir * maxf(knockback_force, 0.0)

	if cuerpo.has_method("take_damage"):
		cuerpo.call("take_damage", charge_damage, global_position, empuje)
	elif cuerpo is RigidBody3D:
		# Cuerpo suelto sin sistema de daño: al menos que salga despedido.
		(cuerpo as RigidBody3D).apply_impulse(empuje * (cuerpo as RigidBody3D).mass,
			punto - (cuerpo as RigidBody3D).global_position)

	# El golpe se ve (polvo, chispas) y se siente (cámara).
	var contenedor: Node = _contenedor_efectos()
	if contenedor is Node3D:
		var donde: Node3D = contenedor
		FuerzaVfx.polvo(donde, punto, 1.2, 20, Color(0.72, 0.66, 0.58), 1.1, 4.0)
		FuerzaVfx.chispas(donde, punto, 0.5, 12, Color(1.0, 0.9, 0.6), 0.35, 6.0)
	FuerzaCombat.sacudir_camara(get_tree(), charge_camera_shake)


## Termina el dash y pasa a la recuperación. Con empuje (ha conectado con
## alguien) el personaje se queda apoyando el empujón un instante más; con un
## choque duro (contra un oponente o contra un muro) se ve primero el gesto del
## frenazo (ShoulderCharge) y después se endereza (ShoulderRecover).
func _terminar_embestida(con_empuje: bool, choque_duro: bool = false) -> void:
	if _habilidad != Habilidad.EMBESTIDA:
		return
	_habilidad = Habilidad.RECUPERAR_EMBESTIDA
	_habilidad_largo = _clip_length(anim_shoulder_recover, 0.45)
	_habilidad_timer = maxf(charge_recovery, 0.05)
	_embestida_empuje_timer = 0.20 if con_empuje else 0.0
	_embestida_impacto_timer = charge_impact_hold if (con_empuje or choque_duro) else 0.0


func _actualizar_recuperacion_embestida(delta: float) -> void:
	_habilidad_timer = maxf(_habilidad_timer - delta, 0.0)
	_embestida_empuje_timer = maxf(_embestida_empuje_timer - delta, 0.0)
	_embestida_impacto_timer = maxf(_embestida_impacto_timer - delta, 0.0)
	if _habilidad_timer <= 0.0:
		_habilidad = Habilidad.NINGUNA
		_embestida_restante = 0.0
		_embestida_golpeados.clear()


## ¿Está en alguna de las tres fases de la embestida? Mientras dure, el bloque
## normal de movimiento no manda (su velocidad la pone _update_ability_velocity)
## y la orientación la fija la dirección de la embestida.
func _embestida_en_marcha() -> bool:
	return _habilidad == Habilidad.PREPARAR_EMBESTIDA \
		or _habilidad == Habilidad.EMBESTIDA \
		or _habilidad == Habilidad.RECUPERAR_EMBESTIDA


## Hacia dónde mira la cámara, en horizontal: es la dirección con la que sale
## la embestida ("apunta con la cámara y embiste"). Sin cámara cae en la
## dirección del modelo, nunca deja de devolver algo.
func _direccion_camara() -> Vector3:
	var cam: Camera3D = _camara_actual()
	if cam != null:
		var d: Vector3 = -cam.global_transform.basis.z
		d.y = 0.0
		if d.length_squared() > 0.0001:
			return d.normalized()
	return _direccion_modelo()


## La roca sujeta sigue a las manos (el clip ya la está "sosteniendo").
func _actualizar_roca_sujeta() -> void:
	if not _sujetando_roca or not is_instance_valid(_roca):
		return
	_roca.global_position = _punto_entre_manos()


## ¿Tiene una roca EN LAS MANOS? (La que ya vuela no cuenta: se puede volver a
## arrancar otra en cuanto el lanzamiento se ha confirmado.)
func _tiene_roca() -> bool:
	return _sujetando_roca and is_instance_valid(_roca)


## La cámara con la que se apunta: la activa del viewport y, si no hay, la del
## jugador. Devuelve null si no existe ninguna (nunca revienta).
func _camara_actual() -> Camera3D:
	var vista: Viewport = get_viewport()
	if vista != null:
		var activa: Camera3D = vista.get_camera_3d()
		if activa != null:
			return activa
	return _camera as Camera3D


## Mientras el jugador apunta, ESC cancela el tiro: la cámara debe dejar de
## usar ESC para liberar el ratón (si no, el apuntado saltaría en dos cosas).
func _bloquear_toggle_captura(bloqueado: bool) -> void:
	if _camera != null and _camera.has_method("set_capture_toggle_blocked"):
		_camera.call("set_capture_toggle_blocked", bloqueado)


## ¿Está cargando la roca? (levantada y lista para tirar: incluye andar con
## ella). Lo pueden consultar HUD, cámara, tutoriales...
func is_aiming_rock() -> bool:
	return _habilidad == Habilidad.CARGAR_ROCA


## ¿Está haciendo la embestida con el hombro? (Preparación, dash o recuperación.)
func is_shoulder_charging() -> bool:
	return _embestida_en_marcha()


## Punto medio entre las dos manos: donde vive la roca. Si el modelo no trae
## esqueleto (o los huesos no se llaman así) devuelve un punto ante el pecho,
## sin errores: la roca sale igual, sólo que un poco menos pegada a las manos.
func _punto_entre_manos() -> Vector3:
	if _esqueleto != null:
		var i_izq: int = _esqueleto.find_bone(hand_bone_left)
		var i_der: int = _esqueleto.find_bone(hand_bone_right)
		if i_izq >= 0 and i_der >= 0:
			var p_izq: Vector3 = _esqueleto.global_transform \
				* _esqueleto.get_bone_global_pose(i_izq).origin
			var p_der: Vector3 = _esqueleto.global_transform \
				* _esqueleto.get_bone_global_pose(i_der).origin
			# OJO: sólo la ROTACIÓN del modelo. Su base trae la escala (1.98), y
			# multiplicar el desfase por ella lo mandaría a medio metro de sitio.
			var giro: Basis = _visual.global_transform.basis.orthonormalized()
			var manos: Vector3 = (p_izq + p_der) * 0.5
			var punto: Vector3 = manos + giro * rock_hold_offset + _apoyo_de_la_roca(manos)
			# Con el IK de los brazos encendido la roca va anclada AL CUERPO (a
			# los hombros), no al punto medio de las manos: si no, el problema se
			# mordería la cola (las manos van a los agarres de la roca y la roca
			# va al punto medio de las manos -> se perseguirían). La mezcla usa el
			# mismo peso que el IK, así que entra y sale sin ningún salto (con
			# peso 0 esto es EXACTAMENTE lo mismo de siempre).
			if _ik_roca != null:
				var peso: float = _ik_roca.peso_actual
				if peso > 0.001:
					punto = punto.lerp(_esqueleto.global_transform * _ik_roca.centro, peso)
			return punto
	var suelo: Vector3 = global_position + _direccion_modelo() * 0.7
	return suelo + Vector3.UP * (1.0 + _apoyo_de_la_roca(suelo).length())


## Dónde va el CENTRO de la roca respecto al punto medio de las manos. Mientras
## la lleva, el módulo es SIEMPRE 1,03 radios (rock_carry_lift): las muñecas
## quedan 2 cm por fuera de la piedra, así que la roca ni le atraviesa las manos
## ni el cuerpo. Lo que cambia es la DIRECCIÓN:
##
##   · Levantando (Q): la mole es más alta que sus brazos, así que espera
##     apoyada en el suelo delante de él y el personaje le pone las DOS PALMAS
##     en la cara de delante (dirección "hacia la mole del suelo"); según la va
##     empujando hacia arriba esa dirección gira hasta quedar recta hacia
##     arriba, y la mole acaba ENCIMA de las manos, por encima de la cabeza.
##   · Cargando y lanzando: recta hacia arriba, apoyada sobre las dos manos.
##   · El resto del tiempo (nacer, caer, rodar): pegada a las manos, sin apoyo.
func _apoyo_de_la_roca(manos: Vector3) -> Vector3:
	var alto: float = rock_size * rock_carry_lift
	if _habilidad == Habilidad.ARRANCAR_ROCA:
		var u: float = 0.0
		if _habilidad_largo > 0.0:
			u = clampf(1.0 - _habilidad_timer / _habilidad_largo, 0.0, 1.0)
		var pin: Vector3 = global_position \
			+ _direccion_modelo() * rock_lift_floor_distance + Vector3.UP * rock_size
		var hacia: Vector3 = pin - manos
		if hacia.length_squared() < 0.0001:
			hacia = Vector3.UP
		# Al principio la mole está CLAVADA en el suelo (el desfase apunta al
		# sitio donde espera) y el personaje se le acerca; cuando las manos ya
		# están en su cara, la mole pasa a ir pegada a ellas y a girar hacia
		# arriba. Así no hay ningún salto: los dos tramos se interpolan.
		var pegado: Vector3 = hacia.normalized().slerp(Vector3.UP,
			smoothstep(rock_lift_push_until, rock_lift_overhead_at, u)) * alto
		return hacia.lerp(pegado, smoothstep(rock_lift_settle_from, rock_lift_push_until, u))
	if _habilidad == Habilidad.CARGAR_ROCA or _habilidad == Habilidad.LANZAR_ROCA:
		return Vector3.UP * alto
	return Vector3.ZERO


## Mantiene al día el IK de los brazos de la roca (BrazosIKRoca, hijo del
## esqueleto): le dice CUÁNTO tiene que pesar y DÓNDE van los dos agarres.
##
##   · Levantando (Q): el IK entra en el último tramo del clip (rock_ik_from ->
##     1). Para entonces el clip ya tiene las manos en la piedra, así que lo
##     único que hace el IK es ENDEREZAR la muñeca, sin mover la roca.
##   · CARGAR_ROCA: peso 1 en todo momento, andando incluido (el clip lleva los
##     pies y el resto del cuerpo; el IK sólo manda en los brazos).
##   · Lanzar o cancelar: peso 0 -> el IK suelta y vuelve a mandar el clip de
##     lanzamiento (la rampa de salida acaba antes del instante de suelta).
##
## El centro de la roca se calcula desde los HOMBROS (hueso del brazo izquierdo
## + derecho) y no desde las manos: con el IK encendido las manos van clavadas a
## la roca, así que la roca no puede depender de ellas (ver _punto_entre_manos).
func _actualizar_ik_roca() -> void:
	if _ik_roca == null or _esqueleto == null:
		return
	var objetivo: float = 0.0
	if _habilidad == Habilidad.ARRANCAR_ROCA and _habilidad_largo > 0.0:
		var u: float = clampf(1.0 - _habilidad_timer / _habilidad_largo, 0.0, 1.0)
		objetivo = smoothstep(rock_ik_from, 1.0, u)
	elif _habilidad == Habilidad.CARGAR_ROCA:
		objetivo = 1.0
	_ik_roca.peso_objetivo = objetivo
	if objetivo <= 0.0 and _ik_roca.peso_actual <= 0.001:
		return
	var i_izq: int = _esqueleto.find_bone(arm_bone_left)
	var i_der: int = _esqueleto.find_bone(arm_bone_right)
	if i_izq < 0 or i_der < 0:
		return
	var centro: Vector3 = (_esqueleto.get_bone_global_pose(i_izq).origin \
		+ _esqueleto.get_bone_global_pose(i_der).origin) * 0.5 + rock_ik_center_offset
	_ik_roca.centro = centro
	_ik_roca.fijar_agarres(centro + rock_ik_grip_left, centro + rock_ik_grip_right)


## Posición en el mundo del puño DERECHO, que es el que clava el golpe aéreo.
## Si el modelo no trae esqueleto (o el hueso no se llama así) devuelve cero:
## quien lo use se queda con su propia posición y no pasa nada, sólo es un poco
## menos preciso. Nunca lanza errores.
func _punto_del_puno() -> Vector3:
	if _esqueleto == null:
		return Vector3.ZERO
	var i: int = _esqueleto.find_bone(hand_bone_right)
	if i < 0:
		return Vector3.ZERO
	return _esqueleto.global_transform * _esqueleto.get_bone_global_pose(i).origin


# --- Ayudas comunes ----------------------------------------------------------
## Primer Skeleton3D que aparezca dentro del modelo (o null si no hay).
func _buscar_esqueleto(raiz: Node) -> Skeleton3D:
	if raiz == null:
		return null
	for hijo: Node in raiz.get_children():
		if hijo is Skeleton3D:
			return hijo
		var encontrado: Skeleton3D = _buscar_esqueleto(hijo)
		if encontrado != null:
			return encontrado
	return null


## Dónde se cuelgan la roca y las ondas: en el escenario, NO dentro del jugador
## (si no, la roca viajaría pegada al personaje y la onda se movería con él).
func _contenedor_efectos() -> Node:
	var padre: Node = get_parent()
	if padre != null:
		return padre
	if get_tree() != null and get_tree().current_scene != null:
		return get_tree().current_scene
	return self


## Hacia dónde "mira" el personaje. Lo marca el MODELO, no el cuerpo: el
## CharacterBody3D nunca gira, sólo gira el nodo visual.
func _direccion_modelo() -> Vector3:
	var base: Basis = global_transform.basis
	if _visual != null:
		base = _visual.global_transform.basis
	var delante: Vector3 = -base.z
	delante.y = 0.0
	if delante.length_squared() < 0.0001:
		return Vector3.FORWARD
	return delante.normalized()


## Altura sobre el suelo que hay justo debajo (para el pisotón).
func _altura_sobre_suelo() -> float:
	var mundo: World3D = get_world_3d()
	if mundo == null:
		return 0.0
	var espacio: PhysicsDirectSpaceState3D = mundo.direct_space_state
	if espacio == null:
		return 0.0
	var consulta: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		global_position + Vector3.UP * 0.2, global_position + Vector3.DOWN * 300.0)
	consulta.exclude = [get_rid()]
	consulta.collision_mask = collision_mask
	var golpe: Dictionary = espacio.intersect_ray(consulta)
	if golpe.is_empty():
		return 999.0            # sin suelo debajo: que lo use si quiere
	return maxf(global_position.y - (golpe["position"] as Vector3).y, 0.0)


## Polvo y piedras al arrancar o al aterrizar de un golpe.
func _polvo_bajo_los_pies(radio: float) -> void:
	var contenedor: Node = _contenedor_efectos()
	if not (contenedor is Node3D):
		return
	var donde: Node3D = contenedor
	FuerzaVfx.polvo(donde, global_position, radio, 22, Color(0.62, 0.55, 0.46), 1.1, 3.0)
	FuerzaVfx.escombros(donde, global_position, radio * 0.7, 14, Color(0.34, 0.30, 0.26), 1.4, 5.0)


## Temblor del modelo mientras carga el super salto.
func _aplicar_temblor() -> void:
	if _visual == null or _visual == self:
		return
	if _temblor <= 0.0001:
		if _visual.position != _visual_pos_base:
			_visual.position = _visual_pos_base
		return
	var t: float = Time.get_ticks_msec() * 0.055
	_visual.position = _visual_pos_base + Vector3(
		sin(t * 1.7), sin(t * 2.9) * 0.6, sin(t * 2.3)) * _temblor


## Daño real de un puñetazo o una patada, en el instante justo del impacto.
func _aplicar_golpe_cuerpo_a_cuerpo() -> void:
	var mundo: World3D = get_world_3d()
	if mundo == null:
		return
	var es_patada: bool = _current_attack == anim_kick
	var dano: float = kick_damage if es_patada else punch_damage
	if dano <= 0.0:
		return
	var alcance: float = kick_reach if es_patada else punch_reach
	var radio: float = kick_hit_radius if es_patada else punch_hit_radius
	var altura: float = kick_hit_height if es_patada else punch_hit_height
	var centro: Vector3 = global_position + Vector3.UP * altura + _direccion_modelo() * alcance
	FuerzaCombat.golpear_esfera(mundo.direct_space_state, centro, radio, dano,
		melee_knockback, [get_rid()], 0.75, 0.25)


# =============================================================================
#  API PÚBLICA — para enganchar otros sistemas (HUD, IA, sonido...)
# =============================================================================

## Velocidad actual sobre el plano horizontal (sin contar la caída).
func get_planar_speed() -> float:
	return Vector2(velocity.x, velocity.z).length()


## ¿Está corriendo ahora mismo?
func is_sprinting() -> bool:
	return _is_sprinting


## ¿Está atacando ahora mismo?
func is_attacking() -> bool:
	return _attack_timer > 0.0


## ¿Está agachado ahora mismo?
func is_crouching() -> bool:
	return _is_crouching


## Nombre de la animación del ataque en curso (&"" si no está atacando).
func get_current_attack() -> StringName:
	return _current_attack


## Habilidad especial en curso (Player.Habilidad.NINGUNA si no hay ninguna).
func get_ability() -> Habilidad:
	return _habilidad


## ¿Está usando una habilidad especial ahora mismo?
func is_using_ability() -> bool:
	return _habilidad != Habilidad.NINGUNA


## Carga del super salto: 0 = acaba de empezar, 1 = al máximo.
func get_charge_ratio() -> float:
	if _habilidad != Habilidad.CARGANDO_SALTO:
		return 0.0
	return clampf(inverse_lerp(super_jump_min_charge, super_jump_max_charge, _carga), 0.0, 1.0)


## La roca que tiene sujeta o en el aire (null si no hay ninguna).
func get_rock() -> FuerzaRock:
	return _roca


## Animaciones que el sistema espera pero que el modelo todavía no trae.
## Sirve para saber exactamente qué clips hay que importar o crear.
func get_missing_animations() -> Array[StringName]:
	var missing: Array[StringName] = []
	for state_name: StringName in _all_animation_states():
		if _anim_player == null or not _anim_player.has_animation(state_name):
			missing.append(state_name)
	return missing
