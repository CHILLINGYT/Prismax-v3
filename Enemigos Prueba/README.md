# Enemigos de prueba (`res://Enemigos Prueba/`)

Sistema de enemigos para probar el combate EN LA PARTIDA PRINCIPAL
(`res://mundo/escena/ziba_prototipo.tscn`). No forma parte de la ficción del
juego: son maniquíes de combate con IA de cerco.

Los enemigos se dibujan con **modelos Mixamo riggeados** (65 huesos `mixamorig_*`)
tomados de `res://cosas para enemigos/enemigos/`; ya no se ven cápsulas ni esferas
de depósito. La cápsula de reserva sigue en `enemigo_prueba.tscn` pero **oculta**
(no se borró) y su sistema se puede seguir generando por API para las pruebas.

## Controles

| Tecla | Acción |
|---|---|
| **G** | Aparece un grupo de **5 enemigos** alrededor del jugador (`enemigos_prueba`; es una tecla libre en el Input Map de main): **3 de cuerpo a cuerpo + 2 con armas**, usando las MISMAS escenas de H y J. Con un grupo activo, G lo retira para poder regenerarlo limpio. |
| **H** | Aparece un grupo de **3 enemigos cuerpo a cuerpo con esqueleto** (`enemigos_melee`). Persiguen al jugador y encadenan el combo golpe1→golpe2→golpe3. Con un grupo activo, H lo retira. |
| **J** | Aparece un grupo de **2 enemigos tiradores con esqueleto** (`enemigos_tirador`). Mantienen una distancia preferida, se reposicionan y disparan proyectiles. Con un grupo activo, J lo retira. |
| **F** | Menú radial de transformaciones de main (incluye Combate). Las transformaciones se eligen ahí: la antigua alternancia directa con tecla (`transformacion_velocidad`) ya no existe. |
| **K** | Daño de prueba al jugador (`dano_prueba`) — sirve para ver la viñeta de daño. |

La tecla **G** reutiliza las escenas de **H** (cuerpo a cuerpo) y **J** (armas): no
crea variantes nuevas. El sistema de **cápsulas** sigue en el proyecto
(`enemigo_prueba.tscn`) y se puede generar con `GerenteEnemigosPrueba.generar_grupo()`
(es lo que usan las suites de cápsulas), pero la tecla G **ya no lo usa**.

## Estructura

```
Enemigos Prueba/
├── Animations/
│   ├── enemigo_animaciones_mixamo.tres       Librería NATIVA (14 clips) para enemigocombate
│   ├── enemigo_animaciones_mixamo_arma.tres  Librería NATIVA (14 clips) para enemigoconarma
├── Materials/                 Materiales de la cápsula y de la barra de vida
│   ├── enemigo_capsula.tres   Cápsula (el destello de daño usa su emisión)
│   ├── barra_vida.gdshader    Barra de vida de una sola pieza (fondo + relleno)
│   └── barra_vida_fondo.tres  Material oscuro sin sombras del visor del enemigo
├── Scenes/
│   ├── enemigo_prueba.tscn    Cápsula de reserva (modelo enemigocombate + cápsula oculta)
│   ├── enemigo_melee.tscn     Enemigo cuerpo a cuerpo (esqueleto + combo golpe1-2-3)
│   ├── enemigo_tirador.tscn   Enemigo tirador (esqueleto + proyectiles)
│   └── proyectil_enemigo.tscn Proyectil pequeño y rápido del tirador
├── Scripts/
│   ├── enemigo_prueba.gd      EnemigoPrueba: vida, daño, IA de cerco y ataque por turnos
│   ├── base/enemigo_base.gd   Base común: vida, contrato de daño, registro, barra, animación
│   ├── enemigo_melee.gd       EnemigoMelee: persecución + combo de tres golpes
│   ├── enemigo_tirador.gd     EnemigoTirador: distancia preferida + disparo
│   ├── proyectil_enemigo.gd   ProyectilEnemigo: avanza con raycast y daña al jugador
│   ├── Tools/                 Bakers (retargeting / nativo), religador de pistas y verificador de skins
│   └── gerente_enemigos_prueba.gd  GerenteEnemigosPrueba: aparición (G/H/J), cerco y coordinación
└── Tests/
    ├── verificacion_enemigos_esqueleto.*  Verificación en vivo (G/H/J)
    └── prueba_enemigos_esqueleto.*        Suite headless (57 comprobaciones, incluye la tecla G)
```

## Barra de vida

La barra es **un solo quad** (0,9 × 0,09 m) con `Materials/barra_vida.gdshader`, que
pinta el fondo, el relleno y su color (rojo → verde según la vida) y hace de
billboard en `vertex()`. Antes eran dos quads superpuestos y el relleno quedaba
tapado por el fondo según hacia dónde mirase el enemigo, porque el desplazamiento
que los separaba giraba con él; con una sola pieza ese fallo no puede ocurrir.
El enemigo sólo actualiza el uniforme `fraccion` (vida actual / vida máxima).

Como el enemigo de prueba es grande y pelea pegado al jugador, la barra **se
oculta sola cuando queda a menos de 2,2 m de la cámara** (a esa distancia taparía
media pantalla y no aporta nada), y reaparece pasados 2,6 m para no parpadear.

## Cómo se integran con lo que ya existía

- **Aparición (G):** `GerenteEnemigosPrueba` (nodo `EnemigosPrueba` de la escena
  principal) busca al jugador por grupo/tipo (sin rutas rígidas), pide puntos de
  aparición válidos al motor (rayo al suelo + sonda de hueco libre) y crea los 6
  enemigos como hijos suyos.
- **Cerco:** el reparto angular lo lleva el **`CombatFormation` del propio módulo
  FreeFlow** (`personaje/transformaciones/transformacion ataque/`), reutilizado
  tal cual; el enemigo solo pide su posición de anillo. Si no hubiera
  `CombatManager`, el gerente mantiene un anillo propio equivalente.
- **Turnos:** el límite de dos atacantes simultáneos lo lleva el
  **`AttackTokenManager` del módulo** (`max_attackers = 2` en
  `combat_config.tres`), con cola por antigüedad y liberación al morir, al
  aturdirse o al perder el alcance.
- **Daño al jugador:** `EstadisticasJugador.recibir_danio()` — el escudo absorbe
  su 80 % mientras tenga carga; la viñeta del HUD cambia de rojo azulado a rojo
  cuando el escudo llega a cero.
- **Daño a los enemigos:** contratos reales del proyecto —
  `take_hit()` (FreeFlow) + registro en el `CombatManager`, `take_damage()`
  (Fuerza) y `apply_damage()` + `get_hit_center()/get_hit_radius()` (acuática),
  todos con el grupo `damageable`.

## Enemigos con esqueleto (H y J)

Dos enemigos que comparten base y esqueleto retargetado
(`Animations/enemigo_animaciones_mixamo*.tres`, 14 clips nativos de Mixamo) pero con
IA distinta:

- **Cuerpo a cuerpo (`enemigo_melee.tscn`, tecla H):** persigue por el anillo de cerco y,
  cuando tiene al jugador cerca y de frente, encadena el combo FIJO golpe_1 → golpe_2 →
  golpe_3 (un solo daño por golpe, en el fotograma de impacto de cada clip) y lo repite.
  Cadencia: perseguir → parar y golpear → recuperar.
- **Tirador (`enemigo_tirador.tscn`, tecla J):** mantiene una **distancia preferida**
  configurable (avanza si está lejos, retrocede si está demasiado cerca), se reposiciona y
  dispara proyectiles pequeños y rápidos (`proyectil_enemigo.tscn`) que avanzan con un
  raycast por fotograma (no pueden atravesar paredes ni al jugador por ir rápido) y aplican
  daño por `EstadisticasJugador.recibir_danio()`.

Ambos heredan de `Scripts/base/enemigo_base.gd` el MISMO contrato real del proyecto que la
cápsula (grupo `damageable` + `take_hit`/`take_damage`/`apply_damage`/`execute`, registro en
el `CombatManager`, turnos y amenaza del módulo FreeFlow, barra de vida y destello de daño),
así que cualquier ataque del jugador (Velocista, Acuática, Fuerza o Combate) los alcanza
igual. El tirador NO usa el anillo de cerco (queda a 2.5 m, demasiado cerca para disparar):
gestiona su propia distancia.

## Modelos y asignación

| Modelo (`res://cosas para enemigos/enemigos/`) | Rol asignado | Rig | Animaciones |
|---|---|---|---|
| `enemigocombate.fbx` (malla `Ch32`, 4 texturas) | **cuerpo a cuerpo** (H y la mitad del grupo de G) | Mixamo, 65 huesos **`mixamorig8_*`**, `skin=true` | clips Mixamo nativos |
| `enemigoconarma.fbx` (malla `Ch35`, 3 superficies) | **tirador** (J) | Mixamo, 65 huesos `mixamorig_*`, `skin=true` | clips Mixamo nativos |

Los dos son rigs Mixamo de 65 huesos, así que **no hace falta retargeting**: los clips
se copian tal cual y sólo se adapta la escala de la pista de posición de la cadera
(`cadera_destino / cadera_origen`). Se conservan el baker con retargeting y el proxy
de Fuerza por si hicieran falta, pero los enemigos ya no los usan.

### Ligar las animaciones al modelo (leer antes de cambiar un modelo)

Las pistas de una librería son rutas `Skeleton3D:<hueso>`, así que dependen del
**nombre** de los huesos del modelo. Godot nombra los huesos de un FBX con el prefijo
de su **armadura** (`fbx/naming_version=2`): con la armadura llamada `mixamorig` salen
los nombres estándar `mixamorig_Hips`, pero con la armadura llamada `mixamorig8` salen
`mixamorig8_Hips`. Mismo rig, mismo orden de huesos… y el `AnimationPlayer` no
encuentra ninguna pista, así que el enemigo se queda en su **pose de reposo (la T)**.

Para religar una librería ya horneada al modelo real (sin tocar los clips: mismos
fotogramas y duración):

```
const Religar := preload("res://Enemigos Prueba/Scripts/Tools/religar_animaciones_a_modelo.gd")
for l in Religar.religar_todos(): print(l)
```

> **NO** se renombran los huesos del modelo para arreglarlo: los `Skin` de la malla
> resuelven sus binds **por nombre**, así que renombrar el esqueleto los deja en −1
> (medido) y la malla deja de deformarse. Las pistas, en cambio, se reescriben sin
> riesgo. Si querés la solución de raíz, re-exportá el modelo con la armadura llamada
> `mixamorig`: entonces los nombres coinciden solos y no hace falta religar nada.

### Orientación (por qué el frente es +Z y hay un giro de 180°)

Los dos FBX apuntan su **frente al +Z local** —comprobado con dos medidas
independientes: en reposo los dedos de los pies van hacia +Z y al golpear/disparar
la mano se extiende hacia +Z—, pero Godot (y este código, que orienta con
`rotation.y = atan2(-hacia.x, -hacia.z)`) trata el **−Z** como adelante. Sin
corrección, el enemigo caminaba y atacaba **de espaldas**.

La corrección es **una sola**, en el nodo **`Visual`** de cada escena:
`Transform3D(-1, 0, 0, 0, 1, 0, 0, 0, -1, 0, 0, 0)` (180° en Y). No se toca ni el
`Skeleton3D` ni la raíz `CharacterBody3D` (nada de giros duplicados) y **no se
invierte ningún vector de movimiento**: el cerco, el daño y el apuntado quedan
intactos. Medido después del cambio: con el cuerpo mirando al objetivo, el frente
del modelo da **+0,76/+0,84** hacia él y las manos de golpe_1/2/3 acaban delante.

> **Nota:** el modelo de `res://cosas para enemigos/Enemigo con esqueleto/` sigue sin
> poder usarse: es una malla ESTÁTICA (0 `Deformer`/`Cluster`/`Skin`). Se conserva, pero
> los enemigos ya no dependen de él. Para comprobar cualquier FBX nuevo:
>
> ```
> godot --headless --path . -s "res://Enemigos Prueba/Scripts/Tools/verificar_skin_enemigo.gd" -- "<ruta del fbx>"
> ```

### Comportamiento

- **Cuerpo a cuerpo:** además del combo, bordea obstáculos (esquiva con sondeos) y **no
  arranca el combo ni aplica daño si no tiene línea de visión** con el jugador: no golpea a
  través de paredes. Si el jugador se aleja, retoma la persecución al terminar la acción.
- **Tirador:** si el jugador se acerca demasiado **retrocede**; si se aleja fuera de alcance
  **avanza**; si una pared tapa la línea de visión **se desplaza de lado** (cambiando de lado
  si el que eligió está tapado) para recuperarla, en vez de disparar contra el muro. Sólo
  dispara con el objetivo vivo, en alcance, visible y dentro del arco.
- **Proyectil:** barrido de esfera (`cast_motion`) en vez de rayo, así no atraviesa nada a
  alta velocidad. Configurable: `radio` y `escala_visual` (tamaño), `velocidad`, `dano`,
  `duracion`, `mascara`. No daña al que lo lanzó ni a otros enemigos, y aplica daño una sola
  vez por impacto (se autodestruye).

## Cómo comprobarlo

- **Suite automática** (no abre ventana; deja las comprobaciones en consola). Se
  ejecuta como escena, igual que las suites de main (`controles_test`,
  `jugabilidad_test`), que es lo que garantiza que los autoloads del proyecto ya
  existan al compilar el controlador:

  ```
  godot --headless --path . res://pruebas/prueba_enemigos_prueba.tscn
  ```

  (También se puede abrir `res://pruebas/prueba_enemigos_prueba.tscn` en el editor
  y pulsar F6.)

- **En vivo**, con el jugador real y una pista plana: abre
  `res://pruebas/escena_verificacion_enemigos.tscn` y pulsa **G** en el juego. El
  monitor imprime cada medio segundo cuántos enemigos hay, cuántos atacan a la
  vez, el estado de la viñeta y la vida/escudo del jugador.

Ninguna de las dos forma parte del juego: viven en `res://pruebas/`.

- **Enemigos con esqueleto (H/J):** suite headless propia y escena de verificación en vivo,
  en `res://pruebas/enemigos/`:

  ```
  godot --headless --path . "res://pruebas/enemigos/prueba_enemigos_esqueleto.tscn"
  ```

  y, en vivo, abre `res://pruebas/enemigos/verificacion_enemigos_esqueleto.tscn` y pulsa
  **H** o **J**.
