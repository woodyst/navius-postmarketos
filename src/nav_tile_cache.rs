// Lector de caché de tiles Mapbox GL (SQLite) con parseo MVT.
//
// El renderer QMapLibre almacena tiles en:
//   ~/.cache/navius/navius/mapboxgl-qml-cache.db
// (ruta por defecto de Qt: ~/.cache/{OrganizationName}/{ApplicationName}/...,
// ver QCoreApplication::setOrganizationName/setApplicationName en main.rs)
// Esquema: tiles(z, x, y, data BLOB, compressed INTEGER)
//   compressed=1 → data es gzip; compressed=0 → MVT en crudo
//
// roads_near(lat, lon) → JSON con LineStrings de vías del área 3×3 z14.
// Usado para dead reckoning sin ruta calculada o snap-to-road offline.

use qmetaobject::*;
use rusqlite::{params, Connection};
use std::io::Read;

// ─── QObject ──────────────────────────────────────────────────────────────────

#[derive(QObject, Default)]
pub struct NavTileCache {
    base: qt_base_class!(trait QObject),

    /// JSON: [{class, name, coords:[[lat,lon],...]},...] o "[]" si no hay datos.
    pub roads_near: qt_method!(fn roads_near(&self, lat: f64, lon: f64) -> QString {
        match query_roads_near(lat, lon) {
            Ok(json) => json.into(),
            Err(e)   => { eprintln!("[tile_cache] roads_near: {e}"); "[]".into() }
        }
    }),

    /// Cuántos tiles z14 hay cacheados en el área 3×3 alrededor del punto (0–9).
    pub cached_tile_count: qt_method!(fn cached_tile_count(&self, lat: f64, lon: f64) -> i32 {
        count_near(lat, lon).unwrap_or(0)
    }),
}

// ─── Ruta del caché ───────────────────────────────────────────────────────────

fn cache_db_path() -> Option<std::path::PathBuf> {
    let home = std::env::var("HOME").ok()?;
    [
        format!("{home}/.cache/navius/navius/mapboxgl-qml-cache.db"),
        format!("{home}/.cache/navius/mapboxgl-qml-cache.db"),
    ]
    .into_iter()
    .map(std::path::PathBuf::from)
    .find(|p| p.exists())
}

fn open_db() -> Result<Connection, String> {
    let path = cache_db_path().ok_or("tile cache DB no encontrado")?;
    Connection::open_with_flags(&path, rusqlite::OpenFlags::SQLITE_OPEN_READ_ONLY)
        .map_err(|e| e.to_string())
}

// ─── Matemática de tiles (z14) ────────────────────────────────────────────────

const ZOOM: i64  = 14;
const N_F: f64   = (1u32 << 14) as f64; // 16384.0

fn latlon_to_tile(lat: f64, lon: f64) -> (i64, i64) {
    let x = ((lon + 180.0) / 360.0 * N_F).floor() as i64;
    let lat_r = lat.to_radians();
    let y = ((1.0 - (lat_r.tan() + 1.0 / lat_r.cos()).ln() / std::f64::consts::PI) / 2.0 * N_F)
        .floor() as i64;
    let max = (1i64 << ZOOM) - 1;
    (x.clamp(0, max), y.clamp(0, max))
}

fn tile_px_to_latlon(tx: i64, ty: i64, px: f64, py: f64, extent: f64) -> (f64, f64) {
    let lon = (tx as f64 + px / extent) / N_F * 360.0 - 180.0;
    let merc = std::f64::consts::PI * (1.0 - 2.0 * (ty as f64 + py / extent) / N_F);
    let lat  = merc.sinh().atan().to_degrees();
    (lat, lon)
}

// ─── Consultas SQLite ─────────────────────────────────────────────────────────

fn count_near(lat: f64, lon: f64) -> Result<i32, String> {
    let db = open_db()?;
    let (cx, cy) = latlon_to_tile(lat, lon);
    db.query_row(
        "SELECT COUNT(*) FROM tiles WHERE z=? AND x BETWEEN ? AND ? AND y BETWEEN ? AND ?",
        params![ZOOM, cx - 1, cx + 1, cy - 1, cy + 1],
        |r| r.get(0),
    )
    .map_err(|e| e.to_string())
}

fn query_roads_near(lat: f64, lon: f64) -> Result<String, String> {
    let db = open_db()?;
    let (cx, cy) = latlon_to_tile(lat, lon);

    let mut stmt = db
        .prepare(
            "SELECT x, y, data, compressed \
             FROM tiles \
             WHERE z=? AND x BETWEEN ? AND ? AND y BETWEEN ? AND ?",
        )
        .map_err(|e| e.to_string())?;

    let mut all_roads: Vec<RoadFeature> = Vec::new();

    let rows = stmt
        .query_map(
            params![ZOOM, cx - 1, cx + 1, cy - 1, cy + 1],
            |row| {
                Ok((
                    row.get::<_, i64>(0)?,
                    row.get::<_, i64>(1)?,
                    row.get::<_, Vec<u8>>(2)?,
                    row.get::<_, i32>(3)?,
                ))
            },
        )
        .map_err(|e| e.to_string())?;

    for row in rows {
        let (tx, ty, data, compressed) = row.map_err(|e| e.to_string())?;
        let mvt = if compressed != 0 {
            decompress_gzip(&data)?
        } else {
            data
        };
        if let Some(mut roads) = extract_roads(&mvt, tx, ty) {
            all_roads.append(&mut roads);
        }
    }

    Ok(roads_to_json(&all_roads))
}

// ─── Descompresión gzip ───────────────────────────────────────────────────────

fn decompress_gzip(data: &[u8]) -> Result<Vec<u8>, String> {
    let mut dec = flate2::read::GzDecoder::new(data);
    let mut out = Vec::new();
    dec.read_to_end(&mut out).map_err(|e| format!("gzip: {e}"))?;
    Ok(out)
}

// ─── Extracción MVT ───────────────────────────────────────────────────────────

struct RoadFeature {
    class:  String,
    name:   String,
    coords: Vec<(f64, f64)>,
}

// Capas que contienen vías en los esquemas más comunes (OpenMapTiles, Shortbread)
const ROAD_LAYERS: &[&str] = &["transportation", "streets", "roads", "highway", "road"];

fn extract_roads(mvt: &[u8], tx: i64, ty: i64) -> Option<Vec<RoadFeature>> {
    let mut rdr    = Pb::new(mvt);
    let mut result = Vec::new();

    while rdr.remaining() {
        let (field, wire) = rdr.tag()?;
        if field == 3 && wire == 2 {
            // Tile.layer
            let layer_data = rdr.bytes()?;
            if let Some(mut roads) = parse_layer(layer_data, tx, ty) {
                result.append(&mut roads);
            }
        } else {
            rdr.skip(wire)?;
        }
    }

    Some(result)
}

fn parse_layer(data: &[u8], tx: i64, ty: i64) -> Option<Vec<RoadFeature>> {
    // Pasada 1: recopilar metadatos (nombre, extent, keys[], values[])
    let mut name   = String::new();
    let mut extent = 4096u32;
    let mut keys:   Vec<String> = Vec::new();
    let mut values: Vec<String> = Vec::new();

    {
        let mut rdr = Pb::new(data);
        while rdr.remaining() {
            let (field, wire) = rdr.tag()?;
            match (field, wire) {
                (1,  2) => name   = String::from_utf8_lossy(rdr.bytes()?).into_owned(),
                (3,  2) => keys.push(String::from_utf8_lossy(rdr.bytes()?).into_owned()),
                (4,  2) => values.push(pb_string_value(rdr.bytes()?)),
                (5,  0) => extent = rdr.varint()? as u32,
                (15, 0) => { rdr.varint()?; }
                (2,  2) => { rdr.bytes()?; } // Feature — ignorar en pasada 1
                (_, wt) => { rdr.skip(wt)?; }
            }
        }
    }

    // Filtrar capas que no son vías
    if !ROAD_LAYERS.iter().any(|&l| name == l) {
        return None;
    }

    let extent_f = extent as f64;

    // Pasada 2: decodificar features LineString con los metadatos ya completos
    let mut rdr2   = Pb::new(data);
    let mut result = Vec::new();

    while rdr2.remaining() {
        let (field, wire) = rdr2.tag()?;
        if field == 2 && wire == 2 {
            let feat = rdr2.bytes()?;
            if let Some(road) = parse_road_feature(feat, &keys, &values, tx, ty, extent_f) {
                result.push(road);
            }
        } else {
            rdr2.skip(wire)?;
        }
    }

    Some(result)
}

fn parse_road_feature(
    data:    &[u8],
    keys:    &[String],
    values:  &[String],
    tx:      i64,
    ty:      i64,
    extent:  f64,
) -> Option<RoadFeature> {
    let mut rdr       = Pb::new(data);
    let mut geom_type = 0u32;
    let mut tags:     Vec<u32> = Vec::new();
    let mut geometry: Vec<u32> = Vec::new();

    while rdr.remaining() {
        let (field, wire) = rdr.tag()?;
        match (field, wire) {
            (1, 0) => { rdr.varint()?; } // id — ignorar
            (2, 2) => tags      = rdr.packed_u32()?,
            (3, 0) => geom_type = rdr.varint()? as u32,
            (4, 2) => geometry  = rdr.packed_u32()?,
            (_, wt) => { rdr.skip(wt)?; }
        }
    }

    // Solo LineString (tipo 2)
    if geom_type != 2 { return None; }

    // Extraer class y name de los pares de tags (key_idx, val_idx)
    let mut class     = String::new();
    let mut road_name = String::new();
    let mut i = 0;
    while i + 1 < tags.len() {
        let ki = tags[i]     as usize;
        let vi = tags[i + 1] as usize;
        if ki < keys.len() && vi < values.len() {
            match keys[ki].as_str() {
                "class" | "highway" | "kind" => class     = values[vi].clone(),
                "name"  | "name:es"          => road_name = values[vi].clone(),
                _ => {}
            }
        }
        i += 2;
    }

    // Decodificar geometría MVT → coordenadas lat/lon
    let coords = decode_linestring_geo(&geometry, tx, ty, extent)?;

    Some(RoadFeature { class, name: road_name, coords })
}

// Decodifica comandos MVT y convierte a lat/lon directamente.
fn decode_linestring_geo(
    geometry: &[u32],
    tx:       i64,
    ty:       i64,
    extent:   f64,
) -> Option<Vec<(f64, f64)>> {
    let mut coords:   Vec<(f64, f64)> = Vec::new();
    let mut cursor_x: i32             = 0;
    let mut cursor_y: i32             = 0;
    let mut i = 0;

    while i < geometry.len() {
        let cmd_word = geometry[i];
        let cmd      = cmd_word & 0x7;
        let count    = (cmd_word >> 3) as usize;
        i += 1;

        match cmd {
            1 | 2 => { // MoveTo o LineTo
                for _ in 0..count {
                    if i + 1 >= geometry.len() { break; }
                    cursor_x += zigzag(geometry[i]);
                    cursor_y += zigzag(geometry[i + 1]);
                    i += 2;
                    let (lat, lon) =
                        tile_px_to_latlon(tx, ty, cursor_x as f64, cursor_y as f64, extent);
                    coords.push((lat, lon));
                }
            }
            7 => {} // ClosePath ��� sin parámetros
            _ => break,
        }
    }

    if coords.len() >= 2 { Some(coords) } else { None }
}

fn zigzag(n: u32) -> i32 {
    ((n >> 1) as i32) ^ (-((n & 1) as i32))
}

// Extrae string_value (field 1) de un mensaje Value protobuf.
fn pb_string_value(data: &[u8]) -> String {
    let mut rdr = Pb::new(data);
    while rdr.remaining() {
        let (field, wire) = match rdr.tag() { Some(v) => v, None => break };
        if field == 1 && wire == 2 {
            if let Some(s) = rdr.bytes() {
                return String::from_utf8_lossy(s).into_owned();
            }
        } else {
            let _ = rdr.skip(wire);
        }
    }
    String::new()
}

// ─── Lector protobuf mínimo ───────────────────────────────────────────────────

struct Pb<'a> {
    data: &'a [u8],
    pos:  usize,
}

impl<'a> Pb<'a> {
    fn new(data: &'a [u8]) -> Self { Pb { data, pos: 0 } }

    fn remaining(&self) -> bool { self.pos < self.data.len() }

    fn varint(&mut self) -> Option<u64> {
        let mut v = 0u64;
        let mut s = 0u32;
        loop {
            if self.pos >= self.data.len() { return None; }
            let b = self.data[self.pos]; self.pos += 1;
            v |= ((b & 0x7f) as u64) << s;
            if b & 0x80 == 0 { return Some(v); }
            s += 7;
            if s >= 64 { return None; }
        }
    }

    fn tag(&mut self) -> Option<(u32, u8)> {
        let v = self.varint()? as u32;
        Some((v >> 3, (v & 0x7) as u8))
    }

    fn bytes(&mut self) -> Option<&'a [u8]> {
        let len = self.varint()? as usize;
        if self.pos + len > self.data.len() { return None; }
        let s = &self.data[self.pos..self.pos + len];
        self.pos += len;
        Some(s)
    }

    fn skip(&mut self, wire: u8) -> Option<()> {
        match wire {
            0 => { self.varint()?; }
            1 => { if self.pos + 8 > self.data.len() { return None; } self.pos += 8; }
            2 => { self.bytes()?; }
            5 => { if self.pos + 4 > self.data.len() { return None; } self.pos += 4; }
            _ => return None,
        }
        Some(())
    }

    fn packed_u32(&mut self) -> Option<Vec<u32>> {
        let data = self.bytes()?;
        let mut r = Pb::new(data);
        let mut v = Vec::new();
        while r.remaining() { v.push(r.varint()? as u32); }
        Some(v)
    }
}

// ─── Serialización JSON manual ────────────────────────────────────────────────

fn roads_to_json(roads: &[RoadFeature]) -> String {
    let mut out = String::with_capacity(roads.len() * 200);
    out.push('[');
    for (i, r) in roads.iter().enumerate() {
        if i > 0 { out.push(','); }
        out.push_str("{\"class\":\"");
        json_str(&r.class, &mut out);
        out.push_str("\",\"name\":\"");
        json_str(&r.name, &mut out);
        out.push_str("\",\"coords\":[");
        for (j, &(lat, lon)) in r.coords.iter().enumerate() {
            if j > 0 { out.push(','); }
            out.push('[');
            out.push_str(&format!("{:.6},{:.6}", lat, lon));
            out.push(']');
        }
        out.push_str("]}");
    }
    out.push(']');
    out
}

fn json_str(s: &str, out: &mut String) {
    for c in s.chars() {
        match c {
            '"'  => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            c    => out.push(c),
        }
    }
}
