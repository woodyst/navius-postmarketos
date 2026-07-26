#!/usr/bin/env python3
"""Herramienta i18n de Navius: detecta y rellena textos sin traducir.

Usa polib (parser real de gettext) en lugar de expresiones regulares: los
msgid multilínea rompen cualquier enfoque con regex — es un error que ya se
cometió en este repo (ver sesión 112).

Subcomandos
-----------
  audit      Busca textos visibles en QML/JS que NO estén envueltos en i18n.tr()
  extract    Regenera el .pot con xgettext y hace msgmerge en cada .po
             (mismos argumentos que src/build.rs, para no divergir del build)
  list       Lista lo que falta por idioma (sin traducir + fuzzy)
  translate  Rellena los msgstr vacíos con un backend de traducción
  check      Valida los .po: placeholders, símbolos y msgfmt -c

Backends de traducción (--backend)
----------------------------------
  google  (por defecto) Google Translate, sin clave ni instalación. Traduce
          es→destino DIRECTO en los 11 idiomas y conserva emojis y símbolos.
          Es lo bastante bueno para frases; en etiquetas de una palabra pierde
          el contexto, para eso está GLOSARIO_FORZADO más abajo.
  claude  Máxima calidad: recibe el contexto de dominio y el estilo del propio
          .po, así que acierta las etiquetas ambiguas sin glosario. Necesita
          credenciales (ANTHROPIC_API_KEY o `ant auth login`) y el SDK.
  none    No traduce; solo informa (equivale a `list`).

Descartado: Argos Translate (offline). Solo es→en y es→pt son directos; los
otros 9 idiomas pivotan por inglés, lo que destroza las etiquetas cortas
("Retirar consentimiento" → ca "Reintegra") y corrompe símbolos (⚠ → "Reg.").

Ejemplos
--------
  ./i18n_tool.py audit
  ./i18n_tool.py extract
  ./i18n_tool.py list
  ./i18n_tool.py translate --lang ca                 # google por defecto
  ./i18n_tool.py translate --backend claude          # todos, secuencial
  ./i18n_tool.py check
"""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
import unicodedata
from pathlib import Path

PO_DIR = Path(__file__).resolve().parent
SRC_DIR = PO_DIR.parent
POT = PO_DIR / "navius.woodyst.pot"

# Nombre nativo de cada idioma, para dárselo al traductor.
LANGS = {
    "ar": "árabe", "ca": "catalán", "de": "alemán", "en": "inglés",
    "eu": "euskera", "fa": "persa (farsi)", "fr": "francés", "it": "italiano",
    "pt": "portugués", "ru": "ruso", "zh": "chino simplificado",
}

# Términos que NUNCA se traducen (marcas, servicios, nombres propios).
GLOSARIO_INTACTO = [
    "Navius", "OSM Scout", "OSM Scout Server", "OpenStreetMap", "OSM",
    "Valhalla", "Overpass", "Photon", "Piper", "PicoTTS", "espeak",
    "Ubuntu Touch", "OpenStore", "GPS", "IMU", "TTS", "Mapbox",
]

# Contexto de dominio: sin esto, un traductor genérico convierte "Adelanto"
# en "anticipo económico" y "radar" en "radar meteorológico".
CONTEXTO = """\
Navius es una aplicación de navegación GPS para coche (Ubuntu Touch/Android).
Estas cadenas son de su interfaz. Notas de dominio imprescindibles:
- "radar" = radar de tráfico / cámara de velocidad (speed camera), NUNCA radar meteorológico.
- "Adelanto" (panel de depuración GPS) = segundos que la posición mostrada se
  ADELANTA para compensar la latencia del fix. Es anticipación temporal
  (lead time / look-ahead), NO un anticipo de dinero ni "progreso".
- "ruta" = itinerario de navegación. "tramo" = segmento de vía.
- "maniobra" = indicación de giro. "fix" = posición GPS válida.
- Tratamiento de usuario: el que ya use el resto del fichero .po."""

# Código de idioma de Google cuando no coincide con el del .po.
# pt.po es portugués EUROPEO ("planear", "ecrã"): pt a secas da brasileño.
GOOGLE_LANG = {"zh": "zh-CN", "pt": "pt-PT"}

# Etiquetas que la traducción automática falla porque, aisladas, son ambiguas.
# Un traductor sin contexto lee "Adelanto" como "progreso" o "anticipo de
# dinero"; aquí significa la anticipación temporal del display GPS.
# Comprobado: google y argos fallan los dos en esta. El backend claude la
# acierta con el contexto, pero se fuerza igual para que ambos coincidan.
# "radar" es el otro caso: la app ya usa el término local de cada idioma para
# radar de tráfico (de "Blitzer", en "camera", it "Autovelox", ru "камеры",
# zh "测速摄像头"). Google devuelve el literal "radar" — en chino incluso 雷达,
# que es el radar meteorológico. Se fuerza para no romper la coherencia con
# las cadenas ya traducidas ("Radares fijos", "Radares de tramo"…).
GLOSARIO_FORZADO = {
    "Adelanto": {
        "ar": "التقديم الزمني", "ca": "Anticipació", "de": "Vorhaltezeit",
        "en": "Lead time", "eu": "Aurrerapen-denbora", "fa": "پیش‌بینی زمانی",
        "fr": "Anticipation", "it": "Anticipo temporale", "pt": "Antecipação",
        "ru": "Упреждение", "zh": "提前量",
    },
    "⚠ No se pudieron obtener los radares · revisa la conexión": {
        "ar": "⚠ تعذر الحصول على الرادارات · تحقق من الاتصال",
        "ca": "⚠ No s'han pogut obtenir els radars · revisa la connexió",
        "de": "⚠ Blitzer konnten nicht geladen werden · Verbindung prüfen",
        "en": "⚠ Could not fetch speed cameras · check the connection",
        "eu": "⚠ Ezin izan dira radarrak lortu · egiaztatu konexioa",
        "fa": "⚠ دوربین‌ها دریافت نشدند · اتصال را بررسی کنید",
        "fr": "⚠ Impossible d'obtenir les radars · vérifiez la connexion",
        "it": "⚠ Impossibile ottenere gli autovelox · controlla la connessione",
        "pt": "⚠ Não foi possível obter os radares · verifique a ligação",
        "ru": "⚠ Не удалось загрузить камеры · проверьте соединение",
        "zh": "⚠ 无法获取测速摄像头 · 请检查连接",
    },
}


# ─────────────────────────── utilidades ────────────────────────────

def _need_polib():
    try:
        import polib  # noqa: F401
    except ImportError:
        sys.exit(
            "Falta polib. Instálalo en un venv (NUNCA con --break-system-packages):\n"
            f"  python3 -m venv {PO_DIR}/.venv-translate\n"
            f"  {PO_DIR}/.venv-translate/bin/pip install polib\n"
            f"  {PO_DIR}/.venv-translate/bin/python {Path(__file__).name} ..."
        )
    import polib
    return polib


def po_files() -> list[Path]:
    return sorted(p for p in PO_DIR.glob("*.po"))


# Marcadores que deben sobrevivir intactos a la traducción.
_PLACEHOLDER = re.compile(r"%\d+|%[sd]|\{\d*\}|\$\w+")


# Puntuación que puede desaparecer legítimamente al traducir: la interrogación
# y exclamación de apertura solo existen en español, y la puntuación CJK y árabe
# sustituye a la latina. Marcarlas como "perdidas" sería un falso positivo.
_PUNT_OMITIBLE = ".,;:!?'\"()[]{}-–—/\\&%+*=<>|_#@~`^$¿¡«»‹›„“”‘’…、。，；：！？（）"


# Idiomas de derecha a izquierda: en ellos las flechas se espejan (→ pasa a ←),
# que es la localización CORRECTA, no un símbolo perdido.
_RTL = {"ar", "fa"}
_ESPEJO = str.maketrans("←⇐«»", "→⇒»«")


def _symbols(s: str, lang: str = "") -> set[str]:
    """Emojis y símbolos que deben sobrevivir a la traducción (⚠ · ° → 📷 🅿)."""
    if lang in _RTL:
        s = s.translate(_ESPEJO)
    return {c for c in s
            if not c.isalnum() and not c.isspace()
            and unicodedata.category(c) in ("So", "Sk", "Sm", "Po")
            and c not in _PUNT_OMITIBLE}


# ───────────────────────────── audit ───────────────────────────────

# Heurística: string literal con al menos una letra y un espacio o mayúscula
# inicial, fuera de i18n.tr(). Descarta rutas, urls, ids, colores, claves JSON.
_DESCARTA = re.compile(
    r"^(?:#|https?://|qrc:|file:|/|\./|\.\./|[a-z_][a-z0-9_]*$|[A-Z_]+$"
    r"|\d|[\w.-]+\.(?:qml|js|png|svg|json|po|mo|wav|ttf)$)", re.I)


def cmd_audit(args) -> int:
    """Textos visibles en QML/JS que no pasan por i18n.tr()."""
    hits: list[tuple[str, int, str]] = []
    files = sorted(SRC_DIR.glob("qml/**/*.qml")) + sorted(SRC_DIR.glob("qml/**/*.js"))
    for f in files:
        for n, line in enumerate(f.read_text(encoding="utf-8").splitlines(), 1):
            code = line.split("//")[0]
            # Propiedades que muestran texto al usuario.
            if not re.search(r"\b(text|title|subtitle|label|placeholderText|"
                             r"description|tooltip)\s*:", code):
                continue
            if "i18n.tr" in code:
                continue
            for lit in re.findall(r'"((?:[^"\\]|\\.)*)"', code):
                if len(lit) < 2 or _DESCARTA.match(lit):
                    continue
                if not re.search(r"[A-Za-zÁÉÍÓÚÑáéíóúñ]", lit):
                    continue
                hits.append((str(f.relative_to(SRC_DIR)), n, lit))

    if not hits:
        print("✓ No se han encontrado textos visibles sin i18n.tr()")
        return 0
    print(f"⚠ {len(hits)} textos posiblemente sin traducir "
          f"(revisar: la heurística tiene falsos positivos)\n")
    for path, n, lit in hits:
        print(f"  {path}:{n}: {lit!r}")
    print("\nNota: el panel de depuración está excluido a propósito del i18n "
          "(decisión de la sesión 112).")
    return 0


# ──────────────────────────── extract ──────────────────────────────

def cmd_extract(args) -> int:
    """Regenera el .pot y hace msgmerge. Mismos flags que src/build.rs."""
    qml = sorted(str(p.relative_to(SRC_DIR)) for p in SRC_DIR.glob("qml/**/*.qml"))
    cmd = ["xgettext", f"--output={POT}", "--language=javascript", "--qt",
           "--keyword=tr", "--keyword=tr:1,2", "--add-comments=i18n",
           "--from-code=UTF-8", *qml]
    r = subprocess.run(cmd, cwd=SRC_DIR, capture_output=True, text=True)
    if r.returncode != 0:
        print(r.stderr, file=sys.stderr)
        return r.returncode
    print(f"✓ .pot regenerado desde {len(qml)} ficheros QML")
    # OJO: build.rs solo barre qml/, no src/*.js — si algún día se envuelven
    # cadenas en .js con i18n.tr(), habrá que añadirlos aquí Y en build.rs.
    for po in po_files():
        subprocess.run(["msgmerge", "--quiet", "--update", "--backup=none",
                        str(po), str(POT)], check=True)
    print(f"✓ msgmerge aplicado a {len(po_files())} ficheros .po")
    return 0


# ────────────────────────────── list ───────────────────────────────

def _pending(po):
    """(sin traducir, fuzzy) de un fichero .po ya cargado."""
    return ([e for e in po if not e.obsolete and not e.msgstr and not e.fuzzy],
            [e for e in po if not e.obsolete and e.fuzzy])


def cmd_list(args) -> int:
    polib = _need_polib()
    total_u = total_f = 0
    for path in po_files():
        lang = path.stem
        if args.lang and lang != args.lang:
            continue
        po = polib.pofile(str(path))
        untr, fuzzy = _pending(po)
        total_u += len(untr)
        total_f += len(fuzzy)
        print(f"{lang:<3} {len(po)-len(untr)-len(fuzzy):>4} ok  "
              f"{len(untr):>3} sin traducir  {len(fuzzy):>3} fuzzy")
        if args.verbose:
            for e in untr:
                print(f"      ∅ {e.msgid!r}")
            for e in fuzzy:
                print(f"      ~ {e.msgid!r} → {e.msgstr!r}")
    print(f"\nTOTAL: {total_u} sin traducir, {total_f} fuzzy")
    return 0


# ─────────────────────────── backends ──────────────────────────────

def _translate_claude(msgids: list[str], lang: str, ejemplos: list[tuple[str, str]]):
    """Traduce con la API de Anthropic. Devuelve {msgid: msgstr}.

    Manda el lote entero en una llamada con salida estructurada, para que el
    modelo mantenga coherencia terminológica dentro del idioma.
    """
    try:
        import anthropic
    except ImportError:
        sys.exit("Falta el SDK: <venv>/bin/pip install anthropic")

    client = anthropic.Anthropic()  # ANTHROPIC_API_KEY o perfil de `ant auth login`

    muestra = "\n".join(f"  {o!r} → {t!r}" for o, t in ejemplos[:25])
    system = f"""\
Eres traductor profesional de interfaces de usuario. Traduces del español al {LANGS[lang]}.

{CONTEXTO}

NO TRADUZCAS estos términos, déjalos literales: {", ".join(GLOSARIO_INTACTO)}.

Reglas estrictas:
1. Conserva EXACTAMENTE los emojis y símbolos del original (⚠, ·, °, →, 📷…).
   No los conviertas en texto ni los sustituyas.
2. Conserva los marcadores de formato (%1, %2, {{}}, $var) sin cambiar su orden
   salvo que la gramática del idioma destino lo exija.
3. Son etiquetas de UI: mantén la longitud parecida al original. Una etiqueta
   de botón corta debe seguir siendo corta.
4. Respeta el registro y el tratamiento del usuario de los ejemplos siguientes.
5. Devuelve SOLO la traducción de cada cadena, sin comillas añadidas ni notas.

Ejemplos ya traducidos en este mismo fichero (imita su estilo):
{muestra}"""

    schema = {
        "type": "object",
        "properties": {
            "traducciones": {
                "type": "array",
                "items": {
                    "type": "object",
                    "properties": {
                        "origen": {"type": "string"},
                        "traduccion": {"type": "string"},
                    },
                    "required": ["origen", "traduccion"],
                    "additionalProperties": False,
                },
            }
        },
        "required": ["traducciones"],
        "additionalProperties": False,
    }

    payload = json.dumps(msgids, ensure_ascii=False, indent=1)
    resp = client.messages.create(
        model="claude-opus-5",
        max_tokens=16000,
        system=system,
        output_config={"format": {"type": "json_schema", "schema": schema}},
        messages=[{"role": "user", "content":
                   f"Traduce al {LANGS[lang]} estas {len(msgids)} cadenas. "
                   f"Devuelve una entrada por cadena, con 'origen' idéntico al "
                   f"recibido:\n{payload}"}],
    )
    if resp.stop_reason == "refusal":
        sys.exit(f"La API rechazó la petición ({resp.stop_details}).")
    text = next(b.text for b in resp.content if b.type == "text")
    data = json.loads(text)
    return {t["origen"]: t["traduccion"] for t in data["traducciones"]}


def _translate_google(msgids: list[str], lang: str, ejemplos) -> dict[str, str]:
    """Google Translate por el endpoint público. Sin clave, es→destino directo.

    Una petición por cadena: el endpoint no garantiza el troceado de un lote y
    mezclar cadenas de UI en un solo texto le hace inventar concordancias.
    """
    import time
    import urllib.parse
    import urllib.request

    def _limpia(t: str) -> str:
        # Google mete U+200B (espacio de ancho cero) alrededor de los nombres
        # propios que no traduce ("Navius ​​akzeptieren"): basura
        # invisible en la UI. Se quita ese y el BOM, pero NO U+200C/U+200D,
        # que en persa y árabe son ortográficamente necesarios (پیش‌بینی).
        t = t.replace("​", "").replace("﻿", "")
        return re.sub(r"[ \t]{2,}", " ", t).strip()

    tl = GOOGLE_LANG.get(lang, lang)
    out: dict[str, str] = {}
    for i, s in enumerate(msgids):
        url = ("https://translate.googleapis.com/translate_a/single"
               f"?client=gtx&sl=es&tl={tl}&dt=t&q=" + urllib.parse.quote(s))
        req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
        try:
            with urllib.request.urlopen(req, timeout=20) as r:
                out[s] = _limpia("".join(p[0] for p in json.load(r)[0]))
        except Exception as exc:                       # noqa: BLE001
            print(f"  ! google falló en {s!r}: {exc}", file=sys.stderr)
        if i < len(msgids) - 1:
            time.sleep(0.3)                            # no martillear el endpoint
    return out


BACKENDS = {"google": _translate_google, "claude": _translate_claude}


# ─────────────────────────── translate ─────────────────────────────

def cmd_translate(args) -> int:
    polib = _need_polib()
    if args.backend == "none":
        return cmd_list(args)
    fn = BACKENDS[args.backend]

    for path in po_files():
        lang = path.stem
        if args.lang and lang != args.lang:
            continue
        po = polib.pofile(str(path))
        untr, fuzzy = _pending(po)

        if args.fuzzy:
            # Las fuzzy CORTAS son emparejamientos erróneos de msgmerge: con
            # etiquetas de pocas palabras el emparejamiento difuso acierta poco
            # ("IMU debug" quedó como "POIs debug" en los 11 idiomas). Las
            # largas suelen ser traducciones humanas correctas que solo perdieron
            # el sello al cambiar el original: retraducirlas con MT sería
            # empeorarlas, así que se dejan para `unfuzzy`.
            untr = untr + [e for e in fuzzy if len(e.msgid) < args.fuzzy_max]

        if not untr:
            print(f"{lang}: nada que traducir")
            continue

        # Ejemplos ya traducidos: fijan registro y terminología.
        ejemplos = [(e.msgid, e.msgstr) for e in po
                    if e.msgstr and not e.fuzzy and not e.obsolete
                    and 3 < len(e.msgid) < 60]

        print(f"{lang}: traduciendo {len(untr)} cadenas con «{args.backend}»…")
        res = fn([e.msgid for e in untr], lang, ejemplos)

        # El glosario manda sobre el backend: son las etiquetas ambiguas que la
        # traducción automática falla por falta de contexto.
        for msgid, porlang in GLOSARIO_FORZADO.items():
            if msgid in res and lang in porlang:
                if res[msgid] != porlang[lang]:
                    print(f"    glosario: {msgid!r} {res[msgid]!r} → {porlang[lang]!r}")
                res[msgid] = porlang[lang]

        aplicadas = 0
        for e in untr:
            t = res.get(e.msgid)
            if not t:
                print(f"  ! sin respuesta para {e.msgid!r}", file=sys.stderr)
                continue
            # No aceptes una traducción que pierde símbolos o placeholders.
            if _symbols(e.msgid) - _symbols(t, lang):
                print(f"  ! símbolos perdidos, descartada: {e.msgid!r} → {t!r}",
                      file=sys.stderr)
                continue
            if set(_PLACEHOLDER.findall(e.msgid)) - set(_PLACEHOLDER.findall(t)):
                print(f"  ! placeholders perdidos, descartada: {e.msgid!r} → {t!r}",
                      file=sys.stderr)
                continue
            if args.dry_run:
                marca = " [fuzzy]" if e.fuzzy else ""
                print(f"    {e.msgid!r} → {t!r}{marca}")
            else:
                e.msgstr = t
                # Retraducida: ya no es dudosa, y si sigue fuzzy msgfmt la
                # excluye del .mo y la app mostraría el español.
                if "fuzzy" in e.flags:
                    e.flags.remove("fuzzy")
            aplicadas += 1

        if not args.dry_run:
            po.save(str(path))
        print(f"  ✓ {aplicadas}/{len(untr)} "
              f"{'(simulacro)' if args.dry_run else 'aplicadas'}")
    return 0


# ───────────────────────────── unfuzzy ─────────────────────────────

def _estructura_ok(msgid: str, msgstr: str) -> str | None:
    """Devuelve el motivo del desajuste, o None si la traducción cuadra."""
    if msgid.count("\n") != msgstr.count("\n"):
        return "saltos de línea"
    if msgid.count("•") != msgstr.count("•"):
        return "viñetas"
    if len(re.findall(r"[①-⑳]", msgid)) != len(re.findall(r"[①-⑳]", msgstr)):
        return "numeración"
    if not 0.7 < len(msgstr) / max(len(msgid), 1) < 1.9:
        return "longitud desproporcionada"
    return None


def cmd_unfuzzy(args) -> int:
    """Quita el sello fuzzy a las traducciones LARGAS que cuadran.

    Una fuzzy no llega al .mo: msgfmt la excluye y la app enseña el español.
    Cuando la traducción es correcta y solo perdió el sello (típico tras editar
    el original), reactivarla es la reparación. Solo se tocan las largas: en las
    cortas el emparejamiento difuso de msgmerge no es fiable — para esas está
    `translate --fuzzy`, que las retraduce.
    """
    polib = _need_polib()
    for path in po_files():
        lang = path.stem
        if args.lang and lang != args.lang:
            continue
        po = polib.pofile(str(path))
        fz = [e for e in po if e.fuzzy and not e.obsolete]
        largas = [e for e in fz if len(e.msgid) >= args.min_len]
        ok, rechazadas = [], []
        for e in largas:
            motivo = _estructura_ok(e.msgid, e.msgstr)
            (rechazadas if motivo else ok).append((e, motivo))
        if not fz:
            continue
        print(f"{lang}: {len(fz)} fuzzy → {len(ok)} reactivables, "
              f"{len(rechazadas)} rechazadas, {len(fz)-len(largas)} cortas "
              f"(usa «translate --fuzzy»)")
        for e, motivo in rechazadas:
            print(f"    ✗ {motivo}: {e.msgid[:60]!r}")
        if not args.dry_run:
            for e, _ in ok:
                e.flags.remove("fuzzy")
            po.save(str(path))
            print(f"  ✓ {len(ok)} reactivadas")
    return 0


# ────────────────────────────── check ──────────────────────────────

def cmd_check(args) -> int:
    polib = _need_polib()
    fallos = 0
    for path in po_files():
        lang = path.stem
        if args.lang and lang != args.lang:
            continue
        po = polib.pofile(str(path))
        probs = []
        for e in po:
            if e.obsolete or not e.msgstr:
                continue
            if _symbols(e.msgid) - _symbols(e.msgstr, lang):
                probs.append(f"símbolos perdidos: {e.msgid!r} → {e.msgstr!r}")
            if set(_PLACEHOLDER.findall(e.msgid)) - set(_PLACEHOLDER.findall(e.msgstr)):
                probs.append(f"placeholders perdidos: {e.msgid!r} → {e.msgstr!r}")
            # Una etiqueta corta que se traduce a algo desproporcionado suele
            # ser una explicación en vez de una traducción.
            if len(e.msgid) < 30 and len(e.msgstr) > 4 * len(e.msgid) + 10:
                probs.append(f"traducción desproporcionada: {e.msgid!r} → {e.msgstr!r}")
        r = subprocess.run(["msgfmt", "-c", "-o", os.devnull, str(path)],
                           capture_output=True, text=True)
        if r.returncode != 0:
            probs.append("msgfmt -c falla:\n" + r.stderr.strip())
        if probs:
            fallos += len(probs)
            print(f"✗ {lang}")
            for p in probs:
                print(f"    {p}")
        else:
            print(f"✓ {lang}")
    return 1 if fallos else 0


# ─────────────────────────────── cli ───────────────────────────────

def main() -> int:
    ap = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)

    sub.add_parser("audit", help="textos QML/JS sin i18n.tr()").set_defaults(fn=cmd_audit)
    sub.add_parser("extract", help="regenera .pot + msgmerge").set_defaults(fn=cmd_extract)

    p = sub.add_parser("list", help="qué falta por idioma")
    p.add_argument("--lang"); p.add_argument("-v", "--verbose", action="store_true")
    p.set_defaults(fn=cmd_list)

    p = sub.add_parser("translate", help="rellena los msgstr vacíos")
    p.add_argument("--lang", help="solo este idioma (por defecto: todos, secuencial)")
    p.add_argument("--backend", choices=[*BACKENDS, "none"], default="google")
    p.add_argument("--dry-run", action="store_true", help="muestra, no escribe")
    p.add_argument("--fuzzy", action="store_true",
                   help="retraduce también las fuzzy cortas (emparejamientos "
                        "erróneos de msgmerge) y les quita el sello")
    p.add_argument("--fuzzy-max", type=int, default=60, metavar="N",
                   help="longitud máx. de msgid fuzzy a retraducir (def. 60)")
    p.add_argument("-v", "--verbose", action="store_true")
    p.set_defaults(fn=cmd_translate)

    p = sub.add_parser("unfuzzy", help="reactiva fuzzy largas que sí cuadran")
    p.add_argument("--lang")
    p.add_argument("--min-len", type=int, default=60, metavar="N",
                   help="longitud mínima de msgid a reactivar (def. 60)")
    p.add_argument("--dry-run", action="store_true")
    p.set_defaults(fn=cmd_unfuzzy)

    p = sub.add_parser("check", help="valida placeholders, símbolos y msgfmt")
    p.add_argument("--lang")
    p.set_defaults(fn=cmd_check)

    args = ap.parse_args()
    return args.fn(args)


if __name__ == "__main__":
    sys.exit(main())
