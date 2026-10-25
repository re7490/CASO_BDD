DROP DATABASE IF EXISTS saludusm;
CREATE DATABASE saludusm CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE saludusm;

-- =======================================================================================
-- TABLAS DE DOMINIO Y CATÁLOGOS
-- =======================================================================================

CREATE TABLE estado_cita (
    nombre_estado VARCHAR(20) PRIMARY KEY
);

INSERT INTO estado_cita (nombre_estado) VALUES 
('Reservada'), ('Confirmada'), ('Atendida'), ('No Asistió'), ('Cancelada');

CREATE TABLE prevision (
    nombre_prevision VARCHAR(20) PRIMARY KEY
);

INSERT INTO prevision (nombre_prevision) VALUES 
('Fonasa'), ('Isapre'), ('Particular');

CREATE TABLE especialidad (
    nombre_especialidad VARCHAR(50) PRIMARY KEY
);

-- =======================================================================================
-- TABLA DE USUARIOS / AUTENTICACIÓN
-- =======================================================================================

CREATE TABLE usuario (
    id_usuario INT AUTO_INCREMENT PRIMARY KEY,
    rut VARCHAR(12) NOT NULL UNIQUE,
    email VARCHAR(100) NOT NULL UNIQUE,
    password_hash VARCHAR(255) NOT NULL,
    rol ENUM('paciente', 'medico', 'admin') NOT NULL
);

-- =======================================================================================
-- ENTIDADES CLÍNICAS Y DE GESTIÓN
-- =======================================================================================

CREATE TABLE diagnostico (
    codigo_cie10 VARCHAR(10) PRIMARY KEY,
    descripcion VARCHAR(150) NOT NULL
);

CREATE TABLE centro_medico (
    codigo_centro INT PRIMARY KEY,
    nombre_centro VARCHAR(100) NOT NULL,
    comuna VARCHAR(50) NOT NULL,
    region VARCHAR(50) NOT NULL
);

CREATE TABLE paciente (
    rut_paciente VARCHAR(12) PRIMARY KEY,
    nombre_completo VARCHAR(100) NOT NULL,
    fecha_nacimiento DATE NOT NULL,
    sexo ENUM('M', 'F', 'Otro') NOT NULL,
    telefono VARCHAR(15),
    comuna_residencia VARCHAR(50) NOT NULL,
    nombre_prevision VARCHAR(20) NOT NULL,
    id_usuario INT UNIQUE,
    FOREIGN KEY (nombre_prevision) REFERENCES prevision(nombre_prevision) ON UPDATE CASCADE,
    FOREIGN KEY (id_usuario) REFERENCES usuario(id_usuario) ON DELETE CASCADE
);

CREATE TABLE medico (
    rut_medico VARCHAR(12) PRIMARY KEY,
    nombre_completo VARCHAR(100) NOT NULL,
    email_institucional VARCHAR(100) NOT NULL UNIQUE,
    id_usuario INT UNIQUE,
    FOREIGN KEY (id_usuario) REFERENCES usuario(id_usuario) ON DELETE SET NULL
);

CREATE TABLE medico_especialidad (
    rut_medico VARCHAR(12) NOT NULL,
    nombre_especialidad VARCHAR(50) NOT NULL,
    PRIMARY KEY (rut_medico, nombre_especialidad),
    FOREIGN KEY (rut_medico) REFERENCES medico(rut_medico) ON DELETE CASCADE ON UPDATE CASCADE,
    FOREIGN KEY (nombre_especialidad) REFERENCES especialidad(nombre_especialidad) ON UPDATE CASCADE
);

CREATE TABLE medico_centro (
    rut_medico VARCHAR(12) NOT NULL,
    codigo_centro INT NOT NULL,
    PRIMARY KEY (rut_medico, codigo_centro),
    FOREIGN KEY (rut_medico) REFERENCES medico(rut_medico) ON DELETE CASCADE ON UPDATE CASCADE,
    FOREIGN KEY (codigo_centro) REFERENCES centro_medico(codigo_centro) ON DELETE CASCADE ON UPDATE CASCADE
);

-- =======================================================================================
-- CITAS, ATENCIONES Y RECETAS
-- =======================================================================================

CREATE TABLE cita_medica (
    id_cita INT AUTO_INCREMENT PRIMARY KEY,
    fecha DATE NOT NULL,
    hora TIME NOT NULL,
    rut_paciente VARCHAR(12) NOT NULL,
    rut_medico VARCHAR(12) NOT NULL,
    codigo_centro INT NOT NULL,
    nombre_especialidad VARCHAR(50) NOT NULL,
    estado VARCHAR(20) NOT NULL DEFAULT 'Reservada',
    CONSTRAINT unq_paciente_horario UNIQUE (fecha, hora, rut_paciente),
    CONSTRAINT unq_medico_horario UNIQUE (fecha, hora, rut_medico),
    FOREIGN KEY (rut_paciente) REFERENCES paciente(rut_paciente) ON DELETE CASCADE ON UPDATE CASCADE,
    FOREIGN KEY (rut_medico) REFERENCES medico(rut_medico) ON UPDATE CASCADE,
    FOREIGN KEY (codigo_centro) REFERENCES centro_medico(codigo_centro) ON UPDATE CASCADE,
    FOREIGN KEY (nombre_especialidad) REFERENCES especialidad(nombre_especialidad) ON UPDATE CASCADE,
    FOREIGN KEY (estado) REFERENCES estado_cita(nombre_estado) ON UPDATE CASCADE
);

CREATE TABLE atencion (
    id_atencion INT AUTO_INCREMENT PRIMARY KEY,
    id_cita INT NOT NULL UNIQUE,
    fecha_atencion DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    motivo_consulta VARCHAR(255) NOT NULL,
    observaciones TEXT,
    FOREIGN KEY (id_cita) REFERENCES cita_medica(id_cita) ON DELETE CASCADE
);

CREATE TABLE atencion_diagnostico (
    id_atencion INT NOT NULL,
    codigo_cie10 VARCHAR(10) NOT NULL,
    PRIMARY KEY (id_atencion, codigo_cie10),
    FOREIGN KEY (id_atencion) REFERENCES atencion(id_atencion) ON DELETE CASCADE,
    FOREIGN KEY (codigo_cie10) REFERENCES diagnostico(codigo_cie10) ON UPDATE CASCADE
);

CREATE TABLE receta (
    id_receta INT AUTO_INCREMENT PRIMARY KEY,
    id_atencion INT NOT NULL,
    medicamento VARCHAR(100) NOT NULL,
    dosis VARCHAR(100) NOT NULL,
    dias_tratamiento INT NOT NULL CHECK (dias_tratamiento > 0),
    FOREIGN KEY (id_atencion) REFERENCES atencion(id_atencion) ON DELETE CASCADE
);

-- =======================================================================================
-- TRIGGER: REGLAS DE NEGOCIO PARA CITAS
-- =======================================================================================

DELIMITER //

CREATE TRIGGER trg_validar_reglas_cita
BEFORE INSERT ON cita_medica
FOR EACH ROW
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM medico_especialidad 
        WHERE rut_medico = NEW.rut_medico AND nombre_especialidad = NEW.nombre_especialidad
    ) THEN
        SIGNAL SQLSTATE '45000' 
        SET MESSAGE_TEXT = 'Error: El médico no posee la especialidad indicada.';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM medico_centro 
        WHERE rut_medico = NEW.rut_medico AND codigo_centro = NEW.codigo_centro
    ) THEN
        SIGNAL SQLSTATE '45000' 
        SET MESSAGE_TEXT = 'Error: El médico no atiende en el centro médico seleccionado.';
    END IF;
END //

CREATE TRIGGER trg_limite_especialidades
BEFORE INSERT ON medico_especialidad
FOR EACH ROW
BEGIN
    DECLARE total INT;
    SELECT COUNT(*) INTO total FROM medico_especialidad WHERE rut_medico = NEW.rut_medico;
    IF total >= 3 THEN
        SIGNAL SQLSTATE '45000' 
        SET MESSAGE_TEXT = 'Error: El médico no puede registrar más de 3 especialidades.';
    END IF;
END //

DELIMITER ;

-- =======================================================================================
-- VIEW: BÚSQUEDA AVANZADA Y RESUMEN
-- =======================================================================================

CREATE OR REPLACE VIEW vw_resumen_citas AS
SELECT 
    c.id_cita,
    c.fecha,
    c.hora,
    c.estado,
    p.rut_paciente,
    p.nombre_completo AS nombre_paciente,
    p.nombre_prevision AS prevision,
    m.rut_medico,
    m.nombre_completo AS nombre_medico,
    c.nombre_especialidad AS especialidad,
    cm.codigo_centro,
    cm.nombre_centro,
    cm.region,
    cm.comuna
FROM cita_medica c
JOIN paciente p ON c.rut_paciente = p.rut_paciente
JOIN medico m ON c.rut_medico = m.rut_medico
JOIN centro_medico cm ON c.codigo_centro = cm.codigo_centro;

-- =======================================================================================
-- FUNCTION: PORCENTAJE DE INASISTENCIA PARA PANEL ADMIN
-- =======================================================================================

DELIMITER //

CREATE FUNCTION fn_porcentaje_inasistencia(p_codigo_centro INT) 
RETURNS DECIMAL(5,2)
DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE total_citas INT DEFAULT 0;
    DECLARE citas_no_asistio INT DEFAULT 0;
    DECLARE porcentaje DECIMAL(5,2) DEFAULT 0.00;

    SELECT COUNT(*) INTO total_citas 
    FROM cita_medica 
    WHERE codigo_centro = p_codigo_centro;

    IF total_citas > 0 THEN
        SELECT COUNT(*) INTO citas_no_asistio 
        FROM cita_medica 
        WHERE codigo_centro = p_codigo_centro AND estado = 'No Asistió';
        
        SET porcentaje = (citas_no_asistio / total_citas) * 100;
    END IF;

    RETURN porcentaje;
END //

-- =======================================================================================
-- STORED PROCEDURE: ACTUALIZAR CITAS VENCIDAS
-- =======================================================================================

CREATE PROCEDURE sp_cancelar_citas_vencidas()
BEGIN
    UPDATE cita_medica
    SET estado = 'Cancelada'
    WHERE estado IN ('Reservada', 'Confirmada')
      AND (fecha < CURDATE() OR (fecha = CURDATE() AND hora < CURTIME()));
END //

DELIMITER ;

-- =======================================================================================
-- POBLAMIENTO DE DATOS (CUMPLE CON VOLÚMENES Y REGLAS T3)
-- =======================================================================================

-- 1. Especialidades (8 especialidades requeridas)
INSERT INTO especialidad (nombre_especialidad) VALUES 
('Medicina General'), ('Pediatría'), ('Cardiología'), ('Dermatología'), ('Traumatología'), ('Neurología'), ('Ginecología'), ('Oftalmología');

-- 2. Diagnósticos CIE-10
INSERT INTO diagnostico (codigo_cie10, descripcion) VALUES 
('J00', 'Rinofaringitis aguda (resfriado común)'),
('I10', 'Hipertensión esencial (primaria)'),
('E11', 'Diabetes mellitus no insulinodependiente'),
('K21', 'Enfermedad por reflujo gastroesofágico'),
('M54', 'Dorsalgia / Lumbalgia'),
('J06', 'Infección aguda de las vías respiratorias superiores'),
('B34', 'Infección viral de sitio no especificado'),
('L20', 'Dermatitis atópica'),
('S83', 'Esguince y desgarro de la rodilla'),
('G43', 'Migraña y cefaleas afines'),
('H10', 'Conjuntivitis aguda'),
('N39', 'Infección del tracto urinario');

-- 3. Centros Médicos (4 centros en 2 regiones)
INSERT INTO centro_medico (codigo_centro, nombre_centro, comuna, region) VALUES 
(101, 'Centro Médico Casa Central', 'Valparaíso', 'Valparaíso'),
(102, 'Centro Médico Viña del Mar', 'Viña del Mar', 'Valparaíso'),
(103, 'Centro Médico San Joaquín', 'San Joaquín', 'Metropolitana'),
(104, 'Centro Médico Providencia', 'Providencia', 'Metropolitana');

-- 4. Usuarios: Administrador (id: 1)
INSERT INTO usuario (id_usuario, rut, email, password_hash, rol) VALUES 
(1, '11111111-1', 'admin@saludusm.cl', '$2y$10$wO3uOaVpT/2xSvyV5Yy/Nu30Iu3Hh4dZf4uBqF8yD8e6kG6ElnQ0a', 'admin');

-- 5. Usuarios y Médicos (16 Médicos, id_usuario 2 al 17)
INSERT INTO usuario (id_usuario, rut, email, password_hash, rol) VALUES 
(2, '22222222-2', 'doctor.perez@saludusm.cl', '$2y$10$wO3uOaVpT/2xSvyV5Yy/Nu30Iu3Hh4dZf4uBqF8yD8e6kG6ElnQ0a', 'medico'),
(3, '22222223-0', 'ana.gomez@saludusm.cl', '$2y$10$wO3uOaVpT/2xSvyV5Yy/Nu30Iu3Hh4dZf4uBqF8yD8e6kG6ElnQ0a', 'medico'),
(4, '22222224-9', 'carlos.munoz@saludusm.cl', '$2y$10$wO3uOaVpT/2xSvyV5Yy/Nu30Iu3Hh4dZf4uBqF8yD8e6kG6ElnQ0a', 'medico'),
(5, '22222225-7', 'maria.lopez@saludusm.cl', '$2y$10$wO3uOaVpT/2xSvyV5Yy/Nu30Iu3Hh4dZf4uBqF8yD8e6kG6ElnQ0a', 'medico'),
(6, '22222226-5', 'jorge.valenzuela@saludusm.cl', '$2y$10$wO3uOaVpT/2xSvyV5Yy/Nu30Iu3Hh4dZf4uBqF8yD8e6kG6ElnQ0a', 'medico'),
(7, '22222227-3', 'carolina.rojas@saludusm.cl', '$2y$10$wO3uOaVpT/2xSvyV5Yy/Nu30Iu3Hh4dZf4uBqF8yD8e6kG6ElnQ0a', 'medico'),
(8, '22222228-1', 'ricardo.diaz@saludusm.cl', '$2y$10$wO3uOaVpT/2xSvyV5Yy/Nu30Iu3Hh4dZf4uBqF8yD8e6kG6ElnQ0a', 'medico'),
(9, '22222229-k', 'valentina.castro@saludusm.cl', '$2y$10$wO3uOaVpT/2xSvyV5Yy/Nu30Iu3Hh4dZf4uBqF8yD8e6kG6ElnQ0a', 'medico'),
(10, '22222230-3', 'felipe.morales@saludusm.cl', '$2y$10$wO3uOaVpT/2xSvyV5Yy/Nu30Iu3Hh4dZf4uBqF8yD8e6kG6ElnQ0a', 'medico'),
(11, '22222231-1', 'camila.herrera@saludusm.cl', '$2y$10$wO3uOaVpT/2xSvyV5Yy/Nu30Iu3Hh4dZf4uBqF8yD8e6kG6ElnQ0a', 'medico'),
(12, '22222232-x', 'gonzalo.araya@saludusm.cl', '$2y$10$wO3uOaVpT/2xSvyV5Yy/Nu30Iu3Hh4dZf4uBqF8yD8e6kG6ElnQ0a', 'medico'),
(13, '22222233-8', 'patricia.fuentes@saludusm.cl', '$2y$10$wO3uOaVpT/2xSvyV5Yy/Nu30Iu3Hh4dZf4uBqF8yD8e6kG6ElnQ0a', 'medico'),
(14, '22222234-6', 'esteban.vargas@saludusm.cl', '$2y$10$wO3uOaVpT/2xSvyV5Yy/Nu30Iu3Hh4dZf4uBqF8yD8e6kG6ElnQ0a', 'medico'),
(15, '22222235-4', 'claudia.navarro@saludusm.cl', '$2y$10$wO3uOaVpT/2xSvyV5Yy/Nu30Iu3Hh4dZf4uBqF8yD8e6kG6ElnQ0a', 'medico'),
(16, '22222236-2', 'rodrigo.sepulveda@saludusm.cl', '$2y$10$wO3uOaVpT/2xSvyV5Yy/Nu30Iu3Hh4dZf4uBqF8yD8e6kG6ElnQ0a', 'medico'),
(17, '22222237-0', 'daniela.pino@saludusm.cl', '$2y$10$wO3uOaVpT/2xSvyV5Yy/Nu30Iu3Hh4dZf4uBqF8yD8e6kG6ElnQ0a', 'medico');

INSERT INTO medico (rut_medico, nombre_completo, email_institucional, id_usuario) VALUES 
('22222222-2', 'Dr. Juan Pérez', 'doctor.perez@saludusm.cl', 2),
('22222223-0', 'Dra. Ana Gómez', 'ana.gomez@saludusm.cl', 3),
('22222224-9', 'Dr. Carlos Muñoz', 'carlos.munoz@saludusm.cl', 4),
('22222225-7', 'Dra. María López', 'maria.lopez@saludusm.cl', 5),
('22222226-5', 'Dr. Jorge Valenzuela', 'jorge.valenzuela@saludusm.cl', 6),
('22222227-3', 'Dra. Carolina Rojas', 'carolina.rojas@saludusm.cl', 7),
('22222228-1', 'Dr. Ricardo Díaz', 'ricardo.diaz@saludusm.cl', 8),
('22222229-k', 'Dra. Valentina Castro', 'valentina.castro@saludusm.cl', 9),
('22222230-3', 'Dr. Felipe Morales', 'felipe.morales@saludusm.cl', 10),
('22222231-1', 'Dra. Camila Herrera', 'camila.herrera@saludusm.cl', 11),
('22222232-x', 'Dr. Gonzalo Araya', 'gonzalo.araya@saludusm.cl', 12),
('22222233-8', 'Dra. Patricia Fuentes', 'patricia.fuentes@saludusm.cl', 13),
('22222234-6', 'Dr. Esteban Vargas', 'esteban.vargas@saludusm.cl', 14),
('22222235-4', 'Dra. Claudia Navarro', 'claudia.navarro@saludusm.cl', 15),
('22222236-2', 'Dr. Rodrigo Sepúlveda', 'rodrigo.sepulveda@saludusm.cl', 16),
('22222237-0', 'Dra. Daniela Pino', 'daniela.pino@saludusm.cl', 17);

-- Especialidades por médico (máximo 3 por trigger)
INSERT INTO medico_especialidad (rut_medico, nombre_especialidad) VALUES 
('22222222-2', 'Medicina General'), ('22222222-2', 'Cardiología'),
('22222223-0', 'Pediatría'),
('22222224-9', 'Pediatría'), ('22222224-9', 'Medicina General'),
('22222225-7', 'Dermatología'),
('22222226-5', 'Traumatología'),
('22222227-3', 'Neurología'),
('22222228-1', 'Ginecología'),
('22222229-k', 'Oftalmología'),
('22222230-3', 'Medicina General'),
('22222231-1', 'Pediatría'),
('22222232-x', 'Cardiología'),
('22222233-8', 'Dermatología'),
('22222234-6', 'Traumatología'),
('22222235-4', 'Neurología'),
('22222236-2', 'Ginecología'),
('22222237-0', 'Oftalmología');

-- Centros donde atienden los médicos
INSERT INTO medico_centro (rut_medico, codigo_centro) VALUES 
('22222222-2', 101), ('22222222-2', 102), ('22222222-2', 103),
('22222223-0', 101), ('22222223-0', 102),
('22222224-9', 103), ('22222224-9', 104),
('22222225-7', 101), ('22222225-7', 104),
('22222226-5', 102), ('22222226-5', 103),
('22222227-3', 101), ('22222227-3', 103),
('22222228-1', 102), ('22222228-1', 104),
('22222229-k', 101), ('22222229-k', 104),
('22222230-3', 101), ('22222230-3', 102), ('22222230-3', 103), ('22222230-3', 104),
('22222231-1', 101), ('22222231-1', 102),
('22222232-x', 103), ('22222232-x', 104),
('22222233-8', 101), ('22222233-8', 103),
('22222234-6', 102), ('22222234-6', 104),
('22222235-4', 101), ('22222235-4', 102),
('22222236-2', 103), ('22222236-2', 104),
('22222237-0', 101), ('22222237-0', 102), ('22222237-0', 103);

-- 6. Usuarios y Pacientes (42 Pacientes, id_usuario 18 al 59)
INSERT INTO usuario (id_usuario, rut, email, password_hash, rol) VALUES 
(18, '33333333-3', 'juan.paciente@gmail.com', '$2y$10$wO3uOaVpT/2xSvyV5Yy/Nu30Iu3Hh4dZf4uBqF8yD8e6kG6ElnQ0a', 'paciente'),
(19, '33333334-1', 'paciente19@mail.cl', '$2y$10$wO3uOaVpT/2xSvyV5Yy/Nu30Iu3Hh4dZf4uBqF8yD8e6kG6ElnQ0a', 'paciente'),
(20, '33333335-x', 'paciente20@mail.cl', '$2y$10$wO3uOaVpT/2xSvyV5Yy/Nu30Iu3Hh4dZf4uBqF8yD8e6kG6ElnQ0a', 'paciente'),
(21, '33333336-8', 'paciente21@mail.cl', '$2y$10$wO3uOaVpT/2xSvyV5Yy/Nu30Iu3Hh4dZf4uBqF8yD8e6kG6ElnQ0a', 'paciente'),
(22, '33333337-6', 'paciente22@mail.cl', '$2y$10$wO3uOaVpT/2xSvyV5Yy/Nu30Iu3Hh4dZf4uBqF8yD8e6kG6ElnQ0a', 'paciente'),
(23, '33333338-4', 'paciente23@mail.cl', '$2y$10$wO3uOaVpT/2xSvyV5Yy/Nu30Iu3Hh4dZf4uBqF8yD8e6kG6ElnQ0a', 'paciente'),
(24, '33333339-2', 'paciente24@mail.cl', '$2y$10$wO3uOaVpT/2xSvyV5Yy/Nu30Iu3Hh4dZf4uBqF8yD8e6kG6ElnQ0a', 'paciente'),
(25, '33333340-6', 'paciente25@mail.cl', '$2y$10$wO3uOaVpT/2xSvyV5Yy/Nu30Iu3Hh4dZf4uBqF8yD8e6kG6ElnQ0a', 'paciente'),
(26, '33333341-4', 'paciente26@mail.cl', '$2y$10$wO3uOaVpT/2xSvyV5Yy/Nu30Iu3Hh4dZf4uBqF8yD8e6kG6ElnQ0a', 'paciente'),
(27, '33333342-2', 'paciente27@mail.cl', '$2y$10$wO3uOaVpT/2xSvyV5Yy/Nu30Iu3Hh4dZf4uBqF8yD8e6kG6ElnQ0a', 'paciente'),
(28, '33333343-0', 'paciente28@mail.cl', '$2y$10$wO3uOaVpT/2xSvyV5Yy/Nu30Iu3Hh4dZf4uBqF8yD8e6kG6ElnQ0a', 'paciente'),
(29, '33333344-9', 'paciente29@mail.cl', '$2y$10$wO3uOaVpT/2xSvyV5Yy/Nu30Iu3Hh4dZf4uBqF8yD8e6kG6ElnQ0a', 'paciente'),
(30, '33333345-7', 'paciente30@mail.cl', '$2y$10$wO3uOaVpT/2xSvyV5Yy/Nu30Iu3Hh4dZf4uBqF8yD8e6kG6ElnQ0a', 'paciente'),
(31, '33333346-5', 'paciente31@mail.cl', '$2y$10$wO3uOaVpT/2xSvyV5Yy/Nu30Iu3Hh4dZf4uBqF8yD8e6kG6ElnQ0a', 'paciente'),
(32, '33333347-3', 'paciente32@mail.cl', '$2y$10$wO3uOaVpT/2xSvyV5Yy/Nu30Iu3Hh4dZf4uBqF8yD8e6kG6ElnQ0a', 'paciente'),
(33, '33333348-1', 'paciente33@mail.cl', '$2y$10$wO3uOaVpT/2xSvyV5Yy/Nu30Iu3Hh4dZf4uBqF8yD8e6kG6ElnQ0a', 'paciente'),
(34, '33333349-k', 'paciente34@mail.cl', '$2y$10$wO3uOaVpT/2xSvyV5Yy/Nu30Iu3Hh4dZf4uBqF8yD8e6kG6ElnQ0a', 'paciente'),
(35, '33333350-3', 'paciente35@mail.cl', '$2y$10$wO3uOaVpT/2xSvyV5Yy/Nu30Iu3Hh4dZf4uBqF8yD8e6kG6ElnQ0a', 'paciente'),
(36, '33333351-1', 'paciente36@mail.cl', '$2y$10$wO3uOaVpT/2xSvyV5Yy/Nu30Iu3Hh4dZf4uBqF8yD8e6kG6ElnQ0a', 'paciente'),
(37, '33333352-x', 'paciente37@mail.cl', '$2y$10$wO3uOaVpT/2xSvyV5Yy/Nu30Iu3Hh4dZf4uBqF8yD8e6kG6ElnQ0a', 'paciente'),
(38, '33333353-8', 'paciente38@mail.cl', '$2y$10$wO3uOaVpT/2xSvyV5Yy/Nu30Iu3Hh4dZf4uBqF8yD8e6kG6ElnQ0a', 'paciente'),
(39, '33333354-6', 'paciente39@mail.cl', '$2y$10$wO3uOaVpT/2xSvyV5Yy/Nu30Iu3Hh4dZf4uBqF8yD8e6kG6ElnQ0a', 'paciente'),
(40, '33333355-4', 'paciente40@mail.cl', '$2y$10$wO3uOaVpT/2xSvyV5Yy/Nu30Iu3Hh4dZf4uBqF8yD8e6kG6ElnQ0a', 'paciente'),
(41, '33333356-2', 'paciente41@mail.cl', '$2y$10$wO3uOaVpT/2xSvyV5Yy/Nu30Iu3Hh4dZf4uBqF8yD8e6kG6ElnQ0a', 'paciente'),
(42, '33333357-0', 'paciente42@mail.cl', '$2y$10$wO3uOaVpT/2xSvyV5Yy/Nu30Iu3Hh4dZf4uBqF8yD8e6kG6ElnQ0a', 'paciente'),
(43, '33333358-9', 'paciente43@mail.cl', '$2y$10$wO3uOaVpT/2xSvyV5Yy/Nu30Iu3Hh4dZf4uBqF8yD8e6kG6ElnQ0a', 'paciente'),
(44, '33333359-7', 'paciente44@mail.cl', '$2y$10$wO3uOaVpT/2xSvyV5Yy/Nu30Iu3Hh4dZf4uBqF8yD8e6kG6ElnQ0a', 'paciente'),
(45, '33333360-0', 'paciente45@mail.cl', '$2y$10$wO3uOaVpT/2xSvyV5Yy/Nu30Iu3Hh4dZf4uBqF8yD8e6kG6ElnQ0a', 'paciente'),
(46, '33333361-9', 'paciente46@mail.cl', '$2y$10$wO3uOaVpT/2xSvyV5Yy/Nu30Iu3Hh4dZf4uBqF8yD8e6kG6ElnQ0a', 'paciente'),
(47, '33333362-7', 'paciente47@mail.cl', '$2y$10$wO3uOaVpT/2xSvyV5Yy/Nu30Iu3Hh4dZf4uBqF8yD8e6kG6ElnQ0a', 'paciente'),
(48, '33333363-5', 'paciente48@mail.cl', '$2y$10$wO3uOaVpT/2xSvyV5Yy/Nu30Iu3Hh4dZf4uBqF8yD8e6kG6ElnQ0a', 'paciente'),
(49, '33333364-3', 'paciente49@mail.cl', '$2y$10$wO3uOaVpT/2xSvyV5Yy/Nu30Iu3Hh4dZf4uBqF8yD8e6kG6ElnQ0a', 'paciente'),
(50, '33333365-1', 'paciente50@mail.cl', '$2y$10$wO3uOaVpT/2xSvyV5Yy/Nu30Iu3Hh4dZf4uBqF8yD8e6kG6ElnQ0a', 'paciente'),
(51, '33333366-x', 'paciente51@mail.cl', '$2y$10$wO3uOaVpT/2xSvyV5Yy/Nu30Iu3Hh4dZf4uBqF8yD8e6kG6ElnQ0a', 'paciente'),
(52, '33333367-8', 'paciente52@mail.cl', '$2y$10$wO3uOaVpT/2xSvyV5Yy/Nu30Iu3Hh4dZf4uBqF8yD8e6kG6ElnQ0a', 'paciente'),
(53, '33333368-6', 'paciente53@mail.cl', '$2y$10$wO3uOaVpT/2xSvyV5Yy/Nu30Iu3Hh4dZf4uBqF8yD8e6kG6ElnQ0a', 'paciente'),
(54, '33333369-4', 'paciente54@mail.cl', '$2y$10$wO3uOaVpT/2xSvyV5Yy/Nu30Iu3Hh4dZf4uBqF8yD8e6kG6ElnQ0a', 'paciente'),
(55, '33333370-8', 'paciente55@mail.cl', '$2y$10$wO3uOaVpT/2xSvyV5Yy/Nu30Iu3Hh4dZf4uBqF8yD8e6kG6ElnQ0a', 'paciente'),
(56, '33333371-6', 'paciente56@mail.cl', '$2y$10$wO3uOaVpT/2xSvyV5Yy/Nu30Iu3Hh4dZf4uBqF8yD8e6kG6ElnQ0a', 'paciente'),
(57, '33333372-4', 'paciente57@mail.cl', '$2y$10$wO3uOaVpT/2xSvyV5Yy/Nu30Iu3Hh4dZf4uBqF8yD8e6kG6ElnQ0a', 'paciente'),
(58, '33333373-2', 'paciente58@mail.cl', '$2y$10$wO3uOaVpT/2xSvyV5Yy/Nu30Iu3Hh4dZf4uBqF8yD8e6kG6ElnQ0a', 'paciente'),
(59, '33333374-0', 'paciente59@mail.cl', '$2y$10$wO3uOaVpT/2xSvyV5Yy/Nu30Iu3Hh4dZf4uBqF8yD8e6kG6ElnQ0a', 'paciente');

INSERT INTO paciente (rut_paciente, nombre_completo, fecha_nacimiento, sexo, telefono, comuna_residencia, nombre_prevision, id_usuario) VALUES 
('33333333-3', 'Juan Silva', '1998-05-12', 'M', '987654321', 'Valparaíso', 'Fonasa', 18),
('33333334-1', 'Camila Soto', '1995-02-14', 'F', '911111111', 'Valparaíso', 'Fonasa', 19),
('33333335-x', 'Pedro Morales', '1987-08-23', 'M', '911111112', 'Viña del Mar', 'Isapre', 20),
('33333336-8', 'Francisca Araya', '2001-11-30', 'F', '911111113', 'Quilpué', 'Particular', 21),
('33333337-6', 'Andrés Castro', '1976-04-18', 'M', '911111114', 'San Joaquín', 'Fonasa', 22),
('33333338-4', 'Javiera Vergara', '1992-09-05', 'F', '911111115', 'Santiago', 'Isapre', 23),
('33333339-2', 'Matías Espinoza', '2005-01-12', 'M', '911111116', 'Providencia', 'Particular', 24),
('33333340-6', 'Constanza Vidal', '1983-06-25', 'F', '911111117', 'Valparaíso', 'Fonasa', 25),
('33333341-4', 'Diego Miranda', '1990-12-03', 'M', '911111118', 'Viña del Mar', 'Isapre', 26),
('33333342-2', 'Valentina Reyes', '1999-07-19', 'F', '911111119', 'San Joaquín', 'Fonasa', 27),
('33333343-0', 'Ignacio Fuentes', '1988-03-22', 'M', '911111120', 'Providencia', 'Isapre', 28),
('33333344-9', 'Catalina Herrera', '2000-10-15', 'F', '911111121', 'Valparaíso', 'Particular', 29),
('33333345-7', 'Sebastián Guzmán', '1993-05-28', 'M', '911111122', 'Viña del Mar', 'Fonasa', 30),
('33333346-5', 'Daniela Salazar', '1985-02-09', 'F', '911111123', 'San Joaquín', 'Isapre', 31),
('33333347-3', 'Tomás Bravo', '1979-11-14', 'M', '911111124', 'Santiago', 'Particular', 32),
('33333348-1', 'Paula Vega', '1996-08-01', 'F', '911111125', 'Valparaíso', 'Fonasa', 33),
('33333349-k', 'Lucas Cárdenas', '2003-04-11', 'M', '911111126', 'Viña del Mar', 'Fonasa', 34),
('33333350-3', 'Isidora Carrasco', '1991-01-30', 'F', '911111127', 'San Joaquín', 'Isapre', 35),
('33333351-1', 'Felipe Sepúlveda', '1982-09-17', 'M', '911111128', 'Providencia', 'Particular', 36),
('33333352-x', 'Fernanda Tapia', '1997-06-08', 'F', '911111129', 'Valparaíso', 'Fonasa', 37),
('33333353-8', 'Gabriel Ortiz', '2002-12-21', 'M', '911111130', 'Viña del Mar', 'Fonasa', 38),
('33333354-6', 'Bárbara Pizarro', '1986-07-04', 'F', '911111131', 'San Joaquín', 'Isapre', 39),
('33333355-4', 'Álvaro Núñez', '1994-03-16', 'M', '911111132', 'Santiago', 'Particular', 40),
('33333356-2', 'Nicole Riquelme', '1989-10-27', 'F', '911111133', 'Providencia', 'Fonasa', 41),
('33333357-0', 'Cristóbal Lagos', '2004-05-02', 'M', '911111134', 'Valparaíso', 'Isapre', 42),
('33333358-9', 'Antonia Henríquez', '1995-11-18', 'F', '911111135', 'Viña del Mar', 'Particular', 43),
('33333359-7', 'Joaquín Palma', '1978-08-10', 'M', '911111136', 'San Joaquín', 'Fonasa', 44),
('33333360-0', 'Monserrat Godoy', '2001-02-24', 'F', '911111137', 'Providencia', 'Fonasa', 45),
('33333361-9', 'Martín Paredes', '1984-04-06', 'M', '911111138', 'Valparaíso', 'Isapre', 46),
('33333362-7', 'Florencia Meza', '1999-09-13', 'F', '911111139', 'Viña del Mar', 'Particular', 47),
('33333363-5', 'Vicente Medina', '1992-01-07', 'M', '911111140', 'San Joaquín', 'Fonasa', 48),
('33333364-3', 'Sofía Sanhueza', '1981-12-29', 'F', '911111141', 'Santiago', 'Isapre', 49),
('33333365-1', 'Benjamín Leiva', '2006-03-14', 'M', '911111142', 'Providencia', 'Particular', 50),
('33333366-x', 'Macarena Valdés', '1990-07-22', 'F', '911111143', 'Valparaíso', 'Fonasa', 51),
('33333367-8', 'Maximiliano Gallardo', '1987-10-09', 'M', '911111144', 'Viña del Mar', 'Fonasa', 52),
('33333368-6', 'Josefa Pino', '2000-06-17', 'F', '911111145', 'San Joaquín', 'Isapre', 53),
('33333369-4', 'Esteban Maldonado', '1975-05-31', 'M', '911111146', 'Providencia', 'Particular', 54),
('33333370-8', 'Emilia Figueroa', '1998-02-11', 'F', '911111147', 'Valparaíso', 'Fonasa', 55),
('33333371-6', 'Guillermo Peña', '1983-08-20', 'M', '911111148', 'Viña del Mar', 'Isapre', 56),
('33333372-4', 'Pía Alarcón', '2003-11-04', 'F', '911111149', 'San Joaquín', 'Particular', 57),
('33333373-2', 'Renato Olivares', '1991-04-26', 'M', '911111150', 'Santiago', 'Fonasa', 58),
('33333374-0', 'Julieta Farías', '1996-09-15', 'F', '911111151', 'Providencia', 'Isapre', 59);

-- 7. Citas Médicas (126 citas)
INSERT INTO cita_medica (id_cita, fecha, hora, rut_paciente, rut_medico, codigo_centro, nombre_especialidad, estado) VALUES
-- Agenda del Dr. Juan Pérez para 2026-10-15 (Consulta 4.3.a)
(1, '2026-10-15', '09:00:00', '33333333-3', '22222222-2', 101, 'Medicina General', 'Reservada'),
(2, '2026-10-15', '09:30:00', '33333334-1', '22222222-2', 101, 'Medicina General', 'Confirmada'),
(3, '2026-10-15', '10:00:00', '33333335-x', '22222222-2', 101, 'Cardiología', 'Confirmada'),
(4, '2026-10-15', '10:30:00', '33333336-8', '22222222-2', 101, 'Medicina General', 'Reservada'),
(5, '2026-10-15', '11:00:00', '33333337-6', '22222222-2', 101, 'Cardiología', 'Confirmada'),

-- Citas atendidas históricas (para atenciones, diagnósticos y recetas)
(6, '2026-09-01', '10:00:00', '33333333-3', '22222222-2', 101, 'Medicina General', 'Atendida'),
(7, '2026-09-02', '10:00:00', '33333333-3', '22222225-7', 101, 'Dermatología', 'Atendida'),
(8, '2026-09-03', '10:00:00', '33333333-3', '22222227-3', 101, 'Neurología', 'Atendida'),
(9, '2026-09-04', '11:00:00', '33333333-3', '22222229-k', 101, 'Oftalmología', 'Atendida'),

(10, '2026-09-05', '09:00:00', '33333334-1', '22222223-0', 101, 'Pediatría', 'Atendida'),
(11, '2026-09-06', '09:30:00', '33333334-1', '22222225-7', 101, 'Dermatología', 'Atendida'),
(12, '2026-09-07', '10:00:00', '33333334-1', '22222227-3', 101, 'Neurología', 'Atendida'),

(13, '2026-09-08', '11:00:00', '33333335-x', '22222222-2', 101, 'Cardiología', 'Atendida'),
(14, '2026-09-09', '11:30:00', '33333335-x', '22222226-5', 102, 'Traumatología', 'Atendida'),
(15, '2026-09-10', '12:00:00', '33333335-x', '22222228-1', 102, 'Ginecología', 'Atendida'),

(16, '2026-09-11', '09:00:00', '33333336-8', '22222224-9', 103, 'Pediatría', 'Atendida'),
(17, '2026-09-12', '10:00:00', '33333337-6', '22222224-9', 103, 'Pediatría', 'Atendida'),
(18, '2026-09-13', '11:00:00', '33333338-4', '22222224-9', 104, 'Pediatría', 'Atendida'),
(19, '2026-09-14', '12:00:00', '33333339-2', '22222223-0', 102, 'Pediatría', 'Atendida'),
(20, '2026-09-15', '09:30:00', '33333340-6', '22222223-0', 101, 'Pediatría', 'Atendida'),
(21, '2026-09-16', '10:30:00', '33333341-4', '22222231-1', 101, 'Pediatría', 'Atendida'),
(22, '2026-09-17', '11:30:00', '33333342-2', '22222231-1', 102, 'Pediatría', 'Atendida'),
(23, '2026-09-18', '09:00:00', '33333343-0', '22222231-1', 101, 'Pediatría', 'Atendida'),
(24, '2026-09-19', '10:00:00', '33333344-9', '22222223-0', 101, 'Pediatría', 'Atendida'),
(25, '2026-09-20', '11:00:00', '33333345-7', '22222224-9', 103, 'Pediatría', 'Atendida'),

(26, '2026-09-01', '12:00:00', '33333346-5', '22222222-2', 101, 'Medicina General', 'Atendida'),
(27, '2026-09-02', '12:30:00', '33333347-3', '22222230-3', 101, 'Medicina General', 'Atendida'),
(28, '2026-09-03', '14:00:00', '33333348-1', '22222230-3', 102, 'Medicina General', 'Atendida'),
(29, '2026-09-04', '14:30:00', '33333349-k', '22222230-3', 103, 'Medicina General', 'Atendida'),
(30, '2026-09-05', '15:00:00', '33333350-3', '22222230-3', 104, 'Medicina General', 'Atendida'),
(31, '2026-09-06', '15:30:00', '33333351-1', '22222224-9', 103, 'Medicina General', 'Atendida'),
(32, '2026-09-07', '16:00:00', '33333352-x', '22222224-9', 104, 'Medicina General', 'Atendida'),
(33, '2026-09-08', '16:30:00', '33333353-8', '22222222-2', 102, 'Cardiología', 'Atendida'),
(34, '2026-09-09', '17:00:00', '33333354-6', '22222232-x', 103, 'Cardiología', 'Atendida'),
(35, '2026-09-10', '17:30:00', '33333355-4', '22222232-x', 104, 'Cardiología', 'Atendida'),
(36, '2026-09-11', '10:00:00', '33333356-2', '22222225-7', 104, 'Dermatología', 'Atendida'),
(37, '2026-09-12', '10:30:00', '33333357-0', '22222233-8', 101, 'Dermatología', 'Atendida'),
(38, '2026-09-13', '11:00:00', '33333358-9', '22222233-8', 103, 'Dermatología', 'Atendida'),
(39, '2026-09-14', '11:30:00', '33333359-7', '22222226-5', 102, 'Traumatología', 'Atendida'),
(40, '2026-09-15', '12:00:00', '33333360-0', '22222234-6', 102, 'Traumatología', 'Atendida'),
(41, '2026-09-16', '12:30:00', '33333361-9', '22222234-6', 104, 'Traumatología', 'Atendida'),
(42, '2026-09-17', '14:00:00', '33333362-7', '22222227-3', 103, 'Neurología', 'Atendida'),
(43, '2026-09-18', '14:30:00', '33333363-5', '22222235-4', 101, 'Neurología', 'Atendida'),
(44, '2026-09-19', '15:00:00', '33333364-3', '22222235-4', 102, 'Neurología', 'Atendida'),
(45, '2026-09-20', '15:30:00', '33333365-1', '22222228-1', 104, 'Ginecología', 'Atendida'),
(46, '2026-09-21', '09:00:00', '33333366-x', '22222236-2', 103, 'Ginecología', 'Atendida'),
(47, '2026-09-22', '09:30:00', '33333367-8', '22222236-2', 104, 'Ginecología', 'Atendida'),
(48, '2026-09-23', '10:00:00', '33333368-6', '22222229-k', 104, 'Oftalmología', 'Atendida'),
(49, '2026-09-24', '10:30:00', '33333369-4', '22222237-0', 101, 'Oftalmología', 'Atendida'),
(50, '2026-09-25', '11:00:00', '33333370-8', '22222237-0', 102, 'Oftalmología', 'Atendida'),
(51, '2026-09-26', '11:30:00', '33333371-6', '22222237-0', 103, 'Oftalmología', 'Atendida'),
(52, '2026-09-27', '12:00:00', '33333372-4', '22222222-2', 101, 'Medicina General', 'Atendida'),
(53, '2026-09-28', '12:30:00', '33333373-2', '22222223-0', 101, 'Pediatría', 'Atendida'),
(54, '2026-09-29', '14:00:00', '33333374-0', '22222225-7', 101, 'Dermatología', 'Atendida'),
(55, '2026-09-30', '14:30:00', '33333333-3', '22222226-5', 102, 'Traumatología', 'Atendida'),
(56, '2026-10-01', '09:00:00', '33333334-1', '22222229-k', 101, 'Oftalmología', 'Atendida'),
(57, '2026-10-02', '09:30:00', '33333335-x', '22222230-3', 101, 'Medicina General', 'Atendida'),
(58, '2026-10-03', '10:00:00', '33333336-8', '22222233-8', 101, 'Dermatología', 'Atendida'),
(59, '2026-10-04', '10:30:00', '33333337-6', '22222235-4', 101, 'Neurología', 'Atendida'),
(60, '2026-10-05', '11:00:00', '33333338-4', '22222237-0', 101, 'Oftalmología', 'Atendida'),
(61, '2026-10-06', '11:30:00', '33333339-2', '22222224-9', 103, 'Medicina General', 'Atendida'),
(62, '2026-10-07', '12:00:00', '33333340-6', '22222226-5', 103, 'Traumatología', 'Atendida'),
(63, '2026-10-08', '12:30:00', '33333341-4', '22222232-x', 103, 'Cardiología', 'Atendida'),
(64, '2026-10-09', '14:00:00', '33333342-2', '22222236-2', 103, 'Ginecología', 'Atendida'),

-- Citas en estado "No Asistió" para superar el 15% en centros 101 y 103 (Consulta 4.3.c)
(65, '2026-08-01', '08:00:00', '33333343-0', '22222222-2', 101, 'Medicina General', 'No Asistió'),
(66, '2026-08-02', '08:00:00', '33333344-9', '22222222-2', 101, 'Medicina General', 'No Asistió'),
(67, '2026-08-03', '08:00:00', '33333345-7', '22222223-0', 101, 'Pediatría', 'No Asistió'),
(68, '2026-08-04', '08:00:00', '33333346-5', '22222225-7', 101, 'Dermatología', 'No Asistió'),
(69, '2026-08-05', '08:00:00', '33333347-3', '22222227-3', 101, 'Neurología', 'No Asistió'),
(70, '2026-08-06', '08:00:00', '33333348-1', '22222229-k', 101, 'Oftalmología', 'No Asistió'),
(71, '2026-08-07', '08:00:00', '33333349-k', '22222230-3', 101, 'Medicina General', 'No Asistió'),
(72, '2026-08-08', '08:00:00', '33333350-3', '22222231-1', 101, 'Pediatría', 'No Asistió'),
(73, '2026-08-09', '08:00:00', '33333351-1', '22222233-8', 101, 'Dermatología', 'No Asistió'),
(74, '2026-08-10', '08:00:00', '33333352-x', '22222235-4', 101, 'Neurología', 'No Asistió'),
(75, '2026-08-11', '08:00:00', '33333353-8', '22222237-0', 101, 'Oftalmología', 'No Asistió'),

(76, '2026-08-01', '08:30:00', '33333354-6', '22222224-9', 103, 'Pediatría', 'No Asistió'),
(77, '2026-08-02', '08:30:00', '33333355-4', '22222226-5', 103, 'Traumatología', 'No Asistió'),
(78, '2026-08-03', '08:30:00', '33333356-2', '22222227-3', 103, 'Neurología', 'No Asistió'),
(79, '2026-08-04', '08:30:00', '33333357-0', '22222230-3', 103, 'Medicina General', 'No Asistió'),
(80, '2026-08-05', '08:30:00', '33333358-9', '22222232-x', 103, 'Cardiología', 'No Asistió'),
(81, '2026-08-06', '08:30:00', '33333359-7', '22222233-8', 103, 'Dermatología', 'No Asistió'),
(82, '2026-08-07', '08:30:00', '33333360-0', '22222236-2', 103, 'Ginecología', 'No Asistió'),

(83, '2026-08-01', '08:30:00', '33333361-9', '22222223-0', 102, 'Pediatría', 'No Asistió'),
(84, '2026-08-02', '09:00:00', '33333362-7', '22222226-5', 102, 'Traumatología', 'No Asistió'),
(85, '2026-08-01', '09:00:00', '33333363-5', '22222224-9', 104, 'Pediatría', 'No Asistió'),

-- Citas Vencidas en estado Reservada o Confirmada (Sección 4.2.3 y prueba 4.4)
(86, '2026-01-10', '09:00:00', '33333364-3', '22222222-2', 101, 'Medicina General', 'Reservada'),
(87, '2026-01-11', '09:30:00', '33333365-1', '22222222-2', 101, 'Medicina General', 'Confirmada'),
(88, '2026-01-12', '10:00:00', '33333366-x', '22222223-0', 101, 'Pediatría', 'Reservada'),
(89, '2026-01-13', '10:30:00', '33333367-8', '22222224-9', 103, 'Pediatría', 'Confirmada'),
(90, '2026-01-14', '11:00:00', '33333368-6', '22222225-7', 104, 'Dermatología', 'Reservada'),
(91, '2026-01-15', '11:30:00', '33333369-4', '22222226-5', 102, 'Traumatología', 'Confirmada'),

-- Citas adicionales para completar el volumen total (>= 120 citas)
(92, '2026-11-01', '09:00:00', '33333370-8', '22222222-2', 101, 'Medicina General', 'Reservada'),
(93, '2026-11-01', '09:30:00', '33333371-6', '22222223-0', 101, 'Pediatría', 'Reservada'),
(94, '2026-11-01', '10:00:00', '33333372-4', '22222225-7', 101, 'Dermatología', 'Confirmada'),
(95, '2026-11-01', '10:30:00', '33333373-2', '22222227-3', 101, 'Neurología', 'Reservada'),
(96, '2026-11-01', '11:00:00', '33333374-0', '22222229-k', 101, 'Oftalmología', 'Confirmada'),
(97, '2026-11-02', '09:00:00', '33333333-3', '22222230-3', 101, 'Medicina General', 'Reservada'),
(98, '2026-11-02', '09:30:00', '33333334-1', '22222231-1', 101, 'Pediatría', 'Confirmada'),
(99, '2026-11-02', '10:00:00', '33333335-x', '22222233-8', 101, 'Dermatología', 'Reservada'),
(100, '2026-11-02', '10:30:00', '33333336-8', '22222235-4', 101, 'Neurología', 'Confirmada'),
(101, '2026-11-02', '11:00:00', '33333337-6', '22222237-0', 101, 'Oftalmología', 'Reservada'),
(102, '2026-11-03', '09:00:00', '33333338-4', '22222222-2', 102, 'Cardiología', 'Confirmada'),
(103, '2026-11-03', '09:30:00', '33333339-2', '22222223-0', 102, 'Pediatría', 'Reservada'),
(104, '2026-11-03', '10:00:00', '33333340-6', '22222226-5', 102, 'Traumatología', 'Confirmada'),
(105, '2026-11-03', '10:30:00', '33333341-4', '22222228-1', 102, 'Ginecología', 'Reservada'),
(106, '2026-11-03', '11:00:00', '33333342-2', '22222230-3', 102, 'Medicina General', 'Confirmada'),
(107, '2026-11-04', '09:00:00', '33333343-0', '22222231-1', 102, 'Pediatría', 'Reservada'),
(108, '2026-11-04', '09:30:00', '33333344-9', '22222234-6', 102, 'Traumatología', 'Confirmada'),
(109, '2026-11-04', '10:00:00', '33333345-7', '22222235-4', 102, 'Neurología', 'Reservada'),
(110, '2026-11-04', '10:30:00', '33333346-5', '22222237-0', 102, 'Oftalmología', 'Confirmada'),
(111, '2026-11-05', '09:00:00', '33333347-3', '22222222-2', 103, 'Medicina General', 'Reservada'),
(112, '2026-11-05', '09:30:00', '33333348-1', '22222224-9', 103, 'Pediatría', 'Confirmada'),
(113, '2026-11-05', '10:00:00', '33333349-k', '22222226-5', 103, 'Traumatología', 'Reservada'),
(114, '2026-11-05', '10:30:00', '33333350-3', '22222227-3', 103, 'Neurología', 'Confirmada'),
(115, '2026-11-05', '11:00:00', '33333351-1', '22222230-3', 103, 'Medicina General', 'Reservada'),
(116, '2026-11-06', '09:00:00', '33333352-x', '22222232-x', 103, 'Cardiología', 'Confirmada'),
(117, '2026-11-06', '09:30:00', '33333353-8', '22222233-8', 103, 'Dermatología', 'Reservada'),
(118, '2026-11-06', '10:00:00', '33333354-6', '22222236-2', 103, 'Ginecología', 'Confirmada'),
(119, '2026-11-06', '10:30:00', '33333355-4', '22222237-0', 103, 'Oftalmología', 'Reservada'),
(120, '2026-11-07', '09:00:00', '33333356-2', '22222224-9', 104, 'Pediatría', 'Confirmada'),
(121, '2026-11-07', '09:30:00', '33333357-0', '22222225-7', 104, 'Dermatología', 'Reservada'),
(122, '2026-11-07', '10:00:00', '33333358-9', '22222228-1', 104, 'Ginecología', 'Confirmada'),
(123, '2026-11-07', '10:30:00', '33333359-7', '22222229-k', 104, 'Oftalmología', 'Reservada'),
(124, '2026-11-07', '11:00:00', '33333360-0', '22222230-3', 104, 'Medicina General', 'Confirmada'),
(125, '2026-11-08', '09:00:00', '33333361-9', '22222232-x', 104, 'Cardiología', 'Reservada'),
(126, '2026-11-08', '09:30:00', '33333362-7', '22222234-6', 104, 'Traumatología', 'Confirmada'),
(127, '2026-09-21', '10:00:00', '33333340-6', '22222223-0', 101, 'Pediatría', 'Atendida'),
(128, '2026-09-22', '10:30:00', '33333341-4', '22222231-1', 101, 'Pediatría', 'Atendida'),
(129, '2026-09-23', '11:00:00', '33333342-2', '22222231-1', 102, 'Pediatría', 'Atendida'),
(130, '2026-09-24', '11:30:00', '33333343-0', '22222231-1', 101, 'Pediatría', 'Atendida'),
(131, '2026-09-25', '12:00:00', '33333344-9', '22222223-0', 101, 'Pediatría', 'Atendida');

-- 8. Atenciones Médicas (64 atenciones para citas 6 a 64 y cita 2)
INSERT INTO atencion (id_atencion, id_cita, fecha_atencion, motivo_consulta, observaciones) VALUES 
(1, 6, '2026-09-01 10:30:00', 'Control de rutina y tos persistente', 'Paciente evoluciona favorablemente'),
(2, 7, '2026-09-02 10:30:00', 'Manchas rojizas en brazos', 'Signos compatibles con dermatitis atópica'),
(3, 8, '2026-09-03 10:30:00', 'Cefaleas continuas', 'Cuadro de migraña aguda'),
(4, 9, '2026-09-04 11:30:00', 'Ardor ocular y enrojecimiento', 'Conjuntivitis bacteriana leve'),
(5, 10, '2026-09-05 09:30:00', 'Fiebre y congestión nasal infantil', 'Cuadro viral agudo en lactante'),
(6, 11, '2026-09-06 10:00:00', 'Picazón e irritación cutánea', 'Brote alérgico estacional'),
(7, 12, '2026-09-07 10:30:00', 'Mareos y fatiga frecuente', 'Exámenes generales solicitados'),
(8, 13, '2026-09-08 11:30:00', 'Palpitaciones al esfuerzo físico', 'Monitoreo de presión arterial'),
(9, 14, '2026-09-09 12:00:00', 'Dolor agudo en rodilla derecha tras correr', 'Sospecha de esguince de rodilla'),
(10, 15, '2026-09-10 12:30:00', 'Control ginecológico anual', 'Exámenes preventivos al día'),
(11, 16, '2026-09-11 09:30:00', 'Control pediátrico y dolor de garganta', 'Infección respiratoria alta'),
(12, 17, '2026-09-12 10:30:00', 'Fiebre y malestar general', 'Amigdalitis aguda'),
(13, 18, '2026-09-13 11:30:00', 'Tos nocturna y dificultad respiratoria', 'Cuadro bronquial obstructivo'),
(14, 19, '2026-09-14 12:30:00', 'Dolor abdominal cólico recurrente', 'Se indican antiespasmódicos'),
(15, 20, '2026-09-15 10:00:00', 'Control sano de niño de 5 años', 'Crecimiento y peso adecuados'),
(16, 21, '2026-09-16 11:00:00', 'Picaduras de insectos infectadas', 'Tratamiento antibiótico tópico'),
(17, 22, '2026-09-17 12:00:00', 'Congestión nasal y estornudos', 'Rinitis alérgica'),
(18, 23, '2026-09-18 09:30:00', 'Dolor de oídos y febrícula', 'Otitis media serosa'),
(19, 24, '2026-09-19 10:30:00', 'Fiebre alta sin foco evidente', 'Infección viral aguda'),
(20, 25, '2026-09-20 11:30:00', 'Diarrea aguda y vómitos', 'Gastroenteritis aguda infantil'),
(21, 26, '2026-09-01 12:30:00', 'Dolor lumbar tras esfuerzo', 'Lumbago mecánico'),
(22, 27, '2026-09-02 13:00:00', 'Control de diabetes mellitus', 'Glicemia descompensada leve'),
(23, 28, '2026-09-03 14:30:00', 'Acidez y regurgitación gástrica', 'Reflujo gastroesofágico crónico'),
(24, 29, '2026-09-04 15:00:00', 'Resfriado con secreción abundante', 'Rinofaringitis común'),
(25, 30, '2026-09-05 15:30:00', 'Dolor al orinar y polaquiuria', 'Infección del tracto urinario'),
(26, 31, '2026-09-06 16:00:00', 'Tos seca persistente', 'Control post viral'),
(27, 32, '2026-09-07 16:30:00', 'Dolor muscular generalizado', 'Mialgia difusa'),
(28, 33, '2026-09-08 17:00:00', 'Presión arterial elevada en control', 'Hipertensión etapa 1'),
(29, 34, '2026-09-09 17:30:00', 'Dolor torácico atípico', 'Electrocardiograma dentro de límites'),
(30, 35, '2026-09-10 18:00:00', 'Seguimiento de insuficiencia leve', 'Ajuste de terapia antihipertensiva'),
(31, 36, '2026-09-11 10:30:00', 'Lesiones descamativas en cuero cabelludo', 'Dermatitis seborreica'),
(32, 37, '2026-09-12 11:00:00', 'Alergia en manos por contacto', 'Dermatitis de contacto'),
(33, 38, '2026-09-13 11:30:00', 'Erupción cutánea pruriginosa', 'Urticaria alérgica'),
(34, 39, '2026-09-14 12:00:00', 'Dolor de tobillo por caída', 'Esguince grado 1'),
(35, 40, '2026-09-15 12:30:00', 'Dolor en hombro al levantar el brazo', 'Tendinitis manguito rotador'),
(36, 41, '2026-09-16 13:00:00', 'Molestias en columna dorsal', 'Dorsalgia mecánica'),
(37, 42, '2026-09-17 14:30:00', 'Cefaleas pulsátiles', 'Migraña común recurrente'),
(38, 43, '2026-09-18 15:00:00', 'Episodio de mareos y vértigo', 'Vértigo postural benigno'),
(39, 44, '2026-09-19 15:30:00', 'Insomnio y tensión cervical', 'Cefalea tensional'),
(40, 45, '2026-09-20 16:00:00', 'Control prenatal primer trimestre', 'Embarazo en óptima evolución'),
(41, 46, '2026-09-21 09:30:00', 'Dolor pélvico intermitente', 'Evaluación ecográfica solicitada'),
(42, 47, '2026-09-22 10:00:00', 'Control ginecológico y citología', 'Muestra tomada sin complicaciones'),
(43, 48, '2026-09-23 10:30:00', 'Disminución de agudeza visual de lejos', 'Vicio de refracción miopía'),
(44, 49, '2026-09-24 11:00:00', 'Ojo rojo y secreción matutina', 'Conjuntivitis bacteriana'),
(45, 50, '2026-09-25 11:30:00', 'Fatiga visual frente a pantallas', 'Astenopía acomodativa'),
(46, 51, '2026-09-26 12:00:00', 'Sequedad ocular y sensación de arena', 'Ojo seco evaporativo'),
(47, 52, '2026-09-27 12:30:00', 'Chequeo preventivo de salud', 'Parámetros vitales normales'),
(48, 53, '2026-09-28 13:00:00', 'Cuadro de vómitos infantiles', 'Gastroenteritis aguda viral'),
(49, 54, '2026-09-29 14:30:00', 'Eczema en pliegues de codos', 'Dermatitis atópica reactiva'),
(50, 55, '2026-09-30 15:00:00', 'Dolor cervical agudo', 'Contractura trapecio'),
(51, 56, '2026-10-01 09:30:00', 'Picazón en ojos e irritación', 'Conjuntivitis alérgica'),
(52, 57, '2026-10-02 10:00:00', 'Chequeo de presión y exámenes', 'Control de rutina'),
(53, 58, '2026-10-03 10:30:00', 'Erupción cutánea difusa', 'Dermatitis inespecífica'),
(54, 59, '2026-10-04 11:00:00', 'Cefalea recurrente post jornada laboral', 'Cefalea tensional crónica'),
(55, 60, '2026-10-05 11:30:00', 'Ardor ocular por sol', 'Fotofobia moderada'),
(56, 61, '2026-10-06 12:00:00', 'Fiebre persistente en adulto', 'Síndrome viral agudo'),
(57, 62, '2026-10-07 12:30:00', 'Contusión de rodilla tras golpe', 'Sin derrame articular significativo'),
(58, 63, '2026-10-08 13:00:00', 'Palpitaciones nocturnas', 'Holter de arritmia solicitado'),
(59, 64, '2026-10-09 14:30:00', 'Control ginecológico y de salud', 'Todo en rango normal'),
(60, 127, '2026-09-21 10:30:00', 'Revisión por control niño sano', 'Sin novedades patológicas'),
(61, 128, '2026-09-22 11:30:00', 'Curación por lesiones de rascado', 'Evolución favorable'),
(62, 129, '2026-09-23 12:30:00', 'Seguimiento de rinitis estacional', 'Buena respuesta a antihistamínicos'),
(63, 130, '2026-09-24 12:00:00', 'Otoscopía de control', 'Membrana timpánica íntegra'),
(64, 131, '2026-09-25 12:30:00', 'Fiebre remitida', 'Alta médica');

-- 9. Diagnósticos asignados a Atenciones (atencion_diagnostico)
INSERT INTO atencion_diagnostico (id_atencion, codigo_cie10) VALUES 
(1, 'J00'), (1, 'I10'),
(2, 'L20'),
(3, 'G43'),
(4, 'H10'),
(5, 'J06'), (5, 'B34'),
(6, 'L20'),
(7, 'B34'),
(8, 'I10'),
(9, 'S83'),
(10, 'N39'),
(11, 'J06'),
(12, 'J06'),
(13, 'J06'),
(14, 'K21'),
(15, 'B34'),
(16, 'L20'),
(17, 'J00'),
(18, 'J06'),
(19, 'B34'),
(20, 'K21'),
(21, 'M54'),
(22, 'E11'),
(23, 'K21'),
(24, 'J00'),
(25, 'N39'),
(26, 'J06'),
(27, 'M54'),
(28, 'I10'),
(29, 'I10'),
(30, 'I10'),
(31, 'L20'),
(32, 'L20'),
(33, 'L20'),
(34, 'S83'),
(35, 'M54'),
(36, 'M54'),
(37, 'G43'),
(38, 'G43'),
(39, 'G43'),
(40, 'N39'),
(41, 'N39'),
(42, 'N39'),
(43, 'H10'),
(44, 'H10'),
(45, 'H10'),
(46, 'H10'),
(47, 'B34'),
(48, 'B34'),
(49, 'L20'),
(50, 'M54'),
(51, 'H10'),
(52, 'I10'),
(53, 'L20'),
(54, 'G43'),
(55, 'H10'),
(56, 'B34'),
(57, 'S83'),
(58, 'I10'),
(59, 'N39'),
(60, 'B34'),
(61, 'L20'),
(62, 'J00'),
(63, 'J06'),
(64, 'B34');

-- 10. Recetas Médicas (86 recetas)
-- Incluye alta presencia de medicamentos pediátricos (atenciones 5, 11-20, 60-64) para la consulta 4.3.d
INSERT INTO receta (id_receta, id_atencion, medicamento, dosis, dias_tratamiento) VALUES 
-- Recetas de atención 1 (Paciente Juan Silva)
(1, 1, 'Paracetamol 500mg', '1 comprimido cada 8 horas', 5),
(2, 1, 'Loratadina 10mg', '1 comprimido por la noche', 7),

-- Recetas en Pediatría (atenciones 5, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20)
(3, 5, 'Paracetamol Gotas', '15 gotas cada 8 horas si hay fiebre', 3),
(4, 5, 'Ibuprofeno Suspensión', '5 ml cada 8 horas con dolor', 3),
(5, 11, 'Amoxicilina Suspensión', '5 ml cada 8 horas', 7),
(6, 11, 'Paracetamol Gotas', '12 gotas cada 8 horas', 3),
(7, 12, 'Amoxicilina Suspensión', '5 ml cada 8 horas', 7),
(8, 12, 'Ibuprofeno Suspensión', '5 ml cada 8 horas', 4),
(9, 13, 'Salbutamol Inhalador', '2 puff cada 6 horas con aerocámara', 5),
(10, 13, 'Prednisona Jarabe', '5 ml diarios por la mañana', 3),
(11, 14, 'Paracetamol Gotas', '10 gotas cada 8 horas', 2),
(12, 14, 'Viadil Gotas', '8 gotas cada 8 horas en caso de cólico', 3),
(13, 15, 'Multivitamínico Infantil', '1 cucharadita diaria', 30),
(14, 16, 'Clorfenamina Jarabe', '2.5 ml cada 12 horas', 5),
(15, 16, 'Mupirocina Crema', 'Aplicar fina capa cada 12 horas', 7),
(16, 17, 'Cetirizina Jarabe', '5 ml cada 24 horas', 10),
(17, 17, 'Paracetamol Gotas', '12 gotas cada 8 horas', 3),
(18, 18, 'Amoxicilina Suspensión', '7.5 ml cada 8 horas', 10),
(19, 18, 'Ibuprofeno Suspensión', '5 ml cada 8 horas', 5),
(20, 19, 'Paracetamol Gotas', '15 gotas cada 8 horas', 3),
(21, 20, 'Sales de Hidratación Oral', '1 sobre disuelto en 1 litro tras cada episodio', 3),
(22, 20, 'Perenteryl Sobres', '1 sobre cada 12 horas', 5),
(23, 60, 'Paracetamol Gotas', '10 gotas condicional a fiebre', 2),
(24, 61, 'Mupirocina Crema', 'Aplicar cada 12 horas', 5),
(25, 62, 'Cetirizina Jarabe', '5 ml diarios', 7),
(26, 63, 'Ibuprofeno Suspensión', '5 ml cada 8 horas', 3),
(27, 64, 'Paracetamol Gotas', '12 gotas cada 8 horas', 2),

-- Recetas para resto de atenciones (Medicina General, Dermatología, etc.)
(28, 2, 'Betametasona Crema', 'Aplicar dos veces al día', 7),
(29, 2, 'Cetirizina 10mg', '1 comprimido diario', 14),
(30, 3, 'Migranol', '1 comprimido al inicio del dolor', 3),
(31, 3, 'Naproxeno 550mg', '1 comprimido cada 12 horas', 4),
(32, 4, 'Ciprofloxacino Oftálmico', '1 gota cada 6 horas en ojo afectado', 7),
(33, 6, 'Loratadina 10mg', '1 comprimido cada 24 horas', 10),
(34, 7, 'Paracetamol 500mg', '1 comprimido cada 8 horas', 3),
(35, 8, 'Losartán 50mg', '1 comprimido cada mañana', 30),
(36, 8, 'Aspirina 100mg', '1 comprimido diario tras el almuerzo', 30),
(37, 9, 'Ketoprofeno 200mg', '1 comprimido cada 24 horas con comida', 5),
(38, 9, 'Paracetamol 500mg', '1 comprimido cada 8 horas', 5),
(39, 10, 'Ácido Fólico 5mg', '1 comprimido diario', 30),
(40, 21, 'Ciclobenzaprina 10mg', '1 comprimido por la noche', 5),
(41, 21, 'Ketoprofeno 200mg', '1 comprimido diario', 5),
(42, 22, 'Metformina 850mg', '1 comprimido con desayuno y cena', 30),
(43, 23, 'Omeprazol 20mg', '1 cápsula en ayunas cada mañana', 28),
(44, 24, 'Paracetamol 500mg', '1 comprimido cada 8 horas', 4),
(45, 24, 'Pseudoefedrina 60mg', '1 comprimido cada 12 horas', 3),
(46, 25, 'Nitrofurantoína 100mg', '1 cápsula cada 8 horas con comida', 7),
(47, 26, 'Ambroxol Jarabe', '10 ml cada 8 horas', 5),
(48, 27, 'Ibuprofeno 400mg', '1 comprimido cada 8 horas', 4),
(49, 28, 'Enalapril 10mg', '1 comprimido cada 12 horas', 30),
(50, 28, 'Hidroclorotiazida 25mg', 'Medio comprimido cada mañana', 30),
(51, 29, 'Aspirina 100mg', '1 comprimido diario', 30),
(52, 30, 'Losartán 50mg', '1 comprimido cada mañana', 30),
(53, 31, 'Ketoconazol Shampoo 2%', 'Lavar cuero cabelludo 3 veces por semana', 14),
(54, 32, 'Hidrocortisona Crema 1%', 'Aplicar capa fina cada 12 horas', 7),
(55, 33, 'Levocetirizina 5mg', '1 comprimido al día', 10),
(56, 34, 'Ibuprofeno 600mg', '1 comprimido cada 8 horas con comida', 5),
(57, 35, 'Meloxicam 15mg', '1 comprimido diario tras almuerzo', 7),
(58, 36, 'Ciclobenzaprina 10mg', '1 comprimido por la noche', 7),
(59, 37, 'Zolmitriptán 2.5mg', '1 comprimido al inicio de crisis de migraña', 2),
(60, 38, 'Difenidol 25mg', '1 comprimido cada 8 horas', 3),
(61, 39, 'Paracetamol 1g', '1 comprimido cada 8 horas', 3),
(62, 40, 'Hierro Quelado', '1 comprimido diario en ayunas', 30),
(63, 41, 'Propinoxato Compuesto', '1 comprimido ante dolor espasmódico', 3),
(64, 42, 'Metronidazol Óvulos', '1 óvulo vaginal por la noche', 10),
(65, 43, 'Lágrimas Artificiales Gotas', '1 gota en cada ojo cada 4 horas', 30),
(66, 44, 'Tobramicina Oftálmica', '1 gota cada 4 horas', 7),
(67, 45, 'Carboximetilcelulosa 0.5%', '1 gota en cada ojo cada 6 horas', 30),
(68, 46, 'Hialuronato de Sodio 0.15%', '1 gota en cada ojo según molestia', 30),
(69, 47, 'Vitamina C 1g', '1 comprimido efervescente al día', 15),
(70, 48, 'Domperidona 10mg', '1 comprimido 15 minutos antes de alimentos', 3),
(71, 49, 'Tacrolimus Ungüento 0.1%', 'Aplicar capa delgada en la noche', 14),
(72, 50, 'Ketoprofeno Gel 2.5%', 'Aplicar masaje suave cada 8 horas', 7),
(73, 51, 'Ketotifeno Colirio', '1 gota cada 12 horas en ambos ojos', 14),
(74, 52, 'Atorvastatina 20mg', '1 comprimido por la noche', 30),
(75, 53, 'Loratadina 10mg', '1 comprimido al día', 10),
(76, 54, 'Ergotamina Compuesta', '1 comprimido ante aviso de dolor', 2),
(77, 55, 'Lágrimas Artificiales Gotas', '1 gota cada 6 horas', 30),
(78, 56, 'Paracetamol 500mg', '1 comprimido cada 8 horas', 4),
(79, 57, 'Ibuprofeno 400mg', '1 comprimido cada 8 horas con comida', 5),
(80, 58, 'Atenolol 50mg', 'Medio comprimido cada mañana', 30),
(81, 59, 'Ácido Fólico 1mg', '1 comprimido diario', 30),
(82, 3, 'Ergotamina Compuesta', '1 comprimido con pródromos', 2),
(83, 8, 'Atorvastatina 20mg', '1 comprimido cada noche', 30),
(84, 11, 'Ibuprofeno Suspensión', '5 ml cada 8 horas', 3),
(85, 12, 'Paracetamol Gotas', '15 gotas cada 8 horas si hay fiebre', 3),
(86, 17, 'Amoxicilina Suspensión', '5 ml cada 8 horas', 7);