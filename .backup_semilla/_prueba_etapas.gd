extends Node
## DIAGNÓSTICO ETAPA POR ETAPA: reproduce la secuencia exacta de `generar_ciudad()`
## llamando a sus etapas una a una y, tras cada una, apunta el ESTADO del
## RandomNumberGenerator del generador, los tamaños de sus listas de trabajo y sus
## contadores. Lo hace dos veces (en frío y en caliente) y compara:
## la primera etapa que difiera es la que consume azar de forma no controlada.
##
## Se ejecuta sin ventana:  godot --headless --path <proj> <esta escena>

const RUTA_MUNDO := "res://ziba/escenas/ziba_prototipo.tscn"
const RUTA_LOG := "res://.backup_semilla/log_etapas.txt"
const LISTAS := ["_paredes", "_linea_central", "_linea_discontinua", "_pasos", "_marcas",
		"_vegetacion", "_prefabs", "_bolardos", "_sumideros", "_alcantarillas", "_cornisas",
		"_aires", "_hojas_puerta", "_marcos_puerta", "_familias", "_modelos", "_categorias",
		"_macetas", "_reposeras", "_sombrillas", "_palmeras"]

var _mundo: Node = null
var _ciudad: Node = null
var _log := ""
var _carpeta := ""


func _ready() -> void:
	await get_tree().process_frame
	var escena: PackedScene = load(RUTA_MUNDO)
	_mundo = escena.instantiate()
	_ciudad = _mundo.get_node_or_null("Ciudad")
	if _ciudad == null:
		print("sin nodo Ciudad")
		get_tree().quit(1)
		return
	_ciudad.set("generar_al_iniciar", false)
	get_tree().root.add_child.call_deferred(_mundo)
	await get_tree().process_frame
	await get_tree().process_frame
	_carpeta = String(_ciudad.call("_resolver_carpeta"))

	var r1 := _ronda("FRÍA (primera del proceso)")
	var r2 := _ronda("CALIENTE (segunda del proceso)")

	_linea("=== COMPARACIÓN ETAPA A ETAPA ===")
	var diferencia := ""
	for i in mini(r1.size(), r2.size()):
		var a: Dictionary = r1[i]
		var b: Dictionary = r2[i]
		var campos := ["semilla", "estado", "listas", "est", "hijos"]
		var dif: Array[String] = []
		for c: String in campos:
			if String(a[c]) != String(b[c]):
				dif.append(c)
		if dif.is_empty():
			_linea("OK   %-18s semilla=%s estado=%s" % [a["nombre"], a["semilla"], a["estado"]])
		else:
			_linea("DIF  %-18s -> %s" % [a["nombre"], ", ".join(dif)])
			for c: String in dif:
				_linea("        fría     %s: %s" % [c, String(a[c]).substr(0, 400)])
				_linea("        caliente %s: %s" % [c, String(b[c]).substr(0, 400)])
			if diferencia == "":
				diferencia = String(a["nombre"])
	_linea("=== %s ===" % ("SIN DIFERENCIAS" if diferencia == "" else "PRIMERA ETAPA QUE DIFIERE: " + diferencia))
	var f := FileAccess.open(RUTA_LOG, FileAccess.WRITE)
	if f != null:
		f.store_string(_log)
		f.close()
	print(_log)
	get_tree().quit(0)


## Una ronda completa: la misma secuencia de llamadas que `generar_ciudad()`, con
## una foto del estado tras cada etapa.
func _ronda(nombre: String) -> Array:
	_linea("")
	_linea("========== RONDA %s ==========" % nombre)
	_ciudad.call("limpiar_ciudad")
	var rng: RandomNumberGenerator = _ciudad.get("_rng")
	rng.seed = SemillaMundo.semilla_de("ciudad")
	var salida: Array = []
	var i := 0
	salida.append(_foto("00 tras sembrar", rng))
	i += 1
	_ciudad.call("_escanear", _carpeta)                       ; salida.append(_foto("01 escanear", rng))
	_ciudad.call("_construir_listas")                          ; salida.append(_foto("02 listas", rng))
	_ciudad.call("_cargar_vegetacion_extra")                   ; salida.append(_foto("03 texturas", rng))
	_ciudad.call("_preparar_trazado")                          ; salida.append(_foto("04 trazado", rng))
	_ciudad.call("_crear_contenedores")                        ; salida.append(_foto("05 contenedores", rng))
	_ciudad.set("_est", {"prefabs": 0, "modulares": 0, "props": 0, "vegetacion": 0, "arboles": 0,
			"parques": 0, "bancos": 0, "macetas": 0, "parcelas": 0, "plazas": 0,
			"parcelas_vacias": 0, "marcas": 0, "suelos": 0, "tramos": 0, "portales": 0,
			"palmeras": 0, "sombrillas": 0, "reposeras": 0, "arboles_costa": 0,
			"arbustos_costa": 0, "ventanas": 0, "ventanas_luz": 0})
	_ciudad.call("_configurar_escena")                         ; salida.append(_foto("06 escena", rng))
	_ciudad.call("_generar_suelo")                             ; salida.append(_foto("07 suelo", rng))
	_ciudad.call("_generar_calles")                            ; salida.append(_foto("08 calles", rng))
	_ciudad.call("_generar_manzanas")                          ; salida.append(_foto("09 manzanas", rng))
	_ciudad.call("_generar_paseo_costero")                     ; salida.append(_foto("10 paseo", rng))
	_ciudad.call("_generar_playa")                             ; salida.append(_foto("11 playa", rng))
	_ciudad.call("_vegetacion_costera")                        ; salida.append(_foto("12 vegetacion costa", rng))
	_ciudad.call("_generar_mobiliario")                        ; salida.append(_foto("13 mobiliario", rng))
	_ciudad.call("_volcar_vegetacion")                         ; salida.append(_foto("14 volcar veget", rng))
	_ciudad.call("_volcar_lotes")                              ; salida.append(_foto("15 volcar lotes", rng))
	_ciudad.call("_volcar_macetas")                            ; salida.append(_foto("16 macetas", rng))
	_ciudad.call("_volcar_playa")                              ; salida.append(_foto("17 volcar playa", rng))
	_ciudad.call("_volcar_ventanas")                           ; salida.append(_foto("18 ventanas", rng))
	_ciudad.call("_construir_colisiones_vegetacion")           ; salida.append(_foto("19 colisiones veg", rng))
	_ciudad.call("_generar_peatones")                          ; salida.append(_foto("20 peatones", rng))
	return salida


func _foto(nombre: String, rng: RandomNumberGenerator) -> Dictionary:
	var listas := {}
	for k: String in LISTAS:
		var v: Variant = _ciudad.get(k)
		if v is Dictionary:
			listas[k] = (v as Dictionary).size()
		elif v is Array:
			listas[k] = (v as Array).size()
		elif v != null:
			listas[k] = v
	var est: Dictionary = _ciudad.get("_est")
	var raiz := _mundo.get_node_or_null("Ciudad/CiudadGenerada")
	return {
		"nombre": nombre,
		"semilla": str(rng.seed),
		"estado": str(rng.state),
		"listas": JSON.stringify(listas),
		"est": JSON.stringify(est),
		"hijos": str(raiz.get_child_count()) if raiz != null else "-1",
	}


func _linea(t: String) -> void:
	_log += t + "\n"