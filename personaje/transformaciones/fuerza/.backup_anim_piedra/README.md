# Respaldo y herramientas: levantado de la roca (forma Fuerza)

Esta carpeta está prefijada con un punto a propósito: Godot la ignora por completo
(no la indexa, no registra sus clases ni sus UID). Aquí no hay nada que el juego
cargue en marcha.

## Contenido

| Archivo | Qué es |
| --- | --- |
| `FuerzaUniversal_original.tres` | La librería COMPLETA de animaciones tal y como estaba antes de rehacer los clips de la roca. Es la fuente que usa `hornear_roca.gd`. |
| `controlador_leo.gd.original` | Copia del controlador antes del cambio de la roca (por si hay que comparar). |
| `BrazosIKRoca.gd.original` | Copia del IK de brazos antes de añadirse el modo roca (`fijar_roca`, `punto_agarre`). |
| `hornear_roca.gd` | Script que regenera los cuatro clips de la roca dentro de la librería viva. Se ejecuta a mano (ver abajo). |

## Qué se cambió y por qué

Los clips originales de la roca (`RockLift`, `RockCarry`, `RockCarryWalk`,
`RockThrow`) estaban construidos hueso a hueso y la muñeca salía doblada ~55°,
la roca flotaba con un desplazamiento fijo delante del pecho y la subida no tenía
fases. Ahora:

- `RockLift` (2.0 s): agacharse con el torso adelante → manos a los lados de la
  piedra en el suelo → tirón con esfuerzo → la roca sube por delante (arco) y
  termina centrada ENCIMA de la cabeza. Sin saltos: el último fotograma es
  idéntico al primer fotograma de `RockCarry`.
- `RockCarry` (1.2 s, bucle): respiración leve de la carga con la roca arriba.
- `RockCarryWalk` (el largo exacto del `Walk` original, bucle): piernas del Walk
  original + torso de carga + la roca sobre la cabeza con un balanceo corto.
- `RockThrow` (0.62 s): el primer 0.12 s mezcla desde la pose de carga exacta
  (así el lanzamiento no altera nada de la pose levantada) y después sigue el
  clip de tiro original.

Los brazos de TODOS los clips se hornean resolviendo las mismas funciones que el
IK usa en el juego (`FuerzaBrazosIK.punto_agarre` + `resolver`): la mano cae
siempre sobre la superficie de la piedra (radio + palma) y la muñeca queda recta.
Por eso animación e IK nunca se pelean.

## Cómo regenerar los clips

1. Abre esta carpeta y copia `hornear_roca.gd` como `res://.godot/ziva_execute_script.gd`… o
   simplemente ejecútalo con la herramienta de scripts de Ziva pegando su contenido
   (el script está pensado para correr en modo headless, `extends SceneTree`).
2. Antes de tocarlo, comprueba que las constantes de la cabecera coinciden con las
   del controlador (`res://personaje/base/scripts/controlador_leo.gd`, bloque
   `F_ROCA_*`, y las funciones `_centro_roca_sk` / `_peso_ik_roca`). **Los dos
   lados deben llevar los mismos números**: el horneado y el IK convierten los
   mismos valores a poses.
3. El script guarda directo en
   `res://personaje/transformaciones/fuerza/animations (1)/libraries/FuerzaUniversal.tres`
   y es idempotente (siempre parte de `FuerzaUniversal_original.tres`).

Las constantes compartidas (espejo entre horneado y controlador):

| Constante | Valor | Significado |
| --- | --- | --- |
| `R_SK` / `F_ROCA_TAM` | 0.404 (sk) / 0.8 (mundo) | Radio de la roca. `R_SK = F_ROCA_TAM / escala_del_esqueleto` (≈1.98). |
| `Z0` / `F_ROCA_Z0` | 0.62 | Dónde nace/apoya la roca (espacio del esqueleto, hacia adelante). |
| `U_SUBIDA`/`U_FIN` | 0.55 / 0.90 | Tramo del levantamiento en el que la roca sube (0..1). |
| `B_CARRY`/`L_CARRY` | 0.10 / −0.05 | Mezcla Idle↔Crouch del cuerpo en la pose de carga. |
| `CARRY_H` / `F_ROCA_CARRY_H` | 1.13 | Altura del centro de la roca sobre la cabeza, en radios. |
| Guarda de cabeza | radio + 0.10 (sk) ≈ ×1.25 | Empuje radial mínimo alrededor de la cabeza. |
| Polos del codo | 2.2 / 0.0 / 0.2 | salida / abajo / atrás. |
| Balanceo del carry | 0.008 | `sin(fase · TAU)` lateral mientras se anda. |