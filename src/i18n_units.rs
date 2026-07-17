use qmetaobject::*;
use gettextrs::gettext;
use std::env;

/// Sustituye el objeto global `units` que Lomiri.Components inyectaba en QML.
/// Expuesto como context property raíz `units` (ver main.rs), igual que
/// `appVersion`, para que los ~2500 usos existentes de `units.gu(N)` en el
/// QML no cambien ni una línea.
#[derive(QObject, Default)]
pub struct NavUnits {
    base: qt_base_class!(trait QObject),
    grid_unit_px: i32,
    pub gu: qt_method!(fn gu(&self, n: f64) -> f64 {
        n * (self.grid_unit_px as f64)
    }),
}

impl NavUnits {
    pub fn new() -> Self {
        // Mismo mecanismo que usaba Ubuntu Touch para escalar la UI según
        // densidad de pantalla; si no está definida, 8px es el valor de
        // referencia con el que se diseñaron los layouts originales.
        let grid_unit_px = env::var("GRID_UNIT_PX")
            .ok()
            .and_then(|v| v.parse::<i32>().ok())
            .unwrap_or(8);
        NavUnits { grid_unit_px, ..Default::default() }
    }
}

/// Sustituye el objeto global `i18n` que Lomiri.Components inyectaba en QML.
/// Envuelve gettext (mismo dominio/textdomain que ya configura
/// `init_gettext()` en main.rs) para que `i18n.tr(...)` siga funcionando en
/// los 31 ficheros QML que lo usan, sin tocarlos.
#[derive(QObject, Default)]
pub struct NavI18n {
    base: qt_base_class!(trait QObject),
    pub tr: qt_method!(fn tr(&self, source_text: QString) -> QString {
        QString::from(gettext(source_text.to_string()))
    }),
}
