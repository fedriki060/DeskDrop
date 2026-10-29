import { Pressable, StyleSheet, Text, View } from 'react-native';
import { colors, fontSize, fontWeight, radius, spacing } from '../theme';

type Props<T extends string> = {
  etiqueta?: string;
  opciones: readonly T[];
  valor: T;
  onChange: (valor: T) => void;
};

export default function SelectorOpciones<T extends string>({
  etiqueta,
  opciones,
  valor,
  onChange,
}: Props<T>) {
  return (
    <View style={styles.contenedor}>
      {etiqueta ? <Text style={styles.etiqueta}>{etiqueta}</Text> : null}
      <View style={styles.fila}>
        {opciones.map((opcion) => {
          const activa = opcion === valor;
          return (
            <Pressable
              key={opcion}
              style={[styles.chip, activa && styles.chipActivo]}
              onPress={() => onChange(opcion)}
            >
              <Text style={[styles.texto, activa && styles.textoActivo]}>{opcion}</Text>
            </Pressable>
          );
        })}
      </View>
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
  fila: {
    flexDirection: 'row',
    flexWrap: 'wrap',
  },
  chip: {
    paddingVertical: spacing.sm,
    paddingHorizontal: spacing.md,
    marginRight: spacing.sm,
    marginBottom: spacing.sm,
    borderWidth: 1,
    borderColor: colors.primary,
    borderRadius: radius.lg,
  },
  chipActivo: {
    backgroundColor: colors.primary,
  },
  texto: {
    fontSize: fontSize.md,
    color: colors.primary,
  },
  textoActivo: {
    fontWeight: fontWeight.bold,
    color: colors.white,
  },
});