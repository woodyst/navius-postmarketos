use cpp::cpp;
use qmetaobject::*;

// ---------------------------------------------------------------------------
// Global C++ block – ALL C++ lives here so cpp_build can find it reliably.
// Impl methods call these via plain extern "C" FFI, no inline cpp! needed.
// ---------------------------------------------------------------------------
cpp! {{
    #include "satellite_source.h"
    #include <QtCore/QTimer>

    // Called from the QTimer lambda every second.
    extern "C" void navius_sat_tick(uintptr_t model_ptr, uintptr_t source_ptr);

    extern "C" void* navius_create_source() {
        return new SatelliteSource();
    }

    // Returns 1 if no GPS source could be created at all, 0 otherwise.
    extern "C" int navius_source_has_error(void *src) {
        return ((SatelliteSource*)src)->is_available() ? 0 : 1;
    }

    extern "C" void navius_delete_source(void *src) {
        delete (SatelliteSource*)src;
    }

    extern "C" void* navius_create_timer(uintptr_t self_ptr, void *src) {
        auto *timer = new QTimer();
        uintptr_t sp = (uintptr_t)src;
        QObject::connect(timer, &QTimer::timeout, [self_ptr, sp]() {
            navius_sat_tick(self_ptr, sp);
        });
        timer->setInterval(1000);
        timer->start();
        ((SatelliteSource*)src)->start();
        return timer;
    }

    extern "C" void navius_stop_all(void *timer_ptr, void *src_ptr) {
        auto *timer  = (QTimer*)timer_ptr;
        auto *source = (SatelliteSource*)src_ptr;
        timer->stop();
        source->stop();
        timer->deleteLater();
        delete source;
    }

    extern "C" bool navius_take_sat_updated(void *src) {
        return ((SatelliteSource*)src)->take_sat_updated();
    }

    // Returns last error code from the satellite source and clears it (0 = no error).
    // QGeoSatelliteInfoSource::Error: AccessError=1, ClosedError=2, UnknownSourceError=-1
    extern "C" int navius_take_error_code(void *src) {
        return ((SatelliteSource*)src)->take_error_code();
    }

    extern "C" int navius_count_in_view(void *src) {
        return ((SatelliteSource*)src)->count_in_view();
    }

    extern "C" void navius_get_sat(void *src, int i, SatDataC *out) {
        sat_source_get((const SatelliteSource*)src, i, out);
    }

    extern "C" bool navius_take_pos_updated(void *src) {
        return ((SatelliteSource*)src)->take_pos_updated();
    }

    extern "C" void navius_get_position(void *src, PosDataC *out) {
        *out = ((SatelliteSource*)src)->get_position();
    }

}}

// ---------------------------------------------------------------------------
// Rust FFI declarations matching the extern "C" functions above.
// ---------------------------------------------------------------------------
extern "C" {
    fn navius_create_source() -> *mut std::ffi::c_void;
    fn navius_source_has_error(src: *mut std::ffi::c_void) -> i32;
    fn navius_delete_source(src: *mut std::ffi::c_void);
    fn navius_create_timer(self_ptr: usize, src: *mut std::ffi::c_void)
        -> *mut std::ffi::c_void;
    fn navius_stop_all(timer: *mut std::ffi::c_void, src: *mut std::ffi::c_void);
    fn navius_take_sat_updated(src: *mut std::ffi::c_void) -> bool;
    fn navius_take_error_code(src: *mut std::ffi::c_void) -> i32;
    fn navius_count_in_view(src: *mut std::ffi::c_void) -> i32;
    fn navius_get_sat(src: *mut std::ffi::c_void, i: i32, out: *mut SatDataC);
    fn navius_take_pos_updated(src: *mut std::ffi::c_void) -> bool;
    fn navius_get_position(src: *mut std::ffi::c_void, out: *mut PosDataC);
}

const DEBUG_DIR: &str = "/home/phablet/.local/share/navius.woodyst/debug";

// ---------------------------------------------------------------------------
// Plain structs mirroring the C++ side (repr(C) for FFI).
// ---------------------------------------------------------------------------
#[repr(C)]
#[derive(Clone, Default)]
pub struct SatDataC {
    pub id:        i32,
    pub signal:    f32,
    pub azimuth:   f32,
    pub elevation: f32,
    pub in_use:    bool,
    pub system:    i32,
}

#[repr(C)]
#[derive(Clone, Default)]
pub struct PosDataC {
    pub lat:        f64,
    pub lon:        f64,
    pub speed_ms:   f64,   // m/s  (-1 = unavailable)
    pub accuracy_m: f64,   // m    (-1 = unavailable)
    pub has_fix:    bool,
}

// ---------------------------------------------------------------------------
// QObject exposed to QML – holds parallel arrays for each satellite field.
// ---------------------------------------------------------------------------
#[derive(QObject, Default)]
pub struct SatelliteModel {
    base: qt_base_class!(trait QObject),

    // Satellite status
    pub in_view_count: qt_property!(i32;     NOTIFY counts_changed),
    pub in_use_count:  qt_property!(i32;     NOTIFY counts_changed),
    counts_changed:    qt_signal!(),

    pub is_active:     qt_property!(bool;    NOTIFY active_changed),
    active_changed:    qt_signal!(),

    pub error_string:  qt_property!(QString; NOTIFY error_changed),
    error_changed:     qt_signal!(),

    // Per-satellite parallel arrays (QML reads these directly)
    pub sat_ids:        qt_property!(QVariantList; NOTIFY data_changed),
    pub sat_signals:    qt_property!(QVariantList; NOTIFY data_changed),
    pub sat_azimuths:   qt_property!(QVariantList; NOTIFY data_changed),
    pub sat_elevations: qt_property!(QVariantList; NOTIFY data_changed),
    pub sat_in_use:     qt_property!(QVariantList; NOTIFY data_changed),
    pub sat_systems:    qt_property!(QVariantList; NOTIFY data_changed),
    data_changed:       qt_signal!(),

    // Position data (from lomiri plugin – actual GPS fix)
    pub pos_lat:      qt_property!(f64;  NOTIFY position_changed),
    pub pos_lon:      qt_property!(f64;  NOTIFY position_changed),
    pub pos_speed_kmh: qt_property!(f64; NOTIFY position_changed),
    pub pos_accuracy: qt_property!(f64;  NOTIFY position_changed),
    pub pos_has_fix:  qt_property!(bool; NOTIFY position_changed),
    position_changed: qt_signal!(),

    // QML-invokable slots
    pub start_updates: qt_method!(fn start_updates(&mut self) { self.do_start(); }),
    pub stop_updates:  qt_method!(fn stop_updates(&mut self)  { self.do_stop();  }),

    pub set_traces_enabled: qt_method!(fn set_traces_enabled(&mut self, enabled: bool) {
        let _ = std::fs::create_dir_all(DEBUG_DIR);
        let flag = format!("{}/.traces_enabled", DEBUG_DIR);
        if enabled { let _ = std::fs::File::create(&flag); }
        else       { let _ = std::fs::remove_file(&flag); }
    }),

    pub log_to_file: qt_method!(fn log_to_file(&mut self, msg: QString) {
        let s: String = msg.into();
        let flag = format!("{}/.traces_enabled", DEBUG_DIR);
        if !std::path::Path::new(&flag).exists() { return; }
        let path = format!("{}/net_debug.log", DEBUG_DIR);
        let _ = std::fs::create_dir_all(DEBUG_DIR);
        if let Ok(mut f) = std::fs::OpenOptions::new().create(true).append(true).open(&path) {
            use std::io::Write;
            let _ = writeln!(f, "{}", s);
        }
    }),

    pub write_text_file: qt_method!(fn write_text_file(&mut self, filename: QString, content: QString) {
        let fname: String = filename.into();
        let text:  String = content.into();
        let path = format!("{}/{}", DEBUG_DIR, fname);
        let _ = std::fs::create_dir_all(DEBUG_DIR);
        if let Ok(mut f) = std::fs::OpenOptions::new().create(true).write(true).truncate(true).open(&path) {
            use std::io::Write;
            let _ = f.write_all(text.as_bytes());
        }
    }),

    pub ensure_debug_dir: qt_method!(fn ensure_debug_dir(&self) {
        let _ = std::fs::create_dir_all(DEBUG_DIR);
    }),

    pub delete_debug_file: qt_method!(fn delete_debug_file(&self, pattern: QString) {
        let pat: String = pattern.into();
        if pat == "all" {
            if let Ok(entries) = std::fs::read_dir(DEBUG_DIR) {
                for entry in entries.flatten() {
                    let _ = std::fs::remove_file(entry.path());
                }
            }
            return;
        }
        if pat == "navius_trace" {
            if let Ok(entries) = std::fs::read_dir(DEBUG_DIR) {
                for entry in entries.flatten() {
                    if entry.file_name().to_string_lossy().starts_with("navius_trace") {
                        let _ = std::fs::remove_file(entry.path());
                    }
                }
            }
            return;
        }
        let _ = std::fs::remove_file(format!("{}/{}", DEBUG_DIR, pat));
    }),

    pub delete_mapbox_cache: qt_method!(fn delete_mapbox_cache(&self) {
        if let Ok(home) = std::env::var("HOME") {
            let path = format!("{}/.cache/navius.woodyst/navius.woodyst/mapboxgl-qml-cache.db", home);
            match std::fs::remove_file(&path) {
                Ok(_) => eprintln!("delete_mapbox_cache: borrado {}", path),
                Err(e) if e.kind() == std::io::ErrorKind::NotFound => {},
                Err(e) => eprintln!("delete_mapbox_cache: error {:?}", e),
            }
        }
    }),

    // Raw pointers to C++ heap objects (stored as usize – single-threaded Qt).
    source_ptr: usize,
    timer_ptr:  usize,
    idle_ticks: usize,   // ticks since last satellite update; timeout at 30s
}

impl SatelliteModel {
    fn do_start(&mut self) {
        if self.is_active { return; }
        let self_ptr = self as *mut Self as usize;

        let src = unsafe { navius_create_source() };

        if unsafe { navius_source_has_error(src) } != 0 {
            self.error_string = "GPS no disponible en este dispositivo".into();
            self.error_changed();
            unsafe { navius_delete_source(src); }
            return;
        }

        let timer = unsafe { navius_create_timer(self_ptr, src) };

        self.source_ptr   = src as usize;
        self.timer_ptr    = timer as usize;
        self.idle_ticks   = 0;
        self.error_string = QString::default();
        self.is_active    = true;
        self.active_changed();
    }

    fn do_stop(&mut self) {
        if !self.is_active { return; }
        unsafe {
            navius_stop_all(
                self.timer_ptr  as *mut std::ffi::c_void,
                self.source_ptr as *mut std::ffi::c_void,
            );
        }
        self.timer_ptr  = 0;
        self.source_ptr = 0;
        self.idle_ticks = 0;
        self.is_active  = false;
        self.active_changed();
        self.clear_data();
    }

    pub fn refresh_from_source(&mut self, source_ptr: usize) {
        let src = source_ptr as *mut std::ffi::c_void;

        // --- position update (lomiri plugin – real GPS fix) ---
        if unsafe { navius_take_pos_updated(src) } {
            let mut p = PosDataC::default();
            unsafe { navius_get_position(src, &mut p); }
            let had_fix = self.pos_has_fix;
            self.pos_lat       = p.lat;
            self.pos_lon       = p.lon;
            self.pos_speed_kmh = if p.speed_ms >= 0.0 { p.speed_ms * 3.6 } else { 0.0 };
            self.pos_accuracy  = p.accuracy_m;
            self.pos_has_fix   = p.has_fix;
            self.position_changed();
            if !had_fix && p.has_fix {
                eprintln!("[navius] GPS fix acquired: acc={:.0}m", p.accuracy_m);
                self.error_string = QString::default();
                self.error_changed();
            }
        }

        // Consume (and discard) any satellite source error — geoclue always fails
        // on this device, the error is not actionable.
        let _ = unsafe { navius_take_error_code(src) };

        // --- satellite data ---
        if !unsafe { navius_take_sat_updated(src) } {
            self.idle_ticks += 1;
            if self.idle_ticks == 30 && !self.pos_has_fix {
                self.error_string =
                    "Sin datos GPS. La aplicación solicitó permiso de ubicación al iniciarse.".into();
                self.error_changed();
            }
            return;
        }

        self.idle_ticks = 0;
        let count = unsafe { navius_count_in_view(src) };

        let mut ids        = QVariantList::default();
        let mut signals    = QVariantList::default();
        let mut azimuths   = QVariantList::default();
        let mut elevations = QVariantList::default();
        let mut in_use     = QVariantList::default();
        let mut systems    = QVariantList::default();
        let mut use_count  = 0i32;

        for i in 0..count {
            let mut d = SatDataC::default();
            unsafe { navius_get_sat(src, i, &mut d); }
            if d.in_use { use_count += 1; }
            ids.push(d.id.into());
            signals.push((d.signal as f64).into());
            azimuths.push((d.azimuth as f64).into());
            elevations.push((d.elevation as f64).into());
            in_use.push(d.in_use.into());
            systems.push(d.system.into());
        }

        self.sat_ids        = ids;
        self.sat_signals    = signals;
        self.sat_azimuths   = azimuths;
        self.sat_elevations = elevations;
        self.sat_in_use     = in_use;
        self.sat_systems    = systems;
        self.in_view_count  = count;
        self.in_use_count   = use_count;
        self.data_changed();
        self.counts_changed();
    }

    fn clear_data(&mut self) {
        self.sat_ids        = QVariantList::default();
        self.sat_signals    = QVariantList::default();
        self.sat_azimuths   = QVariantList::default();
        self.sat_elevations = QVariantList::default();
        self.sat_in_use     = QVariantList::default();
        self.sat_systems    = QVariantList::default();
        self.in_view_count  = 0;
        self.in_use_count   = 0;
        self.pos_has_fix    = false;
        self.data_changed();
        self.counts_changed();
        self.position_changed();
    }
}

// ---------------------------------------------------------------------------
// C callback – invoked from the QTimer lambda defined in navius_create_timer.
// ---------------------------------------------------------------------------
#[no_mangle]
pub unsafe extern "C" fn navius_sat_tick(model_ptr: usize, source_ptr: usize) {
    if model_ptr == 0 { return; }
    let model = &mut *(model_ptr as *mut SatelliteModel);
    model.refresh_from_source(source_ptr);
}

