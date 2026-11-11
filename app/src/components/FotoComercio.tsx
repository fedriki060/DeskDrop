import { Image, StyleSheet, Text, View } from 'react-native';
import { colors, fontWeight, radius } from '../theme';

type Props = {
  nombre: string;
  imagenUrl?: string | null;
  /** Lado del cuadrado en píxeles */
  tamano?: number;
};

// Foto del comercio; si todavía no tiene, un cuadro con la letra inicial.
export default function FotoComercio({ nombre, imagenUrl, tamano = 88 }: Props) {
  const caja = { width: tamano, height: tamano, borderRadius: radius.md };
  if (imagenUrl) {
    return <Image source={{ uri: imagenUrl }} style={[styles.foto, caja]} resizeMode="cover" />;
  }
  return (
    <View style={[styles.inicial, caja]}>
      <Text style={[styles.letra, { fontSize: tamano * 0.45 }]}>{nombre.charAt(0).toUpperCase()}</Text>
    </View>
  );
}

const styles = StyleSheet.create({
  foto: { backgroundColor: colors.border },
  inicial: { alignItems: 'center', justifyContent: 'center', backgroundColor: colors.primary },
  letra: { fontWeight: fontWeight.bold, color: colors.white },
});
