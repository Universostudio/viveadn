// Prueba de la validación del precio y de la simulación de facturación (modo de prueba). Uso: npm run test:facturacion
import assert from 'node:assert/strict'
import { motivoFuera, simular, validarPrecio } from '../supabase/functions/plataforma/facturacion.ts'

// Validación
assert.deepEqual(validarPrecio({ plan: 'premium', precio_mensual_centimos: 1900, precio_anual_centimos: 19000, moneda: ' eur ' }), { ok: true, clave: 'premium', mensual: 1900, anual: 19000, moneda: 'EUR' })
assert.deepEqual(validarPrecio({ plan: 'semilla', precio_mensual_centimos: '', precio_anual_centimos: null }), { ok: true, clave: 'semilla', mensual: null, anual: null, moneda: null }, 'vaciar borra el precio')
assert.deepEqual(validarPrecio({ plan: 'semilla', moneda: 'EUR' }), { ok: true, clave: 'semilla', mensual: null, anual: null, moneda: null }, 'moneda sin precio no se guarda')
for (const mal of [{}, { plan: 'A B' }, { plan: 'p', precio_mensual_centimos: -1, moneda: 'EUR' }, { plan: 'p', precio_mensual_centimos: 19.5, moneda: 'EUR' }, { plan: 'p', precio_mensual_centimos: '19', moneda: 'EUR' },
  { plan: 'p', precio_mensual_centimos: 100 }, { plan: 'p', precio_mensual_centimos: 100, moneda: 'euro' }, { plan: 'p', precio_mensual_centimos: 99_999_999, moneda: 'EUR' }, { plan: 'p', precio_anual_centimos: 1e9, moneda: 'EUR' }])
  assert.equal(validarPrecio(mal as any).ok, false, JSON.stringify(mal))

// Quién entra en el cálculo: solo activas, no demo, no borradas
const ig = (plan: string, etapa: string | null, extra = {}) => ({ plan, etapa, activa: etapa === 'activa', es_demo: false, adn_borrada_en: null, ...extra })
assert.equal(motivoFuera(ig('a', 'activa')), null)
assert.equal(motivoFuera(ig('a', 'prueba')), 'prueba'); assert.equal(motivoFuera(ig('a', 'onboarding')), 'onboarding'); assert.equal(motivoFuera(ig('a', 'receso')), 'receso')
assert.equal(motivoFuera(ig('a', 'suspendida')), 'suspendida'); assert.equal(motivoFuera(ig('a', 'activa', { es_demo: true })), 'demo')
assert.equal(motivoFuera(ig('a', 'activa', { adn_borrada_en: '2026-11-01' })), 'borrada')
assert.equal(motivoFuera({ plan: 'a', activa: true, etapa: null }), null, 'sin etapa, activa cuenta como activa')
assert.equal(motivoFuera({ plan: 'a', activa: false, etapa: null }), 'suspendida')

const planes = [
  { clave: 'semilla', nombre: 'Semilla', precio_mensual_centimos: null, precio_anual_centimos: null, moneda: null },
  { clave: 'premium', nombre: 'Premium', precio_mensual_centimos: 4900, precio_anual_centimos: 49000, moneda: 'EUR' },
  { clave: 'vacio', nombre: 'Vacío', precio_mensual_centimos: 100, precio_anual_centimos: null, moneda: 'EUR' },
]
const iglesias = [ig('premium', 'activa'), ig('premium', 'activa'), ig('semilla', 'activa'), ig('premium', 'prueba'), ig('premium', 'activa', { es_demo: true }), ig('semilla', 'receso'),
  ig('premium', 'suspendida'), ig('premium', 'onboarding'), ig('premium', 'activa', { adn_borrada_en: '2026-10-01' }), ig('antiguo', 'activa')]
const s = simular(iglesias, planes)
assert.equal(s.etiqueta, 'datos_de_prueba')
const f = (c: string) => s.planes.find(p => p.clave === c)!
assert.equal(f('premium').iglesias, 2); assert.equal(f('premium').ingreso_mensual_centimos, 9800); assert.equal(f('premium').causa, null)
assert.equal(f('semilla').iglesias, 1); assert.equal(f('semilla').ingreso_mensual_centimos, null, 'con iglesias y sin precio no se inventa un cero'); assert.equal(f('semilla').causa, 'sin_precio')
assert.equal(f('vacio').iglesias, 0); assert.equal(f('vacio').ingreso_mensual_centimos, 0); assert.equal(f('vacio').causa, 'sin_iglesias', 'el cero honesto lleva su causa')
assert.equal(s.plan_desconocido, 1); assert.equal(s.pagando, 4); assert.equal(s.incompleto, true)
assert.deepEqual(s.ingreso_mensual_por_moneda, { EUR: 9800 })
assert.deepEqual(s.fuera_del_calculo, { demo: 1, onboarding: 1, prueba: 1, receso: 1, suspendida: 1, borrada: 1 })

// Nada de iglesias: todo cero con causa, y completo
const v = simular([], planes)
assert.equal(v.pagando, 0); assert.equal(v.incompleto, false); assert.deepEqual(v.ingreso_mensual_por_moneda, {}); assert.ok(v.planes.every(p => p.ingreso_mensual_centimos === 0 && p.causa === 'sin_iglesias'))
// Entradas nulas no rompen
assert.equal(simular(null, null).pagando, 0)
// Dos monedas no se suman entre sí
const dos = simular([ig('a', 'activa'), ig('b', 'activa')], [{ clave: 'a', precio_mensual_centimos: 1000, moneda: 'EUR' }, { clave: 'b', precio_mensual_centimos: 2000, moneda: 'USD' }])
assert.deepEqual(dos.ingreso_mensual_por_moneda, { EUR: 1000, USD: 2000 })
// El resultado no lleva nada de personas
assert.doesNotMatch(JSON.stringify(s), /email|nombre_iglesia|telefono/i)
console.log('Facturación (modo de prueba): todo correcto')

// M6: el agregado de SQL (una fila por grupo con su número) simula exactamente igual que la lista de iglesias de una en una
import { filasDeFacturacion } from '../supabase/functions/plataforma/facturacion.ts'
{
  const uno = (plan: string, etapa: string, es_demo = false, borrada = false) => ({ plan, activa: etapa !== 'suspendida', etapa, es_demo, adn_borrada_en: borrada ? 'x' : null })
  const lista = [uno('premium', 'activa'), uno('premium', 'activa'), uno('semilla', 'activa'), uno('premium', 'prueba'), uno('premium', 'activa', true), uno('semilla', 'suspendida', false, true), uno('inventado', 'activa')]
  const planes = [{ clave: 'semilla', nombre: 'Semilla', precio_mensual_centimos: 500, moneda: 'EUR' }, { clave: 'premium', nombre: 'Premium', precio_mensual_centimos: 2000, moneda: 'EUR' }]
  const grupos = new Map<string, any>()
  for (const i of lista) { const k = JSON.stringify([i.plan, i.activa, i.etapa, i.es_demo, !!i.adn_borrada_en]); const g = grupos.get(k) ?? { plan: i.plan, activa: i.activa, etapa: i.etapa, es_demo: i.es_demo, borrada: !!i.adn_borrada_en, n: 0 }; g.n++; grupos.set(k, g) }
  const agregado = [...grupos.values()].map(g => ({ ...g, n: String(g.n) }))
  assert.deepEqual(simular(filasDeFacturacion(agregado), planes), simular(lista, planes), 'agregado y lista de una en una dan la misma simulación')
  assert.deepEqual(simular(filasDeFacturacion(null), planes).pagando, 0)
  console.log('Facturación: el agregado de SQL equivale a la lista')
}

// ---- Impuestos: configuración sin tasas de fábrica
{
  const { validarImpuestos, resumenImpuestos } = await import('../supabase/functions/plataforma/facturacion.ts')
  assert.deepEqual(resumenImpuestos(undefined), { estado: 'pendiente', reglas: [], activas: 0, aplicados_en_simulacion: false }, 'sin nada guardado: pendiente de configurar, sin tasas inventadas')
  assert.equal(resumenImpuestos({ reglas: 'basura' }).estado, 'pendiente'); assert.equal(resumenImpuestos(null).estado, 'pendiente')
  const ok = validarImpuestos({ reglas: [{ region: ' es ', concepto: ' IVA ', tasa_pct: 21, activo: true, incluido_en_precio: false }, { region: 'MX', concepto: 'IVA', tasa_pct: 16.0125 }] })
  assert.ok(ok.ok)
  if (ok.ok) {
    assert.deepEqual(ok.reglas[0], { region: 'ES', concepto: 'IVA', tasa_pct: 21, activo: true, incluido_en_precio: false })
    assert.deepEqual(ok.reglas[1], { region: 'MX', concepto: 'IVA', tasa_pct: 16.0125, activo: false, incluido_en_precio: null }, 'sin decir nada, la regla nace desactivada y sin marca')
  }
  assert.equal(resumenImpuestos({ reglas: ok.ok ? ok.reglas : [] }).estado, 'configurado')
  assert.equal(resumenImpuestos({ reglas: [{ region: 'MX', concepto: 'IVA', tasa_pct: 16, activo: false }] }).estado, 'pendiente', 'una regla desactivada no cuenta')
  assert.deepEqual(validarImpuestos({ reglas: [] }), { ok: true, reglas: [] }, 'vaciar la lista es válido')
  for (const mal of [{}, { reglas: 'x' }, { reglas: [null] }, { reglas: [{ region: 'E', concepto: 'IVA', tasa_pct: 1 }] }, { reglas: [{ region: 'ES', concepto: '', tasa_pct: 1 }] },
    { reglas: [{ region: 'ES', concepto: '<b>', tasa_pct: 1 }] }, { reglas: [{ region: 'ES', concepto: 'IVA', tasa_pct: -1 }] }, { reglas: [{ region: 'ES', concepto: 'IVA', tasa_pct: 100.5 }] },
    { reglas: [{ region: 'ES', concepto: 'IVA', tasa_pct: '21' }] }, { reglas: [{ region: 'ES', concepto: 'IVA', tasa_pct: 1.00001 }] }, { reglas: [{ region: 'ES', concepto: 'IVA', tasa_pct: NaN }] },
    { reglas: [{ region: 'ES', concepto: 'IVA', tasa_pct: 1, activo: 'si' }] }, { reglas: [{ region: 'ES', concepto: 'IVA', tasa_pct: 1, incluido_en_precio: 1 }] },
    { reglas: [{ region: 'ES', concepto: 'IVA', tasa_pct: 1 }, { region: 'es', concepto: 'iva', tasa_pct: 2 }] },
    { reglas: Array.from({ length: 51 }, (_, i) => ({ region: 'R' + i, concepto: 'X', tasa_pct: 1 })) }])
    assert.equal(validarImpuestos(mal as any).ok, false, JSON.stringify(mal).slice(0, 80))
  // La simulación sigue siendo antes de impuestos: el módulo de cálculo no los usa
  assert.equal(JSON.stringify(simular([], [])).includes('impuesto'), false)
}
{
  const { resumenImpuestos } = await import('../supabase/functions/plataforma/facturacion.ts')
  const { salidaSegura } = await import('../supabase/functions/plataforma/panel.ts')
  salidaSegura({ ok: true, impuestos: resumenImpuestos({ reglas: [{ region: 'ES', concepto: 'IVA', tasa_pct: 21, activo: true }] }) })   // las claves de la regla no disparan la barrera de privacidad
}
