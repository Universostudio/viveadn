// Versión del texto de consentimiento del registro por QR (clave checkin.consentimiento de src/i18n/locales).
// Cada versión vive, con su huella, en la tabla adn_consentimiento_textos y no se edita: si el texto cambia en la web,
// se crea una versión nueva en una migración y se actualiza esta constante.
// scripts/comprobar-textos-consentimiento.mts falla si el texto de la web no coincide con la versión registrada.
export const CHECKIN_TEXTO_VERSION = 'v1'
