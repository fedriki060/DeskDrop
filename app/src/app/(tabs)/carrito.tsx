import { Ionicons } from '@expo/vector-icons';
import { Alert, FlatList, Pressable, StyleSheet, Text, View } from 'react-native';
import { useCarrito } from '../../context/CarritoContext';
import { colors, fontSize, fontWeight, radius, spacing } from '../../theme';
import { formatearPrecio } from '../../utils/format';

export default function Carrito() {
  const { items, total, totalUnidades, cambiarCantidad, quitar } = useCarrito();

  if (items.length === 0) {
    return (
      <View style={styles.vacio}>
        <Ionicons name="cart-outline" size={64} color={colors.textMuted} />
        <Text style={styles.vacioTexto}>Tu carrito está vacío</Text>
      </View>
    );
  }

  return (
    <View style={styles.container}>
      <FlatList
        data={items}
        keyExtractor={(i) => i.producto.id}
        contentContainerStyle={styles.lista}
        renderItem={({ item }) => (
          <View style={styles.fila}>
            <View style={styles.info}>
              <Text style={styles.nombre}>{item.producto.nombre}</Text>
              <Text style={styles.unitario}>
                {formatearPrecio(item.producto.precio)} c/u
              </Text>
              <View style={styles.selector}>
                <Pressable
                  style={styles.botonCantidad}
                  onPress={() => cambiarCantidad(item.producto.id, item.cantidad - 1)}
                >
                  <Ionicons name="remove" size={18} color={colors.white} />
                </Pressable>
                <Text style={styles.cantidad}>{item.cantidad}</Text>
                <Pressable
                  style={[
                    styles.botonCantidad,
                    item.cantidad >= item.producto.inventario && styles.botonInactivo,
                  ]}
                  disabled={item.cantidad >= item.producto.inventario}
                  onPress={() => cambiarCantidad(item.producto.id, item.cantidad + 1)}
                >
                  <Ionicons name="add" size={18} color={colors.white} />
                </Pressable>
              </View>
            </View>
            <View style={styles.derecha}>
              <Text style={styles.precio}>
                {formatearPrecio(item.cantidad * item.producto.precio)}
              </Text>
              <Pressable onPress={() => quitar(item.producto.id)} hitSlop={8}>
                <Ionicons name="trash-outline" size={22} color={colors.danger} />
              </Pressable>
            </View>
          </View>
        )}
      />

      <View style={styles.resumen}>
        <View style={styles.filaTotal}>
          <Text style={styles.etiqueta}>Subtotal ({totalUnidades})</Text>
          <Text style={styles.total}>{formatearPrecio(total)}</Text>
        </View>
        <Pressable
          style={styles.botonPagar}
          onPress={() =>
            Alert.alert('Próximamente', 'La confirmación del pedido se construye en T-027.')
          }
        >
          <Text style={styles.textoPagar}>Ir a pagar</Text>
        </Pressable>
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: colors.background,
  },
  lista: {
    padding: spacing.md,
  },
  vacio: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.background,
  },
  vacioTexto: {
    marginTop: spacing.md,
    fontSize: fontSize.lg,
    color: colors.textMuted,
  },
  fila: {
    flexDirection: 'row',
    padding: spacing.md,
    marginBottom: spacing.sm,
    backgroundColor: colors.surface,
    borderRadius: radius.md,
  },
  info: {
    flex: 1,
  },
  nombre: {
    fontSize: fontSize.lg,
    fontWeight: fontWeight.bold,
    color: colors.text,
  },
  unitario: {
    marginTop: spacing.xs,
    fontSize: fontSize.md,
    color: colors.textMuted,
  },
  selector: {
    flexDirection: 'row',
    alignItems: 'center',
    marginTop: spacing.sm,
  },
  botonCantidad: {
    width: 32,
    height: 32,
    borderRadius: 16,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.primary,
  },
  botonInactivo: {
    opacity: 0.4,
  },
  cantidad: {
    minWidth: 40,
    textAlign: 'center',
    fontSize: fontSize.lg,
    fontWeight: fontWeight.bold,
    color: colors.text,
  },
  derecha: {
    alignItems: 'flex-end',
    justifyContent: 'space-between',
  },
  precio: {
    fontSize: fontSize.lg,
    fontWeight: fontWeight.bold,
    color: colors.primary,
  },
  resumen: {
    padding: spacing.md,
    borderTopWidth: 1,
    borderTopColor: colors.border,
    backgroundColor: colors.background,
  },
  filaTotal: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    marginBottom: spacing.md,
  },
  etiqueta: {
    fontSize: fontSize.lg,
    color: colors.textMuted,
  },
  total: {
    fontSize: fontSize.xl,
    fontWeight: fontWeight.bold,
    color: colors.text,
  },
  botonPagar: {
    padding: spacing.md,
    alignItems: 'center',
    borderRadius: radius.md,
    backgroundColor: colors.primary,
  },
  textoPagar: {
    fontSize: fontSize.lg,
    fontWeight: fontWeight.bold,
    color: colors.white,
  },
});