import { Ionicons } from '@expo/vector-icons';
import { useRouter } from 'expo-router';
import * as ImagePicker from 'expo-image-picker';
import { useEffect, useState } from 'react';
import { Modal, Pressable, ScrollView, StyleSheet, Switch, Text, View } from 'react-native';
import { Alert } from '../../utils/alerta';
import { useAuth } from '../../context/AuthContext';
import CampoTexto from '../../components/CampoTexto';
import FotoComercio from '../../components/FotoComercio';
import Casilla from '../../components/Casilla';
import BotonPrimario from '../../components/BotonPrimario';
import { useCarrito } from '../../context/CarritoContext';
import { useComercio } from '../../context/ComercioContext';
import { tieneEntregasEnCurso } from '../../services/repartidorService';
import { colors, fontSize, fontWeight, radius, spacing } from '../../theme';
import { CONDICIONES_REPARTIDOR } from '../../utils/legal';
import { esTelefonoValido, normalizarTelefono } from '../../utils/validaciones';
import { etiquetasRol, puedeActivarRepartidor, rutaInicial } from '../../utils/roles';

export default function Perfil() {
  const router = useRouter();
  const {
    usuario,
    perfil,
    rolActivo,
    cambiarRolActivo,
    habilitadoRepartidor,
    habilitarRepartidor,
    actualizarTelefono,
    cerrarSesion,
    eliminarCuenta,
  } = useAuth();
  const { vaciar } = useCarrito();
  const { comercio, cambiarFoto, quitarFoto } = useComercio();
  const [guardandoFoto, setGuardandoFoto] = useState(false);

  // Solo para cuentas de comercio: la foto que aparece en la lista de tiendas
  const elegirFoto = async () => {
    const resultado = await ImagePicker.launchImageLibraryAsync({
      mediaTypes: ['images'],
      allowsEditing: true,
      aspect: [1, 1],
      quality: 0.7,
    });
    if (resultado.canceled) return;
    const foto = resultado.assets[0];
    setGuardandoFoto(true);
    const guardada = await cambiarFoto(foto.uri, foto.mimeType);
    setGuardandoFoto(false);
    if (!guardada.ok) Alert.alert('No se pudo guardar la foto', guardada.mensaje);
  };

  const eliminarFoto = async () => {
    setGuardandoFoto(true);
    const quitada = await quitarFoto();
    setGuardandoFoto(false);
    if (!quitada.ok) Alert.alert('No se pudo quitar la foto', quitada.mensaje);
  };
  const [eliminando, setEliminando] = useState(false);

  const [telefono, setTelefono] = useState('');
  const [errorTelefono, setErrorTelefono] = useState<string>();
  const [guardandoTelefono, setGuardandoTelefono] = useState(false);
  useEffect(() => setTelefono(perfil?.telefono ?? ''), [perfil?.telefono]);
  const telefonoCambio = normalizarTelefono(telefono) !== (perfil?.telefono ?? '');

  const guardarTelefono = async () => {
    const limpio = normalizarTelefono(telefono);
    if (limpio && !esTelefonoValido(limpio)) {
      setErrorTelefono('Escribe un celular de 10 dígitos que empiece por 3.');
      return;
    }
    setErrorTelefono(undefined);
    setGuardandoTelefono(true);
    const resultado = await actualizarTelefono(limpio || null);
    setGuardandoTelefono(false);
    if (!resultado.ok) setErrorTelefono(resultado.mensaje);
    else Alert.alert('Listo', limpio ? 'Guardamos tu celular.' : 'Borramos tu celular.');
  };

  const [declaracion, setDeclaracion] = useState(false);
  const [mayorDeEdad, setMayorDeEdad] = useState(false);
  const [errorDeclaracion, setErrorDeclaracion] = useState<string>();
  const [guardando, setGuardando] = useState(false);

  // Cualquier solicitante puede pedir la vista de domiciliario; la primera vez declara su edad
  const puedeSerDomiciliario = perfil ? puedeActivarRepartidor(perfil.rol) : false;
  const modoDomiciliario = rolActivo === 'domiciliario';

  const irAModo = (nuevoRol: 'solicitante' | 'domiciliario') => {
    cambiarRolActivo(nuevoRol);
    router.navigate(rutaInicial(nuevoRol));
  };

  const onCambiarModo = async (activar: boolean) => {
    if (activar) {
      if (habilitadoRepartidor) irAModo('domiciliario');
      else {
        setMayorDeEdad(false);
        setErrorDeclaracion(undefined);
        setDeclaracion(true);
      }
      return;
    }
    if (await tieneEntregasEnCurso()) {
      Alert.alert(
        'Tienes entregas en curso',
        'Termina tus entregas antes de volver a la vista de solicitante.'
      );
      return;
    }
    irAModo('solicitante');
  };

  const confirmarDeclaracion = async () => {
    if (!mayorDeEdad) {
      setErrorDeclaracion('Debes declarar que tienes 18 años o más');
      return;
    }
    setGuardando(true);
    const resultado = await habilitarRepartidor();
    setGuardando(false);
    if (!resultado.ok) {
      setErrorDeclaracion(resultado.mensaje);
      return;
    }
    setDeclaracion(false);
    irAModo('domiciliario');
  };

  const onCerrarSesion = () => {
    vaciar();
    cerrarSesion();
  };

  const eliminar = async () => {
    setEliminando(true);
    const resultado = await eliminarCuenta();
    setEliminando(false);
    if (resultado.ok) {
      vaciar(); // al cerrarse la sesión, _layout lleva al login
    } else {
      Alert.alert('No se pudo eliminar', resultado.mensaje);
    }
  };

  const onEliminarCuenta = () => {
    Alert.alert(
      'Eliminar cuenta',
      'Se borrarán tu nombre, correo y teléfono, y no podrás volver a entrar con esta cuenta. ' +
        'Tus pedidos anteriores se conservan de forma anónima. Esta acción no se puede deshacer.',
      [
        { text: 'Cancelar', style: 'cancel' },
        { text: 'Eliminar', style: 'destructive', onPress: eliminar },
      ]
    );
  };

  return (
    <ScrollView style={styles.fondo} contentContainerStyle={styles.container}>
      <Ionicons name="person-circle-outline" size={96} color={colors.primary} />
      <Text style={styles.nombre}>{usuario}</Text>
      <Text style={styles.rol}>Rol activo: {etiquetasRol[rolActivo]}</Text>

      {perfil?.rol === 'comercio' && comercio ? (
        <View style={styles.bloqueFoto}>
          <FotoComercio nombre={comercio.nombre} imagenUrl={comercio.imagenUrl} tamano={120} />
          <Text style={styles.nombreComercio}>{comercio.nombre}</Text>
          <Pressable onPress={elegirFoto} disabled={guardandoFoto} hitSlop={8}>
            <Text style={styles.enlaceFoto}>
              {guardandoFoto ? 'Guardando...' : comercio.imagenUrl ? 'Cambiar foto' : 'Subir foto'}
            </Text>
          </Pressable>
          {comercio.imagenUrl && !guardandoFoto ? (
            <Pressable onPress={eliminarFoto} hitSlop={8}>
              <Text style={styles.quitarFoto}>Quitar foto</Text>
            </Pressable>
          ) : null}
        </View>
      ) : null}

      {/* El celular es para el contacto entre solicitante y domiciliario: el comercio no lo necesita */}
      {perfil?.rol !== 'comercio' && (
        <View style={styles.bloqueTelefono}>
          <CampoTexto
            etiqueta="Celular"
            value={telefono}
            onChangeText={(t) => {
              setTelefono(t);
              setErrorTelefono(undefined);
            }}
            keyboardType="phone-pad"
            maxLength={14}
            placeholder="3001234567"
            error={errorTelefono}
          />
          <Text style={styles.ayudaTelefono}>
            Si haces entregas, el solicitante lo ve solo mientras llevas su pedido.
          </Text>
          {telefonoCambio ? (
            <BotonPrimario
              titulo={guardandoTelefono ? 'Guardando...' : 'Guardar celular'}
              deshabilitado={guardandoTelefono}
              onPress={guardarTelefono}
            />
          ) : null}
        </View>
      )}

      {puedeSerDomiciliario && (
        <View style={styles.filaModo}>
          <Text style={styles.textoModo}>Activar Domiciliario</Text>
          <Switch
            value={modoDomiciliario}
            onValueChange={onCambiarModo}
            trackColor={{ false: colors.border, true: colors.primary }}
          />
        </View>
      )}

      <Modal visible={declaracion} transparent animationType="fade" onRequestClose={() => setDeclaracion(false)}>
        <View style={styles.fondoModal}>
          <View style={styles.tarjetaModal}>
            <Text style={styles.tituloModal}>Vista de domiciliario</Text>
            {CONDICIONES_REPARTIDOR.map((c) => (
              <Text key={c.titulo} style={styles.textoCondicion}>
                <Text style={styles.negrita}>{c.titulo}: </Text>
                {c.cuerpo}
              </Text>
            ))}
            <Casilla marcada={mayorDeEdad} onCambiar={setMayorDeEdad} error={errorDeclaracion}>
              Declaro que tengo 18 años o más y acepto estas condiciones.
            </Casilla>
            <BotonPrimario
              titulo={guardando ? 'Guardando...' : 'Activar'}
              deshabilitado={guardando}
              onPress={confirmarDeclaracion}
            />
            <Pressable onPress={() => setDeclaracion(false)} hitSlop={8}>
              <Text style={styles.cancelar}>Cancelar</Text>
            </Pressable>
          </View>
        </View>
      </Modal>

      <Pressable style={styles.boton} onPress={onCerrarSesion}>
        <Text style={styles.textoBoton}>Cerrar Sesión</Text>
      </Pressable>

      {/* La cuenta de un comercio la gestiona el equipo de DeskDrop: no se elimina desde la app */}
      {perfil?.rol !== 'comercio' && (
        <Pressable onPress={onEliminarCuenta} disabled={eliminando} hitSlop={8}>
          <Text style={styles.eliminar}>
            {eliminando ? 'Eliminando cuenta...' : 'Eliminar mi cuenta'}
          </Text>
        </Pressable>
      )}
    </ScrollView>
  );
}

const styles = StyleSheet.create({
  bloqueFoto: { alignItems: 'center', marginBottom: spacing.lg, gap: spacing.xs },
  nombreComercio: { marginTop: spacing.sm, fontSize: fontSize.lg, fontWeight: fontWeight.bold, color: colors.text },
  enlaceFoto: { fontSize: fontSize.md, fontWeight: fontWeight.bold, color: colors.primary },
  quitarFoto: { fontSize: fontSize.md, color: colors.danger },
  bloqueTelefono: { alignSelf: 'stretch', marginBottom: spacing.lg },
  ayudaTelefono: { marginBottom: spacing.sm, fontSize: fontSize.sm, color: colors.textMuted },
  fondo: { flex: 1, backgroundColor: colors.background },
  container: {
    flexGrow: 1,
    alignItems: 'center',
    padding: spacing.lg,
    paddingTop: spacing.xl,
    backgroundColor: colors.background,
  },
  nombre: {
    marginTop: spacing.sm,
    fontSize: fontSize.xl,
    fontWeight: fontWeight.bold,
    color: colors.text,
  },
  rol: {
    marginTop: spacing.xs,
    marginBottom: spacing.xl,
    fontSize: fontSize.md,
    color: colors.textMuted,
  },
  filaModo: {
    alignSelf: 'stretch',
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    padding: spacing.md,
    marginBottom: spacing.lg,
    borderWidth: 1,
    borderColor: colors.primary,
    borderRadius: radius.sm,
  },
  textoModo: {
    fontSize: fontSize.lg,
    color: colors.primary,
  },
  boton: {
    alignSelf: 'stretch',
    padding: spacing.md,
    alignItems: 'center',
    borderRadius: radius.sm,
    backgroundColor: colors.primary,
  },
  textoBoton: {
    fontSize: fontSize.lg,
    fontWeight: fontWeight.bold,
    color: colors.white,
  },
  fondoModal: {
    flex: 1,
    justifyContent: 'center',
    padding: spacing.lg,
    backgroundColor: 'rgba(0,0,0,0.5)',
  },
  tarjetaModal: {
    padding: spacing.lg,
    borderRadius: radius.sm,
    backgroundColor: colors.background,
  },
  tituloModal: {
    marginBottom: spacing.md,
    fontSize: fontSize.xl,
    fontWeight: fontWeight.bold,
    color: colors.text,
  },
  textoCondicion: {
    marginBottom: spacing.sm,
    fontSize: fontSize.md,
    color: colors.text,
  },
  negrita: {
    fontWeight: fontWeight.bold,
  },
  cancelar: {
    textAlign: 'center',
    fontSize: fontSize.md,
    color: colors.textMuted,
  },
  eliminar: {
    marginTop: spacing.xl,
    fontSize: fontSize.md,
    color: colors.danger,
  },
});