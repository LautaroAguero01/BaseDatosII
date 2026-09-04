-- =============================================================================
-- Food Store — schema.sql — TP1 Base de Datos I (UTN)
-- Semana 1: Del dominio al esquema — DDL PostgreSQL ejecutable
-- Concilia Partes 2 (ER→Relacional) y 3 (Normalización 3FN/BCNF)
-- Requisitos: PK, FK, UNIQUE, 3 CHECKs, NOT NULL, DEFAULT, 2 INDEX, ENUM
-- Orden de creación respeta dependencias FK — script idempotente
-- =============================================================================

-- Limpieza idempotente para re-ejecución sin errores
DROP TABLE IF EXISTS pedido_producto CASCADE;
DROP TABLE IF EXISTS pedido CASCADE;
DROP TABLE IF EXISTS producto CASCADE;
DROP TABLE IF EXISTS cliente CASCADE;
DROP TABLE IF EXISTS categoria CASCADE;
DROP TYPE IF EXISTS forma_pago_enum CASCADE;

-- Dominio cerrado: forma de pago (PDF p5 exige CREATE TYPE AS ENUM)
CREATE TYPE forma_pago_enum AS ENUM ('EFECTIVO', 'TARJETA', 'TRANSFERENCIA');

-- -------------------------------------------------------------------------
-- Tabla: categoria
-- R1: categoría puede tener 0..N productos (participación parcial)
-- R7: baja lógica con activo DEFAULT TRUE, conserva historial
-- -------------------------------------------------------------------------
CREATE TABLE categoria (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nombre VARCHAR(80) NOT NULL UNIQUE, -- UNIQUE: evita categorías duplicadas (ej Pizzas)
    activo BOOLEAN NOT NULL DEFAULT TRUE, -- R7: no DELETE físico
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE categoria IS 'Agrupaciones de productos (R1). Participación parcial: puede existir sin productos.';
COMMENT ON COLUMN categoria.nombre IS 'Nombre único de categoría';

-- -------------------------------------------------------------------------
-- Tabla: cliente
-- R6: email UNIQUE identifica unívocamente al cliente
-- R2: cliente puede tener 0..N pedidos (parcial)
-- -------------------------------------------------------------------------
CREATE TABLE cliente (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nombre VARCHAR(100) NOT NULL, -- compuesto por simplicidad, ver Parte 1 Q3
    email VARCHAR(255) NOT NULL UNIQUE, -- R6: clave candidata UNIQUE
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE cliente IS 'Clientes registrados (R2, R6). Email es clave candidata.';
COMMENT ON COLUMN cliente.email IS 'R6: UNIQUE, identifica unívocamente al cliente';

-- -------------------------------------------------------------------------
-- Tabla: producto
-- R1: todo producto pertenece exactamente a una categoría (categoria_id NOT NULL, participación total)
-- R5: precio y stock no negativos (CHECK)
-- R7: baja lógica activo
-- -------------------------------------------------------------------------
CREATE TABLE producto (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nombre VARCHAR(100) NOT NULL,
    precio NUMERIC(10,2) NOT NULL CHECK (precio >= 0), -- R5: precio no negativo, NUMERIC para dinero (no FLOAT)
    stock INTEGER NOT NULL CHECK (stock >= 0), -- R5: stock no negativo
    activo BOOLEAN NOT NULL DEFAULT TRUE, -- R7
    categoria_id BIGINT NOT NULL REFERENCES categoria(id) ON DELETE RESTRICT ON UPDATE CASCADE, -- R1 total, R7 RESTRICT: no borrar categoría con productos históricos
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE producto IS 'Productos a la venta (R1,R5,R7). FK categoria_id NOT NULL por participación total.';
COMMENT ON COLUMN producto.precio IS 'Precio lista actual. R5 CHECK >=0. Histórico se congela en pedido_producto.precio_unitario (R4).';
COMMENT ON COLUMN producto.categoria_id IS 'FK obligatoria a categoria. ON DELETE RESTRICT: baja lógica, no borrado físico.';

-- -------------------------------------------------------------------------
-- Tabla: pedido
-- R2: todo pedido pertenece exactamente a un cliente (cliente_id NOT NULL, total)
-- forma_pago ENUM cerrado
-- -------------------------------------------------------------------------
CREATE TABLE pedido (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    fecha TIMESTAMPTZ NOT NULL DEFAULT now(), -- fecha/hora del pedido, DEFAULT now() por PDF p5
    forma_pago forma_pago_enum NOT NULL, -- ENUM EFECTIVO/TARJETA/TRANSFERENCIA
    cliente_id BIGINT NOT NULL REFERENCES cliente(id) ON DELETE RESTRICT ON UPDATE CASCADE, -- R2 total, RESTRICT: conservar historial
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE pedido IS 'Cabecera de pedido (R2). Un pedido = un cliente, una fecha, una forma de pago.';
COMMENT ON COLUMN pedido.cliente_id IS 'FK obligatoria a cliente. ON DELETE RESTRICT: no eliminar cliente con pedidos.';
COMMENT ON COLUMN pedido.forma_pago IS 'Dominio cerrado vía ENUM.';

-- -------------------------------------------------------------------------
-- Tabla intermedia N:M: pedido_producto (línea de pedido)
-- R3: N:M entre pedido y producto
-- R4: cantidad y precio_unitario viven aquí, congelan histórico
-- Decisión PK compuesta (pedido_id, producto_id) — evita producto duplicado por pedido (PDF p4)
-- Ambas FK NOT NULL por ser PK (integridad de entidad)
-- -------------------------------------------------------------------------
CREATE TABLE pedido_producto (
    pedido_id BIGINT NOT NULL REFERENCES pedido(id) ON DELETE RESTRICT ON UPDATE CASCADE, -- R3/R4, RESTRICT: no borrar pedido con líneas
    producto_id BIGINT NOT NULL REFERENCES producto(id) ON DELETE RESTRICT ON UPDATE CASCADE, -- R3/R4, RESTRICT: no borrar producto con ventas históricas (R7 baja lógica)
    cantidad INTEGER NOT NULL CHECK (cantidad > 0), -- R4: >0, no nula
    precio_unitario NUMERIC(10,2) NOT NULL CHECK (precio_unitario >= 0), -- R4: congela precio histórico, CHECK >=0

    PRIMARY KEY (pedido_id, producto_id) -- PK compuesta fijada por consigna
    -- Alternativa descartada: id BIGSERIAL PK + UNIQUE(pedido_id, producto_id) — ver Parte 2
);

COMMENT ON TABLE pedido_producto IS 'Asociativa N:M pedido-producto (R3,R4). PK compuesta garantiza unicidad de producto por pedido.';
COMMENT ON COLUMN pedido_producto.cantidad IS 'R4: unidades pedidas. CHECK >0.';
COMMENT ON COLUMN pedido_producto.precio_unitario IS 'R4: precio congelado al facturar. No depende solo de producto (varía en tiempo), depende de (pedido,producto). CHECK >=0.';
COMMENT ON COLUMN pedido_producto.pedido_id IS 'FK a pedido. ON DELETE RESTRICT: preservar historial de facturación.';
COMMENT ON COLUMN pedido_producto.producto_id IS 'FK a producto. ON DELETE RESTRICT: R7 baja lógica, no borrado físico.';

-- =============================================================================
-- Índices justificados (PDF p5 exige al menos 2 con comentario)
-- =============================================================================

-- Índice 1: acelera la consulta más frecuente — "buscar todos los pedidos de un cliente"
-- Ej: SELECT * FROM pedido WHERE cliente_id = ? ORDER BY fecha DESC;
CREATE INDEX idx_pedido_cliente ON pedido(cliente_id);

-- Índice 2: acelera "listar productos vigentes de una categoría" (catálogo activo)
-- Ej: SELECT * FROM producto WHERE categoria_id = ? AND activo = TRUE ORDER BY nombre;
-- Índice parcial opcional pero se deja simple para portabilidad; comentario justifica uso
CREATE INDEX idx_producto_categoria ON producto(categoria_id);

-- Índice adicional opcional: acelerar join de líneas por pedido (ya cubierto por PK, pero se documenta)
-- La PK (pedido_id, producto_id) ya crea índice implícito para búsquedas por pedido.
-- Si se consulta mucho por producto: CREATE INDEX idx_pedido_producto_producto ON pedido_producto(producto_id); -- acelera "¿en qué pedidos se vendió X producto?"

-- =============================================================================
-- Verificación: script debe ejecutarse sin errores de principio a fin
-- Probar con: psql -U postgres -d foodstore -f schema.sql
-- =============================================================================
