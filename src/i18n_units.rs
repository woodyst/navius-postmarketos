use qmetaobject::*;
use gettextrs::gettext;
use cpp::cpp;
use std::env;

cpp! {{
    #include <QtGui/QGuiApplication>
    #include <QtGui/QScreen>
    #include <QtCore/QRect>
    #include <QtCore/QSettings>
}}

/// Referencia de Ubuntu Touch: en el dispositivo donde se diseñó la UI
/// (teléfono de referencia, 1080×2400) Lomiri arrancaba la app con `GRID_UNIT_PX=12` y
/// `devicePixelRatio=1` (comprobado en los logs: "Using TextureNode for map
/// rendering. devicePixelRatio: 1"), o sea 1080/12 = **90 grid units de ancho**
/// en vertical.
const UT_GU_ACROSS_PORTRAIT: f64 = 90.0;

/// Ajuste sobre la referencia de UT, medido en el dispositivo: con Phosh al
/// 300 % (dpr=3) la escala exacta de UT se queda pequeña, y el tamaño que se dio
/// por bueno es **1.7× la de UT** — 1 gu = 6.8 px lógicos = 20.4 px físicos,
/// unos 53 gu de ancho de pantalla. Ese es el 100 % de "Escala de interfaz";
/// el slider de Preferencias ajusta a partir de aquí.
const UI_SCALE_OVER_UT: f64 = 1.7;

/// Grid units a lo ancho (en vertical) que se buscan al calcular el tamaño de
/// 1 gu: ≈ 52.94.
const GU_ACROSS_PORTRAIT: f64 = UT_GU_ACROSS_PORTRAIT / UI_SCALE_OVER_UT;

/// Valor de emergencia si no hay QScreen (no debería pasar con la QApplication
/// ya creada por QmlEngine::new()).
const FALLBACK_GRID_UNIT_PX: f64 = 8.0;

/// Sustituye el objeto global `units` que Lomiri.Components inyectaba en QML.
/// Expuesto como context property raíz `units` (ver main.rs), igual que
/// `appVersion`, para que los ~2500 usos existentes de `units.gu(N)` en el
/// QML no cambien ni una línea.
#[derive(QObject, Default)]
pub struct NavUnits {
    base: qt_base_class!(trait QObject),
    /// Tamaño real de 1 gu en píxeles lógicos. Expuesto solo como información
    /// para la UI (Preferencias): es CONST porque cambiarlo en caliente no
    /// re-evaluaría los bindings que llaman a gu() — hace falta reiniciar.
    pub grid_unit_px: qt_property!(f64; CONST),
    pub gu: qt_method!(fn gu(&self, n: f64) -> f64 {
        n * self.grid_unit_px
    }),
}

impl NavUnits {
    pub fn new() -> Self {
        // Geometría de la pantalla en píxeles LÓGICOS: Qt ya divide por el
        // devicePixelRatio que le da el compositor (en Phosh al 300 % → dpr=3,
        // 1080×2400 físicos → 360×800 lógicos).
        let (screen_w, screen_h, dpr) = screen_metrics();

        // Base automática: nº fijo de grid units a lo ancho, derivado de la
        // referencia de Ubuntu Touch (ver constantes arriba). Antes era una
        // constante de 8 px pensada para dpr=1, que con el escalado de Phosh
        // daba 24 px físicos por gu.
        let auto = if screen_w > 0.0 && screen_h > 0.0 {
            screen_w.min(screen_h) / GU_ACROSS_PORTRAIT
        } else {
            FALLBACK_GRID_UNIT_PX
        };

        // GRID_UNIT_PX permite forzarlo igual que en Ubuntu Touch (ahora
        // admite decimales, p.ej. GRID_UNIT_PX=4.5), útil para probar valores
        // en el dispositivo sin recompilar.
        let base = env::var("GRID_UNIT_PX")
            .ok()
            .and_then(|v| v.parse::<f64>().ok())
            .filter(|v| *v > 0.0)
            .unwrap_or(auto);

        // Ajuste fino del usuario (Preferencias → Escala de interfaz), guardado
        // en el mismo navius.conf que usa Qt.labs.settings en Main.qml.
        // (un valor ausente o ilegible en el .conf da 0.0 → se ignora)
        let raw_scale = read_ui_scale();
        let ui_scale = if raw_scale >= 0.1 { raw_scale.clamp(0.5, 2.5) } else { 1.0 };

        let grid = (base * ui_scale).clamp(2.0, 40.0);
        eprintln!(
            "[navius] units: screen={}x{} logical dpr={} auto_gu={:.2} base={:.2} uiScale={:.2} -> gridUnit={:.2}px",
            screen_w, screen_h, dpr, auto, base, ui_scale, grid
        );

        NavUnits { grid_unit_px: grid, ..Default::default() }
    }
}

/// (ancho, alto, devicePixelRatio) de la pantalla primaria en píxeles lógicos.
fn screen_metrics() -> (f64, f64, f64) {
    unsafe {
        let w = cpp!([] -> f64 as "double" {
            QScreen *s = QGuiApplication::primaryScreen();
            return s ? double(s->geometry().width()) : 0.0;
        });
        let h = cpp!([] -> f64 as "double" {
            QScreen *s = QGuiApplication::primaryScreen();
            return s ? double(s->geometry().height()) : 0.0;
        });
        let dpr = cpp!([] -> f64 as "double" {
            QScreen *s = QGuiApplication::primaryScreen();
            return s ? double(s->devicePixelRatio()) : 1.0;
        });
        (w, h, dpr)
    }
}

/// Lee `uiScale` de ~/.config/navius/navius.conf (grupo [General]), que es
/// donde escribe el `Settings {}` sin category de Main.qml.
fn read_ui_scale() -> f64 {
    unsafe {
        cpp!([] -> f64 as "double" {
            QSettings s;
            return s.value(QStringLiteral("uiScale"), 1.0).toDouble();
        })
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
