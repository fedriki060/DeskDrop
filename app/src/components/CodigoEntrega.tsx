import { useEffect, useState } from 'react';
import { StyleSheet, Text, View } from 'react-native';
import { obtenerCodigoEntrega } from '../services/seguimientoService';
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
      <Text style={styles.ayuda}>Díselo al domiciliario solo cuando tengas tu pedido en la mano.</Text>
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
  ayuda: {
    marginTop: spacing.sm,
    textAlign: 'center',
    fontSize: fontSize.sm,
    color: colors.textMuted,
  },
});
