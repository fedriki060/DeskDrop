import ListaHistorial from '../../components/ListaHistorial';
import ProtegidoPorRol from '../../components/ProtegidoPorRol';

export default function Historial() {
  return (
    <ProtegidoPorRol rol="solicitante">
      <ListaHistorial />
    </ProtegidoPorRol>
  );
}
