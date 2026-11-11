import { useEffect, useState } from 'react';
import { Alert, Pressable, StyleSheet, Text, View } from 'react-native';
import { obtenerCodigoEntrega, regenerarCodigoEntrega } from '../services/seguimientoService';
import { colors, fontSize, fontWeight, radius, spacing } from '../theme';

type Props = {
  pedidoId: string;
};

// Lo ve el solicitante mientras espera su pedido: es el código que le dice al domiciliario al recibir.
export default function CodigoEntrega({ pedidoId }: Props) {
  const [codigo, setCodigo] = useState<string | null>();

  useEffect(() => {
    let vigente = true;
    obtenerCodigoEntrega(pedidoId).then((c) => {
      if (vigente) setCodigo(c);
    });
    return () => {
      vigente = false;
    };
  }, [pedidoId]);

  const generarNuevo = () => {
    Alert.alert(
      'Generar nuevo código',
      'El código actual dejará de servir. Úsalo si alguien más lo vio o se agotaron los intentos.',
      [
        { text: 'Cancelar', style: 'cancel' },
        {
          text: 'Generar',
          onPress: async () => {
            const nuevo = await regenerarCodigoEntrega(pedidoId);
            if (nuevo) setCodigo(nuevo);
            else Alert.alert('No se pudo generar', 'Inténtalo de nuevo.');
          },
        },
      ]
    );
  };

  if (codigo === undefined) return null; // cargando
  if (codigo === null) return null; // no se pudo leer: no se muestra nada confuso

  return (
    <View style={styles.contenedor}>
      <Text style={styles.titulo}>Código de entrega</Text>
      <View style={styles.digitos}>
        {codigo.split('').map((d, i) => (
          <View key={i} style={styles.caja}>
            <Text style={styles.digito}>{d}</Text>
          </View>
        ))}
      </View>
      <Text style={styles.ayuda}>Díselo al domiciliario solo cuando recibas el pedido.</Text>
      <Pressable onPress={generarNuevo} hitSlop={8}>
        <Text style={styles.nuevo}>Generar nuevo código</Text>
      </Pressable>
    </View>
  );
}

const styles = StyleSheet.create({
  contenedor: {
    alignSelf: 'stretch',
    alignItems: 'center',
    padding: spacing.md,
    marginBottom: spacing.md,
    borderWidth: 1,
    borderColor: colors.primary,
    borderRadius: radius.sm,
  },
  titulo: {
    marginBottom: spacing.sm,
    fontSize: fontSize.md,
    color: colors.textMuted,
  },
  digitos: {
    flexDirection: 'row',
    gap: spacing.sm,
  },
  caja: {
    width: 48,
    height: 56,
    alignItems: 'center',
    justifyContent: 'center',
    borderRadius: radius.sm,
    backgroundColor: colors.surface,
  },
  digito: {
    fontSize: fontSize.xxl,
    fontWeight: fontWeight.bold,
    color: colors.primary,
  },
  nuevo: {
    marginTop: spacing.sm,
    fontSize: fontSize.sm,
    color: colors.primary,
    textDecorationLine: 'underline',
  },
  ayuda: {
    marginTop: spacing.sm,
    textAlign: 'center',
    fontSize: fontSize.sm,
    color: colors.textMuted,
  },
});
