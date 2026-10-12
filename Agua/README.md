# Sistema de agua del pueblito

Paquete extraído en copia desde `res://coastal/` para reutilizar el sistema acuático original. Los archivos originales no se modificaron. Compatible con Godot 4.7.2 (proyecto fuente); requiere Godot 4.2+ con Renderer Forward+ recomendado.

## Contenido

- `Scenes/CoastalZone.tscn`: zona costera original, copiada con rutas internas dirigidas a `Agua/`. Incluye la superficie oceánica, sus parámetros/shader/material y textura normal de ripples embebida; también incluye arena, 46 algas, casas de playa y muelle como parte de la escena original. No depende de esos edificios/objetos para dibujar el agua; se conservaron por fidelidad de la escena fuente.
- `Scenes/MarineLife.tscn`, `Scripts/marine_life.gd`: animación puramente visual opcional de barcos, peces, algas y boyas por grupos (`marine_boat`, `marine_fish`, `marine_kelp`, `marine_algae`). Es la escena de vida marina original, con recursos geométricos/materiales embebidos. Se recomienda usarla solo si se copian/crean dichos objetos y grupos.
- `Scripts/underwater_effect.gd`: transición visual al sumergir la cámara. La escena costera incluye su CanvasLayer/overlay shader.
- `Scripts/explore_camera.gd`: cámara libre de demostración, prescindible en la ciudad; eliminar el nodo `ExploreCamera` al usar cámara propia.
- `Shaders/water_surface.gdshader`, `Shaders/underwater_overlay.gdshader`: fuentes de referencia extraídas de los shaders embebidos. La escena mantiene las copias embebidas que preservan la apariencia original.
- `Textures/sand_tile.png`: textura necesaria para la plataforma de arena costera.
- `Scenes/WaterTest.tscn`: prueba aislada mínima empaquetada con luz y entorno.

No se detectaron colisiones de agua, sonidos acuáticos ni complemento requerido para la superficie. El agua es visual; sus olas son desplazamiento de vértices y normal animada, no física de oleaje.

## Instalación e integración

1. Copiar la carpeta completa `Agua` dentro de `res://` del proyecto ciudad, de modo que las rutas queden `res://Agua/...`.
2. Abrir/importar el proyecto y dejar que Godot importe `Textures/sand_tile.png`.
3. Para la zona costera completa de muestra, instanciar `res://Agua/Scenes/CoastalZone.tscn`. Para solo el océano alrededor de Terrain3D, abrir esta escena y conservar el nodo `Water` (con su `PlaneMesh` y material original); ocultar o retirar `Sand`, `Seaweed`, `BeachHouses` y `Dock` si se desea una escena solo de agua. La extensión base del plano es 592 × 508 unidades; su centro está desplazado X=216, Y=-2, Z=0 respecto del nodo raíz. Al instanciar alrededor de la isla, ajustar posición raíz y escala/extensión de malla según convenga. El efecto submarino tiene un rectángulo de activación exportado (por defecto `Rect2(-60, -256, 572, 512)`) y nivel `-2`; ajustar esos exports si cambia tamaño o altura.
4. Para efecto submarino, mantener `UnderwaterEffect` y una `WorldEnvironment` con `Environment` asignado. El script ajusta temporalmente niebla, contraste y saturación del recurso Environment compartido; no cambiará ajustes globales del proyecto por sí solo, pero el efecto opera sobre el Environment de la escena anfitriona mientras la cámara esté sumergida.
5. Comprobar `Rendering > Renderer` en Forward+ o Mobile con soporte de shaders espaciales. El shader lee `hint_depth_texture` y usa `TIME`; el renderizador Compatibility puede cambiar el resultado o no ser compatible. No hay ajustes globales adicionales requeridos observados.
6. Configurar una luz direccional y un WorldEnvironment/iluminación ambiental. `WaterTest.tscn` lleva un entorno/luz de referencia para comprobar el aspecto, no modifica `project.godot`. En la ciudad, conservar la iluminación propia y comparar reflejos/respuesta especular; el shader mezcla reflejo de cielo estilizado y Fresnel, no requiere ReflectionProbe.
7. Verificar ejecutando `WaterTest.tscn`: el color muestra transición de claro a profundo por profundidad de escena, Fresnel, transparencias, normales con movimiento y oleaje. La malla base mide 592 × 508; la superficie está en Y=-2. Para extenderla en océano abierto, escalar el plano o aumentar `PlaneMesh.size` y subdivisiones en una copia, teniendo presente que alterar tamaño/repetición puede cambiar el patrón visual.

## Parámetros visuales originales

Shader espacial embebido en `CoastalZone.tscn`: shallow `vec3(0.40,0.70,0.79)`, deep `vec3(0.03,0.20,0.38)`, alfa 0.10–0.78, profundidad 16, reflejo estilizado `vec3(0.60,0.72,0.84)`, amplitud 0.13, frecuencia 0.05 y velocidad 1.0. Normales de ripple 128×128 RGB, generadas como ImageTexture embebida. Flujo de UV doble con velocidades 0.020/0.014 y -0.013/-0.024, normal especular con roughness 0.14 y specular 0.45. El overlay submarino usa tinte azul y se desvanece según distancia al centro de pantalla.

## Dependencias y límites

- Las rutas de escenas/scripts/textura fueron redirigidas dentro de `Agua`; las mallas, shaders y ripple están serializados en la escena. La escena de prueba está diseñada para no referenciar `coastal/`, `demo/`, Terrain3D ni edificios del juego original.
- `WaterTest` proporciona luz/Environment de prueba. El aspecto exacto depende del renderer, exposición/tonemapping, cámara, iluminación y geometría bajo la superficie; la composición de reflejo es estilizada y puede verse diferente si el proyecto anfitrión tiene otros ajustes.
- No hay colisión de superficie ni interacción física con personajes/barcos. El movimiento de barcos/peces/plantas de `MarineLife` es animación visual y depende de grupos de escena globales; añadir esa escena no agrega modelos por sí mismo.
- Las casas, muelle, arena y algas que están dentro de `CoastalZone` son contenido del escenario costero, no requisito de render para el plano Water. Se conservan en la escena original empaquetada por fidelidad; pueden omitirse al integrar solo el océano.
- El formato original usa `gd_scene format=4` y fue creado en Godot 4.7.2; conviene probar/importar con la versión exacta del proyecto destino (Godot 4.2+), pues una versión anterior puede necesitar guardar/conversión. Se recomienda conservar una copia del paquete antes de abrirlo en un Godot más antiguo.
