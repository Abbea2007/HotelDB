USE master;
GO

/* =============================================================
   SCRIPT: EXTENDED EVENTS - MONITOREO Y CAPTURA DE EVENTOS
   BASE DE DATOS: HotelDB
   DESCRIPCIÓN: Sesiones XE para monitorear rendimiento, seguridad,
                errores, bloqueos y actividad operativa del hotel.
   VERSIÓN: 1.0
   ============================================================= */


/* =============================================================
   SECCIÓN 1 - SESIÓN: CONSULTAS LENTAS
   Captura queries que superen 1 segundo de duración.
   Útil para detectar consultas mal optimizadas en reservas y pagos.
   ============================================================= */

IF EXISTS (
    SELECT 1 FROM sys.server_event_sessions 
    WHERE name = 'XE_HotelDB_ConsultasLentas'
)
    DROP EVENT SESSION XE_HotelDB_ConsultasLentas ON SERVER;
GO

CREATE EVENT SESSION XE_HotelDB_ConsultasLentas
ON SERVER

ADD EVENT sqlserver.sql_statement_completed (
    ACTION (
        sqlserver.sql_text,
        sqlserver.database_name,
        sqlserver.username,
        sqlserver.client_hostname,
        sqlserver.client_app_name,
        sqlserver.plan_handle,
        sqlserver.query_hash
    )
    WHERE (
        sqlserver.database_name = N'HotelDB'
        AND duration > 1000000      -- duración en microsegundos (1 segundo)
    )
),

ADD EVENT sqlserver.rpc_completed (
    ACTION (
        sqlserver.sql_text,
        sqlserver.database_name,
        sqlserver.username,
        sqlserver.client_hostname,
        sqlserver.plan_handle
    )
    WHERE (
        sqlserver.database_name = N'HotelDB'
        AND duration > 1000000
    )
)

ADD TARGET package0.event_file (
    SET filename            = N'C:\XEvents\HotelDB\ConsultasLentas.xel',
        max_file_size       = 50,       -- MB por archivo
        max_rollover_files  = 5
),
ADD TARGET package0.ring_buffer (
    SET max_memory = 10240              -- KB en memoria (10 MB)
)

WITH (
    MAX_DISPATCH_LATENCY    = 5 SECONDS,
    EVENT_RETENTION_MODE    = ALLOW_SINGLE_EVENT_LOSS,
    MAX_EVENT_SIZE          = 0 KB,
    MEMORY_PARTITION_MODE   = NONE,
    TRACK_CAUSALITY         = ON,
    STARTUP_STATE           = ON        -- se inicia automáticamente con SQL Server
);
GO

PRINT '>> Sesión XE_HotelDB_ConsultasLentas creada.';
GO


/* =============================================================
   SECCIÓN 2 - SESIÓN: ERRORES Y EXCEPCIONES
   Captura errores de usuario, violaciones de constraints y
   errores de severidad media-alta dentro de HotelDB.
   ============================================================= */

IF EXISTS (
    SELECT 1 FROM sys.server_event_sessions 
    WHERE name = 'XE_HotelDB_Errores'
)
    DROP EVENT SESSION XE_HotelDB_Errores ON SERVER;
GO

CREATE EVENT SESSION XE_HotelDB_Errores
ON SERVER

ADD EVENT sqlserver.error_reported (
    ACTION (
        sqlserver.sql_text,
        sqlserver.database_name,
        sqlserver.username,
        sqlserver.client_hostname,
        sqlserver.client_app_name,
        sqlserver.session_id
    )
    WHERE (
        sqlserver.database_name = N'HotelDB'
        AND severity >= 11          -- errores que afectan la operación (11-25)
    )
),

ADD EVENT sqlserver.user_error_reported (
    ACTION (
        sqlserver.sql_text,
        sqlserver.database_name,
        sqlserver.username,
        sqlserver.session_id
    )
    WHERE (
        sqlserver.database_name = N'HotelDB'
    )
),

-- Violaciones de constraints (PK, FK, CHECK, UNIQUE)
ADD EVENT sqlserver.exception (
    ACTION (
        sqlserver.sql_text,
        sqlserver.database_name,
        sqlserver.username,
        sqlserver.session_id
    )
    WHERE (
        sqlserver.database_name = N'HotelDB'
    )
)

ADD TARGET package0.event_file (
    SET filename            = N'C:\XEvents\HotelDB\Errores.xel',
        max_file_size       = 30,
        max_rollover_files  = 5
),
ADD TARGET package0.ring_buffer (
    SET max_memory = 5120
)

WITH (
    MAX_DISPATCH_LATENCY    = 5 SECONDS,
    EVENT_RETENTION_MODE    = ALLOW_SINGLE_EVENT_LOSS,
    TRACK_CAUSALITY         = ON,
    STARTUP_STATE           = ON
);
GO

PRINT '>> Sesión XE_HotelDB_Errores creada.';
GO


/* =============================================================
   SECCIÓN 3 - SESIÓN: BLOQUEOS Y DEADLOCKS
   Captura deadlocks y esperas largas en tablas críticas:
   Reservas, Habitaciones y Pagos.
   ============================================================= */

IF EXISTS (
    SELECT 1 FROM sys.server_event_sessions 
    WHERE name = 'XE_HotelDB_Bloqueos'
)
    DROP EVENT SESSION XE_HotelDB_Bloqueos ON SERVER;
GO

CREATE EVENT SESSION XE_HotelDB_Bloqueos
ON SERVER

-- Deadlock con gráfico XML completo
ADD EVENT sqlserver.xml_deadlock_report (
    ACTION (
        sqlserver.database_name,
        sqlserver.username,
        sqlserver.session_id
    )
    WHERE (
        sqlserver.database_name = N'HotelDB'
    )
),

-- Lock adquirido con espera > 3 segundos
ADD EVENT sqlserver.lock_acquired (
    ACTION (
        sqlserver.sql_text,
        sqlserver.database_name,
        sqlserver.username,
        sqlserver.session_id
    )
    WHERE (
        sqlserver.database_name = N'HotelDB'
        AND duration > 3000000      -- 3 segundos
    )
),

-- Lock liberado tras espera prolongada
ADD EVENT sqlserver.lock_released (
    ACTION (
        sqlserver.sql_text,
        sqlserver.database_name,
        sqlserver.username
    )
    WHERE (
        sqlserver.database_name = N'HotelDB'
        AND duration > 3000000
    )
),

-- Escalación de bloqueos (muchos locks → lock de tabla)
ADD EVENT sqlserver.lock_escalation (
    ACTION (
        sqlserver.sql_text,
        sqlserver.database_name,
        sqlserver.username,
        sqlserver.session_id
    )
    WHERE (
        sqlserver.database_name = N'HotelDB'
    )
)

ADD TARGET package0.event_file (
    SET filename            = N'C:\XEvents\HotelDB\Bloqueos.xel',
        max_file_size       = 30,
        max_rollover_files  = 5
),
ADD TARGET package0.ring_buffer (
    SET max_memory = 5120
)

WITH (
    MAX_DISPATCH_LATENCY    = 5 SECONDS,
    EVENT_RETENTION_MODE    = ALLOW_SINGLE_EVENT_LOSS,
    TRACK_CAUSALITY         = ON,
    STARTUP_STATE           = ON
);
GO

PRINT '>> Sesión XE_HotelDB_Bloqueos creada.';
GO


/* =============================================================
   SECCIÓN 4 - SESIÓN: SEGURIDAD Y ACCESOS
   Monitorea intentos de login fallidos, cambios de permisos
   y accesos sospechosos sobre HotelDB.
   ============================================================= */

IF EXISTS (
    SELECT 1 FROM sys.server_event_sessions 
    WHERE name = 'XE_HotelDB_Seguridad'
)
    DROP EVENT SESSION XE_HotelDB_Seguridad ON SERVER;
GO

CREATE EVENT SESSION XE_HotelDB_Seguridad
ON SERVER

-- Logins fallidos
ADD EVENT sqlserver.error_reported (
    ACTION (
        sqlserver.username,
        sqlserver.client_hostname,
        sqlserver.client_app_name,
        sqlserver.session_id
    )
    WHERE (
        error_number = 18456        -- Login failed
    )
),

-- Logins exitosos de usuarios del hotel
ADD EVENT sqlserver.login (
    ACTION (
        sqlserver.username,
        sqlserver.client_hostname,
        sqlserver.client_app_name
    )
    WHERE (
        sqlserver.username LIKE N'login_%_hotel'
    )
),

-- Logout de usuarios del hotel
ADD EVENT sqlserver.logout (
    ACTION (
        sqlserver.username,
        sqlserver.client_hostname
    )
    WHERE (
        sqlserver.username LIKE N'login_%_hotel'
    )
),

-- Cambios de permisos (GRANT / REVOKE / DENY)
ADD EVENT sqlserver.audit_database_permission_event (
    ACTION (
        sqlserver.sql_text,
        sqlserver.username,
        sqlserver.database_name,
        sqlserver.session_id
    )
    WHERE (
        sqlserver.database_name = N'HotelDB'
    )
),

-- Creación o modificación de usuarios/roles
ADD EVENT sqlserver.audit_add_member_to_db_role_event (
    ACTION (
        sqlserver.username,
        sqlserver.database_name
    )
    WHERE (
        sqlserver.database_name = N'HotelDB'
    )
)

ADD TARGET package0.event_file (
    SET filename            = N'C:\XEvents\HotelDB\Seguridad.xel',
        max_file_size       = 50,
        max_rollover_files  = 10    -- más historial para auditoría de seguridad
),
ADD TARGET package0.ring_buffer (
    SET max_memory = 10240
)

WITH (
    MAX_DISPATCH_LATENCY    = 5 SECONDS,
    EVENT_RETENTION_MODE    = ALLOW_SINGLE_EVENT_LOSS,
    TRACK_CAUSALITY         = ON,
    STARTUP_STATE           = ON
);
GO

PRINT '>> Sesión XE_HotelDB_Seguridad creada.';
GO


/* =============================================================
   SECCIÓN 5 - SESIÓN: ACTIVIDAD OPERATIVA (CHECK-IN / CHECK-OUT)
   Captura inserciones y modificaciones en las tablas más
   sensibles del negocio hotelero.
   ============================================================= */

IF EXISTS (
    SELECT 1 FROM sys.server_event_sessions 
    WHERE name = 'XE_HotelDB_ActividadOperativa'
)
    DROP EVENT SESSION XE_HotelDB_ActividadOperativa ON SERVER;
GO

CREATE EVENT SESSION XE_HotelDB_ActividadOperativa
ON SERVER

-- DML sobre tablas clave (INSERT, UPDATE, DELETE)
ADD EVENT sqlserver.sql_statement_completed (
    ACTION (
        sqlserver.sql_text,
        sqlserver.database_name,
        sqlserver.username,
        sqlserver.client_hostname,
        sqlserver.client_app_name,
        sqlserver.session_id,
        sqlserver.transaction_id
    )
    WHERE (
        sqlserver.database_name = N'HotelDB'
        -- Filtra solo statements que tocan las tablas operativas clave
        AND (
               sqlserver.sql_text LIKE N'%CheckIn%'
            OR sqlserver.sql_text LIKE N'%CheckOut%'
            OR sqlserver.sql_text LIKE N'%Reservas%'
            OR sqlserver.sql_text LIKE N'%Pagos%'
            OR sqlserver.sql_text LIKE N'%Habitaciones%'
        )
    )
),

-- Transacciones que hacen commit en HotelDB
ADD EVENT sqlserver.sql_transaction (
    ACTION (
        sqlserver.database_name,
        sqlserver.username,
        sqlserver.session_id,
        sqlserver.transaction_id
    )
    WHERE (
        sqlserver.database_name = N'HotelDB'
    )
)

ADD TARGET package0.event_file (
    SET filename            = N'C:\XEvents\HotelDB\ActividadOperativa.xel',
        max_file_size       = 100,
        max_rollover_files  = 5
),
ADD TARGET package0.ring_buffer (
    SET max_memory = 20480          -- 20 MB — mayor volumen esperado
)

WITH (
    MAX_DISPATCH_LATENCY    = 10 SECONDS,
    EVENT_RETENTION_MODE    = ALLOW_SINGLE_EVENT_LOSS,
    TRACK_CAUSALITY         = ON,
    STARTUP_STATE           = ON
);
GO

PRINT '>> Sesión XE_HotelDB_ActividadOperativa creada.';
GO


/* =============================================================
   SECCIÓN 6 - CONTROL DE SESIONES
   Procedimientos para iniciar, detener y consultar el estado
   de todas las sesiones XE de HotelDB.
   ============================================================= */

USE HotelDB;
GO

-- Inicia todas las sesiones XE del hotel
CREATE OR ALTER PROCEDURE Auditoria.usp_IniciarSesionesXE
AS
BEGIN
    SET NOCOUNT ON;

    ALTER EVENT SESSION XE_HotelDB_ConsultasLentas    ON SERVER STATE = START;
    ALTER EVENT SESSION XE_HotelDB_Errores            ON SERVER STATE = START;
    ALTER EVENT SESSION XE_HotelDB_Bloqueos           ON SERVER STATE = START;
    ALTER EVENT SESSION XE_HotelDB_Seguridad          ON SERVER STATE = START;
    ALTER EVENT SESSION XE_HotelDB_ActividadOperativa ON SERVER STATE = START;

    INSERT INTO Auditoria.RegistroAuditoria
        (TablaAfectada, Accion, Descripcion)
    VALUES
        ('Extended Events', 'UPDATE',
         'Todas las sesiones XE iniciadas por: ' + SYSTEM_USER);

    PRINT '>> Todas las sesiones XE de HotelDB han sido iniciadas.';
END;
GO

-- Detiene todas las sesiones XE del hotel
CREATE OR ALTER PROCEDURE Auditoria.usp_DetenerSesionesXE
AS
BEGIN
    SET NOCOUNT ON;

    ALTER EVENT SESSION XE_HotelDB_ConsultasLentas    ON SERVER STATE = STOP;
    ALTER EVENT SESSION XE_HotelDB_Errores            ON SERVER STATE = STOP;
    ALTER EVENT SESSION XE_HotelDB_Bloqueos           ON SERVER STATE = STOP;
    ALTER EVENT SESSION XE_HotelDB_Seguridad          ON SERVER STATE = STOP;
    ALTER EVENT SESSION XE_HotelDB_ActividadOperativa ON SERVER STATE = STOP;

    INSERT INTO Auditoria.RegistroAuditoria
        (TablaAfectada, Accion, Descripcion)
    VALUES
        ('Extended Events', 'UPDATE',
         'Todas las sesiones XE detenidas por: ' + SYSTEM_USER);

    PRINT '>> Todas las sesiones XE de HotelDB han sido detenidas.';
END;
GO

PRINT '>> Sección 6 completada: Procedimientos de control XE creados.';
GO


/* =============================================================
   SECCIÓN 7 - CONSULTAS DE MONITOREO EN TIEMPO REAL
   Permiten leer los eventos capturados desde el ring_buffer
   (memoria) sin necesidad de abrir los archivos .xel.
   ============================================================= */

-- 7.1 Estado actual de todas las sesiones XE
CREATE OR ALTER VIEW Auditoria.vw_EstadoSesionesXE
AS
SELECT
    s.name                                          AS NombreSesion,
    CASE s.event_session_id
        WHEN 0 THEN 'Detenida'
        ELSE 'Activa'
    END                                             AS EstadoDefinicion,
    CASE 
        WHEN r.name IS NOT NULL THEN 'EN EJECUCIÓN'
        ELSE 'DETENIDA'
    END                                             AS EstadoEjecucion,
    s.max_dispatch_latency,
    s.startup_state
FROM sys.server_event_sessions          s
LEFT JOIN sys.dm_xe_sessions            r ON s.name = r.name
WHERE s.name LIKE 'XE_HotelDB_%';
GO


-- 7.2 Consultas lentas desde ring_buffer (últimos eventos en memoria)
CREATE OR ALTER PROCEDURE Auditoria.usp_ConsultarConsultasLentas
    @Top INT = 50
AS
BEGIN
    SET NOCOUNT ON;

    SELECT TOP (@Top)
        event_data.value('(event/@timestamp)[1]',   'DATETIME2')    AS FechaHora,
        event_data.value('(event/data[@name="duration"]/value)[1]',
                         'BIGINT') / 1000                            AS DuracionMS,
        event_data.value('(event/action[@name="database_name"]/value)[1]',
                         'NVARCHAR(128)')                            AS BaseDatos,
        event_data.value('(event/action[@name="username"]/value)[1]',
                         'NVARCHAR(128)')                            AS Usuario,
        event_data.value('(event/action[@name="client_hostname"]/value)[1]',
                         'NVARCHAR(256)')                            AS Host,
        LEFT(
            event_data.value('(event/action[@name="sql_text"]/value)[1]',
                             'NVARCHAR(MAX)'), 500)                  AS TextoSQL
    FROM (
        SELECT
            CAST(xdr.target_data AS XML).nodes('//RingBufferTarget/event') AS t(event_data)
        FROM sys.dm_xe_sessions             s
        JOIN sys.dm_xe_session_targets      xdr ON s.address = xdr.event_session_address
        WHERE s.name  = 'XE_HotelDB_ConsultasLentas'
          AND xdr.target_name = 'ring_buffer'
    ) AS src
    ORDER BY DuracionMS DESC;
END;
GO


-- 7.3 Errores recientes desde ring_buffer
CREATE OR ALTER PROCEDURE Auditoria.usp_ConsultarErrores
    @Top INT = 50
AS
BEGIN
    SET NOCOUNT ON;

    SELECT TOP (@Top)
        event_data.value('(event/@timestamp)[1]',   'DATETIME2')    AS FechaHora,
        event_data.value('(event/data[@name="error_number"]/value)[1]',
                         'INT')                                      AS NumeroError,
        event_data.value('(event/data[@name="severity"]/value)[1]',
                         'INT')                                      AS Severidad,
        event_data.value('(event/data[@name="message"]/value)[1]',
                         'NVARCHAR(MAX)')                            AS Mensaje,
        event_data.value('(event/action[@name="username"]/value)[1]',
                         'NVARCHAR(128)')                            AS Usuario,
        event_data.value('(event/action[@name="session_id"]/value)[1]',
                         'INT')                                      AS SesionID,
        LEFT(
            event_data.value('(event/action[@name="sql_text"]/value)[1]',
                             'NVARCHAR(MAX)'), 500)                  AS TextoSQL
    FROM (
        SELECT
            CAST(xdr.target_data AS XML).nodes('//RingBufferTarget/event') AS t(event_data)
        FROM sys.dm_xe_sessions             s
        JOIN sys.dm_xe_session_targets      xdr ON s.address = xdr.event_session_address
        WHERE s.name  = 'XE_HotelDB_Errores'
          AND xdr.target_name = 'ring_buffer'
    ) AS src
    ORDER BY FechaHora DESC;
END;
GO


-- 7.4 Deadlocks capturados desde ring_buffer
CREATE OR ALTER PROCEDURE Auditoria.usp_ConsultarDeadlocks
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        event_data.value('(event/@timestamp)[1]',   'DATETIME2')    AS FechaHora,
        event_data.value('(event/action[@name="database_name"]/value)[1]',
                         'NVARCHAR(128)')                            AS BaseDatos,
        event_data.value('(event/action[@name="username"]/value)[1]',
                         'NVARCHAR(128)')                            AS Usuario,
        -- El XML del deadlock completo para análisis
        CAST(event_data.value('(event/data[@name="xml_report"]/value)[1]',
                              'NVARCHAR(MAX)') AS XML)               AS GraficoDeadlock
    FROM (
        SELECT
            CAST(xdr.target_data AS XML).nodes('//RingBufferTarget/event') AS t(event_data)
        FROM sys.dm_xe_sessions             s
        JOIN sys.dm_xe_session_targets      xdr ON s.address = xdr.event_session_address
        WHERE s.name  = 'XE_HotelDB_Bloqueos'
          AND xdr.target_name = 'ring_buffer'
    ) AS src
    ORDER BY FechaHora DESC;
END;
GO


-- 7.5 Eventos de seguridad: logins fallidos y cambios de permisos
CREATE OR ALTER PROCEDURE Auditoria.usp_ConsultarEventosSeguridad
    @Top INT = 100
AS
BEGIN
    SET NOCOUNT ON;

    SELECT TOP (@Top)
        event_data.value('(event/@name)[1]',        'NVARCHAR(128)') AS TipoEvento,
        event_data.value('(event/@timestamp)[1]',   'DATETIME2')     AS FechaHora,
        event_data.value('(event/action[@name="username"]/value)[1]',
                         'NVARCHAR(128)')                             AS Usuario,
        event_data.value('(event/action[@name="client_hostname"]/value)[1]',
                         'NVARCHAR(256)')                             AS Host,
        event_data.value('(event/action[@name="client_app_name"]/value)[1]',
                         'NVARCHAR(256)')                             AS Aplicacion,
        event_data.value('(event/data[@name="error_number"]/value)[1]',
                         'INT')                                       AS CodigoError
    FROM (
        SELECT
            CAST(xdr.target_data AS XML).nodes('//RingBufferTarget/event') AS t(event_data)
        FROM sys.dm_xe_sessions             s
        JOIN sys.dm_xe_session_targets      xdr ON s.address = xdr.event_session_address
        WHERE s.name  = 'XE_HotelDB_Seguridad'
          AND xdr.target_name = 'ring_buffer'
    ) AS src
    ORDER BY FechaHora DESC;
END;
GO

PRINT '>> Sección 7 completada: Vistas y procedimientos de consulta XE creados.';
GO


/* =============================================================
   SECCIÓN 8 - VERIFICACIÓN FINAL
   Confirma que las sesiones XE existen y muestra su estado.
   ============================================================= */

-- Estado de las sesiones XE del hotel
SELECT
    s.name                                          AS Sesion,
    CASE 
        WHEN r.name IS NOT NULL THEN 'EN EJECUCIÓN'
        ELSE 'DETENIDA'
    END                                             AS Estado,
    s.startup_state                                 AS InicioAutomatico,
    s.max_dispatch_latency
FROM sys.server_event_sessions          s
LEFT JOIN sys.dm_xe_sessions            r ON s.name = r.name
WHERE s.name LIKE 'XE_HotelDB_%'
ORDER BY s.name;
GO

-- Objetos XE creados en HotelDB
SELECT
    s.name + '.' + o.name                          AS Procedimiento,
    o.type_desc,
    o.create_date,
    o.modify_date
FROM sys.objects  o
INNER JOIN sys.schemas s ON o.schema_id = s.schema_id
WHERE s.name = 'Auditoria'
  AND o.name LIKE '%XE%'
   OR (s.name = 'Auditoria' AND o.name LIKE 'usp_Consultar%')
ORDER BY o.name;
GO

PRINT '================================================================';
PRINT ' Extended Events de HotelDB instalados correctamente.';
PRINT ' Para iniciar todas las sesiones ejecuta:';
PRINT '   EXEC HotelDB.Auditoria.usp_IniciarSesionesXE;';
PRINT '================================================================';
GO