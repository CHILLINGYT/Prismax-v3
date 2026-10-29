extends Node3D

## Arnés de RENDIMIENTO (sólo medición, no modifica nada del juego).
##
## Carga el mundo real (ziba_prototipo.tscn), deja que se genere por completo y
## mide el coste de fotograma en varias condiciones, una detrás de otra, DENTRO
## DE LA MISMA EJECUCIÓN: así la comparación es en idénticas condiciones
## (misma ventana, misma escena, misma posición del jugador).
##
## Fases que mide:
##   base       -> el estado tal cual está el proyecto (sin tocar nada).
##   probe_0.5  -> sólo baja la escala de renderizado 3D a 0.50 y la restaura.
##                 Diagnóstico: si los FPS CASI NO SUBEN, el cuello no es la GPU
##                 de relleno/resolución, sino CPU o draw calls.
##   baja/media/alta -> sólo si AjustesGraficos ya tiene el perfil de calidad
##                 (así este mismo arnés sirve antes y después de implementarlo).
##
## Uso:
##   godot --path . pruebas/medir_rendimiento.tscn
##
## Imprime, por fase, una línea estable y fácil de comparar:
##   MEDICION perfil=... fps=.. frame_ms=.. p95_ms=.. max_ms=.. proc_ms=.. phys_ms=..
##            draw=.. prim=.. obj=.. npc=.. enem=..

const MUNDO := "res://mundo/escena/ziba_prototipo.tscn"

## Espera generosa a que terminen terreno, ciudad, bosque y peatones (la primera
## generación es síncrona y tarda ~10-15 s: medir antes daría números falsos).
const ESPERA_GENERACION := 22.0
## Margen tras cambiar un ajuste, para que se estabilice (atlas de sombras, LOD).
const ASENTAR := 2.5
## Duración de cada ventana de medición.
const MEDIR := 6.0

## Tamaño de ventana forzado: la comparación exige condiciones idénticas, y la
## preferencia guardada del jugador podría ser otra resolución.
const VENTANA := Vector2i(1280, 720)

## Semilla FIJA del generador de ciudad: sin esto cada ejecución construye una
## ciudad distinta (el generador sortea semilla) y las medidas no son comparables.
const SEMILLA := 20261011

var _mundo: Node = null
var _fases: Array = []

func _ready() -> void:
	# Sin vsync ni tope de FPS: se mide lo que la máquina puede dar de verdad.
	Engine.max_fps = 0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	if not Engine.is_embedded_in_editor():
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(VENTANA)
		await get_tree().process_frame

	print("===== MEDICION DE RENDIMIENTO =====")
	print("godot=", Engine.get_version_info().string)
	print("renderer=", ProjectSettings.get_setting("rendering/renderer/rendering_method", "?"))
	print("gpu=", RenderingServer.get_video_adapter_name())
	print("ventana=", DisplayServer.window_get_size())
	print("vsync=", DisplayServer.window_get_vsync_mode(), " max_fps=", Engine.max_fps)

	print("[arnes] cargando el mundo y esperando la generación (", ESPERA_GENERACION, " s)...")
	_mundo = (load(MUNDO) as PackedScene).instantiate()
	# La semilla se fija ANTES de añadirlo al árbol (el generador lee la propiedad
	# en su _ready): así todas las ejecuciones miden exactamente la misma ciudad.
	var ciudad := _mundo.get_node_or_null("Ciudad")
	if ciudad != null:
		ciudad.set("semilla", SEMILLA)
	add_child(_mundo)
	await _esperar(ESPERA_GENERACION)

	print("[arnes] mundo listo: npcs=", _contar_npc(), " enemigos=",
			get_tree().get_nodes_in_group("enemigos_prueba").size())

	# 1) Estado tal cual (SIN tocar nada): la referencia del "antes".
	await _medir_fase("base", 1.0)

	# 2) Diagnóstico GPU: sólo escala 0.5, restaurada después.
	await _medir_fase("probe_0.5", 0.5)

	# 3) Comparación POR PARES. Este equipo deriva: la primera medida de una
	#    ejecución sale ~30 % mejor que las de un minuto después (calor/ruido), y
	#    eso se come cualquier comparación secuencial. Por eso cada candidato se
	#    mide INMEDIATAMENTE DESPUÉS de su referencia ALTA: los dos pagan la misma
	#    deriva y la diferencia entre ambos es lo que vale.
	if AjustesGraficos != null and AjustesGraficos.has_method("poner_calidad"):
		for plan in [["baja", 3], ["media", 2]]:
			var perfil_estudio: String = plan[0]
			for vuelta in int(plan[1]):
				await _poner_perfil("alta")
				await _medir_fase("alta_v%d_%s" % [vuelta + 1, perfil_estudio], 1.0)
				await _poner_perfil(perfil_estudio)
				await _medir_fase("%s_v%d" % [perfil_estudio, vuelta + 1], 1.0)
	else:
		print("[arnes] AjustesGraficos aún no tiene perfiles de calidad: sólo base + sonda.")

	print("===== FIN DE LA MEDICION =====")
	get_tree().quit(0)

# ------------------------------------------------------------------ fases
## Mide una fase. `escala` se aplica al viewport si difiere de 1.0 (sonda de GPU)
## y se restaura al terminar.
func _medir_fase(etiqueta: String, escala: float) -> void:
	var vp := get_viewport()
	var escala_previa := vp.scaling_3d_scale
	if not is_equal_approx(escala, 1.0):
		vp.scaling_3d_scale = escala
	await _esperar(ASENTAR)

	var muestras: Array[float] = []
	var proc := 0.0
	var phys := 0.0
	var draw := 0.0
	var prim := 0.0
	var obj := 0.0
	var n := 0
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < int(MEDIR * 1000.0):
		await get_tree().process_frame
		muestras.append(get_process_delta_time() * 1000.0)
		proc += Performance.get_monitor(Performance.TIME_PROCESS)
		phys += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)
		draw += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		prim += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
		obj += Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)
		n += 1

	if not is_equal_approx(escala, 1.0):
		vp.scaling_3d_scale = escala_previa

	if n == 0:
		print("MEDICION perfil=", etiqueta, " SIN MUESTRAS")
		return
	muestras.sort()
	var suma := 0.0
	for m in muestras:
		suma += m
	var media := suma / float(n)
	# La MEDIANA es la referencia (el editor y otros procesos meten picos sueltos;
	# la media y el p95 los arrastran). fps sale de la mediana.
	var mediana := muestras[n / 2]
	var p95 := muestras[mini(n - 1, int(round(float(n) * 0.95)))]
	var maximo := muestras[n - 1]
	print("MEDICION perfil=%s fps=%.1f med_ms=%.1f media_ms=%.1f p95_ms=%.1f max_ms=%.1f proc_ms=%.2f phys_ms=%.2f draw=%d prim=%d obj=%d npc=%d enem=%d escala=%.2f n=%d" % [
		etiqueta,
		1000.0 / maxf(mediana, 0.001),
		mediana, media, p95, maximo,
		(proc / float(n)) * 1000.0,
		(phys / float(n)) * 1000.0,
		int(draw / float(n)), int(prim / float(n)), int(obj / float(n)),
		_contar_npc(), get_tree().get_nodes_in_group("enemigos_prueba").size(),
		vp.scaling_3d_scale, n])

func _poner_perfil(nombre: String) -> bool:
	var mapa := {"baja": 0, "media": 1, "alta": 2}
	if not mapa.has(nombre):
		return false
	AjustesGraficos.poner_calidad(int(mapa[nombre]))
	await _esperar(0.4)
	print("[arnes] perfil aplicado: ", nombre, " -> estado=", AjustesGraficos.calidad)
	return true

# ------------------------------------------------------------------ utilidad
func _esperar(segundos: float) -> void:
	await get_tree().create_timer(segundos, true, false, true).timeout

func _contar_npc() -> int:
	var total := 0
	for n in get_tree().root.find_children("*", "CharacterBody3D", true, false):
		var s: Script = n.get_script() as Script
		if s != null and String(s.resource_path).ends_with("npc_citizen.gd"):
			total += 1
	return total