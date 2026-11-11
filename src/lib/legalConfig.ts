// Datos del titular que aparecen en los textos legales. Se leen de la configuración de la web y NUNCA se inventan:
// si falta uno, el texto muestra un aviso visible en su lugar, y `npm run check:config-legal` falla antes de publicar.
import type { ClaveConfig } from '@/legal/tipos'

export type ConfigLegal = Record<ClaveConfig, string>

const env = import.meta.env as Record<string, string | undefined>
const limpio = (v: string | undefined) => (v ?? '').trim()

export const CONFIG_LEGAL: ConfigLegal = {
  // El titular lo ha indicado Gerencia; el resto lo confirma Gerencia
  titular: limpio(env.VITE_LEGAL_TITULAR) || 'Visualiza Studio',
  nif: limpio(env.VITE_LEGAL_NIF),
  domicilio: limpio(env.VITE_LEGAL_DOMICILIO),
  emailLegal: limpio(env.VITE_EMAIL_LEGAL),
  emailSoporte: limpio(env.VITE_EMAIL_SOPORTE),
  registro: limpio(env.VITE_LEGAL_REGISTRO),
  // Región de la infraestructura donde se alojan los datos (la indica Gerencia); debe ser una región de la UE, lo comprueba check:config-legal
  regionDatos: limpio(env.VITE_REGION_DATOS),
}

/** Datos sin los cuales los textos no se pueden publicar. El registro público es opcional: solo si el titular está inscrito. */
export const OBLIGATORIOS: ClaveConfig[] = ['titular', 'nif', 'domicilio', 'emailLegal', 'emailSoporte', 'regionDatos']

export const pendientes = (c: ConfigLegal = CONFIG_LEGAL): ClaveConfig[] => OBLIGATORIOS.filter(k => !c[k])

export const MARCA_PENDIENTE = (k: ClaveConfig) => `[${k} pendiente de configurar]`

/** Sustituye los marcadores {clave} por su valor; un dato que falta se deja visible como aviso */
export function sustituir(texto: string, c: ConfigLegal = CONFIG_LEGAL): string {
  return texto.replace(/\{(\w+)\}/g, (_m, k: string) => (k in c ? c[k as ClaveConfig] || MARCA_PENDIENTE(k as ClaveConfig) : `{${k}}`))
}
