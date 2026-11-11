import { Href, useRouter } from 'expo-router';
import { useState } from 'react';
import { Pressable, StyleSheet, Text } from 'react-native';
import BotonPrimario from '../components/BotonPrimario';
import CampoTexto from '../components/CampoTexto';
import PantallaAuth from '../components/PantallaAuth';
import { useAuth } from '../context/AuthContext';
import { colors, fontSize, spacing } from '../theme';
import { esCorreoInstitucional } from '../utils/validaciones';

export default function Recuperar() {
  const router = useRouter();
  const { solicitarRecuperacion } = useAuth();
  const [correo, setCorreo] = useState('');
  const [error, setError] = useState('');
  const [enviando, setEnviando] = useState(false);

  const onEnviar = async () => {
    if (!esCorreoInstitucional(correo)) {
      setError('Ingresa un correo institucional válido');
      return;
    }
    setError('');
    setEnviando(true);
    const resultado = await solicitarRecuperacion(correo);
    setEnviando(false);

    if (!resultado.ok) {
      setError(resultado.mensaje);
      return;
    }
    router.push({
      pathname: '/restablecer',
      params: { correo: correo.trim().toLowerCase() },
    } as Href);
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

      <BotonPrimario
        titulo={enviando ? 'Enviando...' : 'Enviar código'}
        deshabilitado={enviando}
        onPress={onEnviar}
      />

      <Pressable onPress={() => router.back()}>
        <Text style={styles.enlace}>Volver a iniciar sesión</Text>
      </Pressable>
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