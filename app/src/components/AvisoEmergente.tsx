import { Ionicons } from '@expo/vector-icons';
import { Modal, Pressable, StyleSheet, Text, View } from 'react-native';
import { colors, fontSize, fontWeight, radius, spacing } from '../theme';

type Props = {
  visible: boolean;
  mensaje: string;
  onCerrar: () => void;
};

export default function AvisoEmergente({ visible, mensaje, onCerrar }: Props) {
  return (
    <Modal visible={visible} transparent animationType="fade" onRequestClose={onCerrar}>
      <View style={styles.fondo}>
        <View style={styles.caja}>
          <Pressable style={styles.cerrar} onPress={onCerrar} hitSlop={12}>
            <Ionicons name="close" size={26} color={colors.primary} />
          </Pressable>
          <Text style={styles.mensaje}>{mensaje}</Text>
        </View>
      </View>
    </Modal>
  );
}

const styles = StyleSheet.create({
  fondo: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    padding: spacing.lg,
    backgroundColor: 'rgba(0,0,0,0.4)',
  },
  caja: {
    alignSelf: 'stretch',
    padding: spacing.xl,
    borderWidth: 2,
    borderColor: colors.primary,
    borderRadius: radius.md,
    backgroundColor: colors.background,
  },
  cerrar: {
    position: 'absolute',
    top: spacing.sm,
    right: spacing.sm,
  },
  mensaje: {
    marginTop: spacing.md,
    textAlign: 'center',
    fontSize: fontSize.xl,
    fontWeight: fontWeight.bold,
    color: colors.primary,
  },
});