import EntregasRepartidor from '../../components/EntregasRepartidor';
import ProtegidoPorRol from '../../components/ProtegidoPorRol';

export default function Entregas() {
  return (
    <ProtegidoPorRol rol="domiciliario">
      <EntregasRepartidor />
    </ProtegidoPorRol>
  );
}
