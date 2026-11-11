// Comprueba que todos los idiomas tienen exactamente las mismas claves que es.json
// y que ningún texto está vacío. Sale con código 1 si encuentra algún problema.
// Uso: npm run check:idiomas
import { readFileSync, readdirSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'
import { baseCompile } from '@intlify/message-compiler'

const carpeta = join(dirname(fileURLToPath(import.meta.url)), '..', 'src', 'i18n', 'locales')
const BASE = 'es.json'

// Aplana { a: { b: 'x' } } en { 'a.b': 'x' }
function aplanar(objeto, prefijo = '', salida = {}) {
  for (const [clave, valor] of Object.entries(objeto)) {
    const ruta = prefijo ? `${prefijo}.${clave}` : clave
    if (valor !== null && typeof valor === 'object' && !Array.isArray(valor)) aplanar(valor, ruta, salida)
    else salida[ruta] = valor
  }
  return salida
}

function cargar(archivo) {
  try {
    return aplanar(JSON.parse(readFileSync(join(carpeta, archivo), 'utf8')))
  } catch (e) {
    console.error(`✗ ${archivo}: no es un JSON válido (${e.message})`)
    process.exit(1)
  }
}

const archivos = readdirSync(carpeta).filter(f => f.endsWith('.json')).sort()
if (!archivos.includes(BASE)) {
  console.error(`✗ Falta el idioma base ${BASE} en ${carpeta}`)
  process.exit(1)
}

const base = cargar(BASE)
const clavesBase = Object.keys(base)
const problemas = []

// Un texto que vue-i18n no puede compilar falla en el navegador (por ejemplo, una @ suelta se toma por una referencia a otro texto): se escribe {'@'}
function compila(valor) {
  const errores = []
  baseCompile(valor, { onError: e => errores.push(e.message.split('\n')[0]) })
  return errores
}

function revisarValores(archivo, textos) {
  for (const [clave, valor] of Object.entries(textos)) {
    if (typeof valor !== 'string') problemas.push(`${archivo}: "${clave}" no es un texto`)
    else if (valor.trim() === '') problemas.push(`${archivo}: "${clave}" está vacío`)
    else {
      const errores = compila(valor)
      if (errores.length) problemas.push(`${archivo}: "${clave}" no compila en vue-i18n (${errores[0]})`)
    }
  }
}

revisarValores(BASE, base)

for (const archivo of archivos.filter(f => f !== BASE)) {
  const textos = cargar(archivo)
  for (const clave of clavesBase) {
    if (!(clave in textos)) problemas.push(`${archivo}: falta "${clave}" (existe en ${BASE})`)
  }
  for (const clave of Object.keys(textos)) {
    if (!(clave in base)) problemas.push(`${archivo}: sobra "${clave}" (no existe en ${BASE})`)
  }
  revisarValores(archivo, textos)
}

if (problemas.length) {
  console.error(`✗ ${problemas.length} problema(s) en las traducciones:`)
  for (const p of problemas) console.error(`  - ${p}`)
  process.exit(1)
}

console.log(`✓ ${archivos.length} idiomas con las mismas ${clavesBase.length} claves y ningún texto vacío ni que no compile: ${archivos.join(', ')}`)
