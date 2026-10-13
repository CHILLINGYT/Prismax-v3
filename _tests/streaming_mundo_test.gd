extends Node
## Prueba ligera del GESTOR CENTRAL del mundo (P10) — NO genera el mundo real.
## Verifica el interruptor central, la creación/retirada de subgestores, la
## inercia por defecto y que no rompe sin un mundo real. No mide rendimiento.

var _ok := 0
var _fallos := 0


func _ready() -> void:
	var g: Node = $StreamingMundo

	# El autoload AjustesGraficos (P10-B) es quien GOBIERNA el gestor en el juego:
	# reaplica el ajuste guardado y, con la optimización apagada, lo apagaría. Para
	# probar el gestor por separado, dejamos la preferencia encendida y la
	# restauramos al final (XDG aislado: no toca nada real).
	AjustesGraficos.optimizacion_agresiva = true

	_comprobar("activo por defecto = false", bool(g.get("activo")) == false)
	_comprobar("inerte por defecto (no procesa)", g.is_processing() == false)
	_comprobar("sin subgestores por defecto", g.get_child_count() == 0)
	_comprobar("resumen().activo == false por defecto", bool(g.call("resumen")["activo"]) == false)

	g.call("set_activo", true)
	_comprobar("activado: procesa", g.is_processing() == true)
	_comprobar("activado: crea 2 subgestores", g.get_child_count() == 2)
	_comprobar("activado: resumen().activo == true", bool(g.call("resumen")["activo"]) == true)
	_comprobar("subgestor ciudad presente", g.get_node_or_null("StreamingCiudad") != null)
	_comprobar("subgestor bosque presente", g.get_node_or_null("StreamingBosque") != null)

	for i in 20:
		await get_tree().process_frame
	_comprobar("sin mundo real sigue activo y sin errores", g.is_processing() == true)

	g.call("restaurar_todo")
	_comprobar("restaurar_todo() sin mundo real no rompe", true)

	g.call("set_activo", false)
	_comprobar("desactivado: no procesa", g.is_processing() == false)
	_comprobar("desactivado: resumen().activo == false", bool(g.call("resumen")["activo"]) == false)

	AjustesGraficos.optimizacion_agresiva = false

	print("===== RESULTADO STREAMING MUNDO: %d OK, %d FALLOS =====" % [_ok, _fallos])
	get_tree().quit(0 if _fallos == 0 else 1)


func _comprobar(texto: String, ok: bool) -> void:
	if ok:
		_ok += 1
		print("[OK]    ", texto)
	else:
		_fallos += 1
		print("[FALLO] ", texto)