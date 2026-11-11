import { Href, useRouter } from 'expo-router';
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
  const [sinVerificar, setSinVerificar] = useState(false);
  const [cargando, setCargando] = useState(false);

  const abrirLegal = (seccion: 'terminos' | 'privacidad') =>
  router.push({ pathname: '/terminos', params: { seccion } } as Href);

  const onIniciar = async () => {
    setError('');
    setSinVerificar(false);
    setCargando(true);
        const resultado = await iniciarSesion(usuario, contrasena);
    setCargando(false);
    if (!resultado.ok) {
      setError(resultado.mensaje);
      setSinVerificar(resultado.sinVerificar === true);
    }
  };

  return (
    <PantallaAuth titulo="Inicia Sesión" subtitulo="Ingresa con el correo institucional">
      <CampoTexto
        placeholder="Correo institucional"
        autoCorrect={false}
        autoCapitalize="none"
        keyboardType="email-address"
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

            {sinVerificar && (
        <Pressable
          onPress={() =>
            router.push({
              pathname: '/verificar',
              params: { correo: usuario.trim().toLowerCase(), desde: 'login' },
            } as Href)
          }
        >
          <Text style={styles.verificar}>Ingresar código de verificación</Text>
        </Pressable>
      )}

      <BotonPrimario
        titulo={cargando ? 'Ingresando...' : 'Iniciar Sesión'}
        deshabilitado={cargando}
        onPress={onIniciar}
      />
      <BotonPrimario titulo="Crear Cuenta" onPress={() => router.push('/registro')} />

      <Text style={styles.terminos}>
                Al hacer clic en iniciar sesión, aceptas nuestros{' '}
        <Text style={styles.link} onPress={() => abrirLegal('terminos')}>
          Términos de servicio
        </Text>{' '}
        y{' '}
        <Text style={styles.link} onPress={() => abrirLegal('privacidad')}>
          Política de privacidad
        </Text>
      </Text>

      <Pressable onPress={() => router.push('/recuperar')}>
        <Text style={styles.enlace}>¿Se te olvidó tu contraseña? Reinicia aquí</Text>
      </Pressable>
    </PantallaAuth>
  );
}

const styles = StyleSheet.create({
    link: {
    color: colors.primary,
    textDecorationLine: 'underline',
  },
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
    verificar: {
    marginBottom: spacing.md,
    textAlign: 'center',
    fontSize: fontSize.md,
    color: colors.primary,
  },
});