import { Ionicons } from '@expo/vector-icons';
import { useRouter } from 'expo-router';
import { useEffect, useMemo, useState } from 'react';
import { Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';
import AvisoEmergente from '../components/AvisoEmergente';
import BotonPrimario from '../components/BotonPrimario';
import { useCarrito } from '../context/CarritoContext';
import {
  crearPedido,
  ErrorPedido,
  TARIFA_DOMICILIO,
  validarCarrito,
  ValidacionCarrito,
} from '../services/checkoutService';
import { colors, fontSize, fontWeight, radius, spacing } from '../theme';
import { formatearPrecio } from '../utils/format';

export default function Resumen() {
  const router = useRouter();
  const { items, total: subtotalLocal, totalUnidades, puntoEntrega, vaciar } = useCarrito();
  const [error, setError] = useState('');
  const [enviando, setEnviando] = useState(false);
  const [codigoCreado, setCodigoCreado] = useState<string>();
  const [validacion, setValidacion] = useState<ValidacionCarrito>();
  const [revision, setRevision] = useState(0);

  const lineas = useMemo(
    () => items.map((i) => ({ productoId: i.producto.id, cantidad: i.cantidad })),
    [items]
  );

  // Revisa el carrito en la base cada vez que cambia (inventario, un solo comercio,
  // productos vigentes) y trae la tarifa vigente. Si no hay conexión se muestran los
  // valores locales: crear_pedido vuelve a validar todo de todas formas.
  useEffect(() => {
    if (lineas.length === 0 || codigoCreado) return;
    let activo = true;
    validarCarrito(lineas)
      .then((v) => activo && setValidacion(v))
      .catch(() => activo && setValidacion(undefined));
    return () => {
      activo = false;
    };
  }, [lineas, revision, codigoCreado]);

  const erroresPorProducto = new Map(
    (validacion?.errores ?? [])
      .filter((e) => e.producto_id)
      .map((e) => [e.producto_id as string, e])
  );
  const erroresGenerales = (validacion?.errores ?? []).filter((e) => !e.producto_id);
  const carritoInvalido = validacion !== undefined && !validacion.valido;

  const subtotal = validacion?.subtotal ?? subtotalLocal;
  const tarifa = validacion?.tarifaDomicilio ?? TARIFA_DOMICILIO;
  const totalPagar = validacion?.total ?? subtotal + tarifa;

  const onHacerPedido = async () => {
    if (!puntoEntrega) {
      setError('Elige el lugar de entrega');
      return;
    }
    if (carritoInvalido) {
      setError('Corrige los productos marcados antes de hacer el pedido');
      return;
    }

    setError('');
    setEnviando(true);
    try {
      const pedido = await crearPedido({ puntoEntregaId: puntoEntrega.id, lineas });
      setCodigoCreado(pedido.codigo);
    } catch (e) {
      setError(e instanceof ErrorPedido ? e.message : 'No se pudo crear el pedido. Revisa tu conexión.');
      // Si el problema fue el carrito (alguien compró la última unidad), se vuelve a revisar
      if (e instanceof ErrorPedido && e.codigo === 'CARRITO_INVALIDO') setRevision((n) => n + 1);
    } finally {
      setEnviando(false);
    }
  };

  const onCerrarAviso = () => {
    setCodigoCreado(undefined);
    setValidacion(undefined);
    router.replace('/');
    vaciar();
  };

  if (items.length === 0 && codigoCreado === undefined) {
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
        {erroresGenerales.map((e) => (
          <Text key={e.codigo} style={styles.error}>
            {e.mensaje}
          </Text>
        ))}
        {items.map((i) => {
          const problema = erroresPorProducto.get(i.producto.id);
          return (
            <View key={i.producto.id} style={styles.producto}>
              <View style={styles.filaTexto}>
                <Text style={styles.nombre}>{i.producto.nombre}</Text>
                <Text style={styles.detalle}>
                  {i.cantidad} × {formatearPrecio(i.producto.precio)}
                </Text>
                {problema && (
                  <Text style={styles.errorProducto}>
                    {problema.codigo === 'INVENTARIO_INSUFICIENTE'
                      ? `Solo quedan ${problema.disponible ?? 0} unidades`
                      : problema.mensaje}
                  </Text>
                )}
              </View>
              <Text style={styles.precio}>
                {formatearPrecio(i.cantidad * i.producto.precio)}
              </Text>
            </View>
          );
        })}

        <View style={styles.totales}>
          <View style={styles.lineaTotal}>
            <Text style={styles.etiquetaTotal}>Subtotal ({totalUnidades})</Text>
            <Text style={styles.valorTotal}>{formatearPrecio(subtotal)}</Text>
          </View>
          <View style={styles.lineaTotal}>
            <Text style={styles.etiquetaTotal}>Tarifa de domicilio</Text>
            <Text style={styles.valorTotal}>{formatearPrecio(tarifa)}</Text>
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
          deshabilitado={enviando || carritoInvalido}
          onPress={onHacerPedido}
        />
      </View>

      <AvisoEmergente
        visible={codigoCreado !== undefined}
        mensaje={`Pedido #${codigoCreado} creado. Ya lo recibió el comercio.`}
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
  errorProducto: {
    marginTop: spacing.xs,
    fontSize: fontSize.sm,
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