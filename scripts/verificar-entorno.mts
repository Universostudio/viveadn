// Verifica un entorno de pruebas desplegado (web, salud, funciones de borde, purga). No crea ni borra nada y no envía correos.
// Las claves se leen del entorno del que ejecuta, nunca de un archivo del repositorio, y nunca se imprimen.
// Uso:
//   ADN_WEB_URL=https://<web-de-pruebas> VITE_SUPABASE_URL=https://<proyecto>.supabase.co \
//   [VITE_SUPABASE_ANON_KEY=...] [ADN_CRON_SECRET=...] npm run check:entorno
import { verificar } from './entorno/verificar.mts'

const web = process.env.ADN_WEB_URL ?? ''
const supabase = process.env.VITE_SUPABASE_URL ?? ''
if (!web || !supabase) {
  console.error('Faltan ADN_WEB_URL y VITE_SUPABASE_URL (solo se leen del entorno; ver docs/PUESTA-EN-MARCHA.md).')
  process.exit(2)
}
const res = await verificar({ web, supabase, anon: process.env.VITE_SUPABASE_ANON_KEY, cron: process.env.ADN_CRON_SECRET })
for (const x of res) console.log(`${x.ok ? 'OK   ' : 'FALLO'} ${x.nombre}: ${x.detalle}`)
const fallos = res.filter(x => !x.ok).length
console.log(fallos ? `\n${fallos} comprobación(es) fallida(s) de ${res.length}` : `\nOK: ${res.length} comprobaciones`)
if (!process.env.ADN_CRON_SECRET) console.log('Nota: sin ADN_CRON_SECRET no se comprueba el estado de la purga ni el libro.')
process.exit(fallos ? 1 : 0)
