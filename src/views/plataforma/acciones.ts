// Texto legible de una acción de la auditoría de plataforma. Solo la clave de la acción: el detalle de la auditoría nunca se muestra.
export type Tr = (clave: string, valores?: Record<string, unknown>) => string
export type Existe = (clave: string) => boolean

export function textoDeAccion(accion: string, t: Tr, existe: Existe): string {
  const clave = `plataformaPanel.accionAuditoria.${accion}`
  return existe(clave) ? t(clave) : t('plataformaPanel.accionAuditoria.otra')
}
