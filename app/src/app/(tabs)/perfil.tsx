import { Ionicons } from '@expo/vector-icons';
import { useRouter } from 'expo-router';
import { useState } from 'react';
import { Alert, Pressable, StyleSheet, Switch, Text, View } from 'react-native';
import { useAuth } from '../../context/AuthContext';
import { useCarrito } from '../../context/CarritoContext';
import { colors, fontSize, fontWeight, radius, spacing } from '../../theme';
import { etiquetasRol, rutaInicial } from '../../utils/roles';

export default function Perfil() {
  const router = useRouter();
  const { usuario, roles, rolActivo, cambiarRolActivo, cerrarSesion, eliminarCuenta } = useAuth();
  const { vaciar } = useCarrito();
  const [eliminando, setEliminando] = useState(false);

  const puedeSerDomiciliario = roles.includes('domiciliario');
  const modoDomiciliario = rolActivo === 'domiciliario';

  const onCambiarModo = (activar: boolean) => {
    const nuevoRol = activar ? 'domiciliario' : 'solicitante';
    cambiarRolActivo(nuevoRol);
    router.navigate(rutaInicial(nuevoRol));
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
    <View style={styles.container}>
      <Ionicons name="person-circle-outline" size={96} color={colors.primary} />
      <Text style={styles.nombre}>{usuario}</Text>
      <Text style={styles.rol}>Rol activo: {etiquetasRol[rolActivo]}</Text>

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

      <Pressable style={styles.boton} onPress={onCerrarSesion}>
        <Text style={styles.textoBoton}>Cerrar Sesión</Text>
      </Pressable>

      <Pressable onPress={onEliminarCuenta} disabled={eliminando} hitSlop={8}>
        <Text style={styles.eliminar}>
          {eliminando ? 'Eliminando cuenta...' : 'Eliminar mi cuenta'}
        </Text>
      </Pressable>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
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
  eliminar: {
    marginTop: spacing.xl,
    fontSize: fontSize.md,
    color: colors.danger,
  },
});