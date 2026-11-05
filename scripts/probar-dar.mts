// Pruebas de la calculadora y las validaciones de la página de dar. Uso: npm run test:dar
import assert from 'node:assert/strict'
const { calcularAporte, colorValido, colorTextoSobre, claveFondo, urlDarValida, leerImporte, formatoMoneda, simboloMoneda, mezclarColores, CONFIG_POR_DEFECTO, PLANTILLAS, MODOS_CALCULADORA, MAX_FONDOS } = await import('../src/lib/dar.ts')

// Ingreso de un día: ingreso del periodo entre los días del periodo
assert.equal(calcularAporte(36500, 'anual', 'dia'), 100)
assert.equal(calcularAporte(3000, 'mensual', 'dia'), 100)
assert.equal(calcularAporte(700, 'semanal', 'dia'), 100)
assert.equal(calcularAporte(1000, 'anual', 'dia'), 2.74, 'redondea a céntimos: 1000/365 = 2,7397')
// Diezmo: el 10 % del ingreso del periodo, sea cual sea el periodo
assert.equal(calcularAporte(36500, 'anual', 'diezmo'), 3650)
assert.equal(calcularAporte(1800, 'mensual', 'diezmo'), 180)
assert.equal(calcularAporte(450, 'semanal', 'diezmo'), 45)
// Personalizado: la cantidad escrita, en cualquier modo
assert.equal(calcularAporte(25, 'personalizado', 'dia'), 25)
assert.equal(calcularAporte(25.5, 'personalizado', 'diezmo'), 25.5)
// Entradas raras: nunca devuelve algo negativo, infinito ni NaN
for (const v of [0, -5, NaN, Infinity, -Infinity]) assert.equal(calcularAporte(v, 'mensual', 'diezmo'), 0, String(v))
assert.equal(calcularAporte(1e15, 'personalizado', 'dia'), 1e9, 'tope de un importe absurdo')
assert.equal(calcularAporte(0.1 + 0.2, 'personalizado', 'dia'), 0.3, 'sin errores de coma flotante')

// Lectura de importes escritos a mano
assert.equal(leerImporte('25'), 25); assert.equal(leerImporte('25,50'), 25.5); assert.equal(leerImporte(' 1 250.5 '), 1250.5)
for (const m of ['', 'abc', '-5', '1e5', '12,345', '1.234,56', '12..3', '0x10', '999999999999']) assert.equal(leerImporte(m), null, m)

// Colores
for (const c of ['#00523c', '#F5A623', '#0F2C4A']) assert.ok(colorValido(c), c)
for (const c of ['', '00523c', '#12345', '#1234567', 'red', '#gggggg', 'red;background:url(x)', '#00523c;']) assert.ok(!colorValido(c), c)
assert.equal(colorTextoSobre('#00523c'), '#ffffff', 'texto blanco sobre verde oscuro')
assert.equal(colorTextoSobre('#0F2C4A'), '#ffffff', 'texto blanco sobre azul marino')
assert.equal(colorTextoSobre('#f5a623'), '#111827', 'texto oscuro sobre dorado')
assert.equal(colorTextoSobre('#ffffff'), '#111827'); assert.equal(colorTextoSobre('#000000'), '#ffffff')
assert.equal(colorTextoSobre('no es un color'), '#ffffff')

// Claves de fondos: válidas para la base (^[a-z0-9_]{1,40}$) y únicas
const valida = (c: string) => /^[a-z0-9_]{1,40}$/.test(c)
assert.equal(claveFondo('Misiones y Expansión', []), 'misiones_y_expansion')
assert.equal(claveFondo('  Casas de Oración  ', []), 'casas_de_oracion')
assert.equal(claveFondo('VMAD (Más Allá del Domingo)', []), 'vmad_mas_alla_del_domingo')
assert.equal(claveFondo('Misiones', ['misiones']), 'misiones_2')
assert.equal(claveFondo('Misiones', ['misiones', 'misiones_2', 'misiones_3']), 'misiones_4')
for (const n of ['', '   ', '¡¡¡', '日本語', 'a'.repeat(200), 'ñandú', 'Con-Guion', "Robert'); DROP TABLE"]) assert.ok(valida(claveFondo(n, [])), `válida para «${n.slice(0, 20)}»`)
assert.equal(claveFondo('', []), 'fondo'); assert.equal(claveFondo('日本語', []), 'fondo')
assert.ok(valida(claveFondo('a'.repeat(200), ['a'.repeat(36)])), 'también al desambiguar')

// Direcciones
assert.ok(urlDarValida('https://dar.iglesia.org/diezmo')); assert.ok(urlDarValida('https://buy.stripe.com/abc123'))
for (const u of ['', 'http://x.org', 'javascript:alert(1)', 'https://x.org/a b', 'ftp://x.org', 'data:text/html,hola', 'https://' + 'a'.repeat(500)]) assert.ok(!urlDarValida(u), u.slice(0, 30))

// Moneda y valores por defecto
assert.match(formatoMoneda(1234.5, 'EUR', 'es-ES'), /1\.?234,50/)
assert.match(formatoMoneda(1234.5, 'USD', 'en-US'), /\$1,234\.50/)
assert.equal(formatoMoneda(5, 'XXXX', 'es'), '5.00 XXXX', 'una moneda inválida no rompe la página')
assert.equal(simboloMoneda('EUR', 'es-ES'), '€'); assert.equal(simboloMoneda('USD', 'en-US'), '$'); assert.equal(simboloMoneda('XXXX', 'es'), 'XXXX')
assert.equal(mezclarColores('#000000', '#ffffff'), '#808080'); assert.equal(mezclarColores('#ff0000', '#ff0000'), '#ff0000'); assert.equal(mezclarColores('#00523c', '#f5a623'), '#7b7c30')
assert.equal(mezclarColores('malo', '#123456'), '#123456'); assert.equal(mezclarColores('malo', 'peor'), '#808080')
assert.deepEqual([...PLANTILLAS], ['clasica', 'dia']); assert.deepEqual([...MODOS_CALCULADORA], ['dia', 'diezmo', 'ninguna']); assert.equal(MAX_FONDOS, 20)
assert.ok(colorValido(CONFIG_POR_DEFECTO.color_primario) && colorValido(CONFIG_POR_DEFECTO.color_acento))
console.log('OK: todas las pruebas de la página de dar pasan')
