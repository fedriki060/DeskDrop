import { useCallback, useEffect, useState } from 'react';
import {
  ActivityIndicator,
  Alert,
  AppState,
  Pressable,
  RefreshControl,
  SectionList,
  StyleSheet,
  Text,
  View,
} from 'react-native';
import { useAuth } from '../context/AuthContext';
import {
  aceptarPedido,
  confirmarRecogida,
  escucharPedidosDelRepartidor,
  listarMisEntregas,
  listarPedidosDisponibles,
} from '../services/entregasService';
import { colors, fontSize, fontWeight, radius, spacing } from '../theme';
import { PedidoEntrega } from '../types';
import { formatearHora, formatearPrecio } from '../utils/format';

// Lo que el domiciliario debe hacer con el dinero, según el método elegido en el checkout
function textoCobro(p: PedidoEntrega): string {
  if (p.metodoPago === 'efectivo') return `Cobrar en efectivo ${formatearPrecio(p.total)}`;
  if (p.estadoPago === 'en_custodia') return 'Pago por transferencia: retenido, se te libera al entregar. No cobres';
  return p.estadoPago === 'cobrado' || p.estadoPago === 'liberado'
    ? 'Pago por transferencia: ya pagado, no cobres'
    : 'Pago por transferencia: no cobres en efectivo';
}

export default function EntregasRepartidor() {
  const { perfil } = useAuth();
  const repartidorId = perfil?.id;
  const [disponibles, setDisponibles] = useState<PedidoEntrega[]>([]);
  const [mias, setMias] = useState<PedidoEntrega[]>([]);
  const [cargando, setCargando] = useState(true);
  const [refrescando, setRefrescando] = useState(false);
  const [ocupado, setOcupado] = useState<string>();
  const [error, setError] = useState('');

  const cargar = useCallback(async () => {
    if (!repartidorId) return;
    try {
      const [d, m] = await Promise.all([listarPedidosDisponibles(), listarMisEntregas(repartidorId)]);
      setDisponibles(d);
      setMias(m);
      setError('');
    } catch (e) {
      setError(e instanceof Error ? e.message : 'No se pudieron cargar los pedidos');
    }
  }, [repartidorId]);

  useEffect(() => {
    cargar().finally(() => setCargando(false));
  }, [cargar]);

  // En vivo: pedidos nuevos y cambios de los míos (ver nota en escucharPedidosDelRepartidor)
  useEffect(() => escucharPedidosDelRepartidor(cargar), [cargar]);

  // Al volver a la app se recarga: aquí se enteran de los pedidos que tomó otro domiciliario
  useEffect(() => {
    const suscripcion = AppState.addEventListener('change', (s) => {
      if (s === 'active') cargar();
    });
    return () => suscripcion.remove();
  }, [cargar]);

  const onRefrescar = async () => {
    setRefrescando(true);
    await cargar();
    setRefrescando(false);
  };

  const ejecutar = async (pedido: PedidoEntrega, accion: (id: string) => Promise<void>) => {
    setOcupado(pedido.id);
    try {
      await accion(pedido.id);
    } catch (e) {
      Alert.alert('No se pudo completar', e instanceof Error ? e.message : 'Intenta de nuevo.');
    } finally {
      // Con éxito o con error se recarga: si otro lo tomó antes, el pedido desaparece de la lista
      await cargar();
      setOcupado(undefined);
    }
  };

  const onAceptar = (p: PedidoEntrega) =>
    Alert.alert(`Pedido #${p.codigo}`, `¿Aceptar este pedido de ${p.comercio}?`, [
      { text: 'Cancelar', style: 'cancel' },
      { text: 'Aceptar', onPress: () => ejecutar(p, aceptarPedido) },
    ]);

  const onRecoger = (p: PedidoEntrega) =>
    Alert.alert(`Pedido #${p.codigo}`, '¿Ya recogiste el pedido en el comercio?', [
      { text: 'Todavía no', style: 'cancel' },
      { text: 'Ya lo recogí', onPress: () => ejecutar(p, confirmarRecogida) },
    ]);

  if (cargando) {
    return (
      <View style={styles.centro}>
        <ActivityIndicator color={colors.primary} />
      </View>
    );
  }

  const secciones = [
    { titulo: 'Mis entregas', data: mias, vacio: 'No tienes entregas en curso' },
    { titulo: 'Pedidos disponibles', data: disponibles, vacio: 'No hay pedidos disponibles por ahora' },
  ];

  return (
    <SectionList
      sections={secciones}
      keyExtractor={(p) => p.id}
      contentContainerStyle={styles.lista}
      refreshControl={<RefreshControl refreshing={refrescando} onRefresh={onRefrescar} />}
      ListHeaderComponent={error !== '' ? <Text style={styles.error}>{error}</Text> : undefined}
      renderSectionHeader={({ section }) => (
        <View>
          <Text style={styles.seccion}>{section.titulo}</Text>
          {section.data.length === 0 && <Text style={styles.vacio}>{section.vacio}</Text>}
        </View>
      )}
      renderItem={({ item }) => {
        const disponible = item.estado === 'Creado';
        return (
          <View style={styles.tarjeta}>
            <View style={styles.encabezado}>
              <Text style={styles.codigo}>Pedido #{item.codigo}</Text>
              <Text style={styles.estado}>{item.estado}</Text>
            </View>
            <Text style={styles.meta}>
              {item.comercio} · {formatearHora(item.creadoEn)}
            </Text>
            <Text style={styles.meta}>Entregar en: {item.puntoEntrega}</Text>
            {item.notasEntrega ? <Text style={styles.meta}>Indicaciones: {item.notasEntrega}</Text> : null}

            <View style={styles.productos}>
              {item.items.map((i, n) => (
                <Text key={`${i.nombre}-${n}`} style={styles.producto}>
                  {i.cantidad} × {i.nombre}
                </Text>
              ))}
            </View>

            <Text style={styles.cobro}>{textoCobro(item)}</Text>
            {item.listoParaRecoger && <Text style={styles.listo}>Listo para recoger en el comercio</Text>}

            <View style={styles.pie}>
              <Text style={styles.total}>{formatearPrecio(item.total)}</Text>
              {disponible ? (
                <Pressable
                  style={[styles.boton, ocupado === item.id && styles.botonInactivo]}
                  disabled={ocupado !== undefined}
                  onPress={() => onAceptar(item)}
                >
                  <Text style={styles.textoBoton}>Aceptar</Text>
                </Pressable>
              ) : item.estado === 'Asignado' ? (
                <Pressable
                  style={[styles.boton, ocupado === item.id && styles.botonInactivo]}
                  disabled={ocupado !== undefined}
                  onPress={() => onRecoger(item)}
                >
                  <Text style={styles.textoBoton}>Ya recogí el pedido</Text>
                </Pressable>
              ) : (
                <Text style={styles.espera}>Esperando confirmación del solicitante</Text>
              )}
            </View>
          </View>
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
  lista: { padding: spacing.md, backgroundColor: colors.background },
  error: { marginBottom: spacing.sm, fontSize: fontSize.md, color: colors.danger },
  seccion: {
    marginTop: spacing.md,
    marginBottom: spacing.sm,
    fontSize: fontSize.lg,
    fontWeight: fontWeight.bold,
    color: colors.primary,
  },
  vacio: { marginBottom: spacing.md, fontSize: fontSize.md, color: colors.textMuted },
  tarjeta: {
    padding: spacing.md,
    marginBottom: spacing.md,
    backgroundColor: colors.surface,
    borderRadius: radius.md,
  },
  encabezado: { flexDirection: 'row', justifyContent: 'space-between' },
  codigo: { fontSize: fontSize.lg, fontWeight: fontWeight.bold, color: colors.text },
  estado: { fontSize: fontSize.md, fontWeight: fontWeight.bold, color: colors.primary },
  meta: { marginTop: spacing.xs, fontSize: fontSize.md, color: colors.textMuted },
  productos: { marginVertical: spacing.sm },
  producto: { fontSize: fontSize.md, color: colors.text },
  cobro: { fontSize: fontSize.md, fontWeight: fontWeight.bold, color: colors.warning },
  listo: { marginTop: spacing.xs, fontSize: fontSize.md, fontWeight: fontWeight.bold, color: colors.success },
  pie: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    marginTop: spacing.sm,
  },
  total: { fontSize: fontSize.lg, fontWeight: fontWeight.bold, color: colors.primary },
  boton: {
    paddingVertical: spacing.sm,
    paddingHorizontal: spacing.md,
    borderRadius: radius.sm,
    backgroundColor: colors.primary,
  },
  botonInactivo: { opacity: 0.5 },
  textoBoton: { fontSize: fontSize.md, fontWeight: fontWeight.bold, color: colors.white },
  espera: { flex: 1, marginLeft: spacing.md, textAlign: 'right', fontSize: fontSize.md, color: colors.textMuted },
});
