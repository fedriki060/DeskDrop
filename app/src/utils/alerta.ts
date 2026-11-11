import { Alert as AlertNativo, AlertButton, Platform } from 'react-native';

/**
 * Igual que Alert.alert de React Native, pero también funciona en el navegador, donde el original
 * no hace nada cuando lleva botones. En web usa los diálogos nativos del navegador:
 * sin botones -> aviso; una acción -> confirmar; varias acciones -> el usuario elige por número.
 */
function alertar(titulo: string, mensaje?: string, botones?: AlertButton[]): void {
  if (Platform.OS !== 'web') {
    AlertNativo.alert(titulo, mensaje, botones);
    return;
  }
  const texto = mensaje ? `${titulo}\n\n${mensaje}` : titulo;
  const acciones = (botones ?? []).filter((b) => b.style !== 'cancel');
  const hayCancelar = (botones ?? []).some((b) => b.style === 'cancel');

  if (acciones.length === 0) {
    window.alert(texto);
    botones?.[0]?.onPress?.();
    return;
  }
  if (acciones.length === 1) {
    // Una sola acción: Aceptar la ejecuta; Cancelar no hace nada
    if (!hayCancelar || window.confirm(texto)) acciones[0].onPress?.();
    return;
  }
  const opciones = acciones.map((b, i) => `${i + 1}) ${b.text}`).join('\n');
  const respuesta = window.prompt(`${texto}\n\n${opciones}\n\nEscribe el número (o deja vacío para cancelar):`);
  const elegida = acciones[Number(respuesta) - 1];
  if (elegida) elegida.onPress?.();
}

export const Alert = { alert: alertar };
