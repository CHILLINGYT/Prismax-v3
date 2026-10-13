class_name GloboDialogo extends CanvasLayer

## GLOBO DE DIÁLOGO DEL PROYECTO (para Dialogue Manager 4.1.0).
##
## Es el "balloon" que Dialogue Manager espera: expone `start(recurso, cue, estados)`
## exactamente como pide su `_start_balloon()` (addons/dialogue_manager/
## dialogue_manager.gd) y se coloca con `DialogueManager.show_dialogue_balloon(...)`.
## Reutiliza el nodo `DialogueLabel` del propio addon (el que escribe/trocea el texto)
## y no toca ningún sistema del juego: es una capa de interfaz.
##
## CÓMO FUNCIONA
##   · Un solo mensaje a la vez: cada línea del .dialogue es una burbuja (`dialogue_line`).
##   · Clic izquierdo sobre el panel o el texto -> mensaje siguiente.
##   · Último mensaje: aparece el botón `Entendido` y el clic sobre el texto NO cierra
##     nada; sólo el botón termina la conversación.
##   · Nunca avanza por tiempo (no se usa el `time` de las líneas).
##   · Mientras está abierto: se bloquean los ataques del jugador (el clic pertenece al
##     diálogo) y el ratón vuelve a su modo anterior al cerrar. La conversación NO se
##     cierra si el jugador se aleja: sigue hasta que la termine él.
##   · Repetible sin límite: no guarda ningún estado de "completado".

## Se emite cuando la conversación termina (botón `Entendido`), esté quien esté escuchando.
signal cerrado

## Mientras esté abierto, ningún otro nodo recibe entrada no manejada.
@export var will_block_other_input: bool = true

## Acción de teclado para avanzar/cerrar (el clic izquierdo funciona siempre).
@export var next_action: StringName = &"ui_accept"

## El recurso de diálogo (lo inyecta DialogueManager).
var dialogue_resource: DialogueResource

## Estados extra que puede consultar el diálogo (el propio globo va siempre primero).
var temporary_game_states: Array = []

@onready var _catcher: Control = $Catcher
@onready var _nombre: RichTextLabel = $Catcher/PanelInferior/Marco/Margen/Columna/Nombre
@onready var _texto: DialogueLabel = $Catcher/PanelInferior/Marco/Margen/Columna/Texto
@onready var _pista: Label = $Catcher/PanelInferior/Marco/Margen/Columna/Pie/Pista
@onready var _entendido: Button = $Catcher/PanelInferior/Marco/Margen/Columna/Pie/Entendido
@onready var _fondo: PanelContainer = $Catcher/PanelInferior/Marco

var _cue: String = ""
var _raton_previo: int = Input.MOUSE_MODE_CAPTURED
var _ultimo: bool = false
var _cerrando: bool = false

## La línea actual. Al quedar nula (fin del diálogo) se cierra el globo.
var dialogue_line: DialogueLine:
	set(value):
		if value != null:
			dialogue_line = value
			_mostrar(value)
		else:
			_cerrar()
	get:
		return dialogue_line


func _ready() -> void:
	_fondo.visible = false
	_entendido.visible = false
	_entendido.pressed.connect(_on_entendido_pressed)
	_catcher.gui_input.connect(_on_catcher_gui_input)


func _exit_tree() -> void:
	# Si el globo desaparece por cualquier motivo (cambio de escena, recarga), se
	# devuelve el control al jugador: nunca se queda sin ratón ni sin ataques.
	_avisar_jugador(false)
	Input.mouse_mode = _raton_previo


# ------------------------------------------------------------------ API del globo

## Arranca la conversación. Firma EXIGIDA por Dialogue Manager (`_start_balloon`).
func start(recurso: DialogueResource = null, cue: String = "", estados: Array = []) -> void:
	temporary_game_states = [self] + estados
	if recurso != null:
		dialogue_resource = recurso
	_cue = cue
	if dialogue_resource == null:
		push_error("[GloboDialogo] Sin recurso de diálogo.")
		_cerrar()
		return
	_raton_previo = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_avisar_jugador(true)
	dialogue_line = await dialogue_resource.get_next_dialogue_line(_cue, temporary_game_states)


# ------------------------------------------------------------------ pintado

## Vuelca una [DialogueLine] en la interfaz. Un mensaje por vez.
func _mostrar(linea: DialogueLine) -> void:
	if _cerrando:
		return
	_fondo.visible = true
	_nombre.visible = not linea.character.is_empty()
	_nombre.text = linea.character
	# El último mensaje es el que el .dialogue marca con la etiqueta [#fin].
	_ultimo = linea.has_tag("fin") or linea.next_id in ["end", "end!", ""]
	_texto.dialogue_line = linea
	_texto.type_out()
	_entendido.visible = _ultimo
	# En el último mensaje el clic no cierra: el texto avisa de que hay que pulsar.
	_pista.text = "Pulsa «Entendido» para terminar" if _ultimo else "Clic izquierdo para continuar"
	if _ultimo:
		_entendido.grab_focus()
	else:
		_catcher.grab_focus()


# ------------------------------------------------------------------ avance y cierre

## Mensaje siguiente (si ya es el último, no hace nada: lo cierra el botón).
func _avanzar() -> void:
	if _cerrando or _ultimo:
		return
	dialogue_line = await dialogue_resource.get_next_dialogue_line(dialogue_line.next_id, temporary_game_states)


## Cierre definitivo: deja de mostrar y devuelve el control al jugador.
func _cerrar() -> void:
	if _cerrando:
		return
	_cerrando = true
	_fondo.visible = false
	_entendido.visible = false
	Input.mouse_mode = _raton_previo
	_avisar_jugador(false)
	cerrado.emit()
	queue_free()


## Bloquea/desbloquea los ataques del jugador durante el diálogo. El bloqueo se levanta
## en el propio controlador un fotograma después, para que el clic que cierra el
## diálogo no se cuele como ataque.
func _avisar_jugador(bloquear: bool) -> void:
	for nodo in get_tree().get_nodes_in_group("player"):
		if nodo.has_method("bloquear_ataques_por_dialogo"):
			nodo.bloquear_ataques_por_dialogo(bloquear)


# ------------------------------------------------------------------ entrada

func _unhandled_input(_evento: InputEvent) -> void:
	# Sólo el globo maneja la entrada no manejada mientras está abierto (igual que el
	# globo de ejemplo del addon): así el clic no llega a los controles del juego.
	if will_block_other_input:
		get_viewport().set_input_as_handled()


func _on_catcher_gui_input(evento: InputEvent) -> void:
	if not (evento is InputEventMouseButton):
		return
	var clic := evento as InputEventMouseButton
	if not clic.pressed or clic.button_index != MOUSE_BUTTON_LEFT:
		return
	get_viewport().set_input_as_handled()
	if _ultimo:
		# En el último mensaje el clic sobre el texto o el panel NO cierra el diálogo:
		# el cierre es cosa del botón `Entendido`.
		return
	_avanzar()


func _on_entendido_pressed() -> void:
	get_viewport().set_input_as_handled()
	_cerrar()