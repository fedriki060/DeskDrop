import { Href, useRouter } from 'expo-router';
import { useState } from 'react';
import { Pressable, StyleSheet, Text } from 'react-native';
import BotonPrimario from '../components/BotonPrimario';
import CampoTexto from '../components/CampoTexto';
import Casilla from '../components/Casilla';
import PantallaAuth from '../components/PantallaAuth';
import { useAuth } from '../context/AuthContext';
import { colors, fontSize, spacing } from '../theme';
import {
  esContrasenaSegura,
  esCorreoInstitucional,
  REQUISITOS_CONTRASENA,
} from '../utils/validaciones';

type Campo = 'nombre' | 'correo' | 'contrasena' | 'terminos';
type Errores = Partial<Record<Campo, string>>;

export default function Registro() {
  const router = useRouter();
  const { registrar } = useAuth();
  const [nombre, setNombre] = useState('');
  const [correo, setCorreo] = useState('');
  const [contrasena, setContrasena] = useState('');
  const [acepta, setAcepta] = useState(false);
  const [errores, setErrores] = useState<Errores>({});
  const [errorGeneral, setErrorGeneral] = useState('');
  const [enviando, setEnviando] = useState(false);

  // Primero se valida aquí para dar mensajes claros; la base vuelve a validar el dominio
  const validar = (): Errores => {
    const e: Errores = {};
    if (nombre.trim().length < 3) e.nombre = 'Ingresa tu nombre completo';
    if (!esCorreoInstitucional(correo)) e.correo = 'Usa tu correo institucional';
    if (!esContrasenaSegura(contrasena)) e.contrasena = REQUISITOS_CONTRASENA;
    if (!acepta) e.terminos = 'Debes aceptar para crear tu cuenta';
    return e;
  };

  const onContinuar = async () => {
    const e = validar();
    setErrores(e);
    setErrorGeneral('');
    if (Object.keys(e).length > 0) return;

    setEnviando(true);
    const resultado = await registrar(nombre, correo, contrasena);
    setEnviando(false);

    if (!resultado.ok) {
      setErrorGeneral(resultado.mensaje);
      return;
    }
    // Sin verificación (local) ya hay sesión y _layout lleva a las pestañas solo
    if (resultado.requiereVerificacion) {
      router.replace({
        pathname: '/verificar',
        params: { correo: correo.trim().toLowerCase() },
      } as Href);
    }
  };

  const abrirLegal = (seccion: 'terminos' | 'privacidad') =>
    router.push({ pathname: '/terminos', params: { seccion } } as Href);

  return (
    <PantallaAuth titulo="Crear Cuenta">
      <CampoTexto
        etiqueta="Nombre completo"
        placeholder="Nombre y apellidos"
        autoCapitalize="words"
        value={nombre}
        onChangeText={setNombre}
        error={errores.nombre}
      />
      <CampoTexto
        etiqueta="Correo institucional"
        placeholder="usuario@eia.edu.co"
        autoCorrect={false}
        keyboardType="email-address"
        value={correo}
        onChangeText={setCorreo}
        error={errores.correo}
      />
      <CampoTexto
        etiqueta="Contraseña"
        placeholder="Contraseña"
        secureTextEntry
        value={contrasena}
        onChangeText={setContrasena}
        error={errores.contrasena}
      />

      <Casilla marcada={acepta} onCambiar={setAcepta} error={errores.terminos}>
        He leído y acepto los{' '}
        <Text style={styles.link} onPress={() => abrirLegal('terminos')}>
          Términos de servicio
        </Text>{' '}
        y la{' '}
        <Text style={styles.link} onPress={() => abrirLegal('privacidad')}>
          Política de privacidad
        </Text>
      </Casilla>

      {errorGeneral ? <Text style={styles.error}>{errorGeneral}</Text> : null}

      <BotonPrimario
        titulo={enviando ? 'Creando cuenta...' : 'Continuar'}
        deshabilitado={enviando}
        onPress={onContinuar}
      />

      <Pressable onPress={() => router.back()}>
        <Text style={styles.enlace}>¿Ya tienes cuenta? Inicia sesión</Text>
      </Pressable>
    </PantallaAuth>
  );
}

const styles = StyleSheet.create({
  error: {
    marginBottom: spacing.md,
    textAlign: 'center',
    fontSize: fontSize.md,
    color: colors.danger,
  },
  link: {
    color: colors.primary,
    textDecorationLine: 'underline',
  },
  enlace: {
    marginTop: spacing.lg,
    textAlign: 'center',
    fontSize: fontSize.md,
    color: colors.primary,
  },
});