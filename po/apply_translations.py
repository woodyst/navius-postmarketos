#!/usr/bin/env python3
"""Aplica traducciones a un .po file.
Uso: python3 apply_translations.py <po_file> <translations.json>
El JSON es una lista de {"msgid": "...", "msgstr": "..."}.
Para entradas fuzzy: quita el flag #, fuzzy y reemplaza msgstr.
Para entradas untranslated: añade msgstr.
"""

import sys, json, re

def parse_po(text):
    """Devuelve lista de bloques {header, refs, flags, msgid, msgstr, raw_start, raw_end}"""
    lines = text.splitlines(keepends=True)
    entries = []
    i = 0
    while i < len(lines):
        # Buscar inicio de una entrada (línea de comentario o msgid)
        if not (lines[i].startswith('#') or lines[i].startswith('msgid')):
            i += 1
            continue
        start = i
        comments = []
        refs = []
        flags = []
        while i < len(lines) and lines[i].startswith('#'):
            if lines[i].startswith('#,'):
                flags = [f.strip() for f in lines[i][2:].split(',')]
            elif lines[i].startswith('#:'):
                refs.append(lines[i])
            comments.append(lines[i])
            i += 1
        if i >= len(lines) or not lines[i].startswith('msgid'):
            i += 1
            continue
        # Leer msgid
        msgid = ''
        m = re.match(r'msgid "(.*)"', lines[i].rstrip('\n'))
        if m:
            msgid = m.group(1)
        i += 1
        while i < len(lines) and lines[i].startswith('"'):
            m = re.match(r'"(.*)"', lines[i].rstrip('\n'))
            if m:
                msgid += m.group(1)
            i += 1
        # Leer msgstr
        msgstr = ''
        msgstr_start = i
        if i < len(lines) and lines[i].startswith('msgstr'):
            m = re.match(r'msgstr "(.*)"', lines[i].rstrip('\n'))
            if m:
                msgstr = m.group(1)
            i += 1
            while i < len(lines) and lines[i].startswith('"'):
                m = re.match(r'"(.*)"', lines[i].rstrip('\n'))
                if m:
                    msgstr += m.group(1)
                i += 1
        # Saltar línea en blanco
        end = i
        if i < len(lines) and lines[i].strip() == '':
            end = i + 1
        entries.append({
            'start': start,
            'end': end,
            'msgstr_start': msgstr_start,
            'flags': flags,
            'msgid': msgid,
            'msgstr': msgstr,
            'lines': lines[start:end],
        })
    return entries, lines

def encode_msgstr(s):
    """Convierte string a líneas gettext, partiendo en 72 chars si es largo."""
    s = s.replace('\\', '\\\\').replace('"', '\\"').replace('\n', '\\n')
    if len(s) <= 72:
        return [f'msgstr "{s}"\n']
    # Partir en líneas de ~72 chars
    result = ['msgstr ""\n']
    while s:
        chunk = s[:72]
        s = s[72:]
        # No terminar chunk con backslash suelto (escaparía la comilla de cierre)
        while chunk and chunk[-1] == '\\':
            s = chunk[-1] + s
            chunk = chunk[:-1]
        result.append(f'"{chunk}"\n')
    return result

def apply(po_path, translations):
    with open(po_path, 'r', encoding='utf-8') as f:
        text = f.read()

    # Normalizar los msgids del JSON: newlines reales → \n literal (2 chars)
    # porque el parser del .po devuelve \n como 2 chars sin conversión
    def norm_msgid(s):
        return s.replace('\n', '\\n')
    trans_map = {norm_msgid(t['msgid']): t['msgstr'] for t in translations}
    lines = text.splitlines(keepends=True)

    entries, _ = parse_po(text)

    # Procesar en orden inverso para no desplazar índices
    patches = []  # (start_line, end_line, new_lines)

    for entry in entries:
        if entry['msgid'] not in trans_map:
            continue
        new_msgstr = trans_map[entry['msgid']]
        # JSON \n sequences are two chars (backslash+n); decode to real newlines
        # so encode_msgstr can properly re-encode them for PO format
        new_msgstr = new_msgstr.replace('\\n', '\n')
        new_block = []
        for line in entry['lines']:
            if line.startswith('#,') and 'fuzzy' in entry['flags']:
                # Quitar fuzzy del flag
                other_flags = [f for f in entry['flags'] if f != 'fuzzy']
                if other_flags:
                    new_block.append('#, ' + ', '.join(other_flags) + '\n')
                # Si solo había fuzzy, omitir la línea de flags
                continue
            if line.startswith('msgstr') or (new_block and line.startswith('"') and
                    any(l.startswith('msgstr') for l in new_block)):
                # Saltar líneas viejas de msgstr
                continue
            new_block.append(line)
        # Insertar nuevo msgstr justo antes de la línea en blanco final
        new_msgstr_lines = encode_msgstr(new_msgstr)
        # Encontrar dónde insertar (después del msgid block)
        insert_pos = None
        for idx, line in enumerate(new_block):
            if line.startswith('msgid'):
                insert_pos = idx
        if insert_pos is not None:
            # Avanzar hasta después de las líneas de continuación del msgid
            j = insert_pos + 1
            while j < len(new_block) and new_block[j].startswith('"'):
                j += 1
            for l in reversed(new_msgstr_lines):
                new_block.insert(j, l)
        patches.append((entry['start'], entry['end'], new_block))

    # Aplicar patches en orden inverso
    patches.sort(key=lambda p: p[0], reverse=True)
    for start, end, new_lines in patches:
        lines[start:end] = new_lines

    with open(po_path, 'w', encoding='utf-8') as f:
        f.writelines(lines)

    print(f"Aplicadas {len(patches)} traducciones a {po_path}")

if __name__ == '__main__':
    if len(sys.argv) != 3:
        print("Uso: apply_translations.py <po_file> <translations.json>")
        sys.exit(1)
    with open(sys.argv[2]) as f:
        data = json.load(f)
    # Accept both a plain list and {"translations": [...]} wrapper
    if isinstance(data, dict) and 'translations' in data:
        translations = data['translations']
    else:
        translations = data
    apply(sys.argv[1], translations)
