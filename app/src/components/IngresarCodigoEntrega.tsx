import { useState } from 'react';
import { StyleSheet } from 'react-native';
import { confirmarEntrega } from '../services/seguimientoService';
import { spacing } from '../theme';
import BotonPrimario from './BotonPrimario';
import CampoTexto from './CampoTexto';

type Props = {
  pedidoId: string;
  /** Se llama cuando el código fue correcto y el pedido quedó Entregado */
  alConfirmar: () => void;
};

// Lo usa el domiciliario al entregar: digita el código de 4 dígitos que le dice el solicitante.
export default function IngresarCodigoEntrega({ pedidoId, alConfirmar }: Props) {
  const [codigo, setCodigo] = useState('');
  const [error, setError] = useState<string>();
  const [enviando, setEnviando] = useState(false);
  const [bloqueado, setBloqueado] = useState(false);

  const enviar = async () => {
    if (!/^[0-9]{4}$/.test(codigo)) {
      setError('El código son 4 dígitos');
      return;
    }
    setEnviando(true);
    setError(undefined);
    const resultado = await confirmarEntrega(pedidoId, codigo);
    setEnviando(false);
    if (resultado.ok) {
      alConfirmar();
      return;
    }
    setError(resultado.mensaje);
    setBloqueado(resultado.bloqueado ?? false);
    setCodigo('');
  };

  return (
    <>
      <CampoTexto
        etiqueta="Código de entrega"
        placeholder="0000"
        value={codigo}
        onChangeText={(t) => setCodigo(t.replace(/[^0-9]/g, '').slice(0, 4))}
        keyboardType="number-pad"
        maxLength={4}
        editable={!bloqueado}
        error={error}
        style={styles.campo}
      />
      <BotonPrimario
        titulo={enviando ? 'Confirmando...' : 'Confirmar entrega'}
        deshabilitado={enviando || bloqueado || codigo.length !== 4}
        onPress={enviar}
      />
    </>
  );
}

const styles = StyleSheet.create({
  campo: {
    textAlign: 'center',
    letterSpacing: spacing.sm,
  },
});
