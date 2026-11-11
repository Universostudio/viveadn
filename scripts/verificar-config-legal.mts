// Comprueba que la configuración legal está completa antes de publicar. Lee las variables del entorno y, si existe,
// del archivo .env o .env.production (nunca imprime los valores, solo cuáles faltan). Uso: npm run check:config-legal
import { existsSync, readFileSync } from 'node:fs'

const OBLIGATORIAS = ['VITE_LEGAL_NIF', 'VITE_LEGAL_DOMICILIO', 'VITE_EMAIL_LEGAL', 'VITE_EMAIL_SOPORTE']
const EMAIL = /^[^\s@]+@[^\s@]+\.[^\s@]+$/
const valores: Record<string, string> = {}
for (const f of ['.env', '.env.production']) {
  if (!existsSync(f)) continue
  for (const l of readFileSync(f, 'utf8').split('\n')) {
    const m = /^\s*([A-Z0-9_]+)\s*=\s*(.*?)\s*$/.exec(l)
    if (m && !l.trim().startsWith('#')) valores[m[1]!] = m[2]!.replace(/^["']|["']$/g, '')
  }
}
for (const k of [...OBLIGATORIAS, 'VITE_LEGAL_TITULAR']) if (process.env[k]) valores[k] = process.env[k]!

const faltan = OBLIGATORIAS.filter(k => !valores[k]?.trim())
const malos = ['VITE_EMAIL_LEGAL', 'VITE_EMAIL_SOPORTE'].filter(k => valores[k]?.trim() && !EMAIL.test(valores[k]!.trim()))
if (faltan.length || malos.length) {
  if (faltan.length) console.error(`FALTA configurar: ${faltan.join(', ')}`)
  if (malos.length) console.error(`No parece un correo: ${malos.join(', ')}`)
  console.error('Los textos legales no se pueden publicar así: mostrarían un aviso en lugar del dato.')
  process.exit(1)
}
console.log('OK: la configuración legal está completa')
