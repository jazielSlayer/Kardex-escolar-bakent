import { connect } from "../database.js";

export const registrarAnotacion = async (req, res) => {
  const pool = connect();

  try {
    const {
      nombre_estudiante,
      apellido_estudiante,
      nombre_reporta,
      apellido_reporta,
      fecha_incidente    = null,
      tipo_falta,
      categoria          = null,
      descripcion,
      sancion            = null,
      fecha_sancion      = null,
      notificado_padres  = 0,
      fecha_notificacion = null,
      seguimiento        = null,
    } = req.body;

    // ── Validaciones de campos obligatorios ───────────────
    const camposObligatorios = {
      nombre_estudiante,
      apellido_estudiante,
      nombre_reporta,
      apellido_reporta,
      tipo_falta,
      descripcion,
    };

    const faltantes = Object.entries(camposObligatorios)
      .filter(([, v]) => v === undefined || v === null || v === "")
      .map(([k]) => k);

    if (faltantes.length > 0) {
      return res.status(400).json({
        ok: false,
        mensaje: `Faltan campos obligatorios: ${faltantes.join(", ")}`,
      });
    }

    const tiposValidos = ["Leve", "Moderada", "Grave", "Muy_grave"];
    if (!tiposValidos.includes(tipo_falta)) {
      return res.status(400).json({
        ok: false,
        mensaje: `Tipo de falta inválido. Valores permitidos: ${tiposValidos.join(", ")}`,
      });
    }

    // ── Verificar que el estudiante esté registrado ───────
    const [[{ total_estudiantes }]] = await pool.query(
      `SELECT COUNT(*) AS total_estudiantes
       FROM estudiante e
       INNER JOIN users    u ON e.ID_User    = u.id
       INNER JOIN persona  p ON u.ID_Persona = p.id
       WHERE p.Nombre   LIKE CONCAT('%', ?, '%')
         AND p.Apellido LIKE CONCAT('%', ?, '%')
         AND e.Estado = 'Activo'`,
      [nombre_estudiante.trim(), apellido_estudiante.trim()]
    );

    if (total_estudiantes === 0) {
      return res.status(404).json({
        ok: false,
        mensaje: `No se encontró ningún estudiante activo con el nombre "${nombre_estudiante} ${apellido_estudiante}". Verifique que esté registrado en el sistema.`,
      });
    }

    if (total_estudiantes > 1) {
      return res.status(409).json({
        ok: false,
        mensaje: `Se encontraron ${total_estudiantes} estudiantes con el nombre "${nombre_estudiante} ${apellido_estudiante}". Use un nombre más específico.`,
      });
    }

    // ── Verificar que el docente/administrativo esté registrado ──
    const [[{ total_reporta }]] = await pool.query(
      `SELECT COUNT(*) AS total_reporta
       FROM users   u
       INNER JOIN persona p ON u.ID_Persona = p.id
       INNER JOIN roles   r ON u.ID_Rol     = r.id
       WHERE p.Nombre   LIKE CONCAT('%', ?, '%')
         AND p.Apellido LIKE CONCAT('%', ?, '%')
         AND u.Estado = 'Activo'
         AND r.Nombre IN ('Docente', 'Administrador', 'Director', 'Secretaria')`,
      [nombre_reporta.trim(), apellido_reporta.trim()]
    );

    if (total_reporta === 0) {
      return res.status(404).json({
        ok: false,
        mensaje: `No se encontró ningún docente o administrativo activo con el nombre "${nombre_reporta} ${apellido_reporta}". Verifique que esté registrado en el sistema.`,
      });
    }

    if (total_reporta > 1) {
      return res.status(409).json({
        ok: false,
        mensaje: `Se encontraron ${total_reporta} usuarios con el nombre "${nombre_reporta} ${apellido_reporta}". Use un nombre más específico.`,
      });
    }

    // ── Llamada al procedimiento almacenado ───────────────
    await pool.query(
      `CALL sp_registrar_anotacion_estudiante(
        ?, ?, ?, ?,
        ?, ?, ?, ?,
        ?, ?, ?, ?, ?,
        @id_reporte, @codigo_estudiante,
        @nombre_completo_est, @nombre_completo_rep,
        @mensaje
      )`,
      [
        nombre_estudiante,   apellido_estudiante,
        nombre_reporta,      apellido_reporta,
        fecha_incidente,     tipo_falta,         categoria,
        descripcion,         sancion,            fecha_sancion,
        notificado_padres,   fecha_notificacion, seguimiento,
      ]
    );

    // ── Leer variables de salida ──────────────────────────
    const [[resultado]] = await pool.query(`
      SELECT
        @id_reporte            AS id_reporte,
        @codigo_estudiante     AS codigo_estudiante,
        @nombre_completo_est   AS estudiante,
        @nombre_completo_rep   AS reportado_por,
        @mensaje               AS mensaje
    `);

    if (resultado.mensaje?.startsWith("Error:")) {
      return res.status(409).json({
        ok: false,
        mensaje: resultado.mensaje,
      });
    }

    return res.status(201).json({
      ok: true,
      mensaje: resultado.mensaje,
      data: {
        id_reporte:        resultado.id_reporte,
        codigo_estudiante: resultado.codigo_estudiante,
        estudiante:        resultado.estudiante,
        reportado_por:     resultado.reportado_por,
      },
    });

  } catch (error) {
    console.error("[registrarAnotacion]", error);
    return res.status(500).json({
      ok: false,
      mensaje: "Error interno del servidor.",
      detalle: process.env.NODE_ENV === "development" ? error.message : undefined,
    });
  }
};

export const obtenerAnotaciones = async (req, res) => {
  const pool = connect();
  try {
    const [rows] = await pool.query(`SELECT * FROM v_anotaciones`);

    return res.status(200).json({
      ok: true,
      total: rows.length,
      data: rows,
    });

  } catch (error) {
    console.error("[obtenerAnotaciones]", error);
    return res.status(500).json({
      ok: false,
      mensaje: "Error interno del servidor.",
      detalle: process.env.NODE_ENV === "development" ? error.message : undefined,
    });
  }
};


export const obtenerAnotacionesPorEstudiante = async (req, res) => {
  const pool = connect();
  try {
    const { nombre, apellido } = req.query;

    if (!nombre || !apellido) {
      return res.status(400).json({
        ok: false,
        mensaje: "Proporcione nombre y apellido. Ej: ?nombre=Santiago&apellido=Sánchez",
      });
    }

    const [rows] = await pool.query(
      `CALL sp_obtener_anotaciones_por_estudiante(?, ?)`,
      [nombre.trim(), apellido.trim()]
    );

    const data = rows[0]; // mysql2 devuelve el resultado del SELECT en rows[0]

    if (!data.length) {
      return res.status(404).json({
        ok: false,
        mensaje: `No se encontraron anotaciones para "${nombre} ${apellido}".`,
      });
    }

    return res.status(200).json({
      ok: true,
      total: data.length,
      estudiante: data[0].estudiante,
      codigo_estudiante: data[0].codigo_estudiante,
      data,
    });

  } catch (error) {
    console.error("[obtenerAnotacionesPorEstudiante]", error);
    return res.status(500).json({
      ok: false,
      mensaje: "Error interno del servidor.",
      detalle: process.env.NODE_ENV === "development" ? error.message : undefined,
    });
  }
};


export const actualizarEstadoAnotacion = async (req, res) => {
  const pool = connect();

  try {
    const { nombre, apellido, fecha_incidente, estado, seguimiento = null } = req.body;
    const usuarioId = req.user?.id ?? 1;

    const estadosValidos = ["Abierto", "En_proceso", "Resuelto", "Cerrado"];
    if (!estado || !estadosValidos.includes(estado)) {
      return res.status(400).json({
        ok: false,
        mensaje: `Estado inválido. Valores permitidos: ${estadosValidos.join(", ")}`,
      });
    }

    if (!fecha_incidente) {
      return res.status(400).json({
        ok: false,
        mensaje: "La fecha del incidente es obligatoria.",
      });
    }

    await pool.query(
      `CALL sp_actualizar_estado_anotacion(?, ?, ?, ?, ?, ?, @id_rep, @nombre_est, @msg)`,
      [nombre, apellido, fecha_incidente, estado, seguimiento, usuarioId]
    );

    const [[result]] = await pool.query(
      `SELECT @id_rep AS id_reporte, @nombre_est AS estudiante, @msg AS mensaje`
    );

    const { id_reporte, estudiante, mensaje } = result;

    if (!id_reporte) {
      return res.status(404).json({ ok: false, mensaje });
    }

    return res.status(200).json({ ok: true, mensaje, id_reporte, estudiante });

  } catch (error) {
    console.error("[actualizarEstadoAnotacion]", error);
    return res.status(500).json({
      ok: false,
      mensaje: "Error interno del servidor.",
      detalle: process.env.NODE_ENV === "development" ? error.message : undefined,
    });
  }
};