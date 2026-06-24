USE msdb;
GO

/* =============================================================
   SCRIPT: SQL SERVER AGENT JOBS
   BASE DE DATOS: HotelDB
   DESCRIPCIÓN: Automatización completa de tareas de mantenimiento,
                backups, Extended Events, auditoría y monitoreo.
                Incluye historial de ejecución y evidencia.
   VERSIÓN: 1.0
   ============================================================= */


/* =============================================================
   SECCIÓN 1 - OPERADOR DE NOTIFICACIONES
   Recibe alertas cuando un job falla o completa tareas críticas.
   NOTA: Ajusta el correo al del administrador real del servidor.
   ============================================================= */

IF NOT EXISTS (
    SELECT 1 FROM msdb.dbo.sysoperators WHERE name = N'OperadorHotelDB'
)
BEGIN
    EXEC msdb.dbo.sp_add_operator
        @name                   = N'OperadorHotelDB',
        @enabled                = 1,
        @email_address          = N'dba@hoteldb.com',
        @pager_days             = 0;
END;
GO

PRINT '>> Operador OperadorHotelDB configurado.';
GO


/* =============================================================
   SECCIÓN 2 - CATEGORÍA DE JOBS
   Agrupa todos los jobs del hotel para identificarlos fácilmente
   en el Agente SQL.
   ============================================================= */

IF NOT EXISTS (
    SELECT 1 FROM msdb.dbo.syscategories 
    WHERE name = N'HotelDB - Mantenimiento'
    AND category_class = 1
)
BEGIN
    EXEC msdb.dbo.sp_add_category
        @class  = N'JOB',
        @type   = N'LOCAL',
        @name   = N'HotelDB - Mantenimiento';
END;
GO

IF NOT EXISTS (
    SELECT 1 FROM msdb.dbo.syscategories 
    WHERE name = N'HotelDB - Backups'
    AND category_class = 1
)
BEGIN
    EXEC msdb.dbo.sp_add_category
        @class  = N'JOB',
        @type   = N'LOCAL',
        @name   = N'HotelDB - Backups';
END;
GO

IF NOT EXISTS (
    SELECT 1 FROM msdb.dbo.syscategories 
    WHERE name = N'HotelDB - Monitoreo'
    AND category_class = 1
)
BEGIN
    EXEC msdb.dbo.sp_add_category
        @class  = N'JOB',
        @type   = N'LOCAL',
        @name   = N'HotelDB - Monitoreo';
END;
GO

PRINT '>> Categorías de jobs creadas.';
GO


/* =============================================================
   SECCIÓN 3 - JOB 1: BACKUP COMPLETO SEMANAL
   Todos los domingos a las 01:00 AM.
   Genera backup completo con compresión y registra en auditoría.
   ============================================================= */

IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = N'HotelDB - Backup Completo Semanal')
    EXEC msdb.dbo.sp_delete_job @job_name = N'HotelDB - Backup Completo Semanal';
GO

EXEC msdb.dbo.sp_add_job
    @job_name               = N'HotelDB - Backup Completo Semanal',
    @enabled                = 1,
    @description            = N'Genera backup completo de HotelDB cada domingo a las 01:00 AM con compresion. Registra resultado en Auditoria.RegistroAuditoria.',
    @category_name          = N'HotelDB - Backups',
    @owner_login_name       = N'sa',
    @notify_level_eventlog  = 2,    -- registra en Event Log solo si falla
    @notify_level_email     = 2,    -- envía email solo si falla
    @notify_email_operator_name = N'OperadorHotelDB';
GO

EXEC msdb.dbo.sp_add_jobstep
    @job_name       = N'HotelDB - Backup Completo Semanal',
    @step_name      = N'Ejecutar Backup Completo',
    @step_id        = 1,
    @subsystem      = N'TSQL',
    @database_name  = N'HotelDB',
    @command        = N'
EXEC Auditoria.usp_BackupCompleto 
    @RutaBackup = N''C:\Backups\HotelDB\'';
',
    @on_success_action  = 3,    -- ir al siguiente paso
    @on_fail_action     = 2;    -- terminar el job reportando fallo
GO

EXEC msdb.dbo.sp_add_jobstep
    @job_name       = N'HotelDB - Backup Completo Semanal',
    @step_name      = N'Registrar Evidencia',
    @step_id        = 2,
    @subsystem      = N'TSQL',
    @database_name  = N'HotelDB',
    @command        = N'
INSERT INTO Auditoria.RegistroAuditoria (TablaAfectada, Accion, Descripcion)
VALUES (
    ''JOB: Backup Completo Semanal'',
    ''INSERT'',
    ''Job completado exitosamente. Fecha: '' + CONVERT(VARCHAR, GETDATE(), 120)
    + '' | Servidor: '' + @@SERVERNAME
);
',
    @on_success_action  = 1,    -- terminar exitosamente
    @on_fail_action     = 2;
GO

EXEC msdb.dbo.sp_add_jobschedule
    @job_name               = N'HotelDB - Backup Completo Semanal',
    @name                   = N'Cada domingo 01:00 AM',
    @enabled                = 1,
    @freq_type              = 8,        -- semanal
    @freq_interval          = 1,        -- domingo (bit 1)
    @freq_subday_type       = 1,        -- una vez al día
    @freq_subday_interval   = 0,
    @freq_recurrence_factor = 1,        -- cada semana
    @active_start_time      = 10000;    -- 01:00:00
GO

EXEC msdb.dbo.sp_add_jobserver
    @job_name   = N'HotelDB - Backup Completo Semanal',
    @server_name = N'(local)';
GO

PRINT '>> Job 1 creado: Backup Completo Semanal.';
GO


/* =============================================================
   SECCIÓN 4 - JOB 2: BACKUP DIFERENCIAL DIARIO
   Lunes a sábado a las 23:00 PM.
   Complementa el backup completo del domingo.
   ============================================================= */

IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = N'HotelDB - Backup Diferencial Diario')
    EXEC msdb.dbo.sp_delete_job @job_name = N'HotelDB - Backup Diferencial Diario';
GO

EXEC msdb.dbo.sp_add_job
    @job_name               = N'HotelDB - Backup Diferencial Diario',
    @enabled                = 1,
    @description            = N'Genera backup diferencial de HotelDB de lunes a sabado a las 23:00. Registra resultado en auditoria.',
    @category_name          = N'HotelDB - Backups',
    @owner_login_name       = N'sa',
    @notify_level_eventlog  = 2,
    @notify_level_email     = 2,
    @notify_email_operator_name = N'OperadorHotelDB';
GO

EXEC msdb.dbo.sp_add_jobstep
    @job_name       = N'HotelDB - Backup Diferencial Diario',
    @step_name      = N'Ejecutar Backup Diferencial',
    @step_id        = 1,
    @subsystem      = N'TSQL',
    @database_name  = N'HotelDB',
    @command        = N'
EXEC Auditoria.usp_BackupDiferencial 
    @RutaBackup = N''C:\Backups\HotelDB\'';
',
    @on_success_action  = 3,
    @on_fail_action     = 2;
GO

EXEC msdb.dbo.sp_add_jobstep
    @job_name       = N'HotelDB - Backup Diferencial Diario',
    @step_name      = N'Registrar Evidencia',
    @step_id        = 2,
    @subsystem      = N'TSQL',
    @database_name  = N'HotelDB',
    @command        = N'
INSERT INTO Auditoria.RegistroAuditoria (TablaAfectada, Accion, Descripcion)
VALUES (
    ''JOB: Backup Diferencial Diario'',
    ''INSERT'',
    ''Job completado exitosamente. Fecha: '' + CONVERT(VARCHAR, GETDATE(), 120)
    + '' | Servidor: '' + @@SERVERNAME
);
',
    @on_success_action  = 1,
    @on_fail_action     = 2;
GO

EXEC msdb.dbo.sp_add_jobschedule
    @job_name               = N'HotelDB - Backup Diferencial Diario',
    @name                   = N'Lunes a sabado 23:00',
    @enabled                = 1,
    @freq_type              = 8,        -- semanal
    @freq_interval          = 126,      -- lunes(2)+martes(4)+miércoles(8)+jueves(16)+viernes(32)+sábado(64) = 126
    @freq_subday_type       = 1,
    @freq_recurrence_factor = 1,
    @active_start_time      = 230000;   -- 23:00:00
GO

EXEC msdb.dbo.sp_add_jobserver
    @job_name    = N'HotelDB - Backup Diferencial Diario',
    @server_name = N'(local)';
GO

PRINT '>> Job 2 creado: Backup Diferencial Diario.';
GO


/* =============================================================
   SECCIÓN 5 - JOB 3: MANTENIMIENTO DE ÍNDICES DIARIO
   Todos los días a las 02:00 AM.
   Reorganiza o reconstruye índices según fragmentación.
   ============================================================= */

IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = N'HotelDB - Mantenimiento de Indices')
    EXEC msdb.dbo.sp_delete_job @job_name = N'HotelDB - Mantenimiento de Indices';
GO

EXEC msdb.dbo.sp_add_job
    @job_name               = N'HotelDB - Mantenimiento de Indices',
    @enabled                = 1,
    @description            = N'Reorganiza o reconstruye indices de HotelDB segun su fragmentacion. Se ejecuta diariamente a las 02:00 AM.',
    @category_name          = N'HotelDB - Mantenimiento',
    @owner_login_name       = N'sa',
    @notify_level_eventlog  = 2,
    @notify_level_email     = 2,
    @notify_email_operator_name = N'OperadorHotelDB';
GO

EXEC msdb.dbo.sp_add_jobstep
    @job_name       = N'HotelDB - Mantenimiento de Indices',
    @step_name      = N'Ejecutar Mantenimiento de Indices',
    @step_id        = 1,
    @subsystem      = N'TSQL',
    @database_name  = N'HotelDB',
    @command        = N'EXEC Auditoria.usp_MantenimientoIndices;',
    @on_success_action  = 3,
    @on_fail_action     = 2;
GO

EXEC msdb.dbo.sp_add_jobstep
    @job_name       = N'HotelDB - Mantenimiento de Indices',
    @step_name      = N'Actualizar Estadisticas',
    @step_id        = 2,
    @subsystem      = N'TSQL',
    @database_name  = N'HotelDB',
    @command        = N'EXEC Auditoria.usp_ActualizarEstadisticas;',
    @on_success_action  = 3,
    @on_fail_action     = 2;
GO

EXEC msdb.dbo.sp_add_jobstep
    @job_name       = N'HotelDB - Mantenimiento de Indices',
    @step_name      = N'Registrar Evidencia',
    @step_id        = 3,
    @subsystem      = N'TSQL',
    @database_name  = N'HotelDB',
    @command        = N'
INSERT INTO Auditoria.RegistroAuditoria (TablaAfectada, Accion, Descripcion)
VALUES (
    ''JOB: Mantenimiento de Indices'',
    ''UPDATE'',
    ''Mantenimiento de indices y estadisticas completado. Fecha: ''
    + CONVERT(VARCHAR, GETDATE(), 120)
);
',
    @on_success_action  = 1,
    @on_fail_action     = 2;
GO

EXEC msdb.dbo.sp_add_jobschedule
    @job_name               = N'HotelDB - Mantenimiento de Indices',
    @name                   = N'Diario 02:00 AM',
    @enabled                = 1,
    @freq_type              = 4,        -- diario
    @freq_interval          = 1,
    @freq_subday_type       = 1,
    @active_start_time      = 20000;    -- 02:00:00
GO

EXEC msdb.dbo.sp_add_jobserver
    @job_name    = N'HotelDB - Mantenimiento de Indices',
    @server_name = N'(local)';
GO

PRINT '>> Job 3 creado: Mantenimiento de Indices Diario.';
GO


/* =============================================================
   SECCIÓN 6 - JOB 4: VERIFICACIÓN DE INTEGRIDAD MENSUAL
   Primer día de cada mes a las 00:30 AM.
   Ejecuta DBCC CHECKDB y registra resultado.
   ============================================================= */

IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = N'HotelDB - Verificacion de Integridad')
    EXEC msdb.dbo.sp_delete_job @job_name = N'HotelDB - Verificacion de Integridad';
GO

EXEC msdb.dbo.sp_add_job
    @job_name               = N'HotelDB - Verificacion de Integridad',
    @enabled                = 1,
    @description            = N'Ejecuta DBCC CHECKDB sobre HotelDB el primer dia de cada mes. Detecta corrupcion de paginas y registra el resultado en auditoria.',
    @category_name          = N'HotelDB - Mantenimiento',
    @owner_login_name       = N'sa',
    @notify_level_eventlog  = 2,
    @notify_level_email     = 2,
    @notify_email_operator_name = N'OperadorHotelDB';
GO

EXEC msdb.dbo.sp_add_jobstep
    @job_name       = N'HotelDB - Verificacion de Integridad',
    @step_name      = N'DBCC CHECKDB',
    @step_id        = 1,
    @subsystem      = N'TSQL',
    @database_name  = N'HotelDB',
    @command        = N'EXEC Auditoria.usp_VerificarIntegridad;',
    @on_success_action  = 3,
    @on_fail_action     = 2;
GO

EXEC msdb.dbo.sp_add_jobstep
    @job_name       = N'HotelDB - Verificacion de Integridad',
    @step_name      = N'Registrar Evidencia',
    @step_id        = 2,
    @subsystem      = N'TSQL',
    @database_name  = N'HotelDB',
    @command        = N'
INSERT INTO Auditoria.RegistroAuditoria (TablaAfectada, Accion, Descripcion)
VALUES (
    ''JOB: Verificacion de Integridad'',
    ''UPDATE'',
    ''DBCC CHECKDB completado sin errores detectados. Fecha: ''
    + CONVERT(VARCHAR, GETDATE(), 120)
    + '' | Servidor: '' + @@SERVERNAME
);
',
    @on_success_action  = 1,
    @on_fail_action     = 2;
GO

EXEC msdb.dbo.sp_add_jobschedule
    @job_name               = N'HotelDB - Verificacion de Integridad',
    @name                   = N'Primer dia del mes 00:30 AM',
    @enabled                = 1,
    @freq_type              = 16,       -- mensual
    @freq_interval          = 1,        -- día 1 del mes
    @freq_subday_type       = 1,
    @freq_recurrence_factor = 1,
    @active_start_time      = 3000;     -- 00:30:00
GO

EXEC msdb.dbo.sp_add_jobserver
    @job_name    = N'HotelDB - Verificacion de Integridad',
    @server_name = N'(local)';
GO

PRINT '>> Job 4 creado: Verificacion de Integridad Mensual.';
GO


/* =============================================================
   SECCIÓN 7 - JOB 5: LIMPIEZA DE AUDITORÍA MENSUAL
   Día 2 de cada mes a las 01:00 AM.
   Archiva y purga registros con más de 90 días.
   ============================================================= */

IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = N'HotelDB - Limpieza de Auditoria')
    EXEC msdb.dbo.sp_delete_job @job_name = N'HotelDB - Limpieza de Auditoria';
GO

EXEC msdb.dbo.sp_add_job
    @job_name               = N'HotelDB - Limpieza de Auditoria',
    @enabled                = 1,
    @description            = N'Archiva registros de auditoria mayores a 90 dias en HistorialAuditoria y los elimina de RegistroAuditoria. Se ejecuta el dia 2 de cada mes.',
    @category_name          = N'HotelDB - Mantenimiento',
    @owner_login_name       = N'sa',
    @notify_level_eventlog  = 2,
    @notify_level_email     = 2,
    @notify_email_operator_name = N'OperadorHotelDB';
GO

EXEC msdb.dbo.sp_add_jobstep
    @job_name       = N'HotelDB - Limpieza de Auditoria',
    @step_name      = N'Archivar y Purgar Auditoria',
    @step_id        = 1,
    @subsystem      = N'TSQL',
    @database_name  = N'HotelDB',
    @command        = N'EXEC Auditoria.usp_LimpiarAuditoria @DiasRetener = 90;',
    @on_success_action  = 3,
    @on_fail_action     = 2;
GO

EXEC msdb.dbo.sp_add_jobstep
    @job_name       = N'HotelDB - Limpieza de Auditoria',
    @step_name      = N'Registrar Evidencia',
    @step_id        = 2,
    @subsystem      = N'TSQL',
    @database_name  = N'HotelDB',
    @command        = N'
INSERT INTO Auditoria.RegistroAuditoria (TablaAfectada, Accion, Descripcion)
VALUES (
    ''JOB: Limpieza de Auditoria'',
    ''DELETE'',
    ''Limpieza de auditoria completada (retención 90 días). Fecha: ''
    + CONVERT(VARCHAR, GETDATE(), 120)
);
',
    @on_success_action  = 1,
    @on_fail_action     = 2;
GO

EXEC msdb.dbo.sp_add_jobschedule
    @job_name               = N'HotelDB - Limpieza de Auditoria',
    @name                   = N'Dia 2 del mes 01:00 AM',
    @enabled                = 1,
    @freq_type              = 16,
    @freq_interval          = 2,        -- día 2 del mes
    @freq_subday_type       = 1,
    @freq_recurrence_factor = 1,
    @active_start_time      = 10000;    -- 01:00:00
GO

EXEC msdb.dbo.sp_add_jobserver
    @job_name    = N'HotelDB - Limpieza de Auditoria',
    @server_name = N'(local)';
GO

PRINT '>> Job 5 creado: Limpieza de Auditoria Mensual.';
GO


/* =============================================================
   SECCIÓN 8 - JOB 6: CONTROL DE EXTENDED EVENTS
   Todos los días a las 00:05 AM.
   Verifica y reinicia las sesiones XE si están caídas.
   ============================================================= */

IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = N'HotelDB - Control de Extended Events')
    EXEC msdb.dbo.sp_delete_job @job_name = N'HotelDB - Control de Extended Events';
GO

EXEC msdb.dbo.sp_add_job
    @job_name               = N'HotelDB - Control de Extended Events',
    @enabled                = 1,
    @description            = N'Verifica que las sesiones de Extended Events esten activas y las reinicia si estan detenidas. Se ejecuta diariamente a las 00:05 AM.',
    @category_name          = N'HotelDB - Monitoreo',
    @owner_login_name       = N'sa',
    @notify_level_eventlog  = 2,
    @notify_level_email     = 2,
    @notify_email_operator_name = N'OperadorHotelDB';
GO

EXEC msdb.dbo.sp_add_jobstep
    @job_name       = N'HotelDB - Control de Extended Events',
    @step_name      = N'Verificar y Reiniciar Sesiones XE',
    @step_id        = 1,
    @subsystem      = N'TSQL',
    @database_name  = N'HotelDB',
    @command        = N'
DECLARE @SesionDetenida BIT = 0;

-- Verifica si alguna sesión XE del hotel no está en ejecución
IF EXISTS (
    SELECT 1
    FROM sys.server_event_sessions      s
    LEFT JOIN sys.dm_xe_sessions        r ON s.name = r.name
    WHERE s.name LIKE N''XE_HotelDB_%''
      AND r.name IS NULL               -- no está activa
)
BEGIN
    SET @SesionDetenida = 1;
    EXEC HotelDB.Auditoria.usp_IniciarSesionesXE;

    INSERT INTO HotelDB.Auditoria.RegistroAuditoria
        (TablaAfectada, Accion, Descripcion)
    VALUES (
        ''JOB: Control Extended Events'',
        ''UPDATE'',
        ''Se detectaron sesiones XE detenidas y fueron reiniciadas. Fecha: ''
        + CONVERT(VARCHAR, GETDATE(), 120)
    );
END;
ELSE
BEGIN
    INSERT INTO HotelDB.Auditoria.RegistroAuditoria
        (TablaAfectada, Accion, Descripcion)
    VALUES (
        ''JOB: Control Extended Events'',
        ''UPDATE'',
        ''Todas las sesiones XE activas correctamente. Fecha: ''
        + CONVERT(VARCHAR, GETDATE(), 120)
    );
END;
',
    @on_success_action  = 1,
    @on_fail_action     = 2;
GO

EXEC msdb.dbo.sp_add_jobschedule
    @job_name               = N'HotelDB - Control de Extended Events',
    @name                   = N'Diario 00:05 AM',
    @enabled                = 1,
    @freq_type              = 4,
    @freq_interval          = 1,
    @freq_subday_type       = 1,
    @active_start_time      = 500;      -- 00:05:00
GO

EXEC msdb.dbo.sp_add_jobserver
    @job_name    = N'HotelDB - Control de Extended Events',
    @server_name = N'(local)';
GO

PRINT '>> Job 6 creado: Control de Extended Events.';
GO


/* =============================================================
   SECCIÓN 9 - JOB 7: DIAGNÓSTICO Y MONITOREO SEMANAL
   Todos los lunes a las 07:00 AM.
   Genera reporte operativo completo del estado del hotel.
   ============================================================= */

IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = N'HotelDB - Diagnostico Semanal')
    EXEC msdb.dbo.sp_delete_job @job_name = N'HotelDB - Diagnostico Semanal';
GO

EXEC msdb.dbo.sp_add_job
    @job_name               = N'HotelDB - Diagnostico Semanal',
    @enabled                = 1,
    @description            = N'Ejecuta el diagnostico completo de HotelDB cada lunes a las 07:00 AM: tamano de BD, filas por tabla, indices fragmentados, reservas activas, pagos pendientes y mantenimientos en curso.',
    @category_name          = N'HotelDB - Monitoreo',
    @owner_login_name       = N'sa',
    @notify_level_eventlog  = 2,
    @notify_level_email     = 2,
    @notify_email_operator_name = N'OperadorHotelDB';
GO

EXEC msdb.dbo.sp_add_jobstep
    @job_name       = N'HotelDB - Diagnostico Semanal',
    @step_name      = N'Ejecutar Diagnostico del Sistema',
    @step_id        = 1,
    @subsystem      = N'TSQL',
    @database_name  = N'HotelDB',
    @command        = N'EXEC Auditoria.usp_DiagnosticoSistema;',
    @on_success_action  = 3,
    @on_fail_action     = 2;
GO

EXEC msdb.dbo.sp_add_jobstep
    @job_name       = N'HotelDB - Diagnostico Semanal',
    @step_name      = N'Registrar Evidencia',
    @step_id        = 2,
    @subsystem      = N'TSQL',
    @database_name  = N'HotelDB',
    @command        = N'
INSERT INTO Auditoria.RegistroAuditoria (TablaAfectada, Accion, Descripcion)
VALUES (
    ''JOB: Diagnostico Semanal'',
    ''UPDATE'',
    ''Diagnostico semanal completado. Fecha: ''
    + CONVERT(VARCHAR, GETDATE(), 120)
    + '' | Servidor: '' + @@SERVERNAME
);
',
    @on_success_action  = 1,
    @on_fail_action     = 2;
GO

EXEC msdb.dbo.sp_add_jobschedule
    @job_name               = N'HotelDB - Diagnostico Semanal',
    @name                   = N'Lunes 07:00 AM',
    @enabled                = 1,
    @freq_type              = 8,        -- semanal
    @freq_interval          = 2,        -- lunes (bit 2)
    @freq_subday_type       = 1,
    @freq_recurrence_factor = 1,
    @active_start_time      = 70000;    -- 07:00:00
GO

EXEC msdb.dbo.sp_add_jobserver
    @job_name    = N'HotelDB - Diagnostico Semanal',
    @server_name = N'(local)';
GO

PRINT '>> Job 7 creado: Diagnostico Semanal.';
GO


/* =============================================================
   SECCIÓN 10 - TABLA DE EVIDENCIA DE EJECUCIÓN DE JOBS
   Registra cada ejecución de job con resultado, duración
   y mensaje. Complementa msdb.dbo.sysjobhistory.
   ============================================================= */

USE HotelDB;
GO

IF OBJECT_ID('Auditoria.EvidenciaJobs', 'U') IS NULL
BEGIN
    CREATE TABLE Auditoria.EvidenciaJobs (
        EvidenciaID     INT IDENTITY(1,1),
        NombreJob       VARCHAR(150)    NOT NULL,
        FechaEjecucion  DATETIME        NOT NULL DEFAULT GETDATE(),
        Resultado       VARCHAR(20)     NOT NULL,   -- 'Exitoso' / 'Fallido'
        DuracionSeg     INT             NULL,
        Mensaje         VARCHAR(500)    NULL,
        Servidor        VARCHAR(128)    NOT NULL DEFAULT @@SERVERNAME,

        CONSTRAINT PK_EvidenciaJobs     PRIMARY KEY (EvidenciaID),
        CONSTRAINT CK_EvidenciaJobs_Res CHECK (Resultado IN ('Exitoso', 'Fallido'))
    );
END;
GO

PRINT '>> Tabla Auditoria.EvidenciaJobs creada.';
GO


/* =============================================================
   SECCIÓN 11 - PROCEDIMIENTO DE CONSULTA DE HISTORIAL
   Lee el historial de ejecución directamente desde msdb
   y la tabla de evidencia propia de HotelDB.
   ============================================================= */

CREATE OR ALTER PROCEDURE Auditoria.usp_HistorialJobs
    @NombreJob  VARCHAR(150)    = NULL,     -- NULL = todos los jobs
    @UltimosDias INT            = 7
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @FechaDesde DATETIME = DATEADD(DAY, -@UltimosDias, GETDATE());

    -- 1. Historial desde msdb (fuente oficial del Agente SQL)
    SELECT
        j.name                                              AS NombreJob,
        jh.step_name                                        AS Paso,
        CASE jh.run_status
            WHEN 0 THEN 'Fallido'
            WHEN 1 THEN 'Exitoso'
            WHEN 2 THEN 'Reintento'
            WHEN 3 THEN 'Cancelado'
            ELSE 'Desconocido'
        END                                                 AS Resultado,
        -- Convierte el formato HHMMSS del agente a datetime legible
        CAST(
            STUFF(STUFF(RIGHT('000000' + CAST(jh.run_time AS VARCHAR), 6), 5, 0, ':'), 3, 0, ':')
            AS TIME)                                        AS HoraEjecucion,
        msdb.dbo.agent_datetime(jh.run_date, jh.run_time)  AS FechaHoraEjecucion,
        -- Duración en segundos desde el formato HHMMSS
        (jh.run_duration / 10000) * 3600
        + ((jh.run_duration % 10000) / 100) * 60
        + (jh.run_duration % 100)                          AS DuracionSeg,
        jh.message                                          AS Mensaje
    FROM msdb.dbo.sysjobhistory    jh
    INNER JOIN msdb.dbo.sysjobs    j  ON jh.job_id = j.job_id
    WHERE j.name LIKE N'HotelDB -%'
      AND msdb.dbo.agent_datetime(jh.run_date, jh.run_time) >= @FechaDesde
      AND (@NombreJob IS NULL OR j.name = @NombreJob)
      AND jh.step_id > 0           -- excluye la fila resumen (step 0)
    ORDER BY FechaHoraEjecucion DESC, j.name, jh.step_id;

    -- 2. Evidencia registrada en HotelDB
    SELECT
        EvidenciaID,
        NombreJob,
        FechaEjecucion,
        Resultado,
        DuracionSeg,
        Mensaje,
        Servidor
    FROM Auditoria.EvidenciaJobs
    WHERE FechaEjecucion >= @FechaDesde
      AND (@NombreJob IS NULL OR NombreJob = @NombreJob)
    ORDER BY FechaEjecucion DESC;
END;
GO

PRINT '>> Procedimiento usp_HistorialJobs creado.';
GO


/* =============================================================
   SECCIÓN 12 - VERIFICACIÓN FINAL
   Lista todos los jobs creados con su estado y próxima ejecución.
   ============================================================= */

USE msdb;
GO

SELECT
    j.name                                          AS NombreJob,
    j.description                                   AS Descripcion,
    c.name                                          AS Categoria,
    CASE j.enabled
        WHEN 1 THEN 'Habilitado'
        ELSE 'Deshabilitado'
    END                                             AS Estado,
    js.next_run_date,
    STUFF(STUFF(RIGHT('000000' 
        + CAST(js.next_run_time AS VARCHAR), 6), 5, 0, ':'), 3, 0, ':')
                                                    AS ProximaEjecucion,
    js.schedule_name                                AS NombreHorario
FROM msdb.dbo.sysjobs              j
INNER JOIN msdb.dbo.syscategories  c  ON j.category_id     = c.category_id
LEFT  JOIN msdb.dbo.sysjobschedules jsch ON j.job_id       = jsch.job_id
LEFT  JOIN msdb.dbo.sysschedules    js   ON jsch.schedule_id = js.schedule_id
WHERE j.name LIKE N'HotelDB -%'
ORDER BY c.name, j.name;
GO

PRINT '================================================================';
PRINT ' SQL Server Agent Jobs de HotelDB instalados correctamente.';
PRINT ' Para consultar el historial de ejecucion:';
PRINT '   EXEC HotelDB.Auditoria.usp_HistorialJobs;';
PRINT '   EXEC HotelDB.Auditoria.usp_HistorialJobs @NombreJob = ''HotelDB - Backup Completo Semanal'';';
PRINT '================================================================';
GO