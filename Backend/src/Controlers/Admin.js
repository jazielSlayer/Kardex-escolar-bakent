import { connect } from "../database.js";



const parsearSecciones = (results) => {
  const grouped      = {};
  let currentSection = "DEFAULT";

  for (const resultSet of results) {
    if (!Array.isArray(resultSet) || resultSet.length === 0) continue;

    const firstRow = resultSet[0];
    const keys     = Object.keys(firstRow);

    // Fila-etiqueta de sección → columna única "Seccion", una sola fila
    if (keys.length === 1 && keys[0] === "Seccion" && resultSet.length === 1) {
      currentSection = firstRow.Seccion;
      continue;
    }

    grouped[currentSection] = resultSet;
  }

  return grouped;
};


export const getDashboardKpi = async (req, res) => {
  const pool = connect();

  try {
    const [results] = await pool.query("CALL sp_admin_dashboard_kpi()");

    // Este SP devuelve un solo result-set sin secciones
    const kpi = Array.isArray(results[0]) ? results[0][0] : results[0];

    return res.status(200).json({
      ok:   true,
      data: kpi,
    });
  } catch (error) {
    console.error("[getDashboardKpi]", error);
    return res.status(500).json({
      ok:      false,
      mensaje: "Error interno del servidor.",
      detalle: process.env.NODE_ENV === "development" ? error.message : undefined,
    });
  }
};

export const getResumenEstudiantes = async (req, res) => {
  const pool = connect();

  try {
    const idAnio = req.query.anio ? Number(req.query.anio) : null;

    const [results] = await pool.query(
      "CALL sp_admin_resumen_estudiantes(?)",
      [idAnio]
    );

    const s = parsearSecciones(results);

    return res.status(200).json({
      ok:   true,
      data: {
        totalesPorEstado:             s.TOTALES_POR_ESTADO              ?? [],
        matriculadosVsNoMatriculados: s.MATRICULADOS_VS_NO_MATRICULADOS  ?? [],
        porcentajePorNivelEducativo:  s.PORCENTAJE_POR_NIVEL_EDUCATIVO   ?? [],
        porcentajePorGrado:           s.PORCENTAJE_POR_GRADO             ?? [],
        distribucionGenero:           s.DISTRIBUCION_GENERO              ?? [],
        tendenciaInscripcionesMes:    s.TENDENCIA_INSCRIPCIONES_MES      ?? [],
      },
    });
  } catch (error) {
    console.error("[getResumenEstudiantes]", error);
    return res.status(500).json({
      ok:      false,
      mensaje: "Error interno del servidor.",
      detalle: process.env.NODE_ENV === "development" ? error.message : undefined,
    });
  }
};


export const getResumenAnotaciones = async (req, res) => {
  const pool = connect();

  try {
    const fechaInicio = req.query.inicio ?? null;
    const fechaFin    = req.query.fin    ?? null;

    const [results] = await pool.query(
      "CALL sp_admin_resumen_anotaciones(?, ?)",
      [fechaInicio, fechaFin]
    );

    const s = parsearSecciones(results);

    return res.status(200).json({
      ok:   true,
      data: {
        porTipoFalta:     s.ANOTACIONES_POR_TIPO_FALTA        ?? [],
        porEstado:        s.ANOTACIONES_POR_ESTADO             ?? [],
        porCategoria:     s.ANOTACIONES_POR_CATEGORIA          ?? [],
        top10:            s.TOP10_ESTUDIANTES_MAS_ANOTACIONES  ?? [],
        porGrado:         s.ANOTACIONES_POR_GRADO              ?? [],
        tendenciaMensual: s.TENDENCIA_MENSUAL_ANOTACIONES      ?? [],
      },
    });
  } catch (error) {
    console.error("[getResumenAnotaciones]", error);
    return res.status(500).json({
      ok:      false,
      mensaje: "Error interno del servidor.",
      detalle: process.env.NODE_ENV === "development" ? error.message : undefined,
    });
  }
};

export const getResumenMovimientos = async (req, res) => {
  const pool = connect();

  try {
    const idAnio = req.query.anio ? Number(req.query.anio) : null;

    const [results] = await pool.query(
      "CALL sp_admin_resumen_movimientos(?)",
      [idAnio]
    );

    const s = parsearSecciones(results);

    return res.status(200).json({
      ok:   true,
      data: {
        inscripcionesPorTipo:    s.INSCRIPCIONES_POR_TIPO     ?? [],
        bajasRetiros:            s.BAJAS_RETIROS               ?? [],
        trasladosPorProcedencia: s.TRASLADOS_POR_PROCEDENCIA   ?? [],
        regresosPorGrado:        s.REINGRESOS_POR_GRADO        ?? [],
        comparativaAnios:        s.COMPARATIVA_ANIOS           ?? [],
        detalleRetiros:          s.DETALLE_RETIROS             ?? [],
      },
    });
  } catch (error) {
    console.error("[getResumenMovimientos]", error);
    return res.status(500).json({
      ok:      false,
      mensaje: "Error interno del servidor.",
      detalle: process.env.NODE_ENV === "development" ? error.message : undefined,
    });
  }
};


export const getCardexEstudiante = async (req, res) => {
  const pool = connect();

  try {
    const idEstudiante = Number(req.params.idEstudiante);
    const idAnio       = req.query.anio ? Number(req.query.anio) : null;

    if (!idEstudiante || isNaN(idEstudiante)) {
      return res.status(400).json({
        ok:      false,
        mensaje: "El parámetro idEstudiante no es válido.",
      });
    }

    const [results] = await pool.query(
      "CALL sp_admin_cardex_estudiante(?, ?)",
      [idEstudiante, idAnio]
    );

    const s = parsearSecciones(results);

    if (!s.DATOS_PERSONALES || s.DATOS_PERSONALES.length === 0) {
      return res.status(404).json({
        ok:      false,
        mensaje: `No se encontró el estudiante con id ${idEstudiante}.`,
      });
    }

    return res.status(200).json({
      ok:   true,
      data: {
        datosPersonales:              s.DATOS_PERSONALES               ?? [],
        tutores:                      s.TUTORES                        ?? [],
        historialMatriculas:          s.HISTORIAL_MATRICULAS           ?? [],
        calificaciones:               s.CALIFICACIONES                 ?? [],
        promediosPorMateria:          s.PROMEDIOS_POR_MATERIA          ?? [],
        promedioGeneral:              s.PROMEDIO_GENERAL               ?? [],
        historialAsistencias:         s.HISTORIAL_ASISTENCIAS          ?? [],
        reportesDisciplinarios:       s.REPORTES_DISCIPLINARIOS        ?? [],
        historialPagos:               s.HISTORIAL_PAGOS                ?? [],
        resumenFinanciero:            s.RESUMEN_FINANCIERO             ?? [],
        actividadesExtracurriculares: s.ACTIVIDADES_EXTRACURRICULARES  ?? [],
        auditoriaCambios:             s.AUDITORIA_CAMBIOS              ?? [],
      },
    });
  } catch (error) {
    console.error("[getCardexEstudiante]", error);
    return res.status(500).json({
      ok:      false,
      mensaje: "Error interno del servidor.",
      detalle: process.env.NODE_ENV === "development" ? error.message : undefined,
    });
  }
};


export const getCardexLista = async (req, res) => {
  const pool = connect();

  try {
    const idAnio  = req.query.anio    ? Number(req.query.anio)  : null;
    const idGrado = req.query.grado   ? Number(req.query.grado) : null;
    const estado  = req.query.estado  ?? null;

    const [results] = await pool.query(
      "CALL sp_admin_cardex_lista(?, ?, ?)",
      [idAnio, idGrado, estado]
    );

    // SP de un solo result-set, sin secciones
    const rows = Array.isArray(results[0]) ? results[0] : results;

    return res.status(200).json({
      ok:    true,
      total: rows.length,
      data:  rows,
    });
  } catch (error) {
    console.error("[getCardexLista]", error);
    return res.status(500).json({
      ok:      false,
      mensaje: "Error interno del servidor.",
      detalle: process.env.NODE_ENV === "development" ? error.message : undefined,
    });
  }
};


// 7.  GET /api/admin/financiero/reporte?anio=1
//     Reporte financiero completo
// ─────────────────────────────────────────────────────────────
export const getReporteFinanciero = async (req, res) => {
  const pool = connect();

  try {
    const idAnio = req.query.anio ? Number(req.query.anio) : null;

    const [results] = await pool.query(
      "CALL sp_admin_reporte_financiero(?)",
      [idAnio]
    );

    const s = parsearSecciones(results);

    return res.status(200).json({
      ok:   true,
      data: {
        resumenGeneral: s.RESUMEN_GENERAL ?? [],
        porConcepto:    s.POR_CONCEPTO    ?? [],
        cobrosPorMes:   s.COBROS_POR_MES  ?? [],
        topMorosos:     s.TOP_MOROSOS     ?? [],
        metodosPago:    s.METODOS_PAGO    ?? [],
      },
    });
  } catch (error) {
    console.error("[getReporteFinanciero]", error);
    return res.status(500).json({
      ok:      false,
      mensaje: "Error interno del servidor.",
      detalle: process.env.NODE_ENV === "development" ? error.message : undefined,
    });
  }
};


export const getReporteRendimiento = async (req, res) => {
  const pool = connect();

  try {
    const idAnio = req.query.anio ? Number(req.query.anio) : null;

    const [results] = await pool.query(
      "CALL sp_admin_reporte_rendimiento_academico(?)",
      [idAnio]
    );

    const s = parsearSecciones(results);

    return res.status(200).json({
      ok:   true,
      data: {
        promedioPorGrado:      s.PROMEDIO_POR_GRADO      ?? [],
        materiasCriticas:      s.MATERIAS_CRITICAS        ?? [],
        rendimientoPorDocente: s.RENDIMIENTO_POR_DOCENTE  ?? [],
        comparativaPeriodos:   s.COMPARATIVA_PERIODOS     ?? [],
      },
    });
  } catch (error) {
    console.error("[getReporteRendimiento]", error);
    return res.status(500).json({
      ok:      false,
      mensaje: "Error interno del servidor.",
      detalle: process.env.NODE_ENV === "development" ? error.message : undefined,
    });
  }
};