import { Ionicons } from '@expo/vector-icons';
import { useRouter } from 'expo-router';
import { Pressable, StyleSheet, Switch, Text, View } from 'react-native';
import { useAuth } from '../../context/AuthContext';
import { useCarrito } from '../../context/CarritoContext';
import { colors, fontSize, fontWeight, radius, spacing } from '../../theme';
import { etiquetasRol, rutaInicial } from '../../utils/roles';

export default function Perfil() {
  const router = useRouter();
  const { usuario, roles, rolActivo, cambiarRolActivo, cerrarSesion } = useAuth();
  const { vaciar } = useCarrito();

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
});