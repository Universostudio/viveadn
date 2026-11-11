// Escritor mínimo de ZIP sin compresión (método "store"), para entregar la exportación de una iglesia en un solo
// archivo sin depender de ninguna librería. Nombres en UTF-8. Son funciones puras, sin acceso a la red ni al navegador.

export interface EntradaZip {
  ruta: string
  contenido: string | Uint8Array
}

const TABLA_CRC = (() => {
  const t = new Uint32Array(256)
  for (let n = 0; n < 256; n++) {
    let c = n
    for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1
    t[n] = c >>> 0
  }
  return t
})()

export function crc32(datos: Uint8Array): number {
  let c = 0xffffffff
  for (let i = 0; i < datos.length; i++) c = TABLA_CRC[(c ^ datos[i]!) & 0xff]! ^ (c >>> 8)
  return (c ^ 0xffffffff) >>> 0
}

// Fecha y hora en el formato de MS-DOS que usa el ZIP (la hora, en UTC, para que el resultado no dependa del equipo)
function fechaDos(d: Date): { fecha: number; hora: number } {
  const anio = Math.min(Math.max(d.getUTCFullYear(), 1980), 2107)
  return {
    fecha: ((anio - 1980) << 9) | ((d.getUTCMonth() + 1) << 5) | d.getUTCDate(),
    hora: (d.getUTCHours() << 11) | (d.getUTCMinutes() << 5) | (d.getUTCSeconds() >> 1),
  }
}

const MAX_ENTRADAS = 0xffff
const MAX_BYTES = 0xffffffff

export function crearZip(entradas: EntradaZip[], fecha: Date = new Date()): Uint8Array {
  if (entradas.length > MAX_ENTRADAS) throw new Error('Demasiados archivos para un ZIP')
  const codificador = new TextEncoder()
  const { fecha: fd, hora: hd } = fechaDos(fecha)
  const rutas = new Set<string>()
  const partes: Uint8Array[] = []
  const central: Uint8Array[] = []
  let desplazamiento = 0

  for (const e of entradas) {
    if (rutas.has(e.ruta)) throw new Error(`Ruta repetida en el ZIP: ${e.ruta}`)
    if (e.ruta.startsWith('/') || e.ruta.split('/').includes('..')) throw new Error(`Ruta no valida en el ZIP: ${e.ruta}`)
    rutas.add(e.ruta)
    const nombre = codificador.encode(e.ruta)
    const datos = typeof e.contenido === 'string' ? codificador.encode(e.contenido) : e.contenido
    if (datos.length > MAX_BYTES || desplazamiento > MAX_BYTES) throw new Error('El ZIP supera los 4 GB')
    const crc = crc32(datos)

    const local = new DataView(new ArrayBuffer(30))
    local.setUint32(0, 0x04034b50, true)
    local.setUint16(4, 20, true)          // version necesaria
    local.setUint16(6, 0x0800, true)      // nombres en UTF-8
    local.setUint16(8, 0, true)           // sin compresion
    local.setUint16(10, hd, true)
    local.setUint16(12, fd, true)
    local.setUint32(14, crc, true)
    local.setUint32(18, datos.length, true)
    local.setUint32(22, datos.length, true)
    local.setUint16(26, nombre.length, true)
    local.setUint16(28, 0, true)
    partes.push(new Uint8Array(local.buffer), nombre, datos)

    const dir = new DataView(new ArrayBuffer(46))
    dir.setUint32(0, 0x02014b50, true)
    dir.setUint16(4, 20, true)
    dir.setUint16(6, 20, true)
    dir.setUint16(8, 0x0800, true)
    dir.setUint16(10, 0, true)
    dir.setUint16(12, hd, true)
    dir.setUint16(14, fd, true)
    dir.setUint32(16, crc, true)
    dir.setUint32(20, datos.length, true)
    dir.setUint32(24, datos.length, true)
    dir.setUint16(28, nombre.length, true)
    dir.setUint32(42, desplazamiento, true)
    central.push(new Uint8Array(dir.buffer), nombre)

    desplazamiento += 30 + nombre.length + datos.length
  }

  const tamanoCentral = central.reduce((a, p) => a + p.length, 0)
  if (desplazamiento + tamanoCentral > MAX_BYTES) throw new Error('El ZIP supera los 4 GB')
  const fin = new DataView(new ArrayBuffer(22))
  fin.setUint32(0, 0x06054b50, true)
  fin.setUint16(8, entradas.length, true)
  fin.setUint16(10, entradas.length, true)
  fin.setUint32(12, tamanoCentral, true)
  fin.setUint32(16, desplazamiento, true)

  const todas = [...partes, ...central, new Uint8Array(fin.buffer)]
  const salida = new Uint8Array(todas.reduce((a, p) => a + p.length, 0))
  let pos = 0
  for (const p of todas) { salida.set(p, pos); pos += p.length }
  return salida
}
