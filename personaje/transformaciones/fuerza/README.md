# Paquete portátil del personaje «Fuerza»
	
	Copia **autocontenida y verificada** del personaje jugable de Prismax: modelo,
	esqueleto, sistema de animación completo, efectos, IK y habilidades. Se puede
	copiar tal cual a otro proyecto Godot **sin traer nada más** de Prismax.
	
	> **Probado en un proyecto Godot vacío**: el personaje carga, el AnimationTree
	> se activa, reproduce Idle y los 23 clips se mueven de verdad (sin T-pose),
	> la roca se levanta/lanza con el IK activo y el pisotón crea su onda.
	
	## 1. Qué contiene
	
	```
	character_package/Fuerza/
	├── README.md                        (este archivo)
	├── scenes/
	│   ├── Fuerza.tscn                  ← LA escena del personaje
	│   └── Demo_Fuerza.tscn             ← pista de pruebas: suelo + luz + Fuerza
	├── model/
	│   ├── tripo_convert_….fbx          (modelo con esqueleto de 65 huesos)
	│   ├── tripo_convert_…_0…4.png      (texturas del modelo)
	│   └── tripo_convert_….fbm/         (mapas basecolor, metallic, normal, rm, roughness)
	├── animations/
	│   └── libraries/FuerzaUniversal.tres   (biblioteca con los 23 clips)
	├── scripts/
	│   ├── Player.gd                    (controlador: movimiento y habilidades)
	│   ├── PlayerCamera.gd              (cámara en tercera persona)
	│   ├── Combat.gd                    (API de daño; grupo «damageable»)
	│   ├── BrazosIKRoca.gd              (IK de los brazos al sostener la roca)
	│   ├── Rock.gd                      (la roca física de la habilidad Q)
	│   └── RockAimIndicator.gd          (retícula y trayectoria de apuntado)
	├── effects/
	│   ├── Shockwave.gd                 (onda del pisotón)
	│   └── Vfx.gd                       (polvo, escombros y chispas)
	├── materials/shockwave.gdshader
	└── textures/rock_stone.png
	```
	
	Además, junto a cada script y al shader hay un archivo `.uid`: es la identidad
	interna que les asigna Godot 4.4+; van incluidos para que las referencias
	queden estables en cualquier proyecto.
	
	## 2. Escena principal y cómo instanciarla
	
	- **Escena:** `scenes/Fuerza.tscn` (CharacterBody3D; nodo raíz «Fuerza»).
	- Instanciala dentro de tu nivel (el personaje necesita suelo con colisión).
	- Trae TODO incorporado: collider de cápsula, modelo + esqueleto, AnimationPlayer,
	  AnimationTree con su StateMachine, el IK de brazos y la cámara en tercera
	  persona (captura el ratón al arrancar; ESC lo libera).
	- Ajustá su `transform` para colocarlo donde quieras; no hace falta tocar nada más.
	
	## 3. ANIMACIONES INCLUIDAS
	
	23 clips, todos dentro de `animations/libraries/FuerzaUniversal.tres`:
	
	| Clip | Duración (s) | Uso |
	|---|---|---|
	| Idle | 2.50 | resposo (bucle) |
	| Walk | 1.43 | caminar (bucle) |
	| Run | 0.78 | correr (bucle) |
	| Jump | 0.50 | subir del salto |
	| Fall | 1.00 | caída (bucle) |
	| Land | 1.27 | aterrizaje |
	| Crouch | 2.93 | agachado |
	| CrouchWalk | 1.67 | agachado andando (bucle) |
	| Punch_Left | 0.87 | jab del combo (1.º golpe) |
	| Punch_Right | 1.00 | cross del combo (2.º golpe) |
	| Kick | 1.60 | patada (clic derecho) |
	| Charge | 3.45 | flexión de carga del super salto |
	| SuperJump | 0.62 | impulso del super salto |
	| AirSlam | 0.46 | caída en picado (E en el aire) |
	| SlamImpact | 0.60 | golpe contra el suelo |
	| RockLift | 1.26 | arrancar la roca del suelo (Q) |
	| RockCarry | 0.90 | sostener la roca (bucle) |
	| RockCarryWalk | 0.60 | andar con la roca (bucle) |
	| RockThrow | 0.62 | lanzamiento a dos manos |
	| ShoulderPrep | 0.18 | preparación de la embestida (R) |
	| ShoulderRun | 0.50 | carrera de la embestida (bucle) |
	| ShoulderCharge | 0.30 | frenazo al empotrarse |
	| ShoulderRecover | 0.45 | recuperación tras la embestida |
	
	Origen: los clips de locomoción/combate vienen de la Universal Animation
	Library (retargeteada al esqueleto del personaje) y de Mixamo («Mma Kick» para
	la patada, «Mutant Walking» para el andar); los clips de habilidades se
	construyeron a medida. **Todo está ya cocido dentro de la biblioteca**: no se
	necesita ningún FBX externo, ni herramientas de retargeteo, ni el proyecto
	original.
	
	## 4. Dónde vive cada pieza del sistema de animación
	
	- **AnimationPlayer** — nodo «AnimationPlayer» de `Fuerza.tscn`; tiene cargada
	  la biblioteca «FuerzaUniversal» (los 23 clips). Su `root_node` es la raíz del
	  personaje, y las pistas apuntan a `Model/CharacterModel/FuerzaModel/Skeleton3D`.
	- **AnimationTree + StateMachine** — nodo «AnimationTree» de `Fuerza.tscn`;
	  su `tree_root` es una StateMachine con Idle/Walk/Run/Jump/Fall/Land/Crouch/
	  CrouchWalk/Punch_Left/Punch_Right/Kick/Charge/SuperJump/AirSlam/SlamImpact/
	  RockLift/RockThrow, y transiciones con fundidos. El script añade al arrancar
	  los estados restantes (RockCarry, RockCarryWalk y los cuatro de la embestida)
	  en cuanto el clip existe.
	- **El script activa el AnimationTree** sólo tras comprobar que existen los
	  cinco clips obligatorios (Idle/Walk/Run/Jump/Fall); con ellos presentes el
	  personaje siempre queda animado.
	- **IK de brazos** — `BrazosIKRoca` (SkeletonModifier3D) cuelga del Skeleton3D
	  con sus objetivos `LeftHandTarget`/`RightHandTarget`; el agarre de la roca
	  funciona sin configurar nada.
	
	## 5. Habilidades y controles
	
	| Control | Acción |
	|---|---|
	| WASD | mover | 
	| Shift | correr |
	| Espacio (mantener) | super salto (carga al soltar) |
	| E en el aire | pisotón con onda expansiva |
	| Clic izquierdo | jab / combo |
	| Clic derecho | patada |
	| Ctrl | agacharse |
	| Q | arrancar roca → apuntar → clic para lanzar (ESC cancela) |
	| R | embestida con el hombro |
	| ESC | liberar/capturar el ratón |
	
	## 6. Dependencias
	
	- **Archivos: NINGUNA.** Todo lo que el personaje necesita está dentro de esta
	  carpeta (comprobado con las dependencias REALES de cada recurso).
	- **Mapa de entradas:** hay que crear estas 12 acciones en el proyecto destino
	  (Proyecto → Mapa de entradas): `move_forward` (W), `move_backward` (S),
	  `move_left` (A), `move_right` (D), `sprint` (Shift), `jump` (Espacio),
	  `attack_punch` (clic izq.), `attack_kick` (clic der.), `crouch` (Ctrl),
	  `air_slam` (E), `rock_throw` (Q), `shoulder_charge` (R). `ui_cancel` (ESC) ya
	  existe por defecto. Sin ellas el personaje carga y se anima igual, pero los
	  controles que falten no responderán.
	- **Versión de Godot:** 4.7 (probado en 4.7.2). El IK usa `SkeletonModifier3D`
	  (Godot 4.3+); en versiones anteriores ese nodo no puede cargarse.
	
	## 7. Cómo integrarlo en otro proyecto
	
	1. Copiá la carpeta `Fuerza/` completa dentro de `res://` del proyecto destino
	   (por ejemplo como `res://character_package/Fuerza/`, que es la ruta que
	   esperan las referencias internas).
	2. Abrí el proyecto y **esperá a que Godot termine de importar** (indicador de
	   progreso abajo a la derecha). Es la importación del modelo y sus texturas.
	3. Creá las 12 acciones del mapa de entradas de la sección 6.
	4. Instanciá `Fuerza/scenes/Fuerza.tscn` dentro de tu nivel… o abrí primero
	   `Fuerza/scenes/Demo_Fuerza.tscn` y ejecutala (F6) para verlo funcionando.
	
	> Importante: si copiás la carpeta con el proyecto YA ABIERTO, esperá unos
	> segundos a que Godot escanee los archivos nuevos antes de ejecutar el juego.
	
	## 8. Verificación rápida (que NO quede en T-pose)
	
	1. Abrí y ejecutá `scenes/Demo_Fuerza.tscn` (F6).
	2. El personaje debe estar **respirando (Idle)** desde el primer segundo.
	3. Movete con WASD: Walk; con Shift: Run; saltá con Espacio; golpeá con clic.
	4. Apretá Q: arranca la roca y la sostiene sobre la cabeza con las dos manos.
	
	**Ojo:** si abrís `Fuerza.tscn` dentro del EDITOR sin ejecutar, vas a ver la
	pose de reposo (los brazos en cruz). Eso es normal: el editor de Godot no
	reproduce animaciones. La animación se ve al EJECUTAR la escena.
	
	## 9. Notas
	
	- Los scripts usan class_name prefijados con `Fuerza` (FuerzaPlayer,
	  FuerzaCamera, FuerzaCombat, FuerzaRock, FuerzaRockAim, FuerzaShockwave,
	  FuerzaVfx, FuerzaBrazosIK) para no chocar con ninguna clase del proyecto
	  destino.
	- El personaje no depende de autoloads, ni de escenas ajenas, ni del motor de
	  física (funciona con Jolt o con el motor por defecto).
	- Los clips «Roll», «Hit_Chest», «Walk_Old» y «Kick_Old» del proyecto original
	  NO se incluyen: el sistema del personaje no los referencia (comprobado).
	
	## 10. Licencias
	
	Los clips de locomoción/combate provienen de Universal Animation Library y de
	Mixamo; consultá `License.txt` del proyecto Prismax original para sus licencias.
	