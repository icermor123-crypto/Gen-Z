// Configuración pública de Supabase. La anon/publishable key NO es una contraseña.
// La seguridad depende de RLS y las funciones SQL incluidas en supabase/schema.sql.
window.GENZ_CONFIG = {
  supabaseUrl: 'PEGA_AQUI_LA_URL_DEL_PROYECTO_SUPABASE',
  supabaseAnonKey: 'PEGA_AQUI_LA_CLAVE_ANON_O_PUBLISHABLE',
  // Identificador por defecto para que la tienda aparezca en la URL raíz del sitio.
  defaultStoreSlug: 'TU-IDENTIFICADOR'
};
