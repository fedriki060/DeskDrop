import { Ionicons } from '@expo/vector-icons';
import { useRouter } from 'expo-router';
import { useEffect, useState } from 'react';
import { ActivityIndicator, FlatList, Pressable, StyleSheet, Text, View } from 'react-native';
import { useCarrito } from '../context/CarritoContext';
import { listarPuntosEntrega, PuntoEntrega } from '../services/checkoutService';
import { colors, fontSize, fontWeight, radius, spacing } from '../theme';

export default function Ubicacion() {
  const router = useRouter();
  const { puntoEntrega, elegirPuntoEntrega } = useCarrito();
  const [puntos, setPuntos] = useState<PuntoEntrega[]>([]);
  const [cargando, setCargando] = useState(true);

  useEffect(() => {
    listarPuntosEntrega()
      .then(setPuntos)
      .finally(() => setCargando(false));
  }, []);

  const onElegir = (punto: PuntoEntrega) => {
    elegirPuntoEntrega(punto);
    router.back();
  };

  if (cargando) {
    return (
      <View style={styles.centro}>
        <ActivityIndicator color={colors.primary} />
      </View>
    );
  }

  return (
    <FlatList
      data={puntos}
      keyExtractor={(p) => p.id}
      contentContainerStyle={styles.lista}
      ListHeaderComponent={
        <View style={styles.encabezado}>
          <Text style={styles.titulo}>Elige dónde recibir tu pedido</Text>
          <Text style={styles.aviso}>
            No se entregan pedidos en aulas ni en lugares cerrados.
          </Text>
        </View>
      }
      renderItem={({ item }) => {
        const elegido = item.id === puntoEntrega?.id;
        return (
          <Pressable
            style={[styles.fila, elegido && styles.filaElegida]}
            onPress={() => onElegir(item)}
          >
            <Ionicons name="location-outline" size={22} color={colors.primary} />
            <Text style={styles.nombre}>{item.nombre}</Text>
            {elegido && <Ionicons name="checkmark" size={22} color={colors.primary} />}
          </Pressable>
        );
      }}
    />
  );
}

const styles = StyleSheet.create({
  centro: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.background,
  },
  lista: {
    padding: spacing.md,
    backgroundColor: colors.background,
  },
  encabezado: {
    marginBottom: spacing.md,
  },
  titulo: {
    fontSize: fontSize.xl,
    fontWeight: fontWeight.bold,
    color: colors.primary,
  },
  aviso: {
    marginTop: spacing.xs,
    fontSize: fontSize.md,
    color: colors.textMuted,
  },
  fila: {
    flexDirection: 'row',
    alignItems: 'center',
    padding: spacing.md,
    marginBottom: spacing.sm,
    backgroundColor: colors.surface,
    borderRadius: radius.md,
  },
  filaElegida: {
    borderWidth: 1,
    borderColor: colors.primary,
  },
  nombre: {
    flex: 1,
    marginLeft: spacing.sm,
    fontSize: fontSize.lg,
    color: colors.text,
  },
});