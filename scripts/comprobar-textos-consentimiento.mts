// Comprueba que el texto de consentimiento del registro por QR que muestra la web (src/i18n/locales, clave
// checkin.consentimiento) es exactamente el que la migración registró para CHECKIN_TEXTO_VERSION, en los cuatro idiomas.
// Si alguien cambia el texto en la web sin crear una versión nueva, falla: la evidencia dejaría de decir la verdad.
// Uso: npm run check:textos
import { readFileSync } from 'node:fs'
import { CHECKIN_TEXTO_VERSION } from '../src/lib/consentimientoTextos.ts'

const IDIOMAS = ['es', 'en', 'fr', 'pt-BR']
const migraciones = ['supabase/migrations/20261111210000_adn_consentimiento_evidencia.sql']
const sql = migraciones.map(m => readFileSync(m, 'utf8')).join('\n')
const comillas = (s: string) => `'${s.replace(/'/g, "''")}'`

let errores = 0
for (const idioma of IDIOMAS) {
  const texto = JSON.parse(readFileSync(`src/i18n/locales/${idioma}.json`, 'utf8')).checkin?.consentimiento
  if (typeof texto !== 'string' || !texto) { console.error(`FALLO: ${idioma} no tiene checkin.consentimiento`); errores++; continue }
  const fila = `('checkin', '${CHECKIN_TEXTO_VERSION}', '${idioma}', ${comillas(texto)},`
  if (!sql.includes(fila)) {
    console.error(`FALLO: el texto de ${idioma} no coincide con la version ${CHECKIN_TEXTO_VERSION} registrada. Crea una version nueva en una migracion y actualiza CHECKIN_TEXTO_VERSION.`)
    errores++
  } else console.log(`OK: ${idioma} coincide con la version ${CHECKIN_TEXTO_VERSION}`)
}
if (errores) process.exit(1)
