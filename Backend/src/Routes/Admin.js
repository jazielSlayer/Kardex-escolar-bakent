import { Router } from "express";
import {
  getDashboardKpi,
  getResumenEstudiantes,
  getResumenAnotaciones,
  getResumenMovimientos,
  getCardexEstudiante,
  getCardexLista,
  getReporteFinanciero,
  getReporteRendimiento,
} from "../Controlers/Admin.js";

const router = Router();


router.get("/dashboard/kpi", getDashboardKpi);


router.get("/estudiantes/resumen", getResumenEstudiantes);


router.get("/anotaciones/resumen", getResumenAnotaciones);

router.get("/movimientos/resumen", getResumenMovimientos);


router.get("/cardex", getCardexLista);


router.get("/cardex/:idEstudiante", getCardexEstudiante);


router.get("/financiero/reporte", getReporteFinanciero);


router.get("/rendimiento/reporte", getReporteRendimiento);

export default router;
