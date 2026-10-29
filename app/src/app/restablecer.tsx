import { useLocalSearchParams, useRouter } from 'expo-router';
import { useEffect, useState } from 'react';
import { Pressable, StyleSheet, Text } from 'react-native';
import BotonPrimario from '../components/BotonPrimario';
import CampoTexto from '../components/CampoTexto';
import PantallaAuth from '../components/PantallaAuth';
import { useAuth } from '../context/AuthContext';
import { colors, fontSize, spacing } from '../theme';
import { esContrasenaSegura, REQUISITOS_CONTRASENA } from '../utils/validaciones';

// Supabase permite códigos de 6 a 10 dígitos según otp_length (config.toml / panel de staging)
const MIN_CODIGO = 6;
const MAX_CODIGO = 10;
// En staging Supabase no deja pedir otro correo antes de 60 s (valor por defecto)
const ESPERA_REENVIO = 60;

type Campo = 'codigo' | 'nueva' | 'confirmar';
type Errores = Partial<Record<Campo, string>>;

export default function Restablecer() {
  const router = useRouter();
  const { correo } = useLocalSearchParams<{ correo: string }>();
  const { restablecerContrasena, solicitarRecuperacion, cancelarRecuperacion } = useAuth();
  const [codigo, setCodigo] = useState('');
  const [nueva, setNueva] = useState('');
  const [confirmar, setConfirmar] = useState('');
  const [errores, setErrores] = useState<Errores>({});
  const [errorGeneral, setErrorGeneral] = useState('');
  const [aviso, setAviso] = useState('');
  const [guardando, setGuardando] = useState(false);
  const [espera, setEspera] = useState(ESPERA_REENVIO);
    // El código ya se validó (y se gastó): solo falta una contraseña que Supabase acepte
  const [codigoValidado, setCodigoValidado] = useState(false);

  // Si el usuario sale de esta pantalla a medias, se cierra la sesión temporal.
  // Con éxito no hace nada: cancelarRecuperacion solo actúa si quedó algo pendiente.
  useEffect(() => {
    return () => {
      cancelarRecuperacion();
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  useEffect(() => {
    if (espera <= 0) return;
    const t = setTimeout(() => setEspera(espera - 1), 1000);
    return () => clearTimeout(t);
  }, [espera]);

  // La contraseña se valida antes de gastar el código: si falla después, toca pedir otro
  const validar = (): Errores => {
    const e: Errores = {};
    if (!codigoValidado && codigo.length < MIN_CODIGO) e.codigo = 'Escribe el código completo que te llegó al correo';
    if (!esContrasenaSegura(nueva)) e.nueva = REQUISITOS_CONTRASENA;
    if (nueva !== confirmar) e.confirmar = 'Las contraseñas no coinciden';
    return e;
  };

  const onRestablecer = async () => {
    const e = validar();
    setErrores(e);
    setErrorGeneral('');
    setAviso('');
    if (Object.keys(e).length > 0) return;

    setGuardando(true);
    const resultado = await restablecerContrasena(correo, codigo, nueva);
    setGuardando(false);
    // Con éxito, la sesión queda iniciada y _layout lleva a las pestañas solo
        if (!resultado.ok) {
      setErrorGeneral(resultado.mensaje);
      setCodigoValidado(resultado.codigoValidado);
    }
  };

    const onVolver = async () => {
    await cancelarRecuperacion();
    router.replace('/login');
  };

  const onReenviar = async () => {
    setErrorGeneral('');
    setAviso('');
    const resultado = await solicitarRecuperacion(correo);
    if (resultado.ok) {
      setAviso('Te enviamos un código nuevo');
      setCodigo('');
      setEspera(ESPERA_REENVIO);
    } else {
      setErrorGeneral(resultado.mensaje);
    }
  };

  return (
    <PantallaAuth
      titulo="Reinicia tu contraseña"
      subtitulo={`Escribe el código que enviamos a ${correo} y tu nueva contraseña`}
    >
            {codigoValidado ? (
        <Text style={styles.aviso}>Código verificado. Ahora elige otra contraseña.</Text>
      ) : (
        <CampoTexto
          placeholder="Código de verificación"
          keyboardType="number-pad"
          textContentType="oneTimeCode"
          autoComplete="one-time-code"
          maxLength={MAX_CODIGO}
          value={codigo}
          onChangeText={(t) => setCodigo(t.replace(/\D/g, ''))}
          error={errores.codigo}
          style={styles.codigo}
        />
      )}

      <CampoTexto
        placeholder="Nueva contraseña"
        secureTextEntry
        textContentType="newPassword"
        value={nueva}
        onChangeText={setNueva}
        error={errores.nueva}
      />
      <CampoTexto
        placeholder="Confirmar contraseña"
        secureTextEntry
        textContentType="newPassword"
        value={confirmar}
        onChangeText={setConfirmar}
        error={errores.confirmar}
      />

      {errorGeneral ? <Text style={styles.error}>{errorGeneral}</Text> : null}
      {aviso ? <Text style={styles.aviso}>{aviso}</Text> : null}

      <BotonPrimario
        titulo={guardando ? 'Guardando...' : 'Restablecer contraseña'}
        deshabilitado={guardando}
        onPress={onRestablecer}
      />

            {!codigoValidado && (
        <Pressable disabled={espera > 0} onPress={onReenviar}>
          <Text style={[styles.enlace, espera > 0 && styles.enlaceInactivo]}>
            {espera > 0 ? `Reenviar código en ${espera} s` : 'Reenviar código'}
          </Text>
        </Pressable>
      )}

      <Pressable onPress={onVolver}>
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
  error: {
    marginBottom: spacing.md,
    textAlign: 'center',
    fontSize: fontSize.md,
    color: colors.danger,
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