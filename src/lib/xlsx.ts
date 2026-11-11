// Escritor mínimo de Excel (.xlsx) sin dependencias, sobre el escritor de ZIP. Cada tabla del informe es una hoja;
// los pares de resumen van a la primera. Los textos se guardan como texto (inlineStr), de modo que una celda que
// empiece por = + - o @ nunca se evalúa como fórmula.
import { crearZip } from './zip.ts'
import type { EntradaZip } from './zip.ts'
import type { Columna, Informe, Valor } from './informeTipos.ts'

const MAX_FILAS_HOJA = 1_048_576
const MAX_TEXTO = 32_767

// Caracteres que XML 1.0 no admite, y sustitutos sueltos
const INVALIDO_RE = /[\u0000-\u0008\u000B\u000C\u000E-\u001F￾￿]|[\uD800-\uDBFF](?![\uDC00-\uDFFF])|(?<![\uD800-\uDBFF])[\uDC00-\uDFFF]/g
export const xmlTexto = (s: string) => s.replace(INVALIDO_RE, '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;')

export function nombreHoja(nombre: string, usados: Set<string>): string {
  let base = nombre.replace(/[[\]:*?/\\]/g, ' ').replace(/^'+|'+$/g, '').replace(/\s+/g, ' ').trim().slice(0, 31) || 'Hoja'
  let n = base; let i = 2
  while (usados.has(n.toLowerCase())) { const sufijo = ` ${i++}`; n = base.slice(0, 31 - sufijo.length) + sufijo }
  usados.add(n.toLowerCase())
  return n
}

// Letras de columna: 0 → A, 25 → Z, 26 → AA
export function letraColumna(i: number): string {
  let s = ''
  for (let n = i; n >= 0; n = Math.floor(n / 26) - 1) s = String.fromCharCode(65 + (n % 26)) + s
  return s
}

// Número de serie de Excel (días desde 1899-12-30) para AAAA-MM-DD o una fecha ISO; null si no es una fecha
export function serieFecha(v: string): number | null {
  const m = /^(\d{4})-(\d{2})-(\d{2})(?:[T ](\d{2}):(\d{2}))?/.exec(v)
  if (!m) return null
  const a = Number(m[1]), mes = Number(m[2]), d = Number(m[3])
  const f = new Date(Date.UTC(a, mes - 1, d))
  if (f.getUTCFullYear() !== a || f.getUTCMonth() !== mes - 1 || f.getUTCDate() !== d || a < 1900) return null
  return (f.getTime() - Date.UTC(1899, 11, 30)) / 86_400_000
}

// Estilos (índices de cellXfs)
const E = { normal: 0, cabecera: 1, titulo: 2, fecha: 3, entero: 4, decimal: 5, porcentaje: 6, nota: 7, etiqueta: 8 }

const ESTILOS = `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
<numFmts count="2"><numFmt numFmtId="164" formatCode="yyyy\\-mm\\-dd"/><numFmt numFmtId="165" formatCode="0.0%"/></numFmts>
<fonts count="5">
<font><sz val="11"/><name val="Calibri"/><family val="2"/></font>
<font><b/><sz val="11"/><color rgb="FFFFFFFF"/><name val="Calibri"/><family val="2"/></font>
<font><b/><sz val="16"/><color rgb="FF00523C"/><name val="Calibri"/><family val="2"/></font>
<font><i/><sz val="10"/><color rgb="FF666666"/><name val="Calibri"/><family val="2"/></font>
<font><b/><sz val="11"/><name val="Calibri"/><family val="2"/></font>
</fonts>
<fills count="3"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill><fill><patternFill patternType="solid"><fgColor rgb="FF00523C"/><bgColor indexed="64"/></patternFill></fill></fills>
<borders count="2"><border><left/><right/><top/><bottom/><diagonal/></border><border><left/><right/><top/><bottom style="thin"><color rgb="FFCCCCCC"/></bottom><diagonal/></border></borders>
<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>
<cellXfs count="9">
<xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>
<xf numFmtId="0" fontId="1" fillId="2" borderId="0" xfId="0" applyFont="1" applyFill="1" applyAlignment="1"><alignment vertical="center" wrapText="1"/></xf>
<xf numFmtId="0" fontId="2" fillId="0" borderId="0" xfId="0" applyFont="1"/>
<xf numFmtId="164" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/>
<xf numFmtId="3" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/>
<xf numFmtId="4" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/>
<xf numFmtId="165" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/>
<xf numFmtId="0" fontId="3" fillId="0" borderId="0" xfId="0" applyFont="1"/>
<xf numFmtId="0" fontId="4" fillId="0" borderId="1" xfId="0" applyFont="1" applyBorder="1"/>
</cellXfs>
<cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>
</styleSheet>`

function celdaTexto(ref: string, s: number, texto: string): string {
  const t = xmlTexto(texto.length > MAX_TEXTO ? texto.slice(0, MAX_TEXTO) : texto)
  return `<c r="${ref}" s="${s}" t="inlineStr"><is><t xml:space="preserve">${t}</t></is></c>`
}

function celda(ref: string, valor: Valor, col: Columna | undefined): string {
  if (valor === null || valor === undefined || valor === '') return ''
  const tipo = col?.tipo ?? 'texto'
  if (typeof valor === 'boolean') return celdaTexto(ref, E.normal, valor ? 'true' : 'false')
  if (typeof valor === 'number') {
    if (!Number.isFinite(valor)) return ''
    const s = tipo === 'porcentaje' ? E.porcentaje : tipo === 'decimal' ? E.decimal : tipo === 'entero' ? E.entero : E.normal
    return `<c r="${ref}" s="${s}"><v>${valor}</v></c>`
  }
  if (tipo === 'fecha') {
    const n = serieFecha(valor)
    if (n !== null) return `<c r="${ref}" s="${E.fecha}"><v>${n}</v></c>`
  }
  return celdaTexto(ref, E.normal, valor)
}

interface HojaXml { nombre: string; xml: string }

function hojaTabla(nombre: string, titulo: string, subtitulo: string, columnas: Columna[], filas: Valor[][]): HojaXml {
  const filasXml: string[] = []
  let r = 1
  filasXml.push(`<row r="${r}" ht="24" customHeight="1">${celdaTexto(`A${r}`, E.titulo, titulo)}</row>`); r++
  filasXml.push(`<row r="${r}">${celdaTexto(`A${r}`, E.nota, subtitulo)}</row>`); r += 2
  const filaCabecera = r
  filasXml.push(`<row r="${r}" ht="30" customHeight="1">${columnas.map((c, i) => celdaTexto(`${letraColumna(i)}${r}`, E.cabecera, c.titulo)).join('')}</row>`); r++
  if (filas.length > MAX_FILAS_HOJA - r) throw new Error('Demasiadas filas para una hoja de Excel')
  for (const f of filas) {
    filasXml.push(`<row r="${r}">${columnas.map((c, i) => celda(`${letraColumna(i)}${r}`, f[i] ?? null, c)).join('')}</row>`)
    r++
  }
  const ultima = letraColumna(Math.max(columnas.length - 1, 0))
  const cols = columnas.map((c, i) => `<col min="${i + 1}" max="${i + 1}" width="${Math.min(Math.max(c.ancho ?? 14, 6), 60)}" customWidth="1"/>`).join('')
  const xml = `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><dimension ref="A1:${ultima}${r - 1}"/><sheetViews><sheetView workbookViewId="0"><pane ySplit="${filaCabecera}" topLeftCell="A${filaCabecera + 1}" activePane="bottomLeft" state="frozen"/></sheetView></sheetViews><sheetFormatPr defaultRowHeight="15"/><cols>${cols}</cols><sheetData>${filasXml.join('')}</sheetData>${filas.length ? `<autoFilter ref="A${filaCabecera}:${ultima}${r - 1}"/>` : ''}</worksheet>`
  return { nombre, xml }
}

function hojaResumen(nombre: string, informe: Informe): HojaXml {
  const filas: string[] = []
  let r = 1
  filas.push(`<row r="${r}" ht="24" customHeight="1">${celdaTexto(`A${r}`, E.titulo, informe.titulo)}</row>`); r++
  filas.push(`<row r="${r}">${celdaTexto(`A${r}`, E.nota, informe.subtitulo)}</row>`); r += 2
  for (const s of informe.secciones) {
    if (s.tipo !== 'pares') continue
    if (s.titulo) { filas.push(`<row r="${r}">${celdaTexto(`A${r}`, E.etiqueta, s.titulo)}${celdaTexto(`B${r}`, E.etiqueta, '')}</row>`); r++ }
    for (const [k, v] of s.pares) { filas.push(`<row r="${r}">${celdaTexto(`A${r}`, E.normal, k)}${celda(`B${r}`, v, { titulo: k, tipo: typeof v === 'number' ? (Number.isInteger(v) ? 'entero' : 'decimal') : 'texto' })}</row>`); r++ }
    r++
  }
  const xml = `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><dimension ref="A1:B${Math.max(r - 1, 1)}"/><sheetViews><sheetView workbookViewId="0" showGridLines="0"/></sheetViews><sheetFormatPr defaultRowHeight="15"/><cols><col min="1" max="1" width="46" customWidth="1"/><col min="2" max="2" width="18" customWidth="1"/></cols><sheetData>${filas.join('')}</sheetData></worksheet>`
  return { nombre, xml }
}

export function crearXlsx(informe: Informe): Uint8Array {
  const usados = new Set<string>()
  const hojas: HojaXml[] = []
  if (informe.secciones.some(s => s.tipo === 'pares')) hojas.push(hojaResumen(nombreHoja(informe.hojaResumen ?? 'Resumen', usados), informe))
  for (const s of informe.secciones) {
    if (s.tipo !== 'tabla') continue
    hojas.push(hojaTabla(nombreHoja(s.hoja ?? s.titulo ?? 'Datos', usados), s.titulo ?? informe.titulo, informe.subtitulo, s.columnas, s.filas))
  }
  if (!hojas.length) hojas.push(hojaResumen(nombreHoja('Resumen', usados), informe))

  const ns = 'xmlns="http://schemas.openxmlformats.org/package/2006/relationships"'
  const iso = informe.generado.toISOString().replace(/\.\d{3}Z$/, 'Z')
  const entradas: EntradaZip[] = [
    { ruta: '[Content_Types].xml', contenido: `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>${hojas.map((_, i) => `<Override PartName="/xl/worksheets/sheet${i + 1}.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>`).join('')}<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/><Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/><Override PartName="/docProps/app.xml" ContentType="application/vnd.openxmlformats-officedocument.extended-properties+xml"/></Types>` },
    { ruta: '_rels/.rels', contenido: `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships ${ns}><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/><Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/extended-properties" Target="docProps/app.xml"/></Relationships>` },
    { ruta: 'docProps/core.xml', contenido: `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:dcterms="http://purl.org/dc/terms/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"><dc:title>${xmlTexto(informe.titulo)}</dc:title><dc:creator>ViveADN</dc:creator><dcterms:created xsi:type="dcterms:W3CDTF">${iso}</dcterms:created></cp:coreProperties>` },
    { ruta: 'docProps/app.xml', contenido: `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties"><Application>ViveADN</Application></Properties>` },
    { ruta: 'xl/workbook.xml', contenido: `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets>${hojas.map((h, i) => `<sheet name="${xmlTexto(h.nombre)}" sheetId="${i + 1}" r:id="rId${i + 1}"/>`).join('')}</sheets></workbook>` },
    { ruta: 'xl/_rels/workbook.xml.rels', contenido: `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships ${ns}>${hojas.map((_, i) => `<Relationship Id="rId${i + 1}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet${i + 1}.xml"/>`).join('')}<Relationship Id="rId${hojas.length + 1}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/></Relationships>` },
    { ruta: 'xl/styles.xml', contenido: ESTILOS },
    ...hojas.map((h, i) => ({ ruta: `xl/worksheets/sheet${i + 1}.xml`, contenido: h.xml })),
  ]
  return crearZip(entradas, informe.generado)
}
