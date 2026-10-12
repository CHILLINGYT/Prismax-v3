extends Node

## Suite de la CONFIGURACIÓN GRÁFICA (perfiles Baja / Media / Alta).
##
## Comprueba la API del autoload AjustesGraficos, que el panel de pausa refleja el
## perfil, que la preferencia se guarda en disco, que aplicar un perfil NO toca el
## recurso Environment de la escena (trabaja sobre una copia) y que deja en paz lo
## que no le corresponde (geometría que no es vegetación).
##
## Uso: godot --headless --path . _tests/prueba_perfiles_graficos.tscn

const ESCENA_PAUSA := "res://ui/scenes/PauseMenu.tscn"
const RUTA_CFG := "user://ajustes_graficos.cfg"

var _ok := 0
var _fallos := 0

func _ready() -> void:
	print("===== PERFILES GRÁFICOS =====")
	_esperar_frames(2)

	var calidad_inicial: int = AjustesGraficos.calidad

	_check("existe el autoload AjustesGraficos", AjustesGraficos != null)
	_check("expone poner_calidad", AjustesGraficos.has_method("poner_calidad"))
	_check("expone pasar_calidad", AjustesGraficos.has_method("pasar_calidad"))
	_check("expone texto_calidad", AjustesGraficos.has_method("texto_calidad"))
	_check("hay 3 perfiles (baja/media/alta)", AjustesGraficos.PERFILES.size() == 3)

	# --- 1) La escala de render 3D cambia con el perfil ---------------------
	AjustesGraficos.poner_calidad(0)
	await _esperar_frames(2)
	var vp := get_viewport()
	var escala_baja: float = vp.scaling_3d_scale
	var lod_baja: float = vp.mesh_lod_threshold
	_check("BAJA deja la escala 3D por debajo de 1 (%.2f)" % escala_baja, escala_baja < 0.95)
	_check("BAJA es el texto del perfil", AjustesGraficos.texto_calidad() == "BAJA")

	AjustesGraficos.poner_calidad(1)
	await _esperar_frames(2)
	var escala_media: float = vp.scaling_3d_scale
	_check("MEDIA queda entre BAJA y 1.0 (%.2f)" % escala_media,
			escala_media > escala_baja and escala_media < 1.0)
	_check("MEDIA es el texto del perfil", AjustesGraficos.texto_calidad() == "MEDIA")

	AjustesGraficos.poner_calidad(2)
	await _esperar_frames(2)
	_check("ALTA devuelve la escala a 1.0 (%.2f)" % vp.scaling_3d_scale,
			is_equal_approx(vp.scaling_3d_scale, 1.0))
	_check("ALTA devuelve el LOD original (%.1f)" % vp.mesh_lod_threshold,
			is_equal_approx(vp.mesh_lod_threshold, 1.0))
	_check("ALTA es el texto del perfil", AjustesGraficos.texto_calidad() == "ALTA")
	_check("BAJA usa LOD más agresivo que ALTA", lod_baja > vp.mesh_lod_threshold)

	# --- 2) El entorno se toca en una COPIA, no en el recurso de la escena ---
	var mundo := WorldEnvironment.new()
	var env_escena := Environment.new()
	env_escena.ssao_enabled = true
	mundo.environment = env_escena
	add_child(mundo)
	await _esperar_frames(2)
	AjustesGraficos.poner_calidad(0)
	await _esperar_frames(2)
	_check("el recurso Environment de la escena queda intacto (ssao sigue ON)",
			env_escena.ssao_enabled)
	_check("el entorno en uso es una copia distinta del recurso",
			mundo.environment != env_escena)
	_check("BAJA apaga el SSAO en la copia", not mundo.environment.ssao_enabled)
	AjustesGraficos.poner_calidad(2)
	await _esperar_frames(2)
	_check("ALTA vuelve a dejar el SSAO como estaba", mundo.environment.ssao_enabled)
	mundo.queue_free()
	await _esperar_frames(2)

	# --- 3) Sólo se recorta la sombra de la vegetación ----------------------
	var vegetacion := MultiMeshInstance3D.new()
	vegetacion.name = "Trozo_0_0"
	vegetacion.multimesh = MultiMesh.new()
	add_child(vegetacion)
	var cosaIgual := MultiMeshInstance3D.new()
	cosaIgual.name = "Edificio_Modulo"
	cosaIgual.multimesh = MultiMesh.new()
	add_child(cosaIgual)
	await _esperar_frames(2)
	AjustesGraficos.poner_calidad(0)
	await _esperar_frames(2)
	_check("BAJA deja la vegetación sin proyectar sombra",
			vegetacion.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
	_check("BAJA NO toca la geometría que no es vegetación",
			cosaIgual.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON)
	AjustesGraficos.poner_calidad(2)
	await _esperar_frames(2)
	_check("ALTA devuelve la sombra a la vegetación",
			vegetacion.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON)
	vegetacion.queue_free()
	cosaIgual.queue_free()
	await _esperar_frames(2)

	# --- 4) El panel de pausa refleja el perfil -----------------------------
	var pausa: Node = (load(ESCENA_PAUSA) as PackedScene).instantiate()
	add_child(pausa)
	await _esperar_frames(2)
	var valor: Label = pausa.get_node_or_null("%CalidadValor") as Label
	_check("el panel de pausa tiene la fila de CALIDAD", valor != null)
	if valor != null:
		AjustesGraficos.poner_calidad(0)
		await _esperar_frames(2)
		_check("el panel muestra BAJA al elegir BAJA", valor.text == "BAJA")
		AjustesGraficos.poner_calidad(1)
		await _esperar_frames(2)
		_check("el panel muestra MEDIA al elegir MEDIA", valor.text == "MEDIA")
		AjustesGraficos.poner_calidad(2)
		await _esperar_frames(2)
		_check("el panel muestra ALTA al elegir ALTA", valor.text == "ALTA")
	_check("la rueda del menú recorre los perfiles sin salirse",
			AjustesGraficos.CALIDAD_NOMBRES.size() == 3)
	pausa.queue_free()
	await _esperar_frames(2)

	# --- 5) Persistencia ----------------------------------------------------
	AjustesGraficos.poner_calidad(1)
	await _esperar_frames(2)
	var cf := ConfigFile.new()
	var guardado := cf.load(RUTA_CFG) == OK
	_check("se guardó el archivo de ajustes gráficos", guardado)
	if guardado:
		_check("la preferencia de calidad queda escrita (MEDIA=1)",
				int(cf.get_value("graficos", "calidad", -1)) == 1)
		_check("no se perdieron las otras claves de gráficos",
				cf.has_section_key("graficos", "distancia")
						and cf.has_section_key("graficos", "mostrar_fps"))

	# --- 6) ARRANQUE: una instancia nueva lee el archivo y aplica lo guardado -----
	# Es el camino real del arranque del juego: AjustesGraficos._ready() -> _cargar()
	# -> _aplicar_calidad(). Se prueba con una instancia nueva del MISMO script.
	var cf2 := ConfigFile.new()
	if cf2.load(RUTA_CFG) == OK:
		cf2.set_value("graficos", "calidad", 0)
		cf2.save(RUTA_CFG)
		var otro: Node = (load("res://ui/scripts/ajustes_graficos.gd") as GDScript).new()
		add_child(otro)
		await _esperar_frames(3)
		_check("al arrancar se aplica la preferencia guardada (BAJA -> escala 0.70)",
				is_equal_approx(get_viewport().scaling_3d_scale, 0.70))
		otro.queue_free()
		await _esperar_frames(2)
	else:
		_fallos += 1
		print("[FALLA] no se pudo leer el archivo para probar el arranque")

	# Restaurar la preferencia que tenía el usuario antes de la prueba. Se escribe
	# el archivo directamente porque poner_calidad() no reescribe si coincide.
	AjustesGraficos.calidad = calidad_inicial
	AjustesGraficos.poner_calidad((calidad_inicial + 1) % 3)
	AjustesGraficos.poner_calidad(calidad_inicial)
	await _esperar_frames(2)
	var cf_fin := ConfigFile.new()
	if cf_fin.load(RUTA_CFG) == OK:
		cf_fin.set_value("graficos", "calidad", calidad_inicial)
		cf_fin.save(RUTA_CFG)
	_check("la preferencia del usuario queda restaurada (%d)" % calidad_inicial,
			cf_fin.load(RUTA_CFG) == OK
					and int(cf_fin.get_value("graficos", "calidad", -1)) == calidad_inicial)
	await _esperar_frames(2)
	print("===== RESULTADO PERFILES: %d OK, %d FALLOS =====" % [_ok, _fallos])
	get_tree().quit(0 if _fallos == 0 else 1)

func _check(texto: String, condicion: bool) -> void:
	if condicion:
		_ok += 1
		print("[OK]    ", texto)
	else:
		_fallos += 1
		print("[FALLA] ", texto)

func _esperar_frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame