import { Stack, useRouter } from 'expo-router';
import { useEffect, useState } from 'react';
import {
  ActivityIndicator,
  FlatList,
  Pressable,
  StyleSheet,
  Text,
  View,
} from 'react-native';
import { listarProductos, obtenerComercio } from '../services/catalogService';
import { colors, fontSize, fontWeight, radius, spacing } from '../theme';
import { Comercio, Producto } from '../types';
import { formatearPrecio } from '../utils/format';

type Props = {
  comercioId: string;
};

export default function CatalogoComercio({ comercioId }: Props) {
  const router = useRouter();
  const [comercio, setComercio] = useState<Comercio>();
  const [productos, setProductos] = useState<Producto[]>([]);
  const [cargando, setCargando] = useState(true);

  useEffect(() => {
    Promise.all([obtenerComercio(comercioId), listarProductos(comercioId)])
      .then(([c, p]) => {
        setComercio(c);
        setProductos(p);
      })
      .finally(() => setCargando(false));
  }, [comercioId]);

  if (cargando) {
    return (
      <View style={styles.centro}>
        <ActivityIndicator color={colors.primary} />
      </View>
    );
  }

  if (!comercio) {
    return (
      <View style={styles.centro}>
        <Text style={styles.vacio}>Comercio no encontrado</Text>
      </View>
    );
  }

  return (
    <>
      <Stack.Screen options={{ title: comercio.nombre }} />
      <FlatList
        data={productos}
        keyExtractor={(p) => p.id}
        contentContainerStyle={styles.lista}
        ListHeaderComponent={
          <Text style={styles.encabezado}>{comercio.descripcion}</Text>
        }
        ListEmptyComponent={
          <Text style={styles.vacio}>Este comercio aún no tiene productos</Text>
        }
        renderItem={({ item }) => {
          const agotado = item.inventario === 0;
          return (
            <Pressable
              style={[styles.tarjeta, agotado && styles.tarjetaAgotada]}
              disabled={agotado}
              onPress={() =>
                  router.push({ pathname: '/producto/[id]', params: { id: item.id } } as Href)
                }
            >
              <View style={styles.info}>
                <Text style={styles.nombre}>{item.nombre}</Text>
                <Text style={styles.descripcion}>{item.descripcion}</Text>
                {agotado && <Text style={styles.etiquetaAgotado}>Agotado</Text>}
              </View>
              <Text style={styles.precio}>{formatearPrecio(item.precio)}</Text>
            </Pressable>
          );
        }}
      />
    </>
  );
}

const styles = StyleSheet.create({
  centro: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.background,
  },
  lista: {
    padding: spacing.md,
    backgroundColor: colors.background,
  },
  encabezado: {
    marginBottom: spacing.md,
    fontSize: fontSize.md,
    color: colors.textMuted,
  },
  vacio: {
    fontSize: fontSize.lg,
    color: colors.textMuted,
    textAlign: 'center',
  },
  tarjeta: {
    flexDirection: 'row',
    alignItems: 'center',
    padding: spacing.md,
    marginBottom: spacing.sm,
    backgroundColor: colors.surface,
    borderRadius: radius.md,
  },
  tarjetaAgotada: {
    opacity: 0.5,
  },
  info: {
    flex: 1,
    marginRight: spacing.md,
  },
  nombre: {
    fontSize: fontSize.lg,
    fontWeight: fontWeight.bold,
    color: colors.text,
  },
  descripcion: {
    marginTop: spacing.xs,
    fontSize: fontSize.md,
    color: colors.textMuted,
  },
  etiquetaAgotado: {
    marginTop: spacing.xs,
    fontSize: fontSize.sm,
    fontWeight: fontWeight.bold,
    color: colors.danger,
  },
  precio: {
    fontSize: fontSize.lg,
    fontWeight: fontWeight.bold,
    color: colors.primary,
  },
});