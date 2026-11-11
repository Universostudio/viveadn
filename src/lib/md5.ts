// MD5 incremental, para calcular la huella de cada CSV de una exportación sin tenerlo entero en memoria (WebCrypto no ofrece MD5 y su
// SHA solo acepta el contenido completo). No es un mecanismo de seguridad: MD5 aquí solo detecta daños y cambios, como en el manifiesto.
// Son funciones puras, sin acceso a la red ni al navegador.

const S = [7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, 5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20,
  4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23, 6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21]
const K = Array.from({ length: 64 }, (_, i) => Math.floor(Math.abs(Math.sin(i + 1)) * 4294967296) >>> 0)

export class Md5 {
  private a = 0x67452301
  private b = 0xefcdab89
  private c = 0x98badcfe
  private d = 0x10325476
  private bloque = new Uint8Array(64)
  private enBloque = 0
  private total = 0
  private cerrado = false

  update(datos: Uint8Array): this {
    if (this.cerrado) throw new Error('El MD5 ya se cerró')
    this.total += datos.length
    let pos = 0
    if (this.enBloque > 0) {
      const toma = Math.min(64 - this.enBloque, datos.length)
      this.bloque.set(datos.subarray(0, toma), this.enBloque)
      this.enBloque += toma; pos = toma
      if (this.enBloque < 64) return this
      this.procesar(this.bloque, 0); this.enBloque = 0
    }
    for (; pos + 64 <= datos.length; pos += 64) this.procesar(datos, pos)
    if (pos < datos.length) { this.bloque.set(datos.subarray(pos), 0); this.enBloque = datos.length - pos }
    return this
  }

  /** Cierra el cálculo y devuelve el resumen en hexadecimal minúscula (32 caracteres). Solo se puede llamar una vez. */
  hex(): string {
    if (this.cerrado) throw new Error('El MD5 ya se cerró')
    const bits = this.total * 8
    const relleno = new Uint8Array(((this.enBloque < 56 ? 56 : 120) - this.enBloque) + 8)
    relleno[0] = 0x80
    const dv = new DataView(relleno.buffer)
    dv.setUint32(relleno.length - 8, bits >>> 0, true)
    dv.setUint32(relleno.length - 4, Math.floor(bits / 4294967296) >>> 0, true)
    const antes = this.total
    this.update(relleno)
    this.total = antes
    this.cerrado = true
    const salida = new DataView(new ArrayBuffer(16))
    ;[this.a, this.b, this.c, this.d].forEach((v, i) => salida.setUint32(i * 4, v >>> 0, true))
    return Array.from(new Uint8Array(salida.buffer), x => x.toString(16).padStart(2, '0')).join('')
  }

  private procesar(m: Uint8Array, desde: number): void {
    const w = new Uint32Array(16)
    for (let i = 0; i < 16; i++) {
      const p = desde + i * 4
      w[i] = (m[p]! | (m[p + 1]! << 8) | (m[p + 2]! << 16) | (m[p + 3]! << 24)) >>> 0
    }
    let a = this.a, b = this.b, c = this.c, d = this.d
    for (let i = 0; i < 64; i++) {
      let f: number, g: number
      if (i < 16) { f = (b & c) | (~b & d); g = i }
      else if (i < 32) { f = (d & b) | (~d & c); g = (5 * i + 1) % 16 }
      else if (i < 48) { f = b ^ c ^ d; g = (3 * i + 5) % 16 }
      else { f = c ^ (b | ~d); g = (7 * i) % 16 }
      f = (f + a + K[i]! + w[g]!) >>> 0
      a = d; d = c; c = b
      b = (b + (((f << S[i]!) | (f >>> (32 - S[i]!))) >>> 0)) >>> 0
    }
    this.a = (this.a + a) >>> 0; this.b = (this.b + b) >>> 0; this.c = (this.c + c) >>> 0; this.d = (this.d + d) >>> 0
  }
}

export const md5Hex = (datos: Uint8Array): string => new Md5().update(datos).hex()
