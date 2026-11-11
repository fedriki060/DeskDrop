import { useCallback, useEffect, useState } from 'react';
import { ActivityIndicator, FlatList, Pressable, RefreshControl, StyleSheet, Text, View } from 'react-native';
import { useAuth } from '../context/AuthContext';
import { useVueltaAPrimerPlano } from '../hooks/useVueltaAPrimerPlano';
import { escucharMisPedidos, obtenerHistorial, PedidoHistorial } from '../services/seguimientoService';
import { colors, fontSize, fontWeight, radius, spacing } from '../theme';
import { EstadoPedido } from '../types';
import { formatearFecha, formatearPrecio } from '../utils/format';

const colorEstado: Record<EstadoPedido, string> = {
  Creado: colors.primary,
  Asignado: colors.warning,
  'En Camino': colors.warning,
  Entregado: colors.success,
  Cerrado: colors.textMuted,
  Cancelado: colors.danger,
};

export default function ListaHistorial() {
  const { perfil } = useAuth();
  const userId = perfil?.id;
  const vueltas = useVueltaAPrimerPlano();
  const [pedidos, setPedidos] = useState<PedidoHistorial[]>([]);
  const [cargando, setCargando] = useState(true);
  const [refrescando, setRefrescando] = useState(false);
  const [error, setError] = useState<string>();
  const [abierto, setAbierto] = useState<string>();

  const cargar = useCallback(async () => {
    if (!userId) return;
    try {
      setPedidos(await obtenerHistorial(userId));
      setError(undefined);
    } catch (e) {
      setError(e instanceof Error ? e.message : 'No se pudo cargar tu historial.');
    }
  }, [userId]);

  useEffect(() => {
    cargar().finally(() => setCargando(false));
  }, [cargar, vueltas]);
  useEffect(
    () => (userId ? escucharMisPedidos(userId, cargar) : undefined),
    [userId, cargar, vueltas]
  );

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
      data={pedidos}
      keyExtractor={(p) => p.id}
      contentContainerStyle={styles.lista}
      refreshControl={<RefreshControl refreshing={refrescando} onRefresh={onRefrescar} />}
      ListHeaderComponent={error ? <Text style={styles.error}>{error}</Text> : undefined}
      ListEmptyComponent={error ? undefined : <Text style={styles.vacio}>Aún no has hecho pedidos</Text>}
      renderItem={({ item }) => (
        <Pressable style={styles.tarjeta} onPress={() => setAbierto(abierto === item.id ? undefined : item.id)}>
          <View style={styles.encabezado}>
            <Text style={styles.comercio}>{item.comercio}</Text>
            <Text style={[styles.estado, { color: colorEstado[item.estado] }]}>{item.estado}</Text>
          </View>
          <Text style={styles.meta}>
            Pedido #{item.numero} · {formatearFecha(item.creadoEn)}
          </Text>
          <Text style={styles.total}>{formatearPrecio(item.total)}</Text>
          {abierto === item.id && (
            <View style={styles.detalle}>
              {item.items.map((i, n) => (
                <Text key={`${i.nombre}-${n}`} style={styles.producto}>
                  {i.cantidad} × {i.nombre}
                </Text>
              ))}
            </View>
          )}
        </Pressable>
      )}
    />
  );
}

const styles = StyleSheet.create({
  centro: { flex: 1, alignItems: 'center', justifyContent: 'center', backgroundColor: colors.background },
  lista: { padding: spacing.md, backgroundColor: colors.background },
  error: { marginBottom: spacing.md, textAlign: 'center', fontSize: fontSize.md, color: colors.danger },
  vacio: { marginTop: spacing.xl, textAlign: 'center', fontSize: fontSize.lg, color: colors.textMuted },
  tarjeta: { padding: spacing.md, marginBottom: spacing.md, backgroundColor: colors.surface, borderRadius: radius.md },
  encabezado: { flexDirection: 'row', justifyContent: 'space-between' },
  comercio: { fontSize: fontSize.lg, fontWeight: fontWeight.bold, color: colors.text },
  estado: { fontSize: fontSize.md, fontWeight: fontWeight.bold },
  meta: { marginTop: spacing.xs, fontSize: fontSize.md, color: colors.textMuted },
  total: { marginTop: spacing.xs, fontSize: fontSize.lg, fontWeight: fontWeight.bold, color: colors.primary },
  detalle: { marginTop: spacing.sm, paddingTop: spacing.sm, borderTopWidth: 1, borderTopColor: colors.border },
  producto: { fontSize: fontSize.md, color: colors.text },
});
