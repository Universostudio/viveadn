// Utilidades mínimas de SQL para compilar el paquete de traspaso: partir un archivo en sentencias (respetando comillas, comentarios y cuerpos entre $$)
// y reconocer unas pocas formas (crear/borrar políticas, disparadores y funciones). No es un analizador de SQL completo: lo que no reconoce lo deja tal cual,
// y la prueba de equivalencia del esquema (generar-traspaso.sh) es la que demuestra que el resultado es correcto.

export interface Sentencia { texto: string; limpio: string }

/** Parte un script en sentencias terminadas en «;». `texto` conserva comentarios y saltos; `limpio` es el SQL sin comentarios, con espacios simples. */
export function partir(sql: string): Sentencia[] {
  const salida: Sentencia[] = []
  let ini = 0, i = 0
  const n = sql.length
  let limpio = ''
  const cerrar = (fin: number) => {
    const texto = sql.slice(ini, fin)
    const l = limpio.replace(/\s+/g, ' ').trim()
    if (l) salida.push({ texto, limpio: l })
    else if (salida.length && texto.trim()) salida[salida.length - 1]!.texto += texto   // comentarios finales sin sentencia: se pegan a la anterior
    ini = fin; limpio = ''
  }
  while (i < n) {
    const c = sql[i]!, d = sql[i + 1]
    if (c === '-' && d === '-') { while (i < n && sql[i] !== '\n') i++; limpio += ' '; continue }
    if (c === '/' && d === '*') { let nivel = 1; i += 2; while (i < n && nivel) { if (sql[i] === '/' && sql[i + 1] === '*') { nivel++; i += 2 } else if (sql[i] === '*' && sql[i + 1] === '/') { nivel--; i += 2 } else i++ } limpio += ' '; continue }
    if (c === "'") { let j = i + 1; while (j < n) { if (sql[j] === "'" && sql[j + 1] === "'") j += 2; else if (sql[j] === "'") break; else j++ } limpio += sql.slice(i, j + 1); i = j + 1; continue }
    if (c === '"') { let j = i + 1; while (j < n && sql[j] !== '"') j++; limpio += sql.slice(i, j + 1); i = j + 1; continue }
    if (c === '$') {
      const m = /^\$([A-Za-z_]\w*)?\$/.exec(sql.slice(i, i + 40))
      if (m) { const fin = sql.indexOf(m[0], i + m[0].length); if (fin < 0) throw new Error('Cuerpo entre $ sin cerrar'); limpio += sql.slice(i, fin + m[0].length); i = fin + m[0].length; continue }
    }
    if (c === ';') { limpio += ';'; i++; cerrar(i); continue }
    limpio += c; i++
  }
  if (sql.slice(ini).trim()) { limpio += ''; const resto = sql.slice(ini); const l = limpio.replace(/\s+/g, ' ').trim(); if (l) salida.push({ texto: resto, limpio: l }); else if (salida.length) salida[salida.length - 1]!.texto += resto }
  return salida
}

const SINONIMOS: [RegExp, string][] = [[/timestamp with time zone/g, 'timestamptz'], [/timestamp without time zone/g, 'timestamp'], [/\binteger\b/g, 'int4'], [/\bint\b/g, 'int4'], [/\bboolean\b/g, 'bool'], [/character varying/g, 'varchar'], [/\bbigint\b/g, 'int8']]
const normalizarTipo = (t: string) => SINONIMOS.reduce((a, [r, s]) => a.replace(r, s), t.toLowerCase().replace(/\s+/g, ' ').trim()).replace(/\s*\[\s*\]/g, '[]')
const sinComillas = (s: string) => s.replace(/"/g, '').toLowerCase()

/** Corta una lista separada por comas al nivel superior (sin entrar en paréntesis ni comillas) */
function listaSuperior(t: string): string[] {
  const l: string[] = []; let nivel = 0, q = false, ini = 0
  for (let i = 0; i < t.length; i++) {
    const c = t[i]!
    if (c === "'") q = !q
    else if (!q && c === '(') nivel++
    else if (!q && c === ')') nivel--
    else if (!q && c === ',' && nivel === 0) { l.push(t.slice(ini, i)); ini = i + 1 }
  }
  if (t.slice(ini).trim()) l.push(t.slice(ini))
  return l.map(x => x.trim()).filter(Boolean)
}

/** Contenido del primer paréntesis a partir de `desde` (equilibrado) */
function parentesis(t: string, desde: number): { dentro: string; fin: number } | null {
  const a = t.indexOf('(', desde); if (a < 0) return null
  let nivel = 0, q = false
  for (let i = a; i < t.length; i++) {
    const c = t[i]!
    if (c === "'") q = !q
    else if (!q && c === '(') nivel++
    else if (!q && c === ')') { nivel--; if (!nivel) return { dentro: t.slice(a + 1, i), fin: i + 1 } }
  }
  return null
}

const tiposDeLista = (dentro: string, conNombre: boolean) => listaSuperior(dentro).map(p => {
  let x = p.replace(/\s+default\s+[\s\S]*$/i, '').replace(/\s*=\s*[\s\S]*$/, '').trim()
  x = x.replace(/^(in|inout|variadic)\s+/i, '')
  if (conNombre) x = x.replace(/^\S+\s+/, '')
  return normalizarTipo(x)
})

export const firmaTexto = (nombre: string, tipos: string[]) => `${sinComillas(nombre)}(${tipos.join(',')})`

export type Clase =
  | { tipo: 'crear_funcion'; firma: string }
  | { tipo: 'borrar_funcion'; firma: string; siExiste: boolean }
  | { tipo: 'permiso_funcion'; firmas: string[] }
  | { tipo: 'crear_politica'; nombre: string; tabla: string }
  | { tipo: 'borrar_politica'; nombre: string; tabla: string }
  | { tipo: 'crear_disparador'; nombre: string; tabla: string }
  | { tipo: 'borrar_disparador'; nombre: string; tabla: string }
  | { tipo: 'crear_tabla'; tabla: string }
  | { tipo: 'borrar_restriccion'; tabla: string; nombre: string; siExiste: boolean }
  | { tipo: 'anadir_restriccion'; tabla: string; nombre: string }
  | { tipo: 'otra' }

export function clasificar(limpio: string): Clase {
  let m: RegExpExecArray | null
  if ((m = /^create\s+(?:or\s+replace\s+)?function\s+("?[\w.]+"?(?:\."?\w+"?)?)\s*\(/i.exec(limpio))) {
    const p = parentesis(limpio, m[0].length - 1)!
    return { tipo: 'crear_funcion', firma: firmaTexto(m[1]!, tiposDeLista(p.dentro, true)) }
  }
  if ((m = /^drop\s+function\s+(if\s+exists\s+)?("?[\w.]+"?)\s*\(/i.exec(limpio))) {
    const p = parentesis(limpio, m[0].length - 1)!
    return { tipo: 'borrar_funcion', firma: firmaTexto(m[2]!, tiposDeLista(p.dentro, false)), siExiste: !!m[1] }
  }
  if ((m = /^(grant|revoke|comment)\b[\s\S]*?\bon\s+function\s+([\s\S]*?)(?:\s+(?:from|to|is)\s)/i.exec(limpio))) {
    const firmas: string[] = []
    const lista = m[2]!
    for (const ref of listaSuperior(lista)) {
      const mm = /^("?[\w.]+"?)\s*\(([\s\S]*)\)$/.exec(ref.trim())
      if (!mm) return { tipo: 'otra' }
      firmas.push(firmaTexto(mm[1]!, tiposDeLista(mm[2]!, false)))
    }
    return { tipo: 'permiso_funcion', firmas }
  }
  if ((m = /^create\s+table\s+(?:if\s+not\s+exists\s+)?("?[\w.]+"?)/i.exec(limpio))) return { tipo: 'crear_tabla', tabla: sinComillas(m[1]!) }
  if ((m = /^alter\s+table\s+(?:only\s+)?("?[\w.]+"?)\s+drop\s+constraint\s+(if\s+exists\s+)?("?\w+"?)/i.exec(limpio))) return { tipo: 'borrar_restriccion', tabla: sinComillas(m[1]!), nombre: sinComillas(m[3]!), siExiste: !!m[2] }
  if ((m = /^alter\s+table\s+(?:only\s+)?("?[\w.]+"?)\s+add\s+constraint\s+("?\w+"?)/i.exec(limpio))) return { tipo: 'anadir_restriccion', tabla: sinComillas(m[1]!), nombre: sinComillas(m[2]!) }
  if ((m = /^create\s+policy\s+("?\w+"?)\s+on\s+("?[\w.]+"?)/i.exec(limpio))) return { tipo: 'crear_politica', nombre: sinComillas(m[1]!), tabla: sinComillas(m[2]!) }
  if ((m = /^drop\s+policy\s+(?:if\s+exists\s+)?("?\w+"?)\s+on\s+("?[\w.]+"?)/i.exec(limpio))) return { tipo: 'borrar_politica', nombre: sinComillas(m[1]!), tabla: sinComillas(m[2]!) }
  if ((m = /^create\s+(?:or\s+replace\s+)?trigger\s+("?\w+"?)\s+[\s\S]*?\bon\s+("?[\w.]+"?)/i.exec(limpio))) return { tipo: 'crear_disparador', nombre: sinComillas(m[1]!), tabla: sinComillas(m[2]!) }
  if ((m = /^drop\s+trigger\s+(?:if\s+exists\s+)?("?\w+"?)\s+on\s+("?[\w.]+"?)/i.exec(limpio))) return { tipo: 'borrar_disparador', nombre: sinComillas(m[1]!), tabla: sinComillas(m[2]!) }
  return { tipo: 'otra' }
}

/** Nombre sin esquema y con esquema: las firmas de «create» llevan esquema; las de «grant/drop» también en estas migraciones */

/** Quita de un «create table» la restricción `nombre`: la declarada con «constraint nombre» o, si se llama <tabla>_<columna>_check, el «check» en línea de esa columna. Devuelve null si no la encuentra. */
export function quitarRestriccionEnLinea(texto: string, tabla: string, nombre: string): string | null {
  const cierre = (t: string, desde: number) => { let nivel = 0, q = false; for (let i = desde; i < t.length; i++) { const c = t[i]!; if (c === "'") q = !q; else if (!q && c === '(') nivel++; else if (!q && c === ')') { nivel--; if (!nivel) return i } } return -1 }
  const re = new RegExp(`,?\\s*constraint\\s+"?${nombre}"?\\s+`, 'i')
  const m = re.exec(texto)
  if (m) {
    const ab = texto.indexOf('(', m.index + m[0].length - 1 + (m[0].endsWith(' ') ? 0 : 0))
    // la restricción puede ser «check (…)» o «foreign key (…) references …»: aquí solo se admite check
    if (!/^check\s*\(/i.test(texto.slice(m.index + m[0].length))) return null
    const a = texto.indexOf('(', m.index + m[0].length)
    const f = cierre(texto, a)
    void ab
    if (f < 0) return null
    const empiezaConComa = m[0].trimStart().startsWith(',')
    let fin = f + 1
    if (!empiezaConComa) { const resto = /^\s*,/.exec(texto.slice(fin)); if (resto) fin += resto[0].length }
    return texto.slice(0, m.index) + texto.slice(fin)
  }
  const nombreTabla = tabla.split('.').pop()!
  const mc = new RegExp(`^${nombreTabla}_(\\w+)_check$`).exec(nombre)
  if (mc) {
    const col = mc[1]!
    const mcol = new RegExp(`(^|\\n)(\\s*${col}\\s+[^\\n]*?)\\s+check\\s*\\(`, 'i').exec(texto)
    if (mcol) {
      const a = texto.indexOf('(', mcol.index + mcol[0].length - 1)
      const f = cierre(texto, a)
      if (f < 0) return null
      const ini = mcol.index + mcol[0].length - mcol[0].replace(/^[\s\S]*?(\s+check\s*\()$/i, '$1').length
      return texto.slice(0, ini) + texto.slice(f + 1)
    }
  }
  return null
}
