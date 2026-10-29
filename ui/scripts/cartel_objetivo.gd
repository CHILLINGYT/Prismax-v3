class_name CartelObjetivo
extends CanvasLayer

## CARTEL DE OBJETIVO INICIAL: «habla con el hombre en la plaza».
##
## Es un cartel de interfaz (2D, fijo en pantalla) que vive en la ESCENA DEL MUNDO
## (ziba_prototipo.tscn), no dentro de la ciudad generada: por eso no le afecta la
## regeneración procedural (sigue oculto o visible como estaba, sin reaparecer).
##
## ARRIBA AL CENTRO, como en la referencia visual del objetivo: el conjunto va dentro
## de un MarginContainer de pantalla completa y el cartel se apoya arriba con
## `size_flags_vertical = SHRINK_BEGIN` y se centra con `SHRINK_CENTER`, así se adapta
## a cualquier resolución y a cualquier relación de aspecto sin recortarse. El tamaño
## del texto es proporcional porque la interfaz del juego se dibuja sobre el lienzo
## escalado (1152x648 con estiramiento `canvas_items`), igual que el resto del HUD.
##
## CUÁNDO APARECE:
## El mundo se instancia durante la pantalla de carga y todavía NO es la escena en
## curso, así que el cartel arranca oculto y se muestra en el primer fotograma en el
## que `get_tree().current_scene` es la raíz del mundo: justo cuando el jugador entra
## a jugar. Nunca se ve en el menú ni en la pantalla de carga (esta escena no es
## parte de ellas).
##
## CUÁNDO DESAPARECE:
## Sólo con el evento real de interacción: el NPC (`NPCEstaticoObrero`) emite su señal
## `dialogo_iniciado` cuando el globo de Dialogue Manager llega a abrirse, es decir con
## la tecla E dentro del rango válido y con la conversación empezada. Acercarse, mirar
## al NPC o pulsar E fuera de rango no emiten nada, así que no lo ocultan. Una vez
## oculto no vuelve a aparecer en toda la partida (bandera `_resuelto`), ni al cerrar
## el diálogo, ni al alejarse, ni al volver a hablar con Iván. No hay ningún temporizador.

## Texto exacto del cartel (el nodo Texto del .tscn lo repite).
const TEXTO := "habla con el hombre en la plaza"

## Raíz del mundo que contiene este cartel (su `owner` dentro de la escena).
var _raiz: Node = null
## NPC del objetivo (se busca por clase, sin depender del nombre del nodo).
var _npc: NPCEstaticoObrero = null
## Objetivo ya completado: el cartel no vuelve a mostrarse en esta partida.
var _resuelto := false


func _ready() -> void:
	# Arranca OCULTO: mientras el mundo se prepara detrás de la pantalla de carga no
	# debe verse nada. Lo muestra `_process` en cuanto el mundo es la escena en curso.
	visible = false
	_raiz = owner if owner != null else get_parent()
	_conectar_objetivo()


func _process(_delta: float) -> void:
	# Sólo hace falta hasta que el jugador entra al mundo: en cuanto la raíz del mundo
	# pasa a ser la escena en curso, se muestra el cartel y este proceso se detiene.
	if get_tree().current_scene != _raiz:
		return
	set_process(false)
	if not _resuelto:
		visible = true
		_animar_entrada()


## Presentación (no decide nada): el cartel baja unos píxeles y se funde al entrar.
const ENTRADA_ACTIVA := true
func _animar_entrada() -> void:
	var cartel := get_node_or_null("Margen/Cartel") as Control
	if not ENTRADA_ACTIVA or cartel == null:
		return
	cartel.modulate.a = 0.0
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(cartel, "modulate:a", 1.0, 0.45).set_delay(0.25)
	# El MarginContainer recoloca al hijo: se anima su margen superior.
	var margen := get_node_or_null("Margen") as MarginContainer
	if margen != null:
		var arriba := margen.get_theme_constant("margin_top")
		margen.add_theme_constant_override("margin_top", arriba - 14)
		tw.tween_method(func(v: int) -> void: margen.add_theme_constant_override("margin_top", v),
				arriba - 14, arriba, 0.5).set_delay(0.25).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


## Busca al NPC del objetivo y se engancha a su señal de conversación iniciada. La
## búsqueda es por CLASE (no por nombre de nodo) para no depender de cómo se llame ni
## de dónde esté colgado dentro del mundo.
func _conectar_objetivo() -> void:
	_npc = _buscar_npc(_raiz)
	if _npc == null:
		push_warning("[CartelObjetivo] No se encontró al NPC del objetivo: el cartel no se ocultará al hablar con él.")
		return
	if not _npc.dialogo_iniciado.is_connected(_al_iniciar_dialogo):
		_npc.dialogo_iniciado.connect(_al_iniciar_dialogo)


func _buscar_npc(raiz: Node) -> NPCEstaticoObrero:
	if raiz == null:
		return null
	var pila: Array[Node] = [raiz]
	while not pila.is_empty():
		var n: Node = pila.pop_back()
		if n is NPCEstaticoObrero:
			return n
		for h in n.get_children():
			pila.append(h)
	return null


## Objetivo completado: la conversación con Iván EMPEZÓ de verdad. Se oculta y no se
## vuelve a mostrar en lo que queda de partida.
func _al_iniciar_dialogo() -> void:
	if _resuelto:
		return
	_resuelto = true
	visible = false