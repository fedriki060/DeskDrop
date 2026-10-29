export function formatearPrecio(valor: number): string {
  return '$' + valor.toString().replace(/\B(?=(\d{3})+(?!\d))/g, ',');
}