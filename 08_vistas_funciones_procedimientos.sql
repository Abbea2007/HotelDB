USE HotelDB;
GO

/* =============================================================
   SCRIPT: PROCEDIMIENTOS, VISTAS Y FUNCIONES
   BASE DE DATOS: HotelDB
   DESCRIPCIÓN: Objetos programables esenciales para la operación
                del sistema hotelero.
   ============================================================= */


/* =============================================================
   SECCIÓN 1 - FUNCIONES
   ============================================================= */

-- ── 1.1 Calcular total de una reserva (habitación + servicios) ──
-- Recibe el ID de reserva y devuelve el monto total a cobrar.
CREATE OR ALTER FUNCTION Hotel.fn_TotalReserva (@ReservaID INT)
RETURNS DECIMAL(10,2)
AS
BEGIN
    DECLARE @TotalHabitacion DECIMAL(10,2);
    DECLARE @TotalServicios  DECIMAL(10,2);

    -- Costo de la habitación según noches y precio base
    SELECT @TotalHabitacion =
        DATEDIFF(DAY, r.FechaEntrada, r.FechaSalida) * t.PrecioBase
    FROM Hotel.Reservas          r
    INNER JOIN Hotel.Habitaciones    h ON r.HabitacionID      = h.HabitacionID
    INNER JOIN Hotel.TiposHabitacion t ON h.TipoHabitacionID  = t.TipoHabitacionID
    WHERE r.ReservaID = @ReservaID;

    -- Costo de servicios adicionales consumidos
    SELECT @TotalServicios = ISNULL(SUM(s.Precio * cs.Cantidad), 0)
    FROM Hotel.ConsumoServicios cs
    INNER JOIN Hotel.Servicios  s ON cs.ServicioID = s.ServicioID
    WHERE cs.ReservaID = @ReservaID;

    RETURN ISNULL(@TotalHabitacion, 0) + @TotalServicios;
END;
GO


-- ── 1.2 Verificar si una habitación está disponible en un rango ──
-- Devuelve 1 = disponible, 0 = ocupada en esas fechas.
CREATE OR ALTER FUNCTION Hotel.fn_HabitacionDisponible (
    @HabitacionID   INT,
    @FechaEntrada   DATE,
    @FechaSalida    DATE
)
RETURNS BIT
AS
BEGIN
    DECLARE @Conflictos INT;

    SELECT @Conflictos = COUNT(*)
    FROM Hotel.Reservas
    WHERE HabitacionID  = @HabitacionID
      AND Estado        NOT IN ('Cancelada', 'Finalizada')
      AND FechaEntrada  < @FechaSalida
      AND FechaSalida   > @FechaEntrada;   -- solapamiento de fechas

    RETURN CASE WHEN @Conflictos = 0 THEN 1 ELSE 0 END;
END;
GO


-- ── 1.3 Calcular noches entre dos fechas ─────────────────────
CREATE OR ALTER FUNCTION Hotel.fn_CalcularNoches (
    @FechaEntrada DATE,
    @FechaSalida  DATE
)
RETURNS INT
AS
BEGIN
    RETURN DATEDIFF(DAY, @FechaEntrada, @FechaSalida);
END;
GO

PRINT '>> Sección 1 completada: Funciones creadas.';
GO


/* =============================================================
   SECCIÓN 2 - PROCEDIMIENTOS ALMACENADOS
   ============================================================= */

-- ── 2.1 Crear reserva validando disponibilidad ───────────────
CREATE OR ALTER PROCEDURE Hotel.usp_CrearReserva
    @ClienteID      INT,
    @HabitacionID   INT,
    @EmpleadoID     INT,
    @FechaEntrada   DATE,
    @FechaSalida    DATE
AS
BEGIN
    SET NOCOUNT ON;

    -- Validar disponibilidad usando la función
    IF Hotel.fn_HabitacionDisponible(@HabitacionID, @FechaEntrada, @FechaSalida) = 0
    BEGIN
        RAISERROR('La habitación no está disponible en las fechas indicadas.', 16, 1);
        RETURN;
    END;

    -- Validar que la fecha de salida sea mayor a la de entrada
    IF @FechaSalida <= @FechaEntrada
    BEGIN
        RAISERROR('La fecha de salida debe ser posterior a la fecha de entrada.', 16, 1);
        RETURN;
    END;

    INSERT INTO Hotel.Reservas
        (ClienteID, HabitacionID, EmpleadoID, FechaEntrada, FechaSalida, Estado)
    VALUES
        (@ClienteID, @HabitacionID, @EmpleadoID, @FechaEntrada, @FechaSalida, 'Confirmada');

    DECLARE @NuevaReservaID INT = SCOPE_IDENTITY();

    SELECT
        @NuevaReservaID                                     AS ReservaID,
        'Confirmada'                                        AS Estado,
        Hotel.fn_TotalReserva(@NuevaReservaID)              AS TotalEstimado,
        Hotel.fn_CalcularNoches(@FechaEntrada, @FechaSalida) AS Noches;
END;
GO


-- ── 2.2 Registrar Check-In ────────────────────────────────────
CREATE OR ALTER PROCEDURE Hotel.usp_CheckIn
    @ReservaID      INT,
    @Observaciones  VARCHAR(250) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    -- Validar que la reserva exista y esté confirmada
    IF NOT EXISTS (
        SELECT 1 FROM Hotel.Reservas
        WHERE ReservaID = @ReservaID AND Estado = 'Confirmada'
    )
    BEGIN
        RAISERROR('La reserva no existe o no está en estado Confirmada.', 16, 1);
        RETURN;
    END;

    -- Validar que no tenga check-in previo
    IF EXISTS (SELECT 1 FROM Hotel.CheckIn WHERE ReservaID = @ReservaID)
    BEGIN
        RAISERROR('Esta reserva ya tiene un Check-In registrado.', 16, 1);
        RETURN;
    END;

    BEGIN TRANSACTION;
    BEGIN TRY
        INSERT INTO Hotel.CheckIn (ReservaID, Observaciones)
        VALUES (@ReservaID, @Observaciones);

        -- Marcar habitación como ocupada
        UPDATE Hotel.Habitaciones
        SET Estado = 'Ocupada'
        WHERE HabitacionID = (
            SELECT HabitacionID FROM Hotel.Reservas WHERE ReservaID = @ReservaID
        );

        COMMIT TRANSACTION;
        PRINT '>> Check-In registrado correctamente para ReservaID: ' + CAST(@ReservaID AS VARCHAR);
    END TRY
    BEGIN CATCH
        ROLLBACK TRANSACTION;
        RAISERROR('Error durante el Check-In: %s', 16, 1, ERROR_MESSAGE());
    END CATCH;
END;
GO


-- ── 2.3 Registrar Check-Out y generar resumen de cobro ───────
CREATE OR ALTER PROCEDURE Hotel.usp_CheckOut
    @ReservaID      INT,
    @MetodoPago     VARCHAR(30),
    @Observaciones  VARCHAR(250) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    -- Validar que exista el check-in previo
    IF NOT EXISTS (SELECT 1 FROM Hotel.CheckIn WHERE ReservaID = @ReservaID)
    BEGIN
        RAISERROR('No existe Check-In para esta reserva.', 16, 1);
        RETURN;
    END;

    -- Validar que no tenga check-out previo
    IF EXISTS (SELECT 1 FROM Hotel.CheckOut WHERE ReservaID = @ReservaID)
    BEGIN
        RAISERROR('Esta reserva ya tiene un Check-Out registrado.', 16, 1);
        RETURN;
    END;

    DECLARE @Total DECIMAL(10,2) = Hotel.fn_TotalReserva(@ReservaID);

    BEGIN TRANSACTION;
    BEGIN TRY
        INSERT INTO Hotel.CheckOut (ReservaID, Observaciones)
        VALUES (@ReservaID, @Observaciones);

        -- Registrar el pago automáticamente
        INSERT INTO Finanzas.Pagos (ReservaID, Monto, MetodoPago, Estado)
        VALUES (@ReservaID, @Total, @MetodoPago, 'Pagado');

        -- Actualizar estados
        UPDATE Hotel.Reservas
        SET Estado = 'Finalizada'
        WHERE ReservaID = @ReservaID;

        UPDATE Hotel.Habitaciones
        SET Estado = 'Limpieza'
        WHERE HabitacionID = (
            SELECT HabitacionID FROM Hotel.Reservas WHERE ReservaID = @ReservaID
        );

        COMMIT TRANSACTION;

        -- Resumen final del cobro
        SELECT
            @ReservaID                          AS ReservaID,
            @Total                              AS TotalCobrado,
            @MetodoPago                         AS MetodoPago,
            'Finalizada'                        AS EstadoReserva,
            GETDATE()                           AS FechaCheckOut;
    END TRY
    BEGIN CATCH
        ROLLBACK TRANSACTION;
        RAISERROR('Error durante el Check-Out: %s', 16, 1, ERROR_MESSAGE());
    END CATCH;
END;
GO


-- ── 2.4 Buscar habitaciones disponibles por tipo y fechas ────
CREATE OR ALTER PROCEDURE Hotel.usp_BuscarHabitaciones
    @FechaEntrada       DATE,
    @FechaSalida        DATE,
    @TipoHabitacionID   INT = NULL      -- NULL = todos los tipos
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        h.HabitacionID,
        h.NumeroHabitacion,
        h.Piso,
        t.NombreTipo,
        t.Capacidad,
        t.PrecioBase                                            AS PrecioPorNoche,
        Hotel.fn_CalcularNoches(@FechaEntrada, @FechaSalida)    AS Noches,
        t.PrecioBase
            * Hotel.fn_CalcularNoches(@FechaEntrada, @FechaSalida) AS TotalEstimado
    FROM Hotel.Habitaciones      h
    INNER JOIN Hotel.TiposHabitacion t ON h.TipoHabitacionID = t.TipoHabitacionID
    WHERE h.Estado = 'Disponible'
      AND Hotel.fn_HabitacionDisponible(h.HabitacionID, @FechaEntrada, @FechaSalida) = 1
      AND (@TipoHabitacionID IS NULL OR h.TipoHabitacionID = @TipoHabitacionID)
    ORDER BY t.PrecioBase;
END;
GO

PRINT '>> Sección 2 completada: Procedimientos creados.';
GO


/* =============================================================
   SECCIÓN 3 - VISTAS
   ============================================================= */

-- ── 3.1 Ocupación actual del hotel ───────────────────────────
CREATE OR ALTER VIEW Hotel.vw_OcupacionActual
AS
SELECT
    h.NumeroHabitacion,
    h.Piso,
    h.Estado                                    AS EstadoHabitacion,
    t.NombreTipo,
    t.PrecioBase,
    c.Nombres + ' ' + c.Apellidos               AS Huesped,
    r.FechaEntrada,
    r.FechaSalida,
    DATEDIFF(DAY, r.FechaEntrada, r.FechaSalida) AS Noches,
    r.Estado                                    AS EstadoReserva
FROM Hotel.Habitaciones          h
INNER JOIN Hotel.TiposHabitacion t  ON h.TipoHabitacionID = t.TipoHabitacionID
LEFT  JOIN Hotel.Reservas        r  ON h.HabitacionID     = r.HabitacionID
                                   AND r.Estado IN ('Confirmada', 'Pendiente')
LEFT  JOIN Hotel.Clientes        c  ON r.ClienteID        = c.ClienteID;
GO


-- ── 3.2 Resumen financiero por reserva ───────────────────────
CREATE OR ALTER VIEW Finanzas.vw_ResumenFinanciero
AS
SELECT
    r.ReservaID,
    c.Nombres + ' ' + c.Apellidos               AS Cliente,
    h.NumeroHabitacion,
    t.NombreTipo,
    r.FechaEntrada,
    r.FechaSalida,
    DATEDIFF(DAY, r.FechaEntrada, r.FechaSalida) AS Noches,
    t.PrecioBase,
    DATEDIFF(DAY, r.FechaEntrada, r.FechaSalida)
        * t.PrecioBase                           AS TotalHabitacion,
    ISNULL(SUM(s.Precio * cs.Cantidad), 0)       AS TotalServicios,
    DATEDIFF(DAY, r.FechaEntrada, r.FechaSalida)
        * t.PrecioBase
        + ISNULL(SUM(s.Precio * cs.Cantidad), 0) AS TotalGeneral,
    ISNULL(SUM(p.Monto), 0)                      AS TotalPagado,
    r.Estado
FROM Hotel.Reservas              r
INNER JOIN Hotel.Clientes        c  ON r.ClienteID        = c.ClienteID
INNER JOIN Hotel.Habitaciones    h  ON r.HabitacionID     = h.HabitacionID
INNER JOIN Hotel.TiposHabitacion t  ON h.TipoHabitacionID = t.TipoHabitacionID
LEFT  JOIN Hotel.ConsumoServicios cs ON r.ReservaID       = cs.ReservaID
LEFT  JOIN Hotel.Servicios        s  ON cs.ServicioID     = s.ServicioID
LEFT  JOIN Finanzas.Pagos         p  ON r.ReservaID       = p.ReservaID
                                     AND p.Estado         = 'Pagado'
GROUP BY
    r.ReservaID, c.Nombres, c.Apellidos,
    h.NumeroHabitacion, t.NombreTipo,
    r.FechaEntrada, r.FechaSalida,
    t.PrecioBase, r.Estado;
GO

PRINT '>> Sección 3 completada: Vistas creadas.';
GO


/* =============================================================
   SECCIÓN 4 - DEMOSTRACIÓN
   Pruebas rápidas de todos los objetos creados.
   ============================================================= */

-- Buscar habitaciones disponibles
EXEC Hotel.usp_BuscarHabitaciones
    @FechaEntrada = '2026-08-01',
    @FechaSalida  = '2026-08-05';
GO

-- Crear una reserva nueva
EXEC Hotel.usp_CrearReserva 
    @ClienteID    = 4,
    @HabitacionID = 2,
    @EmpleadoID   = 2,
    @FechaEntrada = '2026-08-01',
    @FechaSalida  = '2026-08-05';
GO

-- Ver total de la reserva 1 usando la función
SELECT
    1                               AS ReservaID,
    Hotel.fn_TotalReserva(1)        AS TotalReserva,
    Hotel.fn_CalcularNoches('2026-07-01', '2026-07-03') AS Noches,
    Hotel.fn_HabitacionDisponible(1, '2026-09-01', '2026-09-05') AS HabitacionLibre;
GO

-- Ver ocupación actual
SELECT * FROM Hotel.vw_OcupacionActual;
GO

-- Ver resumen financiero
SELECT * FROM Finanzas.vw_ResumenFinanciero;
GO
