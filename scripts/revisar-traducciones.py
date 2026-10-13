#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Busca textos que el usuario ve y que NO se van a traducir nunca.

Hay tres formas de que una cadena salga en castellano dentro de una pantalla en
otro idioma, y las tres se han dado de verdad en este port:

  1. El literal no esta envuelto en i18n.tr(), asi que xgettext no lo extrae y
     no existe en ningun .po. No falla, no sale vacio: sale en castellano.
  2. Esta en el .po pero sin traducir.
  3. Esta marcado #, fuzzy. msgfmt descarta las fuzzy sin decir nada, asi que el
     efecto es identico a no tener la traduccion. El 26/09/2026 habia 29 asi, y
     ademas con traducciones inventadas por msgmerge: "Supermercado" tenia como
     msgstr ingles "GPS recovered".

Contar con grep '^msgstr ""' no vale: casa con la primera linea de toda entrada
multilinea y da cifras infladas. Aqui se pregunta a msgattrib, que entiende el
formato.

Tambien revisa los marcadores: si el msgid trae %1 y la traduccion no, .arg()
se queda sin sitio donde poner el dato y el texto sale incompleto.

Uso:  scripts/revisar-traducciones.py [--todos]
      --todos incluye los literales dudosos (una sola palabra sin tilde), que
      dan muchos falsos positivos: nombres de color, iconos, claves de ajustes.
"""
import os, re, subprocess, sys

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
QML  = os.path.join(RAIZ, 'qml')
PO   = os.path.join(RAIZ, 'po')

# Palabras que solo aparecen en prosa castellana, nunca en una clave ni en un
# nombre de icono. Con una basta para dar la cadena por texto de interfaz.
PISTAS = set("""el la los las un una unos unas de del al y o no si se su sus tu tus
mi mis que con sin para por como mas menos muy ya hay esta este esto estos estas
ese esa eso todo toda todos todas otro otra cada donde cuando desde hasta entre
sobre pero aunque porque cual quien hacia tras ante bajo segun durante mientras
ninguna ningun alguna algun varios varias es son era fue ser estar tiene tienen
puede pueden debe deben hace hacen va van sale salen queda quedan pulsa toca
escribe rellena selecciona elige guarda borra anade activa desactiva busca
introduce comprueba revisa espera vuelve cierra abre""".split())

ACENTOS = re.compile(r'[áéíóúüñÁÉÍÓÚÜÑ¿¡]')
# Un texto de sugerencia dentro de un campo SIEMPRE lo lee el usuario, aunque no
# parezca prosa. El 26/09/2026 se escapo asi "correo@ejemplo.com", que salia en
# castellano en medio del panel de acceso en ingles, y las sugerencias de
# latitud y longitud de la posicion manual.
SUGERENCIA = re.compile(r'placeholderText\s*:\s*$')
# Literales entre comillas dobles o simples, respetando el escape.
LITERAL = re.compile(r'"((?:[^"\\]|\\.)*)"' + r"|'((?:[^'\\]|\\.)*)'")
# Lo que precede a un literal ya traducido: i18n.tr( o qsTr(, con el posible
# segundo argumento de los plurales.
TRADUCE = re.compile(r'(?:i18n\.tr|qsTr|tr)\s*\(\s*(?:"(?:[^"\\]|\\.)*"\s*,\s*)?$')
# Lineas que no pintan texto en pantalla aunque lleven castellano dentro. Las
# trazas son el grueso: el registro de depuracion se escribe en castellano a
# proposito, porque lo lee quien desarrolla, no quien conduce.
TRAZAS = re.compile(r'\b(_fileDump|_logMsg|_addLog|log_to_file|logMsg|_traza|'
                    r'_omitir|dbg|console\.(log|warn|error|debug|info))\s*\(')
SQL     = re.compile(r'\b(SELECT|INSERT INTO|UPDATE|DELETE FROM|CREATE TABLE|'
                     r'DROP TABLE|ORDER BY|WHERE|openDatabaseSync)\b')
# Ordenes de consola —el find con el que MediaPanel busca la musica— y listas de
# palabras clave de los scripts que se inyectan en el visor de Google Maps: no es
# texto que lea nadie en pantalla.
CONSOLA = re.compile(r"(find ~/|-iname |hideKeywords|dismissKeywords|CONTIENE|EXACTOS)")
# Comparaciones: el literal es un valor interno, no algo que se muestre.
COMPARA = re.compile(r'(indexOf|startsWith|endsWith|includes|localeCompare)\s*\($')
# Propiedades que nunca llevan texto visible.
TECNICO = re.compile(r'\b(source|iconName|icon\.name|objectName|font\.family|'
                     r'color|border\.color|url|Qt\.resolvedUrl|setValue|value\(|'
                     r'settings\.|_cfg|qInfo|import |pragma |property |signal |id:)')
# Ficheros que no forman parte de la app publicada.
APARTE = ('MapTest.qml',)

# Literales que se quedan en castellano A PROPOSITO, con el motivo. Se listan
# aparte para que el guion pueda acabar en cero y servir de reja antes de
# empaquetar: si aparece algo que no esta aqui, es que se ha colado sin traducir.
# El texto tiene que casar exacto; si cambia, vuelve a salir como fallo, que es
# lo que se quiere.
PERMITIDOS = {
    # Trazas y panel de depuracion: los lee quien desarrolla, no quien conduce.
    ' ms (hilo de eventos parado)':            'traza de depuracion',
    ' no existe -> activo ':                   'traza de depuracion',
    'tiles (desvío)':                          'panel de depuracion',
    'desvío ':                                 'panel de depuracion',
    'Ruta del usuario':                        'rutas de simulacion, solo en depuracion',
    '  todo_text TEXT NOT NULL,':              'SQL',
    # Datos de prueba fijos.
    'C/ de Provença, Eixample, Barcelona':     'direccion de prueba',
    'Plaça de Catalunya, Barcelona':           'direccion de prueba',
    # Habla. Va en el idioma de la VOZ, que se elige aparte del de la interfaz,
    # asi que traducirlo con el catalogo seria meter la pata al reves.
    'Voz activada para alertas':               'habla: idioma de la voz',
    'Voz activada para indicaciones':          'habla: idioma de la voz',
    'Soy paiper con voz ':                     'habla: prueba de voz',
    'Seleccionado español para indicaciones y alertas':      'habla: ya esta en su idioma',
    'Sélectionné français pour les instructions et alertes': 'habla: ya esta en su idioma',
    'Deutsch ausgewählt für Anweisungen und Warnungen':      'habla: ya esta en su idioma',
    'Selecionado português para instruções e alertas':       'habla: ya esta en su idioma',
    'En quinientos metros, gire a la derecha': 'habla: prueba por adb',
    # Gramatica castellana sobre el texto que devuelve Valhalla en castellano.
    'séptima': 'ordinales para las instrucciones en castellano',
    'décima':  'ordinales para las instrucciones en castellano',
    'séptimo': 'ordinales para las instrucciones en castellano',
    'décimo':  'ordinales para las instrucciones en castellano',
    # Propios de este port, y tampoco se traducen a proposito.
    ' no existe → activo ':                     'traza de depuracion',
    '✕ Sin IMU: Qt no expone acelerómetro':     'panel de depuracion del IMU',
    '⚠ Acelerómetro sin lecturas':              'panel de depuracion del IMU',
    '   (sin giro)':                            'panel de depuracion del IMU',
    'SIN BACKEND':                              'traza del IMU',
    'la posición en túnel se apoyará solo en el shape de la ruta': 'traza del IMU',
    'ninguna lectura (¿sesión no activa para polkit?)': 'traza del IMU',
    'Soy Pico T T S con voz ':                  'habla: prueba de voz',
    'Soy espeak con voz ':                      'habla: prueba de voz',
    'Hola! Soy el motor T T S ':                'habla: prueba de voz',
    'automático':                               'nombre de ajuste de voz',
    ' no disponible':                           'traza de voz',
    'Español (Latino)':                         'nombre de idioma, escrito en su propio idioma',
    'ar · ca · de · en · es · fa · fr · it · pt · ru · zh · y otros': 'lista de codigos de idioma',
    "find ~/Music -type f \\( -iname '*.mp3' -o -iname '*.flac' ": 'orden de consola',
    "-o -iname '*.ogg' -o -iname '*.m4a' -o -iname '*.opus' ":        'orden de consola',
    "-o -iname '*.wav' -o -iname '*.aac' \\) ":                      'orden de consola',
    # Palabras clave de los scripts que se inyectan en el visor de Google Maps:
    # sirven para reconocer sus botones, no se enseñan.
    'abrir la aplicación':      'palabra clave del visor de Maps',
    'abrir en la aplicación':   'palabra clave del visor de Maps',
    'ver en la app':            'palabra clave del visor de Maps',
    'abrir la app':             'palabra clave del visor de Maps',
    'continuar en el navegador':'palabra clave del visor de Maps',
    'no thanks':                'palabra clave del visor de Maps',
    # Nombres que no se traducen.
    '  (mi, ft)': 'abreviaturas de unidades',
    'Español':    'nombre de idioma, escrito en su propio idioma',
}

def es_prosa(t):
    """¿Parece un texto que lee una persona?"""
    if len(t) < 2 or t.startswith('#') or t.startswith('qrc:'):
        return False
    if re.fullmatch(r'[\W\d_]+', t):          # simbolos, numeros, unidades
        return False
    if ACENTOS.search(t):
        return True
    palabras = re.findall(r"[A-Za-zÁ-úñ]+", t.lower())
    return any(p in PISTAS for p in palabras)

def dudosa(t):
    """Una sola palabra sin tilde: puede ser texto o puede ser una clave."""
    return not ACENTOS.search(t) and len(t.split()) < 2

def ficheros():
    for base, _, fs in os.walk(QML):
        for f in sorted(fs):
            if f.endswith(('.qml', '.js')) and f not in APARTE:
                yield os.path.join(base, f)

def sin_envolver(todos=False):
    """Devuelve (fallos, ya_en_catalogo, a_proposito).

    La segunda lista son literales sueltos cuyo texto SI aparece envuelto en
    otra linea del mismo fichero. Es el patron de AlertasOverjay.qml: las
    etiquetas se guardan en castellano y se traducen al pintarlas, con una lista
    _i18nNoop aparte para que xgettext las vea. No son fallos, pero se enseñan
    porque el mismo sintoma puede ser un descuido.
    """
    fallos, conocidos, permitidos = [], [], []
    for ruta in ficheros():
        with open(ruta, encoding='utf-8') as fh:
            lineas = fh.readlines()
        rel = os.path.relpath(ruta, RAIZ)
        # Todo lo que este fichero ya mete en el catalogo.
        envueltos = set()
        texto = ''.join(lineas)
        for m in re.finditer(r'(?:i18n\.tr|qsTr|tr)\s*\(\s*((?:"(?:[^"\\]|\\.)*"\s*\+?\s*)+)', texto):
            envueltos.add(''.join(re.findall(r'"((?:[^"\\]|\\.)*)"', m.group(1))))
        # Una llamada a tr() puede ocupar varias lineas, concatenando literales
        # con +. xgettext las junta bien (lo hace de verdad, comprobado con el
        # parrafo de AboutDialog), asi que sus continuaciones no son fallos. Se
        # siguen contando parentesis desde la llamada hasta que cierra.
        abierta = 0
        for n, linea in enumerate(lineas, 1):
            codigo = linea.split('//')[0] if '://' not in linea else linea
            if abierta > 0:
                abierta += codigo.count('(') - codigo.count(')')
                continue
            m = re.search(r'(?:i18n\.tr|qsTr|\btr)\s*\(', codigo)
            if m:
                resto = codigo[m.end():]
                pendiente = 1 + resto.count('(') - resto.count(')')
                if pendiente > 0:
                    abierta = pendiente
                    continue
            if TECNICO.search(codigo) or TRAZAS.search(codigo) \
                    or SQL.search(codigo) or CONSOLA.search(codigo):
                continue
            for m in LITERAL.finditer(codigo):
                t = m.group(1) if m.group(1) is not None else m.group(2)
                antes = codigo[:m.start()]
                sugerencia = bool(SUGERENCIA.search(antes.rstrip()))
                if not sugerencia and not es_prosa(t):
                    continue
                if TRADUCE.search(antes) or COMPARA.search(antes):
                    continue
                if dudosa(t) and not sugerencia and not todos:
                    continue
                if t in PERMITIDOS:
                    permitidos.append((rel, n, t))
                else:
                    (conocidos if t in envueltos else fallos).append((rel, n, t))
    return fallos, conocidos, permitidos

def pendientes():
    """Por idioma: entradas sin traducir, fuzzy y marcadores descuadrados."""
    filas = []
    for po in sorted(os.listdir(PO)) if os.path.isdir(PO) else []:
        if not po.endswith('.po'):
            continue
        ruta = os.path.join(PO, po)
        def cuenta(*flags):
            out = subprocess.run(['msgattrib', *flags, '--no-obsolete', ruta],
                                 capture_output=True, text=True).stdout
            return len([b for b in re.findall(r'^msgid\s+"(.*)"', out, re.M) if b])
        filas.append((po[:-3], cuenta('--untranslated'), cuenta('--only-fuzzy'),
                      marcadores(ruta)))
    return filas

def marcadores(ruta):
    """Traducciones que pierden o inventan un %1: .arg() se queda sin sitio."""
    with open(ruta, encoding='utf-8') as fh:
        s = fh.read()
    mal = 0
    for m in re.finditer(r'\nmsgid ((?:"(?:[^"\\]|\\.)*"\s*)+)msgstr ((?:"(?:[^"\\]|\\.)*"\s*)+)', s):
        mid = ''.join(re.findall(r'"((?:[^"\\]|\\.)*)"', m.group(1)))
        mst = ''.join(re.findall(r'"((?:[^"\\]|\\.)*)"', m.group(2)))
        if not mid or not mst:
            continue
        if sorted(set(re.findall(r'%[1-9]', mid))) != sorted(set(re.findall(r'%[1-9]', mst))):
            mal += 1
    return mal

def main():
    todos = '--todos' in sys.argv
    fallos, conocidos, permitidos = sin_envolver(todos)
    print('== Literales sin i18n.tr() ==')
    for ruta, n, t in fallos:
        print('  %s:%d  %s' % (ruta, n, t[:90]))
    print('  %d%s' % (len(fallos), '' if todos else
                      ' (sin contar dudosos; --todos los incluye)'))
    if conocidos:
        print()
        print('== Sin envolver, pero el texto ya esta en el catalogo por otra')
        print('   linea del mismo fichero (patron _i18nNoop; repasar) ==')
        for ruta, n, t in conocidos:
            print('  %s:%d  %s' % (ruta, n, t[:90]))
    if permitidos and todos:
        print()
        print('== Sin traducir a proposito ==')
        for ruta, n, t in permitidos:
            print('  %s:%d  %s  [%s]' % (ruta, n, t[:60], PERMITIDOS[t]))
    elif permitidos:
        print('  y %d literales que no se traducen a proposito (--todos los lista)'
              % len(permitidos))
    print()
    print('== Catalogos ==')
    mal = 0
    for lang, sin, fuzzy, marc in pendientes():
        if sin or fuzzy or marc:
            mal += 1
        print('  %-3s  sin traducir %3d   fuzzy %3d   marcadores %3d   %s'
              % (lang, sin, fuzzy, marc, 'REVISAR' if (sin or fuzzy or marc) else 'ok'))
    return 1 if fallos or mal else 0

if __name__ == '__main__':
    sys.exit(main())
