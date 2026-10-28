import { useLocalSearchParams } from 'expo-router';
import CatalogoComercio from '../../components/CatalogoComercio';

export default function Restaurante() {
  const { id } = useLocalSearchParams<{ id: string }>();
  return <CatalogoComercio comercioId={id} />;
}