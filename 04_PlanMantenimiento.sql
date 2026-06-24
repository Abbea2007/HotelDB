USE HotelDB;
GO

/* =============================================================
   SCRIPT: PLAN DE MANTENIMIENTO COMPLETO
   BASE DE DATOS: HotelDB
   DESCRIPCIÓN: Mantenimiento de índices, estadísticas, integridad,
                backups, limpieza de auditoría y monitoreo general.
   VERSIÓN: 1.0
   ============================================================= */


/* =============================================================
   SECCIÓN 1 - ÍNDICES ADICIONALES
   Optimizan las consultas más frecuentes en el sistema hotelero.
   ============================================================= */

-- Reservas: búsqueda por cliente y fechas
IF NOT EXISTS (SELECT 1 FROM sys.indexes 
               WHERE object_id = OBJECT_ID('Hotel.Reservas') 
               AND name = 'IX_Reservas_ClienteID')
BEGIN
    CREATE NONCLUSTERED INDEX IX_Reservas_ClienteID
    ON Hotel.Reservas (ClienteID)
    INCLUDE (HabitacionID, FechaEntrada, FechaSalida, Estado);
END;
GO

-- Reservas: búsqueda por fechas de entrada/salida
IF NOT EXISTS (SELECT 1 FROM sys.indexes 
               WHERE object_id = OBJECT_ID('Hotel.Reservas') 
               AND name = 'IX_Reservas_Fechas')
BEGIN
    CREATE NONCLUSTERED INDEX IX_Reservas_Fechas
    ON Hotel.Reservas (FechaEntrada, FechaSalida)
    INCLUDE (ClienteID, HabitacionID, Estado);
END;
GO

-- Reservas: búsqueda por estado
IF NOT EXISTS (SELECT 1 FROM sys.indexes 
               WHERE object_id = OBJECT_ID('Hotel.Reservas') 
               AND name = 'IX_Reservas_Estado')
BEGIN
    CREATE NONCLUSTERED INDEX IX_Reservas_Estado
    ON Hotel.Reservas (Estado)
    INCLUDE (ClienteID, HabitacionID, FechaEntrada, FechaSalida);
END;
GO

-- Habitaciones: búsqueda por estado y tipo
IF NOT EXISTS (SELECT 1 FROM sys.indexes 
               WHERE object_id = OBJECT_ID('Hotel.Habitaciones') 
               AND name = 'IX_Habitaciones_EstadoTipo')
BEGIN
    CREATE NONCLUSTERED INDEX IX_Habitaciones_EstadoTipo
    ON Hotel.Habitaciones (Estado, TipoHabitacionID)
    INCLUDE (NumeroHabitacion, Piso);
END;
GO

-- Clientes: búsqueda por documento, apellidos
IF NOT EXISTS (SELECT 1 FROM sys.indexes 
               WHERE object_id = OBJECT_ID('Hotel.Clientes') 
               AND name = 'IX_Clientes_Apellidos')
BEGIN
    CREATE NONCLUSTERED INDEX IX_Clientes_Apellidos
    ON Hotel.Clientes (Apellidos, Nombres)
    INCLUDE (Documento, Telefono, Correo);
END;
GO

-- Pagos: búsqueda por reserva y estado
IF NOT EXISTS (SELECT 1 FROM sys.indexes 
               WHERE object_id = OBJECT_ID('Finanzas.Pagos') 
               AND name = 'IX_Pagos_ReservaEstado')
BEGIN
    CREATE NONCLUSTERED INDEX IX_Pagos_ReservaEstado
    ON Finanzas.Pagos (ReservaID, Estado)
    INCLUDE (Monto, MetodoPago, FechaPago);
END;
GO

-- Auditoría: búsqueda por fecha y tabla
IF NOT EXISTS (SELECT 1 FROM sys.indexes 
               WHERE object_id = OBJECT_ID('Auditoria.RegistroAuditoria') 
               AND name = 'IX_Auditoria_FechaTabla')
BEGIN
    CREATE NONCLUSTERED INDEX IX_Auditoria_FechaTabla
    ON Auditoria.RegistroAuditoria (FechaAccion DESC, TablaAfectada)
    INCLUDE (Accion, UsuarioSistema, Descripcion);
END;
GO

-- Mantenimiento Habitaciones: búsqueda por estado
IF NOT EXISTS (SELECT 1 FROM sys.indexes 
               WHERE object_id = OBJECT_ID('Hotel.MantenimientoHabitaciones') 
               AND name = 'IX_Mantenimiento_Estado')
BEGIN
    CREATE NONCLUSTERED INDEX IX_Mantenimiento_Estado
    ON Hotel.MantenimientoHabitaciones (Estado)
    INCLUDE (HabitacionID, EmpleadoID, FechaInicio, FechaFin);
END;
GO

-- ConsumoServicios: búsqueda por reserva
IF NOT EXISTS (SELECT 1 FROM sys.indexes 
               WHERE object_id = OBJECT_ID('Hotel.ConsumoServicios') 
               AND name = 'IX_ConsumoServicios_ReservaID')
BEGIN
    CREATE NONCLUSTERED INDEX IX_ConsumoServicios_ReservaID
    ON Hotel.ConsumoServicios (ReservaID)
    INCLUDE (ServicioID, Cantidad, FechaConsumo);
END;
GO

PRINT '>> Sección 1 completada: Índices creados correctamente.';
GO


/* =============================================================
   SECCIÓN 2 - PROCEDIMIENTO DE MANTENIMIENTO DE ÍNDICES
   Reorganiza o reconstruye según el porcentaje de fragmentación.
   ============================================================= */

CREATE OR ALTER PROCEDURE Auditoria.usp_MantenimientoIndices
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @NombreObjeto    NVARCHAR(300);
    DECLARE @NombreIndice    NVARCHAR(300);
    DECLARE @Fragmentacion   FLOAT;
    DECLARE @SQL             NVARCHAR(MAX);
    DECLARE @Mensaje         NVARCHAR(500);

    -- Cursor sobre índices fragmentados (> 5%) en la base de datos actual
    DECLARE cur_Indices CURSOR FOR
        SELECT 
            QUOTENAME(s.name) + '.' + QUOTENAME(t.name) AS NombreObjeto,
            QUOTENAME(i.name)                            AS NombreIndice,
            ips.avg_fragmentation_in_percent             AS Fragmentacion
        FROM sys.dm_db_index_physical_stats(
                 DB_ID(), NULL, NULL, NULL, 'LIMITED') ips
        INNER JOIN sys.indexes      i ON ips.object_id = i.object_id
                                     AND ips.index_id  = i.index_id
        INNER JOIN sys.tables       t ON i.object_id   = t.object_id
        INNER JOIN sys.schemas      s ON t.schema_id   = s.schema_id
        WHERE ips.avg_fragmentation_in_percent > 5
          AND i.index_id > 0          -- excluye heaps
          AND i.name IS NOT NULL;

    OPEN cur_Indices;
    FETCH NEXT FROM cur_Indices INTO @NombreObjeto, @NombreIndice, @Fragmentacion;

    WHILE @@FETCH_STATUS = 0
    BEGIN
        IF @Fragmentacion >= 30
        BEGIN
            -- Fragmentación alta → REBUILD
            SET @SQL = 'ALTER INDEX ' + @NombreIndice 
                     + ' ON ' + @NombreObjeto + ' REBUILD WITH (ONLINE = OFF);';
            SET @Mensaje = 'REBUILD en ' + @NombreObjeto + '.' + @NombreIndice
                         + ' | Fragmentación: ' + CAST(ROUND(@Fragmentacion,2) AS VARCHAR) + '%';
        END
        ELSE
        BEGIN
            -- Fragmentación moderada (5-29%) → REORGANIZE
            SET @SQL = 'ALTER INDEX ' + @NombreIndice 
                     + ' ON ' + @NombreObjeto + ' REORGANIZE;';
            SET @Mensaje = 'REORGANIZE en ' + @NombreObjeto + '.' + @NombreIndice
                         + ' | Fragmentación: ' + CAST(ROUND(@Fragmentacion,2) AS VARCHAR) + '%';
        END;

        EXEC sp_executesql @SQL;

        -- Registrar en auditoría
        INSERT INTO Auditoria.RegistroAuditoria
            (TablaAfectada, Accion, Descripcion)
        VALUES
            ('sys.indexes', 'UPDATE', @Mensaje);

        PRINT @Mensaje;

        FETCH NEXT FROM cur_Indices INTO @NombreObjeto, @NombreIndice, @Fragmentacion;
    END;

    CLOSE cur_Indices;
    DEALLOCATE cur_Indices;

    PRINT '>> Mantenimiento de índices completado.';
END;
GO

PRINT '>> Sección 2 completada: Procedimiento de mantenimiento de índices creado.';
GO


/* =============================================================
   SECCIÓN 3 - ACTUALIZACIÓN DE ESTADÍSTICAS
   Garantiza que el optimizador de consultas trabaje con datos frescos.
   ============================================================= */

CREATE OR ALTER PROCEDURE Auditoria.usp_ActualizarEstadisticas
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @NombreTabla NVARCHAR(300);
    DECLARE @SQL         NVARCHAR(MAX);

    DECLARE cur_Tablas CURSOR FOR
        SELECT QUOTENAME(s.name) + '.' + QUOTENAME(t.name)
        FROM sys.tables  t
        INNER JOIN sys.schemas s ON t.schema_id = s.schema_id
        WHERE s.name IN ('Hotel', 'Finanzas', 'Auditoria', 'Seguridad');

    OPEN cur_Tablas;
    FETCH NEXT FROM cur_Tablas INTO @NombreTabla;

    WHILE @@FETCH_STATUS = 0
    BEGIN
        SET @SQL = 'UPDATE STATISTICS ' + @NombreTabla + ' WITH FULLSCAN;';
        EXEC sp_executesql @SQL;
        PRINT 'Estadísticas actualizadas: ' + @NombreTabla;
        FETCH NEXT FROM cur_Tablas INTO @NombreTabla;
    END;

    CLOSE cur_Tablas;
    DEALLOCATE cur_Tablas;

    INSERT INTO Auditoria.RegistroAuditoria
        (TablaAfectada, Accion, Descripcion)
    VALUES
        ('TODAS LAS TABLAS', 'UPDATE',
         'Actualización completa de estadísticas ejecutada por: ' + SYSTEM_USER);

    PRINT '>> Actualización de estadísticas completada.';
END;
GO

PRINT '>> Sección 3 completada: Procedimiento de actualización de estadísticas creado.';
GO


/* =============================================================
   SECCIÓN 4 - VERIFICACIÓN DE INTEGRIDAD (DBCC CHECKDB)
   Detecta corrupción en páginas, tablas e índices.
   ============================================================= */

CREATE OR ALTER PROCEDURE Auditoria.usp_VerificarIntegridad
AS
BEGIN
    SET NOCOUNT ON;

    PRINT '>> Iniciando verificación de integridad de HotelDB...';

    BEGIN TRY
        DBCC CHECKDB ('HotelDB') WITH NO_INFOMSGS, ALL_ERRORMSGS;

        INSERT INTO Auditoria.RegistroAuditoria
            (TablaAfectada, Accion, Descripcion)
        VALUES
            ('HotelDB', 'UPDATE',
             'DBCC CHECKDB ejecutado sin errores por: ' + SYSTEM_USER);

        PRINT '>> Verificación completada sin errores.';
    END TRY
    BEGIN CATCH
        INSERT INTO Auditoria.RegistroAuditoria
            (TablaAfectada, Accion, Descripcion)
        VALUES
            ('HotelDB', 'UPDATE',
             'ERROR en DBCC CHECKDB: ' + ERROR_MESSAGE() + ' | Usuario: ' + SYSTEM_USER);

        PRINT '>> ERROR durante la verificación: ' + ERROR_MESSAGE();
    END CATCH;
END;
GO

PRINT '>> Sección 4 completada: Procedimiento de verificación de integridad creado.';
GO


/* =============================================================
   SECCIÓN 5 - BACKUP COMPLETO Y DIFERENCIAL
   Scripts listos para ejecutarse manualmente o desde el Agente SQL.
   NOTA: Ajusta la ruta @RutaBackup según tu servidor.
   ============================================================= */

CREATE OR ALTER PROCEDURE Auditoria.usp_BackupCompleto
    @RutaBackup NVARCHAR(500) = 'C:\Backups\HotelDB\'
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @NombreArchivo NVARCHAR(600);
    DECLARE @SQL           NVARCHAR(MAX);
    DECLARE @FechaHora     VARCHAR(20);

    SET @FechaHora = FORMAT(GETDATE(), 'yyyyMMdd_HHmmss');
    SET @NombreArchivo = @RutaBackup + 'HotelDB_FULL_' + @FechaHora + '.bak';

    SET @SQL = 'BACKUP DATABASE HotelDB 
                TO DISK = N''' + @NombreArchivo + '''
                WITH FORMAT,
                     COMPRESSION,
                     STATS = 10,
                     NAME = N''HotelDB - Backup Completo ' + @FechaHora + ''';';

    BEGIN TRY
        EXEC sp_executesql @SQL;

        INSERT INTO Auditoria.RegistroAuditoria
            (TablaAfectada, Accion, Descripcion)
        VALUES
            ('HotelDB', 'INSERT',
             'Backup completo generado: ' + @NombreArchivo + ' | Usuario: ' + SYSTEM_USER);

        PRINT '>> Backup completo generado: ' + @NombreArchivo;
    END TRY
    BEGIN CATCH
        INSERT INTO Auditoria.RegistroAuditoria
            (TablaAfectada, Accion, Descripcion)
        VALUES
            ('HotelDB', 'INSERT',
             'ERROR en backup completo: ' + ERROR_MESSAGE() + ' | Usuario: ' + SYSTEM_USER);

        PRINT '>> ERROR en backup: ' + ERROR_MESSAGE();
    END CATCH;
END;
GO

-- -------------------------------------------------------
CREATE OR ALTER PROCEDURE Auditoria.usp_BackupDiferencial
    @RutaBackup NVARCHAR(500) = 'C:\Backups\HotelDB\'
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @NombreArchivo NVARCHAR(600);
    DECLARE @SQL           NVARCHAR(MAX);
    DECLARE @FechaHora     VARCHAR(20);

    SET @FechaHora = FORMAT(GETDATE(), 'yyyyMMdd_HHmmss');
    SET @NombreArchivo = @RutaBackup + 'HotelDB_DIFF_' + @FechaHora + '.bak';

    SET @SQL = 'BACKUP DATABASE HotelDB 
                TO DISK = N''' + @NombreArchivo + '''
                WITH DIFFERENTIAL,
                     COMPRESSION,
                     STATS = 10,
                     NAME = N''HotelDB - Backup Diferencial ' + @FechaHora + ''';';

    BEGIN TRY
        EXEC sp_executesql @SQL;

        INSERT INTO Auditoria.RegistroAuditoria
            (TablaAfectada, Accion, Descripcion)
        VALUES
            ('HotelDB', 'INSERT',
             'Backup diferencial generado: ' + @NombreArchivo + ' | Usuario: ' + SYSTEM_USER);

        PRINT '>> Backup diferencial generado: ' + @NombreArchivo;
    END TRY
    BEGIN CATCH
        INSERT INTO Auditoria.RegistroAuditoria
            (TablaAfectada, Accion, Descripcion)
        VALUES
            ('HotelDB', 'INSERT',
             'ERROR en backup diferencial: ' + ERROR_MESSAGE() + ' | Usuario: ' + SYSTEM_USER);

        PRINT '>> ERROR en backup diferencial: ' + ERROR_MESSAGE();
    END CATCH;
END;
GO

PRINT '>> Sección 5 completada: Procedimientos de backup creados.';
GO


/* =============================================================
   SECCIÓN 6 - LIMPIEZA DE REGISTROS DE AUDITORÍA
   Archiva y elimina registros antiguos para controlar el tamaño.
   ============================================================= */

-- Tabla de historial donde se archivan registros antes de eliminarlos
IF OBJECT_ID('Auditoria.HistorialAuditoria', 'U') IS NULL
BEGIN
    CREATE TABLE Auditoria.HistorialAuditoria (
        HistorialID     INT IDENTITY(1,1),
        AuditoriaID     INT NOT NULL,
        TablaAfectada   VARCHAR(100) NOT NULL,
        Accion          VARCHAR(20)  NOT NULL,
        UsuarioSistema  VARCHAR(100) NOT NULL,
        FechaAccion     DATETIME     NOT NULL,
        Descripcion     VARCHAR(500),
        FechaArchivado  DATETIME     NOT NULL DEFAULT GETDATE(),

        CONSTRAINT PK_HistorialAuditoria PRIMARY KEY (HistorialID)
    );
END;
GO

CREATE OR ALTER PROCEDURE Auditoria.usp_LimpiarAuditoria
    @DiasRetener INT = 90   -- conserva los últimos N días (default: 90)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @FechaCorte DATETIME = DATEADD(DAY, -@DiasRetener, GETDATE());
    DECLARE @Registros  INT;

    -- Archivar antes de eliminar
    INSERT INTO Auditoria.HistorialAuditoria
        (AuditoriaID, TablaAfectada, Accion, UsuarioSistema, FechaAccion, Descripcion)
    SELECT 
        AuditoriaID, TablaAfectada, Accion, UsuarioSistema, FechaAccion, Descripcion
    FROM Auditoria.RegistroAuditoria
    WHERE FechaAccion < @FechaCorte;

    SET @Registros = @@ROWCOUNT;

    -- Eliminar los registros archivados
    DELETE FROM Auditoria.RegistroAuditoria
    WHERE FechaAccion < @FechaCorte;

    PRINT '>> Registros archivados y eliminados: ' + CAST(@Registros AS VARCHAR) 
        + ' (anteriores a ' + CONVERT(VARCHAR, @FechaCorte, 103) + ')';

    INSERT INTO Auditoria.RegistroAuditoria
        (TablaAfectada, Accion, Descripcion)
    VALUES
        ('Auditoria.RegistroAuditoria', 'DELETE',
         'Limpieza de auditoría: ' + CAST(@Registros AS VARCHAR) 
         + ' registros archivados. Usuario: ' + SYSTEM_USER);
END;
GO

PRINT '>> Sección 6 completada: Procedimiento de limpieza de auditoría creado.';
GO


/* =============================================================
   SECCIÓN 7 - MONITOREO DEL ESTADO DE LA BASE DE DATOS
   Vistas y procedimientos de diagnóstico operativo.
   ============================================================= */

-- Vista: Habitaciones disponibles con tipo y precio
CREATE OR ALTER VIEW Hotel.vw_HabitacionesDisponibles
AS
SELECT
    h.HabitacionID,
    h.NumeroHabitacion,
    h.Piso,
    h.Estado,
    t.NombreTipo,
    t.PrecioBase,
    t.Capacidad
FROM Hotel.Habitaciones  h
INNER JOIN Hotel.TiposHabitacion t ON h.TipoHabitacionID = t.TipoHabitacionID
WHERE h.Estado = 'Disponible';
GO

-- Vista: Reservas activas con detalle de cliente y habitación
CREATE OR ALTER VIEW Hotel.vw_ReservasActivas
AS
SELECT
    r.ReservaID,
    r.FechaEntrada,
    r.FechaSalida,
    r.Estado                                         AS EstadoReserva,
    c.Nombres + ' ' + c.Apellidos                   AS NombreCliente,
    c.Documento,
    h.NumeroHabitacion,
    t.NombreTipo,
    t.PrecioBase,
    DATEDIFF(DAY, r.FechaEntrada, r.FechaSalida)    AS Noches,
    DATEDIFF(DAY, r.FechaEntrada, r.FechaSalida)
        * t.PrecioBase                               AS TotalHabitacion
FROM Hotel.Reservas         r
INNER JOIN Hotel.Clientes       c ON r.ClienteID     = c.ClienteID
INNER JOIN Hotel.Habitaciones   h ON r.HabitacionID  = h.HabitacionID
INNER JOIN Hotel.TiposHabitacion t ON h.TipoHabitacionID = t.TipoHabitacionID
WHERE r.Estado IN ('Pendiente', 'Confirmada');
GO

-- Vista: Resumen de pagos por reserva
CREATE OR ALTER VIEW Finanzas.vw_ResumenPagos
AS
SELECT
    r.ReservaID,
    c.Nombres + ' ' + c.Apellidos  AS NombreCliente,
    SUM(p.Monto)                    AS TotalPagado,
    COUNT(p.PagoID)                 AS NumPagos,
    MAX(p.FechaPago)                AS UltimoPago,
    r.Estado                        AS EstadoReserva
FROM Hotel.Reservas   r
INNER JOIN Hotel.Clientes c  ON r.ClienteID = c.ClienteID
LEFT  JOIN Finanzas.Pagos p  ON r.ReservaID = p.ReservaID
                             AND p.Estado   = 'Pagado'
GROUP BY r.ReservaID, c.Nombres, c.Apellidos, r.Estado;
GO

-- Procedimiento: diagnóstico general del sistema
CREATE OR ALTER PROCEDURE Auditoria.usp_DiagnosticoSistema
AS
BEGIN
    SET NOCOUNT ON;

    -- 1. Tamaño de la base de datos
    PRINT '--- 1. TAMAÑO DE LA BASE DE DATOS ---';
    EXEC sp_spaceused;

    -- 2. Conteo de filas por tabla
    PRINT '';
    PRINT '--- 2. CONTEO DE FILAS POR TABLA ---';
    SELECT
        s.name                              AS Esquema,
        t.name                              AS Tabla,
        p.rows                              AS TotalFilas
    FROM sys.tables       t
    INNER JOIN sys.schemas     s ON t.schema_id  = s.schema_id
    INNER JOIN sys.partitions  p ON t.object_id  = p.object_id
                                 AND p.index_id  IN (0, 1)
    ORDER BY s.name, t.name;

    -- 3. Índices con alta fragmentación
    PRINT '';
    PRINT '--- 3. ÍNDICES FRAGMENTADOS (> 10%) ---';
    SELECT
        QUOTENAME(s.name) + '.' + QUOTENAME(t.name)     AS Tabla,
        i.name                                           AS Indice,
        ROUND(ips.avg_fragmentation_in_percent, 2)       AS Fragmentacion_Pct,
        CASE
            WHEN ips.avg_fragmentation_in_percent >= 30 THEN 'REBUILD recomendado'
            ELSE 'REORGANIZE recomendado'
        END                                              AS Accion
    FROM sys.dm_db_index_physical_stats(
             DB_ID(), NULL, NULL, NULL, 'LIMITED') ips
    INNER JOIN sys.indexes  i ON ips.object_id = i.object_id
                              AND ips.index_id  = i.index_id
    INNER JOIN sys.tables   t ON i.object_id   = t.object_id
    INNER JOIN sys.schemas  s ON t.schema_id   = s.schema_id
    WHERE ips.avg_fragmentation_in_percent > 10
      AND i.index_id > 0
      AND i.name IS NOT NULL
    ORDER BY ips.avg_fragmentation_in_percent DESC;

    -- 4. Últimos 20 registros de auditoría
    PRINT '';
    PRINT '--- 4. ÚLTIMOS 20 REGISTROS DE AUDITORÍA ---';
    SELECT TOP 20
        AuditoriaID,
        TablaAfectada,
        Accion,
        UsuarioSistema,
        FechaAccion,
        Descripcion
    FROM Auditoria.RegistroAuditoria
    ORDER BY FechaAccion DESC;

    -- 5. Reservas activas
    PRINT '';
    PRINT '--- 5. RESERVAS ACTIVAS ---';
    SELECT * FROM Hotel.vw_ReservasActivas
    ORDER BY FechaEntrada;

    -- 6. Habitaciones fuera de servicio
    PRINT '';
    PRINT '--- 6. HABITACIONES FUERA DE SERVICIO ---';
    SELECT
        NumeroHabitacion,
        Piso,
        Estado
    FROM Hotel.Habitaciones
    WHERE Estado IN ('Mantenimiento', 'Limpieza')
    ORDER BY Estado, Piso;

    -- 7. Pagos pendientes
    PRINT '';
    PRINT '--- 7. PAGOS PENDIENTES ---';
    SELECT
        p.PagoID,
        p.ReservaID,
        c.Nombres + ' ' + c.Apellidos AS NombreCliente,
        p.Monto,
        p.MetodoPago,
        p.FechaPago
    FROM Finanzas.Pagos    p
    INNER JOIN Hotel.Reservas  r ON p.ReservaID = r.ReservaID
    INNER JOIN Hotel.Clientes  c ON r.ClienteID = c.ClienteID
    WHERE p.Estado = 'Pendiente'
    ORDER BY p.FechaPago;

    -- 8. Mantenimientos en curso
    PRINT '';
    PRINT '--- 8. MANTENIMIENTOS EN CURSO ---';
    SELECT
        mh.MantenimientoID,
        h.NumeroHabitacion,
        e.Nombres + ' ' + e.Apellidos AS Responsable,
        mh.FechaInicio,
        mh.Descripcion,
        mh.Estado
    FROM Hotel.MantenimientoHabitaciones mh
    INNER JOIN Hotel.Habitaciones h ON mh.HabitacionID = h.HabitacionID
    INNER JOIN Hotel.Empleados    e ON mh.EmpleadoID   = e.EmpleadoID
    WHERE mh.Estado = 'En proceso'
    ORDER BY mh.FechaInicio;
END;
GO

PRINT '>> Sección 7 completada: Vistas y diagnóstico creados.';
GO


/* =============================================================
   SECCIÓN 8 - PROCEDIMIENTO MAESTRO DE MANTENIMIENTO
   Ejecuta todo el plan en el orden correcto con un solo llamado.
   ============================================================= */

CREATE OR ALTER PROCEDURE Auditoria.usp_EjecutarMantenimientoCompleto
    @RutaBackup     NVARCHAR(500)   = 'C:\Backups\HotelDB\',
    @DiasRetener    INT             = 90,
    @EjecutarBackup BIT             = 1
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Inicio DATETIME = GETDATE();
    DECLARE @Paso   VARCHAR(100);

    PRINT '============================================================';
    PRINT ' INICIO DEL MANTENIMIENTO COMPLETO - HotelDB';
    PRINT ' Fecha/Hora: ' + CONVERT(VARCHAR, @Inicio, 120);
    PRINT '============================================================';

    -- Paso 1: Backup completo (opcional)
    IF @EjecutarBackup = 1
    BEGIN
        SET @Paso = 'Backup completo';
        PRINT '';
        PRINT '>> Paso 1: ' + @Paso;
        EXEC Auditoria.usp_BackupCompleto @RutaBackup = @RutaBackup;
    END;

    -- Paso 2: Verificación de integridad
    SET @Paso = 'Verificación de integridad';
    PRINT '';
    PRINT '>> Paso 2: ' + @Paso;
    EXEC Auditoria.usp_VerificarIntegridad;

    -- Paso 3: Mantenimiento de índices
    SET @Paso = 'Mantenimiento de índices';
    PRINT '';
    PRINT '>> Paso 3: ' + @Paso;
    EXEC Auditoria.usp_MantenimientoIndices;

    -- Paso 4: Actualización de estadísticas
    SET @Paso = 'Actualización de estadísticas';
    PRINT '';
    PRINT '>> Paso 4: ' + @Paso;
    EXEC Auditoria.usp_ActualizarEstadisticas;

    -- Paso 5: Limpieza de auditoría
    SET @Paso = 'Limpieza de auditoría';
    PRINT '';
    PRINT '>> Paso 5: ' + @Paso;
    EXEC Auditoria.usp_LimpiarAuditoria @DiasRetener = @DiasRetener;

    -- Paso 6: Diagnóstico final
    SET @Paso = 'Diagnóstico del sistema';
    PRINT '';
    PRINT '>> Paso 6: ' + @Paso;
    EXEC Auditoria.usp_DiagnosticoSistema;

    -- Registro final
    INSERT INTO Auditoria.RegistroAuditoria
        (TablaAfectada, Accion, Descripcion)
    VALUES
        ('HotelDB - Mantenimiento Completo', 'UPDATE',
         'Mantenimiento completo ejecutado. Duración: '
         + CAST(DATEDIFF(SECOND, @Inicio, GETDATE()) AS VARCHAR) + ' segundos. Usuario: '
         + SYSTEM_USER);

    PRINT '';
    PRINT '============================================================';
    PRINT ' MANTENIMIENTO COMPLETADO';
    PRINT ' Duración total: ' 
        + CAST(DATEDIFF(SECOND, @Inicio, GETDATE()) AS VARCHAR) + ' segundos';
    PRINT '============================================================';
END;
GO

PRINT '>> Sección 8 completada: Procedimiento maestro creado.';
GO


/* =============================================================
   SECCIÓN 9 - JOBS DEL AGENTE SQL (GUÍA DE PROGRAMACIÓN)
   Estos comandos ilustran cómo llamar a cada procedimiento
   desde un trabajo programado del Agente SQL Server.
   ============================================================= */

/*
   ── JOB DIARIO (cada noche a las 02:00) ──
   Paso 1 (T-SQL):
       EXEC HotelDB.Auditoria.usp_MantenimientoIndices;
   Paso 2 (T-SQL):
       EXEC HotelDB.Auditoria.usp_ActualizarEstadisticas;

   ── JOB SEMANAL (domingos a las 01:00) ──
   Paso 1 (T-SQL):
       EXEC HotelDB.Auditoria.usp_EjecutarMantenimientoCompleto
           @RutaBackup  = 'C:\Backups\HotelDB\',
           @DiasRetener = 90,
           @EjecutarBackup = 1;

   ── JOB MENSUAL (primer día del mes a las 00:30) ──
   Paso 1 (T-SQL):
       EXEC HotelDB.Auditoria.usp_VerificarIntegridad;
   Paso 2 (T-SQL):
       EXEC HotelDB.Auditoria.usp_LimpiarAuditoria @DiasRetener = 90;
*/

PRINT '>> Sección 9: Guía de programación de jobs incluida como comentario.';
GO


/* =============================================================
   SECCIÓN 10 - VERIFICACIÓN FINAL
   Confirma que todos los objetos del plan existen en la BD.
   ============================================================= */

SELECT
    'PROCEDIMIENTO'     AS TipoObjeto,
    s.name + '.' + o.name AS NombreCompleto,
    o.create_date,
    o.modify_date
FROM sys.objects  o
INNER JOIN sys.schemas s ON o.schema_id = s.schema_id
WHERE o.type = 'P'
  AND s.name IN ('Auditoria', 'Hotel', 'Finanzas')
  AND o.name LIKE 'usp_%'

UNION ALL

SELECT
    'VISTA',
    s.name + '.' + o.name,
    o.create_date,
    o.modify_date
FROM sys.objects  o
INNER JOIN sys.schemas s ON o.schema_id = s.schema_id
WHERE o.type = 'V'
  AND s.name IN ('Hotel', 'Finanzas')

UNION ALL

SELECT
    'ÍNDICE',
    s.name + '.' + t.name + '.' + i.name,
    NULL,
    NULL
FROM sys.indexes  i
INNER JOIN sys.tables  t ON i.object_id = t.object_id
INNER JOIN sys.schemas s ON t.schema_id = s.schema_id
WHERE i.name LIKE 'IX_%'
  AND s.name IN ('Hotel', 'Finanzas', 'Auditoria')

ORDER BY TipoObjeto, NombreCompleto;
GO

PRINT '>> Plan de mantenimiento completo instalado correctamente en HotelDB.';
GO