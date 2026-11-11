import { useCallback, useEffect, useState } from 'react';
import {
  ActivityIndicator,
  FlatList,
  KeyboardAvoidingView,
  Modal,
  Platform,
  Pressable,
  RefreshControl,
  ScrollView,
  StyleSheet,
  Switch,
  Text,
  View,
} from 'react-native';
import { useVueltaAPrimerPlano } from '../hooks/useVueltaAPrimerPlano';
import {
  actualizarProducto,
  cambiarDisponibilidadProducto,
  crearProducto,
  eliminarProducto,
  listarProductosComercio,
  ProductoGestion,
  validarProducto,
} from '../services/productosComercioService';
import { colors, fontSize, fontWeight, radius, spacing } from '../theme';
import { Alert } from '../utils/alerta';
import { formatearPrecio } from '../utils/format';
import BotonPrimario from './BotonPrimario';
import CampoTexto from './CampoTexto';

type Props = { comercioId: string };

export default function GestionProductos({ comercioId }: Props) {
  const [productos, setProductos] = useState<ProductoGestion[]>([]);
  const [cargando, setCargando] = useState(true);
  const [refrescando, setRefrescando] = useState(false);
  const [error, setError] = useState<string>();
  const vueltas = useVueltaAPrimerPlano();

  // Formulario: editando === undefined -> cerrado; null -> producto nuevo
  const [editando, setEditando] = useState<ProductoGestion | null | undefined>(undefined);
  const [nombre, setNombre] = useState('');
  const [descripcion, setDescripcion] = useState('');
  const [precio, setPrecio] = useState('');
  const [inventario, setInventario] = useState('');
  const [errorForm, setErrorForm] = useState<string>();
  const [guardando, setGuardando] = useState(false);

  const cargar = useCallback(async () => {
    try {
      setProductos(await listarProductosComercio(comercioId));
      setError(undefined);
    } catch (e) {
      setError(e instanceof Error ? e.message : 'No se pudieron cargar tus productos.');
    }
  }, [comercioId]);

  useEffect(() => {
    cargar().finally(() => setCargando(false));
  }, [cargar, vueltas]);

  const abrirForm = (p: ProductoGestion | null) => {
    setEditando(p);
    setNombre(p?.nombre ?? '');
    setDescripcion(p?.descripcion ?? '');
    setPrecio(p ? String(p.precio) : '');
    setInventario(p ? String(p.inventario) : '');
    setErrorForm(undefined);
  };

  const guardar = async () => {
    const invalido = validarProducto(nombre, precio, inventario);
    if (invalido) {
      setErrorForm(invalido);
      return;
    }
    setGuardando(true);
    const datos = {
      nombre,
      descripcion,
      precio: Number(precio.trim()),
      inventario: Number(inventario.trim()),
    };
    const fallo = editando
      ? await actualizarProducto(editando.id, datos)
      : await crearProducto(comercioId, datos);
    setGuardando(false);
    if (fallo) {
      setErrorForm(fallo);
      return;
    }
    setEditando(undefined);
    await cargar();
  };

  const alternar = async (p: ProductoGestion, activo: boolean) => {
    const fallo = await cambiarDisponibilidadProducto(p.id, activo);
    if (fallo) Alert.alert('No se pudo cambiar', fallo);
    await cargar();
  };

  const confirmarEliminar = (p: ProductoGestion) => {
    Alert.alert(
      `Eliminar "${p.nombre}"`,
      'Se quita de tu lista. Si ya tiene pedidos, quedará desactivado para conservar el historial.',
      [
        { text: 'Cancelar', style: 'cancel' },
        {
          text: 'Eliminar',
          style: 'destructive',
          onPress: async () => {
            const r = await eliminarProducto(p.id);
            if (r === 'desactivado') {
              Alert.alert(
                'Producto desactivado',
                'Tiene pedidos asociados, así que no se puede borrar. Ya no aparece en el catálogo.'
              );
            } else if (r !== 'eliminado') {
              Alert.alert('No se pudo eliminar', r);
            }
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
    <View style={styles.contenedor}>
      <FlatList
        data={productos}
        keyExtractor={(p) => p.id}
        contentContainerStyle={styles.lista}
        refreshControl={
          <RefreshControl
            refreshing={refrescando}
            onRefresh={async () => {
              setRefrescando(true);
              await cargar();
              setRefrescando(false);
            }}
          />
        }
        ListHeaderComponent={
          <View>
            <BotonPrimario titulo="Agregar producto" onPress={() => abrirForm(null)} />
            {error ? <Text style={styles.error}>{error}</Text> : null}
          </View>
        }
        ListEmptyComponent={
          error ? undefined : <Text style={styles.vacio}>Aún no tienes productos. Agrega el primero.</Text>
        }
        renderItem={({ item }) => (
          <View style={[styles.tarjeta, !item.activo && styles.tarjetaInactiva]}>
            <View style={styles.fila}>
              <View style={styles.info}>
                <Text style={styles.nombre}>{item.nombre}</Text>
                <Text style={styles.meta}>
                  {formatearPrecio(item.precio)} · Inventario: {item.inventario}
                </Text>
                {item.inventario === 0 && item.activo ? (
                  <Text style={styles.agotado}>Agotado</Text>
                ) : null}
              </View>
              <View style={styles.disponibilidad}>
                <Text style={styles.etiquetaDisp}>{item.activo ? 'Disponible' : 'Oculto'}</Text>
                <Switch
                  value={item.activo}
                  onValueChange={(v) => alternar(item, v)}
                  trackColor={{ false: colors.border, true: colors.primary }}
                />
              </View>
            </View>
            <View style={styles.acciones}>
              <Pressable onPress={() => abrirForm(item)} hitSlop={8}>
                <Text style={styles.editar}>Editar</Text>
              </Pressable>
              <Pressable onPress={() => confirmarEliminar(item)} hitSlop={8}>
                <Text style={styles.eliminar}>Eliminar</Text>
              </Pressable>
            </View>
          </View>
        )}
      />

      <Modal visible={editando !== undefined} animationType="slide" onRequestClose={() => setEditando(undefined)}>
        <KeyboardAvoidingView
          style={styles.modal}
          behavior={Platform.OS === 'ios' ? 'padding' : undefined}
        >
          <ScrollView contentContainerStyle={styles.form} keyboardShouldPersistTaps="handled">
            <Text style={styles.tituloForm}>{editando ? 'Editar producto' : 'Nuevo producto'}</Text>
            <CampoTexto
              etiqueta="Nombre"
              value={nombre}
              onChangeText={setNombre}
              autoCapitalize="sentences"
              maxLength={150}
            />
            <CampoTexto
              etiqueta="Descripción (opcional)"
              value={descripcion}
              onChangeText={setDescripcion}
              autoCapitalize="sentences"
              multiline
            />
            <CampoTexto
              etiqueta="Precio (COP)"
              value={precio}
              onChangeText={setPrecio}
              keyboardType="number-pad"
            />
            <CampoTexto
              etiqueta="Inventario disponible"
              value={inventario}
              onChangeText={setInventario}
              keyboardType="number-pad"
            />
            {errorForm ? <Text style={styles.error}>{errorForm}</Text> : null}
            <BotonPrimario
              titulo={guardando ? 'Guardando…' : 'Guardar'}
              deshabilitado={guardando}
              onPress={guardar}
            />
            <Pressable onPress={() => setEditando(undefined)} style={styles.cancelar}>
              <Text style={styles.textoCancelar}>Cancelar</Text>
            </Pressable>
          </ScrollView>
        </KeyboardAvoidingView>
      </Modal>
    </View>
  );
}

const styles = StyleSheet.create({
  contenedor: { flex: 1, backgroundColor: colors.background },
  centro: { flex: 1, alignItems: 'center', justifyContent: 'center', backgroundColor: colors.background },
  lista: { padding: spacing.md },
  vacio: { marginTop: spacing.xl, textAlign: 'center', fontSize: fontSize.lg, color: colors.textMuted },
  error: { marginBottom: spacing.md, textAlign: 'center', fontSize: fontSize.md, color: colors.danger },
  tarjeta: {
    padding: spacing.md,
    marginBottom: spacing.md,
    borderWidth: 1,
    borderColor: colors.border,
    borderRadius: radius.md,
  },
  tarjetaInactiva: { opacity: 0.6, backgroundColor: colors.surface },
  fila: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between' },
  info: { flex: 1, marginRight: spacing.sm },
  nombre: { fontSize: fontSize.lg, fontWeight: fontWeight.bold, color: colors.text },
  meta: { marginTop: spacing.xs, fontSize: fontSize.md, color: colors.textMuted },
  agotado: { marginTop: spacing.xs, fontSize: fontSize.sm, fontWeight: fontWeight.bold, color: colors.danger },
  disponibilidad: { alignItems: 'center' },
  etiquetaDisp: { fontSize: fontSize.sm, color: colors.textMuted },
  acciones: { flexDirection: 'row', justifyContent: 'flex-end', gap: spacing.lg, marginTop: spacing.sm },
  editar: { fontSize: fontSize.md, fontWeight: fontWeight.bold, color: colors.primary },
  eliminar: { fontSize: fontSize.md, color: colors.danger },
  modal: { flex: 1, backgroundColor: colors.background },
  form: { padding: spacing.lg, paddingTop: spacing.xl },
  tituloForm: {
    marginBottom: spacing.lg,
    fontSize: fontSize.xl,
    fontWeight: fontWeight.bold,
    color: colors.primary,
  },
  cancelar: { alignItems: 'center', padding: spacing.sm },
  textoCancelar: { fontSize: fontSize.lg, color: colors.textMuted },
});
