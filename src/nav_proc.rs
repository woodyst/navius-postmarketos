use qmetaobject::*;
use std::io::{BufRead, BufReader};
use std::path::PathBuf;
use std::process::{Child, Command, Stdio};
use std::sync::{Arc, Mutex};

// Búsqueda en Google Maps para postmarketOS.
//
// En Ubuntu Touch el panel GoogleMapsPanel.qml embebe un WebEngineView (Qt5)
// dentro de la propia app. En Alpine/postmarketOS no existe QtWebEngine para
// Qt5 (solo qt6-qtwebengine), así que el visor va en un PROCESO APARTE: el
// fichero QML de Qt6 `navius-gmaps.qml` ejecutado con el `qmlscene` de Qt6
// (paquete qt6-qtdeclarative; qt6-qtwebengine aporta el módulo QtWebEngine).
// Phosh pone la ventana nueva encima de Navius y vuelve a Navius al cerrarse.
//
// Canal de vuelta: el visor escribe por stderr (console.log) una línea
//   NAVIUS_SEL<TAB>lat<TAB>lon<TAB>nombre
// al pulsar "Usar este destino", y termina. Un hilo lee esa salida y el QML de
// Navius hace polling con gmaps_poll() cada 400 ms mientras el visor vive.
//
// Parámetros hacia el visor (textos traducidos, UA, ruta de caché): qmlscene
// no admite argumentos propios, así que se genera una copia del QML en la
// caché con el marcador /*@ARGS@*/ sustituido por el JSON, y se ejecuta esa.

const QMLSCENE_DEFAULT: &str = "/usr/lib/qt6/bin/qmlscene";
const HELPER_QML_DEFAULT: &str = "/usr/share/navius/navius-gmaps.qml";

fn qmlscene_path() -> PathBuf {
    std::env::var("NAVIUS_QMLSCENE").map(PathBuf::from)
        .unwrap_or_else(|_| PathBuf::from(QMLSCENE_DEFAULT))
}

fn helper_qml_path() -> PathBuf {
    std::env::var("NAVIUS_GMAPS_QML").map(PathBuf::from)
        .unwrap_or_else(|_| PathBuf::from(HELPER_QML_DEFAULT))
}

// ~/.cache/navius/gmaps — perfil persistente de WebEngine (cookies, caché
// HTTP) y el QML generado. Lo que borra "Limpiar caché Google Maps".
fn gmaps_cache_dir() -> PathBuf {
    let base = std::env::var("XDG_CACHE_HOME").ok()
        .filter(|s| !s.is_empty())
        .map(PathBuf::from)
        .unwrap_or_else(|| {
            let home = std::env::var("HOME").unwrap_or_else(|_| "/tmp".to_string());
            PathBuf::from(home).join(".cache")
        });
    base.join("navius").join("gmaps")
}

#[derive(Default)]
struct ProcState {
    child:  Option<Child>,
    result: Option<String>,
}

#[derive(QObject, Default)]
pub struct NavProc {
    base: qt_base_class!(trait QObject),

    state: Arc<Mutex<ProcState>>,

    // QML: navProc.gmaps_available() — hay qmlscene de Qt6 y el QML del visor.
    pub gmaps_available: qt_method!(fn gmaps_available(&mut self) -> bool {
        qmlscene_path().is_file() && helper_qml_path().is_file()
    }),

    // QML: navProc.gmaps_cache_dir() — ruta del perfil WebEngine del visor.
    pub gmaps_cache_dir: qt_method!(fn gmaps_cache_dir(&mut self) -> QString {
        gmaps_cache_dir().to_string_lossy().into_owned().into()
    }),

    // QML: navProc.gmaps_start(argsJson) → true si el proceso arrancó.
    // argsJson se incrusta tal cual en el QML del visor (objeto JS).
    pub gmaps_start: qt_method!(fn gmaps_start(&mut self, args_json: QString) -> bool {
        let args: String = args_json.into();
        self.start_helper(&args)
    }),

    // QML: navProc.gmaps_running()
    pub gmaps_running: qt_method!(fn gmaps_running(&mut self) -> bool {
        let mut st = self.state.lock().unwrap();
        match st.child.as_mut() {
            Some(c) => match c.try_wait() { Ok(Some(_)) => false, Ok(None) => true, Err(_) => false },
            None => false,
        }
    }),

    // QML: navProc.gmaps_poll() → "" mientras corre sin resultado,
    // "lat\tlon\tnombre" cuando el usuario eligió destino, "EXIT" si el
    // visor se cerró sin elegir nada. El resultado se entrega una sola vez.
    pub gmaps_poll: qt_method!(fn gmaps_poll(&mut self) -> QString {
        let mut st = self.state.lock().unwrap();
        if let Some(r) = st.result.take() {
            // El visor ya se cierra solo (Qt.quit) tras imprimir; por si
            // acaso, recoger el proceso.
            if let Some(mut c) = st.child.take() { let _ = c.try_wait(); }
            return QString::from(r);
        }
        let exited = match st.child.as_mut() {
            Some(c) => match c.try_wait() { Ok(Some(_)) | Err(_) => true, Ok(None) => false },
            None => true,
        };
        if exited {
            st.child = None;
            return QString::from("EXIT");
        }
        QString::from("")
    }),

    // QML: navProc.gmaps_stop() — cierra el visor si sigue abierto.
    pub gmaps_stop: qt_method!(fn gmaps_stop(&mut self) {
        let mut st = self.state.lock().unwrap();
        if let Some(mut c) = st.child.take() {
            let _ = c.kill();
            let _ = c.wait();
        }
        st.result = None;
    }),

    // QML: navProc.gmaps_clear_cache() — borra ~/.cache/navius/gmaps entero
    // (perfil WebEngine + QML generado). Solo si el visor no está abierto.
    pub gmaps_clear_cache: qt_method!(fn gmaps_clear_cache(&mut self) -> bool {
        {
            let mut st = self.state.lock().unwrap();
            if let Some(mut c) = st.child.take() { let _ = c.kill(); let _ = c.wait(); }
            st.result = None;
        }
        let dir = gmaps_cache_dir();
        if !dir.exists() { return true; }
        std::fs::remove_dir_all(&dir).is_ok()
    }),
}

impl NavProc {
    fn start_helper(&mut self, args_json: &str) -> bool {
        // Una instancia a la vez: si sigue viva, no abrir otra.
        {
            let mut st = self.state.lock().unwrap();
            if let Some(c) = st.child.as_mut() {
                if let Ok(None) = c.try_wait() { return true; }
            }
            st.child = None;
            st.result = None;
        }

        let template = match std::fs::read_to_string(helper_qml_path()) {
            Ok(t) => t,
            Err(e) => { eprintln!("[navius] gmaps: no se puede leer el QML del visor: {e}"); return false; }
        };
        let dir = gmaps_cache_dir();
        if let Err(e) = std::fs::create_dir_all(&dir) {
            eprintln!("[navius] gmaps: no se puede crear {}: {e}", dir.display());
            return false;
        }
        let args = if args_json.trim().is_empty() { "{}" } else { args_json };
        let generated = template.replace("/*@ARGS@*/ ({})", &format!("({args})"));
        let qml_path = dir.join("navius-gmaps.generated.qml");
        if let Err(e) = std::fs::write(&qml_path, generated) {
            eprintln!("[navius] gmaps: no se puede escribir {}: {e}", qml_path.display());
            return false;
        }

        let mut cmd = Command::new(qmlscene_path());
        cmd.arg(&qml_path)
            // qmlscene es de Qt6: que no herede ajustes del Qt5 de Navius.
            .env("QT_QPA_PLATFORM", "wayland")
            .env("QT_QUICK_CONTROLS_STYLE", "Material")
            .env("QT_QUICK_CONTROLS_MATERIAL_THEME", "Dark")
            .env_remove("QT_PLUGIN_PATH")
            .env_remove("QML2_IMPORT_PATH")
            .env_remove("QML_IMPORT_PATH")
            .env_remove("QML_DISABLE_DISK_CACHE")
            .stdin(Stdio::null())
            .stdout(Stdio::null())
            .stderr(Stdio::piped());
        let mut child = match cmd.spawn() {
            Ok(c) => c,
            Err(e) => { eprintln!("[navius] gmaps: no se puede lanzar qmlscene: {e}"); return false; }
        };
        let stderr = child.stderr.take();
        {
            let mut st = self.state.lock().unwrap();
            st.child = Some(child);
        }
        if let Some(err) = stderr {
            let state = Arc::clone(&self.state);
            std::thread::spawn(move || {
                let reader = BufReader::new(err);
                for line in reader.lines() {
                    let line = match line { Ok(l) => l, Err(_) => break };
                    // qmlscene antepone "qml: " a los console.log
                    let l = line.trim_start_matches("qml: ");
                    if let Some(rest) = l.strip_prefix("NAVIUS_SEL\t") {
                        let mut st = state.lock().unwrap();
                        st.result = Some(rest.to_string());
                    }
                }
            });
        }
        true
    }
}
