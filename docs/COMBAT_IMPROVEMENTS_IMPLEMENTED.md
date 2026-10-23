# Mejoras de Combate Implementadas - Arena AI - 23/10/2026
## Branch: arena/cleanup - Commits: 03a6951 + nuevos

### ✅ 4 MEJORAS PRINCIPALES IMPLEMENTADAS (Semana 1)

#### 1. Targeting 3D + Oclusión - `combat_targeting.gd`
**Antes:**
- Solo distancia flat (Y=0), no consideraba altura
- Targeteaba a través de paredes
- Score solo alignment + distance + threat binario

**Ahora:**
- Distancia 3D con peso Y=0.4 (como FuerzaCombat): permite targetear enemigos en barco/muelle
- Penalización por altura: -0.15 por metro si diferencia >2m
- Raycast de oclusión: si hay pared entre jugador y enemigo (capa mundo), score *= 0.3 (-70%)
- Cache de space_state para performance
- Función `_check_occlusion` con detección de pared real (90% distancia)

**Impacto:** No más targetear enemigos detrás de edificios del generador_ciudad. Funciona en muelle, barco, escaleras.

---

#### 2. Pathfinding APPROACH con Sidestep - `player.gd`
**Antes:**
- `desired_vel = dirn * spd` directo, sin obstáculos
- Si había banco/farola, se quedaba trabado contra pared hasta que timer 1.5s expiraba
- No subía bordillos

**Ahora:**
- Detecta `is_on_wall()` y acumula `_approach_stuck_time`
- Después de 150ms trabado, elige sidestep izq/der:
  - Prueba `test_move` 0.8m a cada lado
  - Elige lado con más espacio o que más acerca al target
  - Aplica `desired_vel = (dirn*0.6 + sidestep*0.8).normalized() * spd`
- Si ambos lados bloqueados, intenta subir escalón con `_intentar_escalon_approach` (0.26m altura, como ControladorLeo)
- Resetea sidestep después de 0.75s para reevaluar
- Variables nuevas: `_approach_stuck_time`, `_approach_sidestep_dir`

**Impacto:** Ya no se traba con mobiliario de la ciudad. Sube bordillos de acera automáticamente.

---

#### 3. Cámara AAA + Hitstop + FOV Punch - `camera_rig.gd` + `camara_jugador.gd`
**Antes:**
- `camera_rig.gd`: shake simple random 0.12, sin FOV, sin hitstop
- `camara_jugador.gd`: solo vibración y lerp FOV, sin API FreeFlow

**Ahora en ambos:**
- `shake(amount)` con trauma (0.8*amount) + random Perlin-like
- `punch_fov(amount, duration)`: tween FOV -4 normal, -8 finisher, -10 special
- `hitstop(duration)`: freeze Engine.time_scale = 0.01 por 0.05s (0.08s finisher) - feel tipo Smash Bros
- `slowmo(duration, amount)`: para counters perfectos y finishers (0.25s, 0.4 time_scale)
- `zoom_to_enemy(enemy, duration)`: tween yaw hacia enemigo para counter perfecto
- Compatibilidad: ambas cámaras ahora están en grupo `camera_rig` y tienen misma API

**En `player.gd` `_apply_hit`:**
- Hitstop 0.05s normal, 0.08s finisher
- Shake escalado: 0.3 + combo*0.08, 0.8 finisher, 1.0 special
- FOV punch: -4 normal, -8 finisher, -10 special
- Slowmo 0.25s en finisher

**Impacto:** Cada golpe se SIENTE. Finisher con slowmo + shake grande + FOV.

---

#### 4. Cadena 5 Golpes con Finisher - `player.gd` + `attack_data.gd`
**Antes:**
- 3 golpes: jab (0.467s, impacto 0.233, daño 1.0, speed 1.25) -> cros (0.733, 0.147, 1.4, 1.2) -> gancho (0.633, 0.327, 1.7, 1.15)
- Sin costo estamina, sin tipo, sin finisher

**Ahora 5 golpes:**
1. jab: 0.467s, impacto 0.233, daño 1.0x, knockback 1.0, speed 1.35, stamina 5, type light
2. cros: 0.733s, 0.147, 1.4x, 1.3, 1.25, stamina 8, light
3. gancho: 0.633s, 0.327, 1.7x, 1.5, 1.20, stamina 12, medium
4. dos: 0.600s, 0.135, 1.5x, 1.4, 1.30, stamina 10, light (del set viejo, ahora parte de cadena)
5. remate: 0.633s, 0.327, 2.8x, 3.5, 0.90, stamina 18, heavy, finisher=true (mismo clip gancho pero lento y devastador)

**En `attack_data.gd`:**
- Nuevos campos: stamina_cost, attack_type (light/medium/heavy), is_finisher, hitstop_duration, camera_shake

**En `player.gd`:**
- `_build_attack_chain` ahora lee stamina, type, finisher, calcula hitstop y shake por tipo
- `_get_directional_attack()` preparado para variantes W=uppercut, S=sweep, A/D=lateral (estructura lista para implementar)

**Impacto:** Combo más largo, con ritmo: rápido-rápido-medio-rápido-LENTO devastador. Finisher con slowmo y VFX grande.

---

### 🔧 2 MEJORAS EXTRA BONUS (Core)

#### 5. Formación Dinámica - `combat_formation.gd`
**Antes:** Radio fijo 2.2m, todos en un anillo, se amontonan con 10 enemigos
**Ahora:**
- Radio dinámico: 2.2 + (n-4)*0.35, tope +2.5m
- Doble anillo si n>6: 40% cerca (radio dinámico), 60% lejos (radio+1.8m), offset medio paso para no alinearse
- Mantiene asignación persistente para evitar jitter

#### 6. Tokens con Prioridad - `attack_token_manager.gd`
**Antes:** Solo por tiempo de espera, sin prioridad
**Ahora:**
- `request(enemy, priority)` con prioridad
- `request_with_context(player_pos, threat_level)` calcula prioridad = threat*2 + (10-dist)*0.1
- `update()` elige por score = prioridad + wait_bonus*0.05 (evita starvation)
- Si cola tiene prioridad >1.5 y todos tokens ocupados, puede robar token al holder menos prioritario (si prioridad >2.0)

#### 7. Threat Level Real - `threat_system.gd`
**Antes:** Binario 1.0 o 0.0
**Ahora:** 0.2 + imminence*0.8 (0.2 al inicio windup, 1.0 al impacto) + bonus 0.3 heavy, 0.5 special. Rango 0.0-1.5

---

## 📊 Métricas de Performance

- `city_utils.aabb_modelo_por_cajas`: 2700ms -> 16ms (ya hecho)
- `city_scanner._datos_desde_estado`: 2-3s -> 70ms (ya hecho)
- `combat_targeting`: +1 raycast por enemigo, pero cacheado space_state, coste ~0.1ms por frame con 10 enemigos
- `approach sidestep`: 2 test_move por frame solo cuando is_on_wall(), despreciable
- `camera shake`: solo randf, sin coste
- `hitstop`: Engine.time_scale = 0.01, pausa física, sin coste extra

## 🧪 Cómo probar

1. Abrir `player.tscn` en `transformacion ataque/scenes/`
2. Probar targeting: poner 2 enemigos, uno detrás de pared de `generador_ciudad`, verificar que no lo targetea o penaliza
3. Probar approach: poner banco entre jugador y enemigo, verificar sidestep
4. Probar cámara: golpear, ver shake + FOV punch + hitstop
5. Probar combo 5 golpes: hacer 5 clicks, ver finisher lento con slowmo

## 📝 TODO Próximas fases

- [ ] Variantes direccionales W/S/A/D + ataque
- [ ] Counter perfecto con ventana (justo en windup <0.15s)
- [ ] Evade perfecto con tiempo bala
- [ ] VFX por golpe (chispa, onda)
- [ ] SFX pitch por combo
- [ ] Enemigos con roles
- [ ] Separar controlador_leo.gd 6066 líneas

## 💾 Espacio Workspace

- Working tree: 34MB (solo código combate, sin FBX)
- .git: 1.3GB
- Total: 1.3GB (antes 3.2GB)
- Sparse checkout activo para no llenar espacio
