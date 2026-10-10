# Velocidad — forma velocista de Leo

Sistema de supervelocidad del personaje. **No es un personaje aparte**: es una
forma de `LeoJugador` (`res://personaje/base/escenas/leo_jugador.tscn`), que
comparte cuerpo, colisión y cámara con las demás formas. La lógica vive en
`res://personaje/base/scripts/controlador_leo.gd` (secciones VELOCISTA).

- Escenas que lo usan: `personaje/base/escenas/leo_jugador.tscn` y
  `ziba/escenas/ziba_prototipo.tscn` (esta última sólo sobreescribe las
  librerías de animación del jugador instanciado).
- Scripts: `scripts/` (efectos_velocidad, trazador, combate, capa_velocidad),
  compartidos con `ziba/` por ser el mismo sistema.
- Shader: `shaders/distorsion_velocidad.gdshader` (post-proceso de pantalla).

---

## Animaciones: de dónde salen los `.tres`

**Los `.fbx` de origen de las animaciones del velocista NO existen en el
proyecto.** Los originales eran `res://ziba/animaciones/**` y sólo quedaron sus
`.fbx.import` (que se conservan sin tocar, porque son metadatos de importación).

Se recuperaron **desde el paquete de referencia `res://nuevo/velocidad/`**
(proyecto `Recuperacion`): allí estaban ya extraídos de la caché de importación
(`.godot/imported/*.res`) y guardados como recursos de texto autocontenidos, de
modo que **no necesitan ni el `.fbx` ni la caché**.

Los 15 `.tres` se copiaron **sin modificar** (verificado por md5) a
`res://personaje/transformaciones/velocidad/animaciones/` y las dos escenas
apuntan ya a ellos. El modelo (`modelo/modelo_velocidad.fbx`) es idéntico al del
paquete de referencia, así que las rutas de hueso de los clips encajan.

### Mapa librería → recurso

Cada clave es la que usa `controlador_leo.gd` (`ANIM_*`) y la que declara el
`AnimationPlayer` `Visual/Pose/Volteo/Modelo/AnimadorVelocista`:

| Clave de librería (constante)                | Archivo `.tres`                | Clip interno  |
|---|---|---|
| `inactivo` (`ANIM_INACTIVO`)                 | `inactivo.tres`                | `mixamo_com`  |
| `inactivo_despues-despues-de-30s-velocidad`  | `inactivo_velocidad.tres`      | `mixamo_com`  |
| `inactivo_modo_ataque` (`ANIM_MODO_ATAQUE`)  | `inactivo_modo_ataque.tres`    | `mixamo_com`  |
| `caminar_hacia_adelante` (`ANIM_ADELANTE`)   | `caminar_hacia_adelante.tres`  | `mixamo_com`  |
| `caminar_hacia_atras` (`ANIM_ATRAS`)         | `caminar_hacia_atras.tres`     | `mixamo_com`  |
| `dash-con-shift` (`ANIM_DASH`)               | `dash.tres`                    | `mixamo_com`  |
| `cargar_poder_click-derecho` (`ANIM_CARGA`)  | `cargar_poder.tres`            | `mixamo_com`  |
| `jumping up(1)` (`ANIM_SALTO`)               | `salto_aire.tres`              | `mixamo_com`  |
| `saltar`                                     | `saltar.tres`                  | `mixamo_com`  |
| `superduper_velocidad` (`ANIM_SUPERVELOCIDAD`)| `superduper_velocidad.tres`   | `mixamo_com`  |
| `combo-1` … `combo-4` (`ANIM_COMBO_*`)       | `combo_1.tres` … `combo_4.tres`| `mixamo_com`  |
| `calentamiento_ataque` (`ANIM_EMOTE`)        | `calentamiento_ataque.tres`    | `mixamo_com`  |

---

## Avisos para no romperlo otra vez

- **No repongas los `.fbx` que faltan**: no existen en `prismax` ni en
  `Recuperacion`; las animaciones ya no dependen de ellos.
- **No borres los `.fbx.import` huérfanos**: son metadatos preexistentes y no
  intervienen (nada los referencia ya).
- **No copies `res://nuevo/velocidad/` sobre este módulo**: es la referencia
  (`Recuperacion`), se conserva intacta y además sus escenas apuntan a
  `res://velocidad/...`, por lo que ese paquete **no se puede ejecutar en su
  sitio actual**; sólo sirvió como fuente de recursos.
- Las animaciones se resuelven por **clave de librería**, no por nombre de
  archivo: si se cambia un clip, respeta la clave de la tabla.