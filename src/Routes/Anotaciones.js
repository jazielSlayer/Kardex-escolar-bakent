import { Router } from 'express';
import { registrarAnotacion, obtenerAnotaciones, obtenerAnotacionesPorEstudiante, actualizarEstadoAnotacion } from '../Controlers/Anotacion';

const router = Router()

router.post("/anotaciones/registrar", registrarAnotacion);

// GET    /anotaciones
router.get("/anotaciones/obtener", obtenerAnotaciones);

// GET    /anotaciones/estudiante?nombre=Santiago&apellido=Sánchez
router.get("/anotaciones/estudiante", obtenerAnotacionesPorEstudiante);


router.patch("/anotaciones/estado", actualizarEstadoAnotacion);

export default router