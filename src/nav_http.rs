use cpp::cpp;
use qmetaobject::*;

cpp! {{
    #include <QtCore/QUrl>
    #include <QtNetwork/QNetworkAccessManager>
    #include <QtNetwork/QNetworkRequest>
    #include <QtNetwork/QNetworkReply>

    extern "C" void navius_http_done(uintptr_t obj_ptr, int32_t req_id,
                                      const uint8_t* body_ptr, int32_t body_len,
                                      const uint8_t* err_ptr,  int32_t err_len);

    extern "C" void navius_http_post(uintptr_t obj_ptr,
                                      const uint8_t* url_ptr,  int32_t url_len,
                                      const uint8_t* data_ptr, int32_t data_len,
                                      const uint8_t* ua_ptr,   int32_t ua_len,
                                      int32_t req_id) {
        QString url  = QString::fromUtf8(reinterpret_cast<const char*>(url_ptr),  url_len);
        QByteArray body(reinterpret_cast<const char*>(data_ptr), data_len);
        QByteArray ua(reinterpret_cast<const char*>(ua_ptr), ua_len);

        auto *mgr = new QNetworkAccessManager();
        QUrl qurl(url);
        QNetworkRequest req(qurl);
        req.setHeader(QNetworkRequest::ContentTypeHeader,
                      QByteArray("application/x-www-form-urlencoded"));
        req.setRawHeader("User-Agent", ua.isEmpty() ? QByteArray("navius/1.0") : ua);

        QNetworkReply *reply = mgr->post(req, body);
        QObject::connect(reply, &QNetworkReply::finished,
                         [obj_ptr, req_id, reply, mgr]() {
            if (reply->error() == QNetworkReply::NoError) {
                QByteArray d = reply->readAll();
                navius_http_done(obj_ptr, req_id,
                    reinterpret_cast<const uint8_t*>(d.constData()), d.size(),
                    reinterpret_cast<const uint8_t*>(""), 0);
            } else {
                QByteArray e = reply->errorString().toUtf8();
                navius_http_done(obj_ptr, req_id,
                    reinterpret_cast<const uint8_t*>(""), 0,
                    reinterpret_cast<const uint8_t*>(e.constData()), e.size());
            }
            reply->deleteLater();
            mgr->deleteLater();
        });
    }
}}

extern "C" {
    fn navius_http_post(
        obj_ptr:  usize,
        url_ptr:  *const u8, url_len:  i32,
        data_ptr: *const u8, data_len: i32,
        ua_ptr:   *const u8, ua_len:   i32,
        req_id:   i32,
    );
}

#[derive(QObject, Default)]
pub struct NavHttp {
    base: qt_base_class!(trait QObject),

    pub done: qt_signal!(req_id: i32, body: QString, err: QString),

    // Biblioteca de música local (ver nav_music.rs). Content Hub copia al sandbox;
    // file:// desde ~/.local/share/<pkg>/Music funciona con media-hub.
    pub music_dir: qt_method!(fn music_dir(&mut self) -> QString {
        crate::nav_music::music_dir().to_string_lossy().into_owned().into()
    }),
    // JSON: [{"name":..,"path":..}] de la biblioteca (no sigue symlinks).
    pub music_list: qt_method!(fn music_list(&mut self) -> QString {
        crate::nav_music::list_tracks().into()
    }),
    // Importa ficheros recibidos por Content Hub (rutas separadas por '\n'). Devuelve cuántas.
    pub music_import: qt_method!(fn music_import(&mut self, urls: QString) -> i32 {
        crate::nav_music::import_tracks(&Into::<String>::into(urls))
    }),
    // Quita una pista de la biblioteca (symlink → solo el enlace).
    pub music_remove: qt_method!(fn music_remove(&mut self, name: QString) -> bool {
        crate::nav_music::remove_track(&Into::<String>::into(name))
    }),

    // QML: navHttp.post(url, formData, reqId)
    pub post: qt_method!(fn post(&mut self, url: QString, data: QString, req_id: i32) {
        let url_b:  Vec<u8> = Into::<String>::into(url).into_bytes();
        let data_b: Vec<u8> = Into::<String>::into(data).into_bytes();
        let ua_b   = b"navius/1.0";
        let self_ptr = self as *mut NavHttp as usize;
        unsafe {
            navius_http_post(
                self_ptr,
                url_b.as_ptr(),  url_b.len()  as i32,
                data_b.as_ptr(), data_b.len() as i32,
                ua_b.as_ptr(),   ua_b.len()   as i32,
                req_id,
            );
        }
    }),
}

#[no_mangle]
pub unsafe extern "C" fn navius_http_done(
    obj_ptr:  usize, req_id: i32,
    body_ptr: *const u8, body_len: i32,
    err_ptr:  *const u8, err_len:  i32,
) {
    if obj_ptr == 0 { return; }
    let obj  = &mut *(obj_ptr as *mut NavHttp);
    let body = std::str::from_utf8(std::slice::from_raw_parts(body_ptr, body_len as usize))
        .unwrap_or("").to_string();
    let err  = std::str::from_utf8(std::slice::from_raw_parts(err_ptr,  err_len  as usize))
        .unwrap_or("").to_string();
    obj.done(req_id, body.into(), err.into());
}
