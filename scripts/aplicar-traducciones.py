#!/usr/bin/env python3
"""Rellena las cadenas pendientes de un .po a partir de una lista de traducciones.

Las traducciones llegan en un fichero de texto, una por linea y EN EL MISMO ORDEN
en que msgattrib lista las pendientes. Los saltos de linea van escritos como \\n,
igual que en el .po.

No se reescriben los msgid: se leen del propio .po y se emiten tal cual en un
compendio que luego aplica msgmerge. Asi es imposible desincronizar el original
de su traduccion, que es el fallo tipico al editar catalogos a mano.
"""
import re, subprocess, sys, io, os

def pendientes(po):
    t = subprocess.run(['msgattrib', '--untranslated', '--no-obsolete', po],
                       capture_output=True, text=True, check=True).stdout
    out = []
    for m in re.finditer(r'\nmsgid ((?:"(?:[^"\\]|\\.)*"\s*)+)msgstr', t):
        partes = re.findall(r'"((?:[^"\\]|\\.)*)"', m.group(1))
        if ''.join(partes):
            out.append(partes)          # se conserva el troceado original
    return out

def main():
    po, fichero = sys.argv[1], sys.argv[2]
    ids = pendientes(po)
    trad = [l.rstrip('\n') for l in io.open(fichero, encoding='utf-8') if l.strip() != '']
    if len(ids) != len(trad):
        sys.exit(f'descuadre: {len(ids)} pendientes y {len(trad)} traducciones')

    comp = po + '.comp'
    with io.open(comp, 'w', encoding='utf-8') as f:
        f.write('msgid ""\nmsgstr "Content-Type: text/plain; charset=UTF-8\\n"\n\n')
        for partes, tr in zip(ids, trad):
            f.write('msgid ""\n' if len(partes) > 1 else 'msgid ')
            for p in partes:
                f.write(f'"{p}"\n')
            # Se escapan solo las comillas dobles. Los \\n de la traduccion son
            # escapes del propio .po y tienen que pasar tal cual.
            f.write('msgstr "' + tr.replace('"', '\\"') + '"\n\n')

    subprocess.run(['msgmerge', '--quiet', '--update', '--backup=none',
                    f'--compendium={comp}', po, po.rsplit("/",1)[0] + '/navius.pot'],
                   check=True)
    os.remove(comp)
    r = subprocess.run(['msgattrib', '--untranslated', '--no-obsolete', po],
                       capture_output=True, text=True).stdout
    quedan = len([1 for m in re.finditer(r'\nmsgid ((?:"(?:[^"\\]|\\.)*"\s*)+)msgstr', r)
                  if ''.join(re.findall(r'"((?:[^"\\]|\\.)*)"', m.group(1)))])
    print(f'{po}: aplicadas {len(trad)}, quedan {quedan}')

main()
