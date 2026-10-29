import { createContext, ReactNode, useContext, useState } from 'react';
import { Rol } from '../types';

type UsuarioPrueba = {
  roles: Rol[];
};

// SIMULADO: usuarios de prueba (la contraseña es igual al usuario).
// En la app real los roles vienen del backend (T-069, T-072)
const USUARIOS_PRUEBA: Record<string, UsuarioPrueba> = {
  '1': { roles: ['solicitante', 'domiciliario'] },
  '2': { roles: ['comercio'] },
};

type DatosSesion = {
  usuario: string;
  roles: Rol[];
  rolActivo: Rol;
};

type AuthContextType = {
  usuario?: string;
  roles: Rol[];
  rolActivo: Rol;
  sesion: boolean;
  iniciarSesion: (usuario: string, contrasena: string) => Promise<boolean>;
  cambiarRolActivo: (rol: Rol) => void;
  cerrarSesion: () => void;
};

const AuthContext = createContext<AuthContextType | undefined>(undefined);

export function AuthProvider({ children }: { children: ReactNode }) {
  const [datos, setDatos] = useState<DatosSesion>();

  const iniciarSesion = async (u: string, contrasena: string) => {
    await new Promise<void>((resolve) => setTimeout(resolve, 300));
    const prueba = USUARIOS_PRUEBA[u];
    if (prueba?.roles && contrasena === u) {
      setDatos({ usuario: u, roles: prueba.roles, rolActivo: prueba.roles[0] });
      return true;
    }
    return false;
  };

  const cambiarRolActivo = (rol: Rol) => {
    setDatos((prev) => (prev && prev.roles.includes(rol) ? { ...prev, rolActivo: rol } : prev));
  };

  const cerrarSesion = () => setDatos(undefined);

  return (
    <AuthContext.Provider
      value={{
        usuario: datos?.usuario,
        roles: datos?.roles ?? [],
        rolActivo: datos?.rolActivo ?? 'solicitante',
        sesion: datos !== undefined,
        iniciarSesion,
        cambiarRolActivo,
        cerrarSesion,
      }}
    >
      {children}
    </AuthContext.Provider>
  );
}

export function useAuth() {
  const contexto = useContext(AuthContext);
  if (!contexto) {
    throw new Error('useAuth debe usarse dentro de AuthProvider');
  }
  return contexto;
}