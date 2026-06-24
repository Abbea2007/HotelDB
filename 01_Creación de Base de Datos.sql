-----CREACIÒN DE BASE DE DATOS-----

CREATE DATABASE HotelDB;
GO

USE HotelDB;
GO


------ESQUEMAS---------

CREATE SCHEMA Seguridad;
GO

CREATE SCHEMA Hotel;
GO

CREATE SCHEMA Finanzas;
GO

CREATE SCHEMA Auditoria;
GO

--TABLAS--

--1. Tabla: Roles--
CREATE TABLE Seguridad.Roles (
    RolID INT IDENTITY(1,1),
    NombreRol VARCHAR(50) NOT NULL,

    CONSTRAINT PK_Roles PRIMARY KEY (RolID),
    CONSTRAINT UQ_Roles_NombreRol UNIQUE (NombreRol)
);
GO

--2. Tabla: Usuarios--

CREATE TABLE Seguridad.Usuarios (
    UsuarioID INT IDENTITY(1,1),
    NombreUsuario VARCHAR(50) NOT NULL,
    Clave VARCHAR(255) NOT NULL,
    RolID INT NOT NULL,
    Estado BIT NOT NULL DEFAULT 1,
    FechaCreacion DATETIME NOT NULL DEFAULT GETDATE(),

    CONSTRAINT PK_Usuarios PRIMARY KEY (UsuarioID),
    CONSTRAINT UQ_Usuarios_NombreUsuario UNIQUE (NombreUsuario),
    CONSTRAINT FK_Usuarios_Roles FOREIGN KEY (RolID)
        REFERENCES Seguridad.Roles(RolID)
);
GO

--3. Tabla: Empleados--
  CREATE TABLE Hotel.Empleados (
    EmpleadoID INT IDENTITY(1,1),
    Nombres VARCHAR(80) NOT NULL,
    Apellidos VARCHAR(80) NOT NULL,
    Cedula VARCHAR(20) NOT NULL,
    Telefono VARCHAR(20),
    Cargo VARCHAR(60) NOT NULL,
    Salario DECIMAL(10,2) NOT NULL,
    FechaContratacion DATE NOT NULL DEFAULT GETDATE(),
    Estado BIT NOT NULL DEFAULT 1,

    CONSTRAINT PK_Empleados PRIMARY KEY (EmpleadoID),
    CONSTRAINT UQ_Empleados_Cedula UNIQUE (Cedula),
    CONSTRAINT CK_Empleados_Salario CHECK (Salario > 0)
);
GO


--3. Tabla: Clientes--

CREATE TABLE Hotel.Clientes (
    ClienteID INT IDENTITY(1,1),
    Nombres VARCHAR(80) NOT NULL,
    Apellidos VARCHAR(80) NOT NULL,
    Documento VARCHAR(30) NOT NULL,
    Telefono VARCHAR(20),
    Correo VARCHAR(100),
    Nacionalidad VARCHAR(50),
    FechaRegistro DATETIME NOT NULL DEFAULT GETDATE(),
    Estado BIT NOT NULL DEFAULT 1,

    CONSTRAINT PK_Clientes PRIMARY KEY (ClienteID),
    CONSTRAINT UQ_Clientes_Documento UNIQUE (Documento),
    CONSTRAINT CK_Clientes_Correo CHECK (Correo LIKE '%@%' OR Correo IS NULL)
);
GO

--4. Tabla: Tipos de habitacion--

CREATE TABLE Hotel.TiposHabitacion (
    TipoHabitacionID INT IDENTITY(1,1),
    NombreTipo VARCHAR(50) NOT NULL,
    Descripcion VARCHAR(200),
    PrecioBase DECIMAL(10,2) NOT NULL,
    Capacidad INT NOT NULL,

    CONSTRAINT PK_TiposHabitacion PRIMARY KEY (TipoHabitacionID),
    CONSTRAINT UQ_TiposHabitacion_NombreTipo UNIQUE (NombreTipo),
    CONSTRAINT CK_TiposHabitacion_Precio CHECK (PrecioBase > 0),
    CONSTRAINT CK_TiposHabitacion_Capacidad CHECK (Capacidad > 0)
);
GO

--5. Tabla: Habitacion--

CREATE TABLE Hotel.Habitaciones (
    HabitacionID INT IDENTITY(1,1),
    NumeroHabitacion VARCHAR(10) NOT NULL,
    TipoHabitacionID INT NOT NULL,
    Piso INT NOT NULL,
    Estado VARCHAR(20) NOT NULL DEFAULT 'Disponible',

    CONSTRAINT PK_Habitaciones PRIMARY KEY (HabitacionID),
    CONSTRAINT UQ_Habitaciones_Numero UNIQUE (NumeroHabitacion),
    CONSTRAINT FK_Habitaciones_Tipos FOREIGN KEY (TipoHabitacionID)
        REFERENCES Hotel.TiposHabitacion(TipoHabitacionID),
    CONSTRAINT CK_Habitaciones_Piso CHECK (Piso > 0),
    CONSTRAINT CK_Habitaciones_Estado CHECK 
        (Estado IN ('Disponible', 'Ocupada', 'Mantenimiento', 'Limpieza'))
);
GO


--6. Tabla: Reservas--

CREATE TABLE Hotel.Reservas (
    ReservaID INT IDENTITY(1,1),
    ClienteID INT NOT NULL,
    HabitacionID INT NOT NULL,
    EmpleadoID INT NOT NULL,
    FechaReserva DATETIME NOT NULL DEFAULT GETDATE(),
    FechaEntrada DATE NOT NULL,
    FechaSalida DATE NOT NULL,
    Estado VARCHAR(20) NOT NULL DEFAULT 'Pendiente',

    CONSTRAINT PK_Reservas PRIMARY KEY (ReservaID),
    CONSTRAINT FK_Reservas_Clientes FOREIGN KEY (ClienteID)
        REFERENCES Hotel.Clientes(ClienteID),
    CONSTRAINT FK_Reservas_Habitaciones FOREIGN KEY (HabitacionID)
        REFERENCES Hotel.Habitaciones(HabitacionID),
    CONSTRAINT FK_Reservas_Empleados FOREIGN KEY (EmpleadoID)
        REFERENCES Hotel.Empleados(EmpleadoID),
    CONSTRAINT CK_Reservas_Fechas CHECK (FechaSalida > FechaEntrada),
    CONSTRAINT CK_Reservas_Estado CHECK 
        (Estado IN ('Pendiente', 'Confirmada', 'Cancelada', 'Finalizada'))
);
GO


--7. Tabla: Check In--

CREATE TABLE Hotel.CheckIn (
    CheckInID INT IDENTITY(1,1),
    ReservaID INT NOT NULL,
    FechaCheckIn DATETIME NOT NULL DEFAULT GETDATE(),
    Observaciones VARCHAR(250),

    CONSTRAINT PK_CheckIn PRIMARY KEY (CheckInID),
    CONSTRAINT UQ_CheckIn_Reserva UNIQUE (ReservaID),
    CONSTRAINT FK_CheckIn_Reservas FOREIGN KEY (ReservaID)
        REFERENCES Hotel.Reservas(ReservaID)
);
GO

--8. Tabla: Check Out--

CREATE TABLE Hotel.CheckOut (
    CheckOutID INT IDENTITY(1,1),
    ReservaID INT NOT NULL,
    FechaCheckOut DATETIME NOT NULL DEFAULT GETDATE(),
    Observaciones VARCHAR(250),

    CONSTRAINT PK_CheckOut PRIMARY KEY (CheckOutID),
    CONSTRAINT UQ_CheckOut_Reserva UNIQUE (ReservaID),
    CONSTRAINT FK_CheckOut_Reservas FOREIGN KEY (ReservaID)
        REFERENCES Hotel.Reservas(ReservaID)
);
GO

--9. Tabla: Servicios--

CREATE TABLE Hotel.Servicios (
    ServicioID INT IDENTITY(1,1),
    NombreServicio VARCHAR(80) NOT NULL,
    Descripcion VARCHAR(200),
    Precio DECIMAL(10,2) NOT NULL,
    Estado BIT NOT NULL DEFAULT 1,

    CONSTRAINT PK_Servicios PRIMARY KEY (ServicioID),
    CONSTRAINT UQ_Servicios_Nombre UNIQUE (NombreServicio),
    CONSTRAINT CK_Servicios_Precio CHECK (Precio > 0)
);
GO

--10. Tabla: Consumo Servicios--

CREATE TABLE Hotel.ConsumoServicios (
    ConsumoID INT IDENTITY(1,1),
    ReservaID INT NOT NULL,
    ServicioID INT NOT NULL,
    Cantidad INT NOT NULL,
    FechaConsumo DATETIME NOT NULL DEFAULT GETDATE(),

    CONSTRAINT PK_ConsumoServicios PRIMARY KEY (ConsumoID),
    CONSTRAINT FK_Consumo_Reservas FOREIGN KEY (ReservaID)
        REFERENCES Hotel.Reservas(ReservaID),
    CONSTRAINT FK_Consumo_Servicios FOREIGN KEY (ServicioID)
        REFERENCES Hotel.Servicios(ServicioID),
    CONSTRAINT CK_Consumo_Cantidad CHECK (Cantidad > 0)
);
GO


--11. Tabla: Pagos--

CREATE TABLE Finanzas.Pagos (
    PagoID INT IDENTITY(1,1),
    ReservaID INT NOT NULL,
    FechaPago DATETIME NOT NULL DEFAULT GETDATE(),
    Monto DECIMAL(10,2) NOT NULL,
    MetodoPago VARCHAR(30) NOT NULL,
    Estado VARCHAR(20) NOT NULL DEFAULT 'Pagado',

    CONSTRAINT PK_Pagos PRIMARY KEY (PagoID),
    CONSTRAINT FK_Pagos_Reservas FOREIGN KEY (ReservaID)
        REFERENCES Hotel.Reservas(ReservaID),
    CONSTRAINT CK_Pagos_Monto CHECK (Monto > 0),
    CONSTRAINT CK_Pagos_Metodo CHECK 
        (MetodoPago IN ('Efectivo', 'Tarjeta', 'Transferencia')),
    CONSTRAINT CK_Pagos_Estado CHECK 
        (Estado IN ('Pagado', 'Pendiente', 'Anulado'))
);
GO

--12. Tabla: Mantenimientos habitaciones--

CREATE TABLE Hotel.MantenimientoHabitaciones (
    MantenimientoID INT IDENTITY(1,1),
    HabitacionID INT NOT NULL,
    EmpleadoID INT NOT NULL,
    FechaInicio DATETIME NOT NULL DEFAULT GETDATE(),
    FechaFin DATETIME NULL,
    Descripcion VARCHAR(250) NOT NULL,
    Estado VARCHAR(20) NOT NULL DEFAULT 'En proceso',

    CONSTRAINT PK_Mantenimiento PRIMARY KEY (MantenimientoID),
    CONSTRAINT FK_Mantenimiento_Habitaciones FOREIGN KEY (HabitacionID)
        REFERENCES Hotel.Habitaciones(HabitacionID),
    CONSTRAINT FK_Mantenimiento_Empleados FOREIGN KEY (EmpleadoID)
        REFERENCES Hotel.Empleados(EmpleadoID),
    CONSTRAINT CK_Mantenimiento_Estado CHECK 
        (Estado IN ('En proceso', 'Finalizado', 'Cancelado'))
);
GO

--13. Tabla: Auditoria--

CREATE TABLE Auditoria.RegistroAuditoria (
    AuditoriaID INT IDENTITY(1,1),
    TablaAfectada VARCHAR(80) NOT NULL,
    Accion VARCHAR(20) NOT NULL,
    UsuarioSistema VARCHAR(100) NOT NULL DEFAULT SYSTEM_USER,
    FechaAccion DATETIME NOT NULL DEFAULT GETDATE(),
    Descripcion VARCHAR(300),

    CONSTRAINT PK_RegistroAuditoria PRIMARY KEY (AuditoriaID),
    CONSTRAINT CK_Auditoria_Accion CHECK 
        (Accion IN ('INSERT', 'UPDATE', 'DELETE'))
);
GO


--INSERCCION DE DATOS INICIALES--

INSERT INTO Seguridad.Roles (NombreRol)
VALUES 
('Administrador'),
('Recepcionista'),
('Auditor'),
('Mantenimiento'),
('Finanzas');
GO

INSERT INTO Seguridad.Usuarios (NombreUsuario, Clave, RolID)
VALUES
('admin', 'Admin123', 1),
('recepcion01', 'Recep123', 2),
('auditor01', 'Audit123', 3),
('mant01', 'Mant123', 4),
('finanzas01', 'Fin123', 5);
GO


INSERT INTO Hotel.Empleados 
(Nombres, Apellidos, Cedula, Telefono, Cargo, Salario)
VALUES
('Carlos', 'Ramírez', '001-010101-0001A', '8888-1111', 'Administrador', 25000),
('María', 'López', '001-020202-0002B', '8888-2222', 'Recepcionista', 15000),
('José', 'García', '001-030303-0003C', '8888-3333', 'Mantenimiento', 14000),
('Ana', 'Martínez', '001-040404-0004D', '8888-4444', 'Contadora', 18000);
GO



INSERT INTO Hotel.Clientes 
(Nombres, Apellidos, Documento, Telefono, Correo, Nacionalidad)
VALUES
('Luis', 'Pérez', 'PAS-1001', '7777-1111', 'luisperez@email.com', 'Nicaragüense'),
('Sofía', 'Hernández', 'PAS-1002', '7777-2222', 'sofia@email.com', 'Costarricense'),
('Miguel', 'Torres', 'PAS-1003', '7777-3333', 'miguel@email.com', 'Hondureño'),
('Laura', 'Castillo', 'PAS-1004', '7777-4444', 'laura@email.com', 'Salvadoreña');
GO

INSERT INTO Hotel.TiposHabitacion
(NombreTipo, Descripcion, PrecioBase, Capacidad)
VALUES
('Individual', 'Habitación para una persona', 45.00, 1),
('Doble', 'Habitación para dos personas', 70.00, 2),
('Suite', 'Habitación premium con sala privada', 120.00, 4),
('Familiar', 'Habitación amplia para familias', 100.00, 5);
GO


INSERT INTO Hotel.Habitaciones
(NumeroHabitacion, TipoHabitacionID, Piso, Estado)
VALUES
('101', 1, 1, 'Disponible'),
('102', 2, 1, 'Disponible'),
('201', 3, 2, 'Disponible'),
('202', 4, 2, 'Disponible'),
('301', 2, 3, 'Mantenimiento');
GO

INSERT INTO Hotel.Reservas
(ClienteID, HabitacionID, EmpleadoID, FechaEntrada, FechaSalida, Estado)
VALUES
(1, 1, 2, '2026-07-01', '2026-07-03', 'Confirmada'),
(2, 2, 2, '2026-07-05', '2026-07-08', 'Pendiente'),
(3, 3, 2, '2026-07-10', '2026-07-12', 'Confirmada');
GO

INSERT INTO Hotel.Servicios
(NombreServicio, Descripcion, Precio)
VALUES
('Desayuno', 'Servicio de desayuno buffet', 8.00),
('Lavandería', 'Lavado y planchado de ropa', 12.00),
('Transporte', 'Transporte desde o hacia aeropuerto', 25.00),
('Spa', 'Servicio de relajación y masaje', 35.00);
GO

INSERT INTO Hotel.ConsumoServicios
(ReservaID, ServicioID, Cantidad)
VALUES
(1, 1, 2),
(1, 2, 1),
(3, 4, 1);
GO

INSERT INTO Finanzas.Pagos
(ReservaID, Monto, MetodoPago, Estado)
VALUES
(1, 90.00, 'Tarjeta', 'Pagado'),
(2, 50.00, 'Efectivo', 'Pendiente'),
(3, 120.00, 'Transferencia', 'Pagado');
GO

INSERT INTO Hotel.MantenimientoHabitaciones
(HabitacionID, EmpleadoID, Descripcion, Estado)
VALUES
(5, 3, 'Reparación de aire acondicionado', 'En proceso');
GO
















