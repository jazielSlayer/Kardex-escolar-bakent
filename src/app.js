import express from 'express';
import cors from 'cors';
import morgan from 'morgan';

import swaggerJSDoc from 'swagger-jsdoc';
import swaggerUi from 'swagger-ui-express';
import { options } from './SwagerrOptions';


import Estudiante from './Routes/Estudiantes'
import Anotacion from './Routes/Anotaciones'
import Admin from './Routes/Admin'

const specs = swaggerJSDoc(options);




const app = express();




app.use(cors());
app.use(morgan('dev'));
app.use(express.json());
app.use(express.urlencoded({ extended: true }));

app.use(Estudiante)
app.use(Anotacion)
app.use(Admin)


app.use('/docs', swaggerUi.serve, swaggerUi.setup(specs));

export default app;