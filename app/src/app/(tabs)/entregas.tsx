import ListaEntregas from '../../components/ListaEntregas';
import ProtegidoPorRol from '../../components/ProtegidoPorRol';

export default function Entregas() {
  return (
    <ProtegidoPorRol rol="domiciliario">
      <ListaEntregas />
    </ProtegidoPorRol>
  );
}
