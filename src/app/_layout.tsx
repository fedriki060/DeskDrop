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
  const { sesion } = useAuth();

  return (
    <Stack screenOptions={{ headerShown: false }}>
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
      </Stack.Protected>
      <Stack.Protected guard={!sesion}>
        <Stack.Screen name="login" />
        <Stack.Screen name="registro" />
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
