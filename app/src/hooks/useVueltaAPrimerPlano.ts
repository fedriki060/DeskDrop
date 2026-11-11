import { useEffect, useRef, useState } from 'react';
import { AppState } from 'react-native';

/**
 * Cuenta cuántas veces la app volvió a primer plano. Úsalo como dependencia de los efectos
 * que leen datos y se suscriben a Realtime: al volver (o al recuperar la conexión del celular)
 * el efecto se repite, lee de nuevo el estado actual y vuelve a suscribirse (T-100).
 */
export function useVueltaAPrimerPlano(): number {
  const [vueltas, setVueltas] = useState(0);
  const anterior = useRef(AppState.currentState);

  useEffect(() => {
    const suscripcion = AppState.addEventListener('change', (estado) => {
      if (anterior.current !== 'active' && estado === 'active') setVueltas((n) => n + 1);
      anterior.current = estado;
    });
    return () => suscripcion.remove();
  }, []);

  return vueltas;
}
