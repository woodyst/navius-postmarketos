// Biblioteca de música local de Navius.
//
// NOTA (postmarketOS): en Ubuntu Touch, media-hub + AppArmor obligaban a copiar o
// symlinkar los ficheros importados dentro del directorio propio de la app
// (~/.local/share/navius/Music/), porque el reproductor del sistema tenía un
// allowlist que rechazaba leer directamente desde ~/Music. postmarketOS reproduce
// audio vía QtMultimedia/PulseAudio sin esa restricción, así que la copia/symlink ya
// no es estrictamente necesaria — se conserva de todas formas por simplicidad (una
// única carpeta de biblioteca, independientemente de dónde estén los ficheros
// originales) y para minimizar el cambio de comportamiento en este port.
//
// list_tracks() sigue usando read_dir SIN seguir symlinks (lstat vía el file_type
// del DirEntry) — detalle heredado, sigue siendo válido: lista la entrada sin
// resolver el symlink.

use std::fs;
use std::os::unix::fs as unix_fs;
use std::path::{Path, PathBuf};

const AUDIO_EXTS: &[&str] = &[
    "mp3", "ogg", "oga", "flac", "m4a", "opus", "wav", "aac", "wma",
];

/// Directorio de biblioteca de música. Lo crea si no existe.
pub fn music_dir() -> PathBuf {
    let data_home = std::env::var("XDG_DATA_HOME").unwrap_or_else(|_| {
        let home = std::env::var("HOME").unwrap_or_else(|_| "/tmp".to_string());
        format!("{}/.local/share", home)
    });
    let dir = PathBuf::from(data_home).join("navius").join("Music");
    let _ = fs::create_dir_all(&dir);
    dir
}

fn is_audio(name: &str) -> bool {
    match Path::new(name).extension().and_then(|e| e.to_str()) {
        Some(ext) => {
            let ext = ext.to_ascii_lowercase();
            AUDIO_EXTS.iter().any(|e| *e == ext)
        }
        None => false,
    }
}

fn json_escape(s: &str) -> String {
    let mut out = String::with_capacity(s.len() + 2);
    for c in s.chars() {
        match c {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            c if (c as u32) < 0x20 => out.push_str(&format!("\\u{:04x}", c as u32)),
            c => out.push(c),
        }
    }
    out
}

/// Lista las pistas de la biblioteca como JSON: [{"name":..,"path":..}].
/// Usa read_dir + file_type() (lstat) para NO seguir symlinks: así un symlink a
/// ~/Music se lista sin que el proceso de Navius intente leer el destino real.
pub fn list_tracks() -> String {
    let dir = music_dir();
    let mut tracks: Vec<(String, String)> = Vec::new();

    if let Ok(entries) = fs::read_dir(&dir) {
        for entry in entries.flatten() {
            let ft = match entry.file_type() {
                Ok(ft) => ft,
                Err(_) => continue,
            };
            // Ficheros normales o symlinks (no seguimos el symlink). Saltamos
            // directorios reales (no recursamos en la biblioteca plana).
            if ft.is_dir() {
                continue;
            }
            let name = entry.file_name().to_string_lossy().into_owned();
            if name.starts_with('.') || !is_audio(&name) {
                continue;
            }
            let path = entry.path().to_string_lossy().into_owned();
            tracks.push((name, path));
        }
    }

    tracks.sort_by(|a, b| a.0.to_lowercase().cmp(&b.0.to_lowercase()));

    let mut json = String::from("[");
    for (i, (name, path)) in tracks.iter().enumerate() {
        if i > 0 {
            json.push(',');
        }
        json.push_str(&format!(
            "{{\"name\":\"{}\",\"path\":\"{}\"}}",
            json_escape(name),
            json_escape(path)
        ));
    }
    json.push(']');
    json
}

/// Directorio HubIncoming de nuestra app (ficheros temporales de Content Hub).
fn hub_incoming_dir() -> PathBuf {
    let cache_home = std::env::var("XDG_CACHE_HOME").unwrap_or_else(|_| {
        let home = std::env::var("HOME").unwrap_or_else(|_| "/tmp".to_string());
        format!("{}/.cache", home)
    });
    PathBuf::from(cache_home).join("navius").join("HubIncoming")
}

/// Importa ficheros recibidos por Content Hub.
/// Si el fichero viene de HubIncoming (temporal) → copia al sandbox.
/// Si viene de otra ubicación (p.ej. ~/Music) → crea symlink en el sandbox,
///   ya que crear un symlink no requiere leer el fichero origen.
/// Devuelve cuántos ficheros se importaron correctamente.
pub fn import_tracks(urls: &str) -> i32 {
    let dir = music_dir();
    let hub = hub_incoming_dir();
    eprintln!("[navius music] import_tracks dir={:?} hub={:?}", dir, hub);
    let mut count = 0;
    for raw in urls.split('\n') {
        let raw = raw.trim();
        if raw.is_empty() {
            continue;
        }
        let src = PathBuf::from(raw.strip_prefix("file://").unwrap_or(raw));
        eprintln!("[navius music] import src={:?}", src);
        let fname = match src.file_name() {
            Some(f) => f.to_owned(),
            None => continue,
        };
        if !is_audio(&fname.to_string_lossy()) {
            eprintln!("[navius music] skip non-audio {:?}", fname);
            continue;
        }
        let dest = dir.join(&fname);
        // Si ya existe (symlink o fichero), no duplicar.
        if dest.exists() || dest.symlink_metadata().is_ok() {
            eprintln!("[navius music] already exists {:?}", fname);
            count += 1;
            continue;
        }
        let ok = if src.starts_with(&hub) {
            // Fichero en HubIncoming: Content Hub puede haber usado un symlink al
            // fichero real en lugar de copiarlo. Si es así, creamos nuestro propio
            // symlink al destino real para no duplicar almacenamiento.
            if let Ok(real) = fs::read_link(&src) {
                eprintln!("[navius music] hub is symlink {:?} -> {:?}", src, real);
                match unix_fs::symlink(&real, &dest) {
                    Ok(_) => { eprintln!("[navius music] symlinked via hub {:?} -> {:?}", dest, real); true }
                    Err(e) => { eprintln!("[navius music] symlink error {:?}: {}", fname, e); false }
                }
            } else {
                match fs::copy(&src, &dest) {
                    Ok(_) => { eprintln!("[navius music] copied {:?}", fname); true }
                    Err(e) => { eprintln!("[navius music] copy error {:?}: {}", fname, e); false }
                }
            }
        } else {
            // Fichero externo → symlink (no necesita leer el origen).
            match unix_fs::symlink(&src, &dest) {
                Ok(_) => { eprintln!("[navius music] symlinked {:?} -> {:?}", dest, src); true }
                Err(e) => { eprintln!("[navius music] symlink error {:?}: {}", fname, e); false }
            }
        };
        if ok { count += 1; }
    }
    eprintln!("[navius music] import_tracks done count={}", count);
    count
}

/// Quita una pista de la biblioteca. Para un symlink borra solo el enlace
/// (remove_file usa unlink, no toca el fichero real en ~/Music).
pub fn remove_track(name: &str) -> bool {
    // Evitar path traversal: solo el nombre base.
    let base = Path::new(name)
        .file_name()
        .map(|f| f.to_owned())
        .unwrap_or_default();
    if base.is_empty() {
        return false;
    }
    let target = music_dir().join(base);
    fs::remove_file(&target).is_ok()
}
