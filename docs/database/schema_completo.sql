-- -----------------------------------------------------------------------------
-- 0. CREACIÓN DE BASE DE DATOS Y ESQUEMAS
-- -----------------------------------------------------------------------------
-- Ejecutar individualmente si no existen:
-- CREATE DATABASE dss_taller_db;
-- \c dss_taller_db;

CREATE SCHEMA IF NOT EXISTS oltp;
CREATE SCHEMA IF NOT EXISTS dw;

-- Extensiones útiles para UUID y funciones criptográficas
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- =============================================================================
-- 1. CAPA OLTP (MODELO TRANSACCIONAL - 3FN)
-- =============================================================================

-- Tabla: Clientes
CREATE TABLE oltp.clientes (
    id_cliente SERIAL PRIMARY KEY,
    nombre VARCHAR(100) NOT NULL,
    apellido VARCHAR(100) NOT NULL,
    telefono VARCHAR(20) NOT NULL,
    email VARCHAR(120) UNIQUE NOT NULL,
    documento_id VARCHAR(20) UNIQUE NOT NULL,
    direccion VARCHAR(200),
    fecha_registro TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Tabla: Usuarios (Mecánicos, Recepcionistas, Administradores)
-- Incluye soporte de seguridad: Hasheo con Salt (PBKDF2 / BCrypt via ASP.NET Core Identity)
CREATE TABLE oltp.usuarios (
    id_usuario SERIAL PRIMARY KEY,
    nombre_completo VARCHAR(150) NOT NULL,
    email VARCHAR(120) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL, -- Almacena hash + salt
    rol VARCHAR(30) NOT NULL CHECK (rol IN ('Administrador', 'Recepcionista', 'Mecanico')),
    especialidad VARCHAR(50) DEFAULT 'General', -- Ej: Electrónica, Frenos, Motor
    esta_disponible BOOLEAN DEFAULT TRUE,
    fecha_creacion TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);



-- Tabla: Vehículos
CREATE TABLE oltp.vehiculos (
    placa VARCHAR(15) PRIMARY KEY,
    marca VARCHAR(50) NOT NULL,
    modelo VARCHAR(50) NOT NULL,
    anio INT NOT NULL CHECK (anio >= 1900 AND anio <= EXTRACT(YEAR FROM CURRENT_DATE) + 1),
    id_cliente INT NOT NULL,
    CONSTRAINT fk_vehiculo_cliente FOREIGN KEY (id_cliente) 
        REFERENCES oltp.clientes (id_cliente) ON DELETE RESTRICT
);

-- Tabla: Repuestos (Inventario / Catálogo)
CREATE TABLE oltp.repuestos (
    id_repuesto SERIAL PRIMARY KEY,
    nombre VARCHAR(100) NOT NULL,
    descripcion TEXT,
    precio_unitario NUMERIC(10, 2) NOT NULL CHECK (precio_unitario >= 0),
    stock_actual INT NOT NULL CHECK (stock_actual >= 0),
    stock_minimo INT NOT NULL DEFAULT 5 CHECK (stock_minimo >= 0),
    categoria VARCHAR(50) DEFAULT 'General'
);

-- Tabla: Órdenes de Trabajo (OT)
CREATE TABLE oltp.ordenes_trabajo (
    id_ot SERIAL PRIMARY KEY,
    placa_vehiculo VARCHAR(15) NOT NULL,
    id_mecanico INT NOT NULL,
    fecha_ingreso TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    fecha_salida TIMESTAMP WITH TIME ZONE,
    estado VARCHAR(30) NOT NULL DEFAULT 'Pendiente' 
        CHECK (estado IN ('Pendiente', 'En Proceso', 'Listo para Retiro', 'Finalizado', 'Cancelado')),
    descripcion_falla TEXT NOT NULL,
    notas_tecnicas TEXT,
    costo_mano_obra NUMERIC(10, 2) DEFAULT 0.00 CHECK (costo_mano_obra >= 0),
    total_cobrar NUMERIC(10, 2) DEFAULT 0.00 CHECK (total_cobrar >= 0),
    notificacion_enviada BOOLEAN DEFAULT FALSE, -- Control de aviso por WhatsApp (HU-10)
    CONSTRAINT fk_ot_vehiculo FOREIGN KEY (placa_vehiculo) 
        REFERENCES oltp.vehiculos (placa) ON DELETE RESTRICT,
    CONSTRAINT fk_ot_mecanico FOREIGN KEY (id_mecanico) 
        REFERENCES oltp.usuarios (id_usuario) ON DELETE RESTRICT
);

-- Tabla Intermedia N:M: Detalle de Repuestos por Orden de Trabajo
CREATE TABLE oltp.detalle_orden_repuestos (
    id_detalle SERIAL PRIMARY KEY,
    id_ot INT NOT NULL,
    id_repuesto INT NOT NULL,
    cantidad INT NOT NULL CHECK (cantidad > 0),
    precio_subtotal NUMERIC(10, 2) NOT NULL CHECK (precio_subtotal >= 0),
    CONSTRAINT fk_detalle_ot FOREIGN KEY (id_ot) 
        REFERENCES oltp.ordenes_trabajo (id_ot) ON DELETE CASCADE,
    CONSTRAINT fk_detalle_repuesto FOREIGN KEY (id_repuesto) 
        REFERENCES oltp.repuestos (id_repuesto) ON DELETE RESTRICT
);

-- ÍNDICES OLTP (Optimización de búsquedas clave)
CREATE INDEX idx_vehiculos_cliente ON oltp.vehiculos(id_cliente);
CREATE INDEX idx_ot_estado ON oltp.ordenes_trabajo(estado);
CREATE INDEX idx_ot_mecanico ON oltp.ordenes_trabajo(id_mecanico);


-- =============================================================================
-- 2. CAPA DATA WAREHOUSE (MODELO MULTIDIMENSIONAL - ESQUEMA EN ESTRELLA)
-- =============================================================================

-- Dimensión: Tiempo
CREATE TABLE dw.dim_tiempo (
    id_tiempo INT PRIMARY KEY, -- Formato AAAAMMDD (Ej: 20260921)
    fecha DATE NOT NULL,
    anio INT NOT NULL,
    mes INT NOT NULL,
    nombre_mes VARCHAR(20) NOT NULL,
    trimestre INT NOT NULL,
    dia_semana VARCHAR(20) NOT NULL,
    es_fin_de_semana BOOLEAN NOT NULL
);

-- Dimensión: Cliente
CREATE TABLE dw.dim_cliente (
    id_cliente_key INT PRIMARY KEY, -- Mismo ID que OLTP
    nombre_completo VARCHAR(200) NOT NULL,
    telefono VARCHAR(20),
    email VARCHAR(120)
);

-- Dimensión: Vehículo
CREATE TABLE dw.dim_vehiculo (
    placa_key VARCHAR(15) PRIMARY KEY,
    marca VARCHAR(50) NOT NULL,
    modelo VARCHAR(50) NOT NULL,
    anio INT NOT NULL
);

-- Dimensión: Empleado / Mecánico
CREATE TABLE dw.dim_empleado (
    id_empleado_key INT PRIMARY KEY,
    nombre_completo VARCHAR(150) NOT NULL,
    rol VARCHAR(30) NOT NULL,
    especialidad VARCHAR(50) NOT NULL
);

-- Dimensión: Repuesto
CREATE TABLE dw.dim_repuesto (
    id_repuesto_key INT PRIMARY KEY,
    nombre VARCHAR(100) NOT NULL,
    categoria VARCHAR(50) NOT NULL
);

-- Tabla de Hechos: Fact_Reparaciones
CREATE TABLE dw.fact_reparaciones (
    id_fact SERIAL PRIMARY KEY,
    id_tiempo_ingreso INT NOT NULL,
    id_tiempo_salida INT,
    id_cliente_key INT NOT NULL,
    placa_key VARCHAR(15) NOT NULL,
    id_empleado_key INT NOT NULL,
    id_repuesto_key INT, -- Puede ser NULL si la reparación no usó repuestos
    
    -- Métricas Analíticas
    duracion_horas NUMERIC(8, 2) DEFAULT 0,
    monto_mano_obra NUMERIC(10, 2) DEFAULT 0.00,
    monto_repuestos NUMERIC(10, 2) DEFAULT 0.00,
    monto_total_facturado NUMERIC(10, 2) DEFAULT 0.00,
    cantidad_repuestos_usados INT DEFAULT 0,

    -- Foreign Keys del Esquema en Estrella
    CONSTRAINT fk_fact_tiempo_ingreso FOREIGN KEY (id_tiempo_ingreso) REFERENCES dw.dim_tiempo (id_tiempo),
    CONSTRAINT fk_fact_tiempo_salida FOREIGN KEY (id_tiempo_salida) REFERENCES dw.dim_tiempo (id_tiempo),
    CONSTRAINT fk_fact_cliente FOREIGN KEY (id_cliente_key) REFERENCES dw.dim_cliente (id_cliente_key),
    CONSTRAINT fk_fact_vehiculo FOREIGN KEY (placa_key) REFERENCES dw.dim_vehiculo (placa_key),
    CONSTRAINT fk_fact_empleado FOREIGN KEY (id_empleado_key) REFERENCES dw.dim_empleado (id_empleado_key),
    CONSTRAINT fk_fact_repuesto FOREIGN KEY (id_repuesto_key) REFERENCES dw.dim_repuesto (id_repuesto_key)
);


-- =============================================================================
-- 3. VISTAS ANALÍTICAS (CONSULTAS PARA LOS KPIs DEL DASHBOARD DSS)
-- =============================================================================

-- KPI 1: Tiempo Promedio de Reparación (MTTR) por Mecánico y Especialidad
CREATE OR REPLACE VIEW dw.v_kpi_mttr_por_mecanico AS
SELECT 
    e.nombre_completo AS mecanico,
    e.especialidad,
    COUNT(f.id_fact) AS total_ordenes_cerradas,
    ROUND(AVG(f.duracion_horas), 2) AS promedio_horas_por_reparacion
FROM dw.fact_reparaciones f
JOIN dw.dim_empleado e ON f.id_empleado_key = e.id_empleado_key
WHERE f.duracion_horas > 0
GROUP BY e.nombre_completo, e.especialidad;

-- KPI 2: Ingresos Mensuales por Facturación y Volumen de Trabajo
CREATE OR REPLACE VIEW dw.v_kpi_ingresos_mensuales AS
SELECT 
    t.anio,
    t.nombre_mes,
    COUNT(DISTINCT f.id_fact) AS total_ordenes,
    SUM(f.monto_total_facturado) AS facturacion_total,
    ROUND(AVG(f.monto_total_facturado), 2) AS ticket_promedio
FROM dw.fact_reparaciones f
JOIN dw.dim_tiempo t ON f.id_tiempo_ingreso = t.id_tiempo
GROUP BY t.anio, t.mes, t.nombre_mes
ORDER BY t.anio DESC, t.mes DESC;

-- KPI 3: Rotación de Repuestos e Impacto Financiero
CREATE OR REPLACE VIEW dw.v_kpi_rotacion_repuestos AS
SELECT 
    r.nombre AS repuesto,
    r.categoria,
    SUM(f.cantidad_repuestos_usados) AS unidades_vendidas,
    SUM(f.monto_repuestos) AS ingresos_generados
FROM dw.fact_reparaciones f
JOIN dw.dim_repuesto r ON f.id_repuesto_key = r.id_repuesto_key
GROUP BY r.nombre, r.categoria
ORDER BY unidades_vendidas DESC;