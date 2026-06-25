USE master;
GO

/* =============================================================
   SCRIPT: DATABASE MAIL - CONFIGURACIÓN Y NOTIFICACIONES
   BASE DE DATOS: HotelDB
   DESCRIPCIÓN: Configuración completa del servicio de correo
                de SQL Server para envío de alertas automáticas
                sobre backups, errores, jobs fallidos y eventos
                críticos del sistema hotelero.
   VERSIÓN: 1.0

   REQUISITOS PREVIOS:
   ─────────────────────────────────────────────────────────────
   1. Cuenta Gmail con verificación en dos pasos activada.
   2. Contraseña de aplicación generada en:
      --https://myaccount.google.com/apppasswords
      (no uses la contraseña normal de Gmail)
   3. Servicio SQL Server Agent en ejecución.
   4. Permisos de sysadmin para ejecutar este script.
   ============================================================= */


/* =============================================================
   SECCIÓN 1 - HABILITAR DATABASE MAIL EN EL SERVIDOR
   Database Mail está desactivado por defecto en SQL Server.
   Requiere habilitar dos opciones de configuración avanzada.
   ============================================================= */

-- Paso 1: exponer las opciones avanzadas de configuración
EXEC sp_configure 'show advanced options', 1;
RECONFIGURE WITH OVERRIDE;
GO

-- Paso 2: habilitar el subsistema de Database Mail
EXEC sp_configure 'Database Mail XPs', 1;
RECONFIGURE WITH OVERRIDE;
GO

-- Verificar que quedó habilitado (run_value debe ser 1)
EXEC sp_configure 'Database Mail XPs';
GO

PRINT '>> Sección 1 completada: Database Mail XPs habilitado en el servidor.';
GO


/* =============================================================
   SECCIÓN 2 - CREAR CUENTA DE CORREO
   La cuenta define el servidor SMTP, el remitente y las
   credenciales de autenticación.

   PARÁMETROS CLAVE:
   • @account_name   : nombre interno en SQL Server
   • @email_address  : dirección que aparece como remitente
   • @display_name   : nombre visible en el cliente de correo
   • @mailserver_name: servidor SMTP del proveedor
   • @port           : 587 para TLS (recomendado) / 465 para SSL
   • @enable_ssl     : 1 = cifrado activado (obligatorio en Gmail)
   • @username       : usuario de autenticación SMTP
   • @password       : contraseña de aplicación (no la de Gmail)
   ============================================================= */

USE msdb;
GO

-- Eliminar la cuenta si ya existe para poder recrearla limpiamente
IF EXISTS (
    SELECT 1 FROM msdb.dbo.sysmail_account 
    WHERE name = 'Cuenta_HotelDB'
)
    EXEC msdb.dbo.sysmail_delete_account_sp 
        @account_name = 'Cuenta_HotelDB';
GO

EXEC msdb.dbo.sysmail_add_account_sp
    @account_name       = 'Cuenta_HotelDB',
    @description        = 'Cuenta SMTP principal para alertas automáticas de HotelDB. Usa Gmail con TLS en puerto 587.',
    @email_address      = 'carlosabea91@gmail.com',     -- remitente visible
    @display_name       = 'HotelDB Alertas',            -- nombre en el correo
    @replyto_address    = 'carlosabea91@gmail.com',
    @mailserver_name    = 'smtp.gmail.com',
    @port               = 587,
    @enable_ssl         = 1,                            -- TLS obligatorio en Gmail
    @username           = 'carlosabea91@gmail.com',
    @password           = 'yxfbyikgfdosywqk';           -- contraseña de aplicación Gmail
GO

PRINT '>> Sección 2 completada: Cuenta de correo Cuenta_HotelDB creada.';
GO


/* =============================================================
   SECCIÓN 3 - CREAR PERFIL DE CORREO
   El perfil agrupa una o varias cuentas y es el que se
   referencia al enviar correos o configurar el Agente SQL.
   Un perfil puede tener cuentas de respaldo (failover).
   ============================================================= */

IF EXISTS (
    SELECT 1 FROM msdb.dbo.sysmail_profile 
    WHERE name = 'Perfil_HotelDB'
)
    EXEC msdb.dbo.sysmail_delete_profile_sp 
        @profile_name = 'Perfil_HotelDB';
GO

EXEC msdb.dbo.sysmail_add_profile_sp
    @profile_name   = 'Perfil_HotelDB',
    @description    = 'Perfil de correo principal para notificaciones automáticas de backups, errores, jobs fallidos y alertas operativas de HotelDB.';
GO

PRINT '>> Sección 3 completada: Perfil Perfil_HotelDB creado.';
GO


/* =============================================================
   SECCIÓN 4 - ASOCIAR CUENTA AL PERFIL
   @sequence_number define el orden de prioridad cuando hay
   varias cuentas: SQL Server intenta la cuenta 1 primero;
   si falla, usa la 2, y así sucesivamente (failover).
   ============================================================= */

EXEC msdb.dbo.sysmail_add_profileaccount_sp
    @profile_name       = 'Perfil_HotelDB',
    @account_name       = 'Cuenta_HotelDB',
    @sequence_number    = 1;    -- cuenta principal (prioridad 1)
GO

PRINT '>> Sección 4 completada: Cuenta asociada al perfil con prioridad 1.';
GO


/* =============================================================
   SECCIÓN 5 - HACER EL PERFIL PÚBLICO Y PREDETERMINADO
   @principal_name = 'public' → cualquier usuario de la BD
   puede usar este perfil para enviar correos.
   @is_default = 1 → se usa automáticamente si no se especifica
   otro perfil en sp_send_dbmail.
   ============================================================= */

EXEC msdb.dbo.sysmail_add_principalprofile_sp
    @profile_name       = 'Perfil_HotelDB',
    @principal_name     = 'public',
    @is_default         = 1;
GO

PRINT '>> Sección 5 completada: Perfil configurado como público y predeterminado.';
GO


/* =============================================================
   SECCIÓN 6 - CONFIGURAR EL AGENTE SQL PARA USAR EL PERFIL
   Vincula el perfil de Database Mail al Agente SQL Server
   para que los jobs puedan enviar notificaciones automáticas
   cuando fallen o completen tareas críticas.
   ============================================================= */

-- Habilitar el sistema de correo del Agente SQL
EXEC msdb.dbo.sp_set_sqlagent_properties
    @email_save_in_sent_folder  = 1;    -- guarda copia en Enviados
GO

-- Asociar el perfil al Agente SQL
EXEC master.dbo.xp_instance_regwrite
    N'HKEY_LOCAL_MACHINE',
    N'SOFTWARE\Microsoft\MSSQLServer\SQLServerAgent',
    N'DatabaseMailProfile',
    N'REG_SZ',
    N'Perfil_HotelDB';
GO

PRINT '>> Sección 6 completada: Agente SQL configurado con Perfil_HotelDB.';
GO


/* =============================================================
   SECCIÓN 7 - PROCEDIMIENTOS DE NOTIFICACIÓN PARA HOTELDB
   Encapsulan los correos más comunes del sistema hotelero,
   listos para ser llamados desde jobs, triggers o alertas.
   ============================================================= */

USE HotelDB;
GO


-- ── 7.1 Notificación genérica (base para los demás) ──────────
USE HotelDB;
GO

CREATE OR ALTER PROCEDURE Auditoria.usp_EnviarCorreo
    @Destinatario   VARCHAR(200),
    @Asunto         VARCHAR(255),
    @Cuerpo         NVARCHAR(MAX),
    @EsHTML         BIT = 0
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Formato VARCHAR(10);

    -- Resuelve el formato antes de llamar al sp
    IF @EsHTML = 1
        SET @Formato = 'HTML';
    ELSE
        SET @Formato = 'TEXT';

    BEGIN TRY
        EXEC msdb.dbo.sp_send_dbmail
            @profile_name   = 'Perfil_HotelDB',
            @recipients     = @Destinatario,
            @subject        = @Asunto,
            @body           = @Cuerpo,
            @body_format    = @Formato;

        INSERT INTO Auditoria.RegistroAuditoria
            (TablaAfectada, Accion, Descripcion)
        VALUES (
            'Database Mail',
            'INSERT',
            'Correo enviado a ' + @Destinatario
            + '. Asunto: ' + @Asunto
            + ' | Usuario: ' + SYSTEM_USER
        );
    END TRY
    BEGIN CATCH
        INSERT INTO Auditoria.RegistroAuditoria
            (TablaAfectada, Accion, Descripcion)
        VALUES (
            'Database Mail',
            'INSERT',
            'ERROR al enviar correo a ' + @Destinatario
            + '. Error: ' + ERROR_MESSAGE()
        );
        PRINT '>> ERROR al enviar correo: ' + ERROR_MESSAGE();
    END CATCH;
END;
GO


-- ── 7.2 Alerta de job fallido ─────────────────────────────────
CREATE OR ALTER PROCEDURE Auditoria.usp_AlertaJobFallido
    @NombreJob      VARCHAR(150),
    @Destinatario   VARCHAR(200)    = 'carlosabea91@gmail.com'
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Asunto VARCHAR(255);
    DECLARE @Cuerpo NVARCHAR(MAX);

    SET @Asunto = '⚠️ ALERTA HotelDB: Job Fallido - ' + @NombreJob;

    SET @Cuerpo = 
        '<h2 style="color:#c0392b;">⚠️ Job Fallido en HotelDB</h2>'
      + '<table border="1" cellpadding="6" cellspacing="0" '
      + 'style="border-collapse:collapse;font-family:Arial,sans-serif;">'
      + '<tr><td><b>Servidor</b></td><td>' + @@SERVERNAME + '</td></tr>'
      + '<tr><td><b>Base de datos</b></td><td>HotelDB</td></tr>'
      + '<tr><td><b>Job</b></td><td>' + @NombreJob + '</td></tr>'
      + '<tr><td><b>Fecha / Hora</b></td><td>' 
      +     CONVERT(VARCHAR, GETDATE(), 120) + '</td></tr>'
      + '<tr><td><b>Acción requerida</b></td><td>'
      +     'Revisar el historial del Agente SQL en msdb.dbo.sysjobhistory'
      + '</td></tr>'
      + '</table>'
      + '<p style="color:#7f8c8d;font-size:12px;">'
      + 'Mensaje automático generado por HotelDB - SQL Server Agent</p>';

    EXEC Auditoria.usp_EnviarCorreo
        @Destinatario   = @Destinatario,
        @Asunto         = @Asunto,
        @Cuerpo         = @Cuerpo,
        @EsHTML         = 1;
END;
GO


-- ── 7.3 Alerta de backup completado ──────────────────────────
CREATE OR ALTER PROCEDURE Auditoria.usp_AlertaBackup
    @TipoBackup     VARCHAR(20),    -- 'Completo' o 'Diferencial'
    @RutaArchivo    VARCHAR(500),
    @Destinatario   VARCHAR(200)    = 'carlosabea91@gmail.com'
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Asunto VARCHAR(255);
    DECLARE @Cuerpo NVARCHAR(MAX);

    SET @Asunto = '✅ HotelDB: Backup ' + @TipoBackup + ' completado - '
                + CONVERT(VARCHAR, GETDATE(), 103);

    SET @Cuerpo =
        '<h2 style="color:#27ae60;">✅ Backup ' + @TipoBackup + ' Exitoso</h2>'
      + '<table border="1" cellpadding="6" cellspacing="0" '
      + 'style="border-collapse:collapse;font-family:Arial,sans-serif;">'
      + '<tr><td><b>Servidor</b></td><td>' + @@SERVERNAME + '</td></tr>'
      + '<tr><td><b>Base de datos</b></td><td>HotelDB</td></tr>'
      + '<tr><td><b>Tipo de backup</b></td><td>' + @TipoBackup + '</td></tr>'
      + '<tr><td><b>Archivo generado</b></td><td>' + @RutaArchivo + '</td></tr>'
      + '<tr><td><b>Fecha / Hora</b></td><td>'
      +     CONVERT(VARCHAR, GETDATE(), 120) + '</td></tr>'
      + '</table>'
      + '<p style="color:#7f8c8d;font-size:12px;">'
      + 'Mensaje automático generado por HotelDB - SQL Server Agent</p>';

    EXEC Auditoria.usp_EnviarCorreo
        @Destinatario   = @Destinatario,
        @Asunto         = @Asunto,
        @Cuerpo         = @Cuerpo,
        @EsHTML         = 1;
END;
GO


-- ── 7.4 Alerta de error crítico en la base de datos ──────────
CREATE OR ALTER PROCEDURE Auditoria.usp_AlertaErrorCritico
    @TablaAfectada  VARCHAR(100),
    @MensajeError   VARCHAR(500),
    @Destinatario   VARCHAR(200)    = 'carlosabea91@gmail.com'
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Asunto VARCHAR(255);
    DECLARE @Cuerpo NVARCHAR(MAX);

    SET @Asunto = '🔴 ERROR CRÍTICO HotelDB: ' + @TablaAfectada
                + ' - ' + CONVERT(VARCHAR, GETDATE(), 103);

    SET @Cuerpo =
        '<h2 style="color:#c0392b;">🔴 Error Crítico Detectado</h2>'
      + '<table border="1" cellpadding="6" cellspacing="0" '
      + 'style="border-collapse:collapse;font-family:Arial,sans-serif;">'
      + '<tr><td><b>Servidor</b></td><td>' + @@SERVERNAME + '</td></tr>'
      + '<tr><td><b>Base de datos</b></td><td>HotelDB</td></tr>'
      + '<tr><td><b>Tabla / Objeto afectado</b></td><td>' + @TablaAfectada + '</td></tr>'
      + '<tr><td><b>Mensaje de error</b></td><td>' + @MensajeError + '</td></tr>'
      + '<tr><td><b>Fecha / Hora</b></td><td>'
      +     CONVERT(VARCHAR, GETDATE(), 120) + '</td></tr>'
      + '<tr><td><b>Acción requerida</b></td><td>'
      +     'Revisar Auditoria.RegistroAuditoria y Extended Events'
      + '</td></tr>'
      + '</table>'
      + '<p style="color:#7f8c8d;font-size:12px;">'
      + 'Mensaje automático generado por HotelDB - SQL Server Agent</p>';

    EXEC Auditoria.usp_EnviarCorreo
        @Destinatario   = @Destinatario,
        @Asunto         = @Asunto,
        @Cuerpo         = @Cuerpo,
        @EsHTML         = 1;
END;
GO



-- ── 7.5 Reporte semanal de estado operativo ───────────────────
CREATE OR ALTER PROCEDURE Auditoria.usp_ReporteEmailSemanal
    @Destinatario   VARCHAR(200)    = 'carlosabea91@gmail.com'
AS
BEGIN
    SET NOCOUNT ON;

    -- Contadores del período (últimos 7 días)
    DECLARE @TotalReservas      INT;
    DECLARE @ReservasConfirmadas INT;
    DECLARE @TotalPagos         DECIMAL(10,2);
    DECLARE @HabitacionesOcupadas INT;
    DECLARE @ErroresAuditoria   INT;
    DECLARE @Cuerpo             NVARCHAR(MAX);
    DECLARE @Asunto             VARCHAR(255);

    SELECT @TotalReservas = COUNT(*)
    FROM HotelDB.Hotel.Reservas
    WHERE FechaReserva >= DATEADD(DAY, -7, GETDATE());

    SELECT @ReservasConfirmadas = COUNT(*)
    FROM HotelDB.Hotel.Reservas
    WHERE Estado = 'Confirmada'
      AND FechaReserva >= DATEADD(DAY, -7, GETDATE());

    SELECT @TotalPagos = ISNULL(SUM(Monto), 0)
    FROM HotelDB.Finanzas.Pagos
    WHERE Estado = 'Pagado'
      AND FechaPago >= DATEADD(DAY, -7, GETDATE());

    SELECT @HabitacionesOcupadas = COUNT(*)
    FROM HotelDB.Hotel.Habitaciones
    WHERE Estado IN ('Ocupada', 'Mantenimiento');

    SELECT @ErroresAuditoria = COUNT(*)
    FROM HotelDB.Auditoria.RegistroAuditoria
    WHERE FechaAccion >= DATEADD(DAY, -7, GETDATE());

    SET @Asunto = '📊 HotelDB - Reporte Semanal: '
                + CONVERT(VARCHAR, DATEADD(DAY,-7,GETDATE()), 103)
                + ' al ' + CONVERT(VARCHAR, GETDATE(), 103);

    SET @Cuerpo =
        '<h2 style="color:#2980b9;">📊 Reporte Semanal - HotelDB</h2>'
      + '<p style="font-family:Arial,sans-serif;">Período: '
      +     CONVERT(VARCHAR, DATEADD(DAY,-7,GETDATE()), 103)
      +     ' al ' + CONVERT(VARCHAR, GETDATE(), 103) + '</p>'
      + '<table border="1" cellpadding="8" cellspacing="0" '
      + 'style="border-collapse:collapse;font-family:Arial,sans-serif;width:100%;">'
      + '<tr style="background:#2980b9;color:white;">'
      +     '<th>Indicador</th><th>Valor</th></tr>'
      + '<tr><td>Reservas creadas en la semana</td><td><b>'
      +     CAST(@TotalReservas AS VARCHAR) + '</b></td></tr>'
      + '<tr style="background:#ecf0f1;"><td>Reservas confirmadas</td><td><b>'
      +     CAST(@ReservasConfirmadas AS VARCHAR) + '</b></td></tr>'
      + '<tr><td>Total ingresos por pagos (USD)</td><td><b>$'
      +     CAST(@TotalPagos AS VARCHAR) + '</b></td></tr>'
      + '<tr style="background:#ecf0f1;"><td>Habitaciones fuera de servicio</td><td><b>'
      +     CAST(@HabitacionesOcupadas AS VARCHAR) + '</b></td></tr>'
      + '<tr><td>Eventos registrados en auditoría</td><td><b>'
      +     CAST(@ErroresAuditoria AS VARCHAR) + '</b></td></tr>'
      + '</table>'
      + '<p style="color:#7f8c8d;font-size:12px;font-family:Arial,sans-serif;">'
      + 'Generado automáticamente por HotelDB | Servidor: ' + @@SERVERNAME + '</p>';

    EXEC Auditoria.usp_EnviarCorreo
        @Destinatario   = @Destinatario,
        @Asunto         = @Asunto,
        @Cuerpo         = @Cuerpo,
        @EsHTML         = 1;
END;
GO

PRINT '>> Sección 7 completada: Procedimientos de notificación creados.';
GO


/* =============================================================
   SECCIÓN 8 - PRUEBAS DE ENVÍO
   Ejecuta las 3 pruebas principales para confirmar que
   Database Mail funciona correctamente antes de activar
   los jobs de producción.
   ============================================================= */

USE HotelDB;
GO

-- Prueba 1: correo básico de texto plano
EXEC msdb.dbo.sp_send_dbmail
    @profile_name   = 'Perfil_HotelDB',
    @recipients     = 'carlosabea91@gmail.com',
    @subject        = '✅ Prueba 1 - Database Mail HotelDB (texto plano)',
    @body           = 
'Hola,

Esta es la prueba de funcionamiento de Database Mail para HotelDB.

Datos del servidor:
- Servidor  : ' + @@SERVERNAME + '
- Base datos: HotelDB
- Fecha     : ' + CONVERT(VARCHAR, GETDATE(), 120) + '

Si recibes este correo, la configuración es correcta.

-- HotelDB Sistema de Alertas';
GO

-- Prueba 2: alerta de job fallido (formato HTML)
EXEC Auditoria.usp_AlertaJobFallido
    @NombreJob      = 'PRUEBA - HotelDB Backup Completo Semanal',
    @Destinatario   = 'carlosabea91@gmail.com';
GO

-- Prueba 3: reporte semanal con datos reales de la BD
EXEC Auditoria.usp_ReporteEmailSemanal
    @Destinatario   = 'carlosabea91@gmail.com';
GO

PRINT '>> Sección 8 completada: Correos de prueba enviados a la cola.';
GO


/* =============================================================
   SECCIÓN 9 - CONSULTAS DE VERIFICACIÓN Y MONITOREO
   Permiten auditar el estado de Database Mail, ver correos
   enviados, pendientes o con error.
   ============================================================= */

USE msdb;
GO

-- 9.1 Confirmar que el perfil y la cuenta existen correctamente
SELECT
    p.name                  AS Perfil,
    p.description           AS DescripcionPerfil,
    a.name                  AS Cuenta,
    a.email_address         AS EmailRemitente,
    a.mailserver_name       AS ServidorSMTP,
    a.port                  AS Puerto,
    a.enable_ssl            AS SSL_Activo,
    pa.sequence_number      AS Prioridad
FROM msdb.dbo.sysmail_profile           p
INNER JOIN msdb.dbo.sysmail_profileaccount pa ON p.profile_id  = pa.profile_id
INNER JOIN msdb.dbo.sysmail_account         a  ON pa.account_id = a.account_id
WHERE p.name = 'Perfil_HotelDB';
GO

-- 9.2 Cola de correos: estado de todos los envíos
SELECT
    m.mailitem_id,
    m.subject                               AS Asunto,
    m.recipients                            AS Destinatario,
    m.sent_date                             AS FechaEnvio,
    CASE m.sent_status
        WHEN 0 THEN 'No enviado'
        WHEN 1 THEN 'Enviado ✅'
        WHEN 3 THEN 'Reintentando'
        ELSE        'Error ❌'
    END                                     AS Estado,
    m.send_request_user                     AS UsuarioSolicitante
FROM msdb.dbo.sysmail_allitems  m
ORDER BY m.sent_date DESC;
GO

-- 9.3 Solo correos fallidos (para diagnóstico)
SELECT
    f.mailitem_id,
    f.subject                               AS Asunto,
    f.recipients                            AS Destinatario,
    f.sent_date                             AS IntentadoEn,
    l.description                           AS MotivoFallo
FROM msdb.dbo.sysmail_faileditems   f
LEFT JOIN msdb.dbo.sysmail_log      l ON f.mailitem_id = l.mailitem_id
ORDER BY f.sent_date DESC;
GO

-- 9.4 Log completo de eventos de Database Mail
SELECT TOP 50
    log_id,
    event_type                              AS TipoEvento,
    log_date                                AS Fecha,
    description                             AS Descripcion
FROM msdb.dbo.sysmail_log
ORDER BY log_date DESC;
GO

-- 9.5 Correos enviados en las últimas 24 horas
SELECT
    subject                                 AS Asunto,
    recipients                              AS Destinatario,
    sent_date                               AS FechaEnvio,
    CASE sent_status
        WHEN 1 THEN 'Enviado ✅'
        ELSE 'Pendiente / Error'
    END                                     AS Estado
FROM msdb.dbo.sysmail_sentitems
WHERE sent_date >= DATEADD(HOUR, -24, GETDATE())
ORDER BY sent_date DESC;
GO

PRINT '================================================================';
PRINT ' Database Mail de HotelDB configurado correctamente.';
PRINT '';
PRINT ' Procedimientos disponibles:';
PRINT '   EXEC HotelDB.Auditoria.usp_EnviarCorreo       (genérico)';
PRINT '   EXEC HotelDB.Auditoria.usp_AlertaJobFallido   (job fallido)';
PRINT '   EXEC HotelDB.Auditoria.usp_AlertaBackup       (backup ok)';
PRINT '   EXEC HotelDB.Auditoria.usp_AlertaErrorCritico (error grave)';
PRINT '   EXEC HotelDB.Auditoria.usp_ReporteEmailSemanal (reporte)';
PRINT '================================================================';
GO






