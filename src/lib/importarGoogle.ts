// Lectura de un CSV de Google Contacts (y del formato de Outlook, que es parecido) para importar miembros.
// Funciones puras, sin acceso a la red. La base de datos repite las comprobaciones que importan (duplicados, claves,
// formatos) en `adn_importar_miembros`, de modo que un archivo o un cliente alterado no puede saltárselas.
//
// Reglas (decididas con Gerencia, 11-11-2026):
//  * Nunca se importan contraseñas: una columna cuyo nombre sugiere una clave no se lee, y una nota que parece
//    guardar una clave se descarta.
//  * Se deduplica por correo: dos filas que comparten algún correo son la misma persona y se fusionan.
//  * Se descartan las filas sin nombre y sin ningún dato de contacto. Las que no tienen nombre pero sí correo o
//    teléfono quedan aparte: solo se importan si quien importa lo pide, con el correo o el teléfono como nombre.
//  * Un teléfono o un correo inválido no invalida a la persona: se descarta ese dato y se cuenta.
import { parseCsv, fechaIso, normalizar } from './importarMiembros.ts'

export const MAX_FILAS_GOOGLE = 25000
export const MAX_BYTES_GOOGLE = 20_000_000
export const LOTE_GOOGLE = 500

export type TipoContacto = 'correo' | 'telefono' | 'direccion' | 'etiqueta'
export interface Contacto { tipo: TipoContacto; etiqueta?: string; valor: string }

export interface ContactoGoogle {
  linea: number
  nombre: string
  apellido: string
  nombreDerivado: boolean
  emails: string[]
  telefonos: { valor: string; etiqueta?: string }[]
  fecha_nacimiento: string | null
  notas: string | null
  direcciones: { valor: string; etiqueta?: string }[]
  etiquetas: string[]
}

export interface ResumenGoogle {
  filas: number
  /** Sin nombre y sin correo ni teléfono: no hay nada que importar */
  descartadasVacias: number
  /** Sin nombre pero con correo o teléfono: quedan aparte, se importan solo si se pide */
  sinNombre: number
  /** Filas fusionadas en otra por compartir un correo (o un teléfono, si no tenían correo) */
  fusionadas: number
  correosInvalidos: number
  telefonosInvalidos: number
  fechasInvalidas: number
  cumpleanosSinAnio: number
  notasConClave: number
  notasRecortadas: number
  /** Personas distintas que salen del archivo, con y sin nombre */
  personas: number
}

export interface AnalisisGoogle {
  error?: 'vacio' | 'noEsGoogle' | 'demasiadasFilas'
  personas: ContactoGoogle[]
  resumen: ResumenGoogle
  /** Columnas cuyo nombre sugiere una clave: no se leyeron, y conviene borrarlas del archivo */
  columnasSensibles: string[]
  /** Columnas reconocidas pero que no se importan, y las que no se reconocen */
  ignoradas: string[]
}

const RESUMEN_VACIO: ResumenGoogle = {
  filas: 0, descartadasVacias: 0, sinNombre: 0, fusionadas: 0, correosInvalidos: 0, telefonosInvalidos: 0,
  fechasInvalidas: 0, cumpleanosSinAnio: 0, notasConClave: 0, notasRecortadas: 0, personas: 0,
}

// Nombre de columna normalizado: sin acentos, en minúsculas, con guiones y puntos como espacios
const SENSIBLE_RE = /(contrasen|password|passwd|passcode|\bpwd\b|\bclave\b|\bsecret|\btoken\b|\bpin\b|\bapi key\b)/
// Una nota que guarda una clave: "contraseña: xxx", "password = xxx", "PIN: 1234"
const NOTA_CLAVE_RE = /\b(contrase(ñ|n)a|password|passwd|passcode|clave|pin|secreto?|secret)\s*[:=]/i
const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/
const SEP_MULTI = /\s*:::\s*/

export function esSensible(cabecera: string): boolean { return SENSIBLE_RE.test(normalizar(cabecera)) }

// Teléfono en forma canónica (solo dígitos y un + inicial), o null si no lo es. La extensión se descarta.
// Tiene que coincidir con adn_telefono_canonico de la base, que vuelve a calcularla.
export function telefonoCanonico(valor: string): string | null {
  // Se quita la extensión ("x123", "ext. 4"); lo que quede solo puede llevar dígitos y signos de número
  let s = valor.trim().replace(/\s*(?:ext\.?|extension|extensión|x|#)\s*\d{1,6}$/i, '').trim()
  if (!/^[+\d\s().\-/]+$/.test(s)) return null          // cualquier letra (p. ej. "casa", "N/A") lo invalida
  if (s.startsWith('00')) s = '+' + s.slice(2)            // 0034... es +34...
  const mas = (s.match(/\+/g) ?? []).length
  if (mas > 1 || (mas === 1 && !s.startsWith('+'))) return null
  const digitos = s.replace(/\D/g, '')
  if (digitos.length < 7 || digitos.length > 15) return null
  if (/^(\d)\1+$/.test(digitos)) return null              // 0000000, 1111111
  return (mas === 1 ? '+' : '') + digitos
}

// Una persona única por correo: minúsculas y sin espacios
const correoLimpio = (v: string) => v.trim().toLowerCase()

function partirMultiples(celda: string): string[] {
  return celda.split(SEP_MULTI).map(x => x.trim()).filter(Boolean)
}

interface Grupo { n: number; valor?: number; etiqueta?: number; formateada?: number; calle?: number; ciudad?: number; region?: number; cp?: number; pais?: number }

export function esFormatoGoogle(cabecera: string[]): boolean {
  const h = cabecera.map(normalizar)
  const tieneNombre = h.includes('first name') || h.includes('given name') || h.includes('family name') || h.includes('last name')
  const tieneContacto = h.some(x => /^(e mail|phone) \d+ (value|type|label)$/.test(x)) || h.includes('e mail address') || h.includes('mobile phone') || h.includes('group membership') || h.includes('labels')
  return tieneNombre && tieneContacto
}

const unir = (...p: (string | undefined)[]) => p.map(x => (x ?? '').trim()).filter(Boolean).join(', ')
const recortar = (s: string, max: number) => (s.length > max ? s.slice(0, max - 1) + '…' : s)

export function analizarGoogle(texto: string): AnalisisGoogle {
  const vacio = (error: AnalisisGoogle['error']): AnalisisGoogle => ({ error, personas: [], resumen: { ...RESUMEN_VACIO }, columnasSensibles: [], ignoradas: [] })
  const filas = parseCsv(texto)
  if (filas.length < 2) return vacio('vacio')
  const cabecera = filas[0] ?? []
  if (!esFormatoGoogle(cabecera)) return vacio('noEsGoogle')
  if (filas.length - 1 > MAX_FILAS_GOOGLE) return vacio('demasiadasFilas')

  // Mapa de columnas. Las sensibles se excluyen aquí, antes de leer ninguna celda.
  const h = cabecera.map(normalizar)
  const sensibles = new Set<number>()
  h.forEach((x, i) => { if (SENSIBLE_RE.test(x)) sensibles.add(i) })
  const idx = (...nombres: string[]) => { for (const n of nombres) { const i = h.indexOf(n); if (i >= 0 && !sensibles.has(i)) return i } return -1 }
  const usadas = new Set<number>()
  const marca = (...is: number[]) => { for (const i of is) if (i >= 0) usadas.add(i) }

  const iNombre = idx('first name', 'given name'); const iMedio = idx('middle name', 'additional name'); const iApellido = idx('last name', 'family name')
  const iNombreCompleto = idx('name'); const iAlias = idx('nickname')
  const iNac = idx('birthday'); const iNotas = idx('notes'); const iEtiquetas = idx('labels', 'group membership', 'categories')
  marca(iNombre, iMedio, iApellido, iNombreCompleto, iAlias, iNac, iNotas, iEtiquetas)

  const grupos = (clave: RegExp) => {
    const m = new Map<number, Grupo>()
    h.forEach((x, i) => {
      const r = clave.exec(x)
      if (!r || sensibles.has(i)) return
      const n = Number(r[1]); const g = m.get(n) ?? { n }
      const campo = r[2]
      if (campo === 'value') g.valor = i
      else if (campo === 'label' || campo === 'type') g.etiqueta = i
      else if (campo === 'formatted') g.formateada = i
      else if (campo === 'street') g.calle = i
      else if (campo === 'city') g.ciudad = i
      else if (campo === 'region') g.region = i
      else if (campo === 'postal code') g.cp = i
      else if (campo === 'country') g.pais = i
      m.set(n, g); marca(i)
    })
    return [...m.values()].sort((a, b) => a.n - b.n)
  }
  const gEmails = grupos(/^e mail (\d+) (value|label|type)$/)
  const gTelefonos = grupos(/^phone (\d+) (value|label|type)$/)
  const gDirecciones = grupos(/^address (\d+) (formatted|label|type|street|city|region|postal code|country)$/)
  // Outlook: columnas sueltas
  const OUTLOOK_EMAIL = ['e mail address', 'e mail 2 address', 'e mail 3 address'].map(n => idx(n)).filter(i => i >= 0)
  const OUTLOOK_TEL = ['mobile phone', 'primary phone', 'home phone', 'home phone 2', 'business phone', 'business phone 2', 'other phone'].map(n => ({ i: idx(n), n })).filter(x => x.i >= 0)
  marca(...OUTLOOK_EMAIL, ...OUTLOOK_TEL.map(x => x.i))
  const OUTLOOK_DIR = [['home', 'home street', 'home city', 'home state', 'home postal code', 'home country region'], ['business', 'business street', 'business city', 'business state', 'business postal code', 'business country region']]
    .map(([e, ...c]) => ({ e, c: c.map(n => idx(n)) })).filter(x => x.c.some(i => i >= 0))
  marca(...OUTLOOK_DIR.flatMap(x => x.c))

  const ignoradas = cabecera.map((x, i) => ({ x: x.trim(), i })).filter(({ x, i }) => x && !usadas.has(i) && !sensibles.has(i)).map(({ x }) => x)
  const columnasSensibles = [...sensibles].map(i => (cabecera[i] ?? '').trim()).filter(Boolean)

  const r: ResumenGoogle = { ...RESUMEN_VACIO, filas: filas.length - 1 }
  const celda = (fila: string[], i: number) => (i >= 0 ? (fila[i] ?? '').trim() : '')

  // Índices de lo ya visto, para fusionar a quien repite un correo (o un teléfono, si no tiene correo)
  const personas: ContactoGoogle[] = []
  const porCorreo = new Map<string, number>()
  const porTelefono = new Map<string, number>()
  const porNombre = new Map<string, number>()

  filas.slice(1).forEach((fila, k) => {
    const linea = k + 2
    // Correos
    const crudosCorreo: string[] = []
    for (const g of gEmails) if (g.valor !== undefined) crudosCorreo.push(...partirMultiples(celda(fila, g.valor)))
    for (const i of OUTLOOK_EMAIL) crudosCorreo.push(...partirMultiples(celda(fila, i)))
    const emails: string[] = []
    for (const e of crudosCorreo) {
      const c = correoLimpio(e)
      if (!EMAIL_RE.test(c) || c.length > 254) { r.correosInvalidos++; continue }
      if (!emails.includes(c)) emails.push(c)
    }
    // Teléfonos
    const telefonos: { valor: string; etiqueta?: string }[] = []
    const anadirTel = (crudo: string, etiqueta: string) => {
      for (const t of partirMultiples(crudo)) {
        const c = telefonoCanonico(t)
        if (!c) { r.telefonosInvalidos++; continue }
        if (!telefonos.some(x => x.valor === c)) telefonos.push({ valor: c, ...(etiqueta ? { etiqueta: recortar(etiqueta, 60) } : {}) })
      }
    }
    for (const g of gTelefonos) if (g.valor !== undefined) anadirTel(celda(fila, g.valor), celda(fila, g.etiqueta ?? -1).replace(SEP_MULTI, '/'))
    for (const { i, n } of OUTLOOK_TEL) anadirTel(celda(fila, i), n)

    // Nombre
    let nombre = [celda(fila, iNombre), celda(fila, iMedio)].filter(Boolean).join(' ')
    let apellido = celda(fila, iApellido)
    if (!nombre && !apellido) nombre = celda(fila, iNombreCompleto) || celda(fila, iAlias)
    nombre = recortar(nombre.replace(/\s+/g, ' '), 100)
    apellido = recortar(apellido.replace(/\s+/g, ' '), 100)
    const tieneNombre = !!(nombre || apellido)
    const tieneContacto = emails.length > 0 || telefonos.length > 0
    if (!tieneNombre && !tieneContacto) { r.descartadasVacias++; return }
    let nombreDerivado = false
    if (!tieneNombre) {
      // Sin nombre: el correo o el teléfono hacen de nombre, sin inventar nada
      nombre = recortar(emails[0] ?? telefonos[0]?.valor ?? '', 100)
      nombreDerivado = true
    } else if (!nombre) { nombre = apellido; apellido = '' }

    // Cumpleaños: AAAA-MM-DD; "--MM-DD" no trae año y no cabe en una fecha de nacimiento
    let nacimiento: string | null = null
    const bruto = celda(fila, iNac)
    if (bruto) {
      if (/^--\d{1,2}-\d{1,2}$/.test(bruto)) r.cumpleanosSinAnio++
      else { nacimiento = fechaIso(bruto); if (!nacimiento) r.fechasInvalidas++ }
    }

    // Notas: se descartan si parecen guardar una clave, y se recortan al máximo
    let notas: string | null = celda(fila, iNotas).replace(/\r\n?/g, '\n') || null
    if (notas && NOTA_CLAVE_RE.test(notas)) { notas = null; r.notasConClave++ }
    if (notas && notas.length > 1000) { notas = recortar(notas, 1000); r.notasRecortadas++ }

    // Direcciones (hasta 3) y etiquetas (hasta 20, sin las de sistema "* myContacts")
    const direcciones: { valor: string; etiqueta?: string }[] = []
    for (const g of gDirecciones) {
      const valor = celda(fila, g.formateada ?? -1) || unir(celda(fila, g.calle ?? -1), celda(fila, g.ciudad ?? -1), celda(fila, g.region ?? -1), celda(fila, g.cp ?? -1), celda(fila, g.pais ?? -1))
      const limpio = recortar(valor.replace(/\s*\n\s*/g, ', ').replace(/\s+/g, ' ').trim(), 500)
      if (limpio) direcciones.push({ valor: limpio, ...(celda(fila, g.etiqueta ?? -1) ? { etiqueta: recortar(celda(fila, g.etiqueta ?? -1), 60) } : {}) })
    }
    for (const d of OUTLOOK_DIR) {
      const limpio = recortar(unir(...d.c.map(i => celda(fila, i))).replace(/\s+/g, ' '), 500)
      if (limpio) direcciones.push({ valor: limpio, etiqueta: d.e })
    }
    const etiquetas: string[] = []
    const brutoEtiquetas = celda(fila, iEtiquetas)
    // Google separa con " ::: "; Outlook (Categories) con punto y coma
    const trozos = brutoEtiquetas.includes(':::') ? partirMultiples(brutoEtiquetas) : brutoEtiquetas.split(';').map(x => x.trim())
    for (const e of trozos) {
      if (!e || e.startsWith('*')) continue                // "* myContacts" y similares son grupos del sistema
      const l = recortar(e, 60)
      if (!etiquetas.some(x => x.toLowerCase() === l.toLowerCase())) etiquetas.push(l)
    }

    const nueva: ContactoGoogle = {
      linea, nombre, apellido, nombreDerivado, emails, telefonos: telefonos.slice(0, 5), fecha_nacimiento: nacimiento, notas,
      direcciones: direcciones.slice(0, 3), etiquetas: etiquetas.slice(0, 20),
    }

    // Fusión: por cualquier correo; si no hay correo, por teléfono; si no hay ni uno ni otro, por nombre
    let destino: number | undefined
    if (emails.length) destino = emails.map(e => porCorreo.get(e)).find(x => x !== undefined)
    else if (telefonos.length) destino = telefonos.map(t => porTelefono.get(t.valor)).find(x => x !== undefined)
    else destino = porNombre.get(normalizar(`${nombre} ${apellido}`))
    if (destino !== undefined) {
      const p = personas[destino]!
      for (const e of emails) if (!p.emails.includes(e)) p.emails.push(e)
      for (const t of telefonos) if (!p.telefonos.some(x => x.valor === t.valor) && p.telefonos.length < 5) p.telefonos.push(t)
      for (const d of nueva.direcciones) if (!p.direcciones.some(x => x.valor === d.valor) && p.direcciones.length < 3) p.direcciones.push(d)
      for (const e of nueva.etiquetas) if (!p.etiquetas.some(x => x.toLowerCase() === e.toLowerCase()) && p.etiquetas.length < 20) p.etiquetas.push(e)
      if (!p.fecha_nacimiento) p.fecha_nacimiento = nueva.fecha_nacimiento
      if (!p.notas) p.notas = nueva.notas
      // Si la primera fila no tenía nombre y esta sí, se queda el nombre real
      if (p.nombreDerivado && !nueva.nombreDerivado) { p.nombre = nueva.nombre; p.apellido = nueva.apellido; p.nombreDerivado = false }
      for (const e of p.emails) porCorreo.set(e, destino)
      for (const t of p.telefonos) porTelefono.set(t.valor, destino)
      r.fusionadas++
      return
    }
    const pos = personas.length
    personas.push(nueva)
    for (const e of emails) porCorreo.set(e, pos)
    for (const t of telefonos) porTelefono.set(t.valor, pos)
    if (!emails.length && !telefonos.length) porNombre.set(normalizar(`${nombre} ${apellido}`), pos)
  })

  r.personas = personas.length
  // El recuento de "sin nombre" es de personas, no de filas: una fila sin nombre fusionada con una con nombre ya no lo es
  r.sinNombre = personas.filter(p => p.nombreDerivado).length
  return { personas, resumen: r, columnasSensibles, ignoradas }
}

// Lo que se envía a la base: la persona con su correo y teléfono principales y el resto como datos adicionales
export function aFilaImportacion(p: ContactoGoogle) {
  const contactos: Contacto[] = [
    ...p.emails.slice(1).map(valor => ({ tipo: 'correo' as const, valor })),
    ...p.telefonos.slice(1).map(t => ({ tipo: 'telefono' as const, valor: t.valor, ...(t.etiqueta ? { etiqueta: t.etiqueta } : {}) })),
    ...p.direcciones.map(d => ({ tipo: 'direccion' as const, valor: d.valor, ...(d.etiqueta ? { etiqueta: d.etiqueta } : {}) })),
    ...p.etiquetas.map(valor => ({ tipo: 'etiqueta' as const, valor })),
  ]
  return {
    nombre: p.nombre, apellido: p.apellido, email: p.emails[0] ?? null, telefono: p.telefonos[0]?.valor ?? null,
    fecha_nacimiento: p.fecha_nacimiento, notas: p.notas, contactos,
  }
}

// Claves para comparar con lo que la iglesia ya tiene, igual que hace la base: correo; sin correo, teléfono; sin ninguno, nombre
export interface Existentes { correos: Set<string>; telefonos: Set<string>; nombres: Set<string> }
export function esDuplicadoDeExistente(p: ContactoGoogle, e: Existentes): boolean {
  if (p.emails.length) return p.emails.some(c => e.correos.has(c))
  if (p.telefonos.length) return p.telefonos.some(t => e.telefonos.has(t.valor))
  return e.nombres.has(normalizar(`${p.nombre} ${p.apellido}`))
}
