export function formatearPrecio(valor: number): string {
  return '$' + valor.toString().replace(/\B(?=(\d{3})+(?!\d))/g, ',');
}

export function formatearHora(iso: string): string {
  const fecha = new Date(iso);
  const dos = (n: number) => n.toString().padStart(2, '0');
  return `${dos(fecha.getHours())}:${dos(fecha.getMinutes())}`;
}