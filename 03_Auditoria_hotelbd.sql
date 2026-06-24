USE HotelDB;
GO

/* =========================================================
   SCRIPT: AUDITORÍA
   BASE DE DATOS: HotelDB
   ========================================================= */


/* =========================================================
   1. TABLA DE AUDITORÍA GENERAL
   ========================================================= */

IF OBJECT_ID('Auditoria.RegistroAuditoria', 'U') IS NULL
BEGIN
    CREATE TABLE Auditoria.RegistroAuditoria (
        AuditoriaID INT IDENTITY(1,1),
        TablaAfectada VARCHAR(100) NOT NULL,
        Accion VARCHAR(20) NOT NULL,
        UsuarioSistema VARCHAR(100) NOT NULL DEFAULT SYSTEM_USER,
        FechaAccion DATETIME NOT NULL DEFAULT GETDATE(),
        Descripcion VARCHAR(500),

        CONSTRAINT PK_RegistroAuditoria PRIMARY KEY (AuditoriaID),
        CONSTRAINT CK_RegistroAuditoria_Accion 
            CHECK (Accion IN ('INSERT', 'UPDATE', 'DELETE'))
    );
END;
GO


/* =========================================================
   2. TRIGGER AUDITORÍA CLIENTES
   ========================================================= */

CREATE OR ALTER TRIGGER Hotel.trg_Auditoria_Clientes
ON Hotel.Clientes
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;

    INSERT INTO Auditoria.RegistroAuditoria
    (TablaAfectada, Accion, Descripcion)
    SELECT 
        'Hotel.Clientes',
        CASE 
            WHEN EXISTS (SELECT 1 FROM inserted) 
             AND EXISTS (SELECT 1 FROM deleted) THEN 'UPDATE'
            WHEN EXISTS (SELECT 1 FROM inserted) THEN 'INSERT'
            ELSE 'DELETE'
        END,
        'Cambio realizado sobre la tabla Clientes por el usuario: ' + SYSTEM_USER;
END;
GO


/* =========================================================
   3. TRIGGER AUDITORÍA RESERVAS
   ========================================================= */

CREATE OR ALTER TRIGGER Hotel.trg_Auditoria_Reservas
ON Hotel.Reservas
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;

    INSERT INTO Auditoria.RegistroAuditoria
    (TablaAfectada, Accion, Descripcion)
    SELECT 
        'Hotel.Reservas',
        CASE 
            WHEN EXISTS (SELECT 1 FROM inserted) 
             AND EXISTS (SELECT 1 FROM deleted) THEN 'UPDATE'
            WHEN EXISTS (SELECT 1 FROM inserted) THEN 'INSERT'
            ELSE 'DELETE'
        END,
        'Cambio realizado sobre la tabla Reservas por el usuario: ' + SYSTEM_USER;
END;
GO


/* =========================================================
   4. TRIGGER AUDITORÍA PAGOS
   ========================================================= */

CREATE OR ALTER TRIGGER Finanzas.trg_Auditoria_Pagos
ON Finanzas.Pagos
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;

    INSERT INTO Auditoria.RegistroAuditoria
    (TablaAfectada, Accion, Descripcion)
    SELECT 
        'Finanzas.Pagos',
        CASE 
            WHEN EXISTS (SELECT 1 FROM inserted) 
             AND EXISTS (SELECT 1 FROM deleted) THEN 'UPDATE'
            WHEN EXISTS (SELECT 1 FROM inserted) THEN 'INSERT'
            ELSE 'DELETE'
        END,
        'Cambio realizado sobre la tabla Pagos por el usuario: ' + SYSTEM_USER;
END;
GO


/* =========================================================
   5. TRIGGER AUDITORÍA HABITACIONES
   ========================================================= */

CREATE OR ALTER TRIGGER Hotel.trg_Auditoria_Habitaciones
ON Hotel.Habitaciones
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;

    INSERT INTO Auditoria.RegistroAuditoria
    (TablaAfectada, Accion, Descripcion)
    SELECT 
        'Hotel.Habitaciones',
        CASE 
            WHEN EXISTS (SELECT 1 FROM inserted) 
             AND EXISTS (SELECT 1 FROM deleted) THEN 'UPDATE'
            WHEN EXISTS (SELECT 1 FROM inserted) THEN 'INSERT'
            ELSE 'DELETE'
        END,
        'Cambio realizado sobre la tabla Habitaciones por el usuario: ' + SYSTEM_USER;
END;
GO


/* =========================================================
   6. PRUEBAS DE AUDITORÍA
   ========================================================= */

INSERT INTO Hotel.Clientes
(Nombres, Apellidos, Documento, Telefono, Correo, Nacionalidad)
VALUES
('Pedro', 'Morales', 'PAS-2001', '7777-5555', 'pedro@email.com', 'Nicaragüense');
GO

UPDATE Hotel.Clientes
SET Telefono = '8888-9999'
WHERE Documento = 'PAS-2001';
GO

UPDATE Hotel.Habitaciones
SET Estado = 'Limpieza'
WHERE NumeroHabitacion = '101';
GO

INSERT INTO Finanzas.Pagos
(ReservaID, Monto, MetodoPago, Estado)
VALUES
(1, 35.00, 'Efectivo', 'Pagado');
GO


/* =========================================================
   7. CONSULTAR REGISTROS AUDITADOS
   ========================================================= */

SELECT 
    AuditoriaID,
    TablaAfectada,
    Accion,
    UsuarioSistema,
    FechaAccion,
    Descripcion
FROM Auditoria.RegistroAuditoria
ORDER BY FechaAccion DESC;
GO