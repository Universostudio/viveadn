// Exporta una iglesia por páginas desde una base de PostgreSQL local, con el mismo recorrido que usa el panel (src/lib/exportacionPaginada.ts),
// y escribe el ZIP en un archivo. Es la fuente de pruebas: cada página es una llamada a psql, como en la función de borde lo es una llamada a la base.
// Uso: PGUSER=postgres node exportar_paginado.mts <base> <uuid_de_la_iglesia> <salida.zip> [filas_por_pagina]
// Imprime una línea JSON con las cifras: filas, bytes, páginas, segundos y el pico de memoria del proceso (VmHWM).
import { spawnSync } from 'node:child_process'
import { openSync, writeSync, closeSync, readFileSync } from 'node:fs'
const { exportarPaginado } = await import('../../../src/lib/exportacionPaginada.ts')
type Fuente = import('../../../src/lib/exportacionPaginada.ts').Fuente

const [base, iglesia, salida, limiteTxt] = process.argv.slice(2)
if (!base || !iglesia || !salida || !/^[0-9a-f-]{36}$/i.test(iglesia) || !/^[A-Za-z0-9_]+$/.test(base)) {
  console.error('Uso: exportar_paginado.mts <base> <uuid_de_la_iglesia> <salida.zip> [filas_por_pagina]'); process.exit(2)
}
const limite = limiteTxt ? Number(limiteTxt) : 1000
let llamadasSql = 0; let msSql = 0

function sql(consulta: string): any {
  const t0 = Date.now()
  const r = spawnSync('psql', ['-X', '-q', '-At', '-v', 'ON_ERROR_STOP=1', '-d', base, '-c', consulta], { encoding: 'utf8', maxBuffer: 1024 * 1024 * 1024 })
  msSql += Date.now() - t0; llamadasSql++
  if (r.status !== 0) throw new Error(`psql falló: ${String(r.stderr).split('\n')[0]}`)
  return JSON.parse(r.stdout)
}
const q = (s: string) => `'${s.replace(/'/g, "''")}'`

const fuente = {
  async plan() { return sql(`select public.adn_exportar_plan(${q(iglesia)})`) },
  async pagina(tabla: string, formato: 'json' | 'csv', despues: string[] | null, lim: number) {
    if (!/^[a-z][a-z0-9_]*$/.test(tabla)) throw new Error('tabla no válida')
    return sql(`select public.adn_exportar_pagina(${q(iglesia)}, ${q(tabla)}, ${q(formato)}, ${despues ? q(JSON.stringify(despues)) + '::jsonb' : 'null'}, ${lim})`)
  },
} as Fuente

const fd = openSync(salida, 'w')
const t0 = Date.now()
try {
  const r = await exportarPaginado(fuente, { slug: 'prueba', hoy: new Date(), leeme: 'Exportación de prueba por páginas\n', limite, destino: p => { writeSync(fd, p) } })
  const hwm = Number(/VmHWM:\s+(\d+) kB/.exec(readFileSync('/proc/self/status', 'utf8'))?.[1] ?? 0) / 1024
  console.log(JSON.stringify({ filas: r.filas, tablas: r.tablas, bytes: r.bytes, paginas: r.paginas, cambios: r.cambios, segundos: +((Date.now() - t0) / 1000).toFixed(1), segundos_sql: +(msSql / 1000).toFixed(1), llamadas_sql: llamadasSql, pico_memoria_mb: Math.round(hwm) }))
} finally { closeSync(fd) }
