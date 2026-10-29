# P10 — Streaming integral del mundo: ACTIVAR, PROBAR Y RETIRAR

> Estado de esta entrega: **ETAPA 1 (infraestructura + integración con interruptor)**.
> El sistema está **integrado en el arranque real pero DESACTIVADO por defecto**.
> Con el interruptor en off, PRISMAX se comporta **exactamente igual que antes**.
>
> IMPORTANTE: esta fase **reutiliza** los gestores de P9-B (bosque) y P9-D1a
> (ciudad). Por eso NO hay que borrarlos si solo quieres retirar P10; P10 depende
> de ellos.

## Qué hace (y qué no)

Orquesta el streaming por proximidad **solo de lo que es seguro descargar**:
- **Ciudad**: sectores visuales `S_x_y` (vía `GestorStreamingCiudad`, P9-D1a).
- **Bosque**: trozos `Trozo_x_y` (vía `GestorStreamingBosque`, P9-B).

**NO se descarga** (queda siempre cargado, a propósito): Terreno (Terrain3D, ya
tiene su propio streaming), Océano (superficie global única), Barco y Muelle
(objetos únicos), Límites del mundo, Farolas. Tampoco se descargan **colisiones**
de la ciudad (fuera de alcance; P9-D2).

---
# 1) Cómo ACTIVAR / DESACTIVAR y probar

## Interruptor central
- El nodo se llama **`StreamingMundo`**, hijo directo de `ZibaPrototipo` en
  `res://mundo/escena/ziba_prototipo.tscn`.
- Su propiedad **`activo`** (por defecto `false`) es el interruptor maestro.
  - `activo = false` → no hace nada (comportamiento original).
  - `activo = true` → crea y arranca los dos subgestores.
- `modo_diagnostico = true` → imprime y muestra en pantalla sectores por estado.
- Radios y presupuesto: `ciudad_r_activo/precarga/descarga`,
  `bosque_r_activo/precarga/descarga`, `max_ops_por_fotograma`.
- En caliente se puede llamar `set_activo(true/false)` y `restaurar_todo()`.

## Prueba ligera (sin generar el mundo real)
```bash
XDG_DATA_HOME=/tmp/p10/xdg \
  /home/micro/Descargas/Godot_v4.7.2-stable_linux.x86_64 --headless --path . \
  res://pruebas/streaming_mundo_test.tscn
```
Esperado: `===== RESULTADO STREAMING MUNDO: 13 OK, 0 FALLOS =====`.

## Prueba del mundo completo (PENDIENTE de verificación)
Arrancar el juego real (`res://mundo/escena/ziba_prototipo.tscn`) con
`StreamingMundo.activo = true` y recorrer ciudad/bosque. **No se pudo ejecutar en
esta sesión por presión de memoria** (memoria disponible ~440 MB); ver el informe.

---
# 2) Retirada MANUAL (sin Git, con el Explorador de archivos)

1. Cierra Godot.
2. **Deshaz la integración en la escena** `res://mundo/escena/ziba_prototipo.tscn`:
   abre el archivo con un editor de texto y borra EXACTAMENTE estas dos partes
   añadidas por P10:
   - la línea `[ext_resource ... path="res://mundo/entorno/streaming/gestor_streaming_mundo.gd" id="44_streaming"]`
   - el bloque del nodo completo:
     ```
     [node name="StreamingMundo" type="Node" parent="."]
     script = ExtResource("44_streaming")
     activo = false
     modo_diagnostico = false
     ```
   (o, más fácil: ábrela en Godot, selecciona el nodo `StreamingMundo` en el árbol
   y bórralo, guarda la escena). **No borres ningún otro nodo.**
3. Borra los archivos NUEVOS de P10:
   - `world/streaming/gestor_streaming_mundo.gd`
   - `world/streaming/gestor_streaming_mundo.gd.uid`
   - `pruebas/streaming_mundo_test.gd`
   - `pruebas/streaming_mundo_test.gd.uid`
   - `pruebas/streaming_mundo_test.tscn`
   - `world/streaming/P10_RETIRADA.md` (este archivo, opcional)
4. **NO borres** `world/streaming/gestor_streaming_ciudad.gd`(+uid) ni
   `gestor_streaming_bosque.gd`(+uid) salvo que quieras retirar también P9-D1a y
   P9-B (ver sus propias guías). P10 los usa.
5. Comprueba: abre el juego; debe arrancar como siempre. Busca en el proyecto el
   texto `StreamingMundo` / `gestor_streaming_mundo`: no debe aparecer.

---
# 3) Retirada mediante GIT (segura, solo lo de esta fase)

Confirma primero qué es exclusivo de P10:
```bash
cd /home/micro/hola/Prismax-v3
git status --porcelain --untracked-files=all | grep -E 'gestor_streaming_mundo|streaming_mundo'
```
Debe listar solo `world/streaming/gestor_streaming_mundo.gd`(+`.uid`) y
`pruebas/streaming_mundo_test.gd`(+`.uid`)(+`.tscn`).

Borrar los archivos nuevos (NO uses `git clean` ni `git reset --hard`):
```bash
rm -f world/streaming/gestor_streaming_mundo.gd
rm -f world/streaming/gestor_streaming_mundo.gd.uid
rm -f pruebas/streaming_mundo_test.gd
rm -f pruebas/streaming_mundo_test.gd.uid
rm -f pruebas/streaming_mundo_test.tscn
rm -f world/streaming/P10_RETIRADA.md   # opcional
```

La escena modificada: P10 solo AÑADIÓ dos cosas a
`ziba/escenas/ziba_prototipo.tscn` (una línea de `ext_resource` y un bloque
`[node name="StreamingMundo" ...]`). Antes de esta fase ese archivo NO tenía otros
cambios locales. Primero **comprueba** que los únicos cambios son los de P10:
```bash
git diff -- ziba/escenas/ziba_prototipo.tscn
```
Si el diff muestra SOLO la línea `44_streaming` y el bloque `StreamingMundo`,
puedes revertir el archivo con seguridad:
```bash
git checkout -- ziba/escenas/ziba_prototipo.tscn
```
Si el diff mostrara cualquier otra cosa, **NO ejecutes** ese comando: borra a mano
las dos partes indicadas en el apartado 2.

Comprobación final:
```bash
git status --porcelain --untracked-files=all | grep -E 'streaming_mundo|gestor_streaming_mundo' \
  && echo "QUEDA ALGO" || echo "P10 retirado limpiamente"
git diff --stat -- ziba/escenas/ziba_prototipo.tscn   # debe quedar vacío
```

---
# 4) Estado de Git registrado

- Rama de trabajo de esta fase: **`p10-streaming-integracion`**
  (HEAD `104c798037b1b5884c1320e875766a953ac47c86`, mismo commit que
  `backup/mi-trabajo`).
- 8 archivos modificados PREEXISTENTES (NO tocados por P10):
  `enemigos/Scripts/proyectil_enemigo.gd`, `npcs/Scripts/director_peatones.gd`,
  `pruebas/auditoria_rendimiento/arnes_auditoria.gd`, `generador_ciudad.gd`,
  `ui/scenes/MainMenu.tscn`, `ui/scripts/ajustes_graficos.gd`,
  `ui/scripts/main_menu.gd`, `ui/scripts/menu_option.gd`.
- Modificado por P10: `ziba/escenas/ziba_prototipo.tscn` (solo las 2 adiciones).
- Preferencias reales (NO tocadas): `ajustes_graficos.cfg` md5
  `3f2ad3952e188d1cded3bcb0e3765ceb`.
- Sin `commit`, `push`, `reset`, `clean`.