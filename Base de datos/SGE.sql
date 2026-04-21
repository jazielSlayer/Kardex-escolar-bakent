-- phpMyAdmin SQL Dump
-- version 5.2.1
-- https://www.phpmyadmin.net/
--
-- Servidor: 127.0.0.1
-- Tiempo de generación: 21-04-2026 a las 21:55:24
-- Versión del servidor: 10.4.32-MariaDB
-- Versión de PHP: 8.1.25

SET SQL_MODE = "NO_AUTO_VALUE_ON_ZERO";
START TRANSACTION;
SET time_zone = "+00:00";


/*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;
/*!40101 SET @OLD_CHARACTER_SET_RESULTS=@@CHARACTER_SET_RESULTS */;
/*!40101 SET @OLD_COLLATION_CONNECTION=@@COLLATION_CONNECTION */;
/*!40101 SET NAMES utf8mb4 */;

--
-- Base de datos: `sge`
--

DELIMITER $$
--
-- Procedimientos
--
CREATE DEFINER=`root`@`localhost` PROCEDURE `sp_actualizar_estado_anotacion` (IN `p_nombre_estudiante` VARCHAR(255), IN `p_apellido_estudiante` VARCHAR(255), IN `p_fecha_incidente` DATE, IN `p_nuevo_estado` ENUM('Abierto','En_proceso','Resuelto','Cerrado'), IN `p_seguimiento` TEXT, IN `p_usuario_modifica` BIGINT, OUT `p_id_reporte_actualizado` BIGINT, OUT `p_nombre_completo_est` VARCHAR(511), OUT `p_mensaje` VARCHAR(500))   proc: BEGIN

    DECLARE v_id_estudiante   BIGINT;
    DECLARE v_count_est       INT DEFAULT 0;
    DECLARE v_count_rep       INT DEFAULT 0;
    DECLARE v_estado_anterior VARCHAR(30);

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SET p_id_reporte_actualizado = NULL;
        SET p_nombre_completo_est    = NULL;
        SET p_mensaje = 'Error: No se pudo actualizar el estado de la anotación.';
    END;

    START TRANSACTION;

    -- ══════════════════════════════════════════════════════════
    -- 1. VALIDACIONES
    -- ══════════════════════════════════════════════════════════

    IF p_nombre_estudiante IS NULL OR TRIM(p_nombre_estudiante) = '' OR
       p_apellido_estudiante IS NULL OR TRIM(p_apellido_estudiante) = '' THEN
        ROLLBACK;
        SET p_mensaje = 'Error: Debe proporcionar el nombre y apellido del estudiante.';
        LEAVE proc;
    END IF;

    IF p_fecha_incidente IS NULL THEN
        ROLLBACK;
        SET p_mensaje = 'Error: La fecha del incidente es obligatoria.';
        LEAVE proc;
    END IF;

    IF p_nuevo_estado IS NULL THEN
        ROLLBACK;
        SET p_mensaje = 'Error: El estado es obligatorio (Abierto, En_proceso, Resuelto, Cerrado).';
        LEAVE proc;
    END IF;

    -- ══════════════════════════════════════════════════════════
    -- 2. BUSCAR ESTUDIANTE
    -- ══════════════════════════════════════════════════════════

    SELECT COUNT(*)
    INTO   v_count_est
    FROM   estudiante e
    INNER JOIN users   u ON e.ID_User    = u.id
    INNER JOIN persona p ON u.ID_Persona = p.id
    WHERE  p.Nombre   LIKE CONCAT('%', TRIM(p_nombre_estudiante),   '%')
      AND  p.Apellido LIKE CONCAT('%', TRIM(p_apellido_estudiante), '%')
      AND  e.Estado = 'Activo';

    IF v_count_est = 0 THEN
        ROLLBACK;
        SET p_mensaje = CONCAT(
            'Error: No se encontró ningún estudiante activo con el nombre "',
            p_nombre_estudiante, ' ', p_apellido_estudiante, '".'
        );
        LEAVE proc;
    END IF;

    IF v_count_est > 1 THEN
        ROLLBACK;
        SET p_mensaje = CONCAT(
            'Error: Se encontraron ', v_count_est,
            ' estudiantes con el nombre "', p_nombre_estudiante, ' ', p_apellido_estudiante,
            '". Use un nombre más específico.'
        );
        LEAVE proc;
    END IF;

    SELECT e.id, CONCAT(p.Nombre, ' ', p.Apellido)
    INTO   v_id_estudiante, p_nombre_completo_est
    FROM   estudiante e
    INNER JOIN users   u ON e.ID_User    = u.id
    INNER JOIN persona p ON u.ID_Persona = p.id
    WHERE  p.Nombre   LIKE CONCAT('%', TRIM(p_nombre_estudiante),   '%')
      AND  p.Apellido LIKE CONCAT('%', TRIM(p_apellido_estudiante), '%')
      AND  e.Estado = 'Activo'
    LIMIT 1;

    -- ══════════════════════════════════════════════════════════
    -- 3. BUSCAR REPORTE POR ESTUDIANTE + FECHA DE INCIDENTE
    -- ══════════════════════════════════════════════════════════

    SELECT COUNT(*)
    INTO   v_count_rep
    FROM   reportes_disciplinarios
    WHERE  ID_Estudiante  = v_id_estudiante
      AND  Fecha_incidente = p_fecha_incidente;

    IF v_count_rep = 0 THEN
        ROLLBACK;
        SET p_mensaje = CONCAT(
            'Error: No se encontró ninguna anotación para "', p_nombre_completo_est,
            '" con fecha ', DATE_FORMAT(p_fecha_incidente, '%d/%m/%Y'), '.'
        );
        LEAVE proc;
    END IF;

    IF v_count_rep > 1 THEN
        ROLLBACK;
        SET p_mensaje = CONCAT(
            'Error: Se encontraron ', v_count_rep,
            ' anotaciones para "', p_nombre_completo_est,
            '" en la fecha ', DATE_FORMAT(p_fecha_incidente, '%d/%m/%Y'),
            '. Contacte al administrador para resolverlo por ID.'
        );
        LEAVE proc;
    END IF;

    SELECT id, Estado
    INTO   p_id_reporte_actualizado, v_estado_anterior
    FROM   reportes_disciplinarios
    WHERE  ID_Estudiante  = v_id_estudiante
      AND  Fecha_incidente = p_fecha_incidente
    LIMIT 1;

    -- ══════════════════════════════════════════════════════════
    -- 4. ACTUALIZAR
    -- ══════════════════════════════════════════════════════════

    UPDATE reportes_disciplinarios
    SET    Estado      = p_nuevo_estado,
           Seguimiento = CASE
               WHEN p_seguimiento IS NOT NULL AND TRIM(p_seguimiento) != ''
               THEN CONCAT(IFNULL(Seguimiento, ''), ' | ', NOW(), ': ', TRIM(p_seguimiento))
               ELSE Seguimiento
           END
    WHERE  id = p_id_reporte_actualizado;

    -- ══════════════════════════════════════════════════════════
    -- 5. AUDITORÍA
    -- ══════════════════════════════════════════════════════════

    INSERT INTO auditoria (
        ID_User, Accion, Tabla_afectada,
        ID_Registro_afectado, Datos_anteriores, Datos_nuevos
    ) VALUES (
        p_usuario_modifica,
        'UPDATE',
        'reportes_disciplinarios',
        p_id_reporte_actualizado,
        JSON_OBJECT('estado', v_estado_anterior),
        JSON_OBJECT(
            'id_reporte',      p_id_reporte_actualizado,
            'id_estudiante',   v_id_estudiante,
            'estudiante',      p_nombre_completo_est,
            'fecha_incidente', p_fecha_incidente,
            'estado_nuevo',    p_nuevo_estado,
            'seguimiento',     p_seguimiento,
            'fecha',           NOW()
        )
    );

    COMMIT;

    SET p_mensaje = CONCAT(
        'Anotación #', p_id_reporte_actualizado, ' del ', DATE_FORMAT(p_fecha_incidente, '%d/%m/%Y'),
        ' actualizada a "', p_nuevo_estado, '" para: ', p_nombre_completo_est, '.'
    );

END proc$$

CREATE DEFINER=`` PROCEDURE `sp_actualizar_estado_buena_conducta` (IN `p_id_reporte` BIGINT, IN `p_nuevo_estado` VARCHAR(50), IN `p_seguimiento` TEXT, IN `p_usuario` BIGINT, OUT `p_mensaje` VARCHAR(500))   proc: BEGIN

    DECLARE v_estado_anterior VARCHAR(50);

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SET p_mensaje = 'Error: No se pudo actualizar el reconocimiento.';
    END;

    START TRANSACTION;

    SELECT Estado INTO v_estado_anterior
    FROM reportes_buena_conducta WHERE id = p_id_reporte;

    IF v_estado_anterior IS NULL THEN
        ROLLBACK;
        SET p_mensaje = 'Error: Reporte de buena conducta no encontrado.';
        LEAVE proc;
    END IF;

    UPDATE reportes_buena_conducta
    SET Estado     = p_nuevo_estado,
        Seguimiento = CASE
            WHEN p_seguimiento IS NOT NULL AND TRIM(p_seguimiento) != ''
            THEN CONCAT(IFNULL(Seguimiento, ''), ' | ', NOW(), ': ', TRIM(p_seguimiento))
            ELSE Seguimiento
        END
    WHERE id = p_id_reporte;

    INSERT INTO auditoria (ID_User, Accion, Tabla_afectada, ID_Registro_afectado, Datos_anteriores, Datos_nuevos)
    VALUES (
        p_usuario, 'UPDATE', 'reportes_buena_conducta', p_id_reporte,
        JSON_OBJECT('estado', v_estado_anterior),
        JSON_OBJECT('estado_nuevo', p_nuevo_estado, 'seguimiento', p_seguimiento, 'fecha', NOW())
    );

    COMMIT;

    SET p_mensaje = CONCAT('Reconocimiento #', p_id_reporte,
                           ' actualizado a "', p_nuevo_estado, '".');
END proc$$

CREATE DEFINER=`` PROCEDURE `sp_actualizar_estado_curso` (IN `p_id_curso` BIGINT, IN `p_nuevo_estado` VARCHAR(50), IN `p_observaciones` TEXT, IN `p_usuario` BIGINT, OUT `p_mensaje` VARCHAR(500))   proc: BEGIN

    DECLARE v_estado_actual VARCHAR(50);

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SET p_mensaje = 'Error: No se pudo actualizar el estado del curso.';
    END;

    START TRANSACTION;

    SELECT Estado INTO v_estado_actual FROM cursos WHERE id = p_id_curso;

    IF v_estado_actual IS NULL THEN
        ROLLBACK;
        SET p_mensaje = 'Error: Curso no encontrado.';
        LEAVE proc;
    END IF;

    UPDATE cursos
    SET Estado       = p_nuevo_estado,
        Observaciones = CASE
            WHEN p_observaciones IS NOT NULL AND TRIM(p_observaciones) != ''
            THEN CONCAT(IFNULL(Observaciones, ''), ' | ', NOW(), ': ', TRIM(p_observaciones))
            ELSE Observaciones
        END,
        Registrado_por = p_usuario
    WHERE id = p_id_curso;

    INSERT INTO auditoria (ID_User, Accion, Tabla_afectada, ID_Registro_afectado, Datos_anteriores, Datos_nuevos)
    VALUES (
        p_usuario, 'UPDATE', 'cursos', p_id_curso,
        JSON_OBJECT('estado', v_estado_actual),
        JSON_OBJECT('estado', p_nuevo_estado, 'observaciones', p_observaciones)
    );

    COMMIT;

    SET p_mensaje = CONCAT('Curso #', p_id_curso, ' actualizado a estado "', p_nuevo_estado, '".');
END proc$$

CREATE DEFINER=`root`@`localhost` PROCEDURE `sp_admin_cardex_estudiante` (IN `p_id_estudiante` BIGINT, IN `p_id_anio_academico` BIGINT)   BEGIN
    -- ── 1. Datos personales completos ─────────────────────────
    SELECT 'DATOS_PERSONALES' AS Seccion;
    SELECT
        e.id                                                      AS ID_Estudiante,
        e.Codigo_estudiante,
        e.Estado                                                  AS Estado_Estudiante,
        CONCAT(p.Nombre, ' ', p.Apellido)                         AS Nombre_Completo,
        p.CI,
        p.Fecha_nacimiento,
        TIMESTAMPDIFF(YEAR, p.Fecha_nacimiento, CURDATE())        AS Edad,
        CASE p.Genero WHEN 'M' THEN 'Masculino' WHEN 'F' THEN 'Femenino' ELSE 'Otro' END AS Genero,
        p.Direccion,
        p.Telefono,
        p.Email_personal,
        p.Nacionalidad,
        p.Estado_civil,
        e.Tipo_sangre,
        e.Alergias,
        e.Condiciones_medicas,
        e.Medicamentos,
        e.Seguro_medico,
        e.Numero_hermanos,
        e.Posicion_hermanos,
        e.Vive_con,
        e.Necesidades_especiales,
        e.Transporte,
        u.Correo,
        u.Ultimo_acceso,
        e.Creado_en                                               AS Fecha_Registro
    FROM estudiante e
    JOIN users      u  ON e.ID_User     = u.id
    JOIN persona    p  ON u.ID_Persona  = p.id
    WHERE e.id = p_id_estudiante;

    -- ── 2. Tutores/Padres vinculados ──────────────────────────
    SELECT 'TUTORES' AS Seccion;
    SELECT
        et.Parentesco,
        CONCAT(pp.Nombre, ' ', pp.Apellido)                       AS Nombre_Tutor,
        pp.CI,
        pp.Telefono,
        pp.Email_personal,
        pt.Ocupacion,
        pt.Lugar_trabajo,
        pt.Telefono_trabajo,
        et.Es_responsable_economicamente,
        et.Es_contacto_emergencia,
        et.Puede_retirar,
        et.Vive_con_estudiante,
        et.Prioridad_contacto,
        pt.Estado                                                 AS Estado_Tutor
    FROM estudiante_tutor et
    JOIN padre_tutor pt  ON et.ID_Padre      = pt.id
    JOIN users       up  ON pt.ID_User       = up.id
    JOIN persona     pp  ON up.ID_Persona    = pp.id
    WHERE et.ID_Estudiante = p_id_estudiante
    ORDER BY et.Prioridad_contacto;

    -- ── 3. Historial de matrículas por año ────────────────────
    SELECT 'HISTORIAL_MATRICULAS' AS Seccion;
    SELECT
        aa.Anio                                                   AS Anio_Academico,
        m.Numero_matricula,
        g.Nombre                                                  AS Grado,
        g.Paralelo,
        ne.Nombre                                                 AS Nivel_Educativo,
        i.Tipo_inscripcion,
        i.Colegio_procedencia,
        m.Tipo_estudiante,
        m.Estado_matricula,
        m.Estado_pago,
        m.Monto_matricula,
        m.Descuento,
        ROUND(m.Monto_matricula * (1 - m.Descuento / 100), 2)    AS Monto_Final,
        m.Requiere_apoyo,
        m.Fecha_matricula
    FROM matricula m
    JOIN inscripcion    i  ON m.ID_Inscripcion     = i.id
    JOIN anio_academico aa ON m.ID_Anio_Academico  = aa.id
    JOIN grado          g  ON m.ID_Grado           = g.id
    JOIN nivel_educativo ne ON g.ID_Nivel_educativo = ne.id
    WHERE m.ID_Estudiante = p_id_estudiante
      AND (p_id_anio_academico IS NULL OR m.ID_Anio_Academico = p_id_anio_academico)
    ORDER BY aa.Anio DESC;

    -- ── 4. Calificaciones detalladas ──────────────────────────
    SELECT 'CALIFICACIONES' AS Seccion;
    SELECT
        aa.Anio                                                   AS Anio_Academico,
        per.Nombre_periodo,
        per.Numero_periodo,
        mat.Codigo                                                AS Codigo_Materia,
        mat.Nombre_de_la_materia,
        mat.Area_conocimiento,
        c.Tipo_evaluacion,
        c.Descripcion,
        c.Fecha_evaluacion,
        c.Nota,
        c.Nota_maxima,
        ROUND(c.Nota / c.Nota_maxima * 100, 2)                   AS Porcentaje,
        c.Estado                                                  AS Estado_Calificacion,
        CASE WHEN c.Nota >= c.Nota_maxima * 0.6 THEN 'Aprobado' ELSE 'Reprobado' END AS Resultado,
        CONCAT(pd.Nombre, ' ', pd.Apellido)                       AS Docente,
        c.Observaciones
    FROM calificaciones c
    JOIN anio_academico aa  ON c.ID_Anio_Academico = aa.id
    JOIN periodo        per ON c.ID_Periodo        = per.id
    JOIN materias       mat ON c.ID_Materia        = mat.id
    JOIN docente        d   ON c.ID_Docente        = d.id
    JOIN users          ud  ON d.ID_User           = ud.id
    JOIN persona        pd  ON ud.ID_Persona       = pd.id
    WHERE c.ID_Estudiante = p_id_estudiante
      AND (p_id_anio_academico IS NULL OR c.ID_Anio_Academico = p_id_anio_academico)
    ORDER BY aa.Anio DESC, per.Numero_periodo, mat.Nombre_de_la_materia;

    -- ── 5. Promedios por materia y período ────────────────────
    SELECT 'PROMEDIOS_POR_MATERIA' AS Seccion;
    SELECT
        aa.Anio                                                   AS Anio_Academico,
        per.Nombre_periodo,
        mat.Nombre_de_la_materia,
        COUNT(c.id)                                               AS Total_Evaluaciones,
        ROUND(AVG(c.Nota), 2)                                     AS Promedio_Nota,
        ROUND(AVG(c.Nota / c.Nota_maxima * 100), 2)               AS Promedio_Porcentaje,
        MAX(c.Nota)                                               AS Nota_Maxima_Obtenida,
        MIN(c.Nota)                                               AS Nota_Minima_Obtenida,
        CASE WHEN AVG(c.Nota / c.Nota_maxima * 100) >= 60
             THEN 'Aprobado' ELSE 'Reprobado' END                 AS Estado_Final
    FROM calificaciones c
    JOIN anio_academico aa  ON c.ID_Anio_Academico = aa.id
    JOIN periodo        per ON c.ID_Periodo        = per.id
    JOIN materias       mat ON c.ID_Materia        = mat.id
    WHERE c.ID_Estudiante = p_id_estudiante
      AND c.Estado IN ('Publicada','Modificada')
      AND (p_id_anio_academico IS NULL OR c.ID_Anio_Academico = p_id_anio_academico)
    GROUP BY aa.Anio, per.id, per.Nombre_periodo, mat.id, mat.Nombre_de_la_materia
    ORDER BY aa.Anio DESC, per.Numero_periodo, mat.Nombre_de_la_materia;

    -- ── 6. Promedio general ───────────────────────────────────
    SELECT 'PROMEDIO_GENERAL' AS Seccion;
    SELECT
        aa.Anio                                                   AS Anio_Academico,
        COUNT(DISTINCT c.ID_Materia)                              AS Total_Materias,
        COUNT(c.id)                                               AS Total_Evaluaciones,
        ROUND(AVG(c.Nota / c.Nota_maxima * 100), 2)               AS Promedio_General,
        SUM(CASE WHEN c.Nota / c.Nota_maxima * 100 >= 90 THEN 1 ELSE 0 END) AS Excelentes,
        SUM(CASE WHEN c.Nota / c.Nota_maxima * 100 BETWEEN 80 AND 89.99 THEN 1 ELSE 0 END) AS Muy_Buenos,
        SUM(CASE WHEN c.Nota / c.Nota_maxima * 100 BETWEEN 70 AND 79.99 THEN 1 ELSE 0 END) AS Buenos,
        SUM(CASE WHEN c.Nota / c.Nota_maxima * 100 BETWEEN 60 AND 69.99 THEN 1 ELSE 0 END) AS Suficientes,
        SUM(CASE WHEN c.Nota / c.Nota_maxima * 100 < 60  THEN 1 ELSE 0 END) AS Insuficientes,
        ROUND(SUM(CASE WHEN c.Nota / c.Nota_maxima * 100 >= 60 THEN 1 ELSE 0 END)
              * 100.0 / NULLIF(COUNT(c.id), 0), 2)                AS Porcentaje_Aprobacion,
        CASE
            WHEN AVG(c.Nota / c.Nota_maxima * 100) >= 90 THEN 'Excelente'
            WHEN AVG(c.Nota / c.Nota_maxima * 100) >= 80 THEN 'Muy Bueno'
            WHEN AVG(c.Nota / c.Nota_maxima * 100) >= 70 THEN 'Bueno'
            WHEN AVG(c.Nota / c.Nota_maxima * 100) >= 60 THEN 'Suficiente'
            ELSE 'Insuficiente'
        END                                                       AS Clasificacion
    FROM calificaciones c
    JOIN anio_academico aa ON c.ID_Anio_Academico = aa.id
    WHERE c.ID_Estudiante = p_id_estudiante
      AND c.Estado IN ('Publicada','Modificada')
      AND (p_id_anio_academico IS NULL OR c.ID_Anio_Academico = p_id_anio_academico)
    GROUP BY aa.Anio
    ORDER BY aa.Anio DESC;

    -- ── 7. Historial de asistencias ───────────────────────────
    SELECT 'HISTORIAL_ASISTENCIAS' AS Seccion;
    SELECT
        YEAR(a.Fecha)                                             AS Anio,
        MONTH(a.Fecha)                                            AS Mes,
        MONTHNAME(a.Fecha)                                        AS Nombre_Mes,
        COUNT(a.id)                                               AS Total_Registros,
        SUM(CASE WHEN a.Estado = 'Presente'   THEN 1 ELSE 0 END) AS Presentes,
        SUM(CASE WHEN a.Estado = 'Ausente'    THEN 1 ELSE 0 END) AS Ausentes,
        SUM(CASE WHEN a.Estado = 'Tardanza'   THEN 1 ELSE 0 END) AS Tardanzas,
        SUM(CASE WHEN a.Estado = 'Justificado'THEN 1 ELSE 0 END) AS Justificados,
        SUM(CASE WHEN a.Estado = 'Permiso'    THEN 1 ELSE 0 END) AS Permisos,
        ROUND(SUM(CASE WHEN a.Estado = 'Presente' THEN 1 ELSE 0 END)
              * 100.0 / NULLIF(COUNT(a.id), 0), 2)               AS Porcentaje_Asistencia
    FROM asistencias a
    WHERE a.ID_Estudiante = p_id_estudiante
      AND (p_id_anio_academico IS NULL
           OR (YEAR(a.Fecha) = (SELECT Anio FROM anio_academico WHERE id = p_id_anio_academico)))
    GROUP BY YEAR(a.Fecha), MONTH(a.Fecha)
    ORDER BY Anio DESC, Mes DESC;

    -- ── 8. Reportes disciplinarios del estudiante ─────────────
    SELECT 'REPORTES_DISCIPLINARIOS' AS Seccion;
    SELECT
        rd.id                                                     AS ID_Reporte,
        rd.Fecha_incidente,
        rd.Tipo_falta,
        rd.Categoria,
        rd.Descripcion,
        rd.Sancion,
        rd.Fecha_sancion,
        rd.Estado,
        CASE rd.Notificado_padres WHEN 1 THEN 'Sí' ELSE 'No' END AS Notificado_Padres,
        rd.Fecha_notificacion,
        rd.Seguimiento,
        CONCAT(pr.Nombre, ' ', pr.Apellido)                       AS Reportado_Por,
        rd.Creado_en
    FROM reportes_disciplinarios rd
    JOIN users      ur ON rd.ID_Reportado_por = ur.id
    JOIN persona    pr ON ur.ID_Persona       = pr.id
    WHERE rd.ID_Estudiante = p_id_estudiante
    ORDER BY rd.Fecha_incidente DESC;

    -- ── 9. Historial de pagos ─────────────────────────────────
    SELECT 'HISTORIAL_PAGOS' AS Seccion;
    SELECT
        aa.Anio                                                   AS Anio_Academico,
        pg.Concepto,
        pg.Mes,
        pg.Monto,
        pg.Descuento,
        pg.Monto_pagado,
        pg.Saldo,
        pg.Estado                                                 AS Estado_Pago,
        pg.Fecha_vencimiento,
        pg.Fecha_pago,
        pg.Metodo_pago,
        pg.Numero_recibo,
        DATEDIFF(CURDATE(), pg.Fecha_vencimiento)                 AS Dias_Desde_Vencimiento,
        pg.Observaciones
    FROM pagos pg
    JOIN anio_academico aa ON pg.ID_Anio_Academico = aa.id
    WHERE pg.ID_Estudiante = p_id_estudiante
      AND (p_id_anio_academico IS NULL OR pg.ID_Anio_Academico = p_id_anio_academico)
    ORDER BY aa.Anio DESC, pg.Creado_en DESC;

    -- ── 10. Resumen financiero del estudiante ─────────────────
    SELECT 'RESUMEN_FINANCIERO' AS Seccion;
    SELECT
        aa.Anio                                                   AS Anio_Academico,
        SUM(pg.Monto)                                             AS Total_Cargo,
        SUM(pg.Monto_pagado)                                      AS Total_Pagado,
        SUM(pg.Saldo)                                             AS Total_Pendiente,
        SUM(CASE WHEN pg.Estado = 'Atrasado' THEN pg.Saldo ELSE 0 END) AS Total_Atrasado,
        COUNT(CASE WHEN pg.Estado IN ('Pendiente','Atrasado') THEN 1 END) AS Cuotas_Pendientes
    FROM pagos pg
    JOIN anio_academico aa ON pg.ID_Anio_Academico = aa.id
    WHERE pg.ID_Estudiante = p_id_estudiante
      AND (p_id_anio_academico IS NULL OR pg.ID_Anio_Academico = p_id_anio_academico)
    GROUP BY aa.Anio
    ORDER BY aa.Anio DESC;

    -- ── 11. Actividades extracurriculares ─────────────────────
    SELECT 'ACTIVIDADES_EXTRACURRICULARES' AS Seccion;
    SELECT
        aa.Anio                                                   AS Anio_Academico,
        ac.Nombre                                                 AS Actividad,
        ac.Tipo,
        ac.Horario,
        ac.Costo_adicional,
        ea.Estado,
        ea.Fecha_inscripcion
    FROM estudiante_actividad ea
    JOIN actividades_extracurriculares ac ON ea.ID_Actividad       = ac.id
    JOIN anio_academico                aa ON ea.ID_Anio_Academico  = aa.id
    WHERE ea.ID_Estudiante = p_id_estudiante
      AND (p_id_anio_academico IS NULL OR ea.ID_Anio_Academico = p_id_anio_academico)
    ORDER BY aa.Anio DESC;

    -- ── 12. Auditoría de cambios del estudiante ───────────────
    SELECT 'AUDITORIA_CAMBIOS' AS Seccion;
    SELECT
        aud.Fecha_hora,
        aud.Accion,
        aud.Tabla_afectada,
        CONCAT(pu.Nombre, ' ', pu.Apellido)                       AS Realizado_Por,
        r.Nombre                                                  AS Rol_Usuario,
        aud.Datos_anteriores,
        aud.Datos_nuevos
    FROM auditoria aud
    JOIN users   u  ON aud.ID_User     = u.id
    JOIN persona pu ON u.ID_Persona    = pu.id
    JOIN roles   r  ON u.ID_Rol        = r.id
    WHERE aud.Tabla_afectada IN ('estudiante','calificaciones','matricula','inscripcion','pagos')
      AND aud.ID_Registro_afectado = p_id_estudiante
    ORDER BY aud.Fecha_hora DESC
    LIMIT 100;

END$$

CREATE DEFINER=`root`@`localhost` PROCEDURE `sp_admin_cardex_lista` (IN `p_id_anio_academico` BIGINT, IN `p_id_grado` BIGINT, IN `p_estado_estudiante` VARCHAR(20))   BEGIN
    DECLARE v_id_anio BIGINT;

    IF p_id_anio_academico IS NULL THEN
        SELECT id INTO v_id_anio FROM anio_academico WHERE Es_actual = 1 LIMIT 1;
    ELSE
        SET v_id_anio = p_id_anio_academico;
    END IF;

    SELECT
        e.id                                                         AS ID_Estudiante,
        e.Codigo_estudiante,
        CONCAT(p.Nombre, ' ', p.Apellido)                            AS Nombre_Completo,
        p.CI,
        p.Fecha_nacimiento,
        TIMESTAMPDIFF(YEAR, p.Fecha_nacimiento, CURDATE())           AS Edad,
        CASE p.Genero WHEN 'M' THEN 'M' WHEN 'F' THEN 'F' ELSE 'O' END AS Genero,
        ne.Nombre                                                    AS Nivel_Educativo,
        g.Nombre                                                     AS Grado,
        g.Paralelo,
        g.Turno,
        m.Numero_matricula,
        m.Tipo_estudiante,
        m.Estado_matricula,
        m.Estado_pago,
        -- Promedio general
        ROUND((SELECT AVG(c.Nota / c.Nota_maxima * 100)
               FROM calificaciones c
               WHERE c.ID_Estudiante      = e.id
                 AND c.ID_Anio_Academico  = v_id_anio
                 AND c.Estado IN ('Publicada','Modificada')), 2)     AS Promedio_General,
        -- Clasificación rendimiento
        CASE
            WHEN (SELECT AVG(c2.Nota / c2.Nota_maxima * 100)
                  FROM calificaciones c2
                  WHERE c2.ID_Estudiante = e.id
                    AND c2.ID_Anio_Academico = v_id_anio
                    AND c2.Estado IN ('Publicada','Modificada')) >= 90 THEN 'Excelente'
            WHEN (SELECT AVG(c2.Nota / c2.Nota_maxima * 100)
                  FROM calificaciones c2
                  WHERE c2.ID_Estudiante = e.id
                    AND c2.ID_Anio_Academico = v_id_anio
                    AND c2.Estado IN ('Publicada','Modificada')) >= 80 THEN 'Muy Bueno'
            WHEN (SELECT AVG(c2.Nota / c2.Nota_maxima * 100)
                  FROM calificaciones c2
                  WHERE c2.ID_Estudiante = e.id
                    AND c2.ID_Anio_Academico = v_id_anio
                    AND c2.Estado IN ('Publicada','Modificada')) >= 70 THEN 'Bueno'
            WHEN (SELECT AVG(c2.Nota / c2.Nota_maxima * 100)
                  FROM calificaciones c2
                  WHERE c2.ID_Estudiante = e.id
                    AND c2.ID_Anio_Academico = v_id_anio
                    AND c2.Estado IN ('Publicada','Modificada')) >= 60 THEN 'Suficiente'
            ELSE 'Sin Calificaciones'
        END                                                          AS Rendimiento,
        -- Asistencia del mes
        (SELECT COUNT(*) FROM asistencias a
         WHERE a.ID_Estudiante = e.id
           AND a.Estado = 'Presente'
           AND MONTH(a.Fecha) = MONTH(CURDATE())
           AND YEAR(a.Fecha)  = YEAR(CURDATE()))                     AS Asistencias_Mes,
        (SELECT COUNT(*) FROM asistencias a2
         WHERE a2.ID_Estudiante = e.id
           AND a2.Estado = 'Ausente'
           AND MONTH(a2.Fecha) = MONTH(CURDATE())
           AND YEAR(a2.Fecha)  = YEAR(CURDATE()))                    AS Ausencias_Mes,
        -- Anotaciones
        (SELECT COUNT(*) FROM reportes_disciplinarios rd
         WHERE rd.ID_Estudiante = e.id)                              AS Total_Anotaciones,
        (SELECT COUNT(*) FROM reportes_disciplinarios rd2
         WHERE rd2.ID_Estudiante = e.id
           AND rd2.Estado IN ('Abierto','En_proceso'))               AS Anotaciones_Activas,
        -- Pagos
        (SELECT IFNULL(SUM(pg.Saldo), 0) FROM pagos pg
         WHERE pg.ID_Estudiante      = e.id
           AND pg.ID_Anio_Academico  = v_id_anio
           AND pg.Estado IN ('Pendiente','Atrasado'))                AS Deuda_Pendiente,
        e.Estado                                                     AS Estado_Estudiante,
        e.Creado_en                                                  AS Fecha_Registro
    FROM estudiante e
    JOIN users          u  ON e.ID_User           = u.id
    JOIN persona        p  ON u.ID_Persona        = p.id
    LEFT JOIN matricula m  ON e.id = m.ID_Estudiante
                           AND m.ID_Anio_Academico = v_id_anio
                           AND m.Estado_matricula  = 'Activa'
    LEFT JOIN grado     g  ON m.ID_Grado           = g.id
    LEFT JOIN nivel_educativo ne ON g.ID_Nivel_educativo = ne.id
    WHERE (p_id_grado          IS NULL OR m.ID_Grado = p_id_grado)
      AND (p_estado_estudiante IS NULL OR e.Estado   = p_estado_estudiante)
    ORDER BY ne.Orden, g.Curso, g.Paralelo, p.Apellido, p.Nombre;

END$$

CREATE DEFINER=`root`@`localhost` PROCEDURE `sp_admin_dashboard_kpi` ()   BEGIN
    DECLARE v_id_anio BIGINT;
    SELECT id INTO v_id_anio FROM anio_academico WHERE Es_actual = 1 LIMIT 1;

    SELECT
        -- Año académico
        (SELECT Nombre FROM anio_academico WHERE id = v_id_anio)  AS Anio_Academico_Actual,

        -- Estudiantes
        (SELECT COUNT(*) FROM estudiante WHERE Estado = 'Activo') AS Total_Estudiantes_Activos,
        (SELECT COUNT(*) FROM matricula
         WHERE ID_Anio_Academico = v_id_anio
           AND Estado_matricula  = 'Activa')                      AS Total_Matriculados,
        (SELECT COUNT(*) FROM estudiante WHERE Estado = 'Retirado') AS Total_Retirados,

        -- Docentes
        (SELECT COUNT(*) FROM docente WHERE Estado = 'Activo')    AS Total_Docentes_Activos,

        -- Administrativos
        (SELECT COUNT(*) FROM plantel_administrativo
         WHERE Estado = 'Activo')                                  AS Total_Administrativos,

        -- Padres/Tutores
        (SELECT COUNT(*) FROM padre_tutor WHERE Estado = 'Activo') AS Total_Tutores,

        -- Anotaciones activas
        (SELECT COUNT(*) FROM reportes_disciplinarios
         WHERE Estado IN ('Abierto','En_proceso'))                 AS Anotaciones_Activas,

        -- Anotaciones graves/muy graves activas
        (SELECT COUNT(*) FROM reportes_disciplinarios
         WHERE Estado IN ('Abierto','En_proceso')
           AND Tipo_falta IN ('Grave','Muy_grave'))                AS Anotaciones_Criticas,

        -- Pagos
        (SELECT COUNT(*) FROM pagos
         WHERE Estado IN ('Pendiente','Atrasado')
           AND ID_Anio_Academico = v_id_anio)                      AS Pagos_Pendientes,
        (SELECT IFNULL(SUM(Saldo), 0) FROM pagos
         WHERE Estado IN ('Pendiente','Atrasado')
           AND ID_Anio_Academico = v_id_anio)                      AS Monto_Total_Pendiente,
        (SELECT IFNULL(SUM(Monto_pagado), 0) FROM pagos
         WHERE Estado = 'Pagado'
           AND ID_Anio_Academico = v_id_anio)                      AS Total_Recaudado,

        -- Asistencia de hoy
        (SELECT COUNT(*) FROM asistencias
         WHERE Fecha = CURDATE() AND Estado = 'Presente')          AS Presentes_Hoy,
        (SELECT COUNT(*) FROM asistencias
         WHERE Fecha = CURDATE() AND Estado = 'Ausente')           AS Ausentes_Hoy,

        -- Inscripciones pendientes de documentos
        (SELECT COUNT(*) FROM inscripcion
         WHERE ID_Anio_Academico = v_id_anio
           AND Documentos_completos = 0
           AND Estado = 'Aprobada')                                AS Inscripciones_Sin_Documentos,

        -- Capacidad global del colegio
        (SELECT SUM(Capacidad_maxima)  FROM grado WHERE Estado = 'Activo') AS Capacidad_Total,
        (SELECT SUM(Capacidad_actual)  FROM grado WHERE Estado = 'Activo') AS Ocupacion_Total,
        ROUND(
            (SELECT SUM(Capacidad_actual)  FROM grado WHERE Estado = 'Activo') * 100.0
          / NULLIF((SELECT SUM(Capacidad_maxima) FROM grado WHERE Estado = 'Activo'), 0)
        , 2)                                                       AS Porcentaje_Ocupacion_Global;

END$$

CREATE DEFINER=`root`@`localhost` PROCEDURE `sp_admin_reporte_financiero` (IN `p_id_anio_academico` BIGINT)   BEGIN
    DECLARE v_id_anio BIGINT;

    IF p_id_anio_academico IS NULL THEN
        SELECT id INTO v_id_anio FROM anio_academico WHERE Es_actual = 1 LIMIT 1;
    ELSE
        SET v_id_anio = p_id_anio_academico;
    END IF;

    -- ── A. Resumen general ────────────────────────────────────
    SELECT 'RESUMEN_GENERAL' AS Seccion;
    SELECT
        aa.Anio                                                   AS Anio_Academico,
        COUNT(DISTINCT pg.ID_Estudiante)                          AS Estudiantes_Con_Pagos,
        SUM(pg.Monto)                                             AS Total_Facturado,
        SUM(pg.Monto_pagado)                                      AS Total_Cobrado,
        SUM(pg.Saldo)                                             AS Total_Pendiente,
        ROUND(SUM(pg.Monto_pagado) * 100.0
              / NULLIF(SUM(pg.Monto), 0), 2)                      AS Porcentaje_Recaudo,
        SUM(CASE WHEN pg.Estado = 'Atrasado' THEN pg.Saldo ELSE 0 END) AS Monto_Atrasado,
        COUNT(CASE WHEN pg.Estado = 'Atrasado' THEN 1 END)        AS Pagos_Atrasados
    FROM pagos pg
    JOIN anio_academico aa ON pg.ID_Anio_Academico = aa.id
    WHERE pg.ID_Anio_Academico = v_id_anio
    GROUP BY aa.Anio;

    -- ── B. Por concepto ───────────────────────────────────────
    SELECT 'POR_CONCEPTO' AS Seccion;
    SELECT
        pg.Concepto,
        COUNT(*)                                                  AS Total_Registros,
        SUM(pg.Monto)                                             AS Total_Facturado,
        SUM(pg.Monto_pagado)                                      AS Total_Cobrado,
        SUM(pg.Saldo)                                             AS Total_Pendiente,
        ROUND(SUM(pg.Monto_pagado) * 100.0
              / NULLIF(SUM(pg.Monto), 0), 2)                      AS Porcentaje_Recaudo
    FROM pagos pg
    WHERE pg.ID_Anio_Academico = v_id_anio
    GROUP BY pg.Concepto
    ORDER BY Total_Facturado DESC;

    -- ── C. Cobros por mes ─────────────────────────────────────
    SELECT 'COBROS_POR_MES' AS Seccion;
    SELECT
        MONTH(pg.Fecha_pago)                                      AS Mes,
        MONTHNAME(pg.Fecha_pago)                                  AS Nombre_Mes,
        COUNT(*)                                                  AS Total_Transacciones,
        SUM(pg.Monto_pagado)                                      AS Total_Cobrado,
        ROUND(SUM(pg.Monto_pagado) * 100.0
              / NULLIF((SELECT SUM(Monto_pagado) FROM pagos
                         WHERE ID_Anio_Academico = v_id_anio
                           AND Estado = 'Pagado'), 0), 2)         AS Porcentaje_Del_Total
    FROM pagos pg
    WHERE pg.ID_Anio_Academico = v_id_anio
      AND pg.Estado = 'Pagado'
      AND pg.Fecha_pago IS NOT NULL
    GROUP BY MONTH(pg.Fecha_pago)
    ORDER BY Mes;

    -- ── D. Top 10 morosos ─────────────────────────────────────
    SELECT 'TOP_MOROSOS' AS Seccion;
    SELECT
        e.Codigo_estudiante,
        CONCAT(p.Nombre, ' ', p.Apellido)                         AS Nombre_Estudiante,
        g.Nombre                                                  AS Grado,
        SUM(pg.Saldo)                                             AS Total_Deuda,
        COUNT(pg.id)                                              AS Cuotas_Pendientes,
        MAX(DATEDIFF(CURDATE(), pg.Fecha_vencimiento))            AS Max_Dias_Vencido
    FROM pagos pg
    JOIN estudiante     e  ON pg.ID_Estudiante  = e.id
    JOIN users          u  ON e.ID_User          = u.id
    JOIN persona        p  ON u.ID_Persona       = p.id
    LEFT JOIN matricula m  ON e.id = m.ID_Estudiante
                           AND m.ID_Anio_Academico = v_id_anio
                           AND m.Estado_matricula  = 'Activa'
    LEFT JOIN grado     g  ON m.ID_Grado           = g.id
    WHERE pg.ID_Anio_Academico = v_id_anio
      AND pg.Estado IN ('Pendiente','Atrasado')
    GROUP BY e.id, e.Codigo_estudiante, p.Nombre, p.Apellido, g.Nombre
    ORDER BY Total_Deuda DESC
    LIMIT 10;

    -- ── E. Métodos de pago utilizados ─────────────────────────
    SELECT 'METODOS_PAGO' AS Seccion;
    SELECT
        IFNULL(pg.Metodo_pago, 'No especificado')                 AS Metodo,
        COUNT(*)                                                  AS Total_Transacciones,
        SUM(pg.Monto_pagado)                                      AS Total_Cobrado,
        ROUND(COUNT(*) * 100.0
              / NULLIF((SELECT COUNT(*) FROM pagos
                         WHERE Estado = 'Pagado'
                           AND ID_Anio_Academico = v_id_anio), 0), 2) AS Porcentaje
    FROM pagos pg
    WHERE pg.ID_Anio_Academico = v_id_anio
      AND pg.Estado = 'Pagado'
    GROUP BY pg.Metodo_pago
    ORDER BY Total_Cobrado DESC;

END$$

CREATE DEFINER=`root`@`localhost` PROCEDURE `sp_admin_reporte_rendimiento_academico` (IN `p_id_anio_academico` BIGINT)   BEGIN
    DECLARE v_id_anio BIGINT;

    IF p_id_anio_academico IS NULL THEN
        SELECT id INTO v_id_anio FROM anio_academico WHERE Es_actual = 1 LIMIT 1;
    ELSE
        SET v_id_anio = p_id_anio_academico;
    END IF;

    -- ── A. Promedio global por grado ──────────────────────────
    SELECT 'PROMEDIO_POR_GRADO' AS Seccion;
    SELECT
        g.Nombre                                                  AS Grado,
        g.Paralelo,
        ne.Nombre                                                 AS Nivel,
        COUNT(DISTINCT c.ID_Estudiante)                           AS Total_Estudiantes,
        COUNT(c.id)                                               AS Total_Evaluaciones,
        ROUND(AVG(c.Nota / c.Nota_maxima * 100), 2)               AS Promedio_General,
        ROUND(SUM(CASE WHEN c.Nota / c.Nota_maxima * 100 >= 60
                       THEN 1 ELSE 0 END) * 100.0
              / NULLIF(COUNT(c.id), 0), 2)                        AS Porcentaje_Aprobacion
    FROM calificaciones c
    JOIN matricula      m  ON c.ID_Estudiante = m.ID_Estudiante
                           AND m.ID_Anio_Academico = v_id_anio
                           AND m.Estado_matricula  = 'Activa'
    JOIN grado          g  ON m.ID_Grado           = g.id
    JOIN nivel_educativo ne ON g.ID_Nivel_educativo = ne.id
    WHERE c.ID_Anio_Academico = v_id_anio
      AND c.Estado IN ('Publicada','Modificada')
    GROUP BY g.id, g.Nombre, g.Paralelo, ne.Nombre
    ORDER BY ne.Orden, g.Curso;

    -- ── B. Materias con mayor índice de reprobación ───────────
    SELECT 'MATERIAS_CRITICAS' AS Seccion;
    SELECT
        mat.Nombre_de_la_materia,
        mat.Area_conocimiento,
        COUNT(c.id)                                               AS Total_Evaluaciones,
        ROUND(AVG(c.Nota / c.Nota_maxima * 100), 2)               AS Promedio_General,
        SUM(CASE WHEN c.Nota / c.Nota_maxima * 100 < 60 THEN 1 ELSE 0 END) AS Total_Reprobados,
        ROUND(SUM(CASE WHEN c.Nota / c.Nota_maxima * 100 < 60 THEN 1 ELSE 0 END)
              * 100.0 / NULLIF(COUNT(c.id), 0), 2)                AS Porcentaje_Reprobacion
    FROM calificaciones c
    JOIN materias mat ON c.ID_Materia = mat.id
    WHERE c.ID_Anio_Academico = v_id_anio
      AND c.Estado IN ('Publicada','Modificada')
    GROUP BY mat.id, mat.Nombre_de_la_materia, mat.Area_conocimiento
    ORDER BY Porcentaje_Reprobacion DESC;

    -- ── C. Rendimiento por docente ────────────────────────────
    SELECT 'RENDIMIENTO_POR_DOCENTE' AS Seccion;
    SELECT
        CONCAT(pd.Nombre, ' ', pd.Apellido)                       AS Docente,
        d.Especialidad,
        COUNT(DISTINCT c.ID_Estudiante)                           AS Total_Estudiantes,
        COUNT(c.id)                                               AS Total_Evaluaciones,
        ROUND(AVG(c.Nota / c.Nota_maxima * 100), 2)               AS Promedio_General,
        ROUND(SUM(CASE WHEN c.Nota / c.Nota_maxima * 100 >= 60 THEN 1 ELSE 0 END)
              * 100.0 / NULLIF(COUNT(c.id), 0), 2)                AS Porcentaje_Aprobacion
    FROM calificaciones c
    JOIN docente  d  ON c.ID_Docente   = d.id
    JOIN users    ud ON d.ID_User      = ud.id
    JOIN persona  pd ON ud.ID_Persona  = pd.id
    WHERE c.ID_Anio_Academico = v_id_anio
      AND c.Estado IN ('Publicada','Modificada')
    GROUP BY d.id, pd.Nombre, pd.Apellido, d.Especialidad
    ORDER BY Promedio_General DESC;

    -- ── D. Comparativa por período ────────────────────────────
    SELECT 'COMPARATIVA_PERIODOS' AS Seccion;
    SELECT
        per.Nombre_periodo,
        per.Numero_periodo,
        COUNT(DISTINCT c.ID_Estudiante)                           AS Estudiantes,
        ROUND(AVG(c.Nota / c.Nota_maxima * 100), 2)               AS Promedio_General,
        ROUND(SUM(CASE WHEN c.Nota / c.Nota_maxima * 100 >= 60 THEN 1 ELSE 0 END)
              * 100.0 / NULLIF(COUNT(c.id), 0), 2)                AS Porcentaje_Aprobacion
    FROM calificaciones c
    JOIN periodo per ON c.ID_Periodo = per.id
    WHERE c.ID_Anio_Academico = v_id_anio
      AND c.Estado IN ('Publicada','Modificada')
    GROUP BY per.id, per.Nombre_periodo, per.Numero_periodo
    ORDER BY per.Numero_periodo;

END$$

CREATE DEFINER=`root`@`localhost` PROCEDURE `sp_admin_resumen_anotaciones` (IN `p_fecha_inicio` DATE, IN `p_fecha_fin` DATE)   BEGIN
    DECLARE v_fecha_inicio DATE;
    DECLARE v_fecha_fin    DATE;

    IF p_fecha_inicio IS NULL THEN
        SELECT Fecha_inicio INTO v_fecha_inicio
        FROM anio_academico WHERE Es_actual = 1 LIMIT 1;
    ELSE
        SET v_fecha_inicio = p_fecha_inicio;
    END IF;

    SET v_fecha_fin = IFNULL(p_fecha_fin, CURDATE());

    -- ── A. Totales por tipo de falta ──────────────────────────
    SELECT 'ANOTACIONES_POR_TIPO_FALTA' AS Seccion;
    SELECT
        rd.Tipo_falta,
        COUNT(*)                                                  AS Total,
        ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2)       AS Porcentaje
    FROM reportes_disciplinarios rd
    WHERE rd.Fecha_incidente BETWEEN v_fecha_inicio AND v_fecha_fin
    GROUP BY rd.Tipo_falta
    ORDER BY FIELD(rd.Tipo_falta, 'Muy_grave','Grave','Moderada','Leve');

    -- ── B. Totales por estado del reporte ─────────────────────
    SELECT 'ANOTACIONES_POR_ESTADO' AS Seccion;
    SELECT
        rd.Estado,
        COUNT(*)                                                  AS Total,
        ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2)       AS Porcentaje
    FROM reportes_disciplinarios rd
    WHERE rd.Fecha_incidente BETWEEN v_fecha_inicio AND v_fecha_fin
    GROUP BY rd.Estado;

    -- ── C. Totales por categoría ──────────────────────────────
    SELECT 'ANOTACIONES_POR_CATEGORIA' AS Seccion;
    SELECT
        IFNULL(rd.Categoria, 'Sin Categoría')                     AS Categoria,
        COUNT(*)                                                  AS Total,
        ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2)       AS Porcentaje
    FROM reportes_disciplinarios rd
    WHERE rd.Fecha_incidente BETWEEN v_fecha_inicio AND v_fecha_fin
    GROUP BY rd.Categoria
    ORDER BY Total DESC;

    -- ── D. Top 10 estudiantes con más anotaciones ─────────────
    SELECT 'TOP10_ESTUDIANTES_MAS_ANOTACIONES' AS Seccion;
    SELECT
        e.Codigo_estudiante,
        CONCAT(p.Nombre, ' ', p.Apellido)                         AS Nombre_Estudiante,
        g.Nombre                                                  AS Grado,
        COUNT(rd.id)                                              AS Total_Anotaciones,
        SUM(CASE WHEN rd.Tipo_falta = 'Leve'      THEN 1 ELSE 0 END) AS Leves,
        SUM(CASE WHEN rd.Tipo_falta = 'Moderada'  THEN 1 ELSE 0 END) AS Moderadas,
        SUM(CASE WHEN rd.Tipo_falta = 'Grave'     THEN 1 ELSE 0 END) AS Graves,
        SUM(CASE WHEN rd.Tipo_falta = 'Muy_grave' THEN 1 ELSE 0 END) AS Muy_Graves
    FROM reportes_disciplinarios rd
    JOIN estudiante  e  ON rd.ID_Estudiante  = e.id
    JOIN users       u  ON e.ID_User         = u.id
    JOIN persona     p  ON u.ID_Persona      = p.id
    LEFT JOIN matricula  m ON e.id = m.ID_Estudiante AND m.Estado_matricula = 'Activa'
    LEFT JOIN grado      g ON m.ID_Grado = g.id
    WHERE rd.Fecha_incidente BETWEEN v_fecha_inicio AND v_fecha_fin
    GROUP BY e.id, e.Codigo_estudiante, p.Nombre, p.Apellido, g.Nombre
    ORDER BY Total_Anotaciones DESC
    LIMIT 10;

    -- ── E. Anotaciones por grado ──────────────────────────────
    SELECT 'ANOTACIONES_POR_GRADO' AS Seccion;
    SELECT
        g.Nombre                                                  AS Grado,
        g.Paralelo,
        COUNT(rd.id)                                              AS Total_Anotaciones,
        ROUND(COUNT(rd.id) * 100.0
              / NULLIF((SELECT COUNT(*) FROM reportes_disciplinarios
                         WHERE Fecha_incidente BETWEEN v_fecha_inicio AND v_fecha_fin), 0), 2) AS Porcentaje
    FROM reportes_disciplinarios rd
    JOIN estudiante  e  ON rd.ID_Estudiante = e.id
    LEFT JOIN matricula m ON e.id = m.ID_Estudiante AND m.Estado_matricula = 'Activa'
    LEFT JOIN grado     g ON m.ID_Grado = g.id
    WHERE rd.Fecha_incidente BETWEEN v_fecha_inicio AND v_fecha_fin
    GROUP BY g.id, g.Nombre, g.Paralelo
    ORDER BY Total_Anotaciones DESC;

    -- ── F. Tendencia mensual de anotaciones ───────────────────
    SELECT 'TENDENCIA_MENSUAL_ANOTACIONES' AS Seccion;
    SELECT
        YEAR(rd.Fecha_incidente)                                  AS Anio,
        MONTH(rd.Fecha_incidente)                                 AS Mes,
        MONTHNAME(rd.Fecha_incidente)                             AS Nombre_Mes,
        COUNT(*)                                                  AS Total,
        SUM(CASE WHEN rd.Tipo_falta = 'Leve'      THEN 1 ELSE 0 END) AS Leves,
        SUM(CASE WHEN rd.Tipo_falta = 'Moderada'  THEN 1 ELSE 0 END) AS Moderadas,
        SUM(CASE WHEN rd.Tipo_falta = 'Grave'     THEN 1 ELSE 0 END) AS Graves,
        SUM(CASE WHEN rd.Tipo_falta = 'Muy_grave' THEN 1 ELSE 0 END) AS Muy_Graves
    FROM reportes_disciplinarios rd
    WHERE rd.Fecha_incidente BETWEEN v_fecha_inicio AND v_fecha_fin
    GROUP BY YEAR(rd.Fecha_incidente), MONTH(rd.Fecha_incidente)
    ORDER BY Anio, Mes;

END$$

CREATE DEFINER=`root`@`localhost` PROCEDURE `sp_admin_resumen_estudiantes` (IN `p_id_anio_academico` BIGINT)   BEGIN
    DECLARE v_id_anio BIGINT;

    IF p_id_anio_academico IS NULL THEN
        SELECT id INTO v_id_anio FROM anio_academico WHERE Es_actual = 1 LIMIT 1;
    ELSE
        SET v_id_anio = p_id_anio_academico;
    END IF;

    -- ── A. Totales por estado del estudiante ─────────────────
    SELECT 'TOTALES_POR_ESTADO' AS Seccion;
    SELECT
        e.Estado,
        COUNT(*)                                                  AS Total,
        ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2)       AS Porcentaje
    FROM estudiante e
    GROUP BY e.Estado
    ORDER BY Total DESC;

    -- ── B. Matriculados vs no matriculados en el año ──────────
    SELECT 'MATRICULADOS_VS_NO_MATRICULADOS' AS Seccion;
    SELECT
        CASE WHEN m.ID_Estudiante IS NOT NULL THEN 'Matriculado' ELSE 'Sin Matrícula' END AS Condicion,
        COUNT(*)                                                                           AS Total,
        ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2)                                AS Porcentaje
    FROM estudiante e
    LEFT JOIN matricula m
           ON e.id = m.ID_Estudiante
          AND m.ID_Anio_Academico = v_id_anio
          AND m.Estado_matricula  = 'Activa'
    WHERE e.Estado = 'Activo'
    GROUP BY Condicion;

    -- ── C. Porcentaje por nivel educativo ─────────────────────
    SELECT 'PORCENTAJE_POR_NIVEL_EDUCATIVO' AS Seccion;
    SELECT
        ne.Nombre                                                 AS Nivel_Educativo,
        COUNT(m.ID_Estudiante)                                    AS Total_Estudiantes,
        ROUND(COUNT(m.ID_Estudiante) * 100.0
              / NULLIF((SELECT COUNT(*) FROM matricula
                         WHERE ID_Anio_Academico = v_id_anio
                           AND Estado_matricula  = 'Activa'), 0), 2) AS Porcentaje
    FROM matricula m
    JOIN grado           g  ON m.ID_Grado             = g.id
    JOIN nivel_educativo ne ON g.ID_Nivel_educativo    = ne.id
    WHERE m.ID_Anio_Academico = v_id_anio
      AND m.Estado_matricula  = 'Activa'
    GROUP BY ne.id, ne.Nombre
    ORDER BY ne.Orden;

    -- ── D. Porcentaje por grado ───────────────────────────────
    SELECT 'PORCENTAJE_POR_GRADO' AS Seccion;
    SELECT
        g.Nombre                                                  AS Grado,
        g.Paralelo,
        g.Turno,
        ne.Nombre                                                 AS Nivel,
        COUNT(m.ID_Estudiante)                                    AS Matriculados,
        g.Capacidad_maxima,
        ROUND(COUNT(m.ID_Estudiante) * 100.0
              / NULLIF(g.Capacidad_maxima, 0), 2)                 AS Porcentaje_Ocupacion,
        g.Capacidad_maxima - COUNT(m.ID_Estudiante)               AS Cupos_Disponibles
    FROM grado g
    JOIN nivel_educativo ne ON g.ID_Nivel_educativo = ne.id
    LEFT JOIN matricula m
           ON g.id = m.ID_Grado
          AND m.ID_Anio_Academico = v_id_anio
          AND m.Estado_matricula  = 'Activa'
    WHERE g.Estado = 'Activo'
    GROUP BY g.id, g.Nombre, g.Paralelo, g.Turno, ne.Nombre, g.Capacidad_maxima
    ORDER BY ne.Orden, g.Curso, g.Paralelo;

    -- ── E. Distribución por género ────────────────────────────
    SELECT 'DISTRIBUCION_GENERO' AS Seccion;
    SELECT
        CASE p.Genero WHEN 'M' THEN 'Masculino' WHEN 'F' THEN 'Femenino' ELSE 'Otro' END AS Genero,
        COUNT(*)                                                       AS Total,
        ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2)            AS Porcentaje
    FROM matricula mat
    JOIN estudiante  e  ON mat.ID_Estudiante = e.id
    JOIN users       u  ON e.ID_User         = u.id
    JOIN persona     p  ON u.ID_Persona      = p.id
    WHERE mat.ID_Anio_Academico = v_id_anio
      AND mat.Estado_matricula  = 'Activa'
    GROUP BY p.Genero;

    -- ── F. Tendencia de inscripciones por mes ─────────────────
    SELECT 'TENDENCIA_INSCRIPCIONES_MES' AS Seccion;
    SELECT
        YEAR(i.Fecha_solicitud)                                   AS Anio,
        MONTH(i.Fecha_solicitud)                                  AS Mes,
        MONTHNAME(i.Fecha_solicitud)                              AS Nombre_Mes,
        COUNT(*)                                                  AS Total_Solicitudes,
        SUM(CASE WHEN i.Estado = 'Aprobada'  THEN 1 ELSE 0 END)  AS Aprobadas,
        SUM(CASE WHEN i.Estado = 'Rechazada' THEN 1 ELSE 0 END)  AS Rechazadas,
        SUM(CASE WHEN i.Estado = 'Cancelada' THEN 1 ELSE 0 END)  AS Canceladas
    FROM inscripcion i
    WHERE i.ID_Anio_Academico = v_id_anio
    GROUP BY YEAR(i.Fecha_solicitud), MONTH(i.Fecha_solicitud)
    ORDER BY Anio, Mes;

END$$

CREATE DEFINER=`root`@`localhost` PROCEDURE `sp_admin_resumen_movimientos` (IN `p_id_anio_academico` BIGINT)   BEGIN
    DECLARE v_id_anio BIGINT;

    IF p_id_anio_academico IS NULL THEN
        SELECT id INTO v_id_anio FROM anio_academico WHERE Es_actual = 1 LIMIT 1;
    ELSE
        SET v_id_anio = p_id_anio_academico;
    END IF;

    -- ── A. Inscripciones por tipo (nuevas/renovación/traslado/reingreso) ──
    SELECT 'INSCRIPCIONES_POR_TIPO' AS Seccion;
    SELECT
        i.Tipo_inscripcion,
        COUNT(*)                                                  AS Total,
        ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2)       AS Porcentaje
    FROM inscripcion i
    WHERE i.ID_Anio_Academico = v_id_anio
    GROUP BY i.Tipo_inscripcion
    ORDER BY Total DESC;

    -- ── B. Bajas / retiros en el año ──────────────────────────
    SELECT 'BAJAS_RETIROS' AS Seccion;
    SELECT
        COUNT(*)                                                  AS Total_Retirados,
        ROUND(COUNT(*) * 100.0
              / NULLIF((SELECT COUNT(*) FROM estudiante), 0), 2)  AS Porcentaje_Sobre_Total,
        SUM(CASE WHEN m.Estado_matricula = 'Retirada'   THEN 1 ELSE 0 END) AS Matriculas_Retiradas,
        SUM(CASE WHEN m.Estado_matricula = 'Trasladada' THEN 1 ELSE 0 END) AS Matriculas_Trasladadas,
        SUM(CASE WHEN m.Estado_matricula = 'Finalizada' THEN 1 ELSE 0 END) AS Matriculas_Finalizadas
    FROM matricula m
    WHERE m.ID_Anio_Academico = v_id_anio
      AND m.Estado_matricula IN ('Retirada','Trasladada','Finalizada');

    -- ── C. Detalle de traslados por colegio de procedencia ────
    SELECT 'TRASLADOS_POR_PROCEDENCIA' AS Seccion;
    SELECT
        IFNULL(i.Colegio_procedencia, 'No especificado')          AS Colegio_Procedencia,
        COUNT(*)                                                  AS Total,
        ROUND(COUNT(*) * 100.0
              / NULLIF((SELECT COUNT(*) FROM inscripcion
                         WHERE Tipo_inscripcion = 'Traslado'
                           AND ID_Anio_Academico = v_id_anio), 0), 2) AS Porcentaje
    FROM inscripcion i
    WHERE i.Tipo_inscripcion    = 'Traslado'
      AND i.ID_Anio_Academico   = v_id_anio
    GROUP BY i.Colegio_procedencia
    ORDER BY Total DESC;

    -- ── D. Reingresos por grado ───────────────────────────────
    SELECT 'REINGRESOS_POR_GRADO' AS Seccion;
    SELECT
        g.Nombre                                                  AS Grado,
        g.Paralelo,
        COUNT(i.id)                                               AS Total_Reingresos
    FROM inscripcion i
    JOIN matricula m ON i.ID_Estudiante      = m.ID_Estudiante
                     AND m.ID_Anio_Academico = v_id_anio
    JOIN grado     g ON m.ID_Grado           = g.id
    WHERE i.Tipo_inscripcion  = 'Reingreso'
      AND i.ID_Anio_Academico = v_id_anio
    GROUP BY g.id, g.Nombre, g.Paralelo
    ORDER BY Total_Reingresos DESC;

    -- ── E. Comparativa año anterior vs año actual ─────────────
    SELECT 'COMPARATIVA_ANIOS' AS Seccion;
    SELECT
        aa.Anio                                                   AS Anio_Academico,
        COUNT(i.id)                                               AS Total_Inscripciones,
        SUM(CASE WHEN i.Tipo_inscripcion = 'Nueva'      THEN 1 ELSE 0 END) AS Nuevas,
        SUM(CASE WHEN i.Tipo_inscripcion = 'Renovacion' THEN 1 ELSE 0 END) AS Renovaciones,
        SUM(CASE WHEN i.Tipo_inscripcion = 'Traslado'   THEN 1 ELSE 0 END) AS Traslados,
        SUM(CASE WHEN i.Tipo_inscripcion = 'Reingreso'  THEN 1 ELSE 0 END) AS Reingresos,
        SUM(CASE WHEN i.Estado = 'Aprobada'             THEN 1 ELSE 0 END) AS Aprobadas
    FROM inscripcion i
    JOIN anio_academico aa ON i.ID_Anio_Academico = aa.id
    WHERE aa.id IN (v_id_anio, v_id_anio - 1)
    GROUP BY aa.Anio
    ORDER BY aa.Anio DESC;

    -- ── F. Retiros de estudiantes (detalle) ───────────────────
    SELECT 'DETALLE_RETIROS' AS Seccion;
    SELECT
        e.Codigo_estudiante,
        CONCAT(p.Nombre, ' ', p.Apellido)                         AS Nombre_Estudiante,
        g.Nombre                                                  AS Grado,
        m.Estado_matricula,
        m.Observaciones                                           AS Motivo,
        m.Actualizado_en                                          AS Fecha_Retiro
    FROM matricula m
    JOIN estudiante e   ON m.ID_Estudiante  = e.id
    JOIN users      u   ON e.ID_User         = u.id
    JOIN persona    p   ON u.ID_Persona      = p.id
    LEFT JOIN grado g   ON m.ID_Grado        = g.id
    WHERE m.ID_Anio_Academico = v_id_anio
      AND m.Estado_matricula IN ('Retirada','Trasladada')
    ORDER BY m.Actualizado_en DESC;

END$$

CREATE DEFINER=`` PROCEDURE `sp_cursos_por_docente` (IN `p_id_docente` BIGINT, IN `p_id_anio_academico` BIGINT, IN `p_id_periodo` BIGINT)   BEGIN

    DECLARE v_id_anio BIGINT;

    IF p_id_anio_academico IS NULL THEN
        SELECT id INTO v_id_anio FROM anio_academico WHERE Es_actual = 1 LIMIT 1;
    ELSE
        SET v_id_anio = p_id_anio_academico;
    END IF;

    SELECT
        c.id                                          AS ID_Curso,
        c.Titulo,
        c.Tema,
        mat.Nombre_de_la_materia                      AS Materia,
        g.Nombre                                      AS Grado,
        g.Paralelo,
        per.Nombre_periodo                            AS Periodo,
        c.Fecha_programada,
        c.Hora_inicio,
        c.Hora_fin,
        c.Aula,
        c.Tipo,
        c.Modalidad,
        c.Estado,
        (SELECT COUNT(*) FROM asistencia_curso ac
         WHERE ac.ID_Curso = c.id
           AND ac.Estado   = 'Presente')              AS Estudiantes_Presentes,
        (SELECT COUNT(*) FROM asistencia_curso ac2
         WHERE ac2.ID_Curso = c.id)                  AS Total_Registros_Asistencia,
        c.Observaciones,
        c.Creado_en
    FROM cursos c
    JOIN asignacion_docente ad ON c.ID_Asignacion     = ad.id
    JOIN materias           mat ON ad.ID_Materia       = mat.id
    JOIN grado              g   ON ad.ID_Grado         = g.id
    JOIN periodo            per ON c.ID_Periodo        = per.id
    WHERE ad.ID_Docente          = p_id_docente
      AND c.ID_Anio_Academico    = v_id_anio
      AND (p_id_periodo IS NULL OR c.ID_Periodo = p_id_periodo)
    ORDER BY c.Fecha_programada DESC, c.Hora_inicio;
END$$

CREATE DEFINER=`root`@`localhost` PROCEDURE `sp_eliminar_administrativo_por_nombre` (IN `p_nombre` VARCHAR(255), IN `p_apellido` VARCHAR(255), IN `p_motivo` TEXT, IN `p_usuario_elimina` BIGINT, OUT `p_eliminados` INT, OUT `p_mensaje` VARCHAR(500))   BEGIN
    DECLARE v_id_admin BIGINT;
    DECLARE v_id_user BIGINT;
    DECLARE v_id_persona BIGINT;
    DECLARE v_count INT DEFAULT 0;
    DECLARE v_done INT DEFAULT 0;
    
    DECLARE cur_admins CURSOR FOR
        SELECT pa.id, pa.ID_User, u.ID_Persona
        FROM plantel_administrativo pa
        INNER JOIN users u ON pa.ID_User = u.id
        INNER JOIN persona p ON u.ID_Persona = p.id
        WHERE p.Nombre LIKE CONCAT('%', p_nombre, '%')
          AND p.Apellido LIKE CONCAT('%', p_apellido, '%')
          AND pa.Estado != 'Retirado';
    
    DECLARE CONTINUE HANDLER FOR NOT FOUND SET v_done = 1;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SET p_mensaje = 'Error: No se pudieron eliminar los administrativos.';
        SET p_eliminados = 0;
    END;
    
    START TRANSACTION;
    
    OPEN cur_admins;
    
    read_loop: LOOP
        FETCH cur_admins INTO v_id_admin, v_id_user, v_id_persona;
        
        IF v_done THEN
            LEAVE read_loop;
        END IF;
        
        -- Registrar en auditoría
        INSERT INTO auditoria (ID_User, Accion, Tabla_afectada, ID_Registro_afectado, Datos_anteriores)
        VALUES (
            p_usuario_elimina,
            'DELETE',
            'plantel_administrativo',
            v_id_admin,
            JSON_OBJECT(
                'id', v_id_admin,
                'Motivo_eliminacion', p_motivo,
                'Fecha_eliminacion', NOW()
            )
        );
        
        -- Cambiar estado a "Retirado"
        UPDATE plantel_administrativo SET Estado = 'Retirado', Fecha_salida = CURDATE(),
               Observaciones = CONCAT(IFNULL(Observaciones, ''), ' | ELIMINADO: ', p_motivo)
        WHERE id = v_id_admin;
        
        -- Desactivar usuario
        UPDATE users SET Estado = 'Inactivo' WHERE id = v_id_user;
        
        SET v_count = v_count + 1;
    END LOOP;
    
    CLOSE cur_admins;
    
    COMMIT;
    
    SET p_eliminados = v_count;
    SET p_mensaje = CONCAT('Se eliminaron (retiraron) ', v_count, ' administrativo(s) exitosamente.');
END$$

CREATE DEFINER=`root`@`localhost` PROCEDURE `sp_eliminar_docente_por_nombre` (IN `p_nombre` VARCHAR(255), IN `p_apellido` VARCHAR(255), IN `p_motivo` TEXT, IN `p_usuario_elimina` BIGINT, OUT `p_eliminados` INT, OUT `p_mensaje` VARCHAR(500))   BEGIN
    DECLARE v_id_docente BIGINT;
    DECLARE v_id_user BIGINT;
    DECLARE v_id_persona BIGINT;
    DECLARE v_count INT DEFAULT 0;
    DECLARE v_done INT DEFAULT 0;
    
    DECLARE cur_docentes CURSOR FOR
        SELECT d.id, d.ID_User, u.ID_Persona
        FROM docente d
        INNER JOIN users u ON d.ID_User = u.id
        INNER JOIN persona p ON u.ID_Persona = p.id
        WHERE p.Nombre LIKE CONCAT('%', p_nombre, '%')
          AND p.Apellido LIKE CONCAT('%', p_apellido, '%')
          AND d.Estado != 'Retirado';
    
    DECLARE CONTINUE HANDLER FOR NOT FOUND SET v_done = 1;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SET p_mensaje = 'Error: No se pudieron eliminar los docentes.';
        SET p_eliminados = 0;
    END;
    
    START TRANSACTION;
    
    OPEN cur_docentes;
    
    read_loop: LOOP
        FETCH cur_docentes INTO v_id_docente, v_id_user, v_id_persona;
        
        IF v_done THEN
            LEAVE read_loop;
        END IF;
        
        -- Registrar en auditoría
        INSERT INTO auditoria (ID_User, Accion, Tabla_afectada, ID_Registro_afectado, Datos_anteriores)
        VALUES (
            p_usuario_elimina,
            'DELETE',
            'docente',
            v_id_docente,
            JSON_OBJECT(
                'id', v_id_docente,
                'Motivo_eliminacion', p_motivo,
                'Fecha_eliminacion', NOW()
            )
        );
        
        -- Cambiar estado a "Retirado"
        UPDATE docente SET Estado = 'Retirado', Observaciones = CONCAT(IFNULL(Observaciones, ''), ' | ELIMINADO: ', p_motivo)
        WHERE id = v_id_docente;
        
        -- Desactivar usuario
        UPDATE users SET Estado = 'Inactivo' WHERE id = v_id_user;
        
        -- Finalizar asignaciones activas
        UPDATE asignacion_docente SET Estado = 'Finalizado', Fecha_fin = CURDATE()
        WHERE ID_Docente = v_id_docente AND Estado = 'Activo';
        
        SET v_count = v_count + 1;
    END LOOP;
    
    CLOSE cur_docentes;
    
    COMMIT;
    
    SET p_eliminados = v_count;
    SET p_mensaje = CONCAT('Se eliminaron (retiraron) ', v_count, ' docente(s) exitosamente.');
END$$

CREATE DEFINER=`root`@`localhost` PROCEDURE `sp_eliminar_estudiante_por_nombre` (IN `p_nombre` VARCHAR(255), IN `p_apellido` VARCHAR(255), IN `p_motivo` TEXT, IN `p_usuario_elimina` BIGINT, OUT `p_eliminados` INT, OUT `p_mensaje` VARCHAR(500))   BEGIN
    DECLARE v_id_estudiante BIGINT;
    DECLARE v_id_user BIGINT;
    DECLARE v_id_persona BIGINT;
    DECLARE v_codigo VARCHAR(50);
    DECLARE v_count INT DEFAULT 0;
    DECLARE v_done INT DEFAULT 0;
    
    DECLARE cur_estudiantes CURSOR FOR
        SELECT e.id, e.ID_User, e.Codigo_estudiante, u.ID_Persona
        FROM estudiante e
        INNER JOIN users u ON e.ID_User = u.id
        INNER JOIN persona p ON u.ID_Persona = p.id
        WHERE p.Nombre LIKE CONCAT('%', p_nombre, '%')
          AND p.Apellido LIKE CONCAT('%', p_apellido, '%')
          AND e.Estado != 'Retirado';
    
    DECLARE CONTINUE HANDLER FOR NOT FOUND SET v_done = 1;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SET p_mensaje = 'Error: No se pudieron eliminar los estudiantes.';
        SET p_eliminados = 0;
    END;
    
    START TRANSACTION;
    
    OPEN cur_estudiantes;
    
    read_loop: LOOP
        FETCH cur_estudiantes INTO v_id_estudiante, v_id_user, v_codigo, v_id_persona;
        
        IF v_done THEN
            LEAVE read_loop;
        END IF;
        
        -- Registrar en auditoría antes de eliminar
        INSERT INTO auditoria (ID_User, Accion, Tabla_afectada, ID_Registro_afectado, Datos_anteriores)
        VALUES (
            p_usuario_elimina,
            'DELETE',
            'estudiante',
            v_id_estudiante,
            JSON_OBJECT(
                'id', v_id_estudiante,
                'Codigo', v_codigo,
                'Motivo_eliminacion', p_motivo,
                'Fecha_eliminacion', NOW()
            )
        );
        
        -- Cambiar estado a "Retirado" en lugar de eliminar físicamente
        UPDATE estudiante SET Estado = 'Retirado', Observaciones = CONCAT(IFNULL(Observaciones, ''), ' | ELIMINADO: ', p_motivo)
        WHERE id = v_id_estudiante;
        
        -- Desactivar usuario
        UPDATE users SET Estado = 'Inactivo' WHERE id = v_id_user;
        
        SET v_count = v_count + 1;
    END LOOP;
    
    CLOSE cur_estudiantes;
    
    COMMIT;
    
    SET p_eliminados = v_count;
    SET p_mensaje = CONCAT('Se eliminaron (retiraron) ', v_count, ' estudiante(s) exitosamente.');
END$$

CREATE DEFINER=`root`@`localhost` PROCEDURE `sp_eliminar_padre_por_nombre` (IN `p_nombre` VARCHAR(255), IN `p_apellido` VARCHAR(255), IN `p_motivo` TEXT, IN `p_usuario_elimina` BIGINT, OUT `p_eliminados` INT, OUT `p_mensaje` VARCHAR(500))   BEGIN
    DECLARE v_id_padre BIGINT;
    DECLARE v_id_user BIGINT;
    DECLARE v_id_persona BIGINT;
    DECLARE v_count INT DEFAULT 0;
    DECLARE v_done INT DEFAULT 0;
    
    DECLARE cur_padres CURSOR FOR
        SELECT pt.id, pt.ID_User, u.ID_Persona
        FROM padre_tutor pt
        INNER JOIN users u ON pt.ID_User = u.id
        INNER JOIN persona p ON u.ID_Persona = p.id
        WHERE p.Nombre LIKE CONCAT('%', p_nombre, '%')
          AND p.Apellido LIKE CONCAT('%', p_apellido, '%')
          AND pt.Estado != 'Inactivo';
    
    DECLARE CONTINUE HANDLER FOR NOT FOUND SET v_done = 1;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SET p_mensaje = 'Error: No se pudieron eliminar los padres/tutores.';
        SET p_eliminados = 0;
    END;
    
    START TRANSACTION;
    
    OPEN cur_padres;
    
    read_loop: LOOP
        FETCH cur_padres INTO v_id_padre, v_id_user, v_id_persona;
        
        IF v_done THEN
            LEAVE read_loop;
        END IF;
        
        -- Registrar en auditoría
        INSERT INTO auditoria (ID_User, Accion, Tabla_afectada, ID_Registro_afectado, Datos_anteriores)
        VALUES (
            p_usuario_elimina,
            'DELETE',
            'padre_tutor',
            v_id_padre,
            JSON_OBJECT(
                'id', v_id_padre,
                'Motivo_eliminacion', p_motivo,
                'Fecha_eliminacion', NOW()
            )
        );
        
        -- Cambiar estado a "Inactivo"
        UPDATE padre_tutor SET Estado = 'Inactivo'
        WHERE id = v_id_padre;
        
        -- Desactivar usuario
        UPDATE users SET Estado = 'Inactivo' WHERE id = v_id_user;
        
        SET v_count = v_count + 1;
    END LOOP;
    
    CLOSE cur_padres;
    
    COMMIT;
    
    SET p_eliminados = v_count;
    SET p_mensaje = CONCAT('Se eliminaron (desactivaron) ', v_count, ' padre(s)/tutor(es) exitosamente.');
END$$

CREATE DEFINER=`root`@`localhost` PROCEDURE `sp_generar_codigo_2fa` (IN `p_id_user` BIGINT, IN `p_metodo` ENUM('Email','Telefono'), IN `p_ip` VARCHAR(45), OUT `p_id_verificacion` BIGINT, OUT `p_destino` VARCHAR(255), OUT `p_mensaje` VARCHAR(500))   proc: BEGIN

    DECLARE v_estado_user   VARCHAR(20);
    DECLARE v_id_persona    BIGINT;
    DECLARE v_email         VARCHAR(255);
    DECLARE v_telefono      VARCHAR(50);
    DECLARE v_codigo        VARCHAR(6);
    DECLARE v_token         VARCHAR(255);
    DECLARE v_expiracion    TIMESTAMP;
    DECLARE v_intentos_hoy  INT DEFAULT 0;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SET p_id_verificacion = NULL;
        SET p_destino         = NULL;
        SET p_mensaje = 'Error: No se pudo generar el código de verificación.';
    END;

    START TRANSACTION;

    -- ── 1. Validar que el usuario existe y está activo ──────────
    SELECT u.Estado, u.ID_Persona
    INTO   v_estado_user, v_id_persona
    FROM   users u
    WHERE  u.id = p_id_user;

    IF v_id_persona IS NULL THEN
        ROLLBACK;
        SET p_mensaje = 'Error: Usuario no encontrado.';
        LEAVE proc;
    END IF;

    IF v_estado_user NOT IN ('Activo') THEN
        ROLLBACK;
        SET p_mensaje = CONCAT('Error: El usuario se encuentra en estado "', v_estado_user, '".');
        LEAVE proc;
    END IF;

    -- ── 2. Verificar límite de solicitudes (máx 5 por hora) ─────
    SELECT COUNT(*)
    INTO   v_intentos_hoy
    FROM   verificacion v
    INNER JOIN users u ON u.ID_Verificacion = v.id
    WHERE  u.id         = p_id_user
      AND  v.Tipo       = p_metodo
      AND  v.Fecha_verificacion >= DATE_SUB(NOW(), INTERVAL 1 HOUR)
      AND  v.Estado IN ('Pendiente','Expirado');

    IF v_intentos_hoy >= 5 THEN
        ROLLBACK;
        SET p_mensaje = 'Error: Ha superado el límite de solicitudes. Intente nuevamente en 1 hora.';
        LEAVE proc;
    END IF;

    -- ── 3. Obtener destino según método ─────────────────────────
    SELECT p.Email_personal, p.Telefono
    INTO   v_email, v_telefono
    FROM   persona p
    WHERE  p.id = v_id_persona;

    IF p_metodo = 'Email' THEN
        -- Usar el correo institucional del users
        SELECT u.Correo INTO v_email FROM users u WHERE u.id = p_id_user;
        IF v_email IS NULL OR TRIM(v_email) = '' THEN
            ROLLBACK;
            SET p_mensaje = 'Error: El usuario no tiene correo electrónico registrado.';
            LEAVE proc;
        END IF;
        SET p_destino = v_email;
    ELSE
        IF v_telefono IS NULL OR TRIM(v_telefono) = '' THEN
            ROLLBACK;
            SET p_mensaje = 'Error: El usuario no tiene número de teléfono registrado.';
            LEAVE proc;
        END IF;
        SET p_destino = v_telefono;
    END IF;

    -- ── 4. Expirar códigos anteriores pendientes del mismo método
    UPDATE verificacion v
    INNER JOIN users u ON u.ID_Verificacion = v.id
    SET    v.Estado = 'Expirado'
    WHERE  u.id     = p_id_user
      AND  v.Tipo   = p_metodo
      AND  v.Estado = 'Pendiente';

    -- ── 5. Generar código de 6 dígitos ──────────────────────────
    SET v_codigo     = LPAD(FLOOR(RAND() * 1000000), 6, '0');
    SET v_expiracion = DATE_ADD(NOW(), INTERVAL 10 MINUTE);
    SET v_token      = CONCAT(
        v_codigo, '|',
        MD5(CONCAT(p_id_user, v_codigo, NOW(), RAND()))
    );

    -- ── 6. Insertar en verificacion ─────────────────────────────
    INSERT INTO verificacion (Tipo, Token, Estado, Fecha_expiracion)
    VALUES (p_metodo, v_token, 'Pendiente', v_expiracion);

    SET p_id_verificacion = LAST_INSERT_ID();

    -- ── 7. Vincular al usuario ───────────────────────────────────
    UPDATE users
    SET    ID_Verificacion = p_id_verificacion
    WHERE  id = p_id_user;

    -- ── 8. Auditoría ─────────────────────────────────────────────
    INSERT INTO auditoria_usuarios (ID_User, Accion, IP_Address, Detalles)
    VALUES (
        p_id_user,
        'LOGIN',
        p_ip,
        JSON_OBJECT(
            'accion',          '2FA_CODIGO_GENERADO',
            'metodo',          p_metodo,
            'id_verificacion', p_id_verificacion,
            'expira_en',       v_expiracion
        )
    );

    COMMIT;

    SET p_mensaje = CONCAT(
        'Código generado. Expira en 10 minutos. Destino: ', p_destino
    );

END proc$$

CREATE DEFINER=`root`@`localhost` PROCEDURE `sp_historial_estudiante` (IN `p_id_estudiante` BIGINT)   BEGIN
    -- Datos básicos
    SELECT 'DATOS_BASICOS' AS Seccion;
    SELECT * FROM v_datos_completos_estudiante WHERE ID_Estudiante = p_id_estudiante;
    
    -- Historial de calificaciones
    SELECT 'CALIFICACIONES' AS Seccion;
    SELECT * FROM v_notas_estudiante WHERE ID_Estudiante = p_id_estudiante ORDER BY Anio_Academico DESC, Numero_periodo DESC;
    
    -- Historial de asistencias
    SELECT 'ASISTENCIAS' AS Seccion;
    SELECT * FROM v_resumen_asistencias_estudiante WHERE ID_Estudiante = p_id_estudiante ORDER BY Anio DESC, Mes DESC;
    
    -- Historial de pagos
    SELECT 'PAGOS' AS Seccion;
    SELECT * FROM pagos WHERE ID_Estudiante = p_id_estudiante ORDER BY Creado_en DESC;
    
    -- Historial de auditoría
    SELECT 'AUDITORIA' AS Seccion;
    SELECT * FROM auditoria WHERE Tabla_afectada IN ('estudiante', 'calificaciones') 
    AND ID_Registro_afectado = p_id_estudiante 
    ORDER BY Fecha_hora DESC LIMIT 50;
END$$

CREATE DEFINER=`root`@`localhost` PROCEDURE `sp_inscribir_estudiante` (IN `p_nombre` VARCHAR(255), IN `p_apellido` VARCHAR(255), IN `p_ci` VARCHAR(50), IN `p_fecha_nacimiento` DATE, IN `p_genero` ENUM('M','F','Otro'), IN `p_direccion` VARCHAR(255), IN `p_telefono` VARCHAR(50), IN `p_email_personal` VARCHAR(255), IN `p_nacionalidad` VARCHAR(100), IN `p_estado_civil` VARCHAR(50), IN `p_correo` VARCHAR(255), IN `p_password` VARCHAR(255), IN `p_tipo_sangre` VARCHAR(10), IN `p_alergias` TEXT, IN `p_condiciones_medicas` TEXT, IN `p_medicamentos` TEXT, IN `p_seguro_medico` VARCHAR(255), IN `p_numero_hermanos` INT, IN `p_posicion_hermanos` INT, IN `p_vive_con` VARCHAR(255), IN `p_necesidades_especiales` TEXT, IN `p_transporte` ENUM('Propio','Escolar','Publico','A_pie'), IN `p_id_grado` BIGINT, IN `p_tipo_inscripcion` ENUM('Nueva','Renovacion','Reingreso','Traslado'), IN `p_colegio_procedencia` VARCHAR(255), IN `p_motivo_traslado` TEXT, IN `p_monto_matricula` DECIMAL(10,2), IN `p_descuento_matricula` DECIMAL(5,2), IN `p_tipo_estudiante` ENUM('Regular','Repitente','Traslado','Oyente'), IN `p_requiere_apoyo` TINYINT(1), IN `p_observaciones` TEXT, IN `p_usuario_registra` BIGINT, IN `p1_nombre` VARCHAR(255), IN `p1_apellido` VARCHAR(255), IN `p1_ci` VARCHAR(50), IN `p1_fecha_nacimiento` DATE, IN `p1_genero_persona` ENUM('M','F','Otro'), IN `p1_direccion` VARCHAR(255), IN `p1_telefono` VARCHAR(50), IN `p1_email_personal` VARCHAR(255), IN `p1_nacionalidad` VARCHAR(100), IN `p1_estado_civil` VARCHAR(50), IN `p1_correo` VARCHAR(255), IN `p1_password` VARCHAR(255), IN `p1_genero_padre` VARCHAR(50), IN `p1_ocupacion` VARCHAR(255), IN `p1_lugar_trabajo` VARCHAR(255), IN `p1_telefono_trabajo` VARCHAR(50), IN `p1_nivel_educativo` VARCHAR(100), IN `p1_ingreso_mensual` DECIMAL(10,2), IN `p1_parentesco` ENUM('Padre','Madre','Abuelo','Abuela','Tio','Tia','Hermano','Hermana','Tutor_legal','Otro'), IN `p1_es_responsable_economico` TINYINT(1), IN `p1_es_contacto_emergencia` TINYINT(1), IN `p1_puede_retirar` TINYINT(1), IN `p1_vive_con_estudiante` TINYINT(1), IN `p2_nombre` VARCHAR(255), IN `p2_apellido` VARCHAR(255), IN `p2_ci` VARCHAR(50), IN `p2_fecha_nacimiento` DATE, IN `p2_genero_persona` ENUM('M','F','Otro'), IN `p2_direccion` VARCHAR(255), IN `p2_telefono` VARCHAR(50), IN `p2_email_personal` VARCHAR(255), IN `p2_nacionalidad` VARCHAR(100), IN `p2_estado_civil` VARCHAR(50), IN `p2_correo` VARCHAR(255), IN `p2_password` VARCHAR(255), IN `p2_genero_padre` VARCHAR(50), IN `p2_ocupacion` VARCHAR(255), IN `p2_lugar_trabajo` VARCHAR(255), IN `p2_telefono_trabajo` VARCHAR(50), IN `p2_nivel_educativo` VARCHAR(100), IN `p2_ingreso_mensual` DECIMAL(10,2), IN `p2_parentesco` ENUM('Padre','Madre','Abuelo','Abuela','Tio','Tia','Hermano','Hermana','Tutor_legal','Otro'), IN `p2_es_responsable_economico` TINYINT(1), IN `p2_es_contacto_emergencia` TINYINT(1), IN `p2_puede_retirar` TINYINT(1), IN `p2_vive_con_estudiante` TINYINT(1), OUT `p_id_persona` BIGINT, OUT `p_id_user` BIGINT, OUT `p_id_estudiante` BIGINT, OUT `p_id_inscripcion` BIGINT, OUT `p_id_matricula` BIGINT, OUT `p_codigo_estudiante` VARCHAR(50), OUT `p_numero_matricula` VARCHAR(50), OUT `p_id_padre1` BIGINT, OUT `p_id_padre2` BIGINT, OUT `p_mensaje` VARCHAR(500))   proc: BEGIN

    DECLARE v_id_verificacion   BIGINT;
    DECLARE v_id_anio_academico BIGINT;
    DECLARE v_anio_actual       INT;
    DECLARE v_correlativo       INT;
    DECLARE v_token             VARCHAR(255);
    DECLARE v_fecha_expiracion  TIMESTAMP;
    DECLARE v_capacidad_max     INT;
    DECLARE v_capacidad_actual  INT;
    DECLARE v_nivel_educativo   BIGINT;
    DECLARE v_p1_id_persona     BIGINT;
    DECLARE v_p1_id_user        BIGINT;
    DECLARE v_p1_id_verif       BIGINT;
    DECLARE v_p1_token          VARCHAR(255);
    DECLARE v_p2_id_persona     BIGINT;
    DECLARE v_p2_id_user        BIGINT;
    DECLARE v_p2_id_verif       BIGINT;
    DECLARE v_p2_token          VARCHAR(255);

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SET p_id_persona        = NULL;
        SET p_id_user           = NULL;
        SET p_id_estudiante     = NULL;
        SET p_id_inscripcion    = NULL;
        SET p_id_matricula      = NULL;
        SET p_codigo_estudiante = NULL;
        SET p_numero_matricula  = NULL;
        SET p_id_padre1         = NULL;
        SET p_id_padre2         = NULL;
        SET p_mensaje = 'Error: No se pudo completar la inscripción. Verifique los datos e intente nuevamente.';
    END;

    START TRANSACTION;

    -- ══════════════════════════════════════════════════════════
    -- VALIDACIONES PREVIAS
    -- ══════════════════════════════════════════════════════════

    IF EXISTS (SELECT 1 FROM users WHERE Correo = p_correo) THEN
        ROLLBACK;
        SET p_mensaje = 'Error: El correo del estudiante ya está registrado.';
        -- ▼▼▼ CAMBIO: LEAVE proc (no LEAVE sp_inscribir_estudiante) ▼▼▼
        LEAVE proc;
    END IF;

    IF EXISTS (SELECT 1 FROM persona WHERE CI = p_ci) THEN
        ROLLBACK;
        SET p_mensaje = 'Error: El CI del estudiante ya está registrado.';
        LEAVE proc;
    END IF;

    IF EXISTS (SELECT 1 FROM users WHERE Correo = p1_correo) THEN
        ROLLBACK;
        SET p_mensaje = 'Error: El correo del tutor 1 ya está registrado.';
        LEAVE proc;
    END IF;

    IF EXISTS (SELECT 1 FROM persona WHERE CI = p1_ci) THEN
        ROLLBACK;
        SET p_mensaje = 'Error: El CI del tutor 1 ya está registrado.';
        LEAVE proc;
    END IF;

    IF p2_nombre IS NOT NULL THEN
        IF EXISTS (SELECT 1 FROM users WHERE Correo = p2_correo) THEN
            ROLLBACK;
            SET p_mensaje = 'Error: El correo del tutor 2 ya está registrado.';
            LEAVE proc;
        END IF;

        IF EXISTS (SELECT 1 FROM persona WHERE CI = p2_ci) THEN
            ROLLBACK;
            SET p_mensaje = 'Error: El CI del tutor 2 ya está registrado.';
            LEAVE proc;
        END IF;
    END IF;

    SELECT Capacidad_maxima, Capacidad_actual, ID_Nivel_educativo
    INTO   v_capacidad_max, v_capacidad_actual, v_nivel_educativo
    FROM   grado
    WHERE  id = p_id_grado AND Estado = 'Activo';

    IF v_capacidad_max IS NULL THEN
        ROLLBACK;
        SET p_mensaje = 'Error: El grado especificado no existe o no está activo.';
        LEAVE proc;
    END IF;

    IF v_capacidad_actual >= v_capacidad_max THEN
        ROLLBACK;
        SET p_mensaje = 'Error: El grado seleccionado no tiene cupos disponibles.';
        LEAVE proc;
    END IF;

    SELECT id, Anio
    INTO   v_id_anio_academico, v_anio_actual
    FROM   anio_academico
    WHERE  Es_actual = 1
    LIMIT  1;

    IF v_id_anio_academico IS NULL THEN
        ROLLBACK;
        SET p_mensaje = 'Error: No hay un año académico activo configurado.';
        LEAVE proc;
    END IF;

    -- ══════════════════════════════════════════════════════════
    -- BLOQUE A — REGISTRO DEL ESTUDIANTE
    -- ══════════════════════════════════════════════════════════

    INSERT INTO persona (
        Nombre, Apellido, CI, Fecha_nacimiento, Genero,
        Direccion, Telefono, Email_personal, Nacionalidad, Estado_civil
    ) VALUES (
        p_nombre, p_apellido, p_ci, p_fecha_nacimiento, p_genero,
        p_direccion, p_telefono, p_email_personal,
        IFNULL(p_nacionalidad, 'Boliviana'), p_estado_civil
    );
    SET p_id_persona = LAST_INSERT_ID();

    SET v_token = CONCAT(MD5(CONCAT(p_correo, NOW(), RAND())), '-', UNIX_TIMESTAMP());
    SET v_fecha_expiracion = DATE_ADD(NOW(), INTERVAL 48 HOUR);

    INSERT INTO verificacion (Tipo, Token, Estado, Fecha_expiracion)
    VALUES ('Email', v_token, 'Pendiente', v_fecha_expiracion);
    SET v_id_verificacion = LAST_INSERT_ID();

    INSERT INTO users (ID_Persona, ID_Verificacion, ID_Rol, Correo, Password, Estado)
    VALUES (p_id_persona, v_id_verificacion, 3, p_correo, p_password, 'Activo');
    SET p_id_user = LAST_INSERT_ID();

    SELECT COUNT(*) + 1 INTO v_correlativo
    FROM   estudiante e
    INNER JOIN users u ON e.ID_User = u.id
    WHERE  YEAR(u.Fecha_de_creacion) = v_anio_actual;

    SET p_codigo_estudiante = CONCAT('EST-', v_anio_actual, '-', LPAD(v_correlativo, 3, '0'));

    WHILE EXISTS (SELECT 1 FROM estudiante WHERE Codigo_estudiante = p_codigo_estudiante) DO
        SET v_correlativo = v_correlativo + 1;
        SET p_codigo_estudiante = CONCAT('EST-', v_anio_actual, '-', LPAD(v_correlativo, 3, '0'));
    END WHILE;

    INSERT INTO estudiante (
        ID_User, Codigo_estudiante, Tipo_sangre, Alergias,
        Condiciones_medicas, Medicamentos, Seguro_medico,
        Numero_hermanos, Posicion_hermanos, Vive_con,
        Necesidades_especiales, Transporte, Estado, Observaciones
    ) VALUES (
        p_id_user, p_codigo_estudiante, p_tipo_sangre, p_alergias,
        p_condiciones_medicas, p_medicamentos, p_seguro_medico,
        IFNULL(p_numero_hermanos, 0), p_posicion_hermanos, p_vive_con,
        p_necesidades_especiales, p_transporte, 'Activo', p_observaciones
    );
    SET p_id_estudiante = LAST_INSERT_ID();

    INSERT INTO inscripcion (
        ID_Estudiante, ID_Anio_Academico, Fecha_solicitud, Fecha_aprobacion,
        Estado, Tipo_inscripcion, Colegio_procedencia, Motivo_traslado,
        Documentos_completos, Observaciones, Aprobado_por
    ) VALUES (
        p_id_estudiante, v_id_anio_academico, NOW(), NOW(),
        'Aprobada', p_tipo_inscripcion, p_colegio_procedencia, p_motivo_traslado,
        0, p_observaciones, p_usuario_registra
    );
    SET p_id_inscripcion = LAST_INSERT_ID();

    SET p_numero_matricula = CONCAT(
        'MAT-', v_anio_actual, '-',
        LPAD((SELECT COUNT(*) + 1 FROM matricula WHERE ID_Anio_Academico = v_id_anio_academico), 3, '0')
    );

    WHILE EXISTS (SELECT 1 FROM matricula WHERE Numero_matricula = p_numero_matricula) DO
        SET p_numero_matricula = CONCAT(
            'MAT-', v_anio_actual, '-',
            LPAD(
                (SELECT COUNT(*) + 1 FROM matricula
                 WHERE Numero_matricula LIKE CONCAT('MAT-', v_anio_actual, '-%')),
                3, '0'
            )
        );
    END WHILE;

    INSERT INTO matricula (
        ID_Inscripcion, ID_Estudiante, ID_Grado, ID_Anio_Academico,
        Numero_matricula, Monto_matricula, Descuento,
        Estado_pago, Estado_matricula, Tipo_estudiante,
        Requiere_apoyo, Observaciones
    ) VALUES (
        p_id_inscripcion, p_id_estudiante, p_id_grado, v_id_anio_academico,
        p_numero_matricula, IFNULL(p_monto_matricula, 0.00), IFNULL(p_descuento_matricula, 0.00),
        'Pendiente', 'Activa', IFNULL(p_tipo_estudiante, 'Regular'),
        IFNULL(p_requiere_apoyo, 0), p_observaciones
    );
    SET p_id_matricula = LAST_INSERT_ID();

    UPDATE grado SET Capacidad_actual = Capacidad_actual + 1 WHERE id = p_id_grado;

    -- ══════════════════════════════════════════════════════════
    -- BLOQUE B — PADRE / TUTOR 1 (obligatorio)
    -- ══════════════════════════════════════════════════════════

    INSERT INTO persona (
        Nombre, Apellido, CI, Fecha_nacimiento, Genero,
        Direccion, Telefono, Email_personal, Nacionalidad, Estado_civil
    ) VALUES (
        p1_nombre, p1_apellido, p1_ci, p1_fecha_nacimiento, p1_genero_persona,
        p1_direccion, p1_telefono, p1_email_personal,
        IFNULL(p1_nacionalidad, 'Boliviana'), p1_estado_civil
    );
    SET v_p1_id_persona = LAST_INSERT_ID();

    SET v_p1_token = CONCAT(MD5(CONCAT(p1_correo, NOW(), RAND())), '-', UNIX_TIMESTAMP());

    INSERT INTO verificacion (Tipo, Token, Estado, Fecha_expiracion)
    VALUES ('Email', v_p1_token, 'Pendiente', DATE_ADD(NOW(), INTERVAL 48 HOUR));
    SET v_p1_id_verif = LAST_INSERT_ID();

    INSERT INTO users (ID_Persona, ID_Verificacion, ID_Rol, Correo, Password, Estado)
    VALUES (v_p1_id_persona, v_p1_id_verif, 4, p1_correo, p1_password, 'Activo');
    SET v_p1_id_user = LAST_INSERT_ID();

    INSERT INTO padre_tutor (
        ID_User, Genero, Ocupacion, Lugar_trabajo,
        Telefono_trabajo, Nivel_educativo, Ingreso_mensual_aproximado, Estado
    ) VALUES (
        v_p1_id_user, p1_genero_padre, p1_ocupacion, p1_lugar_trabajo,
        p1_telefono_trabajo, p1_nivel_educativo, p1_ingreso_mensual, 'Activo'
    );
    SET p_id_padre1 = LAST_INSERT_ID();

    INSERT INTO estudiante_tutor (
        ID_Estudiante, ID_Padre, Parentesco,
        Es_responsable_economicamente, Es_contacto_emergencia,
        Puede_retirar, Vive_con_estudiante, Prioridad_contacto
    ) VALUES (
        p_id_estudiante, p_id_padre1, p1_parentesco,
        IFNULL(p1_es_responsable_economico, 1),
        IFNULL(p1_es_contacto_emergencia, 1),
        IFNULL(p1_puede_retirar, 1),
        IFNULL(p1_vive_con_estudiante, 1),
        1
    );

    -- ══════════════════════════════════════════════════════════
    -- BLOQUE C — PADRE / TUTOR 2 (opcional)
    -- ══════════════════════════════════════════════════════════

    IF p2_nombre IS NOT NULL THEN

        INSERT INTO persona (
            Nombre, Apellido, CI, Fecha_nacimiento, Genero,
            Direccion, Telefono, Email_personal, Nacionalidad, Estado_civil
        ) VALUES (
            p2_nombre, p2_apellido, p2_ci, p2_fecha_nacimiento, p2_genero_persona,
            p2_direccion, p2_telefono, p2_email_personal,
            IFNULL(p2_nacionalidad, 'Boliviana'), p2_estado_civil
        );
        SET v_p2_id_persona = LAST_INSERT_ID();

        SET v_p2_token = CONCAT(MD5(CONCAT(p2_correo, NOW(), RAND())), '-', UNIX_TIMESTAMP());

        INSERT INTO verificacion (Tipo, Token, Estado, Fecha_expiracion)
        VALUES ('Email', v_p2_token, 'Pendiente', DATE_ADD(NOW(), INTERVAL 48 HOUR));
        SET v_p2_id_verif = LAST_INSERT_ID();

        INSERT INTO users (ID_Persona, ID_Verificacion, ID_Rol, Correo, Password, Estado)
        VALUES (v_p2_id_persona, v_p2_id_verif, 4, p2_correo, p2_password, 'Activo');
        SET v_p2_id_user = LAST_INSERT_ID();

        INSERT INTO padre_tutor (
            ID_User, Genero, Ocupacion, Lugar_trabajo,
            Telefono_trabajo, Nivel_educativo, Ingreso_mensual_aproximado, Estado
        ) VALUES (
            v_p2_id_user, p2_genero_padre, p2_ocupacion, p2_lugar_trabajo,
            p2_telefono_trabajo, p2_nivel_educativo, p2_ingreso_mensual, 'Activo'
        );
        SET p_id_padre2 = LAST_INSERT_ID();

        INSERT INTO estudiante_tutor (
            ID_Estudiante, ID_Padre, Parentesco,
            Es_responsable_economicamente, Es_contacto_emergencia,
            Puede_retirar, Vive_con_estudiante, Prioridad_contacto
        ) VALUES (
            p_id_estudiante, p_id_padre2, p2_parentesco,
            IFNULL(p2_es_responsable_economico, 1),
            IFNULL(p2_es_contacto_emergencia, 1),
            IFNULL(p2_puede_retirar, 1),
            IFNULL(p2_vive_con_estudiante, 1),
            2
        );

    ELSE
        SET p_id_padre2 = NULL;
    END IF;

    -- ══════════════════════════════════════════════════════════
    -- BLOQUE D — AUDITORÍA GLOBAL
    -- ══════════════════════════════════════════════════════════

    INSERT INTO auditoria (
        ID_User, Accion, Tabla_afectada,
        ID_Registro_afectado, Datos_nuevos
    ) VALUES (
        p_usuario_registra,
        'INSERT',
        'inscripcion',
        p_id_inscripcion,
        JSON_OBJECT(
            'id_persona',        p_id_persona,
            'id_user',           p_id_user,
            'id_estudiante',     p_id_estudiante,
            'codigo_estudiante', p_codigo_estudiante,
            'id_inscripcion',    p_id_inscripcion,
            'id_matricula',      p_id_matricula,
            'numero_matricula',  p_numero_matricula,
            'id_grado',          p_id_grado,
            'tipo_inscripcion',  p_tipo_inscripcion,
            'anio_academico',    v_anio_actual,
            'id_padre1',         p_id_padre1,
            'id_padre2',         p_id_padre2,
            'registrado_por',    p_usuario_registra,
            'fecha',             NOW()
        )
    );

    COMMIT;

    SET p_mensaje = CONCAT(
        'Inscripción completada. ',
        'Estudiante: ', p_codigo_estudiante, ' | ',
        'Matrícula: ',  p_numero_matricula,  ' | ',
        'Tutores registrados: ', IF(p_id_padre2 IS NULL, '1', '2')
    );

-- ▼▼▼ CAMBIO: cierre con la misma etiqueta ▼▼▼
END proc$$

CREATE DEFINER=`root`@`localhost` PROCEDURE `sp_login` (IN `p_correo` VARCHAR(255), IN `p_password` VARCHAR(255), IN `p_ip` VARCHAR(45), IN `p_user_agent` VARCHAR(255), OUT `p_id_user` BIGINT, OUT `p_id_rol` BIGINT, OUT `p_nombre_rol` VARCHAR(50), OUT `p_nombre_completo` VARCHAR(511), OUT `p_requiere_2fa` TINYINT(1), OUT `p_mensaje` VARCHAR(500))   proc: BEGIN

    DECLARE v_password_bd   VARCHAR(255);
    DECLARE v_estado        VARCHAR(20);
    DECLARE v_intentos      INT DEFAULT 0;
    DECLARE v_id_persona    BIGINT;
    DECLARE v_nivel_acceso  INT DEFAULT 1;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SET p_id_user      = NULL;
        SET p_id_rol       = NULL;
        SET p_nombre_rol   = NULL;
        SET p_nombre_completo = NULL;
        SET p_requiere_2fa = 0;
        SET p_mensaje = 'Error: Fallo en el sistema de autenticación.';
    END;

    START TRANSACTION;

    -- ── 1. Validar campos obligatorios ───────────────────────────
    IF p_correo IS NULL OR TRIM(p_correo) = '' OR
       p_password IS NULL OR TRIM(p_password) = '' THEN
        ROLLBACK;
        SET p_mensaje = 'Error: Correo y contraseña son obligatorios.';
        LEAVE proc;
    END IF;

    -- ── 2. Buscar usuario por correo ─────────────────────────────
    SELECT
        u.id,
        u.Password,
        u.Estado,
        u.Intentos_fallidos,
        u.ID_Persona,
        u.ID_Rol
    INTO
        p_id_user,
        v_password_bd,
        v_estado,
        v_intentos,
        v_id_persona,
        p_id_rol
    FROM users u
    WHERE u.Correo = TRIM(p_correo)
    LIMIT 1;

    -- ── 3. Usuario no encontrado ─────────────────────────────────
    IF p_id_user IS NULL THEN
        INSERT INTO auditoria_usuarios (ID_User, Accion, IP_Address, User_Agent, Detalles)
        VALUES (
            0, 'INTENTO_FALLIDO', p_ip, p_user_agent,
            JSON_OBJECT('correo_intentado', p_correo, 'motivo', 'usuario_no_existe')
        );
        COMMIT;
        SET p_id_user    = NULL;
        SET p_requiere_2fa = 0;
        SET p_mensaje    = 'Error: Credenciales incorrectas.';
        LEAVE proc;
    END IF;

    -- ── 4. Cuenta bloqueada ──────────────────────────────────────
    IF v_estado = 'Bloqueado' THEN
        INSERT INTO auditoria_usuarios (ID_User, Accion, IP_Address, User_Agent, Detalles)
        VALUES (
            p_id_user, 'INTENTO_FALLIDO', p_ip, p_user_agent,
            JSON_OBJECT('motivo', 'cuenta_bloqueada')
        );
        COMMIT;
        SET p_id_user    = NULL;
        SET p_requiere_2fa = 0;
        SET p_mensaje    = 'Error: Cuenta bloqueada. Contacte al administrador.';
        LEAVE proc;
    END IF;

    -- ── 5. Cuenta inactiva / suspendida ──────────────────────────
    IF v_estado NOT IN ('Activo') THEN
        COMMIT;
        SET p_id_user    = NULL;
        SET p_requiere_2fa = 0;
        SET p_mensaje    = CONCAT('Error: Su cuenta se encuentra en estado "', v_estado, '".');
        LEAVE proc;
    END IF;

    -- ── 6. Contraseña incorrecta ─────────────────────────────────
    IF v_password_bd != p_password THEN
        UPDATE users
        SET Intentos_fallidos = Intentos_fallidos + 1
        WHERE id = p_id_user;

        -- Bloquear si llega a 5 intentos
        IF v_intentos + 1 >= 5 THEN
            UPDATE users SET Estado = 'Bloqueado' WHERE id = p_id_user;

            INSERT INTO auditoria_usuarios (ID_User, Accion, IP_Address, User_Agent, Detalles)
            VALUES (
                p_id_user, 'BLOQUEO', p_ip, p_user_agent,
                JSON_OBJECT('motivo', 'maximos_intentos_fallidos', 'intentos', v_intentos + 1)
            );
            COMMIT;
            SET p_id_user    = NULL;
            SET p_requiere_2fa = 0;
            SET p_mensaje    = 'Error: Cuenta bloqueada por múltiples intentos fallidos. Contacte al administrador.';
            LEAVE proc;
        END IF;

        INSERT INTO auditoria_usuarios (ID_User, Accion, IP_Address, User_Agent, Detalles)
        VALUES (
            p_id_user, 'INTENTO_FALLIDO', p_ip, p_user_agent,
            JSON_OBJECT(
                'motivo',              'password_incorrecto',
                'intentos_acumulados', v_intentos + 1,
                'intentos_restantes',  4 - v_intentos
            )
        );
        COMMIT;
        SET p_id_user    = NULL;
        SET p_requiere_2fa = 0;
        SET p_mensaje    = CONCAT(
            'Error: Credenciales incorrectas. Intentos restantes: ', (4 - v_intentos), '.'
        );
        LEAVE proc;
    END IF;

    -- ── 7. Login correcto ────────────────────────────────────────
    UPDATE users
    SET Intentos_fallidos = 0,
        Ultimo_acceso     = NOW()
    WHERE id = p_id_user;

    -- Obtener nombre completo y rol
    SELECT
        CONCAT(p.Nombre, ' ', p.Apellido),
        r.Nombre,
        r.Nivel_acceso
    INTO
        p_nombre_completo,
        p_nombre_rol,
        v_nivel_acceso
    FROM persona p
    JOIN users   u ON u.ID_Persona = p.id
    JOIN roles   r ON u.ID_Rol     = r.id
    WHERE u.id = p_id_user;

    -- Roles con nivel_acceso >= 3 requieren 2FA (Docente, Admin, Director, Secretaria)
    SET p_requiere_2fa = IF(v_nivel_acceso >= 3, 1, 0);

    INSERT INTO auditoria_usuarios (ID_User, Accion, IP_Address, User_Agent, Detalles)
    VALUES (
        p_id_user, 'LOGIN', p_ip, p_user_agent,
        JSON_OBJECT(
            'accion',       'LOGIN_PASO_1_OK',
            'requiere_2fa', p_requiere_2fa,
            'rol',          p_nombre_rol
        )
    );

    COMMIT;

    SET p_mensaje = IF(
        p_requiere_2fa = 1,
        'Credenciales correctas. Se requiere verificación en dos pasos.',
        'Login exitoso.'
    );

END proc$$

CREATE DEFINER=`root`@`localhost` PROCEDURE `sp_obtener_anotaciones_por_estudiante` (IN `p_nombre` VARCHAR(255), IN `p_apellido` VARCHAR(255))   BEGIN
    SELECT
        rd.id                               AS id_reporte,
        CONCAT(pe.Nombre, ' ', pe.Apellido) AS estudiante,
        e.Codigo_estudiante                 AS codigo_estudiante,
        g.Nombre                            AS grado,
        rd.Fecha_incidente                  AS fecha_incidente,
        rd.Tipo_falta                       AS tipo_falta,
        rd.Categoria                        AS categoria,
        rd.Descripcion                      AS descripcion,
        rd.Sancion                          AS sancion,
        rd.Estado                           AS estado,
        CONCAT(pr.Nombre, ' ', pr.Apellido) AS reportado_por,
        rd.Creado_en                        AS fecha_registro
    FROM   reportes_disciplinarios rd
    INNER JOIN estudiante e  ON rd.ID_Estudiante    = e.id
    INNER JOIN users      ue ON e.ID_User           = ue.id
    INNER JOIN persona    pe ON ue.ID_Persona       = pe.id
    INNER JOIN users      ur ON rd.ID_Reportado_por = ur.id
    INNER JOIN persona    pr ON ur.ID_Persona       = pr.id
    LEFT JOIN matricula  m  ON e.id = m.ID_Estudiante
                             AND m.Estado_matricula = 'Activa'
    LEFT JOIN grado      g  ON m.ID_Grado = g.id
    WHERE  pe.Nombre   LIKE CONCAT('%', TRIM(p_nombre),   '%')
      AND  pe.Apellido LIKE CONCAT('%', TRIM(p_apellido), '%')
    ORDER BY rd.Creado_en DESC;
END$$

CREATE DEFINER=`root`@`localhost` PROCEDURE `sp_recuperar_calificacion` (IN `p_id_auditoria` BIGINT, IN `p_usuario_recupera` BIGINT, OUT `p_id_calificacion_nueva` BIGINT, OUT `p_mensaje` VARCHAR(500))   BEGIN
    DECLARE v_id_estudiante BIGINT;
    DECLARE v_id_materia BIGINT;
    DECLARE v_id_periodo BIGINT;
    DECLARE v_id_docente BIGINT;
    DECLARE v_nota DECIMAL(5,2);
    DECLARE v_estado VARCHAR(50);
    
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SET p_mensaje = 'Error: No se pudo recuperar la calificación.';
        SET p_id_calificacion_nueva = NULL;
    END;
    
    START TRANSACTION;
    
    -- Obtener datos de la auditoría
    SELECT ID_Estudiante, ID_Materia, ID_Periodo, ID_Docente, Nota_anterior, Estado_anterior
    INTO v_id_estudiante, v_id_materia, v_id_periodo, v_id_docente, v_nota, v_estado
    FROM auditoria_calificaciones
    WHERE id = p_id_auditoria AND Accion = 'DELETE';
    
    IF v_id_estudiante IS NULL THEN
        ROLLBACK;
        SET p_mensaje = 'Error: No se encontró el registro de auditoría o no es una eliminación.';
        SET p_id_calificacion_nueva = NULL;
    ELSE
        -- Insertar la calificación recuperada
        INSERT INTO calificaciones (
            ID_Estudiante, ID_Materia, ID_Periodo, ID_Docente,
            Nota, Estado, Observaciones
        ) VALUES (
            v_id_estudiante, v_id_materia, v_id_periodo, v_id_docente,
            v_nota, 'Borrador', CONCAT('Recuperada desde auditoría ID: ', p_id_auditoria)
        );
        
        SET p_id_calificacion_nueva = LAST_INSERT_ID();
        
        -- Registrar la recuperación
        INSERT INTO auditoria (ID_User, Accion, Tabla_afectada, ID_Registro_afectado, Datos_nuevos)
        VALUES (
            p_usuario_recupera,
            'RECUPERACION',
            'calificaciones',
            p_id_calificacion_nueva,
            JSON_OBJECT('id_auditoria_origen', p_id_auditoria)
        );
        
        COMMIT;
        
        SET p_mensaje = CONCAT('Calificación recuperada exitosamente. Nueva ID: ', p_id_calificacion_nueva);
    END IF;
END$$

CREATE DEFINER=`root`@`localhost` PROCEDURE `sp_recuperar_pago` (IN `p_id_auditoria` BIGINT, IN `p_usuario_recupera` BIGINT, OUT `p_id_pago_nuevo` BIGINT, OUT `p_mensaje` VARCHAR(500))   BEGIN
    DECLARE v_id_estudiante BIGINT;
    DECLARE v_concepto VARCHAR(50);
    DECLARE v_monto DECIMAL(10,2);
    DECLARE v_estado VARCHAR(50);
    
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SET p_mensaje = 'Error: No se pudo recuperar el pago.';
        SET p_id_pago_nuevo = NULL;
    END;
    
    START TRANSACTION;
    
    -- Obtener datos de la auditoría
    SELECT ID_Estudiante, Concepto, Monto_anterior, Estado_anterior
    INTO v_id_estudiante, v_concepto, v_monto, v_estado
    FROM auditoria_pagos
    WHERE id = p_id_auditoria AND Accion = 'DELETE';
    
    IF v_id_estudiante IS NULL THEN
        ROLLBACK;
        SET p_mensaje = 'Error: No se encontró el registro de auditoría o no es una eliminación.';
        SET p_id_pago_nuevo = NULL;
    ELSE
        -- Insertar el pago recuperado
        INSERT INTO pagos (
            ID_Estudiante, ID_Anio_Academico, Concepto, Monto, Estado,
            Observaciones, Registrado_por
        ) VALUES (
            v_id_estudiante, 
            (SELECT id FROM anio_academico WHERE Es_actual = 1 LIMIT 1),
            v_concepto, v_monto, 'Pendiente',
            CONCAT('Recuperado desde auditoría ID: ', p_id_auditoria),
            p_usuario_recupera
        );
        
        SET p_id_pago_nuevo = LAST_INSERT_ID();
        
        COMMIT;
        
        SET p_mensaje = CONCAT('Pago recuperado exitosamente. Nueva ID: ', p_id_pago_nuevo);
    END IF;
END$$

CREATE DEFINER=`root`@`localhost` PROCEDURE `sp_registrar_anotacion_estudiante` (IN `p_nombre_estudiante` VARCHAR(255), IN `p_apellido_estudiante` VARCHAR(255), IN `p_nombre_reporta` VARCHAR(255), IN `p_apellido_reporta` VARCHAR(255), IN `p_fecha_incidente` DATE, IN `p_tipo_falta` ENUM('Leve','Moderada','Grave','Muy_grave'), IN `p_categoria` VARCHAR(100), IN `p_descripcion` TEXT, IN `p_sancion` TEXT, IN `p_fecha_sancion` DATE, IN `p_notificado_padres` TINYINT(1), IN `p_fecha_notificacion` DATE, IN `p_seguimiento` TEXT, OUT `p_id_reporte` BIGINT, OUT `p_codigo_estudiante` VARCHAR(50), OUT `p_nombre_completo_est` VARCHAR(511), OUT `p_nombre_completo_rep` VARCHAR(511), OUT `p_mensaje` VARCHAR(500))   proc: BEGIN

    DECLARE v_id_estudiante     BIGINT;
    DECLARE v_id_user_reporta   BIGINT;
    DECLARE v_count_est         INT DEFAULT 0;
    DECLARE v_count_rep         INT DEFAULT 0;

    -- ── Handler de errores ────────────────────────────────
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SET p_id_reporte          = NULL;
        SET p_codigo_estudiante   = NULL;
        SET p_nombre_completo_est = NULL;
        SET p_nombre_completo_rep = NULL;
        SET p_mensaje = 'Error: No se pudo registrar la anotación. Verifique los datos e intente nuevamente.';
    END;

    START TRANSACTION;

    -- ══════════════════════════════════════════════════════
    -- VALIDACIONES DE CAMPOS OBLIGATORIOS
    -- ══════════════════════════════════════════════════════

    IF p_nombre_estudiante IS NULL OR TRIM(p_nombre_estudiante) = '' OR
       p_apellido_estudiante IS NULL OR TRIM(p_apellido_estudiante) = '' THEN
        ROLLBACK;
        SET p_mensaje = 'Error: Debe proporcionar el nombre y apellido del estudiante.';
        LEAVE proc;
    END IF;

    IF p_nombre_reporta IS NULL OR TRIM(p_nombre_reporta) = '' OR
       p_apellido_reporta IS NULL OR TRIM(p_apellido_reporta) = '' THEN
        ROLLBACK;
        SET p_mensaje = 'Error: Debe proporcionar el nombre y apellido del docente/admin que reporta.';
        LEAVE proc;
    END IF;

    IF p_descripcion IS NULL OR TRIM(p_descripcion) = '' THEN
        ROLLBACK;
        SET p_mensaje = 'Error: La descripción del incidente es obligatoria.';
        LEAVE proc;
    END IF;

    IF p_tipo_falta IS NULL THEN
        ROLLBACK;
        SET p_mensaje = 'Error: El tipo de falta es obligatorio (Leve, Moderada, Grave, Muy_grave).';
        LEAVE proc;
    END IF;

    -- ══════════════════════════════════════════════════════
    -- BUSCAR ESTUDIANTE POR NOMBRE Y APELLIDO
    -- ══════════════════════════════════════════════════════

    SELECT COUNT(*)
    INTO   v_count_est
    FROM   estudiante e
    INNER JOIN users u    ON e.ID_User    = u.id
    INNER JOIN persona p  ON u.ID_Persona = p.id
    WHERE  p.Nombre  LIKE CONCAT('%', TRIM(p_nombre_estudiante),   '%')
      AND  p.Apellido LIKE CONCAT('%', TRIM(p_apellido_estudiante), '%')
      AND  e.Estado = 'Activo';

    IF v_count_est = 0 THEN
        ROLLBACK;
        SET p_mensaje = CONCAT(
            'Error: No se encontró ningún estudiante activo con el nombre "',
            p_nombre_estudiante, ' ', p_apellido_estudiante, '".'
        );
        LEAVE proc;
    END IF;

    IF v_count_est > 1 THEN
        ROLLBACK;
        SET p_mensaje = CONCAT(
            'Error: Se encontraron ', v_count_est,
            ' estudiantes con el nombre "', p_nombre_estudiante, ' ', p_apellido_estudiante,
            '". Use un nombre más específico.'
        );
        LEAVE proc;
    END IF;

    -- Obtener ID del estudiante y datos para la respuesta
    SELECT e.id,
           e.Codigo_estudiante,
           CONCAT(p.Nombre, ' ', p.Apellido)
    INTO   v_id_estudiante,
           p_codigo_estudiante,
           p_nombre_completo_est
    FROM   estudiante e
    INNER JOIN users u   ON e.ID_User    = u.id
    INNER JOIN persona p ON u.ID_Persona = p.id
    WHERE  p.Nombre  LIKE CONCAT('%', TRIM(p_nombre_estudiante),   '%')
      AND  p.Apellido LIKE CONCAT('%', TRIM(p_apellido_estudiante), '%')
      AND  e.Estado = 'Activo'
    LIMIT 1;

    -- ══════════════════════════════════════════════════════
    -- BUSCAR USUARIO QUE REPORTA (docente o admin)
    -- ══════════════════════════════════════════════════════

    -- Buscar en docentes activos
    SELECT COUNT(*)
    INTO   v_count_rep
    FROM   users u
    INNER JOIN persona p ON u.ID_Persona = p.id
    WHERE  p.Nombre  LIKE CONCAT('%', TRIM(p_nombre_reporta),   '%')
      AND  p.Apellido LIKE CONCAT('%', TRIM(p_apellido_reporta), '%')
      AND  u.Estado = 'Activo'
      AND  u.ID_Rol IN (
               SELECT id FROM roles
               WHERE Nombre IN ('Docente','Administrador','Director','Secretaria')
           );

    IF v_count_rep = 0 THEN
        ROLLBACK;
        SET p_mensaje = CONCAT(
            'Error: No se encontró ningún docente o administrativo activo con el nombre "',
            p_nombre_reporta, ' ', p_apellido_reporta, '".'
        );
        LEAVE proc;
    END IF;

    IF v_count_rep > 1 THEN
        ROLLBACK;
        SET p_mensaje = CONCAT(
            'Error: Se encontraron ', v_count_rep,
            ' usuarios con el nombre "', p_nombre_reporta, ' ', p_apellido_reporta,
            '". Use un nombre más específico.'
        );
        LEAVE proc;
    END IF;

    -- Obtener ID del usuario que reporta
    SELECT u.id,
           CONCAT(p.Nombre, ' ', p.Apellido)
    INTO   v_id_user_reporta,
           p_nombre_completo_rep
    FROM   users u
    INNER JOIN persona p ON u.ID_Persona = p.id
    WHERE  p.Nombre  LIKE CONCAT('%', TRIM(p_nombre_reporta),   '%')
      AND  p.Apellido LIKE CONCAT('%', TRIM(p_apellido_reporta), '%')
      AND  u.Estado = 'Activo'
      AND  u.ID_Rol IN (
               SELECT id FROM roles
               WHERE Nombre IN ('Docente','Administrador','Director','Secretaria')
           )
    LIMIT 1;

    -- ══════════════════════════════════════════════════════
    -- REGISTRAR LA ANOTACIÓN
    -- ══════════════════════════════════════════════════════

    INSERT INTO reportes_disciplinarios (
        ID_Estudiante,
        ID_Reportado_por,
        Fecha_incidente,
        Tipo_falta,
        Categoria,
        Descripcion,
        Sancion,
        Fecha_sancion,
        Notificado_padres,
        Fecha_notificacion,
        Estado,
        Seguimiento
    ) VALUES (
        v_id_estudiante,
        v_id_user_reporta,
        IFNULL(p_fecha_incidente, CURDATE()),
        p_tipo_falta,
        p_categoria,
        p_descripcion,
        p_sancion,
        p_fecha_sancion,
        IFNULL(p_notificado_padres, 0),
        p_fecha_notificacion,
        'Abierto',
        p_seguimiento
    );

    SET p_id_reporte = LAST_INSERT_ID();

    -- ══════════════════════════════════════════════════════
    -- REGISTRAR EN AUDITORÍA
    -- ══════════════════════════════════════════════════════

    INSERT INTO auditoria (
        ID_User,
        Accion,
        Tabla_afectada,
        ID_Registro_afectado,
        Datos_nuevos
    ) VALUES (
        v_id_user_reporta,
        'INSERT',
        'reportes_disciplinarios',
        p_id_reporte,
        JSON_OBJECT(
            'id_reporte',       p_id_reporte,
            'id_estudiante',    v_id_estudiante,
            'codigo_estudiante', p_codigo_estudiante,
            'estudiante',       p_nombre_completo_est,
            'reportado_por',    p_nombre_completo_rep,
            'tipo_falta',       p_tipo_falta,
            'categoria',        p_categoria,
            'fecha_incidente',  IFNULL(p_fecha_incidente, CURDATE()),
            'fecha_registro',   NOW()
        )
    );

    COMMIT;

    SET p_mensaje = CONCAT(
        'Anotación registrada exitosamente. ',
        'Reporte #', p_id_reporte, ' | ',
        'Estudiante: ', p_nombre_completo_est, ' (', p_codigo_estudiante, ') | ',
        'Reportado por: ', p_nombre_completo_rep, ' | ',
        'Falta: ', p_tipo_falta
    );

END proc$$

CREATE DEFINER=`` PROCEDURE `sp_registrar_buena_conducta` (IN `p_nombre_estudiante` VARCHAR(255), IN `p_apellido_estudiante` VARCHAR(255), IN `p_nombre_reporta` VARCHAR(255), IN `p_apellido_reporta` VARCHAR(255), IN `p_fecha_conducta` DATE, IN `p_tipo_reconocimiento` VARCHAR(100), IN `p_categoria` VARCHAR(100), IN `p_descripcion` TEXT, IN `p_acciones_tomadas` TEXT, IN `p_fecha_accion` DATE, IN `p_notificado_padres` TINYINT(1), IN `p_fecha_notificacion` DATE, IN `p_puntos` INT, IN `p_seguimiento` TEXT, OUT `p_id_reporte` BIGINT, OUT `p_codigo_estudiante` VARCHAR(50), OUT `p_nombre_completo_est` VARCHAR(511), OUT `p_nombre_completo_rep` VARCHAR(511), OUT `p_mensaje` VARCHAR(500))   proc: BEGIN

    DECLARE v_id_estudiante   BIGINT;
    DECLARE v_id_user_reporta BIGINT;
    DECLARE v_count_est       INT DEFAULT 0;
    DECLARE v_count_rep       INT DEFAULT 0;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SET p_id_reporte          = NULL;
        SET p_codigo_estudiante   = NULL;
        SET p_nombre_completo_est = NULL;
        SET p_nombre_completo_rep = NULL;
        SET p_mensaje = 'Error: No se pudo registrar el reconocimiento de conducta.';
    END;

    START TRANSACTION;

    -- Validaciones básicas
    IF p_nombre_estudiante IS NULL OR TRIM(p_nombre_estudiante) = '' OR
       p_apellido_estudiante IS NULL OR TRIM(p_apellido_estudiante) = '' THEN
        ROLLBACK;
        SET p_mensaje = 'Error: Nombre y apellido del estudiante son obligatorios.';
        LEAVE proc;
    END IF;

    IF p_descripcion IS NULL OR TRIM(p_descripcion) = '' THEN
        ROLLBACK;
        SET p_mensaje = 'Error: La descripción del reconocimiento es obligatoria.';
        LEAVE proc;
    END IF;

    -- Buscar estudiante
    SELECT COUNT(*) INTO v_count_est
    FROM estudiante e
    INNER JOIN users u   ON e.ID_User    = u.id
    INNER JOIN persona p ON u.ID_Persona = p.id
    WHERE p.Nombre   LIKE CONCAT('%', TRIM(p_nombre_estudiante),   '%')
      AND p.Apellido LIKE CONCAT('%', TRIM(p_apellido_estudiante), '%')
      AND e.Estado = 'Activo';

    IF v_count_est = 0 THEN
        ROLLBACK;
        SET p_mensaje = CONCAT('Error: No se encontró estudiante activo con el nombre "',
                               p_nombre_estudiante, ' ', p_apellido_estudiante, '".');
        LEAVE proc;
    END IF;

    IF v_count_est > 1 THEN
        ROLLBACK;
        SET p_mensaje = CONCAT('Error: Se encontraron ', v_count_est,
                               ' estudiantes. Use un nombre más específico.');
        LEAVE proc;
    END IF;

    SELECT e.id, e.Codigo_estudiante, CONCAT(p.Nombre, ' ', p.Apellido)
    INTO   v_id_estudiante, p_codigo_estudiante, p_nombre_completo_est
    FROM estudiante e
    INNER JOIN users u   ON e.ID_User    = u.id
    INNER JOIN persona p ON u.ID_Persona = p.id
    WHERE p.Nombre   LIKE CONCAT('%', TRIM(p_nombre_estudiante),   '%')
      AND p.Apellido LIKE CONCAT('%', TRIM(p_apellido_estudiante), '%')
      AND e.Estado = 'Activo'
    LIMIT 1;

    -- Buscar usuario que reporta (docente o admin)
    SELECT COUNT(*) INTO v_count_rep
    FROM users u
    INNER JOIN persona p ON u.ID_Persona = p.id
    WHERE p.Nombre   LIKE CONCAT('%', TRIM(p_nombre_reporta),   '%')
      AND p.Apellido LIKE CONCAT('%', TRIM(p_apellido_reporta), '%')
      AND u.Estado = 'Activo'
      AND u.ID_Rol IN (
          SELECT id FROM roles
          WHERE Nombre IN ('Docente','Administrador','Director','Secretaria')
      );

    IF v_count_rep = 0 THEN
        ROLLBACK;
        SET p_mensaje = CONCAT('Error: No se encontró docente/admin activo con el nombre "',
                               p_nombre_reporta, ' ', p_apellido_reporta, '".');
        LEAVE proc;
    END IF;

    IF v_count_rep > 1 THEN
        ROLLBACK;
        SET p_mensaje = CONCAT('Error: Se encontraron ', v_count_rep,
                               ' usuarios. Use un nombre más específico.');
        LEAVE proc;
    END IF;

    SELECT u.id, CONCAT(p.Nombre, ' ', p.Apellido)
    INTO   v_id_user_reporta, p_nombre_completo_rep
    FROM users u
    INNER JOIN persona p ON u.ID_Persona = p.id
    WHERE p.Nombre   LIKE CONCAT('%', TRIM(p_nombre_reporta),   '%')
      AND p.Apellido LIKE CONCAT('%', TRIM(p_apellido_reporta), '%')
      AND u.Estado = 'Activo'
      AND u.ID_Rol IN (
          SELECT id FROM roles
          WHERE Nombre IN ('Docente','Administrador','Director','Secretaria')
      )
    LIMIT 1;

    -- Insertar reconocimiento
    INSERT INTO reportes_buena_conducta (
        ID_Estudiante, ID_Reportado_por, Fecha_conducta,
        Tipo_reconocimiento, Categoria, Descripcion,
        Acciones_tomadas, Fecha_accion,
        Notificado_padres, Fecha_notificacion,
        Estado, Puntos, Seguimiento
    ) VALUES (
        v_id_estudiante, v_id_user_reporta,
        IFNULL(p_fecha_conducta, CURDATE()),
        p_tipo_reconocimiento, p_categoria, p_descripcion,
        p_acciones_tomadas, p_fecha_accion,
        IFNULL(p_notificado_padres, 0), p_fecha_notificacion,
        'Registrado', IFNULL(p_puntos, 0), p_seguimiento
    );

    SET p_id_reporte = LAST_INSERT_ID();

    COMMIT;

    SET p_mensaje = CONCAT(
        'Reconocimiento registrado. Reporte #', p_id_reporte,
        ' | Estudiante: ', p_nombre_completo_est, ' (', p_codigo_estudiante, ')',
        ' | Tipo: ', p_tipo_reconocimiento,
        ' | Registrado por: ', p_nombre_completo_rep
    );
END proc$$

CREATE DEFINER=`` PROCEDURE `sp_registrar_curso` (IN `p_id_asignacion` BIGINT, IN `p_id_periodo` BIGINT, IN `p_titulo` VARCHAR(255), IN `p_descripcion` TEXT, IN `p_tema` VARCHAR(255), IN `p_fecha_programada` DATE, IN `p_hora_inicio` TIME, IN `p_hora_fin` TIME, IN `p_aula` VARCHAR(100), IN `p_tipo` VARCHAR(50), IN `p_modalidad` VARCHAR(50), IN `p_recursos` TEXT, IN `p_objetivos` TEXT, IN `p_observaciones` TEXT, IN `p_registrado_por` BIGINT, OUT `p_id_curso` BIGINT, OUT `p_mensaje` VARCHAR(500))   proc: BEGIN

    DECLARE v_id_anio    BIGINT;
    DECLARE v_count_asig INT DEFAULT 0;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SET p_id_curso = NULL;
        SET p_mensaje  = 'Error: No se pudo registrar el curso.';
    END;

    START TRANSACTION;

    -- Validaciones
    IF p_titulo IS NULL OR TRIM(p_titulo) = '' THEN
        ROLLBACK;
        SET p_mensaje = 'Error: El título del curso es obligatorio.';
        LEAVE proc;
    END IF;

    SELECT COUNT(*) INTO v_count_asig
    FROM asignacion_docente
    WHERE id = p_id_asignacion AND Estado = 'Activo';

    IF v_count_asig = 0 THEN
        ROLLBACK;
        SET p_mensaje = 'Error: La asignación docente no existe o no está activa.';
        LEAVE proc;
    END IF;

    -- Obtener año académico desde el período
    SELECT ID_Anio_Academico INTO v_id_anio
    FROM periodo WHERE id = p_id_periodo LIMIT 1;

    IF v_id_anio IS NULL THEN
        ROLLBACK;
        SET p_mensaje = 'Error: El período indicado no existe.';
        LEAVE proc;
    END IF;

    INSERT INTO cursos (
        ID_Asignacion, ID_Periodo, ID_Anio_Academico,
        Titulo, Descripcion, Tema,
        Fecha_programada, Hora_inicio, Hora_fin, Aula,
        Tipo, Modalidad, Recursos, Objetivos, Observaciones,
        Registrado_por, Estado
    ) VALUES (
        p_id_asignacion, p_id_periodo, v_id_anio,
        TRIM(p_titulo), p_descripcion, p_tema,
        p_fecha_programada, p_hora_inicio, p_hora_fin, p_aula,
        IFNULL(p_tipo, 'Teorica'), IFNULL(p_modalidad, 'Presencial'),
        p_recursos, p_objetivos, p_observaciones,
        p_registrado_por, 'Programado'
    );

    SET p_id_curso = LAST_INSERT_ID();

    COMMIT;

    SET p_mensaje = CONCAT('Curso registrado exitosamente. ID: ', p_id_curso,
                           ' | Título: ', p_titulo,
                           ' | Fecha: ', IFNULL(DATE_FORMAT(p_fecha_programada, '%d/%m/%Y'), 'Sin fecha'));
END proc$$

CREATE DEFINER=`root`@`localhost` PROCEDURE `sp_registrar_login` (IN `p_correo` VARCHAR(255), IN `p_password` VARCHAR(255), IN `p_ip` VARCHAR(45), IN `p_user_agent` VARCHAR(255), OUT `p_id_user` BIGINT, OUT `p_id_rol` BIGINT, OUT `p_nombre_completo` VARCHAR(511), OUT `p_mensaje` VARCHAR(500))   BEGIN
    DECLARE v_password_bd VARCHAR(255);
    DECLARE v_estado VARCHAR(50);
    DECLARE v_intentos INT;
    DECLARE v_id_persona BIGINT;
    
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SET p_mensaje = 'Error en el sistema de autenticación.';
        SET p_id_user = NULL;
    END;
    
    START TRANSACTION;
    
    -- Buscar usuario
    SELECT id, Password, Estado, Intentos_fallidos, ID_Persona, ID_Rol
    INTO p_id_user, v_password_bd, v_estado, v_intentos, v_id_persona, p_id_rol
    FROM users
    WHERE Correo = p_correo;
    
    IF p_id_user IS NULL THEN
        -- Usuario no existe
        SET p_mensaje = 'Credenciales incorrectas.';
        SET p_id_user = NULL;
        ROLLBACK;
    ELSEIF v_estado = 'Bloqueado' THEN
        -- Usuario bloqueado
        INSERT INTO auditoria_usuarios (ID_User, Accion, IP_Address, User_Agent)
        VALUES (p_id_user, 'INTENTO_FALLIDO', p_ip, p_user_agent);
        
        SET p_mensaje = 'Usuario bloqueado. Contacte al administrador.';
        SET p_id_user = NULL;
        COMMIT;
    ELSEIF v_password_bd = p_password THEN
        -- Login exitoso
        UPDATE users SET 
            Ultimo_acceso = NOW(),
            Intentos_fallidos = 0
        WHERE id = p_id_user;
        
        INSERT INTO auditoria_usuarios (ID_User, Accion, IP_Address, User_Agent)
        VALUES (p_id_user, 'LOGIN', p_ip, p_user_agent);
        
        -- Obtener nombre completo
        SELECT CONCAT(Nombre, ' ', Apellido) INTO p_nombre_completo
        FROM persona WHERE id = v_id_persona;
        
        SET p_mensaje = 'Login exitoso.';
        COMMIT;
    ELSE
        -- Contraseña incorrecta
        UPDATE users SET Intentos_fallidos = Intentos_fallidos + 1 WHERE id = p_id_user;
        
        IF v_intentos + 1 >= 5 THEN
            UPDATE users SET Estado = 'Bloqueado' WHERE id = p_id_user;
            INSERT INTO auditoria_usuarios (ID_User, Accion, IP_Address, User_Agent)
            VALUES (p_id_user, 'BLOQUEO', p_ip, p_user_agent);
            SET p_mensaje = 'Usuario bloqueado por múltiples intentos fallidos.';
        ELSE
            INSERT INTO auditoria_usuarios (ID_User, Accion, IP_Address, User_Agent)
            VALUES (p_id_user, 'INTENTO_FALLIDO', p_ip, p_user_agent);
            SET p_mensaje = 'Credenciales incorrectas.';
        END IF;
        
        SET p_id_user = NULL;
        COMMIT;
    END IF;
END$$

CREATE DEFINER=`` PROCEDURE `sp_resumen_buena_conducta_grado` (IN `p_fecha_inicio` DATE, IN `p_fecha_fin` DATE)   BEGIN

    DECLARE v_fecha_inicio DATE;
    DECLARE v_fecha_fin    DATE;

    IF p_fecha_inicio IS NULL THEN
        SELECT Fecha_inicio INTO v_fecha_inicio
        FROM anio_academico WHERE Es_actual = 1 LIMIT 1;
    ELSE
        SET v_fecha_inicio = p_fecha_inicio;
    END IF;

    SET v_fecha_fin = IFNULL(p_fecha_fin, CURDATE());

    -- Por tipo de reconocimiento
    SELECT 'POR_TIPO' AS Seccion;
    SELECT
        rbc.Tipo_reconocimiento,
        COUNT(*)                                               AS Total,
        ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2)   AS Porcentaje
    FROM reportes_buena_conducta rbc
    WHERE rbc.Fecha_conducta BETWEEN v_fecha_inicio AND v_fecha_fin
    GROUP BY rbc.Tipo_reconocimiento
    ORDER BY Total DESC;

    -- Top 10 estudiantes con más reconocimientos
    SELECT 'TOP10_ESTUDIANTES' AS Seccion;
    SELECT
        e.Codigo_estudiante,
        CONCAT(p.Nombre, ' ', p.Apellido)                     AS Nombre_Estudiante,
        g.Nombre                                              AS Grado,
        COUNT(rbc.id)                                         AS Total_Reconocimientos,
        IFNULL(SUM(rbc.Puntos), 0)                            AS Total_Puntos
    FROM reportes_buena_conducta rbc
    JOIN estudiante  e  ON rbc.ID_Estudiante = e.id
    JOIN users       u  ON e.ID_User         = u.id
    JOIN persona     p  ON u.ID_Persona      = p.id
    LEFT JOIN matricula m ON e.id = m.ID_Estudiante AND m.Estado_matricula = 'Activa'
    LEFT JOIN grado   g  ON m.ID_Grado       = g.id
    WHERE rbc.Fecha_conducta BETWEEN v_fecha_inicio AND v_fecha_fin
    GROUP BY e.id, e.Codigo_estudiante, p.Nombre, p.Apellido, g.Nombre
    ORDER BY Total_Reconocimientos DESC
    LIMIT 10;

    -- Por grado
    SELECT 'POR_GRADO' AS Seccion;
    SELECT
        g.Nombre                                              AS Grado,
        g.Paralelo,
        COUNT(rbc.id)                                         AS Total_Reconocimientos,
        IFNULL(SUM(rbc.Puntos), 0)                            AS Total_Puntos
    FROM reportes_buena_conducta rbc
    JOIN estudiante  e  ON rbc.ID_Estudiante = e.id
    LEFT JOIN matricula m ON e.id = m.ID_Estudiante AND m.Estado_matricula = 'Activa'
    LEFT JOIN grado   g  ON m.ID_Grado       = g.id
    WHERE rbc.Fecha_conducta BETWEEN v_fecha_inicio AND v_fecha_fin
    GROUP BY g.id, g.Nombre, g.Paralelo
    ORDER BY Total_Reconocimientos DESC;

    -- Tendencia mensual
    SELECT 'TENDENCIA_MENSUAL' AS Seccion;
    SELECT
        YEAR(rbc.Fecha_conducta)                              AS Anio,
        MONTH(rbc.Fecha_conducta)                             AS Mes,
        MONTHNAME(rbc.Fecha_conducta)                         AS Nombre_Mes,
        COUNT(*)                                              AS Total
    FROM reportes_buena_conducta rbc
    WHERE rbc.Fecha_conducta BETWEEN v_fecha_inicio AND v_fecha_fin
    GROUP BY YEAR(rbc.Fecha_conducta), MONTH(rbc.Fecha_conducta)
    ORDER BY Anio, Mes;
END$$

CREATE DEFINER=`` PROCEDURE `sp_resumen_conducta_estudiante` (IN `p_id_estudiante` BIGINT, IN `p_id_anio_academico` BIGINT)   BEGIN

    DECLARE v_id_anio BIGINT;

    IF p_id_anio_academico IS NULL THEN
        SELECT id INTO v_id_anio FROM anio_academico WHERE Es_actual = 1 LIMIT 1;
    ELSE
        SET v_id_anio = p_id_anio_academico;
    END IF;

    -- Datos del estudiante
    SELECT 'DATOS_ESTUDIANTE' AS Seccion;
    SELECT Codigo_estudiante, Nombre_Completo, Grado_Actual, Paralelo
    FROM v_datos_completos_estudiante
    WHERE ID_Estudiante = p_id_estudiante;

    -- Reconocimientos de buena conducta
    SELECT 'RECONOCIMIENTOS' AS Seccion;
    SELECT
        rbc.id                                        AS ID_Reconocimiento,
        rbc.Fecha_conducta,
        rbc.Tipo_reconocimiento,
        rbc.Categoria,
        rbc.Descripcion,
        rbc.Acciones_tomadas,
        rbc.Puntos,
        rbc.Estado,
        CONCAT(pr.Nombre, ' ', pr.Apellido)           AS Reconocido_Por,
        rbc.Notificado_padres,
        rbc.Seguimiento,
        rbc.Creado_en
    FROM reportes_buena_conducta rbc
    JOIN users   ur ON rbc.ID_Reportado_por = ur.id
    JOIN persona pr ON ur.ID_Persona        = pr.id
    WHERE rbc.ID_Estudiante = p_id_estudiante
    ORDER BY rbc.Fecha_conducta DESC;

    -- Reportes disciplinarios (para comparar)
    SELECT 'REPORTES_DISCIPLINARIOS' AS Seccion;
    SELECT
        rd.id                                        AS ID_Reporte,
        rd.Fecha_incidente,
        rd.Tipo_falta,
        rd.Categoria,
        rd.Descripcion,
        rd.Estado
    FROM reportes_disciplinarios rd
    WHERE rd.ID_Estudiante = p_id_estudiante
    ORDER BY rd.Fecha_incidente DESC;

    -- Balance general de conducta
    SELECT 'BALANCE_CONDUCTA' AS Seccion;
    SELECT
        (SELECT COUNT(*) FROM reportes_buena_conducta
         WHERE ID_Estudiante = p_id_estudiante)                   AS Total_Reconocimientos,
        (SELECT IFNULL(SUM(Puntos), 0) FROM reportes_buena_conducta
         WHERE ID_Estudiante = p_id_estudiante)                   AS Total_Puntos_Positivos,
        (SELECT COUNT(*) FROM reportes_buena_conducta
         WHERE ID_Estudiante = p_id_estudiante
           AND Estado IN ('Registrado', 'En_proceso'))            AS Reconocimientos_Activos,
        (SELECT COUNT(*) FROM reportes_disciplinarios
         WHERE ID_Estudiante = p_id_estudiante)                   AS Total_Anotaciones,
        (SELECT COUNT(*) FROM reportes_disciplinarios
         WHERE ID_Estudiante = p_id_estudiante
           AND Estado IN ('Abierto', 'En_proceso'))               AS Anotaciones_Activas,
        (SELECT COUNT(*) FROM reportes_disciplinarios
         WHERE ID_Estudiante = p_id_estudiante
           AND Tipo_falta IN ('Grave', 'Muy_grave'))              AS Faltas_Graves;

END$$

CREATE DEFINER=`root`@`localhost` PROCEDURE `sp_verificar_codigo_2fa` (IN `p_id_user` BIGINT, IN `p_id_verificacion` BIGINT, IN `p_codigo` VARCHAR(6), IN `p_ip` VARCHAR(45), OUT `p_verificado` TINYINT(1), OUT `p_mensaje` VARCHAR(500))   proc: BEGIN

    DECLARE v_token          VARCHAR(255);
    DECLARE v_estado         VARCHAR(20);
    DECLARE v_expiracion     TIMESTAMP;
    DECLARE v_codigo_real    VARCHAR(6);
    DECLARE v_tipo           VARCHAR(20);
    DECLARE v_intentos_fail  INT DEFAULT 0;
    DECLARE v_max_intentos   INT DEFAULT 5;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SET p_verificado = 0;
        SET p_mensaje    = 'Error: No se pudo verificar el código.';
    END;

    START TRANSACTION;

    SET p_verificado = 0;

    -- ── 1. Obtener el registro de verificación ───────────────────
    SELECT v.Token, v.Estado, v.Fecha_expiracion, v.Tipo
    INTO   v_token, v_estado, v_expiracion, v_tipo
    FROM   verificacion v
    WHERE  v.id = p_id_verificacion;

    IF v_token IS NULL THEN
        ROLLBACK;
        SET p_mensaje = 'Error: Código de verificación no encontrado.';
        LEAVE proc;
    END IF;

    -- ── 2. Verificar que pertenece al usuario correcto ───────────
    IF NOT EXISTS (
        SELECT 1 FROM users
        WHERE id = p_id_user
          AND ID_Verificacion = p_id_verificacion
    ) THEN
        ROLLBACK;
        SET p_mensaje = 'Error: El código no corresponde a este usuario.';
        LEAVE proc;
    END IF;

    -- ── 3. Verificar estado ─────────────────────────────────────
    IF v_estado = 'Verificado' THEN
        ROLLBACK;
        SET p_mensaje = 'Error: Este código ya fue utilizado.';
        LEAVE proc;
    END IF;

    IF v_estado = 'Rechazado' THEN
        ROLLBACK;
        SET p_mensaje = 'Error: Este código fue bloqueado por intentos fallidos.';
        LEAVE proc;
    END IF;

    IF v_estado = 'Expirado' OR NOW() > v_expiracion THEN
        -- Marcar como expirado si aún no lo está
        UPDATE verificacion SET Estado = 'Expirado' WHERE id = p_id_verificacion;
        COMMIT;
        SET p_mensaje = 'Error: El código ha expirado. Solicite uno nuevo.';
        LEAVE proc;
    END IF;

    -- ── 4. Contar intentos fallidos recientes (últimos 15 min) ───
    SELECT COUNT(*)
    INTO   v_intentos_fail
    FROM   auditoria_usuarios
    WHERE  ID_User     = p_id_user
      AND  Accion      = 'INTENTO_FALLIDO'
      AND  Detalles    LIKE CONCAT('%"id_verificacion":', p_id_verificacion, '%')
      AND  Fecha_hora >= DATE_SUB(NOW(), INTERVAL 15 MINUTE);

    IF v_intentos_fail >= v_max_intentos THEN
        UPDATE verificacion SET Estado = 'Rechazado' WHERE id = p_id_verificacion;

        INSERT INTO auditoria_usuarios (ID_User, Accion, IP_Address, Detalles)
        VALUES (
            p_id_user, 'BLOQUEO', p_ip,
            JSON_OBJECT(
                'accion',          '2FA_CODIGO_BLOQUEADO',
                'id_verificacion', p_id_verificacion,
                'intentos',        v_intentos_fail
            )
        );

        COMMIT;
        SET p_mensaje = 'Error: Demasiados intentos fallidos. Solicite un nuevo código.';
        LEAVE proc;
    END IF;

    -- ── 5. Extraer el código del token (formato: CODIGO|hash) ────
    SET v_codigo_real = SUBSTRING_INDEX(v_token, '|', 1);

    -- ── 6. Comparar código ───────────────────────────────────────
    IF p_codigo != v_codigo_real THEN
        -- Registrar intento fallido
        INSERT INTO auditoria_usuarios (ID_User, Accion, IP_Address, Detalles)
        VALUES (
            p_id_user, 'INTENTO_FALLIDO', p_ip,
            JSON_OBJECT(
                'accion',          '2FA_CODIGO_INCORRECTO',
                'id_verificacion', p_id_verificacion,
                'intento_numero',  v_intentos_fail + 1,
                'intentos_restantes', v_max_intentos - v_intentos_fail - 1
            )
        );

        COMMIT;
        SET p_verificado = 0;
        SET p_mensaje = CONCAT(
            'Error: Código incorrecto. Intentos restantes: ',
            (v_max_intentos - v_intentos_fail - 1), '.'
        );
        LEAVE proc;
    END IF;

    -- ── 7. Código correcto: marcar como verificado ───────────────
    UPDATE verificacion
    SET    Estado              = 'Verificado',
           Fecha_verificacion  = NOW()
    WHERE  id = p_id_verificacion;

    -- ── 8. Actualizar último acceso del usuario ──────────────────
    UPDATE users
    SET    Ultimo_acceso      = NOW(),
           Intentos_fallidos  = 0
    WHERE  id = p_id_user;

    -- ── 9. Auditoría de login exitoso 2FA ────────────────────────
    INSERT INTO auditoria_usuarios (ID_User, Accion, IP_Address, Detalles)
    VALUES (
        p_id_user, 'LOGIN', p_ip,
        JSON_OBJECT(
            'accion',          '2FA_VERIFICADO',
            'metodo',          v_tipo,
            'id_verificacion', p_id_verificacion,
            'fecha',           NOW()
        )
    );

    COMMIT;

    SET p_verificado = 1;
    SET p_mensaje    = 'Verificación exitosa. Acceso concedido.';

END proc$$

DELIMITER ;

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `actividades_extracurriculares`
--

CREATE TABLE `actividades_extracurriculares` (
  `id` bigint(20) NOT NULL,
  `Nombre` varchar(255) NOT NULL,
  `Descripcion` text DEFAULT NULL,
  `Tipo` enum('Deporte','Arte','Musica','Ciencia','Club','Otro') NOT NULL,
  `ID_Responsable` bigint(20) DEFAULT NULL COMMENT 'Docente o admin responsable',
  `Cupo_maximo` int(11) DEFAULT NULL,
  `Horario` varchar(255) DEFAULT NULL,
  `Costo_adicional` decimal(10,2) DEFAULT 0.00,
  `Estado` enum('Activo','Inactivo','Suspendido') DEFAULT 'Activo'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Volcado de datos para la tabla `actividades_extracurriculares`
--

INSERT INTO `actividades_extracurriculares` (`id`, `Nombre`, `Descripcion`, `Tipo`, `ID_Responsable`, `Cupo_maximo`, `Horario`, `Costo_adicional`, `Estado`) VALUES
(1, 'Fútbol', 'Equipo de fútbol infantil', 'Deporte', 5, 25, 'Martes y Jueves 16:00-17:30', 0.00, 'Activo'),
(2, 'Ballet', 'Clases de ballet clásico', 'Arte', 4, 20, 'Lunes y Miércoles 16:00-17:00', 100.00, 'Activo'),
(3, 'Robótica', 'Club de robótica educativa', 'Ciencia', 2, 15, 'Viernes 15:00-17:00', 150.00, 'Activo'),
(4, 'Coro', 'Coro del colegio', 'Musica', 2, 30, 'Miércoles 15:00-16:30', 0.00, 'Activo'),
(5, 'Ajedrez', 'Club de ajedrez', 'Club', 3, 20, 'Jueves 15:00-16:30', 0.00, 'Activo');

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `anio_academico`
--

CREATE TABLE `anio_academico` (
  `id` bigint(20) NOT NULL,
  `Anio` int(4) NOT NULL COMMENT 'Año académico (ej: 2026)',
  `Nombre` varchar(100) NOT NULL COMMENT 'Nombre descriptivo (ej: "Año Académico 2026")',
  `Fecha_inicio` date NOT NULL,
  `Fecha_fin` date NOT NULL,
  `Estado` enum('Planificado','En_curso','Finalizado','Cancelado') DEFAULT 'Planificado',
  `Es_actual` tinyint(1) DEFAULT 0 COMMENT 'Indica si es el año académico actual',
  `Observaciones` text DEFAULT NULL,
  `Creado_en` timestamp NOT NULL DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Volcado de datos para la tabla `anio_academico`
--

INSERT INTO `anio_academico` (`id`, `Anio`, `Nombre`, `Fecha_inicio`, `Fecha_fin`, `Estado`, `Es_actual`, `Observaciones`, `Creado_en`) VALUES
(1, 2026, 'Año Académico 2026', '2026-02-01', '2026-11-30', 'En_curso', 1, NULL, '2026-02-14 18:25:42');

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `asignacion_docente`
--

CREATE TABLE `asignacion_docente` (
  `id` bigint(20) NOT NULL,
  `ID_Docente` bigint(20) NOT NULL,
  `ID_Materia` bigint(20) NOT NULL,
  `ID_Grado` bigint(20) NOT NULL,
  `ID_Anio_Academico` bigint(20) NOT NULL,
  `Horas_semanales` int(11) DEFAULT NULL COMMENT 'Cantidad de horas por semana',
  `Es_titular` tinyint(1) DEFAULT 1 COMMENT 'Si es el docente titular o suplente',
  `Fecha_inicio` date DEFAULT NULL,
  `Fecha_fin` date DEFAULT NULL,
  `Estado` enum('Activo','Finalizado','Suspendido') DEFAULT 'Activo',
  `Observaciones` text DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Volcado de datos para la tabla `asignacion_docente`
--

INSERT INTO `asignacion_docente` (`id`, `ID_Docente`, `ID_Materia`, `ID_Grado`, `ID_Anio_Academico`, `Horas_semanales`, `Es_titular`, `Fecha_inicio`, `Fecha_fin`, `Estado`, `Observaciones`) VALUES
(1, 1, 1, 8, 1, 6, 1, '2026-02-01', NULL, 'Activo', NULL),
(2, 1, 1, 9, 1, 6, 1, '2026-02-01', NULL, 'Activo', NULL),
(3, 1, 8, 10, 1, 6, 1, '2026-02-01', NULL, 'Activo', NULL),
(4, 2, 2, 8, 1, 6, 1, '2026-02-01', NULL, 'Activo', NULL),
(5, 2, 2, 9, 1, 6, 1, '2026-02-01', NULL, 'Activo', NULL),
(6, 2, 9, 10, 1, 5, 1, '2026-02-01', NULL, 'Activo', NULL),
(7, 3, 3, 8, 1, 4, 1, '2026-02-01', NULL, 'Activo', NULL),
(8, 3, 3, 9, 1, 4, 1, '2026-02-01', NULL, 'Activo', NULL),
(9, 3, 12, 10, 1, 4, 1, '2026-02-01', NULL, 'Activo', NULL),
(10, 4, 5, 8, 1, 3, 1, '2026-02-01', NULL, 'Activo', NULL),
(11, 4, 5, 9, 1, 3, 1, '2026-02-01', NULL, 'Activo', NULL),
(12, 4, 16, 10, 1, 2, 1, '2026-02-01', NULL, 'Activo', NULL);

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `asistencias`
--

CREATE TABLE `asistencias` (
  `id` bigint(20) NOT NULL,
  `ID_Estudiante` bigint(20) NOT NULL,
  `ID_Materia` bigint(20) DEFAULT NULL COMMENT 'NULL si es asistencia general del día',
  `ID_Docente` bigint(20) DEFAULT NULL,
  `Fecha` date NOT NULL,
  `Estado` enum('Presente','Ausente','Tardanza','Justificado','Permiso') NOT NULL,
  `Hora_llegada` time DEFAULT NULL,
  `Observaciones` text DEFAULT NULL,
  `Justificacion` text DEFAULT NULL,
  `Registrado_por` bigint(20) DEFAULT NULL,
  `Creado_en` timestamp NOT NULL DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Volcado de datos para la tabla `asistencias`
--

INSERT INTO `asistencias` (`id`, `ID_Estudiante`, `ID_Materia`, `ID_Docente`, `Fecha`, `Estado`, `Hora_llegada`, `Observaciones`, `Justificacion`, `Registrado_por`, `Creado_en`) VALUES
(1, 1, 1, 1, '2026-02-03', 'Presente', '07:55:00', NULL, NULL, 1, '2026-02-15 18:27:25'),
(2, 1, 2, 2, '2026-02-03', 'Presente', '07:55:00', NULL, NULL, 2, '2026-02-15 18:27:25'),
(3, 1, 1, 1, '2026-02-04', 'Presente', '07:58:00', NULL, NULL, 1, '2026-02-15 18:27:25'),
(4, 1, 2, 2, '2026-02-04', 'Presente', '07:58:00', NULL, NULL, 2, '2026-02-15 18:27:25'),
(5, 1, 1, 1, '2026-02-05', 'Presente', '07:55:00', NULL, NULL, 1, '2026-02-15 18:27:25'),
(6, 1, 2, 2, '2026-02-05', 'Presente', '07:55:00', NULL, NULL, 2, '2026-02-15 18:27:25'),
(7, 1, 1, 1, '2026-02-06', 'Presente', '08:05:00', NULL, NULL, 1, '2026-02-15 18:27:25'),
(8, 1, 2, 2, '2026-02-06', 'Tardanza', '08:10:00', NULL, NULL, 2, '2026-02-15 18:27:25'),
(9, 1, 1, 1, '2026-02-07', 'Presente', '07:55:00', NULL, NULL, 1, '2026-02-15 18:27:25'),
(10, 3, 1, 1, '2026-02-03', 'Presente', '07:55:00', NULL, NULL, 1, '2026-02-15 18:27:25'),
(11, 3, 2, 2, '2026-02-03', 'Presente', '07:55:00', NULL, NULL, 2, '2026-02-15 18:27:25'),
(12, 3, 1, 1, '2026-02-04', 'Ausente', NULL, NULL, NULL, 1, '2026-02-15 18:27:25'),
(13, 3, 2, 2, '2026-02-04', 'Ausente', NULL, NULL, NULL, 2, '2026-02-15 18:27:25'),
(14, 3, 1, 1, '2026-02-05', 'Justificado', NULL, NULL, NULL, 1, '2026-02-15 18:27:25'),
(15, 3, 2, 2, '2026-02-05', 'Justificado', NULL, NULL, NULL, 2, '2026-02-15 18:27:25'),
(16, 4, 1, 1, '2026-02-03', 'Presente', '07:55:00', NULL, NULL, 1, '2026-02-15 18:27:25'),
(17, 4, 2, 2, '2026-02-03', 'Presente', '07:55:00', NULL, NULL, 2, '2026-02-15 18:27:25'),
(18, 4, 1, 1, '2026-02-04', 'Presente', '07:55:00', NULL, NULL, 1, '2026-02-15 18:27:25'),
(19, 4, 2, 2, '2026-02-04', 'Presente', '07:55:00', NULL, NULL, 2, '2026-02-15 18:27:25'),
(20, 5, 8, 1, '2026-02-03', 'Presente', '07:55:00', NULL, NULL, 1, '2026-02-15 18:27:25'),
(21, 5, 9, 2, '2026-02-03', 'Presente', '07:55:00', NULL, NULL, 2, '2026-02-15 18:27:25'),
(22, 5, 8, 1, '2026-02-04', 'Presente', '07:55:00', NULL, NULL, 1, '2026-02-15 18:27:25'),
(23, 5, 9, 2, '2026-02-04', 'Presente', '07:55:00', NULL, NULL, 2, '2026-02-15 18:27:25');

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `asistencia_curso`
--

CREATE TABLE `asistencia_curso` (
  `id` bigint(20) NOT NULL,
  `ID_Curso` bigint(20) NOT NULL,
  `ID_Estudiante` bigint(20) NOT NULL,
  `Estado` enum('Presente','Ausente','Tardanza','Justificado','Permiso') NOT NULL DEFAULT 'Presente',
  `Hora_llegada` time DEFAULT NULL,
  `Observaciones` text DEFAULT NULL,
  `Registrado_por` bigint(20) DEFAULT NULL,
  `Creado_en` timestamp NOT NULL DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='Asistencia por curso (clase individual)';

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `auditoria`
--
-- Error leyendo la estructura de la tabla sge.auditoria: #1932 - Table &#039;sge.auditoria&#039; doesn&#039;t exist in engine
-- Error leyendo datos de la tabla sge.auditoria: #1064 - Algo está equivocado en su sintax cerca &#039;FROM `sge`.`auditoria`&#039; en la linea 1

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `auditoria_calificaciones`
--

CREATE TABLE `auditoria_calificaciones` (
  `id` bigint(20) NOT NULL,
  `ID_Calificacion_original` bigint(20) NOT NULL,
  `ID_Estudiante` bigint(20) NOT NULL,
  `ID_Materia` bigint(20) NOT NULL,
  `ID_Periodo` bigint(20) NOT NULL,
  `ID_Docente` bigint(20) NOT NULL,
  `Nota_anterior` decimal(5,2) DEFAULT NULL,
  `Nota_nueva` decimal(5,2) DEFAULT NULL,
  `Estado_anterior` enum('Borrador','Publicada','Modificada','Anulada') DEFAULT NULL,
  `Estado_nuevo` enum('Borrador','Publicada','Modificada','Anulada') DEFAULT NULL,
  `Accion` enum('INSERT','UPDATE','DELETE') NOT NULL,
  `Usuario_accion` bigint(20) NOT NULL,
  `Motivo` text DEFAULT NULL,
  `Fecha_hora` timestamp NOT NULL DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='Auditoría detallada de calificaciones';

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `auditoria_pagos`
--

CREATE TABLE `auditoria_pagos` (
  `id` bigint(20) NOT NULL,
  `ID_Pago_original` bigint(20) NOT NULL,
  `ID_Estudiante` bigint(20) NOT NULL,
  `Concepto` enum('Matricula','Pension','Examen','Materiales','Transporte','Uniforme','Otro') NOT NULL,
  `Monto_anterior` decimal(10,2) DEFAULT NULL,
  `Monto_nuevo` decimal(10,2) DEFAULT NULL,
  `Estado_anterior` enum('Pendiente','Pagado','Atrasado','Cancelado','Exonerado') DEFAULT NULL,
  `Estado_nuevo` enum('Pendiente','Pagado','Atrasado','Cancelado','Exonerado') DEFAULT NULL,
  `Accion` enum('INSERT','UPDATE','DELETE') NOT NULL,
  `Usuario_accion` bigint(20) NOT NULL,
  `Motivo` text DEFAULT NULL,
  `Fecha_hora` timestamp NOT NULL DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='Auditoría detallada de pagos';

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `auditoria_personas`
--

CREATE TABLE `auditoria_personas` (
  `id` bigint(20) NOT NULL,
  `ID_Persona_original` bigint(20) NOT NULL,
  `Datos_completos_anterior` longtext DEFAULT NULL COMMENT 'JSON con todos los datos antes del cambio',
  `Datos_completos_nuevo` longtext DEFAULT NULL COMMENT 'JSON con todos los datos después del cambio',
  `Accion` enum('INSERT','UPDATE','DELETE') NOT NULL,
  `Usuario_accion` bigint(20) DEFAULT NULL,
  `Motivo` text DEFAULT NULL,
  `Fecha_hora` timestamp NOT NULL DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='Auditoría completa de datos personales';

--
-- Volcado de datos para la tabla `auditoria_personas`
--

INSERT INTO `auditoria_personas` (`id`, `ID_Persona_original`, `Datos_completos_anterior`, `Datos_completos_nuevo`, `Accion`, `Usuario_accion`, `Motivo`, `Fecha_hora`) VALUES
(2, 23, NULL, '{\"Nombre\": \"Valentina\", \"Apellido\": \"Mamani\", \"CI\": \"1234567-CB\", \"Fecha_nacimiento\": \"2015-03-22\", \"Genero\": \"F\", \"Direccion\": \"Calle Sucre #345, Cochabamba\", \"Telefono\": \"76543210\", \"Email_personal\": \"vale.mamani@gmail.com\", \"Nacionalidad\": \"Boliviana\"}', 'INSERT', NULL, NULL, '2026-03-15 20:30:07'),
(3, 24, NULL, '{\"Nombre\": \"Jorge\", \"Apellido\": \"Mamani\", \"CI\": \"4567890\", \"Fecha_nacimiento\": \"1978-11-10\", \"Genero\": \"M\", \"Direccion\": \"Calle Sucre #345, Cochabamba\", \"Telefono\": \"71234567\", \"Email_personal\": \"jorge.mamani@gmail.com\", \"Nacionalidad\": \"Boliviana\"}', 'INSERT', NULL, NULL, '2026-03-15 20:30:07'),
(4, 25, NULL, '{\"Nombre\": \"Rosa\", \"Apellido\": \"Torrez\", \"CI\": \"5678901\", \"Fecha_nacimiento\": \"1981-06-25\", \"Genero\": \"F\", \"Direccion\": \"Calle Sucre #345, Cochabamba\", \"Telefono\": \"72345678\", \"Email_personal\": \"rosa.torrez@gmail.com\", \"Nacionalidad\": \"Boliviana\"}', 'INSERT', NULL, NULL, '2026-03-15 20:30:07'),
(5, 26, NULL, '{\"Nombre\": \"Boris\", \"Apellido\": \"Vargas\", \"CI\": \"1234321234-lp\", \"Fecha_nacimiento\": \"2017-02-17\", \"Genero\": \"M\", \"Direccion\": \"bvcxasdgfdsasdf\", \"Telefono\": \"123454321234\", \"Email_personal\": \"asdfngfdsderfd\", \"Nacionalidad\": \"Boliviana\"}', 'INSERT', NULL, NULL, '2026-03-15 21:25:59'),
(6, 27, NULL, '{\"Nombre\": \"Jaziel\", \"Apellido\": \"asfcasc\", \"CI\": \"acsac\", \"Fecha_nacimiento\": \"2002-01-30\", \"Genero\": \"M\", \"Direccion\": \"ascasc\", \"Telefono\": \"123321221\", \"Email_personal\": \"sdvvadcac\", \"Nacionalidad\": \"Boliviana\"}', 'INSERT', NULL, NULL, '2026-03-15 21:25:59'),
(7, 28, NULL, '{\"Nombre\": \"fghjkl\", \"Apellido\": \"zxcvb\", \"CI\": \"sdfghj\", \"Fecha_nacimiento\": \"2026-03-04\", \"Genero\": \"F\", \"Direccion\": \"asdfghj\", \"Telefono\": \"12345678\", \"Email_personal\": \"xcvbnm,\", \"Nacionalidad\": \"Boliviana\"}', 'INSERT', NULL, NULL, '2026-03-15 22:30:27'),
(8, 29, NULL, '{\"Nombre\": \"ZXC\", \"Apellido\": \"ZXC\", \"CI\": \"BVCX\", \"Fecha_nacimiento\": \"0000-00-00\", \"Genero\": \"F\", \"Direccion\": \"SVS\", \"Telefono\": \"ASDF\", \"Email_personal\": \"VSVS\", \"Nacionalidad\": \"Boliviana\"}', 'INSERT', NULL, NULL, '2026-03-15 22:30:27'),
(9, 30, NULL, '{\"Nombre\": \"sdfg\", \"Apellido\": \"zxcvbn\", \"CI\": \"12345678\", \"Fecha_nacimiento\": \"0456-03-12\", \"Genero\": \"M\", \"Direccion\": \"excvbnm,fdxfcgvh\", \"Telefono\": \"123456789\", \"Email_personal\": \"werctvybnm,kvcgthvbn\", \"Nacionalidad\": \"Boliviana\"}', 'INSERT', NULL, NULL, '2026-03-15 22:51:10'),
(10, 31, NULL, '{\"Nombre\": \"asdfbvc\", \"Apellido\": \"bvcxzx\", \"CI\": \"zxzxczcac\", \"Fecha_nacimiento\": \"0000-00-00\", \"Genero\": \"\", \"Direccion\": \"\", \"Telefono\": \"\", \"Email_personal\": \"\", \"Nacionalidad\": \"Boliviana\"}', 'INSERT', NULL, NULL, '2026-03-15 22:51:10'),
(11, 32, NULL, '{\"Nombre\": \"Deybid\", \"Apellido\": \"Choque\", \"CI\": \"1234\", \"Fecha_nacimiento\": \"2026-03-11\", \"Genero\": \"M\", \"Direccion\": \"asdfgbnm\", \"Telefono\": \"12345\", \"Email_personal\": \"asdfg\", \"Nacionalidad\": \"Boliviana\"}', 'INSERT', NULL, NULL, '2026-03-18 00:11:39'),
(12, 33, NULL, '{\"Nombre\": \"dfghjk\", \"Apellido\": \"fgbhjkl\", \"CI\": \"2345678\", \"Fecha_nacimiento\": \"2026-03-19\", \"Genero\": \"F\", \"Direccion\": \"cvbn\", \"Telefono\": \"345678\", \"Email_personal\": \"xcvbnm\", \"Nacionalidad\": \"Boliviana\"}', 'INSERT', NULL, NULL, '2026-03-18 00:11:39'),
(13, 21, '{\"Nombre\": \"Jaziel\", \"Apellido\": \"Vargas\", \"CI\": \"0288103\", \"Fecha_nacimiento\": \"0000-00-00\", \"Genero\": \"M\", \"Direccion\": \"limanipata\", \"Telefono\": \"829092993\", \"Email_personal\": \"ss xns \", \"Nacionalidad\": \"cacscsc\"}', '{\"Nombre\": \"Jaziel\", \"Apellido\": \"Vargas\", \"CI\": \"0288103\", \"Fecha_nacimiento\": \"0000-00-00\", \"Genero\": \"M\", \"Direccion\": \"limanipata\", \"Telefono\": \"829092993\", \"Email_personal\": \"jazielarmandovargaschoque@gmail.com\", \"Nacionalidad\": \"cacscsc\"}', 'UPDATE', 21, NULL, '2026-04-04 21:20:45'),
(14, 21, '{\"Nombre\": \"Jaziel\", \"Apellido\": \"Vargas\", \"CI\": \"0288103\", \"Fecha_nacimiento\": \"0000-00-00\", \"Genero\": \"M\", \"Direccion\": \"limanipata\", \"Telefono\": \"829092993\", \"Email_personal\": \"jazielarmandovargaschoque@gmail.com\", \"Nacionalidad\": \"cacscsc\"}', '{\"Nombre\": \"Jaziel\", \"Apellido\": \"Vargas\", \"CI\": \"0288103\", \"Fecha_nacimiento\": \"0000-00-00\", \"Genero\": \"M\", \"Direccion\": \"limanipata\", \"Telefono\": \"+591 79532646\", \"Email_personal\": \"jazielarmandovargaschoque@gmail.com\", \"Nacionalidad\": \"cacscsc\"}', 'UPDATE', 21, NULL, '2026-04-04 22:05:09');

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `auditoria_usuarios`
--

CREATE TABLE `auditoria_usuarios` (
  `id` bigint(20) NOT NULL,
  `ID_User` bigint(20) NOT NULL,
  `Accion` enum('LOGIN','LOGOUT','CAMBIO_PASSWORD','INTENTO_FALLIDO','BLOQUEO','DESBLOQUEO','CREACION','MODIFICACION','ELIMINACION') NOT NULL,
  `IP_Address` varchar(45) DEFAULT NULL,
  `User_Agent` varchar(255) DEFAULT NULL,
  `Detalles` text DEFAULT NULL COMMENT 'JSON con detalles adicionales',
  `Fecha_hora` timestamp NOT NULL DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='Auditoría específica de usuarios';

--
-- Volcado de datos para la tabla `auditoria_usuarios`
--

INSERT INTO `auditoria_usuarios` (`id`, `ID_User`, `Accion`, `IP_Address`, `User_Agent`, `Detalles`, `Fecha_hora`) VALUES
(1, 1, 'LOGIN', '::ffff:127.0.0.1', NULL, '{\"accion\": \"2FA_CODIGO_GENERADO\", \"metodo\": \"Email\", \"id_verificacion\": \"33\", \"expira_en\": \"2026-04-04 17:12:19\"}', '2026-04-04 21:02:19'),
(2, 1, 'LOGIN', '::ffff:127.0.0.1', NULL, '{\"accion\": \"2FA_CODIGO_GENERADO\", \"metodo\": \"Telefono\", \"id_verificacion\": \"34\", \"expira_en\": \"2026-04-04 17:13:12\"}', '2026-04-04 21:03:12'),
(3, 1, 'LOGIN', '::ffff:127.0.0.1', 'vscode-restclient', '{\"accion\": \"LOGIN_PASO_1_OK\", \"requiere_2fa\": \"1\", \"rol\": \"Administrador\"}', '2026-04-04 21:10:06'),
(4, 1, 'LOGIN', '::ffff:127.0.0.1', NULL, '{\"accion\": \"2FA_CODIGO_GENERADO\", \"metodo\": \"Email\", \"id_verificacion\": \"35\", \"expira_en\": \"2026-04-04 17:20:19\"}', '2026-04-04 21:10:19'),
(5, 1, 'LOGIN', '::ffff:127.0.0.1', NULL, '{\"accion\": \"2FA_CODIGO_GENERADO\", \"metodo\": \"Email\", \"id_verificacion\": \"36\", \"expira_en\": \"2026-04-04 17:20:34\"}', '2026-04-04 21:10:34'),
(6, 1, 'INTENTO_FALLIDO', '::ffff:127.0.0.1', 'vscode-restclient', '{\"motivo\": \"password_incorrecto\", \"intentos_acumulados\": 1, \"intentos_restantes\": 4}', '2026-04-04 21:10:45'),
(10, 1, 'LOGIN', '::ffff:127.0.0.1', 'vscode-restclient', '{\"accion\": \"LOGIN_PASO_1_OK\", \"requiere_2fa\": \"1\", \"rol\": \"Administrador\"}', '2026-04-04 21:47:04'),
(14, 21, 'LOGIN', '::ffff:127.0.0.1', 'vscode-restclient', '{\"accion\": \"LOGIN_PASO_1_OK\", \"requiere_2fa\": \"1\", \"rol\": \"Docente\"}', '2026-04-04 21:50:04'),
(15, 21, 'LOGIN', '::1', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/145.0.0.0 Safari/537.36 OPR/129.0.0.0', '{\"accion\": \"LOGIN_PASO_1_OK\", \"requiere_2fa\": \"1\", \"rol\": \"Docente\"}', '2026-04-04 21:50:19'),
(16, 21, 'LOGIN', '::1', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/145.0.0.0 Safari/537.36 OPR/129.0.0.0', '{\"accion\": \"LOGIN_PASO_1_OK\", \"requiere_2fa\": \"1\", \"rol\": \"Docente\"}', '2026-04-04 21:59:04'),
(17, 21, 'LOGIN', '::1', NULL, '{\"accion\": \"2FA_CODIGO_GENERADO\", \"metodo\": \"Telefono\", \"id_verificacion\": \"37\", \"expira_en\": \"2026-04-04 18:09:13\"}', '2026-04-04 21:59:13'),
(18, 21, 'LOGIN', '::1', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/145.0.0.0 Safari/537.36 OPR/129.0.0.0', '{\"accion\": \"LOGIN_PASO_1_OK\", \"requiere_2fa\": \"1\", \"rol\": \"Docente\"}', '2026-04-05 18:52:29'),
(19, 21, 'LOGIN', '::1', NULL, '{\"accion\": \"2FA_CODIGO_GENERADO\", \"metodo\": \"Email\", \"id_verificacion\": \"38\", \"expira_en\": \"2026-04-05 15:02:35\"}', '2026-04-05 18:52:35'),
(20, 21, 'LOGIN', '::1', NULL, '{\"accion\": \"2FA_CODIGO_GENERADO\", \"metodo\": \"Email\", \"id_verificacion\": \"39\", \"expira_en\": \"2026-04-05 15:25:01\"}', '2026-04-05 19:15:01'),
(21, 21, 'LOGIN', '::1', NULL, '{\"accion\": \"2FA_CODIGO_GENERADO\", \"metodo\": \"Email\", \"id_verificacion\": \"40\", \"expira_en\": \"2026-04-05 15:26:16\"}', '2026-04-05 19:16:16'),
(22, 21, 'LOGIN', '::1', NULL, '{\"accion\": \"2FA_CODIGO_GENERADO\", \"metodo\": \"Email\", \"id_verificacion\": \"41\", \"expira_en\": \"2026-04-05 15:27:06\"}', '2026-04-05 19:17:06'),
(23, 21, 'LOGIN', '::1', NULL, '{\"accion\": \"2FA_CODIGO_GENERADO\", \"metodo\": \"Email\", \"id_verificacion\": \"42\", \"expira_en\": \"2026-04-05 15:43:49\"}', '2026-04-05 19:33:49'),
(24, 21, 'LOGIN', '::ffff:127.0.0.1', NULL, '{\"accion\": \"2FA_CODIGO_GENERADO\", \"metodo\": \"Email\", \"id_verificacion\": \"43\", \"expira_en\": \"2026-04-05 15:44:13\"}', '2026-04-05 19:34:13'),
(25, 1, 'LOGIN', '::ffff:127.0.0.1', NULL, '{\"accion\": \"2FA_CODIGO_GENERADO\", \"metodo\": \"Email\", \"id_verificacion\": \"44\", \"expira_en\": \"2026-04-05 15:50:41\"}', '2026-04-05 19:40:41'),
(26, 21, 'LOGIN', '::1', NULL, '{\"accion\": \"2FA_CODIGO_GENERADO\", \"metodo\": \"Email\", \"id_verificacion\": \"45\", \"expira_en\": \"2026-04-05 15:59:25\"}', '2026-04-05 19:49:25'),
(27, 21, 'LOGIN', '::1', NULL, '{\"accion\": \"2FA_CODIGO_GENERADO\", \"metodo\": \"Email\", \"id_verificacion\": \"46\", \"expira_en\": \"2026-04-05 16:00:06\"}', '2026-04-05 19:50:06'),
(28, 21, 'LOGIN', '::1', NULL, '{\"accion\": \"2FA_CODIGO_GENERADO\", \"metodo\": \"Email\", \"id_verificacion\": \"47\", \"expira_en\": \"2026-04-05 16:00:30\"}', '2026-04-05 19:50:30'),
(29, 21, 'LOGIN', '::1', NULL, '{\"accion\": \"2FA_CODIGO_GENERADO\", \"metodo\": \"Email\", \"id_verificacion\": \"48\", \"expira_en\": \"2026-04-05 16:05:23\"}', '2026-04-05 19:55:23'),
(30, 21, 'LOGIN', '::1', NULL, '{\"accion\": \"2FA_CODIGO_GENERADO\", \"metodo\": \"Email\", \"id_verificacion\": \"49\", \"expira_en\": \"2026-04-05 16:06:18\"}', '2026-04-05 19:56:18'),
(31, 21, 'LOGIN', '::1', NULL, '{\"accion\": \"2FA_CODIGO_GENERADO\", \"metodo\": \"Email\", \"id_verificacion\": \"50\", \"expira_en\": \"2026-04-05 16:08:01\"}', '2026-04-05 19:58:01'),
(32, 21, 'LOGIN', '::1', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/145.0.0.0 Safari/537.36 OPR/129.0.0.0', '{\"accion\": \"LOGIN_PASO_1_OK\", \"requiere_2fa\": \"1\", \"rol\": \"Docente\"}', '2026-04-05 20:21:12'),
(33, 21, 'LOGIN', '::1', NULL, '{\"accion\": \"2FA_CODIGO_GENERADO\", \"metodo\": \"Email\", \"id_verificacion\": \"51\", \"expira_en\": \"2026-04-05 16:31:13\"}', '2026-04-05 20:21:13'),
(34, 21, 'LOGIN', '::1', NULL, '{\"accion\": \"2FA_CODIGO_GENERADO\", \"metodo\": \"Email\", \"id_verificacion\": \"52\", \"expira_en\": \"2026-04-05 16:37:03\"}', '2026-04-05 20:27:03'),
(35, 21, 'LOGIN', '::1', NULL, '{\"accion\": \"2FA_CODIGO_GENERADO\", \"metodo\": \"Email\", \"id_verificacion\": \"53\", \"expira_en\": \"2026-04-05 16:40:13\"}', '2026-04-05 20:30:13'),
(36, 21, 'LOGIN', '::1', NULL, '{\"accion\": \"2FA_CODIGO_GENERADO\", \"metodo\": \"Email\", \"id_verificacion\": \"54\", \"expira_en\": \"2026-04-05 16:40:34\"}', '2026-04-05 20:30:34'),
(37, 21, 'LOGIN', '::1', NULL, '{\"accion\": \"2FA_CODIGO_GENERADO\", \"metodo\": \"Email\", \"id_verificacion\": \"55\", \"expira_en\": \"2026-04-05 16:44:49\"}', '2026-04-05 20:34:49'),
(38, 21, 'LOGIN', '::1', NULL, '{\"accion\": \"2FA_CODIGO_GENERADO\", \"metodo\": \"Email\", \"id_verificacion\": \"56\", \"expira_en\": \"2026-04-05 16:58:58\"}', '2026-04-05 20:48:58'),
(39, 21, 'LOGIN', '::1', NULL, '{\"accion\": \"2FA_CODIGO_GENERADO\", \"metodo\": \"Email\", \"id_verificacion\": \"57\", \"expira_en\": \"2026-04-05 17:11:17\"}', '2026-04-05 21:01:17'),
(40, 21, 'LOGIN', '::1', NULL, '{\"accion\": \"2FA_CODIGO_GENERADO\", \"metodo\": \"Email\", \"id_verificacion\": \"58\", \"expira_en\": \"2026-04-05 17:21:29\"}', '2026-04-05 21:11:29'),
(41, 21, 'LOGIN', '::ffff:127.0.0.1', 'vscode-restclient', '{\"accion\": \"LOGIN_PASO_1_OK\", \"requiere_2fa\": \"1\", \"rol\": \"Docente\"}', '2026-04-05 22:08:16'),
(42, 21, 'LOGIN', '::ffff:127.0.0.1', 'vscode-restclient', '{\"accion\": \"LOGIN_PASO_1_OK\", \"requiere_2fa\": \"1\", \"rol\": \"Docente\"}', '2026-04-05 22:09:48'),
(43, 21, 'LOGIN', '::ffff:127.0.0.1', NULL, '{\"accion\": \"2FA_CODIGO_GENERADO\", \"metodo\": \"Email\", \"id_verificacion\": \"59\", \"expira_en\": \"2026-04-05 18:22:57\"}', '2026-04-05 22:12:57'),
(44, 21, 'LOGIN', '::ffff:127.0.0.1', NULL, '{\"accion\": \"2FA_CODIGO_GENERADO\", \"metodo\": \"Email\", \"id_verificacion\": \"60\", \"expira_en\": \"2026-04-05 18:24:19\"}', '2026-04-05 22:14:19'),
(45, 21, 'LOGIN', '::ffff:127.0.0.1', NULL, '{\"accion\": \"2FA_CODIGO_GENERADO\", \"metodo\": \"Email\", \"id_verificacion\": \"61\", \"expira_en\": \"2026-04-05 18:26:01\"}', '2026-04-05 22:16:01'),
(46, 21, 'LOGIN', '::ffff:127.0.0.1', NULL, '{\"accion\": \"2FA_CODIGO_GENERADO\", \"metodo\": \"Email\", \"id_verificacion\": \"62\", \"expira_en\": \"2026-04-05 18:27:00\"}', '2026-04-05 22:17:00'),
(47, 21, 'LOGIN', '::ffff:127.0.0.1', NULL, '{\"accion\": \"2FA_VERIFICADO\", \"metodo\": \"Email\", \"id_verificacion\": \"62\", \"fecha\": \"2026-04-05 18:17:49\"}', '2026-04-05 22:17:49'),
(48, 21, 'LOGIN', '::1', NULL, '{\"accion\": \"2FA_CODIGO_GENERADO\", \"metodo\": \"Email\", \"id_verificacion\": \"63\", \"expira_en\": \"2026-04-05 18:35:45\"}', '2026-04-05 22:25:45'),
(49, 21, 'LOGIN', '::1', NULL, '{\"accion\": \"2FA_VERIFICADO\", \"metodo\": \"Email\", \"id_verificacion\": \"63\", \"fecha\": \"2026-04-05 18:26:12\"}', '2026-04-05 22:26:12'),
(50, 21, 'LOGIN', '::ffff:127.0.0.1', 'vscode-restclient', '{\"accion\": \"LOGIN_PASO_1_OK\", \"requiere_2fa\": \"1\", \"rol\": \"Docente\"}', '2026-04-05 22:45:11'),
(51, 21, 'LOGIN', '::ffff:127.0.0.1', NULL, '{\"accion\": \"2FA_CODIGO_GENERADO\", \"metodo\": \"Email\", \"id_verificacion\": \"64\", \"expira_en\": \"2026-04-05 18:55:26\"}', '2026-04-05 22:45:26'),
(52, 21, 'LOGIN', '::ffff:127.0.0.1', NULL, '{\"accion\": \"2FA_VERIFICADO\", \"metodo\": \"Email\", \"id_verificacion\": \"64\", \"fecha\": \"2026-04-05 18:46:10\"}', '2026-04-05 22:46:10'),
(53, 21, 'LOGIN', '::1', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/145.0.0.0 Safari/537.36 OPR/129.0.0.0', '{\"accion\": \"LOGIN_PASO_1_OK\", \"requiere_2fa\": \"1\", \"rol\": \"Docente\"}', '2026-04-05 22:55:32'),
(54, 21, 'LOGIN', '::1', NULL, '{\"accion\": \"2FA_CODIGO_GENERADO\", \"metodo\": \"Email\", \"id_verificacion\": \"65\", \"expira_en\": \"2026-04-05 19:05:44\"}', '2026-04-05 22:55:44'),
(55, 21, 'LOGIN', '::1', NULL, '{\"accion\": \"2FA_VERIFICADO\", \"metodo\": \"Email\", \"id_verificacion\": \"65\", \"fecha\": \"2026-04-05 18:56:21\"}', '2026-04-05 22:56:21'),
(56, 21, 'LOGIN', '::1', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/145.0.0.0 Safari/537.36 OPR/129.0.0.0', '{\"accion\": \"LOGIN_PASO_1_OK\", \"requiere_2fa\": \"1\", \"rol\": \"Docente\"}', '2026-04-05 22:57:08'),
(57, 21, 'LOGIN', '::1', NULL, '{\"accion\": \"2FA_CODIGO_GENERADO\", \"metodo\": \"Email\", \"id_verificacion\": \"66\", \"expira_en\": \"2026-04-05 19:07:14\"}', '2026-04-05 22:57:14'),
(58, 21, 'LOGIN', '::1', NULL, '{\"accion\": \"2FA_VERIFICADO\", \"metodo\": \"Email\", \"id_verificacion\": \"66\", \"fecha\": \"2026-04-05 18:58:01\"}', '2026-04-05 22:58:01'),
(59, 21, 'LOGIN', '::1', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/145.0.0.0 Safari/537.36 OPR/129.0.0.0', '{\"accion\": \"LOGIN_PASO_1_OK\", \"requiere_2fa\": \"1\", \"rol\": \"Docente\"}', '2026-04-06 18:23:17'),
(60, 21, 'INTENTO_FALLIDO', '::1', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/146.0.0.0 Safari/537.36 Edg/146.0.0.0', '{\"motivo\": \"password_incorrecto\", \"intentos_acumulados\": 1, \"intentos_restantes\": 4}', '2026-04-06 18:24:21'),
(61, 21, 'LOGIN', '::1', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/146.0.0.0 Safari/537.36 Edg/146.0.0.0', '{\"accion\": \"LOGIN_PASO_1_OK\", \"requiere_2fa\": \"1\", \"rol\": \"Docente\"}', '2026-04-06 18:24:51'),
(62, 21, 'LOGIN', '::1', NULL, '{\"accion\": \"2FA_CODIGO_GENERADO\", \"metodo\": \"Email\", \"id_verificacion\": \"67\", \"expira_en\": \"2026-04-06 14:35:03\"}', '2026-04-06 18:25:03'),
(63, 21, 'LOGIN', '::1', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/146.0.0.0 Safari/537.36 Edg/146.0.0.0', '{\"accion\": \"LOGIN_PASO_1_OK\", \"requiere_2fa\": \"1\", \"rol\": \"Docente\"}', '2026-04-06 18:27:55'),
(64, 21, 'LOGIN', '::1', NULL, '{\"accion\": \"2FA_CODIGO_GENERADO\", \"metodo\": \"Email\", \"id_verificacion\": \"68\", \"expira_en\": \"2026-04-06 14:53:44\"}', '2026-04-06 18:43:44'),
(65, 21, 'LOGIN', '::1', NULL, '{\"accion\": \"2FA_CODIGO_GENERADO\", \"metodo\": \"Email\", \"id_verificacion\": \"69\", \"expira_en\": \"2026-04-06 14:53:53\"}', '2026-04-06 18:43:53'),
(66, 21, 'LOGIN', '', '', '{\"accion\": \"LOGIN_PASO_1_OK\", \"requiere_2fa\": \"1\", \"rol\": \"Docente\"}', '2026-04-06 22:58:05'),
(67, 21, 'LOGIN', '::ffff:127.0.0.1', 'vscode-restclient', '{\"accion\": \"LOGIN_PASO_1_OK\", \"requiere_2fa\": \"1\", \"rol\": \"Docente\"}', '2026-04-21 19:16:13'),
(68, 21, 'LOGIN', '::1', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/145.0.0.0 Safari/537.36 OPR/129.0.0.0', '{\"accion\": \"LOGIN_PASO_1_OK\", \"requiere_2fa\": \"1\", \"rol\": \"Docente\"}', '2026-04-21 19:20:19'),
(69, 21, 'LOGIN', '::1', NULL, '{\"accion\": \"2FA_CODIGO_GENERADO\", \"metodo\": \"Email\", \"id_verificacion\": \"70\", \"expira_en\": \"2026-04-21 15:31:00\"}', '2026-04-21 19:21:00'),
(70, 21, 'LOGIN', '::1', NULL, '{\"accion\": \"2FA_VERIFICADO\", \"metodo\": \"Email\", \"id_verificacion\": \"70\", \"fecha\": \"2026-04-21 15:21:17\"}', '2026-04-21 19:21:17'),
(71, 21, 'LOGIN', '::1', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/145.0.0.0 Safari/537.36 OPR/129.0.0.0', '{\"accion\": \"LOGIN_PASO_1_OK\", \"requiere_2fa\": \"1\", \"rol\": \"Admin\"}', '2026-04-21 19:24:21'),
(72, 21, 'LOGIN', '::1', NULL, '{\"accion\": \"2FA_CODIGO_GENERADO\", \"metodo\": \"Email\", \"id_verificacion\": \"71\", \"expira_en\": \"2026-04-21 15:34:22\"}', '2026-04-21 19:24:22'),
(73, 21, 'LOGIN', '::1', NULL, '{\"accion\": \"2FA_VERIFICADO\", \"metodo\": \"Email\", \"id_verificacion\": \"71\", \"fecha\": \"2026-04-21 15:24:37\"}', '2026-04-21 19:24:37'),
(74, 21, 'LOGIN', '::ffff:127.0.0.1', 'vscode-restclient', '{\"accion\": \"LOGIN_PASO_1_OK\", \"requiere_2fa\": \"1\", \"rol\": \"Admin\"}', '2026-04-21 19:25:27'),
(75, 21, 'LOGIN', '::1', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/145.0.0.0 Safari/537.36 OPR/129.0.0.0', '{\"accion\": \"LOGIN_PASO_1_OK\", \"requiere_2fa\": \"1\", \"rol\": \"Admin\"}', '2026-04-21 19:28:21'),
(76, 21, 'LOGIN', '::1', NULL, '{\"accion\": \"2FA_CODIGO_GENERADO\", \"metodo\": \"Email\", \"id_verificacion\": \"72\", \"expira_en\": \"2026-04-21 15:39:23\"}', '2026-04-21 19:29:23'),
(77, 21, 'LOGIN', '::1', NULL, '{\"accion\": \"2FA_VERIFICADO\", \"metodo\": \"Email\", \"id_verificacion\": \"72\", \"fecha\": \"2026-04-21 15:29:46\"}', '2026-04-21 19:29:46'),
(78, 21, 'LOGIN', '::1', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/145.0.0.0 Safari/537.36 OPR/129.0.0.0', '{\"accion\": \"LOGIN_PASO_1_OK\", \"requiere_2fa\": \"1\", \"rol\": \"Admin\"}', '2026-04-21 19:52:09'),
(79, 21, 'LOGIN', '::1', NULL, '{\"accion\": \"2FA_CODIGO_GENERADO\", \"metodo\": \"Email\", \"id_verificacion\": \"73\", \"expira_en\": \"2026-04-21 16:02:10\"}', '2026-04-21 19:52:10'),
(80, 21, 'LOGIN', '::1', NULL, '{\"accion\": \"2FA_VERIFICADO\", \"metodo\": \"Email\", \"id_verificacion\": \"73\", \"fecha\": \"2026-04-21 15:52:33\"}', '2026-04-21 19:52:33');

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `calificaciones`
--

CREATE TABLE `calificaciones` (
  `id` bigint(20) NOT NULL,
  `ID_Estudiante` bigint(20) NOT NULL,
  `ID_Materia` bigint(20) NOT NULL,
  `ID_Periodo` bigint(20) NOT NULL,
  `ID_Docente` bigint(20) NOT NULL,
  `ID_Anio_Academico` bigint(20) DEFAULT NULL,
  `Nota` decimal(5,2) DEFAULT NULL COMMENT 'Nota obtenida',
  `Nota_maxima` decimal(5,2) DEFAULT 100.00 COMMENT 'Nota máxima posible',
  `Porcentaje_peso` decimal(5,2) DEFAULT NULL COMMENT 'Peso en la nota del período',
  `Descripcion` varchar(255) DEFAULT NULL,
  `Fecha_evaluacion` date DEFAULT NULL,
  `Tipo_evaluacion` enum('Examen','Tarea','Proyecto','Participacion','Practica','Promedio_Periodo','Nota_Final') NOT NULL,
  `Fecha_registro` timestamp NOT NULL DEFAULT current_timestamp(),
  `Estado` enum('Borrador','Publicada','Modificada','Anulada') DEFAULT 'Borrador',
  `Observaciones` text DEFAULT NULL,
  `Actualizado_por` bigint(20) DEFAULT NULL,
  `Actualizado_en` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Volcado de datos para la tabla `calificaciones`
--

INSERT INTO `calificaciones` (`id`, `ID_Estudiante`, `ID_Materia`, `ID_Periodo`, `ID_Docente`, `ID_Anio_Academico`, `Nota`, `Nota_maxima`, `Porcentaje_peso`, `Descripcion`, `Fecha_evaluacion`, `Tipo_evaluacion`, `Fecha_registro`, `Estado`, `Observaciones`, `Actualizado_por`, `Actualizado_en`) VALUES
(1, 1, 1, 1, 1, 1, 85.00, 100.00, 30.00, 'Examen parcial', '2026-02-10', 'Examen', '2026-02-15 18:27:25', 'Publicada', NULL, NULL, '2026-02-15 18:27:25'),
(2, 1, 1, 1, 1, 1, 90.00, 100.00, 20.00, 'Tarea 1', '2026-02-05', 'Tarea', '2026-02-15 18:27:25', 'Publicada', NULL, NULL, '2026-02-15 18:27:25'),
(3, 1, 2, 1, 2, 1, 88.00, 100.00, 30.00, 'Examen parcial', '2026-02-12', 'Examen', '2026-02-15 18:27:25', 'Publicada', NULL, NULL, '2026-02-15 18:27:25'),
(4, 1, 3, 1, 3, 1, 92.00, 100.00, 30.00, 'Examen parcial', '2026-02-11', 'Examen', '2026-02-15 18:27:25', 'Publicada', NULL, NULL, '2026-02-15 18:27:25'),
(5, 3, 1, 1, 1, 1, 78.00, 100.00, 30.00, 'Examen parcial', '2026-02-10', 'Examen', '2026-02-15 18:27:25', 'Publicada', NULL, NULL, '2026-02-15 18:27:25'),
(6, 3, 1, 1, 1, 1, 85.00, 100.00, 20.00, 'Tarea 1', '2026-02-05', 'Tarea', '2026-02-15 18:27:25', 'Publicada', NULL, NULL, '2026-02-15 18:27:25'),
(7, 3, 2, 1, 2, 1, 82.00, 100.00, 30.00, 'Examen parcial', '2026-02-12', 'Examen', '2026-02-15 18:27:25', 'Publicada', NULL, NULL, '2026-02-15 18:27:25'),
(8, 4, 1, 1, 1, 1, 95.00, 100.00, 30.00, 'Examen parcial', '2026-02-10', 'Examen', '2026-02-15 18:27:25', 'Publicada', NULL, NULL, '2026-02-15 18:27:25'),
(9, 4, 2, 1, 2, 1, 93.00, 100.00, 30.00, 'Examen parcial', '2026-02-12', 'Examen', '2026-02-15 18:27:25', 'Publicada', NULL, NULL, '2026-02-15 18:27:25'),
(10, 5, 8, 1, 1, 1, 87.00, 100.00, 30.00, 'Examen parcial', '2026-02-10', 'Examen', '2026-02-15 18:27:25', 'Publicada', NULL, NULL, '2026-02-15 18:27:25'),
(11, 5, 9, 1, 2, 1, 89.00, 100.00, 30.00, 'Examen parcial', '2026-02-12', 'Examen', '2026-02-15 18:27:25', 'Publicada', NULL, NULL, '2026-02-15 18:27:25'),
(12, 5, 12, 1, 3, 1, 91.00, 100.00, 30.00, 'Examen parcial', '2026-02-11', 'Examen', '2026-02-15 18:27:25', 'Publicada', NULL, NULL, '2026-02-15 18:27:25');

--
-- Disparadores `calificaciones`
--
DELIMITER $$
CREATE TRIGGER `tr_auditoria_calificaciones_delete` BEFORE DELETE ON `calificaciones` FOR EACH ROW BEGIN
    DECLARE v_id_user BIGINT;
    SELECT ID_User INTO v_id_user FROM docente WHERE id = OLD.ID_Docente;
    
    INSERT INTO auditoria_calificaciones (
        ID_Calificacion_original, ID_Estudiante, ID_Materia, ID_Periodo, ID_Docente,
        Nota_anterior, Nota_nueva, Estado_anterior, Estado_nuevo,
        Accion, Usuario_accion
    ) VALUES (
        OLD.id, OLD.ID_Estudiante, OLD.ID_Materia, OLD.ID_Periodo, OLD.ID_Docente,
        OLD.Nota, NULL, OLD.Estado, NULL,
        'DELETE', v_id_user
    );
END
$$
DELIMITER ;
DELIMITER $$
CREATE TRIGGER `tr_auditoria_calificaciones_insert` AFTER INSERT ON `calificaciones` FOR EACH ROW BEGIN
    DECLARE v_id_user BIGINT;
    SELECT ID_User INTO v_id_user FROM docente WHERE id = NEW.ID_Docente;
    
    INSERT INTO auditoria_calificaciones (
        ID_Calificacion_original, ID_Estudiante, ID_Materia, ID_Periodo, ID_Docente,
        Nota_anterior, Nota_nueva, Estado_anterior, Estado_nuevo,
        Accion, Usuario_accion
    ) VALUES (
        NEW.id, NEW.ID_Estudiante, NEW.ID_Materia, NEW.ID_Periodo, NEW.ID_Docente,
        NULL, NEW.Nota, NULL, NEW.Estado,
        'INSERT', v_id_user
    );
END
$$
DELIMITER ;
DELIMITER $$
CREATE TRIGGER `tr_auditoria_calificaciones_update` AFTER UPDATE ON `calificaciones` FOR EACH ROW BEGIN
    DECLARE v_id_user BIGINT;
    SELECT ID_User INTO v_id_user FROM docente WHERE id = NEW.ID_Docente;
    
    INSERT INTO auditoria_calificaciones (
        ID_Calificacion_original, ID_Estudiante, ID_Materia, ID_Periodo, ID_Docente,
        Nota_anterior, Nota_nueva, Estado_anterior, Estado_nuevo,
        Accion, Usuario_accion
    ) VALUES (
        NEW.id, NEW.ID_Estudiante, NEW.ID_Materia, NEW.ID_Periodo, NEW.ID_Docente,
        OLD.Nota, NEW.Nota, OLD.Estado, NEW.Estado,
        'UPDATE', v_id_user
    );
END
$$
DELIMITER ;
DELIMITER $$
CREATE TRIGGER `tr_calificaciones_delete` BEFORE DELETE ON `calificaciones` FOR EACH ROW BEGIN
    DECLARE v_id_user BIGINT;
    SELECT ID_User INTO v_id_user FROM docente WHERE id = OLD.ID_Docente;
    
    INSERT INTO auditoria (ID_User, Accion, Tabla_afectada, ID_Registro_afectado, Datos_anteriores)
    VALUES (
        v_id_user,
        'DELETE',
        'calificaciones',
        OLD.id,
        JSON_OBJECT(
            'ID_Estudiante', OLD.ID_Estudiante,
            'ID_Materia', OLD.ID_Materia,
            'Nota', OLD.Nota
        )
    );
END
$$
DELIMITER ;
DELIMITER $$
CREATE TRIGGER `tr_calificaciones_insert` AFTER INSERT ON `calificaciones` FOR EACH ROW BEGIN
    DECLARE v_id_user BIGINT;
    SELECT ID_User INTO v_id_user FROM docente WHERE id = NEW.ID_Docente;
    
    INSERT INTO auditoria (ID_User, Accion, Tabla_afectada, ID_Registro_afectado, Datos_nuevos)
    VALUES (
        v_id_user,
        'INSERT',
        'calificaciones',
        NEW.id,
        JSON_OBJECT(
            'ID_Estudiante', NEW.ID_Estudiante,
            'ID_Materia', NEW.ID_Materia,
            'Nota', NEW.Nota,
            'Tipo_evaluacion', NEW.Tipo_evaluacion,
            'Estado', NEW.Estado
        )
    );
END
$$
DELIMITER ;
DELIMITER $$
CREATE TRIGGER `tr_calificaciones_update` AFTER UPDATE ON `calificaciones` FOR EACH ROW BEGIN
    DECLARE v_id_user BIGINT;
    SELECT ID_User INTO v_id_user FROM docente WHERE id = NEW.ID_Docente;
    
    INSERT INTO auditoria (ID_User, Accion, Tabla_afectada, ID_Registro_afectado, Datos_anteriores, Datos_nuevos)
    VALUES (
        v_id_user,
        'UPDATE',
        'calificaciones',
        NEW.id,
        JSON_OBJECT(
            'Nota', OLD.Nota,
            'Estado', OLD.Estado
        ),
        JSON_OBJECT(
            'Nota', NEW.Nota,
            'Estado', NEW.Estado
        )
    );
END
$$
DELIMITER ;

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `comunicados`
--

CREATE TABLE `comunicados` (
  `id` bigint(20) NOT NULL,
  `Titulo` varchar(255) NOT NULL,
  `Contenido` text NOT NULL,
  `Tipo` enum('General','Urgente','Academico','Administrativo','Evento') NOT NULL,
  `Destinatario` enum('Todos','Estudiantes','Padres','Docentes','Administrativos') NOT NULL,
  `ID_Grado` bigint(20) DEFAULT NULL COMMENT 'Si es para un grado específico',
  `Fecha_publicacion` timestamp NOT NULL DEFAULT current_timestamp(),
  `Fecha_vencimiento` date DEFAULT NULL,
  `Adjunto` varchar(500) DEFAULT NULL,
  `Creado_por` bigint(20) NOT NULL,
  `Estado` enum('Borrador','Publicado','Archivado') DEFAULT 'Borrador'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Volcado de datos para la tabla `comunicados`
--

INSERT INTO `comunicados` (`id`, `Titulo`, `Contenido`, `Tipo`, `Destinatario`, `ID_Grado`, `Fecha_publicacion`, `Fecha_vencimiento`, `Adjunto`, `Creado_por`, `Estado`) VALUES
(1, 'Inicio del Año Escolar 2026', 'Estimadas familias, les damos la bienvenida al año escolar 2026. Las clases iniciarán el 1 de febrero. Les recordamos revisar la lista de útiles escolares en nuestra página web.', 'General', 'Todos', NULL, '2026-01-15 13:00:00', '2026-02-01', NULL, 1, 'Publicado'),
(2, 'Reunión de Padres 5to Primaria', 'Se convoca a reunión de padres de familia de 5to de Primaria el día viernes 21 de febrero a las 18:00 hrs. en el Aula 205.', 'Academico', 'Padres', 8, '2026-02-10 14:00:00', '2026-02-21', NULL, 2, 'Publicado'),
(3, 'Jornada Deportiva', 'El próximo sábado 22 de febrero realizaremos nuestra jornada deportiva anual. La participación es obligatoria. Horario: 8:00 - 12:00.', 'Evento', 'Estudiantes', NULL, '2026-02-12 15:00:00', '2026-02-22', NULL, 1, 'Publicado');

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `cursos`
--

CREATE TABLE `cursos` (
  `id` bigint(20) NOT NULL,
  `ID_Asignacion` bigint(20) NOT NULL COMMENT 'FK a asignacion_docente',
  `ID_Periodo` bigint(20) NOT NULL COMMENT 'FK a periodo',
  `ID_Anio_Academico` bigint(20) NOT NULL COMMENT 'FK a anio_academico',
  `Titulo` varchar(255) NOT NULL COMMENT 'Nombre o título de la clase/unidad',
  `Descripcion` text DEFAULT NULL,
  `Tema` varchar(255) DEFAULT NULL COMMENT 'Tema principal de la clase',
  `Fecha_programada` date DEFAULT NULL,
  `Hora_inicio` time DEFAULT NULL,
  `Hora_fin` time DEFAULT NULL,
  `Aula` varchar(100) DEFAULT NULL,
  `Tipo` enum('Teorica','Practica','Laboratorio','Evaluacion','Taller','Visita','Otro') NOT NULL DEFAULT 'Teorica',
  `Estado` enum('Programado','En_curso','Realizado','Cancelado','Postergado') NOT NULL DEFAULT 'Programado',
  `Modalidad` enum('Presencial','Virtual','Hibrido') NOT NULL DEFAULT 'Presencial',
  `Recursos` text DEFAULT NULL COMMENT 'Materiales o recursos necesarios',
  `Objetivos` text DEFAULT NULL,
  `Observaciones` text DEFAULT NULL,
  `Registrado_por` bigint(20) DEFAULT NULL COMMENT 'FK a users',
  `Creado_en` timestamp NOT NULL DEFAULT current_timestamp(),
  `Actualizado_en` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='Clases/unidades programadas por asignación docente';

--
-- Volcado de datos para la tabla `cursos`
--

INSERT INTO `cursos` (`id`, `ID_Asignacion`, `ID_Periodo`, `ID_Anio_Academico`, `Titulo`, `Descripcion`, `Tema`, `Fecha_programada`, `Hora_inicio`, `Hora_fin`, `Aula`, `Tipo`, `Estado`, `Modalidad`, `Recursos`, `Objetivos`, `Observaciones`, `Registrado_por`, `Creado_en`, `Actualizado_en`) VALUES
(1, 1, 1, 1, 'Introducción a Álgebra', 'Primera clase del trimestre: repaso de operaciones básicas y conceptos algebraicos', 'Álgebra elemental', '2026-02-03', '08:00:00', '09:00:00', 'Edificio B - Aula 205', 'Teorica', 'Realizado', 'Presencial', NULL, 'Que el estudiante reconozca y aplique operaciones algebraicas básicas.', NULL, 2, '2026-04-08 21:27:28', '2026-04-08 21:27:28'),
(2, 1, 1, 1, 'Ecuaciones de primer grado', 'Resolución de ecuaciones lineales con una incógnita', 'Ecuaciones lineales', '2026-02-10', '08:00:00', '09:00:00', 'Edificio B - Aula 205', 'Practica', 'Realizado', 'Presencial', NULL, 'Resolver ecuaciones de primer grado aplicando propiedades de igualdad.', NULL, 2, '2026-04-08 21:27:28', '2026-04-08 21:27:28'),
(3, 4, 1, 1, 'Lenguaje: Estructura del texto', 'Comprensión lectora y análisis textual', 'Tipos de texto y estructura', '2026-02-03', '08:00:00', '09:00:00', 'Edificio B - Aula 205', 'Teorica', 'Realizado', 'Presencial', NULL, 'Identificar la estructura de diferentes tipos de texto.', NULL, 3, '2026-04-08 21:27:28', '2026-04-08 21:27:28');

--
-- Disparadores `cursos`
--
DELIMITER $$
CREATE TRIGGER `tr_cursos_delete` BEFORE DELETE ON `cursos` FOR EACH ROW BEGIN
    INSERT INTO auditoria (ID_User, Accion, Tabla_afectada, ID_Registro_afectado, Datos_anteriores)
    VALUES (
        IFNULL(OLD.Registrado_por, 0),
        'DELETE',
        'cursos',
        OLD.id,
        JSON_OBJECT(
            'id',      OLD.id,
            'Titulo',  OLD.Titulo,
            'Estado',  OLD.Estado,
            'Fecha',   OLD.Fecha_programada
        )
    );
END
$$
DELIMITER ;
DELIMITER $$
CREATE TRIGGER `tr_cursos_insert` AFTER INSERT ON `cursos` FOR EACH ROW BEGIN
    INSERT INTO auditoria (ID_User, Accion, Tabla_afectada, ID_Registro_afectado, Datos_nuevos)
    VALUES (
        IFNULL(NEW.Registrado_por, 0),
        'INSERT',
        'cursos',
        NEW.id,
        JSON_OBJECT(
            'id',            NEW.id,
            'ID_Asignacion', NEW.ID_Asignacion,
            'Titulo',        NEW.Titulo,
            'Fecha',         NEW.Fecha_programada,
            'Tipo',          NEW.Tipo,
            'Estado',        NEW.Estado
        )
    );
END
$$
DELIMITER ;
DELIMITER $$
CREATE TRIGGER `tr_cursos_update` AFTER UPDATE ON `cursos` FOR EACH ROW BEGIN
    INSERT INTO auditoria (ID_User, Accion, Tabla_afectada, ID_Registro_afectado, Datos_anteriores, Datos_nuevos)
    VALUES (
        IFNULL(NEW.Registrado_por, 0),
        'UPDATE',
        'cursos',
        NEW.id,
        JSON_OBJECT('Estado', OLD.Estado, 'Titulo', OLD.Titulo, 'Fecha', OLD.Fecha_programada),
        JSON_OBJECT('Estado', NEW.Estado, 'Titulo', NEW.Titulo, 'Fecha', NEW.Fecha_programada)
    );
END
$$
DELIMITER ;

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `docente`
--

CREATE TABLE `docente` (
  `id` bigint(20) NOT NULL,
  `ID_User` bigint(20) NOT NULL,
  `Especialidad` varchar(255) DEFAULT NULL,
  `Titulo_profesional` varchar(255) DEFAULT NULL,
  `Nivel_academico` enum('Bachiller','Licenciatura','Maestría','Doctorado') DEFAULT NULL,
  `Años_experiencia` int(11) DEFAULT NULL,
  `Fecha_ingreso` date DEFAULT NULL,
  `Tipo_contrato` enum('Planta','Temporal','Por_horas') DEFAULT 'Planta',
  `Estado` enum('Activo','Inactivo','Licencia','Retirado') DEFAULT 'Activo',
  `Observaciones` text DEFAULT NULL,
  `Creado_en` timestamp NOT NULL DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Volcado de datos para la tabla `docente`
--

INSERT INTO `docente` (`id`, `ID_User`, `Especialidad`, `Titulo_profesional`, `Nivel_academico`, `Años_experiencia`, `Fecha_ingreso`, `Tipo_contrato`, `Estado`, `Observaciones`, `Creado_en`) VALUES
(1, 2, 'Matemáticas', 'Licenciada en Matemáticas', 'Maestría', 8, '2018-02-01', 'Planta', 'Activo', NULL, '2026-02-15 18:27:25'),
(2, 3, 'Lenguaje y Literatura', 'Licenciado en Literatura', 'Licenciatura', 10, '2016-02-01', 'Planta', 'Activo', NULL, '2026-02-15 18:27:25'),
(3, 4, 'Ciencias Naturales', 'Licenciada en Biología', 'Maestría', 5, '2021-02-01', 'Planta', 'Activo', NULL, '2026-02-15 18:27:25'),
(4, 5, 'Educación Física', 'Licenciado en Educación Física', 'Licenciatura', 7, '2019-02-01', 'Planta', 'Activo', NULL, '2026-02-15 18:27:25'),
(5, 21, 'sistemas', 'sistemas', 'Doctorado', NULL, '2026-02-15', 'Planta', 'Activo', NULL, '2026-02-15 22:11:05');

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `documentos_inscripcion`
--

CREATE TABLE `documentos_inscripcion` (
  `id` bigint(20) NOT NULL,
  `ID_Inscripcion` bigint(20) NOT NULL,
  `Tipo_documento` enum('Certificado_Nacimiento','CI_Estudiante','CI_Tutor','Libreta_Escolar','Certificado_Medico','Fotos','Comprobante_Domicilio','Otro') NOT NULL,
  `Nombre_documento` varchar(255) NOT NULL,
  `Ruta_archivo` varchar(500) DEFAULT NULL,
  `Fecha_subida` timestamp NOT NULL DEFAULT current_timestamp(),
  `Estado` enum('Pendiente','Recibido','Aprobado','Rechazado') DEFAULT 'Pendiente',
  `Observaciones` text DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `estudiante`
--

CREATE TABLE `estudiante` (
  `id` bigint(20) NOT NULL,
  `ID_User` bigint(20) NOT NULL,
  `Codigo_estudiante` varchar(50) DEFAULT NULL COMMENT 'Código único del estudiante',
  `Tipo_sangre` varchar(10) DEFAULT NULL,
  `Alergias` text DEFAULT NULL,
  `Condiciones_medicas` text DEFAULT NULL,
  `Medicamentos` text DEFAULT NULL,
  `Seguro_medico` varchar(255) DEFAULT NULL,
  `Numero_hermanos` int(11) DEFAULT 0,
  `Posicion_hermanos` int(11) DEFAULT NULL COMMENT 'Si es el 1ro, 2do, etc.',
  `Vive_con` varchar(255) DEFAULT NULL COMMENT 'Con quién vive el estudiante',
  `Necesidades_especiales` text DEFAULT NULL,
  `Transporte` enum('Propio','Escolar','Publico','A_pie') DEFAULT NULL,
  `Estado` enum('Activo','Inactivo','Retirado','Graduado','Suspendido') DEFAULT 'Activo',
  `Observaciones` text DEFAULT NULL,
  `Creado_en` timestamp NOT NULL DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Volcado de datos para la tabla `estudiante`
--

INSERT INTO `estudiante` (`id`, `ID_User`, `Codigo_estudiante`, `Tipo_sangre`, `Alergias`, `Condiciones_medicas`, `Medicamentos`, `Seguro_medico`, `Numero_hermanos`, `Posicion_hermanos`, `Vive_con`, `Necesidades_especiales`, `Transporte`, `Estado`, `Observaciones`, `Creado_en`) VALUES
(1, 13, 'EST-2026-001', 'O+', 'Ninguna', 'Ninguna', 'Ninguno', 'Seguro Universal de Salud', 1, 1, 'Ambos padres', NULL, 'Propio', 'Activo', NULL, '2026-02-15 18:27:25'),
(2, 14, 'EST-2026-002', 'O+', 'Ninguna', 'Ninguna', 'Ninguno', 'Seguro Universal de Salud', 1, 2, 'Ambos padres', NULL, 'Propio', 'Activo', NULL, '2026-02-15 18:27:25'),
(3, 15, 'EST-2026-003', 'A+', 'Polen', 'Asma leve', 'Inhalador', 'Seguro Privado', 0, 1, 'Padre', NULL, 'Escolar', 'Activo', NULL, '2026-02-15 18:27:25'),
(4, 16, 'EST-2026-004', 'B+', 'Ninguna', 'Ninguna', 'Ninguno', 'Seguro Privado', 0, 1, 'Ambos padres', NULL, 'Propio', 'Activo', NULL, '2026-02-15 18:27:25'),
(5, 17, 'EST-2026-005', 'AB+', 'Ninguna', 'Ninguna', 'Ninguno', 'Seguro Universal de Salud', 0, 1, 'Ambos padres', NULL, 'Escolar', 'Activo', NULL, '2026-02-15 18:27:25'),
(6, 18, 'EST-2026-006', 'O-', 'Lactosa', 'Ninguna', 'Ninguno', 'Seguro Privado', 0, 1, 'Madre', NULL, 'Propio', 'Activo', NULL, '2026-02-15 18:27:25'),
(7, 19, 'EST-2026-007', 'A+', 'Ninguna', 'Ninguna', 'Ninguno', 'Seguro Universal de Salud', 0, 1, 'Ambos padres', NULL, 'Publico', 'Activo', NULL, '2026-02-15 18:27:25'),
(8, 20, 'EST-2026-008', 'B-', 'Ninguna', 'Ninguna', 'Ninguno', 'Seguro Privado', 0, 1, 'Ambos padres', NULL, 'Propio', 'Activo', NULL, '2026-02-15 18:27:25'),
(10, 23, 'EST-2026-009', 'A+', 'Polen, polvo', 'Asma leve', 'Inhalador salbutamol', 'Seguro Privado Boliviano', 2, 1, 'Ambos padres', NULL, 'Escolar', 'Activo', 'Estudiante nueva inscripción 2026', '2026-03-15 20:30:07'),
(11, 26, 'EST-2026-010', 'O+', 'eqwfe', 'fwfew', 'fewf', 'hcascsa', 2, 2, 'vwdscwe', 'wfe', 'Propio', 'Activo', 'adwdadad', '2026-03-15 21:25:59'),
(12, 28, 'EST-2026-011', '', 'sdvbvca', 'cxasd', 'sfs', '', 1, NULL, '', 'ass', '', 'Activo', 'ASDV', '2026-03-15 22:30:27'),
(13, 30, 'EST-2026-012', 'O-', 'xcvbn', 'f fcgvb', 'hgvhbn', '23456789', 2, 12345678, '23456789', 'fcgvb', 'Escolar', 'Activo', 'xcvbnm,.-\n', '2026-03-15 22:51:10'),
(14, 32, 'EST-2026-013', 'A+', 'cvxc', 'zx', 'zx', 'qawsedrftg', 123, 2, 'zxcvb ', 'X', 'Escolar', 'Activo', 'fghj', '2026-03-18 00:11:39');

--
-- Disparadores `estudiante`
--
DELIMITER $$
CREATE TRIGGER `tr_estudiante_delete` BEFORE DELETE ON `estudiante` FOR EACH ROW BEGIN
    INSERT INTO auditoria (ID_User, Accion, Tabla_afectada, ID_Registro_afectado, Datos_anteriores)
    VALUES (
        OLD.ID_User,
        'DELETE',
        'estudiante',
        OLD.id,
        JSON_OBJECT(
            'id', OLD.id,
            'ID_User', OLD.ID_User,
            'Codigo_estudiante', OLD.Codigo_estudiante,
            'Tipo_sangre', OLD.Tipo_sangre,
            'Estado', OLD.Estado
        )
    );
END
$$
DELIMITER ;
DELIMITER $$
CREATE TRIGGER `tr_estudiante_insert` AFTER INSERT ON `estudiante` FOR EACH ROW BEGIN
    INSERT INTO auditoria (ID_User, Accion, Tabla_afectada, ID_Registro_afectado, Datos_nuevos)
    VALUES (
        NEW.ID_User,
        'INSERT',
        'estudiante',
        NEW.id,
        JSON_OBJECT(
            'id', NEW.id,
            'ID_User', NEW.ID_User,
            'Codigo_estudiante', NEW.Codigo_estudiante,
            'Tipo_sangre', NEW.Tipo_sangre,
            'Estado', NEW.Estado
        )
    );
END
$$
DELIMITER ;
DELIMITER $$
CREATE TRIGGER `tr_estudiante_update` AFTER UPDATE ON `estudiante` FOR EACH ROW BEGIN
    INSERT INTO auditoria (ID_User, Accion, Tabla_afectada, ID_Registro_afectado, Datos_anteriores, Datos_nuevos)
    VALUES (
        NEW.ID_User,
        'UPDATE',
        'estudiante',
        NEW.id,
        JSON_OBJECT(
            'id', OLD.id,
            'Codigo_estudiante', OLD.Codigo_estudiante,
            'Tipo_sangre', OLD.Tipo_sangre,
            'Estado', OLD.Estado
        ),
        JSON_OBJECT(
            'id', NEW.id,
            'Codigo_estudiante', NEW.Codigo_estudiante,
            'Tipo_sangre', NEW.Tipo_sangre,
            'Estado', NEW.Estado
        )
    );
END
$$
DELIMITER ;

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `estudiante_actividad`
--

CREATE TABLE `estudiante_actividad` (
  `id` bigint(20) NOT NULL,
  `ID_Estudiante` bigint(20) NOT NULL,
  `ID_Actividad` bigint(20) NOT NULL,
  `ID_Anio_Academico` bigint(20) NOT NULL,
  `Fecha_inscripcion` timestamp NOT NULL DEFAULT current_timestamp(),
  `Estado` enum('Activo','Retirado','Finalizado') DEFAULT 'Activo'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Volcado de datos para la tabla `estudiante_actividad`
--

INSERT INTO `estudiante_actividad` (`id`, `ID_Estudiante`, `ID_Actividad`, `ID_Anio_Academico`, `Fecha_inscripcion`, `Estado`) VALUES
(1, 1, 1, 1, '2026-02-01 14:00:00', 'Activo'),
(2, 1, 5, 1, '2026-02-01 14:05:00', 'Activo'),
(3, 3, 1, 1, '2026-02-01 14:10:00', 'Activo'),
(4, 5, 3, 1, '2026-02-01 14:15:00', 'Activo'),
(5, 6, 2, 1, '2026-02-01 14:20:00', 'Activo'),
(6, 7, 1, 1, '2026-02-01 14:25:00', 'Activo');

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `estudiante_tutor`
--

CREATE TABLE `estudiante_tutor` (
  `id` bigint(20) NOT NULL,
  `ID_Estudiante` bigint(20) NOT NULL,
  `ID_Padre` bigint(20) DEFAULT NULL,
  `Parentesco` enum('Padre','Madre','Abuelo','Abuela','Tio','Tia','Hermano','Hermana','Tutor_legal','Otro') NOT NULL,
  `Es_responsable_economicamente` tinyint(1) DEFAULT NULL,
  `Es_contacto_emergencia` tinyint(1) DEFAULT 0,
  `Puede_retirar` tinyint(1) DEFAULT 1 COMMENT 'Si puede retirar al estudiante',
  `Vive_con_estudiante` tinyint(1) DEFAULT NULL,
  `Prioridad_contacto` int(11) DEFAULT 1 COMMENT 'Orden de prioridad para contactar (1=primero)',
  `Observaciones` text DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Volcado de datos para la tabla `estudiante_tutor`
--

INSERT INTO `estudiante_tutor` (`id`, `ID_Estudiante`, `ID_Padre`, `Parentesco`, `Es_responsable_economicamente`, `Es_contacto_emergencia`, `Puede_retirar`, `Vive_con_estudiante`, `Prioridad_contacto`, `Observaciones`) VALUES
(1, 1, 1, 'Padre', 1, 1, 1, 1, 1, NULL),
(2, 1, 2, 'Madre', 1, 1, 1, 1, 2, NULL),
(3, 2, 1, 'Padre', 1, 1, 1, 1, 1, NULL),
(4, 2, 2, 'Madre', 1, 1, 1, 1, 2, NULL),
(5, 3, 3, 'Padre', 1, 1, 1, 1, 1, NULL),
(6, 4, 4, 'Madre', 1, 1, 1, 1, 1, NULL),
(7, 5, 5, 'Padre', 1, 1, 1, 1, 1, NULL),
(8, 6, 6, 'Madre', 1, 1, 1, 1, 1, NULL),
(9, 10, 7, 'Padre', 1, 1, 1, 1, 1, NULL),
(10, 10, 8, 'Madre', 1, 1, 1, 1, 2, NULL),
(11, 11, 9, 'Padre', 1, 1, 1, 1, 1, NULL),
(12, 12, 10, 'Tio', 1, 1, 1, 1, 1, NULL),
(13, 13, 11, 'Padre', 1, 1, 1, 1, 1, NULL),
(14, 14, 12, 'Abuelo', 1, 1, 1, 1, 1, NULL);

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `grado`
--

CREATE TABLE `grado` (
  `id` bigint(20) NOT NULL,
  `ID_Nivel_educativo` bigint(20) DEFAULT NULL,
  `Nombre` varchar(100) DEFAULT NULL COMMENT 'Ej: 1ro de Primaria, 4to de Secundaria',
  `Curso` int(11) DEFAULT NULL COMMENT 'Número de curso (1, 2, 3, etc.)',
  `Paralelo` varchar(10) DEFAULT NULL COMMENT 'A, B, C, etc.',
  `Capacidad_maxima` int(11) NOT NULL DEFAULT 30,
  `Capacidad_actual` int(11) DEFAULT 0,
  `Turno` enum('Mañana','Tarde','Noche') DEFAULT 'Mañana',
  `Ubicacion` varchar(255) DEFAULT NULL COMMENT 'Aula o edificio',
  `Estado` enum('Activo','Inactivo','Cerrado') DEFAULT 'Activo',
  `Observaciones` text DEFAULT NULL,
  `Creado_en` timestamp NOT NULL DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Volcado de datos para la tabla `grado`
--

INSERT INTO `grado` (`id`, `ID_Nivel_educativo`, `Nombre`, `Curso`, `Paralelo`, `Capacidad_maxima`, `Capacidad_actual`, `Turno`, `Ubicacion`, `Estado`, `Observaciones`, `Creado_en`) VALUES
(1, 1, 'Inicial 3 años A', 1, 'A', 20, 1, 'Mañana', 'Edificio A - Aula 101', 'Activo', NULL, '2026-02-15 18:27:25'),
(2, 1, 'Inicial 4 años A', 2, 'A', 20, 2, 'Mañana', 'Edificio A - Aula 102', 'Activo', NULL, '2026-02-15 18:27:25'),
(3, 1, 'Inicial 5 años A', 3, 'A', 25, 3, 'Mañana', 'Edificio A - Aula 103', 'Activo', NULL, '2026-02-15 18:27:25'),
(4, 2, '1ro de Primaria A', 1, 'A', 30, 0, 'Mañana', 'Edificio B - Aula 201', 'Activo', NULL, '2026-02-15 18:27:25'),
(5, 2, '2do de Primaria A', 2, 'A', 30, 0, 'Mañana', 'Edificio B - Aula 202', 'Activo', NULL, '2026-02-15 18:27:25'),
(6, 2, '3ro de Primaria A', 3, 'A', 30, 0, 'Mañana', 'Edificio B - Aula 203', 'Activo', NULL, '2026-02-15 18:27:25'),
(7, 2, '4to de Primaria A', 4, 'A', 30, 0, 'Mañana', 'Edificio B - Aula 204', 'Activo', NULL, '2026-02-15 18:27:25'),
(8, 2, '5to de Primaria A', 5, 'A', 30, 3, 'Mañana', 'Edificio B - Aula 205', 'Activo', NULL, '2026-02-15 18:27:25'),
(9, 2, '6to de Primaria A', 6, 'A', 30, 3, 'Mañana', 'Edificio B - Aula 206', 'Activo', NULL, '2026-02-15 18:27:25'),
(10, 3, '1ro de Secundaria A', 1, 'A', 35, 1, 'Mañana', 'Edificio C - Aula 301', 'Activo', NULL, '2026-02-15 18:27:25'),
(11, 3, '2do de Secundaria A', 2, 'A', 35, 0, 'Mañana', 'Edificio C - Aula 302', 'Activo', NULL, '2026-02-15 18:27:25'),
(12, 3, '3ro de Secundaria A', 3, 'A', 35, 0, 'Mañana', 'Edificio C - Aula 303', 'Activo', NULL, '2026-02-15 18:27:25'),
(13, 3, '4to de Secundaria A', 4, 'A', 35, 0, 'Mañana', 'Edificio C - Aula 304', 'Activo', NULL, '2026-02-15 18:27:25'),
(14, 3, '5to de Secundaria A', 5, 'A', 35, 0, 'Mañana', 'Edificio C - Aula 305', 'Activo', NULL, '2026-02-15 18:27:25'),
(15, 3, '6to de Secundaria A', 6, 'A', 35, 0, 'Mañana', 'Edificio C - Aula 306', 'Activo', NULL, '2026-02-15 18:27:25');

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `horarios`
--

CREATE TABLE `horarios` (
  `id` bigint(20) NOT NULL,
  `ID_Asignacion_docente` bigint(20) NOT NULL,
  `Dia_semana` enum('Lunes','Martes','Miércoles','Jueves','Viernes','Sábado') NOT NULL,
  `Hora_inicio` time NOT NULL,
  `Hora_fin` time NOT NULL,
  `Aula` varchar(100) DEFAULT NULL,
  `Observaciones` text DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Volcado de datos para la tabla `horarios`
--

INSERT INTO `horarios` (`id`, `ID_Asignacion_docente`, `Dia_semana`, `Hora_inicio`, `Hora_fin`, `Aula`, `Observaciones`) VALUES
(1, 1, 'Lunes', '08:00:00', '09:00:00', 'Edificio B - Aula 205', NULL),
(2, 1, 'Miércoles', '08:00:00', '09:00:00', 'Edificio B - Aula 205', NULL),
(3, 1, 'Viernes', '08:00:00', '09:00:00', 'Edificio B - Aula 205', NULL),
(4, 2, 'Lunes', '09:00:00', '10:00:00', 'Edificio B - Aula 206', NULL),
(5, 2, 'Miércoles', '09:00:00', '10:00:00', 'Edificio B - Aula 206', NULL),
(6, 2, 'Viernes', '09:00:00', '10:00:00', 'Edificio B - Aula 206', NULL),
(7, 3, 'Martes', '08:00:00', '09:00:00', 'Edificio C - Aula 301', NULL),
(8, 3, 'Jueves', '08:00:00', '09:00:00', 'Edificio C - Aula 301', NULL),
(9, 4, 'Martes', '08:00:00', '09:00:00', 'Edificio B - Aula 205', NULL),
(10, 4, 'Jueves', '08:00:00', '09:00:00', 'Edificio B - Aula 205', NULL),
(11, 5, 'Martes', '09:00:00', '10:00:00', 'Edificio B - Aula 206', NULL),
(12, 5, 'Jueves', '09:00:00', '10:00:00', 'Edificio B - Aula 206', NULL);

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `inscripcion`
--

CREATE TABLE `inscripcion` (
  `id` bigint(20) NOT NULL,
  `ID_Estudiante` bigint(20) NOT NULL,
  `ID_Anio_Academico` bigint(20) NOT NULL,
  `Fecha_solicitud` timestamp NOT NULL DEFAULT current_timestamp(),
  `Fecha_aprobacion` timestamp NULL DEFAULT NULL,
  `Estado` enum('Solicitada','Aprobada','Rechazada','Pendiente_Documentos','Cancelada') DEFAULT 'Solicitada',
  `Tipo_inscripcion` enum('Nueva','Renovacion','Reingreso','Traslado') NOT NULL,
  `Colegio_procedencia` varchar(255) DEFAULT NULL,
  `Motivo_traslado` text DEFAULT NULL,
  `Documentos_completos` tinyint(1) DEFAULT 0,
  `Observaciones` text DEFAULT NULL,
  `Aprobado_por` bigint(20) DEFAULT NULL COMMENT 'ID del usuario que aprobó',
  `Creado_en` timestamp NOT NULL DEFAULT current_timestamp(),
  `Actualizado_en` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Volcado de datos para la tabla `inscripcion`
--

INSERT INTO `inscripcion` (`id`, `ID_Estudiante`, `ID_Anio_Academico`, `Fecha_solicitud`, `Fecha_aprobacion`, `Estado`, `Tipo_inscripcion`, `Colegio_procedencia`, `Motivo_traslado`, `Documentos_completos`, `Observaciones`, `Aprobado_por`, `Creado_en`, `Actualizado_en`) VALUES
(1, 1, 1, '2026-01-10 13:00:00', '2026-01-15 14:30:00', 'Aprobada', 'Renovacion', NULL, NULL, 1, NULL, 1, '2026-02-15 18:27:25', '2026-02-15 18:27:25'),
(2, 2, 1, '2026-01-10 13:30:00', '2026-01-15 14:35:00', 'Aprobada', 'Renovacion', NULL, NULL, 1, NULL, 1, '2026-02-15 18:27:25', '2026-02-15 18:27:25'),
(3, 3, 1, '2026-01-11 14:00:00', '2026-01-16 15:00:00', 'Aprobada', 'Renovacion', NULL, NULL, 1, NULL, 1, '2026-02-15 18:27:25', '2026-02-15 18:27:25'),
(4, 4, 1, '2026-01-11 14:30:00', '2026-01-16 15:05:00', 'Aprobada', 'Renovacion', NULL, NULL, 1, NULL, 1, '2026-02-15 18:27:25', '2026-02-15 18:27:25'),
(5, 5, 1, '2026-01-12 15:00:00', '2026-01-17 16:00:00', 'Aprobada', 'Renovacion', NULL, NULL, 1, NULL, 1, '2026-02-15 18:27:25', '2026-02-15 18:27:25'),
(6, 6, 1, '2026-01-12 15:30:00', '2026-01-17 16:05:00', 'Aprobada', 'Renovacion', NULL, NULL, 1, NULL, 1, '2026-02-15 18:27:25', '2026-02-15 18:27:25'),
(7, 7, 1, '2026-01-13 13:00:00', '2026-01-18 14:00:00', 'Aprobada', 'Renovacion', NULL, NULL, 1, NULL, 1, '2026-02-15 18:27:25', '2026-02-15 18:27:25'),
(8, 8, 1, '2026-01-13 13:30:00', '2026-01-18 14:05:00', 'Aprobada', 'Renovacion', NULL, NULL, 1, NULL, 1, '2026-02-15 18:27:25', '2026-02-15 18:27:25'),
(10, 10, 1, '2026-03-15 20:30:07', '2026-03-15 20:30:07', 'Aprobada', 'Nueva', NULL, NULL, 0, 'Estudiante nueva inscripción 2026', 1, '2026-03-15 20:30:07', '2026-03-15 20:30:07'),
(11, 11, 1, '2026-03-15 21:25:59', '2026-03-15 21:25:59', 'Aprobada', 'Nueva', '', '', 0, 'adwdadad', 1, '2026-03-15 21:25:59', '2026-03-15 21:25:59'),
(12, 12, 1, '2026-03-15 22:30:27', '2026-03-15 22:30:27', 'Aprobada', 'Nueva', '', '', 0, 'ASDV', 1, '2026-03-15 22:30:27', '2026-03-15 22:30:27'),
(13, 13, 1, '2026-03-15 22:51:10', '2026-03-15 22:51:10', 'Aprobada', 'Reingreso', 'sdfgh', '', 0, 'xcvbnm,.-\n', 1, '2026-03-15 22:51:10', '2026-03-15 22:51:10'),
(14, 14, 1, '2026-03-18 00:11:39', '2026-03-18 00:11:39', 'Aprobada', 'Reingreso', '456178', '', 0, 'fghj', 1, '2026-03-18 00:11:39', '2026-03-18 00:11:39');

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `materias`
--

CREATE TABLE `materias` (
  `id` bigint(20) NOT NULL,
  `Codigo` varchar(50) DEFAULT NULL COMMENT 'Código único de la materia',
  `Nombre_de_la_materia` varchar(255) NOT NULL,
  `Descripcion` text DEFAULT NULL,
  `Area_conocimiento` varchar(100) DEFAULT NULL COMMENT 'Ej: Ciencias, Humanidades, Matemáticas',
  `Carga_horaria_semanal` int(11) DEFAULT NULL COMMENT 'Horas por semana',
  `Creditos` int(11) DEFAULT NULL,
  `Es_obligatoria` tinyint(1) DEFAULT 1,
  `Estado` enum('Activo','Inactivo') DEFAULT 'Activo',
  `Creado_en` timestamp NOT NULL DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Volcado de datos para la tabla `materias`
--

INSERT INTO `materias` (`id`, `Codigo`, `Nombre_de_la_materia`, `Descripcion`, `Area_conocimiento`, `Carga_horaria_semanal`, `Creditos`, `Es_obligatoria`, `Estado`, `Creado_en`) VALUES
(1, 'MAT-PRI-01', 'Matemáticas', 'Matemáticas nivel primaria', 'Matemáticas', 6, 6, 1, 'Activo', '2026-02-15 18:27:25'),
(2, 'LEN-PRI-01', 'Lenguaje', 'Lenguaje y comunicación', 'Lenguaje', 6, 6, 1, 'Activo', '2026-02-15 18:27:25'),
(3, 'CN-PRI-01', 'Ciencias Naturales', 'Ciencias de la naturaleza', 'Ciencias', 4, 4, 1, 'Activo', '2026-02-15 18:27:25'),
(4, 'CS-PRI-01', 'Ciencias Sociales', 'Historia y geografía', 'Ciencias Sociales', 4, 4, 1, 'Activo', '2026-02-15 18:27:25'),
(5, 'EF-PRI-01', 'Educación Física', 'Deporte y actividad física', 'Deportes', 3, 3, 1, 'Activo', '2026-02-15 18:27:25'),
(6, 'ART-PRI-01', 'Artes Plásticas', 'Educación artística', 'Arte', 2, 2, 1, 'Activo', '2026-02-15 18:27:25'),
(7, 'MUS-PRI-01', 'Música', 'Educación musical', 'Arte', 2, 2, 1, 'Activo', '2026-02-15 18:27:25'),
(8, 'MAT-SEC-01', 'Matemáticas', 'Matemáticas nivel secundaria', 'Matemáticas', 6, 6, 1, 'Activo', '2026-02-15 18:27:25'),
(9, 'LEN-SEC-01', 'Lengua y Literatura', 'Literatura y comunicación', 'Lenguaje', 5, 5, 1, 'Activo', '2026-02-15 18:27:25'),
(10, 'FIS-SEC-01', 'Física', 'Física general', 'Ciencias', 4, 4, 1, 'Activo', '2026-02-15 18:27:25'),
(11, 'QUI-SEC-01', 'Química', 'Química general', 'Ciencias', 4, 4, 1, 'Activo', '2026-02-15 18:27:25'),
(12, 'BIO-SEC-01', 'Biología', 'Biología general', 'Ciencias', 4, 4, 1, 'Activo', '2026-02-15 18:27:25'),
(13, 'HIS-SEC-01', 'Historia', 'Historia de Bolivia y universal', 'Ciencias Sociales', 3, 3, 1, 'Activo', '2026-02-15 18:27:25'),
(14, 'GEO-SEC-01', 'Geografía', 'Geografía física y humana', 'Ciencias Sociales', 3, 3, 1, 'Activo', '2026-02-15 18:27:25'),
(15, 'ING-SEC-01', 'Inglés', 'Idioma inglés', 'Idiomas', 4, 4, 1, 'Activo', '2026-02-15 18:27:25'),
(16, 'EF-SEC-01', 'Educación Física', 'Deporte y actividad física', 'Deportes', 2, 2, 1, 'Activo', '2026-02-15 18:27:25');

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `materia_grado`
--

CREATE TABLE `materia_grado` (
  `id` bigint(20) NOT NULL,
  `ID_Materia` bigint(20) NOT NULL,
  `ID_Grado` bigint(20) NOT NULL,
  `ID_Anio_Academico` bigint(20) NOT NULL,
  `Es_obligatoria` tinyint(1) DEFAULT 1
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Volcado de datos para la tabla `materia_grado`
--

INSERT INTO `materia_grado` (`id`, `ID_Materia`, `ID_Grado`, `ID_Anio_Academico`, `Es_obligatoria`) VALUES
(1, 1, 8, 1, 1),
(2, 2, 8, 1, 1),
(3, 3, 8, 1, 1),
(4, 4, 8, 1, 1),
(5, 5, 8, 1, 1),
(6, 6, 8, 1, 1),
(7, 7, 8, 1, 1),
(8, 1, 9, 1, 1),
(9, 2, 9, 1, 1),
(10, 3, 9, 1, 1),
(11, 4, 9, 1, 1),
(12, 5, 9, 1, 1),
(13, 6, 9, 1, 1),
(14, 7, 9, 1, 1),
(15, 8, 10, 1, 1),
(16, 9, 10, 1, 1),
(17, 10, 10, 1, 1),
(18, 11, 10, 1, 1),
(19, 12, 10, 1, 1),
(20, 13, 10, 1, 1),
(21, 14, 10, 1, 1),
(22, 15, 10, 1, 1),
(23, 16, 10, 1, 1);

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `matricula`
--

CREATE TABLE `matricula` (
  `id` bigint(20) NOT NULL,
  `ID_Inscripcion` bigint(20) DEFAULT NULL,
  `ID_Estudiante` bigint(20) NOT NULL,
  `ID_Grado` bigint(20) DEFAULT NULL,
  `ID_Anio_Academico` bigint(20) DEFAULT NULL,
  `Numero_matricula` varchar(50) DEFAULT NULL COMMENT 'Número único de matrícula',
  `Fecha_matricula` timestamp NOT NULL DEFAULT current_timestamp(),
  `Monto_matricula` decimal(10,2) DEFAULT NULL,
  `Descuento` decimal(5,2) DEFAULT 0.00 COMMENT 'Porcentaje de descuento',
  `Estado_pago` enum('Pendiente','Pagado_Parcial','Pagado_Completo','Exonerado') DEFAULT 'Pendiente',
  `Estado_matricula` enum('Activa','Inactiva','Retirada','Trasladada','Finalizada') DEFAULT 'Activa',
  `Tipo_estudiante` enum('Regular','Repitente','Traslado','Oyente') DEFAULT 'Regular',
  `Requiere_apoyo` tinyint(1) DEFAULT 0 COMMENT 'Si requiere apoyo académico especial',
  `Observaciones` text DEFAULT NULL,
  `Creado_en` timestamp NOT NULL DEFAULT current_timestamp(),
  `Actualizado_en` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Volcado de datos para la tabla `matricula`
--

INSERT INTO `matricula` (`id`, `ID_Inscripcion`, `ID_Estudiante`, `ID_Grado`, `ID_Anio_Academico`, `Numero_matricula`, `Fecha_matricula`, `Monto_matricula`, `Descuento`, `Estado_pago`, `Estado_matricula`, `Tipo_estudiante`, `Requiere_apoyo`, `Observaciones`, `Creado_en`, `Actualizado_en`) VALUES
(1, 1, 1, 8, 1, 'MAT-2026-001', '2026-01-20 13:00:00', 500.00, 0.00, 'Pagado_Completo', 'Activa', 'Regular', 0, NULL, '2026-02-15 18:27:25', '2026-02-15 18:27:25'),
(2, 2, 2, 3, 1, 'MAT-2026-002', '2026-01-20 13:15:00', 450.00, 10.00, 'Pagado_Completo', 'Activa', 'Regular', 0, NULL, '2026-02-15 18:27:25', '2026-02-15 18:27:25'),
(3, 3, 3, 8, 1, 'MAT-2026-003', '2026-01-20 13:30:00', 500.00, 0.00, 'Pagado_Completo', 'Activa', 'Regular', 0, NULL, '2026-02-15 18:27:25', '2026-02-15 18:27:25'),
(4, 4, 4, 9, 1, 'MAT-2026-004', '2026-01-20 13:45:00', 500.00, 0.00, 'Pagado_Completo', 'Activa', 'Regular', 0, NULL, '2026-02-15 18:27:25', '2026-02-15 18:27:25'),
(5, 5, 5, 10, 1, 'MAT-2026-005', '2026-01-20 14:00:00', 600.00, 0.00, 'Pagado_Completo', 'Activa', 'Regular', 0, NULL, '2026-02-15 18:27:25', '2026-02-15 18:27:25'),
(6, 6, 6, 8, 1, 'MAT-2026-006', '2026-01-20 14:15:00', 500.00, 0.00, 'Pagado_Completo', 'Activa', 'Regular', 0, NULL, '2026-02-15 18:27:25', '2026-02-15 18:27:25'),
(7, 7, 7, 9, 1, 'MAT-2026-007', '2026-01-20 14:30:00', 500.00, 0.00, 'Pagado_Completo', 'Activa', 'Regular', 0, NULL, '2026-02-15 18:27:25', '2026-02-15 18:27:25'),
(8, 8, 8, 3, 1, 'MAT-2026-008', '2026-01-20 14:45:00', 450.00, 0.00, 'Pagado_Completo', 'Activa', 'Regular', 0, NULL, '2026-02-15 18:27:25', '2026-02-15 18:27:25'),
(9, 10, 10, 9, 1, 'MAT-2026-009', '2026-03-15 20:30:07', 500.00, 0.00, 'Pendiente', 'Activa', 'Regular', 0, 'Estudiante nueva inscripción 2026', '2026-03-15 20:30:07', '2026-03-15 20:30:07'),
(10, 11, 11, 1, 1, 'MAT-2026-010', '2026-03-15 21:25:59', 500.00, 50.00, 'Pendiente', 'Activa', 'Regular', 0, 'adwdadad', '2026-03-15 21:25:59', '2026-03-15 21:25:59'),
(11, 12, 12, 2, 1, 'MAT-2026-011', '2026-03-15 22:30:27', 0.00, 0.00, 'Pendiente', 'Activa', 'Regular', 1, 'ASDV', '2026-03-15 22:30:27', '2026-03-15 22:30:27'),
(12, 13, 13, 2, 1, 'MAT-2026-012', '2026-03-15 22:51:10', 1234.00, 5.00, 'Pendiente', 'Activa', 'Repitente', 1, 'xcvbnm,.-\n', '2026-03-15 22:51:10', '2026-03-15 22:51:10'),
(13, 14, 14, 3, 1, 'MAT-2026-013', '2026-03-18 00:11:39', 12.00, 0.00, 'Pendiente', 'Activa', 'Repitente', 0, 'fghj', '2026-03-18 00:11:39', '2026-03-18 00:11:39');

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `nivel_educativo`
--

CREATE TABLE `nivel_educativo` (
  `id` bigint(20) NOT NULL,
  `Nombre` varchar(100) NOT NULL COMMENT 'Ej: Inicial, Primaria, Secundaria',
  `Descripcion` text DEFAULT NULL,
  `Orden` int(11) NOT NULL COMMENT 'Orden de los niveles',
  `Estado` enum('Activo','Inactivo') DEFAULT 'Activo'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Volcado de datos para la tabla `nivel_educativo`
--

INSERT INTO `nivel_educativo` (`id`, `Nombre`, `Descripcion`, `Orden`, `Estado`) VALUES
(1, 'Inicial', 'Educación inicial para niños de 3 a 5 años', 1, 'Activo'),
(2, 'Primaria', 'Educación primaria de 1ro a 6to grado', 2, 'Activo'),
(3, 'Secundaria', 'Educación secundaria de 1ro a 6to año', 3, 'Activo');

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `padre_tutor`
--

CREATE TABLE `padre_tutor` (
  `id` bigint(20) NOT NULL,
  `ID_User` bigint(20) NOT NULL,
  `Genero` varchar(50) DEFAULT NULL,
  `Ocupacion` varchar(255) DEFAULT NULL,
  `Lugar_trabajo` varchar(255) DEFAULT NULL,
  `Telefono_trabajo` varchar(50) DEFAULT NULL,
  `Nivel_educativo` varchar(100) DEFAULT NULL,
  `Ingreso_mensual_aproximado` decimal(10,2) DEFAULT NULL,
  `Estado` enum('Activo','Inactivo') DEFAULT 'Activo',
  `Creado_en` timestamp NOT NULL DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Volcado de datos para la tabla `padre_tutor`
--

INSERT INTO `padre_tutor` (`id`, `ID_User`, `Genero`, `Ocupacion`, `Lugar_trabajo`, `Telefono_trabajo`, `Nivel_educativo`, `Ingreso_mensual_aproximado`, `Estado`, `Creado_en`) VALUES
(1, 7, 'M', 'Ingeniero', 'Empresa Constructora ABC', '22334455', 'Licenciatura', 6500.00, 'Activo', '2026-02-15 18:27:25'),
(2, 8, 'F', 'Contadora', 'Estudio Contable XYZ', '22445566', 'Licenciatura', 5500.00, 'Activo', '2026-02-15 18:27:25'),
(3, 9, 'M', 'Abogado', 'Bufete Legal', '22556677', 'Maestría', 7000.00, 'Activo', '2026-02-15 18:27:25'),
(4, 10, 'F', 'Médica', 'Hospital San Juan', '22667788', 'Doctorado', 8500.00, 'Activo', '2026-02-15 18:27:25'),
(5, 11, 'M', 'Comerciante', 'Negocio Propio', '22778899', 'Bachiller', 5000.00, 'Activo', '2026-02-15 18:27:25'),
(6, 12, 'F', 'Profesora', 'Universidad Mayor', '22889900', 'Maestría', 6000.00, 'Activo', '2026-02-15 18:27:25'),
(7, 24, 'M', 'Médico', 'Hospital Viedma', '44221133', 'Doctorado', 9500.00, 'Activo', '2026-03-15 20:30:07'),
(8, 25, 'F', 'Arquitecta', 'Estudio de Arquitectura BTR', '44332211', 'Licenciatura', 7200.00, 'Activo', '2026-03-15 20:30:07'),
(9, 27, '', 'acasc', 'acsacc', '1313123', 'Doctorado', 99999999.99, 'Activo', '2026-03-15 21:25:59'),
(10, 29, '', '', 'ZVZ', 'ZCZ', 'Secundaria', 1413.00, 'Activo', '2026-03-15 22:30:27'),
(11, 31, '', '', '', '', '', NULL, 'Activo', '2026-03-15 22:51:10'),
(12, 33, '', 'vgbnm', 'dfgh', '34567', 'Licenciatura', 123.00, 'Activo', '2026-03-18 00:11:39');

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `pagos`
--

CREATE TABLE `pagos` (
  `id` bigint(20) NOT NULL,
  `ID_Estudiante` bigint(20) NOT NULL,
  `ID_Anio_Academico` bigint(20) NOT NULL,
  `Concepto` enum('Matricula','Pension','Examen','Materiales','Transporte','Uniforme','Otro') NOT NULL,
  `Mes` int(11) DEFAULT NULL COMMENT 'Mes de la pensión (1-12)',
  `Monto` decimal(10,2) NOT NULL,
  `Descuento` decimal(10,2) DEFAULT 0.00,
  `Monto_pagado` decimal(10,2) DEFAULT 0.00,
  `Saldo` decimal(10,2) DEFAULT NULL,
  `Fecha_vencimiento` date DEFAULT NULL,
  `Fecha_pago` date DEFAULT NULL,
  `Metodo_pago` enum('Efectivo','Transferencia','Cheque','Tarjeta','QR') DEFAULT NULL,
  `Numero_recibo` varchar(100) DEFAULT NULL,
  `Estado` enum('Pendiente','Pagado','Atrasado','Cancelado','Exonerado') DEFAULT 'Pendiente',
  `Observaciones` text DEFAULT NULL,
  `Registrado_por` bigint(20) DEFAULT NULL,
  `Creado_en` timestamp NOT NULL DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Volcado de datos para la tabla `pagos`
--

INSERT INTO `pagos` (`id`, `ID_Estudiante`, `ID_Anio_Academico`, `Concepto`, `Mes`, `Monto`, `Descuento`, `Monto_pagado`, `Saldo`, `Fecha_vencimiento`, `Fecha_pago`, `Metodo_pago`, `Numero_recibo`, `Estado`, `Observaciones`, `Registrado_por`, `Creado_en`) VALUES
(1, 1, 1, 'Matricula', NULL, 500.00, 0.00, 500.00, 0.00, '2026-01-31', '2026-01-20', 'Transferencia', 'REC-2026-001', 'Pagado', NULL, 6, '2026-02-15 18:27:25'),
(2, 1, 1, 'Pension', 2, 350.00, 0.00, 350.00, 0.00, '2026-02-05', '2026-02-03', 'Transferencia', 'REC-2026-010', 'Pagado', NULL, 6, '2026-02-15 18:27:25'),
(3, 1, 1, 'Pension', 3, 350.00, 0.00, 0.00, 350.00, '2026-03-05', NULL, NULL, NULL, 'Pendiente', NULL, 6, '2026-02-15 18:27:25'),
(4, 2, 1, 'Matricula', NULL, 450.00, 50.00, 450.00, 0.00, '2026-01-31', '2026-01-20', 'Transferencia', 'REC-2026-002', 'Pagado', NULL, 6, '2026-02-15 18:27:25'),
(5, 2, 1, 'Pension', 2, 300.00, 50.00, 300.00, 0.00, '2026-02-05', '2026-02-03', 'Transferencia', 'REC-2026-011', 'Pagado', NULL, 6, '2026-02-15 18:27:25'),
(6, 3, 1, 'Matricula', NULL, 500.00, 0.00, 500.00, 0.00, '2026-01-31', '2026-01-21', 'Efectivo', 'REC-2026-003', 'Pagado', NULL, 6, '2026-02-15 18:27:25'),
(7, 3, 1, 'Pension', 2, 350.00, 0.00, 350.00, 0.00, '2026-02-05', '2026-02-04', 'Efectivo', 'REC-2026-012', 'Pagado', NULL, 6, '2026-02-15 18:27:25'),
(8, 4, 1, 'Matricula', NULL, 500.00, 0.00, 500.00, 0.00, '2026-01-31', '2026-01-21', 'QR', 'REC-2026-004', 'Pagado', NULL, 6, '2026-02-15 18:27:25'),
(9, 4, 1, 'Pension', 2, 350.00, 0.00, 350.00, 0.00, '2026-02-05', '2026-02-05', 'QR', 'REC-2026-013', 'Pagado', NULL, 6, '2026-02-15 18:27:25'),
(10, 5, 1, 'Matricula', NULL, 600.00, 0.00, 600.00, 0.00, '2026-01-31', '2026-01-22', 'Transferencia', 'REC-2026-005', 'Pagado', NULL, 6, '2026-02-15 18:27:25'),
(11, 5, 1, 'Pension', 2, 400.00, 0.00, 400.00, 0.00, '2026-02-05', '2026-02-05', 'Transferencia', 'REC-2026-014', 'Pagado', NULL, 6, '2026-02-15 18:27:25');

--
-- Disparadores `pagos`
--
DELIMITER $$
CREATE TRIGGER `tr_auditoria_pagos_delete` BEFORE DELETE ON `pagos` FOR EACH ROW BEGIN
    INSERT INTO auditoria_pagos (
        ID_Pago_original, ID_Estudiante, Concepto,
        Monto_anterior, Monto_nuevo, Estado_anterior, Estado_nuevo,
        Accion, Usuario_accion
    ) VALUES (
        OLD.id, OLD.ID_Estudiante, OLD.Concepto,
        OLD.Monto, NULL, OLD.Estado, NULL,
        'DELETE', IFNULL(OLD.Registrado_por, 0)
    );
END
$$
DELIMITER ;
DELIMITER $$
CREATE TRIGGER `tr_auditoria_pagos_insert` AFTER INSERT ON `pagos` FOR EACH ROW BEGIN
    INSERT INTO auditoria_pagos (
        ID_Pago_original, ID_Estudiante, Concepto,
        Monto_anterior, Monto_nuevo, Estado_anterior, Estado_nuevo,
        Accion, Usuario_accion
    ) VALUES (
        NEW.id, NEW.ID_Estudiante, NEW.Concepto,
        NULL, NEW.Monto, NULL, NEW.Estado,
        'INSERT', IFNULL(NEW.Registrado_por, 0)
    );
END
$$
DELIMITER ;
DELIMITER $$
CREATE TRIGGER `tr_auditoria_pagos_update` AFTER UPDATE ON `pagos` FOR EACH ROW BEGIN
    INSERT INTO auditoria_pagos (
        ID_Pago_original, ID_Estudiante, Concepto,
        Monto_anterior, Monto_nuevo, Estado_anterior, Estado_nuevo,
        Accion, Usuario_accion
    ) VALUES (
        NEW.id, NEW.ID_Estudiante, NEW.Concepto,
        OLD.Monto, NEW.Monto, OLD.Estado, NEW.Estado,
        'UPDATE', IFNULL(NEW.Registrado_por, 0)
    );
END
$$
DELIMITER ;

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `periodo`
--

CREATE TABLE `periodo` (
  `id` bigint(20) NOT NULL,
  `ID_Anio_Academico` bigint(20) DEFAULT NULL,
  `Nombre_periodo` varchar(255) NOT NULL,
  `Numero_periodo` int(11) DEFAULT NULL COMMENT '1, 2, 3, 4',
  `Descripcion` text DEFAULT NULL,
  `Fecha_inicio` date DEFAULT NULL,
  `Fecha_fin` date DEFAULT NULL,
  `Porcentaje_nota` decimal(5,2) DEFAULT NULL COMMENT 'Peso del período en la nota final',
  `Estado` enum('Planificado','En_curso','Finalizado') DEFAULT 'Planificado'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Volcado de datos para la tabla `periodo`
--

INSERT INTO `periodo` (`id`, `ID_Anio_Academico`, `Nombre_periodo`, `Numero_periodo`, `Descripcion`, `Fecha_inicio`, `Fecha_fin`, `Porcentaje_nota`, `Estado`) VALUES
(1, 1, '1er Trimestre 2026', 1, NULL, '2026-02-01', '2026-04-30', 25.00, 'En_curso'),
(2, 1, '2do Trimestre 2026', 2, NULL, '2026-05-01', '2026-07-31', 25.00, 'Planificado'),
(3, 1, '3er Trimestre 2026', 3, NULL, '2026-08-01', '2026-09-30', 25.00, 'Planificado'),
(4, 1, '4to Trimestre 2026', 4, NULL, '2026-10-01', '2026-11-30', 25.00, 'Planificado');

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `permisos`
--

CREATE TABLE `permisos` (
  `id` bigint(20) NOT NULL,
  `Nombre` varchar(100) NOT NULL COMMENT 'Nombre del permiso',
  `Codigo` varchar(50) NOT NULL COMMENT 'Código único del permiso (ej: users.create)',
  `Modulo` varchar(50) DEFAULT NULL COMMENT 'Módulo al que pertenece',
  `Descripcion` text DEFAULT NULL,
  `Estado` enum('Activo','Inactivo') DEFAULT 'Activo',
  `Creado_en` timestamp NOT NULL DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='Catálogo de permisos del sistema';

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `persona`
--

CREATE TABLE `persona` (
  `id` bigint(20) NOT NULL,
  `Nombre` varchar(255) NOT NULL,
  `Apellido` varchar(255) NOT NULL,
  `CI` varchar(50) DEFAULT NULL COMMENT 'Cédula de Identidad o documento de identificación',
  `Fecha_nacimiento` date DEFAULT NULL,
  `Genero` enum('M','F','Otro') DEFAULT NULL,
  `Direccion` varchar(255) DEFAULT NULL,
  `Telefono` varchar(50) DEFAULT NULL,
  `Email_personal` varchar(255) DEFAULT NULL,
  `Foto` varchar(255) DEFAULT NULL COMMENT 'Ruta de la foto de perfil',
  `Estado_civil` varchar(50) DEFAULT NULL,
  `Nacionalidad` varchar(100) DEFAULT 'Boliviana',
  `Creado_en` timestamp NOT NULL DEFAULT current_timestamp(),
  `Actualizado_en` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Volcado de datos para la tabla `persona`
--

INSERT INTO `persona` (`id`, `Nombre`, `Apellido`, `CI`, `Fecha_nacimiento`, `Genero`, `Direccion`, `Telefono`, `Email_personal`, `Foto`, `Estado_civil`, `Nacionalidad`, `Creado_en`, `Actualizado_en`) VALUES
(1, 'Carlos', 'Mendoza', '5123456', '1980-05-15', 'M', 'Av. 6 de Agosto #1234', '71234567', 'carlos.mendoza@gmail.com', NULL, 'Casado', 'Boliviana', '2026-02-15 18:27:25', '2026-02-15 18:27:25'),
(2, 'María', 'Rodríguez', '6234567', '1985-03-20', 'F', 'Calle Comercio #456', '72345678', 'maria.rodriguez@gmail.com', NULL, 'Soltera', 'Boliviana', '2026-02-15 18:27:25', '2026-02-15 18:27:25'),
(3, 'Juan', 'Pérez', '7345678', '1982-07-12', 'M', 'Av. Arce #789', '73456789', 'juan.perez@gmail.com', NULL, 'Casado', 'Boliviana', '2026-02-15 18:27:25', '2026-02-15 18:27:25'),
(4, 'Ana', 'López', '8456789', '1990-11-25', 'F', 'Calle 21 #321', '74567890', 'ana.lopez@gmail.com', NULL, 'Soltera', 'Boliviana', '2026-02-15 18:27:25', '2026-02-15 18:27:25'),
(5, 'Pedro', 'García', '9567890', '1988-09-08', 'M', 'Zona Sur #654', '75678901', 'pedro.garcia@gmail.com', NULL, 'Casado', 'Boliviana', '2026-02-15 18:27:25', '2026-02-15 18:27:25'),
(6, 'Laura', 'Martínez', '1678901', '1992-02-14', 'F', 'Av. Busch #987', '76789012', 'laura.martinez@gmail.com', NULL, 'Soltera', 'Boliviana', '2026-02-15 18:27:25', '2026-02-15 18:27:25'),
(7, 'Roberto', 'Vargas', '2789012', '1975-06-30', 'M', 'Calle Murillo #123', '77890123', 'roberto.vargas@gmail.com', NULL, 'Casado', 'Boliviana', '2026-02-15 18:27:25', '2026-02-15 18:27:25'),
(8, 'Carmen', 'Flores', '3890123', '1978-04-18', 'F', 'Calle Murillo #123', '78901234', 'carmen.flores@gmail.com', NULL, 'Casada', 'Boliviana', '2026-02-15 18:27:25', '2026-02-15 18:27:25'),
(9, 'Miguel', 'Sánchez', '4901234', '1980-08-22', 'M', 'Av. Libertador #456', '79012345', 'miguel.sanchez@gmail.com', NULL, 'Divorciado', 'Boliviana', '2026-02-15 18:27:25', '2026-02-15 18:27:25'),
(10, 'Patricia', 'Rojas', '5012345', '1982-12-05', 'F', 'Calle Potosí #789', '70123456', 'patricia.rojas@gmail.com', NULL, 'Casada', 'Boliviana', '2026-02-15 18:27:25', '2026-02-15 18:27:25'),
(11, 'Fernando', 'Castro', '6123456', '1977-01-15', 'M', 'Zona Norte #321', '71234568', 'fernando.castro@gmail.com', NULL, 'Casado', 'Boliviana', '2026-02-15 18:27:25', '2026-02-15 18:27:25'),
(12, 'Sofía', 'Morales', '7234567', '1983-10-28', 'F', 'Av. del Maestro #654', '72345679', 'sofia.morales@gmail.com', NULL, 'Soltera', 'Boliviana', '2026-02-15 18:27:25', '2026-02-15 18:27:25'),
(13, 'Diego', 'Vargas', '8345678-LP', '2014-03-15', 'M', 'Calle Murillo #123', '77890123', NULL, NULL, NULL, 'Boliviana', '2026-02-15 18:27:25', '2026-02-15 18:27:25'),
(14, 'Valentina', 'Vargas', '9456789-LP', '2016-08-20', 'F', 'Calle Murillo #123', '77890123', NULL, NULL, NULL, 'Boliviana', '2026-02-15 18:27:25', '2026-02-15 18:27:25'),
(15, 'Santiago', 'Sánchez', '1567890-LP', '2015-05-10', 'M', 'Av. Libertador #456', '79012345', NULL, NULL, NULL, 'Boliviana', '2026-02-15 18:27:25', '2026-02-15 18:27:25'),
(16, 'Isabella', 'Rojas', '2678901-LP', '2014-11-30', 'F', 'Calle Potosí #789', '70123456', NULL, NULL, NULL, 'Boliviana', '2026-02-15 18:27:25', '2026-02-15 18:27:25'),
(17, 'Mateo', 'Castro', '3789012-LP', '2013-07-22', 'M', 'Zona Norte #321', '71234568', NULL, NULL, NULL, 'Boliviana', '2026-02-15 18:27:25', '2026-02-15 18:27:25'),
(18, 'Emma', 'Morales', '4890123-LP', '2015-02-14', 'F', 'Av. del Maestro #654', '72345679', NULL, NULL, NULL, 'Boliviana', '2026-02-15 18:27:25', '2026-02-15 18:27:25'),
(19, 'Sebastián', 'Torres', '5901234-LP', '2014-09-05', 'M', 'Calle Sucre #234', '73456780', NULL, NULL, NULL, 'Boliviana', '2026-02-15 18:27:25', '2026-02-15 18:27:25'),
(20, 'Lucía', 'Mendoza', '6012345-LP', '2016-01-18', 'F', 'Av. América #567', '74567891', NULL, NULL, NULL, 'Boliviana', '2026-02-15 18:27:25', '2026-02-15 18:27:25'),
(21, 'Jaziel', 'Vargas', '0288103', '0000-00-00', 'M', 'limanipata', '+591 79532646', 'jazielarmandovargaschoque@gmail.com', 'cscacca', 'cacasc', 'cacscsc', '2026-02-15 22:11:05', '2026-04-04 22:05:09'),
(23, 'Valentina', 'Mamani', '1234567-CB', '2015-03-22', 'F', 'Calle Sucre #345, Cochabamba', '76543210', 'vale.mamani@gmail.com', NULL, NULL, 'Boliviana', '2026-03-15 20:30:07', '2026-03-15 20:30:07'),
(24, 'Jorge', 'Mamani', '4567890', '1978-11-10', 'M', 'Calle Sucre #345, Cochabamba', '71234567', 'jorge.mamani@gmail.com', NULL, 'Casado', 'Boliviana', '2026-03-15 20:30:07', '2026-03-15 20:30:07'),
(25, 'Rosa', 'Torrez', '5678901', '1981-06-25', 'F', 'Calle Sucre #345, Cochabamba', '72345678', 'rosa.torrez@gmail.com', NULL, 'Casada', 'Boliviana', '2026-03-15 20:30:07', '2026-03-15 20:30:07'),
(26, 'Boris', 'Vargas', '1234321234-lp', '2017-02-17', 'M', 'bvcxasdgfdsasdf', '123454321234', 'asdfngfdsderfd', NULL, 'Soltero', 'Boliviana', '2026-03-15 21:25:59', '2026-03-15 21:25:59'),
(27, 'Jaziel', 'asfcasc', 'acsac', '2002-01-30', 'M', 'ascasc', '123321221', 'sdvvadcac', NULL, '', 'Boliviana', '2026-03-15 21:25:59', '2026-03-15 21:25:59'),
(28, 'fghjkl', 'zxcvb', 'sdfghj', '2026-03-04', 'F', 'asdfghj', '12345678', 'xcvbnm,', NULL, '', 'Boliviana', '2026-03-15 22:30:27', '2026-03-15 22:30:27'),
(29, 'ZXC', 'ZXC', 'BVCX', '0000-00-00', 'F', 'SVS', 'ASDF', 'VSVS', NULL, '', 'Boliviana', '2026-03-15 22:30:27', '2026-03-15 22:30:27'),
(30, 'sdfg', 'zxcvbn', '12345678', '0456-03-12', 'M', 'excvbnm,fdxfcgvh', '123456789', 'werctvybnm,kvcgthvbn', NULL, 'Soltero', 'Boliviana', '2026-03-15 22:51:10', '2026-03-15 22:51:10'),
(31, 'asdfbvc', 'bvcxzx', 'zxzxczcac', '0000-00-00', '', '', '', '', NULL, '', 'Boliviana', '2026-03-15 22:51:10', '2026-03-15 22:51:10'),
(32, 'Deybid', 'Choque', '1234', '2026-03-11', 'M', 'asdfgbnm', '12345', 'asdfg', NULL, 'Soltero', 'Boliviana', '2026-03-18 00:11:39', '2026-03-18 00:11:39'),
(33, 'dfghjk', 'fgbhjkl', '2345678', '2026-03-19', 'F', 'cvbn', '345678', 'xcvbnm', NULL, '', 'Boliviana', '2026-03-18 00:11:39', '2026-03-18 00:11:39');

--
-- Disparadores `persona`
--
DELIMITER $$
CREATE TRIGGER `tr_auditoria_personas_delete` BEFORE DELETE ON `persona` FOR EACH ROW BEGIN
    DECLARE v_id_user BIGINT;
    SELECT id INTO v_id_user FROM users WHERE ID_Persona = OLD.id LIMIT 1;
    
    INSERT INTO auditoria_personas (
        ID_Persona_original,
        Datos_completos_anterior,
        Datos_completos_nuevo,
        Accion,
        Usuario_accion
    ) VALUES (
        OLD.id,
        JSON_OBJECT(
            'Nombre', OLD.Nombre,
            'Apellido', OLD.Apellido,
            'CI', OLD.CI,
            'Fecha_nacimiento', OLD.Fecha_nacimiento,
            'Genero', OLD.Genero,
            'Direccion', OLD.Direccion,
            'Telefono', OLD.Telefono,
            'Email_personal', OLD.Email_personal,
            'Nacionalidad', OLD.Nacionalidad
        ),
        NULL,
        'DELETE',
        v_id_user
    );
END
$$
DELIMITER ;
DELIMITER $$
CREATE TRIGGER `tr_auditoria_personas_insert` AFTER INSERT ON `persona` FOR EACH ROW BEGIN
    DECLARE v_id_user BIGINT;
    SELECT id INTO v_id_user FROM users WHERE ID_Persona = NEW.id LIMIT 1;
    
    INSERT INTO auditoria_personas (
        ID_Persona_original, Datos_completos_anterior, Datos_completos_nuevo,
        Accion, Usuario_accion
    ) VALUES (
        NEW.id, NULL,
        JSON_OBJECT(
            'Nombre', NEW.Nombre,
            'Apellido', NEW.Apellido,
            'CI', NEW.CI,
            'Fecha_nacimiento', NEW.Fecha_nacimiento,
            'Genero', NEW.Genero,
            'Direccion', NEW.Direccion,
            'Telefono', NEW.Telefono,
            'Email_personal', NEW.Email_personal,
            'Nacionalidad', NEW.Nacionalidad
        ),
        'INSERT', v_id_user
    );
END
$$
DELIMITER ;
DELIMITER $$
CREATE TRIGGER `tr_auditoria_personas_update` AFTER UPDATE ON `persona` FOR EACH ROW BEGIN
    DECLARE v_id_user BIGINT;
    SELECT id INTO v_id_user FROM users WHERE ID_Persona = NEW.id LIMIT 1;
    
    INSERT INTO auditoria_personas (
        ID_Persona_original, Datos_completos_anterior, Datos_completos_nuevo,
        Accion, Usuario_accion
    ) VALUES (
        NEW.id,
        JSON_OBJECT(
            'Nombre', OLD.Nombre,
            'Apellido', OLD.Apellido,
            'CI', OLD.CI,
            'Fecha_nacimiento', OLD.Fecha_nacimiento,
            'Genero', OLD.Genero,
            'Direccion', OLD.Direccion,
            'Telefono', OLD.Telefono,
            'Email_personal', OLD.Email_personal,
            'Nacionalidad', OLD.Nacionalidad
        ),
        JSON_OBJECT(
            'Nombre', NEW.Nombre,
            'Apellido', NEW.Apellido,
            'CI', NEW.CI,
            'Fecha_nacimiento', NEW.Fecha_nacimiento,
            'Genero', NEW.Genero,
            'Direccion', NEW.Direccion,
            'Telefono', NEW.Telefono,
            'Email_personal', NEW.Email_personal,
            'Nacionalidad', NEW.Nacionalidad
        ),
        'UPDATE', v_id_user
    );
END
$$
DELIMITER ;
DELIMITER $$
CREATE TRIGGER `tr_persona_delete` BEFORE DELETE ON `persona` FOR EACH ROW BEGIN
    DECLARE v_id_user BIGINT;
    
    SELECT id INTO v_id_user FROM users WHERE ID_Persona = OLD.id LIMIT 1;
    
    INSERT INTO auditoria (ID_User, Accion, Tabla_afectada, ID_Registro_afectado, Datos_anteriores)
    VALUES (
        IFNULL(v_id_user, 0),
        'DELETE',
        'persona',
        OLD.id,
        JSON_OBJECT(
            'Nombre', OLD.Nombre,
            'Apellido', OLD.Apellido,
            'CI', OLD.CI,
            'Telefono', OLD.Telefono
        )
    );
END
$$
DELIMITER ;
DELIMITER $$
CREATE TRIGGER `tr_persona_update` AFTER UPDATE ON `persona` FOR EACH ROW BEGIN
    DECLARE v_id_user BIGINT;
    
    -- Obtener ID del usuario relacionado
    SELECT id INTO v_id_user FROM users WHERE ID_Persona = NEW.id LIMIT 1;
    
    INSERT INTO auditoria (ID_User, Accion, Tabla_afectada, ID_Registro_afectado, Datos_anteriores, Datos_nuevos)
    VALUES (
        IFNULL(v_id_user, 0),
        'UPDATE',
        'persona',
        NEW.id,
        JSON_OBJECT(
            'Nombre', OLD.Nombre,
            'Apellido', OLD.Apellido,
            'CI', OLD.CI,
            'Telefono', OLD.Telefono,
            'Direccion', OLD.Direccion
        ),
        JSON_OBJECT(
            'Nombre', NEW.Nombre,
            'Apellido', NEW.Apellido,
            'CI', NEW.CI,
            'Telefono', NEW.Telefono,
            'Direccion', NEW.Direccion
        )
    );
END
$$
DELIMITER ;

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `plantel_administrativo`
--

CREATE TABLE `plantel_administrativo` (
  `id` bigint(20) NOT NULL,
  `ID_User` bigint(20) NOT NULL,
  `Cargo` varchar(100) NOT NULL COMMENT 'Director, Secretaria, Contador, etc.',
  `Departamento` varchar(100) DEFAULT NULL,
  `Tipo_contrato` enum('Planta','Temporal','Por_Servicios') DEFAULT 'Planta',
  `Nivel_acceso` enum('Bajo','Medio','Alto','Total') DEFAULT 'Medio',
  `Fecha_ingreso` date DEFAULT NULL,
  `Fecha_salida` date DEFAULT NULL,
  `Estado` enum('Activo','Inactivo','Licencia','Retirado') DEFAULT 'Activo',
  `Salario` decimal(10,2) DEFAULT NULL,
  `Observaciones` text DEFAULT NULL,
  `Creado_en` timestamp NOT NULL DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Volcado de datos para la tabla `plantel_administrativo`
--

INSERT INTO `plantel_administrativo` (`id`, `ID_User`, `Cargo`, `Departamento`, `Tipo_contrato`, `Nivel_acceso`, `Fecha_ingreso`, `Fecha_salida`, `Estado`, `Salario`, `Observaciones`, `Creado_en`) VALUES
(1, 1, 'Director General', 'Dirección', 'Planta', 'Total', '2020-02-01', NULL, 'Activo', 8500.00, NULL, '2026-02-15 18:27:25'),
(2, 6, 'Secretaria Académica', 'Administración', 'Planta', 'Alto', '2021-03-15', NULL, 'Activo', 4500.00, NULL, '2026-02-15 18:27:25');

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `reportes_buena_conducta`
--

CREATE TABLE `reportes_buena_conducta` (
  `id` bigint(20) NOT NULL,
  `ID_Estudiante` bigint(20) NOT NULL,
  `ID_Reportado_por` bigint(20) NOT NULL COMMENT 'Docente o admin que otorga el reconocimiento',
  `Fecha_conducta` date NOT NULL,
  `Tipo_reconocimiento` enum('Felicitacion','Mencion_honor','Premio_academico','Premio_deportivo','Premio_artistico','Reconocimiento_conducta','Liderazgo','Solidaridad','Participacion_destacada','Otro') NOT NULL DEFAULT 'Felicitacion',
  `Categoria` varchar(100) DEFAULT NULL COMMENT 'Ej: Académico, Deportivo, Artístico, Comunitario',
  `Descripcion` text NOT NULL COMMENT 'Descripción del comportamiento o logro',
  `Acciones_tomadas` text DEFAULT NULL COMMENT 'Certificado, diploma, mención en acto, etc.',
  `Fecha_accion` date DEFAULT NULL,
  `Notificado_padres` tinyint(1) NOT NULL DEFAULT 0,
  `Fecha_notificacion` date DEFAULT NULL,
  `Estado` enum('Registrado','En_proceso','Reconocido','Archivado') NOT NULL DEFAULT 'Registrado',
  `Seguimiento` text DEFAULT NULL,
  `Puntos` int(11) DEFAULT 0 COMMENT 'Sistema de puntos de conducta (opcional)',
  `Creado_en` timestamp NOT NULL DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='Reconocimientos y reportes de buena conducta de estudiantes';

--
-- Volcado de datos para la tabla `reportes_buena_conducta`
--

INSERT INTO `reportes_buena_conducta` (`id`, `ID_Estudiante`, `ID_Reportado_por`, `Fecha_conducta`, `Tipo_reconocimiento`, `Categoria`, `Descripcion`, `Acciones_tomadas`, `Fecha_accion`, `Notificado_padres`, `Fecha_notificacion`, `Estado`, `Seguimiento`, `Puntos`, `Creado_en`) VALUES
(1, 1, 2, '2026-02-10', 'Reconocimiento_conducta', 'Académico', 'Diego Vargas obtuvo el mejor puntaje en el examen parcial de Matemáticas con 100/100.', 'Mención verbal en clase y notificación a padres.', NULL, 1, NULL, 'Reconocido', NULL, 10, '2026-04-08 21:27:28'),
(2, 4, 2, '2026-02-12', 'Participacion_destacada', 'Académico', 'Isabella Rojas participó activamente en la resolución de problemas en pizarra, ayudando a sus compañeros.', NULL, NULL, 0, NULL, 'Registrado', NULL, 5, '2026-04-08 21:27:28'),
(3, 5, 3, '2026-02-05', 'Liderazgo', 'Comunitario', 'Mateo Castro organizó a su grupo en el proyecto de ciencias naturales, demostrando excelente liderazgo.', 'Diploma de reconocimiento al liderazgo estudiantil.', NULL, 1, NULL, 'Reconocido', NULL, 8, '2026-04-08 21:27:28');

--
-- Disparadores `reportes_buena_conducta`
--
DELIMITER $$
CREATE TRIGGER `tr_rbc_insert` AFTER INSERT ON `reportes_buena_conducta` FOR EACH ROW BEGIN
    INSERT INTO auditoria (ID_User, Accion, Tabla_afectada, ID_Registro_afectado, Datos_nuevos)
    VALUES (
        NEW.ID_Reportado_por,
        'INSERT',
        'reportes_buena_conducta',
        NEW.id,
        JSON_OBJECT(
            'id_reporte',       NEW.id,
            'id_estudiante',    NEW.ID_Estudiante,
            'tipo',             NEW.Tipo_reconocimiento,
            'categoria',        NEW.Categoria,
            'fecha',            NEW.Fecha_conducta,
            'puntos',           NEW.Puntos
        )
    );
END
$$
DELIMITER ;
DELIMITER $$
CREATE TRIGGER `tr_rbc_update` AFTER UPDATE ON `reportes_buena_conducta` FOR EACH ROW BEGIN
    INSERT INTO auditoria (ID_User, Accion, Tabla_afectada, ID_Registro_afectado, Datos_anteriores, Datos_nuevos)
    VALUES (
        NEW.ID_Reportado_por,
        'UPDATE',
        'reportes_buena_conducta',
        NEW.id,
        JSON_OBJECT('Estado', OLD.Estado, 'Puntos', OLD.Puntos),
        JSON_OBJECT('Estado', NEW.Estado, 'Puntos', NEW.Puntos)
    );
END
$$
DELIMITER ;

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `reportes_disciplinarios`
--

CREATE TABLE `reportes_disciplinarios` (
  `id` bigint(20) NOT NULL,
  `ID_Estudiante` bigint(20) NOT NULL,
  `ID_Reportado_por` bigint(20) NOT NULL COMMENT 'Usuario que reporta (docente/admin)',
  `Fecha_incidente` date NOT NULL,
  `Tipo_falta` enum('Leve','Moderada','Grave','Muy_grave') NOT NULL,
  `Categoria` varchar(100) DEFAULT NULL COMMENT 'Conducta, Académico, Asistencia, etc.',
  `Descripcion` text NOT NULL,
  `Sancion` text DEFAULT NULL,
  `Fecha_sancion` date DEFAULT NULL,
  `Notificado_padres` tinyint(1) DEFAULT 0,
  `Fecha_notificacion` date DEFAULT NULL,
  `Estado` enum('Abierto','En_proceso','Resuelto','Cerrado') DEFAULT 'Abierto',
  `Seguimiento` text DEFAULT NULL,
  `Creado_en` timestamp NOT NULL DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Volcado de datos para la tabla `reportes_disciplinarios`
--

INSERT INTO `reportes_disciplinarios` (`id`, `ID_Estudiante`, `ID_Reportado_por`, `Fecha_incidente`, `Tipo_falta`, `Categoria`, `Descripcion`, `Sancion`, `Fecha_sancion`, `Notificado_padres`, `Fecha_notificacion`, `Estado`, `Seguimiento`, `Creado_en`) VALUES
(1, 3, 2, '2026-02-06', 'Leve', 'Conducta', 'Llegó tarde a clase sin justificación', 'Llamada de atención verbal', '2026-02-06', 0, NULL, 'En_proceso', ' | 2026-03-15 16:52:47: Se citó a los padres para el día 20 de marzo.', '2026-02-15 18:27:25'),
(2, 7, 3, '2026-02-08', 'Moderada', 'Conducta', 'No presentó tarea en dos ocasiones consecutivas', 'Citación a padres', '2026-02-08', 1, NULL, 'En_proceso', NULL, '2026-02-15 18:27:25'),
(3, 3, 2, '2026-03-15', 'Moderada', 'Conducta', 'Interrumpió la clase reiteradamente.', 'Citación a padres', NULL, 0, NULL, 'En_proceso', ' | 2026-03-16 16:49:04: Se citó a los padres para el día 20 de marzo. | 2026-03-16 16:49:04: Se citó a los padres para el día 20 de marzo. | 2026-03-16 16:57:24: Se citó a los padres para el día 20 de marzo.', '2026-03-15 20:51:26'),
(4, 3, 2, '2026-03-16', 'Moderada', 'Conducta', 'Interrumpió la clase reiteradamente.', 'Citación a padres', NULL, 0, NULL, 'Abierto', NULL, '2026-03-16 21:50:08'),
(5, 3, 2, '2026-03-12', 'Moderada', 'Disciplinaria', 'es pendejo', 'citacion', '2026-03-18', 1, '2026-03-17', 'Abierto', 'pendejos', '2026-03-16 21:59:41');

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `roles`
--

CREATE TABLE `roles` (
  `id` bigint(20) NOT NULL,
  `Nombre` varchar(50) NOT NULL COMMENT 'Nombre del rol',
  `Descripcion` text DEFAULT NULL COMMENT 'Descripción del rol y sus permisos',
  `Nivel_acceso` int(11) DEFAULT 1 COMMENT 'Nivel de acceso (1=bajo, 5=alto)',
  `Estado` enum('Activo','Inactivo') DEFAULT 'Activo',
  `Es_sistema` tinyint(1) DEFAULT 0 COMMENT 'Si es un rol del sistema (no eliminable)',
  `Creado_en` timestamp NOT NULL DEFAULT current_timestamp(),
  `Actualizado_en` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='Catálogo de roles del sistema';

--
-- Volcado de datos para la tabla `roles`
--

INSERT INTO `roles` (`id`, `Nombre`, `Descripcion`, `Nivel_acceso`, `Estado`, `Es_sistema`, `Creado_en`, `Actualizado_en`) VALUES
(1, 'Admin', 'Acceso total al sistema, puede gestionar usuarios y configuraciones', 5, 'Activo', 1, '2026-02-14 23:42:05', '2026-04-21 19:23:54'),
(2, 'Docente', 'Profesor con acceso a gestión académica, calificaciones y asistencias', 3, 'Activo', 1, '2026-02-14 23:42:05', '2026-02-14 23:42:05'),
(3, 'Estudiante', 'Alumno con acceso a visualizar sus calificaciones y horarios', 1, 'Activo', 1, '2026-02-14 23:42:05', '2026-02-14 23:42:05'),
(4, 'Padre_Tutor', 'Padre o tutor con acceso a información de sus hijos', 2, 'Activo', 1, '2026-02-14 23:42:05', '2026-02-14 23:42:05'),
(5, 'Secretaria', 'Personal administrativo con acceso a gestión de matrículas y documentos', 3, 'Activo', 1, '2026-02-14 23:42:05', '2026-02-14 23:42:05'),
(6, 'Director', 'Director con acceso a reportes y gestión general', 4, 'Activo', 1, '2026-02-14 23:42:05', '2026-02-14 23:42:05');

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `rol_permiso`
--

CREATE TABLE `rol_permiso` (
  `id` bigint(20) NOT NULL,
  `ID_Rol` bigint(20) NOT NULL,
  `ID_Permiso` bigint(20) NOT NULL,
  `Creado_en` timestamp NOT NULL DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='Relación entre roles y permisos';

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `users`
--

CREATE TABLE `users` (
  `id` bigint(20) NOT NULL,
  `ID_Persona` bigint(20) NOT NULL,
  `ID_Verificacion` bigint(20) DEFAULT NULL,
  `ID_Rol` bigint(20) NOT NULL,
  `Correo` varchar(255) NOT NULL,
  `Password` varchar(255) NOT NULL COMMENT 'Contraseña hasheada',
  `Estado` enum('Activo','Inactivo','Suspendido','Bloqueado') DEFAULT 'Activo',
  `Ultimo_acceso` timestamp NULL DEFAULT NULL,
  `Intentos_fallidos` int(11) DEFAULT 0,
  `Fecha_de_creacion` timestamp NOT NULL DEFAULT current_timestamp(),
  `Fecha_de_modificacion` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Volcado de datos para la tabla `users`
--

INSERT INTO `users` (`id`, `ID_Persona`, `ID_Verificacion`, `ID_Rol`, `Correo`, `Password`, `Estado`, `Ultimo_acceso`, `Intentos_fallidos`, `Fecha_de_creacion`, `Fecha_de_modificacion`) VALUES
(1, 1, 44, 1, 'admin@colegio.edu.bo', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'Activo', '2026-04-04 21:47:04', 0, '2026-02-15 18:27:25', '2026-04-05 19:40:41'),
(2, 2, 2, 2, 'maria.rodriguez@colegio.edu.bo', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'Activo', '2026-02-15 11:30:00', 0, '2026-02-15 18:27:25', '2026-02-15 18:27:25'),
(3, 3, 3, 2, 'juan.perez@colegio.edu.bo', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'Activo', '2026-02-14 20:45:00', 0, '2026-02-15 18:27:25', '2026-02-15 18:27:25'),
(4, 4, 4, 2, 'ana.lopez@colegio.edu.bo', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'Activo', '2026-02-14 19:20:00', 0, '2026-02-15 18:27:25', '2026-02-15 18:27:25'),
(5, 5, 5, 2, 'pedro.garcia@colegio.edu.bo', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'Activo', '2026-02-13 18:00:00', 0, '2026-02-15 18:27:25', '2026-02-15 18:27:25'),
(6, 6, 6, 5, 'secretaria@colegio.edu.bo', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'Activo', '2026-02-15 12:15:00', 0, '2026-02-15 18:27:25', '2026-02-15 18:27:25'),
(7, 7, 7, 4, 'roberto.vargas@gmail.com', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'Activo', '2026-02-15 00:30:00', 0, '2026-02-15 18:27:25', '2026-02-15 18:27:25'),
(8, 8, 8, 4, 'carmen.flores@gmail.com', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'Activo', '2026-02-13 23:45:00', 0, '2026-02-15 18:27:25', '2026-02-15 18:27:25'),
(9, 9, 9, 4, 'miguel.sanchez@gmail.com', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'Activo', '2026-02-13 01:00:00', 0, '2026-02-15 18:27:25', '2026-02-15 18:27:25'),
(10, 10, 10, 4, 'patricia.rojas@gmail.com', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'Activo', '2026-02-11 22:30:00', 0, '2026-02-15 18:27:25', '2026-02-15 18:27:25'),
(11, 11, 11, 4, 'fernando.castro@gmail.com', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'Activo', '2026-02-11 00:00:00', 0, '2026-02-15 18:27:25', '2026-02-15 18:27:25'),
(12, 12, 12, 4, 'sofia.morales@gmail.com', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'Activo', '2026-02-09 23:15:00', 0, '2026-02-15 18:27:25', '2026-02-15 18:27:25'),
(13, 13, 13, 3, 'diego.vargas@estudiante.colegio.edu.bo', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'Activo', '2026-02-14 21:00:00', 0, '2026-02-15 18:27:25', '2026-02-15 18:27:25'),
(14, 14, 14, 3, 'valentina.vargas@estudiante.colegio.edu.bo', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'Activo', '2026-02-13 20:30:00', 0, '2026-02-15 18:27:25', '2026-02-15 18:27:25'),
(15, 15, 15, 3, 'santiago.sanchez@estudiante.colegio.edu.bo', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'Activo', '2026-02-12 21:15:00', 0, '2026-02-15 18:27:25', '2026-02-15 18:27:25'),
(16, 16, 16, 3, 'isabella.rojas@estudiante.colegio.edu.bo', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'Activo', '2026-02-11 20:45:00', 0, '2026-02-15 18:27:25', '2026-02-15 18:27:25'),
(17, 17, 17, 3, 'mateo.castro@estudiante.colegio.edu.bo', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'Activo', '2026-02-10 21:30:00', 0, '2026-02-15 18:27:25', '2026-02-15 18:27:25'),
(18, 18, 18, 3, 'emma.morales@estudiante.colegio.edu.bo', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'Activo', '2026-02-09 20:00:00', 0, '2026-02-15 18:27:25', '2026-02-15 18:27:25'),
(19, 19, 19, 3, 'sebastian.torres@estudiante.colegio.edu.bo', '$2y$10$COFZ0Ml935KoioAN7ZigguwbrkcW9g.wUDwGUGqUls5NFkslLSnKi', 'Activo', '2026-02-08 21:00:00', 0, '2026-02-15 18:27:25', '2026-03-13 22:14:28'),
(20, 20, 20, 3, 'lucia.mendoza@estudiante.colegio.edu.bo', '$2y$10$8F61dyK53hsszzl1AS1.ouVXd3qtZjaHK5J9st7RZ04Fx7EtiktwO', 'Activo', '2026-02-07 20:30:00', 0, '2026-02-15 18:27:25', '2026-03-13 22:17:14'),
(21, 21, 73, 1, 'jazielarmandovargaschoque@gmail.com', '$2y$10$IrD8GWE5p6jnhbC5.LeXNuh7xIoAFmCJXf8Nht8PkZu0oHXGEMMFO', 'Activo', '2026-04-21 19:52:33', 0, '2026-02-15 22:11:05', '2026-04-21 19:52:33'),
(23, 23, 22, 3, 'valentina.mamani@estudiante.colegio.edu.bo', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'Activo', NULL, 0, '2026-03-15 20:30:07', '2026-03-15 20:30:07'),
(24, 24, 23, 4, 'jorge.mamani@gmail.com', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'Activo', NULL, 0, '2026-03-15 20:30:07', '2026-03-15 20:30:07'),
(25, 25, 24, 4, 'rosa.torrez@gmail.com', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'Activo', NULL, 0, '2026-03-15 20:30:07', '2026-03-15 20:30:07'),
(26, 26, 25, 3, 'xzASDDASACvs', '12345678', 'Activo', NULL, 0, '2026-03-15 21:25:59', '2026-03-15 21:25:59'),
(27, 27, 26, 4, 'qeqeqwe', '123456788', 'Activo', NULL, 0, '2026-03-15 21:25:59', '2026-03-15 21:25:59'),
(28, 28, 27, 3, 'fgh', '9zVp3jjdsGZdvj7', 'Activo', NULL, 0, '2026-03-15 22:30:27', '2026-03-15 22:30:27'),
(29, 29, 28, 4, '1234QAXDFD', '9zVp3jjdsGZdvj7', 'Activo', NULL, 0, '2026-03-15 22:30:27', '2026-03-15 22:30:27'),
(30, 30, 29, 3, 'rxcvbnml,iuytvbj', '9876456789', 'Activo', NULL, 0, '2026-03-15 22:51:10', '2026-03-15 22:51:10'),
(31, 31, 30, 4, 'wedfggfd', '9zVp3jjdsGZdvj7', 'Activo', NULL, 0, '2026-03-15 22:51:10', '2026-03-15 22:51:10'),
(32, 32, 31, 3, 'asdfgbh', '9zVp3jjdsGZdvj7', 'Activo', NULL, 0, '2026-03-18 00:11:39', '2026-03-18 00:11:39'),
(33, 33, 32, 4, 'sdfb', '9zVp3jjdsGZdvj7', 'Activo', NULL, 0, '2026-03-18 00:11:39', '2026-03-18 00:11:39');

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `verificacion`
--

CREATE TABLE `verificacion` (
  `id` bigint(20) NOT NULL,
  `Fecha_verificacion` timestamp NOT NULL DEFAULT current_timestamp(),
  `Tipo` enum('Email','Telefono','Documento','Biometrico') NOT NULL DEFAULT 'Email',
  `Token` varchar(255) DEFAULT NULL,
  `Estado` enum('Pendiente','Verificado','Expirado','Rechazado') DEFAULT 'Pendiente',
  `Fecha_expiracion` timestamp NULL DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Volcado de datos para la tabla `verificacion`
--

INSERT INTO `verificacion` (`id`, `Fecha_verificacion`, `Tipo`, `Token`, `Estado`, `Fecha_expiracion`) VALUES
(1, '2026-01-15 14:00:00', 'Email', 'token123abc', 'Verificado', NULL),
(2, '2026-01-16 15:30:00', 'Email', 'token456def', 'Verificado', NULL),
(3, '2026-01-17 13:15:00', 'Email', 'token789ghi', 'Verificado', NULL),
(4, '2026-01-18 18:20:00', 'Email', 'tokenjkl012', 'Verificado', NULL),
(5, '2026-01-19 20:45:00', 'Email', 'tokenmno345', 'Verificado', NULL),
(6, '2026-01-20 12:30:00', 'Email', 'tokenpqr678', 'Verificado', NULL),
(7, '2026-01-21 17:00:00', 'Email', 'tokenstu901', 'Verificado', NULL),
(8, '2026-01-22 19:30:00', 'Email', 'tokenvwx234', 'Verificado', NULL),
(9, '2026-01-23 14:45:00', 'Email', 'tokenyz567', 'Verificado', NULL),
(10, '2026-01-24 16:00:00', 'Email', 'token890abc', 'Verificado', NULL),
(11, '2026-01-25 13:00:00', 'Email', 'tokendef123', 'Verificado', NULL),
(12, '2026-01-26 15:00:00', 'Email', 'tokenghi456', 'Verificado', NULL),
(13, '2026-01-27 18:00:00', 'Email', 'tokenjkl789', 'Verificado', NULL),
(14, '2026-01-28 20:00:00', 'Email', 'tokenmno012', 'Verificado', NULL),
(15, '2026-01-29 14:30:00', 'Email', 'tokenpqr345', 'Verificado', NULL),
(16, '2026-01-30 17:30:00', 'Email', 'tokenstu678', 'Verificado', NULL),
(17, '2026-01-31 19:00:00', 'Email', 'tokenvwx901', 'Verificado', NULL),
(18, '2026-02-01 12:00:00', 'Email', 'tokenyz234', 'Verificado', NULL),
(19, '2026-02-02 14:00:00', 'Email', 'token567def', 'Verificado', NULL),
(20, '2026-02-03 16:30:00', 'Email', 'token890ghi', 'Verificado', NULL),
(22, '2026-03-15 20:30:07', 'Email', '3f43e30299fd10bba1b6cd4485d63c06-1773606607', 'Pendiente', '2026-03-17 20:30:07'),
(23, '2026-03-15 20:30:07', 'Email', '404e1e0804c6b5b95b67325637569ae7-1773606607', 'Pendiente', '2026-03-17 20:30:07'),
(24, '2026-03-15 20:30:07', 'Email', 'be9618733decfc4cbcc893fbffbba516-1773606607', 'Pendiente', '2026-03-17 20:30:07'),
(25, '2026-03-15 21:25:59', 'Email', '7b0f89a13fbbda52bfeefad640a023ee-1773609959', 'Pendiente', '2026-03-17 21:25:59'),
(26, '2026-03-15 21:25:59', 'Email', '45f4721577b2c9330114029dd600338b-1773609959', 'Pendiente', '2026-03-17 21:25:59'),
(27, '2026-03-15 22:30:27', 'Email', '2aae9659370aed1bdb3374919b88f9c4-1773613827', 'Pendiente', '2026-03-17 22:30:27'),
(28, '2026-03-15 22:30:27', 'Email', '0de8cd6cc09de23647119b6b30fe0608-1773613827', 'Pendiente', '2026-03-17 22:30:27'),
(29, '2026-03-15 22:51:10', 'Email', '59c38ae9bfa03211c1797a6e30cdee9d-1773615070', 'Pendiente', '2026-03-17 22:51:10'),
(30, '2026-03-15 22:51:10', 'Email', '6979b3cbb6b442d1fadf3ed18138b2d9-1773615070', 'Pendiente', '2026-03-17 22:51:10'),
(31, '2026-03-18 00:11:39', 'Email', '4c591b3f5c44d3730fb3d29d3ceed258-1773792699', 'Pendiente', '2026-03-20 00:11:39'),
(32, '2026-03-18 00:11:39', 'Email', '8a3dae3c54defcc6bfda9b567be1b261-1773792699', 'Pendiente', '2026-03-20 00:11:39'),
(33, '2026-04-04 21:02:19', 'Email', '242122|7e5305dbe0cd21f3796597e3146a4794', 'Pendiente', '2026-04-04 21:12:19'),
(34, '2026-04-04 21:03:12', 'Telefono', '624491|f24f62d7db9b842a487ce1eb9b939e2b', 'Pendiente', '2026-04-04 21:13:12'),
(35, '2026-04-04 21:10:19', 'Email', '599233|5a06de3438332a11f814a5cb561925bd', 'Expirado', '2026-04-04 21:20:19'),
(36, '2026-04-04 21:10:34', 'Email', '653059|7209bc5e3d14029d83e2be24343ae9e8', 'Expirado', '2026-04-04 21:20:34'),
(37, '2026-04-04 21:59:13', 'Telefono', '015027|4445cf22529bef8444609d9d69f27afe', 'Pendiente', '2026-04-04 22:09:13'),
(38, '2026-04-05 18:52:35', 'Email', '334835|1cf535eda688ae39cc6111865854f0e9', 'Expirado', '2026-04-05 19:02:35'),
(39, '2026-04-05 19:15:01', 'Email', '340346|65bc9afb427b9ae01862324655a24a74', 'Expirado', '2026-04-05 19:25:01'),
(40, '2026-04-05 19:16:16', 'Email', '726034|438ec75ffdc17f243298381468136937', 'Expirado', '2026-04-05 19:26:16'),
(41, '2026-04-05 19:17:06', 'Email', '367962|a5ff6431b342b8d20fed629b273f115f', 'Expirado', '2026-04-05 19:27:06'),
(42, '2026-04-05 19:33:49', 'Email', '574576|435c69ed68c3a78326316c9b10be91ab', 'Expirado', '2026-04-05 19:43:49'),
(43, '2026-04-05 19:34:13', 'Email', '035010|fbda6bb382b5631151c049c3ecb425f0', 'Expirado', '2026-04-05 19:44:13'),
(44, '2026-04-05 19:40:41', 'Email', '253223|0b959b5e37d790feb87cd9d473ebff3e', 'Pendiente', '2026-04-05 19:50:41'),
(45, '2026-04-05 19:49:25', 'Email', '453233|49c893a49f0eddae581eb7870937ca20', 'Expirado', '2026-04-05 19:59:25'),
(46, '2026-04-05 19:50:06', 'Email', '436272|0e63eb423432c04bc3e361f6e5b55a99', 'Expirado', '2026-04-05 20:00:06'),
(47, '2026-04-05 19:50:30', 'Email', '210077|bcd3effed40bc0cbfa71ae0d2f2368ed', 'Expirado', '2026-04-05 20:00:30'),
(48, '2026-04-05 19:55:23', 'Email', '695588|2082d4d50d98d3f9eb05f6a3ce4d2550', 'Expirado', '2026-04-05 20:05:23'),
(49, '2026-04-05 19:56:18', 'Email', '502005|f21a9bb053f8b5f5d61f49e5ac2830f9', 'Expirado', '2026-04-05 20:06:18'),
(50, '2026-04-05 19:58:01', 'Email', '147869|66b33740ad3c5b4ae112807050090de0', 'Expirado', '2026-04-05 20:08:01'),
(51, '2026-04-05 20:21:13', 'Email', '191005|20a9ba8c97aa6702b7d18ace8611cdf7', 'Expirado', '2026-04-05 20:31:13'),
(52, '2026-04-05 20:27:03', 'Email', '134377|65f36dddb2a0ef79ae0d7f35ac62270c', 'Expirado', '2026-04-05 20:37:03'),
(53, '2026-04-05 20:30:13', 'Email', '407052|e5a856129deead11a62ebf851d9571e5', 'Expirado', '2026-04-05 20:40:13'),
(54, '2026-04-05 20:30:34', 'Email', '835813|55916a3b7197198b89e2ab3a7876cf85', 'Expirado', '2026-04-05 20:40:34'),
(55, '2026-04-05 20:34:49', 'Email', '770295|82d7adf47b7ad92a7a7140ff1213e38c', 'Expirado', '2026-04-05 20:44:49'),
(56, '2026-04-05 20:48:58', 'Email', '489159|1e519fb6be989ffce4e7b8ca67d49d5a', 'Expirado', '2026-04-05 20:58:58'),
(57, '2026-04-05 21:01:17', 'Email', '091601|0d52592898f86a15daa9a30b5b606e9b', 'Expirado', '2026-04-05 21:11:17'),
(58, '2026-04-05 21:11:29', 'Email', '644959|a434bb87657fead274decc71622e0669', 'Expirado', '2026-04-05 21:21:29'),
(59, '2026-04-05 22:12:57', 'Email', '559860|37502124ccffad164cdbe0d2e53dd918', 'Expirado', '2026-04-05 22:22:57'),
(60, '2026-04-05 22:14:19', 'Email', '207105|472abe87ce29474c6a5cb4f8d098b8f3', 'Expirado', '2026-04-05 22:24:19'),
(61, '2026-04-05 22:16:01', 'Email', '206163|d35f8263bab60f68ea8f3ad8548cf04a', 'Expirado', '2026-04-05 22:26:01'),
(62, '2026-04-05 22:17:49', 'Email', '356997|7a309934379dda9edaea9fe29037b546', 'Verificado', '2026-04-05 22:27:00'),
(63, '2026-04-05 22:26:12', 'Email', '226556|3eaa2d1bbc8dc43ff07bbddf5a9e83cf', 'Verificado', '2026-04-05 22:35:45'),
(64, '2026-04-05 22:46:10', 'Email', '759935|acc0b8a1c9f482db54272ca95a9d56ef', 'Verificado', '2026-04-05 22:55:26'),
(65, '2026-04-05 22:56:21', 'Email', '498860|14b4f78b4da6aeef4eeceb94c1580364', 'Verificado', '2026-04-05 23:05:44'),
(66, '2026-04-05 22:58:01', 'Email', '953966|eac320d1382a019de5c5065fc962cc21', 'Verificado', '2026-04-05 23:07:14'),
(67, '2026-04-06 18:25:03', 'Email', '788833|9456c2a7c598cf03b154008240485ad0', 'Expirado', '2026-04-06 18:35:03'),
(68, '2026-04-06 18:43:44', 'Email', '856690|0d8a8ed09b6c48ac3ec4f620b40e20ed', 'Expirado', '2026-04-06 18:53:44'),
(69, '2026-04-06 18:43:53', 'Email', '177607|741910e11dfd1595ecd7d9b410995ff5', 'Expirado', '2026-04-06 18:53:53'),
(70, '2026-04-21 19:21:17', 'Email', '777712|8d6c40c56f78297e1fd8da32c999982c', 'Verificado', '2026-04-21 19:31:00'),
(71, '2026-04-21 19:24:37', 'Email', '173696|8d7d39e294f4294db2945a5ba85a4f84', 'Verificado', '2026-04-21 19:34:22'),
(72, '2026-04-21 19:29:46', 'Email', '300810|a70901d6a1e63a4fb7997f517da526d3', 'Verificado', '2026-04-21 19:39:23'),
(73, '2026-04-21 19:52:33', 'Email', '687153|ed00a177dec4a95d583d4f8994548b37', 'Verificado', '2026-04-21 20:02:10');

-- --------------------------------------------------------

--
-- Estructura Stand-in para la vista `v_anotaciones`
-- (Véase abajo para la vista actual)
--
CREATE TABLE `v_anotaciones` (
`id_reporte` bigint(20)
,`estudiante` varchar(511)
,`codigo_estudiante` varchar(50)
,`grado` varchar(100)
,`paralelo` varchar(10)
,`reportado_por` varchar(511)
,`rol_reporta` varchar(50)
,`fecha_incidente` date
,`tipo_falta` enum('Leve','Moderada','Grave','Muy_grave')
,`categoria` varchar(100)
,`descripcion` text
,`sancion` text
,`fecha_sancion` date
,`notificado_padres` tinyint(1)
,`fecha_notificacion` date
,`estado` enum('Abierto','En_proceso','Resuelto','Cerrado')
,`seguimiento` text
,`fecha_registro` timestamp
);

-- --------------------------------------------------------

--
-- Estructura Stand-in para la vista `v_asistencias_estudiante`
-- (Véase abajo para la vista actual)
--
CREATE TABLE `v_asistencias_estudiante` (
`ID_Asistencia` bigint(20)
,`ID_Estudiante` bigint(20)
,`Codigo_estudiante` varchar(50)
,`Nombre_Estudiante` varchar(511)
,`ID_Materia` bigint(20)
,`Nombre_de_la_materia` varchar(255)
,`Fecha` date
,`Dia_Semana` varchar(9)
,`Estado` enum('Presente','Ausente','Tardanza','Justificado','Permiso')
,`Hora_llegada` time
,`Observaciones` text
,`Justificacion` text
,`Docente_Registro` varchar(511)
,`Fecha_Registro` timestamp
);

-- --------------------------------------------------------

--
-- Estructura Stand-in para la vista `v_balance_conducta_estudiante`
-- (Véase abajo para la vista actual)
--
CREATE TABLE `v_balance_conducta_estudiante` (
`ID_Estudiante` bigint(20)
,`Codigo_estudiante` varchar(50)
,`Nombre_Estudiante` varchar(511)
,`Grado` varchar(100)
,`Paralelo` varchar(10)
,`Total_Reconocimientos` bigint(21)
,`Total_Puntos_Positivos` decimal(32,0)
,`Total_Anotaciones` bigint(21)
,`Faltas_Graves` bigint(21)
,`Balance_Neto` decimal(33,0)
,`Clasificacion_Conducta` varchar(9)
);

-- --------------------------------------------------------

--
-- Estructura Stand-in para la vista `v_buena_conducta`
-- (Véase abajo para la vista actual)
--
CREATE TABLE `v_buena_conducta` (
`ID_Reconocimiento` bigint(20)
,`Estudiante` varchar(511)
,`Codigo_estudiante` varchar(50)
,`Grado` varchar(100)
,`Paralelo` varchar(10)
,`Reconocido_Por` varchar(511)
,`Rol_Reporta` varchar(50)
,`Fecha_conducta` date
,`Tipo_reconocimiento` enum('Felicitacion','Mencion_honor','Premio_academico','Premio_deportivo','Premio_artistico','Reconocimiento_conducta','Liderazgo','Solidaridad','Participacion_destacada','Otro')
,`Categoria` varchar(100)
,`Descripcion` text
,`Acciones_tomadas` text
,`Fecha_accion` date
,`Puntos` int(11)
,`Notificado_padres` tinyint(1)
,`Fecha_notificacion` date
,`Estado` enum('Registrado','En_proceso','Reconocido','Archivado')
,`Seguimiento` text
,`Fecha_Registro` timestamp
);

-- --------------------------------------------------------

--
-- Estructura Stand-in para la vista `v_crear_estudiante`
-- (Véase abajo para la vista actual)
--
CREATE TABLE `v_crear_estudiante` (
`Instrucciones` varchar(34)
,`Nota` varchar(22)
,`Parametros` varchar(331)
);

-- --------------------------------------------------------

--
-- Estructura Stand-in para la vista `v_cursos`
-- (Véase abajo para la vista actual)
--
CREATE TABLE `v_cursos` (
`ID_Curso` bigint(20)
,`Titulo` varchar(255)
,`Tema` varchar(255)
,`Descripcion` text
,`Codigo_Materia` varchar(50)
,`Materia` varchar(255)
,`Area_conocimiento` varchar(100)
,`Grado` varchar(100)
,`Paralelo` varchar(10)
,`Nivel_Educativo` varchar(100)
,`Docente` varchar(511)
,`Especialidad` varchar(255)
,`Periodo` varchar(255)
,`Numero_periodo` int(11)
,`Anio_Academico` int(4)
,`Fecha_programada` date
,`Hora_inicio` time
,`Hora_fin` time
,`Aula` varchar(100)
,`Tipo` enum('Teorica','Practica','Laboratorio','Evaluacion','Taller','Visita','Otro')
,`Modalidad` enum('Presencial','Virtual','Hibrido')
,`Estado` enum('Programado','En_curso','Realizado','Cancelado','Postergado')
,`Recursos` text
,`Objetivos` text
,`Total_Asistencia_Registrada` bigint(21)
,`Total_Presentes` bigint(21)
,`Observaciones` text
,`Registrado_Por` varchar(511)
,`Creado_en` timestamp
,`Actualizado_en` timestamp
);

-- --------------------------------------------------------

--
-- Estructura Stand-in para la vista `v_dashboard_docente`
-- (Véase abajo para la vista actual)
--
CREATE TABLE `v_dashboard_docente` (
`ID_Docente` bigint(20)
,`Nombre_Completo` varchar(511)
,`Materias_Asignadas` bigint(21)
,`Estudiantes_A_Cargo` bigint(21)
,`Calificaciones_Pendientes` bigint(21)
,`Especialidad` varchar(255)
);

-- --------------------------------------------------------

--
-- Estructura Stand-in para la vista `v_dashboard_estudiante`
-- (Véase abajo para la vista actual)
--
CREATE TABLE `v_dashboard_estudiante` (
`ID_Estudiante` bigint(20)
,`Codigo_estudiante` varchar(50)
,`Nombre_Completo` varchar(511)
,`Grado` varchar(100)
,`Paralelo` varchar(10)
,`Promedio_General` decimal(11,2)
,`Asistencias_Mes` bigint(21)
,`Ausencias_Mes` bigint(21)
,`Pagos_Pendientes` bigint(21)
,`Total_Deuda` decimal(32,2)
);

-- --------------------------------------------------------

--
-- Estructura Stand-in para la vista `v_datos_completos_docente`
-- (Véase abajo para la vista actual)
--
CREATE TABLE `v_datos_completos_docente` (
`ID_Docente` bigint(20)
,`Nombre` varchar(255)
,`Apellido` varchar(255)
,`Nombre_Completo` varchar(511)
,`CI` varchar(50)
,`Fecha_nacimiento` date
,`Edad` bigint(21)
,`Genero` enum('M','F','Otro')
,`Direccion` varchar(255)
,`Telefono` varchar(50)
,`Email_personal` varchar(255)
,`Foto` varchar(255)
,`Estado_civil` varchar(50)
,`Nacionalidad` varchar(100)
,`Especialidad` varchar(255)
,`Titulo_profesional` varchar(255)
,`Nivel_academico` enum('Bachiller','Licenciatura','Maestría','Doctorado')
,`Años_experiencia` int(11)
,`Fecha_ingreso` date
,`Años_Servicio` bigint(21)
,`Tipo_contrato` enum('Planta','Temporal','Por_horas')
,`Estado_Docente` enum('Activo','Inactivo','Licencia','Retirado')
,`Observaciones` text
,`Correo` varchar(255)
,`Estado_Usuario` enum('Activo','Inactivo','Suspendido','Bloqueado')
,`Ultimo_acceso` timestamp
,`Rol` varchar(50)
,`Materias_Asignadas` bigint(21)
,`Fecha_Registro` timestamp
);

-- --------------------------------------------------------

--
-- Estructura Stand-in para la vista `v_datos_completos_estudiante`
-- (Véase abajo para la vista actual)
--
CREATE TABLE `v_datos_completos_estudiante` (
`ID_Estudiante` bigint(20)
,`Codigo_estudiante` varchar(50)
,`Estado_Estudiante` enum('Activo','Inactivo','Retirado','Graduado','Suspendido')
,`Nombre` varchar(255)
,`Apellido` varchar(255)
,`Nombre_Completo` varchar(511)
,`CI` varchar(50)
,`Fecha_nacimiento` date
,`Edad` bigint(21)
,`Genero` enum('M','F','Otro')
,`Direccion` varchar(255)
,`Telefono` varchar(50)
,`Email_personal` varchar(255)
,`Foto` varchar(255)
,`Estado_civil` varchar(50)
,`Nacionalidad` varchar(100)
,`Tipo_sangre` varchar(10)
,`Alergias` text
,`Condiciones_medicas` text
,`Medicamentos` text
,`Seguro_medico` varchar(255)
,`Numero_hermanos` int(11)
,`Posicion_hermanos` int(11)
,`Vive_con` varchar(255)
,`Necesidades_especiales` text
,`Transporte` enum('Propio','Escolar','Publico','A_pie')
,`Correo` varchar(255)
,`Estado_Usuario` enum('Activo','Inactivo','Suspendido','Bloqueado')
,`Ultimo_acceso` timestamp
,`Rol` varchar(50)
,`ID_Matricula_Actual` bigint(20)
,`Numero_matricula` varchar(50)
,`Grado_Actual` varchar(100)
,`Paralelo` varchar(10)
,`Turno` enum('Mañana','Tarde','Noche')
,`Nivel_Educativo` varchar(100)
,`Anio_Academico` int(4)
,`Nombre_Anio_Academico` varchar(100)
,`Estado_matricula` enum('Activa','Inactiva','Retirada','Trasladada','Finalizada')
,`Tipo_estudiante` enum('Regular','Repitente','Traslado','Oyente')
,`Requiere_apoyo` tinyint(1)
,`Fecha_Registro` timestamp
);

-- --------------------------------------------------------

--
-- Estructura Stand-in para la vista `v_datos_completos_padre`
-- (Véase abajo para la vista actual)
--
CREATE TABLE `v_datos_completos_padre` (
`ID_Padre` bigint(20)
,`Nombre` varchar(255)
,`Apellido` varchar(255)
,`Nombre_Completo` varchar(511)
,`CI` varchar(50)
,`Fecha_nacimiento` date
,`Edad` bigint(21)
,`Genero_Persona` enum('M','F','Otro')
,`Direccion` varchar(255)
,`Telefono` varchar(50)
,`Email_personal` varchar(255)
,`Foto` varchar(255)
,`Estado_civil` varchar(50)
,`Nacionalidad` varchar(100)
,`Genero_Padre` varchar(50)
,`Ocupacion` varchar(255)
,`Lugar_trabajo` varchar(255)
,`Telefono_trabajo` varchar(50)
,`Nivel_educativo` varchar(100)
,`Ingreso_mensual_aproximado` decimal(10,2)
,`Estado_Padre` enum('Activo','Inactivo')
,`Correo` varchar(255)
,`Estado_Usuario` enum('Activo','Inactivo','Suspendido','Bloqueado')
,`Ultimo_acceso` timestamp
,`Rol` varchar(50)
,`Cantidad_Estudiantes_Cargo` bigint(21)
,`Fecha_Registro` timestamp
);

-- --------------------------------------------------------

--
-- Estructura Stand-in para la vista `v_estudiantes_por_grado`
-- (Véase abajo para la vista actual)
--
CREATE TABLE `v_estudiantes_por_grado` (
`ID_Grado` bigint(20)
,`Grado` varchar(100)
,`Paralelo` varchar(10)
,`Turno` enum('Mañana','Tarde','Noche')
,`Nivel_Educativo` varchar(100)
,`Anio_Academico` int(4)
,`ID_Estudiante` bigint(20)
,`Codigo_estudiante` varchar(50)
,`Nombre_Estudiante` varchar(511)
,`CI` varchar(50)
,`Telefono` varchar(50)
,`Estado_matricula` enum('Activa','Inactiva','Retirada','Trasladada','Finalizada')
,`Tipo_estudiante` enum('Regular','Repitente','Traslado','Oyente')
);

-- --------------------------------------------------------

--
-- Estructura Stand-in para la vista `v_estudiantes_por_tutor`
-- (Véase abajo para la vista actual)
--
CREATE TABLE `v_estudiantes_por_tutor` (
`ID_Padre` bigint(20)
,`Nombre_Tutor` varchar(511)
,`ID_Estudiante` bigint(20)
,`Codigo_estudiante` varchar(50)
,`Nombre_Estudiante` varchar(511)
,`Grado` varchar(100)
,`Paralelo` varchar(10)
,`Parentesco` enum('Padre','Madre','Abuelo','Abuela','Tio','Tia','Hermano','Hermana','Tutor_legal','Otro')
,`Es_contacto_emergencia` tinyint(1)
,`Promedio_Estudiante` decimal(11,2)
,`Pagos_Pendientes_Estudiante` bigint(21)
);

-- --------------------------------------------------------

--
-- Estructura Stand-in para la vista `v_estudiante_tutores`
-- (Véase abajo para la vista actual)
--
CREATE TABLE `v_estudiante_tutores` (
`ID_Estudiante` bigint(20)
,`Codigo_estudiante` varchar(50)
,`Nombre_Estudiante` varchar(511)
,`Parentesco` enum('Padre','Madre','Abuelo','Abuela','Tio','Tia','Hermano','Hermana','Tutor_legal','Otro')
,`ID_Padre` bigint(20)
,`Nombre_Tutor` varchar(511)
,`CI_Tutor` varchar(50)
,`Telefono_Tutor` varchar(50)
,`Email_Tutor` varchar(255)
,`Ocupacion` varchar(255)
,`Lugar_trabajo` varchar(255)
,`Telefono_trabajo` varchar(50)
,`Es_responsable_economicamente` tinyint(1)
,`Es_contacto_emergencia` tinyint(1)
,`Puede_retirar` tinyint(1)
,`Vive_con_estudiante` tinyint(1)
,`Prioridad_contacto` int(11)
);

-- --------------------------------------------------------

--
-- Estructura Stand-in para la vista `v_horario_estudiante`
-- (Véase abajo para la vista actual)
--
CREATE TABLE `v_horario_estudiante` (
`ID_Estudiante` bigint(20)
,`Codigo_estudiante` varchar(50)
,`Nombre_Estudiante` varchar(511)
,`Nombre_de_la_materia` varchar(255)
,`Dia_semana` enum('Lunes','Martes','Miércoles','Jueves','Viernes','Sábado')
,`Hora_inicio` time
,`Hora_fin` time
,`Aula` varchar(100)
,`Nombre_Docente` varchar(511)
,`Grado` varchar(100)
,`Paralelo` varchar(10)
);

-- --------------------------------------------------------

--
-- Estructura Stand-in para la vista `v_lista_docentes`
-- (Véase abajo para la vista actual)
--
CREATE TABLE `v_lista_docentes` (
`id` bigint(20)
,`Nombre_Completo` varchar(511)
,`CI` varchar(50)
,`Telefono` varchar(50)
,`Especialidad` varchar(255)
,`Estado` enum('Activo','Inactivo','Licencia','Retirado')
,`Materias_Activas` bigint(21)
);

-- --------------------------------------------------------

--
-- Estructura Stand-in para la vista `v_lista_estudiantes`
-- (Véase abajo para la vista actual)
--
CREATE TABLE `v_lista_estudiantes` (
`id` bigint(20)
,`Codigo_estudiante` varchar(50)
,`Nombre_Completo` varchar(511)
,`CI` varchar(50)
,`Telefono` varchar(50)
,`Grado` varchar(100)
,`Paralelo` varchar(10)
,`Estado` enum('Activo','Inactivo','Retirado','Graduado','Suspendido')
);

-- --------------------------------------------------------

--
-- Estructura Stand-in para la vista `v_notas_estudiante`
-- (Véase abajo para la vista actual)
--
CREATE TABLE `v_notas_estudiante` (
`ID_Calificacion` bigint(20)
,`ID_Estudiante` bigint(20)
,`Codigo_estudiante` varchar(50)
,`Nombre_Estudiante` varchar(511)
,`ID_Materia` bigint(20)
,`Codigo_Materia` varchar(50)
,`Nombre_de_la_materia` varchar(255)
,`Area_conocimiento` varchar(100)
,`ID_Periodo` bigint(20)
,`Nombre_periodo` varchar(255)
,`Numero_periodo` int(11)
,`ID_Anio_Academico` bigint(20)
,`Anio_Academico` int(4)
,`Nombre_Anio` varchar(100)
,`Grado` varchar(100)
,`Paralelo` varchar(10)
,`Nota` decimal(5,2)
,`Nota_maxima` decimal(5,2)
,`Porcentaje` decimal(11,2)
,`Porcentaje_peso` decimal(5,2)
,`Tipo_evaluacion` enum('Examen','Tarea','Proyecto','Participacion','Practica','Promedio_Periodo','Nota_Final')
,`Descripcion` varchar(255)
,`Fecha_evaluacion` date
,`Estado_Calificacion` enum('Borrador','Publicada','Modificada','Anulada')
,`Observaciones` text
,`Nombre_Docente` varchar(511)
,`Estado_Aprobacion` varchar(13)
,`Fecha_registro` timestamp
,`Actualizado_en` timestamp
);

-- --------------------------------------------------------

--
-- Estructura Stand-in para la vista `v_pagos_pendientes`
-- (Véase abajo para la vista actual)
--
CREATE TABLE `v_pagos_pendientes` (
`ID_Pago` bigint(20)
,`Codigo_estudiante` varchar(50)
,`Nombre_Estudiante` varchar(511)
,`Grado` varchar(100)
,`Concepto` enum('Matricula','Pension','Examen','Materiales','Transporte','Uniforme','Otro')
,`Mes` int(11)
,`Monto` decimal(10,2)
,`Descuento` decimal(10,2)
,`Monto_pagado` decimal(10,2)
,`Saldo` decimal(10,2)
,`Fecha_vencimiento` date
,`Dias_Vencido` int(7)
,`Estado` enum('Pendiente','Pagado','Atrasado','Cancelado','Exonerado')
,`Anio_Academico` int(4)
);

-- --------------------------------------------------------

--
-- Estructura Stand-in para la vista `v_promedio_estudiante_materia`
-- (Véase abajo para la vista actual)
--
CREATE TABLE `v_promedio_estudiante_materia` (
`ID_Estudiante` bigint(20)
,`Codigo_estudiante` varchar(50)
,`Nombre_Estudiante` varchar(511)
,`ID_Materia` bigint(20)
,`Nombre_de_la_materia` varchar(255)
,`ID_Periodo` bigint(20)
,`Nombre_periodo` varchar(255)
,`ID_Anio_Academico` bigint(20)
,`Anio_Academico` int(4)
,`Total_Evaluaciones` bigint(21)
,`Promedio_Notas` decimal(6,2)
,`Promedio_Porcentaje` decimal(11,2)
,`Nota_Maxima_Obtenida` decimal(5,2)
,`Nota_Minima_Obtenida` decimal(5,2)
,`Estado` varchar(9)
);

-- --------------------------------------------------------

--
-- Estructura Stand-in para la vista `v_rendimiento_estudiante`
-- (Véase abajo para la vista actual)
--
CREATE TABLE `v_rendimiento_estudiante` (
`ID_Estudiante` bigint(20)
,`Codigo_estudiante` varchar(50)
,`Nombre_Estudiante` varchar(511)
,`ID_Anio_Academico` bigint(20)
,`Anio_Academico` int(4)
,`Grado` varchar(100)
,`Paralelo` varchar(10)
,`Total_Materias` bigint(21)
,`Total_Evaluaciones` bigint(21)
,`Promedio_General` decimal(11,2)
,`Evaluaciones_Excelente` decimal(22,0)
,`Evaluaciones_Muy_Bueno` decimal(22,0)
,`Evaluaciones_Bueno` decimal(22,0)
,`Evaluaciones_Suficiente` decimal(22,0)
,`Evaluaciones_Insuficiente` decimal(22,0)
,`Porcentaje_Aprobacion` decimal(28,2)
,`Clasificacion_Rendimiento` varchar(12)
);

-- --------------------------------------------------------

--
-- Estructura Stand-in para la vista `v_reporte_financiero`
-- (Véase abajo para la vista actual)
--
CREATE TABLE `v_reporte_financiero` (
`Anio_Academico` int(4)
,`Total_Estudiantes_Con_Pagos` bigint(21)
,`Total_Ingresos` decimal(32,2)
,`Total_Pendiente` decimal(32,2)
,`Ingresos_Matricula` decimal(32,2)
,`Ingresos_Pension` decimal(32,2)
,`Ingresos_Otros` decimal(32,2)
,`Pagos_Atrasados` bigint(21)
);

-- --------------------------------------------------------

--
-- Estructura Stand-in para la vista `v_resumen_asistencias_estudiante`
-- (Véase abajo para la vista actual)
--
CREATE TABLE `v_resumen_asistencias_estudiante` (
`ID_Estudiante` bigint(20)
,`Codigo_estudiante` varchar(50)
,`Nombre_Estudiante` varchar(511)
,`Anio` int(4)
,`Mes` int(2)
,`Total_Registros` bigint(21)
,`Total_Presentes` decimal(22,0)
,`Total_Ausentes` decimal(22,0)
,`Total_Tardanzas` decimal(22,0)
,`Total_Justificados` decimal(22,0)
,`Total_Permisos` decimal(22,0)
,`Porcentaje_Asistencia` decimal(28,2)
,`Porcentaje_Ausencias` decimal(28,2)
);

-- --------------------------------------------------------

--
-- Estructura para la vista `v_anotaciones`
--
DROP TABLE IF EXISTS `v_anotaciones`;

CREATE ALGORITHM=UNDEFINED DEFINER=`root`@`localhost` SQL SECURITY DEFINER VIEW `v_anotaciones`  AS SELECT `rd`.`id` AS `id_reporte`, concat(`pe`.`Nombre`,' ',`pe`.`Apellido`) AS `estudiante`, `e`.`Codigo_estudiante` AS `codigo_estudiante`, `g`.`Nombre` AS `grado`, `g`.`Paralelo` AS `paralelo`, concat(`pr`.`Nombre`,' ',`pr`.`Apellido`) AS `reportado_por`, `ro`.`Nombre` AS `rol_reporta`, `rd`.`Fecha_incidente` AS `fecha_incidente`, `rd`.`Tipo_falta` AS `tipo_falta`, `rd`.`Categoria` AS `categoria`, `rd`.`Descripcion` AS `descripcion`, `rd`.`Sancion` AS `sancion`, `rd`.`Fecha_sancion` AS `fecha_sancion`, `rd`.`Notificado_padres` AS `notificado_padres`, `rd`.`Fecha_notificacion` AS `fecha_notificacion`, `rd`.`Estado` AS `estado`, `rd`.`Seguimiento` AS `seguimiento`, `rd`.`Creado_en` AS `fecha_registro` FROM ((((((((`reportes_disciplinarios` `rd` join `estudiante` `e` on(`rd`.`ID_Estudiante` = `e`.`id`)) join `users` `ue` on(`e`.`ID_User` = `ue`.`id`)) join `persona` `pe` on(`ue`.`ID_Persona` = `pe`.`id`)) join `users` `ur` on(`rd`.`ID_Reportado_por` = `ur`.`id`)) join `persona` `pr` on(`ur`.`ID_Persona` = `pr`.`id`)) join `roles` `ro` on(`ur`.`ID_Rol` = `ro`.`id`)) left join `matricula` `m` on(`e`.`id` = `m`.`ID_Estudiante` and `m`.`Estado_matricula` = 'Activa')) left join `grado` `g` on(`m`.`ID_Grado` = `g`.`id`)) ORDER BY `rd`.`Creado_en` DESC ;

-- --------------------------------------------------------

--
-- Estructura para la vista `v_asistencias_estudiante`
--
DROP TABLE IF EXISTS `v_asistencias_estudiante`;

CREATE ALGORITHM=UNDEFINED DEFINER=`root`@`localhost` SQL SECURITY DEFINER VIEW `v_asistencias_estudiante`  AS SELECT `a`.`id` AS `ID_Asistencia`, `e`.`id` AS `ID_Estudiante`, `e`.`Codigo_estudiante` AS `Codigo_estudiante`, concat(`p`.`Nombre`,' ',`p`.`Apellido`) AS `Nombre_Estudiante`, `m`.`id` AS `ID_Materia`, `m`.`Nombre_de_la_materia` AS `Nombre_de_la_materia`, `a`.`Fecha` AS `Fecha`, dayname(`a`.`Fecha`) AS `Dia_Semana`, `a`.`Estado` AS `Estado`, `a`.`Hora_llegada` AS `Hora_llegada`, `a`.`Observaciones` AS `Observaciones`, `a`.`Justificacion` AS `Justificacion`, concat(`pd`.`Nombre`,' ',`pd`.`Apellido`) AS `Docente_Registro`, `a`.`Creado_en` AS `Fecha_Registro` FROM (((((((`asistencias` `a` join `estudiante` `e` on(`a`.`ID_Estudiante` = `e`.`id`)) join `users` `ue` on(`e`.`ID_User` = `ue`.`id`)) join `persona` `p` on(`ue`.`ID_Persona` = `p`.`id`)) left join `materias` `m` on(`a`.`ID_Materia` = `m`.`id`)) left join `docente` `d` on(`a`.`ID_Docente` = `d`.`id`)) left join `users` `ud` on(`d`.`ID_User` = `ud`.`id`)) left join `persona` `pd` on(`ud`.`ID_Persona` = `pd`.`id`)) ORDER BY `a`.`Fecha` DESC ;

-- --------------------------------------------------------

--
-- Estructura para la vista `v_balance_conducta_estudiante`
--
DROP TABLE IF EXISTS `v_balance_conducta_estudiante`;

CREATE ALGORITHM=UNDEFINED DEFINER=`` SQL SECURITY DEFINER VIEW `v_balance_conducta_estudiante`  AS SELECT `e`.`id` AS `ID_Estudiante`, `e`.`Codigo_estudiante` AS `Codigo_estudiante`, concat(`p`.`Nombre`,' ',`p`.`Apellido`) AS `Nombre_Estudiante`, `g`.`Nombre` AS `Grado`, `g`.`Paralelo` AS `Paralelo`, (select count(0) from `reportes_buena_conducta` `rbc` where `rbc`.`ID_Estudiante` = `e`.`id`) AS `Total_Reconocimientos`, (select ifnull(sum(`reportes_buena_conducta`.`Puntos`),0) from `reportes_buena_conducta` where `reportes_buena_conducta`.`ID_Estudiante` = `e`.`id`) AS `Total_Puntos_Positivos`, (select count(0) from `reportes_disciplinarios` `rd` where `rd`.`ID_Estudiante` = `e`.`id`) AS `Total_Anotaciones`, (select count(0) from `reportes_disciplinarios` `rd` where `rd`.`ID_Estudiante` = `e`.`id` and `rd`.`Tipo_falta` in ('Grave','Muy_grave')) AS `Faltas_Graves`, (select ifnull(sum(`reportes_buena_conducta`.`Puntos`),0) from `reportes_buena_conducta` where `reportes_buena_conducta`.`ID_Estudiante` = `e`.`id`) - (select count(0) * 5 from `reportes_disciplinarios` `rd` where `rd`.`ID_Estudiante` = `e`.`id` and `rd`.`Tipo_falta` in ('Grave','Muy_grave')) AS `Balance_Neto`, CASE WHEN (select count(0) from `reportes_disciplinarios` where `reportes_disciplinarios`.`ID_Estudiante` = `e`.`id` AND `reportes_disciplinarios`.`Estado` in ('Abierto','En_proceso') AND `reportes_disciplinarios`.`Tipo_falta` in ('Grave','Muy_grave')) > 0 THEN 'Crítico' WHEN (select count(0) from `reportes_disciplinarios` where `reportes_disciplinarios`.`ID_Estudiante` = `e`.`id` AND `reportes_disciplinarios`.`Estado` in ('Abierto','En_proceso')) > 3 THEN 'Atención' WHEN (select count(0) from `reportes_buena_conducta` where `reportes_buena_conducta`.`ID_Estudiante` = `e`.`id`) > 2 THEN 'Destacado' ELSE 'Normal' END AS `Clasificacion_Conducta` FROM ((((`estudiante` `e` join `users` `u` on(`e`.`ID_User` = `u`.`id`)) join `persona` `p` on(`u`.`ID_Persona` = `p`.`id`)) left join `matricula` `m` on(`e`.`id` = `m`.`ID_Estudiante` and `m`.`Estado_matricula` = 'Activa')) left join `grado` `g` on(`m`.`ID_Grado` = `g`.`id`)) WHERE `e`.`Estado` = 'Activo' ;

-- --------------------------------------------------------

--
-- Estructura para la vista `v_buena_conducta`
--
DROP TABLE IF EXISTS `v_buena_conducta`;

CREATE ALGORITHM=UNDEFINED DEFINER=`` SQL SECURITY DEFINER VIEW `v_buena_conducta`  AS SELECT `rbc`.`id` AS `ID_Reconocimiento`, concat(`pe`.`Nombre`,' ',`pe`.`Apellido`) AS `Estudiante`, `e`.`Codigo_estudiante` AS `Codigo_estudiante`, `g`.`Nombre` AS `Grado`, `g`.`Paralelo` AS `Paralelo`, concat(`pr`.`Nombre`,' ',`pr`.`Apellido`) AS `Reconocido_Por`, `ro`.`Nombre` AS `Rol_Reporta`, `rbc`.`Fecha_conducta` AS `Fecha_conducta`, `rbc`.`Tipo_reconocimiento` AS `Tipo_reconocimiento`, `rbc`.`Categoria` AS `Categoria`, `rbc`.`Descripcion` AS `Descripcion`, `rbc`.`Acciones_tomadas` AS `Acciones_tomadas`, `rbc`.`Fecha_accion` AS `Fecha_accion`, `rbc`.`Puntos` AS `Puntos`, `rbc`.`Notificado_padres` AS `Notificado_padres`, `rbc`.`Fecha_notificacion` AS `Fecha_notificacion`, `rbc`.`Estado` AS `Estado`, `rbc`.`Seguimiento` AS `Seguimiento`, `rbc`.`Creado_en` AS `Fecha_Registro` FROM ((((((((`reportes_buena_conducta` `rbc` join `estudiante` `e` on(`rbc`.`ID_Estudiante` = `e`.`id`)) join `users` `ue` on(`e`.`ID_User` = `ue`.`id`)) join `persona` `pe` on(`ue`.`ID_Persona` = `pe`.`id`)) join `users` `ur` on(`rbc`.`ID_Reportado_por` = `ur`.`id`)) join `persona` `pr` on(`ur`.`ID_Persona` = `pr`.`id`)) join `roles` `ro` on(`ur`.`ID_Rol` = `ro`.`id`)) left join `matricula` `m` on(`e`.`id` = `m`.`ID_Estudiante` and `m`.`Estado_matricula` = 'Activa')) left join `grado` `g` on(`m`.`ID_Grado` = `g`.`id`)) ORDER BY `rbc`.`Fecha_conducta` DESC ;

-- --------------------------------------------------------

--
-- Estructura para la vista `v_crear_estudiante`
--
DROP TABLE IF EXISTS `v_crear_estudiante`;

CREATE ALGORITHM=UNDEFINED DEFINER=`root`@`localhost` SQL SECURITY DEFINER VIEW `v_crear_estudiante`  AS SELECT 'USE_PROCEDURE: sp_crear_estudiante' AS `Instrucciones`, 'Parámetros requeridos:' AS `Nota`, 'p_nombre, p_apellido, p_ci, p_fecha_nacimiento, p_genero, p_direccion, p_telefono, \r\n     p_email_personal, p_correo, p_password, p_tipo_sangre, p_alergias, p_condiciones_medicas,\r\n     p_medicamentos, p_seguro_medico, p_numero_hermanos, p_posicion_hermanos, p_vive_con,\r\n     p_necesidades_especiales, p_transporte, p_nacionalidad' AS `Parametros` ;

-- --------------------------------------------------------

--
-- Estructura para la vista `v_cursos`
--
DROP TABLE IF EXISTS `v_cursos`;

CREATE ALGORITHM=UNDEFINED DEFINER=`` SQL SECURITY DEFINER VIEW `v_cursos`  AS SELECT `c`.`id` AS `ID_Curso`, `c`.`Titulo` AS `Titulo`, `c`.`Tema` AS `Tema`, `c`.`Descripcion` AS `Descripcion`, `mat`.`Codigo` AS `Codigo_Materia`, `mat`.`Nombre_de_la_materia` AS `Materia`, `mat`.`Area_conocimiento` AS `Area_conocimiento`, `g`.`Nombre` AS `Grado`, `g`.`Paralelo` AS `Paralelo`, `ne`.`Nombre` AS `Nivel_Educativo`, concat(`pd`.`Nombre`,' ',`pd`.`Apellido`) AS `Docente`, `d`.`Especialidad` AS `Especialidad`, `per`.`Nombre_periodo` AS `Periodo`, `per`.`Numero_periodo` AS `Numero_periodo`, `aa`.`Anio` AS `Anio_Academico`, `c`.`Fecha_programada` AS `Fecha_programada`, `c`.`Hora_inicio` AS `Hora_inicio`, `c`.`Hora_fin` AS `Hora_fin`, `c`.`Aula` AS `Aula`, `c`.`Tipo` AS `Tipo`, `c`.`Modalidad` AS `Modalidad`, `c`.`Estado` AS `Estado`, `c`.`Recursos` AS `Recursos`, `c`.`Objetivos` AS `Objetivos`, (select count(0) from `asistencia_curso` `ac` where `ac`.`ID_Curso` = `c`.`id`) AS `Total_Asistencia_Registrada`, (select count(0) from `asistencia_curso` `ac` where `ac`.`ID_Curso` = `c`.`id` and `ac`.`Estado` = 'Presente') AS `Total_Presentes`, `c`.`Observaciones` AS `Observaciones`, concat(`pu`.`Nombre`,' ',`pu`.`Apellido`) AS `Registrado_Por`, `c`.`Creado_en` AS `Creado_en`, `c`.`Actualizado_en` AS `Actualizado_en` FROM (((((((((((`cursos` `c` join `asignacion_docente` `ad` on(`c`.`ID_Asignacion` = `ad`.`id`)) join `materias` `mat` on(`ad`.`ID_Materia` = `mat`.`id`)) join `grado` `g` on(`ad`.`ID_Grado` = `g`.`id`)) join `nivel_educativo` `ne` on(`g`.`ID_Nivel_educativo` = `ne`.`id`)) join `docente` `d` on(`ad`.`ID_Docente` = `d`.`id`)) join `users` `ud` on(`d`.`ID_User` = `ud`.`id`)) join `persona` `pd` on(`ud`.`ID_Persona` = `pd`.`id`)) join `periodo` `per` on(`c`.`ID_Periodo` = `per`.`id`)) join `anio_academico` `aa` on(`c`.`ID_Anio_Academico` = `aa`.`id`)) left join `users` `ur` on(`c`.`Registrado_por` = `ur`.`id`)) left join `persona` `pu` on(`ur`.`ID_Persona` = `pu`.`id`)) ORDER BY `c`.`Fecha_programada` DESC, `c`.`Hora_inicio` ASC ;

-- --------------------------------------------------------

--
-- Estructura para la vista `v_dashboard_docente`
--
DROP TABLE IF EXISTS `v_dashboard_docente`;

CREATE ALGORITHM=UNDEFINED DEFINER=`root`@`localhost` SQL SECURITY DEFINER VIEW `v_dashboard_docente`  AS SELECT `d`.`id` AS `ID_Docente`, concat(`p`.`Nombre`,' ',`p`.`Apellido`) AS `Nombre_Completo`, (select count(0) from `asignacion_docente` `ad` where `ad`.`ID_Docente` = `d`.`id` and `ad`.`Estado` = 'Activo' and `ad`.`ID_Anio_Academico` = (select `anio_academico`.`id` from `anio_academico` where `anio_academico`.`Es_actual` = 1 limit 1)) AS `Materias_Asignadas`, (select count(distinct `m`.`ID_Estudiante`) from (`asignacion_docente` `ad` join `matricula` `m` on(`ad`.`ID_Grado` = `m`.`ID_Grado`)) where `ad`.`ID_Docente` = `d`.`id` and `ad`.`Estado` = 'Activo' and `m`.`Estado_matricula` = 'Activa') AS `Estudiantes_A_Cargo`, (select count(0) from `calificaciones` `c` where `c`.`ID_Docente` = `d`.`id` and `c`.`Estado` = 'Borrador') AS `Calificaciones_Pendientes`, `d`.`Especialidad` AS `Especialidad` FROM ((`docente` `d` join `users` `u` on(`d`.`ID_User` = `u`.`id`)) join `persona` `p` on(`u`.`ID_Persona` = `p`.`id`)) WHERE `d`.`Estado` = 'Activo' ;

-- --------------------------------------------------------

--
-- Estructura para la vista `v_dashboard_estudiante`
--
DROP TABLE IF EXISTS `v_dashboard_estudiante`;

CREATE ALGORITHM=UNDEFINED DEFINER=`root`@`localhost` SQL SECURITY DEFINER VIEW `v_dashboard_estudiante`  AS SELECT `e`.`id` AS `ID_Estudiante`, `e`.`Codigo_estudiante` AS `Codigo_estudiante`, concat(`p`.`Nombre`,' ',`p`.`Apellido`) AS `Nombre_Completo`, `g`.`Nombre` AS `Grado`, `g`.`Paralelo` AS `Paralelo`, (select round(avg(`c`.`Nota` / `c`.`Nota_maxima` * 100),2) from `calificaciones` `c` where `c`.`ID_Estudiante` = `e`.`id` and `c`.`ID_Anio_Academico` = (select `anio_academico`.`id` from `anio_academico` where `anio_academico`.`Es_actual` = 1 limit 1) and `c`.`Estado` in ('Publicada','Modificada')) AS `Promedio_General`, (select count(0) from `asistencias` `a` where `a`.`ID_Estudiante` = `e`.`id` and `a`.`Estado` = 'Presente' and month(`a`.`Fecha`) = month(curdate()) and year(`a`.`Fecha`) = year(curdate())) AS `Asistencias_Mes`, (select count(0) from `asistencias` `a` where `a`.`ID_Estudiante` = `e`.`id` and `a`.`Estado` = 'Ausente' and month(`a`.`Fecha`) = month(curdate()) and year(`a`.`Fecha`) = year(curdate())) AS `Ausencias_Mes`, (select count(0) from `pagos` `pg` where `pg`.`ID_Estudiante` = `e`.`id` and `pg`.`Estado` in ('Pendiente','Atrasado')) AS `Pagos_Pendientes`, (select ifnull(sum(`pg`.`Saldo`),0) from `pagos` `pg` where `pg`.`ID_Estudiante` = `e`.`id` and `pg`.`Estado` in ('Pendiente','Atrasado')) AS `Total_Deuda` FROM ((((`estudiante` `e` join `users` `u` on(`e`.`ID_User` = `u`.`id`)) join `persona` `p` on(`u`.`ID_Persona` = `p`.`id`)) left join `matricula` `m` on(`e`.`id` = `m`.`ID_Estudiante` and `m`.`Estado_matricula` = 'Activa')) left join `grado` `g` on(`m`.`ID_Grado` = `g`.`id`)) WHERE `e`.`Estado` = 'Activo' ;

-- --------------------------------------------------------

--
-- Estructura para la vista `v_datos_completos_docente`
--
DROP TABLE IF EXISTS `v_datos_completos_docente`;

CREATE ALGORITHM=UNDEFINED DEFINER=`root`@`localhost` SQL SECURITY DEFINER VIEW `v_datos_completos_docente`  AS SELECT `d`.`id` AS `ID_Docente`, `p`.`Nombre` AS `Nombre`, `p`.`Apellido` AS `Apellido`, concat(`p`.`Nombre`,' ',`p`.`Apellido`) AS `Nombre_Completo`, `p`.`CI` AS `CI`, `p`.`Fecha_nacimiento` AS `Fecha_nacimiento`, timestampdiff(YEAR,`p`.`Fecha_nacimiento`,curdate()) AS `Edad`, `p`.`Genero` AS `Genero`, `p`.`Direccion` AS `Direccion`, `p`.`Telefono` AS `Telefono`, `p`.`Email_personal` AS `Email_personal`, `p`.`Foto` AS `Foto`, `p`.`Estado_civil` AS `Estado_civil`, `p`.`Nacionalidad` AS `Nacionalidad`, `d`.`Especialidad` AS `Especialidad`, `d`.`Titulo_profesional` AS `Titulo_profesional`, `d`.`Nivel_academico` AS `Nivel_academico`, `d`.`Años_experiencia` AS `Años_experiencia`, `d`.`Fecha_ingreso` AS `Fecha_ingreso`, timestampdiff(YEAR,`d`.`Fecha_ingreso`,curdate()) AS `Años_Servicio`, `d`.`Tipo_contrato` AS `Tipo_contrato`, `d`.`Estado` AS `Estado_Docente`, `d`.`Observaciones` AS `Observaciones`, `u`.`Correo` AS `Correo`, `u`.`Estado` AS `Estado_Usuario`, `u`.`Ultimo_acceso` AS `Ultimo_acceso`, `r`.`Nombre` AS `Rol`, (select count(0) from `asignacion_docente` where `asignacion_docente`.`ID_Docente` = `d`.`id` and `asignacion_docente`.`Estado` = 'Activo') AS `Materias_Asignadas`, `d`.`Creado_en` AS `Fecha_Registro` FROM (((`docente` `d` join `users` `u` on(`d`.`ID_User` = `u`.`id`)) join `persona` `p` on(`u`.`ID_Persona` = `p`.`id`)) join `roles` `r` on(`u`.`ID_Rol` = `r`.`id`)) ;

-- --------------------------------------------------------

--
-- Estructura para la vista `v_datos_completos_estudiante`
--
DROP TABLE IF EXISTS `v_datos_completos_estudiante`;

CREATE ALGORITHM=UNDEFINED DEFINER=`root`@`localhost` SQL SECURITY DEFINER VIEW `v_datos_completos_estudiante`  AS SELECT `e`.`id` AS `ID_Estudiante`, `e`.`Codigo_estudiante` AS `Codigo_estudiante`, `e`.`Estado` AS `Estado_Estudiante`, `p`.`Nombre` AS `Nombre`, `p`.`Apellido` AS `Apellido`, concat(`p`.`Nombre`,' ',`p`.`Apellido`) AS `Nombre_Completo`, `p`.`CI` AS `CI`, `p`.`Fecha_nacimiento` AS `Fecha_nacimiento`, timestampdiff(YEAR,`p`.`Fecha_nacimiento`,curdate()) AS `Edad`, `p`.`Genero` AS `Genero`, `p`.`Direccion` AS `Direccion`, `p`.`Telefono` AS `Telefono`, `p`.`Email_personal` AS `Email_personal`, `p`.`Foto` AS `Foto`, `p`.`Estado_civil` AS `Estado_civil`, `p`.`Nacionalidad` AS `Nacionalidad`, `e`.`Tipo_sangre` AS `Tipo_sangre`, `e`.`Alergias` AS `Alergias`, `e`.`Condiciones_medicas` AS `Condiciones_medicas`, `e`.`Medicamentos` AS `Medicamentos`, `e`.`Seguro_medico` AS `Seguro_medico`, `e`.`Numero_hermanos` AS `Numero_hermanos`, `e`.`Posicion_hermanos` AS `Posicion_hermanos`, `e`.`Vive_con` AS `Vive_con`, `e`.`Necesidades_especiales` AS `Necesidades_especiales`, `e`.`Transporte` AS `Transporte`, `u`.`Correo` AS `Correo`, `u`.`Estado` AS `Estado_Usuario`, `u`.`Ultimo_acceso` AS `Ultimo_acceso`, `r`.`Nombre` AS `Rol`, `m`.`id` AS `ID_Matricula_Actual`, `m`.`Numero_matricula` AS `Numero_matricula`, `g`.`Nombre` AS `Grado_Actual`, `g`.`Paralelo` AS `Paralelo`, `g`.`Turno` AS `Turno`, `ne`.`Nombre` AS `Nivel_Educativo`, `aa`.`Anio` AS `Anio_Academico`, `aa`.`Nombre` AS `Nombre_Anio_Academico`, `m`.`Estado_matricula` AS `Estado_matricula`, `m`.`Tipo_estudiante` AS `Tipo_estudiante`, `m`.`Requiere_apoyo` AS `Requiere_apoyo`, `e`.`Creado_en` AS `Fecha_Registro` FROM (((((((`estudiante` `e` join `users` `u` on(`e`.`ID_User` = `u`.`id`)) join `persona` `p` on(`u`.`ID_Persona` = `p`.`id`)) join `roles` `r` on(`u`.`ID_Rol` = `r`.`id`)) left join `matricula` `m` on(`e`.`id` = `m`.`ID_Estudiante` and `m`.`Estado_matricula` = 'Activa' and `m`.`ID_Anio_Academico` = (select `anio_academico`.`id` from `anio_academico` where `anio_academico`.`Es_actual` = 1 limit 1))) left join `grado` `g` on(`m`.`ID_Grado` = `g`.`id`)) left join `nivel_educativo` `ne` on(`g`.`ID_Nivel_educativo` = `ne`.`id`)) left join `anio_academico` `aa` on(`m`.`ID_Anio_Academico` = `aa`.`id`)) ;

-- --------------------------------------------------------

--
-- Estructura para la vista `v_datos_completos_padre`
--
DROP TABLE IF EXISTS `v_datos_completos_padre`;

CREATE ALGORITHM=UNDEFINED DEFINER=`root`@`localhost` SQL SECURITY DEFINER VIEW `v_datos_completos_padre`  AS SELECT `pt`.`id` AS `ID_Padre`, `p`.`Nombre` AS `Nombre`, `p`.`Apellido` AS `Apellido`, concat(`p`.`Nombre`,' ',`p`.`Apellido`) AS `Nombre_Completo`, `p`.`CI` AS `CI`, `p`.`Fecha_nacimiento` AS `Fecha_nacimiento`, timestampdiff(YEAR,`p`.`Fecha_nacimiento`,curdate()) AS `Edad`, `p`.`Genero` AS `Genero_Persona`, `p`.`Direccion` AS `Direccion`, `p`.`Telefono` AS `Telefono`, `p`.`Email_personal` AS `Email_personal`, `p`.`Foto` AS `Foto`, `p`.`Estado_civil` AS `Estado_civil`, `p`.`Nacionalidad` AS `Nacionalidad`, `pt`.`Genero` AS `Genero_Padre`, `pt`.`Ocupacion` AS `Ocupacion`, `pt`.`Lugar_trabajo` AS `Lugar_trabajo`, `pt`.`Telefono_trabajo` AS `Telefono_trabajo`, `pt`.`Nivel_educativo` AS `Nivel_educativo`, `pt`.`Ingreso_mensual_aproximado` AS `Ingreso_mensual_aproximado`, `pt`.`Estado` AS `Estado_Padre`, `u`.`Correo` AS `Correo`, `u`.`Estado` AS `Estado_Usuario`, `u`.`Ultimo_acceso` AS `Ultimo_acceso`, `r`.`Nombre` AS `Rol`, (select count(0) from `estudiante_tutor` where `estudiante_tutor`.`ID_Padre` = `pt`.`id`) AS `Cantidad_Estudiantes_Cargo`, `pt`.`Creado_en` AS `Fecha_Registro` FROM (((`padre_tutor` `pt` join `users` `u` on(`pt`.`ID_User` = `u`.`id`)) join `persona` `p` on(`u`.`ID_Persona` = `p`.`id`)) join `roles` `r` on(`u`.`ID_Rol` = `r`.`id`)) ;

-- --------------------------------------------------------

--
-- Estructura para la vista `v_estudiantes_por_grado`
--
DROP TABLE IF EXISTS `v_estudiantes_por_grado`;

CREATE ALGORITHM=UNDEFINED DEFINER=`root`@`localhost` SQL SECURITY DEFINER VIEW `v_estudiantes_por_grado`  AS SELECT `g`.`id` AS `ID_Grado`, `g`.`Nombre` AS `Grado`, `g`.`Paralelo` AS `Paralelo`, `g`.`Turno` AS `Turno`, `ne`.`Nombre` AS `Nivel_Educativo`, `aa`.`Anio` AS `Anio_Academico`, `e`.`id` AS `ID_Estudiante`, `e`.`Codigo_estudiante` AS `Codigo_estudiante`, concat(`p`.`Nombre`,' ',`p`.`Apellido`) AS `Nombre_Estudiante`, `p`.`CI` AS `CI`, `p`.`Telefono` AS `Telefono`, `m`.`Estado_matricula` AS `Estado_matricula`, `m`.`Tipo_estudiante` AS `Tipo_estudiante` FROM ((((((`grado` `g` join `nivel_educativo` `ne` on(`g`.`ID_Nivel_educativo` = `ne`.`id`)) join `matricula` `m` on(`g`.`id` = `m`.`ID_Grado`)) join `anio_academico` `aa` on(`m`.`ID_Anio_Academico` = `aa`.`id`)) join `estudiante` `e` on(`m`.`ID_Estudiante` = `e`.`id`)) join `users` `u` on(`e`.`ID_User` = `u`.`id`)) join `persona` `p` on(`u`.`ID_Persona` = `p`.`id`)) WHERE `m`.`Estado_matricula` = 'Activa' ORDER BY `g`.`Nombre` ASC, `g`.`Paralelo` ASC, `p`.`Apellido` ASC, `p`.`Nombre` ASC ;

-- --------------------------------------------------------

--
-- Estructura para la vista `v_estudiantes_por_tutor`
--
DROP TABLE IF EXISTS `v_estudiantes_por_tutor`;

CREATE ALGORITHM=UNDEFINED DEFINER=`root`@`localhost` SQL SECURITY DEFINER VIEW `v_estudiantes_por_tutor`  AS SELECT `pt`.`id` AS `ID_Padre`, concat(`pp`.`Nombre`,' ',`pp`.`Apellido`) AS `Nombre_Tutor`, `e`.`id` AS `ID_Estudiante`, `e`.`Codigo_estudiante` AS `Codigo_estudiante`, concat(`pe`.`Nombre`,' ',`pe`.`Apellido`) AS `Nombre_Estudiante`, `g`.`Nombre` AS `Grado`, `g`.`Paralelo` AS `Paralelo`, `et`.`Parentesco` AS `Parentesco`, `et`.`Es_contacto_emergencia` AS `Es_contacto_emergencia`, (select round(avg(`c`.`Nota` / `c`.`Nota_maxima` * 100),2) from `calificaciones` `c` where `c`.`ID_Estudiante` = `e`.`id` and `c`.`ID_Anio_Academico` = (select `anio_academico`.`id` from `anio_academico` where `anio_academico`.`Es_actual` = 1 limit 1) and `c`.`Estado` in ('Publicada','Modificada')) AS `Promedio_Estudiante`, (select count(0) from `pagos` `pg` where `pg`.`ID_Estudiante` = `e`.`id` and `pg`.`Estado` in ('Pendiente','Atrasado')) AS `Pagos_Pendientes_Estudiante` FROM ((((((((`padre_tutor` `pt` join `users` `up` on(`pt`.`ID_User` = `up`.`id`)) join `persona` `pp` on(`up`.`ID_Persona` = `pp`.`id`)) join `estudiante_tutor` `et` on(`pt`.`id` = `et`.`ID_Padre`)) join `estudiante` `e` on(`et`.`ID_Estudiante` = `e`.`id`)) join `users` `ue` on(`e`.`ID_User` = `ue`.`id`)) join `persona` `pe` on(`ue`.`ID_Persona` = `pe`.`id`)) left join `matricula` `m` on(`e`.`id` = `m`.`ID_Estudiante` and `m`.`Estado_matricula` = 'Activa')) left join `grado` `g` on(`m`.`ID_Grado` = `g`.`id`)) WHERE `pt`.`Estado` = 'Activo' AND `e`.`Estado` = 'Activo' ;

-- --------------------------------------------------------

--
-- Estructura para la vista `v_estudiante_tutores`
--
DROP TABLE IF EXISTS `v_estudiante_tutores`;

CREATE ALGORITHM=UNDEFINED DEFINER=`root`@`localhost` SQL SECURITY DEFINER VIEW `v_estudiante_tutores`  AS SELECT `e`.`id` AS `ID_Estudiante`, `e`.`Codigo_estudiante` AS `Codigo_estudiante`, concat(`pe`.`Nombre`,' ',`pe`.`Apellido`) AS `Nombre_Estudiante`, `et`.`Parentesco` AS `Parentesco`, `pt`.`id` AS `ID_Padre`, concat(`pp`.`Nombre`,' ',`pp`.`Apellido`) AS `Nombre_Tutor`, `pp`.`CI` AS `CI_Tutor`, `pp`.`Telefono` AS `Telefono_Tutor`, `pp`.`Email_personal` AS `Email_Tutor`, `pt`.`Ocupacion` AS `Ocupacion`, `pt`.`Lugar_trabajo` AS `Lugar_trabajo`, `pt`.`Telefono_trabajo` AS `Telefono_trabajo`, `et`.`Es_responsable_economicamente` AS `Es_responsable_economicamente`, `et`.`Es_contacto_emergencia` AS `Es_contacto_emergencia`, `et`.`Puede_retirar` AS `Puede_retirar`, `et`.`Vive_con_estudiante` AS `Vive_con_estudiante`, `et`.`Prioridad_contacto` AS `Prioridad_contacto` FROM ((((((`estudiante_tutor` `et` join `estudiante` `e` on(`et`.`ID_Estudiante` = `e`.`id`)) join `users` `ue` on(`e`.`ID_User` = `ue`.`id`)) join `persona` `pe` on(`ue`.`ID_Persona` = `pe`.`id`)) join `padre_tutor` `pt` on(`et`.`ID_Padre` = `pt`.`id`)) join `users` `up` on(`pt`.`ID_User` = `up`.`id`)) join `persona` `pp` on(`up`.`ID_Persona` = `pp`.`id`)) ORDER BY `e`.`id` ASC, `et`.`Prioridad_contacto` ASC ;

-- --------------------------------------------------------

--
-- Estructura para la vista `v_horario_estudiante`
--
DROP TABLE IF EXISTS `v_horario_estudiante`;

CREATE ALGORITHM=UNDEFINED DEFINER=`root`@`localhost` SQL SECURITY DEFINER VIEW `v_horario_estudiante`  AS SELECT `e`.`id` AS `ID_Estudiante`, `e`.`Codigo_estudiante` AS `Codigo_estudiante`, concat(`p`.`Nombre`,' ',`p`.`Apellido`) AS `Nombre_Estudiante`, `m`.`Nombre_de_la_materia` AS `Nombre_de_la_materia`, `h`.`Dia_semana` AS `Dia_semana`, `h`.`Hora_inicio` AS `Hora_inicio`, `h`.`Hora_fin` AS `Hora_fin`, `h`.`Aula` AS `Aula`, concat(`pd`.`Nombre`,' ',`pd`.`Apellido`) AS `Nombre_Docente`, `g`.`Nombre` AS `Grado`, `g`.`Paralelo` AS `Paralelo` FROM ((((((((((`estudiante` `e` join `users` `u` on(`e`.`ID_User` = `u`.`id`)) join `persona` `p` on(`u`.`ID_Persona` = `p`.`id`)) join `matricula` `mat` on(`e`.`id` = `mat`.`ID_Estudiante`)) join `grado` `g` on(`mat`.`ID_Grado` = `g`.`id`)) join `asignacion_docente` `ad` on(`g`.`id` = `ad`.`ID_Grado`)) join `horarios` `h` on(`ad`.`id` = `h`.`ID_Asignacion_docente`)) join `materias` `m` on(`ad`.`ID_Materia` = `m`.`id`)) join `docente` `d` on(`ad`.`ID_Docente` = `d`.`id`)) join `users` `ud` on(`d`.`ID_User` = `ud`.`id`)) join `persona` `pd` on(`ud`.`ID_Persona` = `pd`.`id`)) WHERE `mat`.`Estado_matricula` = 'Activa' AND `ad`.`Estado` = 'Activo' ORDER BY `e`.`id` ASC, `h`.`Dia_semana` ASC, `h`.`Hora_inicio` ASC ;

-- --------------------------------------------------------

--
-- Estructura para la vista `v_lista_docentes`
--
DROP TABLE IF EXISTS `v_lista_docentes`;

CREATE ALGORITHM=UNDEFINED DEFINER=`root`@`localhost` SQL SECURITY DEFINER VIEW `v_lista_docentes`  AS SELECT `d`.`id` AS `id`, concat(`p`.`Nombre`,' ',`p`.`Apellido`) AS `Nombre_Completo`, `p`.`CI` AS `CI`, `p`.`Telefono` AS `Telefono`, `d`.`Especialidad` AS `Especialidad`, `d`.`Estado` AS `Estado`, (select count(0) from `asignacion_docente` where `asignacion_docente`.`ID_Docente` = `d`.`id` and `asignacion_docente`.`Estado` = 'Activo') AS `Materias_Activas` FROM ((`docente` `d` join `users` `u` on(`d`.`ID_User` = `u`.`id`)) join `persona` `p` on(`u`.`ID_Persona` = `p`.`id`)) WHERE `d`.`Estado` = 'Activo' ;

-- --------------------------------------------------------

--
-- Estructura para la vista `v_lista_estudiantes`
--
DROP TABLE IF EXISTS `v_lista_estudiantes`;

CREATE ALGORITHM=UNDEFINED DEFINER=`root`@`localhost` SQL SECURITY DEFINER VIEW `v_lista_estudiantes`  AS SELECT `e`.`id` AS `id`, `e`.`Codigo_estudiante` AS `Codigo_estudiante`, concat(`p`.`Nombre`,' ',`p`.`Apellido`) AS `Nombre_Completo`, `p`.`CI` AS `CI`, `p`.`Telefono` AS `Telefono`, `g`.`Nombre` AS `Grado`, `g`.`Paralelo` AS `Paralelo`, `e`.`Estado` AS `Estado` FROM ((((`estudiante` `e` join `users` `u` on(`e`.`ID_User` = `u`.`id`)) join `persona` `p` on(`u`.`ID_Persona` = `p`.`id`)) left join `matricula` `m` on(`e`.`id` = `m`.`ID_Estudiante` and `m`.`Estado_matricula` = 'Activa')) left join `grado` `g` on(`m`.`ID_Grado` = `g`.`id`)) WHERE `e`.`Estado` = 'Activo' ;

-- --------------------------------------------------------

--
-- Estructura para la vista `v_notas_estudiante`
--
DROP TABLE IF EXISTS `v_notas_estudiante`;

CREATE ALGORITHM=UNDEFINED DEFINER=`root`@`localhost` SQL SECURITY DEFINER VIEW `v_notas_estudiante`  AS SELECT `c`.`id` AS `ID_Calificacion`, `e`.`id` AS `ID_Estudiante`, `e`.`Codigo_estudiante` AS `Codigo_estudiante`, concat(`p`.`Nombre`,' ',`p`.`Apellido`) AS `Nombre_Estudiante`, `m`.`id` AS `ID_Materia`, `m`.`Codigo` AS `Codigo_Materia`, `m`.`Nombre_de_la_materia` AS `Nombre_de_la_materia`, `m`.`Area_conocimiento` AS `Area_conocimiento`, `per`.`id` AS `ID_Periodo`, `per`.`Nombre_periodo` AS `Nombre_periodo`, `per`.`Numero_periodo` AS `Numero_periodo`, `aa`.`id` AS `ID_Anio_Academico`, `aa`.`Anio` AS `Anio_Academico`, `aa`.`Nombre` AS `Nombre_Anio`, `g`.`Nombre` AS `Grado`, `g`.`Paralelo` AS `Paralelo`, `c`.`Nota` AS `Nota`, `c`.`Nota_maxima` AS `Nota_maxima`, round(`c`.`Nota` / `c`.`Nota_maxima` * 100,2) AS `Porcentaje`, `c`.`Porcentaje_peso` AS `Porcentaje_peso`, `c`.`Tipo_evaluacion` AS `Tipo_evaluacion`, `c`.`Descripcion` AS `Descripcion`, `c`.`Fecha_evaluacion` AS `Fecha_evaluacion`, `c`.`Estado` AS `Estado_Calificacion`, `c`.`Observaciones` AS `Observaciones`, concat(`pd`.`Nombre`,' ',`pd`.`Apellido`) AS `Nombre_Docente`, CASE WHEN `c`.`Nota` >= `c`.`Nota_maxima` * 0.6 THEN 'Aprobado' WHEN `c`.`Nota` < `c`.`Nota_maxima` * 0.6 THEN 'Reprobado' ELSE 'Sin Calificar' END AS `Estado_Aprobacion`, `c`.`Fecha_registro` AS `Fecha_registro`, `c`.`Actualizado_en` AS `Actualizado_en` FROM (((((((((((`calificaciones` `c` join `estudiante` `e` on(`c`.`ID_Estudiante` = `e`.`id`)) join `users` `ue` on(`e`.`ID_User` = `ue`.`id`)) join `persona` `p` on(`ue`.`ID_Persona` = `p`.`id`)) join `materias` `m` on(`c`.`ID_Materia` = `m`.`id`)) join `periodo` `per` on(`c`.`ID_Periodo` = `per`.`id`)) join `anio_academico` `aa` on(`c`.`ID_Anio_Academico` = `aa`.`id`)) join `docente` `d` on(`c`.`ID_Docente` = `d`.`id`)) join `users` `ud` on(`d`.`ID_User` = `ud`.`id`)) join `persona` `pd` on(`ud`.`ID_Persona` = `pd`.`id`)) left join `matricula` `mat` on(`e`.`id` = `mat`.`ID_Estudiante` and `mat`.`ID_Anio_Academico` = `aa`.`id`)) left join `grado` `g` on(`mat`.`ID_Grado` = `g`.`id`)) WHERE `c`.`Estado` in ('Publicada','Modificada') ;

-- --------------------------------------------------------

--
-- Estructura para la vista `v_pagos_pendientes`
--
DROP TABLE IF EXISTS `v_pagos_pendientes`;

CREATE ALGORITHM=UNDEFINED DEFINER=`root`@`localhost` SQL SECURITY DEFINER VIEW `v_pagos_pendientes`  AS SELECT `pg`.`id` AS `ID_Pago`, `e`.`Codigo_estudiante` AS `Codigo_estudiante`, concat(`p`.`Nombre`,' ',`p`.`Apellido`) AS `Nombre_Estudiante`, `g`.`Nombre` AS `Grado`, `pg`.`Concepto` AS `Concepto`, `pg`.`Mes` AS `Mes`, `pg`.`Monto` AS `Monto`, `pg`.`Descuento` AS `Descuento`, `pg`.`Monto_pagado` AS `Monto_pagado`, `pg`.`Saldo` AS `Saldo`, `pg`.`Fecha_vencimiento` AS `Fecha_vencimiento`, to_days(curdate()) - to_days(`pg`.`Fecha_vencimiento`) AS `Dias_Vencido`, `pg`.`Estado` AS `Estado`, `aa`.`Anio` AS `Anio_Academico` FROM ((((((`pagos` `pg` join `estudiante` `e` on(`pg`.`ID_Estudiante` = `e`.`id`)) join `users` `u` on(`e`.`ID_User` = `u`.`id`)) join `persona` `p` on(`u`.`ID_Persona` = `p`.`id`)) join `anio_academico` `aa` on(`pg`.`ID_Anio_Academico` = `aa`.`id`)) left join `matricula` `m` on(`e`.`id` = `m`.`ID_Estudiante` and `m`.`ID_Anio_Academico` = `aa`.`id`)) left join `grado` `g` on(`m`.`ID_Grado` = `g`.`id`)) WHERE `pg`.`Estado` in ('Pendiente','Atrasado') ORDER BY `pg`.`Fecha_vencimiento` ASC, `p`.`Apellido` ASC ;

-- --------------------------------------------------------

--
-- Estructura para la vista `v_promedio_estudiante_materia`
--
DROP TABLE IF EXISTS `v_promedio_estudiante_materia`;

CREATE ALGORITHM=UNDEFINED DEFINER=`root`@`localhost` SQL SECURITY DEFINER VIEW `v_promedio_estudiante_materia`  AS SELECT `e`.`id` AS `ID_Estudiante`, `e`.`Codigo_estudiante` AS `Codigo_estudiante`, concat(`p`.`Nombre`,' ',`p`.`Apellido`) AS `Nombre_Estudiante`, `m`.`id` AS `ID_Materia`, `m`.`Nombre_de_la_materia` AS `Nombre_de_la_materia`, `per`.`id` AS `ID_Periodo`, `per`.`Nombre_periodo` AS `Nombre_periodo`, `aa`.`id` AS `ID_Anio_Academico`, `aa`.`Anio` AS `Anio_Academico`, count(`c`.`id`) AS `Total_Evaluaciones`, round(avg(`c`.`Nota`),2) AS `Promedio_Notas`, round(avg(`c`.`Nota` / `c`.`Nota_maxima` * 100),2) AS `Promedio_Porcentaje`, max(`c`.`Nota`) AS `Nota_Maxima_Obtenida`, min(`c`.`Nota`) AS `Nota_Minima_Obtenida`, CASE WHEN avg(`c`.`Nota` / `c`.`Nota_maxima` * 100) >= 60 THEN 'Aprobado' ELSE 'Reprobado' END AS `Estado` FROM ((((((`estudiante` `e` join `calificaciones` `c` on(`e`.`id` = `c`.`ID_Estudiante`)) join `users` `u` on(`e`.`ID_User` = `u`.`id`)) join `persona` `p` on(`u`.`ID_Persona` = `p`.`id`)) join `materias` `m` on(`c`.`ID_Materia` = `m`.`id`)) join `periodo` `per` on(`c`.`ID_Periodo` = `per`.`id`)) join `anio_academico` `aa` on(`c`.`ID_Anio_Academico` = `aa`.`id`)) WHERE `c`.`Estado` in ('Publicada','Modificada') GROUP BY `e`.`id`, `m`.`id`, `per`.`id`, `aa`.`id` ;

-- --------------------------------------------------------

--
-- Estructura para la vista `v_rendimiento_estudiante`
--
DROP TABLE IF EXISTS `v_rendimiento_estudiante`;

CREATE ALGORITHM=UNDEFINED DEFINER=`root`@`localhost` SQL SECURITY DEFINER VIEW `v_rendimiento_estudiante`  AS SELECT `e`.`id` AS `ID_Estudiante`, `e`.`Codigo_estudiante` AS `Codigo_estudiante`, concat(`p`.`Nombre`,' ',`p`.`Apellido`) AS `Nombre_Estudiante`, `aa`.`id` AS `ID_Anio_Academico`, `aa`.`Anio` AS `Anio_Academico`, `g`.`Nombre` AS `Grado`, `g`.`Paralelo` AS `Paralelo`, count(distinct `c`.`ID_Materia`) AS `Total_Materias`, count(`c`.`id`) AS `Total_Evaluaciones`, round(avg(`c`.`Nota` / `c`.`Nota_maxima` * 100),2) AS `Promedio_General`, sum(case when `c`.`Nota` / `c`.`Nota_maxima` * 100 >= 90 then 1 else 0 end) AS `Evaluaciones_Excelente`, sum(case when `c`.`Nota` / `c`.`Nota_maxima` * 100 >= 80 and `c`.`Nota` / `c`.`Nota_maxima` * 100 < 90 then 1 else 0 end) AS `Evaluaciones_Muy_Bueno`, sum(case when `c`.`Nota` / `c`.`Nota_maxima` * 100 >= 70 and `c`.`Nota` / `c`.`Nota_maxima` * 100 < 80 then 1 else 0 end) AS `Evaluaciones_Bueno`, sum(case when `c`.`Nota` / `c`.`Nota_maxima` * 100 >= 60 and `c`.`Nota` / `c`.`Nota_maxima` * 100 < 70 then 1 else 0 end) AS `Evaluaciones_Suficiente`, sum(case when `c`.`Nota` / `c`.`Nota_maxima` * 100 < 60 then 1 else 0 end) AS `Evaluaciones_Insuficiente`, round(sum(case when `c`.`Nota` / `c`.`Nota_maxima` * 100 >= 60 then 1 else 0 end) / count(`c`.`id`) * 100,2) AS `Porcentaje_Aprobacion`, CASE WHEN avg(`c`.`Nota` / `c`.`Nota_maxima` * 100) >= 90 THEN 'Excelente' WHEN avg(`c`.`Nota` / `c`.`Nota_maxima` * 100) >= 80 THEN 'Muy Bueno' WHEN avg(`c`.`Nota` / `c`.`Nota_maxima` * 100) >= 70 THEN 'Bueno' WHEN avg(`c`.`Nota` / `c`.`Nota_maxima` * 100) >= 60 THEN 'Suficiente' ELSE 'Insuficiente' END AS `Clasificacion_Rendimiento` FROM ((((((`estudiante` `e` join `users` `u` on(`e`.`ID_User` = `u`.`id`)) join `persona` `p` on(`u`.`ID_Persona` = `p`.`id`)) join `calificaciones` `c` on(`e`.`id` = `c`.`ID_Estudiante`)) join `anio_academico` `aa` on(`c`.`ID_Anio_Academico` = `aa`.`id`)) left join `matricula` `m` on(`e`.`id` = `m`.`ID_Estudiante` and `m`.`ID_Anio_Academico` = `aa`.`id`)) left join `grado` `g` on(`m`.`ID_Grado` = `g`.`id`)) WHERE `c`.`Estado` in ('Publicada','Modificada') GROUP BY `e`.`id`, `aa`.`id` ;

-- --------------------------------------------------------

--
-- Estructura para la vista `v_reporte_financiero`
--
DROP TABLE IF EXISTS `v_reporte_financiero`;

CREATE ALGORITHM=UNDEFINED DEFINER=`root`@`localhost` SQL SECURITY DEFINER VIEW `v_reporte_financiero`  AS SELECT `aa`.`Anio` AS `Anio_Academico`, count(distinct `pg`.`ID_Estudiante`) AS `Total_Estudiantes_Con_Pagos`, sum(case when `pg`.`Estado` = 'Pagado' then `pg`.`Monto_pagado` else 0 end) AS `Total_Ingresos`, sum(case when `pg`.`Estado` in ('Pendiente','Atrasado') then `pg`.`Saldo` else 0 end) AS `Total_Pendiente`, sum(case when `pg`.`Concepto` = 'Matricula' and `pg`.`Estado` = 'Pagado' then `pg`.`Monto_pagado` else 0 end) AS `Ingresos_Matricula`, sum(case when `pg`.`Concepto` = 'Pension' and `pg`.`Estado` = 'Pagado' then `pg`.`Monto_pagado` else 0 end) AS `Ingresos_Pension`, sum(case when `pg`.`Concepto` in ('Examen','Materiales','Transporte','Uniforme','Otro') and `pg`.`Estado` = 'Pagado' then `pg`.`Monto_pagado` else 0 end) AS `Ingresos_Otros`, count(case when `pg`.`Estado` = 'Atrasado' then 1 end) AS `Pagos_Atrasados` FROM (`pagos` `pg` join `anio_academico` `aa` on(`pg`.`ID_Anio_Academico` = `aa`.`id`)) GROUP BY `aa`.`Anio` ;

-- --------------------------------------------------------

--
-- Estructura para la vista `v_resumen_asistencias_estudiante`
--
DROP TABLE IF EXISTS `v_resumen_asistencias_estudiante`;

CREATE ALGORITHM=UNDEFINED DEFINER=`root`@`localhost` SQL SECURITY DEFINER VIEW `v_resumen_asistencias_estudiante`  AS SELECT `e`.`id` AS `ID_Estudiante`, `e`.`Codigo_estudiante` AS `Codigo_estudiante`, concat(`p`.`Nombre`,' ',`p`.`Apellido`) AS `Nombre_Estudiante`, year(`a`.`Fecha`) AS `Anio`, month(`a`.`Fecha`) AS `Mes`, count(`a`.`id`) AS `Total_Registros`, sum(case when `a`.`Estado` = 'Presente' then 1 else 0 end) AS `Total_Presentes`, sum(case when `a`.`Estado` = 'Ausente' then 1 else 0 end) AS `Total_Ausentes`, sum(case when `a`.`Estado` = 'Tardanza' then 1 else 0 end) AS `Total_Tardanzas`, sum(case when `a`.`Estado` = 'Justificado' then 1 else 0 end) AS `Total_Justificados`, sum(case when `a`.`Estado` = 'Permiso' then 1 else 0 end) AS `Total_Permisos`, round(sum(case when `a`.`Estado` = 'Presente' then 1 else 0 end) / count(`a`.`id`) * 100,2) AS `Porcentaje_Asistencia`, round(sum(case when `a`.`Estado` = 'Ausente' then 1 else 0 end) / count(`a`.`id`) * 100,2) AS `Porcentaje_Ausencias` FROM (((`estudiante` `e` join `users` `u` on(`e`.`ID_User` = `u`.`id`)) join `persona` `p` on(`u`.`ID_Persona` = `p`.`id`)) join `asistencias` `a` on(`e`.`id` = `a`.`ID_Estudiante`)) GROUP BY `e`.`id`, year(`a`.`Fecha`), month(`a`.`Fecha`) ;

--
-- Índices para tablas volcadas
--

--
-- Indices de la tabla `actividades_extracurriculares`
--
ALTER TABLE `actividades_extracurriculares`
  ADD PRIMARY KEY (`id`),
  ADD KEY `Actividades_ID_Responsable_fkey` (`ID_Responsable`);

--
-- Indices de la tabla `anio_academico`
--
ALTER TABLE `anio_academico`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `unique_anio` (`Anio`),
  ADD KEY `idx_estado` (`Estado`),
  ADD KEY `idx_es_actual` (`Es_actual`);

--
-- Indices de la tabla `asignacion_docente`
--
ALTER TABLE `asignacion_docente`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `unique_asignacion` (`ID_Docente`,`ID_Materia`,`ID_Grado`,`ID_Anio_Academico`),
  ADD KEY `Asignacion_docente_ID_Anio_Academico_fkey` (`ID_Anio_Academico`),
  ADD KEY `Asignacion_docente_ID_Grado_fkey` (`ID_Grado`),
  ADD KEY `Asignacion_docente_ID_Materia_fkey` (`ID_Materia`);

--
-- Indices de la tabla `asistencias`
--
ALTER TABLE `asistencias`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `unique_asistencia_estudiante_materia_fecha` (`ID_Estudiante`,`ID_Materia`,`Fecha`),
  ADD KEY `Asistencias_ID_Estudiante_fkey` (`ID_Estudiante`),
  ADD KEY `Asistencias_ID_Materia_fkey` (`ID_Materia`),
  ADD KEY `Asistencias_ID_Docente_fkey` (`ID_Docente`),
  ADD KEY `idx_fecha` (`Fecha`);

--
-- Indices de la tabla `asistencia_curso`
--
ALTER TABLE `asistencia_curso`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `unique_curso_estudiante` (`ID_Curso`,`ID_Estudiante`),
  ADD KEY `idx_curso` (`ID_Curso`),
  ADD KEY `idx_estudiante` (`ID_Estudiante`),
  ADD KEY `fk_asistencia_curso_reg` (`Registrado_por`);

--
-- Indices de la tabla `auditoria_calificaciones`
--
ALTER TABLE `auditoria_calificaciones`
  ADD PRIMARY KEY (`id`),
  ADD KEY `idx_calificacion` (`ID_Calificacion_original`),
  ADD KEY `idx_estudiante` (`ID_Estudiante`),
  ADD KEY `idx_fecha` (`Fecha_hora`);

--
-- Indices de la tabla `auditoria_pagos`
--
ALTER TABLE `auditoria_pagos`
  ADD PRIMARY KEY (`id`),
  ADD KEY `idx_pago` (`ID_Pago_original`),
  ADD KEY `idx_estudiante` (`ID_Estudiante`),
  ADD KEY `idx_fecha` (`Fecha_hora`);

--
-- Indices de la tabla `auditoria_personas`
--
ALTER TABLE `auditoria_personas`
  ADD PRIMARY KEY (`id`),
  ADD KEY `idx_persona` (`ID_Persona_original`),
  ADD KEY `idx_fecha` (`Fecha_hora`);

--
-- Indices de la tabla `auditoria_usuarios`
--
ALTER TABLE `auditoria_usuarios`
  ADD PRIMARY KEY (`id`),
  ADD KEY `idx_user` (`ID_User`),
  ADD KEY `idx_fecha` (`Fecha_hora`),
  ADD KEY `idx_accion` (`Accion`);

--
-- Indices de la tabla `calificaciones`
--
ALTER TABLE `calificaciones`
  ADD PRIMARY KEY (`id`),
  ADD KEY `Calificaciones_ID_Anio_Academico_fkey` (`ID_Anio_Academico`),
  ADD KEY `idx_tipo_evaluacion` (`Tipo_evaluacion`),
  ADD KEY `Calificaciones_ID_Docente_fkey` (`ID_Docente`),
  ADD KEY `Calificaciones_ID_Estudiante_fkey` (`ID_Estudiante`),
  ADD KEY `Calificaciones_ID_Materia_fkey` (`ID_Materia`),
  ADD KEY `Calificaciones_ID_Periodo_fkey` (`ID_Periodo`);

--
-- Indices de la tabla `comunicados`
--
ALTER TABLE `comunicados`
  ADD PRIMARY KEY (`id`),
  ADD KEY `Comunicados_ID_Grado_fkey` (`ID_Grado`),
  ADD KEY `Comunicados_Creado_por_fkey` (`Creado_por`);

--
-- Indices de la tabla `cursos`
--
ALTER TABLE `cursos`
  ADD PRIMARY KEY (`id`),
  ADD KEY `idx_asignacion` (`ID_Asignacion`),
  ADD KEY `idx_periodo` (`ID_Periodo`),
  ADD KEY `idx_anio` (`ID_Anio_Academico`),
  ADD KEY `idx_fecha_programada` (`Fecha_programada`),
  ADD KEY `idx_estado` (`Estado`),
  ADD KEY `fk_cursos_registrado` (`Registrado_por`);

--
-- Indices de la tabla `docente`
--
ALTER TABLE `docente`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `unique_user_docente` (`ID_User`);

--
-- Indices de la tabla `documentos_inscripcion`
--
ALTER TABLE `documentos_inscripcion`
  ADD PRIMARY KEY (`id`),
  ADD KEY `Documentos_inscripcion_ID_Inscripcion_fkey` (`ID_Inscripcion`);

--
-- Indices de la tabla `estudiante`
--
ALTER TABLE `estudiante`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `unique_user_estudiante` (`ID_User`),
  ADD UNIQUE KEY `unique_codigo` (`Codigo_estudiante`);

--
-- Indices de la tabla `estudiante_actividad`
--
ALTER TABLE `estudiante_actividad`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `unique_estudiante_actividad_anio` (`ID_Estudiante`,`ID_Actividad`,`ID_Anio_Academico`),
  ADD KEY `Estudiante_actividad_ID_Estudiante_fkey` (`ID_Estudiante`),
  ADD KEY `Estudiante_actividad_ID_Actividad_fkey` (`ID_Actividad`),
  ADD KEY `Estudiante_actividad_ID_Anio_Academico_fkey` (`ID_Anio_Academico`);

--
-- Indices de la tabla `estudiante_tutor`
--
ALTER TABLE `estudiante_tutor`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `unique_estudiante_padre` (`ID_Estudiante`,`ID_Padre`),
  ADD KEY `Estudiante_tutor_ID_Padre_fkey` (`ID_Padre`);

--
-- Indices de la tabla `grado`
--
ALTER TABLE `grado`
  ADD PRIMARY KEY (`id`),
  ADD KEY `idx_curso_paralelo` (`Curso`,`Paralelo`),
  ADD KEY `Grado_ID_Nivel_educativo_fkey` (`ID_Nivel_educativo`);

--
-- Indices de la tabla `horarios`
--
ALTER TABLE `horarios`
  ADD PRIMARY KEY (`id`),
  ADD KEY `Horarios_ID_Asignacion_docente_fkey` (`ID_Asignacion_docente`);

--
-- Indices de la tabla `inscripcion`
--
ALTER TABLE `inscripcion`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `unique_estudiante_anio_inscripcion` (`ID_Estudiante`,`ID_Anio_Academico`),
  ADD KEY `Inscripcion_ID_Estudiante_fkey` (`ID_Estudiante`),
  ADD KEY `Inscripcion_ID_Anio_Academico_fkey` (`ID_Anio_Academico`),
  ADD KEY `Inscripcion_Aprobado_por_fkey` (`Aprobado_por`),
  ADD KEY `idx_estado_inscripcion` (`Estado`);

--
-- Indices de la tabla `materias`
--
ALTER TABLE `materias`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `unique_codigo` (`Codigo`),
  ADD KEY `idx_area` (`Area_conocimiento`);

--
-- Indices de la tabla `materia_grado`
--
ALTER TABLE `materia_grado`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `unique_materia_grado_anio` (`ID_Materia`,`ID_Grado`,`ID_Anio_Academico`),
  ADD KEY `Materia_grado_ID_Materia_fkey` (`ID_Materia`),
  ADD KEY `Materia_grado_ID_Grado_fkey` (`ID_Grado`),
  ADD KEY `Materia_grado_ID_Anio_Academico_fkey` (`ID_Anio_Academico`);

--
-- Indices de la tabla `matricula`
--
ALTER TABLE `matricula`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `unique_estudiante_grado_anio` (`ID_Estudiante`,`ID_Grado`,`ID_Anio_Academico`),
  ADD UNIQUE KEY `unique_numero_matricula` (`Numero_matricula`),
  ADD KEY `Matricula_ID_Inscripcion_fkey` (`ID_Inscripcion`),
  ADD KEY `idx_estado_matricula` (`Estado_matricula`),
  ADD KEY `Matricula_ID_Anio_Academico_fkey` (`ID_Anio_Academico`),
  ADD KEY `Matricula_ID_Grado_fkey` (`ID_Grado`);

--
-- Indices de la tabla `nivel_educativo`
--
ALTER TABLE `nivel_educativo`
  ADD PRIMARY KEY (`id`);

--
-- Indices de la tabla `padre_tutor`
--
ALTER TABLE `padre_tutor`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `unique_user_padre` (`ID_User`);

--
-- Indices de la tabla `pagos`
--
ALTER TABLE `pagos`
  ADD PRIMARY KEY (`id`),
  ADD KEY `Pagos_ID_Estudiante_fkey` (`ID_Estudiante`),
  ADD KEY `Pagos_ID_Anio_Academico_fkey` (`ID_Anio_Academico`),
  ADD KEY `idx_estado_pago` (`Estado`);

--
-- Indices de la tabla `periodo`
--
ALTER TABLE `periodo`
  ADD PRIMARY KEY (`id`),
  ADD KEY `Periodo_ID_Anio_Academico_fkey` (`ID_Anio_Academico`);

--
-- Indices de la tabla `permisos`
--
ALTER TABLE `permisos`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `unique_codigo_permiso` (`Codigo`),
  ADD KEY `idx_modulo` (`Modulo`);

--
-- Indices de la tabla `persona`
--
ALTER TABLE `persona`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `unique_ci` (`CI`),
  ADD KEY `idx_ci` (`CI`),
  ADD KEY `idx_apellido_nombre` (`Apellido`,`Nombre`);

--
-- Indices de la tabla `plantel_administrativo`
--
ALTER TABLE `plantel_administrativo`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `unique_user_admin` (`ID_User`);

--
-- Indices de la tabla `reportes_buena_conducta`
--
ALTER TABLE `reportes_buena_conducta`
  ADD PRIMARY KEY (`id`),
  ADD KEY `idx_estudiante` (`ID_Estudiante`),
  ADD KEY `idx_reportado` (`ID_Reportado_por`),
  ADD KEY `idx_fecha` (`Fecha_conducta`),
  ADD KEY `idx_tipo` (`Tipo_reconocimiento`),
  ADD KEY `idx_estado` (`Estado`);

--
-- Indices de la tabla `reportes_disciplinarios`
--
ALTER TABLE `reportes_disciplinarios`
  ADD PRIMARY KEY (`id`),
  ADD KEY `Reportes_disciplinarios_ID_Estudiante_fkey` (`ID_Estudiante`),
  ADD KEY `Reportes_disciplinarios_ID_Reportado_por_fkey` (`ID_Reportado_por`);

--
-- Indices de la tabla `roles`
--
ALTER TABLE `roles`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `unique_nombre_rol` (`Nombre`),
  ADD KEY `idx_estado` (`Estado`);

--
-- Indices de la tabla `rol_permiso`
--
ALTER TABLE `rol_permiso`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `unique_rol_permiso` (`ID_Rol`,`ID_Permiso`),
  ADD KEY `Rol_permiso_ID_Rol_fkey` (`ID_Rol`),
  ADD KEY `Rol_permiso_ID_Permiso_fkey` (`ID_Permiso`);

--
-- Indices de la tabla `users`
--
ALTER TABLE `users`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `unique_correo` (`Correo`),
  ADD KEY `Users_ID_Persona_fkey` (`ID_Persona`),
  ADD KEY `Users_ID_Verificacion_fkey` (`ID_Verificacion`),
  ADD KEY `idx_rol` (`ID_Rol`);

--
-- Indices de la tabla `verificacion`
--
ALTER TABLE `verificacion`
  ADD PRIMARY KEY (`id`);

--
-- AUTO_INCREMENT de las tablas volcadas
--

--
-- AUTO_INCREMENT de la tabla `actividades_extracurriculares`
--
ALTER TABLE `actividades_extracurriculares`
  MODIFY `id` bigint(20) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=6;

--
-- AUTO_INCREMENT de la tabla `anio_academico`
--
ALTER TABLE `anio_academico`
  MODIFY `id` bigint(20) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=2;

--
-- AUTO_INCREMENT de la tabla `asignacion_docente`
--
ALTER TABLE `asignacion_docente`
  MODIFY `id` bigint(20) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=13;

--
-- AUTO_INCREMENT de la tabla `asistencias`
--
ALTER TABLE `asistencias`
  MODIFY `id` bigint(20) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=24;

--
-- AUTO_INCREMENT de la tabla `asistencia_curso`
--
ALTER TABLE `asistencia_curso`
  MODIFY `id` bigint(20) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT de la tabla `auditoria_calificaciones`
--
ALTER TABLE `auditoria_calificaciones`
  MODIFY `id` bigint(20) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT de la tabla `auditoria_pagos`
--
ALTER TABLE `auditoria_pagos`
  MODIFY `id` bigint(20) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT de la tabla `auditoria_personas`
--
ALTER TABLE `auditoria_personas`
  MODIFY `id` bigint(20) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=15;

--
-- AUTO_INCREMENT de la tabla `auditoria_usuarios`
--
ALTER TABLE `auditoria_usuarios`
  MODIFY `id` bigint(20) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=81;

--
-- AUTO_INCREMENT de la tabla `calificaciones`
--
ALTER TABLE `calificaciones`
  MODIFY `id` bigint(20) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=13;

--
-- AUTO_INCREMENT de la tabla `comunicados`
--
ALTER TABLE `comunicados`
  MODIFY `id` bigint(20) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=4;

--
-- AUTO_INCREMENT de la tabla `cursos`
--
ALTER TABLE `cursos`
  MODIFY `id` bigint(20) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=4;

--
-- AUTO_INCREMENT de la tabla `docente`
--
ALTER TABLE `docente`
  MODIFY `id` bigint(20) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=6;

--
-- AUTO_INCREMENT de la tabla `documentos_inscripcion`
--
ALTER TABLE `documentos_inscripcion`
  MODIFY `id` bigint(20) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT de la tabla `estudiante`
--
ALTER TABLE `estudiante`
  MODIFY `id` bigint(20) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=15;

--
-- AUTO_INCREMENT de la tabla `estudiante_actividad`
--
ALTER TABLE `estudiante_actividad`
  MODIFY `id` bigint(20) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=7;

--
-- AUTO_INCREMENT de la tabla `estudiante_tutor`
--
ALTER TABLE `estudiante_tutor`
  MODIFY `id` bigint(20) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=15;

--
-- AUTO_INCREMENT de la tabla `grado`
--
ALTER TABLE `grado`
  MODIFY `id` bigint(20) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=16;

--
-- AUTO_INCREMENT de la tabla `horarios`
--
ALTER TABLE `horarios`
  MODIFY `id` bigint(20) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=13;

--
-- AUTO_INCREMENT de la tabla `inscripcion`
--
ALTER TABLE `inscripcion`
  MODIFY `id` bigint(20) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=15;

--
-- AUTO_INCREMENT de la tabla `materias`
--
ALTER TABLE `materias`
  MODIFY `id` bigint(20) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=17;

--
-- AUTO_INCREMENT de la tabla `materia_grado`
--
ALTER TABLE `materia_grado`
  MODIFY `id` bigint(20) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=24;

--
-- AUTO_INCREMENT de la tabla `matricula`
--
ALTER TABLE `matricula`
  MODIFY `id` bigint(20) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=14;

--
-- AUTO_INCREMENT de la tabla `nivel_educativo`
--
ALTER TABLE `nivel_educativo`
  MODIFY `id` bigint(20) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=4;

--
-- AUTO_INCREMENT de la tabla `padre_tutor`
--
ALTER TABLE `padre_tutor`
  MODIFY `id` bigint(20) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=13;

--
-- AUTO_INCREMENT de la tabla `pagos`
--
ALTER TABLE `pagos`
  MODIFY `id` bigint(20) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=12;

--
-- AUTO_INCREMENT de la tabla `periodo`
--
ALTER TABLE `periodo`
  MODIFY `id` bigint(20) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=5;

--
-- AUTO_INCREMENT de la tabla `permisos`
--
ALTER TABLE `permisos`
  MODIFY `id` bigint(20) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT de la tabla `persona`
--
ALTER TABLE `persona`
  MODIFY `id` bigint(20) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=34;

--
-- AUTO_INCREMENT de la tabla `plantel_administrativo`
--
ALTER TABLE `plantel_administrativo`
  MODIFY `id` bigint(20) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=3;

--
-- AUTO_INCREMENT de la tabla `reportes_buena_conducta`
--
ALTER TABLE `reportes_buena_conducta`
  MODIFY `id` bigint(20) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=4;

--
-- AUTO_INCREMENT de la tabla `reportes_disciplinarios`
--
ALTER TABLE `reportes_disciplinarios`
  MODIFY `id` bigint(20) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=6;

--
-- AUTO_INCREMENT de la tabla `roles`
--
ALTER TABLE `roles`
  MODIFY `id` bigint(20) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=7;

--
-- AUTO_INCREMENT de la tabla `rol_permiso`
--
ALTER TABLE `rol_permiso`
  MODIFY `id` bigint(20) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT de la tabla `users`
--
ALTER TABLE `users`
  MODIFY `id` bigint(20) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=34;

--
-- AUTO_INCREMENT de la tabla `verificacion`
--
ALTER TABLE `verificacion`
  MODIFY `id` bigint(20) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=74;

--
-- Restricciones para tablas volcadas
--

--
-- Filtros para la tabla `actividades_extracurriculares`
--
ALTER TABLE `actividades_extracurriculares`
  ADD CONSTRAINT `Actividades_ID_Responsable_fkey` FOREIGN KEY (`ID_Responsable`) REFERENCES `users` (`id`);

--
-- Filtros para la tabla `asignacion_docente`
--
ALTER TABLE `asignacion_docente`
  ADD CONSTRAINT `Asignacion_docente_ID_Anio_Academico_fkey` FOREIGN KEY (`ID_Anio_Academico`) REFERENCES `anio_academico` (`id`),
  ADD CONSTRAINT `Asignacion_docente_ID_Docente_fkey` FOREIGN KEY (`ID_Docente`) REFERENCES `docente` (`id`) ON DELETE CASCADE,
  ADD CONSTRAINT `Asignacion_docente_ID_Grado_fkey` FOREIGN KEY (`ID_Grado`) REFERENCES `grado` (`id`),
  ADD CONSTRAINT `Asignacion_docente_ID_Materia_fkey` FOREIGN KEY (`ID_Materia`) REFERENCES `materias` (`id`);

--
-- Filtros para la tabla `asistencias`
--
ALTER TABLE `asistencias`
  ADD CONSTRAINT `Asistencias_ID_Docente_fkey` FOREIGN KEY (`ID_Docente`) REFERENCES `docente` (`id`),
  ADD CONSTRAINT `Asistencias_ID_Estudiante_fkey` FOREIGN KEY (`ID_Estudiante`) REFERENCES `estudiante` (`id`) ON DELETE CASCADE,
  ADD CONSTRAINT `Asistencias_ID_Materia_fkey` FOREIGN KEY (`ID_Materia`) REFERENCES `materias` (`id`);

--
-- Filtros para la tabla `asistencia_curso`
--
ALTER TABLE `asistencia_curso`
  ADD CONSTRAINT `fk_asistencia_curso_curso` FOREIGN KEY (`ID_Curso`) REFERENCES `cursos` (`id`) ON DELETE CASCADE,
  ADD CONSTRAINT `fk_asistencia_curso_est` FOREIGN KEY (`ID_Estudiante`) REFERENCES `estudiante` (`id`) ON DELETE CASCADE,
  ADD CONSTRAINT `fk_asistencia_curso_reg` FOREIGN KEY (`Registrado_por`) REFERENCES `users` (`id`) ON DELETE SET NULL;

--
-- Filtros para la tabla `auditoria_usuarios`
--
ALTER TABLE `auditoria_usuarios`
  ADD CONSTRAINT `auditoria_usuarios_ibfk_1` FOREIGN KEY (`ID_User`) REFERENCES `users` (`id`) ON DELETE CASCADE;

--
-- Filtros para la tabla `calificaciones`
--
ALTER TABLE `calificaciones`
  ADD CONSTRAINT `Calificaciones_ID_Anio_Academico_fkey` FOREIGN KEY (`ID_Anio_Academico`) REFERENCES `anio_academico` (`id`),
  ADD CONSTRAINT `Calificaciones_ID_Docente_fkey` FOREIGN KEY (`ID_Docente`) REFERENCES `docente` (`id`),
  ADD CONSTRAINT `Calificaciones_ID_Estudiante_fkey` FOREIGN KEY (`ID_Estudiante`) REFERENCES `estudiante` (`id`) ON DELETE CASCADE,
  ADD CONSTRAINT `Calificaciones_ID_Materia_fkey` FOREIGN KEY (`ID_Materia`) REFERENCES `materias` (`id`),
  ADD CONSTRAINT `Calificaciones_ID_Periodo_fkey` FOREIGN KEY (`ID_Periodo`) REFERENCES `periodo` (`id`);

--
-- Filtros para la tabla `comunicados`
--
ALTER TABLE `comunicados`
  ADD CONSTRAINT `Comunicados_Creado_por_fkey` FOREIGN KEY (`Creado_por`) REFERENCES `users` (`id`),
  ADD CONSTRAINT `Comunicados_ID_Grado_fkey` FOREIGN KEY (`ID_Grado`) REFERENCES `grado` (`id`);

--
-- Filtros para la tabla `cursos`
--
ALTER TABLE `cursos`
  ADD CONSTRAINT `fk_cursos_anio` FOREIGN KEY (`ID_Anio_Academico`) REFERENCES `anio_academico` (`id`),
  ADD CONSTRAINT `fk_cursos_asignacion` FOREIGN KEY (`ID_Asignacion`) REFERENCES `asignacion_docente` (`id`) ON DELETE CASCADE,
  ADD CONSTRAINT `fk_cursos_periodo` FOREIGN KEY (`ID_Periodo`) REFERENCES `periodo` (`id`),
  ADD CONSTRAINT `fk_cursos_registrado` FOREIGN KEY (`Registrado_por`) REFERENCES `users` (`id`) ON DELETE SET NULL;

--
-- Filtros para la tabla `docente`
--
ALTER TABLE `docente`
  ADD CONSTRAINT `Docente_ID_User_fkey` FOREIGN KEY (`ID_User`) REFERENCES `users` (`id`) ON DELETE CASCADE;

--
-- Filtros para la tabla `documentos_inscripcion`
--
ALTER TABLE `documentos_inscripcion`
  ADD CONSTRAINT `Documentos_inscripcion_ID_Inscripcion_fkey` FOREIGN KEY (`ID_Inscripcion`) REFERENCES `inscripcion` (`id`) ON DELETE CASCADE;

--
-- Filtros para la tabla `estudiante`
--
ALTER TABLE `estudiante`
  ADD CONSTRAINT `Estudiante_ID_User_fkey` FOREIGN KEY (`ID_User`) REFERENCES `users` (`id`) ON DELETE CASCADE;

--
-- Filtros para la tabla `estudiante_actividad`
--
ALTER TABLE `estudiante_actividad`
  ADD CONSTRAINT `Estudiante_actividad_ID_Actividad_fkey` FOREIGN KEY (`ID_Actividad`) REFERENCES `actividades_extracurriculares` (`id`) ON DELETE CASCADE,
  ADD CONSTRAINT `Estudiante_actividad_ID_Anio_Academico_fkey` FOREIGN KEY (`ID_Anio_Academico`) REFERENCES `anio_academico` (`id`),
  ADD CONSTRAINT `Estudiante_actividad_ID_Estudiante_fkey` FOREIGN KEY (`ID_Estudiante`) REFERENCES `estudiante` (`id`) ON DELETE CASCADE;

--
-- Filtros para la tabla `estudiante_tutor`
--
ALTER TABLE `estudiante_tutor`
  ADD CONSTRAINT `Estudiante_tutor_ID_Estudiante_fkey` FOREIGN KEY (`ID_Estudiante`) REFERENCES `estudiante` (`id`) ON DELETE CASCADE,
  ADD CONSTRAINT `Estudiante_tutor_ID_Padre_fkey` FOREIGN KEY (`ID_Padre`) REFERENCES `padre_tutor` (`id`) ON DELETE CASCADE;

--
-- Filtros para la tabla `grado`
--
ALTER TABLE `grado`
  ADD CONSTRAINT `Grado_ID_Nivel_educativo_fkey` FOREIGN KEY (`ID_Nivel_educativo`) REFERENCES `nivel_educativo` (`id`);

--
-- Filtros para la tabla `horarios`
--
ALTER TABLE `horarios`
  ADD CONSTRAINT `Horarios_ID_Asignacion_docente_fkey` FOREIGN KEY (`ID_Asignacion_docente`) REFERENCES `asignacion_docente` (`id`) ON DELETE CASCADE;

--
-- Filtros para la tabla `inscripcion`
--
ALTER TABLE `inscripcion`
  ADD CONSTRAINT `Inscripcion_Aprobado_por_fkey` FOREIGN KEY (`Aprobado_por`) REFERENCES `users` (`id`) ON DELETE SET NULL,
  ADD CONSTRAINT `Inscripcion_ID_Anio_Academico_fkey` FOREIGN KEY (`ID_Anio_Academico`) REFERENCES `anio_academico` (`id`),
  ADD CONSTRAINT `Inscripcion_ID_Estudiante_fkey` FOREIGN KEY (`ID_Estudiante`) REFERENCES `estudiante` (`id`) ON DELETE CASCADE;

--
-- Filtros para la tabla `materia_grado`
--
ALTER TABLE `materia_grado`
  ADD CONSTRAINT `Materia_grado_ID_Anio_Academico_fkey` FOREIGN KEY (`ID_Anio_Academico`) REFERENCES `anio_academico` (`id`),
  ADD CONSTRAINT `Materia_grado_ID_Grado_fkey` FOREIGN KEY (`ID_Grado`) REFERENCES `grado` (`id`),
  ADD CONSTRAINT `Materia_grado_ID_Materia_fkey` FOREIGN KEY (`ID_Materia`) REFERENCES `materias` (`id`);

--
-- Filtros para la tabla `matricula`
--
ALTER TABLE `matricula`
  ADD CONSTRAINT `Matricula_ID_Anio_Academico_fkey` FOREIGN KEY (`ID_Anio_Academico`) REFERENCES `anio_academico` (`id`),
  ADD CONSTRAINT `Matricula_ID_Estudiante_fkey` FOREIGN KEY (`ID_Estudiante`) REFERENCES `estudiante` (`id`) ON DELETE CASCADE,
  ADD CONSTRAINT `Matricula_ID_Grado_fkey` FOREIGN KEY (`ID_Grado`) REFERENCES `grado` (`id`),
  ADD CONSTRAINT `Matricula_ID_Inscripcion_fkey` FOREIGN KEY (`ID_Inscripcion`) REFERENCES `inscripcion` (`id`);

--
-- Filtros para la tabla `padre_tutor`
--
ALTER TABLE `padre_tutor`
  ADD CONSTRAINT `Padre_Tutor_ID_User_fkey` FOREIGN KEY (`ID_User`) REFERENCES `users` (`id`) ON DELETE CASCADE;

--
-- Filtros para la tabla `pagos`
--
ALTER TABLE `pagos`
  ADD CONSTRAINT `Pagos_ID_Anio_Academico_fkey` FOREIGN KEY (`ID_Anio_Academico`) REFERENCES `anio_academico` (`id`),
  ADD CONSTRAINT `Pagos_ID_Estudiante_fkey` FOREIGN KEY (`ID_Estudiante`) REFERENCES `estudiante` (`id`) ON DELETE CASCADE;

--
-- Filtros para la tabla `periodo`
--
ALTER TABLE `periodo`
  ADD CONSTRAINT `Periodo_ID_Anio_Academico_fkey` FOREIGN KEY (`ID_Anio_Academico`) REFERENCES `anio_academico` (`id`);

--
-- Filtros para la tabla `plantel_administrativo`
--
ALTER TABLE `plantel_administrativo`
  ADD CONSTRAINT `Plantel_administrativo_ID_User_fkey` FOREIGN KEY (`ID_User`) REFERENCES `users` (`id`) ON DELETE CASCADE;

--
-- Filtros para la tabla `reportes_buena_conducta`
--
ALTER TABLE `reportes_buena_conducta`
  ADD CONSTRAINT `fk_rbc_estudiante` FOREIGN KEY (`ID_Estudiante`) REFERENCES `estudiante` (`id`) ON DELETE CASCADE,
  ADD CONSTRAINT `fk_rbc_reportado` FOREIGN KEY (`ID_Reportado_por`) REFERENCES `users` (`id`);

--
-- Filtros para la tabla `reportes_disciplinarios`
--
ALTER TABLE `reportes_disciplinarios`
  ADD CONSTRAINT `Reportes_disciplinarios_ID_Estudiante_fkey` FOREIGN KEY (`ID_Estudiante`) REFERENCES `estudiante` (`id`) ON DELETE CASCADE,
  ADD CONSTRAINT `Reportes_disciplinarios_ID_Reportado_por_fkey` FOREIGN KEY (`ID_Reportado_por`) REFERENCES `users` (`id`);

--
-- Filtros para la tabla `rol_permiso`
--
ALTER TABLE `rol_permiso`
  ADD CONSTRAINT `Rol_permiso_ID_Permiso_fkey` FOREIGN KEY (`ID_Permiso`) REFERENCES `permisos` (`id`) ON DELETE CASCADE,
  ADD CONSTRAINT `Rol_permiso_ID_Rol_fkey` FOREIGN KEY (`ID_Rol`) REFERENCES `roles` (`id`) ON DELETE CASCADE;

--
-- Filtros para la tabla `users`
--
ALTER TABLE `users`
  ADD CONSTRAINT `Users_ID_Persona_fkey` FOREIGN KEY (`ID_Persona`) REFERENCES `persona` (`id`) ON DELETE CASCADE,
  ADD CONSTRAINT `Users_ID_Rol_fkey` FOREIGN KEY (`ID_Rol`) REFERENCES `roles` (`id`),
  ADD CONSTRAINT `Users_ID_Verificacion_fkey` FOREIGN KEY (`ID_Verificacion`) REFERENCES `verificacion` (`id`) ON DELETE SET NULL;
COMMIT;

/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
