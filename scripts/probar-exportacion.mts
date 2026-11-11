// Pruebas del ZIP y del armado de la exportación de una iglesia. Uso: npm run test:exportacion
// El ZIP se valida con el lector de Python (zipfile), que comprueba el CRC de cada archivo.
import assert from 'node:assert/strict'
import { execFileSync } from 'node:child_process'
import { mkdtempSync, writeFileSync, rmSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
const { crearZip, crc32 } = await import('../src/lib/zip.ts')
const { construirPaquete } = await import('../src/lib/exportacion.ts')

// CRC-32 de referencia
assert.equal(crc32(new TextEncoder().encode('123456789')), 0xcbf43926, 'CRC-32 de la cadena estandar')
assert.equal(crc32(new Uint8Array(0)), 0, 'CRC-32 de nada')

const LEE = `
import sys, zipfile, json, base64
z = zipfile.ZipFile(sys.argv[1])
bad = z.testzip()
assert bad is None, f"CRC incorrecto en {bad}"
print(json.dumps({i.filename: base64.b64encode(z.read(i)).decode() for i in z.infolist()}))
`
function leer(bytes: Uint8Array): Record<string, string> {
  const b64 = leerBytes(bytes)
  return Object.fromEntries(Object.entries(b64).map(([k, v]) => [k, v.toString('utf8')]))
}
function leerBytes(bytes: Uint8Array): Record<string, Buffer> {
  const dir = mkdtempSync(join(tmpdir(), 'zip-'))
  try {
    const f = join(dir, 'a.zip')
    writeFileSync(f, bytes)
    const crudo = JSON.parse(execFileSync('python3', ['-I', '-c', LEE, f], { encoding: 'utf8', maxBuffer: 64 * 1024 * 1024 })) as Record<string, string>
    return Object.fromEntries(Object.entries(crudo).map(([k, v]) => [k, Buffer.from(v, 'base64')]))
  } finally { rmSync(dir, { recursive: true, force: true }) }
}

// Ida y vuelta, con nombres con acentos, carpetas, un archivo vacio y uno grande (mas de 64 KB)
const grande = 'línea con ñ y 🙏\r\n'.repeat(20000)
const zipMixto = crearZip([
  { ruta: 'a.txt', contenido: 'hola' },
  { ruta: 'csv/niños, "y" más.csv', contenido: 'x,y\r\n1,2\r\n' },
  { ruta: 'vacio.txt', contenido: '' },
  { ruta: 'grande.csv', contenido: grande },
  { ruta: 'binario.bin', contenido: new Uint8Array([0, 255, 1, 254]) },
], new Date('2026-11-11T10:20:30Z'))
const leido = leer(zipMixto)
assert.deepEqual([...(leerBytes(zipMixto)['binario.bin'] ?? [])], [0, 255, 1, 254], 'los bytes binarios vuelven intactos')
assert.equal(leido['a.txt'], 'hola')
assert.equal(leido['csv/niños, "y" más.csv'], 'x,y\r\n1,2\r\n')
assert.equal(leido['vacio.txt'], '')
assert.equal(leido['grande.csv'], grande, 'un archivo grande vuelve identico, con sus CRLF')
assert.equal(Object.keys(leido).length, 5)

// Un ZIP sin archivos tambien es valido
assert.deepEqual(leer(crearZip([])), {})

// Rutas peligrosas o repetidas
assert.throws(() => crearZip([{ ruta: '../fuera.txt', contenido: 'x' }]), /no valida/)
assert.throws(() => crearZip([{ ruta: '/abs.txt', contenido: 'x' }]), /no valida/)
assert.throws(() => crearZip([{ ruta: 'a', contenido: 'x' }, { ruta: 'a', contenido: 'y' }]), /repetida/)

// El mismo contenido da siempre el mismo ZIP (la fecha va en UTC)
const f = new Date('2026-11-11T10:20:30Z')
assert.deepEqual(crearZip([{ ruta: 'a', contenido: 'x' }], f), crearZip([{ ruta: 'a', contenido: 'x' }], f))

// Armado de la exportacion
const exp = {
  formato: 'viveadn-exportacion-2', exportado_en: '2026-11-11T10:00:00Z', iglesia: { id: 'i1', slug: 'mi-iglesia' },
  tablas: { miembros: [{ id: 'm1', nombre: 'Zoë' }] },
  csv: { iglesias: 'id,slug\r\ni1,mi-iglesia\r\n', miembros: 'id,nombre\r\nm1,Zoë\r\n' },
  manifiesto: { formato: 'viveadn-exportacion-2', total_filas: 2, tablas: [
    { nombre: 'iglesias', archivo_csv: 'csv/iglesias.csv', filas: 1 }, { nombre: 'miembros', archivo_csv: 'csv/miembros.csv', filas: 1 } ] },
  archivos: { 'iglesia-archivos': [] },
}
const p = construirPaquete(exp, 'mi-iglesia', new Date('2026-11-11T12:00:00Z'), 'Léeme')
assert.equal(p.tipo, 'zip')
assert.equal(p.nombre, 'viveadn-mi-iglesia-2026-11-11.zip')
assert.ok(p.tipo === 'zip' && p.tablas === 2 && p.filas === 2)
const contenido = leer((p as { bytes: Uint8Array }).bytes)
assert.deepEqual(Object.keys(contenido).sort(), ['LEEME.txt', 'csv/iglesias.csv', 'csv/miembros.csv', 'datos.json', 'manifest.json'])
assert.equal(contenido['csv/miembros.csv'], exp.csv.miembros)
assert.equal(contenido['LEEME.txt'], 'Léeme')
assert.deepEqual(JSON.parse(contenido['datos.json']).tablas, exp.tablas)
assert.equal(JSON.parse(contenido['manifest.json']).total_filas, 2)
assert.ok(!('csv' in JSON.parse(contenido['datos.json'])), 'el JSON de datos no repite los CSV')

// Sin manifiesto (funcion de borde anterior) sale el JSON de siempre
const viejo = construirPaquete({ formato: 'viveadn-exportacion-1', tablas: {} }, 'x', new Date('2026-01-02T00:00:00Z'), '')
assert.equal(viejo.tipo, 'json')
assert.equal(viejo.nombre, 'viveadn-x-2026-01-02.json')

// Si falta el CSV de una tabla del manifiesto, falla en vez de entregar un paquete incompleto
assert.throws(() => construirPaquete({ ...exp, csv: { iglesias: 'x' } }, 's', new Date(), ''), /Falta el CSV de la tabla miembros/)

console.log('Exportacion: todas las pruebas pasan')
