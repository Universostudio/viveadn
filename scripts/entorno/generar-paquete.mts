// Genera el paquete de aplicación del esquema de Vive ADN: archivos SQL numerados que reproducen exactamente lo que hace montar-rama.sh, pero sin psql,
// para aplicarlos uno a uno con una herramienta que ejecuta SQL (por ejemplo el editor SQL de Supabase). Es determinista: la misma entrada da los mismos archivos.
// Uso: node scripts/entorno/generar-paquete.mts --salida <carpeta> [--esperados <archivo con líneas nombre|valor>]
// Sin --esperados, 99_verificacion.sql queda sin valores esperados (la usa generar-paquete.sh para calcularlos en una base de referencia).
import { readFileSync, readdirSync, writeFileSync, mkdirSync, rmSync } from 'node:fs'
import { createHash } from 'node:crypto'
import { join, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'

const RAIZ = join(dirname(fileURLToPath(import.meta.url)), '..', '..')
const MAX_BYTES = 60_000      // tamaño objetivo por archivo; un origen nunca se parte, así que ninguno supera el de su mayor fuente (24 KB hoy)
const LIMITE_DURO = 100_000
const args = process.argv.slice(2)
const val = (k: string) => { const i = args.indexOf(k); return i >= 0 ? args[i + 1] : undefined }
const salida = val('--salida')
if (!salida) { console.error('Falta --salida <carpeta>'); process.exit(2) }
const esperadosArchivo = val('--esperados')

const leer = (r: string) => readFileSync(join(RAIZ, 'supabase', r), 'utf8')
const sha = (t: string) => createHash('sha256').update(t).digest('hex').slice(0, 12)
const tamano = (t: string) => Buffer.byteLength(t, 'utf8')

interface Fuente { ruta: string; texto: string }
const fuentes: Fuente[] = [
  { ruta: 'schema/esquema_completo.sql', texto: leer('schema/esquema_completo.sql') },
  { ruta: 'schema/seed.sql', texto: leer('schema/seed.sql') },
  ...readdirSync(join(RAIZ, 'supabase', 'migrations')).filter(f => f.endsWith('.sql')).sort().map(f => ({ ruta: `migrations/${f}`, texto: leer(`migrations/${f}`) })),
]
for (const f of fuentes) if (/^\\/m.test(f.texto)) throw new Error(`${f.ruta} contiene una orden propia de psql: el paquete no usa psql`)
const migraciones = fuentes.filter(f => f.ruta.startsWith('migrations/')).length

// El search_path va en CADA archivo: una herramienta que ejecuta SQL puede abrir una conexión nueva por llamada
const CABECERA = `set search_path = public, extensions;\n`

// Agrupa fuentes consecutivas hasta MAX_BYTES, sin partir ninguna
const grupos: Fuente[][] = []
let actual: Fuente[] = []; let bytes = 0
for (const f of fuentes) {
  if (actual.length && bytes + tamano(f.texto) > MAX_BYTES) { grupos.push(actual); actual = []; bytes = 0 }
  actual.push(f); bytes += tamano(f.texto)
}
if (actual.length) grupos.push(actual)

const comprobacionVacia = `-- Vive ADN, paquete de aplicación 00: comprobación de base vacía. No cambia nada. Si falla, NO se sigue.
${CABECERA}do $$
begin
  if current_user <> 'postgres' then
    raise exception 'El rol es %, no postgres: los permisos por defecto de las migraciones se fijan para el rol postgres y los objetos saldrían con otros permisos. Avisar a Desarrollo.', current_user;
  end if;
  if to_regclass('public.iglesias') is not null then
    raise exception 'La base ya tiene el esquema de Vive ADN: no se toca. Usa un proyecto vacío.';
  end if;
  if to_regclass('auth.users') is null then
    raise exception 'No existe auth.users: esto no parece una base de Supabase.';
  end if;
  if not exists (select 1 from pg_namespace where nspname = 'extensions') then
    raise exception 'No existe el esquema extensions: esto no parece una base de Supabase.';
  end if;
  if exists (select 1 from pg_namespace where nspname = 'private') then
    raise exception 'Ya existe el esquema private: la base no está vacía.';
  end if;
end $$;
select 'ok: base vacía de Supabase, rol postgres' as resultado;
`

mkdirSync(salida, { recursive: true })
for (const f of readdirSync(salida)) if (/^\d\d_.*\.sql$/.test(f) || f === 'INDICE.md') rmSync(join(salida, f))
const escribir = (nombre: string, texto: string) => { if (tamano(texto) > LIMITE_DURO) throw new Error(`${nombre} supera ${LIMITE_DURO} bytes`); writeFileSync(join(salida, nombre), texto) }
const pad = (n: number) => String(n).padStart(2, '0')

const indice: { archivo: string; bytes: number; contenido: string; privilegios: string }[] = []
escribir('00_comprobar_base_vacia.sql', comprobacionVacia)
indice.push({ archivo: '00_comprobar_base_vacia.sql', bytes: tamano(comprobacionVacia), contenido: 'Comprobación de base vacía (solo lectura)', privilegios: 'Ninguno' })

const PRIV: [RegExp, string][] = [
  [/alter default privileges for role postgres/i, 'ALTER DEFAULT PRIVILEGES FOR ROLE postgres (exige ser postgres o miembro)'],
  [/storage\.objects/i, 'Políticas sobre storage.objects (propiedad de supabase_storage_admin)'],
  [/storage\.buckets/i, 'INSERT en storage.buckets'],
  [/create extension/i, 'CREATE EXTENSION (ya existen: no hace nada)'],
  [/references auth\.users/i, 'Claves foráneas a auth.users (exige REFERENCES sobre esa tabla)'],
  [/create schema/i, 'CREATE SCHEMA private'],
]
grupos.forEach((g, i) => {
  const n = i + 1
  const nombre = `${pad(n)}_aplicar_${pad(n)}.sql`
  let texto = `-- Vive ADN, paquete de aplicación ${pad(n)} de ${pad(grupos.length)}. Aplicar en orden y detenerse en el primer error.\n${CABECERA}`
  const priv = new Set<string>()
  for (const f of g) {
    texto += `\n-- ===== ${f.ruta} (sha256 ${sha(f.texto)}) =====\n${f.texto.endsWith('\n') ? f.texto : f.texto + '\n'}`
    for (const [re, desc] of PRIV) if (re.test(f.texto)) priv.add(desc)
  }
  escribir(nombre, texto)
  indice.push({ archivo: nombre, bytes: tamano(texto), contenido: g.map(f => f.ruta.replace(/^migrations\//, '').replace(/\.sql$/, '')).join(', '), privilegios: priv.size ? [...priv].join('; ') : 'Ninguno especial' })
})

// Verificación: la consulta de huellas con los valores esperados incrustados
const huellas = readFileSync(join(RAIZ, 'scripts', 'entorno', 'huellas.sql'), 'utf8').trim().replace(/;$/, '')
let esperados: [string, string][] = []
if (esperadosArchivo) {
  esperados = readFileSync(esperadosArchivo, 'utf8').split('\n').filter(Boolean).map(l => { const i = l.indexOf('|'); return [l.slice(0, i), l.slice(i + 1)] as [string, string] })
  const q = (s: string) => `'${s.replace(/'/g, "''")}'`
  const verif = `-- Vive ADN, paquete de aplicación 99: verificación. Solo lee. Cada fila compara una huella del esquema con el valor esperado de la base de referencia.
-- El resultado correcto es TODAS las filas con ok = true. Las dos primeras filas son recuentos: 47 tablas y 107 funciones.
set search_path = pg_catalog;
with obtenido(nombre, valor) as (
${huellas}
), esperado(nombre, valor) as (values
${esperados.map(([n, v]) => `  (${q(n)}, ${q(v)})`).join(',\n')}
)
select e.nombre, o.valor as obtenido, e.valor as esperado, (o.valor is not distinct from e.valor) as ok
from esperado e left join obtenido o using (nombre)
union all
select 'zz_todo_ok', null, null, bool_and(o.valor is not distinct from e.valor) from esperado e left join obtenido o using (nombre)
order by 1;
`
  escribir('99_verificacion.sql', verif)
  indice.push({ archivo: '99_verificacion.sql', bytes: tamano(verif), contenido: 'Verificación del esquema (solo lectura)', privilegios: 'Lectura del catálogo y de storage.buckets' })
} else {
  writeFileSync(join(salida, '99_verificacion.sql'), '-- (sin valores esperados todavía)\n')
}

const esp = (n: string) => esperados.find(e => e[0] === n)?.[1] ?? '?'
const md = `# Paquete de aplicación del esquema de Vive ADN (proyecto de pruebas)

Generado por \`scripts/entorno/generar-paquete.sh\`. Reproduce \`scripts/entorno/montar-rama.sh\` sin psql: esquema base, catálogo y ${migraciones} migraciones, en archivos SQL numerados.

**Reglas.** Solo sobre un proyecto de pruebas VACÍO. Aplicar los archivos en orden con una herramienta que ejecute SQL; **detenerse en el primer error** y avisar a Desarrollo con el texto del error. No hay reintento seguro: un archivo que falla puede dejar el proyecto a medias, y entonces se recrea el proyecto vacío. Cada archivo empieza con su propio \`set search_path\`, así que no depende de la conexión. Los archivos no contienen claves ni datos de personas.

## Orden

| Archivo | Bytes | Contenido | Privilegios que exige |
| --- | --- | --- | --- |
${indice.map(i => `| \`${i.archivo}\` | ${i.bytes.toLocaleString('es-ES')} | ${i.contenido} | ${i.privilegios} |`).join('\n')}

## Resultado esperado

- \`00\`: una fila \`ok: base vacía de Supabase, rol postgres\`. Si el rol no es \`postgres\`, falla a propósito (las migraciones fijan permisos por defecto para ese rol).
- \`01\` a \`${pad(grupos.length)}\`: sin filas de error. Los avisos \`NOTICE\` de objetos que no existían son normales.
- \`99\`: todas las filas con \`ok = true\` y la última, \`zz_todo_ok\`, en \`true\`. Valores de referencia: ${esp('a01_tablas_en_public')} tablas en \`public\`, ${esp('a02_funciones_en_public_y_private')} funciones en \`public\` y \`private\`, ${esp('d01_filas_de_permisos')} permisos, ${esp('d02_filas_de_plan_modulos')} filas de plan_modulos, ${esp('d03_filas_de_planes')} planes, 0 iglesias y 2 cubos de archivos.

## Qué puede fallar por privilegios (no se ha podido probar en Supabase real) [NV]

- \`ALTER DEFAULT PRIVILEGES FOR ROLE postgres\` (migraciones \`20261025080000\` y \`20261027090000\`): exige ejecutar como \`postgres\` o como miembro de ese rol. Por eso el archivo 00 lo comprueba.
- Políticas e inserción de cubos en \`storage\` (\`20261105222115_archivos_por_iglesia\`): \`storage.objects\` pertenece a \`supabase_storage_admin\`. El rol \`postgres\` suele poder crear políticas ahí, pero hoy no se ha comprobado. Si falla, el error será \`must be owner of table objects\`; avisar a Desarrollo.
- Claves foráneas a \`auth.users\` (esquema base): exigen REFERENCES sobre esa tabla; \`postgres\` lo tiene en Supabase [NV].
- \`CREATE EXTENSION IF NOT EXISTS\`: las extensiones ya existen, así que no hace nada.

## Comprobación hecha en local

En una base local vacía con un esquema \`auth\` mínimo, los archivos aplicados con psql tal cual (sin variables de sesión) dan una verificación con todas las filas \`ok\`, y un \`pg_dump\` del esquema idéntico al de \`montar-rama.sh\` (\`supabase/tests/paquete_pruebas.sh\`). Si el proyecto real da otro valor en alguna fila, la letra de la fila dice dónde mirar: \`a\` recuentos, \`b\` estructura (tablas, columnas, funciones con su código, restricciones, índices, políticas, disparadores), \`c\` permisos, \`d\` datos de catálogo.
`
writeFileSync(join(salida, 'INDICE.md'), md)
console.log(`Paquete en ${salida}: ${indice.length} archivos, ${grupos.length} de aplicación, ${migraciones} migraciones`)
