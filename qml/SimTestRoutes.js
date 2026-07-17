.pragma library

// Datos de radar para rutas de test.
// La geometría de cada ruta la calcula Valhalla desde los ENDPOINTS.
// radarData: {fijos:[{lat,lon,maxspeed,direction}], tramos:[{shape,maxspeed,lengthM}]}

// ── Radar fijo A-3 km 20, sentido NO (rumbo ~307°) ───────────────────────────
var _radarDataFijo = {
    fijos:  [{lat:40.3221297, lon:-3.515801, maxspeed:120, direction:307}],
    tramos: []
}

// ── Mismo radar, ruta en sentido SE (rumbo ~127°) → banner azul contrario ────
var _radarDataFijo2 = {
    fijos:  [{lat:40.3221297, lon:-3.515801, maxspeed:120, direction:307}],
    tramos: []
}

// ── Radar de tramo RM-603 Avenida Mazarrón ───────────────────────────────────
// Nodos OSM 4136904469 / 4136904470  (lat≈37.935-37.940, maxspeed=60)
var _radarDataTramo = {
    fijos: [],
    tramos: [{
        shape: [
            [-1.191770, 37.936987],
            [-1.186960, 37.937902],
            [-1.182150, 37.938817]
        ],
        maxspeed: 60,
        lengthM: 870
    }]
}

// ── API pública ───────────────────────────────────────────────────────────────

var NAMES = [
    "Muntaner → Gran Via (BCN)",
    "Test radar fijo 1",
    "Test radar fijo 2",
    "Test radar tramo",
    "Ruta del usuario"
]

// Puntos de inicio y fin de cada ruta (para SearchPanel)
var ENDPOINTS = [
    null,   // Muntaner→Gran Via usa loadDemoRoute en _applySimRoute
    { originLat: 40.327783,  originLon: -3.522482,  originName: "A-3 radar fijo 2 (inicio)",
      destLat:   40.316169,  destLon:   -3.506728,  destName:   "A-3 radar fijo 2 (fin)" },
    { originLat: 37.939000,  originLon: -1.200000,  originName: "Test radar tramo (inicio)",
      destLat:   37.940650,  destLon:   -1.172529,  destName:   "Test radar tramo (fin)" },
    { originLat: 40.316366,  originLon: -3.506753,  originName: "A-3 radar fijo 1 (inicio)",
      destLat:   40.327882,  destLon:   -3.522327,  destName:   "A-3 radar fijo 1 (fin)" }
]

// idx: 0=fijo1(NO), 1=fijo2(SE), 2=tramo
// Devuelve radarData + endpoints; la ruta la calcula Valhalla en SearchPanel.
function getRoute(idx) {
    if (idx === 0) return { radarData: _radarDataFijo,  endpoints: ENDPOINTS[3] }
    if (idx === 1) return { radarData: _radarDataFijo2, endpoints: ENDPOINTS[1] }
    if (idx === 2) return { radarData: _radarDataTramo, endpoints: ENDPOINTS[2] }
    return null
}
