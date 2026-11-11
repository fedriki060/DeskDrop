import { useEffect, useState } from 'react';
import { ActivityIndicator, StyleSheet, Text, View } from 'react-native';
import BandejaPedidos from '../../components/BandejaPedidos';
import ProtegidoPorRol from '../../components/ProtegidoPorRol';
import { useAuth } from '../../context/AuthContext';
import { obtenerMiComercio } from '../../services/pedidosService';
import { colors, fontSize, spacing } from '../../theme';

export default function Bandeja() {
  const { perfil } = useAuth();
  const [comercioId, setComercioId] = useState<string | null>();

  // El comercio es el que administra el usuario con sesión
  useEffect(() => {
    if (!perfil) return;
    let vigente = true;
    obtenerMiComercio(perfil.id).then((c) => {
      if (vigente) setComercioId(c?.id ?? null);
    });
    return () => {
      vigente = false;
    };
  }, [perfil]);

  return (
    <ProtegidoPorRol rol="comercio">
      {comercioId === undefined ? (
        <View style={styles.centro}>
          <ActivityIndicator color={colors.primary} />
        </View>
      ) : comercioId === null ? (
        <View style={styles.centro}>
          <Text style={styles.texto}>Tu cuenta aún no tiene un comercio asignado.</Text>
        </View>
      ) : (
        <BandejaPedidos comercioId={comercioId} />
      )}
    </ProtegidoPorRol>
  );
}

const styles = StyleSheet.create({
  centro: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    padding: spacing.lg,
    backgroundColor: colors.background,
  },
  texto: {
    textAlign: 'center',
    fontSize: fontSize.lg,
    color: colors.textMuted,
  },
});
