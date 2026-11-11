import { ActivityIndicator, StyleSheet, Text, View } from 'react-native';
import GestionProductos from '../../components/GestionProductos';
import ProtegidoPorRol from '../../components/ProtegidoPorRol';
import { useComercio } from '../../context/ComercioContext';
import { colors, fontSize, spacing } from '../../theme';

export default function Productos() {
  const { comercio } = useComercio();

  return (
    <ProtegidoPorRol rol="comercio">
      {comercio === undefined ? (
        <View style={styles.centro}>
          <ActivityIndicator color={colors.primary} />
        </View>
      ) : comercio === null ? (
        <View style={styles.centro}>
          <Text style={styles.texto}>Tu cuenta aún no tiene un comercio asignado.</Text>
        </View>
      ) : (
        <GestionProductos comercioId={comercio.id} />
      )}
    </ProtegidoPorRol>
  );
}

const styles = StyleSheet.create({
  centro: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    padding: spacing.lg,
    backgroundColor: colors.background,
  },
  texto: { textAlign: 'center', fontSize: fontSize.lg, color: colors.textMuted },
});
