import PlaceholderScreen from '../../components/PlaceholderScreen';
import ProtegidoPorRol from '../../components/ProtegidoPorRol';

export default function Entregas() {
  return (
    <ProtegidoPorRol rol="domiciliario">
      <PlaceholderScreen title="Entregas" />
    </ProtegidoPorRol>
  );
}