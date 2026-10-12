# Inventario y trazabilidad

## Elementos acuáticos hallados en el proyecto

- `res://coastal/coastal_zone.tscn`: escena principal de costa. Nodo `Water` (`MeshInstance3D`) usa plano subdividido de 592×508, colocado en (216,-2,0), con ShaderMaterial espacial. Malla de arena ArrayMesh, alfombra de algas (46 piezas), muelle, casas costeras y `UnderwaterEffect` están en la misma escena.
- Shader oceánico y normal de ondulación: subrecursos embebidos en la escena, sin archivo separado original. El vertex shader mueve olas sinusoidales. El fragment shader lee depth texture para gradiente/transparencia por espesor, Fresnel, normal perturbada por dos muestreos animados, y reflexión estilizada del cielo.
- Shader de overlay submarino: otro subrecurso canvas_item dentro de escena.
- `res://coastal/underwater_effect.gd`: detecta cámara bajo nivel y dentro de rectángulo; funde overlay y modifica fog/adjustment de WorldEnvironment.
- `res://coastal/explore_camera.gd`: cámara de vuelo de demostración (no es necesaria si el juego tiene cámara propia).
- `res://coastal/marine_life.tscn` y `marine_life.gd`: barcos/peces/plantas decorativos y movimiento visual asociado. Geometrías/materiales de esta escena están embebidos.
- `res://assets/generated/sand_tile.png`: textura requerida por arena; copiada y ruta corregida.
- `res://node_3d.tscn`: anfitrión fuente contiene WorldEnvironment y DirectionalLight3D con sombras. La escena también instancia Terrain3D, Village, Scenery y MarineLife; esos sistemas no son requisito de la superficie de agua. La referencia de entorno/luz se documenta/reproduce en la prueba, no se copia el mapa anfitrión.
- El pozo de `village.tscn` incluye un `Water` local como detalle decorativo, no pertenece al océano.
- No se hallaron shaders externos/addons/sonidos/colisiones vinculados a la superficie oceánica.

## Paquete

`Scenes/CoastalZone.tscn` + tres scripts internos + textura arena tienen rutas internas autocontenidas. Shaders portables también están en `Shaders/`, pero la escena conserva sus subrecursos originales para evitar cambiar aspecto. `MarineLife.tscn` es módulo adicional opcional.

## Prueba

`Scenes/WaterTest.tscn` instancia solo `Agua/Scenes/CoastalZone.tscn`, con luz direccional y Environment básico de soporte. Revisar visualmente en Forward+; cámara de exploración incluida en zona permite volar. No usar esta escena de prueba como sustituto de la escena ciudad.
