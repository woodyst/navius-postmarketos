#!/usr/bin/env python3
"""Genera iconos PNG para cada categoría de alerta comunitaria.
Salida: assets/alertas/<categoria>.png  (128x128 RGBA)
Uso:    python3 assets/gen_alerta_icons.py
"""
import os
from PIL import Image, ImageDraw, ImageFont

FONT_PATH  = '/usr/share/fonts/truetype/noto/NotoColorEmoji.ttf'
FONT_SIZE  = 109    # único tamaño disponible en el strike bitmap
ICON_SIZE  = 144    # 136px emoji + 8px margen
RADIUS     = 66

CATEGORIES = {
    "trafico":           ("🚗",  "#E65100"),
    "policia":           ("👮",  "#1565C0"),
    "accidente":         ("💥",  "#C62828"),
    "peligro":           ("⚠",   "#F9A825"),   # sin variation selector
    "carretera_cortada": ("🚧",  "#B71C1C"),
    "carril_bloqueado":  ("⛔",  "#37474F"),
    "error_mapa":        ("🗺",  "#00695C"),    # sin variation selector
    "mal_tiempo":        ("🌧",  "#283593"),    # sin variation selector
    "asistencia":        ("🆘",  "#2E7D32"),
    "lugar":             ("📍",  "#6A1B9A"),
}

def hex_rgba(h, a=220):
    h = h.lstrip('#')
    return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16), a)

out_dir = os.path.join(os.path.dirname(__file__), 'alertas')
os.makedirs(out_dir, exist_ok=True)

font = ImageFont.truetype(FONT_PATH, FONT_SIZE)

for cat, (emoji, color) in CATEGORIES.items():
    img  = Image.new('RGBA', (ICON_SIZE, ICON_SIZE), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    cx = cy = ICON_SIZE // 2

    bbox = draw.textbbox((0, 0), emoji, font=font, embedded_color=True)
    tw = bbox[2] - bbox[0]
    th = bbox[3] - bbox[1]
    x  = cx - tw // 2 - bbox[0]
    y  = cy - th // 2 - bbox[1]
    draw.text((x, y), emoji, font=font, embedded_color=True)

    path = os.path.join(out_dir, f'{cat}.png')
    img.save(path)
    print(f'  {cat}.png  ({tw}x{th} emoji)')

print(f'\n{len(CATEGORIES)} iconos generados en {out_dir}/')
