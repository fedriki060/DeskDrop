import { useRouter } from 'expo-router';
import { useCallback, useEffect, useState } from 'react';
import { ActivityIndicator, RefreshControl, ScrollView, StyleSheet, Text, View } from 'react-native';
import BotonPrimario from '../../components/BotonPrimario';
import { useVueltaAPrimerPlano } from '../../hooks/useVueltaAPrimerPlano';
import ProtegidoPorRol from '../../components/ProtegidoPorRol';
import SeguimientoPedido from '../../components/SeguimientoPedido';
import { useAuth } from '../../context/AuthContext';
import {
  escucharMisPedidos,
  obtenerUltimoPedido,
  SeguimientoPedido as Pedido,
} from '../../services/seguimientoService';
import { colors, fontSize, spacing } from '../../theme';

const REFRESCO_MS = 15000;
const ESTADOS_EN_CURSO = ['Creado', 'Asignado', 'En Camino', 'Entregado'];

export default function Inicio() {
  const { perfil } = useAuth();
  const router = useRouter();
  const userId = perfil?.id;
  const [pedido, setPedido] = useState<Pedido | null>();
  const [error, setError] = useState<string>();
  const [refrescando, setRefrescando] = useState(false);
  const vueltas = useVueltaAPrimerPlano();

  const cargar = useCallback(async () => {
    if (!userId) return;
    try {
      setPedido(await obtenerUltimoPedido(userId));
      setError(undefined);
    } catch (e) {
      setError(e instanceof Error ? e.message : 'No se pudo cargar tu pedido.');
    }
  }, [userId]);

  // También al volver la app a primer plano: se lee el estado actual y se vuelve a suscribir
  useEffect(() => {
    cargar();
  }, [cargar, vueltas]);

  // Cambios en vivo (Realtime) y, por si se pierde algún aviso, una recarga periódica
  useEffect(
    () => (userId ? escucharMisPedidos(userId, cargar) : undefined),
    [userId, cargar, vueltas]
  );
  useEffect(() => {
    const t = setInterval(cargar, REFRESCO_MS);
    return () => clearInterval(t);
  }, [cargar]);

  const onRefrescar = async () => {
    setRefrescando(true);
    await cargar();
    setRefrescando(false);
  };

  return (
    <ProtegidoPorRol rol="solicitante">
      <ScrollView
        contentContainerStyle={styles.contenedor}
        refreshControl={<RefreshControl refreshing={refrescando} onRefresh={onRefrescar} />}
      >
        {error ? <Text style={styles.error}>{error}</Text> : null}
        {pedido === undefined && !error ? (
          <View style={styles.centro}>
            <ActivityIndicator color={colors.primary} />
          </View>
        ) : pedido && ESTADOS_EN_CURSO.includes(pedido.estado) ? (
          <SeguimientoPedido pedido={pedido} alCambiar={cargar} />
        ) : !error ? (
          <View>
            <Text style={styles.vacio}>No tienes un pedido en curso.</Text>
            <BotonPrimario titulo="Ir a Tiendas" onPress={() => router.navigate('/tiendas')} />
          </View>
        ) : null}
      </ScrollView>
    </ProtegidoPorRol>
  );
}

const styles = StyleSheet.create({
  contenedor: { flexGrow: 1, padding: spacing.lg, backgroundColor: colors.background },
  centro: { flex: 1, alignItems: 'center', justifyContent: 'center' },
  error: { marginBottom: spacing.md, textAlign: 'center', fontSize: fontSize.md, color: colors.danger },
  vacio: { marginTop: spacing.xl, textAlign: 'center', fontSize: fontSize.lg, color: colors.textMuted },
});
