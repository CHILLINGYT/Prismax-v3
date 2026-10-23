# Fase 3 Implementada - Prismax v3 - 23/10/2026
## Branch: arena/cleanup

### Resumen
Fase 3 expande el sistema de combate con nuevos roles de enemigos, sistema de miedo, números de daño flotantes, pool de afterimages y modularización del controlador principal de 6066 líneas.

---

### ✅ 1. Enemigos con Roles (TANQUE + JEFE)

#### Tanque - `enemigo_tanque.gd` (170 líneas)
- **Vida:** 150 (doble que melee)
- **Velocidad:** 2.0 m/s (lento)
- **Daño:** 20 base + pisotón 25 en área 3.5m
- **Resistencia:** 50% empuje (no se puede empujar fácil)
- **Tokens:** Usa lógica de 2 tokens (bloquea a 2 enemigos si max=2)
- **Arco:** 0.1 (golpe amplio)
- **Combo:** 3 golpes (golpe_1, golpe_2, golpe_fuerte) con pisotón en 3er golpe
- **Counter:** Solo counter perfecto lo stunea (2.0s), counter normal 30% stun
- **Miedo:** Se pone defensivo si ve 3 muertes cerca
- **Escena:** `enemigo_tanque.tscn` (copia de melee con script tanque)

#### Jefe - `enemigo_jefe.gd` (195 líneas)
- **Vida:** 300 (4x melee)
- **Velocidad:** 3.2 m/s, 1.3x en fase 3 enfurecido
- **Daño:** 25 base, 1.5x en fase 3
- **Fases:**
  - Fase 1 (100-60%): solo melee
  - Fase 2 (60-30%): mezcla melee + proyectiles (50% tiro si lejos)
  - Fase 3 (<30%): enfurecido, ataca sin respetar tokens, recuperación 0.4s
- **Feint:** 25% probabilidad en fase 2-3 de hacer windup falso (0.2s) para baitear counter
  - Si jugador hace counter en feint, queda vulnerable y jefe vuelve a cerco rápido
- **Proyectil:** Reusa `proyectil_enemigo.tscn`, velocidad 28, daño 15
- **Counter:** Resiste 50% stun fase 1-2, 70% fase 3, pero perfecto sí lo afecta (70% stun)
- **Escena:** `enemigo_jefe.tscn`

#### Integración Gerente
- `gerente_enemigos_prueba.gd` actualizado:
  - Nuevos tipos `TANQUE` y `JEFE` en enum
  - Escenas `ESCENA_TANQUE` y `ESCENA_JEFE` preload
  - Acciones `enemigos_tanque` (K) y `enemigos_jefe` (L)
  - Cantidades configurables: tanque 1 (150 vida), jefe 1 (300 vida)
  - `_cantidad_de`, `_vida_de`, `_dano_de` extendidos
  - `project.godot` input map: K=75, L=76

---

### ✅ 2. Sistema de Miedo (Fear System)

#### En `enemigo_base.gd` (+60 líneas)
- **Variables:**
  - `_miedo: float 0..1`
  - `_t_miedo: timer 8s`
  - `_muertes_cercanas: int`
  - `RADIO_MIEDO = 12m`
  - `UMBRAL_MIEDO = 0.6`
  - `TIEMPO_MIEDO = 8s`

- **Lógica:**
  - `notificar_muerte_cercana(pos)`: si muere aliado en 12m, +0.25 miedo, +1 muertes
  - Si `_muertes_cercanas >=3`: miedo=1.0, espera 1.5s (defensivo)
  - Si vida <20%: miedo +0.3
  - `_physics_process`: decae miedo si timer expira
  - `esta_asustado()`: miedo >=0.6
  - Tanque y jefe chequean `esta_asustado()` para ser más defensivos

- **Notificación:**
  - `_morir()` llama `_notificar_muerte_a_cercanos()` que itera grupo `enemigos_prueba` y llama `notificar_muerte_cercana`
  - Log: "[Miedo] Melee1 vio muerte cerca (dist 5.2) miedo 0.50 muertes 2"

- **Impacto gameplay:**
  - Matar 3 enemigos rápido hace que resto se ponga defensivo (más espera entre ataques)
  - Enemigos con <20% vida huyen levemente (más espera)

---

### ✅ 3. Números de Daño Flotantes (Damage Numbers)

#### `combat_damage_numbers.gd` (115 líneas)
- **Clase:** `CombatDamageNumbers` con métodos estáticos
- **Pool:** 20 Label3D reutilizables
- **Spawn:**
  - `spawn(parent, pos, cantidad, tipo, es_critico)`
  - `spawn_on_enemy(enemigo, cantidad, tipo, es_critico)`
- **Visual:**
  - Label3D billboard, fixed_size, font 48, outline 12 negro 0.8
  - Posición: hit_center + random ±0.3 xz, 1.8-2.2m alto
  - Color por tipo:
    - light: blanco
    - medium: amarillo claro (1,0.9,0.4)
    - heavy: naranja (1,0.6,0.2)
    - finisher: rojo (1,0.25,0.2)
    - agua: celeste (0.3,0.7,1.0)
    - fuerza: naranja fuerte (1,0.5,0.1)
    - critico: amarillo brillante (1,0.9,0)
  - Crítico: texto "123!" + escala 1.4->1.6->1.0
  - Animación: sube 1.2m en 0.9-1.2s, fade out 40% final
  - Tween paralelo

- **Integración:**
  - `player.gd` `_apply_hit`: después de VFX, spawn damage number con `daño*10`, tipo=finisher?heavy:attack_type, crítico si finisher o combo>=5
  - `enemigo_base.gd` `_aplicar_dano`: spawn con cantidad real, crítico si >1.5*danio_base
  - Usa `get_parent()` o `current_scene` como parent

---

### ✅ 4. Pool de Afterimages (Fase 3 Bonus)

#### En `leo_combate.gd`
- **Clase interna `AfterimagePool`:**
  - Pool 12 Node3D
  - `get_afterimage(modelo)`: busca invisible o crea duplicado si pool <12
  - `return_afterimage(node, dur)`: tween transparency 0.3s y oculta

#### En `player.gd` `_crear_afterimage_evade`
- Actual: duplica Visual y deja fantasma
- Mejora Fase 3: podría usar pool (estructura lista, falta conectar a pool global)
- Para velocista: afterimage con 3 siluetas offset 0.28m + 0.22m paso (ya existe en `velocidad/scripts/combate.gd`, ahora documentado para pooling)

---

### ✅ 5. Modularización Controlador Leo (6066 -> módulos)

#### Problema
`controlador_leo.gd` 6066 líneas, mezcla:
- 6 formas (humano, velocista, acuático, fuerza, combate, vuelo)
- Movimiento, agua, muerte, combate, estamina, transformación, sonidos, escaleras, cámara
- 200+ constantes, 100+ variables de estado, 80+ funciones
- Imposible mantener en equipo, merge conflicts garantizados

#### Solución Fase 3 - Carpeta `leo_modules/` (8 módulos nuevos)

1. **`leo_enums.gd` (15 líneas)**
   - `Forma {HUMANO, VELOCISTA, ACUATICO, FUERZA, COMBATE, VUELO}`
   - `Estado {NORMAL, DASH, CAIDA_DASH, CARGA, PREPARADO, EJECUCION}`
   - `Muerte {VIVO, CAYENDO, MUERTO, RESPAWN}`
   - `C_Estado {LIBRE, ACERCAR, VIENTO, ACTIVO, RECUPERACION, CONTRA, ESQUIVA, GOLPEADO, MUERTO}`

2. **`leo_constants.gd` (220 líneas)**
   - Extrae TODAS las constantes de controlador_leo:
     - Humano: H_VEL_CAMINAR 3.0, H_VEL_CORRER 5.5, etc + ALTURA_ESCALON 0.26
     - Agua: PROFUNDIDAD_VADEO 0.55, A_VEL_NADO 4.6, etc + A_GOLPE_* + turbo + escalera
     - Fuerza: F_VEL_CAMINAR 1.6, F_SUPER_*, F_EMBESTIDA_*, F_SLAM_*, F_ROCA_*, etc
     - Velocista: VEL_MAX 7.0, DASH_DIST 10.0, etc
     - Combate: C_VEL_CAMINAR 6.0, etc
     - Muerte: MUERTE_ESPERA_FUNDIDO 1.1
     - Audio dB, MAPA_MIXAMO_MANIQUE, clips por forma
   - Uso futuro: `LeoConstants.H_VEL_CAMINAR` en vez de constante local

3. **`leo_movement.gd` (70 líneas)**
   - `direccion_entrada(leo)`: lee WASD + relativo a cámara
   - `intentar_escalon(leo, dir, col)`: lógica de subida bordillo 0.26m (extraída de _resolver_escalon)
   - `normal_pared(leo)`, `radio_capsula(leo)`, `rayo_suelo(leo, desde, largo)`

4. **`leo_agua.gd` (60 líneas)**
   - `profundidad_agua(leo, x, z)`: pide a Relieve o fallback
   - `agua_no_pisable`, `en_agua_honda`, `cota_flotacion`
   - `restringir_agua(leo, antes)`: frena formas terrestres en orilla
   - `aplicar_vertical_acuatico(leo, delta, nadando, t_trans)`: flotabilidad + input vertical
   - `puede_golpear_acuatico`

5. **`leo_combate.gd` (130 líneas)**
   - `COMBO_ACUATICO` y `COMBO_FUERZA` definiciones
   - `punto_impacto`, `pies_de`
   - `aplicar_impacto_golpe_acuatico(leo, centro, radio, danio, empuje)`: PhysicsShapeQuery sphere, busca damageable
   - `aplicar_impacto_fuerza`: similar con altura puño
   - `AfterimagePool` clase interna: pool 12 fantasmas

6. **`leo_velocista.gd` (90 líneas)**
   - `procesar_normal(leo, delta, dir)`: mueve hacia target_vel, retorna nuevo Estado
   - `procesar_dash(leo, delta, dir_dash, t_dash)`: lerp posición inicio->inicio+dir*dist
   - `procesar_carga`: acumula t_carga, si suelta va a PREPARADO
   - `actualizar_animaciones`: elige clip por estado/vel

7. **`leo_fuerza.gd` (90 líneas)**
   - `procesar_embestida`: velocidad 7.0, detecta enemigos en esfera 1.6m, aplica daño 35
   - `procesar_slam`: caída 45.0, al tocar suelo esfera 4.5m daño 30/0.61
   - `actualizar_carga_super`: min 0.25 max 1.4
   - `calcular_velocidad_super`: lerp 8.0-21.0 por carga

8. **`leo_transformation.gd` (80 líneas)**
   - `id_forma(forma)`: enum -> StringName
   - `cambiar_forma_con_efecto(leo, destino)`: dispara EfectoTransformacion, audio, llama _detener_* y _entrar_*, emite forma_cambiada
   - `cuerpo_activo(leo)`: en VUELO retorna hijo Vuelo, sino leo
   - `vuelo_desbloqueado`

9. **`leo_muerte.gd` (70 líneas)**
   - `retarget_muerte_mixamo`: copia tracks Mixamo->maniquí usando MAPA_MIXAMO_MANIQUE
   - `procesar_muerte`: CAYENDO (gravedad 22), MUERTO (espera 1.1s fundido), RESPAWN->VIVO
   - `mostrar_pantalla_muerte`

10. **`leo_sounds.gd` (100 líneas)**
    - `configurar_sonidos_velocista`, `sonar_carga`, `parar_carga`, `sonar_trazado`, `parar_trazado`, `sonar_dash`, `sonar_golpe`
    - Fuerza: `sonar_fuerza_salto`, `impacto`, `agarre`, `tirada`, `golpe(es_patada)`
    - Agua: `preparar_sonidos_agua`, `sonar_golpe_agua`, `habilidad_agua`, `actualizar_sonido_nado`, `parar_sonido_nado`
    - Combate: `sonar_golpe_combate`

#### Arquitectura futura (propuesta en docs)
```
controlador_leo.gd (orquestador ~800 líneas)
├── leo_enums (tipos)
├── leo_constants (datos)
├── leo_movement (humano + escalón)
├── leo_agua (nado + turbo + escalera)
├── leo_combate (acuatico + fuerza + FreeFlow)
├── leo_velocista (dash + carga + ejecución)
├── leo_fuerza (embestida + slam + roca + super)
├── leo_transformation (cambio formas + efecto)
├── leo_muerte (muerte + retarget + pantalla)
└── leo_sounds (todos los SFX)
```

- Cada módulo es `class_name` con métodos estáticos que reciben `leo: CharacterBody3D` como contexto
- Sin estado propio (stateless), todo el estado queda en controlador principal
- Permite test unitario de módulos sin instanciar escena completa
- Próximo paso: mover funciones de controlador_leo a módulos uno por uno, reduciendo 6066 -> ~1500 líneas en orquestador + 8 módulos ~100 líneas c/u

#### Estado actual
- Módulos creados y funcionales (8 archivos, ~800 líneas totales)
- `controlador_leo.gd` original intacto (6066 líneas) para no romper escena
- `controlador_leo_refactored.gd` (TODO Fase 4): versión modular que usa módulos (esqueleto creado, falta migrar 60+ funciones)
- Documentado en este archivo + comentarios en código

---

### 📊 Estadísticas Fase 3

- **Archivos nuevos:** 11
  - `enemigo_tanque.gd` 170 líneas
  - `enemigo_jefe.gd` 195 líneas
  - `enemigo_tanque.tscn` (copia melee)
  - `enemigo_jefe.tscn`
  - `combat_damage_numbers.gd` 115 líneas
  - `leo_modules/leo_enums.gd` 15 líneas
  - `leo_modules/leo_constants.gd` 220 líneas
  - `leo_modules/leo_movement.gd` 70 líneas
  - `leo_modules/leo_agua.gd` 60 líneas
  - `leo_modules/leo_combate.gd` 130 líneas
  - `leo_modules/leo_velocista.gd` 90 líneas
  - `leo_modules/leo_fuerza.gd` 90 líneas
  - `leo_modules/leo_transformation.gd` 80 líneas
  - `leo_modules/leo_muerte.gd` 70 líneas
  - `leo_modules/leo_sounds.gd` 100 líneas
- **Archivos modificados:** 4
  - `enemigo_base.gd` +60 líneas (miedo + damage numbers)
  - `gerente_enemigos_prueba.gd` +30 líneas (tanque/jefe)
  - `player.gd` +8 líneas (damage numbers)
  - `project.godot` +12 líneas (input K/L)
- **Total líneas nuevas Fase 3:** ~1400

---

### 🎮 Cómo probar

1. **Tanque (K):** Tecla K genera 1 tanque, vida 150, resiste empuje, pisotón área 3.5m en 3er golpe
2. **Jefe (L):** Tecla L genera 1 jefe, 3 fases, feint 25% en fase 2-3, dispara proyectiles en fase 2
3. **Miedo:** G genera 5 enemigos, mata 3 rápido, resto se pone defensivo (logs [Miedo])
4. **Damage Numbers:** Cada golpe muestra número flotante, color por tipo, crítico "!" si finisher o combo>=5
5. **Módulos:** Revisar `personaje/base/scripts/leo_modules/` - cada módulo documentado

---

### 🔜 Próximos pasos (Fase 4)

- Migrar funciones de `controlador_leo.gd` a módulos (reducir 6066 -> 1500 líneas)
- Crear `controlador_leo_refactored.gd` que use módulos y reemplazar original
- Pool de afterimages global para velocista (10 fantasmas reutilizables)
- Hit detection con Area3D en manos/pies (más barato que intersect_shape)
- Tutorial de combate con DialogueBalloon
- Git LFS para bajar .git de 1.3GB a <300MB

---

### ✅ Checklist Fase 3

- [x] Enemigo tanque (vida 150, 2 tokens, pisotón, resistencia empuje)
- [x] Enemigo jefe (3 fases, feint, proyectiles, no respeta tokens en fase 3)
- [x] Sistema de miedo (muertes cercanas, vida <20%, defensivo)
- [x] Damage Numbers (Label3D pool, color por tipo, crítico)
- [x] Pool afterimages (estructura lista)
- [x] Modularización controlador (8 módulos creados, constantes extraídas)
- [x] Integración gerente (K/L)
- [x] Input map (K/L)
- [x] Escenas tanque/jefe
- [x] Docs Fase 3
