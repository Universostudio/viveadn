// Prueba de los reportes de la plataforma (crecimiento, distribución, personas, módulos), sin navegador ni red. Uso: npm run test:reportes
import assert from 'node:assert/strict'
import { crecimiento, distribucion, modulos, personas } from '../src/views/plataforma/reportes.ts'
import { vistaDe } from '../src/views/plataforma/adaptador.ts'

const AHORA = Date.UTC(2026, 10, 16, 12) // 16 de noviembre de 2026
const f = (o: any) => ({ id: 'x', nombre: 'N', slug: 's', plan: 'premium', activa: true, etapa: 'activa', prueba_hasta: null, borrado_programado_en: null, adn_borrada_en: null, es_demo: false, created_at: '2026-01-10T00:00:00Z', iglesia_madre_id: null, miembros: 0, usuarios: 0, addons: [], ...o })

const lista = [
  f({ id: 'a', created_at: '2026-01-10T00:00:00Z', miembros: 100, usuarios: 4 }),
  f({ id: 'b', created_at: '2026-09-30T23:59:59Z', plan: 'semilla', miembros: 40, usuarios: 2 }),
  f({ id: 'c', created_at: '2026-10-01T00:00:00Z', etapa: 'prueba', plan: 'semilla', miembros: 10, usuarios: 1 }),
  f({ id: 'd', created_at: '2026-10-05T00:00:00Z', adn_borrada_en: '2026-11-02T10:00:00Z', etapa: 'suspendida', activa: false, miembros: 500, usuarios: 9 }),
  f({ id: 'e', created_at: '2026-11-03T00:00:00Z', etapa: 'onboarding', plan: 'semilla', miembros: 0, usuarios: 1 }),
  f({ id: 'g', created_at: '2026-06-15T00:00:00Z', etapa: 'receso', activa: false, plan: 'premium', miembros: 20, usuarios: 1 }),
  f({ id: 'h', created_at: '2026-11-10T00:00:00Z', es_demo: true, miembros: 300, usuarios: 6 }),
]
const reales = lista.filter(i => !i.es_demo)

// Crecimiento: 12 meses, el último es noviembre de 2026
const c = crecimiento(reales, AHORA)
assert.equal(c.length, 12); assert.equal(c[0].mes, '2025-12'); assert.equal(c[11].mes, '2026-11')
const mes = (m: string) => c.find(x => x.mes === m)!
assert.deepEqual(mes('2026-09'), { mes: '2026-09', altas: 1, bajas: 0, acumuladas: 3 }, 'el borde 30 de septiembre cuenta en septiembre')
assert.deepEqual(mes('2026-10'), { mes: '2026-10', altas: 2, bajas: 0, acumuladas: 5 })
assert.deepEqual(mes('2026-11'), { mes: '2026-11', altas: 1, bajas: 1, acumuladas: 5 }, 'una alta y una baja en noviembre')
assert.equal(mes('2026-01').acumuladas, 1); assert.equal(mes('2025-12').acumuladas, 0, 'antes de la primera alta no hay nada')
assert.deepEqual(crecimiento([], AHORA, 3).map(x => x.acumuladas), [0, 0, 0])

// Las demostraciones entran o salen con la misma regla que todo el panel
assert.equal(crecimiento(vistaDe(lista as any, true), AHORA).at(-1)!.acumuladas, 6)
assert.equal(crecimiento(vistaDe(lista as any, false), AHORA).at(-1)!.acumuladas, 5)

// Distribución: las dadas de baja no entran; los planes del catálogo salen aunque estén vacíos
const d = distribucion(reales, [{ clave: 'semilla' }, { clave: 'premium' }, { clave: 'nuevo' }])
assert.deepEqual(d.filas.map(x => [x.plan, x.total]), [['semilla', 3], ['premium', 2], ['nuevo', 0]])
assert.deepEqual(d.totalPorEtapa, { onboarding: 1, prueba: 1, activa: 2, receso: 1, suspendida: 0 })
assert.equal(d.total, 5)
assert.equal(distribucion([f({ plan: 'viejo' })], []).filas[0].plan, 'viejo', 'un plan fuera del catálogo no se pierde')

// Personas: solo vivas
const p = personas(reales)
assert.equal(p.miembros, 170); assert.equal(p.usuarios, 9); assert.equal(p.iglesias, 5); assert.equal(p.promedio, 34)
assert.deepEqual(p.porPlan, [{ plan: 'premium', miembros: 120, iglesias: 2 }, { plan: 'semilla', miembros: 50, iglesias: 3 }])
assert.equal(personas([]).promedio, null, 'sin iglesias no hay promedio inventado')
assert.equal(personas([f({ miembros: undefined })]).miembros, 0)

// Módulos: acceso por plan o por complemento, solo iglesias con servicio
const cat = { planes: [], modulos: [{ clave: 'm', nombre: 'Miembros', tipo: 'nucleo' }, { clave: 'e', nombre: 'Eventos', tipo: 'opcional' }],
  planModulos: [{ plan: 'premium', modulo: 'm' }, { plan: 'semilla', modulo: 'm' }, { plan: 'premium', modulo: 'e' }] }
const conComplemento = reales.map(i => i.id === 'b' ? { ...i, addons: [{ modulo: 'e', activo: true }] } : i.id === 'c' ? { ...i, addons: [{ modulo: 'e', activo: false }] } : i)
const m = modulos(conComplemento, cat)
// Con servicio: a (activa premium), b (activa semilla), c (prueba semilla), e (alta semilla). g está en receso: fuera
assert.deepEqual(m.find(x => x.clave === 'm'), { clave: 'm', nombre: 'Miembros', tipo: 'nucleo', conAcceso: 4, deTotal: 4, porComplemento: 0 })
assert.deepEqual(m.find(x => x.clave === 'e'), { clave: 'e', nombre: 'Eventos', tipo: 'opcional', conAcceso: 2, deTotal: 4, porComplemento: 1 }, 'a por plan, b por complemento activo, c con complemento apagado no')
assert.equal(modulos([], cat)[0].deTotal, 0)
console.log('Reportes de la plataforma: todo correcto')
