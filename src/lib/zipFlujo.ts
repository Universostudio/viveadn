// Escritor de ZIP en flujo (método "store", sin compresión): cada archivo se escribe por trozos y su CRC y su tamaño se anotan al final
// con un descriptor de datos, de modo que ningún archivo tiene que estar entero en memoria. Quien lo usa decide adónde va cada parte
// (en el navegador, a una lista de partes de un Blob; en pruebas, a un archivo). Nombres en UTF-8. Hasta 4 GB y 65.535 archivos.
// El lector lee el directorio central del final, como hacen Python, 7-Zip, unzip y los gestores de archivos habituales.
import { crc32Acumulado, crc32Final } from './zip.ts'

export type Destino = (parte: Uint8Array) => void | Promise<void>

interface Anotada { nombre: Uint8Array; crc: number; tamano: number; desplazamiento: number }

const MAX_ENTRADAS = 0xffff
const MAX_BYTES = 0xffffffff
const codificador = new TextEncoder()

function fechaDos(d: Date): { fecha: number; hora: number } {
  const anio = Math.min(Math.max(d.getUTCFullYear(), 1980), 2107)
  return {
    fecha: ((anio - 1980) << 9) | ((d.getUTCMonth() + 1) << 5) | d.getUTCDate(),
    hora: (d.getUTCHours() << 11) | (d.getUTCMinutes() << 5) | (d.getUTCSeconds() >> 1),
  }
}

export class EscritorZip {
  private anotadas: Anotada[] = []
  private rutas = new Set<string>()
  private actual: { nombre: Uint8Array; crc: number; tamano: number; desplazamiento: number } | null = null
  private desplazamiento = 0
  private cerrado = false
  private dos: { fecha: number; hora: number }

  private destino: Destino

  constructor(destino: Destino, fecha: Date = new Date()) { this.destino = destino; this.dos = fechaDos(fecha) }

  /** Bytes escritos hasta ahora */
  get bytes(): number { return this.desplazamiento }
  get archivos(): number { return this.anotadas.length + (this.actual ? 1 : 0) }

  private async emitir(parte: Uint8Array): Promise<void> {
    this.desplazamiento += parte.length
    if (this.desplazamiento > MAX_BYTES) throw new Error('El ZIP supera los 4 GB')
    await this.destino(parte)
  }

  /** Empieza un archivo nuevo; cierra el anterior si seguía abierto */
  async empezar(ruta: string): Promise<void> {
    if (this.cerrado) throw new Error('El ZIP ya está cerrado')
    await this.terminarArchivo()
    if (this.anotadas.length >= MAX_ENTRADAS) throw new Error('Demasiados archivos para un ZIP')
    if (this.rutas.has(ruta)) throw new Error(`Ruta repetida en el ZIP: ${ruta}`)
    if (ruta === '' || ruta.startsWith('/') || ruta.split('/').includes('..')) throw new Error(`Ruta no valida en el ZIP: ${ruta}`)
    this.rutas.add(ruta)
    const nombre = codificador.encode(ruta)
    const local = new DataView(new ArrayBuffer(30))
    local.setUint32(0, 0x04034b50, true)
    local.setUint16(4, 20, true)
    local.setUint16(6, 0x0808, true)     // descriptor de datos (bit 3) y nombres en UTF-8 (bit 11)
    local.setUint16(8, 0, true)          // sin compresion
    local.setUint16(10, this.dos.hora, true)
    local.setUint16(12, this.dos.fecha, true)
    // CRC y tamanos a cero: van en el descriptor que sigue a los datos
    local.setUint16(26, nombre.length, true)
    this.actual = { nombre, crc: 0xffffffff, tamano: 0, desplazamiento: this.desplazamiento }
    await this.emitir(new Uint8Array(local.buffer))
    await this.emitir(nombre)
  }

  /** Añade datos al archivo abierto */
  async escribir(datos: string | Uint8Array): Promise<void> {
    if (!this.actual) throw new Error('No hay ningún archivo abierto en el ZIP')
    const bytes = typeof datos === 'string' ? codificador.encode(datos) : datos
    if (bytes.length === 0) return
    this.actual.crc = crc32Acumulado(this.actual.crc, bytes)
    this.actual.tamano += bytes.length
    if (this.actual.tamano > MAX_BYTES) throw new Error('El ZIP supera los 4 GB')
    await this.emitir(bytes)
  }

  private async terminarArchivo(): Promise<void> {
    const a = this.actual
    if (!a) return
    this.actual = null
    const crc = crc32Final(a.crc)
    const desc = new DataView(new ArrayBuffer(16))
    desc.setUint32(0, 0x08074b50, true)
    desc.setUint32(4, crc, true)
    desc.setUint32(8, a.tamano, true)
    desc.setUint32(12, a.tamano, true)
    await this.emitir(new Uint8Array(desc.buffer))
    this.anotadas.push({ nombre: a.nombre, crc, tamano: a.tamano, desplazamiento: a.desplazamiento })
  }

  /** Cierra el último archivo y escribe el directorio central. Devuelve el tamaño total y el número de archivos */
  async cerrar(): Promise<{ bytes: number; archivos: number }> {
    if (this.cerrado) throw new Error('El ZIP ya está cerrado')
    await this.terminarArchivo()
    this.cerrado = true
    const inicioCentral = this.desplazamiento
    for (const e of this.anotadas) {
      const dir = new DataView(new ArrayBuffer(46))
      dir.setUint32(0, 0x02014b50, true)
      dir.setUint16(4, 20, true)
      dir.setUint16(6, 20, true)
      dir.setUint16(8, 0x0808, true)
      dir.setUint16(10, 0, true)
      dir.setUint16(12, this.dos.hora, true)
      dir.setUint16(14, this.dos.fecha, true)
      dir.setUint32(16, e.crc, true)
      dir.setUint32(20, e.tamano, true)
      dir.setUint32(24, e.tamano, true)
      dir.setUint16(28, e.nombre.length, true)
      dir.setUint32(42, e.desplazamiento, true)
      await this.emitir(new Uint8Array(dir.buffer))
      await this.emitir(e.nombre)
    }
    const tamanoCentral = this.desplazamiento - inicioCentral
    const fin = new DataView(new ArrayBuffer(22))
    fin.setUint32(0, 0x06054b50, true)
    fin.setUint16(8, this.anotadas.length, true)
    fin.setUint16(10, this.anotadas.length, true)
    fin.setUint32(12, tamanoCentral, true)
    fin.setUint32(16, inicioCentral, true)
    await this.emitir(new Uint8Array(fin.buffer))
    return { bytes: this.desplazamiento, archivos: this.anotadas.length }
  }
}
