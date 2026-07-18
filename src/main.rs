#![recursion_limit = "4096"]

/*
 * Copyright (C) 2026  Edi
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; version 3.
 *
 * navius is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

#[macro_use]
extern crate cstr;
#[macro_use]
extern crate qmetaobject;

use std::cell::RefCell;
use std::env;
use std::path::PathBuf;

use gettextrs::{bindtextdomain, textdomain};
use qmetaobject::*;
use cpp::cpp;

mod i18n_units;
mod nav_http;
mod nav_music;
mod nav_power;
mod nav_tile_cache;
mod nav_tracker;
mod nav_tts;
mod qrc;
mod satellite_model;

use i18n_units::{NavI18n, NavUnits};
use nav_http::NavHttp;
use nav_power::NavPower;
use nav_tile_cache::NavTileCache;
use nav_tracker::NavTracker;
use nav_tts::NavTts;
use satellite_model::SatelliteModel;

fn main() {
    // Allow QML XMLHttpRequest to read/write local file:// URLs (debug command file).
    env::set_var("QML_XHR_ALLOW_FILE_READ", "1");
    env::set_var("QML_XHR_ALLOW_FILE_WRITE", "1");
    env::set_var("QML_DISABLE_DISK_CACHE", "1");

    // URI geo: recibida al lanzar la app (p.ej. desde el "compartir ubicación"
    // de otra app, vía MimeType=x-scheme-handler/geo; del .desktop). Sustituye
    // al Content-Hub de Lomiri — ver Main.qml Component.onCompleted.
    let shared_uri = env::args().nth(1).unwrap_or_default();

    init_gettext();
    unsafe {
        cpp! { {
            #include <QtCore/QCoreApplication>
            #include <QtCore/QString>
        }}
        cpp! {[]{
            QCoreApplication::setOrganizationName(QStringLiteral("navius"));
            QCoreApplication::setOrganizationDomain(QStringLiteral("navius"));
            QCoreApplication::setApplicationName(QStringLiteral("navius"));
        }}
    }
    // Estilo QQC2 estándar del sistema (Suru era exclusivo del SDK Lomiri, no
    // existe en postmarketOS). Material viene siempre con qt5-qtquickcontrols2,
    // sin depender de ningún paquete extra.
    QQuickStyle::set_style("Material");
    qrc::load();

    qml_register_type::<SatelliteModel>(
        cstr!("Navius"),
        1, 0,
        cstr!("SatelliteModel"),
    );
    qml_register_type::<NavHttp>(
        cstr!("Navius"),
        1, 0,
        cstr!("NavHttp"),
    );
    qml_register_type::<NavTracker>(
        cstr!("Navius"),
        1, 0,
        cstr!("NavTracker"),
    );
    qml_register_type::<NavTts>(
        cstr!("Navius"),
        1, 0,
        cstr!("NavTts"),
    );
    qml_register_type::<NavTileCache>(
        cstr!("Navius"),
        1, 0,
        cstr!("NavTileCache"),
    );
    qml_register_type::<NavPower>(
        cstr!("Navius"),
        1, 0,
        cstr!("NavPower"),
    );

    let mut engine = QmlEngine::new();
    engine.set_property("appVersion".into(), QString::from(env!("CARGO_PKG_VERSION")).into());
    engine.set_property("sharedUri".into(), QString::from(shared_uri).into());

    // Directorio de datos del usuario (antes hardcodeado a /home/phablet/.../
    // navius.woodyst en el click package). El QML usa dataDirPath para rutas
    // de fichero planas y dataDirUri (con prefijo file://) para XMLHttpRequest
    // (ver "File-based debug command system" en Main.qml).
    let home = env::var("HOME").unwrap_or_else(|_| "/tmp".to_string());
    let data_dir_path  = format!("{home}/.local/share/navius");
    let data_dir_uri   = format!("file://{data_dir_path}");
    let cache_dir_path = format!("{home}/.cache/navius");
    engine.set_property("dataDirPath".into(),  QString::from(data_dir_path).into());
    engine.set_property("dataDirUri".into(),   QString::from(data_dir_uri).into());
    engine.set_property("cacheDirPath".into(), QString::from(cache_dir_path).into());

    // `units`/`i18n`: sustituyen a los objetos globales que Lomiri.Components
    // inyectaba en QML (ver src/i18n_units.rs). Se filtran (leak) para que
    // vivan el resto del proceso — QObjectPinned exige que el QObject no se
    // mueva en memoria mientras el motor QML lo tenga referenciado.
    let nav_units: &'static RefCell<NavUnits> = Box::leak(Box::new(RefCell::new(NavUnits::new())));
    let nav_i18n:  &'static RefCell<NavI18n>  = Box::leak(Box::new(RefCell::new(NavI18n::default())));
    engine.set_object_property("units".into(), unsafe { QObjectPinned::new(nav_units) });
    engine.set_object_property("i18n".into(),  unsafe { QObjectPinned::new(nav_i18n) });

    // El plugin QML MapboxMap ahora viene del paquete del sistema
    // mapbox-gl-qml (usr/lib/qt5/qml/MapboxMap), ya en el import path por
    // defecto de Qt — no hace falta añadir ningún directorio extra.
    engine.add_import_path("qrc:/qml".into());
    engine.load_file("qrc:/qml/Main.qml".into());
    engine.exec();
}

fn init_gettext() {
    let domain = "navius.woodyst";
    textdomain(domain).expect("Failed to set gettext domain");

    // Instalado como paquete apk normal: los .mo compilados van siempre a la
    // ruta estándar del sistema (a diferencia del click package de Ubuntu
    // Touch, donde el directorio de trabajo apuntaba al sandbox de la app).
    let path = PathBuf::from("/usr/share/locale");
    bindtextdomain(domain, path.to_str().unwrap()).expect("Failed to bind gettext domain");
}
