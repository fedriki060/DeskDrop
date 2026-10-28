import { Ionicons } from '@expo/vector-icons';
import { useLocalSearchParams, useRouter } from 'expo-router';
import { useEffect, useState } from 'react';
import {
    ActivityIndicator,
    Alert,
    Pressable,
    StyleSheet,
    Text,
    View,
} from 'react-native';
import { useCarrito } from '../../context/CarritoContext';
import { obtenerProducto } from '../../services/catalogService';
import { colors, fontSize, fontWeight, radius, spacing } from '../../theme';
import { Producto } from '../../types';
import { formatearPrecio } from '../../utils/format';

export default function DetalleProducto() {
  const { id } = useLocalSearchParams<{ id: string }>();
  const router = useRouter();
  const { items, comercioId, agregar, vaciar } = useCarrito();
  const [producto, setProducto] = useState<Producto>();
  const [cargando, setCargando] = useState(true);
  const [cantidad, setCantidad] = useState(1);

  useEffect(() => {
    obtenerProducto(id)
      .then(setProducto)
      .finally(() => setCargando(false));
  }, [id]);

  if (cargando) {
    return (
      <View style={styles.centro}>
        <ActivityIndicator color={colors.primary} />
      </View>
    );
  }

  if (!producto) {
    return (
      <View style={styles.centro}>
        <Text style={styles.aviso}>Producto no encontrado</Text>
      </View>
    );
  }

  const enCarrito = items.find((i) => i.producto.id === producto.id)?.cantidad ?? 0;
  const disponibles = producto.inventario - enCarrito;
  const sinStock = disponibles <= 0;

  const agregarYVolver = () => {
    agregar(producto, cantidad);
    router.back();
  };

  const onAgregar = () => {
    if (comercioId && comercioId !== producto.comercioId) {
      Alert.alert(
        'Carrito de otro comercio',
        'Tu carrito tiene productos de otro comercio. ¿Quieres vaciarlo y agregar este producto?',
        [
          { text: 'Cancelar', style: 'cancel' },
          {
            text: 'Vaciar y agregar',
            style: 'destructive',
            onPress: () => {
              vaciar();
              agregarYVolver();
            },
          },
        ]
      );
      return;
    }
    agregarYVolver();
  };

  return (
    <View style={styles.container}>
      <View style={styles.contenido}>
        <Text style={styles.nombre}>{producto.nombre}</Text>
        <Text style={styles.precio}>{formatearPrecio(producto.precio)}</Text>
        <Text style={styles.descripcion}>{producto.descripcion}</Text>

        {producto.inventario === 0 ? (
          <Text style={styles.agotado}>Agotado</Text>
        ) : (
          <Text style={styles.stock}>Disponibles: {producto.inventario}</Text>
        )}
        {enCarrito > 0 && (
          <Text style={styles.stock}>Ya tienes {enCarrito} en tu carrito</Text>
        )}

        {!sinStock && (
          <View style={styles.selector}>
            <Pressable
              style={[styles.botonCantidad, cantidad <= 1 && styles.botonInactivo]}
              disabled={cantidad <= 1}
              onPress={() => setCantidad(cantidad - 1)}
            >
              <Ionicons name="remove" size={22} color={colors.white} />
            </Pressable>
            <Text style={styles.cantidad}>{cantidad}</Text>
            <Pressable
              style={[styles.botonCantidad, cantidad >= disponibles && styles.botonInactivo]}
              disabled={cantidad >= disponibles}
              onPress={() => setCantidad(cantidad + 1)}
            >
              <Ionicons name="add" size={22} color={colors.white} />
            </Pressable>
          </View>
        )}
      </View>

      <Pressable
        style={[styles.botonAgregar, sinStock && styles.botonInactivo]}
        disabled={sinStock}
        onPress={onAgregar}
      >
        <Text style={styles.textoAgregar}>
          {sinStock
            ? 'Sin unidades disponibles'
            : `Agregar al carrito · ${formatearPrecio(cantidad * producto.precio)}`}
        </Text>
      </Pressable>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    padding: spacing.lg,
    backgroundColor: colors.background,
  },
  contenido: {
    flex: 1,
  },
  centro: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.background,
  },
  aviso: {
    fontSize: fontSize.lg,
    color: colors.textMuted,
  },
  nombre: {
    fontSize: fontSize.xxl,
    fontWeight: fontWeight.bold,
    color: colors.text,
  },
  precio: {
    marginTop: spacing.sm,
    fontSize: fontSize.xl,
    fontWeight: fontWeight.bold,
    color: colors.primary,
  },
  descripcion: {
    marginTop: spacing.md,
    fontSize: fontSize.lg,
    color: colors.textMuted,
  },
  stock: {
    marginTop: spacing.md,
    fontSize: fontSize.md,
    color: colors.textMuted,
  },
  agotado: {
    marginTop: spacing.md,
    fontSize: fontSize.lg,
    fontWeight: fontWeight.bold,
    color: colors.danger,
  },
  selector: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    marginTop: spacing.xl,
  },
  botonCantidad: {
    width: 44,
    height: 44,
    borderRadius: 22,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.primary,
  },
  botonInactivo: {
    opacity: 0.4,
  },
  cantidad: {
    minWidth: 60,
    textAlign: 'center',
    fontSize: fontSize.xxl,
    fontWeight: fontWeight.bold,
    color: colors.text,
  },
  botonAgregar: {
    padding: spacing.md,
    alignItems: 'center',
    borderRadius: radius.md,
    backgroundColor: colors.primary,
  },
  textoAgregar: {
    fontSize: fontSize.lg,
    fontWeight: fontWeight.bold,
    color: colors.white,
  },
});