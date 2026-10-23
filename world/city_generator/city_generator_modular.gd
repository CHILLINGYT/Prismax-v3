@tool
class_name CityGeneratorModular
extends Node3D
## Generador Modular - Reemplazo futuro de generador_ciudad.gd (3925 lineas)
## Fase 1: Estructura modular para trabajo en equipo

signal progreso_generacion(valor: float, etapa: String)

@export_group("1. Recursos")
@export_dir var carpeta_modelos: String = "res://Exports/glTF (Godot)/"
@export var semilla: int = 0

@export_group("2. Trazado")
@export_range(1, 10) var manzanas_x: int = 6
@export_range(1, 10) var manzanas_z: int = 6
@export_range(12.0, 60.0, 6.0) var tamano_manzana: float = 24.0
@export_range(6.0, 18.0, 6.0) var ancho_calzada: float = 12.0
@export_range(3.0, 9.0, 3.0) var ancho_acera: float = 3.0

@export_group("3. Edificios")
@export var usar_prefabricados: bool = false
@export var usar_modulares: bool = true
@export_range(2, 8) var pisos_min: int = 2
@export_range(2, 10) var pisos_max: int = 7
@export_range(0.0, 0.6) var prob_torre: float = 0.18
@export_range(0.0, 0.6) var prob_solar_vacio: float = 0.12

@export_group("5. Rendimiento")
@export var usar_multimesh: bool = true
@export var agrupar_por_sector: bool = true
@export var lado_sector: float = 42.0
@export var usar_aabb_por_cajas: bool = true
@export var escanear_desde_estado: bool = true

@export_group("6. Parques")
@export var manzanas_parque: int = 3

@export_group("8. Ejecución")
@export var generar_al_iniciar: bool = true
@export var generar_en_editor: bool = true
@export_tool_button("Generar ciudad (Modular)", "Reload") var _btn_generar: Callable = generar_ciudad
@export_tool_button("Limpiar ciudad", "Remove") var _btn_limpiar: Callable = limpiar_ciudad

var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	if Engine.is_editor_hint():
		if generar_en_editor and get_node_or_null(CityConstants.NODO_CIUDAD) == null:
			generar_ciudad()
		return
	if generar_al_iniciar:
		generar_ciudad()

func generar_ciudad() -> void:
	var t0 := Time.get_ticks_msec()
	limpiar_ciudad()
	_rng.seed = semilla if semilla != 0 else randi()
	
	# Fase 1: Scanner modular
	progreso_generacion.emit(0.0, "escaneo modular")
	var scanner := CityScanner.new(escanear_desde_estado, usar_aabb_por_cajas)
	var carpeta := scanner.resolver_carpeta(carpeta_modelos)
	if carpeta == "":
		push_error("[Modular] No carpeta")
		return
	var modelos: Dictionary = {}
	var categorias: Dictionary = {}
	scanner.escanear(carpeta, modelos, categorias)
	var listas := scanner.construir_listas()
	
	# Fase 2: Tracer modular
	progreso_generacion.emit(0.25, "trazado modular")
	var config := {"manzanas_x": manzanas_x, "manzanas_z": manzanas_z, "tamano_manzana": tamano_manzana, "ancho_calzada": ancho_calzada, "ancho_acera": ancho_acera, "lado_sector": lado_sector}
	var tracer := CityTracer.new(_rng, config)
	var trazado := tracer.preparar_trazado()
	var parques := tracer.elegir_parques(manzanas_parque)
	
	# Fase 3: Por ahora delegar al original para no romper
	progreso_generacion.emit(0.35, "delegando a generador original")
	var gen_original := load("res://generador_ciudad.gd").new()
	gen_original.manzanas_x = manzanas_x
	gen_original.manzanas_z = manzanas_z
	gen_original.tamano_manzana = tamano_manzana
	gen_original.ancho_calzada = ancho_calzada
	gen_original.ancho_acera = ancho_acera
	gen_original.semilla = _rng.seed
	gen_original.carpeta_modelos = carpeta_modelos
	gen_original.generar_al_iniciar = false
	gen_original.generar_en_editor = false
	
	var root := Node3D.new()
	root.name = CityConstants.NODO_CIUDAD
	add_child(root)
	root.add_child(gen_original)
	gen_original.generar_ciudad()
	
	var ms := Time.get_ticks_msec() - t0
	print("[CityGeneratorModular] Generado en %d ms - %d modelos - %d parques" % [ms, modelos.size(), parques.size()])
	progreso_generacion.emit(1.0, "completado")

func limpiar_ciudad() -> void:
	var existente := get_node_or_null(CityConstants.NODO_CIUDAD)
	if existente != null:
		existente.queue_free()
