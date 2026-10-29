import { Stack } from 'expo-router';
import { StatusBar } from 'expo-status-bar';
import { AuthProvider, useAuth } from '../context/AuthContext';
import { CarritoProvider } from '../context/CarritoContext';
import { colors, fontSize, fontWeight } from '../theme';

const headerCatalogo = {
  headerShown: true,
  headerTitleAlign: 'center' as const,
  headerTitleStyle: {
    color: colors.primary,
    fontSize: fontSize.lg,
    fontWeight: fontWeight.bold,
  },
  headerTintColor: colors.primary,
  headerStyle: { backgroundColor: colors.background },
  headerShadowVisible: false,
};

function Rutas() {
    const { sesion, cargando } = useAuth();

  // Mientras se lee la sesión guardada no se decide la ruta (evita ver el login un instante)
  if (cargando) return null;

  return (
    <Stack screenOptions={{ headerShown: false }}>
            {/* Fuera de los grupos: se abre con y sin sesión (desde login, registro o perfil) */}
      <Stack.Screen
        name="terminos"
        options={{ ...headerCatalogo, title: 'Términos y privacidad' }}
      />
      <Stack.Protected guard={sesion}>
        <Stack.Screen name="(tabs)" />
        <Stack.Screen
          name="restaurante/[id]"
          options={{ ...headerCatalogo, title: 'Restaurante' }}
        />
        <Stack.Screen
          name="utensilios/[id]"
          options={{ ...headerCatalogo, title: 'Utensilios' }}
        />
        <Stack.Screen
          name="producto/[id]"
          options={{ ...headerCatalogo, title: 'Producto' }}
        />
        <Stack.Screen
          name="resumen"
          options={{ ...headerCatalogo, title: 'Resumen del pedido' }}
        />
        <Stack.Screen
          name="ubicacion"
          options={{ ...headerCatalogo, title: 'Lugar de entrega' }}
        />
      </Stack.Protected>
      <Stack.Protected guard={!sesion}>
        <Stack.Screen name="login" />
        <Stack.Screen name="registro" />
        <Stack.Screen name="verificar" />
        <Stack.Screen name="recuperar" />
        <Stack.Screen name="restablecer" />
      </Stack.Protected>
    </Stack>
  );
}

export default function RootLayout() {
  return (
    <AuthProvider>
      <CarritoProvider>
        <StatusBar style="dark" />
        <Rutas />
      </CarritoProvider>
    </AuthProvider>
  );
}