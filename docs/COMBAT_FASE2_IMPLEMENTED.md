# Fase 2 Implementada - Combate Perfeccionado
**Branch:** arena/cleanup
**Commits:** 0778852 + 5cb3ae3
**Workspace:** 34MB código (sparse) + 1.3GB .git = 1.3GB total

## ✅ Implementado en esta fase

### 1. Variantes Direccionales (WASD + Ataque)
**Archivo:** `player.gd` `_get_directional_attack()` + `_crear_ataque_direccional()`

- **Sin dirección:** Combo normal 5 golpes (jab/cros/gancho/dos/remate)
- **W + Ataque (forward_dot >0.7):** `uppercut`
  - Anim: gancho
  - Daño 1.3x, knockback vertical 0.5x + stun aéreo 0.6s
  - Speed 0.9x, windup 1.1x
  - Cámara shake 0.6, hitstop 0.07s
  - Uso: Lanza enemigo al aire, prepara combo aéreo

- **S + Ataque (forward_dot <-0.7):** `sweep`
  - Anim: dos
  - Rango 1.3x, knockback 1.8x, stun 0.8s (tumba)
  - Speed 0.85x
  - Uso: Barrido bajo, tumba a varios enemigos

- **A/D + Ataque (right_dot >0.7):** `lateral`
  - Anim: cros
  - Approach speed 1.4x, daño 1.1x, knockback 1.2x
  - Speed 1.15x
  - Uso: Golpe con desplazamiento lateral, reposiciona en combate

**Cómo se activa:**
```gdscript
var dir_attack := _get_directional_attack() # lee _input_dir() vs _camera_dir()
if dir_attack != "":
    _attack = _crear_ataque_direccional(dir_attack, _attack)
```

---

### 2. Counter Perfecto
**Archivo:** `player.gd` `_try_counter()`

**Antes:**
- Counter genérico: range 2.8m, arc 0.2, duration 0.45s, stun 1.2s
- Sin diferencia entre timing bueno y malo

**Ahora:**
- Ventana perfecta: `time_left <0.15s && >0.02s` (130ms antes de impacto)
- **Counter perfecto:**
  - Stun 2.0s vs 1.2s normal
  - Slowmo 0.2x por 0.35s
  - Shake 1.2 vs 0.5 normal
  - FOV punch -10 vs -4
  - Zoom a enemigo 0.25s
  - Print "[COMBAT] ¡COUNTER PERFECTO!"
- **Counter normal:** Stun 1.2s, shake 0.5, FOV -4

**Impacto:** Recompensa timing preciso, feel tipo Sekiro/Arkham.

---

### 3. Evade Perfecto
**Archivo:** `player.gd` `_start_evade()` + `_crear_afterimage_evade()`

**Antes:**
- Evade speed 10m/s, duration 0.35s, iframes 0.25s
- Sin bonus por timing

**Ahora:**
- Ventana perfecta: `time_left <0.2s && >0.02s` con enemigo <3.8m
- **Evade perfecto:**
  - Duration 1.3x (0.35s -> 0.455s)
  - Iframes = duration completa (vs 0.25s)
  - Gadget cooldown -2s
  - Slowmo 0.25x por 0.4s (tiempo bala)
  - Shake 0.6
  - Afterimage en posición anterior (fantasma que se desvanece 0.3s)
  - Print "[COMBAT] ¡EVADE PERFECTO!"
- **Evade normal:** Shake 0.2

**Impacto:** Evade no es solo defensivo, es ofensivo (tiempo bala para contraatacar).

---

### 4. VFX de Combate
**Archivo nuevo:** `combat_vfx.gd` (CombatVFX)

**Funciones:**
- `spawn_hit_vfx(parent, pos, attack_type, is_finisher, combo_count)`
  - light: chispa pequeña 0.08m + combo*0.02m, color amarillo, emissive 2.0, tween scale 2x + fade 0.15s
  - medium: onda 1.2m blanca
  - heavy: onda 1.8m naranja
  - finisher: onda 2.5m roja + 6 chispas grandes que vuelan 1.5m + UP 0.5m, fade 0.4s

- `spawn_counter_vfx(parent, pos, is_perfect)`
  - Perfecto: onda 2.0m azul + chispas grandes
  - Normal: onda 1.2m amarilla

**Integración en `player.gd` `_apply_hit`:**
```gdscript
var hit_pos := t.global_position + UP*1.0
if t.has_method("get_hit_center"): hit_pos = t.call("get_hit_center")
CombatVFX.spawn_hit_vfx(vfx_parent, hit_pos, attack_type, is_finisher, combo_c)
```

**Performance:** MeshInstance3D temporal con tween que se auto-libera, sin partículas GPU (compatible con tu setup actual).

---

### 5. SFX con Pitch por Combo
**Archivo:** `player.gd` `_play_combat_sfx()`

- Busca `SFX_Combate` o `AudioCombate` o crea temporal
- Pitch escala: 1.0 + combo*0.05
  - Combo 0: 1.0
  - Combo 3: 1.15
  - Finisher: 1.3
  - Heavy: 1.15
  - Clamp 0.9-1.4
- Si no hay stream, usa `SonidoUI.reproducir("golpe_%s" % attack_type)`
- Fallback compatible con tu sistema de audio actual

**Impacto:** Cada golpe suena más agudo, finisher suena épico.

---

### 6. Mejoras Extra de Fase 1 (ya committeadas)

- **Formación dinámica:** Radio 2.2 + (n-4)*0.35, doble anillo si >6
- **Tokens con prioridad:** threat*2 + distancia, robo si >2.0
- **Threat real:** 0.2 + imminence*0.8 + bonus heavy/special

---

## 🎮 Cómo probar Fase 2

1. **Direccionales:** En combate, mantené W y atacá = uppercut que lanza. S+ataque = barrido que tumba. A/D+ataque = lateral con dash.
2. **Counter perfecto:** Esperá a que enemigo haga windup, justo cuando va a golpear (<0.15s), presioná counter. Debe hacer slowmo + zoom + stun largo.
3. **Evade perfecto:** Igual pero con evade. Debe hacer tiempo bala + afterimage + gadget cooldown.
4. **VFX:** Cada golpe deja chispa/onda. Finisher deja 6 chispas grandes + onda roja 2.5m.
5. **SFX:** Cada golpe suena más agudo, finisher más agudo aún.

## 📊 Estado Actual

- **Archivos modificados:** 9 archivos, +629 líneas, -71 líneas
- **Nuevos:** `combat_vfx.gd`
- **Workspace:** 34MB (sparse) - sin FBX de 681MB
- **Commits:** 
  - 5cb3ae3 Fase 1 (targeting, approach, cámara, combo 5)
  - 0778852 Fase 2 (direccionales, counter/evade perfecto, VFX/SFX)

## 🚀 Próximo: Fase 3 (si querés seguir)

- Enemigos con roles (grunt/tanque/tirador)
- Separar controlador_leo.gd 6066 líneas
- HUD combo con números de daño flotantes
- Tutorial de combate
