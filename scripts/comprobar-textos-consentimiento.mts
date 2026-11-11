// Comprueba que los textos de consentimiento del registro por QR que muestra la web (src/i18n/locales, claves
// checkin.consentimiento y checkin.canalEmail, canalWhatsapp y canalSms) son exactamente los que las migraciones
// registraron para CHECKIN_TEXTO_VERSION, en los cuatro idiomas. Si alguien cambia un texto en la web sin crear una
// versión nueva, falla: la evidencia dejaría de decir la verdad. Uso: npm run check:textos
import { readFileSync, readdirSync } from 'node:fs'
import { CHECKIN_TEXTO_VERSION } from '../src/lib/consentimientoTextos.ts'

const IDIOMAS = ['es', 'en', 'fr', 'pt-BR']
// Cada finalidad registrada en la base y la clave de la web que la muestra
const TEXTOS: Record<string, string> = {
  checkin: 'consentimiento',
  checkin_email: 'canalEmail',
  checkin_whatsapp: 'canalWhatsapp',
  checkin_sms: 'canalSms',
}
const sql = readdirSync('supabase/migrations').filter(f => /adn_consentimiento_evidencia|adn_checkin_canales/.test(f))
  .map(f => readFileSync(`supabase/migrations/${f}`, 'utf8')).join('\n')
const comillas = (s: string) => `'${s.replace(/'/g, "''")}'`

let errores = 0
for (const idioma of IDIOMAS) {
  const checkin = JSON.parse(readFileSync(`src/i18n/locales/${idioma}.json`, 'utf8')).checkin ?? {}
  for (const [finalidad, clave] of Object.entries(TEXTOS)) {
    const texto = checkin[clave]
    if (typeof texto !== 'string' || !texto) { console.error(`FALLO: ${idioma} no tiene checkin.${clave}`); errores++; continue }
    if (!sql.includes(`('${finalidad}', '${CHECKIN_TEXTO_VERSION}', '${idioma}', ${comillas(texto)},`)) {
      console.error(`FALLO: checkin.${clave} de ${idioma} no coincide con la version ${CHECKIN_TEXTO_VERSION} de ${finalidad}. Crea una version nueva en una migracion y actualiza CHECKIN_TEXTO_VERSION.`)
      errores++
    }
  }
}
if (errores) process.exit(1)
console.log(`OK: los ${Object.keys(TEXTOS).length} textos del registro por QR coinciden con la version ${CHECKIN_TEXTO_VERSION} en ${IDIOMAS.length} idiomas`)
