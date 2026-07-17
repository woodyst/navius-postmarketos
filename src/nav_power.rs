use qmetaobject::*;

extern "C" {
    fn navius_power_keep_on() -> i32;
    fn navius_power_release(cookie: i32);
}

#[derive(QObject, Default)]
pub struct NavPower {
    base:    qt_base_class!(trait QObject),
    inhibit: qt_property!(bool; WRITE set_inhibit),
    _cookie: i32,
}

impl NavPower {
    fn set_inhibit(&mut self, value: bool) {
        if value && self._cookie < 0 {
            self._cookie = unsafe { navius_power_keep_on() };
        } else if !value && self._cookie >= 0 {
            unsafe { navius_power_release(self._cookie) };
            self._cookie = -1;
        }
    }
}
