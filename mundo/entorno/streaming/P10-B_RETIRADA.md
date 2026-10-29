# P10-B — "Optimización agresiva del mundo" (menú): ACTIVAR, DESACTIVAR Y RETIRAR

> Función **OPCIONAL del jugador**. **Desactivada por defecto**: sin activarla,
> PRISMAX se comporta igual que siempre. Se controla desde el menú de pausa
> (en partida): **ESC → CONFIGURACIÓN → GRÁFICOS**.

## Qué es
Un interruptor en GRÁFICOS ("OPTIMIZACIÓN AGRESIVA DEL MUNDO") que habilita el
gestor central `StreamingMundo` (P10). Al encenderlo aparecen sus controles:
- **DISTANCIA DE CARGA** (barra): radio que se mantiene cargado. 60..600 m.
- **DISTANCIA DE PRECARGA** (barra): margen que se suma a la carga. 20..300 m.
- **MODO DE DIAGNÓSTICO** (SÍ/NO): muestra sectores cargados/precargados/descargados.
- (La **DISTANCIA DE VISIÓN** ya existía como ajuste gráfico; NO se duplica.)
Las barras van en METROS reales porque la ciudad usa sectores de 42 m y el bosque
trozos de 200 m. La descarga tiene histéresis (+60 m) para no oscilar.

## 1) Activar / desactivar desde el juego
- En partida: ESC → CONFIGURACIÓN → GRÁFICOS → "OPTIMIZACIÓN AGRESIVA DEL MUNDO"
  (< SÍ >). Aparecen las barras y el diagnóstico.
- Al **desactivarla**, el gestor restaura de forma segura todos los sectores
  descargados (no queda mundo a medias).
- La elección se guarda en `user://ajustes_graficos.cfg` (sección `graficos`:
  `optimizacion_agresiva`, `distancia_carga`, `distancia_precarga`,
  `modo_diagnostico_stream`).
- Prueba ligera (sin mundo):
  ```bash
  XDG_DATA_HOME=/tmp/p10b/xdg /home/micro/Descargas/Godot_v4.7.2-stable_linux.x86_64 \
    --headless --path . res://pruebas/ajustes_p10b_test.tscn
  ```
  Esperado: `===== RESULTADO P10-B AJUSTES: 21 OK, 0 FALLOS =====`.

## 2) Archivos de esta fase
**Nuevos:** `pruebas/ajustes_p10b_test.gd` (+`.uid`) y `pruebas/ajustes_p10b_test.tscn`.

**Modificados (sólo se AÑADIERON bloques, no se cambió nada existente):**
- `world/streaming/gestor_streaming_mundo.gd` — nuevos métodos `aplicar_radios()` y
  `set_diagnostico()`.
- `ui/scripts/ajustes_graficos.gd` — estado, persistencia y `_aplicar_streaming()`.
- `ui/scripts/pause_menu.gd` — referencias, conexiones, manejadores y refresco.
- `ui/scenes/PauseMenu.tscn` — fila del interruptor + panel de controles dependientes.

> ⚠️ `ui/scripts/ajustes_graficos.gd` YA tenía cambios locales preexistentes (era
> uno de los 8 archivos modificados antes de esta fase). **Nunca** hagas
> `git checkout` sobre él: se perderían esos cambios previos. Su retirada es MANUAL
> (apartado 3).

## 3) Retirada MANUAL (sólo los cambios de P10-B)

1. Cierra Godot.
2. **`ui/scripts/ajustes_graficos.gd`** — borra los bloques marcados "P10-B":
   - el bloque de variables tras `var calidad: int = Calidad.ALTA` (las 4 líneas
     `var optimizacion_agresiva/...` y su comentario);
   - las 4 líneas `cf.set_value(SECCION, "optimizacion_agresiva"/"distancia_carga"/
     "distancia_precarga"/"modo_diagnostico_stream", ...)` en `_guardar`;
   - las 4 líneas de lectura `optimizacion_agresiva = ...` (etc.) en `_cargar`;
   - la línea `_aplicar_streaming()` en `_reaplicar_todo`;
   - TODA la sección final `# ===== P10-B: STREAMING` hasta el final del archivo.
3. **`ui/scripts/pause_menu.gd`** — borra: el bloque `@onready` de P10-B (desde
   `# P10-B: streaming...` hasta `_diag_der`), el bloque de conexiones de P10-B en
   `_conectar_opciones_graficos`, las funciones `_on_optimizacion_paso` y
   `_on_diagnostico_paso`, y las líneas de P10-B dentro de
   `_actualizar_opciones_graficos` (desde `# P10-B: opción de streaming` hasta
   `_diag_valor.text = ...`).
4. **`ui/scenes/PauseMenu.tscn`** — borra los nodos `OptimizacionFila` y
   `OptimizacionDependientes` (y sus hijos). Es más fácil desde el editor: abre la
   escena, selecciona esos dos nodos y bórralos.
5. **`world/streaming/gestor_streaming_mundo.gd`** — borra las funciones
   `aplicar_radios()` y `set_diagnostico()`.
6. **Archivos nuevos** — borra `pruebas/ajustes_p10b_test.gd` (+`.uid`) y
   `pruebas/ajustes_p10b_test.tscn`.
7. Abre el juego: en GRÁFICOS ya no debe aparecer "OPTIMIZACIÓN AGRESIVA DEL MUNDO".

## 4) Retirada mediante GIT (sólo donde es seguro)

Los archivos NUEVOS son de esta fase y sin seguimiento:
```bash
cd /home/micro/hola/Prismax-v3
git status --porcelain --untracked-files=all | grep ajustes_p10b   # confirmar
rm -f pruebas/ajustes_p10b_test.gd pruebas/ajustes_p10b_test.gd.uid pruebas/ajustes_p10b_test.tscn
```

`ui/scenes/PauseMenu.tscn` y `ui/scripts/pause_menu.gd` NO formaban parte de los 8
archivos preexistentes, así que antes de esta fase estaban limpios. **Verifica** que
sus únicos cambios son los de P10-B y, sólo entonces:
```bash
git diff -- ui/scenes/PauseMenu.tscn ui/scripts/pause_menu.gd   # ¿sólo P10-B?
git checkout -- ui/scenes/PauseMenu.tscn ui/scripts/pause_menu.gd
```
Si el diff mostrara algo más, **NO** ejecutes `git checkout`: borra a mano (apartado 3).

`ui/scripts/ajustes_graficos.gd` **NO** se revierte con git (tiene cambios previos):
usa el apartado 3. `world/streaming/gestor_streaming_mundo.gd` es de P10 (nuevo, sin
seguimiento): si retiras P10 entero, se borra con su guía (`P10_RETIRADA.md`).

**Nunca** uses `git clean` ni `git reset --hard`.

## 5) Estado de Git registrado
- Rama: `p10-streaming-integracion`.
- 8 archivos modificados PREEXISTENTES (intactos, NO revertir):
  `Enemigos Prueba/Scripts/proyectil_enemigo.gd`, `NPCs/Scripts/director_peatones.gd`,
  `pruebas/auditoria_rendimiento/arnes_auditoria.gd`, `generador_ciudad.gd`,
  `ui/scenes/MainMenu.tscn`, `ui/scripts/ajustes_graficos.gd`,
  `ui/scripts/main_menu.gd`, `ui/scripts/menu_option.gd`.
- Preferencias reales: `ajustes_graficos.cfg` md5 `3f2ad3952e188d1cded3bcb0e3765ceb`
  (NO tocadas por las pruebas: se usó `XDG_DATA_HOME` aislado).