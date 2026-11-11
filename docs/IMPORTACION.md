# Importación de miembros desde Google Contactos

Complementa la importación por plantilla CSV. Se detecta sola: si la primera fila del archivo es la de una exportación de Google Contactos (formato nuevo con `First Name` y `Labels`, formato antiguo con `Given Name` y `Group Membership`) o de Outlook, el asistente abre su propia revisión. Etiquetas: **[V]** verificado ejecutándolo en esta sesión, **[NV]** no verificable aquí. Los archivos reales de Gerencia no están en el repositorio y no se han leído: todo lo verificado usa datos sintéticos.

## Qué columnas se leen y dónde se guardan

| Dato de Google | Dónde queda |
| --- | --- |
| Nombre, segundo nombre y apellido (`First/Middle/Last Name`, `Given/Additional/Family Name`, o `Name` y `Nickname` si no hay otros) | `miembros.nombre` (nombre y segundo nombre) y `miembros.apellido`. El apellido puede quedar vacío |
| `E-mail 1 - Value` y siguientes (varios valores en una celda van separados por ` ::: `) | El primero en `miembros.email`; los demás en `adn_miembro_contactos` (tipo `correo`) |
| `Phone 1 - Value`, `Phone 2`, `Phone 3` y siguientes | El primero en `miembros.telefono`, canonizado (solo dígitos y un `+` inicial); los demás en `adn_miembro_contactos` (tipo `telefono`, con su etiqueta) |
| `Birthday` | `miembros.fecha_nacimiento`, solo si trae año |
| `Address 1 - Formatted` o calle, ciudad, región, código postal y país | `adn_miembro_contactos` (tipo `direccion`, hasta 3) |
| `Labels`, `Group Membership`, `Categories` | `adn_miembro_contactos` (tipo `etiqueta`, hasta 20; los grupos del sistema como `* myContacts` se omiten) |
| `Notes` | `miembros.notas` (recortadas a 1000 caracteres), salvo que parezcan guardar una contraseña |
| Foto, organización, sitios web, campos personalizados y el resto | No se importan; el asistente lista las columnas ignoradas |

`adn_miembro_contactos` es una tabla nueva (una fila por dato, con seguridad por filas y clave foránea compuesta a `miembros`). La ficha del miembro muestra esos datos, y cada importado lleva una etiqueta `Importado AAAA-MM-DD (google)` para poder encontrar y deshacer lo que entró de una vez.

## Reglas

1. **Nunca se importan contraseñas.** Una columna cuyo nombre sugiere una clave (`Password`, `Contraseña`, `Clave`, `PIN`, `Token`, `Secret`…) no se lee: se excluye antes de recorrer ninguna celda y el asistente avisa de que conviene borrarla del archivo. Una nota que contiene `contraseña:`, `password =`, `PIN:` y similares se descarta. Los campos personalizados no se importan. La base de datos repite el filtro de notas y solo acepta una lista cerrada de campos, así que un cliente alterado no lo salta [V].
2. **Se deduplica por correo.** Dos filas que comparten cualquier correo son la misma persona y se fusionan (se suman correos, teléfonos, direcciones y etiquetas, y se conserva el primer dato de cada campo). Sin correo, se fusiona por teléfono; sin correo ni teléfono, por nombre. La comparación contra lo que la iglesia ya tiene sigue el mismo orden, en el navegador para la vista previa y en la base para el resultado definitivo.
3. **Se descartan las filas sin nombre y sin contacto** (sin correo ni teléfono válidos). Las que no tienen nombre pero sí correo o teléfono quedan aparte y **no se importan salvo que quien importa lo marque**; si lo marca, el correo o el teléfono hacen de nombre, sin inventar nada.
4. **Un dato inválido no invalida a la persona.** Un teléfono (menos de 7 o más de 15 dígitos, con letras, repetido como `0000000`) o un correo mal formado se descarta y se cuenta; la persona se importa igual.
5. Un cumpleaños sin año (`--03-15`) no se importa, porque una fecha de nacimiento necesita el año.
6. No está disponible en una iglesia en modo alias: guardaría nombres y correos reales.

## Qué hace la base de datos

`adn_importar_miembros` importa un lote de hasta 1000 contactos de forma atómica, con los permisos de quien llama: exige `miembros.importar` además de las políticas de `miembros`, respeta el límite del plan y los disparadores, y si algo falla (por ejemplo el límite del plan) no entra nada de ese lote. La web envía lotes de 500. Devuelve conteos de importados y omitidos por correo, por teléfono y por nombre [V, 40 comprobaciones en `supabase/tests/adn_importar_contactos.sql`, incluido el aislamiento entre iglesias: el mismo correo en otra iglesia no es un duplicado].

## Verificación a escala

`npm run test:google` genera un archivo sintético con las cifras de Gerencia: 6.100 filas, 1.934 sin nombre, 2.216 correos únicos y 960 teléfonos inválidos. El modelo que lo genera conoce la respuesta, de modo que la comprobación no depende del código que prueba [V]:

- 6.100 filas se leen en unos 90 ms y dan 2.916 personas, con 2.484 filas fusionadas y 700 descartadas por estar vacías.
- Salen exactamente 2.216 correos, ninguno en dos personas, todos en minúsculas, aunque el archivo los traiga con otra caja o repartidos entre columnas.
- Se cuentan los 960 teléfonos inválidos y se importa a cada persona igualmente.
- Ninguna clave, ni de la columna `Password` ni de las notas, llega al resultado.

## Cómo comprobar el archivo real sin exponerlo

Con el archivo guardado **fuera** del repositorio: `node scripts/resumen-contactos-google.mts /ruta/contactos.csv`. Imprime solo cifras (nunca nombres, correos ni teléfonos) y se niega a leer un archivo que esté dentro del repositorio. `.gitignore` también excluye `contacts*.csv`, `contactos*.csv`, `*.vcf` y `datos-privados/`.

## Decisiones que quedan abiertas y límites

- **Contactos sin nombre.** No se importan por defecto. Si el archivo real se parece a los 1.934 sin nombre que describe Gerencia, es muy probable que sean contactos automáticos y que importarlos llene la lista de miembros de direcciones sueltas. Deshacerlo es lento (no hay borrado masivo), mientras que marcar la casilla después es inmediato, y los repetidos se omiten. Gerencia debe confirmar la regla cuando vea las cifras reales.
- **Teléfonos con y sin prefijo de país** (`+34 600…` y `600…`) no se consideran el mismo número: la importación no sabe a qué país pertenece la iglesia. Si la iglesia es de un solo país se puede fijar un prefijo por defecto.
- La deduplicación por nombre contra lo que ya existe distingue acentos en la base (`José` y `Jose` son nombres distintos allí), mientras que la vista previa en el navegador no los distingue. Solo afecta a personas sin correo ni teléfono.
- Hasta 25.000 filas y 20 MB por archivo. Un archivo mayor debe dividirse.
- [NV] El asistente y el componente de revisión se compilan y se comprueban de tipos, pero no se ejecutaron en un navegador contra una base real. Las funciones de la lectura y la función de base de datos sí se probaron.
- [NV] El formato exacto de las exportaciones reales de Gerencia no se ha visto. Se cubren los formatos conocidos de Google (nuevo y antiguo) y Outlook; un formato distinto se rechazará con un aviso, no se importará mal.
