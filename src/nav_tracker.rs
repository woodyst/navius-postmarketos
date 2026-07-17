use qmetaobject::*;
use rusqlite::{Connection, params};
use std::collections::VecDeque;
use std::sync::Mutex;
use std::time::{SystemTime, UNIX_EPOCH};

const TRACKS_DB:      &str = "/home/phablet/.local/share/navius.woodyst/gps_tracks.db";
const TRACKS_GPX_DIR: &str = "/home/phablet/.local/share/navius.woodyst/gps_tracks";

// Cola de resultados de operaciones BD en background.
// Los hilos de fondo empujan aquí; poll() drena en el hilo Qt.
static PENDING: Mutex<VecDeque<TrackOp>> = Mutex::new(VecDeque::new());

enum TrackOp {
    ListTracks(String),        // json
    SimRoute(String, String, String),  // (id, points_json, route_json)
    GpxExport(String, String), // (id, path_o_vacío)
    Deleted(String),           // id
}

fn open_db() -> rusqlite::Result<Connection> {
    let conn = Connection::open(TRACKS_DB)?;
    conn.execute_batch(
        "CREATE TABLE IF NOT EXISTS tracks (
            id           TEXT PRIMARY KEY,
            name         TEXT NOT NULL,
            date_ts      INTEGER NOT NULL,
            duration_s   REAL DEFAULT 0,
            dist_m       REAL DEFAULT 0,
            point_count  INTEGER DEFAULT 0
        );
        CREATE TABLE IF NOT EXISTS track_points (
            track_id TEXT    NOT NULL,
            seq      INTEGER NOT NULL,
            lat      REAL    NOT NULL,
            lon      REAL    NOT NULL,
            spd_kmh  REAL    NOT NULL,
            ts       INTEGER NOT NULL,
            PRIMARY KEY (track_id, seq)
        );
        CREATE INDEX IF NOT EXISTS idx_tp_track ON track_points(track_id, seq);",
    )?;
    // Migración: columna con la ruta Valhalla activa al grabar (shape+maniobras, JSON).
    // Falla si ya existe → se ignora.
    let _ = conn.execute("ALTER TABLE tracks ADD COLUMN route_json TEXT", []);
    Ok(conn)
}

fn now_secs() -> u64 {
    SystemTime::now().duration_since(UNIX_EPOCH).unwrap_or_default().as_secs()
}

fn haversine_m(lat1: f64, lon1: f64, lat2: f64, lon2: f64) -> f64 {
    const R: f64 = 6_371_000.0;
    let dlat = (lat2 - lat1).to_radians();
    let dlon = (lon2 - lon1).to_radians();
    let a = (dlat / 2.0).sin().powi(2)
        + lat1.to_radians().cos() * lat2.to_radians().cos() * (dlon / 2.0).sin().powi(2);
    2.0 * R * a.sqrt().atan2((1.0 - a).sqrt())
}

fn unix_to_iso(ts_secs: i64) -> String {
    if ts_secs < 0 { return "1970-01-01T00:00:00Z".to_string(); }
    let rem = ts_secs % 86400;
    let h = rem / 3600;
    let m = (rem % 3600) / 60;
    let s = rem % 60;
    let (y, mo, d) = days_to_ymd(ts_secs / 86400);
    format!("{y:04}-{mo:02}-{d:02}T{h:02}:{m:02}:{s:02}Z")
}

fn days_to_ymd(mut days: i64) -> (i64, i64, i64) {
    if days < 0 { return (1970, 1, 1); }
    let mut y = 1970i64;
    loop {
        let dy = if is_leap(y) { 366 } else { 365 };
        if days < dy { break; }
        days -= dy;
        y += 1;
    }
    let dim = if is_leap(y) {
        [31i64, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
    } else {
        [31i64, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
    };
    let mut mo = 1i64;
    for &d in &dim { if days < d { break; } days -= d; mo += 1; }
    (y, mo, days + 1)
}

fn is_leap(y: i64) -> bool {
    (y % 4 == 0 && y % 100 != 0) || y % 400 == 0
}

fn fmt_dur(secs: f64) -> String {
    let s = secs as i64;
    if s < 60 { format!("{s}s") }
    else if s < 3600 { format!("{}m {:02}s", s / 60, s % 60) }
    else { format!("{}h {:02}m", s / 3600, (s % 3600) / 60) }
}

fn fmt_dist(m: f64) -> String {
    if m < 1000.0 { format!("{m:.0} m") }
    else { format!("{:.1} km", m / 1000.0) }
}

fn _track_header(pts: &[(f64,f64,f64,i64)]) -> (i64, f64, f64, i32) {
    let first_ts   = pts[0].3;
    let last_ts    = pts[pts.len()-1].3;
    let duration_s = ((last_ts - first_ts) as f64) / 1000.0;
    let mut dist_m = 0.0f64;
    for i in 1..pts.len() {
        dist_m += haversine_m(pts[i-1].0, pts[i-1].1, pts[i].0, pts[i].1);
    }
    (first_ts / 1000, duration_s, dist_m, pts.len() as i32)
}

// Escribe un batch de puntos nuevos + actualiza cabecera del track.
// seq_start: índice del primer punto del batch en la secuencia global.
// header: (date_ts, duration_s, dist_m, total_count) del track completo hasta ahora.
fn flush_batch_async(id: String, batch: Vec<(f64,f64,f64,i64)>, seq_start: usize,
                     header: (i64, f64, f64, i32), route_json: String) {
    if batch.is_empty() { return; }
    std::thread::spawn(move || {
        let Ok(mut conn) = open_db() else { return; };
        let (date_ts, duration_s, dist_m, total) = header;
        let route_opt: Option<String> = if route_json.is_empty() { None } else { Some(route_json) };
        let _ = conn.execute(
            "INSERT OR REPLACE INTO tracks (id,name,date_ts,duration_s,dist_m,point_count,route_json) \
             VALUES (?1,?2,?3,?4,?5,?6,?7)",
            params![id, id, date_ts, duration_s, dist_m, total, route_opt],
        );
        let Ok(tx) = conn.transaction() else { return; };
        if let Ok(mut stmt) = tx.prepare(
            "INSERT OR IGNORE INTO track_points (track_id,seq,lat,lon,spd_kmh,ts) \
             VALUES (?1,?2,?3,?4,?5,?6)"
        ) {
            for (i, (lat, lon, spd, ts)) in batch.iter().enumerate() {
                let _ = stmt.execute(params![id, (seq_start + i) as i32, lat, lon, spd, ts]);
            }
        }
        let _ = tx.commit();
    });
}

fn save_track_async(id: String, pts: Vec<(f64, f64, f64, i64)>, flushed: usize, route_json: String) {
    if pts.len() < 2 { return; }
    let header = _track_header(&pts);
    let batch  = pts[flushed..].to_vec();
    flush_batch_async(id, batch, flushed, header, route_json);
}

#[derive(QObject, Default)]
pub struct NavTracker {
    base: qt_base_class!(trait QObject),

    pub recording:         qt_property!(bool; NOTIFY recording_changed),
    pub recording_changed: qt_signal!(),

    // Señales async — emitidas desde poll() en el hilo Qt
    pub tracks_ready:    qt_signal!(json: QString),
    pub sim_route_ready: qt_signal!(id: QString, json: QString, route: QString),
    pub gpx_ready:       qt_signal!(id: QString, path: QString),
    pub track_deleted:   qt_signal!(id: QString),

    pub start_recording: qt_method!(fn start_recording(&mut self) {
        self.pts.clear();
        self.flushed = 0;
        self.current_id = format!("track_{}", now_secs());
        self.current_route_json.clear();
        self.recording = true;
        self.recording_changed();
    }),

    pub stop_and_save: qt_method!(fn stop_and_save(&mut self) -> QString {
        if !self.recording { return QString::from(""); }
        let pts     = std::mem::take(&mut self.pts);
        let id      = std::mem::take(&mut self.current_id);
        let flushed = self.flushed;
        self.flushed  = 0;
        self.recording = false;
        self.recording_changed();
        if pts.len() < 2 { return QString::from(""); }
        let ret = id.clone();
        let route_json = std::mem::take(&mut self.current_route_json);
        save_track_async(id, pts, flushed, route_json);
        QString::from(ret.as_str())
    }),

    // Guarda la ruta Valhalla activa (shape+maniobras, JSON) para asociarla al track
    // en grabación. QML la pasa al iniciar grabación si hay navegación activa, y en
    // cada recálculo. Vacío = track sin ruta (replay solo GPS crudo).
    pub set_route_json: qt_method!(fn set_route_json(&mut self, json: QString) {
        self.current_route_json = json.into();
    }),

    pub discard_recording: qt_method!(fn discard_recording(&mut self) {
        // Borra de la BD si ya se había hecho flush parcial
        if !self.current_id.is_empty() {
            let id = std::mem::take(&mut self.current_id);
            std::thread::spawn(move || {
                if let Ok(conn) = open_db() {
                    let _ = conn.execute("DELETE FROM track_points WHERE track_id=?1", params![id]);
                    let _ = conn.execute("DELETE FROM tracks WHERE id=?1", params![id]);
                }
            });
        }
        self.pts.clear();
        self.flushed = 0;
        self.recording = false;
        self.recording_changed();
    }),

    pub add_point: qt_method!(fn add_point(&mut self, lat: f64, lon: f64, spd_kmh: f64, ts: f64) {
        if !self.recording { return; }
        if let Some(&(plat, plon, pspd, _)) = self.pts.last() {
            if haversine_m(plat, plon, lat, lon) < 2.0 && pspd < 1.0 && spd_kmh < 1.0 {
                return;
            }
        }
        self.pts.push((lat, lon, spd_kmh, ts as i64));
        // Flush periódico cada 50 puntos nuevos
        if self.pts.len() - self.flushed >= 50 {
            let batch  = self.pts[self.flushed..].to_vec();
            let from   = self.flushed;
            let header = _track_header(&self.pts);
            let id     = self.current_id.clone();
            let route  = self.current_route_json.clone();
            self.flushed = self.pts.len();
            flush_batch_async(id, batch, from, header, route);
        }
    }),

    pub get_point_count: qt_method!(fn get_point_count(&self) -> i32 {
        self.pts.len() as i32
    }),

    // Dispara la carga de tracks en background; resultado llega via tracks_ready(json).
    pub list_tracks_async: qt_method!(fn list_tracks_async(&self) {
        std::thread::spawn(|| {
            let json = _load_tracks_json();
            if let Ok(mut q) = PENDING.lock() { q.push_back(TrackOp::ListTracks(json)); }
        });
    }),

    // Dispara la carga de puntos en background; resultado llega via
    // sim_route_ready(id, points_json, route_json). route_json = "" si el track no
    // tiene ruta Valhalla guardada (tracks viejos o grabados sin navegación).
    pub get_track_sim_route_async: qt_method!(fn get_track_sim_route_async(&self, id: QString) {
        let id_str = id.to_string();
        std::thread::spawn(move || {
            let json  = _load_sim_route_json(&id_str);
            let route = _load_track_route_json(&id_str);
            if let Ok(mut q) = PENDING.lock() { q.push_back(TrackOp::SimRoute(id_str, json, route)); }
        });
    }),

    // Dispara la exportación en background; resultado llega via gpx_ready(id, path).
    pub export_gpx_async: qt_method!(fn export_gpx_async(&self, id: QString) {
        let id_str = id.to_string();
        std::thread::spawn(move || {
            let path = _export_gpx(&id_str);
            if let Ok(mut q) = PENDING.lock() { q.push_back(TrackOp::GpxExport(id_str, path)); }
        });
    }),

    // Dispara el borrado en background; resultado llega via track_deleted(id).
    pub delete_track_async: qt_method!(fn delete_track_async(&self, id: QString) {
        let id_str = id.to_string();
        std::thread::spawn(move || {
            if let Ok(conn) = open_db() {
                let _ = conn.execute("DELETE FROM track_points WHERE track_id=?1", params![id_str]);
                let _ = conn.execute("DELETE FROM tracks WHERE id=?1", params![id_str]);
            }
            let _ = std::fs::remove_file(format!("{TRACKS_GPX_DIR}/{id_str}.gpx"));
            if let Ok(mut q) = PENDING.lock() { q.push_back(TrackOp::Deleted(id_str)); }
        });
    }),

    pub delete_all_tracks: qt_method!(fn delete_all_tracks(&self) {
        std::thread::spawn(|| {
            if let Ok(conn) = open_db() {
                let _ = conn.execute("DELETE FROM track_points", []);
                let _ = conn.execute("DELETE FROM tracks", []);
            }
            if let Ok(entries) = std::fs::read_dir(TRACKS_GPX_DIR) {
                for entry in entries.flatten() {
                    let path = entry.path();
                    if path.extension().map_or(false, |e| e == "gpx") {
                        let _ = std::fs::remove_file(path);
                    }
                }
            }
        });
    }),

    pub rename_track: qt_method!(fn rename_track(&self, id: QString, name: QString) {
        let (id, name) = (id.to_string(), name.to_string());
        std::thread::spawn(move || {
            if let Ok(conn) = open_db() {
                let _ = conn.execute("UPDATE tracks SET name=?1 WHERE id=?2", params![name, id]);
            }
        });
    }),

    // Llamado por un QML Timer cada 100 ms; drena la cola y emite señales.
    pub poll: qt_method!(fn poll(&mut self) {
        loop {
            let op = { PENDING.lock().ok().and_then(|mut q| q.pop_front()) };
            match op {
                Some(TrackOp::ListTracks(json))        => self.tracks_ready(QString::from(json.as_str())),
                Some(TrackOp::SimRoute(id, json, route)) => self.sim_route_ready(QString::from(id.as_str()), QString::from(json.as_str()), QString::from(route.as_str())),
                Some(TrackOp::GpxExport(id, path))     => self.gpx_ready(QString::from(id.as_str()), QString::from(path.as_str())),
                Some(TrackOp::Deleted(id))             => self.track_deleted(QString::from(id.as_str())),
                None => break,
            }
        }
    }),

    pts:                Vec<(f64, f64, f64, i64)>,
    current_id:         String,
    flushed:            usize,
    current_route_json: String,
}

fn _load_tracks_json() -> String {
    let Ok(conn) = open_db() else { return "[]".to_string(); };
    let Ok(mut stmt) = conn.prepare(
        "SELECT id,name,date_ts,duration_s,dist_m,point_count, \
         (route_json IS NOT NULL AND route_json != '') as has_route \
         FROM tracks ORDER BY date_ts DESC"
    ) else { return "[]".to_string(); };
    let mut out = String::from("[");
    let mut first = true;
    if let Ok(rows) = stmt.query_map([], |r| Ok((
        r.get::<_,String>(0)?, r.get::<_,String>(1)?,
        r.get::<_,i64>(2)?,    r.get::<_,f64>(3)?,
        r.get::<_,f64>(4)?,    r.get::<_,i32>(5)?,
        r.get::<_,i32>(6)?,
    ))) {
        for row in rows.flatten() {
            let (id, name, date_ts, dur, dist, npts, has_route) = row;
            if !first { out.push(','); }
            first = false;
            let ne = name.replace('\\', "\\\\").replace('"', "\\\"");
            let ds = unix_to_iso(date_ts);
            let hr = if has_route != 0 { "true" } else { "false" };
            out.push_str(&format!(
                r#"{{"id":"{id}","name":"{ne}","date":"{ds}","dur":"{}","dist":"{}","npts":{npts},"has_route":{hr}}}"#,
                fmt_dur(dur), fmt_dist(dist)
            ));
        }
    }
    out.push(']');
    out
}

// Devuelve la ruta Valhalla guardada del track (JSON) o "" si no tiene.
fn _load_track_route_json(id: &str) -> String {
    let Ok(conn) = open_db() else { return String::new(); };
    conn.query_row(
        "SELECT route_json FROM tracks WHERE id=?1", params![id],
        |r| r.get::<_, Option<String>>(0),
    ).ok().flatten().unwrap_or_default()
}

fn _load_sim_route_json(id: &str) -> String {
    let Ok(conn) = open_db() else { return "[]".to_string(); };
    let Ok(mut stmt) = conn.prepare(
        "SELECT lat,lon,spd_kmh,ts FROM track_points WHERE track_id=?1 ORDER BY seq"
    ) else { return "[]".to_string(); };
    let mut out = String::from("[");
    let mut first = true;
    if let Ok(rows) = stmt.query_map(params![id], |r| {
        Ok((r.get::<_,f64>(0)?, r.get::<_,f64>(1)?, r.get::<_,f64>(2)?, r.get::<_,i64>(3)?))
    }) {
        for (lat, lon, spd, ts) in rows.flatten() {
            if !first { out.push(','); }
            first = false;
            out.push_str(&format!(r#"{{"lat":{lat:.7},"lon":{lon:.7},"spd":{spd:.2},"ts":{ts}}}"#));
        }
    }
    out.push(']');
    out
}

fn _export_gpx(id: &str) -> String {
    let Ok(conn) = open_db() else { return String::new(); };
    let Ok((name, _)) = conn.query_row(
        "SELECT name,date_ts FROM tracks WHERE id=?1", params![id],
        |r| Ok((r.get::<_,String>(0)?, r.get::<_,i64>(1)?)),
    ) else { return String::new(); };
    let Ok(mut stmt) = conn.prepare(
        "SELECT lat,lon,spd_kmh,ts FROM track_points WHERE track_id=?1 ORDER BY seq"
    ) else { return String::new(); };
    let mut trkpts = String::new();
    if let Ok(rows) = stmt.query_map(params![id], |r| Ok((
        r.get::<_,f64>(0)?, r.get::<_,f64>(1)?, r.get::<_,f64>(2)?, r.get::<_,i64>(3)?
    ))) {
        for (lat, lon, spd_kmh, ts_ms) in rows.flatten() {
            trkpts.push_str(&format!(
                "      <trkpt lat=\"{lat:.7}\" lon=\"{lon:.7}\">\n\
                 \t<time>{}</time>\n\
                 \t<extensions><speed>{:.3}</speed></extensions>\n\
                 \t</trkpt>\n",
                unix_to_iso(ts_ms / 1000), spd_kmh / 3.6
            ));
        }
    }
    let nx = name.replace('&',"&amp;").replace('<',"&lt;").replace('>',"&gt;");
    let gpx = format!(
        "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n\
         <gpx version=\"1.1\" creator=\"Navius GPS\" xmlns=\"http://www.topografix.com/GPX/1/1\">\n  \
         <trk>\n    <name>{nx}</name>\n    <trkseg>\n\
         {trkpts}\
         </trkseg>\n  </trk>\n</gpx>"
    );
    let _ = std::fs::create_dir_all(TRACKS_GPX_DIR);
    let path = format!("{TRACKS_GPX_DIR}/{id}.gpx");
    if std::fs::write(&path, &gpx).is_ok() { path } else { String::new() }
}
