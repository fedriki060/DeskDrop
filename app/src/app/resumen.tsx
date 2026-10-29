import { Ionicons } from '@expo/vector-icons';
import { useRouter } from 'expo-router';
import { useState } from 'react';
import { Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';
import AvisoEmergente from '../components/AvisoEmergente';
import BotonPrimario from '../components/BotonPrimario';
import { useAuth } from '../context/AuthContext';
import { useCarrito } from '../context/CarritoContext';
import { crearPedido, TARIFA_DOMICILIO } from '../services/checkoutService';
import { colors, fontSize, fontWeight, radius, spacing } from '../theme';
import { formatearPrecio } from '../utils/format';

export default function Resumen() {
  const router = useRouter();
  const { usuario } = useAuth();
  const {
    items,
    comercioId,
    total: subtotal,
    totalUnidades,
    puntoEntrega,
    vaciar,
  } = useCarrito();
  const [error, setError] = useState('');
  const [enviando, setEnviando] = useState(false);
  const [numeroCreado, setNumeroCreado] = useState<number>();

  const totalPagar = subtotal + TARIFA_DOMICILIO;

  const onHacerPedido = async () => {
    if (!puntoEntrega) {
      setError('Elige el lugar de entrega');
      return;
    }
    if (!comercioId) return;

    setError('');
    setEnviando(true);
    const { numero } = await crearPedido({
      solicitante: usuario ?? 'Solicitante',
      comercioId,
      items: items.map((i) => ({
        nombre: i.producto.nombre,
        cantidad: i.cantidad,
        precio: i.producto.precio,
      })),
    });
    setEnviando(false);
    setNumeroCreado(numero);
  };

  const onCerrarAviso = () => {
    setNumeroCreado(undefined);
    router.replace('/');
    vaciar();
  };

  if (items.length === 0 && numeroCreado === undefined) {
    return (
      <View style={styles.vacio}>
        <Text style={styles.vacioTexto}>Tu carrito está vacío</Text>
      </View>
    );
  }

  return (
    <View style={styles.flex}>
      <ScrollView contentContainerStyle={styles.container}>
        <Pressable style={styles.fila} onPress={() => router.push('/ubicacion')}>
          <View style={styles.filaTexto}>
            <Text style={styles.etiqueta}>Lugar de entrega</Text>
            <Text style={[styles.valor, !puntoEntrega && styles.valorPendiente]}>
              {puntoEntrega ? puntoEntrega.nombre : 'Agregar lugar de entrega'}
            </Text>
          </View>
          <Ionicons name="chevron-forward" size={20} color={colors.textMuted} />
        </Pressable>
        {error !== '' && <Text style={styles.error}>{error}</Text>}

        <View style={styles.fila}>
          <View style={styles.filaTexto}>
            <Text style={styles.etiqueta}>Pago</Text>
            <Text style={styles.valor}>Efectivo, pagas al recibir</Text>
          </View>
        </View>

        <Text style={styles.seccion}>Productos</Text>
        {items.map((i) => (
          <View key={i.producto.id} style={styles.producto}>
            <View style={styles.filaTexto}>
              <Text style={styles.nombre}>{i.producto.nombre}</Text>
              <Text style={styles.detalle}>
                {i.cantidad} × {formatearPrecio(i.producto.precio)}
              </Text>
            </View>
            <Text style={styles.precio}>
              {formatearPrecio(i.cantidad * i.producto.precio)}
            </Text>
          </View>
        ))}

        <View style={styles.totales}>
          <View style={styles.lineaTotal}>
            <Text style={styles.etiquetaTotal}>Subtotal ({totalUnidades})</Text>
            <Text style={styles.valorTotal}>{formatearPrecio(subtotal)}</Text>
          </View>
          <View style={styles.lineaTotal}>
            <Text style={styles.etiquetaTotal}>Tarifa de domicilio</Text>
            <Text style={styles.valorTotal}>{formatearPrecio(TARIFA_DOMICILIO)}</Text>
          </View>
          <View style={styles.lineaTotal}>
            <Text style={styles.totalFinal}>Total a pagar</Text>
            <Text style={styles.totalFinal}>{formatearPrecio(totalPagar)}</Text>
          </View>
        </View>
      </ScrollView>

      <View style={styles.pie}>
        <BotonPrimario
          titulo={enviando ? 'Enviando pedido...' : 'Hacer pedido'}
          deshabilitado={enviando}
          onPress={onHacerPedido}
        />
      </View>

      <AvisoEmergente
        visible={numeroCreado !== undefined}
        mensaje={`Pedido #${numeroCreado} creado. Ya lo recibió el comercio.`}
        onCerrar={onCerrarAviso}
      />
    </View>
  );
}

const styles = StyleSheet.create({
  flex: {
    flex: 1,
    backgroundColor: colors.background,
  },
  container: {
    padding: spacing.md,
  },
  vacio: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.background,
  },
  vacioTexto: {
    fontSize: fontSize.lg,
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
  filaTexto: {
    flex: 1,
  },
  etiqueta: {
    fontSize: fontSize.sm,
    fontWeight: fontWeight.bold,
    color: colors.textMuted,
  },
  valor: {
    marginTop: spacing.xs,
    fontSize: fontSize.lg,
    color: colors.text,
  },
  valorPendiente: {
    color: colors.primary,
  },
  error: {
    marginBottom: spacing.sm,
    fontSize: fontSize.md,
    color: colors.danger,
  },
  seccion: {
    marginTop: spacing.md,
    marginBottom: spacing.sm,
    fontSize: fontSize.lg,
    fontWeight: fontWeight.bold,
    color: colors.primary,
  },
  producto: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingVertical: spacing.sm,
    borderBottomWidth: 1,
    borderBottomColor: colors.border,
  },
  nombre: {
    fontSize: fontSize.lg,
    color: colors.text,
  },
  detalle: {
    marginTop: spacing.xs,
    fontSize: fontSize.md,
    color: colors.textMuted,
  },
  precio: {
    fontSize: fontSize.lg,
    fontWeight: fontWeight.bold,
    color: colors.text,
  },
  totales: {
    marginTop: spacing.lg,
  },
  lineaTotal: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    marginBottom: spacing.sm,
  },
  etiquetaTotal: {
    fontSize: fontSize.md,
    color: colors.textMuted,
  },
  valorTotal: {
    fontSize: fontSize.md,
    color: colors.text,
  },
  totalFinal: {
    marginTop: spacing.sm,
    fontSize: fontSize.xl,
    fontWeight: fontWeight.bold,
    color: colors.primary,
  },
  pie: {
    padding: spacing.md,
    borderTopWidth: 1,
    borderTopColor: colors.border,
    backgroundColor: colors.background,
  },
});