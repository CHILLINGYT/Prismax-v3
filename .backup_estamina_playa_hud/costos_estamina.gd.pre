class_name CostosEstamina
extends RefCounted

## ================== SISTEMA CENTRALIZADO DE ESTAMINA (costes y colores) ==================
##
## ÚNICA fuente de verdad de LOS COSTES y de LOS COLORES de la barra: aquí viven
## las tablas de movimiento, ataques y habilidades de TODAS las formas. Las
## mecánicas no llevan números propios: preguntan a estas funciones estáticas
## ("¿me alcanza?" -> gastá), así que rebalancear = tocar SÓLO este archivo.
##
## UNIDADES:
##   · MOVIMIENTO   -> puntos por SEGUNDO de acción sostenida (se multiplican por delta).
##   · ATAQUES      -> puntos por EJECUCIÓN (una vez, cuando el golpe arranca de verdad).
##   · HABILIDADES  -> puntos por EJECUCIÓN (activación). Un "turbo" además lleva
##                     gasto sostenido propio en MOVIMIENTO.
##
## REGLAS que estas tablas activan:
##   · Sin estamina: no arrancan ataques, combos, habilidades, dash/turbo nuevos
##     (probar_gasto devuelve false y el llamador NO ejecuta la acción).
##   · Un ataque o habilidad cobra UNA sola vez (activación real), nunca también
##     al confirmar el impacto.
##   · Los gastos sostenidos nunca bloquean (no hay energía negativa): consumen
##     lo que quede y la regeneración se apaga mientras consuman.
##   · El caminar es siempre posible y NO cuesta estamina (sólo el correr/esprint
##     con SHIFT, el turbo y el vuelo consumen al moverse). Si la estamina llega
##     a cero se bloquea el correr/esprintar/turbo, nunca el movimiento básico.
##
## La estamina VIVE en `EstadisticasJugador` (una por personaje, igual que la vida
## y la resistencia). Este archivo sólo dice CUÁNTO cuesta cada cosa y cómo pintar
## la barra de cada personaje.

## Máximo de referencia (el máximo real por forma lo publica EstadisticasJugador;
## con un perfil `stamina_max` en `perfiles` se puede ajustar por personaje).
const MAXIMA := 100.0
## Con la estamina en este valor (o menos) la forma se considera AGOTADA.
const UMBRAL_AGOTADA := 0.5
## Velocidad horizontal (m/s) a partir de la cual el movimiento consume: quieto
## o contra una pared no gasta.
const UMBRAL_MOVIMIENTO := 0.3

## Aspecto de la barra de estamina, VERTICAL y a la DERECHA del dial de vida (se
## construye en código en el HUD, como el resto del diseño). EST_ANCHO = grosor
## (horizontal); EST_ALTO = longitud (vertical).
const EST_ANCHO := 20.0
const EST_ALTO := 150.0
## Separación (px) entre el borde derecho del dial (aro de vida) y la barra, que
## queda INMEDIATAMENTE a la derecha de la vida.
const EST_SEPARACION := 6.0
const EST_BORDE := 2.0
## Suavizado del relleno (1/s): mayor = más rápido. Nunca salta de golpe.
const EST_SUAVIZADO := 7.0
const EST_COLOR_FONDO := Color(0.05, 0.06, 0.09, 0.72)

## Color del RELLENO de la barra por personaje (pedido):
##   Max humano = violeta rosado (híbrido violeta/rosa con blanco y negro).
##   velocista = rojo intenso; pes = azul intenso; tanque = naranja intenso;
##   combate = negro/gris oscuro; aguila = blanco plateado.
const COLORES := {
	&"humano": Color(0.76, 0.45, 0.95, 1.0),
	&"velocista": Color(0.96, 0.16, 0.12, 1.0),
	&"pes": Color(0.10, 0.46, 1.0, 1.0),
	&"tanque": Color(1.0, 0.49, 0.08, 1.0),
	&"combate": Color(0.16, 0.17, 0.20, 1.0),
	&"aguila": Color(0.94, 0.96, 1.0, 1.0),
}
## Color del BORDE cuando el relleno necesita contraste (oscuro -> borde claro).
const COLOR_BORDE := Color(0.08, 0.06, 0.12, 0.95)
const BORDES := {
	&"combate": Color(0.88, 0.91, 0.96, 1.0),
}

## MOVIMIENTO: puntos por SEGUNDO de cada acción sostenida, por forma.
## CAMINAR NO APARECE: caminar no cuesta estamina en ninguna forma (así el reloj
## de gasto no se reinicia y la estamina puede regenerarse mientras se anda).
const MOVIMIENTO := {
	&"humano": {&"correr": 6.0},
	&"velocista": {&"esprintar": 9.0, &"supervelocidad": 14.0},
	&"pes": {&"correr": 5.0, &"nadar": 3.5, &"nadar_rapido": 7.5, &"turbo": 16.0},
	&"tanque": {&"correr": 4.0},
	&"combate": {&"correr": 7.0},
	&"aguila": {&"correr": 5.5, &"volar": 5.5, &"volar_boost": 11.0, &"volar_picada": 7.5},
}

## ATAQUES: puntos por EJECUCIÓN (golpe que arranca de verdad).
const ATAQUES := {
	&"humano": {},
	&"velocista": {&"golpe": 5.0},
	&"pes": {&"golpe": 4.0},
	&"tanque": {&"golpe": 3.5, &"patada": 5.0},
	&"combate": {&"golpe": 4.0},
	&"aguila": {&"golpe": 4.0, &"pluma": 2.5},
}

## HABILIDADES: puntos por EJECUCIÓN (activación real, después de sus chequeos).
const HABILIDADES := {
	&"humano": {},
	&"velocista": {&"dash": 10.0, &"supervelocidad": 10.0},
	&"pes": {&"proyectil": 8.0, &"esfera": 14.0, &"prision": 16.0, &"oleada": 25.0, &"turbo": 12.0},
	&"tanque": {&"embestida": 12.0, &"pisotón": 18.0, &"roca": 22.0, &"super_salto": 10.0},
	&"combate": {},
	&"aguila": {&"despegue": 10.0, &"palmazo": 12.0, &"garras": 15.0},
}

# =============================================================== Consultas
## Recurso de un personaje subiendo por los ancestros (funciona desde el HUD, el
## cuerpo del vuelo, sus habilidades, etc.). null si no hay sistema (pruebas
## aisladas): en ese caso nada se bloquea ni se cobra.
static func estadisticas_de(nodo: Node) -> EstadisticasJugador:
	var p: Node = nodo
	while p != null:
		var est := p.get_node_or_null("Estadisticas") as EstadisticasJugador
		if est != null:
			return est
		p = p.get_parent()
	return null

## Coste de una clave en una de las tres tablas para un id de forma (0 si no existe).
static func costo_movimiento(id: StringName, clave: StringName) -> float:
	return float((MOVIMIENTO.get(id, {}) as Dictionary).get(clave, 0.0))

static func costo_ataque(id: StringName, clave: StringName) -> float:
	return float((ATAQUES.get(id, {}) as Dictionary).get(clave, 0.0))

static func costo_habilidad(id: StringName, clave: StringName) -> float:
	return float((HABILIDADES.get(id, {}) as Dictionary).get(clave, 0.0))

## ¿Le alcanza la estamina de su forma ACTUAL para una clave de esta tabla?
static func puede(nodo: Node, tabla: Dictionary, clave: StringName) -> bool:
	var est := estadisticas_de(nodo)
	if est == null:
		return true
	return est.puede_gastar(float((tabla.get(est.forma_actual(), {}) as Dictionary).get(clave, 0.0)))

## Gasto de EJECUCIÓN: cobra UNA vez y devuelve si se ejecutó. Sin sistema
## (o con la clave sin coste) devuelve true: el llamador sigue igual.
static func activar(nodo: Node, tabla: Dictionary, clave: StringName) -> bool:
	var est := estadisticas_de(nodo)
	if est == null:
		return true
	return est.probar_gasto(
			float((tabla.get(est.forma_actual(), {}) as Dictionary).get(clave, 0.0)), clave)

static func activar_ataque(nodo: Node, clave: StringName) -> bool:
	return activar(nodo, ATAQUES, clave)

static func activar_habilidad(nodo: Node, clave: StringName) -> bool:
	return activar(nodo, HABILIDADES, clave)

static func puede_habilidad(nodo: Node, clave: StringName) -> bool:
	return puede(nodo, HABILIDADES, clave)

## Igual que `puede_habilidad` para las claves de ATAQUES (chequeo sin cobrar).
static func puede_ataque(nodo: Node, clave: StringName) -> bool:
	return puede(nodo, ATAQUES, clave)

## Clave de habilidad acuática por índice (1..4 = orden de ABIL_AGUA del pez).
const AGUA_CLAVES := [&"proyectil", &"esfera", &"prision", &"oleada"]
static func clave_habilidad_agua(idx: int) -> StringName:
	if idx < 1 or idx > AGUA_CLAVES.size():
		return &"proyectil"
	return AGUA_CLAVES[idx - 1]

## Gasto SOSTENIDO por fotograma: la cantidad sale del coste por segundo por delta.
## Nunca bloquea (clamp a 0) y mantiene apagada la regeneración mientras consuma.
static func gastar_movimiento(nodo: Node, clave: StringName, delta: float) -> void:
	var est := estadisticas_de(nodo)
	if est == null or delta <= 0.0:
		return
	var c := costo_movimiento(est.forma_actual(), clave) * delta
	if c > 0.0:
		est.gastar_continuo(c)

## ¿La forma activa (la del sistema de ese nodo) está agotada?
static func agotada(nodo: Node) -> bool:
	var est := estadisticas_de(nodo)
	if est == null:
		return false
	return est.stamina_agotada()

# =============================================================== Colores
static func color_de(id: StringName) -> Color:
	return COLORES.get(id, COLORES[&"humano"])

static func borde_de(id: StringName) -> Color:
	return BORDES.get(id, COLOR_BORDE)