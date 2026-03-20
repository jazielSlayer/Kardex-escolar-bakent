import { Router } from 'express';
import { inscribirEstudiante } from '../Controlers/Estudiante';

const router = Router()

router.post('/registrar/estudiante', inscribirEstudiante)

export default router