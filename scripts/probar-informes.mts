// Pruebas de los informes en PDF y Excel. Uso: npm run test:informes
// Los archivos generados se validan con lectores independientes de Python: pypdf y pdfplumber para el PDF, openpyxl para
// el Excel (pip install openpyxl==3.1.5 pypdf==6.17.0 pdfplumber==0.11.10). Los datos son sintéticos.
import assert from 'node:assert/strict'
import { execFileSync } from 'node:child_process'
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
const { crearPdf, aWinAnsi, anchoTexto, ajustar } = await import('../src/lib/pdf.ts')
const { crearXlsx, nombreHoja, letraColumna, serieFecha, xmlTexto } = await import('../src/lib/xlsx.ts')
const { informeMiembros, informeAsistencia, informeCrecimiento } = await import('../src/lib/informes.ts')

// ---------- Piezas pequeñas ----------
assert.deepEqual(aWinAnsi('Añ€é'), [0x41, 0xf1, 0x80, 0xe9])
assert.deepEqual(aWinAnsi('日本🙏'), [0x3f, 0x3f, 0x3f], 'lo que WinAnsi no tiene sale como ?')
assert.deepEqual(aWinAnsi('a\nb\tc\u0000d'), [0x61, 0x20, 0x62, 0x20, 0x63, 0x64], 'saltos de línea a espacio y controles fuera')
assert.deepEqual(aWinAnsi('1\u202f234\u2009%'), [0x31, 0x20, 0x32, 0x33, 0x34, 0x20, 0x25], 'los espacios finos de Intl (francés) pasan a espacio normal, no a ?')
assert.deepEqual(aWinAnsi('1\u00a0%'), [0x31, 0xa0, 0x25], 'el espacio duro se conserva')
assert.equal(Math.round(anchoTexto(aWinAnsi('Hello'), 10) * 100) / 100, 22.78, 'ancho de "Hello" en Helvetica 10 pt (722+556+222+222+556)')
assert.ok(anchoTexto(aWinAnsi('Hello'), 10, true) > anchoTexto(aWinAnsi('Hello'), 10), 'la negrita es más ancha')
const largo = ajustar('Una cadena muy larga que no cabe en la celda', 60, 8)
assert.ok(anchoTexto(largo, 8) <= 60 && String.fromCharCode(...largo.slice(-3)) === '...', 'se recorta con puntos suspensivos y cabe')
assert.equal(String.fromCharCode(...ajustar('corto', 200, 8)), 'corto')
assert.deepEqual([0, 1, 25, 26, 27, 51, 52, 701, 702].map(letraColumna), ['A', 'B', 'Z', 'AA', 'AB', 'AZ', 'BA', 'ZZ', 'AAA'])
assert.equal(serieFecha('1900-01-01'), 2); assert.equal(serieFecha('2026-11-11'), 46337); assert.equal(serieFecha('2026-11-11T10:00:00Z'), 46337)
assert.equal(serieFecha('2026-02-30'), null); assert.equal(serieFecha('abc'), null)
assert.equal(xmlTexto('a<b>&"c\u0000\u0008d\uD800'), 'a&lt;b&gt;&amp;&quot;cd', 'se escapa XML y se quitan caracteres inválidos')
{
  const usados = new Set<string>()
  assert.equal(nombreHoja('Resumen', usados), 'Resumen'); assert.equal(nombreHoja('resumen', usados), 'resumen 2', 'sin repetir, sin distinguir caja')
  assert.equal(nombreHoja('A/B:C*D?[E]\\F', new Set()), 'A B C D E F', 'sin caracteres prohibidos')
  assert.equal(nombreHoja('x'.repeat(50), new Set()).length, 31); assert.equal(nombreHoja('', new Set()), 'Hoja'); assert.equal(nombreHoja("'ab'", new Set()), 'ab')
  const u2 = new Set<string>(); nombreHoja('x'.repeat(31), u2); assert.equal(nombreHoja('x'.repeat(31), u2).length, 31, 'el sufijo no pasa de 31')
}

// ---------- Traductor real, con las claves de cada idioma ----------
const IDIOMAS = ['es', 'en', 'fr', 'pt-BR'] as const
function traductor(idioma: string) {
  const dic = JSON.parse(readFileSync(new URL(`../src/i18n/locales/${idioma}.json`, import.meta.url), 'utf8'))
  const usadas = new Set<string>()
  const t = (clave: string, params?: Record<string, unknown>) => {
    const v = clave.split('.').reduce((o: any, p) => o?.[p], dic)
    if (typeof v !== 'string') throw new Error(`Falta la clave ${clave} en ${idioma}`)
    usadas.add(clave)
    return v.replace(/\{(\w+)\}/g, (_, k) => String(params?.[k] ?? `{${k}}`))
  }
  return { t, usadas }
}

// ---------- Datos sintéticos ----------
const ahora = new Date('2026-11-11T12:00:00Z')
const filasMiembros = Array.from({ length: 420 }, (_, i) => ({
  crm_id: `ADN-${String(i + 1).padStart(5, '0')}`, nombre: i === 5 ? 'Zoë (el "Pastor")' : i === 6 ? 'Ana\\María' : i === 7 ? '日本語 🙏' : `Nombre${i}`, apellido: i === 5 ? "O'Brien, Jr." : `Apellido ${i}`,
  email: i % 3 ? `m${i}@x.test` : null, telefono: i % 4 ? '+34600111222' : null, fecha_nacimiento: i % 5 ? '1990-05-21' : null, genero: null, casa: i % 6 ? 'Casa Norte' : null,
  nivel_compromiso: ['nuevo', 'en_crecimiento', 'maduro', 'lider', 'multiplicador'][i % 5]!, bautizado: i % 2 === 0, fecha_conversion: i % 7 ? '2025-03-01' : null, activo: i % 10 !== 0, registrado: '2026-01-15',
  ...(i === 8 ? { nombre: '=SUMA(1+1)', apellido: '@cmd' } : {}),
}))
const resumenMiembros = { total: 420, activos: 378, inactivos: 42, bautizados: 210, con_correo: 280, con_telefono: 315, sin_casa: 70, por_nivel: { nuevo: 84, en_crecimiento: 84, maduro: 84, lider: 84, multiplicador: 84 } }
const asistencia = {
  desde: '2026-10-15', hasta: '2026-11-11',
  casas: { registros: 120, presentes: 90, semanal: [{ semana: '2026-10-12', registros: 30, presentes: 20 }, { semana: '2026-10-19', registros: 30, presentes: 25 }, { semana: '2026-10-26', registros: 30, presentes: 22 }, { semana: '2026-11-02', registros: 30, presentes: 23 }],
    por_casa: [{ casa: 'Casa Norte', registros: 60, presentes: 50, personas: 12 }, { casa: 'Casa Sur (nueva)', registros: 60, presentes: 40, personas: 9 }] },
  eventos: { registros: 100, presentes: 80, lista: [{ titulo: 'Culto, domingo', tipo: 'culto', inicia_en: '2026-11-01T10:00:00+00:00', registros: 60, presentes: 50 }, { titulo: 'Vigilia', tipo: null, inicia_en: '2026-11-06T23:00:00+00:00', registros: 40, presentes: 30 }] },
}
const crecimiento = Array.from({ length: 12 }, (_, i) => ({ mes: `2026-${String(i % 12 + 1).padStart(2, '0')}-01`, nuevos_miembros: (i * 7) % 23, miembros_acumulados: 100 + i * 12, conversiones: i, bautizos: i % 3, consolidaciones_iniciadas: i + 1, consolidaciones_completadas: i }))

// ---------- Los tres informes, en los cuatro idiomas ----------
for (const idioma of IDIOMAS) {
  const { t } = traductor(idioma)
  const ctx = { t, locale: idioma, iglesia: 'Iglesia "Exportación", S.L.', ahora }
  for (const inf of [informeMiembros(resumenMiembros, filasMiembros, ctx), informeAsistencia(asistencia, ctx), informeCrecimiento(crecimiento, ctx)]) {
    assert.ok(inf.titulo && inf.subtitulo.includes('Exportación') && inf.pie.includes(inf.titulo), `${idioma}: título, subtítulo y pie`)
    assert.ok(inf.textoPagina?.includes('{n}') && inf.textoPagina.includes('{total}'), `${idioma}: el texto de página conserva sus marcadores`)
    crearPdf(inf); crearXlsx(inf)
  }
}
console.log('   Los tres informes se construyen en es, en, fr y pt-BR sin claves que falten')

// ---------- Las cifras de los informes salen de los datos ----------
const es = traductor('es')
const ctxEs = { t: es.t, locale: 'es', iglesia: 'Mi iglesia', ahora }
{
  const c = informeCrecimiento(crecimiento, ctxEs)
  const pares = Object.fromEntries((c.secciones.find(s => s.tipo === 'pares') as any).pares)
  assert.equal(pares['Miembros registrados'], 100 + 11 * 12, 'registrados = el acumulado del último mes')
  assert.equal(pares['Nuevos miembros en el período'], crecimiento.reduce((a, f) => a + f.nuevos_miembros, 0))
  assert.equal(pares['Bautizos'], crecimiento.reduce((a, f) => a + f.bautizos, 0))
  const barras = c.secciones.find(s => s.tipo === 'barras') as any
  assert.deepEqual(barras.valores, crecimiento.map(f => f.nuevos_miembros)); assert.equal(barras.etiquetas.length, 12)
  const a = informeAsistencia(asistencia, ctxEs)
  const pa = Object.fromEntries((a.secciones.find(s => s.tipo === 'pares') as any).pares)
  const sinNbsp = (v: unknown) => String(v).replace(/\u00a0/g, ' ')
  assert.equal(sinNbsp(pa['Reuniones de casa: asistencia']), '75 %'); assert.equal(sinNbsp(pa['Eventos: asistencia']), '80 %')
  const casas = a.secciones.find(s => s.tipo === 'tabla' && s.hoja === 'Por casa') as any
  assert.deepEqual(casas.filas[1], ['Casa Sur (nueva)', 60, 40, 9, 40 / 60])
  const sinDatos = informeAsistencia({ ...asistencia, casas: { registros: 0, presentes: 0, semanal: [], por_casa: [] }, eventos: { registros: 0, presentes: 0, lista: [] } }, ctxEs)
  assert.ok(!sinDatos.secciones.some(s => s.tipo === 'barras'), 'sin semanas no hay gráfico')
  assert.equal(Object.fromEntries((sinDatos.secciones.find(s => s.tipo === 'pares') as any).pares)['Reuniones de casa: asistencia'], '—', 'sin registros el porcentaje no es 0 ni NaN')
  crearPdf(sinDatos); crearXlsx(sinDatos); crearPdf(informeCrecimiento([], ctxEs)); crearXlsx(informeCrecimiento([], ctxEs))
  const m = informeMiembros(resumenMiembros, filasMiembros, ctxEs)
  const tabla = m.secciones.find(s => s.tipo === 'tabla') as any
  assert.equal(tabla.filas.length, 420); assert.equal(tabla.filas[0][8], 'Sí'); assert.equal(tabla.filas[1][8], 'No')
  assert.equal(m.apaisado, true)
}

// ---------- Validación con lectores independientes ----------
function py(codigo: string, ...args: string[]): any {
  return JSON.parse(execFileSync('python3', ['-I', '-c', codigo, ...args], { encoding: 'utf8', maxBuffer: 256 * 1024 * 1024 }))
}
const dir = mkdtempSync(join(tmpdir(), 'informes-'))
try {
  // PDF de miembros: 420 filas en apaisado
  const infM = informeMiembros(resumenMiembros, filasMiembros, ctxEs)
  const pdfM = crearPdf(infM); writeFileSync(join(dir, 'm.pdf'), pdfM)
  assert.equal(new TextDecoder('latin1').decode(pdfM.slice(0, 8)), '%PDF-1.4\n'.slice(0, 8)); assert.ok(new TextDecoder('latin1').decode(pdfM.slice(-6)).includes('%%EOF'))
  const r = py(`
import sys, json, re, pypdf, pdfplumber
rd = pypdf.PdfReader(sys.argv[1], strict=True)
n = len(rd.pages)
w = rd.pages[0].mediabox
meta = rd.metadata
textos = []
with pdfplumber.open(sys.argv[1]) as pdf:
    for p in pdf.pages: textos.append(p.extract_text() or '')
todo = '\\n'.join(textos)
print(json.dumps({'paginas': n, 'ancho': float(w.width), 'alto': float(w.height), 'titulo': meta.title, 'creador': meta.creator,
  'codigos': len(re.findall(r'ADN-\\d{5}', todo)), 'unicos': len(set(re.findall(r'ADN-\\d{5}', todo))), 'pies': [re.search(r'Página (\\d+) de (\\d+)', t).groups() if re.search(r'Página (\\d+) de (\\d+)', t) else None for t in textos],
  'cabeceras': sum(1 for t in textos if 'Código Nombre Apellido Correo' in t), 'primera': textos[0][:400], 'texto': todo}))
`, join(dir, 'm.pdf'))
  assert.equal(r.paginas, r.pies.length); assert.ok(r.paginas >= 10, `420 filas ocupan varias páginas (${r.paginas})`)
  assert.ok(r.ancho > r.alto, 'el informe de miembros va apaisado'); assert.equal(r.titulo, 'Informe de miembros'); assert.equal(r.creador, 'ViveADN')
  assert.equal(r.codigos, 420, 'cada miembro sale una vez'); assert.equal(r.unicos, 420)
  assert.deepEqual(r.pies.map((p: string[]) => p[1]), r.pies.map(() => String(r.paginas)), 'el pie dice "de N" con el total real')
  assert.deepEqual(r.pies.map((p: string[]) => Number(p[0])), r.pies.map((_: unknown, i: number) => i + 1), 'páginas numeradas en orden')
  assert.equal(r.cabeceras, r.paginas, 'la cabecera de la tabla se repite en cada página')
  assert.ok(r.texto.includes('Zoë (el "Pastor")') && r.texto.includes("O'Brien") && r.texto.includes('Ana\\María'), 'paréntesis, comillas, barra invertida y acentos sobreviven')
  assert.ok(r.texto.includes('Resumen') && r.texto.includes('Miembros registrados') && r.texto.includes('420'), 'el resumen está en la primera página')
  assert.ok(r.texto.includes('??? ?') || r.texto.includes('???'), 'los caracteres no latinos salen como ?')
  assert.ok(!/NaN|undefined|null/.test(r.texto), 'ningún "NaN", "undefined" ni "null" visible')

  // PDF de crecimiento y de asistencia: gráfico, tablas y varios idiomas
  for (const idioma of IDIOMAS) {
    const { t } = traductor(idioma)
    const ctx = { t, locale: idioma, iglesia: 'Mi iglesia', ahora }
    for (const [nombre, inf] of [['crecimiento', informeCrecimiento(crecimiento, ctx)], ['asistencia', informeAsistencia(asistencia, ctx)]] as const) {
      writeFileSync(join(dir, `${nombre}-${idioma}.pdf`), crearPdf(inf))
      const o = py(`
import sys, json, pypdf, pdfplumber
rd = pypdf.PdfReader(sys.argv[1], strict=True)
with pdfplumber.open(sys.argv[1]) as pdf: txt = '\\n'.join(p.extract_text() or '' for p in pdf.pages)
print(json.dumps({'paginas': len(rd.pages), 'titulo': rd.metadata.title, 'texto': txt}))`, join(dir, `${nombre}-${idioma}.pdf`))
      assert.equal(o.titulo, inf.titulo, `${nombre}/${idioma}: título en las propiedades`)
      assert.ok(o.texto.includes(inf.titulo) && o.paginas >= 1, `${nombre}/${idioma}`)
      assert.ok(!/NaN|undefined|null/.test(o.texto), `${nombre}/${idioma}: sin NaN ni undefined`)
    }
  }
  const fr = py(`
import sys, json, pdfplumber
with pdfplumber.open(sys.argv[1]) as pdf: print(json.dumps(pdf.pages[0].extract_text()))`, join(dir, 'asistencia-fr.pdf'))
  assert.ok(fr.includes('75') && fr.includes('Réunions de maison') && /Page 1 sur 1/.test(fr), 'francés: textos, porcentaje y "Page 1 sur 1"')
  assert.ok(!fr.includes('?'), 'francés: ningún ? por espacios finos de Intl')

  // Excel de miembros: tipos, fechas, congelado, filtro, texto que parece fórmula y alfabetos no latinos
  const xlsxM = crearXlsx(infM); writeFileSync(join(dir, 'm.xlsx'), xlsxM)
  const x = py(`
import sys, json, openpyxl, datetime
wb = openpyxl.load_workbook(sys.argv[1])
ws = wb['Miembros']
filas = list(ws.iter_rows(min_row=5, values_only=True))
cab = [c.value for c in ws[4]]
f9 = [c for c in ws[13]]   # fila 13 = miembro 9 (indice 8): nombre =SUMA(1+1)
print(json.dumps({'hojas': wb.sheetnames, 'congelado': ws.freeze_panes, 'filtro': ws.auto_filter.ref, 'cab': cab, 'n': len(filas),
  'dim': ws.dimensions, 'primera': [str(v) for v in filas[0]], 'tipoFecha': type(filas[1][5]).__name__, 'fmtFecha': ws['F6'].number_format,
  'formula_texto': [ws['B13'].value, ws['B13'].data_type, ws['C13'].value, ws['C13'].data_type], 'japones': ws['B12'].value,
  'ancho': ws.column_dimensions['D'].width, 'resumen': [[c for c in r] for r in wb['Resumen'].iter_rows(min_row=1, max_row=8, values_only=True)],
  'bool_texto': sorted({str(r[8]) for r in filas}), 'titulo_doc': wb.properties.title, 'creador': wb.properties.creator}))
`, join(dir, 'm.xlsx'))
  assert.deepEqual(x.hojas, ['Resumen', 'Miembros']); assert.equal(x.congelado, 'A5'); assert.equal(x.filtro, `A4:L${4 + 420}`)
  assert.equal(x.n, 420); assert.equal(x.cab[0], 'Código'); assert.equal(x.cab[11], 'Registrado')
  assert.equal(x.tipoFecha, 'datetime'); assert.equal(x.fmtFecha, 'yyyy\\-mm\\-dd')
  assert.deepEqual(x.formula_texto, ['=SUMA(1+1)', 's', '@cmd', 's'], 'una celda que empieza por = o @ queda como texto, nunca como fórmula')
  assert.equal(x.japones, '日本語 🙏', 'el Excel conserva todos los caracteres')
  assert.deepEqual(x.bool_texto, ['No', 'Sí']); assert.equal(x.titulo_doc, 'Informe de miembros'); assert.equal(x.creador, 'ViveADN')
  assert.equal(x.ancho, (infM.secciones.find(s => s.tipo === 'tabla') as any).columnas[3].ancho, 'la anchura de columna viene de la definición')
  assert.deepEqual(x.resumen[3], ['Resumen', ''], 'la hoja de resumen lleva los títulos de sección')

  // Excel de asistencia y crecimiento: números reales, porcentaje y una hoja por tabla
  for (const [nombre, inf, hojas] of [['asistencia', informeAsistencia(asistencia, ctxEs), ['Resumen', 'Por semana', 'Por casa', 'Eventos']], ['crecimiento', informeCrecimiento(crecimiento, ctxEs), ['Resumen', 'Mensual']]] as const) {
    writeFileSync(join(dir, `${nombre}.xlsx`), crearXlsx(inf))
    const o = py(`
import sys, json, openpyxl
wb = openpyxl.load_workbook(sys.argv[1])
ws = wb.worksheets[1]
print(json.dumps({'hojas': wb.sheetnames, 'fila': [str(c.value) for c in ws[5]], 'tipos': [c.data_type for c in ws[5]], 'fmts': [c.number_format for c in ws[5]]}))`, join(dir, `${nombre}.xlsx`))
    assert.deepEqual(o.hojas, hojas, `${nombre}: una hoja por tabla`)
    assert.ok(o.tipos.slice(1).every((t: string) => t === 'n' || t === 's'), `${nombre}: números como números`)
  }
  const asi = py(`
import sys, json, openpyxl
wb = openpyxl.load_workbook(sys.argv[1]); ws = wb['Por casa']
print(json.dumps([[c.value for c in r] for r in ws.iter_rows(min_row=5, values_only=False)] and [[c.value for c in r] for r in ws.iter_rows(min_row=5)] + [ws['E5'].number_format]))`, join(dir, 'asistencia.xlsx'))
  assert.equal(asi[0][0], 'Casa Norte'); assert.equal(asi[0][1], 60); assert.ok(Math.abs(asi[0][4] - 50 / 60) < 1e-9); assert.equal(asi[2], '0.0%')

  // Un Excel grande sigue siendo válido
  const grande = informeMiembros(resumenMiembros, Array.from({ length: 12000 }, (_, i) => ({ ...filasMiembros[i % 420]!, crm_id: `G-${i}` })), ctxEs)
  writeFileSync(join(dir, 'g.xlsx'), crearXlsx(grande))
  const g = py(`
import sys, json, openpyxl
wb = openpyxl.load_workbook(sys.argv[1], read_only=True)
print(json.dumps(sum(1 for _ in wb['Miembros'].iter_rows(min_row=5))))`, join(dir, 'g.xlsx'))
  assert.equal(g, 12000)
  const t0 = Date.now(); crearPdf(grande); const msPdf = Date.now() - t0
  assert.ok(msPdf < 8000, `12.000 filas de PDF en menos de 8 s (${msPdf} ms)`)
} finally { rmSync(dir, { recursive: true, force: true }) }

console.log('OK: todas las pruebas de informes pasan')
