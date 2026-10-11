# Enemigos de prueba (`res://Enemigos Prueba/`)

Sistema de enemigos cápsula para probar el combate EN LA PARTIDA PRINCIPAL
(`res://ziba/escenas/ziba_prototipo.tscn`). No forma parte de la ficción del
juego: son maniquíes de combate con IA de cerco.

## Controles

| Tecla | Acción |
|---|---|
| **G** | Aparece un grupo de **6 enemigos** alrededor del jugador (`enemigos_prueba`; es una tecla libre en el Input Map de main). Con un grupo activo, G lo retira para poder regenerarlo limpio. |
| **F** | Menú radial de transformaciones de main (incluye Combate). Las transformaciones se eligen ahí: la antigua alternancia directa con tecla (`transformacion_velocidad`) ya no existe. |
| **K** | Daño de prueba al jugador (`dano_prueba`) — sirve para ver la viñeta de daño. |

## Estructura

```
Enemigos Prueba/
├── Materials/                 Materiales de la cápsula y de la barra de vida
│   ├── enemigo_capsula.tres   Cápsula (el destello de daño usa su emisión)
│   ├── barra_vida.gdshader    Barra de vida de una sola pieza (fondo + relleno)
│   └── barra_vida_fondo.tres  Material oscuro sin sombras del visor del enemigo
├── Scenes/
│   └── enemigo_prueba.tscn    Enemigo reutilizable (CharacterBody3D + cápsula + barra)
└── Scripts/
    ├── enemigo_prueba.gd      EnemigoPrueba: vida, daño, IA de cerco y ataque por turnos
    └── gerente_enemigos_prueba.gd  GerenteEnemigosPrueba: aparición (G), cerco y coordinación
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

## Cómo comprobarlo

- **Suite automática** (no abre ventana; deja las comprobaciones en consola). Se
  ejecuta como escena, igual que las suites de main (`controles_test`,
  `jugabilidad_test`), que es lo que garantiza que los autoloads del proyecto ya
  existan al compilar el controlador:

  ```
  godot --headless --path . res://_tests/prueba_enemigos_prueba.tscn
  ```

  (También se puede abrir `res://_tests/prueba_enemigos_prueba.tscn` en el editor
  y pulsar F6.)

- **En vivo**, con el jugador real y una pista plana: abre
  `res://_tests/escena_verificacion_enemigos.tscn` y pulsa **G** en el juego. El
  monitor imprime cada medio segundo cuántos enemigos hay, cuántos atacan a la
  vez, el estado de la viñeta y la vida/escudo del jugador.

Ninguna de las dos forma parte del juego: viven en `res://_tests/`.