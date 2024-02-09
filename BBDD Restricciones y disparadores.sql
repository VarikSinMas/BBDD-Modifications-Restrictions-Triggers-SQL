USE ICX0_P3_6;

/*
10. Eliminamos todas las FK entre las tablas de la BBDD.
*/

ALTER TABLE corporativo
	DROP FOREIGN KEY socio_corporativo,
	DROP FOREIGN KEY socio_empresa;

ALTER TABLE historico
	DROP FOREIGN KEY historico_socio;

ALTER TABLE horario
	DROP FOREIGN KEY actividad_horario,
	DROP FOREIGN KEY actividad_instalacion;
    
ALTER TABLE principal
	DROP FOREIGN KEY socio_principal;

ALTER TABLE seguimiento
	DROP FOREIGN KEY seguimiento_socio;

ALTER TABLE socio
	DROP FOREIGN KEY socio_plan;
    
/*
11. Realizamos las modificaciones pertinentes en la BBDD para ajustar la misma a los nuevos requisitos.
*/

/* Creamos la Tabla Monitores*/

-- MONITORES, se guardará la información de los monitores del Gimnasio así como de las actividades que cada monitor puede impartir. 
-- Los datos personales a guardar para los monitores, serán los siguientes: id, documento identificación, nombre, apellidos, titulación(es), teléfono fijo, teléfono móvil. 
-- Tomar en cuenta que puede ser necesaria la creación de varias tablas en este punto.


CREATE TABLE IF NOT EXISTS monitores (
  id_monitor int NOT NULL AUTO_INCREMENT,
  documento_identificacion varchar(20) NOT NULL,
  nombre varchar(30) NOT NULL,
  apellidos varchar(40) NOT NULL,
  titulaciones varchar(30) NOT NULL,
  telefono_fijo varchar(15) DEFAULT NULL,
  telefono_movil varchar(15) NOT NULL,
  PRIMARY KEY (id_monitor),
  UNIQUE KEY documento_identificacion_UNIQUE (documento_identificacion)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

/* Creamos la Tabla Actividad_Monitor*/

CREATE TABLE IF NOT EXISTS actividad_monitor (
  id_actividad int NOT NULL,
  id_monitor int NOT NULL,
  PRIMARY KEY (id_actividad, id_monitor)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- INSTALACIONES con la descripción de las diferentes salas del Gimnasio. Datos requeridos: id, zona gimnasio (zona de agua, canchas, salones de entrenamiento...).
-- denominación, descripción, metros cuadrados, aforo.
-- Esta tabla ya existe en la BBDD proporcionada.

/*
HORARIO permite registrar el horario y monitor de las diferentes actividades. Datos requeridos: fecha, hora, id_actividad, id_instalación, id_monitor, 
participantes (no puede ser mayor al aforo de la instalación), observaciones
Modificamos la columna "monitor" para que pueda ser NULL, para salvaguardar los datos de monitores anteriores y añadimos las columnas id_monitor
y participantes como se nos indican en los nuevos requisitos.
*/

ALTER TABLE horario
 MODIFY COLUMN monitor varchar(45) NULL,
 ADD COLUMN id_monitor int NOT NULL,
 ADD COLUMN participantes int NOT NULL;

/* Creamos el Trigger para que el aforo de la instlación no se exceda*/

DELIMITER //
CREATE TRIGGER check_aforo_before_insert
BEFORE INSERT ON horario
FOR EACH ROW
BEGIN
    DECLARE v_aforo INT;
    SELECT aforo INTO v_aforo FROM instalacion WHERE id_instalacion = NEW.id_instalacion;
    IF NEW.participantes > v_aforo THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'El número de participantes excede el aforo de la instalación';
    END IF;
END //
DELIMITER ;

DELIMITER //
CREATE TRIGGER check_aforo_before_update
BEFORE UPDATE ON horario
FOR EACH ROW
BEGIN
    DECLARE v_aforo INT;
    SELECT aforo INTO v_aforo FROM instalacion WHERE id_instalacion = NEW.id_instalacion;
    IF NEW.participantes > v_aforo THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'El número de participantes excede el aforo de la instalación';
    END IF;
END //
DELIMITER ;

/* Creamos el campo recomendado por en la tabla socio */

ALTER TABLE socio
ADD COLUMN recomendado_por INT DEFAULT NULL;

/* Crear la tabla Descuentos */

CREATE TABLE IF NOT EXISTS DESCUENTOS (
  idSocio INT NOT NULL,
  idSocioRecomendado INT NOT NULL,
  fechaDescuento DATE NOT NULL,
  Importe DECIMAL(10, 2) NOT NULL,
  PRIMARY KEY (idSocio, idSocioRecomendado)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;


/* Modificamos la tabla ACTIVIDAD para incluir el tipo de actividad y el precio de la sesion en caso de de ser actividad extra */

ALTER TABLE actividad
 ADD COLUMN tipo ENUM('Incluida', 'Extra') NOT NULL DEFAULT 'Incluida',
 ADD COLUMN precio_sesion DECIMAL(10, 2) DEFAULT NULL;
 
 
 /* Creamos el Trigger en la tabla Actividad para que cuando se cree una actividad extra se obligue a indicar un precio.*/

DELIMITER //
CREATE TRIGGER before_actividad_insert
BEFORE INSERT ON actividad
FOR EACH ROW
BEGIN
    IF NEW.tipo = 'Extra' AND NEW.precio_sesion IS NULL THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Se debe indicar el precio por sesión para las actividades extras.';
    END IF;
END //
DELIMITER ;

/* Creamos la tabla Inscripciones */

CREATE TABLE IF NOT EXISTS inscripciones (
  idActividad int NOT NULL,
  idSocio int NOT NULL,
  fechaSesion date NOT NULL,
  horaSesion time NOT NULL,
  importe decimal(10, 2) NOT NULL,
  PRIMARY KEY (idActividad, idSocio, fechaSesion, horaSesion)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

/* 
Crearmos trigger para verificar:
	- Que la actividad sea de tipo extra.
	- Que la actividad este en el horario.
	- El aforo de la actividad.
	- Asignamos el importe de la sesión.
	- Actualizamos el número de participantes.
*/

DELIMITER //
CREATE TRIGGER before_inscripcion_insert
BEFORE INSERT ON inscripciones
FOR EACH ROW
BEGIN
  DECLARE v_tipo VARCHAR(10);
  DECLARE v_precio_session DECIMAL(10, 2);
  DECLARE v_aforo INT;
  DECLARE v_participantes INT;

  -- Verificamos que la actividad es de tipo "Extra"
  SELECT tipo, precio_sesion INTO v_tipo, v_precio_session FROM actividad WHERE id_actividad = NEW.idActividad;
  IF v_tipo != 'Extra' THEN
    SIGNAL SQLSTATE '45000'
    SET MESSAGE_TEXT = 'La actividad no es extra, no se puede inscribir';
  END IF;

  -- Verificamos que la actividad está en horario
  SELECT aforo, participantes INTO v_aforo, v_participantes
  FROM horario
  JOIN instalacion ON horario.id_instalacion = instalacion.id_instalacion
  WHERE id_actividad = NEW.idActividad AND fecha = NEW.fechaSesion AND hora = NEW.horaSesion;

  IF v_aforo IS NULL THEN
    SIGNAL SQLSTATE '45000'
    SET MESSAGE_TEXT = 'La actividad no está disponible en el horario especificado';
  END IF;

  -- Verificamos que hay cupo de aforo en la actividad
  IF v_participantes >= v_aforo THEN
    SIGNAL SQLSTATE '45000'
    SET MESSAGE_TEXT = 'La actividad ya está llena';
  END IF;

  -- Asignamos el importe de la sesión
  SET NEW.importe = v_precio_session;

  -- Actualizamos la cantidad de participantes en el horario
  UPDATE horario
  SET participantes = v_participantes + 1
  WHERE id_actividad = NEW.idActividad AND fecha = NEW.fechaSesion AND hora = NEW.horaSesion;
END;
//
DELIMITER ;

/*12. Volvemos a crear las FK */

-- Corporativo
ALTER TABLE corporativo
	ADD CONSTRAINT socio_corporativo FOREIGN KEY (id_socio) REFERENCES socio (id_socio)
	ON UPDATE CASCADE -- Si se actualiza el id_socio, queremos que se refleje en esta tabla
	ON DELETE CASCADE; -- Si se elimina el socio, también queremos eliminar su relación con corporativo

ALTER TABLE corporativo
	ADD CONSTRAINT socio_empresa FOREIGN KEY (nif) REFERENCES empresa (nif)
	ON UPDATE CASCADE -- Si se actualiza el id_empresa, queremos que se refleje en esta tabla
	ON DELETE CASCADE; -- Si se elimina la empresa, también queremos eliminar su relación con corporativo

-- Historico
ALTER TABLE historico
	ADD CONSTRAINT historico_socio FOREIGN KEY (id_socio) REFERENCES socio (id_socio)
	ON UPDATE CASCADE -- Si se actualiza el id_socio, queremos que se refleje en esta tabla
	ON DELETE CASCADE; -- Si se elimina el socio, también queremos eliminar su historial

-- Horario
ALTER TABLE horario
	ADD CONSTRAINT horario_actividad FOREIGN KEY (id_actividad) REFERENCES actividad (id_actividad)
	ON UPDATE CASCADE -- Si se actualiza el id_actividad, queremos que se refleje en esta tabla
	ON DELETE CASCADE; -- Si se elimina la actividad, también queremos eliminar su horario

ALTER TABLE horario
	ADD CONSTRAINT horario_instalacion FOREIGN KEY (id_instalacion) REFERENCES instalacion (id_instalacion)
	ON UPDATE CASCADE -- Si se actualiza el id_instalacion, queremos que se refleje en esta tabla
	ON DELETE CASCADE; -- Si se elimina la instalación, también queremos eliminar su horario

-- Ponemos a "0" el check de la FK porque hemos añadido en la tabla horario la columna id_monitor
-- al existir ya registros dentro de la tabla si ejecutamos la creación del FK nos da "Error 1452"
SET FOREIGN_KEY_CHECKS=0;

ALTER TABLE horario
    ADD CONSTRAINT horario_monitor FOREIGN KEY (id_monitor) REFERENCES monitores (id_monitor)
	ON UPDATE CASCADE -- Si se actualiza el id_monitor, queremos que se refleje en esta tabla
	ON DELETE CASCADE; -- Si se elimina el monitor, también queremos eliminar su horario

-- Una vez creada dicha FK volvemos a poner el check a 1
SET FOREIGN_KEY_CHECKS=1;

-- Principal
ALTER TABLE principal
    ADD CONSTRAINT principal_socio FOREIGN KEY (idsocio) REFERENCES socio (id_socio)
	ON UPDATE CASCADE -- Si se actualiza el id_socio, queremos que se refleje en esta tabla
	ON DELETE CASCADE; -- Si se elimina el socio, también queremos eliminar su designación como principal

-- Seguimiento
ALTER TABLE seguimiento
	ADD CONSTRAINT seguimient_socio FOREIGN KEY (id_socio) REFERENCES socio (id_socio) 
	ON UPDATE CASCADE -- Si se actualiza el id_socio, queremos que se refleje en esta tabla
	ON DELETE CASCADE; -- Si se elimina el socio, también queremos eliminar su seguimiento

-- Socio (Plan)
ALTER TABLE socio
	ADD CONSTRAINT socio_plan FOREIGN KEY (id_plan) REFERENCES plan(id_plan) 
	ON UPDATE CASCADE -- Si se actualiza el id_plan, queremos que se refleje en esta tabla
	ON DELETE CASCADE; -- Si se elimina el plan, también queremos eliminar el plan

-- Actividad Monitor
ALTER TABLE actividad_monitor
	ADD CONSTRAINT actividad_monitor_actividad FOREIGN KEY (id_actividad) REFERENCES actividad(id_actividad) 
	ON UPDATE CASCADE -- Si se actualiza el id_actividad, queremos que se refleje en esta tabla
	ON DELETE CASCADE; -- Si se elimina la actividad, también queremos eliminar su relación con los monitores

ALTER TABLE actividad_monitor
	ADD CONSTRAINT actividad_monitor_monitores FOREIGN KEY (id_monitor) REFERENCES monitores(id_monitor) 
	ON UPDATE CASCADE -- Si se actualiza el id_monitor, queremos que se refleje en esta tabla
	ON DELETE CASCADE; -- Si se elimina el monitor, también queremos eliminar su relación con las actividades

-- Descuentos
ALTER TABLE DESCUENTOS
	ADD CONSTRAINT descuentos_socio FOREIGN KEY (idSocio) REFERENCES socio(id_socio) 
	ON UPDATE CASCADE -- Si se actualiza el id_socio, queremos que se refleje en esta tabla
	ON DELETE CASCADE; -- Si se elimina el socio, también queremos eliminar su información de descuentos

ALTER TABLE DESCUENTOS
	ADD CONSTRAINT descuentos_socio_recomendado FOREIGN KEY (idSocioRecomendado) REFERENCES socio(id_socio) 
	ON UPDATE CASCADE -- Si se actualiza el id_socio, queremos que se refleje en esta tabla
	ON DELETE CASCADE; -- Si se elimina el socio recomendado, también queremos eliminar su información de descuentos

-- Inscripciones
ALTER TABLE inscripciones
	ADD CONSTRAINT inscripciones_actividad FOREIGN KEY (idActividad) REFERENCES actividad(id_actividad) 
	ON UPDATE CASCADE -- Si se actualiza el id_actividad, queremos que se refleje en esta tabla
	ON DELETE CASCADE; -- Si se elimina la actividad, también queremos eliminar las inscripciones

ALTER TABLE inscripciones
	ADD CONSTRAINT inscripciones_socio FOREIGN KEY (idSocio) REFERENCES socio(id_socio) 
	ON UPDATE CASCADE -- Si se actualiza el id_socio, queremos que se refleje en esta tabla
	ON DELETE CASCADE; -- Si se elimina el socio, también queremos eliminar sus inscripciones
    
/* 13. Revisar las tablas de la Base de Datos y generar dos restricciones de tipo check para controlar la integridad de los datos.
*/

-- Tabla Actividad la duración sea de 30 a 120 minutos

ALTER TABLE actividad
 ADD CONSTRAINT check_duracion CHECK (duracion_sesion_minutos BETWEEN 30 AND 120) ENFORCED;
 
-- Añadimos una restricción que esté dentro de un rango razonable, digamos entre 1% y 70%.
ALTER TABLE seguimiento
ADD CONSTRAINT check_porcentaje_grasa
CHECK (porcentaje_grasa_corporal >= 0.01 AND porcentaje_grasa_corporal <= 0.7);

-- Restriccion para asegurarnos que la fecha inical del un convenio sea anterior o igual a la fecha final del convenio

ALTER TABLE empresa
ADD CONSTRAINT check_fechas_convenio
CHECK (fecha_inicio_convenio <= fecha_fin_convenio OR fecha_fin_convenio IS NULL);

-- Restricción con el horario del gimnasio, suponemos que el horario es de 07:00 a 23:00 y se verifica que no hay una actividad
-- fuera de ese horario.

ALTER TABLE horario
ADD CONSTRAINT check_hora_actividad
CHECK (hora >= '07:00:00' AND hora <= '23:00:00');

-- Resticción para impedir que los valores de la matricula y la cuota sean inferior a 0.
ALTER TABLE plan
ADD CONSTRAINT check_cuota_matricula
CHECK (cuota_mensual > 0 AND matricula >= 0);

/*14) Crear dos campos autocalculados en diferentes tablas de la Base de Datos.
*/

-- Autocalcula la cuota total anual que tendá el socio en la columna total_cuota_anual
ALTER TABLE plan
ADD COLUMN total_cuota_anual DECIMAL(12,2) GENERATED ALWAYS AS (cuota_mensual * 12) STORED;

-- Autocalcula el indice de masa corporal con los valores del peso y la estatura del socio
ALTER TABLE seguimiento
ADD COLUMN imc DECIMAL(10,2) GENERATED ALWAYS AS (peso / (estatura_cm / 100 * estatura_cm / 100)) STORED;


/*15)
Crear un disparador que al llenar en la tabla SOCIO el campo Recomendado por cree el registro pertinente en la tabla DESCUENTOS. 
Probar el disparador agregando dos nuevos socios recomendados.

Creamos un Trigger con el 25% de descuento */ 

DELIMITER //
CREATE TRIGGER after_socio_insert
AFTER INSERT ON socio
FOR EACH ROW
BEGIN
    DECLARE descuento DECIMAL(10, 2);
    IF NEW.recomendado_por IS NOT NULL THEN
        SELECT cuota_mensual * 0.25 INTO descuento
        FROM plan
        JOIN socio ON socio.id_plan = plan.id_plan
        WHERE socio.id_socio = NEW.recomendado_por;

        INSERT INTO DESCUENTOS (idSocio, idSocioRecomendado, fechaDescuento, Importe)
        VALUES (NEW.recomendado_por, NEW.id_socio, CURDATE(), descuento);
    END IF;
END //
DELIMITER ;

-- Comprobación insertando dos nuevos registros con el campo recomendado

INSERT INTO SOCIO (documento_identidad, nombre, apellido1, fecha_nacimiento, id_plan, fecha_alta, activo, telefono_contacto, email, codigo_postal, recomendado_por)
VALUES 
('12345678X', 'Juan', 'Perez', '1990-01-01', 1, '2023-01-01', 1, '123456789', 'juan.perez@email.com', '28001', 1),
('23456789Y', 'Maria', 'Gomez', '1992-02-02', 2, '2023-01-01', 1, '987654321', 'maria.gomez@email.com', '28002', 2);

/*16)
	Diseñar un disparador que prevenga que un monitor no pueda impartir dos clases (actividades) al mismo tiempo en la tabla horario.
*/

DELIMITER //
CREATE TRIGGER before_insert_horario
BEFORE INSERT ON horario
FOR EACH ROW
BEGIN
    DECLARE monitor_count INT;
    
    SELECT COUNT(*)
    INTO monitor_count
    FROM horario
    WHERE monitor = NEW.monitor
    AND fecha = NEW.fecha
    AND hora = NEW.hora;
    
    IF monitor_count > 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Este monitor ya tiene una actividad programada en el mismo horario.';
    END IF;
END;
//
DELIMITER ;

/*17) 
	Inventar un disparador. Describirlo y justificarlo haciendo uso de los comentarios en la plantilla.

	El siguiente disparador se ejecuta antes de eliminar una instalación, realiza una comprobación de que no hayan activiades programas antes de eliminar la instalación.
*/

DELIMITER //
CREATE TRIGGER before_instalacion_delete
BEFORE DELETE ON instalacion
FOR EACH ROW
BEGIN
  IF EXISTS (SELECT 1 FROM horario WHERE id_instalacion = OLD.id_instalacion) THEN
    SIGNAL SQLSTATE '45000'
    SET MESSAGE_TEXT = 'Error: No se puede eliminar la instalación porque hay actividades programadas en ella.';
  END IF;
END;
//
DELIMITER ;

/*18)

-- Insertar un mínimo de 10 registros en las tablas MONITORES, INSTALACIONES, HORARIO e INSCRIPCIONES.
*/

INSERT INTO monitores 
(documento_identificacion, nombre, apellidos, titulaciones, telefono_fijo, telefono_movil) 
VALUES 
('12345678A', 'Ana', 'Martínez López', 'Entrenador Personal', '912345678', '612345678'),
('12345678B', 'Luis', 'Gómez Sánchez', 'Fisioterapeuta', '912345679', '612345679'),
('12345678C', 'Sofía', 'Pérez Rodríguez', 'Nutricionista', NULL, '612345680'),
('12345678D', 'Carlos', 'Fernández Jiménez', 'Instructor Yoga', '912345681', '612345681'),
('12345678E', 'Laura', 'García Ortega', 'Entrenador Personal', NULL, '612345682'),
('12345678F', 'Javier', 'Martín Alonso', 'Instructor Pilates', '912345683', '612345683'),
('12345678G', 'Carmen', 'Rodríguez Mora', 'Entrenador Natación', NULL, '612345684'),
('12345678H', 'David', 'López Casado', 'Fisioterapeuta', '912345685', '612345685'),
('12345678I', 'Patricia', 'González Ramiro', 'Nutricionista', NULL, '612345686'),
('12345678J', 'Fernando', 'Romero Peña', 'Entrenador Personal', '912345686', '612345687');

INSERT INTO instalacion (id_instalacion, zona, denominacion, descripcion_zona, metros_cuadrados, aforo) VALUES
(16, 'A', 'Sala de Yoga', '', 80, 25),
(17, 'A', 'Sala de Pilates', '', 70, 20),
(18, 'A', 'Zona de Pesas', '', 90, 30),
(19, 'B', 'Cafetería', '', 50, 20),
(20, 'B', 'Tienda Deportiva', 'Venta de artículos deportivos', 40, 10),
(21, 'B', 'Sala de Juegos', '', 60, 15),
(22, 'C', 'Estudio de Danza', '', 80, 25),
(23, 'C', 'Sala de Artes Marciales', '', 100, 30),
(24, 'C', 'Zona de Entrenamiento Funcional', '', 70, 20),
(25, 'C', 'Zona de Estiramientos', '', 60, 15);


INSERT INTO horario (id_actividad, id_instalacion, fecha, hora, monitor, observaciones, id_monitor, participantes) VALUES
(1, 5, '2023-11-01', '08:00:00', '', '', 1, 5),
(2, 5, '2023-11-01', '09:00:00', '', '', 2, 6),
(3, 5, '2023-11-02', '10:00:00', '', '', 3, 7),
(4, 5, '2023-11-02', '11:00:00', '', '', 4, 5),
(5, 5, '2023-11-03', '12:00:00', '', '', 5, 6),
(6, 6, '2023-11-03', '13:00:00', '', '', 6, 7),
(7, 6, '2023-11-04', '14:00:00', '', '', 7, 5),
(8, 6, '2023-11-04', '15:00:00', '', '', 8, 6),
(9, 6, '2023-11-05', '16:00:00', '', '', 9, 7),
(10, 6, '2023-11-05', '17:00:00', '', '', 10, 5);


INSERT INTO actividad (actividad, descripcion, dirigida_a, nivel, duracion_sesion_minutos, tipo, precio_sesion) VALUES 
('Yoga Avanzado', 'Clase de yoga para niveles avanzados, enfocada en mejorar la flexibilidad y la concentración', 'Adultos', 'Avanzado', 60, 'Extra', 15.00),
('Boxeo', 'Clase de boxeo para iniciarse', 'Todo Público', 'Inicial', 120, 'Extra', 20.00),
('Clase de Baile', 'Clase dinámica de baile para aprender nuevos estilos y mejorar la coordinación y agilidad', 'Niños', 'Intermedio', 45, 'Extra', 10.00),
('Entrenamiento Funcional', 'Sesión intensiva de entrenamiento funcional para mejorar la fuerza y resistencia', 'Adultos', 'Intermedio', 30, 'Extra', 12.50),
('Meditación y Relajación', 'Sesión guiada de meditación y técnicas de relajación para reducir el estrés', 'Todo Público', 'Inicial', 30, 'Extra', 8.00);


-- Para hacer las inscriciones de estas actividades vamos a añadirlas en el horario.

INSERT INTO horario (id_actividad, id_instalacion, fecha, hora, monitor, observaciones, id_monitor, participantes) VALUES
(22, 5, '2023-11-01', '08:30:00', '', '', 10, 5),
(23, 5, '2023-11-01', '09:30:00', '', '', 9, 6),
(24, 5, '2023-11-02', '10:30:00', '', '', 8, 7),
(25, 5, '2023-11-02', '11:30:00', '', '', 7, 5),
(26, 5, '2023-11-03', '12:30:00', '', '', 6, 6),
(22, 6, '2023-11-03', '13:30:00', '', '', 5, 7),
(23, 6, '2023-11-04', '14:30:00', '', '', 4, 5),
(24, 6, '2023-11-04', '15:30:00', '', '', 3, 6),
(25, 6, '2023-11-05', '16:30:00', '', '', 2, 7),
(26, 6, '2023-11-05', '17:30:00', '', '', 1, 5);


INSERT INTO inscripciones (idActividad, idSocio, fechaSesion, horaSesion, importe) VALUES 
(22, 1, '2023-11-01', '08:30:00', 15.00),
(23, 2, '2023-11-01', '09:30:00', 20.00),
(24, 3, '2023-11-02', '10:30:00', 10.00),
(25, 4, '2023-11-02', '11:30:00', 12.50),
(26, 5, '2023-11-03', '12:30:00', 8.00),
(22, 6, '2023-11-03', '13:30:00', 15.00),
(23, 7, '2023-11-04', '14:30:00', 20.00),
(24, 8, '2023-11-04', '15:30:00', 10.00),
(25, 9, '2023-11-05', '16:30:00', 12.50),
(26, 10, '2023-11-05', '17:30:00', 8.00);

