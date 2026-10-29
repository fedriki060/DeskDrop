import { useEffect, useState } from 'react';
import { Text } from 'react-native';
import { supabase } from '../lib/supabase';

// Comprueba la cadena completa: app -> API de Supabase -> función health() en Postgres.
export function HealthCheck() {
  const [estado, setEstado] = useState('Comprobando conexión…');

  useEffect(() => {
    supabase.rpc('health').then(({ data, error }) => {
      setEstado(error ? `Error: ${error.message}` : `Supabase: ${data}`);
    });
  }, []);

  return <Text>{estado}</Text>;
}
