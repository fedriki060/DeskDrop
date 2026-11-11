import { useCallback, useEffect, useState } from 'react';
import {
  ActivityIndicator,
  FlatList,
  Pressable,
  RefreshControl,
  StyleSheet,
  Switch,
  Text,
  View,
} from 'react-native';
import { Alert } from '../utils/alerta';
import { useComercio } from '../context/ComercioContext';
import { useVueltaAPrimerPlano } from '../hooks/useVueltaAPrimerPlano';
import {
  cancelarPedido,
  escucharPedidosComercio,
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

type Pestana = 'activos' | 'historial';
const puedeRechazar = (p: Pedido) => p.estado === 'Creado' || p.estado === 'Asignado';
const ESTADOS_ACTIVOS: EstadoPedido[] = ['Creado', 'Asignado', 'En Camino', 'Entregado'];

export default function BandejaPedidos({ comercioId }: Props) {
  const [pedidos, setPedidos] = useState<Pedido[]>([]);
  const [cargando, setCargando] = useState(true);
  const [refrescando, setRefrescando] = useState(false);
  const [error, setError] = useState<string>();
  const [pestana, setPestana] = useState<Pestana>('activos');
  const { comercio, cambiarRecibiendo } = useComercio();
  const vueltas = useVueltaAPrimerPlano();

  const cargar = useCallback(async () => {
    try {
      setPedidos(await listarPedidosComercio(comercioId));
      setError(undefined);
    } catch (e) {
      setError(e instanceof Error ? e.message : 'No se pudieron cargar los pedidos.');
    }
  }, [comercioId]);

  useEffect(() => {
    cargar().finally(() => setCargando(false));
  }, [cargar, vueltas]);

  // Pedido nuevo o cambio de estado: se recarga la lista sin que el comercio tenga que deslizar
  useEffect(() => escucharPedidosComercio(comercioId, cargar), [comercioId, cargar, vueltas]);

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
            try {
              await marcarListoParaRecoger(pedido.id);
            } catch (e) {
              Alert.alert('No se pudo marcar', e instanceof Error ? e.message : 'Intenta de nuevo.');
            }
            await cargar();
          },
        },
      ]
    );
  };

  const rechazar = (pedido: Pedido) => {
    const ejecutar = async (motivo: string) => {
      const error = await cancelarPedido(pedido.id, motivo);
      if (error) Alert.alert('No se pudo rechazar', error);
      await cargar();
    };
    Alert.alert(
      `Rechazar pedido #${pedido.numero}`,
      'El pedido se cancela, el inventario se repone y el cliente queda avisado. ¿Cuál es el motivo?',
      [
        { text: 'No rechazar', style: 'cancel' },
        { text: 'Sin inventario', style: 'destructive', onPress: () => ejecutar('Sin inventario') },
        { text: 'Otro motivo', style: 'destructive', onPress: () => ejecutar('Rechazado por el comercio') },
      ]
    );
  };

  const onCambiarRecibiendo = async (recibiendo: boolean) => {
    if (!(await cambiarRecibiendo(recibiendo))) {
      Alert.alert('No se pudo cambiar', 'Revisa tu conexión e inténtalo de nuevo.');
    }
  };

  const visibles = pedidos.filter((p) => ESTADOS_ACTIVOS.includes(p.estado) === (pestana === 'activos'));

  if (cargando) {
    return (
      <View style={styles.centro}>
        <ActivityIndicator color={colors.primary} />
      </View>
    );
  }

  return (
    <FlatList
      data={visibles}
      keyExtractor={(p) => p.id}
      contentContainerStyle={styles.lista}
      refreshControl={<RefreshControl refreshing={refrescando} onRefresh={onRefrescar} />}
      ListHeaderComponent={
        <View>
          {comercio ? (
            <View style={styles.filaRecibiendo}>
              <View style={styles.textoRecibiendo}>
                <Text style={styles.tituloRecibiendo}>Recibiendo pedidos</Text>
                <Text style={styles.ayudaRecibiendo}>
                  {comercio.activo
                    ? 'Tu tienda aparece en el catálogo.'
                    : 'Cerrada: no aparece ni recibe pedidos nuevos.'}
                </Text>
              </View>
              <Switch
                value={comercio.activo}
                onValueChange={onCambiarRecibiendo}
                trackColor={{ false: colors.border, true: colors.primary }}
              />
            </View>
          ) : null}
          <View style={styles.pestanas}>
            {(['activos', 'historial'] as Pestana[]).map((p) => (
              <Pressable
                key={p}
                style={[styles.pestana, pestana === p && styles.pestanaActiva]}
                onPress={() => setPestana(p)}
              >
                <Text style={[styles.textoPestana, pestana === p && styles.textoPestanaActiva]}>
                  {p === 'activos' ? 'Activos' : 'Historial'}
                </Text>
              </Pressable>
            ))}
          </View>
          {error ? <Text style={styles.error}>{error}</Text> : null}
        </View>
      }
      ListEmptyComponent={
        error ? undefined : (
          <Text style={styles.vacio}>
            {pestana === 'activos' ? 'No hay pedidos activos' : 'Aún no hay pedidos terminados'}
          </Text>
        )
      }
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
          {item.repartidor ? <Text style={styles.meta}>Domiciliario: {item.repartidor}</Text> : null}

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
          {puedeRechazar(item) && (
            <Pressable onPress={() => rechazar(item)} hitSlop={8}>
              <Text style={styles.rechazar}>Rechazar pedido</Text>
            </Pressable>
          )}
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
  filaRecibiendo: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    padding: spacing.md,
    marginBottom: spacing.md,
    borderWidth: 1,
    borderColor: colors.primary,
    borderRadius: radius.sm,
  },
  textoRecibiendo: { flex: 1, marginRight: spacing.sm },
  tituloRecibiendo: { fontSize: fontSize.lg, fontWeight: fontWeight.bold, color: colors.primary },
  ayudaRecibiendo: { marginTop: spacing.xs, fontSize: fontSize.sm, color: colors.textMuted },
  pestanas: { flexDirection: 'row', marginBottom: spacing.md },
  pestana: {
    flex: 1,
    padding: spacing.sm,
    alignItems: 'center',
    borderBottomWidth: 2,
    borderBottomColor: colors.border,
  },
  pestanaActiva: { borderBottomColor: colors.primary },
  textoPestana: { fontSize: fontSize.md, color: colors.textMuted },
  textoPestanaActiva: { fontWeight: fontWeight.bold, color: colors.primary },
  error: {
    marginBottom: spacing.md,
    textAlign: 'center',
    fontSize: fontSize.md,
    color: colors.danger,
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
  rechazar: { marginTop: spacing.sm, textAlign: 'right', fontSize: fontSize.md, color: colors.danger },
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