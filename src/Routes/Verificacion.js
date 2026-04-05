import { Router } from 'express';
import { login, generarCodigo2FA, verificarCodigo2FA } from '../Controlers/Verificacion.js';

const router = Router();

router.post('/auth/login',         login);
router.post('/auth/2fa/generar',   generarCodigo2FA);
router.post('/auth/2fa/verificar', verificarCodigo2FA);

export default router;