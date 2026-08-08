use qmetaobject::*;

// Implementadas en src/nav_power.cpp sobre org.freedesktop.ScreenSaver.
// El cookie es el uint32 que devuelve Inhibit(); 0 = no hay inhibición activa,
// y es también lo que devuelve keep_on() si algo falla.
extern "C" {
    fn navius_power_keep_on() -> u32;
    fn navius_power_release(cookie: u32);
}

#[derive(QObject, Default)]
pub struct NavPower {
    base:    qt_base_class!(trait QObject),
    inhibit: qt_property!(bool; WRITE set_inhibit),
    // 0 = sin inhibición. Antes era un i32 con -1 como centinela, pero Default
    // lo dejaba en 0, así que la primera activación no llegaba a pedir nada:
    // solo funcionaba si el binding pasaba por false antes de ponerse a true.
    _cookie: u32,
}

impl NavPower {
    fn set_inhibit(&mut self, value: bool) {
        if value && self._cookie == 0 {
            self._cookie = unsafe { navius_power_keep_on() };
            eprintln!("[navius] power: inhibir pantalla -> cookie={}", self._cookie);
        } else if !value && self._cookie != 0 {
            unsafe { navius_power_release(self._cookie) };
            eprintln!("[navius] power: liberar pantalla (cookie={})", self._cookie);
            self._cookie = 0;
        }
    }
}
