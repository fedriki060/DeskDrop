import { Ionicons } from '@expo/vector-icons';
import { useLocalSearchParams } from 'expo-router';
import { useCallback, useEffect, useState } from 'react';
import { ActivityIndicator, AppState, ScrollView, StyleSheet, Text, View } from 'react-native';
import AvisoEmergente from '../../components/AvisoEmergente';
import BotonPrimario from '../../components/BotonPrimario';
import {
  confirmarRecepcion,
  DetallePedido,
  escucharPedido,
  obtenerPedido,
} from '../../services/seguimientoService';
import { colors, fontSize, fontWeight, radius, spacing } from '../../theme';
import { EstadoPedido } from '../../types';
import { formatearPrecio } from '../../utils/format';

// Línea de estados del pedido (T-047). Cerrado cuenta como entregado; Cancelado se muestra aparte.
const PASOS: { estado: EstadoPedido; titulo: string; detalle: string }[] = [
  { estado: 'Creado', titulo: 'Pedido creado', detalle: 'Esperando un domiciliario' },
  { estado: 'Asignado', titulo: 'Domiciliario asignado', detalle: 'Va a recoger tu pedido' },
  { estado: 'En Camino', titulo: 'En camino', detalle: 'Tu pedido va hacia ti' },
  { estado: 'Entregado', titulo: 'Entregado', detalle: 'Pedido recibido' },
];

function pasoActual(estado: EstadoPedido): number {
  if (estado === 'Cerrado') return PASOS.length - 1;
  return PASOS.findIndex((p) => p.estado === estado);
}

export default function Seguimiento() {
  const { id } = useLocalSearchParams<{ id: string }>();
  const [pedido, setPedido] = useState<DetallePedido | null>();
  const [cargando, setCargando] = useState(true);
  const [error, setError] = useState('');
  const [confirmando, setConfirmando] = useState(false);
  const [aviso, setAviso] = useState('');

  const cargar = useCallback(async () => {
    try {
      setPedido(await obtenerPedido(id));
      setError('');
    } catch (e) {
      setError(e instanceof Error ? e.message : 'No se pudo cargar el pedido.');
    } finally {
      setCargando(false);
    }
  }, [id]);

  useEffect(() => {
    cargar();
  }, [cargar]);

  // En vivo: Supabase Realtime (T-046). Solo llegan cambios de estado, el resto del pedido no cambia.
  useEffect(
    () =>
      escucharPedido(id, (c) =>
        setPedido((p) =>
          p
            ? { ...p, estado: c.estado, listoParaRecoger: c.listoParaRecoger, actualizadoEn: c.actualizadoEn }
            : p
        )
      ),
    [id]
  );

  // Al volver a la app se vuelve a leer el pedido, por si se perdió algún cambio sin conexión
  useEffect(() => {
    const suscripcion = AppState.addEventListener('change', (s) => {
      if (s === 'active') cargar();
    });
    return () => suscripcion.remove();
  }, [cargar]);

  const onConfirmar = async () => {
    if (!pedido) return;
    setConfirmando(true);
    try {
      const { estado } = await confirmarRecepcion(pedido.id);
      setPedido((p) => (p ? { ...p, estado } : p));
      setAviso('¡Listo! Confirmaste que recibiste tu pedido.');
    } catch (e) {
      setAviso(e instanceof Error ? e.message : 'No se pudo confirmar la entrega.');
      cargar();
    } finally {
      setConfirmando(false);
    }
  };

  if (cargando) {
    return (
      <View style={styles.centro}>
        <ActivityIndicator color={colors.primary} />
      </View>
    );
  }

  if (!pedido) {
    return (
      <View style={styles.centro}>
        <Text style={styles.mensajeVacio}>{error || 'No encontramos este pedido.'}</Text>
      </View>
    );
  }

  const actual = pasoActual(pedido.estado);
  const cancelado = pedido.estado === 'Cancelado';

  return (
    <View style={styles.flex}>
      <ScrollView contentContainerStyle={styles.container}>
        <Text style={styles.titulo}>Pedido #{pedido.codigo}</Text>
        <Text style={styles.subtitulo}>{pedido.comercio}</Text>

        {cancelado ? (
          <View style={styles.cancelado}>
            <Ionicons name="close-circle" size={22} color={colors.danger} />
            <Text style={styles.canceladoTexto}>Este pedido fue cancelado.</Text>
          </View>
        ) : (
          <View style={styles.linea}>
            {PASOS.map((paso, i) => {
              const hecho = i <= actual;
              return (
                <View key={paso.estado} style={styles.paso}>
                  <View style={styles.columnaIcono}>
                    <Ionicons
                      name={hecho ? 'checkmark-circle' : 'ellipse-outline'}
                      size={26}
                      color={hecho ? colors.primary : colors.border}
                    />
                    {i < PASOS.length - 1 && (
                      <View style={[styles.conector, i < actual && styles.conectorHecho]} />
                    )}
                  </View>
                  <View style={styles.pasoTexto}>
                    <Text style={[styles.pasoTitulo, !hecho && styles.pasoPendiente]}>{paso.titulo}</Text>
                    {i === actual && <Text style={styles.pasoDetalle}>{paso.detalle}</Text>}
                    {i === 0 && actual <= 1 && pedido.listoParaRecoger && (
                      <Text style={styles.pasoDetalle}>El comercio ya lo tiene listo para recoger</Text>
                    )}
                  </View>
                </View>
              );
            })}
          </View>
        )}

        <View style={styles.tarjeta}>
          <Text style={styles.etiqueta}>Lugar de entrega</Text>
          <Text style={styles.valor}>{pedido.puntoEntrega}</Text>
        </View>

        <Text style={styles.seccion}>Productos</Text>
        {pedido.items.map((item, i) => (
          <View key={`${item.nombre}-${i}`} style={styles.producto}>
            <Text style={styles.productoNombre}>
              {item.cantidad} × {item.nombre}
            </Text>
            <Text style={styles.productoPrecio}>{formatearPrecio(item.cantidad * item.precioUnitario)}</Text>
          </View>
        ))}

        <View style={styles.totales}>
          <View style={styles.lineaTotal}>
            <Text style={styles.etiquetaTotal}>Subtotal</Text>
            <Text style={styles.valorTotal}>{formatearPrecio(pedido.subtotal)}</Text>
          </View>
          <View style={styles.lineaTotal}>
            <Text style={styles.etiquetaTotal}>Tarifa de domicilio</Text>
            <Text style={styles.valorTotal}>{formatearPrecio(pedido.tarifaDomicilio)}</Text>
          </View>
          <View style={styles.lineaTotal}>
            <Text style={styles.totalFinal}>Total</Text>
            <Text style={styles.totalFinal}>{formatearPrecio(pedido.total)}</Text>
          </View>
        </View>
      </ScrollView>

      {/* T-041: solo el solicitante, y solo con el pedido En Camino (la base lo vuelve a validar) */}
      {pedido.estado === 'En Camino' && (
        <View style={styles.pie}>
          <BotonPrimario
            titulo={confirmando ? 'Confirmando...' : 'Ya recibí mi pedido'}
            deshabilitado={confirmando}
            onPress={onConfirmar}
          />
        </View>
      )}

      <AvisoEmergente visible={aviso !== ''} mensaje={aviso} onCerrar={() => setAviso('')} />
    </View>
  );
}

const styles = StyleSheet.create({
  flex: { flex: 1, backgroundColor: colors.background },
  container: { padding: spacing.md },
  centro: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    padding: spacing.lg,
    backgroundColor: colors.background,
  },
  mensajeVacio: { fontSize: fontSize.lg, color: colors.textMuted, textAlign: 'center' },
  titulo: { fontSize: fontSize.xl, fontWeight: fontWeight.bold, color: colors.primary },
  subtitulo: { marginTop: spacing.xs, marginBottom: spacing.md, fontSize: fontSize.md, color: colors.textMuted },
  linea: { marginBottom: spacing.md },
  paso: { flexDirection: 'row' },
  columnaIcono: { alignItems: 'center', width: 32 },
  conector: { width: 2, flex: 1, minHeight: 24, backgroundColor: colors.border },
  conectorHecho: { backgroundColor: colors.primary },
  pasoTexto: { flex: 1, marginLeft: spacing.sm, paddingBottom: spacing.md },
  pasoTitulo: { fontSize: fontSize.lg, fontWeight: fontWeight.bold, color: colors.text },
  pasoPendiente: { color: colors.textMuted, fontWeight: fontWeight.regular },
  pasoDetalle: { marginTop: spacing.xs, fontSize: fontSize.md, color: colors.textMuted },
  cancelado: {
    flexDirection: 'row',
    alignItems: 'center',
    padding: spacing.md,
    marginBottom: spacing.md,
    borderRadius: radius.md,
    backgroundColor: colors.surface,
  },
  canceladoTexto: { marginLeft: spacing.sm, fontSize: fontSize.lg, color: colors.danger },
  tarjeta: {
    padding: spacing.md,
    marginBottom: spacing.sm,
    backgroundColor: colors.surface,
    borderRadius: radius.md,
  },
  etiqueta: { fontSize: fontSize.sm, fontWeight: fontWeight.bold, color: colors.textMuted },
  valor: { marginTop: spacing.xs, fontSize: fontSize.lg, color: colors.text },
  seccion: {
    marginTop: spacing.md,
    marginBottom: spacing.sm,
    fontSize: fontSize.lg,
    fontWeight: fontWeight.bold,
    color: colors.primary,
  },
  producto: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    paddingVertical: spacing.sm,
    borderBottomWidth: 1,
    borderBottomColor: colors.border,
  },
  productoNombre: { flex: 1, fontSize: fontSize.lg, color: colors.text },
  productoPrecio: { fontSize: fontSize.lg, fontWeight: fontWeight.bold, color: colors.text },
  totales: { marginTop: spacing.lg },
  lineaTotal: { flexDirection: 'row', justifyContent: 'space-between', marginBottom: spacing.sm },
  etiquetaTotal: { fontSize: fontSize.md, color: colors.textMuted },
  valorTotal: { fontSize: fontSize.md, color: colors.text },
  totalFinal: { marginTop: spacing.sm, fontSize: fontSize.xl, fontWeight: fontWeight.bold, color: colors.primary },
  pie: {
    padding: spacing.md,
    borderTopWidth: 1,
    borderTopColor: colors.border,
    backgroundColor: colors.background,
  },
});
