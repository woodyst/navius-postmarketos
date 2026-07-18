/* Copyright (C) 2018 Olivier Goffart <ogoffart@woboq.com>
Permission is hereby granted, free of charge, to any person obtaining a copy of this software and
associated documentation files (the "Software"), to deal in the Software without restriction,
including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense,
and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so,
subject to the following conditions:
The above copyright notice and this permission notice shall be included in all copies or substantial
portions of the Software.
THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT
NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES
OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
*/
use std::env;
use std::fs;
use std::path::PathBuf;
use std::process::Command;

fn qmake_query(qmake: &str, args: &str, var: &str) -> String {
    let mut qmake_cmd_list: Vec<&str> = qmake.split(' ').collect();
    qmake_cmd_list.push("-query");
    qmake_cmd_list.push(var);

    if !args.is_empty() {
        qmake_cmd_list.append(&mut args.split(' ').collect());
    }

    String::from_utf8(
        Command::new(qmake_cmd_list[0])
            .args(&qmake_cmd_list[1..])
            .output()
            .expect("Failed to execute qmake. Make sure 'qmake' is in your path")
            .stdout,
    )
    .expect("UTF-8 conversion failed")
}

fn qmake_call() -> String {
    env::var("QMAKE").unwrap_or(String::from("qmake"))
}

fn qmake_args() -> String {
    env::var("QMAKE_ARGS").unwrap_or_default()
}

fn update_language_files() {
    let pot_file = "po/navius.woodyst.pot";
    let source_files = source_files();

    let mut child = Command::new("xgettext")
        .args([
            &format!("--output={}", pot_file),
            "--language=javascript",
            "--qt",
            "--keyword=tr",
            "--keyword=tr:1,2",
            "--add-comments=i18n",
            "--from-code=UTF-8",
        ])
        .args(&source_files)
        .spawn()
        .unwrap();

    let exit_status = child.wait().unwrap();
    assert!(exit_status.code() == Some(0));

    for po_file in po_files() {
        let po_file_name = po_file
            .to_str()
            .expect("po language file name contains invalid characters");

        let mut child = Command::new("msgmerge")
            .args(["--update", po_file_name, pot_file])
            .spawn()
            .unwrap();

        let exit_status = child.wait().unwrap();
        assert!(exit_status.code() == Some(0));

        // El APKBUILD (Fase 6) exporta INSTALL_DIR=$pkgdir/usr para el build de
        // empaquetado; en un `cargo build`/`cargo check` normal (desarrollo local)
        // no está definida, así que usamos OUT_DIR (siempre presente) como default.
        let install_dir = env::var("INSTALL_DIR").unwrap_or_else(|_| env::var("OUT_DIR").unwrap());
        let lang = po_file.file_stem().unwrap().to_str().unwrap();
        let mo_dir = format!("{install_dir}/share/locale/{lang}/LC_MESSAGES");
        let mo_file = format!("{}/navius.woodyst.mo", mo_dir);

        fs::create_dir_all(&mo_dir)
            .expect("Failed to create directory for compiled language files");

        let mut child = Command::new("msgfmt")
            .args([po_file_name, "-o", &mo_file])
            .spawn()
            .unwrap();

        let exit_status = child.wait().unwrap();
        assert!(exit_status.code() == Some(0));
    }
}

fn source_files() -> Vec<PathBuf> {
    walk_dir(PathBuf::from("qml"), "qml")
}

fn po_files() -> Vec<PathBuf> {
    walk_dir(PathBuf::from("po"), "po")
}

fn walk_dir(dir: PathBuf, ext: &str) -> Vec<PathBuf> {
    let mut files: Vec<PathBuf> = Vec::new();

    for entry in fs::read_dir(dir)
        .expect("Failed to iterate over directory")
        .filter_map(Result::ok)
    {
        if entry.file_type().unwrap().is_dir() {
            files.append(&mut walk_dir(entry.path(), ext));
        } else if let Some(file_ext) = entry.path().extension() {
            if file_ext.to_str().unwrap() == ext {
                files.push(entry.path())
            }
        }
    }

    files
}

fn find_moc(qt_bin_path: &str) -> String {
    let candidates = [
        format!("{}/moc", qt_bin_path.trim()),
        "/usr/lib/qt5/bin/moc".to_string(),
        "/usr/lib/x86_64-linux-gnu/qt5/bin/moc".to_string(),
        "moc-qt5".to_string(),
        "moc".to_string(),
    ];
    for c in &candidates {
        if Command::new(c).arg("--version").output().is_ok() {
            return c.clone();
        }
    }
    panic!("Could not find moc. Install qtbase5-dev or set QT_INSTALL_BINS.");
}

fn main() {
    // Rerun build.rs when any C++ header or source changes.
    println!("cargo:rerun-if-changed=src/main.rs");
    println!("cargo:rerun-if-changed=src/nav_tts.rs");
    println!("cargo:rerun-if-changed=src/satellite_source.h");
    println!("cargo:rerun-if-changed=src/nmea_sat_source.h");
    println!("cargo:rerun-if-changed=src/location_props.h");
    println!("cargo:rerun-if-changed=src/location_props.cpp");

    update_language_files();

    let qmake_cmd = qmake_call();
    let args = qmake_args();

    let qt_include_path = qmake_query(&qmake_cmd, &args, "QT_INSTALL_HEADERS");
    let qt_library_path = qmake_query(&qmake_cmd, &args, "QT_INSTALL_LIBS");
    let qt_bin_path     = qmake_query(&qmake_cmd, &args, "QT_INSTALL_BINS");

    // Generate moc output for LocationPropsWatcher.
    let moc = find_moc(&qt_bin_path);
    let moc_out = "src/moc_location_props.cpp";
    let status = Command::new(&moc)
        .args(["-I", qt_include_path.trim(), "src/location_props.h", "-o", moc_out])
        .status()
        .expect("Failed to run moc");
    assert!(status.success(), "moc failed");

    // cpp_build must be linked BEFORE location_props so the references in
    // librust_cpp_generated.a are resolved when liblocaton_props.a is scanned.
    cpp_build::Config::new()
        .include(qt_include_path.trim())
        .include("src")          // so #include "satellite_source.h" resolves
        .flag("-std=c++14")
        .flag("-Wno-deprecated-copy")
        .flag("-Wno-unused-result")
        .build("src/main.rs");

    // Compile LocationPropsWatcher (needs MOC) separately via cc crate.
    // Must come AFTER cpp_build so location_props ends up later in the link order.
    cc::Build::new()
        .file("src/location_props.cpp")
        .file(moc_out)
        .include(qt_include_path.trim())
        .include("src")
        .flag("-std=c++14")
        .flag("-Wno-deprecated-copy")
        .compile("location_props");

    cc::Build::new()
        .file("src/nav_power.cpp")
        .include(qt_include_path.trim())
        .flag("-std=c++14")
        .flag("-Wno-deprecated-copy")
        .compile("nav_power");

    let macos_lib_search = if cfg!(target_os = "macos") { "=framework" } else { "" };
    let lib_framework    = if cfg!(target_os = "macos") { ""           } else { "5" };
    let qt_library_path  = qt_library_path.trim();

    println!("cargo:rustc-link-search{macos_lib_search}={qt_library_path}");
    println!("cargo:rustc-link-lib{macos_lib_search}=Qt{lib_framework}Widgets");
    println!("cargo:rustc-link-lib{macos_lib_search}=Qt{lib_framework}Gui");
    println!("cargo:rustc-link-lib{macos_lib_search}=Qt{lib_framework}Core");
    println!("cargo:rustc-link-lib{macos_lib_search}=Qt{lib_framework}Quick");
    println!("cargo:rustc-link-lib{macos_lib_search}=Qt{lib_framework}Qml");
    println!("cargo:rustc-link-lib{macos_lib_search}=Qt{lib_framework}QuickControls2");
    println!("cargo:rustc-link-lib{macos_lib_search}=Qt{lib_framework}Positioning");
    println!("cargo:rustc-link-lib{macos_lib_search}=Qt{lib_framework}Network");
    println!("cargo:rustc-link-lib{macos_lib_search}=Qt{lib_framework}DBus");

    // dlopen/dlsym viven directamente en libc en musl (a diferencia de
    // glibc, que los separa en libdl.so) — enlazar -ldl explícitamente
    // en postmarketOS genera una entrada NEEDED "libdl.so.2" que no
    // corresponde a ningún paquete real y rompe el empaquetado con
    // abuild ("libdl.so.2: path not found" al trazar dependencias).
    if !cfg!(target_env = "musl") {
        println!("cargo:rustc-link-lib=dl");
    }
}
