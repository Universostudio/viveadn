// Compila el PAQUETE DE TRASPASO: lo que hay que aplicar sobre viveadn-saas (el proyecto real, que tiene las migraciones hasta BASE) para llevarlo al estado
// de la rama. Solo añade. Parte de las migraciones del repositorio (no de ningún proyecto de pruebas) y:
//  * quita los «drop policy/trigger if exists» que solo eran guardas de objetos que no existen todavía;
//  * cuando una migración sustituye un objeto creado antes en la misma cadena, deja solo la definición final;
//  * lo que sí reemplaza algo que ya existe en el real (la firma antigua de registrar_checkin) va aparte, en DROP_HAROLD, para aplicarlo a mano;
//  * sustituye la limpieza de asistencias duplicadas (un DELETE) por una comprobación que falla si hubiera duplicados (el real tiene 0).
// Ningún archivo de aplicación contiene drop, delete ni truncate. La equivalencia con la cadena completa la demuestra scripts/entorno/generar-traspaso.sh.
// Uso: node scripts/entorno/generar-traspaso.mts --salida <carpeta> [--esperados <archivo nombre|valor>]
import { readFileSync, readdirSync, writeFileSync, mkdirSync, rmSync, existsSync } from 'node:fs'
import { createHash } from 'node:crypto'
import { join, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'
import { clasificar, partir, quitarRestriccionEnLinea, type Clase } from './sql.mts'

const RAIZ = join(dirname(fileURLToPath(import.meta.url)), '..', '..')
const BASE = '20261106011008'                       // última migración que el real ya tiene registrada (certificados_formacion)
const MAX_BYTES = 60_000, LIMITE_DURO = 100_000
const args = process.argv.slice(2)
const val = (k: string) => { const i = args.indexOf(k); return i >= 0 ? args[i + 1] : undefined }
const salida = val('--salida'); if (!salida) { console.error('Falta --salida <carpeta>'); process.exit(2) }
const esperadosArchivo = val('--esperados')
const leer = (r: string) => readFileSync(join(RAIZ, r), 'utf8')
const sha = (t: string | Buffer) => createHash('sha256').update(t).digest('hex')
const bytes = (t: string) => Buffer.byteLength(t, 'utf8')
const pad = (n: number) => String(n).padStart(2, '0')

interface S { texto: string; limpio: string; clase: Clase; fuera?: string; reemplazada?: boolean }
interface M { version: string; nombre: string; origen: string; stmts: S[] }

const dirMig = join(RAIZ, 'supabase', 'migrations')
const todas = readdirSync(dirMig).filter(f => f.endsWith('.sql')).sort()
const mkM = (f: string): M => ({ version: f.slice(0, 14), nombre: f.replace(/\.sql$/, ''), origen: readFileSync(join(dirMig, f), 'utf8'), stmts: [] })
const baseMigs = todas.filter(f => f.slice(0, 14) <= BASE).map(mkM)
const cadena = todas.filter(f => f.slice(0, 14) > BASE).map(mkM)
if (!cadena.length) throw new Error('No hay migraciones posteriores a la base')
for (const m of cadena) {
  if (/^\\/m.test(m.origen)) throw new Error(`${m.nombre} contiene una orden propia de psql`)
  m.stmts = partir(m.origen).map(s => ({ ...s, clase: clasificar(s.limpio) }))
}

// Lo que ya existe en el real (base): políticas, disparadores y funciones creados por el esquema base y las migraciones hasta BASE
const textoBase = [leer('supabase/schema/esquema_completo.sql'), leer('supabase/schema/seed.sql'), ...baseMigs.map(m => m.origen)]
const enBase = { politica: new Set<string>(), disparador: new Set<string>(), funcion: new Set<string>(), tabla: new Set<string>() }
for (const t of textoBase) for (const s of partir(t)) {
  const c = clasificar(s.limpio)
  if (c.tipo === 'crear_politica') enBase.politica.add(`${c.nombre}@${c.tabla}`)
  if (c.tipo === 'crear_disparador') enBase.disparador.add(`${c.nombre}@${c.tabla}`)
  if (c.tipo === 'crear_funcion') enBase.funcion.add(c.firma)
  if (c.tipo === 'crear_tabla') enBase.tabla.add(c.tabla)
}

const posiciones: [M, S][] = cadena.flatMap(m => m.stmts.map(s => [m, s] as [M, S]))
const dropHarold: { firma: string; texto: string; migracion: string; motivo: string }[] = []
const cambios: string[] = []
const anotar = (m: M, s: S, motivo: string) => { s.fuera = motivo; cambios.push(`${m.nombre}: ${motivo} — ${s.limpio.slice(0, 110)}`) }

for (let k = 0; k < posiciones.length; k++) {
  const [m, s] = posiciones[k]!
  if (s.fuera) continue
  const c = s.clase
  if (c.tipo === 'borrar_politica' || c.tipo === 'borrar_disparador') {
    const crea = c.tipo === 'borrar_politica' ? 'crear_politica' : 'crear_disparador'
    const previas = posiciones.slice(0, k).filter(([, p]) => !p.fuera && p.clase.tipo === crea && (p.clase as { nombre: string; tabla: string }).nombre === c.nombre && (p.clase as { tabla: string }).tabla === c.tabla)
    if (previas.length) { for (const [pm, p] of previas) anotar(pm, p, 'sustituida más abajo en la cadena (queda solo la definición final)'); anotar(m, s, 'guarda de reemplazo, ya sin objeto previo') }
    else if ((c.tipo === 'borrar_politica' ? enBase.politica : enBase.disparador).has(`${c.nombre}@${c.tabla}`)) throw new Error(`${m.nombre} reemplaza ${c.nombre} que ya existe en el real: va a DROP_HAROLD, revisar a mano`)
    else anotar(m, s, 'guarda de un objeto que aún no existe')
  } else if (c.tipo === 'borrar_funcion') {
    const previas = posiciones.slice(0, k).filter(([, p]) => !p.fuera && p.clase.tipo === 'crear_funcion' && p.clase.firma === c.firma)
    if (previas.length) {
      const primera = posiciones.indexOf(previas[0]!)
      for (const [pm, p] of previas) anotar(pm, p, 'firma antigua sustituida más abajo (queda solo la final)')
      for (const [pm, p] of posiciones.slice(primera, k)) if (!p.fuera && p.clase.tipo === 'permiso_funcion' && p.clase.firmas.includes(c.firma)) {
        if (p.clase.firmas.length > 1) throw new Error(`${pm.nombre}: un permiso agrupa varias funciones y una es ${c.firma}; separar a mano`)
        anotar(pm, p, 'permiso de una firma antigua')
      }
      anotar(m, s, 'baja de una firma creada en esta misma cadena')
    } else if (enBase.funcion.has(c.firma)) { dropHarold.push({ firma: c.firma, texto: s.texto, migracion: m.nombre, motivo: 'firma que el real ya tiene' }); anotar(m, s, 'pasa a DROP_HAROLD (la firma ya existe en el real)') }
    else if (c.siExiste) anotar(m, s, 'baja «if exists» de una firma que no existe en el real ni en la cadena')
    else throw new Error(`${m.nombre}: baja de ${c.firma}, que no existe ni en el real ni en la cadena`)
  } else if (c.tipo === 'borrar_restriccion') {
    let hecho = false
    for (const [pm, p] of posiciones.slice(0, k)) {
      if (p.fuera) continue
      if (p.clase.tipo === 'anadir_restriccion' && p.clase.tabla === c.tabla && p.clase.nombre === c.nombre) { anotar(pm, p, 'restricción sustituida más abajo (queda la final)'); hecho = true }
      else if (p.clase.tipo === 'crear_tabla' && p.clase.tabla === c.tabla) {
        const nuevo = quitarRestriccionEnLinea(p.texto, c.tabla, c.nombre)
        if (nuevo !== null) { p.texto = nuevo; p.limpio = partir(nuevo)[0]!.limpio; cambios.push(`${pm.nombre}: se quita la restricción en línea ${c.nombre} de ${c.tabla} (la redefine ${m.nombre})`); hecho = true }
      }
    }
    if (hecho) anotar(m, s, 'baja de una restricción creada en esta misma cadena')
    else if (textoBase.some(t => t.includes(c.nombre))) throw new Error(`${m.nombre} quita la restricción ${c.nombre} de ${c.tabla}, que ya existe en el real: va a DROP_HAROLD, revisar a mano`)
    else if (c.siExiste) anotar(m, s, 'guarda de una restricción que aún no existe')
    else throw new Error(`${m.nombre}: baja de la restricción ${c.nombre} de ${c.tabla}, que no se encuentra en la cadena`)
  } else if (/^do\s*\$/i.test(s.limpio) && /delete\s+from\s+public\.asistencias/i.test(s.limpio)) {
    s.fuera = 'limpieza de duplicados (DELETE) sustituida por una comprobación'
    cambios.push(`${m.nombre}: limpieza de asistencias duplicadas (DELETE) sustituida por una comprobación que falla si hay duplicados (el real tiene 0)`)
    s.texto = `\n-- Comprobación en lugar de la limpieza de asistencias duplicadas de la migración original: el real tiene 0 asistencias duplicadas, así que no hay nada que archivar.\n` +
      `-- Si algún día hubiera duplicados, esto falla y hay que archivarlos a mano antes de crear el índice único.\n` +
      `do $$ begin\n  if exists (select 1 from public.asistencias group by casa_oracion_id, miembro_id, fecha having count(*) > 1) then\n    raise exception 'Hay asistencias duplicadas: archivarlas a mano antes de crear el indice unico';\n  end if;\nend $$;\n`
    s.limpio = partir(s.texto)[0]!.limpio
    s.fuera = undefined
  }
}

// Comentarios de línea completa: sin las palabras que una herramienta cautelosa podría tomar por sentencias
const limpiarComentarios = (t: string) => t.split('\n').map(l => /^\s*--/.test(l) ? l.replace(/\bdrop\b/gi, 'quitar').replace(/\bdelete\b/gi, 'borrar').replace(/\btruncate\b/gi, 'vaciar') : l).join('\n')
const compilar = (m: M) => m.stmts.filter(s => !s.fuera).map(s => limpiarComentarios(s.texto)).join('')

// Barrido final: ni una palabra destructiva en lo que se aplica
const PROHIBIDO = /\bdrop\b|\bdelete\s+from\b|\btruncate\b/i
const restos: string[] = []
for (const m of cadena) for (const s of m.stmts) if (!s.fuera && PROHIBIDO.test(s.limpio) && !/^do\s*\$\s*begin\s+if exists \(select 1 from public\.asistencias/i.test(s.limpio)) restos.push(`${m.nombre}: ${s.limpio.slice(0, 200)}`)
if (restos.length) { console.error(`Quedan ${restos.length} órdenes destructivas sin tratar:\n${restos.join('\n')}`); process.exit(1) }

const CABECERA = `set search_path = public, extensions;\n`
mkdirSync(salida, { recursive: true })
for (const f of readdirSync(salida)) if (/^\d\d_.*\.sql$/.test(f) || ['INDICE.md', 'HUELLAS.sha256', 'funciones.json', 'sembrar_iglesias_prueba.sql', 'CAMBIOS_SOBRE_LAS_MIGRACIONES.md'].includes(f)) rmSync(join(salida, f))
rmSync(join(salida, 'reversion'), { recursive: true, force: true })
rmSync(join(salida, 'despues'), { recursive: true, force: true })

// Reparto en TRAMOS pequeños (como máximo 20.000 bytes por archivo), partiendo entre sentencias, nunca dentro de una. Cada tramo se puede aplicar solo y repetir sin error:
// va dentro de un bloque que se salta si su objeto centinela (el último objeto nuevo que crea) ya existe, y exige que el tramo anterior esté aplicado.
const LIMITE_ARCHIVO = 20_000, CUERPO_MAX = 16_000, CUERPO_DURO = 18_800
interface Trozo { texto: string; clave?: string; comprobar?: string }
const claveDe = (c: Clase): { clave: string; comprobar: string } | null => {
  if (c.tipo === 'crear_tabla') return { clave: `t:${c.tabla}`, comprobar: `to_regclass('${c.tabla}') is not null` }
  if (c.tipo === 'crear_funcion') return { clave: `f:${c.firma}`, comprobar: `to_regprocedure('${c.firma}') is not null` }
  if (c.tipo === 'crear_politica') { const [e, t] = c.tabla.includes('.') ? c.tabla.split('.') : ['public', c.tabla]; return { clave: `p:${c.nombre}@${c.tabla}`, comprobar: `exists (select 1 from pg_policies where schemaname = '${e}' and tablename = '${t}' and policyname = '${c.nombre}')` } }
  if (c.tipo === 'crear_disparador') return { clave: `g:${c.nombre}@${c.tabla}`, comprobar: `exists (select 1 from pg_trigger where tgname = '${c.nombre}' and tgrelid = '${c.tabla}'::regclass and not tgisinternal)` }
  return null
}
const creadas = new Set<string>([...enBase.tabla].map(t => `t:${t}`).concat([...enBase.funcion].map(f => `f:${f}`), [...enBase.politica].map(x => `p:${x}`), [...enBase.disparador].map(x => `g:${x}`)))
const trozos: Trozo[] = []
for (const m of cadena) {
  const c0 = compilar(m)
  let primero = true
  for (const st of m.stmts.filter(x => !x.fuera)) {
    const cab = primero ? `\n-- ===== ${m.nombre} (origen sha256 ${sha(m.origen).slice(0, 12)}, compilado sha256 ${sha(c0).slice(0, 12)}) =====\n` : ''
    primero = false
    const k = claveDe(st.clase)
    let nueva: { clave: string; comprobar: string } | null = null
    if (k && !creadas.has(k.clave)) { creadas.add(k.clave); nueva = k }
    trozos.push({ texto: cab + limpiarComentarios(st.texto), ...(nueva ?? {}) })
  }
}
const tramos: Trozo[][] = []
{ let act: Trozo[] = [], tam = 0
  const tieneCentinela = (l: Trozo[]) => l.some(x => x.comprobar)
  for (const t of trozos) {
    const b = bytes(t.texto); if (b > CUERPO_MAX) throw new Error(`Una sentencia pesa ${b} bytes y no cabe en un tramo`)
    // Un tramo se cierra al llegar al tamaño máximo, pero solo si ya tiene un objeto nuevo que sirva de centinela; si no, sigue hasta el tope duro
    if (act.length && tam + b > CUERPO_MAX && (tieneCentinela(act) || tam + b > CUERPO_DURO)) { tramos.push(act); act = []; tam = 0 }
    act.push(t); tam += b
  }
  if (act.length) tramos.push(act) }
const centinela = tramos.map((t, i) => { const nuevos = t.filter(x => x.comprobar); if (!nuevos.length) throw new Error(`El tramo ${i + 1} no crea ningún objeto nuevo que sirva de centinela: reordenar o fusionar`); return nuevos[nuevos.length - 1]!.comprobar! })
const hayDrop = dropHarold.length > 0
const TOTAL = 1 + tramos.length + (hayDrop ? 1 : 0) + 1 + 1     // comprobación, aplicación, DROP_HAROLD, verificación, registro de migraciones
const encabezado = (n: number, titulo: string) => `-- Vive ADN, traspaso al proyecto real, archivo ${n} de ${TOTAL}: ${titulo}\n`
const escribir = (nombre: string, texto: string) => { if (bytes(texto) > 20_000) throw new Error(`${nombre} supera 20.000 bytes`); writeFileSync(join(salida, nombre), texto) }
const indice: { archivo: string; n: number; bytes: number; sha: string; contenido: string }[] = []
const registrar = (archivo: string, n: number, texto: string, contenido: string) => { escribir(archivo, texto); indice.push({ archivo, n, bytes: bytes(texto), sha: sha(texto), contenido }) }

const comprobacion = `${encabezado(1, 'comprobación previa (solo lee, no cambia nada). Si falla, NO se sigue.')}${CABECERA}do $$
begin
  if current_user <> 'postgres' then raise exception 'El rol es %, no postgres: las migraciones fijan permisos por defecto para postgres.', current_user; end if;
  if to_regclass('auth.users') is null then raise exception 'No existe auth.users: esto no parece una base de Supabase.'; end if;
  if to_regclass('public.iglesias') is null or to_regclass('public.certificados') is null or to_regprocedure('public.registrar_checkin(text, text, text, text, text, text)') is null then
    raise exception 'Esta base no está en el estado esperado del real (hasta ${BASE}): faltan objetos base. No se sigue.'; end if;
  if to_regclass('public.adn_mensajes') is not null or to_regclass('public.adn_seguimiento_metodos') is not null then
    raise exception 'Esta base ya tiene objetos del traspaso: no se vuelve a aplicar.'; end if;
  if (select count(*) from pg_tables where schemaname = 'public') <> 33 then
    raise exception 'El real debía tener 33 tablas públicas y tiene %: revisar antes de seguir.', (select count(*) from pg_tables where schemaname = 'public'); end if;
end $$;
select 'ok: el real está en el estado esperado, listo para el traspaso' as resultado, (select count(*) from public.iglesias) as iglesias, (select count(*) from auth.users) as usuarios;
`
registrar('00_comprobar_estado_real.sql', 1, comprobacion, 'Comprobación previa (solo lectura)')

tramos.forEach((t, i) => {
  const n = i + 2, N = tramos.length
  const cuerpo = t.map(x => x.texto).join('')
  if (cuerpo.includes('$cuerpo$') || cuerpo.includes('$tramo$')) throw new Error(`El tramo ${i + 1} contiene una etiqueta reservada`)
  const previo = i > 0 ? `  if not (${centinela[i - 1]}) then raise exception 'Falta aplicar antes el tramo ${i} de ${N}: no se sigue.'; end if;\n` : ''
  const texto = `${encabezado(n, `tramo ${i + 1} de ${N}. Se puede aplicar solo y repetir sin error: si ya está aplicado, no hace nada. Detenerse en el primer error.`)}${CABECERA}do $tramo$
begin
  -- Ya aplicado: el último objeto nuevo que crea este tramo existe. Las sentencias van en un solo bloque, así que o se aplican todas o ninguna.
  if ${centinela[i]} then raise notice 'Tramo ${i + 1} de ${N} ya aplicado: no se repite'; return; end if;
${previo}  execute $cuerpo$
${cuerpo}
$cuerpo$;
end $tramo$;
select 'ok: tramo ${i + 1} de ${N} aplicado' as resultado, (${centinela[i]}) as comprobado;
`
  if (bytes(texto) > LIMITE_ARCHIVO) throw new Error(`El tramo ${i + 1} pesa ${bytes(texto)} bytes (máximo ${LIMITE_ARCHIVO})`)
  registrar(`${pad(i + 1)}_tramo_${pad(i + 1)}_de_${pad(N)}.sql`, n, texto, `tramo ${i + 1} de ${N}: ${[...new Set(cuerpo.match(/-- ===== (\S+)/g) ?? [])].map(x => x.slice(9).replace(/^\d+_/, '')).join(', ')}`)
})

let n = tramos.length + 2
if (hayDrop) {
  const t = `${encabezado(n, 'DROP_HAROLD: lo único destructivo. Se aplica a mano, DESPUÉS de todos los de aplicación y ANTES de la verificación.')}${CABECERA}` +
    `-- Quita la firma antigua de public.registrar_checkin (6 parámetros) que el real tiene desde la migración del check-in QR y que la migración nueva sustituye por la de 10 parámetros.\n` +
    `-- No toca datos: es solo la definición de una función. Mientras no se aplique, conviven las dos firmas y una llamada con exactamente 6 argumentos sería ambigua;\n` +
    `-- por eso hay que aplicarlo antes de redesplegar checkin-evento.\n` +
    dropHarold.map(d => `\n-- (${d.migracion}: ${d.motivo}). «if exists» para poder repetirlo sin error.\n${d.texto.trim().replace(/(^|\n)drop function (if exists )?/i, '$1drop function if exists ')}\n`).join('')
  registrar(`${pad(n - 1)}_DROP_HAROLD_firma_antigua_registrar_checkin.sql`, n, t, 'DROP_HAROLD: quita la firma antigua de registrar_checkin (única orden destructiva)')
  n++
}

// Verificación: las huellas de la cadena completa, sin las que dependen de los datos del real
const huellas = readFileSync(join(RAIZ, 'scripts', 'entorno', 'huellas.sql'), 'utf8').trim().replace(/;$/, '')
let verif = '-- (sin valores esperados todavía)\n'
if (esperadosArchivo) {
  const esperados = readFileSync(esperadosArchivo, 'utf8').split('\n').filter(Boolean).map(l => { const i = l.indexOf('|'); return [l.slice(0, i), l.slice(i + 1)] as [string, string] }).filter(([nombre]) => nombre !== 'd04_iglesias_vacia')
  const q = (s: string) => `'${s.replace(/'/g, "''")}'`
  verif = `${encabezado(n, 'verificación (solo lee). Resultado correcto: TODAS las filas con ok = true y zz_todo_ok = true.')}-- Cada fila compara una huella del esquema con el valor de la cadena completa montada en local. No mira los datos del real (iglesias, usuarios).
set search_path = pg_catalog;
with obtenido(nombre, valor) as (
${huellas}
), esperado(nombre, valor) as (values
${esperados.map(([a, b]) => `  (${q(a)}, ${q(b)})`).join(',\n')}
)
select e.nombre, o.valor as obtenido, e.valor as esperado, (o.valor is not distinct from e.valor) as ok
from esperado e left join obtenido o using (nombre)
union all
select 'zz_todo_ok', null, null, bool_and(o.valor is not distinct from e.valor) from esperado e left join obtenido o using (nombre)
order by 1;
`
}
registrar(`${pad(n - 1)}_verificacion.sql`, n, verif, 'Verificación del esquema (solo lectura)')
n++
const registro = `${encabezado(n, 'registro de las migraciones en supabase_migrations. PASO APARTE: solo después de que la verificación salga toda en verde.')}-- Anota las ${cadena.length} versiones del repositorio para que el historial del proyecto real coincida con el de la rama. Solo añade filas (created_by queda vacío) y se puede repetir.
insert into supabase_migrations.schema_migrations (version, name) values
${cadena.map(m => `  ('${m.version}', '${m.nombre.slice(15)}')`).join(',\n')}
on conflict (version) do nothing;
select count(*) as migraciones_registradas from supabase_migrations.schema_migrations;
`
registrar(`${pad(n - 1)}_registro_migraciones.sql`, n, registro, 'Registro de las migraciones en supabase_migrations (paso aparte, tras verificar)')

// Reversión: los .down.sql de la cadena, de la última a la primera, sin las órdenes propias de psql. Solo si Gerencia lo ordena.
const downs = cadena.map(m => ({ m, t: readFileSync(join(RAIZ, 'supabase', 'reversiones', `${m.nombre}.down.sql`), 'utf8').replace(/^\\set ON_ERROR_STOP on\s*$/m, '').trim() + '\n' })).reverse()
mkdirSync(join(salida, 'reversion'), { recursive: true })
const gr: typeof downs[] = []; let ar: typeof downs = [], tr = 0
for (const d of downs) { if (ar.length && tr + bytes(d.t) > 17_000) { gr.push(ar); ar = []; tr = 0 } ar.push(d); tr += bytes(d.t) }
if (ar.length) gr.push(ar)
const reversionIndice: { archivo: string; bytes: number; sha: string; contenido: string }[] = []
gr.forEach((g, i) => {
  const t = `-- Vive ADN, REVERSIÓN del traspaso, archivo ${i + 1} de ${gr.length}. Solo si Gerencia lo ordena. Aplicar en orden y detenerse en el primer error. Deja el real como estaba antes del traspaso (salvo los datos que se hayan creado después).\n${CABECERA}` +
    g.map(d => `\n-- ===== reversión de ${d.m.nombre} =====\n${d.t}`).join('')
  const nombre = `R${pad(i + 1)}_revertir_${pad(i + 1)}_de_${pad(gr.length)}.sql`
  escribir(`reversion/${nombre}`, t); reversionIndice.push({ archivo: `reversion/${nombre}`, bytes: bytes(t), sha: sha(t), contenido: g.map(d => d.m.nombre.replace(/^\d+_/, '')).join(', ') })
})

// Siembra de iglesias de demostración (idempotente, es_demo = true): se copia tal cual con su huella de origen
const siembra = leer('supabase/seeds/sembrar_iglesias_prueba.sql')
if (/^\\/m.test(siembra)) throw new Error('La siembra contiene órdenes de psql')
const POR_DEFECTO = "select set_config('siembra.mega', 'casa-reino', false)"
if (!siembra.includes(POR_DEFECTO)) throw new Error('La siembra ya no tiene el ajuste siembra.mega esperado')
// En el real, casa-reino es una iglesia REAL (no demostración): la siembra se niega a tocarla. La mega de demostración va con otra dirección, como en pruebas.
writeFileSync(join(salida, 'sembrar_iglesias_prueba.sql'), `-- Origen: supabase/seeds/sembrar_iglesias_prueba.sql, sha256 ${sha(siembra).slice(0, 12)}. Única diferencia: siembra.mega = 'prueba-mega' (en el real, casa-reino es una iglesia real y no se toca).\n-- Se aplica DESPUÉS de verificar el traspaso. Crea solo iglesias con es_demo = true; no toca ninguna que ya exista.\n${limpiarComentarios(siembra.replace(POR_DEFECTO, "select set_config('siembra.mega', 'prueba-mega', false)"))}`)

// Tarea programada de purga (pg_cron + pg_net + Vault): se aplica DESPUÉS, cuando existan las extensiones y los tres secretos. Sin las órdenes propias de psql, para ejecutarla con una herramienta de SQL.
mkdirSync(join(salida, 'despues'), { recursive: true })
const despues: string[] = []
for (const f of ['programar.sql', 'verificar.sql']) {
  const o = leer(`scripts/entorno/purga-programada/${f}`)
  const t = `-- Origen: scripts/entorno/purga-programada/${f}, sha256 ${sha(o).slice(0, 12)}. Solo cambia que se quitan las órdenes propias de psql.\n${limpiarComentarios(o.replace(/^\\set .*$/gm, ''))}`
  if (PROHIBIDO.test(t)) throw new Error(`${f} contiene una orden destructiva`)
  writeFileSync(join(salida, 'despues', f), t); despues.push(`despues/${f}`)
}

// Funciones de borde con su huella
const SIN_JWT = ['baja', 'confirmar-suscripcion', 'enviar-confirmaciones', 'invitaciones']   // invitaciones: false a propósito (acciones públicas con token; las autenticadas validan con auth.getUser, docs/MULTITENANT.md apartado 3)
const carpetaF = join(RAIZ, 'supabase', 'functions')
const funciones = readdirSync(carpetaF, { withFileTypes: true }).filter(d => d.isDirectory()).map(d => d.name).sort().map(nombre => ({
  nombre, verify_jwt: !SIN_JWT.includes(nombre), entrada: 'index.ts', carpeta: `supabase/functions/${nombre}`,
  archivos: readdirSync(join(carpetaF, nombre)).filter(f => f.endsWith('.ts')).sort().map(f => { const b = readFileSync(join(carpetaF, nombre, f)); return { ruta: f, bytes: b.length, sha256: sha(b) } }),
}))
writeFileSync(join(salida, 'funciones.json'), JSON.stringify({ nota: 'invitaciones lleva verify_jwt false a propósito (confirmado por la sesión CRM, dueña del real): no se cambia.', funciones }, null, 2) + '\n')

writeFileSync(join(salida, 'CAMBIOS_SOBRE_LAS_MIGRACIONES.md'), `# Qué cambia el compilador respecto a las migraciones del repositorio\n\nEl paquete de traspaso es el resultado de compilar las ${cadena.length} migraciones posteriores a \`${BASE}\`. Estas son todas las diferencias con su texto original (${cambios.length}). La equivalencia del esquema resultante con la cadena sin tocar está probada en \`scripts/entorno/generar-traspaso.sh\`.\n\n${cambios.map(c => `- ${c}`).join('\n')}\n`)

const md = `# Paquete de traspaso al proyecto real (viveadn-saas)

Generado por \`scripts/entorno/generar-traspaso.sh\`. Lleva el real, que tiene las migraciones hasta \`${BASE}\`, al estado de la rama (${cadena.length} migraciones más). **Solo añade**: no importa ninguna fila de pruebas ni copia \`casa-reino\`. Ningún archivo de aplicación contiene drop, delete ni truncate; lo único destructivo está aislado en el archivo \`DROP_HAROLD\`.

## Orden (${TOTAL} archivos)

| N de ${TOTAL} | Archivo | Bytes | sha256 | Contenido |
| --- | --- | --- | --- | --- |
${indice.map(i => `| ${i.n} de ${TOTAL} | \`${i.archivo}\` | ${i.bytes.toLocaleString('es-ES')} | \`${i.sha.slice(0, 16)}\` | ${i.contenido} |`).join('\n')}

1. Aplicar los archivos en orden, uno a uno, ninguno de más de 20 KB. Cada tramo se puede aplicar solo y **repetir sin error** (si ya está aplicado, no hace nada) y falla si falta el tramo anterior. **Detenerse en el primer error** y avisar con el texto del error: cada tramo es un solo bloque, así que o se aplica entero o no se aplica nada.
2. El de comprobación (1 de ${TOTAL}) no cambia nada y debe decir «ok». Si dice otra cosa, no se sigue.
3. Tras los de aplicación, \`DROP_HAROLD\` (a mano), y después la verificación: todas las filas con \`ok = true\`.
4. Solo entonces: siembra de demostraciones (\`sembrar_iglesias_prueba.sql\`), funciones de borde (\`funciones.json\`), Vault y tareas (ver \`docs/TRASPASO-AL-REAL.md\`).
5. El registro en \`supabase_migrations\` es un paso aparte, después de verificar.

## Reversión

${reversionIndice.map(r => `- \`${r.archivo}\` (${r.bytes.toLocaleString('es-ES')} bytes, sha256 \`${r.sha.slice(0, 16)}\`): ${r.contenido}`).join('\n')}

Se aplican en orden R01, R02… y solo si Gerencia lo ordena. Probada en local: deja el esquema idéntico al del real antes del traspaso.

## Huella

\`HUELLAS.sha256\` lista el sha256 completo de cada archivo y el de todo el paquete. Comprobar con \`sha256sum -c HUELLAS.sha256\` antes de aplicar.

Qué cambia el compilador respecto a las migraciones originales: \`CAMBIOS_SOBRE_LAS_MIGRACIONES.md\`.
`
writeFileSync(join(salida, 'INDICE.md'), md)

const todos = [...indice.map(i => i.archivo), ...reversionIndice.map(r => r.archivo), ...despues, 'sembrar_iglesias_prueba.sql', 'funciones.json', 'CAMBIOS_SOBRE_LAS_MIGRACIONES.md', 'INDICE.md']
const lineas = todos.map(f => `${sha(readFileSync(join(salida, f)))}  ${f}`)
writeFileSync(join(salida, 'HUELLAS.sha256'), lineas.join('\n') + '\n' + `# huella del conjunto: ${sha(lineas.join('\n'))}\n`.replace(/^/, ''))
if (!existsSync(join(salida, 'INDICE.md'))) throw new Error('sin índice')
console.log(`Traspaso en ${salida}: ${TOTAL} archivos (${tramos.length} tramos de aplicación), ${gr.length} de reversión, ${cambios.length} cambios sobre las migraciones, ${dropHarold.length} DROP_HAROLD`)
