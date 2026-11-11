import { useLocalSearchParams, useRouter } from 'expo-router';
import { useEffect, useState } from 'react';
import { Pressable, StyleSheet, Text } from 'react-native';
import BotonPrimario from '../components/BotonPrimario';
import CampoTexto from '../components/CampoTexto';
import PantallaAuth from '../components/PantallaAuth';
import { useAuth } from '../context/AuthContext';
import { colors, fontSize, spacing } from '../theme';

// Debe coincidir con otp_length de [auth.email] en config.toml y con el panel de staging
const LONGITUD_CODIGO = 6;
// En staging Supabase no deja reenviar antes de 60 s (valor por defecto); así el botón no falla
const ESPERA_REENVIO = 60;

export default function Verificar() {
  const router = useRouter();
  // desde=login: el usuario no trae un código reciente, así que puede reenviar de una vez
  const { correo, desde } = useLocalSearchParams<{ correo: string; desde?: string }>();
  const { verificarCodigo, reenviarCodigo } = useAuth();
  const [codigo, setCodigo] = useState('');
  const [error, setError] = useState('');
  const [aviso, setAviso] = useState('');
  const [verificando, setVerificando] = useState(false);
  const [espera, setEspera] = useState(desde === 'login' ? 0 : ESPERA_REENVIO);

  // Cuenta regresiva para el botón de reenviar
  useEffect(() => {
    if (espera <= 0) return;
    const t = setTimeout(() => setEspera(espera - 1), 1000);
    return () => clearTimeout(t);
  }, [espera]);

  const onVerificar = async () => {
    setAviso('');
    if (codigo.length !== LONGITUD_CODIGO) {
      setError(`El código tiene ${LONGITUD_CODIGO} dígitos`);
      return;
    }
    setError('');
    setVerificando(true);
    const resultado = await verificarCodigo(correo, codigo);
    setVerificando(false);
    // Si salió bien, Supabase crea la sesión y _layout cambia a las pestañas solo
    if (!resultado.ok) setError(resultado.mensaje);
  };

  const onReenviar = async () => {
    setError('');
    setAviso('');
    const resultado = await reenviarCodigo(correo);
    if (resultado.ok) {
      setAviso('Te enviamos un código nuevo');
      setCodigo('');
      setEspera(ESPERA_REENVIO);
    } else {
      setError(resultado.mensaje);
    }
  };

  return (
    <PantallaAuth titulo="Verifica tu correo" subtitulo={`Escribe el código que enviamos a ${correo}`}>
      <CampoTexto
        placeholder="Código de 6 dígitos"
        keyboardType="number-pad"
        textContentType="oneTimeCode"
        autoComplete="one-time-code"
        maxLength={LONGITUD_CODIGO}
        value={codigo}
        onChangeText={(t) => setCodigo(t.replace(/\D/g, ''))}
        error={error}
        style={styles.codigo}
      />
      {aviso ? <Text style={styles.aviso}>{aviso}</Text> : null}

      <BotonPrimario
        titulo={verificando ? 'Verificando...' : 'Verificar'}
        deshabilitado={verificando}
        onPress={onVerificar}
      />

      <Pressable disabled={espera > 0} onPress={onReenviar}>
        <Text style={[styles.enlace, espera > 0 && styles.enlaceInactivo]}>
          {espera > 0 ? `Reenviar código en ${espera} s` : 'Reenviar código'}
        </Text>
      </Pressable>

      <Pressable onPress={() => router.replace('/login')}>
        <Text style={styles.enlace}>Volver a iniciar sesión</Text>
      </Pressable>
    </PantallaAuth>
  );
}

const styles = StyleSheet.create({
  codigo: {
    textAlign: 'center',
    letterSpacing: 8,
  },
  aviso: {
    marginBottom: spacing.md,
    textAlign: 'center',
    fontSize: fontSize.md,
    color: colors.primary,
  },
  enlace: {
    marginTop: spacing.md,
    textAlign: 'center',
    fontSize: fontSize.md,
    color: colors.primary,
  },
  enlaceInactivo: {
    color: colors.textMuted,
  },
});