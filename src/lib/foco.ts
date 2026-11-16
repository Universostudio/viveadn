// Ayudas de teclado para diálogos y cajones: qué es enfocable dentro de un contenedor y cómo mantener la tecla Tab dentro de él.
const SELECTOR = 'a[href], button, input, select, textarea, summary, [tabindex]'

/** Los elementos del contenedor a los que se llega con Tab, en orden: visibles, sin deshabilitar y sin tabindex negativo */
export function enfocables(raiz: HTMLElement): HTMLElement[] {
  return [...raiz.querySelectorAll<HTMLElement>(SELECTOR)].filter(el => {
    if ((el as HTMLButtonElement).disabled || el.getAttribute('tabindex') === '-1' || (el as HTMLInputElement).type === 'hidden') return false
    if (el.closest('[inert]')) return false
    return el.getClientRects().length > 0
  })
}

/** Con el diálogo abierto, Tab y Mayús+Tab dan la vuelta dentro de él en lugar de salir a la página de detrás */
export function atraparTab(ev: KeyboardEvent, raiz: HTMLElement | null | undefined): void {
  if (ev.key !== 'Tab' || !raiz) return
  const lista = enfocables(raiz)
  if (!lista.length) { ev.preventDefault(); raiz.focus(); return }
  const primero = lista[0]!, ultimo = lista[lista.length - 1]!, activo = document.activeElement
  if (ev.shiftKey && (activo === primero || !raiz.contains(activo))) { ev.preventDefault(); ultimo.focus() }
  else if (!ev.shiftKey && (activo === ultimo || !raiz.contains(activo))) { ev.preventDefault(); primero.focus() }
}
