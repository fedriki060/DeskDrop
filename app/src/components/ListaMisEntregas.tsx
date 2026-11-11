import { useCallback, useEffect, useState } from 'react';
import { ActivityIndicator, FlatList, RefreshControl, StyleSheet, Text, View } from 'react-native';
import { useAuth } from '../context/AuthContext';
import { useVueltaAPrimerPlano } from '../hooks/useVueltaAPrimerPlano';
import { obtenerMisEntregas, ResumenEntregas } from '../services/entregasService';
import { colors, fontSize, fontWeight, radius, spacing } from '../theme';
import { formatearFecha, formatearPrecio } from '../utils/format';

export default function ListaMisEntregas() {
  const { perfil } = useAuth();
  const userId = perfil?.id;
  const vueltas = useVueltaAPrimerPlano();
  const [resumen, setResumen] = useState<ResumenEntregas>();
  const [cargando, setCargando] = useState(true);
  const [refrescando, setRefrescando] = useState(false);
  const [error, setError] = useState<string>();

  const cargar = useCallback(async () => {
    if (!userId) return;
    try {
      setResumen(await obtenerMisEntregas(userId));
      setError(undefined);
    } catch (e) {
      setError(e instanceof Error ? e.message : 'No se pudieron cargar tus entregas.');
    }
  }, [userId]);

  useEffect(() => {
    cargar().finally(() => setCargando(false));
  }, [cargar, vueltas]);

  const onRefrescar = async () => {
    setRefrescando(true);
    await cargar();
    setRefrescando(false);
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
      data={resumen?.entregas ?? []}
      keyExtractor={(e) => e.id}
      contentContainerStyle={styles.lista}
      refreshControl={<RefreshControl refreshing={refrescando} onRefresh={onRefrescar} />}
      ListHeaderComponent={
        <View>
          {error ? <Text style={styles.error}>{error}</Text> : null}
          {resumen ? (
            <View style={styles.resumen}>
              <View style={styles.dato}>
                <Text style={styles.valor}>{formatearPrecio(resumen.gananciaEstimada)}</Text>
                <Text style={styles.etiqueta}>Ganado (estimado, 80 % de la tarifa)</Text>
              </View>
              <View style={styles.dato}>
                <Text style={styles.valor}>{formatearPrecio(resumen.efectivoCobrado)}</Text>
                <Text style={styles.etiqueta}>Efectivo cobrado</Text>
              </View>
              <View style={styles.dato}>
                <Text style={styles.valor}>{resumen.entregas.length}</Text>
                <Text style={styles.etiqueta}>Entregas</Text>
              </View>
            </View>
          ) : null}
        </View>
      }
      ListEmptyComponent={error ? undefined : <Text style={styles.vacio}>Aún no tienes entregas cerradas</Text>}
      renderItem={({ item }) => (
        <View style={styles.tarjeta}>
          <View style={styles.encabezado}>
            <Text style={styles.numero}>Pedido #{item.numero}</Text>
            <Text style={styles.fecha}>{formatearFecha(item.fecha)}</Text>
          </View>
          <Text style={styles.meta}>Recogido en: {item.comercio}</Text>
          <Text style={styles.meta}>Entregado en: {item.puntoEntrega}</Text>
          <Text style={styles.meta}>Cobrado: {formatearPrecio(item.cobrado)}</Text>
        </View>
      )}
    />
  );
}

const styles = StyleSheet.create({
  centro: { flex: 1, alignItems: 'center', justifyContent: 'center', backgroundColor: colors.background },
  lista: { padding: spacing.md, backgroundColor: colors.background },
  error: { marginBottom: spacing.md, textAlign: 'center', fontSize: fontSize.md, color: colors.danger },
  vacio: { marginTop: spacing.xl, textAlign: 'center', fontSize: fontSize.lg, color: colors.textMuted },
  resumen: {
    flexDirection: 'row',
    gap: spacing.sm,
    marginBottom: spacing.md,
  },
  dato: {
    flex: 1,
    padding: spacing.sm,
    alignItems: 'center',
    borderWidth: 1,
    borderColor: colors.primary,
    borderRadius: radius.sm,
  },
  valor: { fontSize: fontSize.lg, fontWeight: fontWeight.bold, color: colors.primary },
  etiqueta: { marginTop: spacing.xs, textAlign: 'center', fontSize: fontSize.sm, color: colors.textMuted },
  tarjeta: { padding: spacing.md, marginBottom: spacing.md, backgroundColor: colors.surface, borderRadius: radius.md },
  encabezado: { flexDirection: 'row', justifyContent: 'space-between' },
  numero: { fontSize: fontSize.lg, fontWeight: fontWeight.bold, color: colors.text },
  fecha: { fontSize: fontSize.md, color: colors.textMuted },
  meta: { marginTop: spacing.xs, fontSize: fontSize.md, color: colors.textMuted },
});
