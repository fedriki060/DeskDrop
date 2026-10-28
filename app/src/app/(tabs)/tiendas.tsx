import { Ionicons } from '@expo/vector-icons';
import { useRouter } from 'expo-router';
import { useEffect, useState } from 'react';
import {
  ActivityIndicator,
  Pressable,
  SectionList,
  StyleSheet,
  Text,
  View,
} from 'react-native';
import { listarComercios } from '../../services/catalogService';
import { colors, fontSize, fontWeight, radius, spacing } from '../../theme';
import { Comercio, TipoComercio } from '../../types';

const rutas = {
  restaurante: '/restaurante/[id]',
  utensilios: '/utensilios/[id]',
} as const;

const titulos: Record<TipoComercio, string> = {
  restaurante: 'Restaurantes',
  utensilios: 'Utensilios',
};

const tipos: TipoComercio[] = ['restaurante', 'utensilios'];

export default function Tiendas() {
  const router = useRouter();
  const [comercios, setComercios] = useState<Comercio[]>([]);
  const [cargando, setCargando] = useState(true);

  useEffect(() => {
    listarComercios()
      .then(setComercios)
      .finally(() => setCargando(false));
  }, []);

  if (cargando) {
    return (
      <View style={styles.centro}>
        <ActivityIndicator color={colors.primary} />
      </View>
    );
  }

  const secciones = tipos
    .map((tipo) => ({
      title: titulos[tipo],
      data: comercios.filter((c) => c.tipo === tipo),
    }))
    .filter((s) => s.data.length > 0);

  return (
    <SectionList
      sections={secciones}
      keyExtractor={(c) => c.id}
      contentContainerStyle={styles.lista}
      stickySectionHeadersEnabled={false}
      renderSectionHeader={({ section }) => (
        <Text style={styles.seccion}>{section.title}</Text>
      )}
      renderItem={({ item }) => (
        <Pressable
          style={styles.tarjeta}
          onPress={() =>
            router.push({ pathname: rutas[item.tipo], params: { id: item.id } })
          }
        >
          <View style={styles.inicial}>
            <Text style={styles.inicialTexto}>{item.nombre.charAt(0)}</Text>
          </View>
          <View style={styles.info}>
            <Text style={styles.nombre}>{item.nombre}</Text>
            <Text style={styles.descripcion}>{item.descripcion}</Text>
          </View>
          <Ionicons name="chevron-forward" size={20} color={colors.textMuted} />
        </Pressable>
      )}
    />
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
  seccion: {
    marginTop: spacing.md,
    marginBottom: spacing.sm,
    fontSize: fontSize.xl,
    fontWeight: fontWeight.bold,
    color: colors.primary,
  },
  tarjeta: {
    flexDirection: 'row',
    alignItems: 'center',
    padding: spacing.md,
    marginBottom: spacing.sm,
    backgroundColor: colors.surface,
    borderRadius: radius.md,
  },
  inicial: {
    width: 44,
    height: 44,
    borderRadius: 22,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.primary,
  },
  inicialTexto: {
    fontSize: fontSize.xl,
    fontWeight: fontWeight.bold,
    color: colors.white,
  },
  info: {
    flex: 1,
    marginHorizontal: spacing.md,
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
});