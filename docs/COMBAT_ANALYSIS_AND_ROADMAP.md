# Análisis Free-Flow Combat & Transformación Combate - Prismax v3
**Fecha:** 23/10/2026 - Arena AI
**Archivos analizados:** 22 archivos .gd de combate

---

## 1. ESTADO ACTUAL - Qué tenés hoy

### 1.1 Core Free-Flow (transformacion ataque/scripts/combat/)
Este es tu sistema más avanzado, tipo Batman Arkham:

**`combat_manager.gd` (118 líneas)**
- ✅ Bien: Centraliza registro de enemigos, tokens, formación, amenazas, combo. No hace daño ni IA.
- ✅ Usa `cuerpo_activo()` para soportar Vuelo (cuerpo hijo que se mueve).
- ❌ Problema: `_physics_process` hace `prune() + update()` de tokens cada frame aunque no haya combate.

**`combat_targeting.gd` (86 líneas) - JOYA**
- ✅ Intent direction = blend ponderado de WASD (peso 4.0) + cámara (2.5) + facing (1.0). Muy bueno, permite cambiar objetivo girando cámara.
- ✅ Scoring: alignment (3.0) + distance (1.0) + threat (1.2) + bonus current target (0.05)
- ✅ Hysteresis con `target_switch_threshold = 0.0` = cambio inmediato, no se pega.
- ❌ Falta: No considera altura (enemigos en barco/muelle), no filtra enemigos detrás de paredes, no prioriza enemigos que te atacan por la espalda.

**`combat_config.gd` (107 líneas) - Excelente**
- ✅ Todo tunable: target_radius 9m, ángulo 140°, approach 9m/s, etc.
- ✅ Config separada para counter, evade, stun, takedown, special, gadget.
- ❌ Problema: Valores hardcodeados en player.gd SPRINT no usan 100% el config (ej: HIT_WINDOW = 0.10 fijo).

**`combat_formation.gd` (113 líneas)**
- ✅ Asignación persistente de slots en anillo (evita jitter al recalcular cada frame).
- ✅ Orden determinístico por ángulo + instance_id.
- ❌ Problema: Radio fijo `formation_radius = 2.2m`, no escala con cantidad de enemigos (10 enemigos en 2.2m se amontonan). No considera obstáculos del `generador_ciudad`.

**`attack_token_manager.gd` (98 líneas)**
- ✅ Limita atacantes simultáneos a `max_attackers = 2`. Cola por tiempo de espera, rota turnos.
- ❌ Problema: No hay prioridad por amenaza (un enemigo lejos con token bloquea a uno que está a 1m).

**`threat_system.gd` (76 líneas)**
- ✅ Registra windups con tiempo restante, permite counter.
- ❌ Problema: `threat_level_for` devuelve 1.0 o 0.0 binario, no nivel real. No distingue entre ataque ligero/pesado.

**`combo_system.gd` (66 líneas)**
- ✅ Buffer de input 0.2s + keep_time 2.0s. Prioridad por acción.
- ❌ Problema: Buffer solo guarda acción+dirección, no timestamp preciso. No hay cancel en animación, solo en recovery.

**`attack_data.gd` (25 líneas)**
- ✅ Definición limpia de ataque: damage, range, windup/active/recovery, cancel_window, knockback, stun, speed.
- ❌ Problema: No tiene datos de hitbox (altura, forma), ni efectos, ni costo de estamina.

### 1.2 Player Free-Flow (player.gd - 865 líneas) - EL CORAZÓN
**SPRINT actual:** 3 golpes medidos sobre clips reales:
- jab: clip 0.467s, impacto 0.233s, daño 1.0x, knockback 1.0, speed 1.25
- cros: clip 0.733s, impacto 0.147s, daño 1.4x, knockback 1.3, speed 1.2
- gancho: clip 0.633s, impacto 0.327s, daño 1.7x, knockback 1.5, speed 1.15

State machine: FREE -> APPROACH (9m/s, max 1.5s) -> WINDUP -> ACTIVE (0.10s) -> RECOVERY (0.30s, cancelable 0.12s) -> FREE
- ✅ Approach automático si target > ideal_distance (1.7m)
- ✅ Combo window 2.0s desde último hit confirmado, no desde input buffer
- ✅ Cambio de target reinicia cadena a jab (FreeFlow rule)
- ✅ Counter (0.45s), Evade (0.35s, iframes 0.25s), Stun, Special (requiere combo 2+), Takedown, Gadget (radio 4.5m, cooldown 6s)
- ❌ Problemas detectados:
  1. `_flat_distance` y `_flat_dir` ignoran Y, pero `_in_front` usa dot 0.3 (~72°). Enemigos en escaleras/muelle fallan.
  2. `APPROACH` no tiene pathfinding, solo va en línea recta. Si hay banco/farola en medio, se traba.
  3. No hay lock-on visual fuerte: indicador circular existe pero es MeshInstance3D simple.
  4. `take_damage` rompe combo y pone HIT 0.25s, pero no hay animación de hit reactiva.

### 1.3 Transformaciones de combate actuales

**VELOCISTA - `velocidad/scripts/combate.gd` (157 líneas)**
- 4 golpes cíclicos 1-2-3-4 con reset 1.3s
- Afterimage cian con 3 siluetas por golpe (offset 0.28m + 0.22m paso)
- ❌ No tiene daño real, solo emite `golpe_realizado`. El daño está en otro lado? Muy desacoplado.
- ❌ Afterimage duplica `Modelo` entero cada golpe = GC spike.

**VUELO - `vuelo/scripts/ground_combat.gd` (342 líneas)**
- Cadena Jab -> Cross -> Kick -> Uppercut, cancel_ratio 0.5 (puede cancelar a mitad)
- Buffer de clics, avance 3.5m/s por golpe, guardia hold Q
- Impacto: esfera 1.4m radio, daño 8 + indice*4, usa `VueloDano.aplicar`
- ❌ Guardia: bug fix reciente ` _guardia = true` faltaba. Aún usa AnimationPlayer overlay, puede pelearse con flight controller.
- ❌ `_impacto_melee` hace `intersect_shape` cada golpe sin capa optimizada, y solo busca grupos `maniqui` o `damageable`.

**FUERZA - `fuerza/scripts (1)/Combat (1).gd` (103 líneas)**
- Sistema mínimo duck typing: grupo `damageable` + método `take_damage(cantidad, desde, empuje)`
- `golpear_esfera` con caída de daño por distancia (0.45 en borde), empuje hacia arriba 0.35
- ❌ Muy básico, no tiene combo, no tiene tokens, no tiene formación. Cada habilidad implementa su propia esfera.

**ACUATICA - `controlador_leo.gd` líneas de combate acuático**
- 2 golpes: attack (0.54 impacto) y attack_2 (0.55 impacto), alcance 1.1m, radio 0.7m
- Marea Quebradefensas: cada 3 impactos consecutivos, salpicadura grande + estado EMPAPADO 5s, +5% daño
- ❌ Solo 2 golpes, se siente pobre vs 4 de velocidad/vuelo.
- ❌ `A_MAREA_IMPACTOS` cuenta impactos al aire? Código dice que golpe al aire corta racha, pero hay que verificar.

**CONTROLADOR_LEO - `controlador_leo.gd` (6066 líneas!)**
- Integra todas las formas, tiene `c_objetivo`, `c_cadena`, `c_estado` para combate
- `_actualizar_indicador_objetivo` cada frame
- ❌ Archivo gigante, mezcla movimiento, agua, muerte, combate, estamina. Imposible de mantener en equipo.

---

## 2. LISTA DE IDEAS - 35 MEJORAS PRIORIZADAS

### 🔴 PRIORIDAD 1 - Core Free-Flow (hacen que se sienta como Arkham)

**1. Targeting 3D real (no solo flat)**
- Problema: `_flat()` pone Y=0, enemigos en barco/muelle no se targetean bien
- Solución: `intent_direction` debe considerar altura con peso menor (0.4 como en Fuerza). Score con `distancia_3d * 0.4 en Y`.
- Archivo: `combat_targeting.gd`

**2. Oclusión de targeting**
- Problema: Targetea enemigos detrás de paredes de `generador_ciudad`
- Solución: Raycast `intersect_ray` desde player a enemigo, si choca con capa mundo, descartar o penalizar -50% score
- Archivo: `combat_targeting.gd`

**3. Formación dinámica por cantidad**
- Problema: 10 enemigos en radio 2.2m se amontonan
- Solución: `formation_radius = 2.2 + (n-1)*0.3`, min_separation escala con n. Si n>6, 2 anillos (4 cerca, resto lejos)
- Archivo: `combat_formation.gd`

**4. Tokens con prioridad por amenaza**
- Problema: Enemigo lejos con token bloquea a uno a 1m
- Solución: `request()` con prioridad = threat_level + 1/distancia. En `update()`, si hay enemigo con prioridad alta sin token, robar token al de menor prioridad
- Archivo: `attack_token_manager.gd`

**5. Threat level real (no binario)**
- Problema: `threat_level_for` devuelve 1 o 0
- Solución: `threat_level = 1.0 - (time_left / total)` (más inminente = más amenaza) + bonus si es ataque pesado
- Archivo: `threat_system.gd`

**6. Hitboxes con forma, no solo distancia**
- Problema: `attack_range = 2.4` es esfera, no considera altura ni cono
- Solución: `attack_data` con `hitbox_type: esfera/caja/cono`, `altura`, `offset`. En `player.gd` usar `intersect_shape` con forma real
- Archivos: `attack_data.gd`, `player.gd`

**7. Pathfinding en APPROACH**
- Problema: Va en línea recta, se traba con bancos/farolas
- Solución: Usar `NavigationAgent3D` o al menos `move_and_collide` con slide. Si `is_on_wall()` en APPROACH, intentar sidestep 0.5m izq/der
- Archivo: `player.gd` `_state_approach`

**8. Indicador de objetivo AAA**
- Problema: MeshInstance3D simple
- Solución: Shader con pulso, flecha que apunta a cámara, cambio de color por amenaza, número de combo encima. Usar `ui/shaders/prism_logo.gdshader` como base
- Archivo: `controlador_leo.gd` `_actualizar_indicador_objetivo`

### 🟠 PRIORIDAD 2 - Transformación Combate (forma COMBATE)

**9. Cadena de 5 golpes con finisher**
- Actual: 3 golpes jab/cros/gancho
- Propuesta: 5 golpes: jab (0.4s) -> cros (0.5s) -> gancho (0.6s) -> codazo (0.5s) -> remate (1.0s, knockback grande). Cada uno con anim y VFX distinto
- Archivo: `player.gd` SPRINT

**10. Variantes por dirección**
- Idea: WASD + ataque = golpe direccional
  - W+ataque = uppercut (lanza al aire)
  - S+ataque = barrido bajo (tumba)
  - A/D+ataque = golpe lateral con desplazamiento
- Archivo: `player.gd` `_begin_attack` leer `_input_dir()`

**11. Counter con ventana perfecta**
- Actual: counter_range 2.8m, arc 0.2, duration 0.45s
- Mejora: 
  - Counter perfecto (justo en windup <0.15s) = stun 2s + combo no se rompe + slowmo 0.2s
  - Counter normal = stun 1.2s
  - Counter tardío = solo bloquea, no stunea
- Archivo: `combat_config.gd`, `player.gd` `_try_counter`

**12. Evade con i-frames visibles y punish**
- Actual: evade_speed 10m/s, iframes 0.25s
- Mejora: 
  - Evade perfecto (justo antes de impacto) = tiempo bala 0.3s + gadget cooldown -2s
  - Dejar afterimage en posición anterior
  - Evade hacia enemigo = ataque sorpresa (coste estamina)
- Archivo: `player.gd` `_start_evade`

**13. Special por forma**
- Actual: special genérico daño 40 si combo 2+
- Propuesta por forma:
  - COMBATE: Onda expansiva 4.5m, daño 40, stun 1.2s
  - VELOCISTA: 10 golpes en 1s a todos en radio
  - FUERZA: Pisoteo que rompe suelo
  - ACUATICA: Prisión de agua masiva
  - VUELO: Vendaval que tira enemigos
- Archivo: `combat_config.gd`, `player.gd` `_begin_special`

**14. Takedown contextuales**
- Actual: busca stunned target
- Mejora: 3 tipos
  - Suelo: remate en suelo (anim larga, invulnerable)
  - Aéreo: si enemigo en aire (uppercut previo), remate aéreo
  - Pared: si enemigo cerca de pared, lo estrella contra pared
- Archivo: `player.gd` `_find_stunned_target`

**15. Estamina de combate**
- Actual: `CostosEstamina.activar_ataque` pero no balanceado
- Propuesta:
  - jab: 5 estamina
  - cros: 8
  - gancho: 12
  - special: 30
  - evade: 15
  - Sin estamina: golpes 50% daño y sin knockback
- Archivo: `personaje/hud_transformacion/scripts/costos_estamina.gd`

### 🟡 PRIORIDAD 3 - Sinergia entre formas

**16. Combos entre transformaciones**
- Idea: Cambiar de forma mid-combo mantiene cadena
  - Ej: COMBATE jab -> VELOCISTA cros (más rápido) -> FUERZA gancho (más daño)
  - Cada forma aporta multiplicador distinto
- Archivo: `controlador_leo.gd` forma_cambiada

**17. Buffs de forma**
- COMBATE: +10% daño por cada enemigo derrotado en 10s (stack 5)
- VELOCISTA: Cada golpe aumenta velocidad 2% (stack 10)
- FUERZA: Cada golpe da escudo 5% vida
- ACUATICA: Golpes aplican EMPAPADO que potencia siguiente forma
- Archivo: `estadisticas_jugador.gd`

**18. Cancel de transformación**
- Permitir cancelar recovery de ataque con transformación (coste estamina alto)
- Ej: COMBATE recovery -> transformar a VELOCISTA y dash para reposicionarse
- Archivo: `player.gd` `_try_consume_buffered`

### 🔵 PRIORIDAD 4 - Feedback (lo que hace que se sienta AAA)

**19. Cámara de combate**
- Actual: `shake(0.5)` genérico
- Mejora:
  - Cada hit: shake corto 0.1s + FOV punch 2%
  - Finisher: shake 0.3s + slowmo 0.1s + FOV -5%
  - Counter perfecto: zoom 0.2s a enemigo
- Archivo: `personaje/base/camara/camara_jugador.gd`

**20. VFX por golpe**
- Actual: solo flash rojo en `_flash_damage`
- Propuesta:
  - jab: chispa pequeña
  - cros: onda blanca
  - gancho: onda grande + partículas
  - Usar `personaje/base/efectos/` existentes
- Archivo: `player.gd` `_apply_hit`

**21. SFX con pitch por combo**
- Actual: sin sonido de golpe en player.gd (solo en tests)
- Propuesta: pitch aumenta con combo_count (1.0, 1.05, 1.1, 1.2, 1.3) + reverb si hay muchos enemigos
- Archivo: `Audio/personaje/transformacion/combate/`

**22. Números de daño**
- Mostrar daño flotante encima de enemigo, color por tipo (blanco normal, amarillo crítico, azul agua, etc)
- Archivo: `ui/scenes/DialogueBalloon.tscn` como base para `DamageNumber.tscn`

**23. Ralentización estratégica**
- Hitstop: 0.05s freeze en cada hit que conecta (como Smash Bros)
- Slowmo en counter perfecto, evade perfecto, finisher
- Archivo: `player.gd` `_apply_hit` con `Engine.time_scale`

### 🟣 PRIORIDAD 5 - Enemigos

**24. Enemigos con roles**
- Actual: `enemigocombate.fbx` genérico
- Propuesta:
  - Grunt: ataca rápido, poca vida, pide token poco
  - Tanque: lento, mucha vida, rompe guardia, no se puede counterear normal
  - Tirador: no entra en formación, ataca a distancia
  - Jefe: usa tokens dobles, ataca aunque no tenga token
- Archivo: `cosas para enemigos/enemigos/`

**25. IA con feints**
- Enemigo hace windup falso (0.2s) y cancela para bait de counter
- Si jugador hace counter en feint, queda vulnerable 0.5s
- Archivo: `NPCs/Scripts/` (necesita crear)

**26. Sistema de miedo**
- Enemigos con <20% vida huyen o piden ayuda
- Si matas 3 rápido, resto se pone defensivo (más guardia, menos ataques)
- Archivo: `combat_manager.gd`

### ⚫ PRIORIDAD 6 - Arquitectura y Performance

**27. Separar controlador_leo.gd (6066 líneas)**
- Actual: todo en un archivo
- Propuesta:
  - `leo_movement.gd` - movimiento humano/velocista
  - `leo_combat.gd` - integración con combat_manager
  - `leo_water.gd` - agua y nado
  - `leo_transformation.gd` - cambio de formas
- Archivo: `personaje/base/scripts/controlador_leo.gd`

**28. Pool de afterimages**
- Actual: `duplicate()` del modelo cada golpe = GC
- Solución: Pool de 10 fantasmas reutilizables, solo cambian transform y material alpha
- Archivo: `velocidad/scripts/combate.gd`

**29. Hit detection optimizada**
- Actual: `intersect_shape` cada golpe con max 48 resultados
- Mejora: Usar `Area3D` en manos/pies con `monitoring`, solo activa en ACTIVE phase. Mucho más barato
- Archivo: `player.gd`, `ground_combat.gd`

**30. Tests automatizados**
- Ya tenés `_tests/prueba_freeflow_objetivo.gd` excelente
- Crear:
  - `prueba_combo_dano.gd` - verifica daño por etapa
  - `prueba_tokens.gd` - verifica que max 2 ataquen
  - `prueba_formacion.gd` - verifica que no se amontonen
- Archivo: `_tests/`

### 🟤 PRIORIDAD 7 - Input y Accesibilidad

**31. Remapeo completo**
- Ya tenés `action_move_forward` etc exportados, bien
- Falta: Permitir cambiar en UI `ajustes_controles.gd` y guardar en `AjustesControles`
- Archivo: `ui/scripts/ajustes_controles.gd`

**32. Asistencia de targeting**
- Opciones en `ajustes_jugabilidad.gd`:
  - Asistencia 0%: sin bonus current_target, sin hysteresis
  - Asistencia 50%: actual (0.05 bonus)
  - Asistencia 100%: radio 12m, ángulo 180°, bonus 0.2, auto-counter ventana +0.1s
- Archivo: `combat_config.gd`

**33. Controles alternativos**
- Soporte para: mantener ataque para ataque cargado, doble tap dirección + ataque = ataque especial direccional
- Archivo: `player.gd` input

### 🟢 PRIORIDAD 8 - Diseño de juego

**34. Tutorial de combate**
- Usar `DialogueBalloon` para enseñar:
  - 1 enemigo: aprende jab/cros/gancho
  - 2 enemigos: aprende cambio de objetivo con cámara
  - 3 enemigos: aprende counter y evade
  - 4+ enemigos: aprende tokens y formación
- Archivo: `misiones/gestor_misiones.gd`

**35. Recompensas de combate**
- Rango por encuentro: D, C, B, A, S basado en combo máximo, daño recibido, tiempo
- S = desbloquea skin o habilidad
- Archivo: `ui/scenes/PanelMision.tscn`

---

## 3. PLAN DE IMPLEMENTACIÓN RECOMENDADO

### Semana 1 - Core (hace que se sienta bien YA)
- [ ] #1 Targeting 3D + #2 Oclusión
- [ ] #7 Pathfinding APPROACH con sidestep
- [ ] #19 Cámara + #23 Hitstop
- [ ] #9 Cadena 5 golpes

### Semana 2 - Profundidad
- [ ] #11 Counter perfecto + #12 Evade perfecto
- [ ] #15 Estamina de combate balanceada
- [ ] #20 VFX + #21 SFX pitch
- [ ] #24 Enemigos con roles

### Semana 3 - Pulido AAA
- [ ] #3 Formación dinámica + #4 Tokens con prioridad
- [ ] #27 Separar controlador_leo.gd
- [ ] #34 Tutorial
- [ ] Tests

---

## 4. ARCHIVOS A MODIFICAR POR PRIORIDAD

**Para empezar hoy (1 archivo, 2 horas):**
`combat_targeting.gd` - Agregar raycast de oclusión y altura

**Para esta semana (5 archivos):**
- `combat_targeting.gd`
- `player.gd` (SPRINT 3->5 golpes)
- `combat_formation.gd`
- `camara_jugador.gd`
- `controlador_leo.gd` (indicador)

**Para refactor grande (10 archivos):**
Todos los de `transformacion ataque/scripts/combat/` + `controlador_leo.gd`

---

## 5. EJEMPLO DE CÓDIGO - Mejora #1 (Targeting con oclusión)

```gdscript
# En combat_targeting.gd, dentro de select_target, después de calcular score:
var space := player.get_world_3d().direct_space_state
var ray := PhysicsRayQueryParameters3D.create(origin + Vector3.UP, e.global_position + Vector3.UP)
ray.collision_mask = 1 # capa mundo
ray.exclude = [player.get_rid()]
var hit := space.intersect_ray(ray)
if not hit.is_empty():
    var dist_obst := origin.distance_to(hit.position)
    var dist_enemy := origin.distance_to(e.global_position)
    if dist_obst < dist_enemy - 0.5:
        score *= 0.3 # penalizar 70% si hay pared en medio
```

---

¿Con cuál querés que empiece? Te recomiendo #1 + #9 + #19 para que sientas la diferencia en 1 hora.
