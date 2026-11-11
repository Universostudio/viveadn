#!/usr/bin/env python3
"""Genera, a partir del manifiesto, el script psql que carga los CSV en una base vacia.
Es el procedimiento de restauracion de referencia: sin disparadores (como pg_restore --disable-triggers),
en el orden de carga del manifiesto, y regenerando los secretos que la exportacion omite.
Uso: generar_carga_csv.py carpeta_de_la_exportacion > carga.sql"""
import json, os, sys

carpeta = sys.argv[1]
m = json.load(open(os.path.join(carpeta, 'manifest.json'), encoding='utf-8'))
print('\\set ON_ERROR_STOP on')
print('\\i tests/exportacion/cargar_comun.sql')
print('begin;')
print('set local session_replication_role = replica;')
for t in sorted(m['tablas'], key=lambda t: (t['orden_carga'], t['nombre'])):
    n = t['nombre']
    cols = ', '.join('"%s"' % c['nombre'] for c in t['columnas'])
    # Columnas omitidas que la tabla exige: se aflojan para cargar y se rellenan con un valor aleatorio nuevo
    print(f"do $$ begin perform pg_temp.preparar('{n}', array[{', '.join(repr(o) for o in t['omitidas'])}]::text[]); end $$;")
    ruta = os.path.join(carpeta, t['archivo_csv'])
    print(f"\\copy public.\"{n}\" ({cols}) from '{ruta}' with (format csv, header true, encoding 'UTF8')")
    print(f"do $$ begin perform pg_temp.rellenar('{n}'); end $$;")
print('do $$ begin perform pg_temp.usuarios_de_acceso(); end $$;')
print('do $$ begin perform pg_temp.secuencias(); end $$;')
print('commit;')
