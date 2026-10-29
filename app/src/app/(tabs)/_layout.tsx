import { Ionicons } from '@expo/vector-icons';
import { Tabs } from 'expo-router';
import { ComponentProps } from 'react';
import { ColorValue } from 'react-native';
import { useAuth } from '../../context/AuthContext';
import { useCarrito } from '../../context/CarritoContext';
import { colors, fontSize, fontWeight } from '../../theme';

type IconName = ComponentProps<typeof Ionicons>['name'];

const tabIcon =
  (name: IconName) =>
  ({ color, size }: { color: ColorValue; size: number }) => (
    <Ionicons name={name} size={size} color={color as string} />
  );

export default function TabsLayout() {
  const { totalUnidades } = useCarrito();
  const { rolActivo } = useAuth();

  // href: null oculta la pestaña de la barra
  const visibleSi = (condicion: boolean) => (condicion ? undefined : null);
  const esSolicitante = rolActivo === 'solicitante';
  const esDomiciliario = rolActivo === 'domiciliario';
  const esComercio = rolActivo === 'comercio';

  return (
    <Tabs
      initialRouteName="index"
      screenOptions={{
        headerTitleAlign: 'center',
        headerTitleStyle: {
          color: colors.primary,
          fontSize: fontSize.lg,
          fontWeight: fontWeight.bold,
        },
        headerStyle: { backgroundColor: colors.background },
        headerShadowVisible: false,
        tabBarShowLabel: false,
        tabBarActiveTintColor: colors.primary,
        tabBarInactiveTintColor: colors.textMuted,
        tabBarStyle: {
          backgroundColor: colors.background,
          borderTopColor: colors.border,
        },
      }}
    >
      <Tabs.Screen
        name="historial"
        options={{
          title: 'Historial',
          tabBarIcon: tabIcon('time-outline'),
          href: visibleSi(esSolicitante),
        }}
      />
      <Tabs.Screen
        name="carrito"
        options={{
          title: 'Carrito',
          tabBarIcon: tabIcon('cart-outline'),
          href: visibleSi(esSolicitante),
          tabBarBadge:
            totalUnidades > 0 ? (totalUnidades > 99 ? '99+' : totalUnidades) : undefined,
          tabBarBadgeStyle: {
            backgroundColor: colors.danger,
            color: colors.white,
            fontSize: fontSize.sm,
          },
        }}
      />
      <Tabs.Screen
        name="index"
        options={{
          title: 'Inicio',
          tabBarIcon: tabIcon('home-outline'),
          href: visibleSi(esSolicitante),
        }}
      />
      <Tabs.Screen
        name="tiendas"
        options={{
          title: 'Tiendas',
          tabBarIcon: tabIcon('storefront-outline'),
          href: visibleSi(esSolicitante),
        }}
      />
      <Tabs.Screen
        name="entregas"
        options={{
          title: 'Entregas',
          tabBarIcon: tabIcon('bicycle-outline'),
          href: visibleSi(esDomiciliario),
        }}
      />
      <Tabs.Screen
        name="bandeja"
        options={{
          title: 'Pedidos',
          tabBarIcon: tabIcon('receipt-outline'),
          href: visibleSi(esComercio),
        }}
      />
      <Tabs.Screen
        name="perfil"
        options={{ title: 'Perfil', tabBarIcon: tabIcon('person-outline') }}
      />
    </Tabs>
  );
}