// Resume un archivo de contactos de Google SIN mostrar datos personales: solo cifras. Sirve para comprobar un archivo
// real (el que entrega Gerencia por el canal privado) antes de importarlo. No escribe nada ni toca ninguna base.
// Uso: node scripts/resumen-contactos-google.mts /ruta/fuera/del/repositorio/contactos.csv
// Los archivos reales no entran al repositorio: el script se niega a leer uno que esté dentro de él.
import { readFileSync, statSync, realpathSync } from 'node:fs'
import { dirname, join, relative, isAbsolute } from 'node:path'
import { fileURLToPath } from 'node:url'
const { analizarGoogle, MAX_BYTES_GOOGLE } = await import('../src/lib/importarGoogle.ts')

const ruta = process.argv[2]
if (!ruta) { console.error('Uso: node scripts/resumen-contactos-google.mts <archivo.csv>'); process.exit(2) }
const raiz = realpathSync(join(dirname(fileURLToPath(import.meta.url)), '..'))
const real = realpathSync(ruta)
const rel = relative(raiz, real)
if (rel === '' || (!rel.startsWith('..') && !isAbsolute(rel))) {
  console.error('FALLO: el archivo está dentro del repositorio. Los datos reales no entran al repositorio: muévelo fuera y repite.')
  process.exit(2)
}
if (statSync(real).size > MAX_BYTES_GOOGLE) { console.error('FALLO: el archivo supera el tamaño máximo que admite la importación.'); process.exit(1) }

const buf = readFileSync(real)
let texto: string
try { texto = new TextDecoder('utf-8', { fatal: true }).decode(buf) } catch { texto = new TextDecoder('windows-1252').decode(buf) }
const a = analizarGoogle(texto)
if (a.error) { console.error(`El archivo no se puede importar: ${a.error}`); process.exit(1) }
const r = a.resumen
const correos = new Set(a.personas.flatMap(p => p.emails))
const lineas: [string, number | string][] = [
  ['Formato detectado', r.formato === 'wix' ? 'Wix' : 'Google u Outlook'],
  ['Filas de datos', r.filas],
  ['Personas distintas tras fusionar repetidos', r.personas],
  ['  con nombre', r.personas - r.sinNombre],
  ['  sin nombre pero con correo o teléfono (aparte)', r.sinNombre],
  ['Filas fusionadas en otra', r.fusionadas],
  ['Filas sin nombre y sin contacto, descartadas', r.descartadasVacias],
  ['Correos únicos válidos', correos.size],
  ['Correos inválidos descartados', r.correosInvalidos],
  ['Teléfonos inválidos descartados', r.telefonosInvalidos],
  ['Fechas de nacimiento inválidas', r.fechasInvalidas],
  ['Cumpleaños sin año', r.cumpleanosSinAnio],
  ['Notas descartadas por parecer contraseñas', r.notasConClave],
  ['Notas recortadas', r.notasRecortadas],
  ['Con dirección', a.personas.filter(p => p.direcciones.length).length],
  ['Con etiquetas', a.personas.filter(p => p.etiquetas.length).length],
  ['Con más de un correo', a.personas.filter(p => p.emails.length > 1).length],
  ['Con más de un teléfono', a.personas.filter(p => p.telefonos.length > 1).length],
]
for (const [k, v] of lineas) console.log(`${k.padEnd(52)} ${v}`)
if (r.formato === 'wix') {
  // Estado de suscripción por canal: personas tras fusionar repetidos (la más restrictiva gana). Solo cifras.
  for (const canal of ['email', 'sms'] as const) {
    const c = r.consentimiento[canal]
    console.log(`Suscripción por ${canal === 'email' ? 'correo' : 'SMS'}: suscritos ${c.suscrito}, sin dato ${c.sin_dato}, nunca suscritos ${c.nunca}, cancelados ${c.cancelado}`)
  }
  console.log(`Estados de suscripción que no se reconocen: ${r.estadosDesconocidos}`)
  console.log(`Con fuente: ${a.personas.filter(p => p.fuente).length}; con fecha de alta: ${a.personas.filter(p => p.creado).length}`)
}
console.log(`Columnas sensibles (no se leyeron): ${a.columnasSensibles.length ? a.columnasSensibles.join(', ') : 'ninguna'}`)
console.log(`Columnas que no se importan: ${a.ignoradas.length}`)
