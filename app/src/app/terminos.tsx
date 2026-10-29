import { useLocalSearchParams } from 'expo-router';
import { useState } from 'react';
import { ScrollView, StyleSheet, Text, View } from 'react-native';
import SelectorOpciones from '../components/SelectorOpciones';
import { colors, fontSize, fontWeight, spacing } from '../theme';
import {
  AVISO_BORRADOR,
  FECHA_VERSION,
  PRIVACIDAD,
  TERMINOS,
  VERSION_LEGAL,
} from '../utils/legal';

const SECCIONES = ['Términos', 'Privacidad'] as const;
type Seccion = (typeof SECCIONES)[number];

export default function Terminos() {
  const { seccion } = useLocalSearchParams<{ seccion?: string }>();
  const [actual, setActual] = useState<Seccion>(
    seccion === 'privacidad' ? 'Privacidad' : 'Términos'
  );
  const contenido = actual === 'Términos' ? TERMINOS : PRIVACIDAD;

  return (
    <ScrollView style={styles.flex} contentContainerStyle={styles.container}>
      <SelectorOpciones opciones={SECCIONES} valor={actual} onChange={setActual} />

      <Text style={styles.version}>
        Versión {VERSION_LEGAL} · {FECHA_VERSION}
      </Text>
      <Text style={styles.borrador}>{AVISO_BORRADOR}</Text>

      {contenido.map((s) => (
        <View key={s.titulo} style={styles.seccion}>
          <Text style={styles.titulo}>{s.titulo}</Text>
          <Text style={styles.cuerpo}>{s.cuerpo}</Text>
        </View>
      ))}
    </ScrollView>
  );
}

const styles = StyleSheet.create({
  flex: {
    flex: 1,
    backgroundColor: colors.background,
  },
  container: {
    padding: spacing.lg,
  },
  version: {
    fontSize: fontSize.sm,
    color: colors.textMuted,
  },
  borrador: {
    marginTop: spacing.xs,
    marginBottom: spacing.md,
    fontSize: fontSize.sm,
    color: colors.warning,
  },
  seccion: {
    marginBottom: spacing.lg,
  },
  titulo: {
    fontSize: fontSize.lg,
    fontWeight: fontWeight.bold,
    color: colors.primary,
  },
  cuerpo: {
    marginTop: spacing.xs,
    fontSize: fontSize.md,
    color: colors.text,
  },
});
