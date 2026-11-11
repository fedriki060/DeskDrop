import { Ionicons } from '@expo/vector-icons';
import { StyleSheet, Text, View } from 'react-native';
import { SeguimientoPedido as Pedido } from '../services/seguimientoService';
import { colors, fontSize, fontWeight, radius, spacing } from '../theme';
import { EstadoPedido } from '../types';
import { formatearPrecio } from '../utils/format';
import CodigoEntrega from './CodigoEntrega';

const PASOS: { estado: EstadoPedido; titulo: string }[] = [
  { estado: 'Creado', titulo: 'Pedido recibido' },
  { estado: 'Asignado', titulo: 'Domiciliario asignado' },
  { estado: 'En Camino', titulo: 'En camino' },
  { estado: 'Entregado', titulo: 'Entregado' },
  { estado: 'Cerrado', titulo: 'Pagado' },
];

function mensajeDe(p: Pedido): string {
  const quien = p.repartidor ?? 'Un domiciliario';
  switch (p.estado) {
    case 'Creado':
      return 'Buscando un domiciliario. Si nadie lo toma en 10 minutos, se cancela.';
    case 'Asignado':
      return p.listoParaRecoger
        ? `${quien} va a recoger tu pedido, que ya está listo.`
        : `${quien} aceptó tu pedido. El comercio lo está preparando.`;
    case 'En Camino':
      return `${quien} va hacia ${p.puntoEntrega}.`;
    case 'Entregado':
      return 'Tu pedido fue entregado. Falta el pago en efectivo al domiciliario.';
    case 'Cerrado':
      return 'Pedido cerrado. ¡Gracias por usar DeskDrop!';
    case 'Cancelado':
      return 'Tu pedido se canceló. Puedes hacer uno nuevo cuando quieras.';
  }
}

export default function SeguimientoPedido({ pedido }: { pedido: Pedido }) {
  const cancelado = pedido.estado === 'Cancelado';
  const indice = PASOS.findIndex((p) => p.estado === pedido.estado);

  return (
    <View>
      <View style={styles.encabezado}>
        <Text style={styles.numero}>Pedido #{pedido.numero}</Text>
        <Text style={[styles.estado, cancelado && { color: colors.danger }]}>{pedido.estado}</Text>
      </View>
      <Text style={styles.mensaje}>{mensajeDe(pedido)}</Text>

      {!cancelado && (
        <View style={styles.pasos}>
          {PASOS.map((paso, i) => {
            const hecho = i <= indice;
            return (
              <View key={paso.estado} style={styles.paso}>
                <Ionicons
                  name={hecho ? 'checkmark-circle' : 'ellipse-outline'}
                  size={22}
                  color={hecho ? colors.success : colors.border}
                />
                <Text style={[styles.textoPaso, hecho && styles.textoPasoHecho]}>{paso.titulo}</Text>
              </View>
            );
          })}
        </View>
      )}

      {(pedido.estado === 'Asignado' || pedido.estado === 'En Camino') && (
        <CodigoEntrega pedidoId={pedido.id} />
      )}

      <View style={styles.detalle}>
        <Text style={styles.meta}>Comercio: {pedido.comercio}</Text>
        <Text style={styles.meta}>Entrega en: {pedido.puntoEntrega}</Text>
        {pedido.items.map((i, n) => (
          <Text key={`${i.nombre}-${n}`} style={styles.producto}>
            {i.cantidad} × {i.nombre}
          </Text>
        ))}
        <Text style={styles.total}>Total: {formatearPrecio(pedido.total)}</Text>
        {pedido.pago && pedido.estado !== 'Cancelado' ? (
          <Text style={styles.meta}>
            {pedido.pago.estado === 'cobrado'
              ? 'Pago en efectivo: cobrado'
              : `Efectivo: pagas ${formatearPrecio(Number(pedido.pago.monto))} al domiciliario`}
          </Text>
        ) : null}
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  encabezado: { flexDirection: 'row', justifyContent: 'space-between', marginBottom: spacing.xs },
  numero: { fontSize: fontSize.xl, fontWeight: fontWeight.bold, color: colors.text },
  estado: { fontSize: fontSize.lg, fontWeight: fontWeight.bold, color: colors.primary },
  mensaje: { marginBottom: spacing.md, fontSize: fontSize.md, color: colors.textMuted },
  pasos: { marginBottom: spacing.md },
  paso: { flexDirection: 'row', alignItems: 'center', paddingVertical: spacing.xs },
  textoPaso: { marginLeft: spacing.sm, fontSize: fontSize.md, color: colors.textMuted },
  textoPasoHecho: { color: colors.text },
  detalle: { padding: spacing.md, borderRadius: radius.md, backgroundColor: colors.surface },
  meta: { marginBottom: spacing.xs, fontSize: fontSize.md, color: colors.textMuted },
  producto: { fontSize: fontSize.md, color: colors.text },
  total: { marginTop: spacing.sm, fontSize: fontSize.lg, fontWeight: fontWeight.bold, color: colors.primary },
});
