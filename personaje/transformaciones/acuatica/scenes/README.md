# SCENES — ESCENAS DEL MÓDULO

> ## `player_test.tscn` = **ESCENA DE PRUEBA / DESARROLLO**
>
> Es el banco de pruebas del personaje acuático: suelo, límites, dos plataformas,
> una rampa, el lago y tres maniquíes de entrenamiento. **No es contenido de
> juego**: es la escena que se ejecuta (F5) para probar el personaje.

Contiene:

| Nodo | Qué es |
| --- | --- |
| `WorldEnvironment`, `Sun` | Cielo procedural y luz direccional |
| `Ground`, `FieldEast/West/North` | Suelo y límites de la zona de pruebas |
| `PlatformSmall`, `PlatformHigh`, `Ramp` | Alturas para probar saltos y rampas |
| `Player` | Instancia de `../character/player.tscn` (el personaje acuático) |
| `Lake` | Instancia de `../water/lake.tscn` (el agua) |
| `Dummy1`, `Dummy2`, `Dummy3` | Maniquíes de entrenamiento (`training_dummy.tscn`) |

## `training_dummy.gd` / `.tscn`

Maniquí de entrenamiento: `StaticBody3D` del grupo `damageable` que se construye
entero en `_ready()`. Tiene vida, recibe daño, se puede **atrapar** con la prisión
de agua y cae al ser derrotado. **No ataca ni se mueve**: sirve de objetivo para
probar las habilidades y el combate.

Cumple el mismo contrato que puede cumplir cualquier enemigo del juego:
`apply_damage()`, `get_hit_center()`, `get_hit_radius()`, `trap()`,
`is_defeated()` y el grupo `damageable`.