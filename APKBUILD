# Maintainer: Eduardo García-Mádico Portabella <woodyst@gmail.com>
pkgname=navius
pkgver=1.0.10
pkgrel=0
pkgdesc="GPS navigator (offline, OSM-based)"
url="https://github.com/woodyst/navius"
arch="aarch64"
license="GPL-3.0-or-later"
depends="
	qt5-qtbase
	qt5-qtdeclarative
	qt5-qtquickcontrols2
	qt5-qtlocation
	qt5-qtsvg
	qt5-qtmultimedia
	qt5-qtsensors
	qt5-qtwayland
	mapbox-gl-qml
	espeak-ng
	piper
	sqlite-libs
	gettext
	geoclue
	"
# "piper" aquí es nuestro aport propio (pmaports/temp/piper, Fase 8): el
# paquete "piper" que trae Alpine por defecto es libratbag/Piper (GUI de
# ratones gaming, sin relación) y queda reemplazado al instalar el nuestro
# (rhasspy/piper compilado nativo musl contra onnxruntime/espeak-ng/fmt/
# spdlog del sistema — ya no gcompat ni binario glibc vendorizado).
makedepends="
	cargo
	rust
	qt5-qtbase-dev
	qt5-qtdeclarative-dev
	qt5-qtlocation-dev
	qt5-qtquickcontrols2-dev
	gettext
	autoconf
	automake
	libtool
	pcre2-dev
	popt-dev
	"
# gettext (no gettext-tiny) para xgettext/msgmerge/msgfmt en build.rs — ambos
# paquetes proveen los mismos comandos y se pisan entre sí, apk no deja tener
# los dos a la vez.
# !tracedeps ya NO hace falta (Fase 8): piper es ahora un binario musl nativo
# normal, sin entradas NEEDED glibc que el rastreador de abuild no entienda.
options="!check net"
# abuild SIEMPRE limpia $srcdir antes de build() (parte normal de su ciclo de
# vida, no un bug) — su default es "$startdir/src", que colisiona con nuestro
# propio directorio src/ (fuentes Rust) y lo borra por completo (ocurrió una
# vez, recuperado de git). Apuntar srcdir a un directorio dedicado que no se
# usa para nada (no hay "source=" que extraer aquí) evita la colisión.
# ¡OJO! NO poner srcdir="$startdir" ni nada que coincida con builddir: la
# limpieza automática de srcdir borraría el repo entero (pasó una segunda
# vez con esa configuración, también recuperado de git).
srcdir="$startdir/.abuild-srcdir"
builddir="$startdir"

# extras/mimic/ (~320MB, fuente de Mimic1 sin _build/voices) NO va en git por
# tamaño — debe sincronizarse antes de compilar (ver README.md del repo).
# piper ya no se vendoriza (Fase 8): es el paquete "piper" propio (depends=).

build() {
	# ── Mimic HTS (motor TTS en español) ────────────────────────────────
	# Recompila mimic1 (MycroftAI/mimic1) nativamente para musl/aarch64.
	# El configure.ac agrupa cmu_grapheme_lang/lex (que SÍ necesitamos) bajo
	# las flags de soporte "indic" — no deshabilitarlas pese al nombre.
	# vid_gb_ap/kal/kal16/awb/rms/slt(no-hts) son voces en inglés que no
	# usamos; una de ellas (vid_gb_ap) directamente no compila tal cual
	# viene el árbol fuente (falta un fichero), de ahí quedar fuera.
	cd "$builddir"/extras/mimic
	./autogen.sh
	rm -rf _build && mkdir _build
	cd _build
	../configure --prefix=/usr/local \
		--disable-vid_gb_ap --disable-cmu_us_kal --disable-cmu_us_kal16 \
		--disable-cmu_us_awb --disable-cmu_us_rms --disable-cmu_us_slt

	# Placeholder: el Makefile generado exige este fichero como prerequisito
	# de "all-am" (voicesinstall_DATA) aunque no existe en el árbol fuente
	# upstream — no usamos la voz de demo de mimic1, solo sus libs. mkdir -p
	# porque el rsync de extras/mimic excluye el voices/ real (--exclude=voices,
	# ~359MB de voces en inglés no usadas) y el directorio puede no existir.
	mkdir -p ../voices
	touch ../voices/cmu_us_slt_hts.htsvoice

	# GCC 15 trata -Wstringop-overflow como error por defecto sobre un
	# vsprintf fortificado en cst_file_stdio.c; falsa alarma de análisis
	# estático más estricto, no un bug real — se downgradea sin tocar el
	# código vendorizado.
	make -j"$(nproc)" \
		CFLAGS="-Wno-error=stringop-overflow" \
		CPPFLAGS="-Wno-error=stringop-overflow"

	MIMIC_SRC="$builddir"/extras/mimic
	MIMIC_LIBS="$MIMIC_SRC"/_build/.libs
	cd "$builddir"
	gcc -O2 \
		-I"$MIMIC_SRC"/include -I"$MIMIC_SRC"/_build/include \
		-I"$MIMIC_SRC"/lang -I"$MIMIC_SRC"/lang/cmu_grapheme_lang \
		-I"$MIMIC_SRC"/src/hts/hts_engine_API/include \
		-o mimic_hts_es \
		vendor/mimic_hts/mimic_hts_es.c vendor/mimic_hts/es_hts_g2p.c \
		-Wl,--start-group \
		"$MIMIC_LIBS"/libttsmimic_lang_cmu_grapheme_lang.a \
		"$MIMIC_LIBS"/libttsmimic_lang_cmu_grapheme_lex.a \
		"$MIMIC_LIBS"/libttsmimic_lang_cmu_us_slt_hts.a \
		"$MIMIC_LIBS"/libttsmimic_lang_cmulex.a \
		"$MIMIC_LIBS"/libttsmimic.a \
		-Wl,--end-group -lm -lpthread

	# ── PicoTTS (motor TTS de respaldo, varios idiomas) ─────────────────
	# Nota: los dos fixes de código en vendor/picotts (picoapi.c,
	# pico2wave.c) ya están aplicados en el repo — no son parte de este
	# build() sino correcciones permanentes de portabilidad musl.
	cd "$builddir"/vendor/picotts/svoxpico
	rm -rf autom4te.cache .libs Makefile configure aclocal.m4 config.log \
		config.status libtool ltmain.sh compile depcomp install-sh \
		missing config.guess config.sub *.lo *.o Makefile.in libttspico.la \
		2>/dev/null || true
	./autogen.sh
	./configure
	make -j"$(nproc)"

	# picolangdir es solo el default compilado — en runtime nav_tts.rs
	# siempre pasa NAVIUS_PICO_LANG (ver pico2wave.c:72), pero deben
	# coincidir para que funcione también si se invoca pico2wave a mano.
	cd "$builddir"/vendor/picotts
	gcc -I. -I./svoxpico -Wall -O2 \
		-Dpicolangdir=\"/usr/lib/navius/lib/picotts-lang\" \
		-c -o pico2wave.o src/pico2wave.c
	gcc -I./svoxpico -Wall -O2 pico2wave.o svoxpico/.libs/libttspico.a \
		-o pico2wave -lm -lpopt

	# ── Shims propios (no paquetes del sistema) ─────────────────────────
	cd "$builddir"
	gcc -shared -fPIC -o libpcaudio.so.0 src/libpcaudio_stub.c
	# Sin -ldl: en musl dlopen/dlsym viven en libc, -ldl genera una entrada
	# NEEDED "libdl.so.2" sin paquete real que la satisfaga (rompe abuild).
	gcc -shared -fPIC -o libpiper_limit.so src/libpiper_limit.c

	# ── navius (Rust + Qt5 vía qmetaobject) ─────────────────────────────
	# INSTALL_DIR: build.rs escribe ahí los .mo compilados (xgettext/
	# msgmerge/msgfmt corren como parte del build). Se usa un directorio
	# de staging propio (no $pkgdir directamente) para no romper la
	# convención de abuild de que solo package() escribe en $pkgdir.
	export INSTALL_DIR="$builddir"/_locale_stage
	mkdir -p "$INSTALL_DIR"
	# GETTEXT_SYSTEM=1: el crate gettext-sys (dependencia de gettext-rs) por
	# defecto compila su PROPIA copia vendorizada de GNU gettext completo
	# desde fuente (con -fanalyzer, muy lento, ~15-20 min) en vez de usar el
	# gettext del sistema ya instalado (makedepends ya lo declara). El
	# clickable.yaml original de Ubuntu Touch ya usaba esta misma variable.
	export GETTEXT_SYSTEM=1
	cargo build --release --locked
}

package() {
	install -Dm755 "$builddir"/target/release/navius \
		"$pkgdir"/usr/bin/navius
	install -Dm644 "$builddir"/navius.desktop \
		"$pkgdir"/usr/share/applications/navius.desktop
	install -Dm644 "$builddir"/assets/logo.svg \
		"$pkgdir"/usr/share/icons/hicolor/scalable/apps/navius.svg

	install -d "$pkgdir"/usr/share/locale
	cp -a "$builddir"/_locale_stage/share/locale/. "$pkgdir"/usr/share/locale/

	# Todos los binarios/datos propios (no cubiertos por paquetes del
	# sistema) viven bajo APP_ROOT/lib = /usr/lib/navius/lib (ver
	# APP_ROOT en nav_tts.rs) — nav_tts.rs construye estas rutas en runtime,
	# no cambiar la estructura sin actualizar ese fichero también.
	local navlib="$pkgdir"/usr/lib/navius/lib
	install -d "$navlib"

	install -Dm755 "$builddir"/mimic_hts_es "$navlib"/mimic_hts_es
	install -Dm644 "$builddir"/vendor/mimic_hts_voice/cstr_upc_upm_spanish_hts.htsvoice \
		"$navlib"/mimic-data/cstr_upc_upm_spanish_hts.htsvoice

	install -Dm755 "$builddir"/vendor/picotts/pico2wave "$navlib"/pico2wave
	install -d "$navlib"/picotts-lang
	cp -a "$builddir"/vendor/picotts/lang/. "$navlib"/picotts-lang/

	install -Dm755 "$builddir"/libpcaudio.so.0    "$navlib"/libpcaudio.so.0
	install -Dm755 "$builddir"/libpiper_limit.so  "$navlib"/libpiper_limit.so

	# piper ya no se instala aquí (Fase 8): viene del paquete "piper" propio
	# (depends=, /usr/bin/piper + /usr/lib/libpiper_phonemize.so*).
}
