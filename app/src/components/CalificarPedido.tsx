import { Ionicons } from '@expo/vector-icons';
import { useEffect, useState } from 'react';
import { Pressable, StyleSheet, Text, View } from 'react-native';
import { calificarPedido, obtenerMiCalificacion } from '../services/seguimientoService';
import { colors, fontSize, fontWeight, spacing } from '../theme';
import BotonPrimario from './BotonPrimario';
import CampoTexto from './CampoTexto';

type Props = {
  pedidoId: string;
  /** Primer nombre del domiciliario */
  repartidor: string | null;
};

const MAXIMO_COMENTARIO = 300;

function Estrellas({ valor, onElegir }: { valor: number; onElegir?: (n: number) => void }) {
  return (
    <View style={styles.estrellas}>
      {[1, 2, 3, 4, 5].map((n) => (
        <Pressable key={n} onPress={() => onElegir?.(n)} disabled={!onElegir} hitSlop={6}>
          <Ionicons name={n <= valor ? 'star' : 'star-outline'} size={34} color={colors.primary} />
        </Pressable>
      ))}
    </View>
  );
}

// El solicitante califica al domiciliario una sola vez después de recibir el pedido (HU-15).
export default function CalificarPedido({ pedidoId, repartidor }: Props) {
  const [previa, setPrevia] = useState<number | null>();
  const [estrellas, setEstrellas] = useState(0);
  const [comentario, setComentario] = useState('');
  const [enviando, setEnviando] = useState(false);
  const [error, setError] = useState<string>();

  useEffect(() => {
    let vigente = true;
    obtenerMiCalificacion(pedidoId).then((e) => {
      if (vigente) setPrevia(e);
    });
    return () => {
      vigente = false;
    };
  }, [pedidoId]);

  const enviar = async () => {
    if (estrellas < 1) {
      setError('Elige de 1 a 5 estrellas.');
      return;
    }
    setError(undefined);
    setEnviando(true);
    const resultado = await calificarPedido(pedidoId, estrellas, comentario);
    setEnviando(false);
    if (resultado.ok) setPrevia(estrellas);
    else setError(resultado.mensaje);
  };

  if (previa === undefined) return null; // leyendo si ya calificó

  if (previa !== null) {
    return (
      <View style={styles.caja}>
        <Text style={styles.titulo}>¡Gracias por calificar!</Text>
        <Estrellas valor={previa} />
      </View>
    );
  }

  return (
    <View style={styles.caja}>
      <Text style={styles.titulo}>¿Cómo te fue con {repartidor ?? 'tu domiciliario'}?</Text>
      <Estrellas valor={estrellas} onElegir={setEstrellas} />
      <CampoTexto
        placeholder="Comentario (opcional)"
        value={comentario}
        onChangeText={setComentario}
        maxLength={MAXIMO_COMENTARIO}
        multiline
        autoCapitalize="sentences"
      />
      {error ? <Text style={styles.error}>{error}</Text> : null}
      <BotonPrimario
        titulo={enviando ? 'Enviando...' : 'Enviar calificación'}
        deshabilitado={enviando}
        onPress={enviar}
      />
    </View>
  );
}

const styles = StyleSheet.create({
  caja: { marginBottom: spacing.md },
  titulo: { marginBottom: spacing.sm, fontSize: fontSize.lg, fontWeight: fontWeight.bold, color: colors.text },
  estrellas: { flexDirection: 'row', gap: spacing.sm, marginBottom: spacing.md },
  error: { marginBottom: spacing.sm, fontSize: fontSize.md, color: colors.danger },
});
