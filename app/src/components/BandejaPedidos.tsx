import { useCallback, useEffect, useState } from 'react';
import {
  ActivityIndicator,
  Alert,
  FlatList,
  Pressable,
  RefreshControl,
  StyleSheet,
  Text,
  View,
} from 'react-native';
import {
  listarPedidosComercio,
  marcarListoParaRecoger,
  puedeMarcarListo,
} from '../services/pedidosService';
import { colors, fontSize, fontWeight, radius, spacing } from '../theme';
import { EstadoPedido, Pedido } from '../types';
import { formatearHora, formatearPrecio } from '../utils/format';

const colorEstado: Record<EstadoPedido, string> = {
  Creado: colors.primary,
  Asignado: colors.warning,
  'En Camino': colors.warning,
  Entregado: colors.success,
  Cerrado: colors.textMuted,
  Cancelado: colors.danger,
};

type Props = {
  comercioId: string;
};

export default function BandejaPedidos({ comercioId }: Props) {
  const [pedidos, setPedidos] = useState<Pedido[]>([]);
  const [cargando, setCargando] = useState(true);
  const [refrescando, setRefrescando] = useState(false);

  const cargar = useCallback(async () => {
    setPedidos(await listarPedidosComercio(comercioId));
  }, [comercioId]);

  useEffect(() => {
    cargar().finally(() => setCargando(false));
  }, [cargar]);

  const onRefrescar = async () => {
    setRefrescando(true);
    await cargar();
    setRefrescando(false);
  };

  const confirmarListo = (pedido: Pedido) => {
    Alert.alert(
      `Pedido #${pedido.numero}`,
      '¿Marcarlo como listo para recoger? Se mostrará así al domiciliario.',
      [
        { text: 'Cancelar', style: 'cancel' },
        {
          text: 'Listo para recoger',
          onPress: async () => {
            await marcarListoParaRecoger(pedido.id);
            await cargar();
          },
        },
      ]
    );
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
      ListEmptyComponent={<Text style={styles.vacio}>Aún no hay pedidos</Text>}
      renderItem={({ item }) => (
        <View style={styles.tarjeta}>
          <View style={styles.encabezado}>
            <Text style={styles.numero}>Pedido #{item.numero}</Text>
            <Text style={[styles.estado, { color: colorEstado[item.estado] }]}>
              {item.estado}
            </Text>
          </View>
          <Text style={styles.meta}>
            {item.solicitante} · {formatearHora(item.creadoEn)}
          </Text>

          <View style={styles.productos}>
            {item.items.map((i) => (
              <Text key={i.nombre} style={styles.producto}>
                {i.cantidad} × {i.nombre}
              </Text>
            ))}
          </View>

          <View style={styles.pie}>
            <Text style={styles.total}>{formatearPrecio(item.total)}</Text>
            {item.listoParaRecoger ? (
              <Text style={styles.listo}>Listo para recoger</Text>
            ) : puedeMarcarListo(item) ? (
              <Pressable style={styles.boton} onPress={() => confirmarListo(item)}>
                <Text style={styles.textoBoton}>Listo para recoger</Text>
              </Pressable>
            ) : null}
          </View>
        </View>
      )}
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
  vacio: {
    marginTop: spacing.xl,
    textAlign: 'center',
    fontSize: fontSize.lg,
    color: colors.textMuted,
  },
  tarjeta: {
    padding: spacing.md,
    marginBottom: spacing.md,
    backgroundColor: colors.surface,
    borderRadius: radius.md,
  },
  encabezado: {
    flexDirection: 'row',
    justifyContent: 'space-between',
  },
  numero: {
    fontSize: fontSize.lg,
    fontWeight: fontWeight.bold,
    color: colors.text,
  },
  estado: {
    fontSize: fontSize.md,
    fontWeight: fontWeight.bold,
  },
  meta: {
    marginTop: spacing.xs,
    fontSize: fontSize.md,
    color: colors.textMuted,
  },
  productos: {
    marginVertical: spacing.sm,
  },
  producto: {
    fontSize: fontSize.md,
    color: colors.text,
  },
  pie: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
  },
  total: {
    fontSize: fontSize.lg,
    fontWeight: fontWeight.bold,
    color: colors.primary,
  },
  listo: {
    fontSize: fontSize.md,
    fontWeight: fontWeight.bold,
    color: colors.success,
  },
  boton: {
    paddingVertical: spacing.sm,
    paddingHorizontal: spacing.md,
    borderRadius: radius.sm,
    backgroundColor: colors.primary,
  },
  textoBoton: {
    fontSize: fontSize.md,
    fontWeight: fontWeight.bold,
    color: colors.white,
  },
});