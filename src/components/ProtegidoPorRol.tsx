import { Redirect } from 'expo-router';
import { ReactNode } from 'react';
import { useAuth } from '../context/AuthContext';
import { Rol } from '../types';
import { rutaInicial } from '../utils/roles';

type Props = {
  rol: Rol;
  children: ReactNode;
};

// Si el rol activo no es el requerido, manda al usuario a la pantalla de inicio de su rol
export default function ProtegidoPorRol({ rol, children }: Props) {
  const { rolActivo } = useAuth();

  if (rolActivo !== rol) {
    return <Redirect href={rutaInicial(rolActivo)} />;
  }
  return <>{children}</>;
}