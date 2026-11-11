import { useCallback, useEffect, useState } from 'react';
import {
  ActivityIndicator,
  Alert,
  Pressable,
  RefreshControl,
  SectionList,
  StyleSheet,
  Text,
  View,
} from 'react-native';
import { useAuth } from '../context/AuthContext';
import { useVueltaAPrimerPlano } from '../hooks/useVueltaAPrimerPlano';
import {
  aceptarPedido,
  confirmarRecogida,
  escucharEntregas,
  listarEntregas,
  registrarCobroEfectivo,
  ResultadoEntrega,
} from '../services/entregasService';
import { colors, fontSize, fontWeight, radius, spacing } from '../theme';
import { Entrega } from '../types';
import { formatearPrecio } from '../utils/format';
import IngresarCodigoEntrega from './IngresarCodigoEntrega';

const REFRESCO_MS = 15000;

export default function ListaEntregas() {
  const { perfil } = useAuth();
  const userId = perfil?.id;
  const [entregas, setEntregas] = useState<Entrega[]>([]);
  const [cargando, setCargando] = useState(true);
  const [refrescando, setRefrescando] = useState(false);
  const [error, setError] = useState<string>();
  const [ocupado, setOcupado] = useState<string>();
  const vueltas = useVueltaAPrimerPlano();

  const cargar = useCallback(async () => {
    if (!userId) return;
    try {
      setEntregas(await listarEntregas(userId));
      setError(undefined);
    } catch (e) {
      setError(e instanceof Error ? e.message : 'No se pudieron cargar los pedidos.');
    }
  }, [userId]);

  useEffect(() => {
    cargar().finally(() => setCargando(false));
  }, [cargar, vueltas]);

  // Realtime, más una recarga periódica: si otro domiciliario toma un pedido, este deja de verse
  useEffect(() => escucharEntregas(cargar), [cargar, vueltas]);
  useEffect(() => {
    const t = setInterval(cargar, REFRESCO_MS);
    return () => clearInterval(t);
  }, [cargar]);

  const onRefrescar = async () => {
    setRefrescando(true);
    await cargar();
    setRefrescando(false);
  };

  const accion = async (id: string, ejecutar: (id: string) => Promise<ResultadoEntrega>) => {
    setOcupado(id);
    const resultado = await ejecutar(id);
    if (!resultado.ok) Alert.alert('No se pudo completar', resultado.mensaje);
    await cargar();
    setOcupado(undefined);
  };

  if (cargando) {
    return (
      <View style={styles.centro}>
        <ActivityIndicator color={colors.primary} />
      </View>
    );
  }

  // Una entrega a la vez: mientras tenga una Asignada o En Camino no puede aceptar otra
  const tieneEntregaActiva = entregas.some(
    (e) => e.esMia && (e.estado === 'Asignado' || e.estado === 'En Camino')
  );

  const secciones = [
    { titulo: 'Mis entregas', data: entregas.filter((e) => e.esMia) },
    { titulo: 'Disponibles', data: entregas.filter((e) => !e.esMia) },
  ].filter((s) => s.data.length > 0);

  return (
    <SectionList
      sections={secciones}
      keyExtractor={(e) => e.id}
      contentContainerStyle={styles.lista}
      refreshControl={<RefreshControl refreshing={refrescando} onRefresh={onRefrescar} />}
      ListHeaderComponent={error ? <Text style={styles.error}>{error}</Text> : undefined}
      ListEmptyComponent={
        error ? undefined : <Text style={styles.vacio}>No hay pedidos por ahora. Se actualiza solo.</Text>
      }
      renderSectionHeader={({ section }) => <Text style={styles.seccion}>{section.titulo}</Text>}
      renderItem={({ item }) => (
        <View style={styles.tarjeta}>
          <View style={styles.encabezado}>
            <Text style={styles.numero}>Pedido #{item.numero}</Text>
            <Text style={styles.estado}>{item.estado}</Text>
          </View>
          <Text style={styles.meta}>Recoger en: {item.comercio}</Text>
          <Text style={styles.meta}>
            Entregar en: {item.puntoEntrega}
            {item.indicaciones ? ` (${item.indicaciones})` : ''}
          </Text>
          {item.notas ? <Text style={styles.meta}>Nota: {item.notas}</Text> : null}
          <View style={styles.productos}>
            {item.items.map((i, n) => (
              <Text key={`${i.nombre}-${n}`} style={styles.producto}>
                {i.cantidad} × {i.nombre}
              </Text>
            ))}
          </View>
          <Text style={styles.total}>Total a cobrar: {formatearPrecio(item.total)}</Text>

          {!item.esMia &&
            (tieneEntregaActiva ? (
              <Text style={styles.espera}>Termina tu entrega actual para aceptar otro pedido</Text>
            ) : (
              <Boton
                titulo="Aceptar pedido"
                deshabilitado={ocupado === item.id}
                onPress={() => accion(item.id, aceptarPedido)}
              />
            ))}

          {item.esMia && item.estado === 'Asignado' &&
            (item.listoParaRecoger ? (
              <Boton
                titulo="Ya lo recogí"
                deshabilitado={ocupado === item.id}
                onPress={() => accion(item.id, confirmarRecogida)}
              />
            ) : (
              <Text style={styles.espera}>Esperando a que el comercio lo marque listo</Text>
            ))}

          {item.esMia && item.estado === 'En Camino' && (
            <IngresarCodigoEntrega pedidoId={item.id} alConfirmar={cargar} />
          )}

          {item.esMia && item.estado === 'Entregado' && (
            <>
              <Text style={styles.cobro}>Cobra {formatearPrecio(item.total)} en efectivo</Text>
              <Boton
                titulo="Ya cobré"
                deshabilitado={ocupado === item.id}
                onPress={() => accion(item.id, registrarCobroEfectivo)}
              />
            </>
          )}
        </View>
      )}
    />
  );
}

function Boton({ titulo, onPress, deshabilitado }: { titulo: string; onPress: () => void; deshabilitado?: boolean }) {
  return (
    <Pressable style={[styles.boton, deshabilitado && styles.inactivo]} disabled={deshabilitado} onPress={onPress}>
      <Text style={styles.textoBoton}>{titulo}</Text>
    </Pressable>
  );
}

const styles = StyleSheet.create({
  centro: { flex: 1, alignItems: 'center', justifyContent: 'center', backgroundColor: colors.background },
  lista: { padding: spacing.md, backgroundColor: colors.background },
  error: { marginBottom: spacing.md, textAlign: 'center', fontSize: fontSize.md, color: colors.danger },
  vacio: { marginTop: spacing.xl, textAlign: 'center', fontSize: fontSize.lg, color: colors.textMuted },
  seccion: {
    marginTop: spacing.sm,
    marginBottom: spacing.sm,
    fontSize: fontSize.lg,
    fontWeight: fontWeight.bold,
    color: colors.primary,
  },
  tarjeta: { padding: spacing.md, marginBottom: spacing.md, backgroundColor: colors.surface, borderRadius: radius.md },
  encabezado: { flexDirection: 'row', justifyContent: 'space-between' },
  numero: { fontSize: fontSize.lg, fontWeight: fontWeight.bold, color: colors.text },
  estado: { fontSize: fontSize.md, fontWeight: fontWeight.bold, color: colors.warning },
  meta: { marginTop: spacing.xs, fontSize: fontSize.md, color: colors.textMuted },
  productos: { marginVertical: spacing.sm },
  producto: { fontSize: fontSize.md, color: colors.text },
  total: { marginBottom: spacing.sm, fontSize: fontSize.lg, fontWeight: fontWeight.bold, color: colors.primary },
  cobro: { marginBottom: spacing.sm, fontSize: fontSize.lg, fontWeight: fontWeight.bold, color: colors.text },
  espera: { fontSize: fontSize.md, color: colors.textMuted },
  boton: { padding: spacing.md, alignItems: 'center', borderRadius: radius.sm, backgroundColor: colors.primary },
  inactivo: { opacity: 0.6 },
  textoBoton: { fontSize: fontSize.md, fontWeight: fontWeight.bold, color: colors.white },
});
