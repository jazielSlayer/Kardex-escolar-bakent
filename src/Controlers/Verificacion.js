import { connect }        from "../database.js";
import { validarEmail, validarTelefono } from "../Controlers/config verificacion/ValidarDestino.js";
import { enviarEmail, enviarSMS }        from "../Controlers/config verificacion/enviarCodigo.js";

// ── LOGIN ─────────────────────────────────────────────────────
export const login = async (req, res) => {
  const pool = connect();
  try {
    const { correo, password } = req.body;
    const ip         = req.ip || req.headers["x-forwarded-for"] || null;
    const user_agent = req.headers["user-agent"] || null;

    if (!correo || !password) {
      return res.status(400).json({
        ok: false,
        mensaje: "Correo y contraseña son obligatorios.",
      });
    }

    await pool.query(
      `CALL sp_login(?, ?, ?, ?,
        @id_user, @id_rol, @nombre_rol,
        @nombre_completo, @requiere_2fa, @mensaje)`,
      [correo, password, ip, user_agent]
    );

    const [[resultado]] = await pool.query(`
      SELECT
        @id_user         AS id_user,
        @id_rol          AS id_rol,
        @nombre_rol      AS nombre_rol,
        @nombre_completo AS nombre_completo,
        @requiere_2fa    AS requiere_2fa,
        @mensaje         AS mensaje
    `);

    if (resultado.mensaje?.startsWith("Error:")) {
      return res.status(401).json({ ok: false, mensaje: resultado.mensaje });
    }

    if (!resultado.requiere_2fa) {
      return res.status(200).json({
        ok: true,
        mensaje: resultado.mensaje,
        requiere_2fa: false,
        data: {
          id_user:         resultado.id_user,
          id_rol:          resultado.id_rol,
          nombre_rol:      resultado.nombre_rol,
          nombre_completo: resultado.nombre_completo,
        },
      });
    }

    return res.status(200).json({
      ok: true,
      mensaje: resultado.mensaje,
      requiere_2fa: true,
      data: {
        id_user:         resultado.id_user,
        nombre_completo: resultado.nombre_completo,
        nombre_rol:      resultado.nombre_rol,
      },
    });

  } catch (error) {
    console.error("[login]", error);
    return res.status(500).json({ ok: false, mensaje: "Error interno del servidor." });
  }
};

// ── GENERAR Y ENVIAR CÓDIGO 2FA ───────────────────────────────
export const generarCodigo2FA = async (req, res) => {
  const pool = connect();
  try {
    const { id_user, metodo } = req.body;
    const ip = req.ip || req.headers["x-forwarded-for"] || null;

    // ── Validar parámetros básicos ────────────────────────────
    if (!id_user || !metodo) {
      return res.status(400).json({ ok: false, mensaje: "Faltan parámetros." });
    }

    if (!["Email", "Telefono"].includes(metodo)) {
      return res.status(400).json({
        ok: false,
        mensaje: 'El método debe ser "Email" o "Telefono".',
      });
    }

    // ── Llamar al SP para generar el código ───────────────────
    await pool.query(
      `CALL sp_generar_codigo_2fa(?, ?, ?, @id_verificacion, @destino, @mensaje)`,
      [id_user, metodo, ip]
    );

    const [[resultado]] = await pool.query(`
      SELECT
        @id_verificacion AS id_verificacion,
        @destino         AS destino,
        @mensaje         AS mensaje
    `);

    if (resultado.mensaje?.startsWith("Error:")) {
      return res.status(409).json({ ok: false, mensaje: resultado.mensaje });
    }

    const destino = resultado.destino;

    // ── Validar que el destino existe en la realidad ──────────
    if (metodo === "Email") {
      const { valido, mensaje } = await validarEmail(destino);
      if (!valido) {
        return res.status(422).json({
          ok: false,
          mensaje: `El correo registrado no es válido: ${mensaje}`,
        });
      }
    }

    if (metodo === "Telefono") {
      const { valido, mensaje } = validarTelefono(destino);
      if (!valido) {
        return res.status(422).json({
          ok: false,
          mensaje: `El teléfono registrado no es válido: ${mensaje}`,
        });
      }
    }

    // ── Obtener el código desde la tabla verificacion ─────────
    const [[{ codigo }]] = await pool.query(
      `SELECT SUBSTRING_INDEX(Token, '|', 1) AS codigo
       FROM verificacion
       WHERE id = ?`,
      [resultado.id_verificacion]
    );

    // ── Enviar el código al destino ───────────────────────────
    try {
      if (metodo === "Email") {
        await enviarEmail(destino, codigo);
      } else {
        // Normalizar el teléfono al formato internacional
        const { normalizado } = validarTelefono(destino);
        await enviarSMS(normalizado, codigo);
      }
    } catch (errorEnvio) {
      console.error("[generarCodigo2FA] Error al enviar:", errorEnvio);

      // Si falla el envío, retornar error claro al frontend
      return res.status(502).json({
        ok: false,
        mensaje:
          metodo === "Email"
            ? "No se pudo enviar el correo. Verifique que el correo registrado sea correcto."
            : "No se pudo enviar el SMS. Verifique que el número registrado sea correcto.",
      });
    }

    // ── Respuesta exitosa ─────────────────────────────────────
    return res.status(200).json({
      ok: true,
      mensaje: `Código enviado correctamente a tu ${metodo === "Email" ? "correo" : "teléfono"}.`,
      data: {
        id_verificacion: resultado.id_verificacion,
        destino_parcial: ocultarDestino(destino, metodo),
      },
    });

  } catch (error) {
    console.error("[generarCodigo2FA]", error);
    return res.status(500).json({ ok: false, mensaje: "Error interno del servidor." });
  }
};

// ── VERIFICAR CÓDIGO 2FA ──────────────────────────────────────
export const verificarCodigo2FA = async (req, res) => {
  const pool = connect();
  try {
    const { id_user, id_verificacion, codigo } = req.body;
    const ip = req.ip || req.headers["x-forwarded-for"] || null;

    if (!id_user || !id_verificacion || !codigo) {
      return res.status(400).json({ ok: false, mensaje: "Faltan parámetros." });
    }

    await pool.query(
      `CALL sp_verificar_codigo_2fa(?, ?, ?, ?, @verificado, @mensaje)`,
      [id_user, id_verificacion, codigo, ip]
    );

    const [[resultado]] = await pool.query(`
      SELECT
        @verificado AS verificado,
        @mensaje    AS mensaje
    `);

    if (!resultado.verificado) {
      return res.status(401).json({ ok: false, mensaje: resultado.mensaje });
    }

    return res.status(200).json({
      ok: true,
      mensaje: resultado.mensaje,
      // token: jwt.sign({ id_user }, process.env.JWT_SECRET, { expiresIn: '8h' })
    });

  } catch (error) {
    console.error("[verificarCodigo2FA]", error);
    return res.status(500).json({ ok: false, mensaje: "Error interno del servidor." });
  }
};

// ── Utilidad: ocultar destino ─────────────────────────────────
function ocultarDestino(destino, metodo) {
  if (!destino) return null;
  if (metodo === "Email") {
    const [user, domain] = destino.split("@");
    return `${user.slice(0, 2)}***@${domain}`;
  }
  return `+591 ****${destino.slice(-4)}`;
}