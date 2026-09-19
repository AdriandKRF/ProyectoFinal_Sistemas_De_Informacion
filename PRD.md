# PRD — Sistema DSS Taller Mecánico

## 1. Objetivo y Fronteras (Boundary Rules)

**Propósito:** Sistema web que digitaliza la operación diaria de un taller mecánico (clientes,
vehículos, órdenes de trabajo e inventario) y transforma esos datos en un tablero analítico (DSS)
que permite al dueño tomar decisiones sobre rentabilidad, productividad del personal y compras
de repuestos.

**Lo que DEBE hacer:**
- Registrar y dar seguimiento completo al ciclo de vida de una Orden de Trabajo (OT), desde su
  creación hasta su cierre, incluyendo el descuento automático de repuestos del inventario.
- Calcular y exponer en tiempo casi real indicadores de negocio (ingresos, OTs por estado,
  productividad por mecánico, repuestos más solicitados) en un dashboard exclusivo para roles
  administrativos.
- Mantener un historial de mantenimiento completo y consultable por placa de vehículo.

**Lo que NO debe hacer / tocar:**
- Ningún agente de IA o script automatizado debe ejecutar sentencias `DROP TABLE`, `TRUNCATE` o
  `DELETE` sin condición `WHERE` sobre el esquema de producción.
- El módulo CRUD no debe escribir directamente sobre las tablas o vistas analíticas del DSS
  (OLAP); toda esa capa se alimenta exclusivamente vía el proceso ETL definido en la Sección 4.
- Los roles "Recepcionista" y "Mecánico" no deben tener acceso de lectura a los montos de
  ingresos ni a los reportes de productividad individual de otros mecánicos.
- No se debe eliminar físicamente ningún registro de Orden de Trabajo ya facturada; solo se
  permite anulación lógica (soft delete) con trazabilidad de quién y cuándo la anuló.
- **Solo el rol Administrador puede crear o modificar cuentas de usuario y asignar roles; ningún
  otro rol ni agente de IA debe exponer o modificar la tabla `usuarios.rol`.**

## 2. Perfiles de Usuario

| Perfil | Rol(es) | Módulo que opera |
|---|---|---|
| Operativo | Recepcionista, Mecánico | CRUD (OLTP) |
| Estratégico | Administrador / Dueño | DSS (OLAP) |

## 3. Módulo 1: Requerimientos Transaccionales (CRUD / OLTP)

**Épicas:** Gestión de Clientes y Vehículos · Gestión de Órdenes de Trabajo · Gestión de
Inventario y Servicios

- **HU-01:** Como recepcionista, quiero registrar un nuevo cliente con sus datos básicos y
  vehículo (placa, marca, modelo), para asociar las órdenes de trabajo a un perfil único.
- **HU-02:** Como recepcionista, quiero crear una Orden de Trabajo asignando un vehículo, un
  mecánico y los servicios a realizar, para iniciar formalmente el proceso de reparación.
- **HU-03:** Como mecánico asignado, quiero cambiar el estado de la Orden de Trabajo (Pendiente,
  En Proceso, Finalizado), para informar en tiempo real el avance de la reparación.
- **HU-04b:** Como sistema, al finalizar una OT quiero descontar automáticamente del inventario
  los repuestos utilizados, para evitar descuadres de stock.
- **HU-07:** Como recepcionista, quiero consultar el historial completo de mantenimientos de un
  vehículo ingresando solo su placa, para brindar atención personalizada.

## 4. Módulo 2: Requerimientos Analíticos (DSS / OLAP)

**Integración (ETL):** Un proceso programado (job nocturno) o disparado por evento (al finalizar
una OT) extrae los datos de las tablas transaccionales (`ordenes_trabajo`, `inventario`,
`clientes`), los transforma (agregación por fecha, mecánico y categoría de repuesto) y los carga
en un esquema analítico de solo lectura (vistas materializadas) que alimenta el dashboard.

- **HU-05:** Como administrador, quiero visualizar un dashboard con ingresos del mes, OTs
  completadas y repuestos más vendidos, para tomar decisiones informadas sobre rentabilidad.
- **HU-08:** Como administrador, quiero generar un reporte de productividad por mecánico en un
  rango de fechas, para evaluar el rendimiento del personal.
- **HU-10:** Como administrador, quiero recibir una alerta visual cuando el margen de ingresos
  del mes actual sea inferior al del mes anterior, para reaccionar a tiempo ante caídas de
  rentabilidad.

## 5. Requerimientos No Funcionales

1. El 95% de las consultas al módulo CRUD deben responder en menos de **800 ms**, medido bajo una
   carga de hasta 20 usuarios concurrentes (ver RNF-4).
2. El sistema debe tener una disponibilidad mínima del **99%** en horario laboral (8:00–20:00,
   hora de Bolivia).
3. El desfase (latencia) entre un dato transaccional y su reflejo en el Dashboard DSS no debe
   superar los **15 minutos**.
4. El sistema debe soportar **20 usuarios concurrentes** sin degradar el tiempo de respuesta más
   allá de un 10% respecto a la línea base.

## 6. Puertas de Calidad (Quality Gates)

**DoR (Definition of Ready):**
- [ ] La historia tiene criterios de aceptación redactados y aprobados por el equipo.
- [ ] Las dependencias con otras historias están identificadas (ej. HU-02 depende de HU-01).
- [ ] El mockup de UI (si aplica) fue validado contra la guía de diseño UX.
- [ ] La historia tiene una estimación en story points.

**DoD (Definition of Done):**
- [ ] Código revisado y aprobado (Pull Request) por al menos un integrante del equipo.
- [ ] Pruebas unitarias del módulo pasan sin errores.
- [ ] Los criterios de aceptación fueron validados manualmente contra la historia original.
- [ ] No existen errores críticos visibles en consola o logs del servidor.
- [ ] Cambios desplegados y verificados en el ambiente de pruebas (staging).

## 7. Mapeo de Arquitectura

```
[ CLIENTE WEB (Browser) ]
          │
          ▼
[  CAPA OLTP (PostgreSQL)  ]
  clientes | vehiculos | ordenes_trabajo | inventario
          │
          ▼   (ETL: job nocturno / disparado por evento)
[  CAPA ETL (Extract-Transform-Load)  ]
  agregación por fecha, mecánico, categoría de repuesto
          │
          ▼
[  CAPA OLAP (Data Mart / Vistas materializadas)  ]
          │
          ▼
[  DASHBOARD DSS (solo lectura, rol Administrador)  ]
```
