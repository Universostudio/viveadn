// Pruebas de la lectura de contactos de Google. Uso: npm run test:google
// Los datos son 100 % sintéticos. La prueba a escala reproduce las cifras del archivo real de Gerencia
// (6.100 filas, 1.934 sin nombre, 2.216 correos únicos, 960 teléfonos inválidos) con un modelo que conoce la respuesta.
import assert from 'node:assert/strict'
const g = await import('../src/lib/importarGoogle.ts')
const { analizarGoogle, telefonoCanonico, esFormatoGoogle, esSensible, aFilaImportacion, esDuplicadoDeExistente } = g
const { analizarCsv, PLANTILLA_CSV } = await import('../src/lib/importarMiembros.ts')

const csv = (filas: string[][]) => filas.map(f => f.map(c => /[",\r\n]/.test(c) ? `"${c.replace(/"/g, '""')}"` : c).join(',')).join('\r\n') + '\r\n'

// ---------- Teléfonos ----------
for (const [entrada, esperado] of [
  ['+34 600 111 222', '+34600111222'], ['600 111 222', '600111222'], ['(600) 111-222', '600111222'], ['600.111.222', '600111222'],
  ['0034 600 111 222', '+34600111222'], ['+1 (555) 010-9999 x123', '+15550109999'], ['600111222 ext. 4', '600111222'], ['91 555 01 23', '915550123'],
  ['123456', null], ['1234567890123456', null], ['abc', null], ['N/A', null], ['600 111 222 casa', null], ['0000000', null], ['1111111', null],
  ['+34+600111222', null], ['34+600111222', null], ['', null], ['-', null], ['600 111 222 / 91 555 01 23', '60011122291555 0123'.replace(/\D/g, '')],
] as const) {
  if (entrada.includes('/')) continue  // dos números en una celda sin ":::" no se parten: queda como un número demasiado largo o inválido
  assert.equal(telefonoCanonico(entrada), esperado, `teléfono ${JSON.stringify(entrada)}`)
}
assert.equal(telefonoCanonico('600 111 222 / 91 555 01 23'), null, 'dos números pegados no se aceptan como uno')

// ---------- Detección del formato ----------
assert.equal(esFormatoGoogle(['First Name', 'Last Name', 'E-mail 1 - Value']), true)
assert.equal(esFormatoGoogle(['Given Name', 'Family Name', 'Group Membership', 'Phone 1 - Type']), true)
assert.equal(esFormatoGoogle(['First Name', 'Last Name', 'E-mail Address', 'Mobile Phone']), true)
assert.equal(esFormatoGoogle(['nombre', 'apellido', 'email', 'telefono']), false, 'la plantilla propia no es de Google')
assert.equal(analizarGoogle(PLANTILLA_CSV).error, 'noEsGoogle')
assert.equal(analizarGoogle('').error, 'vacio')
assert.equal(analizarGoogle('First Name,E-mail 1 - Value\r\n').error, 'vacio')
// El importador anterior no cambia
assert.equal(analizarCsv(PLANTILLA_CSV).filas.length, 1)

// ---------- Contraseñas ----------
for (const h of ['Password', 'Contraseña', 'contrasena', 'Clave de acceso', 'Wi-Fi Password', 'PIN', 'API Key', 'Secret', 'Token', 'Passcode']) assert.equal(esSensible(h), true, `columna sensible: ${h}`)
for (const h of ['First Name', 'Notes', 'Labels', 'Organization Name', 'Spinning', 'Pinterest', 'Clavel']) assert.equal(esSensible(h), false, `columna normal: ${h}`)
{
  const a = analizarGoogle(csv([
    ['First Name', 'Last Name', 'E-mail 1 - Value', 'Password', 'Notes', 'Custom Field 1 - Label', 'Custom Field 1 - Value'],
    ['Ana', 'Pérez', 'ana@x.test', 'SECRETO-1', 'Contraseña: SECRETO-2', 'Password', 'SECRETO-3'],
    ['Luis', 'Gil', 'luis@x.test', 'SECRETO-4', 'Clase de spin: martes', '', ''],
    ['Eva', 'Sol', 'eva@x.test', '', 'password = SECRETO-5', '', ''],
    ['Max', 'Ray', 'max@x.test', '', 'PIN:1234', '', ''],
    ['Pía', 'Mar', 'pia@x.test', '', 'Se le olvidó la contraseña del wifi; avisar', '', ''],
  ]))
  assert.deepEqual(a.columnasSensibles, ['Password'])
  assert.ok(!JSON.stringify(a).includes('SECRETO'), 'ninguna clave aparece en el resultado, ni en columnas, ni en notas, ni en campos personalizados')
  assert.equal(a.resumen.notasConClave, 3)
  assert.equal(a.personas.find(p => p.nombre === 'Luis')?.notas, 'Clase de spin: martes', 'una nota con "spin:" no es una clave')
  assert.equal(a.personas.find(p => p.nombre === 'Pía')?.notas, 'Se le olvidó la contraseña del wifi; avisar', 'mencionar la palabra no basta para descartar una nota')
  assert.ok(!a.ignoradas.includes('Password'), 'la columna sensible no se lista como ignorada, solo como sensible')
}

// ---------- Formato nuevo de Google: un caso completo ----------
{
  const a = analizarGoogle(csv([
    ['First Name', 'Middle Name', 'Last Name', 'Birthday', 'Notes', 'Labels', 'E-mail 1 - Label', 'E-mail 1 - Value', 'E-mail 2 - Label', 'E-mail 2 - Value', 'Phone 1 - Label', 'Phone 1 - Value', 'Phone 2 - Label', 'Phone 2 - Value', 'Phone 3 - Label', 'Phone 3 - Value', 'Address 1 - Label', 'Address 1 - Formatted', 'Address 1 - Street', 'Address 1 - City', 'Address 1 - Country', 'Photo'],
    ['María', 'José', 'García López', '1990-05-21', 'Llegó por una amiga', '* myContacts ::: Célula Norte ::: voluntarios ::: Voluntarios', 'Casa', 'MARIA@X.TEST ::: maria.alt@x.test', 'Trabajo', 'trabajo@x.test', 'Móvil', '+34 600 111 222', 'Casa', '(91) 555-01-23', 'Otro', 'no es un teléfono', 'Casa', 'Calle Falsa 123\nSevilla', 'x', 'y', 'z', 'http://foto'],
    ['Solo', '', '', '--03-15', '', '', '', 'solo@x.test', '', '', '', '', '', '', '', '', '', '', 'Av. Sol 5', 'Sevilla', 'España', ''],
  ]))
  assert.equal(a.personas.length, 2)
  const m = a.personas[0]!
  assert.equal(m.nombre, 'María José'); assert.equal(m.apellido, 'García López')
  assert.deepEqual(m.emails, ['maria@x.test', 'maria.alt@x.test', 'trabajo@x.test'], 'tres correos de dos celdas, en minúsculas y en orden')
  assert.deepEqual(m.telefonos.map(t => t.valor), ['+34600111222', '915550123'])
  assert.equal(m.telefonos[0]?.etiqueta, 'Móvil')
  assert.equal(a.resumen.telefonosInvalidos, 1)
  assert.equal(m.fecha_nacimiento, '1990-05-21')
  assert.deepEqual(m.etiquetas, ['Célula Norte', 'voluntarios'], 'sin grupos de sistema y sin repetir por mayúsculas')
  assert.deepEqual(m.direcciones, [{ valor: 'Calle Falsa 123, Sevilla', etiqueta: 'Casa' }], 'la dirección formateada pierde sus saltos de línea')
  const s = a.personas[1]!
  assert.equal(s.fecha_nacimiento, null); assert.equal(a.resumen.cumpleanosSinAnio, 1)
  assert.deepEqual(s.direcciones, [{ valor: 'Av. Sol 5, Sevilla, España' }], 'sin dirección formateada se arma con calle, ciudad y país')
  const fila = aFilaImportacion(m)
  assert.equal(fila.email, 'maria@x.test'); assert.equal(fila.telefono, '+34600111222')
  assert.deepEqual(fila.contactos.filter(c => c.tipo === 'correo').map(c => c.valor), ['maria.alt@x.test', 'trabajo@x.test'])
  assert.deepEqual(fila.contactos.filter(c => c.tipo === 'telefono').map(c => c.valor), ['915550123'])
  assert.equal(fila.contactos.filter(c => c.tipo === 'etiqueta').length, 2)
  assert.ok(!('Photo' in fila) && !JSON.stringify(a).includes('http://foto'), 'la foto no se importa')
}

// ---------- Formato antiguo de Google y Outlook ----------
{
  const a = analizarGoogle(csv([
    ['Name', 'Given Name', 'Additional Name', 'Family Name', 'Birthday', 'Group Membership', 'E-mail 1 - Type', 'E-mail 1 - Value', 'Phone 1 - Type', 'Phone 1 - Value'],
    ['Ana Pérez', 'Ana', '', 'Pérez', '1985-03-05', '* My Contacts ::: Familia', 'Home', 'ana@x.test', 'Mobile', '600 123 456'],
    ['Solo Nombre Completo', '', '', '', '', '', '', '', '', ''],
  ]))
  assert.equal(a.personas[0]?.nombre, 'Ana'); assert.deepEqual(a.personas[0]?.etiquetas, ['Familia'])
  assert.equal(a.personas[1]?.nombre, 'Solo Nombre Completo', 'sin nombre ni apellido separados se usa el nombre completo')
  const o = analizarGoogle(csv([
    ['First Name', 'Last Name', 'E-mail Address', 'E-mail 2 Address', 'Mobile Phone', 'Home Phone', 'Birthday', 'Home Street', 'Home City', 'Categories'],
    ['Eva', 'Sol', 'eva@x.test', 'eva2@x.test', '600111222', '915550123', '1990-01-02', 'Calle 1', 'Sevilla', 'Amigos;Iglesia'],
  ]))
  assert.deepEqual(o.personas[0]?.emails, ['eva@x.test', 'eva2@x.test'])
  assert.deepEqual(o.personas[0]?.telefonos.map(t => t.valor), ['600111222', '915550123'])
  assert.deepEqual(o.personas[0]?.etiquetas, ['Amigos', 'Iglesia']); assert.equal(o.personas[0]?.direcciones[0]?.etiqueta, 'home')
}

// ---------- Reglas de descarte, fusión y duplicados ----------
{
  const a = analizarGoogle(csv([
    ['First Name', 'Last Name', 'E-mail 1 - Value', 'E-mail 2 - Value', 'Phone 1 - Value', 'Notes'],
    ['Ana', 'Pérez', 'ana@x.test', '', '600111222', 'nota 1'],
    ['Ana', 'P.', '', 'ANA@x.test', '600-111-222', 'nota 2'],                // mismo correo, otra caja: se fusiona
    ['', '', 'otro@x.test', 'ana@x.test', '', ''],                           // sin nombre, comparte correo con Ana: se fusiona y no queda sin nombre
    ['', '', '', '', '', 'solo una nota'],                                   // sin nombre y sin contacto: se descarta
    ['', '', 'correo-malo', '', 'abc', ''],                                  // sin nombre y solo datos inválidos: se descarta
    ['', '', 'huerfano@x.test', '', '', ''],                                 // sin nombre con correo: aparte
    ['', '', '', '', '+34 611 222 333', ''],                                 // sin nombre con teléfono: aparte
    ['Luis', '', '', '', '+34-611-222-333', ''],                              // sin correo y mismo teléfono que el anterior, con otro formato: se fusiona y toma el nombre
    ['Pía', 'Sola', '', '', '', ''],                                         // solo nombre
    ['pía', 'sola', '', '', '', ''],                                         // mismo nombre sin contacto: repetido
    ['Eva', 'Ruiz', 'eva@x.test', '', '600111222', ''],                      // mismo teléfono que Ana, pero con correo propio: persona distinta
  ]))
  assert.deepEqual(a.personas.map(p => p.nombre), ['Ana', 'huerfano@x.test', 'Luis', 'Pía', 'Eva'])
  const ana = a.personas[0]!
  assert.deepEqual(ana.emails.sort(), ['ana@x.test', 'otro@x.test'])
  assert.equal(ana.notas, 'nota 1', 'al fusionar se conserva lo ya guardado')
  assert.equal(a.resumen.descartadasVacias, 2)
  assert.equal(a.resumen.fusionadas, 4)
  assert.equal(a.resumen.sinNombre, 1, 'solo queda aparte el correo huérfano: el teléfono sin nombre ganó el de Luis')
  assert.equal(a.personas[2]?.nombreDerivado, false)
  assert.equal(a.personas.find(p => p.nombre === 'Eva')?.emails[0], 'eva@x.test')
  assert.equal(a.resumen.correosInvalidos, 1)
  // Contra lo que la iglesia ya tiene: el mismo orden de reglas que la base
  const existentes = { correos: new Set(['ana@x.test']), telefonos: new Set(['+34611222333']), nombres: new Set(['pia sola']) }
  assert.equal(esDuplicadoDeExistente(a.personas[0]!, existentes), true, 'por correo')
  assert.equal(esDuplicadoDeExistente(a.personas.find(p => p.nombre === 'Luis')!, existentes), true, 'sin correo, por teléfono')
  assert.equal(esDuplicadoDeExistente(a.personas.find(p => p.nombre === 'Pía')!, existentes), true, 'sin correo ni teléfono, por nombre sin acentos')
  assert.equal(esDuplicadoDeExistente(a.personas.find(p => p.nombre === 'Eva')!, existentes), false)
}

// ---------- Límites ----------
assert.equal(analizarGoogle(csv([['First Name', 'E-mail 1 - Value'], ...Array.from({ length: g.MAX_FILAS_GOOGLE + 1 }, (_, i) => [`N${i}`, `n${i}@x.test`])])).error, 'demasiadasFilas')
{
  const largo = analizarGoogle(csv([['First Name', 'Last Name', 'E-mail 1 - Value', 'Notes'], ['A'.repeat(300), 'B'.repeat(300), 'a@x.test', 'n'.repeat(1500)]]))
  assert.equal(largo.personas[0]?.nombre.length, 100); assert.equal(largo.personas[0]?.apellido.length, 100)
  assert.equal(largo.personas[0]?.notas?.length, 1000); assert.equal(largo.resumen.notasRecortadas, 1)
}

// ---------- A escala: las cifras de Gerencia, con un modelo que conoce la respuesta ----------
{
  let semilla = 7
  const azar = (n: number) => { semilla = (semilla * 1664525 + 1013904223) % 4294967296; return semilla % n }
  const NOMBRES = ['Lucía', 'Pablo', 'Marta', 'Andrés', 'Sara', 'Jorge', 'Elena', 'Daniel', 'Zoë', 'Mateo', 'Noemí', 'Tomás']
  const APELLIDOS = ['Romero', 'Cano', 'Gil', 'Vela', 'Molina', "O'Brien", 'Ruiz, Jr.', 'Peña']
  let contador = 0
  const unico = () => ++contador
  const conFormato = (n: number, formato: number) => { const d = String(600000000 + n); return [`${d.slice(0, 3)} ${d.slice(3, 6)} ${d.slice(6)}`, `${d.slice(0, 3)}-${d.slice(3, 6)}-${d.slice(6)}`, `(${d.slice(0, 3)}) ${d.slice(3, 6)} ${d.slice(6)}`, d][formato % 4]! }
  interface Persona { nombre: string; apellido: string; emails: string[]; tel: number | null; filas: number }
  const personas: Persona[] = []
  const nueva = (tipo: Partial<Persona> & { filas: number }): Persona => { const p: Persona = { nombre: '', apellido: '', emails: [], tel: null, ...tipo }; personas.push(p); return p }
  const nombre = () => ({ nombre: `${NOMBRES[azar(NOMBRES.length)]} ${unico()}`, apellido: APELLIDOS[azar(APELLIDOS.length)]! })
  // Con nombre: 1.400 con correo (500 con segundo correo), 700 solo con teléfono y 200 sin nada
  const conNombre: Persona[] = []
  for (let i = 0; i < 1400; i++) conNombre.push(nueva({ ...nombre(), emails: i < 500 ? [`p${unico()}@x.test`, `p${unico()}@x.test`] : [`p${unico()}@x.test`], filas: 0 }))
  for (let i = 0; i < 700; i++) conNombre.push(nueva({ ...nombre(), tel: unico(), filas: 0 }))
  for (let i = 0; i < 200; i++) conNombre.push(nueva({ ...nombre(), filas: 0 }))
  // 4.166 filas con nombre repartidas entre las 2.300 personas
  conNombre.forEach((p, i) => { p.filas = 1 + (i < 1866 ? 1 : 0) })
  // Sin nombre: 316 con correo (700 filas), 300 solo con teléfono (534 filas) y 700 filas vacías con un teléfono inválido
  const sinNombreCorreo = Array.from({ length: 316 }, () => nueva({ emails: [`u${unico()}@x.test`], filas: 0 }))
  sinNombreCorreo.forEach((p, i) => { p.filas = 2 + (i < 68 ? 1 : 0) })  // 316*2 + 68 = 700
  const sinNombreTel = Array.from({ length: 300 }, () => nueva({ tel: unico(), filas: 0 }))
  sinNombreTel.forEach((p, i) => { p.filas = 1 + (i < 234 ? 1 : 0) })    // 300 + 234 = 534
  assert.equal(conNombre.reduce((a, p) => a + p.filas, 0), 4166)
  assert.equal(sinNombreCorreo.reduce((a, p) => a + p.filas, 0) + sinNombreTel.reduce((a, p) => a + p.filas, 0), 1234)

  const CAB = ['First Name', 'Middle Name', 'Last Name', 'Phonetic First Name', 'Nickname', 'Organization Name', 'Birthday', 'Notes', 'Photo', 'Labels', 'E-mail 1 - Label', 'E-mail 1 - Value', 'E-mail 2 - Label', 'E-mail 2 - Value', 'Phone 1 - Label', 'Phone 1 - Value', 'Phone 2 - Label', 'Phone 2 - Value', 'Phone 3 - Label', 'Phone 3 - Value', 'Address 1 - Label', 'Address 1 - Formatted', 'Custom Field 1 - Label', 'Custom Field 1 - Value', 'Password']
  const filas: string[][] = []
  let invalidosTel = 0, invalidosCorreo = 0, secretos = 0
  const fila = (p: Persona, k: number, extra: Partial<Record<string, string>> = {}) => {
    const v: Record<string, string> = Object.fromEntries(CAB.map(c => [c, '']))
    v['First Name'] = p.nombre; v['Last Name'] = p.apellido
    if (p.nombre) { v['Labels'] = '* myContacts ::: Iglesia'; v['Birthday'] = k % 3 === 0 ? '1990-05-21' : '' }
    // Un correo cambia de caja y de columna entre filas del mismo contacto; con dos correos, la fila repetida trae solo uno
    if (p.emails.length === 2) {
      if (k === 0) { v['E-mail 1 - Value'] = p.emails[0]!; v['E-mail 2 - Value'] = p.emails[1]!.toUpperCase() }
      else v['E-mail 1 - Value'] = p.emails[1]!.toUpperCase()
    } else if (p.emails.length === 1) { v['E-mail 1 - Value'] = k % 2 ? p.emails[0]!.toUpperCase() : p.emails[0]!; if (k % 4 === 3) v['E-mail 2 - Value'] = p.emails[0]! }
    if (p.tel !== null) v['Phone 1 - Value'] = conFormato(p.tel, k)
    Object.assign(v, extra)
    filas.push(CAB.map(c => v[c]!))
  }
  const todas: [Persona, number][] = []
  for (const p of personas) for (let k = 0; k < p.filas; k++) todas.push([p, k])
  // Mezclar para que las repeticiones no estén seguidas
  for (let i = todas.length - 1; i > 0; i--) { const j = azar(i + 1); [todas[i], todas[j]] = [todas[j]!, todas[i]!] }
  const vistas = new Map<Persona, number>()
  todas.forEach(([p]) => {
    const k = vistas.get(p) ?? 0; vistas.set(p, k + 1)
    const extra: Record<string, string> = {}
    // 260 teléfonos inválidos y 50 correos inválidos en filas con nombre, y secretos en la columna de contraseña y en notas
    if (p.nombre && invalidosTel < 260 && azar(10) === 0) { extra['Phone 3 - Value'] = 'no es un teléfono'; invalidosTel++ }
    // El segundo correo inválido solo va donde esa columna está libre
    if (p.nombre && invalidosCorreo < 50 && p.emails.length < 2 && !(p.emails.length === 1 && k % 4 === 3) && azar(40) === 0) { extra['E-mail 2 - Value'] = 'correo-malo'; invalidosCorreo++ }
    if (azar(20) === 0) { extra['Password'] = `S3CR3T-${++secretos}` }
    if (p.nombre && azar(50) === 0) { extra['Notes'] = `Contraseña: S3CR3T-N${++secretos}` }
    if (p.nombre && azar(5) === 0) extra['Notes'] = extra['Notes'] ?? 'Nota normal, con "comillas" y coma'
    fila(p, k, extra)
  })
  // 700 filas vacías, cada una con un teléfono inválido
  for (let i = 0; i < 700; i++) { const v: string[] = CAB.map(() => ''); v[CAB.indexOf('Phone 1 - Value')] = i % 2 ? 'sin número' : '12345'; v[CAB.indexOf('Photo')] = 'http://foto'; filas.push(v) }
  // Completar hasta las 960 exactas (la mezcla azarosa puede no haber llegado a 260)
  let faltan = 260 - invalidosTel
  for (let i = 0; i < filas.length && faltan > 0; i++) {
    const f = filas[i]!
    if (f[CAB.indexOf('First Name')] && !f[CAB.indexOf('Phone 3 - Value')]) { f[CAB.indexOf('Phone 3 - Value')] = 'no es un teléfono'; faltan--; invalidosTel++ }
  }
  assert.equal(invalidosTel, 260)
  assert.equal(filas.length, 6100, '4.166 filas con nombre + 1.234 sin nombre con contacto + 700 vacías')
  const texto = csv([CAB, ...filas])

  const t0 = Date.now()
  const a = analizarGoogle(texto)
  const ms = Date.now() - t0
  const r = a.resumen
  assert.equal(r.filas, 6100)
  assert.equal(filas.filter(f => !f[CAB.indexOf('First Name')] && !f[CAB.indexOf('Last Name')]).length, 1934, 'el archivo tiene 1.934 filas sin nombre')
  assert.equal(r.telefonosInvalidos, 700 + 260, 'el archivo tiene 960 teléfonos inválidos y se cuentan todos')
  assert.equal(r.correosInvalidos, invalidosCorreo)
  assert.equal(r.descartadasVacias, 700, 'las filas sin nombre y sin contacto se descartan')
  const esperadas = 1400 + 700 + 200 + 316 + 300
  assert.equal(r.personas, esperadas, 'cada persona sale una sola vez, aunque tenga varias filas, otro correo o distinta caja')
  assert.equal(a.personas.length, esperadas)
  assert.equal(r.fusionadas, 6100 - 700 - esperadas)
  assert.equal(r.sinNombre, 316 + 300, 'quedan aparte las personas sin nombre pero con contacto')
  const correos = a.personas.flatMap(p => p.emails)
  assert.equal(new Set(correos).size, correos.length, 'ningún correo aparece en dos personas')
  assert.equal(correos.length, 2216, 'salen los 2.216 correos únicos del archivo')
  assert.ok(correos.every(c => c === c.toLowerCase() && c.includes('@')), 'todos en minúsculas')
  const telefonos = a.personas.flatMap(p => p.telefonos.map(t => t.valor))
  assert.ok(telefonos.every(t => /^\d{9}$/.test(t)), 'los teléfonos salen en forma canónica')
  assert.ok(a.personas.filter(p => p.nombreDerivado).every(p => p.nombre === p.emails[0] || p.nombre === p.telefonos[0]?.valor), 'sin nombre, el correo o el teléfono hacen de nombre')
  assert.deepEqual(a.columnasSensibles, ['Password'])
  const todoJson = JSON.stringify(a)
  assert.ok(!todoJson.includes('S3CR3T'), 'ninguna clave, ni de la columna ni de las notas, llega al resultado')
  assert.ok(r.notasConClave > 0, 'se descartaron notas con claves')
  assert.ok(!todoJson.includes('http://foto'), 'la foto no se importa')
  assert.ok(ms < 3000, `6.100 filas se leen en menos de 3 s (${ms} ms)`)
  // Lo que se envía a la base cabe en lotes de LOTE_GOOGLE y no lleva campos fuera de la lista
  const enviado = a.personas.map(aFilaImportacion)
  assert.ok(enviado.every(f => Object.keys(f).sort().join() === 'apellido,contactos,email,fecha_nacimiento,nombre,notas,telefono'))
  console.log(`   A escala: ${r.filas} filas → ${r.personas} personas (${r.sinNombre} sin nombre), ${r.fusionadas} fusionadas, ${r.descartadasVacias} vacías descartadas, ${correos.length} correos, en ${ms} ms`)
}

console.log('OK: todas las pruebas de contactos de Google pasan')
