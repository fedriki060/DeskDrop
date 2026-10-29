import BandejaPedidos from '../../components/BandejaPedidos';
import ProtegidoPorRol from '../../components/ProtegidoPorRol';

// SIMULADO: el comercio vendrá del usuario autenticado (T-029)
const COMERCIO_PRUEBA_ID = 'c1';

export default function Bandeja() {
  return (
    <ProtegidoPorRol rol="comercio">
      <BandejaPedidos comercioId={COMERCIO_PRUEBA_ID} />
    </ProtegidoPorRol>
  );
}