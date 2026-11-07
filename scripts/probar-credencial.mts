// Pruebas del texto del QR de la credencial y de su lectura con el mismo decodificador que usa el escaner. Uso: npm run test:credencial
import assert from 'node:assert/strict'
import QRCode from 'qrcode'
import jsQR from 'jsqr'
const { PREFIJO_CREDENCIAL, textoQr, tokenDeQr } = await import('../src/lib/credencial.ts')

const token = '0123456789abcdef0123456789abcdef'
assert.equal(textoQr(token), 'ADN1:' + token)
assert.equal(PREFIJO_CREDENCIAL, 'ADN1:')
// Lo que teclea un lector USB o lee la camara
for (const entrada of [textoQr(token), ' ' + textoQr(token) + '\n', textoQr(token).toUpperCase(), token]) assert.equal(tokenDeQr(entrada), token, JSON.stringify(entrada))
// Cualquier otra cosa no es una credencial: una direccion, un token corto o largo, texto con el token dentro
for (const malo of ['', 'ADN1:', 'ADN1:' + token.slice(1), 'ADN1:' + token + '0', 'ADN2:' + token, 'https://viveadn.com/verificar/' + token, 'hola ' + token, 'ADN1:' + 'g'.repeat(32), "ADN1:" + token + "'"]) {
  assert.equal(tokenDeQr(malo), null, JSON.stringify(malo).slice(0, 40))
}
// Que el QR no lleve nada de la persona: solo el prefijo y el token
assert.match(textoQr(token), /^ADN1:[0-9a-f]{32}$/)

// Viaje completo: se dibuja el QR como lo hace la tarjeta y se lee con jsQR, como el escaner
function aPixeles(texto: string, escala = 6, margen = 4) {
  const qr = QRCode.create(texto, { errorCorrectionLevel: 'M' })
  const n = qr.modules.size, lado = (n + margen * 2) * escala
  const datos = new Uint8ClampedArray(lado * lado * 4).fill(255)
  for (let y = 0; y < n; y++) for (let x = 0; x < n; x++) {
    if (!qr.modules.get(y, x)) continue
    for (let dy = 0; dy < escala; dy++) for (let dx = 0; dx < escala; dx++) {
      const i = (((y + margen) * escala + dy) * lado + (x + margen) * escala + dx) * 4
      datos[i] = datos[i + 1] = datos[i + 2] = 0
    }
  }
  return { datos, lado }
}
for (const t of [token, 'f'.repeat(32), '00000000000000000000000000000001']) {
  const { datos, lado } = aPixeles(textoQr(t))
  const leido = jsQR(datos, lado, lado, { inversionAttempts: 'dontInvert' })
  assert.ok(leido, 'jsQR lee el QR de la credencial')
  assert.equal(tokenDeQr(leido.data), t)
}
console.log('OK: todas las pruebas de la credencial pasan')
