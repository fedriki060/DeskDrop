import { Pressable, StyleSheet, Text } from 'react-native';
import { colors, fontSize, fontWeight, radius, spacing } from '../theme';

type Props = {
  titulo: string;
  onPress: () => void;
  deshabilitado?: boolean;
};

export default function BotonPrimario({ titulo, onPress, deshabilitado }: Props) {
  return (
    <Pressable
      style={[styles.boton, deshabilitado && styles.inactivo]}
      disabled={deshabilitado}
      onPress={onPress}
    >
      <Text style={styles.texto}>{titulo}</Text>
    </Pressable>
  );
}

const styles = StyleSheet.create({
  boton: {
    padding: spacing.md,
    marginBottom: spacing.md,
    alignItems: 'center',
    borderRadius: radius.sm,
    backgroundColor: colors.primary,
  },
  inactivo: {
    opacity: 0.6,
  },
  texto: {
    fontSize: fontSize.lg,
    fontWeight: fontWeight.bold,
    color: colors.white,
  },
});