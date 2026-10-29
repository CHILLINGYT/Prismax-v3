@tool
class_name GeneradorCiudad3D
extends Node3D
## =============================================================================
##  GENERADOR PROCEDURAL DE CIUDAD 3D
##  Usa exclusivamente los modelos .gltf/.glb de la carpeta indicada (por
##  defecto el kit "Downtown" exportado a res://Exports/glTF (Godot)/).
## -----------------------------------------------------------------------------
##  Qué hace:
##   1. ESCANEA la carpeta y clasifica cada modelo por nombre y por su firma
##      geométrica medida (edificios, calles, aceras, vegetación, props,
##      marcas viales y módulos de fachada).
##   2. TRAZA la ciudad en cuadrícula: manzanas edificables separadas por
##      calles de 12 m (calzada de 6 m + 2 aceras de 3 m). El reparto es
##      disjunto: cada región del plano se cubre una sola vez, así que no hay
##      solapamientos entre piezas.
##   3. DA VARIACIÓN: los edificios giran en pasos de 90°, tienen altura variable,
##      posibilidad de torre (prob_torre) y **una sola familia de fachada** cada
##      uno (ladrillo / metal / molduras). Las piezas de una familia se agrupan
##      por nombre en _construir_familias(), así que un edificio nunca mezcla
##      texturas: elige familia (muros, planta baja, ventanas, remate, esquinas y
##      cornisa) y la usa entera. Las ventanas se alinean en la misma vertical
##      (patrón fijo por edificio), no sorteadas celda a celda.
##   4. CIERRA LAS MANZANAS Y LOS EDIFICIOS: cada edificio ocupa su parcela
##      completa, así que los vecinos se tocan y no quedan callejones. Los muros
##      se colocan CENTRADOS en su celda (el módulo va de x = -1 a +1), así cada
##      cara cubre de esquina a esquina: sin rendijas al empezar (que dejaban ver
##      el interior, los "parches negros" de las esquinas) ni paños colgando al
##      terminar. Cada tramo va adelantado unos milímetros para que el canto del
##      muro no quede coplanar con la fachada perpendicular (evita el parpadeo
##      blanco/negro en las esquinas). El portal va centrado en su celda, con
##      marco de la MISMA familia que el edificio (madera con ladrillo, moldura
##      con moldura, metal con metal) y DOS hojas de 1 m que cierran el vano de
##      2 m, con el fondo medido contra la caja real del marco: nunca se cruzan
##      con la textura de la fachada ni dejan media puerta abierta.
##      Los edificios llevan colisión envolvente: no se puede entrar.
##   5. VEGETACIÓN Y PARQUES: algunas manzanas (céntricas) se convierten en
##      parque: césped texturizado, senderos en cruz, árboles 3D, arbustos,
##      jardineras del kit y bolardos. Además hay árboles de alineación en las
##      aceras y vegetación en los solares vacíos. Los árboles y arbustos son
##      geometría 3D real (tronco + masas de hoja) apoyada en el suelo.
##   6. ORGANIZA la escena en contenedores: Suelo, Calles, Aceras, Edificios
##      (Prefabricados / Modulares), Vegetacion, Props y MarcasViales. Las
##      piezas muy repetidas (pavimentos, muros, azoteas, árboles...) se agrupan
##      en MultiMeshInstance3D para que la ciudad sea barata de dibujar.
##   7. COLISIONES: comprueba si cada modelo ya trae cuerpo físico y, si no,
##      añade StaticBody3D + CollisionShape3D a suelo, aceras, manzanas y
##      edificios (y opcionalmente a los props).
##
##  TAMAÑO: por defecto 6x6 manzanas de 24 m con AVENIDAS de 12 m (cuatro
##  carriles) = 252 x 252 m (unas 16 hectáreas) con 3 parques, pensado para
##  recorrerse a pie. Para más ciudad, sube manzanas_x / manzanas_z (hasta 10)
##  en el Inspector: 8x8 son unos 20.000 nodos y ~2 s de generación.
##
##  ACABADO: la calzada se tesela con planchas planas de asfalto y se pinta con
##  raya doble amarilla en el eje, discontinuas por carril y pasos de peatones
##  anchos en los cruces. Cada azotea es una losa propia con membrana de grava
##  (res://assets/generated/techo_grava.png) repetida cada 4 m; no se usan las
##  planchas de tejado del kit, que dejaban parches beige y gris a la misma cota. Los canteros con reja del kit no se colocan: el
##  suelo de plazas y parques queda liso y continuo, y la vegetación la ponen
##  los árboles y arbustos 3D. Los edificios completos del kit (Building_*) van
##  apagados porque traen la puerta abierta de fábrica.
##
##  Cómo usarlo:
##   · Adjunta este script a un Node3D raíz.
##   · En el EDITOR: botones "Generar ciudad" / "Limpiar ciudad" en el Inspector
##     (quedan en la escena y se guardan al salvar el .tscn).
##   · En RUNTIME: con "generar_al_iniciar" activo la ciudad se crea al pulsar
##     Play; también puedes llamar a generar_ciudad() desde tu propio código.
##   · CÁMARA LIBRE (si "camara_libre" está activo): ratón para mirar,
##     W/A/S/D para volar, E/Q para subir/bajar, Shift para ir rápido,
##     R para volver a la vista inicial y Esc para liberar el ratón.
##
##  Convenciones métricas del kit (medidas sobre los .gltf reales):
##   · y =  0.00  -> superficie peatonal: acera, plaza y base de los edificios.
##   · y = -0.15  -> superficie de la calzada (las planchas de asfalto son
##                   planos justo a esa altura).
##   · Piezas de fachada: 2.00 m de ancho x 3.00 m de alto, con la cara
##     exterior en z = 0 y el volumen hacia -z (por eso "giran" con múltiplos
##     de 90° para formar el perímetro del edificio).
## =============================================================================

## Emitida por generar_ciudad_por_etapas() conforme avanza el trabajo: 'valor' es
## el avance normalizado (0..1) y 'etapa' el nombre de la etapa en curso. El valor
## es una ESTIMACIÓN por etapas y unidades completadas, no una medida de tiempo.
signal progreso_generacion(valor: float, etapa: String)

# --- Medidas del kit (metros) -------------------------------------------------
const MODULO_ANCHO := 2.0      ## ancho de un módulo de fachada
const PLANTA_ALTO := 3.0       ## altura de una planta / de un módulo de muro
const Y_ACERA := 0.0           ## cota de aceras, plazas y base de edificios
const Y_CALZADA := -0.15       ## cota de la calzada
const Y_LOSA := -0.002         ## cara superior de las plataformas de manzana
const Y_SUELO := -0.16         ## cara inferior de las losas / del terreno
const Y_TERRENO := -0.155      ## cara superior del terreno (5 mm bajo la calzada)
const COLOR_SUELO := Color(0.20, 0.20, 0.21)
const COLOR_LOSA := Color(0.56, 0.55, 0.52)
const NODO_CIUDAD := "CiudadGenerada"

# --- Vegetación propia (césped, árboles y arbustos generados) ------------------
const Y_PARQUE := -0.15         ## cota del césped de los parques (nivel de calzada)
const RUTA_CESPED := "res://assets/generated/parque_cesped.png"
## Membrana de grava de las azoteas (textura generada, teselable).
const RUTA_TECHO := "res://assets/generated/techo_grava.png"

# --- Configuración expuesta en el Inspector -----------------------------------
@export_group("1. Recursos")
## Carpeta con los modelos .gltf/.glb. Si no existe se busca automáticamente.
@export_dir var carpeta_modelos: String = "res://Exports/glTF (Godot)/"
## Semilla del azar. 0 = la semilla FIJA de `world/semilla_mundo.gd` (el mundo
## sale siempre igual); con otro valor se fuerza ésa sólo para esta ciudad.
@export var semilla: int = 0

@export_group("2. Trazado")
@export_range(1, 10) var manzanas_x: int = 6     ## manzanas en el eje X
@export_range(1, 10) var manzanas_z: int = 6     ## manzanas en el eje Z
## Lado de la manzana edificable (se ajusta a múltiplo de 6 m).
@export_range(12.0, 60.0, 6.0) var tamano_manzana: float = 24.0
## Ancho de la calzada (múltiplo de 6 m: plancha de asfalto). Con 12 m sale una
## avenida de cuatro carriles: raya doble amarilla en el eje y discontinuas.
@export_range(6.0, 18.0, 6.0) var ancho_calzada: float = 12.0
## Ancho de cada acera (múltiplo de 3 m: loseta de acera).
@export_range(3.0, 9.0, 3.0) var ancho_acera: float = 3.0

@export_group("3. Edificios")
## Coloca los edificios completos del kit (Building_*). Van apagados por
## defecto: esos modelos traen la puerta de entrada abierta de fábrica y su
## volumen no encaja con la retícula de 2 m, así que los solares se resuelven
## con el edificio modular (fachada coherente y portal cerrado de verdad).
@export var usar_prefabricados: bool = false
## Compone edificios con módulos del kit (muros, ventanas, cornisas, azotea).
@export var usar_modulares: bool = true
@export_range(2, 8) var pisos_min: int = 2
@export_range(2, 10) var pisos_max: int = 7
## Probabilidad de que una parcela salga mucho más alta (torre del skyline).
@export_range(0.0, 0.6) var prob_torre: float = 0.18
## Variación aleatoria máxima de escala (uniforme) de los edificios.
@export_range(0.0, 0.4) var variacion_escala: float = 0.10
## Probabilidad de que un solar quede libre (plaza con vegetación).
@export_range(0.0, 0.6) var prob_solar_vacio: float = 0.12

@export_group("4. Detalle")
## Pavimenta el interior de las manzanas con losas de acera sin bordillo.
@export var pavimentar_manzanas: bool = true
@export var generar_props: bool = true
@export var generar_vegetacion: bool = true
@export var generar_marcas_viales: bool = true
## Aparatos de aire acondicionado sobre las azoteas modulares.
@export var props_en_azotea: bool = true

@export_group("5. Rendimiento")
## Agrupa las piezas repetidas en MultiMeshInstance3D (recomendado).
@export var usar_multimesh: bool = true
## Agrupa por SECTOR en vez de por pieza: cada sector (bloque de la trama) aloja
## sus propios MultiMeshInstance3D, de modo que cada zona se pueda activar,
## dibujar o descargar por separado. Con false se vuelve al comportamiento
## anterior (un único lote por pieza para toda la ciudad).
@export var agrupar_por_sector: bool = true
## Lado (m) de cada sector. Por defecto igual al paso de la trama (manzana +
## calles), así que un sector es, en la práctica, una manzana.
@export var lado_sector: float = 42.0
## Caja envolvente del modelo: une las cajas de sus mallas (`Mesh.get_aabb()`
## transformada) en vez de recorrer todos sus vértices. Validado en el flujo real
## (semilla 20261011): `[HASH-CIUDAD]` idéntico con ambos métodos (4948 nodos y 19488
## matrices MultiMesh), conteos idénticos y `aabb+arrays` 2700 ms → 16 ms (y 1166 → 24 ms
## en el A/B anterior). El método original (`_aabb_vertices`) sigue en el archivo y se
## puede seguir usando con PRISMAX_AABB_CAJAS=0.
@export var usar_aabb_por_cajas: bool = true

@export_group("6. Parques y vegetación")
## Manzanas que se convierten en parque (césped, senderos en cruz y árboles).
@export var manzanas_parque: int = 3
## Árboles por parque, además de arbustos y jardineras del kit.
@export var arboles_por_parque: int = 18
## Separación media entre árboles de calle, en metros (0 = sin árboles de calle).
@export var arboles_calle: float = 14.0
## Usa la vegetación propia: césped generado y árboles/arbustos en 3D.
@export var usar_vegetacion_propia: bool = true
## Paseo costero: pavimenta la franja entre la última calle y la arena en los
## sectores donde la costa queda cerca, con vegetación costera. Sigue la costa REAL
## (la que genera `Relieve`), así que se adapta sola si el mapa cambia.
@export var paseo_costero: bool = true
## Ancho máximo (m) de la franja pavimentada del paseo costero. Es un paseo
## ESTRECHO pegado a las veredas: el resto de la franja hasta la arena queda como
## terreno natural (pasto), que es la transición que se quiere ver.
@export_range(4.0, 40.0, 2.0) var paseo_ancho_max: float = 8.0
## Franja mínima (m) de terreno natural (pasto) que se deja SIEMPRE entre el paseo
## y la arena: ciudad/veredas -> paseo -> pasto -> transición natural -> arena.
@export var paseo_pasto_min: float = 4.0

@export_group("6b. Playa, costa y ventanas nocturnas")
## Palmeras, sombrillas y reposeras repartidas por la arena de la costa urbana
## (sigue la orilla real de `Relieve`; la cantidad se adapta al espacio).
@export var playa_mobiliario: bool = true
## Densidad del mobiliario de playa (1 = la repartida de referencia).
@export_range(0.0, 2.0, 0.05) var playa_densidad: float = 1.0
## Palmeras (borde de la playa y transición al pasto) y su densidad.
@export_range(0.0, 2.0, 0.05) var palmeras_densidad: float = 1.0
## Vegetación del prado costero junto a la playa (grupos moderados de árboles y
## arbustos sobre el césped, sin macetas), en el frente de costa despejado.
@export var costa_vegetacion: bool = true
## Algunas ventanas de los edificios se encienden de noche en tonos cálidos.
## Va en fase con el ciclo de día y noche, igual que las farolas de la calle.
@export var ventanas_noche: bool = true

@export_group("6c. Peatones (la ciudad habitada)")
## Ciudadanos que recorren la ciudad por la RED PEATONAL (veredas y pasos de
## peatones pintados; la calzada no es superficie válida). Configuración
## centralizada: cantidad, reparto por plazas y por la costa, y topes de
## ocupación de bancos y reposeras.
@export var peatones_activos: bool = true
## Ciudadanos totales (los que reparte este generador). Reparto por SECTORES: rejilla 4x4
## sobre el núcleo urbano, la franja costera (paseo + arena) y un sector por plaza/parque,
## de modo que la gente queda repartida por todo el mapa y no amontonada en el centro.
@export_range(0, 200) var peatones_total: int = 70
## Fracción de ciudadanos cuyo destino son plazas y parques.
@export_range(0.0, 1.0) var peatones_plaza: float = 0.30
## Peatones del frente costero (paseo, arena y reposeras).
@export_range(0, 60) var peatones_playa: int = 16
## Asientos de banco ocupados como máximo (el resto quedan libres).
@export_range(0, 100) var peatones_sentados: int = 18
## Reposeras ocupadas como máximo (siempre quedan reposeras vacías).
@export_range(0, 100) var peatones_tumbados: int = 11
## Auditoría de seguridad en ejecución: comprueba cada segundo que ningún
## peatón esté sobre el asfalto fuera de un paso de peatones (queda en consola).
@export var peatones_auditoria: bool = false

@export_group("7. Colisiones")
@export var colisiones_suelo: bool = true
@export var colisiones_edificios: bool = true
@export var colisiones_props: bool = false
## Colisión de los TRONCOS de los árboles y palmeras y de los CANTEROS de obra (capa 1,
## la misma del terreno y los edificios): el jugador no los atraviesa. Sólo el tronco y
## el cantero son sólidos; las copas (tarjetas cruzadas) no bloquean el paso por debajo.
@export var colisiones_vegetacion: bool = true

@export_group("8. Ejecución")
## Genera la ciudad automáticamente al arrancar el juego (no en el editor).
@export var generar_al_iniciar: bool = true
## Genera la ciudad al ABRIR la escena en el editor, para poder verla en el visor
## 3D sin pulsar Play (tarda unos segundos, avisa a la barra de estado). Es una
## vista de trabajo: esos nodos no se guardan al salvar la escena (para guardarla
## de verdad, usa "Generar ciudad" y salva tú la escena).
@export var generar_en_editor: bool = true
## Crea cámara, luz solar y entorno (cielo) si la escena no los tiene, para
## poder ver la ciudad al pulsar Play. Nodos: CamaraCiudad, Sol, Entorno.
@export var crear_camara_y_luz: bool = true
## Convierte la cámara en cámara libre de vuelo (ratón + WASD + E/Q, Esc libera).
@export var camara_libre: bool = true
@warning_ignore("unused_private_class_variable")
@export_tool_button("Generar ciudad", "Reload") var _btn_generar: Callable = generar_ciudad
@warning_ignore("unused_private_class_variable")
@export_tool_button("Limpiar ciudad", "Remove") var _btn_limpiar: Callable = limpiar_ciudad

# --- Estado interno -----------------------------------------------------------
var _rng := RandomNumberGenerator.new()
## Fase de edición en curso (ver `world/ediciones_ciudad.gd`): mientras está
## activa, las mallas del edificio que se está construyendo NO se añaden al
## mundo. El azar se consume igual que siempre, así que ocultar una casa no
## mueve ni un milímetro el resto de la ciudad.
var _ocultar_actual := false
## Material con el que pintar TODAS las mallas del edificio en curso (null = el suyo).
var _material_edificio: Material = null
## RNG propio de cada edificio: los detalles de ESA casa (ventanas encendidas,
## aires acondicionados…) se sortean aquí y no en el generador de la ciudad, para
## que editar una casa (por ejemplo, darle más plantas) no desplace los sorteos
## de las demás.
var _rng_edificio := RandomNumberGenerator.new()
var _vista_editor := false   ## true mientras se genera sólo para el visor 3D
var _carpeta := ""
var _modelos := {}          ## nombre -> {escena: PackedScene, caja: AABB, categoria: String}
var _categorias := {}       ## categoria -> PackedStringArray con los nombres encontrados
var _lotes := {}            ## pieza -> {clave_sector -> {pistas: Array, padre: Node3D}}
var _sector_padre := {}     ## clave_sector -> Node3D contenedor de ese sector
var _cont_sectores: Node3D = null   ## contenedor raíz de los sectores (se crea al primer uso)
var _mm_cache := {}         ## nombre -> bool (¿se puede agrupar en MultiMesh?)
var _mm_datos := {}         ## PackedScene -> {mallas, sup, malla, local} (una sola instanciación por modelo)
var _cont := {}             ## nombre -> Node3D contenedor
# --- MEDICIÓN TEMPORAL DE ETAPAS (instrumentación; se puede borrar entera) ----
var _medir_etapas := false   ## la activa PRISMAX_MEDIR_ETAPAS=1 (apagada no hace nada)
var _etapas: Array = []      ## [{nombre, ms, est, delta}]
var _etapa_nombre := ""
var _etapa_t0 := 0
var _sub_scan := {}          ## sub-tiempos del escaneo de modelos (ms por paso)
var _sub_aabb := {"sup": 0, "verts": 0}   ## superficies y vértices leídos por la AABB
## Valor EFECTIVO del método de AABB: el export `usar_aabb_por_cajas` (por defecto
## `true`, unión de cajas de malla) o, sin tocar el archivo, PRISMAX_AABB_CAJAS:
## 1 = cajas, 0 = método original de vértices. Aquí sólo se guarda el resultado.
var _aabb_cajas := false
## P2-C (ACTIVADO por defecto tras la validación P2-C/P2-D): obtener los datos de cada
## modelo leyendo el estado del PackedScene en vez de instanciar y liberar el template.
## Elimina `instantiate()`+`free()` (medido 2,1-3,9 s del escaneo en las referencias A/B)
## dejando solo la lectura del estado (~70-120 ms para 153 modelos). Validado en 4 corridas
## del arnés real: `[HASH-CIUDAD]` 2901108029 idéntico, 4948 nodos, 19488 matrices,
## contadores idénticos, 153/153 por estado y 0 fallbacks. Con cualquier estructura no
## soportada cae automáticamente al método actual (fallback contado y registrado).
## Se puede volver a la ruta de referencia con PRISMAX_ESCANEO_ESTADO=0.
@export var escanear_desde_estado: bool = true
var _escanear_estado := false
var _leidos_estado := 0      ## modelos resueltos leyendo el estado (diagnóstico)
var _fallbacks_estado := 0   ## modelos que cayeron al método actual (diagnóstico)
var _trazado := {}          ## parámetros calculados de la trama urbana
var _est := {}              ## contadores para el informe

# Listas funcionales construidas al clasificar los modelos
var _prefabs: Array[String] = []
var _paredes: Array[String] = []
var _paredes_bajas: Array[String] = []
var _paredes_top: Array[String] = []
var _ventanas: Array[String] = []
var _esquinas_muro: Array[String] = []
var _marcos_puerta: Array[String] = []
var _hojas_puerta: Array[String] = []
var _cornisas: Array[String] = []
var _techos := {}                       ## lado (int) -> Array[String]
## Familias de fachada coherentes: familia -> {muros, bajas, ventanas, top,
## esquinas, cornisas}. Cada edificio usa UNA sola familia, así sus texturas
## nunca se mezclan (ladrillo con metal con molduras en el mismo muro).
var _familias: Dictionary = {}
var _mat_relleno: StandardMaterial3D = null
var _tramo_calle: Array[String] = []
var _plancha_asfalto: Array[String] = []
var _acera_recta: Array[String] = []
var _acera_pavimento: Array[String] = []
var _esquinas_acera: Array[String] = []
var _esquina_dir := {}                  ## nombre -> Vector2i (esquina redondeada del modelo)
var _con_decal := {}                    ## nombre -> bool (trae capa de pintura "MI_StreetDecals")
var _mallas_limpias := {}               ## malla original -> copia sin capas de pintura
var _linea_discontinua: Array[String] = []
var _linea_central: Array[String] = []      ## raya doble amarilla del eje
var _pasos_peatones: Array[String] = []
var _pasos_anchos: Array[String] = []       ## pasos que cubren la calzada entera
var _pintura_esquinas: Array[String] = []
var _tex_cesped: Texture2D = null          ## césped de los parques (si existe)
var _tex_techo: Texture2D = null           ## membrana de grava de las azoteas
var _maceta_modelo: String = ""            ## cantero del kit para árboles sobre pavimento
var _pistas_maceta: Array[Transform3D] = []  ## macetas pendientes de volcar en MultiMesh
# --- Playa y ventanas nocturnas ------------------------------------------------
var _pistas_palmera: Array[Transform3D] = []       ## palmeras pendientes de volcar
var _pistas_sombrilla: Array = [[], [], []]        ## sombrillas, por esquema de color
var _pistas_reposera: Array[Transform3D] = []      ## reposeras pendientes de volcar
var _tintes_reposera: Array[Color] = []            ## color de tela por reposera
var _pistas_ventana: Array[Transform3D] = []       ## paños de ventana encendidos de noche
var _datos_ventana: Array[Color] = []              ## (brillo, calidez) por paño encendido
var _vent_medidas := {}                            ## pieza de ventana -> vidrio medido
var _factor_ventanas_edificio := 0.5               ## "vida nocturna" del edificio en curso
# --- Ruidos de agrupación de las plantas costeras ------------------------------
var _ruido_costa: FastNoiseLite = null    ## manchas de arbolado del prado costero
var _ruido_palmas: FastNoiseLite = null   ## grupos y claros de palmeras
# --- Datos para los peatones (los llena la generación, los usa el DirectorPeatones) ---
var _cruces_peatones: Array = []          ## brazos con paso de peatones pintado
var _bancos_datos: Array = []             ## {pos, giro} de cada banco colocado
var _plazas_datos: Array[Rect2] = []      ## solares resueltos como plaza
var _parques_datos: Array[Rect2] = []     ## manzanas-parque
var _paseo_datos: Array = []              ## cadenas de centros de tramo del paseo
var _playa_tramos: Array = []             ## {borde, hacia_mar, a0, a1, lado} de la arena seca
var _arena_datos: Array = []              ## cadenas de nodos de la calle de arena elegida
var _reposeras_datos: Array = []          ## {pos, yaw, variante} de cada reposera
var _obstaculos_plantas: Array[Vector3] = []  ## base de cada planta (peatones: rodearlas)
## Obstáculos sólidos para los peatones (círculos en planta: {x, z, r}): troncos, canteros,
## bancos, reposeras y postes de sombrilla. El DirectorPeatones los usa para la evitación
## local; aquí se apuntan en el momento de colocar cada pieza.
var _obstaculos_peatones: Array = []
var director_peatones: Node = null        ## DirectorPeatones de la ciudad actual
## Troncos, canteros y palmeras con colisión física para el jugador ({x, y, z, r, h}).
## Se acumulan al plantar cada pieza y se vuelcan juntas en un StaticBody3D al cerrar
## la ciudad (`_construir_colisiones_vegetacion`). Las COPA de las tarjetas cruzadas no
## lleva colisión: se puede caminar por debajo del arbolado.
var _colisiones_vegetacion: Array = []
var _mat_techo := {}                       ## lado de la plancha -> material de membrana
## Vegetación: matrices y colores agrupados POR TEXTURA (tarjetas cruzadas de
## `Vegetacion`), para volcar una MultiMeshInstance3D por especie.
var _pistas_planta: Dictionary = {}
var _tintes_planta: Dictionary = {}
var _alcantarillas: Array[String] = []
var _sumideros: Array[String] = []
var _bolardos: Array[String] = []
var _aires: Array[String] = []
var _vegetacion: Array[String] = []
## Para pruebas visuales (escena prueba_puerta.tscn): centro y normal hacia la
## calle de cada portal, y esquina noreste exterior de cada edificio modular.
var prueba_portales: Array[Vector3] = []
var prueba_portales_dir: Array[Vector3] = []
## Cuánto sobresale por delante del plano del portón la cara exterior del marco (m, en el
## sentido de `prueba_portales_dir`): con esto el DirectorPeatones sabe a qué distancia
## exacta queda la puerta real y dónde debe pararse el ciudadano que va a entrar.
var prueba_portales_frente: Array[float] = []
var prueba_esquinas: Array[Vector3] = []
var prueba_esquinas_dir: Array[Vector3] = []


## Recursos del sistema de peatones, pedidos por adelantado en segundo plano con el
## hilo de ResourceLoader (el MISMO mecanismo que ya usa LoadingScreen). No dependen
## de la ciudad, del mundo instanciado, del RNG ni de ningún ajuste: sólo se adelanta
## su carga para que no bloquee el hilo principal al instalar el director, que sigue
## llamando a `load()` como siempre y encuentra los recursos ya en caché.
const DIRECTOR_PEATONES := preload("res://NPCs/Scripts/director_peatones.gd")
const ESCENA_CIUDADANO := "res://NPCs/Scenes/NPC_Citizen.tscn"


func _precargar_recursos_peatones() -> void:
	var fallos := 0
	for ruta: String in DIRECTOR_PEATONES.rutas_modelos():
		if ResourceLoader.load_threaded_request(ruta) != OK:
			fallos += 1
	if ResourceLoader.load_threaded_request(ESCENA_CIUDADANO) != OK:
		fallos += 1
	if fallos > 0:
		# No es fatal: el director los cargará de forma síncrona al instalar,
		# como venía haciendo; sólo se pierde el adelanto.
		push_warning("[GeneradorCiudad] no se pudieron adelantar %d recursos de peatón" % fallos)


func _ready() -> void:
	_medir_etapas = OS.get_environment("PRISMAX_MEDIR_ETAPAS") == "1"
	_aabb_cajas = usar_aabb_por_cajas
	var env_aabb := OS.get_environment("PRISMAX_AABB_CAJAS")
	if env_aabb == "1":
		_aabb_cajas = true
	elif env_aabb == "0":
		_aabb_cajas = false
	_escanear_estado = escanear_desde_estado or OS.get_environment("PRISMAX_ESCANEO_ESTADO") == "1"
	if Engine.is_editor_hint():
		# Vista de trabajo en el editor: se genera la ciudad para poder verla en
		# el visor 3D sin pulsar Play. Sin "owner" (no se guarda al salvar) y con
		# la vista del editor enfocada en ella. Si ya hay ciudad (por ejemplo,
		# generada con el botón del Inspector), se respeta la que haya.
		if generar_en_editor and is_inside_tree() and get_node_or_null(NODO_CIUDAD) == null:
			_vista_editor = true
			generar_ciudad()
			_vista_editor = false
		return
	# Si una ejecución anterior guardó la cámara temporalmente en la escena,
	# devolverla al encuadre aéreo predeterminado de la ciudad.
	var cam_inicial := get_node_or_null("CamaraCiudad") as Camera3D
	if cam_inicial != null:
		cam_inicial.position = Vector3(168.0, 124.0, 168.0)
		cam_inicial.rotation_degrees = Vector3(-27.5, 45.0, 0.0)
	# Los recursos de los peatones se piden ya en segundo plano: no dependen de la
	# ciudad y así su carga no bloquea el hilo principal al instalar el director.
	_precargar_recursos_peatones()
	if generar_al_iniciar:
		generar_ciudad()


# =============================================================================
#  API pública
# =============================================================================

# =============================================================================
#  MEDICIÓN DE ETAPAS (instrumentación temporal: borrar este bloque entero)
# =============================================================================
## Con PRISMAX_MEDIR_ETAPAS=1, cada generación imprime una tabla con el tiempo y
## los elementos de cada etapa. Sin esa variable no hace NADA (ni marcadores ni
## impresiones), así que no cambia el comportamiento normal.
func _m(nombre: String) -> void:
	if not _medir_etapas:
		return
	var ahora := Time.get_ticks_usec()
	if _etapa_nombre != "":
		_etapas.append({
			"nombre": _etapa_nombre,
			"ms": float(ahora - _etapa_t0) / 1000.0,
			"est": _est.duplicate(),
		})
	_etapa_nombre = nombre
	_etapa_t0 = ahora


## Cierra la última etapa y escribe la tabla, de mayor a menor duración.
func _m_fin() -> void:
	if not _medir_etapas or _etapa_nombre == "":
		return
	_m("####")                     # cierra (guarda) la última etapa real
	var prev := {}
	var total := 0.0
	for e in _etapas:
		var d: Dictionary = e
		d["delta"] = _delta_est(prev, d["est"])
		prev = d["est"]
		total += float(d["ms"])
	print("[GeneradorCiudad][ETAPAS] ===== tabla de etapas: total %.0f ms =====" % total)
	var orden := _etapas.duplicate()
	orden.sort_custom(_mayor_ms)
	for e in orden:
		var d: Dictionary = e
		var cola := String(d["delta"])
		print("[GeneradorCiudad][ETAPAS] %7.1f ms | %-28s | %s" % [
				float(d["ms"]), String(d["nombre"]), cola if cola != "" else "-"])
	print("[GeneradorCiudad][ETAPAS] ===== fin de la tabla =====")
	if not _sub_scan.is_empty():
		print("[GeneradorCiudad][ESCANEO] load=%.0f ms | instantiate=%.0f ms | aabb+arrays=%.0f ms | decal=%.0f ms | datos_malla=%.0f ms (recorrido_arbol=%.0f + plantilla_free=%.0f)" % [
				float(_sub_scan.get("load", 0.0)), float(_sub_scan.get("instantiate", 0.0)),
				float(_sub_scan.get("aabb", 0.0)), float(_sub_scan.get("decal", 0.0)),
				float(_sub_scan.get("datos_malla", 0.0)),
				float(_sub_scan.get("recorrido_arbol", 0.0)), float(_sub_scan.get("plantilla_free", 0.0))])
		var coste_estado := float(_sub_scan.get("escaneo_estado", 0.0))
		_sub_scan.clear()
		_sub_aabb = {"sup": 0, "verts": 0}
		if _escanear_estado:
			print("[GeneradorCiudad][ESCANEO-ESTADO] leidos=%d | fallbacks=%d | coste_estado=%.0f ms" % [
					int(_leidos_estado), int(_fallbacks_estado), coste_estado])
		_leidos_estado = 0
		_fallbacks_estado = 0
	_etapas.clear()
	_etapa_nombre = ""


## Acumula un sub-tiempo del escaneo (sólo con la medición activa).
func _sumar_sub(nombre: String, desde: int, hasta: int) -> void:
	_sub_scan[nombre] = float(_sub_scan.get(nombre, 0.0)) + float(hasta - desde) / 1000.0


func _mayor_ms(a: Dictionary, b: Dictionary) -> bool:
	return float(a["ms"]) > float(b["ms"])


## Elementos generados durante una etapa (diferencia de los contadores del informe).
func _delta_est(prev: Dictionary, ahora: Dictionary) -> String:
	var partes: Array[String] = []
	var claves: Array = ahora.keys()
	claves.sort()
	for k in claves:
		var d := int(ahora[k]) - int(prev.get(k, 0))
		if d != 0:
			partes.append("%s +%d" % [String(k), d])
	return " · ".join(partes)


## La vía por etapas YA emite `progreso_generacion` al cerrar cada etapa: basta
## engancharse a esa señal para medir el camino real que usa la pantalla de carga,
## sin tocar su código, sus señales ni su comportamiento.
func _etapa_emitida(_valor: float, etapa: String) -> void:
	if not _medir_etapas:
		return
	_m(etapa)


func _etapas_ini() -> void:
	if not _medir_etapas:
		return
	_etapas.clear()
	_etapa_nombre = ""
	if not progreso_generacion.is_connected(_etapa_emitida):
		progreso_generacion.connect(_etapa_emitida)


func _etapas_fin() -> void:
	if not _medir_etapas:
		return
	if progreso_generacion.is_connected(_etapa_emitida):
		progreso_generacion.disconnect(_etapa_emitida)
	_m_fin()


## Borra la ciudad anterior (si existe) y genera una nueva con la semilla actual.
func generar_ciudad() -> void:
	var t0 := Time.get_ticks_msec()
	limpiar_ciudad()

	_rng = RandomNumberGenerator.new()
	# Semilla FIJA del mundo: la de `world/semilla_mundo.gd` (allí se cambia).
	# Con `semilla != 0` en el inspector se fuerza otra semilla sólo para esta
	# ciudad (experimentos); sin tocar nada, el mapa sale siempre idéntico.
	_rng.seed = semilla if semilla != 0 else SemillaMundo.semilla_de("ciudad")
	prueba_portales.clear()
	prueba_portales_dir.clear()
	prueba_portales_frente.clear()
	prueba_esquinas.clear()
	prueba_esquinas_dir.clear()

	# 1) Localizar e inspeccionar los modelos -------------------------------
	_carpeta = _resolver_carpeta()
	if _carpeta == "":
		push_error("[GeneradorCiudad] No se encontró ninguna carpeta con modelos .gltf/.glb.")
		return
	_m("escaneo de modelos")
	_escanear(_carpeta)
	if _modelos.is_empty():
		push_error("[GeneradorCiudad] La carpeta %s no contiene modelos utilizables." % _carpeta)
		return
	_m("listas y texturas")
	_construir_listas()
	_cargar_vegetacion_extra()

	# 2) Trazado y contenedores --------------------------------------------
	_m("trazado urbano")
	_preparar_trazado()
	_m("contenedores")
	_crear_contenedores()
	_est = {"prefabs": 0, "modulares": 0, "props": 0, "vegetacion": 0, "arboles": 0,
			"parques": 0, "bancos": 0, "macetas": 0, "parcelas": 0, "plazas": 0,
			"parcelas_vacias": 0, "marcas": 0, "suelos": 0, "tramos": 0, "portales": 0,
			"palmeras": 0, "sombrillas": 0, "reposeras": 0, "arboles_costa": 0,
			"arbustos_costa": 0, "ventanas": 0, "ventanas_luz": 0}

	# 3) Construcción de la ciudad -----------------------------------------
	_m("configurar escena")
	_configurar_escena()
	_m("suelo")
	_generar_suelo()
	_m("calles y aceras")
	_generar_calles()
	_m("manzanas y edificios")
	_generar_manzanas()
	_m("paseo costero")
	_generar_paseo_costero()
	_m("playa")
	_generar_playa()
	_m("vegetación costera")
	_vegetacion_costera()
	_m("mobiliario")
	_generar_mobiliario()
	_m("volcado vegetación")
	_volcar_vegetacion()
	_m("volcado de lotes (multimesh)")
	_volcar_lotes()
	_m("macetas")
	_volcar_macetas()
	_m("volcado de playa")
	_volcar_playa()
	_m("ventanas")
	_volcar_ventanas()
	_m("colisiones de vegetación")
	_construir_colisiones_vegetacion()
	_m("peatones")
	_generar_peatones()
	# Marca de "ciudad cerrada": la usan las farolas (Farolas) para saber que ya pueden
	# leer el mobiliario real de las aceras y plantar sus postes sin meterse en un árbol.
	_est["ciudad_lista"] = 1

	# 4) Cierre -------------------------------------------------------------
	if Engine.is_editor_hint():
		_marcar_owner(get_node_or_null(NODO_CIUDAD))
		# En el editor, deja la vista 3D mirando la ciudad recién generada.
		_enfocar_vista_editor()
	var ms := Time.get_ticks_msec() - t0
	_informe(ms)
	_m_fin()


## Igual que generar_ciudad(), pero reparte el trabajo entre fotogramas para que
## la interfaz siga respondiendo durante la carga: hace await get_tree().process_frame
## entre etapas y entre lotes de cada etapa pesada. Es una corrutina, hay que
## await-earla; devuelve true si la ciudad quedó generada y false si hubo un error.
##
## El avance que emite por progreso_generacion es una ESTIMACIÓN por etapas y por
## unidades de trabajo completadas, NO una medida de tiempo. A cada etapa se le
## asigna un tramo del recorrido 0..1 según su coste aproximado:
##   escaneo de modelos       0.00 - 0.24
##   listas y texturas        0.24 - 0.29
##   trazado y contenedores   0.29 - 0.32
##   suelo                    0.32 - 0.34
##   calles y cruces          0.34 - 0.52
##   manzanas y edificios     0.52 - 0.74
##   mobiliario y vegetación  0.74 - 0.90
##   multimesh de vegetación  0.90 - 0.93
##   multimesh de piezas      0.93 - 1.00
func generar_ciudad_por_etapas() -> bool:
	var t0 := Time.get_ticks_msec()
	_etapas_ini()
	limpiar_ciudad()

	_rng = RandomNumberGenerator.new()
	# Igual que en `generar_ciudad()`: semilla FIJA de `world/semilla_mundo.gd`,
	# para que la generación por etapas dé EXACTAMENTE la misma ciudad.
	_rng.seed = semilla if semilla != 0 else SemillaMundo.semilla_de("ciudad")
	prueba_portales.clear()
	prueba_portales_dir.clear()
	prueba_portales_frente.clear()
	prueba_esquinas.clear()
	prueba_esquinas_dir.clear()

	# --- 1) Localizar la carpeta y escanear los modelos (lote por archivo) ---
	_carpeta = _resolver_carpeta()
	if _carpeta == "":
		push_error("[GeneradorCiudad] No se encontró ninguna carpeta con modelos .gltf/.glb.")
		return false
	_modelos.clear()
	_categorias.clear()
	_con_decal.clear()
	_mallas_limpias.clear()
	if not DirAccess.dir_exists_absolute(_carpeta):
		push_error("[GeneradorCiudad] No se pudo abrir la carpeta %s." % _carpeta)
		return false
	var nombres: Array[String] = []
	# `ResourceLoader.list_directory` y no `DirAccess.get_files`: en el juego
	# EXPORTADO los .gltf/.glb sólo quedan como `.import` y DirAccess no los
	# encontraría (la ciudad saldría vacía). En el editor la lista es idéntica.
	for f in ResourceLoader.list_directory(_carpeta):
		if f.get_extension().to_lower() in ["gltf", "glb"]:
			nombres.append(f)
	nombres.sort()
	var total_modelos := nombres.size()
	for k in total_modelos:
		_escanear_archivo(_carpeta, nombres[k])
		if (k % 12) == 11 or k == total_modelos - 1:
			progreso_generacion.emit(0.24 * float(k + 1) / float(maxi(total_modelos, 1)), "escaneo de modelos")
			await get_tree().process_frame
	if _modelos.is_empty():
		push_error("[GeneradorCiudad] La carpeta %s no contiene modelos utilizables." % _carpeta)
		return false

	# --- 2) Listas de trabajo y texturas extra ------------------------------
	progreso_generacion.emit(0.26, "clasificación de modelos")
	await get_tree().process_frame
	_construir_listas()
	_cargar_vegetacion_extra()

	# --- 3) Trazado, contenedores y entorno --------------------------------
	progreso_generacion.emit(0.29, "trazado urbano")
	await get_tree().process_frame
	_preparar_trazado()
	_crear_contenedores()
	_est = {"prefabs": 0, "modulares": 0, "props": 0, "vegetacion": 0, "arboles": 0,
			"parques": 0, "bancos": 0, "macetas": 0, "parcelas": 0, "plazas": 0,
			"parcelas_vacias": 0, "marcas": 0, "suelos": 0, "tramos": 0, "portales": 0,
			"palmeras": 0, "sombrillas": 0, "reposeras": 0, "arboles_costa": 0,
			"arbustos_costa": 0, "ventanas": 0, "ventanas_luz": 0}
	_configurar_escena()

	# --- 4) Suelo -----------------------------------------------------------
	progreso_generacion.emit(0.32, "terreno")
	await get_tree().process_frame
	_generar_suelo()

	# --- 5) Calles, aceras y cruces (un tramo por lote) --------------------
	progreso_generacion.emit(0.34, "calles y aceras")
	await get_tree().process_frame
	var off: Vector2 = _trazado.off
	var ext: Vector2 = _trazado.ext
	var paso: float = _trazado.paso
	var unidades := (manzanas_x + 1) + (manzanas_z + 1) + (manzanas_x + 1) * (manzanas_z + 1)
	var hechas := 0
	for i in manzanas_x + 1:
		_corredor(true, off.x + i * paso, off.y, off.y + ext.y)
		hechas += 1
		if hechas % 4 == 0:
			progreso_generacion.emit(0.34 + 0.18 * float(hechas) / float(unidades), "calles y aceras")
			await get_tree().process_frame
	for j in manzanas_z + 1:
		_corredor(false, off.y + j * paso, off.x, off.x + ext.x)
		hechas += 1
		if hechas % 4 == 0:
			progreso_generacion.emit(0.34 + 0.18 * float(hechas) / float(unidades), "calles y aceras")
			await get_tree().process_frame
	for i in manzanas_x + 1:
		for j in manzanas_z + 1:
			_interseccion(off.x + i * paso, off.y + j * paso, i, j)
			hechas += 1
			if hechas % 8 == 0:
				progreso_generacion.emit(0.34 + 0.18 * float(hechas) / float(unidades), "cruces")
				await get_tree().process_frame

	# --- 6) Manzanas y edificios (una manzana por lote) --------------------
	progreso_generacion.emit(0.52, "manzanas y edificios")
	await get_tree().process_frame
	var parques := _elegir_parques()
	var total_manzanas := manzanas_x * manzanas_z
	var manzanas_hechas := 0
	for i in manzanas_x:
		for j in manzanas_z:
			_generar_manzana(i, j, parques)
			manzanas_hechas += 1
			if manzanas_hechas % 2 == 0:
				progreso_generacion.emit(0.52 + 0.22 * float(manzanas_hechas) / float(maxi(total_manzanas, 1)), "manzanas y edificios")
				await get_tree().process_frame

	# --- 7) Paseo costero, mobiliario y vegetación (un eje por lote) -------
	_generar_paseo_costero()
	_generar_playa()
	_vegetacion_costera()
	progreso_generacion.emit(0.74, "mobiliario urbano")
	await get_tree().process_frame
	if generar_props or generar_vegetacion:
		_generar_mobiliario_ejes([true])
		progreso_generacion.emit(0.82, "vegetación")
		await get_tree().process_frame
		_generar_mobiliario_ejes([false])
	# Objetos puestos a mano (`PROPS_EXTRA`): van siempre, también por etapas.
	_colocar_props_extra()

	# --- 8) Multimesh de vegetación ---------------------------------------
	progreso_generacion.emit(0.90, "vegetación (mallas)")
	await get_tree().process_frame
	_volcar_vegetacion()

	# --- 9) Multimesh de las piezas agrupadas (un lote por paso) ----------
	progreso_generacion.emit(0.93, "cerrando la ciudad")
	await get_tree().process_frame
	var claves := _lotes.keys()
	var total_lotes := claves.size()
	for idx in total_lotes:
		_volcar_lote(String(claves[idx]))
		if (idx % 8) == 7 or idx == total_lotes - 1:
			progreso_generacion.emit(0.93 + 0.07 * float(idx + 1) / float(maxi(total_lotes, 1)), "cerrando la ciudad")
			await get_tree().process_frame
	_lotes.clear()
	_volcar_macetas()
	_volcar_playa()
	_volcar_ventanas()
	_construir_colisiones_vegetacion()
	_generar_peatones()
	_est["ciudad_lista"] = 1

	_informe(Time.get_ticks_msec() - t0)
	_etapas_fin()
	progreso_generacion.emit(1.0, "listo")
	return true


## Crea el DirectorPeatones de esta ciudad: la ciudad habitada. Le pasa los datos
## reales del mapa (trazado, plazas, parques, cruces pintados, paseo, arena, bancos
## y reposeras) y la configuración centralizada del grupo "6c. Peatones".
##
## El director construye la RED PEATONAL (veredas, cruces pintados, plazas, parques,
## paseo y arena) y coloca a los ciudadanos sobre ella: se mueven sólo por sus
## aristas y cruzan la calzada únicamente por los pasos que el generador ha pintado.
func _generar_peatones() -> void:
	director_peatones = null
	if not peatones_activos:
		return
	var raiz := get_node_or_null(NODO_CIUDAD)
	if raiz == null:
		return
	var jefe := Node3D.new()
	jefe.name = "Peatones"
	jefe.set_script(load("res://NPCs/Scripts/director_peatones.gd"))
	raiz.add_child(jefe)
	jefe.set("cantidad_total", peatones_total)
	jefe.set("cantidad_playa", mini(peatones_playa, peatones_total))
	jefe.set("proporcion_plaza", peatones_plaza)
	jefe.set("max_sentados", peatones_sentados)
	jefe.set("max_tumbados", peatones_tumbados)
	jefe.set("auditoria", peatones_auditoria)
	jefe.call("instalar", {
		"trazado": _trazado,
		"manzanas": Vector2i(manzanas_x, manzanas_z),
		"plazas": _plazas_datos,
		"parques": _parques_datos,
		"cruces": _cruces_peatones,
		"paseo": _paseo_datos,
		"arena": _arena_datos,
		"bancos": _bancos_datos,
		"reposeras": _reposeras_datos,
		"obstaculos": _obstaculos_plantas,
		"mobiliario": _obstaculos_peatones,
		# Puertas reales del mapa (centro del marco, normal hacia la calle y cuánto
		# sobresale el marco): con esto los ciudadanos simulan entrar en las casas.
		"portales": prueba_portales,
		"portales_dir": prueba_portales_dir,
		"portales_frente": prueba_portales_frente,
	})
	director_peatones = jefe


## Elimina los nodos de la ciudad generada y limpia las cachés.
func limpiar_ciudad() -> void:
	var anterior := get_node_or_null(NODO_CIUDAD)
	if anterior != null:
		anterior.free()          # liberación inmediata: permite regenerar en el acto
	_lotes.clear()
	_sector_padre.clear()
	_cont_sectores = null
	_mm_cache.clear()
	_mm_datos.clear()
	_cont.clear()
	_con_decal.clear()
	_mallas_limpias.clear()
	_pistas_planta.clear()
	_tintes_planta.clear()
	_pistas_maceta.clear()
	_pistas_palmera.clear()
	for lista in _pistas_sombrilla:
		(lista as Array).clear()
	_pistas_reposera.clear()
	_tintes_reposera.clear()
	_pistas_ventana.clear()
	_datos_ventana.clear()
	_vent_medidas.clear()
	# Datos de los peatones: cada generación los vuelve a llenar desde cero.
	_cruces_peatones.clear()
	_bancos_datos.clear()
	_plazas_datos.clear()
	_parques_datos.clear()
	_paseo_datos.clear()
	_playa_tramos.clear()
	_arena_datos.clear()
	_reposeras_datos.clear()
	_obstaculos_plantas.clear()
	_obstaculos_peatones.clear()
	_colisiones_vegetacion.clear()
	director_peatones = null


# =============================================================================
#  Paso 1: lectura y clasificación de recursos
# =============================================================================

func _resolver_carpeta() -> String:
	# Se prueban la ruta configurada y las variantes habituales; si ninguna
	# existe, se busca cualquier carpeta con "gltf" en el nombre del proyecto.
	var candidatos: Array[String] = [
		carpeta_modelos,
		"res://Exports/glTF (Godot)/",
		"res://glTF (Godot)/",
		"res://models/glTF (Godot)/",
	]
	for c in candidatos:
		if c != "" and DirAccess.dir_exists_absolute(c):
			return c
	var encontradas: Array[String] = []
	_buscar_carpetas_gltf("res://", 2, encontradas)
	return encontradas[0] if not encontradas.is_empty() else ""


func _buscar_carpetas_gltf(ruta: String, profundidad: int, salida: Array[String]) -> void:
	if profundidad < 0:
		return
	var d := DirAccess.open(ruta)
	if d == null:
		return
	for sub in d.get_directories():
		if sub.begins_with(".") or sub == "addons":
			continue
		var completa := ruta.path_join(sub)
		if sub.to_lower().contains("gltf"):
			salida.append(completa)
		else:
			_buscar_carpetas_gltf(completa, profundidad - 1, salida)


## Carga el césped propio de los parques (si existe). Los árboles y arbustos son
## geometría 3D que compone el propio script, así que no necesitan texturas.
func _cargar_vegetacion_extra() -> void:
	_tex_cesped = null
	if usar_vegetacion_propia:
		_tex_cesped = _cargar_textura(RUTA_CESPED)
	# Membrana de las azoteas: se carga siempre, porque la textura de tejado del
	# kit trae manchas oscuras y un patrón muy ruidoso (parches negros pixelados).
	_tex_techo = _cargar_textura(RUTA_TECHO)


## Carga una textura del disco: primero como recurso importado y, si aún no lo
## está, leyendo el PNG directamente.
func _cargar_textura(ruta: String) -> Texture2D:
	if ResourceLoader.exists(ruta):
		var recurso := ResourceLoader.load(ruta)
		if recurso is Texture2D:
			return recurso as Texture2D
	var imagen := Image.new()
	if imagen.load(ruta) == OK:
		imagen.generate_mipmaps()
		return ImageTexture.create_from_image(imagen)
	return null


## ¿La pieza es una plancha de azotea del kit (Roof_2x2 / Roof_4x4)?
func _es_plancha_techo(pieza: String) -> bool:
	for lado in _techos.keys():
		if (_techos[lado] as Array).has(pieza):
			return true
	return false


## Material de membrana para las planchas de azotea, con una losa de textura
## cada 4 m. Sustituye la textura original del kit, que trae manchas oscuras.
func _material_techo(pieza: String) -> Material:
	if _tex_techo == null:
		return null
	var datos: Dictionary = _modelos.get(pieza, {})
	var caja: AABB = datos.get("caja", AABB())
	var lado := maxf(1.0, caja.size.x)
	if _mat_techo.has(lado):
		return _mat_techo[lado] as Material
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = _tex_techo
	var rep := maxf(1.0, lado / 4.0)
	mat.uv1_scale = Vector3(rep, rep, 1.0)
	mat.roughness = 1.0
	mat.metallic = 0.0
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_mat_techo[lado] = mat
	return mat


## Material de la losa de azotea: la membrana se repite cada 4 m tanto a lo
## ancho como a lo largo, así el grano de la grava se ve igual de fino en
## edificios grandes y pequeños.
func _material_azotea(ancho: float, fondo: float) -> Material:
	if _tex_techo == null:
		return null
	var clave := Vector2(ancho, fondo)
	if _mat_techo.has(clave):
		return _mat_techo[clave] as Material
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = _tex_techo
	mat.albedo_color = Color(0.78, 0.78, 0.80)   # grava un poco más apagada
	mat.uv1_scale = Vector3(maxf(1.0, ancho / 4.0), maxf(1.0, fondo / 4.0), 1.0)
	mat.roughness = 1.0
	mat.metallic = 0.0
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_mat_techo[clave] = mat
	return mat


## Recorre la carpeta, carga cada .gltf/.glb, mide su caja envolvente y lo clasifica.
func _escanear(carpeta: String) -> void:
	_modelos.clear()
	_categorias.clear()
	_con_decal.clear()
	_mallas_limpias.clear()
	if not DirAccess.dir_exists_absolute(carpeta):
		return
	var nombres: Array[String] = []
	# list_directory: funciona también en el juego exportado (ver arriba).
	for f in ResourceLoader.list_directory(carpeta):
		if f.get_extension().to_lower() in ["gltf", "glb"]:
			nombres.append(f)
	nombres.sort()

	for archivo in nombres:
		_escanear_archivo(carpeta, archivo)


## Carga, mide y clasifica UN archivo de modelo. Es la unidad de trabajo del
## escaneo, para poder repartirlo entre fotogramas en la carga por etapas.
func _escanear_archivo(carpeta: String, archivo: String) -> void:
	var ruta := carpeta.path_join(archivo)
	var t_ini := Time.get_ticks_usec()
	var recurso := ResourceLoader.load(ruta)
	var t_load := Time.get_ticks_usec()
	if not (recurso is PackedScene):
		push_warning("[GeneradorCiudad] No se pudo cargar %s" % ruta)
		return
	var escena := recurso as PackedScene
	var caja := AABB()
	var decal := false
	var t_inst := t_load
	var t_aabb := t_load
	var t_decal := t_load
	var t_rec := t_load
	var desde_estado := false
	if _escanear_estado:
		var d := _datos_desde_estado(escena)
		if d.is_empty():
			_fallbacks_estado += 1      # estructura no soportada → método actual
		else:
			caja = d["caja"]
			decal = d["decal"]
			_mm_datos[escena] = {"mallas": d["mallas"], "sup": d["sup"], "malla": d["malla"], "local": d["local"]}
			desde_estado = true
			_leidos_estado += 1
		t_rec = Time.get_ticks_usec()
	if not desde_estado:
		var plantilla := escena.instantiate() as Node3D
		t_inst = Time.get_ticks_usec()
		if plantilla == null:
			return
		caja = _aabb_modelo(plantilla)
		t_aabb = Time.get_ticks_usec()
		decal = _tiene_capa_decal(plantilla)
		t_decal = Time.get_ticks_usec()
		# Los datos de agrupación se leen de ESTA MISMA instancia: así el prefab no se
		# vuelve a instanciar después (ni en _es_multimesh ni al volcar los lotes).
		_datos_malla(escena, plantilla)
		t_rec = Time.get_ticks_usec()
		plantilla.free()
	var t_fin := Time.get_ticks_usec()
	if _medir_etapas:
		_sumar_sub("load", t_ini, t_load)
		if desde_estado:
			_sumar_sub("escaneo_estado", t_load, t_rec)
		else:
			_sumar_sub("instantiate", t_load, t_inst)
			_sumar_sub("aabb", t_inst, t_aabb)
			_sumar_sub("decal", t_aabb, t_decal)
			_sumar_sub("datos_malla", t_decal, t_fin)      # recorrido + liberación
			_sumar_sub("recorrido_arbol", t_decal, t_rec)  # sólo el recorrido
			_sumar_sub("plantilla_free", t_rec, t_fin)     # sólo plantilla.free()
	var nombre := archivo.get_basename()
	var categoria := _clasificar(nombre)
	_modelos[nombre] = {"escena": escena, "caja": caja, "categoria": categoria}
	_con_decal[nombre] = decal
	if not _categorias.has(categoria):
		_categorias[categoria] = []
	(_categorias[categoria] as Array).append(nombre)


## Clasificación por nombre/función (las categorías que pidió el proyecto).
## Se compara por "palabras" del nombre (tokens), no por subcadenas, para que
## "Street" no cuente como "tree".
func _clasificar(nombre: String) -> String:
	var n := nombre.to_lower()
	var tokens := n.replace("-", "_").split("_")
	# La vegetación se comprueba antes que "sidewalk"/"prop": Prop_Planter_Single
	# y Sidewalk_Planter son mobiliario verde.
	var palabras_vegetacion := ["tree", "trees", "plant", "plants", "planter", "planters", "bush",
			"bushes", "grass", "vegetation", "veget", "arbol", "árbol", "planta", "plantas",
			"maceta", "macetas", "jardinera", "flower", "flowers", "flowerpot", "pot"]
	for t in tokens:
		if t in palabras_vegetacion:
			return "vegetacion"
	if n.begins_with("building") or n.begins_with("edificio"):
		return "edificios"
	if n.begins_with("street") or n.begins_with("road") or n.begins_with("calle") or n.begins_with("asphalt"):
		return "calles"
	if n.begins_with("sidewalk") or n.begins_with("acera") or n.begins_with("curb"):
		return "aceras"
	if n.begins_with("decal") or n.contains("marking") or n.contains("crosswalk"):
		return "marcas_viales"
	if n.begins_with("prop") or n.contains("bollard") or n.contains("lamp") or n.contains("bench") \
			or n.contains("farola") or n.contains("banco") or n.contains("bin"):
		return "props"
	if n.begins_with("brick") or n.begins_with("metal") or n.begins_with("trim") or n.begins_with("cornice") \
			or n.begins_with("roof") or n.begins_with("floor") or n.begins_with("door") \
			or n.begins_with("entrance") or n.begins_with("stairs") or n.begins_with("column"):
		return "modulos_edificio"
	return "otros"


## Construye las listas de trabajo a partir de nombre + firma geométrica medida.
func _construir_listas() -> void:
	_prefabs.clear() ; _paredes.clear() ; _paredes_bajas.clear() ; _paredes_top.clear()
	_ventanas.clear() ; _esquinas_muro.clear()
	_marcos_puerta.clear() ; _hojas_puerta.clear() ; _cornisas.clear() ; _techos.clear()
	_tramo_calle.clear() ; _plancha_asfalto.clear() ; _acera_recta.clear()
	_acera_pavimento.clear() ; _esquinas_acera.clear() ; _esquina_dir.clear()
	_linea_discontinua.clear() ; _pasos_peatones.clear() ; _pintura_esquinas.clear()
	_alcantarillas.clear()
	# Estas dos se LLENAN en este método pero se olvidaban al vaciar: al regenerar
	# en la misma sesión arrastraban las piezas de la ciudad anterior, `_elegir`
	# sorteaba entre más candidatas y la ciudad salía distinta de la primera vez
	# (la raya del eje se teselaba con otra pieza y cambiaba el número de marcas).
	# Con la semilla fija, las dos generaciones tienen que dar EXACTAMENTE el mundo.
	_linea_central.clear() ; _pasos_anchos.clear()
	_sumideros.clear() ; _bolardos.clear() ; _aires.clear() ; _vegetacion.clear()

	for clave in _modelos.keys():
		var nombre := String(clave)
		var ln := nombre.to_lower()
		var caja: AABB = _modelos[clave]["caja"]
		var s := caja.size

		# --- Edificios completos del kit ---
		if _modelos[clave]["categoria"] == "edificios" and s.y > 6.0:
			_prefabs.append(nombre)

		# --- Calzadas ---
		# Tramos de 6 m de ancho (calzada + bordillos) por 12 m de largo, que es
		# la sección completa de un vial: 3 m de acera + 6 de calzada + 3 de acera.
		if ln.begins_with("street") and absf(s.x - 6.0) < 0.1 and absf(s.z - 12.0) < 0.1 and s.y > 0.1:
			_tramo_calle.append(nombre)
		# Planchas planas 6x6 m para los cruces.
		elif ln.begins_with("street") and absf(s.y) < 0.02 and absf(s.x - 6.0) < 0.1 and absf(s.z - 6.0) < 0.1:
			_plancha_asfalto.append(nombre)

		# --- Aceras ---
		# Piezas macizas (de la calzada a cota de acera) frente a las variantes
		# "Stripe", que son planos de pintura a cota de calzada.
		if ln.contains("sidewalk_straight") and s.y > 0.1:
			_acera_recta.append(nombre)
		if ln.contains("sidewalk_nocurb"):
			_acera_pavimento.append(nombre)
		if ln.contains("sidewalk_corner"):
			_esquina_dir[nombre] = _medir_esquina_redondeada(caja, _modelos[clave]["escena"])
			if s.y > 0.1:
				_esquinas_acera.append(nombre)
			elif s.y < 0.04:
				_pintura_esquinas.append(nombre)

		# --- Marcas viales ---
		if ln.contains("brokenline"):
			_linea_discontinua.append(nombre)
		# Raya doble amarilla del eje de la calzada (avenidas de varios carriles):
		# SÓLO la pieza RECTA y estrecha (6 x 0.39 m). Las piezas "Curve_..._DoubleYellow"
		# del kit son cuadrantes de 9.2 x 9.2 m pensados para los giros: si se cuelan en
		# esta lista, `_elegir` las sortea entre las rectas y la raya del eje sale
		# torcida, con tramos pegados, cortes en diagonal y superposiciones.
		if ln.contains("doubleyellow") and not ln.contains("curve") \
				and s.z < 1.0 and s.x > 1.0:
			_linea_central.append(nombre)
		# Pasos de peatones: el normal (4.5 x 5.4 m) y el ancho (3.1 x 11.4 m),
		# que es el que cubre la calzada entera en las avenidas.
		if ln.contains("crosswalk"):
			if s.z < 7.0:
				_pasos_peatones.append(nombre)
			else:
				_pasos_anchos.append(nombre)

		# --- Mobiliario de calle ---
		if ln.contains("manhole"):
			_alcantarillas.append(nombre)
		if ln.contains("drain"):
			_sumideros.append(nombre)
		if ln.contains("bollard"):
			_bolardos.append(nombre)
		if ln.contains("acunit") or ln.contains("ac_unit"):
			_aires.append(nombre)
		# Vegetación del kit: las jardineras con reja (Prop_Planter_Single,
		# Sidewalk_Planter) se descartan a propósito: dejan el suelo liso y
		# continuo, y la vegetación la ponen los árboles y arbustos 3D.
		if _modelos[clave]["categoria"] == "vegetacion":
			if ln.contains("planter"):
				# Canteros del kit: antes se descartaban por completo. El de acera
				# (Sidewalk_Planter: cemento con tierra) se guarda como MACETA
				# para los árboles plantados sobre pavimento (aceras y plazas
				# duras); en el césped y los jardines los árboles van sin maceta.
				if _maceta_modelo == "" or ln.contains("sidewalk"):
					_maceta_modelo = nombre
			else:
				_vegetacion.append(nombre)

		# --- Módulos de fachada (firma 2.00 x 3.00 m, poco fondo) ---
		var es_muro := absf(s.x - MODULO_ANCHO) < 0.06 and absf(s.y - PLANTA_ALTO) < 0.06 \
				and s.z > 0.05 and s.z < 0.7 and caja.position.y > -0.05
		if es_muro:
			if ln.contains("doorframe") or ln.contains("door_frame"):
				_marcos_puerta.append(nombre)
			else:
				_paredes.append(nombre)
				if ln.contains("window"):
					_ventanas.append(nombre)
				if ln.contains("firstfloor") or ln.contains("first_floor") or ln.contains("bottom"):
					_paredes_bajas.append(nombre)
				if ln.contains("toptrim") or ln.contains("top_trim"):
					_paredes_top.append(nombre)
		# Bloque de esquina del perímetro: 2.00 x 3.00 x 2.00 m
		if ln.contains("corner") and absf(s.x - 2.0) < 0.1 and absf(s.y - PLANTA_ALTO) < 0.1 \
				and absf(s.z - 2.0) < 0.1 and not ln.contains("roof") and not ln.contains("slate") \
				and not ln.contains("sidewalk") and not ln.contains("decal") and not ln.contains("ribbon"):
			_esquinas_muro.append(nombre)
		# Hoja de puerta: ~1.00 x 2.20 m
		if ln.begins_with("door_") and absf(s.x - 1.0) < 0.1 and s.y > 2.0 and s.y < 2.5:
			_hojas_puerta.append(nombre)

		# --- Cornisas: banda de 2 x 1 m que sobresale de la fachada ---
		# (sólo piezas "Cornice_": Entrance/Stairs son zócalos, no cornisas)
		if ln.begins_with("cornice") and absf(s.x - MODULO_ANCHO) < 0.06 and absf(s.y - 1.0) < 0.06 \
				and s.z > 0.3 and (caja.position.z + s.z) > 0.3 and not ln.contains("90angle"):
			_cornisas.append(nombre)

		# --- Azoteas planas: 2x2 m o 4x4 m, sin grosor ---
		if absf(s.y) < 0.02 and absf(s.x - s.z) < 0.06 and not ln.contains("90angle") \
				and ln.contains("roof"):
			var lado := int(round(s.x))
			if lado == 2 or lado == 4:
				if not _techos.has(lado):
					_techos[lado] = []
				(_techos[lado] as Array).append(nombre)

	# Si el kit trae esquinas redondeadas se usan ésas (las de esquina recta
	# quedan sin chaflán que orientar).
	var redondas: Array[String] = []
	for n in _esquinas_acera:
		if n.to_lower().contains("round"):
			redondas.append(n)
	if not redondas.is_empty():
		_esquinas_acera = redondas

	# Orden estable de las listas (una semilla fija da siempre la misma ciudad).
	_marcos_puerta.sort()
	_hojas_puerta.sort()

	_construir_familias()


## Agrupa las piezas del kit en familias de fachada coherentes (brick / metal /
## trim). Cada familia se completa con lo que tenga a mano, de modo que un
## edificio entero (planta baja, plantas, remate, esquinas y cornisa) pueda
## levantarse con una sola familia y nunca quede una celda sin cerrar.
func _construir_familias() -> void:
	_familias.clear()
	for fam: String in ["brick", "metal", "trim"]:
		var f := {
			"muros": _por_familia(_paredes, fam, true),
			"bajas": _por_familia(_paredes_bajas, fam, true),
			"ventanas": _por_familia(_ventanas, fam, true),
			"top": _por_familia(_paredes_top, fam, true),
			"esquinas": _por_familia(_esquinas_muro, fam),
			"cornisas": _por_familia(_cornisas, fam),
		}
		# Rellenos: si la familia no tiene pieza para una planta se repite una
		# pared lisa de la MISMA familia, antes que mezclar texturas.
		if (f["bajas"] as Array).is_empty():
			f["bajas"] = f["muros"]
		if (f["ventanas"] as Array).is_empty():
			f["ventanas"] = f["muros"]
		if (f["top"] as Array).is_empty():
			f["top"] = f["muros"]
		_familias[fam] = f


## Piezas de 'lista' cuyo nombre contiene 'fam'. Con 'solo_fachada' se descartan
## las piezas de borde (ángulos de 90°, tapas, guardas, semicolumnas y paredes de
## interior): son remates que, puestos en medio de un muro, dejan aletas y
## paneles a medio terminar. Nunca se usan como muro normal.
func _por_familia(lista: Array, fam: String, solo_fachada: bool = false) -> Array[String]:
	var salida: Array[String] = []
	if fam == "":
		return salida
	var descartes := ["90angle", "topcover", "guard", "interiorwall", "interior_wall",
			"halfcolumn", "halftrim", "corner", "inset_window", "wall_guard"]
	for n in lista:
		var ln := String(n).to_lower()
		if ln.contains("interiorwall") or ln.contains("interior_wall"):
			continue
		var borde := false
		if solo_fachada:
			for d: String in descartes:
				if ln.contains(d):
					borde = true
					break
		if borde:
			continue
		if ln.contains(fam):
			salida.append(String(n))
	return salida


## Deduce en qué esquina del modelo (en planta) está el chaflán redondeado:
## la esquina redondeada es la que queda más lejos de cualquier vértice.
## Devuelve (0,0) si el modelo no tiene una esquina realmente recortada.
func _medir_esquina_redondeada(caja: AABB, escena: PackedScene) -> Vector2i:
	var plantilla := escena.instantiate() as Node3D
	if plantilla == null:
		return Vector2i(0, 0)
	var verts := PackedVector3Array()
	_vertices(plantilla, verts)
	plantilla.free()
	if verts.is_empty():
		return Vector2i(0, 0)
	var esquinas: Array[Vector2] = [
		Vector2(caja.position.x, caja.position.z),
		Vector2(caja.end.x, caja.position.z),
		Vector2(caja.position.x, caja.end.z),
		Vector2(caja.end.x, caja.end.z),
	]
	var direcciones: Array[Vector2i] = [Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(1, 1)]
	var mejor := 0
	var mejor_dist := -1.0
	for k in 4:
		var d := INF
		for v in verts:
			d = minf(d, Vector2(v.x, v.z).distance_to(esquinas[k]))
		if d > mejor_dist:
			mejor_dist = d
			mejor = k
	# Un chaflán real deja la esquina original a más de 40 cm de cualquier vértice.
	if mejor_dist < 0.4:
		return Vector2i(0, 0)
	return direcciones[mejor]


# =============================================================================
#  Utilidades de medición
# =============================================================================

## AABB exacta de un modelo, leyendo sus vértices (más fiable que get_aabb()).
## AABB del modelo, en el espacio local de `nodo`. Por defecto usa la unión de las cajas
## de malla (P1, activado); el método original por vértices sigue disponible con
## `usar_aabb_por_cajas = false` o PRISMAX_AABB_CAJAS=0.
func _aabb_modelo(nodo: Node) -> AABB:
	if _aabb_cajas:
		return _aabb_por_cajas(nodo)
	return _aabb_vertices(nodo)


## Método EXPERIMENTAL: caja envolvente uniendo las cajas de las mallas
## (`Mesh.get_aabb()` transformada por la transformación RELATIVA de cada una
## respecto a `nodo`, el mismo espacio que usa `_aabb_vertices`). No lee los
## vértices, así que no copia arrays de superficie. No sustituye a `_aabb_vertices`.
func _aabb_por_cajas(nodo: Node) -> AABB:
	var pila: Array[Node] = [nodo]
	var caja := AABB()
	var primera := true
	while not pila.is_empty():
		var n: Node = pila.pop_back()
		for c in n.get_children():
			pila.append(c)
		if n is MeshInstance3D:
			var mi := n as MeshInstance3D
			if mi.mesh == null:
				continue
			var c2: AABB = _transform_relativo(nodo, mi) * mi.get_aabb()
			if primera:
				caja = c2
				primera = false
			else:
				caja = caja.merge(c2)
	return caja


func _aabb_vertices(nodo: Node) -> AABB:
	var verts := PackedVector3Array()
	_vertices(nodo, verts)
	if verts.is_empty():
		return AABB()
	var caja := AABB(verts[0], Vector3.ZERO)
	for v in verts:
		caja = caja.expand(v)
	return caja


## Acumula en 'salida' los vértices de todas las mallas, en el espacio de 'nodo'.
func _vertices(nodo: Node, salida: PackedVector3Array) -> void:
	var pila: Array[Node] = [nodo]
	while not pila.is_empty():
		var n: Node = pila.pop_back()
		for c in n.get_children():
			pila.append(c)
		if n is MeshInstance3D:
			var mi := n as MeshInstance3D
			if mi.mesh == null:
				continue
			var t := _transform_relativo(nodo, mi)
			for sup in mi.mesh.get_surface_count():
				var matriz := mi.mesh.surface_get_arrays(sup)
				if matriz.is_empty():
					continue
				var datos: Variant = matriz[Mesh.ARRAY_VERTEX]
				if datos == null:
					continue
				for v in (datos as PackedVector3Array):
					salida.append(t * v)


## Transformación de 'nodo' al espacio de su antepasado 'raiz'.
func _transform_relativo(raiz: Node, nodo: Node) -> Transform3D:
	var t := Transform3D.IDENTITY
	var actual: Node = nodo
	while actual != null and actual != raiz:
		if actual is Node3D:
			t = (actual as Node3D).transform * t
		actual = actual.get_parent()
	return t


## Devuelve {malla, local} si el modelo es un único MeshInstance3D (agrupable
## en MultiMesh, ya que los materiales viven en las superficies de la malla).
##
## Los datos se calculan UNA sola vez por PackedScene (caché `_mm_datos`): el
## escaneo ya instancia el prefab, así que allí se reutiliza esa misma instancia
## en vez de crear otra. El resultado es idéntico al de instanciar y mirar.
func _malla_unica(escena: PackedScene, permitir_multi_superficie: bool = false) -> Dictionary:
	var info: Dictionary = _mm_datos.get(escena, {})
	if info.is_empty():
		var raiz := escena.instantiate()
		info = _datos_malla(escena, raiz)
		raiz.free()
	# Sólo es agrupable si tiene UNA malla y esa malla tiene UNA superficie (las
	# mallas con varias capas — calzada + pintura — se instancian una a una),
	# salvo que el llamante permita varias superficies (cada una con su material),
	# como el cantero Sidewalk_Planter (cemento + tierra).
	if int(info["mallas"]) == 1 and int(info["sup"]) >= 1 \
			and (int(info["sup"]) == 1 or permitir_multi_superficie):
		return {"malla": info["malla"], "local": info["local"]}
	return {}


## Mide las mallas de una instancia YA existente (nº de MeshInstance3D, superficies
## de la única malla y su transformación relativa a la raíz) y lo cachea por
## PackedScene. Guarda la MALLA (recurso compartido del PackedScene, que sigue vivo
## en `_modelos`) y un Transform3D: nunca una referencia al nodo instanciado.
## P2-C: obtiene del estado del PackedScene lo mismo que el método actual obtiene
## instanciando el template. Mismo espacio de coordenadas que `_aabb_por_cajas` (une las
## cajas de las mallas transformadas relativas a la raíz). Devuelve {} si algo no se puede
## reconstruir con seguridad (sub-escena instanciada, malla ausente o transformación en la
## raíz) para que el llamante caiga al método actual. No instancia nada.
func _datos_desde_estado(escena: PackedScene) -> Dictionary:
	var st := escena.get_state()
	if st == null:
		return {}
	var trans := {}                 ## ruta -> Transform3D (identidad si no se guarda)
	var caja := AABB()
	var primera := true
	var mallas := 0
	var sup := 0
	var malla: Mesh = null
	var local := Transform3D()
	var decal := false
	for i in st.get_node_count():
		var ruta := String(st.get_node_path(i))
		if st.is_node_instance_placeholder(i):
			return {}               ## sub-escena instanciada: no inspeccionable aquí
		var tr := Transform3D.IDENTITY
		for p in st.get_node_property_count(i):
			if String(st.get_node_property_name(i, p)) == "transform":
				tr = st.get_node_property_value(i, p) as Transform3D
		trans[ruta] = tr
		if String(st.get_node_type(i)) != "MeshInstance3D":
			continue
		## Transformación relativa: se compone por la ruta del nodo (la raíz se omite).
		var rel := Transform3D.IDENTITY
		var acum := ""
		for parte in ruta.split("/"):
			acum = parte if acum == "" else acum + "/" + parte
			if trans.has(acum):
				rel = (trans[acum] as Transform3D) * rel
		var m: Mesh = null
		for p in st.get_node_property_count(i):
			if String(st.get_node_property_name(i, p)) == "mesh":
				m = st.get_node_property_value(i, p) as Mesh
		if m == null:
			return {}               ## sin malla: no reproducible con seguridad
		for s in m.get_surface_count():
			var mat := m.surface_get_material(s)
			if mat != null and _es_capa_decal(mat):
				decal = true
		var c2: AABB = rel * m.get_aabb()
		if primera:
			caja = c2
			primera = false
		else:
			caja = caja.merge(c2)
		mallas += 1
		if mallas == 1:
			malla = m
			local = rel
			sup = m.get_surface_count()
	if primera:
		return {}                   ## sin mallas: lo trata el método actual
	if trans.has("") and (trans[""] as Transform3D) != Transform3D.IDENTITY:
		return {}                   ## transformación en la raíz: la composición la ignora
	if trans.has(".") and (trans["."] as Transform3D) != Transform3D.IDENTITY:
		return {}
	if mallas > 1:
		malla = null
		local = Transform3D()
		sup = 0
	return {"caja": caja, "decal": decal, "mallas": mallas, "sup": sup, "malla": malla, "local": local}


func _datos_malla(escena: PackedScene, raiz: Node) -> Dictionary:
	var mallas: Array[Node] = []
	var pila: Array[Node] = [raiz]
	while not pila.is_empty():
		var n: Node = pila.pop_back()
		for c in n.get_children():
			pila.append(c)
		if n is MeshInstance3D:
			mallas.append(n)
	var sup := 0
	var malla: Mesh = null
	var local := Transform3D()
	if mallas.size() == 1:
		var mi := mallas[0] as MeshInstance3D
		if mi.mesh != null:
			sup = mi.mesh.get_surface_count()
			malla = mi.mesh
			local = _transform_relativo(raiz, mi)
	var datos := {"mallas": mallas.size(), "sup": sup, "malla": malla, "local": local}
	_mm_datos[escena] = datos
	return datos


func _es_multimesh(nombre: String) -> bool:
	if not _mm_cache.has(nombre):
		# Se aceptan también las mallas de VARIAS superficies (cada una con su
		# material): MultiMesh las dibuja igual que las de una sola, y así entran
		# los muros modulares, suelos, calles, tejados y marcos de puerta, que son
		# el grueso de las piezas de la ciudad.
		var datos := _malla_unica(_modelos[nombre]["escena"], true)
		_mm_cache[nombre] = not datos.is_empty()
	return bool(_mm_cache[nombre])


## ¿Es esta capa la pintura del kit? (material "MI_StreetDecals", con blending).
func _es_capa_decal(mat: Material) -> bool:
	if mat is BaseMaterial3D:
		var m := mat as BaseMaterial3D
		if m.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
			return true
	return String(mat.resource_name).to_lower().contains("decal") if mat != null else false


## ¿El modelo trae capas de pintura propietarias? (tramos y planchas de asfalto
## las traen pintadas; el generador prefiere colocar sus propias marcas).
func _tiene_capa_decal(raiz: Node) -> bool:
	var pila: Array[Node] = [raiz]
	while not pila.is_empty():
		var n: Node = pila.pop_back()
		for c in n.get_children():
			pila.append(c)
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
			var malla: Mesh = (n as MeshInstance3D).mesh
			for i in malla.get_surface_count():
				if _es_capa_decal(malla.surface_get_material(i)):
					return true
	return false


## Sustituye las mallas del nodo por copias sin la capa de pintura.
func _quitar_capas_decal(nodo: Node) -> void:
	if nodo is MeshInstance3D and (nodo as MeshInstance3D).mesh != null:
		var mi := nodo as MeshInstance3D
		mi.mesh = _malla_sin_decal(mi.mesh)
	for c in nodo.get_children():
		_quitar_capas_decal(c)


## Copia de una malla sin sus superficies de pintura (se cachea por malla).
func _malla_sin_decal(malla: Mesh) -> Mesh:
	if _mallas_limpias.has(malla):
		return _mallas_limpias[malla] as Mesh
	var limpia := ArrayMesh.new()
	for i in malla.get_surface_count():
		var mat: Material = malla.surface_get_material(i)
		if _es_capa_decal(mat):
			continue
		var capas: Array = malla.surface_get_arrays(i)
		if capas.is_empty():
			continue
		limpia.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, capas)
		limpia.surface_set_material(limpia.get_surface_count() - 1, mat)
	if limpia.get_surface_count() == 0:
		limpia = null        # no quedaba nada sólido: se deja la malla original
		_mallas_limpias[malla] = malla
		return malla
	_mallas_limpias[malla] = limpia
	return limpia


# =============================================================================
#  Paso 2: trazado y contenedores
# =============================================================================

func _preparar_trazado() -> void:
	var calzada := maxf(6.0, roundf(ancho_calzada / 6.0) * 6.0)      # múltiplo de 6 m
	var acera := maxf(3.0, roundf(ancho_acera / 3.0) * 3.0)           # múltiplo de 3 m
	var manzana := maxf(12.0, roundf(tamano_manzana / 6.0) * 6.0)     # múltiplo de 6 m
	var hw := calzada * 0.5 + acera                                   # semiancho del vial
	var paso := manzana + 2.0 * hw                                    # distancia entre líneas de calle
	var ext := Vector2(float(manzanas_x) * paso, float(manzanas_z) * paso)
	_trazado = {
		"calzada": calzada,
		"acera": acera,
		"manzana": manzana,
		"hw": hw,
		"paso": paso,
		"ext": ext,
		"off": -ext * 0.5,
	}


func _crear_contenedores() -> void:
	var raiz := Node3D.new()
	raiz.name = NODO_CIUDAD
	add_child(raiz)
	var nombres: Array[String] = ["Suelo", "Calles", "Aceras", "Edificios", "Vegetacion", "Props", "MarcasViales"]
	for n in nombres:
		var c := Node3D.new()
		c.name = n
		raiz.add_child(c)
		_cont[n] = c
	# Subcontenedor para los edificios completos (los modulares van a MultiMesh).
	var pref := Node3D.new()
	pref.name = "Prefabricados"
	(_cont["Edificios"] as Node3D).add_child(pref)
	_cont["Prefabricados"] = pref
	# Subcontenedor de los edificios modulares (piezas sueltas + su colisión).
	var mods := Node3D.new()
	mods.name = "Modulares"
	(_cont["Edificios"] as Node3D).add_child(mods)
	_cont["Modulares"] = mods


# =============================================================================
#  Paso 3: colocación de piezas
# =============================================================================

## Transformación de colocación: posición + giro en Y + escala uniforme.
func _t(pos: Vector3, giro: float = 0.0, escala: float = 1.0) -> Transform3D:
	var base := Basis(Vector3.UP, giro)
	if not is_equal_approx(escala, 1.0):
		base = base.scaled(Vector3.ONE * escala)
	return Transform3D(base, pos)


## Giro en Y (múltiplo de 90°) que lleva 'dir_modelo' sobre 'dir_deseada'.
func _rot_para_dir(dir_modelo: Vector2i, dir_deseada: Vector2i) -> float:
	var modelo := Vector2(dir_modelo).normalized()
	var deseada := Vector2(dir_deseada).normalized()
	for k in 4:
		var giro := PI * 0.5 * float(k)
		var rotado := Vector2(modelo.x * cos(giro) + modelo.y * sin(giro),
				-modelo.x * sin(giro) + modelo.y * cos(giro))
		if rotado.dot(deseada) > 0.9:
			return giro
	return 0.0


func _elegir(lista: Array) -> String:
	if lista.is_empty():
		return ""
	return String(lista[_rng.randi_range(0, lista.size() - 1)])


## Coloca una pieza: agrupada en MultiMesh si es posible, si no instanciada.
## Con 'limpiar_decal' se instancia suelta y sin su capa de pintura.
## Si la casa en curso está EDITA A MANO (material propio u oculta), sus piezas se
## instancian sueltas: el lote compartido de las demás casas no se toca.
func _colocar(pieza: String, xf: Transform3D, padre: Node3D, limpiar_decal: bool = false) -> void:
	if pieza == "":
		# Cualquier celda sin pieza sería un hueco en la fachada: se cuenta para
		# que el informe final avise si alguna vez pasara.
		_est["piezas_vacias"] = int(_est.get("piezas_vacias", 0)) + 1
		return
	if _ocultar_actual:
		return                      # casa oculta: su malla no llega al mundo
	var agrupable := usar_multimesh and not (limpiar_decal and bool(_con_decal.get(pieza, false)))
	if agrupable and _es_multimesh(pieza) and _material_edificio == null:
		# La pieza se guarda en el lote de SU sector (bloque). Un sector es la
		# unidad que después se puede activar, dibujar o descargar por separado;
		# con agrupar_por_sector apagado todas caen en "0_0" y el resultado es el
		# de antes (un lote por pieza para toda la ciudad).
		if not _lotes.has(pieza):
			_lotes[pieza] = {}
		var por_sector: Dictionary = _lotes[pieza]
		var clave := _clave_sector(xf.origin) if agrupar_por_sector else "0_0"
		if not por_sector.has(clave):
			por_sector[clave] = {
				"pistas": [],
				"padre": _padre_sector(clave) if agrupar_por_sector else padre,
			}
		var grupo: Dictionary = por_sector[clave]
		(grupo["pistas"] as Array).append(xf)
	else:
		_instanciar_pieza(pieza, xf, padre, pieza, limpiar_decal)


## Clave del sector (bloque) que contiene un punto del mundo.
func _clave_sector(p: Vector3) -> String:
	var lado := maxf(1.0, lado_sector)
	return "%d_%d" % [int(floorf(p.x / lado)), int(floorf(p.z / lado))]


## Contenedor de un sector, creado la primera vez que una pieza cae en él. Todos
## los sectores viven bajo un único nodo "Sectores" colgado del nodo de ciudad,
## de modo que activar o descargar una zona es operar sobre UN nodo.
func _padre_sector(clave: String) -> Node3D:
	if _sector_padre.has(clave):
		return _sector_padre[clave] as Node3D
	if _cont_sectores == null or not is_instance_valid(_cont_sectores):
		_cont_sectores = Node3D.new()
		_cont_sectores.name = "Sectores"
		var raiz := get_node_or_null(NODO_CIUDAD)
		if raiz != null:
			raiz.add_child(_cont_sectores)
		else:
			add_child(_cont_sectores)
		_marcar_owner(_cont_sectores)
	var sector := Node3D.new()
	sector.name = "S_%s" % clave
	_cont_sectores.add_child(sector)
	_sector_padre[clave] = sector
	return sector


func _instanciar_pieza(pieza: String, xf: Transform3D, padre: Node3D, nombre: String,
		limpiar_decal: bool = false) -> Node3D:
	var escena := _modelos[pieza]["escena"] as PackedScene
	var nodo := escena.instantiate() as Node3D
	# Un nombre de nodo no admite ':' (los ids de edición lo usan: "tapa:V3:2").
	nodo.name = String(nombre).replace(":", "_")
	nodo.transform = xf
	if limpiar_decal:
		_quitar_capas_decal(nodo)
	if _es_plancha_techo(pieza):
		# Azotea suelta: misma membrana de grava que las agrupadas.
		var mat_techo := _material_techo(pieza)
		if mat_techo != null:
			for n in nodo.find_children("*", "MeshInstance3D", true, false):
				(n as MeshInstance3D).material_override = mat_techo
	# Edición de material: TODAS las mallas de esta casa llevan el material pedido.
	# La casa se construye aparte (instanciada), así que el cambio no toca a las
	# demás casas del mismo tipo.
	if _material_edificio != null:
		if nodo is MeshInstance3D:
			(nodo as MeshInstance3D).material_override = _material_edificio
		for n in nodo.find_children("*", "MeshInstance3D", true, false):
			(n as MeshInstance3D).material_override = _material_edificio
	if _ocultar_actual:
		# Casa oculta a mano: el nodo se descarta y no entra en el árbol.
		nodo.free()
		return null
	padre.add_child(nodo)
	return nodo


## Losa horizontal (rect en XZ) con la cara superior en 'techo' (por defecto
## Y_LOSA, cota de acera) y la inferior en Y_SUELO.
func _losa(rect: Rect2, color: Color, con_malla: bool, con_colision: bool, padre: Node3D,
		nombre: String, techo: float = Y_LOSA) -> void:
	var alto := techo - Y_SUELO
	var tam := Vector3(rect.size.x, alto, rect.size.y)
	var cuerpo := StaticBody3D.new()
	cuerpo.name = nombre
	cuerpo.position = Vector3(rect.get_center().x, Y_SUELO + alto * 0.5, rect.get_center().y)
	if con_malla:
		var caja := BoxMesh.new()
		caja.size = tam
		var mi := MeshInstance3D.new()
		mi.mesh = caja
		var mat := StandardMaterial3D.new()
		mat.albedo_color = color
		mat.roughness = 0.95
		mi.material_override = mat
		cuerpo.add_child(mi)
	if con_colision:
		var forma := CollisionShape3D.new()
		var caja_col := BoxShape3D.new()
		caja_col.size = tam
		forma.shape = caja_col
		cuerpo.add_child(forma)
	padre.add_child(cuerpo)


## Añade colisión envolvente a un nodo, sólo si el modelo no trae ya una.
func _anadir_colision_caja(nodo: Node3D, caja: AABB) -> void:
	if _tiene_colision(nodo):
		return
	var cuerpo := StaticBody3D.new()
	cuerpo.name = "Colision"
	var forma := CollisionShape3D.new()
	var caja_col := BoxShape3D.new()
	caja_col.size = caja.size
	forma.shape = caja_col
	forma.position = caja.get_center()
	cuerpo.add_child(forma)
	nodo.add_child(cuerpo)


func _tiene_colision(nodo: Node) -> bool:
	var pila: Array[Node] = [nodo]
	while not pila.is_empty():
		var n: Node = pila.pop_back()
		if n is CollisionShape3D or n is StaticBody3D or n is Area3D:
			return true
		for c in n.get_children():
			pila.append(c)
	return false


# =============================================================================
#  Terreno y viario
# =============================================================================

# =============================================================================
#  Cámara, luz y entorno (opcional: sólo si la escena no los tiene)
# =============================================================================

## Añade Cámara + Sol + Entorno para que la ciudad se vea al pulsar Play.
## No toca nada si esos nodos ya existen (así respeta escenas con su propia cámara).
func _configurar_escena() -> void:
	if not crear_camara_y_luz:
		return
	var raiz: Node = null
	if is_inside_tree():
		var arbol := get_tree()
		raiz = arbol.edited_scene_root if Engine.is_editor_hint() else arbol.current_scene
	if raiz == null:
		raiz = self

	if raiz.get_node_or_null("Entorno") == null:
		var entorno := WorldEnvironment.new()
		entorno.name = "Entorno"
		var env := Environment.new()
		env.background_mode = Environment.BG_SKY
		var cielo := Sky.new()
		var mat := ProceduralSkyMaterial.new()
		mat.sky_top_color = Color(0.30, 0.47, 0.76)
		mat.sky_horizon_color = Color(0.76, 0.81, 0.87)
		mat.ground_bottom_color = Color(0.21, 0.21, 0.22)
		mat.ground_horizon_color = Color(0.58, 0.59, 0.58)
		cielo.sky_material = mat
		env.sky = cielo
		env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
		env.ambient_light_sky_contribution = 0.6
		env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
		env.ssao_enabled = true
		env.fog_enabled = true
		env.fog_light_color = Color(0.73, 0.76, 0.81)
		env.fog_density = 0.00035
		entorno.environment = env
		# Diferido: este método puede correr dentro del _ready del generador
		# (generar al iniciar) y el padre rechaza add_child mientras monta sus
		# hijos ("Parent node is busy setting up children"). Con call_deferred
		# la cámara, el sol y el cielo aparecen igual, un fotograma después.
		raiz.add_child.call_deferred(entorno)
		_preparar_para_guardar(entorno, raiz)

	if raiz.get_node_or_null("Sol") == null:
		var sol := DirectionalLight3D.new()
		sol.name = "Sol"
		sol.rotation_degrees = Vector3(-52.0, 15.0, 0.0)
		sol.light_energy = 1.25
		sol.shadow_enabled = true
		# Sombras: distancia ajustada al tamaño de la ciudad y sesgo alto. Es lo
		# que quita el "acné" de sombra: los parches oscuros y pixelados que
		# salían sobre las azoteas y las aceras.
		sol.directional_shadow_max_distance = 260.0
		sol.shadow_bias = 0.04
		sol.shadow_normal_bias = 2.0
		sol.shadow_blur = 1.2
		sol.directional_shadow_blend_splits = true
		raiz.add_child.call_deferred(sol)
		_preparar_para_guardar(sol, raiz)

	if raiz.get_node_or_null("CamaraCiudad") == null:
		var cam := Camera3D.new()
		cam.name = "CamaraCiudad"
		cam.position = Vector3(168.0, 124.0, 168.0)
		cam.rotation_degrees = Vector3(-27.5, 45.0, 0.0)
		cam.current = true
		if camara_libre and ResourceLoader.exists("res://camara_libre.gd"):
			cam.set_script(ResourceLoader.load("res://camara_libre.gd"))
		raiz.add_child.call_deferred(cam)
		_preparar_para_guardar(cam, raiz)


## En el editor marca el owner para que el nodo se guarde con la escena.
func _preparar_para_guardar(nodo: Node, raiz: Node) -> void:
	if _vista_editor:
		return
	if Engine.is_editor_hint() and is_inside_tree() and raiz == get_tree().edited_scene_root:
		nodo.owner = raiz


## Enfoca la vista 3D del editor en la ciudad recién generada (sólo editor).
func _enfocar_vista_editor() -> void:
	if not Engine.is_editor_hint():
		return
	var vista := EditorInterface.get_editor_viewport_3d()
	if vista == null:
		return
	var cam := vista.get_camera_3d()
	if cam == null:
		return
	cam.look_at_from_position(Vector3(168.0, 124.0, 168.0), Vector3(0.0, 6.0, 0.0), Vector3.UP)


func _generar_suelo() -> void:
	var off: Vector2 = _trazado.off
	var ext: Vector2 = _trazado.ext
	var hw: float = _trazado.hw
	var margen := 2.0
	var rect := Rect2(off.x - hw - margen, off.y - hw - margen,
			ext.x + 2.0 * (hw + margen), ext.y + 2.0 * (hw + margen))
	_losa(rect, COLOR_SUELO, true, colisiones_suelo, _cont["Suelo"], "Terreno", Y_TERRENO)
	_est["suelos"] = int(_est.get("suelos", 0)) + 1


func _generar_calles() -> void:
	var off: Vector2 = _trazado.off
	var ext: Vector2 = _trazado.ext
	var paso: float = _trazado.paso
	# Calles verticales (discurren en Z) y horizontales (en X)
	for i in manzanas_x + 1:
		_corredor(true, off.x + i * paso, off.y, off.y + ext.y)
	for j in manzanas_z + 1:
		_corredor(false, off.y + j * paso, off.x, off.x + ext.x)
	# Cruces
	for i in manzanas_x + 1:
		for j in manzanas_z + 1:
			_interseccion(off.x + i * paso, off.y + j * paso, i, j)


## Distancia (m) desde el borde de un cruce hasta donde puede empezar la pintura de un
## tramo: los pasos de peatones se colocan a 2.27 m del borde del cruce y miden lo que
## mida la pieza (se toma la más profunda de las que se pueden usar con esta calzada),
## más 15 cm de holgura. No es una constante inventada: sale de la geometría real de las
## piezas y de dónde las coloca `_interseccion`.
func _margen_pasos() -> float:
	var prof := 4.5
	var lista: Array = _pasos_peatones
	if float(_trazado.calzada) >= 9.0 and not _pasos_anchos.is_empty():
		lista = _pasos_anchos
	for nombre_p in lista:
		var caja_p: AABB = _modelos[nombre_p]["caja"]
		prof = maxf(prof, minf(caja_p.size.x, caja_p.size.z))
	return 2.27 + prof * 0.5 + 0.15


## Largo (m) de una pieza de marca a lo largo de la calle. Las rayas del kit están
## modeladas sobre su eje X local (la colocación las gira 90° en las calles que van en
## Z), así que el largo es `size.x`; una pieza más larga en Z se descarta, porque
## teselarla daría pasos equivocados.
func _largo_pieza_marca(pieza: String) -> float:
	if pieza == "" or not _modelos.has(pieza):
		return 0.0
	var caja: AABB = _modelos[pieza]["caja"]
	if caja.size.z > caja.size.x:
		return 0.0
	return caja.size.x


## Corredor viario: p = línea de calle, d0..d1 = extensión del núcleo urbano.
## Sección: acera + calzada + acera. La acera se compone con piezas macizas de
## 3x3 m (su bordillo mira a la calzada) y la calzada con planchas planas de
## asfalto de 6x6 m teseladas a lo largo y a lo ancho (avenidas de 12 m), sin la
## pintura propia del kit.
func _corredor(vertical: bool, p: float, d0: float, d1: float) -> void:
	var calzada: float = _trazado.calzada
	var acera: float = _trazado.acera
	var paso: float = _trazado.paso
	var n_lineas: int = (manzanas_z + 1) if vertical else (manzanas_x + 1)
	var cont_calles: Node3D = _cont["Calles"]
	var cont_marcas: Node3D = _cont["MarcasViales"]
	var cont_acera: Node3D = _cont["Aceras"]
	# Piezas de marca de ESTA calle: se eligen una sola vez por calle (no por celda ni
	# por tramo) para que toda la calle lleve la misma raya: mismo ancho, misma
	# separación entre las dos líneas y mismo color, en toda la ciudad.
	var pieza_eje := _elegir(_linea_central)
	var pieza_lateral := _elegir(_linea_discontinua)
	var giro_m := PI * 0.5 if vertical else 0.0
	# Franja libre de pintura dentro de cada cuadra: entre los pasos de peatones de los
	# dos cruces que la cierran (los pasos van a 2.27 m del borde del cruce).
	var margen_m := _margen_pasos()

	# Aceras: superficie peatonal y colisión a ambos lados del vial, POR TRAMOS.
	# La colisión se corta en cada cruce para no atravesar la calzada transversal
	# (esas franjas continuas eran las "paredes invisibles" de las intersecciones).
	for lado: float in [-1.0, 1.0]:
		_bandas_acera(vertical, p, lado, d0, d1, n_lineas)

	# Tramos entre cruces consecutivos: calzada y aceras.
	for k in n_lineas - 1:
		var ini: float = d0 + k * paso + calzada * 0.5
		var fin: float = d0 + (k + 1) * paso - calzada * 0.5
		var largo := fin - ini
		if largo < 6.0:
			continue
		var n := maxi(1, int(round(largo / 6.0)))
		# Planchas de asfalto: se teselan a lo largo y, si la calzada es más ancha
		# que una plancha (avenida de varios carriles), también a lo ancho.
		var n_ancho := maxi(1, int(round(calzada / 6.0)))
		for t in n:
			var c: float = ini + largo * (float(t) + 0.5) / float(n)
			for a in n_ancho:
				var lat: float = p - calzada * 0.5 + 6.0 * (float(a) + 0.5)
				var pos := Vector3(lat, Y_ACERA, c) if vertical else Vector3(c, Y_ACERA, lat)
				# Calzada: planchas planas (sin bordillo ni pintura propias).
				if not _plancha_asfalto.is_empty():
					_colocar(_elegir(_plancha_asfalto), _t(pos), cont_calles, true)
				elif not _tramo_calle.is_empty():
					# Reserva: tramos con aceras incorporadas, alineados con el vial.
					_colocar(_elegir(_tramo_calle), _t(pos, 0.0 if vertical else PI * 0.5),
							cont_calles, true)
				_est["tramos"] = int(_est.get("tramos", 0)) + 1
			# Marcas viales del tramo: doble amarilla en el eje y una discontinua por cada
		# separación de carriles (calles de 9 m o más). Se pintan SÓLO en la franja
		# libre de la cuadra —entre los pasos de peatones de los dos cruces que la
		# cierran— y se teselan con el largo REAL de la pieza, centradas: así la raya es
		# continua, paralela y uniforme, no invade el paso de peatones ni el cruce, y no
		# quedan piezas superpuestas, ni desplazadas, ni cortes en diagonal.
		if generar_marcas_viales:
			var libre_m := largo - 2.0 * margen_m
			var ejes: Array[float] = [0.0]
			if calzada >= 9.0:
				ejes.append(-calzada * 0.25)
				ejes.append(calzada * 0.25)
			for e: float in ejes:
				var pieza_m := pieza_eje if is_zero_approx(e) else pieza_lateral
				var largo_m := _largo_pieza_marca(pieza_m)
				var n_m := int(floor(libre_m / largo_m)) if largo_m > 0.0 else 0
				if n_m < 1:
					continue
				var arranque := ini + largo * 0.5 - largo_m * float(n_m) * 0.5
				for t_m in n_m:
					var c_m := arranque + largo_m * (float(t_m) + 0.5)
					var lat_m: float = p + e
					var pos_m := Vector3(lat_m, Y_ACERA, c_m) if vertical else Vector3(c_m, Y_ACERA, lat_m)
					_colocar(pieza_m, _t(pos_m, giro_m), cont_marcas)
					_est["marcas"] = int(_est.get("marcas", 0)) + 1
		# Aceras del tramo: piezas de 3x3 m, 1 cm metidas bajo el bordillo de la
		# calzada y 1 cm antes del borde de la manzana (evita caras coplanares).
		if _acera_recta.is_empty():
			continue
		var pieza_acera: String = _elegir(_acera_recta)
		var m := maxi(1, int(round(largo / 3.0)))
		for t in m:
			var c: float = ini + largo * (float(t) + 0.5) / float(m)
			for lado: float in [-1.0, 1.0]:
				var centro := p + lado * (calzada * 0.5 + acera * 0.5 - 0.01)
				var pos := Vector3(centro, Y_ACERA, c) if vertical else Vector3(c, Y_ACERA, centro)
				_colocar(pieza_acera, _t(pos, _giro_acera(vertical, lado)), cont_acera)


## Giro que deja el bordillo de las piezas de acera mirando a la calzada.
## En el kit, el módulo de acera tiene la calzada hacia su -X local.
func _giro_acera(vertical: bool, lado: float) -> float:
	if vertical:
		return PI if lado < 0.0 else 0.0
	return PI * 0.5 if lado < 0.0 else -PI * 0.5


## Colisión de acera a un lado del vial, dividida en TRAMOS para que NO cruce las
## calzadas de las calles perpendiculares (esas franjas continuas eran las
## "paredes invisibles" de las intersecciones). Cada tramo cubre la acera de su
## manzana; los cuatro chaflanes de cada cruce los cubren los tramos contiguos,
## así que no se duplica la colisión de las esquinas. En los bordes del mapa la
## acera se prolonga hw metros (igual que la geometría del kit) para cerrar los
## chaflanes exteriores y que el jugador no caiga por el borde.
func _bandas_acera(vertical: bool, p: float, lado: float, d0: float, d1: float, n_lineas: int) -> void:
	var medio: float = _trazado.calzada * 0.5
	var hw: float = _trazado.hw
	var paso: float = _trazado.paso
	# Borde inicial del mapa (cubre el chaflán exterior del primer cruce).
	_banda_acera(vertical, p, lado, d0 - hw, d0 - medio)
	# Tramos entre cruces consecutivos: acera sólo donde hay manzana, nunca sobre
	# la calzada de la calle que cruza.
	for k in n_lineas - 1:
		_banda_acera(vertical, p, lado,
				d0 + float(k) * paso + medio, d0 + float(k + 1) * paso - medio)
	# Borde final del mapa.
	_banda_acera(vertical, p, lado, d1 + medio, d1 + hw)


## Colisión de un tramo de acera (banda de 'acera' de ancho) a un lado del vial.
func _banda_acera(vertical: bool, p: float, lado: float, d0: float, d1: float) -> void:
	if d1 - d0 < 0.01:
		return
	var calzada: float = _trazado.calzada
	var acera: float = _trazado.acera
	var centro_lat := p + lado * (calzada * 0.5 + acera * 0.5)
	var rect: Rect2
	if vertical:
		rect = Rect2(centro_lat - acera * 0.5, d0, acera, d1 - d0)
	else:
		rect = Rect2(d0, centro_lat - acera * 0.5, d1 - d0, acera)
	_losa(rect, COLOR_LOSA, false, colisiones_suelo, _cont["Aceras"], "Acera")


## Cruce: calzada completa + 4 esquinas de acera + pasos de peatones.
func _interseccion(px: float, pz: float, i: int, j: int) -> void:
	var calzada: float = _trazado.calzada
	var acera: float = _trazado.acera
	var cont_calles: Node3D = _cont["Calles"]
	var cont_acera: Node3D = _cont["Aceras"]
	var cont_marcas: Node3D = _cont["MarcasViales"]

	# Calzada del cruce: planchas cuadradas que cubren todo el cuadrado.
	var lado_pl := 6.0
	var n := maxi(1, int(round(calzada / lado_pl)))
	for a in n:
		for b in n:
			var x := px - calzada * 0.5 + lado_pl * (float(a) + 0.5)
			var z := pz - calzada * 0.5 + lado_pl * (float(b) + 0.5)
			_colocar(_elegir(_plancha_asfalto), _t(Vector3(x, Y_ACERA, z)), cont_calles, true)

	# Esquinas de acera: el chaflán redondeado mira al centro del cruce. Sobre
	# cada losa se pinta además la marca curva del chaflán (piezas "Stripe",
	# planas y a cota de calzada) para rematar el bordillo como en el kit.
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			if _esquinas_acera.is_empty():
				continue
			var x := px + sx * (calzada * 0.5 + acera * 0.5)
			var z := pz + sz * (calzada * 0.5 + acera * 0.5)
			var dir_deseada := Vector2i(-int(sx), -int(sz))
			var pieza := _elegir(_esquinas_acera)
			var giro := _rot_para_dir(_esquina_dir.get(pieza, Vector2i(1, 1)), dir_deseada)
			_colocar(pieza, _t(Vector3(x, Y_ACERA, z), giro), cont_acera)
			if not _pintura_esquinas.is_empty():
				# La pieza de pintura es la banda del bordillo: su hueco queda
				# al lado contrario del chaflán, así que apunta hacia fuera del
				# cruce para dejar la curva sobre la calzada.
				var pintura := _elegir(_pintura_esquinas)
				var giro_p := _rot_para_dir(_esquina_dir.get(pintura, Vector2i(1, 1)), Vector2i(int(sx), int(sz)))
				_colocar(pintura, _t(Vector3(x, Y_ACERA, z), giro_p), cont_marcas)
				_est["marcas"] = int(_est.get("marcas", 0)) + 1

	# Pasos de peatones en los cuatro brazos (no se pintan si el brazo da al vacío).
	# En avenidas se usa el paso ancho, que cruza la calzada de 12 m entera.
	var pasos: Array = _pasos_peatones
	if calzada >= 9.0 and not _pasos_anchos.is_empty():
		pasos = _pasos_anchos
	if generar_marcas_viales and not pasos.is_empty():
		var paso_pieza := _elegir(pasos)
		for sz: float in [-1.0, 1.0]:
			if j + int(sz) < 0 or j + int(sz) > manzanas_z:
				continue
			if _rng.randf() <= 0.85:
				var z := pz + sz * (calzada * 0.5 + 2.27)
				_colocar(paso_pieza, _t(Vector3(px, Y_ACERA, z), PI * 0.5), cont_marcas)
				_est["marcas"] = int(_est.get("marcas", 0)) + 1
				# Paso de peatones REAL: los peatones sólo cruzarán por aquí.
				_cruces_peatones.append({"i": i, "j": j, "lado": "N" if sz > 0.0 else "S"})
		for sx: float in [-1.0, 1.0]:
			if i + int(sx) < 0 or i + int(sx) > manzanas_x:
				continue
			if _rng.randf() <= 0.85:
				var x := px + sx * (calzada * 0.5 + 2.27)
				_colocar(paso_pieza, _t(Vector3(x, Y_ACERA, pz), 0.0), cont_marcas)
				_est["marcas"] = int(_est.get("marcas", 0)) + 1
				_cruces_peatones.append({"i": i, "j": j, "lado": "E" if sx > 0.0 else "W"})


# =============================================================================
#  Paseo costero (el borde urbano que da al mar)
# =============================================================================

## Pavimenta un paseo ESTRECHO pegado al borde urbano en los sectores donde la
## costa queda cerca, y deja el resto de la franja como terreno natural (pasto):
## la secuencia que ve el jugador es ciudad/veredas -> paseo -> pasto -> transición
## natural -> arena -> agua somera.
##
## La costa NO se codifica a mano: se le pregunta a `Relieve`, la misma función que
## genera el terreno, así que el paseo sigue la orilla real (incluida la bahía) y se
## adapta solo si el mapa cambia. En los lados donde la costa queda lejos (las
## montañas) no se construye nada: la ciudad sólo se abre al mar donde el mar está.
func _generar_paseo_costero() -> void:
	if not paseo_costero:
		return
	var rel := Relieve.new()
	# El paseo arranca donde acaba el pavimento de la última calle: el corredor
	# exterior del recinto urbano se centra en el borde y mide 'hw' a cada lado.
	var semi := maxf(absf(_trazado.off.x), absf(_trazado.off.y))
	var borde_urb := semi + float(_trazado.hw)
	var padre: Node3D = _cont["Suelo"]
	# Dos lados costeros del recinto: el que mira a +X (este) y el que mira a +Z
	# (sur). Son los que dan al sector sin montañas.
	var lados: Array = [
		{"desde": Vector2(borde_urb, -borde_urb), "dir": Vector2(0, 1), "nor": Vector2(1, 0)},
		{"desde": Vector2(-borde_urb, borde_urb), "dir": Vector2(1, 0), "nor": Vector2(0, 1)},
	]
	var paso := 3.0
	var largo_lado := borde_urb * 2.0
	for lado: Dictionary in lados:
		var base: Vector2 = lado["desde"]
		var dir: Vector2 = lado["dir"]
		var nor: Vector2 = lado["nor"]
		# Cada lado costero es una cadena propia de paseo para la red peatonal.
		_paseo_datos.append([])
		var d := 0.0
		while d <= largo_lado:
			var borde: Vector2 = base + dir * d
			# Distancia real del borde urbano a la arena (la marca el terreno).
			var hasta_arena := _distancia_a_arena(rel, borde, nor)
			# Se pavimenta SÓLO dejando delante la franja de pasto: el resto es
			# terreno natural. Así vuelve a verse ciudad -> paseo -> pasto -> arena.
			var ancho := clampf(hasta_arena - paseo_pasto_min, 0.0, paseo_ancho_max)
			if ancho >= 2.0:
				_poner_tramo_paseo(rel, padre, borde, dir, nor, ancho, paso)
			d += paso


## Distancia (m) del borde urbano a la ARENA (donde el terreno baja de la cota de
## arena), avanzando hacia el mar, o -1 si ese tramo no es costa. Si antes de llegar
## a la arena el terreno EMPIEZA A SUBIR (colinas del interior), no hay playa ahí y
## no se construye paseo: así el borde urbano sólo se pavimenta donde da al mar.
func _distancia_a_arena(rel: Relieve, borde: Vector2, nor: Vector2) -> float:
	var a := 0.0
	while a < 60.0:
		var p: Vector2 = borde + nor * a
		var h := rel.altura(p.x, p.y)
		if h < Relieve.COTA_ARENA:
			return a
		if h > Relieve.COTA_CIUDAD + 1.0:
			return -1.0
		a += 1.0
	return -1.0


## Un tramo de paseo: losa ESTRECHA que SIGUE la cota del terreno (se inclina con la
## pendiente entre su borde interior y el exterior), con colisión, y un arbusto
## costero cada cuatro tramos sobre el borde que da al pasto.
##
## POR QUÉ INCLINADA Y NO HORIZONTAL: antes era una losa PLANA con la cara superior
## a la altura del CENTRO del tramo. Como la rampa hacia la arena ya empieza dentro
## de esa franja, el borde que daba al mar quedaba sobresaliendo hasta 25-28 cm por
## encima de la arena: ese era el "escalón artificial" que cortaba el paso de la
## ciudad a la playa (y que el trazador del velocista leía como muro). Siguiendo la
## pendiente, la cara superior acompaña al terreno y no queda ningún labio.
func _poner_tramo_paseo(rel: Relieve, padre: Node3D, borde: Vector2, dir: Vector2,
		nor: Vector2, ancho: float, largo: float) -> void:
	var alto := 0.18
	var centro: Vector2 = borde + nor * (ancho * 0.5)
	var giro := atan2(dir.x, dir.y)
	# El +X local del cuerpo, en horizontal y en el mundo (según el giro).
	var x_local := Vector3(dir.y, 0.0, -dir.x)
	var p_mas: Vector2 = centro + Vector2(x_local.x, x_local.z) * (ancho * 0.5)
	var p_menos: Vector2 = centro - Vector2(x_local.x, x_local.z) * (ancho * 0.5)
	var h_mas := rel.altura(p_mas.x, p_mas.y)
	var h_menos := rel.altura(p_menos.x, p_menos.y)
	var base := Basis(Vector3.UP, giro)
	# Inclinación sobre el eje Z local (el largo del tramo, a lo largo de la costa):
	# la cara superior pasa exactamente por los dos bordes, así no sobresale ninguno.
	base = Basis(base.z, atan2(h_mas - h_menos, maxf(ancho, 0.01))) * base
	var cuerpo := StaticBody3D.new()
	cuerpo.name = "PaseoCostero"
	cuerpo.transform = Transform3D(base, Vector3(centro.x,
			(h_mas + h_menos) * 0.5 + 0.03 - alto * 0.5, centro.y))
	var caja := BoxMesh.new()
	caja.size = Vector3(ancho, alto, largo)
	var mi := MeshInstance3D.new()
	mi.mesh = caja
	var mat := StandardMaterial3D.new()
	mat.albedo_color = COLOR_LOSA
	mat.roughness = 0.95
	mi.material_override = mat
	cuerpo.add_child(mi)
	var forma := CollisionShape3D.new()
	var caja_col := BoxShape3D.new()
	caja_col.size = Vector3(ancho, alto, largo)
	forma.shape = caja_col
	cuerpo.add_child(forma)
	padre.add_child(cuerpo)
	var n := int(_est.get("paseo", 0)) + 1
	_est["paseo"] = n
	# Nodo de la red peatonal en el eje del tramo (con la cota real del paseo).
	if not _paseo_datos.is_empty():
		(_paseo_datos[_paseo_datos.size() - 1] as Array).append(Vector3(
				centro.x, (h_mas + h_menos) * 0.5 + 0.03, centro.y))
	# Vegetación costera sobre el borde exterior del paseo (ya dentro del pasto).
	if n % 4 == 0:
		var v: Vector2 = borde + nor * (ancho + 0.8)
		_colocar_arbusto(Vector3(v.x, rel.altura(v.x, v.y), v.y), 0.9, 1.7)


func _generar_manzanas() -> void:
	var parques := _elegir_parques()
	for i in manzanas_x:
		for j in manzanas_z:
			_generar_manzana(i, j, parques)


## Genera UNA manzana (unidad de trabajo de la etapa de manzanas y edificios).
func _generar_manzana(i: int, j: int, parques: Array) -> void:
	var off: Vector2 = _trazado.off
	var paso: float = _trazado.paso
	var manzana: float = _trazado.manzana
	var hw: float = _trazado.hw
	var rect := Rect2(off.x + i * paso + hw, off.y + j * paso + hw, manzana, manzana)
	# Manzana-parque: césped y jardines en lugar de solares edificados.
	if parques.has(Vector2i(i, j)):
		_parque(rect)
		return
	# Losa de manzana: plataforma a cota de acera, 2 mm por debajo del
	# pavimento del kit (así nunca queda un hueco a la vista y tampoco
	# hay caras coplanares). Se retranquea 2 cm del borde.
	var losa := rect.grow(-0.02)
	_losa(losa, COLOR_LOSA, true, colisiones_suelo, _cont["Suelo"], "Manzana_%d_%d" % [i, j])
	_est["suelos"] = int(_est.get("suelos", 0)) + 1
	# El pavimento lo pone cada plaza: los solares edificados quedan
	# tapados por el propio edificio, que ocupa la parcela entera.
	_poblar_manzana(rect, i, j)


## Reparte la manzana en solares (1x1, 2x1, 1x2 o 2x2) y edifica cada uno.
func _poblar_manzana(rect: Rect2, i: int, j: int) -> void:
	var div_x := 2
	var div_z := 2
	if rect.size.x >= 18.0 and rect.size.y >= 18.0:
		var r := _rng.randf()
		if r < 0.30:
			div_x = 1 ; div_z = 1       # manzana entera: solar para edificio grande
		elif r < 0.50:
			div_x = 2 ; div_z = 1
		elif r < 0.70:
			div_x = 1 ; div_z = 2
		else:
			div_x = 2 ; div_z = 2       # cuatro solares medianos
	for a in div_x:
		for b in div_z:
			var origen := Vector2(rect.position.x + rect.size.x * float(a) / float(div_x),
					rect.position.y + rect.size.y * float(b) / float(div_z))
			var parcela := Rect2(origen, Vector2(rect.size.x / float(div_x), rect.size.y / float(div_z)))
			_est["parcelas"] = int(_est.get("parcelas", 0)) + 1
			# Id ESTABLE del solar (depende de su sitio en el mapa, no del azar):
			# es lo que permite editar UNA casa concreta desde
			# `world/ediciones_ciudad.gd` sin tocar las demás.
			var id_solar: String = EdicionesCiudad.id_edificio(Vector2i(i, j), Vector2i(a, b))
			if _rng.randf() < prob_solar_vacio:
				_plaza(parcela)
			else:
				_poner_edificio(parcela, id_solar)


## Elige las manzanas que serán parque: se prefieren las céntricas (las más
## visibles) con un poco de azar, para que no salgan siempre en el mismo sitio.
func _elegir_parques() -> Array[Vector2i]:
	var elegidas: Array[Vector2i] = []
	var total := manzanas_x * manzanas_z
	var cuantos := clampi(manzanas_parque, 0, maxi(total - 1, 0))
	if cuantos == 0:
		return elegidas
	var centro := Vector2(float(manzanas_x - 1) * 0.5, float(manzanas_z - 1) * 0.5)
	var candidatas: Array = []
	for i in manzanas_x:
		for j in manzanas_z:
			var d := Vector2(float(i), float(j)).distance_to(centro)
			candidatas.append({"celda": Vector2i(i, j), "peso": d + _rng.randf_range(0.0, 1.6)})
	candidatas.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["peso"]) < float(b["peso"]))
	for k in cuantos:
		elegidas.append(candidatas[k]["celda"] as Vector2i)
	return elegidas


## Material del césped: repite la textura cada 2 m sobre la cara superior.
func _material_cesped(tam: Vector2) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	if _tex_cesped != null:
		mat.albedo_texture = _tex_cesped
		mat.uv1_scale = Vector3(maxf(tam.x, 1.0) / 2.0, maxf(tam.y, 1.0) / 2.0, 1.0)
	else:
		mat.albedo_color = Color(0.24, 0.36, 0.18)
	mat.roughness = 1.0
	return mat


## Manzana-parque: césped a cota de calzada, senderos en cruz a cota de acera,
## vegetación por los cuatro cuadrantes y bolardos en las bocas de los senderos.
func _parque(rect: Rect2) -> void:
	var centro := rect.get_center()
	var cont_aceras: Node3D = _cont["Aceras"]
	_est["parques"] = int(_est.get("parques", 0)) + 1
	_parques_datos.append(rect)          # los peatones pasean por aquí

	# --- Césped: losa con colisión, 15 cm por debajo de la acera -------------
	var alto := Y_PARQUE - Y_SUELO
	var tam := Vector3(rect.size.x, alto, rect.size.y)
	var cuerpo := StaticBody3D.new()
	cuerpo.name = "Parque_%d" % int(_est["parques"])
	cuerpo.position = Vector3(centro.x, Y_SUELO + alto * 0.5, centro.y)
	var caja := BoxMesh.new()
	caja.size = tam
	var malla := MeshInstance3D.new()
	malla.mesh = caja
	malla.material_override = _material_cesped(rect.size)
	cuerpo.add_child(malla)
	if colisiones_suelo:
		var forma := CollisionShape3D.new()
		var caja_col := BoxShape3D.new()
		caja_col.size = tam
		forma.shape = caja_col
		cuerpo.add_child(forma)
	_cont["Suelo"].add_child(cuerpo)

	# --- Senderos en cruz de 3 m con las losas sin bordillo del kit ----------
	if not _acera_pavimento.is_empty():
		var n := maxi(2, int(round(rect.size.x / 3.0)))
		@warning_ignore("integer_division")
		var central := n / 2
		for a in n:
			var x := rect.position.x + 1.5 + 3.0 * float(a)
			var z := rect.position.y + 1.5 + 3.0 * float(a)
			# Sendero este-oeste (fila central completa).
			_colocar(_elegir(_acera_pavimento), _t(Vector3(x, Y_ACERA, centro.y)), cont_aceras)
			# Sendero norte-sur (la losa central ya está puesta).
			if a != central:
				_colocar(_elegir(_acera_pavimento), _t(Vector3(centro.x, Y_ACERA, z), PI * 0.5),
						cont_aceras)

	# --- Bancos: dos a cada lado del sendero E-O y uno a cada lado del N-S,
	# mirando al sendero. Van ANTES que árboles y jardineras para que éstos se
	# aparten de ellos (ver _lejos_de_bancos): nunca un banco dentro de un árbol.
	var bancos := _bancos_parque(rect)

	# --- Árboles: por el césped, sin pisar los senderos ----------------------
	var puestos := 0
	var intentos := 0
	while puestos < arboles_por_parque and intentos < arboles_por_parque * 25:
		intentos += 1
		var x := _rng.randf_range(rect.position.x + 2.2, rect.end.x - 2.2)
		var z := _rng.randf_range(rect.position.y + 2.2, rect.end.y - 2.2)
		if absf(x - centro.x) < 2.1 or absf(z - centro.y) < 2.1:
			continue
		if not _lejos_de_bancos(bancos, x, z):
			continue
		if _colocar_arbol(Vector3(x, Y_PARQUE, z), 5.0, 7.5):
			puestos += 1

	# --- Arbustos junto a los dos senderos -----------------------------------
	for k in 4:
		var c := rect.position.x + 3.0 + 6.0 * float(k)
		for s: float in [-1.0, 1.0]:
			_colocar_arbusto(Vector3(c + _rng.randf_range(-0.6, 0.6), Y_PARQUE,
					centro.y + s * 2.3), 0.7, 1.1)
	for k in 3:
		var c2 := rect.position.y + 4.5 + 7.0 * float(k)
		for s: float in [-1.0, 1.0]:
			_colocar_arbusto(Vector3(centro.x + s * 2.3, Y_PARQUE,
					c2 + _rng.randf_range(-0.6, 0.6)), 0.7, 1.1)

	# --- Jardineras del propio kit repartidas por el césped ------------------
	if not _vegetacion.is_empty():
		for k in 5:
			var x2 := _rng.randf_range(rect.position.x + 2.5, rect.end.x - 2.5)
			var z2 := _rng.randf_range(rect.position.y + 2.5, rect.end.y - 2.5)
			if absf(x2 - centro.x) < 2.1 or absf(z2 - centro.y) < 2.1:
				continue
			if not _lejos_de_bancos(bancos, x2, z2):
				continue
			_colocar_vegetacion(Vector3(x2, Y_PARQUE, z2), _rng.randf_range(0.9, 1.1), Y_PARQUE)

	# --- Bolardos en las cuatro bocas de los senderos ------------------------
	if generar_props and not _bolardos.is_empty():
		var pieza := _elegir(_bolardos)
		for s: float in [-1.0, 1.0]:
			for t: float in [-1.0, 1.0]:
				var boca_x := Vector3(centro.x + s * 1.8, Y_ACERA,
						centro.y + t * (rect.size.y * 0.5 - 1.0))
				var boca_z := Vector3(centro.x + t * (rect.size.x * 0.5 - 1.0), Y_ACERA,
						centro.y + s * 1.8)
				_colocar_prop(pieza, boca_x, true, 1.0)
				_colocar_prop(pieza, boca_z, true, 1.0)


## Coloca seis bancos de parque: dos a cada lado del sendero este-oeste y uno a
## cada lado del norte-sur, mirando siempre al sendero. Devuelve sus posiciones
## (x, z globales) para que árboles y jardineras del mismo parque se aparten.
func _bancos_parque(rect: Rect2) -> Array[Vector2]:
	var centro := rect.get_center()
	var puestos: Array[Vector2] = []
	# (x, z, giro): el modelo del banco mira a -Z con giro 0 (world/bancos.gd).
	var sitios: Array = [
		[centro.x - 6.05, centro.y + 3.85, 0.0],
		[centro.x + 6.05, centro.y + 3.85, 0.0],
		[centro.x - 6.05, centro.y - 3.85, PI],
		[centro.x + 6.05, centro.y - 3.85, PI],
		[centro.x + 4.05, centro.y - 7.5, PI * 0.5],
		[centro.x - 4.05, centro.y + 7.5, -PI * 0.5],
	]
	for sitio in sitios:
		var x: float = sitio[0] + _rng.randf_range(-0.30, 0.30)
		var z: float = sitio[1] + _rng.randf_range(-0.30, 0.30)
		var giro: float = sitio[2] + _rng.randf_range(-0.06, 0.06)
		var cuerpo := Bancos.colocar(_cont["Props"], _t(Vector3(x, Y_PARQUE, z), giro))
		cuerpo.name = "BancoParque_%d" % (int(_est.get("bancos", 0)) + 1)
		_marcar_owner(cuerpo)
		_est["bancos"] = int(_est.get("bancos", 0)) + 1
		_bancos_datos.append({"pos": Vector3(x, Y_PARQUE, z), "giro": giro})
		_anadir_obstaculo_banco(Vector3(x, Y_PARQUE, z), giro)
		puestos.append(Vector2(x, z))
	return puestos


## ¿Está el punto (x, z) lo bastante lejos de todos los bancos ya colocados?
func _lejos_de_bancos(bancos: Array, x: float, z: float) -> bool:
	for b: Vector2 in bancos:
		if Vector2(x, z).distance_squared_to(b) < 3.61:   # 1.9 m entre centros
			return false
	return true


## Solar vacío: plaza pavimentada y con vegetación. Al estar rodeada de
## edificios que ocupan su parcela entera, tampoco deja huecos ocultos.
func _plaza(rect: Rect2) -> void:
	_est["plazas"] = int(_est.get("plazas", 0)) + 1
	_plazas_datos.append(rect)           # los peatones pasean por aquí
	# Pavimento a cota de acera con las losas sin bordillo del kit.
	if pavimentar_manzanas and not _acera_pavimento.is_empty():
		var n_x := maxi(1, int(round(rect.size.x / 3.0)))
		var n_z := maxi(1, int(round(rect.size.y / 3.0)))
		for a in n_x:
			for b in n_z:
				var x := rect.position.x + 1.5 + 3.0 * float(a)
				var z := rect.position.y + 1.5 + 3.0 * float(b)
				_colocar(_elegir(_acera_pavimento),
						_t(Vector3(x, Y_ACERA, z), PI * 0.5 * float(_rng.randi_range(0, 3))),
						_cont["Aceras"])
	# Bancos: uno (o dos si el solar es amplio) mirando al centro de la plaza.
	# Van antes que árboles, arbustos y jardineras para que éstos se aparten.
	var bancos: Array[Vector2] = []
	var centro_plaza := rect.get_center()
	var n_bancos := 2 if minf(rect.size.x, rect.size.y) >= 15.0 else 1
	for k in n_bancos:
		var lado := -1.0 if k == 0 else 1.0
		var bx := centro_plaza.x + _rng.randf_range(-0.8, 0.8)
		var bz := centro_plaza.y + lado * (rect.size.y * 0.5 - 3.2)
		var giro := PI if lado < 0.0 else 0.0
		var giro_final := giro + _rng.randf_range(-0.06, 0.06)
		var cuerpo := Bancos.colocar(_cont["Props"], _t(Vector3(bx, Y_ACERA, bz), giro_final))
		cuerpo.name = "BancoPlaza_%d" % (int(_est.get("bancos", 0)) + 1)
		_marcar_owner(cuerpo)
		_est["bancos"] = int(_est.get("bancos", 0)) + 1
		_bancos_datos.append({"pos": Vector3(bx, Y_ACERA, bz), "giro": giro_final})
		_anadir_obstaculo_banco(Vector3(bx, Y_ACERA, bz), giro_final)
		bancos.append(Vector2(bx, bz))
	var margen := 2.5
	if generar_vegetacion and not _vegetacion.is_empty():
		for k in _rng.randi_range(1, 3):
			var x := _rng.randf_range(rect.position.x + margen, rect.end.x - margen)
			var z := _rng.randf_range(rect.position.y + margen, rect.end.y - margen)
			if not _lejos_de_bancos(bancos, x, z):
				continue
			_colocar_vegetacion(Vector3(x, Y_ACERA, z), _rng.randf_range(0.85, 1.05))
	# Algún árbol y algún arbusto para que el hueco no quede pelado.
	for k in _rng.randi_range(1, 2):
		var xa := _rng.randf_range(rect.position.x + margen, rect.end.x - margen)
		var za := _rng.randf_range(rect.position.y + margen, rect.end.y - margen)
		if not _lejos_de_bancos(bancos, xa, za):
			continue
		# En la plaza dura (pavimento) el árbol también lleva cantero.
		_colocar_arbol(Vector3(xa, Y_ACERA, za), 4.5, 6.5, true)
	if _rng.randf() < 0.7:
		var xb := _rng.randf_range(rect.position.x + margen, rect.end.x - margen)
		var zb := _rng.randf_range(rect.position.y + margen, rect.end.y - margen)
		if _lejos_de_bancos(bancos, xb, zb):
			_colocar_arbusto(Vector3(xb, Y_ACERA, zb), 0.8, 1.2)


func _poner_edificio(rect: Rect2, id_solar: String = "") -> void:
	var antes := int(_est.get("modulares", 0)) + int(_est.get("prefabs", 0))
	# Ediciones hechas a mano para ESTE solar (vacío = nada especial). Ver
	# `world/ediciones_ciudad.gd`: allí se cambia una casa sin tocar las demás.
	var ed := EdicionesCiudad.edificio(id_solar)
	# Solar oculto a mano: se construye igual que siempre —el azar del resto de
	# la ciudad no se mueve ni un número— pero sus mallas no se añaden al mundo.
	_ocultar_actual = bool(ed.get("ocultar", false))
	_material_edificio = EdicionesCiudad.material_de(ed)
	var forzado := String(ed.get("prefab", ""))
	if forzado != "" and not _modelos.has(forzado):
		push_warning("[GeneradorCiudad] La edición de %s pide el modelo '%s', que no existe." % [id_solar, forzado])
	var cabe_prefab := minf(rect.size.x, rect.size.y) >= 13.0
	# En solares grandes se intenta siempre el edificio completo del kit; si no
	# encaja (o están desactivados) se cae al edificio modular.
	var poner_prefab := usar_prefabricados and cabe_prefab
	if forzado != "" and _modelos.has(forzado):
		poner_prefab = true      # la edición manda sobre los interruptores generales
	if poner_prefab and _poner_prefab(rect, id_solar, forzado, ed):
		_ocultar_actual = false
		_material_edificio = null
		return
	if usar_modulares:
		_poner_modular(rect, id_solar, ed)
	elif usar_prefabricados:
		_poner_prefab(rect, id_solar, forzado, ed)
	# Red de seguridad: si pese a todo la parcela quedó sin construcción (p. ej.
	# una parcela por debajo del mínimo de 6 m), se resuelve como plaza con
	# vegetación en lugar de dejar un solar pelado sin nada.
	if int(_est.get("modulares", 0)) + int(_est.get("prefabs", 0)) == antes:
		_est["parcelas_vacias"] = int(_est.get("parcelas_vacias", 0)) + 1
		_plaza(rect)
	_ocultar_actual = false
	_material_edificio = null


## Coloca uno de los edificios completos del kit (Building_*). Se estira en
## planta para llenar la parcela entera, de modo que el solar queda cerrado y
## el edificio se pega a los vecinos: no quedan rendijas por las que colarse.
## Si el estirón deformaría demasiado el modelo, se descarta y el solar se
## resuelve con el edificio modular (que encaja exacto en la retícula de 2 m).
## Opción de prefab (nombre, giro y escala) para un modelo concreto dentro de una
## parcela: la MISMA cuenta que usa el generador para todos. Devuelve {} si ese
## modelo no encaja (se estiraría demasiado).
func _opcion_prefab(nombre: String, disponible: Vector2) -> Dictionary:
	if not _modelos.has(nombre):
		return {}
	var caja: AABB = _modelos[nombre]["caja"]
	if caja.size.x < 0.5 or caja.size.z < 0.5:
		return {}
	for giro: float in [0.0, PI * 0.5]:
		# Escalas en los ejes LOCALES del modelo: con el giro de 90° el eje
		# x local acaba apuntando al z del mundo y al revés.
		var girado := not is_zero_approx(giro)
		var esc_local_x := (disponible.x / caja.size.z) if girado else (disponible.x / caja.size.x)
		var esc_local_z := (disponible.y / caja.size.x) if girado else (disponible.y / caja.size.z)
		var deforme := maxf(esc_local_x, esc_local_z) / maxf(minf(esc_local_x, esc_local_z), 0.001)
		if esc_local_x < 0.8 or esc_local_z < 0.8 or esc_local_x > 2.2 or esc_local_z > 2.2 or deforme > 1.35:
			continue
		# La altura crece con el menor de los dos estirones (nunca se
		# deforma más de la cuenta en vertical).
		return {"nombre": nombre, "giro": giro,
				"esc": Vector3(esc_local_x, minf(esc_local_x, esc_local_z), esc_local_z)}
	return {}


func _poner_prefab(rect: Rect2, id_solar: String = "", forzado: String = "", ed: Dictionary = {}) -> bool:
	var disponible := rect.size
	var opciones: Array = []
	for nombre in _prefabs:
		var opcion := _opcion_prefab(nombre, disponible)
		if not opcion.is_empty():
			opciones.append(opcion)
	if opciones.is_empty():
		return false
	# El sorteo se hace SIEMPRE entre las mismas opciones que antes de existir las
	# ediciones, aunque luego la edición pida otro modelo: así el azar de la
	# ciudad no se altera y las demás casas quedan exactamente donde estaban.
	var op: Dictionary = opciones[_rng.randi_range(0, opciones.size() - 1)]
	if forzado != "" and _modelos.has(forzado):
		var forzada := _opcion_prefab(forzado, disponible)
		if not forzada.is_empty():
			op = forzada
		else:
			push_warning("[GeneradorCiudad] El modelo '%s' pedido para %s no encaja en su parcela: se deja el que tocó por sorteo." % [forzado, id_solar])
	var nombre_op: String = op.nombre
	var caja_op: AABB = _modelos[nombre_op]["caja"]
	var giro_op: float = float(op.giro)
	var esc_op: Vector3 = op.esc
	# Ediciones de esta casa: giro, tamaño y desplazamiento extra.
	if ed.has("giro_grados"):
		giro_op += deg_to_rad(float(ed["giro_grados"]))
	var esc_ed := float(ed.get("escala", 1.0))
	esc_op = esc_op * esc_ed
	var despl: Vector3 = ed.get("desplazamiento", Vector3.ZERO)
	var base := Basis(Vector3.UP, giro_op).scaled(esc_op)
	var centro := Vector3(caja_op.get_center().x, 0.0, caja_op.get_center().z)
	var origen := Vector3(rect.get_center().x, 0.0, rect.get_center().y) - base * centro + despl
	origen.y = -caja_op.position.y * esc_op.y + despl.y   # apoyo exacto sobre la acera
	# El nodo lleva el ID del solar: así la casa se encuentra en el árbol del juego
	# y se puede editar sin tocar a las demás.
	var nombre_nodo := id_solar if id_solar != "" else nombre_op
	var nodo := _instanciar_pieza(nombre_op, Transform3D(base, origen), _cont["Prefabricados"], nombre_nodo)
	if nodo == null:
		# Solar oculto a mano: la casa se contó y consumió su azar como cualquier
		# otra, pero su malla no llegó al mundo. Se da por puesta.
		_est["prefabs"] = int(_est.get("prefabs", 0)) + 1
		return true
	if not _ocultar_actual and colisiones_edificios and not _tiene_colision(nodo):
		# Caja de colisión como hermana del edificio: así no hereda la escala no
		# uniforme (que Jolt no admite) y mide exactamente la parcela, que es
		# justo lo que ocupa el edificio.
		var alto_mundo := caja_op.size.y * esc_op.y
		var cuerpo := StaticBody3D.new()
		cuerpo.name = "Colision"
		cuerpo.position = Vector3(rect.get_center().x + despl.x, alto_mundo * 0.5 + despl.y,
				rect.get_center().y + despl.z)
		var forma := CollisionShape3D.new()
		var caja_col := BoxShape3D.new()
		caja_col.size = Vector3(disponible.x, alto_mundo, disponible.y)
		forma.shape = caja_col
		cuerpo.add_child(forma)
		_cont["Prefabricados"].add_child(cuerpo)
	_est["prefabs"] = int(_est.get("prefabs", 0)) + 1
	return true


## Compone un edificio con módulos del kit: perímetro de muros (2x3 m) con
## ventanas, marco y hoja de puerta, cornisa perimetral y azotea plana.
func _poner_modular(rect: Rect2, id_solar: String = "", ed: Dictionary = {}) -> void:
	if _paredes.is_empty():
		return
	# El edificio ocupa TODA la parcela: así los edificios vecinos se tocan y la
	# manzana queda cerrada, sin callejones por los que colarse dentro.
	var ancho := floorf(rect.size.x / MODULO_ANCHO) * MODULO_ANCHO
	var fondo := floorf(rect.size.y / MODULO_ANCHO) * MODULO_ANCHO
	if minf(ancho, fondo) < 6.0:
		return
	var fam := _familia_aleatoria()
	# Edición de ESTA casa: familia de módulos y número de plantas. Los sorteos se
	# hacen igual que siempre (aquí y unas líneas más abajo) y luego se sustituye
	# el resultado: así cambiar una casa no desplaza a ninguna de las demás.
	if ed.has("familia"):
		var fam_ed := String(ed["familia"])
		if _familias.has(fam_ed):
			fam = fam_ed
		else:
			push_warning("[GeneradorCiudad] La edición de %s pide la familia '%s', que no existe." % [id_solar, fam_ed])
	# Evitamos bloques de esquina decorativos: algunos son columnas abiertas y
	# dejan un hueco oscuro en el encuentro. Los paños rectos de la misma familia
	# llegan hasta cada vértice y se encuentran allí, cerrando la fachada.
	var con_esquinas: bool = false
	var pisos := _rng.randi_range(pisos_min, pisos_max)
	if _rng.randf() < prob_torre:
		pisos += _rng.randi_range(1, 4)      # torre: rompe la línea del skyline
	if ed.has("pisos"):
		pisos = maxi(1, int(ed["pisos"]))
	# "Vida nocturna" del edificio: unas fachadas quedan casi a oscuras y otras
	# con bastantes ventanas encendidas. La usa `_quizas_ventana` para decidir,
	# ventana a ventana, cuáles se iluminan de noche (irregular A PROPÓSITO).
	_factor_ventanas_edificio = _rng.randf_range(0.30, 0.72)
	if _rng.randf() < 0.20:
		_factor_ventanas_edificio = _rng.randf_range(0.03, 0.12)
	var centro := Vector3(rect.get_center().x, 0.0, rect.get_center().y)
	var alto := float(pisos) * PLANTA_ALTO
	# Nodo con el ID del solar: es el nombre que se busca en el árbol del juego
	# para editar ESTA casa. Va en el ORIGEN (es una carpeta con nombre: las
	# piezas usan coordenadas de mundo, así que colgarlas de aquí las deja donde
	# les toca) y las piezas de una casa EDITADA se instancian dentro, en vez de
	# ir al lote compartido: así la edición no toca a las demás del mismo tipo.
	var cont_ed: Node3D = null
	var cont_comun: Node3D = _cont["Modulares"]
	var padre_piezas: Node3D = cont_comun
	if id_solar != "":
		cont_ed = Node3D.new()
		cont_ed.name = id_solar
		cont_ed.position = Vector3.ZERO
		cont_comun.add_child(cont_ed)
		_marcar_owner(cont_ed)
		var piezas := Node3D.new()
		piezas.name = "Piezas"
		cont_ed.add_child(piezas)
		padre_piezas = piezas
		_cont["Modulares"] = piezas

	# --- Perímetro: muros de 2x3 m (y bloques de esquina, si la familia los trae)
	var modulos := _fachadas(ancho, fondo, false)
	# Portal: nunca en una celda pegada a la esquina (los marcos sobresalen del
	# plano de fachada y quedarían colgando fuera del edificio).
	var candidatos: Array[int] = []
	for i in modulos.size():
		var mp: Dictionary = modulos[i]
		var en_esquina := false
		if is_zero_approx(float(mp.giro)) or is_equal_approx(absf(float(mp.giro)), PI):
			en_esquina = mp.pos.x >= ancho * 0.5 - 1.01 or mp.pos.x <= -ancho * 0.5 + 1.01
		else:
			en_esquina = mp.pos.z >= fondo * 0.5 - 1.01 or mp.pos.z <= -fondo * 0.5 + 1.01
		if not en_esquina:
			candidatos.append(i)
	var idx_puerta := _rng.randi_range(0, modulos.size() - 1)
	if not candidatos.is_empty():
		idx_puerta = candidatos[_rng.randi_range(0, candidatos.size() - 1)]
	# Patrón de huecos fijo por edificio: las ventanas se apilan en la misma
	# vertical en todas las plantas, como en un edificio de verdad (antes se
	# sorteaban celda a celda y la fachada salía moteada).
	var desfase := _rng.randi_range(0, 1)
	var m_plano := _pieza_familia(fam, "muros")
	var m_baja := _pieza_familia(fam, "bajas", ["muros"])
	var m_alto := _pieza_familia(fam, "top", ["muros"])
	var m_ventana := _pieza_familia(fam, "ventanas", ["muros"])
	var m_esquina := _pieza_familia(fam, "esquinas", ["muros"])
	var marco := _marco_puerta(fam)
	# A partir de aquí los sorteos son de ESTA casa (ventanas encendidas, aires
	# acondicionados…): van en su propio RNG, sembrado con su id, así que editar
	# una casa no desplaza el azar de las demás.
	var rng_ciudad := _rng
	_rng_edificio.seed = SemillaMundo.semilla_de("edificio_" + (id_solar if id_solar != "" else "libre"))
	_rng = _rng_edificio
	for piso in pisos:
		var y := float(piso) * PLANTA_ALTO
		var es_top := piso == pisos - 1
		for idx in modulos.size():
			var m: Dictionary = modulos[idx]
			var pos := centro + Vector3(m.pos.x, y, m.pos.z)
			var giro: float = m.giro
			if piso == 0 and idx == idx_puerta and not marco.is_empty():
				# Portal CERRADO: el marco va en el centro de la celda (igual que
				# los muros) y el vano de 2 m se cierra con DOS hojas de 1 m, una
				# por mitad (la hoja va de -1 a 0 respecto de su origen, así que
				# las mitades van en x local 0.0 y +1.0). Con una sola hoja
				# quedaba media puerta abierta hacia el interior.
				var b := Basis(Vector3.UP, giro)
				var p_marco := pos
				_colocar(marco, _t(p_marco, giro), _cont["Modulares"])
				if not _hojas_puerta.is_empty():
					var hoja := _elegir(_hojas_puerta)
					var caja_marco: AABB = _modelos[marco]["caja"]
					var caja_hoja: AABB = _modelos[hoja]["caja"]
					# El fondo se mide con las cajas reales de los modelos: la
					# hoja queda 2 cm por detrás del frente del marco, sin
					# cruzarse con el muro ni con el propio marco.
					var z_hoja: float = caja_marco.end.z - caja_hoja.end.z - 0.02
					for mitad in 2:
						var pos_hoja: Vector3 = p_marco + b * Vector3(float(mitad), 0.0, z_hoja)
						_colocar(hoja, _t(pos_hoja, giro), _cont["Modulares"])
					# Los portales son datos del MUNDO (los peatones los usan para
					# entrar en las casas): una casa oculta a mano no aporta ninguno.
					if not _ocultar_actual:
						prueba_portales.append(_t(p_marco, giro).origin)
						prueba_portales_dir.append(b * Vector3(0.0, 0.0, 1.0))
						# Cara exterior del marco medida con su caja real: es la referencia de
						# "dónde está la puerta" para el ciudadano que va a entrar en la casa.
						prueba_portales_frente.append(maxf(caja_marco.end.z, 0.0))
						_est["portales"] = int(_est.get("portales", 0)) + 1
				else:
					_colocar(m_baja, _t(pos, giro), _cont["Modulares"])
			elif piso == 0:
				_colocar(m_baja, _t(pos, giro), _cont["Modulares"])
				# En la planta baja (locales) se encienden menos que arriba.
				_quizas_ventana(m_baja, pos, giro, 0.55)
			elif es_top:
				_colocar(m_alto, _t(pos, giro), _cont["Modulares"])
				_quizas_ventana(m_alto, pos, giro, 0.85)
			elif (idx % 2) == desfase:
				_colocar(m_ventana, _t(pos, giro), _cont["Modulares"])
				_quizas_ventana(m_ventana, pos, giro, 1.0)
			else:
				_colocar(m_plano, _t(pos, giro), _cont["Modulares"])
				# El muro elegido puede ser también una pieza con ventana (el
				# kit mete las ventanas de ladrillo entre los muros lisos).
				_quizas_ventana(m_plano, pos, giro, 1.0)

		# Esquinas: bloque de 2x2 m, sólo si la familia trae piezas propias.
		# Si no, las propias paredes de los lados ya llegan hasta la esquina.
		if con_esquinas:
			for c in _esquinas_modulares(ancho, fondo, centro, y):
				_colocar(m_esquina, _t(c.pos, c.giro), _cont["Modulares"])

	# --- Cornisa perimetral (banda de 1 m rematando la fachada) ---
	if not _cornisas.is_empty():
		# Cornisa de la familia si el kit la trae; si no, la genérica del kit.
		var lista_c := _por_familia(_cornisas, fam)
		if lista_c.is_empty():
			lista_c = _cornisas
		var cornisas := _elegir(lista_c)
		var yc := alto - 1.0
		# Lados norte/sur: ancho completo (incluyen el remate de las esquinas).
		var n_c := int(round(ancho / MODULO_ANCHO))
		for k in n_c:
			var x := -ancho * 0.5 + MODULO_ANCHO * (float(k) + 0.5)
			# Mismo voladizo de 6 mm que los muros: la cornisa queda a ras del
			# frente del muro, sin caras coplanares en la esquina.
			_colocar(cornisas, _t(centro + Vector3(x, yc, fondo * 0.5 + 0.006), 0.0), _cont["Modulares"])
			_colocar(cornisas, _t(centro + Vector3(x, yc, -fondo * 0.5 - 0.006), PI), _cont["Modulares"])
		# Lados este/oeste: profundidad completa, 2 cm más afuera para no
		# encontrarse cara con cara con los tramos anteriores en las esquinas.
		var m_c := int(round(fondo / MODULO_ANCHO))
		for k in m_c:
			# La cornisa ocupa x local -2..0: ajustar origen por separado según
			# el sentido del giro, igual que en los muros laterales.
			var z_derecha := -fondo * 0.5 + MODULO_ANCHO * float(k)
			var z_izquierda := -fondo * 0.5 + MODULO_ANCHO * (float(k) + 1.0)
			_colocar(cornisas, _t(centro + Vector3(ancho * 0.5 + 0.02, yc, z_derecha), PI * 0.5), _cont["Modulares"])
			_colocar(cornisas, _t(centro + Vector3(-ancho * 0.5 - 0.02, yc, z_izquierda), -PI * 0.5), _cont["Modulares"])

	# --- Azotea: plancha de tejado a ras del último forjado ---
	_colocar_techos(centro, ancho, fondo, alto)

	# --- Mobiliario de azotea ---
	if props_en_azotea and not _aires.is_empty():
		for k in _rng.randi_range(1, 3):
			var x := centro.x + _rng.randf_range(-ancho * 0.5 + 1.5, ancho * 0.5 - 1.5)
			var z := centro.z + _rng.randf_range(-fondo * 0.5 + 1.5, fondo * 0.5 - 1.5)
			_instanciar_pieza(_elegir(_aires),
					_t(Vector3(x, alto + 0.2, z), _rng.randf_range(0.0, TAU)), _cont["Props"], "AireAcondicionado")

	_rng = rng_ciudad          # se devuelve el generador de la ciudad
	# --- Colisión envolvente del edificio ---
	# La caja va DENTRO del nodo con el ID del solar cuando existe (así se ve de
	# qué casa es) y en el contenedor común cuando no; siempre con coordenadas de
	# mundo, porque el nodo del id está en el origen.
	if colisiones_edificios and not _ocultar_actual:
		var cuerpo := StaticBody3D.new()
		cuerpo.name = "Edificio_modular_%d" % int(_est.get("modulares", 0))
		cuerpo.position = Vector3(centro.x, Y_ACERA + alto * 0.5, centro.z)
		var forma := CollisionShape3D.new()
		var caja_col := BoxShape3D.new()
		caja_col.size = Vector3(ancho, alto, fondo)
		forma.shape = caja_col
		cuerpo.add_child(forma)
		if cont_ed != null:
			cont_ed.add_child(cuerpo)
		else:
			cont_comun.add_child(cuerpo)

	if not _ocultar_actual:
		prueba_esquinas.append(centro + Vector3(ancho * 0.5, 0.0, fondo * 0.5))
		prueba_esquinas_dir.append(Vector3(0.7071068, 0.0, 0.7071068))

	# --- Relleno interior: suficientemente retraído para que no cruce el vano
	# de la puerta ni se vea desde los laterales/esquinas de la fachada, y con
	# el techo 0.5 m por debajo de la losa para no asomar por la azotea ---
	if not _ocultar_actual:
		_relleno_interior(_cont["Modulares"], centro, ancho, fondo, alto - 0.5, 1.25)
	# El contenedor común vuelve a su sitio (ver el principio de la función): el
	# desvío a las piezas de ESTA casa dura sólo mientras se construye.
	_cont["Modulares"] = cont_comun
	_est["modulares"] = int(_est.get("modulares", 0)) + 1


## Muros del perímetro: {pos: Vector3, giro: float}. El módulo va CENTRADO en
## su celda (el modelo ocupa x = -1..+1), así que el run cubre de esquina a
## esquina sin rendijas ni paños colgando. Con 'con_esquinas' los lados dejan
## libres las esquinas (2x2 m) para los bloques de esquina del kit.
func _fachadas(ancho: float, fondo: float, con_esquinas: bool = true) -> Array:
	var modulos: Array = []
	var libre := 2.0 * MODULO_ANCHO if con_esquinas else 0.0
	# IMPORTANTE: el módulo de muro está CENTRADO en su origen (x = -1..+1), así
	# que cada celda se rellena colocándolo en su CENTRO y los paños contiguos
	# se tocan en el borde. Antes se colocaba en el borde derecho de la celda:
	# eso dejaba 1 m sin fachada en la esquina inicial (por ahí se veía el
	# interior, los "parches negros") y 1 m de paño colgando fuera en la final,
	# además de descuadrar el portal 1 m (la puerta "cortada" con un hueco al
	# lado). Cada tramo se adelanta además unos milímetros hacia la calle para
	# que el canto del muro no quede coplanar con la fachada perpendicular y no
	# parpadee en las esquinas.
	var voladizo := 0.006       # lados norte/sur
	var voladizo_lat := 0.012   # lados este/oeste
	var n := int(round((ancho - libre) / MODULO_ANCHO))
	for k in n:
		var x := -ancho * 0.5 + libre * 0.5 + MODULO_ANCHO * (float(k) + 0.5)
		modulos.append({"pos": Vector3(x, 0.0, fondo * 0.5 + voladizo), "giro": 0.0})
		modulos.append({"pos": Vector3(x, 0.0, -fondo * 0.5 - voladizo), "giro": PI})
	var m := int(round((fondo - libre) / MODULO_ANCHO))
	for k in m:
		# Módulo centrado: el mismo centro sirve para los dos lados; el giro
		# opuesto solo cambia hacia dónde mira la cara exterior.
		var z_c := -fondo * 0.5 + libre * 0.5 + MODULO_ANCHO * (float(k) + 0.5)
		modulos.append({"pos": Vector3(ancho * 0.5 + voladizo_lat, 0.0, z_c), "giro": PI * 0.5})
		modulos.append({"pos": Vector3(-ancho * 0.5 - voladizo_lat, 0.0, z_c), "giro": -PI * 0.5})
	return modulos


## Posición y giro de los cuatro bloques de esquina (2x2x3 m). El modelo tiene
## sus caras exteriores en z = 0 y x = +1 (esquina noreste), así que cada
## cuadrante se resuelve con un giro de 90° y su origen 1 m hacia -x local.
func _esquinas_modulares(ancho: float, fondo: float, centro: Vector3, y: float) -> Array:
	var lista: Array = []
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			var giro := 0.0
			if sx > 0.0 and sz < 0.0:
				giro = PI * 0.5              # noreste -> sureste
			elif sx < 0.0 and sz < 0.0:
				giro = PI                    # -> suroeste
			elif sx < 0.0 and sz > 0.0:
				giro = PI * 1.5              # -> noroeste
			var base := Basis(Vector3.UP, giro)
			var pos := centro + Vector3(sx * ancho * 0.5, y, sz * fondo * 0.5) + base * Vector3(-1.0, 0.0, 0.0)
			lista.append({"pos": pos, "giro": giro})
	return lista


## Azotea: losa propia de membrana de grava, UNA sola capa por edificio. Antes
## se usaban las planchas del kit (Roof_2x2 / Roof_4x4): a la misma cota que el
## remate del edificio peleaban entre capas y dejaban esos parches beige y gris
## con bordes irregulares.
func _colocar_techos(centro: Vector3, ancho: float, fondo: float, alto: float) -> void:
	if _tex_techo == null:
		return
	var caja := BoxMesh.new()
	caja.size = Vector3(ancho, 0.24, fondo)
	var mi := MeshInstance3D.new()
	mi.name = "Azotea"
	mi.mesh = caja
	mi.material_override = _material_azotea(ancho, fondo)
	mi.position = Vector3(centro.x, alto + 0.08, centro.z)   # cara superior en alto + 0.20
	_cont["Modulares"].add_child(mi)


## Pieza de una categoría de la familia elegida (muros / bajas / ventanas / top /
## esquinas). Si la familia no tiene nada en esa categoría se prueban las
## alternativas y, como último recurso, cualquier muro del kit: así nunca queda
## una celda de fachada sin cerrar.
func _pieza_familia(fam: String, categoria: String, alternativas: Array = []) -> String:
	var f: Dictionary = _familias.get(fam, {})
	var lista: Array = f.get(categoria, []) as Array
	if lista.is_empty():
		for alt: String in alternativas:
			var otra: Array = f.get(alt, []) as Array
			if not otra.is_empty():
				lista = otra
				break
	if lista.is_empty():
		lista = _paredes
	return _elegir(lista)


## Familia de fachada al azar entre las que tienen muros utilizables.
func _familia_aleatoria() -> String:
	var opciones: Array[String] = []
	for fam: String in _familias.keys():
		var f: Dictionary = _familias[fam]
		if not (f.get("muros", []) as Array).is_empty():
			opciones.append(String(fam))
	if opciones.is_empty():
		return ""
	return opciones[_rng.randi_range(0, opciones.size() - 1)]


## Marco de puerta del edificio. La pareja familia -> marco es fija (ladrillo
## con madera, molduras con moldura, metal con metal), así que el portal nunca
## mezcla materiales con la fachada y no cambia de marco entre llamadas.
func _marco_puerta(fam: String) -> String:
	if _marcos_puerta.is_empty():
		return ""
	var quiere := {"brick": "wooden", "trim": "trim", "metal": "metal"}
	var busca := String(quiere.get(fam, ""))
	if busca != "":
		for n in _marcos_puerta:
			if String(n).to_lower().contains(busca):
				return String(n)
	return _marcos_puerta[0]


## ¿La familia trae bloques de esquina propios (2x2x3 m)?
func _familia_con_esquinas(fam: String) -> bool:
	var f: Dictionary = _familias.get(fam, {})
	return not (f.get("esquinas", []) as Array).is_empty()


## Relleno interior retraído para cerrar el volumen sin invadir entradas ni
## quedar a la vista desde las esquinas de la fachada.
func _relleno_interior(padre: Node3D, centro: Vector3, ancho: float, fondo: float,
		alto: float, margen: float) -> void:
	var tam := Vector3(ancho - margen * 2.0, alto, fondo - margen * 2.0)
	if minf(tam.x, tam.z) < 0.5 or alto < 0.5:
		return
	if _mat_relleno == null:
		_mat_relleno = StandardMaterial3D.new()
		_mat_relleno.albedo_color = Color(0.58, 0.53, 0.45)
		_mat_relleno.roughness = 0.95
	var caja := BoxMesh.new()
	caja.size = tam
	var mi := MeshInstance3D.new()
	mi.name = "Relleno_interior"
	mi.mesh = caja
	mi.material_override = _mat_relleno
	mi.position = Vector3(centro.x, alto * 0.5, centro.z)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	padre.add_child(mi)


# =============================================================================
#  Mobiliario urbano y vegetación
# =============================================================================

## Jardinera o maceta con rotación libre y escala variable.
func _colocar_vegetacion(pos: Vector3, escala: float, base_y: float = Y_ACERA) -> void:
	if not generar_vegetacion or _vegetacion.is_empty():
		return
	var pieza := _elegir(_vegetacion)
	var caja: AABB = _modelos[pieza]["caja"]
	# Se limita la escala para que la pieza quepa en la acera de 3 m, incluso girada.
	var maxima := 1.4 / maxf(maxf(caja.size.x, caja.size.z) * 0.5, 0.001)
	var esc := clampf(escala, 0.8, minf(maxima, 1.1))
	var p := pos
	p.y = base_y - caja.position.y * esc
	_instanciar_pieza(pieza, _t(p, _rng.randf_range(0.0, TAU), esc), _cont["Vegetacion"], "Vegetacion")
	_est["vegetacion"] = int(_est.get("vegetacion", 0)) + 1


## Árbol: una TARJETA CRUZADA con el dibujo de una de las especies del proyecto
## (`Vegetacion`), apoyada sobre el terreno, con altura, giro y tono al azar.
## Antes se construía con tronco cilíndrico y masas de esferas o conos, que es lo
## que daba siluetas de "círculos y triángulos"; el reparto (dónde va cada árbol)
## no cambia en absoluto.
## Con `con_maceta` (árboles plantados sobre pavimento: aceras de calle y plazas
## duras) se coloca además el cantero del kit alrededor de la base; sobre césped
## y jardines el árbol va sin maceta.
func _colocar_arbol(pos: Vector3, alto_min: float, alto_max: float, con_maceta: bool = false) -> bool:
	if not generar_vegetacion or not usar_vegetacion_propia:
		return false
	var alto := _rng.randf_range(alto_min, alto_max)
	var ruta: String = Vegetacion.ARBOLES[_rng.randi_range(0, Vegetacion.ARBOLES.size() - 1)]
	_anadir_planta(ruta, Vegetacion.matriz(pos, ruta, alto, _rng.randf_range(0.0, TAU)), _color_hoja())
	# Colisión del TRONCO para el jugador: el tronco dibujado ocupa ~12 % del ancho de la
	# figura en la base (medido sobre parque_arbol_a.png), así que el radio va en proporción
	# a la altura y el cilindro llega sólo hasta la cruz: la copa NO bloquea.
	_colisiones_vegetacion.append({"x": pos.x, "y": pos.y, "z": pos.z,
			"r": clampf(alto * 0.045, 0.20, 0.70), "h": clampf(alto * 0.40, 1.6, 3.2)})
	if con_maceta:
		_colocar_maceta(pos, alto)
	_est["arboles"] = int(_est.get("arboles", 0)) + 1
	return true


## Cantero urbano para un árbol plantado sobre pavimento. Reutiliza el modelo
## Sidewalk_Planter del kit (cemento + tierra, 1.97 x 0.51 x 1.77 m, base en
## y = 0): se apoya en la misma cota que el árbol y se escala según su altura.
## En las aceras el árbol va arrimado al bordillo, así que la escala se limita
## para que el cantero no pise la calzada ni invada el paso peatonal.
func _colocar_maceta(pos: Vector3, alto_arbol: float) -> void:
	if _maceta_modelo == "":
		return
	var escala := clampf(0.56 + (alto_arbol - 4.5) * 0.09, 0.56, 0.72)
	var caja: AABB = _modelos[_maceta_modelo]["caja"]
	var p := pos
	p.y = pos.y - caja.position.y * escala
	var giro := PI * 0.5 * float(_rng.randi_range(0, 3))
	# Se acumulan y se vuelcan todas juntas en un MultiMesh al cerrar la ciudad
	# (la malla del cantero trae DOS superficies — cemento y tierra —, así que
	# no pasa por el lote normal de piezas).
	_pistas_maceta.append(_t(p, giro, escala))
	_obstaculos_plantas.append(p)
	# El cantero es ancho (≈1,4 m con la escala de la acera): los peatones lo rodean.
	_obstaculos_peatones.append({"x": p.x, "z": p.z, "r": 0.75})
	# Colisión del cantero para el jugador: cilindro bajo algo más estrecho que la caja
	# visible (0,56-0,72 de escala sobre 1,97 x 1,77 m), para no bloquear de más.
	_colisiones_vegetacion.append({"x": p.x, "y": pos.y, "z": p.z, "r": 0.60, "h": 0.45})
	_est["macetas"] = int(_est.get("macetas", 0)) + 1


## Color de hoja: verde con variación por árbol.
func _color_hoja() -> Color:
	var oscuro := Color(0.13, 0.30, 0.11)
	var claro := Color(0.34, 0.52, 0.20)
	return oscuro.lerp(claro, _rng.randf()).lightened(_rng.randf_range(0.0, 0.05))


## Arbusto: tarjeta cruzada con el dibujo del arbusto.
func _colocar_arbusto(pos: Vector3, alto_min: float, alto_max: float) -> bool:
	if not generar_vegetacion or not usar_vegetacion_propia:
		return false
	var alto := _rng.randf_range(alto_min, alto_max)
	_anadir_planta(Vegetacion.ARBUSTO,
			Vegetacion.matriz(pos, Vegetacion.ARBUSTO, alto, _rng.randf_range(0.0, TAU)), _color_hoja())
	_est["vegetacion"] = int(_est.get("vegetacion", 0)) + 1
	return true


## Apunta un banco como obstáculo para los peatones: dos círculos a lo ancho (el banco mide
## 1,94 m de largo y 0,51 de fondo), uno por plaza de asiento.
func _anadir_obstaculo_banco(pos: Vector3, giro: float) -> void:
	var eje := Vector2(sin(giro + PI * 0.5), cos(giro + PI * 0.5))   # a lo largo del banco
	for k: float in [-0.5, 0.5]:
		_obstaculos_peatones.append({"x": pos.x + eje.x * k, "z": pos.z + eje.y * k, "r": 0.6})


## Guarda una planta en el grupo de su textura (una MultiMesh por especie). También
## apunta su posición en `_obstaculos_plantas`: los peatones deben poder rodearla
## (vértices de plaza y parque apartados de los troncos).
func _anadir_planta(ruta: String, xf: Transform3D, color: Color) -> void:
	if not _pistas_planta.has(ruta):
		_pistas_planta[ruta] = []
		_tintes_planta[ruta] = []
	(_pistas_planta[ruta] as Array).append(xf)
	(_tintes_planta[ruta] as Array).append(color)
	_obstaculos_plantas.append(xf.origin)
	_obstaculos_peatones.append({"x": xf.origin.x, "z": xf.origin.z, "r": 0.5})


## Vuelca la vegetación en una MultiMeshInstance3D por ESPECIE (tarjetas cruzadas
## con recorte de alfa y tono por ejemplar). Es lo más barato de dibujar con
## cientos de árboles y el aspecto es el de un árbol de verdad, no el de una
## primitiva.
func _volcar_vegetacion() -> void:
	if _pistas_planta.is_empty():
		return
	var cont: Node3D = _cont["Vegetacion"]
	var rutas: Array = _pistas_planta.keys()
	rutas.sort()
	for ruta: String in rutas:
		cont.add_child(_crear_multi(Vegetacion.malla(), _pistas_planta[ruta], _tintes_planta[ruta],
				Vegetacion.material(ruta), ruta.get_file().get_basename()))


## MultiMeshInstance3D a partir de una lista de matrices (y colores opcionales).
func _crear_multi(malla: Mesh, pistas: Array, colores: Array,
		material: Material, nombre: String) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = malla
	if not colores.is_empty():
		mm.use_colors = true
	mm.set_instance_count(pistas.size())
	for k in pistas.size():
		mm.set_instance_transform(k, pistas[k])
		if not colores.is_empty():
			mm.set_instance_color(k, colores[k])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "%s_x%d" % [nombre, pistas.size()]
	mmi.multimesh = mm
	mmi.material_override = material
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	return mmi


func _generar_mobiliario() -> void:
	# Los objetos puestos A MANO (`PROPS_EXTRA` de `world/ediciones_ciudad.gd`) van
	# siempre, aunque el mobiliario procedural esté apagado: son ediciones del mundo.
	_colocar_props_extra()
	if not generar_props and not generar_vegetacion:
		return
	_generar_mobiliario_ejes([true, false])


## Mobiliario y vegetación de los ejes indicados ('verticales'). Separar los dos
## ejes permite generar por etapas (un eje por lote) sin bloquear la interfaz; la
## lista define también el orden, así que el resultado es idéntico al de una vez.
func _generar_mobiliario_ejes(verticales: Array) -> void:
	var calzada: float = _trazado.calzada
	var acera: float = _trazado.acera
	var hw: float = _trazado.hw
	var paso: float = _trazado.paso
	var ext: Vector2 = _trazado.ext
	var off: Vector2 = _trazado.off
	# Árboles de calle: uno cada 'arboles_calle' metros de acera (0 = ninguno).
	var prob_arbol := 0.0
	if usar_vegetacion_propia and generar_vegetacion and arboles_calle > 0.0:
		prob_arbol = clampf(6.0 / arboles_calle, 0.0, 1.0)

	for vertical: bool in verticales:
		# Etiqueta del eje: entra en los ids ESTABLES de tapas y sumideros
		# ("tapa:V3:2", "sumidero:H0:1:0"), que son los que admite
		# `world/ediciones_ciudad.gd` para cambiar o quitar una pieza concreta.
		var eje := "V" if vertical else "H"
		var n_lineas: int = (manzanas_x + 1) if vertical else (manzanas_z + 1)
		var n_cruces: int = (manzanas_z + 1) if vertical else (manzanas_x + 1)
		var d0: float = off.y if vertical else off.x
		var largo: float = ext.y if vertical else ext.x
		for i in n_lineas:
			var p: float = (off.x + float(i) * paso) if vertical else (off.y + float(i) * paso)

			# --- Mobiliario y vegetación sobre las aceras ---
			for lado: float in [-1.0, 1.0]:
				var centro_lat := p + lado * (calzada * 0.5 + acera * 0.5)
				var n_slots := int(round(largo / 6.0))
				for s in n_slots:
					var c := d0 + 3.0 + 6.0 * float(s)
					var en_cruce := false
					for b in n_cruces:
						if absf(c - (d0 + paso * float(b))) < hw + 1.5:
							en_cruce = true
							break
					if en_cruce:
						continue
					var pos := Vector3(centro_lat, Y_ACERA, c) if vertical else Vector3(c, Y_ACERA, centro_lat)
					if prob_arbol > 0.0 and _rng.randf() < prob_arbol:
						# Árbol de alineación, arrimado al bordillo.
						var lat_a := centro_lat - lado * (acera * 0.5 - 0.8)
						var pos_a := Vector3(lat_a, Y_ACERA, c) if vertical else Vector3(c, Y_ACERA, lat_a)
						_colocar_arbol(pos_a, 4.5, 6.5, true)
					elif _rng.randf() < 0.28:
						_colocar_vegetacion(pos, _rng.randf_range(0.85, 1.05))
					elif _rng.randf() < 0.35 and generar_props and not _bolardos.is_empty():
						# Bolardos junto al bordillo, desplazados hacia la calzada.
						var lat := centro_lat - lado * (acera * 0.5 - 0.5)
						var pos_b := Vector3(lat, 0.0, c) if vertical else Vector3(c, 0.0, lat)
						_colocar_prop(_elegir(_bolardos), pos_b, true, _rng.randf_range(0.9, 1.1))

			# --- Sumideros y registros sobre la calzada ---
			if generar_props:
				for k in manzanas_z if vertical else manzanas_x:
					var ini := d0 + paso * float(k) + hw
					var fin := d0 + paso * float(k + 1) - hw
					if fin - ini < 6.0:
						continue
					# Sumideros: rejas junto al bordillo, repartidas a lo largo de la
					# cuadra (mismo reparto de siempre; ahora llevan id estable para
					# poder cambiar su modelo o quitarlos desde la tabla de ediciones).
					for lado: float in [-1.0, 1.0]:
						if not _sumideros.is_empty() and _rng.randf() < 0.6:
							var c := _rng.randf_range(ini + 1.5, fin - 1.5)
							var pieza_s := _elegir(_sumideros)
							var id_s := "sumidero:%s%d:%d:%d" % [eje, i, k, 0 if lado < 0.0 else 1]
							var lat := p + lado * (calzada * 0.5 - 0.5)
							var pos := Vector3(lat, 0.0, c) if vertical else Vector3(c, 0.0, lat)
							_colocar_prop(pieza_s, pos, false, 1.0, -1.0, id_s)
					# Tapa de alcantarilla: UNA por cuadra, calculada con la geometría
					# REAL de esa cuadra (nunca una separación fija ni una posición al
					# azar):
					#   · longitudinal: el centro exacto entre los dos cruces que la
					#     cierran, (ini + fin) / 2 = d0 + paso·(k + 0.5); con una cuadra
					#     de 100 m la tapa queda a 50 m de cada extremo, y con una de
					#     24 m a 12 m, porque sale de ini y fin, no de una constante;
					#   · transversal: el eje de la calzada (p), que es el centro de la
					#     calzada porque las planchas se teselan a p ± calzada/2;
					#   · giro 0: alineada con el pavimento y con la calle.
					# Cada cuadra recibe exactamente una, larga o corta.
					if not _alcantarillas.is_empty():
						var c_t := (ini + fin) * 0.5
						var pos_t := Vector3(p, Y_CALZADA, c_t) if vertical else Vector3(c_t, Y_CALZADA, p)
						var id_t := "tapa:%s%d:%d" % [eje, i, k]
						_colocar_prop(_elegir(_alcantarillas), pos_t, false, 1.0, 0.0, id_t)


## Coloca un prop apoyado exactamente en su superficie (acera o calzada).
## Giro: por defecto (-1) al azar, como el mobiliario suelto; con un giro fijo se alinea
## a lo que corresponda (las tapas de alcantarilla van alineadas con el pavimento, que
## está teselado en los ejes de la ciudad).
## 'id' es el identificador ESTABLE del prop (ver `world/ediciones_ciudad.gd`): con él
## se puede cambiar su modelo, su tamaño o esconderlo sin tocar los demás.
func _colocar_prop(pieza: String, pos: Vector3, en_acera: bool, escala: float, giro: float = -1.0,
		id: String = "") -> void:
	if pieza == "":
		return
	var ed: Dictionary = EdicionesCiudad.prop(id) if id != "" else {}
	if bool(ed.get("ocultar", false)):
		return
	if ed.has("pieza"):
		var otra := String(ed["pieza"])
		if _modelos.has(otra):
			pieza = otra
		else:
			push_warning("[GeneradorCiudad] La edición de %s pide el modelo '%s', que no existe." % [id, otra])
	escala = escala * float(ed.get("escala", 1.0))
	var caja: AABB = _modelos[pieza]["caja"]
	var p := pos
	# La pieza se apoya sobre la superficie: se compensa el mínimo de su caja.
	p.y = (Y_ACERA if en_acera else Y_CALZADA) - caja.position.y * escala
	# El giro al azar se sortea SIEMPRE, aunque la edición fije otro: así el azar
	# del resto de la ciudad no se desplaza por editar un prop suelto.
	var g := giro
	if giro < 0.0:
		var sorteo := _rng.randf_range(0.0, TAU)
		g = deg_to_rad(float(ed["giro_grados"])) if ed.has("giro_grados") else sorteo
	elif ed.has("giro_grados"):
		g = deg_to_rad(float(ed["giro_grados"]))
	var nodo := _instanciar_pieza(pieza, _t(p, g, escala), _cont["Props"], id if id != "" else pieza)
	if colisiones_props and nodo != null:
		_anadir_colision_caja(nodo, caja)
	_est["props"] = int(_est.get("props", 0)) + 1


## Objetos colocados A MANO en una posición exacta (`PROPS_EXTRA` de
## `world/ediciones_ciudad.gd`): farolas, bancos, señales… en el sitio elegido.
## La generación no los recalcula nunca: se añaden enteros en cada regeneración.
func _colocar_props_extra() -> void:
	var lista := EdicionesCiudad.props_extra()
	for ed: Dictionary in lista:
		var pieza := String(ed.get("pieza", ""))
		if pieza == "" or not _modelos.has(pieza):
			push_warning("[GeneradorCiudad] PROPS_EXTRA pide el modelo '%s', que no existe: se salta." % pieza)
			continue
		var en_acera := bool(ed.get("en_acera", true))
		var escala := float(ed.get("escala", 1.0))
		var pos: Vector3 = ed.get("pos", Vector3.ZERO)
		var caja: AABB = _modelos[pieza]["caja"]
		var p := pos
		if bool(ed.get("apoyar", true)):
			p.y = (Y_ACERA if en_acera else Y_CALZADA) - caja.position.y * escala
		var giro := deg_to_rad(float(ed.get("giro_grados", 0.0)))
		# La clave puede ser 'nombre' (para encontrarlo en el árbol) o el propio id.
		var nombre := String(ed.get("nombre", id_de_props_extra(ed)))
		var nodo := _instanciar_pieza(pieza, _t(p, giro, escala), _cont["Props"], nombre)
		if nodo == null:
			continue
		if bool(ed.get("colision", colisiones_props)):
			_anadir_colision_caja(nodo, caja)
		_est["props_extra"] = int(_est.get("props_extra", 0)) + 1


## Nombre por defecto de un objeto de `PROPS_EXTRA` sin 'nombre': su posición, que
## es lo que lo identifica y lo hace fácil de localizar en el árbol del juego.
func id_de_props_extra(ed: Dictionary) -> String:
	var pos: Vector3 = ed.get("pos", Vector3.ZERO)
	return "Extra_%d_%d" % [int(round(pos.x)), int(round(pos.z))]


# =============================================================================
#  Volcado de lotes (MultiMesh) y cierre
# =============================================================================

## Colisiones de la vegetación para el JUGADOR: un StaticBody3D con un cilindro por tronco
## (árboles y palmeras) y por cantero de obra. Van en la capa 1, la misma del terreno y de
## los edificios, que es la que mira la máscara del jugador (17 = capas 1 y 5): así no se
## atraviesa ni un tronco ni una maceta. Nunca se pone colisión a la copa: las plantas son
## tarjetas cruzadas y por debajo del arbolado se camina.
##
## Los peatones no usan física (se mueven por la red peatonal), así que a ellos los cubren
## los círculos en planta de `_obstaculos_peatones`, que son los mismos troncos y canteros.
func _construir_colisiones_vegetacion() -> void:
	if not colisiones_vegetacion or _colisiones_vegetacion.is_empty():
		print("[GeneradorCiudad] Colisiones de vegetación: desactivadas o sin piezas")
		return
	var cuerpo := StaticBody3D.new()
	cuerpo.name = "ColisionesVegetacion"
	cuerpo.collision_layer = 1
	cuerpo.collision_mask = 0
	for e: Dictionary in _colisiones_vegetacion:
		var forma := CollisionShape3D.new()
		var c := CylinderShape3D.new()
		c.radius = float(e["r"])
		c.height = float(e["h"])
		forma.shape = c
		forma.position = Vector3(float(e["x"]), float(e["y"]) + float(e["h"]) * 0.5, float(e["z"]))
		cuerpo.add_child(forma)
	var padre := _cont.get("Vegetacion", null) as Node3D
	if padre == null:
		padre = self
	padre.add_child(cuerpo)
	_marcar_owner(cuerpo)
	var troncos := 0
	for e2: Dictionary in _colisiones_vegetacion:
		if float(e2["h"]) > 1.0:
			troncos += 1
	print("[GeneradorCiudad] Colisiones de vegetación: %d cilindros (%d troncos de árbol/palmera + %d canteros) en capa 1" % [
			cuerpo.get_child_count(), troncos, cuerpo.get_child_count() - troncos])


## Convierte cada lote en un MultiMeshInstance3D bajo su contenedor.
func _volcar_lotes() -> void:
	for clave in _lotes.keys():
		_volcar_lote(String(clave))
	_lotes.clear()


## Vuelca todas las macetas de árbol en UN único MultiMeshInstance3D (un solo
## dibujado para las ~220 macetas de la ciudad). El cantero trae dos superficies
## (cemento y tierra): MultiMesh las dibuja con sus propios materiales.
func _volcar_macetas() -> void:
	if _pistas_maceta.is_empty():
		return
	if _maceta_modelo == "":
		_pistas_maceta.clear()
		return
	var datos := _malla_unica(_modelos[_maceta_modelo]["escena"], true)
	if datos.is_empty():
		# Sin agrupación posible, se instancian una a una (no debería pasar).
		for xf: Transform3D in _pistas_maceta:
			_instanciar_pieza(_maceta_modelo, xf, _cont["Props"], _maceta_modelo)
		_pistas_maceta.clear()
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = datos["malla"]
	mm.set_instance_count(_pistas_maceta.size())
	var local: Transform3D = datos["local"]
	for k in _pistas_maceta.size():
		mm.set_instance_transform(k, _pistas_maceta[k] * local)
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Macetas_x%d" % _pistas_maceta.size()
	mmi.multimesh = mm
	_cont["Props"].add_child(mmi)
	_marcar_owner(mmi)
	_pistas_maceta.clear()


# =============================================================================
#  Playa, prado costero y ventanas nocturnas
# =============================================================================

## Reparte el mobiliario de playa (palmeras, sombrillas y reposeras) por la
## ARENA de la costa urbana. Sigue la orilla REAL de `Relieve` (igual que el
## paseo costero): recorre los dos lados costeros del recinto urbano —y 60 m más
## allá de las esquinas sureste y suroeste— y en cada tramo busca la franja de
## arena que va del borde del pasto al agua.
##
## Reparto: sombrillas dispersas (sueltas y de a dos o tres) con sus reposeras
## orientadas al mar, palmeras sólo en el borde de la playa (la transición al
## pasto) y todo con espaciados mínimos y azar para que no se vea una fila.
## Nada lleva colisión: es decoración, como las farolas.
func _generar_playa() -> void:
	if not playa_mobiliario and palmeras_densidad <= 0.0:
		return
	_preparar_ruido_plantas()
	var rel := Relieve.new()
	var semi := maxf(absf(_trazado.off.x), absf(_trazado.off.y))
	var borde_urb := semi + float(_trazado.hw)
	var lados: Array = [
		{"desde": Vector2(borde_urb, -borde_urb), "dir": Vector2(0, 1),
				"largo": borde_urb * 2.0 + 60.0},
		{"desde": Vector2(-borde_urb - 60.0, borde_urb), "dir": Vector2(1, 0),
				"largo": borde_urb * 2.0 + 60.0},
	]
	var paso := 4.0
	var sombrillas: Array[Vector2] = []
	var palmeras: Array[Vector2] = []
	for lado: Dictionary in lados:
		var base: Vector2 = lado["desde"]
		var dir: Vector2 = lado["dir"]
		# Cada lado de costa es una cadena propia de arena para la red peatonal.
		_playa_tramos.append([])
		var d := 0.0
		while d <= float(lado["largo"]):
			var borde: Vector2 = base + dir * d
			# Dirección real hacia el mar: radial desde el centro de la ciudad
			# (en las esquinas la búsqueda gira con la costa).
			_playa_en_tramo(rel, borde, borde.normalized(), sombrillas, palmeras)
			d += paso
	# Con el mobiliario ya repartido se elige por dónde caminarán los peatones por
	# la arena (la calle de arena) y se guarda cada reposera para las actividades.
	_calcular_calle_arena(rel)
	_tomar_datos_reposeras()


## La "calle de arena" de la red peatonal: para cada tramo de playa seca se prueban tres
## profundidades y se toma la que más se aparta de sombrillas, palmeras y reposeras, de
## modo que los peatones caminan por la arena sin atravesar el mobiliario.
func _calcular_calle_arena(rel: Relieve) -> void:
	var obstaculos: Array[Vector2] = []
	for e in 3:
		for t: Transform3D in _pistas_sombrilla[e]:
			obstaculos.append(Vector2(t.origin.x, t.origin.z))
	for t2: Transform3D in _pistas_reposera:
		obstaculos.append(Vector2(t2.origin.x, t2.origin.z))
	for p: Transform3D in _pistas_palmera:
		obstaculos.append(Vector2(p.origin.x, p.origin.z))
	_arena_datos.clear()
	var tramos_saltados := 0
	for lado: Array in _playa_tramos:
		var cadena: Array = []
		for tramo: Dictionary in lado:
			var borde: Vector2 = tramo["borde"]
			var hacia: Vector2 = tramo["hacia_mar"]
			var a0: float = tramo["a0"]
			var a1: float = tramo["a1"]
			if a1 - a0 < 10.0:
				continue
			var mejor := Vector3.ZERO
			var mejor_d := -1.0
			# Cinco profundidades: se busca la que deja más hueco libre de sombrillas, palmeras
			# y reposeras. Si ni así hay 0,6 m de paso, este tramo no lleva calle de arena (los
			# peatones saltan al siguiente tramo enlazado) antes que meterse en el mobiliario.
			for f: float in [0.25, 0.35, 0.45, 0.55, 0.65]:
				var a := lerpf(a0 + 1.5, a1 - 3.5, f)
				var p: Vector2 = borde + hacia * a
				var h := rel.altura(p.x, p.y)
				if h > Relieve.COTA_ARENA or h < -1.2:
					continue
				var libre := 99.0
				for o: Vector2 in obstaculos:
					libre = minf(libre, p.distance_to(o))
				if libre > mejor_d:
					mejor_d = libre
					mejor = Vector3(p.x, h, p.y)
			if mejor_d >= 0.6:
				cadena.append(mejor)
			else:
				tramos_saltados += 1
		if not cadena.is_empty():
			_arena_datos.append(cadena)
	if tramos_saltados > 0:
		print("[GeneradorCiudad] Calle de arena: %d tramos sin hueco libre suficiente (se saltan)" % tramos_saltados)


## Guarda posición, giro y variante de cada reposera (para las actividades de playa).
## Se toma ANTES de vaciar las pistas al volcar el mobiliario.
func _tomar_datos_reposeras() -> void:
	_reposeras_datos.clear()
	for k in _pistas_reposera.size():
		var t: Transform3D = _pistas_reposera[k]
		_reposeras_datos.append({
			"pos": t.origin,
			"yaw": t.basis.get_euler().y,
			"variante": 0 if (k % 2) == 0 else 1,
		})


## Un tramo de playa: busca la arena (del borde del pasto al agua) avanzando
## hacia el mar y reparte en ella sombrillas con reposeras, y palmeras en la
## transición al pasto. Si el tramo no da al mar (colina), no hace nada.
func _playa_en_tramo(rel: Relieve, borde: Vector2, hacia_mar: Vector2,
		sombrillas: Array[Vector2], palmeras: Array[Vector2]) -> void:
	# 1) Borde del pasto = donde el terreno baja de la cota de arena.
	var a0 := -1.0
	var a := 0.0
	while a < 80.0:
		var p: Vector2 = borde + hacia_mar * a
		var h := rel.altura(p.x, p.y)
		if h < Relieve.COTA_ARENA:
			a0 = a
			break
		if h > Relieve.COTA_CIUDAD + 1.0:
			return                      # colina: aquí no hay playa
		a += 1.5
	if a0 < 0.0:
		return
	# 2) Orilla del agua dentro de la arena (o fin del tramo si el mar tarda).
	var a1 := -1.0
	a = a0
	while a < a0 + 60.0:
		if rel.altura(borde.x + hacia_mar.x * a, borde.y + hacia_mar.y * a) < -1.60:
			a1 = a
			break
		a += 1.5
	if a1 < 0.0:
		a1 = a0 + 40.0
	var ancho := a1 - a0
	# Tramo de playa real: la red peatonal le pondrá una calle de arena.
	if not _playa_tramos.is_empty():
		(_playa_tramos[_playa_tramos.size() - 1] as Array).append({
			"borde": borde, "hacia_mar": hacia_mar, "a0": a0, "a1": a1})
	# 3) Palmeras: muchas más que antes, en tres franjas y con grupos/ claros
	#    marcados por el ruido `_ruido_palmas` (donde sube, salen 2-4 juntas;
	#    donde baja, tramos largos sin ninguna). Franjas:
	#      a) borde de la arena (transición pasto-arena),
	#      b) franja de pasto entre el paseo y la arena (borde del paseo),
	#      c) un poco dentro de la arena seca, como palmeras sueltas de playa.
	if palmeras_densidad > 0.0:
		var nucleo := _ruido_palmas.get_noise_2d(borde.x, borde.y) * 0.5 + 0.5
		# a) Transición pasto-arena.
		if _rng.randf() < 0.60 * nucleo * palmeras_densidad:
			var ap := a0 + _rng.randf_range(-2.5, 4.5)
			var pp: Vector2 = borde + hacia_mar * ap
			var hp := rel.altura(pp.x, pp.y)
			if hp < Relieve.COTA_ARENA + 0.6 and hp > -1.2 and not _cerca_de(pp, palmeras, 5.5):
				_anadir_palmera(Vector3(pp.x, hp, pp.y))
				palmeras.append(pp)
		# b) Borde del paseo costero (entre el pavimento y la arena).
		var ancho_paseo := clampf(a0 - paseo_pasto_min, 0.0, paseo_ancho_max)
		if paseo_costero and ancho_paseo >= 2.0 \
				and _rng.randf() < 0.46 * nucleo * palmeras_densidad:
			var aq := ancho_paseo + _rng.randf_range(1.4, 3.6)
			if aq < a0 - 0.8:
				var pq: Vector2 = borde + hacia_mar * aq
				if not _cerca_de(pq, palmeras, 5.5):
					_anadir_palmera(Vector3(pq.x, rel.altura(pq.x, pq.y), pq.y))
					palmeras.append(pq)
		# c) Palmera suelta dentro de la arena seca (lejos del agua).
		if ancho > 10.0 and _rng.randf() < 0.10 * nucleo * palmeras_densidad:
			var ar := a0 + _rng.randf_range(4.0, 8.0)
			if ar < a1 - 5.0:
				var pr: Vector2 = borde + hacia_mar * ar
				var hr := rel.altura(pr.x, pr.y)
				if hr < Relieve.COTA_ARENA - 0.02 and hr > -1.0 \
						and not _cerca_de(pr, palmeras, 5.5):
					_anadir_palmera(Vector3(pr.x, hr, pr.y))
					palmeras.append(pr)
	# 4) Sombrillas: sólo si la franja de arena es ancha y seca de verdad.
	if not playa_mobiliario or ancho < 9.0:
		return
	if _rng.randf() > 0.24 * playa_densidad:
		return
	var a_somb := _rng.randf_range(a0 + 3.0, a1 - 3.5)
	var ps: Vector2 = borde + hacia_mar * a_somb
	if _cerca_de(ps, sombrillas, 6.0):
		return
	var hs := rel.altura(ps.x, ps.y)
	if hs > Relieve.COTA_ARENA or hs < -1.35:
		return
	_anadir_sombrilla(Vector3(ps.x, hs, ps.y))
	sombrillas.append(ps)
	# 5) Reposeras: normalmente un par junto a la sombrilla (mirando al mar),
	# más alguna suelta lejos, como las deja la gente. Cada reposera se aparta
	# lo suficiente del mástil (1,35-2,5 m) y de las otras (≥1,15 m), así que
	# nunca atraviesan la sombrilla ni se pisan entre sí.
	var cuantas := 1 + (1 if _rng.randf() < 0.75 else 0)
	if _rng.randf() < 0.18:
		cuantas += 1
	var puestas: Array[Vector2] = []
	for _k in cuantas:
		var elegida := Vector2.ZERO
		var hay := false
		for _intento in 6:
			var ang := hacia_mar.angle() + _rng.randf_range(-1.0, 1.0)
			var dd := _rng.randf_range(1.35, 2.5)
			var pr: Vector2 = ps + Vector2(cos(ang), sin(ang)) * dd
			var hr := rel.altura(pr.x, pr.y)
			if hr > Relieve.COTA_ARENA - 0.05 or hr < -1.45:
				continue
			var choque := false
			for q in puestas:
				if q.distance_to(pr) < 1.15:
					choque = true
					break
			if choque:
				continue
			elegida = pr
			hay = true
			break
		if hay:
			puestas.append(elegida)
			_anadir_reposera(Vector3(elegida.x, rel.altura(elegida.x, elegida.y), elegida.y),
					hacia_mar.rotated(_rng.randf_range(-0.35, 0.35)))
	if _rng.randf() < 0.13 * playa_densidad:
		var ar := _rng.randf_range(a0 + 4.0, a1 - 4.0)
		var pr2: Vector2 = borde + hacia_mar * ar
		var hr2 := rel.altura(pr2.x, pr2.y)
		if hr2 < Relieve.COTA_ARENA - 0.05 and hr2 > -1.45:
			_anadir_reposera(Vector3(pr2.x, hr2, pr2.y),
					hacia_mar.rotated(_rng.randf_range(-0.5, 0.5)))


## Prepara (una sola vez) los dos ruidos que reparten la vegetación costera en
## grupos con claros: `_ruido_costa` organiza las manchas de arbolado del prado
## y `_ruido_palmas` los grupos de palmeras de la playa.
func _preparar_ruido_plantas() -> void:
	if _ruido_palmas == null:
		_ruido_palmas = FastNoiseLite.new()
		_ruido_palmas.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		_ruido_palmas.seed = 515151
		_ruido_palmas.frequency = 0.028
		_ruido_palmas.fractal_octaves = 2
	if _ruido_costa == null:
		_ruido_costa = FastNoiseLite.new()
		_ruido_costa.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		_ruido_costa.seed = 909090
		_ruido_costa.frequency = 0.011
		_ruido_costa.fractal_octaves = 2


## ¿Hay algún punto de 'lista' a menos de 'minimo' m de 'p'?
func _cerca_de(p: Vector2, lista: Array[Vector2], minimo: float) -> bool:
	for q in lista:
		if q.distance_to(p) < minimo:
			return true
	return false


## Añade una palmera a la lista de volcado. Malla adulta (8,5 m) con dos
## clases de ejemplar: adultas grandes (la mayoría) y algunas jóvenes.
func _anadir_palmera(pos: Vector3) -> void:
	var alto := _rng.randf_range(1.02, 1.38)
	if _rng.randf() < 0.22:
		alto = _rng.randf_range(0.74, 0.98)
	# Se hunde un poco para que la base no quede al aire en las pendientes.
	_pistas_palmera.append(_t(pos - Vector3(0.0, 0.12, 0.0), _rng.randf_range(0.0, TAU), alto))
	_est["palmeras"] = int(_est.get("palmeras", 0)) + 1
	_obstaculos_peatones.append({"x": pos.x, "z": pos.z, "r": 0.55})
	# Colisión del TRONCO de la palmera para el jugador (cilindro fino, la copa no bloquea).
	_colisiones_vegetacion.append({"x": pos.x, "y": pos.y, "z": pos.z, "r": 0.34, "h": 3.0})


## Añade una sombrilla (esquema de color al azar) a la lista de su color.
func _anadir_sombrilla(pos: Vector3) -> void:
	var esquema := _rng.randi_range(0, 2)
	(_pistas_sombrilla[esquema] as Array).append(
			_t(pos - Vector3(0.0, 0.05, 0.0), _rng.randf_range(0.0, TAU),
			_rng.randf_range(0.90, 1.12)))
	_est["sombrillas"] = int(_est.get("sombrillas", 0)) + 1
	# El poste de la sombrilla sí molesta a quien camina (la lona queda por encima).
	_obstaculos_peatones.append({"x": pos.x, "z": pos.z, "r": 0.35})


## Añade una reposera orientada hacia el mar (el +Z local mira al mar).
func _anadir_reposera(pos: Vector3, hacia_mar: Vector2) -> void:
	var giro := atan2(hacia_mar.x, hacia_mar.y)
	# Telas de la gente de playa: de blanco a azul suave, arena o verde agua.
	var tinte := Color(0.94, 0.92, 0.88).lerp(
			[Color(0.60, 0.72, 0.88), Color(0.90, 0.78, 0.70), Color(0.80, 0.86, 0.84)][_rng.randi_range(0, 2)],
			_rng.randf_range(0.0, 0.75))
	_pistas_reposera.append(_t(pos - Vector3(0.0, 0.035, 0.0), giro, _rng.randf_range(0.94, 1.06)))
	_tintes_reposera.append(tinte)
	_est["reposeras"] = int(_est.get("reposeras", 0)) + 1
	# La reposera es un obstáculo para los peatones: tres círculos a lo largo del lecho.
	var eje := Vector2(sin(giro), cos(giro))
	for k: float in [-0.6, 0.0, 0.6]:
		_obstaculos_peatones.append({"x": pos.x + eje.x * k, "z": pos.z + eje.y * k, "r": 0.5})


## Dibuja el mobiliario de playa: una MultiMeshInstance3D por modelo (las
## palmeras, las tres lonas de sombrilla y las dos variantes de reposera).
## Las mallas de `Playa` ya traen una superficie por material (hoja/tronco,
## lona/herrajes, tela/bastidor): no se les pone material_override.
func _volcar_playa() -> void:
	if not _pistas_palmera.is_empty():
		_cont["Props"].add_child(_crear_multi(Playa.malla_palmera(), _pistas_palmera, [],
				null, "Palmeras"))
		_pistas_palmera.clear()
	for e in 3:
		var lista: Array = _pistas_sombrilla[e]
		if lista.is_empty():
			continue
		_cont["Props"].add_child(_crear_multi(Playa.malla_sombrilla(e), lista, [],
				null, "Sombrillas_%d" % e))
		lista.clear()
	if _pistas_reposera.is_empty():
		return
	# Las reposeras van repartidas entre las dos variantes (tumbadas y
	# reclinadas) para que no queden todas iguales.
	var tumbadas: Array[Transform3D] = []
	var tumbadas_color: Array[Color] = []
	var reclinadas: Array[Transform3D] = []
	var reclinadas_color: Array[Color] = []
	for k in _pistas_reposera.size():
		if (k % 2) == 0:
			tumbadas.append(_pistas_reposera[k])
			tumbadas_color.append(_tintes_reposera[k])
		else:
			reclinadas.append(_pistas_reposera[k])
			reclinadas_color.append(_tintes_reposera[k])
	if not tumbadas.is_empty():
		_cont["Props"].add_child(_crear_multi(Playa.malla_reposera(0), tumbadas,
				tumbadas_color, null, "Reposeras_tumbadas"))
	if not reclinadas.is_empty():
		_cont["Props"].add_child(_crear_multi(Playa.malla_reposera(1), reclinadas,
				reclinadas_color, null, "Reposeras_reclinadas"))
	_pistas_reposera.clear()
	_tintes_reposera.clear()


# --- Prado costero -------------------------------------------------------------

## Reparte vegetación por las áreas verdes del COSTADO DE LA PLAYA (el sector
## suroeste: la loma de césped que se ve junto a la arena delante de la montaña,
## tal como aparece en las fotos de referencia): grupos de árboles y arbustos
## con claros amplios de césped. Es la única zona que se toca: no se dispersan
## árboles por el resto de la ciudad ni sobre la arena.
##
## Reglas del encargo:
##   · sólo sobre césped (nunca en la arena, el agua ni las rocas altas),
##   · sólo el frente de costa despejado del suroeste, cerca de la playa
##     (fuera del anillo de la ciudad y de su paseo, y fuera del bosque),
##   · fuera del anillo de la ciudad y de su paseo (no estorba calles, veredas
##     ni accesos a la playa; además no lleva colisión),
##   · nunca dentro del bosque que ya existe (`peso_bosque`), para no duplicar
##     la vegetación de la isla,
##   · sin macetas: es césped, como los árboles de los parques.
func _vegetacion_costera() -> void:
	if not costa_vegetacion or not generar_vegetacion or not usar_vegetacion_propia:
		return
	_preparar_ruido_plantas()
	var rel := Relieve.new()
	var semi := maxf(absf(_trazado.off.x), absf(_trazado.off.y))
	var borde_urb := semi + float(_trazado.hw)
	var rng := RandomNumberGenerator.new()
	rng.seed = _rng.randi()
	var paso := 7.0
	var x := -320.0
	while x <= 120.0:
		var z := 100.0
		while z <= 340.0:
			var px := x + rng.randf_range(-paso, paso) * 0.5
			var pz := z + rng.randf_range(-paso, paso) * 0.5
			_costa_punto(rel, rng, _ruido_costa, Vector2(px, pz), borde_urb)
			z += paso
		x += paso


## Un candidato del prado costero: decide si se planta algo y el qué.
## Sólo el sector de las áreas verdes junto a la playa del suroeste (la loma de
## las fotos de referencia): entre el sureste y el oeste manda el bosque que ya
## existe, y el arco sur de la ciudad se deja libre como paseo.
func _costa_punto(rel: Relieve, rng: RandomNumberGenerator, ruido: FastNoiseLite,
		p: Vector2, borde_urb: float) -> void:
	var ang := rad_to_deg(atan2(p.y - Relieve.CENTRO.y, p.x - Relieve.CENTRO.x))
	if ang < 95.0 or ang > 165.0:
		return
	if rel.peso_bosque(p.x, p.y) > 0.05:
		return
	if maxf(absf(p.x), absf(p.y)) < borde_urb + 11.0:
		return                      # el anillo de la ciudad y su paseo
	var h := rel.altura(p.x, p.y)
	if h < Relieve.COTA_ARENA + 0.15 or h > 45.0:
		return                      # arena, agua o rocas altas
	var dc := rel.distancia_costa(p.x, p.y)
	if dc < 3.0 or dc > 135.0:
		return                      # pegado a la orilla o ya lejos de la playa
	if rel.pendiente(p.x, p.y, 4.0) > 30.0:
		return                      # paredes de roca
	# Densidad con manchas: grupos y claros (el prado respira).
	var manchas := ruido.get_noise_2d(p.x, p.y) * 0.5 + 0.5
	if rng.randf() > 0.58 * clampf(manchas * 1.65, 0.0, 1.25):
		return
	var pos := Vector3(p.x, h - 0.15, p.y)
	# Cerca de la arena, a veces una palmera en vez de un árbol (transición).
	if dc < 30.0 and palmeras_densidad > 0.0 and rng.randf() < 0.55 * palmeras_densidad:
		_anadir_palmera(pos)
		return
	if rng.randf() < 0.80:
		_colocar_arbol(pos, 5.0, 11.0, false)
		_est["arboles_costa"] = int(_est.get("arboles_costa", 0)) + 1
	else:
		_colocar_arbusto(pos, 1.2, 2.4)
		_est["arbustos_costa"] = int(_est.get("arbustos_costa", 0)) + 1


# --- Ventanas encendidas de noche ----------------------------------------------

## Mide el VIDRIO de una pieza de fachada (la superficie con material MI_Glass,
## el vidrio oscuro del kit) y lo deja cacheado: {centro: Vector3, tam: Vector2}
## en el espacio del módulo, con el plano un centímetro por delante del vidrio.
## Devuelve {} si la pieza no trae vidrio (un muro liso).
func _medir_ventana(pieza: String) -> Dictionary:
	if _vent_medidas.has(pieza):
		return _vent_medidas[pieza]
	var resultado := {}
	var escena: PackedScene = _modelos[pieza]["escena"]
	var plantilla := escena.instantiate() as Node3D
	if plantilla != null:
		var pila: Array[Node] = [plantilla]
		while not pila.is_empty() and resultado.is_empty():
			var n: Node = pila.pop_back()
			for c in n.get_children():
				pila.append(c)
			var mi := n as MeshInstance3D
			if mi == null or mi.mesh == null:
				continue
			var xf := _transform_relativo(plantilla, mi)
			for s in mi.mesh.get_surface_count():
				var mat := mi.mesh.surface_get_material(s)
				if mat == null or not String(mat.resource_name).to_lower().contains("glass"):
					continue
				var arrays := mi.mesh.surface_get_arrays(s)
				var posiciones: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				if posiciones.is_empty():
					continue
				var caja := AABB(posiciones[0], Vector3.ZERO)
				for v in posiciones:
					caja = caja.expand(xf * v)
				var tam := Vector2(caja.size.x, caja.size.y)
				if tam.x < 0.15 or tam.y < 0.15:
					continue
				resultado = {
					"centro": Vector3((caja.position.x + caja.end.x) * 0.5,
							(caja.position.y + caja.end.y) * 0.5, caja.end.z + 0.012),
					"tam": tam,
				}
				break
		plantilla.free()
	_vent_medidas[pieza] = resultado
	return resultado


## Registra una VENTANA de un edificio y decide si queda encendida de noche. Se
## llama junto a cada pieza de fachada colocada; sólo las piezas con vidrio de
## verdad cuentan como ventana. Ni todas se encienden (probabilidad por edificio
## × el papel de la planta) ni todas brillan igual (brillo y calidez al azar).
func _quizas_ventana(pieza: String, pos: Vector3, giro: float, multiplicador: float) -> void:
	if not ventanas_noche or pieza == "":
		return
	var vidrio := _medir_ventana(pieza)
	if vidrio.is_empty():
		return
	_est["ventanas"] = int(_est.get("ventanas", 0)) + 1
	if _rng.randf() > _factor_ventanas_edificio * multiplicador:
		return
	var centro: Vector3 = vidrio["centro"]
	var tam: Vector2 = vidrio["tam"]
	var b := Basis(Vector3.UP, giro)
	# El paño queda un pelo por delante del vidrio y algo más chico que el hueco
	# (no toca el marco). La escala va en x/y locales: el plano es el +Z.
	_pistas_ventana.append(Transform3D(b.scaled(Vector3(tam.x * 0.96, tam.y * 0.96, 1.0)),
			pos + b * centro))
	# Brillo y calidez al azar: la mayoría normales y algunas más vivas o tenues.
	var brillo := _rng.randf_range(0.55, 1.15)
	if _rng.randf() < 0.12:
		brillo = _rng.randf_range(1.15, 1.35)
	elif _rng.randf() < 0.15:
		brillo = _rng.randf_range(0.40, 0.55)
	_datos_ventana.append(Color(brillo, _rng.randf(), 0.0, 1.0))
	_est["ventanas_luz"] = int(_est.get("ventanas_luz", 0)) + 1


## Dibuja TODAS las ventanas encendidas en una sola MultiMeshInstance3D con el
## shader `world/ventanas_noche.gdshader` y crea el nodo que lo pone EN FASE con
## el ciclo de día y noche (`world/luces_ventanas.gd`: la misma curva que las
## farolas). De día el shader queda a 0 y el nodo oculto: ni se ve.
func _volcar_ventanas() -> void:
	if _pistas_ventana.is_empty():
		return
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	var material := ShaderMaterial.new()
	material.shader = load("res://world/ventanas_noche.gdshader")
	material.set_shader_parameter("noche", 0.0)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = quad
	mm.set_instance_count(_pistas_ventana.size())
	for k in _pistas_ventana.size():
		mm.set_instance_transform(k, _pistas_ventana[k])
		mm.set_instance_custom_data(k, _datos_ventana[k])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "VentanasNoche_x%d" % _pistas_ventana.size()
	mmi.multimesh = mm
	mmi.material_override = material
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.visible = false
	_cont["Modulares"].add_child(mmi)
	_pistas_ventana.clear()
	_datos_ventana.clear()
	# Controlador del fundido, enganchado al ciclo de día y noche de la escena.
	var raiz := get_node_or_null(NODO_CIUDAD)
	if raiz != null:
		var control := Node.new()
		control.name = "LucesVentanas"
		control.set_script(load("res://world/luces_ventanas.gd"))
		control.set("material", material)
		control.set("mmi", mmi)
		raiz.add_child(control)
		if Engine.is_editor_hint() and not _vista_editor:
			_marcar_owner(control)


## Convierte UN lote en su MultiMeshInstance3D (unidad de trabajo del cierre).
func _volcar_lote(pieza: String) -> void:
	var por_sector: Dictionary = _lotes.get(pieza, {})
	if por_sector.is_empty():
		return
	# La malla del modelo se resuelve UNA vez por pieza (se reutiliza en todos
	# los sectores) y se acepta multi-superficie, igual que al agrupar.
	var datos := _malla_unica(_modelos[pieza]["escena"], true)
	var techo := _es_plancha_techo(pieza)
	for clave in por_sector.keys():
		var grupo: Dictionary = por_sector[clave]
		var lista: Array = grupo["pistas"]
		if lista.is_empty():
			continue
		var padre: Node3D = grupo["padre"]
		if datos.is_empty():
			# No agrupable (varias mallas): se instancian una a una.
			for xf in lista:
				_instanciar_pieza(pieza, xf, padre, pieza)
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = datos["malla"]
		mm.set_instance_count(lista.size())
		var local: Transform3D = datos["local"]
		for k in lista.size():
			mm.set_instance_transform(k, (lista[k] as Transform3D) * local)
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "%s_x%d" % [pieza, lista.size()]
		mmi.multimesh = mm
		if techo:
			mmi.material_override = _material_techo(pieza)
		padre.add_child(mmi)


## En el editor, marca la propiedad "owner" para que los nodos se guarden.
func _marcar_owner(nodo: Node) -> void:
	if nodo == null or _vista_editor:
		return
	var arbol := get_tree()
	if arbol == null:
		return
	var raiz := arbol.edited_scene_root
	if raiz != null and nodo != raiz:
		nodo.owner = raiz
	for c in nodo.get_children():
		_marcar_owner(c)


## Hash determinista de las transformaciones del árbol generado (origen, base de cada
## Node3D y matrices de instancia de cada MultiMesh), para comparar dos configuraciones
## con la MISMA semilla. Sólo se calcula con la medición activa.
## Subárboles EXCLUIDOS del hash de ciudad estática, con su porqué. NO se excluye
## ningún nodo de la ciudad generada: sólo lo que se crea de forma aleatoria o
## escalonada en el tiempo y por tanto no es reproducible entre ejecuciones.
##  - "Peatones": su director llama a `_rng.randomize()` (aleatorio por diseño, ya
##    existente) y los ciudadanos nacen escalonados durante los fotogramas de la
##    generación por etapas, así que su número y colocación cambian entre corridas.
##    Se mide aparte con [HASH-PEATONES] para diagnosticar esa variación.
const HASH_EXCLUIDOS: Array[String] = ["Peatones"]

## Hash determinista de un árbol. Si `excluir` contiene NOMBRES de nodos, se saltan
## esos subárboles enteros (se cuentan en `saltados`). Devuelve
## [hash, nodos_incluidos, instancias_multimesh, subárboles_saltados].
func _hash_transformaciones(raiz: Node, excluir: Array = []) -> Array:
	var cuerpo := ""
	var nodos := 0
	var instancias := 0
	var saltados := 0
	var pila: Array[Node] = [raiz]
	while not pila.is_empty():
		var n: Node = pila.pop_back()
		if excluir.has(String(n.name)):
			saltados += 1
			continue
		if n is Node3D:
			var tr := (n as Node3D).transform
			cuerpo += "%s|%s|%s;" % [str(n.get_path()), str(tr.origin), str(tr.basis)]
			nodos += 1
		if n is MultiMeshInstance3D:
			var mm := (n as MultiMeshInstance3D).multimesh
			if mm != null:
				cuerpo += "%s|mm%d;" % [str(n.get_path()), mm.instance_count]
				for i in mm.instance_count:
					cuerpo += str(mm.get_instance_transform(i))
				instancias += mm.instance_count
		for c in n.get_children():
			pila.append(c)
	return [hash(cuerpo), nodos, instancias, saltados]


func _informe(ms: int) -> void:
	print("[GeneradorCiudad] ------------------------------------------------")
	print("[GeneradorCiudad] Carpeta: %s  (semilla %d)" % [_carpeta, _rng.seed])
	print("[GeneradorCiudad] Semilla del mundo: %s | ediciones a mano: %s" % [
			SemillaMundo.descripcion(), EdicionesCiudad.resumen()])
	print("[GeneradorCiudad] Modelos escaneados: %d" % _modelos.size())
	for cat in _categorias.keys():
		var nombres: Array = _categorias[cat]
		var ordenados := PackedStringArray(nombres)
		var muestra := ", ".join(ordenados) if ordenados.size() <= 8 else "%s ... (%d)" % [", ".join(ordenados.slice(0, 8)), ordenados.size()]
		print("[GeneradorCiudad]   %-14s %3d  | %s" % [cat, ordenados.size(), muestra])
	var calzada: float = _trazado.calzada
	var acera: float = _trazado.acera
	var manzana: float = _trazado.manzana
	print("[GeneradorCiudad] Trama: %dx%d manzanas de %.0f m | calle %.0f m (calzada %.0f + aceras %.0f/%.0f)"
			% [manzanas_x, manzanas_z, manzana, calzada + 2.0 * acera, calzada, acera, acera])
	print("[GeneradorCiudad] Suelos: %d | tramos de calle: %d | marcas: %d"
			% [_est.get("suelos", 0), _est.get("tramos", 0), _est.get("marcas", 0)])
	print("[GeneradorCiudad] Parques: %d | árboles: %d | arbustos y jardineras: %d"
			% [_est.get("parques", 0), _est.get("arboles", 0), _est.get("vegetacion", 0)])
	print("[GeneradorCiudad] Bancos en parques y plazas: %d" % _est.get("bancos", 0))
	print("[GeneradorCiudad] Macetas (árboles sobre pavimento): %d" % _est.get("macetas", 0))
	print("[GeneradorCiudad] Playa: palmeras %d | sombrillas %d | reposeras %d"
			% [_est.get("palmeras", 0), _est.get("sombrillas", 0), _est.get("reposeras", 0)])
	print("[GeneradorCiudad] Prado costero: árboles %d | arbustos %d (césped, sin macetas)"
			% [_est.get("arboles_costa", 0), _est.get("arbustos_costa", 0)])
	print("[GeneradorCiudad] Ventanas nocturnas: %d encendidas de %d ventanas (%d edificios)"
			% [_est.get("ventanas_luz", 0), _est.get("ventanas", 0), _est.get("modulares", 0)])
	# Invariante de manzanas: cada parcela acaba con edificio o con plaza (las
	# incidencias del fallback se cuentan aparte); si no cuadra, hay solares
	# sin resolver.
	print("[GeneradorCiudad] Parcelas: %d = edificios %d + plazas %d (fallbacks: %d)"
			% [_est.get("parcelas", 0),
			int(_est.get("modulares", 0)) + int(_est.get("prefabs", 0)),
			_est.get("plazas", 0), _est.get("parcelas_vacias", 0)])
	print("[GeneradorCiudad] Edificios: %d (%d prefabricados + %d modulares) | props: %d | vegetación: %d"
			% [int(_est.get("prefabs", 0)) + int(_est.get("modulares", 0)), _est.get("prefabs", 0),
			_est.get("modulares", 0), _est.get("props", 0), _est.get("vegetacion", 0)])
	print("[GeneradorCiudad] Portales: %d | puertas colocadas: %d"
			% [_est.get("portales", 0), prueba_portales.size()])
	# Cierre de fachadas: si aparecen piezas vacías sería que alguna celda se
	# quedó sin muro (un hueco por el que se vería el interior del edificio).
	var familias := ""
	for fam: String in _familias.keys():
		var f: Dictionary = _familias[fam]
		familias += "%s%d " % [fam.substr(0, 1).to_upper(), (f.get("muros", []) as Array).size()]
	var vacias := int(_est.get("piezas_vacias", 0))
	print("[GeneradorCiudad] Fachadas: familias %s| piezas sin modelo: %d %s"
			% [familias, vacias, "OK (todo cerrado)" if vacias == 0 else "OJO: hay huecos"])
	var multi := 0
	var sueltos := 0
	var raiz := get_node_or_null(NODO_CIUDAD)
	if raiz != null:
		var conteo := _contar_nodos(raiz, [0], [0])
		multi = conteo[0]
		sueltos = conteo[1]
	print("[GeneradorCiudad] MultiMeshInstance3D: %d | nodos instanciados: %d | tiempo: %.2f s"
			% [multi, sueltos, float(ms) / 1000.0])
	if _medir_etapas and raiz != null:
		var hc := _hash_transformaciones(raiz, HASH_EXCLUIDOS)
		print("[GeneradorCiudad][HASH-CIUDAD] %d | nodos=%d | instancias_multimesh=%d | saltados=%d | aabb_cajas=%s"
				% [hc[0], hc[1], hc[2], hc[3], str(_aabb_cajas)])
		var peat := raiz.get_node_or_null("Peatones")
		if peat != null:
			var hpe := _hash_transformaciones(peat, [])
			print("[GeneradorCiudad][HASH-PEATONES] %d | nodos=%d (subárbol excluido del hash de ciudad)"
					% [hpe[0], hpe[1]])
		else:
			print("[GeneradorCiudad][HASH-PEATONES] ausente en este momento (0 nodos)")
	print("[GeneradorCiudad] Contenedores en nodo '%s'." % NODO_CIUDAD)
	if director_peatones != null:
		var rp: Dictionary = director_peatones.call("resumen")
		print("[GeneradorCiudad] Peatones: %d ciudadanos | caminando %d · sentados %d · tumbados %d | bancos libres %d/%d reposeras libres %d/%d | cruces pintados %d" % [
			rp.get("total", 0), rp.get("caminando", 0), rp.get("sentados", 0), rp.get("tumbados", 0),
			rp.get("banco_libre", 0), _bancos_datos.size() * 2,
			rp.get("reposera_libre", 0), _reposeras_datos.size(), _cruces_peatones.size()])


## Cuenta [MultiMeshInstance3D, piezas instanciadas] bajo un nodo.
func _contar_nodos(nodo: Node, multi: Array, sueltos: Array) -> Array:
	if nodo is MultiMeshInstance3D:
		multi[0] = int(multi[0]) + 1
	elif _modelos.has(nodo.name):
		sueltos[0] = int(sueltos[0]) + 1
	for c in nodo.get_children():
		_contar_nodos(c, multi, sueltos)
	return [int(multi[0]), int(sueltos[0])]