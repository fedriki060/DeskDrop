import ListaHistorial from '../../components/ListaHistorial';
import ListaMisEntregas from '../../components/ListaMisEntregas';
import { useAuth } from '../../context/AuthContext';

// Solicitante: su historial de pedidos. Domiciliario: sus entregas cerradas y lo ganado.
export default function Historial() {
  const { rolActivo } = useAuth();
  return rolActivo === 'domiciliario' ? <ListaMisEntregas /> : <ListaHistorial />;
}
