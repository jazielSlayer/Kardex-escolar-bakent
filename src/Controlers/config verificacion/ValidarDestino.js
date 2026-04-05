import dns from "dns";

// ── Validar formato y existencia real del email ───────────────
export const validarEmail = async (email) => {

  // 1. Validar que no esté vacío
  if (!email || email.trim() === "") {
    return {
      valido: false,
      mensaje: "El correo electrónico no puede estar vacío.",
    };
  }

  // 2. Validar formato básico
  const formatoValido = /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email.trim());
  if (!formatoValido) {
    return {
      valido: false,
      mensaje: "El correo electrónico no tiene un formato válido.",
    };
  }

  // 3. Verificar que el dominio tiene registros MX
  const dominio = email.split("@")[1];

  try {
    // Timeout de 5 segundos para no bloquear el servidor
    const registrosMX = await Promise.race([
      dns.promises.resolveMx(dominio),
      new Promise((_, reject) =>
        setTimeout(() => reject(new Error("timeout")), 5000)
      ),
    ]);

    if (!registrosMX || registrosMX.length === 0) {
      return {
        valido: false,
        mensaje: `El dominio "${dominio}" no acepta correos.`,
      };
    }

    return { valido: true, mensaje: null };

  } catch (err) {

    // Si es timeout o error de red, aceptar el correo
    // para no bloquear el flujo por problemas de conectividad
    if (err.message === "timeout" || err.code === "ECONNREFUSED") {
      console.warn(`[validarEmail] No se pudo verificar DNS de "${dominio}", se permite por defecto.`);
      return { valido: true, mensaje: null };
    }

    // ENOTFOUND = dominio realmente no existe
    if (err.code === "ENOTFOUND" || err.code === "ENODATA") {
      return {
        valido: false,
        mensaje: `El dominio "${dominio}" no existe.`,
      };
    }

    // Cualquier otro error de DNS → permitir para no bloquear
    console.warn(`[validarEmail] Error DNS inesperado (${err.code}), se permite por defecto.`);
    return { valido: true, mensaje: null };
  }
};

// ── Validar formato del teléfono boliviano ────────────────────
export const validarTelefono = (telefono) => {

  if (!telefono || telefono.trim() === "") {
    return {
      valido: false,
      mensaje: "El número de teléfono no puede estar vacío.",
    };
  }

  // Limpiar espacios, guiones, paréntesis, +
  const limpio = telefono.replace(/[\s\-().+]/g, "");

  // Bolivia: celulares 8 dígitos empezando en 6 o 7
  // Con código de país: 591 seguido de 8 dígitos
  const formatoBoliviano = /^(?:591)?(6|7)\d{7}$/.test(limpio);

  if (!formatoBoliviano) {
    return {
      valido: false,
      mensaje: "El número de teléfono no es válido. Debe ser un celular boliviano (ej: 71234567).",
    };
  }

  // Normalizar al formato internacional para Twilio
  const normalizado = limpio.startsWith("591")
    ? `+${limpio}`
    : `+591${limpio}`;

  return { valido: true, normalizado, mensaje: null };
};