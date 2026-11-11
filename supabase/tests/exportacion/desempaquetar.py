#!/usr/bin/env python3
"""Convierte la respuesta de adn_exportar_paquete en los archivos de la exportacion:
manifest.json, datos.json y csv/<tabla>.csv. Comprueba que el md5 de cada CSV es el del manifiesto.
Uso: desempaquetar.py paquete.json carpeta_de_salida"""
import hashlib, json, os, sys

origen, destino = sys.argv[1], sys.argv[2]
with open(origen, encoding='utf-8') as f:
    p = json.load(f)
os.makedirs(os.path.join(destino, 'csv'), exist_ok=True)

def escribir(ruta, texto):
    # newline='' conserva los CRLF del CSV tal como los genero la base
    with open(os.path.join(destino, ruta), 'w', encoding='utf-8', newline='') as f:
        f.write(texto)

escribir('manifest.json', json.dumps(p['manifiesto'], ensure_ascii=False, indent=2))
escribir('datos.json', json.dumps({k: p[k] for k in ('formato', 'exportado_en', 'iglesia', 'tablas')}, ensure_ascii=False, indent=2))
for t in p['manifiesto']['tablas']:
    texto = p['csv'][t['nombre']]
    md5 = hashlib.md5(texto.encode('utf-8')).hexdigest()
    if md5 != t['md5_csv']:
        sys.exit(f"FALLO: el md5 de {t['nombre']}.csv no coincide con el manifiesto")
    escribir(t['archivo_csv'], texto)
print(f"OK: {len(p['manifiesto']['tablas'])} CSV con el md5 del manifiesto")
