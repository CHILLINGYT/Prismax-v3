# Modularización Controlador Leo - Fase 3

## Problema original
`controlador_leo.gd` tenía **6066 líneas** mezclando:
- 6 formas (humano, velocista, acuático, fuerza, combate, vuelo)
- Movimiento, agua, muerte, combate, estamina, transformación, sonidos, escaleras, cámara
- 200+ constantes, 100+ variables, 80+ funciones
- Imposible mantener en equipo

## Solución Fase 3 - Módulos

### Arquitectura
```
controlador_leo.gd (orquestador ~800 líneas futuro)
├── leo_enums.gd - Enums Forma, Estado, Muerte, C_Estado
├── leo_constants.gd - Todas las constantes agrupadas por forma
├── leo_movement.gd - Movimiento humano + escalón + rayos
├── leo_agua.gd - Agua, nado, turbo, escalera, restricción
├── leo_combate.gd - Combate acuatico/fuerza/FreeFlow + AfterimagePool
├── leo_velocista.gd - Dash, carga, ejecución, animaciones
├── leo_fuerza.gd - Embestida, slam, roca, supersalto
├── leo_transformation.gd - Cambio formas + cuerpo_activo + efecto
├── leo_muerte.gd - Muerte, retarget Mixamo, pantalla
└── leo_sounds.gd - Todos los SFX por forma
```

### Principios
- **Stateless modules:** Métodos estáticos que reciben `leo: CharacterBody3D` como contexto
- **Sin estado propio:** Todo estado queda en controlador principal (forma, _t_dash, etc)
- **Testeable:** Cada módulo se puede testear sin instanciar escena completa
- **Sin dependencias circulares:** Módulos solo dependen de leo_constants y leo_enums

### Uso ejemplo
```gdscript
# Antes (en controlador_leo.gd, 50 líneas mezcladas)
func _procesar_humano(delta):
    var dir = _direccion_entrada()
    # ... 40 líneas de movimiento, escalón, animación ...

# Después (modular)
func _procesar_humano(delta):
    var dir = LeoMovement.direccion_entrada(self)
    LeoMovement.intentar_escalon(self, dir, get_last_slide_collision())
    # ... delega a módulo
```

### Migración progresiva
1. **Fase 3 (hecho):** Crear módulos con constantes y funciones extraídas, documentar
2. **Fase 4 (pendiente):** Mover funciones de controlador_leo a módulos una por una
   - Semana 1: movimiento humano + agua
   - Semana 2: velocista + fuerza
   - Semana 3: combate + muerte + transformación
3. **Resultado:** controlador_leo.gd 6066 -> ~1500 líneas orquestador + 8 módulos ~100 líneas c/u = más mantenible, menos conflictos

### Estado actual
- [x] 10 módulos creados (800 líneas totales)
- [x] Constantes extraídas (220 líneas)
- [x] Enums extraídos (15 líneas)
- [x] Funciones base extraídas (movimiento, agua, combate, velocista, fuerza, transformación, muerte, sonidos)
- [ ] Migrar 60+ funciones restantes de controlador_leo.gd (Fase 4)
- [ ] Crear controlador_leo_refactored.gd que use módulos (esqueleto)
- [ ] Reemplazar original cuando refactored esté completo y testeado

### Beneficios
- **Mantenibilidad:** Cada forma en su módulo, fácil encontrar código
- **Colaboración:** 2 devs pueden trabajar en fuerza y agua sin conflicto
- **Performance:** Módulos stateless, sin overhead
- **Tests:** Cada módulo testeable unitariamente
- **Documentación:** Cada módulo documentado con su responsabilidad

### Próximos pasos
- Ver `docs/COMBAT_FASE3_IMPLEMENTED.md` para detalles de implementación
- Ver `controlador_leo_refactored.gd` (cuando exista) para ejemplo de orquestador modular
