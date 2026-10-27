import { Ionicons } from '@expo/vector-icons';
import { Tabs } from 'expo-router';
import { ComponentProps } from 'react';
import { useCarrito } from '../../context/CarritoContext';
import { colors, fontSize, fontWeight } from '../../theme';

type IconName = ComponentProps<typeof Ionicons>['name'];

const tabIcon =
  (name: IconName) =>
  ({ color, size }: { color: string; size: number }) => (
    <Ionicons name={name} size={size} color={color} />
  );

export default function TabsLayout() {
  const { totalUnidades } = useCarrito();

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
        options={{ title: 'Historial', tabBarIcon: tabIcon('time-outline') }}
      />
      <Tabs.Screen
        name="carrito"
        options={{
          title: 'Carrito',
          tabBarIcon: tabIcon('cart-outline'),
          tabBarBadge: totalUnidades > 0 ? (totalUnidades > 99 ? '99+' : totalUnidades) : undefined,
          tabBarBadgeStyle: {
            backgroundColor: colors.danger,
            color: colors.white,
            fontSize: fontSize.sm,
          },
        }}
      />
      <Tabs.Screen
        name="index"
        options={{ title: 'Inicio', tabBarIcon: tabIcon('home-outline') }}
      />
      <Tabs.Screen
        name="tiendas"
        options={{ title: 'Tiendas', tabBarIcon: tabIcon('storefront-outline') }}
      />
      <Tabs.Screen
        name="perfil"
        options={{ title: 'Perfil', tabBarIcon: tabIcon('person-outline') }}
      />
    </Tabs>
  );
}