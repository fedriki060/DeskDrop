import { createContext, ReactNode, useContext, useState } from 'react';

type AuthContextType = {
  usuario?: string;
  sesion: boolean;
  iniciarSesion: (usuario: string, contrasena: string) => Promise<boolean>;
  cerrarSesion: () => void;
};

const AuthContext = createContext<AuthContextType | undefined>(undefined);

export function AuthProvider({ children }: { children: ReactNode }) {
  const [usuario, setUsuario] = useState<string>();

  // SIMULADO: reemplazar por la llamada a la API de login (T-069)
  const iniciarSesion = async (u: string, contrasena: string) => {
    await new Promise<void>((resolve) => setTimeout(resolve, 300));
    if (u === '1' && contrasena === '1') {
      setUsuario(u);
      return true;
    }
    return false;
  };

  const cerrarSesion = () => setUsuario(undefined);

  return (
    <AuthContext.Provider
      value={{ usuario, sesion: usuario !== undefined, iniciarSesion, cerrarSesion }}
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