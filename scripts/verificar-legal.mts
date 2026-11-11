// Verifica los textos legales: los cuatro idiomas tienen la misma estructura y los mismos marcadores, y ningún texto
// cambia sin una versión nueva. Uso: npm run check:legal   (con --registrar guarda las huellas de la versión vigente)
import assert from 'node:assert/strict'
import { createHash } from 'node:crypto'
import { readFileSync, writeFileSync } from 'node:fs'

// LEGAL_IDIOMAS=es,en limita la comprobación (para validar una traducción sola); sin él, son los cuatro
const TODOS = ['es', 'en', 'fr', 'pt-BR'] as const
const IDIOMAS = TODOS.filter(i => (process.env.LEGAL_IDIOMAS ?? TODOS.join(',')).split(',').includes(i))
const ARCHIVO: Record<string, string> = { es: 'es', en: 'en', fr: 'fr', 'pt-BR': 'ptBR' }
const DOCS = ['privacidad', 'terminos', 'aviso', 'cookies'] as const
const REGISTRO = new URL('../src/legal/versiones.json', import.meta.url)

type Parrafo = string | { texto: string; si: string }
interface Seccion { id: string; titulo: string; parrafos: Parrafo[]; lista?: string[]; cierre?: Parrafo[] }
interface Documento { titulo: string; resumen: string; secciones: Seccion[] }

const textoDe = (p: Parrafo) => (typeof p === 'string' ? p : p.texto)
const marcadores = (s: string) => [...s.matchAll(/\{(\w+)\}/g)].map(m => m[1]!).sort().join(',')
const CONOCIDOS = new Set(['titular', 'nif', 'domicilio', 'emailLegal', 'emailSoporte', 'registro'])

const textos: Record<string, Record<string, Documento>> = {}
for (const i of IDIOMAS) textos[i] = (await import(`../src/legal/${ARCHIVO[i]}.ts`)).default

let errores = 0
const falla = (m: string) => { console.error('FALLO: ' + m); errores++ }

// 1. Misma estructura que el texto maestro (español)
for (const d of DOCS) {
  const base = textos.es![d]!
  for (const i of IDIOMAS) {
    const x = textos[i]![d]
    if (!x) { falla(`${i} no tiene el documento ${d}`); continue }
    if (!x.titulo?.trim() || !x.resumen?.trim()) falla(`${i}/${d}: falta título o resumen`)
    if (x.secciones.length !== base.secciones.length) { falla(`${i}/${d}: ${x.secciones.length} secciones y el maestro ${base.secciones.length}`); continue }
    base.secciones.forEach((sb, n) => {
      const sx = x.secciones[n]!
      const donde = `${i}/${d}/${sb.id}`
      if (sx.id !== sb.id) return falla(`${donde}: el id es ${sx.id}`)
      if (!sx.titulo?.trim()) falla(`${donde}: título vacío`)
      if (sx.parrafos.length !== sb.parrafos.length) falla(`${donde}: ${sx.parrafos.length} párrafos y el maestro ${sb.parrafos.length}`)
      if ((sx.lista?.length ?? 0) !== (sb.lista?.length ?? 0)) falla(`${donde}: ${sx.lista?.length ?? 0} elementos de lista y el maestro ${sb.lista?.length ?? 0}`)
      if ((sx.cierre?.length ?? 0) !== (sb.cierre?.length ?? 0)) falla(`${donde}: ${sx.cierre?.length ?? 0} párrafos de cierre y el maestro ${sb.cierre?.length ?? 0}`)
      const pares: [string, string, string][] = []
      sb.parrafos.forEach((p, k) => sx.parrafos[k] && pares.push([`parrafo ${k + 1}`, textoDe(p), textoDe(sx.parrafos[k]!)]))
      sb.lista?.forEach((p, k) => sx.lista?.[k] !== undefined && pares.push([`lista ${k + 1}`, p, sx.lista[k]!]))
      sb.cierre?.forEach((p, k) => sx.cierre?.[k] && pares.push([`cierre ${k + 1}`, textoDe(p), textoDe(sx.cierre[k]!)]))
      for (const [lugar, a, b] of pares) {
        if (!b.trim()) falla(`${donde} ${lugar}: vacío`)
        if (marcadores(a) !== marcadores(b)) falla(`${donde} ${lugar}: marcadores {${marcadores(b)}} y el maestro {${marcadores(a)}}`)
        if (/[—–]/.test(b)) falla(`${donde} ${lugar}: contiene un guion largo`)
      }
      sb.parrafos.forEach((p, k) => {
        const q = sx.parrafos[k]
        if (typeof p !== typeof q || (typeof p === 'object' && typeof q === 'object' && p.si !== q.si)) falla(`${donde} parrafo ${k + 1}: la condición no coincide con el maestro`)
      })
    })
  }
}
// 2. Solo marcadores conocidos, y los datos de contacto que el texto promete están
for (const i of IDIOMAS) for (const d of DOCS) for (const s of textos[i]![d]!.secciones) {
  const todo = [s.titulo, ...s.parrafos.map(textoDe), ...(s.lista ?? []), ...(s.cierre ?? [])].join(' ')
  for (const m of todo.matchAll(/\{(\w+)\}/g)) if (!CONOCIDOS.has(m[1]!)) falla(`${i}/${d}/${s.id}: marcador desconocido {${m[1]}}`)
}

// 3. Versión: el contenido de cada documento y idioma coincide con la huella registrada para su versión
const huella = (doc: Documento) => createHash('sha256').update(JSON.stringify(doc)).digest('hex')
const actual: Record<string, Record<string, string>> = {}
for (const d of DOCS) { actual[d] = {}; for (const i of IDIOMAS) actual[d]![i] = huella(textos[i]![d]!) }
if (process.argv.includes('--registrar')) {
  if (errores) { console.error('No se registra con errores de estructura.'); process.exit(1) }
  const reg = JSON.parse(readFileSync(REGISTRO, 'utf8'))
  for (const d of DOCS) {
    const v = reg.documentos[d].versiones.at(-1)
    v.huellas = actual[d]
  }
  writeFileSync(REGISTRO, JSON.stringify(reg, null, 2) + '\n')
  console.log('Huellas registradas para la última versión de cada documento.')
  process.exit(0)
}
if (process.env.LEGAL_IDIOMAS) { if (errores) { console.error(`${errores} problema(s)`); process.exit(1) } console.log('OK: estructura y marcadores coinciden con el maestro (sin comprobar huellas)'); process.exit(0) }
const reg = JSON.parse(readFileSync(REGISTRO, 'utf8'))
for (const d of DOCS) {
  const doc = reg.documentos[d]
  assert.ok(doc?.versiones?.length, `${d}: sin versiones registradas`)
  const v = doc.versiones.at(-1)
  assert.match(v.fecha, /^\d{4}-\d{2}-\d{2}$/, `${d}: fecha de la versión`)
  assert.ok(v.cambios?.trim(), `${d}: la versión ${v.version} no resume sus cambios`)
  for (const i of IDIOMAS) {
    if (v.huellas?.[i] !== actual[d]![i]) falla(`${d}/${i}: el texto no coincide con la versión ${v.version} registrada. Si el cambio es intencionado, crea una versión nueva en src/legal/versiones.json y ejecuta npm run check:legal -- --registrar`)
  }
}
if (errores) { console.error(`${errores} problema(s)`); process.exit(1) }
console.log(`OK: ${DOCS.length} documentos en ${IDIOMAS.length} idiomas con la misma estructura, los mismos marcadores y la huella de su versión`)
