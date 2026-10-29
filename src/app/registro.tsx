import { useRouter } from 'expo-router';
import { useState } from 'react';
import { Pressable, StyleSheet, Text } from 'react-native';
import AvisoEmergente from '../components/AvisoEmergente';
import BotonPrimario from '../components/BotonPrimario';
import CampoTexto from '../components/CampoTexto';
import Casilla from '../components/Casilla';
import PantallaAuth from '../components/PantallaAuth';
import SelectorOpciones from '../components/SelectorOpciones';
import { registrarAceptacion } from '../services/consentimientoService';
import { colors, fontSize, spacing } from '../theme';
import {
  esCorreoInstitucional,
  esDocumentoValido,
  esFechaValida,
  formatearFecha,
  LONGITUD_MINIMA_CONTRASENA,
  TIPOS_DOCUMENTO,
  TipoDocumento,
} from '../utils/validaciones';

type Campo = 'nombre' | 'fecha' | 'documento' | 'correo' | 'contrasena' | 'terminos';
type Errores = Partial<Record<Campo, string>>;

export default function Registro() {
  const router = useRouter();
  const [nombre, setNombre] = useState('');
  const [fecha, setFecha] = useState('');
  const [tipoDocumento, setTipoDocumento] = useState<TipoDocumento>('CC');
  const [documento, setDocumento] = useState('');
  const [correo, setCorreo] = useState('');
  const [contrasena, setContrasena] = useState('');
  const [acepta, setAcepta] = useState(false);
  const [errores, setErrores] = useState<Errores>({});
  const [cargando, setCargando] = useState(false);
  const [creada, setCreada] = useState(false);

  const validar = (): Errores => {
    const e: Errores = {};
    if (nombre.trim().length < 3) e.nombre = 'Ingresa tu nombre completo';
    if (!esFechaValida(fecha)) e.fecha = 'Usa el formato DD/MM/AAAA';
    if (!esDocumentoValido(documento)) e.documento = 'Número de documento no válido';
    if (!esCorreoInstitucional(correo)) e.correo = 'Usa tu correo institucional';
    if (contrasena.length < LONGITUD_MINIMA_CONTRASENA) {
      e.contrasena = `Mínimo ${LONGITUD_MINIMA_CONTRASENA} caracteres`;
    }
    if (!acepta) e.terminos = 'Debes aceptar para crear tu cuenta';
    return e;
  };

  // SIMULADO: aquí irá la llamada a la API de registro (T-068)
  const onContinuar = async () => {
    const e = validar();
    setErrores(e);
    if (Object.keys(e).length > 0) return;

    setCargando(true);
    await registrarAceptacion(correo.trim().toLowerCase());
    setCargando(false);
    setCreada(true);
  };

  const onCerrarAviso = () => {
    setCreada(false);
    router.replace('/login');
  };

  const abrirLegal = (seccion: 'terminos' | 'privacidad') =>
    router.push({ pathname: '/terminos', params: { seccion } });

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
        etiqueta="Fecha de nacimiento"
        placeholder="DD/MM/AAAA"
        keyboardType="number-pad"
        maxLength={10}
        value={fecha}
        onChangeText={(t) => setFecha(formatearFecha(t))}
        error={errores.fecha}
      />
      <SelectorOpciones
        etiqueta="Tipo de documento"
        opciones={TIPOS_DOCUMENTO}
        valor={tipoDocumento}
        onChange={setTipoDocumento}
      />
      <CampoTexto
        etiqueta="Número de documento"
        placeholder="Número de documento"
        autoCorrect={false}
        value={documento}
        onChangeText={setDocumento}
        error={errores.documento}
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

      <BotonPrimario
        titulo={cargando ? 'Creando cuenta...' : 'Continuar'}
        deshabilitado={cargando}
        onPress={onContinuar}
      />

      <Pressable onPress={() => router.back()}>
        <Text style={styles.enlace}>¿Ya tienes cuenta? Inicia sesión</Text>
      </Pressable>

      <AvisoEmergente
        visible={creada}
        mensaje="Cuenta creada. Te enviamos un enlace de verificación a tu correo."
        onCerrar={onCerrarAviso}
      />
    </PantallaAuth>
  );
}

const styles = StyleSheet.create({
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
