# Steering — Tech Stack y Convenciones Food Store

## Stack
- Motor: PostgreSQL 18.6 (`C:\Program Files\PostgreSQL\18\bin\psql.exe`), DB `foodstore` + copia `foodstore_copia`
- Lenguaje DDL: PostgreSQL `BIGINT GENERATED ALWAYS AS IDENTITY`, `NUMERIC(10,2)`, `TIMESTAMPTZ`, `ENUM`
- Repo: Git `main` → `origin https://github.com/LautaroAguero01/BaseDatosII.git`, PowerShell 5.1, Windows 11

## Convenciones de nombres y tipos
- Tablas en singular: `categoria`, `producto`, `cliente`, `pedido`, `pedido_producto` (asociativa N:M con PK compuesta)
- PK: `BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY` (no SERIAL, no UUID)
- Dinero: `NUMERIC(10,2) CHECK >=0` (no FLOAT) — `producto.precio`, `pedido_producto.precio_unitario`
- Tiempo: `TIMESTAMPTZ NOT NULL DEFAULT now()` — `pedido.fecha`, `created_at`
- Dominio cerrado: `CREATE TYPE forma_pago_enum AS ENUM ('EFECTIVO','TARJETA','TRANSFERENCIA')`
- Borrado lógico: `activo BOOLEAN NOT NULL DEFAULT TRUE` en `categoria` y `producto`; FK `ON DELETE RESTRICT ON UPDATE CASCADE` (no CASCADE, preserva historial R7)
- Constraints: `UNIQUE(categoria.nombre)`, `UNIQUE(cliente.email)`, `CHECK(stock>=0)`, `CHECK(cantidad>0)`, `CHECK(precio>=0)`

## Patrones de integridad (TP2 Parte 1)
- CHECK declarativo para rangos: `CHECK (fecha <= now())`, `CHECK (fecha >= '2024-01-01')`
- TRIGGER para validación cruzada: `BEFORE INSERT OR UPDATE ON pedido_producto` que `SELECT activo FROM producto JOIN categoria` y `RAISE EXCEPTION` si inactivo
- UNIQUE compuesto: `UNIQUE(nombre, categoria_id)` si se necesita
- Inmutabilidad: `TRIGGER BEFORE UPDATE ON pedido_producto` si `OLD.precio_unitario IS DISTINCT FROM NEW.precio_unitario` → `RAISE`
- Índices: `idx_pedido_cliente`, `idx_producto_categoria`; PK compuesta ya indexa `pedido_producto`

## Workflow IA
- Spec exacta con `tabla.columna` antes de generar
- No aplicar sin `git diff` + `BEGIN; ...; ROLLBACK;` en copia
- Commits descriptivos: `feat: chk_pedido_fecha_no_futura garantiza rango temporal` no `fix`
