import { useRouter } from 'expo-router';
import { useState } from 'react';
import { Pressable, StyleSheet, Text } from 'react-native';
import BotonPrimario from '../components/BotonPrimario';
import CampoTexto from '../components/CampoTexto';
import PantallaAuth from '../components/PantallaAuth';
import { useAuth } from '../context/AuthContext';
import { colors, fontSize, spacing } from '../theme';

export default function Login() {
  const router = useRouter();
  const { iniciarSesion } = useAuth();
  const [usuario, setUsuario] = useState('');
  const [contrasena, setContrasena] = useState('');
  const [error, setError] = useState('');
  const [cargando, setCargando] = useState(false);

  const onIniciar = async () => {
    setError('');
    setCargando(true);
    const ok = await iniciarSesion(usuario.trim(), contrasena);
    setCargando(false);
    if (!ok) {
      setError('Usuario o contraseña incorrectos');
    }
  };

  return (
    <PantallaAuth titulo="Inicia Sesión" subtitulo="Ingresa con el correo institucional">
      <CampoTexto
        placeholder="Correo institucional"
        autoCorrect={false}
        value={usuario}
        onChangeText={setUsuario}
      />
      <CampoTexto
        placeholder="Contraseña"
        secureTextEntry
        value={contrasena}
        onChangeText={setContrasena}
        error={error}
      />

      <BotonPrimario
        titulo={cargando ? 'Ingresando...' : 'Iniciar Sesión'}
        deshabilitado={cargando}
        onPress={onIniciar}
      />
      <BotonPrimario titulo="Crear Cuenta" onPress={() => router.push('/registro')} />

      <Text style={styles.terminos}>
        Al hacer clic en iniciar sesión, aceptas nuestros Términos de servicio y
        Política de privacidad
      </Text>

      <Pressable onPress={() => router.push('/recuperar')}>
        <Text style={styles.enlace}>¿Se te olvidó tu contraseña? Reinicia aquí</Text>
      </Pressable>

      <Text style={styles.prueba}>Modo prueba: usuario 1 / contraseña 1</Text>
    </PantallaAuth>
  );
}

const styles = StyleSheet.create({
  terminos: {
    marginTop: spacing.sm,
    textAlign: 'center',
    fontSize: fontSize.sm,
    color: colors.textMuted,
  },
  enlace: {
    marginTop: spacing.lg,
    textAlign: 'center',
    fontSize: fontSize.md,
    color: colors.primary,
  },
  prueba: {
    marginTop: spacing.xl,
    textAlign: 'center',
    fontSize: fontSize.sm,
    color: colors.textMuted,
  },
});