import { connect } from "../database.js";

export const inscribirEstudiante = async (req, res) => {
  // ▼ connect() devuelve el pool, no hay que abrir ni cerrar nada
  const pool = connect();

  try {
    const {
      // ── Datos personales del estudiante ──────────────────
      nombre,
      apellido,
      ci,
      fecha_nacimiento,
      genero,
      direccion,
      telefono,
      email_personal,
      nacionalidad           = "Boliviana",
      estado_civil           = null,
      // ── Acceso del estudiante ─────────────────────────────
      correo,
      password,
      // ── Datos médicos ──────────────────────────────────────
      tipo_sangre            = null,
      alergias               = null,
      condiciones_medicas    = null,
      medicamentos           = null,
      seguro_medico          = null,
      numero_hermanos        = 0,
      posicion_hermanos      = null,
      vive_con               = null,
      necesidades_especiales = null,
      transporte             = null,
      // ── Datos de inscripción ───────────────────────────────
      id_grado,
      tipo_inscripcion,
      colegio_procedencia    = null,
      motivo_traslado        = null,
      monto_matricula        = 0,
      descuento_matricula    = 0,
      tipo_estudiante        = "Regular",
      requiere_apoyo         = 0,
      observaciones          = null,
      usuario_registra,
      // ── Tutores ────────────────────────────────────────────
      tutor1 = {},
      tutor2 = null,
    } = req.body;

    // ── Validaciones ──────────────────────────────────────
    const camposObligatorios = {
      nombre, apellido, ci, fecha_nacimiento, genero,
      correo, password, id_grado, tipo_inscripcion, usuario_registra,
    };

    const faltantes = Object.entries(camposObligatorios)
      .filter(([, v]) => v === undefined || v === null || v === "")
      .map(([k]) => k);

    if (faltantes.length > 0) {
      return res.status(400).json({
        ok: false,
        mensaje: `Faltan campos del estudiante: ${faltantes.join(", ")}`,
      });
    }

    const camposT1 = ["nombre", "apellido", "ci", "correo", "password", "parentesco"];
    const faltantesT1 = camposT1.filter((k) => !tutor1[k] || tutor1[k] === "");

    if (faltantesT1.length > 0) {
      return res.status(400).json({
        ok: false,
        mensaje: `Faltan campos del tutor 1: ${faltantesT1.join(", ")}`,
      });
    }

    // ── Desestructurar tutor 1 ────────────────────────────
    const {
      nombre:                   p1_nombre,
      apellido:                 p1_apellido,
      ci:                       p1_ci,
      fecha_nacimiento:         p1_fecha_nacimiento          = null,
      genero_persona:           p1_genero_persona            = null,
      direccion:                p1_direccion                 = null,
      telefono:                 p1_telefono                  = null,
      email_personal:           p1_email_personal            = null,
      nacionalidad:             p1_nacionalidad              = "Boliviana",
      estado_civil:             p1_estado_civil              = null,
      correo:                   p1_correo,
      password:                 p1_password,
      genero_padre:             p1_genero_padre              = null,
      ocupacion:                p1_ocupacion                 = null,
      lugar_trabajo:            p1_lugar_trabajo             = null,
      telefono_trabajo:         p1_telefono_trabajo          = null,
      nivel_educativo:          p1_nivel_educativo           = null,
      ingreso_mensual:          p1_ingreso_mensual           = null,
      parentesco:               p1_parentesco,
      es_responsable_economico: p1_es_responsable_economico = 1,
      es_contacto_emergencia:   p1_es_contacto_emergencia   = 1,
      puede_retirar:            p1_puede_retirar             = 1,
      vive_con_estudiante:      p1_vive_con_estudiante       = 1,
    } = tutor1;

    // ── Desestructurar tutor 2 ────────────────────────────
    const {
      nombre:                   p2_nombre                    = null,
      apellido:                 p2_apellido                  = null,
      ci:                       p2_ci                        = null,
      fecha_nacimiento:         p2_fecha_nacimiento          = null,
      genero_persona:           p2_genero_persona            = null,
      direccion:                p2_direccion                 = null,
      telefono:                 p2_telefono                  = null,
      email_personal:           p2_email_personal            = null,
      nacionalidad:             p2_nacionalidad              = null,
      estado_civil:             p2_estado_civil              = null,
      correo:                   p2_correo                    = null,
      password:                 p2_password                  = null,
      genero_padre:             p2_genero_padre              = null,
      ocupacion:                p2_ocupacion                 = null,
      lugar_trabajo:            p2_lugar_trabajo             = null,
      telefono_trabajo:         p2_telefono_trabajo          = null,
      nivel_educativo:          p2_nivel_educativo           = null,
      ingreso_mensual:          p2_ingreso_mensual           = null,
      parentesco:               p2_parentesco                = null,
      es_responsable_economico: p2_es_responsable_economico = null,
      es_contacto_emergencia:   p2_es_contacto_emergencia   = null,
      puede_retirar:            p2_puede_retirar             = null,
      vive_con_estudiante:      p2_vive_con_estudiante       = null,
    } = tutor2 ?? {};

    // ── SQL ───────────────────────────────────────────────
    const sql = `
      CALL sp_inscribir_estudiante(
        ?, ?, ?, ?, ?, ?, ?, ?, ?, ?,
        ?, ?,
        ?, ?, ?, ?, ?, ?, ?, ?, ?, ?,
        ?, ?, ?, ?, ?, ?, ?, ?, ?, ?,
        ?, ?, ?, ?, ?, ?, ?, ?, ?, ?,
        ?, ?,
        ?, ?, ?, ?, ?, ?,
        ?, ?, ?, ?, ?,
        ?, ?, ?, ?, ?, ?, ?, ?, ?, ?,
        ?, ?,
        ?, ?, ?, ?, ?, ?,
        ?, ?, ?, ?, ?,
        @id_persona, @id_user, @id_estudiante,
        @id_inscripcion, @id_matricula,
        @codigo_estudiante, @numero_matricula,
        @id_padre1, @id_padre2, @mensaje
      )
    `;

    const params = [
      // Estudiante — datos personales (10)
      nombre, apellido, ci, fecha_nacimiento, genero,
      direccion, telefono, email_personal, nacionalidad, estado_civil,
      // Estudiante — acceso (2)
      correo, password,
      // Estudiante — médicos (10)
      tipo_sangre, alergias, condiciones_medicas, medicamentos, seguro_medico,
      numero_hermanos, posicion_hermanos, vive_con, necesidades_especiales, transporte,
      // Inscripción (10)
      id_grado, tipo_inscripcion, colegio_procedencia, motivo_traslado,
      monto_matricula, descuento_matricula, tipo_estudiante,
      requiere_apoyo, observaciones, usuario_registra,
      // Tutor 1 — datos personales (10)
      p1_nombre, p1_apellido, p1_ci, p1_fecha_nacimiento, p1_genero_persona,
      p1_direccion, p1_telefono, p1_email_personal, p1_nacionalidad, p1_estado_civil,
      // Tutor 1 — acceso (2)
      p1_correo, p1_password,
      // Tutor 1 — laboral (6)
      p1_genero_padre, p1_ocupacion, p1_lugar_trabajo,
      p1_telefono_trabajo, p1_nivel_educativo, p1_ingreso_mensual,
      // Tutor 1 — relación (5)
      p1_parentesco, p1_es_responsable_economico, p1_es_contacto_emergencia,
      p1_puede_retirar, p1_vive_con_estudiante,
      // Tutor 2 — datos personales (10)
      p2_nombre, p2_apellido, p2_ci, p2_fecha_nacimiento, p2_genero_persona,
      p2_direccion, p2_telefono, p2_email_personal, p2_nacionalidad, p2_estado_civil,
      // Tutor 2 — acceso (2)
      p2_correo, p2_password,
      // Tutor 2 — laboral (6)
      p2_genero_padre, p2_ocupacion, p2_lugar_trabajo,
      p2_telefono_trabajo, p2_nivel_educativo, p2_ingreso_mensual,
      // Tutor 2 — relación (5)
      p2_parentesco, p2_es_responsable_economico, p2_es_contacto_emergencia,
      p2_puede_retirar, p2_vive_con_estudiante,
    ];

    // ▼ pool.query() administra la conexión internamente
    await pool.query(sql, params);

    // ── Leer variables de salida ───────────────────────────
    const [[resultado]] = await pool.query(`
      SELECT
        @id_persona         AS id_persona,
        @id_user            AS id_user,
        @id_estudiante      AS id_estudiante,
        @id_inscripcion     AS id_inscripcion,
        @id_matricula       AS id_matricula,
        @codigo_estudiante  AS codigo_estudiante,
        @numero_matricula   AS numero_matricula,
        @id_padre1          AS id_padre1,
        @id_padre2          AS id_padre2,
        @mensaje            AS mensaje
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
        id_persona:        resultado.id_persona,
        id_user:           resultado.id_user,
        id_estudiante:     resultado.id_estudiante,
        codigo_estudiante: resultado.codigo_estudiante,
        id_inscripcion:    resultado.id_inscripcion,
        id_matricula:      resultado.id_matricula,
        numero_matricula:  resultado.numero_matricula,
        id_padre1:         resultado.id_padre1,
        id_padre2:         resultado.id_padre2,
      },
    });

  } catch (error) {
    console.error("[inscribirEstudiante]", error);
    return res.status(500).json({
      ok: false,
      mensaje: "Error interno del servidor.",
      detalle: process.env.NODE_ENV === "development" ? error.message : undefined,
    });
  }
  // ▼ SIN finally — el pool gestiona sus conexiones solo,
  //   nunca llamar pool.end() ni pool.release()
};