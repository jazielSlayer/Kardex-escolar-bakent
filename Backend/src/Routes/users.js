import { Router } from 'express';
import { getUsers } from '../Controlers/users_controllers';

const router = Router()

router.get('/users', getUsers)

export default router