// Prueba del seguimiento de nuevos convertidos: contactos, huecos y enlaces de llamada y WhatsApp. Sin red ni navegador.
// Uso: npm run test:seguimiento
import assert from 'node:assert/strict'
import { camposContacto, contactosDe, enlaceLlamar, enlaceWhatsApp, fechaDeContactoValida, prefijoDePais, siguienteHueco } from '../src/lib/seguimiento.ts'

// Huecos y contactos
assert.equal(siguienteHueco({}), 1)
assert.equal(siguienteHueco({ primer_contacto_fecha: 'x' }), 2)
assert.equal(siguienteHueco({ primer_contacto_fecha: 'x', segundo_contacto_fecha: 'y' }), 3)
assert.equal(siguienteHueco({ primer_contacto_fecha: 'x', segundo_contacto_fecha: 'y', tercer_contacto_fecha: 'z' }), null, 'con los tres, ya no hay hueco')
assert.equal(siguienteHueco({ segundo_contacto_fecha: 'y' }), 1, 'si falta el primero, ese es el siguiente')
assert.deepEqual(contactosDe({ primer_contacto_fecha: 'a', primer_contacto_notas: 'Llamada', tercer_contacto_fecha: 'c' }).map(c => [c.n, c.fecha, c.notas]), [[1, 'a', 'Llamada'], [3, 'c', null]])
assert.deepEqual(contactosDe({}), [])
assert.deepEqual(camposContacto(2, '2026-11-16T10:00:00Z', '  Fue amable  '), { segundo_contacto_fecha: '2026-11-16T10:00:00Z', segundo_contacto_notas: 'Fue amable' })
assert.deepEqual(camposContacto(1, '2026-11-16T10:00:00Z', '   '), { primer_contacto_fecha: '2026-11-16T10:00:00Z', primer_contacto_notas: null }, 'una nota en blanco se guarda como nula')
assert.equal(String(camposContacto(3, 'x', 'a'.repeat(5000)).tercer_contacto_notas).length, 1000, 'la nota se recorta')

// Fecha del contacto
const AHORA = Date.UTC(2026, 10, 16, 12)
assert.ok(fechaDeContactoValida('2026-11-16T11:00:00Z', AHORA))
assert.ok(fechaDeContactoValida('2026-11-16T12:04:00Z', AHORA), 'hasta 5 minutos por el reloj del dispositivo')
assert.ok(!fechaDeContactoValida('2026-11-16T12:10:00Z', AHORA))
assert.ok(!fechaDeContactoValida('no es una fecha', AHORA))

// Llamar
assert.equal(enlaceLlamar('600 123 456'), 'tel:600123456')
assert.equal(enlaceLlamar('+34 600-123-456'), 'tel:+34600123456')
assert.equal(enlaceLlamar('(600) 12'), null, 'demasiado corto')
assert.equal(enlaceLlamar('12345678901234567'), null, 'demasiado largo')
assert.equal(enlaceLlamar(null), null); assert.equal(enlaceLlamar(''), null)
assert.ok(!/[ ()-]/.test(enlaceLlamar('+1 (555) 123-4567')!), 'el enlace no lleva símbolos')

// WhatsApp: formato internacional
assert.equal(enlaceWhatsApp('+34 600 123 456'), 'https://wa.me/34600123456')
assert.equal(enlaceWhatsApp('0034600123456'), 'https://wa.me/34600123456', 'el 00 inicial se quita')
assert.equal(enlaceWhatsApp('600123456', 'España'), 'https://wa.me/34600123456', 'sin prefijo, se completa con el del país')
assert.equal(enlaceWhatsApp('600123456', 'es'), 'https://wa.me/34600123456')
assert.equal(enlaceWhatsApp('0600123456', 'ES'), 'https://wa.me/34600123456', 'se quita el cero inicial nacional')
assert.equal(enlaceWhatsApp('3001234567', 'Colombia'), 'https://wa.me/573001234567')
assert.equal(enlaceWhatsApp('600123456'), null, 'sin prefijo y sin país conocido no se adivina')
assert.equal(enlaceWhatsApp('600123456', 'Narnia'), null)
assert.equal(enlaceWhatsApp('+34 12'), null)
assert.equal(enlaceWhatsApp(null, 'ES'), null)
assert.equal(prefijoDePais('  México '), '52', 'acentos y espacios no importan')
assert.equal(prefijoDePais(null), null)
// Nada de datos personales en el enlace salvo el propio número, ni texto prefijado
assert.ok(!/text=/.test(enlaceWhatsApp('+34600123456')!), 'no se rellena ningún mensaje')

console.log('Seguimiento: todo correcto')
