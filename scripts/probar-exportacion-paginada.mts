// Pruebas de la exportación por páginas: MD5 incremental, ZIP en flujo y el recorrido completo con una fuente simulada.
// El ZIP se valida con el lector de Python (zipfile), que comprueba el CRC de cada archivo, y las huellas con `node:crypto`.
// Uso: npm run test:exportacion-paginada
import assert from 'node:assert/strict'
import { createHash, randomBytes } from 'node:crypto'
import { execFileSync } from 'node:child_process'
import { mkdtempSync, writeFileSync, rmSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
const { Md5, md5Hex } = await import('../src/lib/md5.ts')
const { EscritorZip } = await import('../src/lib/zipFlujo.ts')
const { exportarPaginado } = await import('../src/lib/exportacionPaginada.ts')
type Fuente = import('../src/lib/exportacionPaginada.ts').Fuente
type Plan = import('../src/lib/exportacionPaginada.ts').Plan

const ref = (b: Uint8Array | string) => createHash('md5').update(b).digest('hex')

// 1. MD5: todas las longitudes alrededor de los límites de bloque y de relleno, y fragmentaciones al azar
for (let n = 0; n <= 200; n++) { const b = randomBytes(n); assert.equal(md5Hex(b), ref(b), `MD5 de ${n} bytes`) }
assert.equal(md5Hex(new Uint8Array(0)), 'd41d8cd98f00b204e9800998ecf8427e', 'MD5 de nada')
assert.equal(md5Hex(new TextEncoder().encode('abc')), '900150983cd24fb0d6963f7d28e17f72', 'MD5 de abc')
for (const tam of [1000, 65536, 1_000_003]) {
  const b = randomBytes(tam); const m = new Md5()
  for (let p = 0; p < b.length;) { const t = Math.min(1 + Math.floor(Math.random() * 300), b.length - p); m.update(b.subarray(p, p + t)); p += t }
  assert.equal(m.hex(), ref(b), `MD5 incremental de ${tam} bytes en trozos al azar`)
}
assert.throws(() => { const m = new Md5(); m.hex(); m.hex() }, /cerr/, 'un MD5 cerrado no se reutiliza')

// Lector independiente
const LEE = `
import sys, zipfile, json, base64
z = zipfile.ZipFile(sys.argv[1])
bad = z.testzip()
assert bad is None, f"CRC incorrecto en {bad}"
print(json.dumps({i.filename: base64.b64encode(z.read(i)).decode() for i in z.infolist()}))
`
function leer(bytes: Uint8Array): Record<string, Buffer> {
  const dir = mkdtempSync(join(tmpdir(), 'zipf-'))
  try {
    const f = join(dir, 'a.zip'); writeFileSync(f, bytes)
    const crudo = JSON.parse(execFileSync('python3', ['-I', '-c', LEE, f], { encoding: 'utf8', maxBuffer: 1024 * 1024 * 1024 })) as Record<string, string>
    return Object.fromEntries(Object.entries(crudo).map(([k, v]) => [k, Buffer.from(v, 'base64')]))
  } finally { rmSync(dir, { recursive: true, force: true }) }
}
const juntar = (partes: Uint8Array[]) => { const o = new Uint8Array(partes.reduce((a, p) => a + p.length, 0)); let q = 0; for (const p of partes) { o.set(p, q); q += p.length } return o }

// 2. ZIP en flujo
{
  const partes: Uint8Array[] = []
  const z = new EscritorZip(p => { partes.push(p) }, new Date('2026-11-11T10:20:30Z'))
  await z.empezar('a.txt'); await z.escribir('ho'); await z.escribir('la')
  await z.empezar('csv/niños, "y" más.csv'); await z.escribir('x,y\r\n'); await z.escribir('1,2\r\n')
  await z.empezar('vacio.txt')
  await z.empezar('grande.bin'); const grande = randomBytes(300_000); for (let p = 0; p < grande.length; p += 7919) await z.escribir(grande.subarray(p, p + 7919))
  await z.empezar('emoji.txt'); await z.escribir('🙏 ñ ')   // trozos con caracteres de varios bytes
  const r = await z.cerrar()
  const zip = juntar(partes)
  assert.equal(r.bytes, zip.length, 'el tamaño informado es el real')
  assert.equal(r.archivos, 5)
  const c = leer(zip)
  assert.equal(c['a.txt']!.toString(), 'hola')
  assert.equal(c['csv/niños, "y" más.csv']!.toString(), 'x,y\r\n1,2\r\n')
  assert.equal(c['vacio.txt']!.length, 0, 'un archivo vacío vuelve vacío')
  assert.ok(c['grande.bin']!.equals(Buffer.from(grande)), 'un archivo binario grande vuelve idéntico')
  assert.equal(c['emoji.txt']!.toString(), '🙏 ñ ')
  // Mismo contenido y fecha: mismo ZIP
  const otras: Uint8Array[] = []
  const z2 = new EscritorZip(p => { otras.push(p) }, new Date('2026-11-11T10:20:30Z'))
  await z2.empezar('a.txt'); await z2.escribir('hola'); await z2.cerrar()
  const otras2: Uint8Array[] = []
  const z3 = new EscritorZip(p => { otras2.push(p) }, new Date('2026-11-11T10:20:30Z'))
  await z3.empezar('a.txt'); await z3.escribir('ho'); await z3.escribir('la'); await z3.cerrar()
  assert.deepEqual(juntar(otras), juntar(otras2), 'trocear no cambia el resultado')
  // Reglas
  const z4 = new EscritorZip(() => {})
  await assert.rejects(() => z4.escribir('x'), /ningún archivo abierto/)
  await z4.empezar('a'); await assert.rejects(() => z4.empezar('a'), /repetida/)
  await assert.rejects(() => z4.empezar('../fuera'), /no valida/)
  await assert.rejects(() => z4.empezar('/abs'), /no valida/)
  await z4.cerrar(); await assert.rejects(() => z4.empezar('b'), /cerrado/)
}
{
  const p: Uint8Array[] = []; const zz = new EscritorZip(x => { p.push(x) }); await zz.cerrar()
  assert.deepEqual(leer(juntar(p)), {}, 'un ZIP sin archivos también es válido')
}
// El destino puede ser asíncrono y el escritor lo espera (contrapresión)
{
  let activo = 0, maxActivo = 0
  const z = new EscritorZip(async () => { activo++; maxActivo = Math.max(maxActivo, activo); await new Promise(r => setTimeout(r, 1)); activo-- })
  await z.empezar('a'); for (let i = 0; i < 20; i++) await z.escribir('x'); await z.cerrar()
  assert.equal(maxActivo, 1, 'cada parte espera a la anterior')
}

// 3. Recorrido completo con una fuente simulada
interface Tabla { nombre: string; clave: string[]; filas: Record<string, string | number | null>[]; omitidas?: string[] }
function fuenteDe(tablas: Tabla[], opciones: { fallos?: Record<string, number>; mutar?: (a: { tabla: string; formato: string; n: number }) => void; plan?: Partial<Plan>; llamadas?: string[] } = {}): Fuente {
  const filaJson = (f: unknown) => JSON.stringify(f)
  const campo = (v: unknown) => { const t = v === null ? '' : String(v); return t === '' && v !== null || /["\r\n,]/.test(t) || /^\s|\s$/.test(t) ? `"${t.replace(/"/g, '""')}"` : t }
  const orden = (t: Tabla) => [...t.filas].sort((a, b) => { const x = t.clave.map(k => String(a[k])).join('\u0000'), y = t.clave.map(k => String(b[k])).join('\u0000'); return x < y ? -1 : x > y ? 1 : 0 })
  const fallos = { ...(opciones.fallos ?? {}) }
  return {
    async plan() {
      return {
        formato: 'viveadn-exportacion-2', iglesia_id: 'i1', exportado_en: '2026-11-11T10:00:00Z', total_filas: tablas.reduce((a, t) => a + t.filas.length, 0),
        archivos: { cubo: [] },
        tablas: tablas.map((t, i) => ({ nombre: t.nombre, orden_carga: i, archivo_csv: `csv/${t.nombre}.csv`, filas: t.filas.length, clave: t.clave, omitidas: t.omitidas ?? [],
          columnas: Object.keys(t.filas[0] ?? { id: 0 }).map(n => ({ nombre: n, tipo: 'text', obligatoria: false })) })),
        ...opciones.plan,
      } as Plan
    },
    async pagina(tabla: string, formato: 'json' | 'csv', despues: string[] | null, limite: number): Promise<any> {
      opciones.llamadas?.push(`${tabla}:${formato}`)
      if ((fallos[tabla] ?? 0) > 0) { fallos[tabla]!--; throw new Error('fallo de red simulado') }
      const t = tablas.find(x => x.nombre === tabla)!
      const todas = orden(t)
      const desde = despues === null ? 0 : todas.findIndex(f => t.clave.map(k => String(f[k])).join('\u0000') > despues.join('\u0000'))
      const resto = desde < 0 ? [] : todas.slice(desde)
      const pag = resto.slice(0, limite)
      opciones.mutar?.({ tabla, formato, n: pag.length })
      const sig = resto.length > limite ? t.clave.map(k => String(pag[pag.length - 1]![k])) : undefined
      if (formato === 'json') return { n: pag.length, json: `[${pag.map(filaJson).join(',')}]`, hashes: pag.map(f => ref(filaJson(f))), ...(sig ? { siguiente: sig } : {}) }
      return { n: pag.length, csv: pag.map(f => Object.values(f).map(campo).join(',') + '\r\n').join(''), ...(sig ? { siguiente: sig } : {}) }
    },
  } as Fuente
}
const misTablas: Tabla[] = [
  { nombre: 'iglesias', clave: ['id'], filas: [{ id: 'i1', nombre: 'Iglesia "Ñ", S.L.' }] },
  { nombre: 'miembros', clave: ['id'], filas: Array.from({ length: 23 }, (_, i) => ({ id: `m${String(i).padStart(3, '0')}`, nombre: i % 5 === 0 ? 'Zoë, "la" \r\nnueva' : `Persona ${i}`, notas: i % 3 === 0 ? null : '' })) },
  { nombre: 'rol_permisos', clave: ['rol_id', 'permiso'], filas: ['a', 'b', 'c'].flatMap(r => ['x', 'y', 'z', 'w'].map(p => ({ rol_id: r, permiso: p }))) },
  { nombre: 'vacia', clave: ['id'], filas: [] },
]
const partes: Uint8Array[] = []
const res = await exportarPaginado(fuenteDe(misTablas), { slug: 'mi-iglesia', hoy: new Date('2026-11-11T12:00:00Z'), leeme: 'Léeme', limite: 5, destino: p => { partes.push(p) } })
assert.equal(res.nombre, 'viveadn-mi-iglesia-2026-11-11.zip')
assert.equal(res.tablas, 4)
assert.equal(res.filas, 1 + 23 + 12, 'cuenta las filas leídas')
assert.equal(res.cambios, false)
const zip = juntar(partes)
assert.equal(res.bytes, zip.length)
const c = leer(zip)
assert.deepEqual(Object.keys(c).sort(), ['LEEME.txt', 'csv/iglesias.csv', 'csv/miembros.csv', 'csv/rol_permisos.csv', 'csv/vacia.csv', 'datos.json', 'manifest.json'])
assert.equal(c['LEEME.txt']!.toString(), 'Léeme')
const datos = JSON.parse(c['datos.json']!.toString())
assert.deepEqual(datos.iglesia, misTablas[0]!.filas[0], 'la iglesia va en su campo')
assert.ok(!('iglesias' in datos.tablas), 'y no dentro de las tablas')
assert.equal(datos.tablas.miembros.length, 23)
assert.deepEqual(datos.tablas.vacia, [])
assert.equal(datos.tablas.rol_permisos.length, 12, 'una clave compuesta se recorre entera con páginas de 5')
const idsLeidos = datos.tablas.miembros.map((f: { id: string }) => f.id)
assert.deepEqual(idsLeidos, [...idsLeidos].sort(), 'en orden de clave')
assert.equal(new Set(idsLeidos).size, 23, 'sin repetir ninguna fila')
assert.deepEqual(datos.tablas.miembros.find((f: { id: string }) => f.id === 'm000').nombre, 'Zoë, "la" \r\nnueva', 'los caracteres incómodos vuelven intactos')
const man = JSON.parse(c['manifest.json']!.toString())
assert.equal(man.total_filas, 36)
assert.equal(man.paginado, true); assert.equal(man.filas_por_pagina, 5); assert.equal(man.cambios_durante_la_exportacion, false)
assert.deepEqual(man.archivos_de_almacenamiento, { cubo: [] })
for (const t of man.tablas) {
  const original = misTablas.find(x => x.nombre === t.nombre)!
  assert.equal(t.filas, original.filas.length, `filas de ${t.nombre}`)
  const esperada = ref(original.filas.map(f => ref(JSON.stringify(f))).sort().join(','))
  assert.equal(t.huella, esperada, `la huella de ${t.nombre} es el md5 de los md5 ordenados`)
  assert.equal(t.md5_csv, ref(c[t.archivo_csv]!), `el md5 del CSV de ${t.nombre} es el del archivo`)
}
// El CSV de cada tabla es exactamente el esperado, calculado aquí por separado: cabecera, filas en orden de clave, CRLF y comillas
{
  const q = (v: unknown) => { const t = v === null ? '' : String(v); return (t === '' && v !== null) || /["\r\n,]/.test(t) || /^\s|\s$/.test(t) ? `"${t.replace(/"/g, '""')}"` : t }
  for (const t of misTablas) {
    const claves = t.clave
    const filas = [...t.filas].sort((x, y) => { const a1 = claves.map(k => String(x[k])).join('\u0000'), b1 = claves.map(k => String(y[k])).join('\u0000'); return a1 < b1 ? -1 : a1 > b1 ? 1 : 0 })
    const columnas = Object.keys(t.filas[0] ?? { id: 0 })
    const esperado = columnas.map(q).join(',') + '\r\n' + filas.map(f => columnas.map(k => q(f[k] as never)).join(',') + '\r\n').join('')
    assert.equal(c[`csv/${t.nombre}.csv`]!.toString(), esperado, `el CSV de ${t.nombre} es exactamente el esperado`)
  }
}
assert.equal(c['csv/vacia.csv']!.toString(), 'id\r\n', 'una tabla vacía lleva solo su cabecera')
assert.ok(c['csv/miembros.csv']!.toString().startsWith('id,nombre,notas\r\n'), 'cabecera del CSV')
assert.ok(c['csv/miembros.csv']!.toString().includes('"Zoë, ""la"" \r\nnueva"'), 'el CSV entrecomilla comas, comillas y saltos')
assert.equal(man.tablas.map((t: { nombre: string }) => t.nombre).join(), 'iglesias,miembros,rol_permisos,vacia', 'el manifiesto conserva el orden de carga')

// Fallos transitorios: se reintenta; si persisten, falla
{
  const llamadas: string[] = []; const esperas: number[] = []
  const r = await exportarPaginado(fuenteDe(misTablas, { fallos: { miembros: 2 }, llamadas }), { slug: 's', hoy: new Date(), leeme: '', limite: 100, destino: () => {}, esperar: async ms => { esperas.push(ms) } })
  assert.equal(r.filas, 36, 'dos fallos de red no estropean la exportación')
  assert.deepEqual(esperas, [250, 500], 'con espera creciente')
  await assert.rejects(() => exportarPaginado(fuenteDe(misTablas, { fallos: { miembros: 99 } }), { slug: 's', hoy: new Date(), leeme: '', destino: () => {}, esperar: async () => {} }), /fallo de red simulado/, 'si persiste, falla con su causa')
}
// La iglesia cambia mientras se exporta: se detecta y se avisa en el manifiesto, sin entregar cifras falsas
{
  const p: Uint8Array[] = []
  let altas = 0
  const mut = fuenteDe(misTablas, { mutar: a => { if (a.tabla === 'miembros' && a.formato === 'csv' && altas++ === 0) { /* el CSV leerá una fila menos */ } } })
  const original = mut.pagina.bind(mut)
  let csvMiembros = 0
  ;(mut as { pagina: Fuente['pagina'] }).pagina = (async (t: string, f: 'json' | 'csv', d: string[] | null, l: number) => {
    const r: any = await original(t as never, f as never, d, l)
    if (t === 'miembros' && f === 'csv' && csvMiembros++ === 0) { r.n -= 1; r.csv = r.csv.split('\r\n').slice(1).join('\r\n') }
    return r
  }) as Fuente['pagina']
  const r = await exportarPaginado(mut, { slug: 's', hoy: new Date(), leeme: '', limite: 100, destino: x => { p.push(x) } })
  assert.equal(r.cambios, true, 'si el CSV y el JSON no coinciden se marca')
  assert.equal(JSON.parse(leer(juntar(p))['manifest.json']!.toString()).cambios_durante_la_exportacion, true)
}
// El plan dice otro número de filas que las leídas (alguien añadió o borró filas entre el plan y la lectura): se marca
{
  const f = fuenteDe(misTablas); const plan0 = f.plan.bind(f)
  ;(f as { plan: Fuente['plan'] }).plan = async () => { const p = await plan0(); p.tablas[1]!.filas += 5; return p }
  const p: Uint8Array[] = []
  const r = await exportarPaginado(f, { slug: 's', hoy: new Date(), leeme: '', destino: x => { p.push(x) } })
  assert.equal(r.cambios, true, 'si el plan y lo leído no coinciden se marca')
  const m = JSON.parse(leer(juntar(p))['manifest.json']!.toString())
  assert.equal(m.cambios_durante_la_exportacion, true)
  assert.equal(m.tablas[1].filas, 23, 'y el manifiesto lleva las filas realmente leídas, no las del plan')
}
{
  const r = await exportarPaginado(fuenteDe(misTablas, { plan: { tablas: undefined } }) as Fuente, { slug: 's', hoy: new Date(), leeme: '', destino: () => {} }).catch(e => e)
  assert.match(String(r.message), /plan/, 'un plan sin tablas se rechaza')
}
// Páginas mal formadas
for (const [que, malo, texto] of [
  ['hashes de menos', (r: any) => { r.hashes = r.hashes.slice(1) }, /huellas/],
  ['huella que no es md5', (r: any) => { r.hashes[0] = 'zz' }, /Huella no válida/],
  ['JSON sin corchetes', (r: any) => { r.json = '{}' }, /JSON de página no válido/],
  ['n mayor que el límite', (r: any) => { r.n = 9999 }, /no válida/],
] as const) {
  const f = fuenteDe(misTablas); const o = f.pagina.bind(f)
  ;(f as { pagina: Fuente['pagina'] }).pagina = (async (t: string, fo: 'json' | 'csv', d: string[] | null, l: number) => { const r: any = await o(t as never, fo as never, d, l); if (fo === 'json' && t === 'miembros') malo(r); return r }) as Fuente['pagina']
  await assert.rejects(() => exportarPaginado(f, { slug: 's', hoy: new Date(), leeme: '', destino: () => {}, esperar: async () => {}, intentos: 1 }), texto, `se rechaza: ${que}`)
}
// Una paginación que no avanza o no termina no cuelga el navegador
{
  const f = fuenteDe(misTablas); const o = f.pagina.bind(f)
  ;(f as { pagina: Fuente['pagina'] }).pagina = (async (t: string, fo: 'json' | 'csv', d: string[] | null, l: number) => {
    const r: any = await o(t as never, fo as never, d, l)
    if (t === 'miembros' && fo === 'json') { r.siguiente = ['m000']; r.n = 0; r.json = '[]'; r.hashes = [] }
    return r
  }) as Fuente['pagina']
  await assert.rejects(() => exportarPaginado(f, { slug: 's', hoy: new Date(), leeme: '', destino: () => {}, esperar: async () => {}, intentos: 1 }), /no avanza/, 'un cursor que no avanza se corta')
}

// 4. La memoria no crece con el contenido de la exportación: 400.000 filas (unos 130 MB de texto) desde una fuente que las genera al vuelo
{
  const FILAS = 400_000
  const relleno = 'x'.repeat(120)
  const tabla = { nombre: 'enorme', clave: ['id'] }
  const fila = (i: number) => ({ id: String(i).padStart(8, '0'), nombre: `Persona ${i}`, notas: relleno })
  const grandes: Fuente = {
    async plan() { return { formato: 'viveadn-exportacion-2', iglesia_id: 'i', exportado_en: 'x', total_filas: FILAS, tablas: [{ ...tabla, orden_carga: 0, archivo_csv: 'csv/enorme.csv', filas: FILAS, omitidas: [], clave: ['id'], columnas: [{ nombre: 'id', tipo: 't', obligatoria: true }, { nombre: 'nombre', tipo: 't', obligatoria: false }, { nombre: 'notas', tipo: 't', obligatoria: false }] }] } },
    async pagina(_t: string, formato: 'json' | 'csv', despues: string[] | null, limite: number): Promise<any> {
      const desde = despues ? Number(despues[0]) + 1 : 0
      const hasta = Math.min(desde + limite, FILAS)
      const filas = Array.from({ length: hasta - desde }, (_, k) => fila(desde + k))
      const sig = hasta < FILAS ? [String(hasta - 1).padStart(8, '0')] : undefined
      // Las claves son números con ceros: el cursor es el último id
      if (formato === 'json') return { n: filas.length, json: `[${filas.map(f => JSON.stringify(f)).join(',')}]`, hashes: filas.map(f => ref(JSON.stringify(f))), ...(sig ? { siguiente: sig } : {}) }
      return { n: filas.length, csv: filas.map(f => `${f.id},${f.nombre},${f.notas}\r\n`).join(''), ...(sig ? { siguiente: sig } : {}) }
    },
  } as Fuente
  const gc = (global as { gc?: () => void }).gc
  assert.ok(gc, 'la prueba de memoria necesita node --expose-gc (npm run test:exportacion-paginada lo pone)')
  gc!()
  const antes = process.memoryUsage().heapUsed
  let retenido = 0; let bytes = 0; let ultimo = 0
  const r = await exportarPaginado(grandes, { slug: 'g', hoy: new Date(), leeme: '', limite: 2000, destino: p => {
    bytes += p.length
    if (bytes - ultimo > 8_000_000) { ultimo = bytes; gc!(); retenido = Math.max(retenido, process.memoryUsage().heapUsed - antes) }
  } })
  assert.equal(r.filas, FILAS)
  assert.ok(bytes > 100_000_000, `se escribieron ${Math.round(bytes / 1e6)} MB`)
  const porFila = retenido / FILAS
  console.log(`  memoria: ${Math.round(bytes / 1e6)} MB escritos; retenido como máximo tras recoger basura: ${(retenido / 1e6).toFixed(1)} MB (${Math.round(porFila)} B por fila, los md5 de la huella)`)
  // Lo único que crece con la exportación son los md5 de las filas (32 caracteres cada uno): decenas de bytes por fila, no el contenido
  assert.ok(porFila < 120, `se retienen ${Math.round(porFila)} B por fila: la memoria debe depender del número de filas (md5), no de su contenido`)
  assert.ok(retenido < bytes / 4, 'y lo retenido es una fracción pequeña de lo exportado')
}
console.log('Exportación paginada: todas las pruebas pasan')
