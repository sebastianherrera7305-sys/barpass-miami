#!/usr/bin/env python3
"""Falla si alguna clave pasada a t(...) no existe en LocalizationService.

POR QUE EXISTE
`t()` devuelve la propia clave cuando no la encuentra. Eso evita un crash,
pero significa que una clave mal escrita no se nota en compilación ni en
runtime: simplemente se pinta el identificador crudo en la pantalla.

Pasó de verdad. Al extraer `CardEntry`, un find/replace de `card.name` a
`draft.entry.name` entró dentro de un string literal y dejó
`t("draft.entry.nameUpperPlaceholder")`. La pantalla de pago mostró ese
texto donde va el nombre del titular hasta que alguien lo vio y lo reportó.

Uso:  python3 BarPass-iOS/scripts/check-l10n-keys.py
"""
import glob
import os
import re
import sys

ROOT = os.path.join(os.path.dirname(__file__), "..", "BarPass")
LOC = os.path.join(ROOT, "Core", "Services", "LocalizationService.swift")

defined = set(re.findall(r'"([a-zA-Z][\w.]*)"\s*:', open(LOC).read()))

broken = []
for path in glob.glob(os.path.join(ROOT, "**", "*.swift"), recursive=True):
    if os.path.samefile(path, LOC):
        continue
    for key in re.findall(r'\bt(?:Sync)?\(\s*"([^"]+)"', open(path).read()):
        # Las claves construidas por interpolación no se pueden verificar
        # estáticamente; se saltan en vez de reportarse como falsos positivos.
        if "\\(" in key or key in defined:
            continue
        broken.append((key, os.path.relpath(path, ROOT)))

if broken:
    print(f"{len(broken)} clave(s) de localización sin definir:")
    for key, path in sorted(broken):
        print(f"  {key}  ->  {path}")
    sys.exit(1)

print(f"ok — {len(defined)} claves definidas, ninguna referencia rota")
