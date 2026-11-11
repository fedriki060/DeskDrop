import type { Session } from '@supabase/supabase-js';
import { createContext, ReactNode, useContext, useEffect, useRef, useState } from 'react';
import { supabase } from '../lib/supabase';
import { Perfil, Rol } from '../types';
import { VERSION_LEGAL } from '../utils/legal';
import { rolesDesdeBase } from '../utils/roles';

type Resultado = { ok: true } | { ok: false; mensaje: string };
type ResultadoLogin = { ok: true } | { ok: false; mensaje: string; sinVerificar?: boolean };
type ResultadoRestablecer =
  | { ok: true }
  | { ok: false; mensaje: string; codigoValidado: boolean };
type ResultadoRegistro =
  | { ok: true; requiereVerificacion: boolean }
  | { ok: false; mensaje: string };

type AuthContextType = {
  /** Nombre para mostrar: nombre completo del perfil o, mientras carga, el correo */
  usuario?: string;
  perfil?: Perfil;
    /** Modos que puede usar según su rol en la base (utils/roles.ts) */
  roles: Rol[];
  /** Modo con el que está usando la app ahora; decide qué pestañas se ven */
  rolActivo: Rol;
  cambiarRolActivo: (rol: Rol) => void;
  sesion: boolean;
  /** true mientras se lee la sesión guardada al abrir la app */
  cargando: boolean;
  iniciarSesion: (correo: string, contrasena: string) => Promise<ResultadoLogin>;
  registrar: (nombre: string, correo: string, contrasena: string) => Promise<ResultadoRegistro>;
  verificarCodigo: (correo: string, codigo: string) => Promise<Resultado>;
  reenviarCodigo: (correo: string) => Promise<Resultado>;
    /** Envía al correo el código para restablecer la contraseña */
  solicitarRecuperacion: (correo: string) => Promise<Resultado>;
  /** Valida el código, guarda la contraseña nueva y deja la sesión iniciada */
    restablecerContrasena: (
    correo: string,
    codigo: string,
    nueva: string
  ) => Promise<ResultadoRestablecer>;
  /** Cierra la sesión temporal si el usuario abandona el restablecimiento a medias */
  cancelarRecuperacion: () => Promise<void>;
  cerrarSesion: () => Promise<void>;
    /** Elimina la cuenta del usuario con sesión (el perfil queda anonimizado) */
  eliminarCuenta: () => Promise<Resultado>;
};

const AuthContext = createContext<AuthContextType | undefined>(undefined);

function mensajeDeError(codigo?: string): string {
  switch (codigo) {
    case 'invalid_credentials':
      return 'Correo o contraseña incorrectos';
    case 'email_not_confirmed':
      return 'Primero verifica tu correo institucional';
    case 'over_request_rate_limit':
    case 'over_email_send_rate_limit':
      return 'Demasiados intentos. Espera unos minutos';
    default:
      return 'No se pudo iniciar sesión. Revisa tu conexión';
  }
}

function mensajeDeErrorRegistro(codigo?: string): string {
  switch (codigo) {
    case 'weak_password':
      return 'La contraseña necesita mayúscula, minúscula y número';
    case 'user_already_exists':
    case 'email_exists':
      return 'Ya existe una cuenta con este correo';
    case 'over_email_send_rate_limit':
    case 'over_request_rate_limit':
      return 'Se alcanzó el límite de correos. Intenta en unos minutos';
    case 'otp_expired':
      return 'El código no es válido o ya venció';
    case 'same_password':
      return 'La contraseña nueva debe ser distinta a la anterior';
    default:
      // El trigger de dominio (validar_dominio_correo) llega aquí como error genérico de base de datos
      return 'No se pudo completar. Verifica que el correo sea institucional e inténtalo de nuevo';
  }
}

const normalizar = (correo: string) => correo.trim().toLowerCase();

export function AuthProvider({ children }: { children: ReactNode }) {
  const [session, setSession] = useState<Session | null>(null);
  const [perfil, setPerfil] = useState<Perfil>();
  const [cargando, setCargando] = useState(true);
  const [rolPreferido, setRolPreferido] = useState<Rol>();
    // Mientras se restablece la contraseña no se publica la sesión: si no, la app saltaría
  // a las pestañas al validar el código y antes de guardar la contraseña nueva
  const sesionEnPausa = useRef(false);
    // true cuando el código ya se validó (y se gastó) pero la contraseña nueva aún no se guarda
  const codigoValidado = useRef(false);

  // Sesión guardada (AsyncStorage) y cambios de sesión: login, logout, token renovado
  useEffect(() => {
    supabase.auth.getSession().then(({ data }) => {
      setSession(data.session);
      setCargando(false);
    });

    // No llamar a supabase dentro de este callback: puede bloquear el cliente
    const { data } = supabase.auth.onAuthStateChange((_evento, nueva) => {
      if (!sesionEnPausa.current) setSession(nueva);
    });
    return () => data.subscription.unsubscribe();
  }, []);

  // Perfil del usuario (RLS: cada quien solo puede leer el suyo)
  const userId = session?.user.id;
  useEffect(() => {
    if (!userId) {
      setPerfil(undefined);
      setRolPreferido(undefined); // quien entre después empieza en su modo por defecto
      return;
    }
    let vigente = true;
    supabase
      .from('perfiles')
      .select('id, email, nombre_completo, rol')
      .eq('id', userId)
      .maybeSingle()
      .then(({ data, error }) => {
        if (!vigente) return;
        if (error) console.warn('[auth] perfil:', error.message);
        setPerfil(
          data
            ? {
                id: data.id,
                email: data.email,
                nombreCompleto: data.nombre_completo,
                rol: data.rol,
              }
            : undefined
        );
      });
    return () => {
      vigente = false;
    };
  }, [userId]);

  const iniciarSesion = async (correo: string, contrasena: string): Promise<ResultadoLogin> => {
    const { error } = await supabase.auth.signInWithPassword({
      email: normalizar(correo),
      password: contrasena,
    });
    if (error) {
      console.warn('[auth] login:', error.code, error.message);
      return {
        ok: false,
        mensaje: mensajeDeError(error.code),
        sinVerificar: error.code === 'email_not_confirmed',
      };
    }
    return { ok: true };
  };

  // Con "Confirm email" activo (staging) no hay sesión hasta verificar el código;
  // sin él (local) Supabase devuelve la sesión de una vez y entra directo.
  const registrar = async (
    nombre: string,
    correo: string,
    contrasena: string
  ): Promise<ResultadoRegistro> => {
    const { data, error } = await supabase.auth.signUp({
      email: normalizar(correo),
      password: contrasena,
            // Los lee el trigger crear_perfil: crea el perfil y registra la aceptación de los términos
      options: { data: { nombre_completo: nombre.trim(), terminos_version: VERSION_LEGAL } },
    });
    if (error) {
      console.warn('[auth] registro:', error.code, error.message);
      return { ok: false, mensaje: mensajeDeErrorRegistro(error.code) };
    }
    // Si el correo ya estaba confirmado, Supabase no da error (para no revelar qué
    // correos existen) pero devuelve un usuario sin identidades.
    if (data.user && data.user.identities?.length === 0) {
      return { ok: false, mensaje: mensajeDeErrorRegistro('user_already_exists') };
    }
    return { ok: true, requiereVerificacion: data.session === null };
  };

  // Al verificar, Supabase crea la sesión y onAuthStateChange lleva a la app
  const verificarCodigo = async (correo: string, codigo: string): Promise<Resultado> => {
    const { error } = await supabase.auth.verifyOtp({
      email: normalizar(correo),
      token: codigo.trim(),
      type: 'email',
    });
    if (error) {
      console.warn('[auth] verificar:', error.code, error.message);
      return { ok: false, mensaje: mensajeDeErrorRegistro(error.code) };
    }
    return { ok: true };
  };

  const reenviarCodigo = async (correo: string): Promise<Resultado> => {
    const { error } = await supabase.auth.resend({ type: 'signup', email: normalizar(correo) });
    if (error) {
      console.warn('[auth] reenviar:', error.code, error.message);
      return { ok: false, mensaje: mensajeDeErrorRegistro(error.code) };
    }
    return { ok: true };
  };

  // Supabase responde igual exista o no la cuenta (para no revelar qué correos están registrados)
  const solicitarRecuperacion = async (correo: string): Promise<Resultado> => {
    const { error } = await supabase.auth.resetPasswordForEmail(normalizar(correo));
    if (error) {
      console.warn('[auth] recuperar:', error.code, error.message);
      return { ok: false, mensaje: mensajeDeErrorRegistro(error.code) };
    }
    return { ok: true };
  };

    // Supabase gasta el código apenas lo valida. Si la contraseña nueva falla (por ejemplo, es
  // igual a la anterior), se conserva la sesión temporal para reintentar sin pedir otro código.
  const restablecerContrasena = async (
    correo: string,
    codigo: string,
    nueva: string
  ): Promise<ResultadoRestablecer> => {
    sesionEnPausa.current = true;

    // 1. Validar el código (solo la primera vez): abre una sesión temporal
    if (!codigoValidado.current) {
      const { error } = await supabase.auth.verifyOtp({
        email: normalizar(correo),
        token: codigo.trim(),
        type: 'recovery',
      });
      if (error) {
        console.warn('[auth] código recuperación:', error.code, error.message);
        sesionEnPausa.current = false;
        return { ok: false, mensaje: mensajeDeErrorRegistro(error.code), codigoValidado: false };
      }
      codigoValidado.current = true;
    }

    // 2. Guardar la contraseña nueva con esa sesión temporal
    const { error } = await supabase.auth.updateUser({ password: nueva });
    if (error) {
      console.warn('[auth] nueva contraseña:', error.code, error.message);
      // La sesión sigue en pausa: el usuario puede intentar con otra contraseña
      return { ok: false, mensaje: mensajeDeErrorRegistro(error.code), codigoValidado: true };
    }

    // 3. Listo: se publica la sesión y la app entra a las pestañas
    codigoValidado.current = false;
    sesionEnPausa.current = false;
    const { data } = await supabase.auth.getSession();
    setSession(data.session);
    return { ok: true };
  };

  const cancelarRecuperacion = async () => {
    if (!codigoValidado.current) return;
    codigoValidado.current = false;
    await supabase.auth.signOut(); // en pausa: la app no se entera de esta sesión
    sesionEnPausa.current = false;
  };

    // El modo activo es el que eligió el usuario, si su rol lo permite; si no, el primero de sus modos
  const roles: Rol[] = perfil ? rolesDesdeBase(perfil.rol) : [];
  const rolActivo: Rol =
    rolPreferido && roles.includes(rolPreferido) ? rolPreferido : (roles[0] ?? 'solicitante');

  const cambiarRolActivo = (rol: Rol) => {
    if (roles.includes(rol)) setRolPreferido(rol);
  };

    const eliminarCuenta = async (): Promise<Resultado> => {
    const { error } = await supabase.rpc('eliminar_mi_cuenta');
    if (error) {
      console.warn('[auth] eliminar cuenta:', error.code, error.message);
      const mensajes: Record<string, string> = {
        DD001: 'Tienes un pedido en curso. Espera a que termine para eliminar tu cuenta',
        DD002: 'Eres el único administrador. Asigna otro antes de eliminar tu cuenta',
      };
      return {
        ok: false,
        mensaje: mensajes[error.code] ?? 'No se pudo eliminar la cuenta. Inténtalo de nuevo',
      };
    }
    // El usuario ya no existe en el servidor: se borra la sesión guardada en el celular
    await supabase.auth.signOut({ scope: 'local' });
    return { ok: true };
  };

  const cerrarSesion = async () => {
    const { error } = await supabase.auth.signOut();
    if (error) console.warn('[auth] logout:', error.message);
  };

  return (
    <AuthContext.Provider
      value={{
        usuario: perfil?.nombreCompleto ?? session?.user.email,
        perfil,
        roles,
        rolActivo,
        cambiarRolActivo,
        sesion: session !== null,
        cargando,
        iniciarSesion,
        registrar,
        verificarCodigo,
        reenviarCodigo,
        solicitarRecuperacion,
        restablecerContrasena,
        cancelarRecuperacion,
        cerrarSesion,
        eliminarCuenta,
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