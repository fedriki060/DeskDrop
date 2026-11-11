import { createContext, ReactNode, useCallback, useContext, useEffect, useState } from 'react';
import { useVueltaAPrimerPlano } from '../hooks/useVueltaAPrimerPlano';
import {
  cambiarRecibiendoPedidos,
  ComercioDelUsuario,
  contarPedidosNuevos,
  escucharPedidosComercio,
  obtenerMiComercio,
} from '../services/pedidosService';
import { useAuth } from './AuthContext';

type ComercioContextType = {
  /** undefined: cargando; null: la cuenta no administra ningún comercio */
  comercio: ComercioDelUsuario | null | undefined;
  /** Pedidos que llegaron y aún no se marcan listos (el número de la pestaña «Pedidos») */
  nuevos: number;
  /** Abre o cierra el comercio; devuelve false si no se pudo */
  cambiarRecibiendo: (recibiendo: boolean) => Promise<boolean>;
};

const ComercioContext = createContext<ComercioContextType | undefined>(undefined);

// Solo trabaja cuando el usuario es de un comercio; para los demás no consulta nada.
export function ComercioProvider({ children }: { children: ReactNode }) {
  const { perfil } = useAuth();
  const vueltas = useVueltaAPrimerPlano();
  const [comercio, setComercio] = useState<ComercioDelUsuario | null | undefined>();
  const [nuevos, setNuevos] = useState(0);

  const userId = perfil?.rol === 'comercio' ? perfil.id : undefined;

  useEffect(() => {
    if (!userId) {
      setComercio(undefined);
      setNuevos(0);
      return;
    }
    let vigente = true;
    obtenerMiComercio(userId).then((c) => {
      if (vigente) setComercio(c);
    });
    return () => {
      vigente = false;
    };
  }, [userId, vueltas]);

  const comercioId = comercio?.id;
  const contar = useCallback(async () => {
    if (comercioId) setNuevos(await contarPedidosNuevos(comercioId));
  }, [comercioId]);

  useEffect(() => {
    contar();
  }, [contar, vueltas]);
  useEffect(
    () => (comercioId ? escucharPedidosComercio(comercioId, contar) : undefined),
    [comercioId, contar, vueltas]
  );

  const cambiarRecibiendo = async (recibiendo: boolean) => {
    if (!comercioId) return false;
    const ok = await cambiarRecibiendoPedidos(comercioId, recibiendo);
    if (ok) setComercio((c) => (c ? { ...c, activo: recibiendo } : c));
    return ok;
  };

  return (
    <ComercioContext.Provider value={{ comercio, nuevos, cambiarRecibiendo }}>
      {children}
    </ComercioContext.Provider>
  );
}

export function useComercio() {
  const contexto = useContext(ComercioContext);
  if (!contexto) throw new Error('useComercio debe usarse dentro de ComercioProvider');
  return contexto;
}
