import { useRouter } from 'expo-router';
import { useState } from 'react';
import { Pressable, StyleSheet, Text } from 'react-native';
import AvisoEmergente from '../components/AvisoEmergente';
import BotonPrimario from '../components/BotonPrimario';
import CampoTexto from '../components/CampoTexto';
import PantallaAuth from '../components/PantallaAuth';
import { colors, fontSize, spacing } from '../theme';
import { esCorreoInstitucional } from '../utils/validaciones';

export default function Recuperar() {
  const router = useRouter();
  const [correo, setCorreo] = useState('');
  const [error, setError] = useState('');
  const [enviado, setEnviado] = useState(false);

  const onEnviar = () => {
    if (!esCorreoInstitucional(correo)) {
      setError('Ingresa un correo institucional válido');
      return;
    }
    setError('');
    setEnviado(true);
  };

  // SIMULADO: en la app real se llega a "restablecer" desde el enlace del correo
  const onCerrarAviso = () => {
    setEnviado(false);
    router.replace('/restablecer');
  };

  return (
    <PantallaAuth titulo="Reinicia tu contraseña" subtitulo="Ingresa tu correo">
      <CampoTexto
        placeholder="Correo institucional"
        autoCorrect={false}
        keyboardType="email-address"
        value={correo}
        onChangeText={setCorreo}
        error={error}
      />

      <BotonPrimario titulo="Enviar link de recuperación" onPress={onEnviar} />

      <Pressable onPress={() => router.back()}>
        <Text style={styles.enlace}>Volver a iniciar sesión</Text>
      </Pressable>

      <AvisoEmergente
        visible={enviado}
        mensaje="Link de recuperación enviado a tu correo."
        onCerrar={onCerrarAviso}
      />
    </PantallaAuth>
  );
}

const styles = StyleSheet.create({
  enlace: {
    marginTop: spacing.md,
    textAlign: 'center',
    fontSize: fontSize.md,
    color: colors.primary,
  },
});