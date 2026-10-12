# Sistema de NPCs ciudadanos — Etapas 1-4, pulido, reconstrucción visual y variedad

Ciudadanos autónomos (de los modelos PSX o de los packs nuevos) para un juego 3D optimizado (estilo
PS2/PS3). Cada ciudadano recorre el terreno con una máquina de estados (quieto → decidir → caminar →
parada o giro a mitad de camino → llegada), elige destinos **alcanzables** sobre la malla de
navegación, se esquiva con los demás y varía su aspecto, su velocidad y sus clips para no parecer un
clon. Los que están lejos entran en niveles de actividad (LOD: completo / simplificado / congelado)
para que la escena aguante cientos de NPCs. La animación está sincronizada con la velocidad real de
avance, así que los pies no patinan.

Además, **los ciudadanos se fijan en el jugador**: cuando lo ven acercarse le giran la cabeza poco a
poco y sólo hasta un límite natural, y algunos se paran a mirarlo, se giran de cuerpo entero, le
dedican un gesto o siguen caminando de reojo. Cada uno reacciona cuando le toca, no todos a la vez.

Su aspecto se sortea por partes (cuerpo, color de cada prenda y tono de piel, todo por separado), así
que no hay dos iguales: las prendas se recolorean en tiempo de ejecución porque los paquetes sólo
traen una versión de color de cada una. Detalles en *Variedad*.

El **jugador de prueba** (`Player_Test.tscn`) usa una cámara de tercera persona de verdad
(rig `PLAYER → CAMERA RIG → CAMERA`, con seguimiento suavizado y recentrado) y movimiento con rampa
de aceleración y frenada; el personaje real del juego (`node_3d.tscn`) no se ha tocado. Todavía no
hay diálogos, selfies, combate ni misiones: el código deja ganchos para añadirlos.

**Etapa 4 — aspecto y comportamiento nuevos.** Los ciudadanos pueden usar ahora los modelos
realistas de los packs *City Folks* y *Urban Man* (humanos vestidos de verdad, en lugar de los PSX de
baja resolución), con su propia locomoción natural y clips de carrera y giro traídos de
*RPG Animations GLB FREE*, más un armazón de decisiones opcional con **GdPlanningAI** (objetivos y
acciones; **sin ningún modelo de lenguaje**). Los packs PSX, las animaciones anteriores, el
generador, la navegación y la evitación siguen funcionando igual: el aspecto nuevo es una proporción
que se ajusta en el generador (`poly_share`), no un reemplazo del sistema.

**Pulido visual y de movimiento.** Después de comparar los modelos uno al lado del otro con la misma
luz, los que se usan por defecto son otra vez los PSX (`poly_share` a 0,0: son los únicos con cara
pintada de verdad y cuestan una décima parte) y lo que se ha mejorado es el acabado de todos los
personajes —aspereza y perfilado de los materiales, más una segunda luz de relleno en la escena— y el
movimiento del jugador, que ahora anda a la velocidad del clip, frena con rampa, gira con inercia y
usa el clip de giro al darse la vuelta. Detalles en *Pulido visual y de movimiento*.

**Estado actual del sistema que se ejecuta (F5).** La **escena principal** del proyecto es
`res://NPCs/Scenes/NPC_TestScene.tscn`, y sus ciudadanos son **todos** de los packs nuevos (City
Folks / Urban Man): el generador de esa escena lleva fijados a mano los tres modelos nuevos en
`citizen_models`, de modo que el sorteo **no puede** elegir un PSX. Los modelos PSX siguen en el
proyecto (los usa el jugador de prueba temporal y siguen disponibles), pero ya no aparecen como
ciudadanos al ejecutar el juego.

## Reconstrucción visual: los ciudadanos nuevos (`NPC_Visual_Test.tscn`)

Los ciudadanos de las etapas anteriores eran los modelos PSX (estilo PS1/PS2). En esta
reconstrucción se **dejan de usar** para los ciudadanos: todos los de la escena nueva se montan con
los packs *City Folks* y *Urban Man*, que son humanos 3D completos y vestidos.

Antes de elegir se pusieron **todos** los humanoides del proyecto en fila, con la misma luz y la
misma cámara, y después se miraron de cerca uno por uno. Eso resolvió de dónde salían esos
"humanoides limpios" que aparecían en las pruebas anteriores:

| Asset | Qué es exactamente | Veredicto |
|---|---|---|
| `Animations/UAL1/UAL1_Standard.glb` | **maniquí amarillo** con anillos de articulación: malla propia de 8.546 vértices con rig de 65 huesos **y 43 clips dentro del mismo archivo** (`Walk_Loop`, `Jog_Fwd_Loop`, `Sprint_Loop`, `Idle_Loop`…) | no sirve como ciudadano: ni cara ni ropa |
| `Animations/UAL2/UAL2_Standard.glb` | el mismo maniquí, con otros 43 clips (combate, cuchillo, zombi…) | igual |
| `Characters/HumanBasic/HumanM_Model.fbx` / `HumanF_Model.fbx` | **maniquíes blancos desnudos**, musculados, sin cara (8.338 / 7.914 vértices, 55 huesos) | igual: son figuras de referencia |
| **City Folks + Urban Man (PolyMate)** | humanos 3D vestidos (sudadera, chándal, tirantes, vaqueros, zapatillas), **con cara modelada y texturizada**, 59 huesos y piezas modulares | ✅ **los que se usan** |
| `Characters/PSX/` | textura pintada muy rica, pero estilo PS1/PS2 | fuera de esta escena |
| City Folks → *Dough Sensei* | su "cabeza" es una **caja con un logotipo pintado** | descartado |

Es decir: los humanoides de los assets *Universal* **sí existen y sí son 3D** (cuerpo, esqueleto y
animaciones propias), pero son maniquíes — no tienen cara ni ropa. Los que se ven como personas de
verdad son los de *City Folks* / *Urban Man*, así que son los que monta la escena nueva.

`NPC_Visual_Test.tscn` es una escena **independiente** (no modifica la anterior): suelo de hormigón
de 80×80 con unos bloques para tener referencia de tamaño, el mismo cielo y las mismas dos luces
(sol + relleno frío), su región de navegación, **8 ciudadanos** y un jugador de prueba propio
(`Player_Visual_Test.tscn`, con el rig nuevo). **No hay ni un modelo PSX dentro.**

### Comprobaciones hechas sobre la escena nueva (medidas, no de ojo)

- [x] Ningún ciudadano es de los modelos PS2/PSX: de 8 ciudadanos, **0** con modelo PSX (se leyó la
      ruta del modelo y las mallas de cada uno).
- [x] Son modelos 3D completos: 5 mallas por ciudadano (cabeza, torso, manos, piernas y pies) y entre
      6.800 y 10.900 vértices, cada una con su textura de 1024.
- [x] Tienen esqueleto: 59 huesos, el primero `root.x` (rig Auto-Rig Pro).
- [x] Las animaciones funcionan: cada ciudadano elige sus propios clips (`walk_m1`, `walk_f1`,
      `walk_u1`, `jog_u1`…) y anda exactamente a la velocidad que trae el clip.
- [x] La caminata es natural y **los brazos NO van hacia adelante**: medido hueso a hueso dentro del
      juego, las manos oscilan ±0,35 m alrededor del hombro con una **media de −0,007 m** (el fallo de
      "va llevando algo en las manos" daría una media muy positiva y un recorrido corto).
- [x] El idle funciona: las dos posturas de espera se alternan solas y nadie se queda congelado.
- [x] No hay zombis ni modelos muertos ni monstruosos: los clips de zombi de UAL2 no se usan y la
      cabeza-caja de Dough Sensei está fuera del sorteo de piezas.
- [x] La escena nueva funciona sola: ejecutarla no depende en nada de la escena anterior.

## Assets utilizados (extraídos desde `Assets NPCS/*.zip`)

| Pack | Contenido | Destino en el proyecto |
|---|---|---|
| Characters_psx_1.1 | 50 ciudadanos rigueados (29 M + 21 F, incl. policía y sheriff) + 49 texturas | `NPCs/Characters/PSX/` |
| Human Basic Motions FREE | 12 clips de locomoción humana (idle, walk, run y giros, M y F) | `NPCs/Animations/HumanBasic/` |
| Universal Animation Library 1 | Librería GLB (rig UE) | `NPCs/Animations/UAL1/` |
| Universal Animation Library 2 | Librería GLB (rig UE) | `NPCs/Animations/UAL2/` |
| City Folks (PolyMate) | Deportista, Dough Sensei y Muscle Man: humanos vestidos y rigueados (Auto-Rig Pro, 59 huesos) con piezas modulares (cabezas, torsos, manos, piernas y pies sueltos) | `Assets NPCS/CityFolks_PolyMate_alstrainfinite/` |
| Urban Man (PolyMate) | Ciudadano urbano con ropa informal (mismo rig Auto-Rig Pro) | `Assets NPCS/UrbanMan_PolyMate_alstrainfinite/` |
| RPG Animations GLB FREE | 64 clips sobre un rig *Biped* de 53 huesos (andar, correr, girar, agacharse…) | `Assets NPCS/RPG_Animations_GLB_FREE/` |
| GdPlanningAI 0.2.0 | Complemento de planificación por objetivos (GOAP) para Godot 4 | `addons/GdPlanningAI/` |

Los packs de animación anteriores (Human Basic, UAL1, UAL2) usan rigs distintos al de los modelos
PSX. El horneador (`NPCs/Scripts/Tools/npc_animation_baker.gd`) los retargetea al rig Mixamo de los
modelos PSX copiando **dirección + torsión relativa** de cada hueso, y guarda la velocidad real de
cada clip.

Los packs *City Folks* y *Urban Man* no usan el rig Mixamo, sino **Auto-Rig Pro** (59 huesos:
`root.x`, `spine_01.x`, `arm_stretch.l`…), así que hay una **segunda librería horneada**
(`Citizen_Animations_ARP.res`) con clips de esos modelos y del rig Biped del pack RPG. Cada
ciudadano elige la librería que corresponde a su esqueleto; la máquina de estados es la misma para
los dos rigs.

## Estructura

```
NPCs/
├── Characters/
│   ├── PSX/                   Modelos de ciudadano (50)
│   │   ├── Male/              29 masculinos (incl. policía y sheriff)
│   │   ├── Female/            21 femeninos
│   │   └── textures/          Una textura .png por modelo
│   └── HumanBasic/            Maniquíes del pack Human Basic (alternativa sin usar)
├── Animations/
│   ├── HumanBasic/            Clips originales (idle / walk / run / giro, M y F)
│   ├── UAL1/, UAL2/           Librerías originales (.glb)
│   ├── Citizen_Animations.res Librería COMPARTIDA con 27 clips horneados (rig Mixamo)
│   ├── Citizen_Animations_ARP.res Librería del rig nuevo con 29 clips (Auto-Rig Pro + RPG)
│   └── Citizen_Locomotion.tres Máquina de estados del AnimationTree (12 estados)
├── Scenes/
│   ├── NPC_Citizen.tscn       Ciudadano (CharacterBody3D + animación + navegación)
│   ├── NPC_TestScene.tscn     Escena de prueba de las etapas 1-4 (25 ciudadanos)
│   ├── Player_Test.tscn       Jugador TEMPORAL de esa escena (no es el del juego)
│   ├── NPC_Visual_Test.tscn   ESCENA VISUAL NUEVA: 8 ciudadanos de los packs nuevos
│   └── Player_Visual_Test.tscn  Jugador de prueba de la escena visual (rig nuevo)
├── Scripts/
│   ├── npc_citizen.gd         NPCCitizen: máquina de estados, locomoción, reacciones y LOD
│   ├── npc_citizen_model.gd   NPCCitizenModel: monta un ciudadano con los modelos nuevos (rig ARP)
│   ├── npc_goap_brain.gd       NPCGoapBrain: objetivos y acciones con GdPlanningAI (opcional)
│   ├── npc_look_at.gd         NPCLookAt: gira la cabeza hacia el jugador (límites y fundido)
│   ├── npc_spawner.gd         NPCSpawner: genera N ciudadanos y reparte los niveles de actividad
│   ├── test_player.gd         Control del jugador de prueba (etapas 1-4)
│   ├── visual_player.gd       Control del jugador de la escena visual (rig nuevo)
│   └── Tools/npc_animation_baker.gd  Horneador de animaciones (NPCAnimationBaker)
├── Shaders/npc_outfit.gdshader       Recoloreado de ropa (variantes de color de las prendas)
└── Navigation/NPC_TestGround.tres    NavigationMesh del terreno de prueba (±34 m)
```

## Cómo probarlo

- **`NPC_TestScene.tscn`** — **es la escena principal del proyecto (la que se ejecuta con F5)** y la
  que hay que mirar: 25 ciudadanos, **todos de los packs nuevos**, con las reacciones, el LOD y el
  planificador de siempre. El único modelo PSX que se ve en ella es el jugador de prueba temporal.
- **`NPC_Visual_Test.tscn`** — escena aparte y más pequeña (8 ciudadanos, 80×80 m) hecha para
  comparar modelos de cerca con otra luz. No es la del juego; se puede borrar cuando no haga falta.

### Escena principal (`NPC_TestScene.tscn`)

1. Ábrela y ejecútala (F5 o F6).
2. **WASD** mover (relativo a la cámara) · **Shift** correr · **Espacio** saltar · **clic** capturar
   el ratón · **ESC** liberarlo.
   El ratón sólo gira/orienta la cámara; el personaje se gira hacia donde avanza.
3. Verás 25 ciudadanos distintos deambulando: se quedan quietos, eligen un destino al azar a entre
   6 y 22 m, caminan hacia él (a veces trotando), a veces se paran o dan media vuelta a mitad de
   camino y al llegar vuelven a decidir. El HUD del jugador de prueba muestra velocidad y FPS. *(Los
   ciudadanos son los modelos nuevos; una tercera parte lleva planificador propio: se les nota en que
   a veces se paran a descansar y en que algún curioso se acerca a mirarte.)*
4. **Acércate a un ciudadano** (a menos de 9 m): se dará cuenta y girará la cabeza hacia ti; algunos
   se pararán a mirarte, otros se girarán de cuerpo entero y el resto seguirán a lo suyo mirándote de
   reojo. Si te alejas, se olvidan de ti y vuelven a su rutina.

### Escena de comparación (`NPC_Visual_Test.tscn`)

1. Ábrela y ejecútala (F6): verás el suelo, unos bloques, el jugador de prueba (chándal gris) y
   **8 ciudadanos** de los packs nuevos deambulando por la zona.
2. **WASD** mover · **Shift** correr · **clic** capturar el ratón · **ESC** liberarlo.
3. Acércate a un ciudadano: se dará cuenta y girará la cabeza hacia ti.

El jugador de prueba existe sólo para recorrer la escena: el personaje real del juego
(`node_3d.tscn`) no se ha tocado.

## Comportamiento (`npc_citizen.gd`)

| Estado | Qué hace |
|---|---|
| `IDLE` | quieto con una de sus posturas (que va cambiando); espera 1–3,5 s o 4–9 s |
| `DECIDE` | busca un destino alcanzable y gira hacia él |
| `WALK` | avanza guiado por `NavigationAgent3D`; a mitad de camino puede pararse o girar |
| `PAUSE` | parada breve en mitad del trayecto (probabilidad `pause_chance`) |
| `TURN` | giro corto (`turn_l` / `turn_r`) y sigue camino (probabilidad `turn_chance`) |
| `ARRIVE` | llega, mira alrededor y vuelve a `IDLE` |
| `NOTICE` | se ha dado cuenta del jugador: si iba andando sigue andando y empieza a mirarlo |
| `REACT` | reacción elegida: mirar de reojo, pararse a mirarlo, girarse entero hacia él o dedicarle un gesto |

Cada ciudadano sortea su propio carácter (`_randomize_personality()`): multiplicador de velocidad
(0.85–1.15), probabilidad de trotar, de pararse y de girar. La velocidad de avance sale siempre del
clip que está reproduciendo (metadata `speed`) multiplicada por ese carácter, así que cada uno va a
su ritmo sin patinar. Si se queda atascado más de `stuck_timeout` segundos, elige otro destino.

## Reacciones al jugador (Etapa 3)

Cada ciudadano comprueba cada 0,25–0,5 s (desfasados entre ellos) si el jugador está a menos de
`notice_distance` (9 m por defecto). Sólo lo hacen los que están en nivel `NEAR`, así que los que
están lejos no gastan nada en mirar a nadie.

| Ajuste | Para qué |
|---|---|
| `notice_distance` | radio en el que se fijan en el jugador |
| `close_distance` | si el jugador pasa muy cerca y se mueve, se fijan aunque ya estuvieran dentro |
| `reaction_chance` | probabilidad de reaccionar (al azar 0,35–0,85 por ciudadano: no reaccionan todos) |
| `reaction_cooldown` | espera (10–32 s) antes de poder volver a fijarse en él |
| `head_yaw_limit` / `head_pitch_limit` | cuánto gira la cabeza sin mover el cuerpo (45–75° / 15–30°) |
| `look_at_height` | altura del jugador a la que miran (1,5 m) |

Tipos de reacción (se sortean con pesos): **mirar de reojo** y seguir a lo suyo (40 %), **pararse a
mirarlo** (24 %), **girarse de cuerpo entero** hacia él, girando despacio (20 %), y **dedicarle un
gesto breve** —asentir, negar, señalar o recoger algo— parándose un momento (16 %). Al terminar, el
ciudadano retoma su trayecto anterior (o se queda quieto si estaba esperando). Cada tipo dura lo suyo
(0,9–3,4 s), así que no reaccionan todos igual ni a la vez.

Cómo se gira la cabeza: un `SkeletonModifier3D` (`NPCLookAt`) calcula el viraje y la inclinación que
le faltan a la cara para apuntar al jugador, los recorta a los límites y los aplica **después** de la
animación de cada fotograma. Como parte de la pose del fotograma, el resultado converge y no se
acumula, y la cabeza vuelve a su sitio sola, con fundido, cuando deja de mirar. El eje de la cara
(+X del hueso `mixamorig_Head`) y el de "arriba" se midieron sobre los propios modelos.

> Nota: la reacción de **dedicar un gesto** usa gestos que ya venían con los rigs (asentir, negar,
> señalar, recoger algo), no un clip de saludo: el único saludo de los packs (UAL2 «Yes») queda con
> pose de caminar al retargetearlo a estos rigs, así que no se usa.

## Ciudadanos con el aspecto nuevo (City Folks / Urban Man)

La **escena principal** (`NPC_TestScene.tscn`) lleva los modelos fijados a mano en `citizen_models`
(Urban Man, Deportista y Muscle Man), así que **todos** sus ciudadanos son de los packs nuevos y el
sorteo no puede elegir un PSX. En `NPC_Visual_Test.tscn` el generador va además con `poly_share` a 1,0.

Los ciudadanos nuevos se montan en caliente (`npc_citizen_model.gd`, clase `NPCCitizenModel`):

- Se parte del cuerpo del personaje, se le quitan sus mallas y se le añaden piezas modulares
  aleatorias (cabeza, torso, manos, piernas, pies) de **los tres personajes que tienen cara**
  (Urban Man, Deportista y Muscle Man). Todas las piezas comparten la pose de reposo, así que encajan
  sin recolocar nada. *Dough Sensei* quedó fuera del sorteo por su cabeza-caja.
- Cada pieza trae su propio *skin* de huesos: se vuelve a enlazar por **nombre de hueso** (el orden
  de huesos cambia entre personajes), no por índice.
- Sirven los mismos clips horneados: la librería del rig nuevo trae andar, trote, correr, giros a
  mitad de camino, saludo con la cabeza y giros de 90°. Los clips del pack RPG que no encajaban
  (andar lesionado, correr de lado en guardia) se descartaron.
- El sorteo de piezas se puede apagar con `vary_model_parts` en el inspector del ciudadano, para ver
  un modelo tal cual viene del paquete.

Se dejaron fuera los accesorios (gorra, gafas): no traen esqueleto y vienen sin escalar.

## Variedad: cuerpos, ropa, clips y reacciones

Los paquetes traen **una sola versión de cada prenda** (una sudadera oscura, un chándal gris, unos
tirantes blancos): no hay variantes de color en los archivos. Para que la multitud no parezca un
ejército clonado se sortean cuatro cosas **por ciudadano y por separado**, de modo que se combinan
libremente:

| Qué se sortea | De dónde sale |
|---|---|
| Cuerpo: cabeza, torso, manos, piernas y pies | 4 personajes (Urban Man, Deportista, Muscle Man y el torso con delantal de Dough Sensei) |
| Color de la ropa | paletas de camiseta, pantalón y zapatos (una sola prenda llamativa por persona) |
| Tono de piel y pelo | 6 tintes suaves |
| Clips | 4 posturas de espera distintas + andar + trote + 2 giros + 1 gesto |

### El color de la ropa (`NPCs/Shaders/npc_outfit.gdshader`)

Multiplicar la textura por un color sólo puede **oscurecer** (nunca da blanco, ni convierte un verde
en azul), así que el recoloreado se hace con un shader que **reemplaza** el color de la tela
conservando su luminancia: el dibujo de las costuras y los pliegues se mantiene y la prenda pasa a ser
la variante. Como cada prenda de origen tiene un brillo muy distinto (un pantalón a 0,15 y unos
tirantes a 0,75), cada pieza lleva apuntado su brillo medio **medido** (`ref`) y el shader lo usa para
normalizar: una tela oscura se recolorea igual de viva que una clara.

El shader deja también un filo de luz en el contorno (rim 0,22), pero con el tinte en blanco
(`RIM_TINT = 0.0`). **Es un detalle que se escapa fácil**: Godot colorea el *rim* con un rosa por
defecto, y en una prenda clara eso se ve como si la tela fuese malva (así salió la primera vez, con
los modelos en fila delante). Los materiales pulidos ya usaban `rim_tint` 0,6, que lo neutraliza; un
shader escrito desde cero no, y hay que ponerlo a mano.

### Las paletas son deliberadas

`NPCCitizenModel.plan_variants()` no sortea colores sueltos: elige dentro de familias que combinan
(negro, gris, azul marino, beis, rojo apagado, mostaza, verde oliva, teal…) y aplica una regla
—**una sola prenda llamativa por persona**—: si la camiseta lleva color, el pantalón va en un tono
neutro (y al revés). Los zapatos son siempre discretos. Son variantes de la misma prenda (clara,
oscura y de color), todos tonos de ropa de calle.

### Lo que NO se recolorea (medido, no supuesto)

Para saber qué se puede teñir hay que saber qué contiene cada textura, y medir el atlas entero engaña
(está casi vacío). Se midió **muestreando cada textura en las coordenadas UV reales de su malla**:

| Pieza | Piel | Decisión |
|---|---|---|
| Torso de tirantes (Muscle Man) | **57 %** | no se recolorea: teñirlo teñiría el pecho y los brazos |
| Torso de Dough Sensei | 23 % | se recolorea poco (`cap` 0,45): así el cuello se salva |
| Torso de Deportista | 3 % | se recolorea algo menos (`cap` 0,6) |
| Sudaderas, piernas, pies, cabeza y manos | 0 % | recoloreado completo; la cabeza y las manos sólo se **tiñen** (multiplicando) para no perder la cara |

Aun así, el shader deja intactos los píxeles con tono de piel (los reconoce por su color), de modo que
una pieza con el cuello o los brazos al aire nunca acaba con la piel azul. Y si una pieza tiene
demasiada piel (el torso de tirantes) se queda como vino, pulida igual que las demás.

### Animaciones por categorías

Los clips horneados van marcados con su categoría (`kind`) y cada ciudadano se reparte él solo los
que le tocan: `idle` + `social` → posturas de espera, `walk` → andar, `jog` + `run` → trote, `turn`
(el lado va en el nombre) → giros a mitad de camino, `react` → gestos. Añadir animaciones nuevas es
hornearlas: entran en el sorteo sin tocar el código. Las que se midieron y **no** se usan están
apuntadas con su motivo (`CLIPS_NOT_USED`): `idle_m3` (0,67 s: en bucle parece un tic), `run_u1` y
`sprint_rpg` (zancada de atleta).

Cada ciudadano recibe **cuatro posturas de espera distintas** (`idle`, `idle_b`, `idle_c`, `idle_d`) y
va pasando de una a otra: al empezar cada espera elige una que no sea la anterior, y en las esperas
largas cambia de postura a mitad. Antes eran dos y siempre las mismas. Las posturas nuevas salen de
las librerías ya instaladas y se eligieron midiéndolas: agacharse, estirar el pecho y hablar por
teléfono (tres cosas que se ven en cualquier acera). Los gestos (`nod_u1`, `shake_u1`, `gesture_u1`,
`pickup_rpg`) los usa la reacción nueva.

### Tiempos

Ningún ciudadano comparte los tiempos de otro: espera entre 1 y 3,5 s y entre 4 y 9 s (antes 1,5–7), y
las reacciones duran entre 0,9 y 3,4 s según el tipo. Las comprobaciones del jugador, la espera antes
de reaccionar y el enfriamiento también se sortean, así que no reaccionan en bloque.

### Comprobado (medido, no de ojo)

- [x] 24 ciudadanos montados con el código real: **0** con una postura de espera repetida dentro de sí
      mismos y **24 de 24** combinaciones de cuatro posturas distintas.
- [x] Los clips disponibles por categoría son exactamente los medidos: 9 posturas, 3 andares, 4 trote,
      3 giros a cada lado y 4 gestos.
- [x] El color llega a la prenda: las piezas 100 % tela llevan el shader con su color, su brillo de
      referencia y su `cap`; el torso de tirantes (57 % piel) y el delantal salen **sin recolorear**;
      la cabeza y las manos quedan teñidas con el mismo tono de piel entre sí.
- [x] El montaje de un ciudadano (piezas + recoloreado) tarda unos 60 ms; los materiales se comparten
      por textura y color, así que cientos de ciudadanos no crean cientos de materiales.
- [x] Comprobado **en vivo** en la escena principal (**195 FPS, sin errores**): los ciudadanos pasean
      con prendas distintas (granate, morado, azul, teal, naranja, gris), todos de pie sobre el suelo
      con su sombra, enteros y **sin el tinte rosa** del contorno.
- [x] Comprobado de cerca (mismos ciudadanos reales, cámara a 5 m): se ven las piernas, los pies y el
      pantalón de cada uno, las cabezas con su cara y el tono de piel compartido entre cabeza y manos;
      el cuerpo de tirantes y el delantal salen sin teñir.

## Pulido visual y de movimiento

Al poner los modelos en fila, con la misma luz y a la misma distancia, se vio claro cuál conviene usar
y cuál no:

| Modelo | Cara | Ropa | Vértices | Veredicto |
|---|---|---|---|---|
| PSX (`Characters/PSX/`, rig Mixamo de 33 huesos) | pintada: ojos, cejas, nariz, boca, barba, arrugas | pliegues y costuras pintados | ~700–1.200 | ya no se usan como ciudadanos: sólo el jugador de prueba temporal |
| City Folks / Urban Man (rig Auto-Rig Pro de 59 huesos) | lisa, sin rasgos, y el pelo facetado | correcta, con sombreado muy duro | 6.000–12.000 | disponibles con `poly_share`, no por defecto |

Aquella comparación dejó `poly_share` a 0,0 (los PSX parecían personas y costaban una décima parte),
pero **la decisión final fue la contraria**: en la escena principal se dejaron de usar los PSX y ahora
sus ciudadanos son los de los packs nuevos, fijados a mano en `citizen_models` (ver *Reconstrucción
visual*). El montaje modular, la segunda librería horneada y el camino de los dos rigs siguen ahí,
intactos, y los PSX siguen en el proyecto.

Lo que sí se cambió, para todos los personajes (jugador incluido), es el **acabado de los materiales**,
con una única función `NPCCitizenModel.polish_materials()` que se llama al montar el modelo (sin
shaders, sin post-proceso y sin una copia de material por ciudadano):

- **Aspereza 0,6** en lugar del 1,0 de fábrica: la piel y la tela dejan un brillo suave que sigue la
  curvatura (frente, hombros, pliegues del pantalón), y eso es lo que hace que se vea el *bulto*.
- **Perfilado (rim) 0,35**: un filo de luz en el contorno que despega la silueta del fondo. Es lo
  contrario de la calcomanía plana. (El shader de ropa usa lo mismo, con el tinte en blanco; ver
  *El color de la ropa*.)
- **Filtrado con mipmaps y anisotrópico**: la textura de 512 no hierve ni destella al moverse.
- El material del paquete no se toca: se trabaja sobre una copia, y como los ciudadanos comparten
  textura la copia se guarda en caché (cientos de NPCs, un solo material).

En la escena de prueba se añadió además una **segunda luz fría de relleno** desde el lado contrario al
sol y se subió el ambiente del cielo: con una sola direccional, el costado en sombra de un personaje
queda plano y se pierde el volumen. Las sombras del sol se afinaron (alcance de 45 m en la escena y
atlas de 4096 en los ajustes del proyecto, en vez de 90 m), lo que se nota en la sombra que proyecta
cada personaje bajo sus pies.

### El jugador de prueba

- **Modelo nuevo**: `Character_15` (chaqueta de cuero, cara pintada completa) en lugar de
  `Character_Male_33`.
- **Velocidad de crucero la del propio clip** (`speed_scale` 1,0 → ~1,6 m/s): a 1,25 andaba con prisa
  y se le acortaba la zancada.
- **Rampa de arranque y frenada de 0,3 s** (`accel_time`, antes 0,14): arrancar y parar de golpe era
  una de las cosas que más "de muñeco" se veían.
- **Giro con inercia** (`_steer`): el cuerpo no se gira de golpe hacia donde avanza; arranca despacio,
  coge velocidad y vuelve a frenar, y se inclina un poco hacia dentro de la curva.
- **Clip de giro en el sitio** (`turn_l` / `turn_r`) cuando hay que darse media vuelta casi parado. Se
  midió antes que el clip **no** trae el giro en el hueso (la cadera apenas se mueve, unos 7°), así que
  aporta el apoyo del pie y el cuerpo lo giramos nosotros: si se girara también el nodo, el personaje
  daría el doble de vuelta.
- **Dos posturas de espera** que se alternan cada 5–12 s (`idle` / `idle_b`), con el cruce lento que ya
  traía el árbol: parado no es una estatua.
- **Cámara** un poco más cerca y menos deformada (3,8 m y campo de visión 64°, antes 4,2 m y 70°).
- **Salto, caída y aterrizaje** con sus propios clips (**Espacio** para saltar). Son los tres únicos
  del pack RPG que aportaban algo que faltaba: antes, al saltar no había nada que reproducir y el
  personaje se quedaba en el aire con pose de caminar. `jump` (0,63 s) → `fall` (1,10 s, repetido) →
  `land` (0,50 s, sale solo al tocar el suelo y devuelve el mando a andar o a quedarse quieto).
  Mientras está en el aire no se le frena, así que el salto conserva la inercia del despegue.

## Decidir con GdPlanningAI (opcional)

`NPCSpawner.goap_share` (por defecto 0,34) decide qué proporción de ciudadanos recibe un **cerebro**
(`NPCGoapBrain`, que hereda de `GdPAIAgent`). El generador crea el mundo del planificador
(`GdPAIWorldNode`) sólo si hace falta; el cerebro nunca lo crea por su cuenta.

- Objetivos: **Pasear** (busca un destino nuevo), **Descansar** (cuando lleva mucho rato andando) y
  **Acercarse al jugador** (si lo tiene cerca y es curioso).
- Acciones: las tres llaman a funciones que ya existían en `npc_citizen.gd`
  (`wander_to_new_destination`, `rest_for`, `approach_player`), así que la navegación, la evitación y
  las animaciones son exactamente las mismas que sin planificador.
- Los ciudadanos sin cerebro siguen con la máquina de estados de siempre: se pueden mezclar los dos
  modos en la misma escena.
- El complemento ya está activado (*Proyecto → Ajustes del proyecto → Plugins*), lo que añade una
  pestaña «GdPlanningAI» en el editor para ver objetivos y acciones en marcha. Para dejarlo sin
  efecto basta con poner `goap_share` a 0.

## Niveles de actividad (LOD)

`NPCSpawner` reparte a los ciudadanos en tres niveles cada `activity_interval` segundos (un cuarto
por turno) según su distancia al jugador:

| Nivel | Distancia | Qué mantiene activo |
|---|---|---|
| `NEAR` | < `mid_distance` (30 m) | máquina de estados + navegación + evitación + animación |
| `MID` | `mid_distance` … `far_distance` | navegación y animación, sin evitación |
| `FAR` | > `far_distance` (70 m) | congelado (`PROCESS_MODE_DISABLED`) tras fundir a idle |

### Ajustes del generador (inspector de `NPCSpawner`)

| Grupo | Ajuste | Para qué |
|---|---|---|
| Generación | `npc_count` | cuántos ciudadanos crear |
| | `spawn_area` | rectángulo donde aparecen |
| | `spawn_min_distance` / `spawn_max_distance` | anillo de distancia al jugador (0 = sin máximo) |
| | `min_spacing` | separación mínima entre ciudadanos (nunca dos en el mismo sitio) |
| | `wander_area` | rectángulo por el que pueden deambular |
| | `player_clearance` | hueco libre alrededor del jugador |
| | `citizen_models` | modelos a usar (vacío = todos los de `Characters/PSX/`) |
| LOD | `mid_distance` / `far_distance` | umbrales de los niveles de actividad |
| | `activity_interval` | cada cuánto se reasigna el nivel |

## Pruebas de escalabilidad

Para medir, cambia `npc_count` en el inspector o llama a `respawn(n)` en marcha. Medido en un
RX 6600 (D3D12, Forward+), con el LOD por defecto y `goap_share = 0,34`:

| Ciudadanos | Aspecto nuevo (`poly_share` 0,7) | Sólo PSX (0,0) | Sólo nuevos (1,0) |
|---|---|---|---|
| 10 | 198 FPS | — | — |
| 25 | 172 FPS | — | — |
| 50 | 117 FPS | 160 FPS | 110 FPS |
| 100 | 66 FPS | — | — |
| 200 (LOD forzado a 14 / 26 m) | 26 FPS | 91 FPS (Etapa 3, sin planificador) | — |

Los modelos nuevos cuestan más que los PSX: son humanos vestidos de 6.000 a 12.000 vértices y cada
ciudadano lleva cinco piezas en mallas separadas (cabeza, torso, manos, piernas y pies), mientras que
un PSX es una sola malla de baja resolución. Para multitudes densas quedan los dos mandos: baja
`poly_share` (los PSX siguen en el proyecto precisamente por esto) y aprieta `mid_distance` /
`far_distance`, que congelan a los que están lejos. El planificador también cuesta CPU por agente, y
por eso el generador sólo se lo pone a `goap_share` de los ciudadanos y sólo en el nivel `NEAR`.

Los que no se mueven son los que están en `IDLE` en ese instante, no ciudadanos bloqueados.

La tabla se midió con `poly_share` 0,7, el valor de la Etapa 4. Con el valor actual (0,0) sólo se pagan
modelos PSX, así que la escena tal y como viene hoy rinde como la columna «sólo PSX».

## Añadir ciudadanos

Instancia `NPC_Citizen.tscn` y asigna en el inspector `model_scene` (un FBX de `Characters/PSX/`)
y `body_type` (`male` / `female`). O usa el nodo `NPCSpawner`, que genera los ciudadanos con
modelos, posiciones, clips y caracteres distintos: si dejas `citizen_models` vacío los detecta solo
de las carpetas PSX (y descarta los que no tienen textura en el paquete).

Cada ciudadano elige al azar **cuatro posturas de espera** distintas, un clip de caminar, uno de
trote, sus dos giros y un gesto (los reparte por categorías: ver *Variedad*), y toma la velocidad de
avance de la propia animación (metadata `speed`), de modo que ningún clip provoca deslizamiento de
pies. La librería de los PSX tiene 18 clips de locomoción y reacción (`idle_m1`, `idle_m2`, `walk_m1`,
`run_m1`, `idle_f1`, `idle_f2`, `walk_f1`, `run_f1`, `turn_m1_l`, `turn_m1_r`, `turn_f1_l`,
`turn_f1_r`, `idle_u1`, `idle_u3`, `walk_u1`, `jog_u1`, `run_u1`, `nod_u1`; velocidades entre 0.61 y
3.28 m/s, los giros duran 1.0 s) más tres de **aire** (`jump_m1`, `fall_m1`, `land_m1`, que sólo usa
el jugador de prueba: ningún ciudadano salta) y seis de **variedad** (agacharse, estirar el pecho,
hablar por teléfono, negar, señalar y una segunda postura de espera). La librería de los modelos
nuevos tiene 29 sumando los del pack RPG (trote y giros de 90°).

Para elegirlos se midió cada clip de los packs y se apartaron los que no son de civil: «Walk_Carry»
(brazos adelantados 0,19 m y codo a 57°, parecía ir cargando algo), «Walk_Formal» (los brazos apenas
se mueven) e «Idle_FoldArms» (brazos cruzados) no se hornean siquiera; «Sprint» y «Yes» sí están en
la librería, pero ningún ciudadano los usa (dejan una zancada exagerada y una pose de caminar).

## Regenerar las animaciones

Si cambias los clips de origen hay que volver a hornear. Desde un script de Godot:

```gdscript
var baker := NPCAnimationBaker.new()
baker.build_all()       # librería de los modelos PSX (rig Mixamo) → Citizen_Animations.res
baker.build_all_arp()   # librería de los modelos nuevos (rig Auto-Rig Pro) → Citizen_Animations_ARP.res
```

Cada hornada imprime la velocidad real de cada clip (m/s) y un error de retargeteo; conviene
comprobar que la velocidad del clip de andar coincide con la del ciudadano, porque es lo que evita
que los pies patinen. Después hay que refrescar la importación
(`godot --headless --path <proyecto> --import`). `build_all()` no cambia nada de la librería PSX si
los clips de origen no han cambiado: se puede volver a ejecutar sin miedo.

## Ganchos para lo que falta (diálogos, reacciones, misiones)

- `NPCCitizen.state` (enum `IDLE` / `DECIDE` / `WALK` / `PAUSE` / `TURN` / `ARRIVE`), `is_walking()`,
  `is_frozen()`, `move_speed()` y `current_clip()` para saber qué está haciendo cada uno.
- `hold_still(segundos)`: detiene al ciudadano para que reaccione, hable o se pare a mirar.
- `is_watching()` / `watch_amount()`: si está mirando al jugador y cuánto (0–1): útil para que
  alguien te hable sólo cuando te está mirando.
- `set_activity(Activity.NEAR)`: fuerza su nivel de actividad (útil para que un NPC que habla contigo
  no se congele ni se aleje).
- `_face_yaw` mide automáticamente hacia dónde mira cada modelo, así que añadir modelos nuevos
  (incluso de otros packs) no rompe el giro.
- `use_goap`, `goap_is_walking()`, `goap_is_resting()`, `goap_is_seeking()`: si el ciudadano lo
  decide un planificador y qué está haciendo.
- `NPCGoapBrain` guarda `cansancio`, `jugador_cerca` y `paseando` en su *blackboard*: para añadir un
  objetivo nuevo basta con escribir una subclase de `Goal` y registrarla en `_build_goals()`.
- `NPCSpawner.spawn_citizens()` devuelve la lista de ciudadanos creados, ideal para asignarles
  diálogos o misiones; `respawn(n)` / `clear_citizens()` permiten reciclarlos.
- Los exports (`trip_distance`, `pause_chance`, `turn_chance`, `hurry_chance`, `stay_chance`,
  `move_scale`, `turn_rate`…) se pueden ajustar por ciudadano o desde el generador sin tocar código.

## Notas técnicas

- Capas de colisión: 1 = mundo, 2 = NPC, 4 = jugador. Los ciudadanos sólo colisionan con el mundo
  y se separan entre sí mediante la evitación del `NavigationAgent3D` (no se empujan con la física).
- La escena necesita un `NavigationRegion3D` con la malla de navegación del terreno para que los
  ciudadanos puedan elegir destinos alcanzables; el generador espera a que el mapa de navegación
  esté sincronizado antes de colocarlos y valida cada punto (distancia a la malla, anillo de
  distancia, separación entre NPCs y hueco del jugador).
- Los clips horneados se aplican sobre el rig Mixamo de los modelos PSX: la pista de cada hueso es
  `Model/Skeleton3D:<hueso>`, por eso el modelo instanciado debe llamarse exactamente `Model`.
  Funcionan igual en los rigs de 41 y 65 huesos (verificado con `Character_Male_34`,
  `Character_Sheriff_N` y `Character_Female_12`).
- Los modelos nuevos usan el rig **Auto-Rig Pro**: los huesos izquierdos llevan sufijo `.l` y los
  derechos `.r`, y las pistas son del mismo estilo (`Model/Skeleton3D:root.x`…). La cabeza se busca
  por nombre y la orientación de la cara se mide del propio esqueleto, así que las reacciones
  funcionan igual en los dos rigs.
- Los huesos de estos modelos vienen a escala 0,01 (centésimas de metro) y los del pack RPG en
  centímetros: al hornear se convierten la velocidad del clip y el recorte de apoyo del pie (si no,
  el ciudadano se hundiría en el suelo o patinaría).
- Las animaciones se eligieron pensando en que no se note el cambio: los tres rigs de origen (Human
  Basic, UAL1 y UAL2) se retargetean al rig Mixamo copiando dirección + torsión relativa de cada
  hueso, con las transiciones a media marcha (`SWITCH_MODE_SYNC`).
- El aspecto "de juego viejo" se corrigió con calidad de render, no cambiando los modelos: MSAA 4×,
  FXAA, filtro anisotrópico 8×, mipmaps activados en las texturas PSX y el suelo en filtro lineal
  (antes usaba filtro *nearest*, que es lo que lo pixelaba de más).
- El volumen de los personajes se arregló en dos sitios a la vez: `NPCCitizenModel.polish_materials()`
  (aspereza 0,6 y perfilado 0,35, sobre copias cacheadas por textura) y una segunda luz de relleno en
  la escena. Con una sola direccional, el costado en sombra queda plano y el modelo parece un recorte.
- Los clips de giro se midieron antes de usarlos: son giros **en el sitio** (el hueso de la cadera
  gira unos 7° en todo el clip), así que el cuerpo hay que girarlo por código a la vez que suena.
- La asignación del clip de giro de los ciudadanos estaba invertida (`turn_l` con ángulo positivo).
  Se corrigió tras comprobar el signo (rotación `y` positiva = girar a la derecha). Es cosmético,
  pero ahora el pie apoya del lado correcto.
- La escena de prueba también ganó presentación: SSAO, niebla a distancia, un poco de glow y ajustes
  de saturación y contraste, con una luz solar de sombras suaves. Todo eso se apaga desde el
  `WorldEnvironment` si se busca un look más plano.
- El jugador de prueba lleva la cámara en un **rig independiente del cuerpo**
  (`CameraRig → CameraPitch → Camera3D`, con `top_level`): el ratón orbita la cámara y el personaje
  gira hacia donde avanza, sin realimentarse. La cámara mantiene la distancia constante
  (`camera_distance`), sigue al personaje con suavizado exponencial (`follow_smoothing`), se recentra
  sola detrás al avanzar (`auto_align_rate`) y se acerca si algo se interpone
  (`camera_collision_mask`). El movimiento del personaje tiene rampa de aceleración y frenada
  (`accel_time`) y la animación se reproduce a la velocidad real de avance, así que no patina ni al
  arrancar ni al frenar. Al girar, el cuerpo lleva inercia y algo de inclinación, y al darse media
  vuelta casi parado usa el clip de giro en el sitio. Parado alterna dos posturas de espera.