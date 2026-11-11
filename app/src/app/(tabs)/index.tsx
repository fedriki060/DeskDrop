import PlaceholderScreen from '../../components/PlaceholderScreen';
import ProtegidoPorRol from '../../components/ProtegidoPorRol';

export default function Inicio() {
  return (
    <ProtegidoPorRol rol="solicitante">
      <PlaceholderScreen title="Inicio" />
    </ProtegidoPorRol>
  );
}