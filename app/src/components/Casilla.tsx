import { Ionicons } from '@expo/vector-icons';
import { ReactNode } from 'react';
import { Pressable, StyleSheet, Text, View } from 'react-native';
import { colors, fontSize, spacing } from '../theme';

type Props = {
  marcada: boolean;
  onCambiar: (valor: boolean) => void;
  error?: string;
  children: ReactNode;
};

export default function Casilla({ marcada, onCambiar, error, children }: Props) {
  return (
    <View style={styles.contenedor}>
      <View style={styles.fila}>
        <Pressable
          onPress={() => onCambiar(!marcada)}
          hitSlop={8}
          accessibilityRole="checkbox"
          accessibilityState={{ checked: marcada }}
        >
          <Ionicons
            name={marcada ? 'checkbox' : 'square-outline'}
            size={26}
            color={error ? colors.danger : colors.primary}
          />
        </Pressable>
        <Text style={styles.texto}>{children}</Text>
      </View>
      {error ? <Text style={styles.error}>{error}</Text> : null}
    </View>
  );
}

const styles = StyleSheet.create({
  contenedor: {
    marginBottom: spacing.md,
  },
  fila: {
    flexDirection: 'row',
    alignItems: 'flex-start',
  },
  texto: {
    flex: 1,
    marginLeft: spacing.sm,
    fontSize: fontSize.md,
    color: colors.text,
  },
  error: {
    marginTop: spacing.xs,
    fontSize: fontSize.sm,
    color: colors.danger,
  },
});
