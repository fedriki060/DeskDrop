import { ReactNode } from 'react';
import {
    KeyboardAvoidingView,
    Platform,
    ScrollView,
    StyleSheet,
    Text,
} from 'react-native';
import { colors, fontSize, fontWeight, spacing } from '../theme';

type Props = {
  titulo: string;
  subtitulo?: string;
  children: ReactNode;
};

export default function PantallaAuth({ titulo, subtitulo, children }: Props) {
  return (
    <KeyboardAvoidingView
      style={styles.flex}
      behavior={Platform.OS === 'ios' ? 'padding' : undefined}
    >
      <ScrollView
        contentContainerStyle={styles.container}
        keyboardShouldPersistTaps="handled"
      >
        <Text style={styles.marca}>DeskDrop</Text>
        <Text style={[styles.titulo, { marginBottom: subtitulo ? spacing.xs : spacing.lg }]}>
          {titulo}
        </Text>
        {subtitulo ? <Text style={styles.subtitulo}>{subtitulo}</Text> : null}
        {children}
      </ScrollView>
    </KeyboardAvoidingView>
  );
}

const styles = StyleSheet.create({
  flex: {
    flex: 1,
    backgroundColor: colors.background,
  },
  container: {
    flexGrow: 1,
    justifyContent: 'center',
    padding: spacing.lg,
  },
  marca: {
    textAlign: 'center',
    fontSize: 40,
    fontWeight: fontWeight.bold,
    color: colors.primary,
  },
  titulo: {
    marginTop: spacing.lg,
    textAlign: 'center',
    fontSize: fontSize.xl,
    fontWeight: fontWeight.bold,
    color: colors.primary,
  },
  subtitulo: {
    marginBottom: spacing.lg,
    textAlign: 'center',
    fontSize: fontSize.md,
    color: colors.textMuted,
  },
});