import { useRouter } from 'expo-router';
import { useState } from 'react';
import AvisoEmergente from '../components/AvisoEmergente';
import BotonPrimario from '../components/BotonPrimario';
import CampoTexto from '../components/CampoTexto';
import PantallaAuth from '../components/PantallaAuth';
import { LONGITUD_MINIMA_CONTRASENA } from '../utils/validaciones';

export default function Restablecer() {
  const router = useRouter();
  const [nueva, setNueva] = useState('');
  const [confirmar, setConfirmar] = useState('');
  const [error, setError] = useState('');
  const [listo, setListo] = useState(false);

  const onRestablecer = () => {
    if (nueva.length < LONGITUD_MINIMA_CONTRASENA) {
      setError(`La contraseña debe tener al menos ${LONGITUD_MINIMA_CONTRASENA} caracteres`);
      return;
    }
    if (nueva !== confirmar) {
      setError('Las contraseñas no coinciden');
      return;
    }
    setError('');
    setListo(true);
  };

  const onCerrarAviso = () => {
    setListo(false);
    router.replace('/login');
  };

  return (
    <PantallaAuth titulo="Reinicia tu contraseña" subtitulo="Ingresa tu nueva contraseña">
      <CampoTexto
        placeholder="Nueva contraseña"
        secureTextEntry
        value={nueva}
        onChangeText={setNueva}
      />
      <CampoTexto
        placeholder="Confirmar contraseña"
        secureTextEntry
        value={confirmar}
        onChangeText={setConfirmar}
        error={error}
      />

      <BotonPrimario titulo="Restablecer contraseña" onPress={onRestablecer} />

      <AvisoEmergente
        visible={listo}
        mensaje="Contraseña restablecida con éxito."
        onCerrar={onCerrarAviso}
      />
    </PantallaAuth>
  );
}