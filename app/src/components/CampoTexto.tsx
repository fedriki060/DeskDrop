import { StyleSheet, Text, TextInput, TextInputProps, View } from 'react-native';
import { colors, fontSize, radius, spacing } from '../theme';

type Props = TextInputProps & {
  etiqueta?: string;
  error?: string;
};

export default function CampoTexto({ etiqueta, error, style, ...resto }: Props) {
  return (
    <View style={styles.contenedor}>
      {etiqueta ? <Text style={styles.etiqueta}>{etiqueta}</Text> : null}
      <TextInput
        placeholderTextColor={colors.textMuted}
        autoCapitalize="none"
        style={[styles.input, error ? styles.inputError : null, style]}
        {...resto}
      />
      {error ? <Text style={styles.error}>{error}</Text> : null}
    </View>
  );
}

const styles = StyleSheet.create({
  contenedor: {
    marginBottom: spacing.md,
  },
  etiqueta: {
    marginBottom: spacing.xs,
    fontSize: fontSize.md,
    color: colors.text,
  },
  input: {
    padding: spacing.md,
    borderWidth: 1,
    borderColor: colors.primary,
    borderRadius: radius.sm,
    fontSize: fontSize.lg,
    color: colors.text,
  },
  inputError: {
    borderColor: colors.danger,
  },
  error: {
    marginTop: spacing.xs,
    fontSize: fontSize.sm,
    color: colors.danger,
  },
});