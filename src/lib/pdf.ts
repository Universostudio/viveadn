// Generador de PDF sin dependencias: Helvetica y Helvetica-Bold estándar (WinAnsi), tablas con paginación y gráfico de
// barras. Los caracteres que WinAnsi no tiene (alfabetos no latinos, emoji) salen como "?": es el límite de no incrustar
// una tipografía. Son funciones puras: devuelven los bytes del archivo.
import type { Columna, Informe, Seccion, Valor } from './informeTipos.ts'

// Anchos de glifo (milésimas de em) por código WinAnsi, tomados de las métricas oficiales de Helvetica
const ANCHO_NORMAL = [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,278,278,355,556,556,889,667,191,333,333,389,584,278,333,278,278,556,556,556,556,556,556,556,556,556,556,278,278,584,584,584,556,1015,667,667,722,722,667,611,778,722,278,500,667,556,833,722,778,667,778,722,667,611,722,667,944,667,667,611,278,278,278,469,556,333,556,556,500,556,556,278,556,556,222,222,500,222,833,556,556,556,556,333,500,278,556,500,722,500,500,500,334,260,334,584,350,556,350,222,556,333,1000,556,556,333,1000,667,333,1000,350,611,350,350,222,222,333,333,350,556,1000,333,1000,500,333,944,350,500,667,278,333,556,556,556,556,260,556,333,737,370,556,584,333,737,333,400,584,333,333,333,556,537,278,333,333,365,556,834,834,834,611,667,667,667,667,667,667,1000,722,667,667,667,667,278,278,278,278,722,722,778,778,778,778,778,584,778,722,722,722,722,667,667,611,556,556,556,556,556,556,889,500,556,556,556,556,278,278,278,278,556,556,556,556,556,556,556,584,611,556,556,556,556,500,556,500]
const ANCHO_NEGRITA = [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,278,333,474,556,556,889,722,238,333,333,389,584,278,333,278,278,556,556,556,556,556,556,556,556,556,556,333,333,584,584,584,611,975,722,722,722,722,667,611,778,722,278,556,722,611,833,722,778,667,778,722,667,611,722,667,944,667,667,611,333,278,333,584,556,333,556,611,556,611,556,333,611,611,278,278,556,278,889,611,611,611,611,389,556,333,611,556,778,556,556,500,389,280,389,584,350,556,350,278,556,500,1000,556,556,333,1000,667,333,1000,350,611,350,350,278,278,500,500,350,556,1000,333,1000,556,333,944,350,500,667,278,333,556,556,556,556,280,556,333,737,370,556,584,333,737,333,400,584,333,333,333,611,556,278,333,333,365,556,834,834,834,611,722,722,722,722,722,722,1000,722,667,667,667,667,278,278,278,278,722,722,778,778,778,778,778,584,778,722,722,722,722,667,667,611,556,556,556,556,556,556,889,556,556,556,556,556,278,278,278,278,611,611,611,611,611,611,611,584,611,611,611,611,611,556,611,556]

// Códigos 0x80-0x9F de WinAnsi (cp1252) que no coinciden con Unicode
const ESPECIALES: Record<number, number> = {
  0x20ac: 0x80, 0x201a: 0x82, 0x0192: 0x83, 0x201e: 0x84, 0x2026: 0x85, 0x2020: 0x86, 0x2021: 0x87, 0x02c6: 0x88, 0x2030: 0x89,
  0x0160: 0x8a, 0x2039: 0x8b, 0x0152: 0x8c, 0x017d: 0x8e, 0x2018: 0x91, 0x2019: 0x92, 0x201c: 0x93, 0x201d: 0x94, 0x2022: 0x95,
  0x2013: 0x96, 0x2014: 0x97, 0x02dc: 0x98, 0x2122: 0x99, 0x0161: 0x9a, 0x203a: 0x9b, 0x0153: 0x9c, 0x017e: 0x9e, 0x0178: 0x9f,
}

// Texto Unicode a bytes WinAnsi; lo que no existe sale como "?" y los saltos de línea como espacio
export function aWinAnsi(texto: string): number[] {
  const bytes: number[] = []
  for (const ch of texto.normalize('NFC')) {
    const c = ch.codePointAt(0)!
    if (c === 0x0a || c === 0x0d || c === 0x09) bytes.push(0x20)
    // Espacios especiales (Intl los usa en francés y otros idiomas para miles y porcentajes): WinAnsi solo tiene el normal y el duro
    else if ((c >= 0x2000 && c <= 0x200a) || c === 0x202f || c === 0x205f || c === 0x3000) bytes.push(0x20)
    else if (c < 0x20 || c === 0x7f) continue
    else if (c < 0x80 || (c >= 0xa0 && c <= 0xff)) bytes.push(c)
    else bytes.push(ESPECIALES[c] ?? 0x3f)
  }
  return bytes
}

export function anchoTexto(bytes: number[], tam: number, negrita = false): number {
  const t = negrita ? ANCHO_NEGRITA : ANCHO_NORMAL
  let a = 0
  for (const b of bytes) a += t[b] ?? 556
  return (a * tam) / 1000
}

// Recorta con "..." para que quepa en `max` puntos
export function ajustar(texto: string, max: number, tam: number, negrita = false): number[] {
  const bytes = aWinAnsi(texto)
  if (anchoTexto(bytes, tam, negrita) <= max) return bytes
  const punto = aWinAnsi('...')
  const reserva = anchoTexto(punto, tam, negrita)
  let n = bytes.length
  while (n > 0 && anchoTexto(bytes.slice(0, n), tam, negrita) + reserva > max) n--
  return [...bytes.slice(0, n), ...punto]
}

// Cadena literal PDF: los paréntesis, la barra y los bytes altos se escapan
function literal(bytes: number[]): string {
  let s = '('
  for (const b of bytes) {
    if (b === 0x28 || b === 0x29 || b === 0x5c) s += '\\' + String.fromCharCode(b)
    else if (b < 0x20 || b > 0x7e) s += '\\' + b.toString(8).padStart(3, '0')
    else s += String.fromCharCode(b)
  }
  return s + ')'
}

// Cadena de metadatos en UTF-16BE con BOM, para que el título conserve cualquier carácter
function utf16Hex(texto: string): string {
  let h = 'FEFF'
  for (let i = 0; i < texto.length; i++) h += texto.charCodeAt(i).toString(16).padStart(4, '0').toUpperCase()
  return `<${h}>`
}

const num = (n: number) => (Math.round(n * 100) / 100).toString()
const VERDE = '0 0.322 0.235', VERDE_CLARO = '0.043 0.478 0.345', GRIS = '0.4 0.4 0.4', TEXTO = '0.13 0.13 0.13', ZEBRA = '0.965 0.961 0.945', CABECERA_FONDO = '0.902 0.937 0.925', LINEA = '0.82 0.82 0.82'

function formatear(v: Valor, col: Columna, locale: string): string {
  if (v === null || v === undefined || v === '') return ''
  if (typeof v === 'boolean') return v ? 'true' : 'false'
  if (typeof v === 'number') {
    if (!Number.isFinite(v)) return ''
    if (col.tipo === 'porcentaje') return new Intl.NumberFormat(locale, { style: 'percent', maximumFractionDigits: 1 }).format(v)
    if (col.tipo === 'decimal') return new Intl.NumberFormat(locale, { minimumFractionDigits: 2, maximumFractionDigits: 2 }).format(v)
    return new Intl.NumberFormat(locale, { maximumFractionDigits: 2 }).format(v)
  }
  if (col.tipo === 'fecha') return v.slice(0, 10)
  return v
}

interface Pagina { ops: string[] }

export function crearPdf(informe: Informe): Uint8Array {
  const locale = informe.locale ?? 'es'
  const ancho = informe.apaisado ? 841.89 : 595.28
  const alto = informe.apaisado ? 595.28 : 841.89
  const margen = 40
  const util = ancho - margen * 2
  const cabeceraAlto = 62
  const pieAlto = 34
  const paginas: Pagina[] = []
  let pag: Pagina
  let y = 0

  const nueva = () => {
    pag = { ops: [] }
    paginas.push(pag)
    texto(informe.titulo, margen, alto - margen - 14, 16, true, VERDE)
    texto(informe.subtitulo, margen, alto - margen - 30, 9, false, GRIS)
    linea(margen, alto - margen - 40, ancho - margen, alto - margen - 40, VERDE_CLARO, 1.2)
    y = alto - margen - cabeceraAlto
  }
  const texto = (t: string, x: number, yy: number, tam: number, negrita: boolean, color = TEXTO, bytes?: number[]) => {
    pag.ops.push(`BT /${negrita ? 'F2' : 'F1'} ${num(tam)} Tf ${color} rg ${num(x)} ${num(yy)} Td ${literal(bytes ?? aWinAnsi(t))} Tj ET`)
  }
  const rect = (x: number, yy: number, w: number, h: number, color: string) => pag.ops.push(`${color} rg ${num(x)} ${num(yy)} ${num(w)} ${num(h)} re f`)
  const linea = (x1: number, y1: number, x2: number, y2: number, color: string, grosor = 0.5) =>
    pag.ops.push(`${color} RG ${num(grosor)} w ${num(x1)} ${num(y1)} m ${num(x2)} ${num(y2)} l S`)
  const hayEspacio = (necesario: number) => y - necesario >= margen + pieAlto

  const tituloSeccion = (t: string, necesario: number) => {
    if (!hayEspacio(necesario + 24)) nueva()
    y -= 8
    texto(t, margen, y - 10, 11.5, true, VERDE)
    y -= 22
  }

  nueva()
  for (const s of informe.secciones as Seccion[]) {
    if (s.tipo === 'pares') {
      const filas = s.pares.length
      tituloSeccion(s.titulo ?? '', Math.min(filas, 4) * 16)
      const mitad = util * 0.62
      s.pares.forEach(([k, v], i) => {
        if (!hayEspacio(16)) nueva()
        if (i % 2 === 0) rect(margen, y - 12, util, 16, ZEBRA)
        texto('', margen + 6, y - 8, 9, false, TEXTO, ajustar(k, mitad - 12, 9))
        const valor = typeof v === 'number' ? new Intl.NumberFormat(locale, { maximumFractionDigits: 2 }).format(v) : String(v ?? '')
        const b = ajustar(valor, util - mitad - 12, 9, true)
        texto('', margen + util - 6 - anchoTexto(b, 9, true), y - 8, 9, true, TEXTO, b)
        y -= 16
      })
      y -= 6
    } else if (s.tipo === 'tabla') {
      const cols = s.columnas
      const total = cols.reduce((a, c) => a + (c.ancho ?? 14), 0)
      const anchos = cols.map(c => ((c.ancho ?? 14) / total) * util)
      const tam = 8
      const alinear = (c: Columna) => (c.tipo === 'entero' || c.tipo === 'decimal' || c.tipo === 'porcentaje' ? 'der' : 'izq')
      const cabecera = () => {
        rect(margen, y - 14, util, 18, CABECERA_FONDO)
        let x = margen
        cols.forEach((c, i) => {
          const b = ajustar(c.titulo, anchos[i]! - 8, tam, true)
          texto('', alinear(c) === 'der' ? x + anchos[i]! - 4 - anchoTexto(b, tam, true) : x + 4, y - 9, tam, true, VERDE, b)
          x += anchos[i]!
        })
        y -= 18
      }
      if (s.titulo) tituloSeccion(s.titulo, 18 + 14 * Math.min(s.filas.length, 3))
      else if (!hayEspacio(18 + 14)) nueva()
      cabecera()
      s.filas.forEach((f, ri) => {
        if (!hayEspacio(14)) { nueva(); cabecera() }
        if (ri % 2 === 1) rect(margen, y - 10.5, util, 14, ZEBRA)
        let x = margen
        cols.forEach((c, i) => {
          const b = ajustar(formatear(f[i] ?? null, c, locale), anchos[i]! - 8, tam)
          texto('', alinear(c) === 'der' ? x + anchos[i]! - 4 - anchoTexto(b, tam) : x + 4, y - 7.5, tam, false, TEXTO, b)
          x += anchos[i]!
        })
        y -= 14
      })
      linea(margen, y + 3.5, margen + util, y + 3.5, LINEA)
      y -= 10
    } else {
      // Barras verticales con escala redondeada
      const altoGrafico = 150
      tituloSeccion(s.titulo, altoGrafico + 40)
      const max = Math.max(...s.valores, 0)
      const paso = (() => { if (max <= 0) return 1; const e = Math.pow(10, Math.floor(Math.log10(max / 4))); const f = max / 4 / e; return (f <= 1 ? 1 : f <= 2 ? 2 : f <= 5 ? 5 : 10) * e })()
      const tope = Math.max(Math.ceil(max / paso), 1) * paso
      const izq = margen + 34
      const areaAncho = util - 34
      const base = y - altoGrafico
      for (let g = 0; g <= tope + 1e-9; g += paso) {
        const gy = base + (g / tope) * altoGrafico
        linea(izq, gy, margen + util, gy, LINEA, 0.4)
        const b = aWinAnsi(new Intl.NumberFormat(locale, { maximumFractionDigits: 1 }).format(g))
        texto('', izq - 4 - anchoTexto(b, 7), gy - 2.5, 7, false, GRIS, b)
      }
      const n = Math.max(s.valores.length, 1)
      const hueco = areaAncho / n
      const barra = Math.min(hueco * 0.62, 34)
      const cadaCuantas = Math.max(1, Math.ceil(26 / hueco))
      s.valores.forEach((v, i) => {
        const bx = izq + i * hueco + (hueco - barra) / 2
        const bh = (v / tope) * altoGrafico
        if (bh > 0) rect(bx, base, barra, bh, VERDE_CLARO)
        if (hueco >= 16) {
          const vb = aWinAnsi(new Intl.NumberFormat(locale, { maximumFractionDigits: 0 }).format(v))
          texto('', bx + barra / 2 - anchoTexto(vb, 6.5) / 2, base + bh + 3, 6.5, false, TEXTO, vb)
        }
        if (i % cadaCuantas === 0) {
          const lb = ajustar(s.etiquetas[i] ?? '', hueco * cadaCuantas, 6.5)
          texto('', bx + barra / 2 - anchoTexto(lb, 6.5) / 2, base - 10, 6.5, false, GRIS, lb)
        }
      })
      linea(izq, base, margen + util, base, GRIS, 0.8)
      y = base - 24
    }
  }

  // Pie con el número de página, ya conocido el total
  const totalPag = paginas.length
  paginas.forEach((p, i) => {
    const pie = ajustar(informe.pie, util * 0.7, 7.5)
    p.ops.push(`BT /F1 7.5 Tf ${GRIS} rg ${num(margen)} ${num(margen - 6)} Td ${literal(pie)} Tj ET`)
    const pg = aWinAnsi((informe.textoPagina ?? 'Page {n} of {total}').replace('{n}', String(i + 1)).replace('{total}', String(totalPag)))
    p.ops.push(`BT /F1 7.5 Tf ${GRIS} rg ${num(ancho - margen - anchoTexto(pg, 7.5))} ${num(margen - 6)} Td ${literal(pg)} Tj ET`)
  })

  // Estructura del archivo: 1 catálogo, 2 páginas, 3 y 4 tipografías, 5 información y luego (página, contenido) por página
  const partes: string[] = []
  const offsets: number[] = []
  let pos = 0
  const emitir = (s: string) => { partes.push(s); pos += s.length }
  const objeto = (n: number, cuerpo: string) => { offsets[n] = pos; emitir(`${n} 0 obj\n${cuerpo}\nendobj\n`) }
  emitir('%PDF-1.4\n%\xE2\xE3\xCF\xD3\n')
  const idPagina = (i: number) => 6 + i * 2
  objeto(1, '<< /Type /Catalog /Pages 2 0 R >>')
  objeto(2, `<< /Type /Pages /Count ${totalPag} /Kids [${paginas.map((_, i) => `${idPagina(i)} 0 R`).join(' ')}] >>`)
  objeto(3, '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>')
  objeto(4, '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold /Encoding /WinAnsiEncoding >>')
  const f = informe.generado
  const p2 = (n: number) => String(n).padStart(2, '0')
  const fecha = `D:${f.getUTCFullYear()}${p2(f.getUTCMonth() + 1)}${p2(f.getUTCDate())}${p2(f.getUTCHours())}${p2(f.getUTCMinutes())}${p2(f.getUTCSeconds())}Z`
  objeto(5, `<< /Title ${utf16Hex(informe.titulo)} /Producer (Vive ADN) /Creator (Vive ADN) /CreationDate (${fecha}) >>`)
  paginas.forEach((p, i) => {
    const contenido = p.ops.join('\n')
    objeto(idPagina(i), `<< /Type /Page /Parent 2 0 R /MediaBox [0 0 ${num(ancho)} ${num(alto)}] /Resources << /Font << /F1 3 0 R /F2 4 0 R >> >> /Contents ${idPagina(i) + 1} 0 R >>`)
    objeto(idPagina(i) + 1, `<< /Length ${contenido.length} >>\nstream\n${contenido}\nendstream`)
  })
  const total = 6 + totalPag * 2
  const xref = pos
  emitir(`xref\n0 ${total}\n0000000000 65535 f \n`)
  for (let n = 1; n < total; n++) emitir(`${String(offsets[n]).padStart(10, '0')} 00000 n \n`)
  emitir(`trailer\n<< /Size ${total} /Root 1 0 R /Info 5 0 R >>\nstartxref\n${xref}\n%%EOF\n`)
  // Todo es ASCII salvo el comentario binario de la cabecera y los bytes ya escapados, así que cada carácter es un byte
  const salida = new Uint8Array(pos)
  let k = 0
  for (const s of partes) for (let i = 0; i < s.length; i++) salida[k++] = s.charCodeAt(i) & 0xff
  return salida
}
