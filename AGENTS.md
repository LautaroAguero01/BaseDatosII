# AGENTS.md — BaseDatosII / Food Store

> Generado por `opencode /init` — describe el repo para agentes IA (OpenCode, Kiro, Muse Spark).
> Proyecto: Tecnicatura en Programación UTN — Base de Datos II — Food Store

## Resumen del repo
- **Esquema principal:** `TP01/schema.sql` — DDL PostgreSQL 15+ idempotente (DROP IF EXISTS + CREATE), 5 tablas, `forma_pago_enum`, PK/FK `ON DELETE RESTRICT`, `UNIQUE(email)`, 3 CHECK, 2 INDEX comentados.
- **Modelo:** `TP01/Desarrollo_Partes_1_2_3.pdf` + `TP01/TP1_FoodStore_ModeloER_Normalizacion_DDL.pdf` + `TP01/Diagrama.png` (dbdiagram.io)
- **DUIA:** `TP01/DUIA.md` (OpenCode + muse-spark-1.2 como motor primario), `TP02/DUIA.md` única para TP2
- **Entregables TP2:** `TP02/protocolo_seguridad.md`, `TP02/restricciones/*.sql`, `TP02/informe_concurrencia.md`, `TP02/ejercicio_lectura_critica.md`

## Estructura de directorios
```
BaseDatosII/
 ├─ TP01/schema.sql
 ├─ TP01/Desarrollo_Partes_1_2_3.pdf
 ├─ TP02/protocolo_seguridad.md # Parte 0 — 3 pasos adaptados
 ├─ TP02/restricciones/         # Parte 1 — scripts versionados
 ├─ TP02/informe_concurrencia.md # Parte 2 — 3 escenarios SAFE
 ├─ TP02/ejercicio_lectura_critica.md # Parte 3
 ├─ TP02/DUIA.md                # DUIA única (3 secciones)
 └─ TP02/backups/               # pg_dump (gitignored, TP02)
```

## Convenciones del esquema (Food Store)
- **Tablas:** `categoria(id, nombre UNIQUE, activo DEFAULT TRUE, created_at TIMESTAMPTZ DEFAULT now())`, `producto(id, nombre, precio NUMERIC(10,2) CHECK>=0, stock CHECK>=0, activo, categoria_id NOT NULL FK RESTRICT, created_at)`, `cliente(id, nombre, email UNIQUE, created_at)`, `pedido(id, fecha TIMESTAMPTZ DEFAULT now(), forma_pago forma_pago_enum, cliente_id NOT NULL FK RESTRICT, created_at)`, `pedido_producto(pedido_id, producto_id PK compuesta, cantidad CHECK>0, precio_unitario CHECK>=0)` — detalles en `TP01/schema.sql:1-130`
- **Tipos:** `BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY`, `NUMERIC(10,2)` para dinero (no FLOAT), `TIMESTAMPTZ`, `ENUM forma_pago_enum ('EFECTIVO','TARJETA','TRANSFERENCIA')`
- **Integridad existente:** `CHECK(precio>=0)`, `CHECK(stock>=0)`, `CHECK(cantidad>0)`, `UNIQUE(categoria.nombre)`, `UNIQUE(cliente.email)`, `FK NOT NULL` por participación total R1/R2, `PK(pedido_id,producto_id)` evita duplicado por pedido
- **Agujeros a cubrir (TP2 Parte 1):** `pedido.fecha` sin CHECK futuro, `producto.activo/categoria.activo` sin validación en `pedido_producto`, `stock` sin control `cantidad <= stock`, `producto.nombre` no UNIQUE por categoría, `precio_unitario` mutable
- **Reglas TP2 elegidas (A+B ganador):** A `CHECK(fecha <= now())`, B `TRIGGER BEFORE INSERT ON pedido_producto bloquea producto/categoría inactiva`
- **Índices:** `idx_pedido_cliente(pedido.cliente_id)`, `idx_producto_categoria(producto.categoria_id)` — PK compuesta ya indexa `pedido_producto(pedido_id,producto_id)`

## Flujo de trabajo con IA (cátedra p3)
1. **Spec primero:** 1-2 frases con tabla.columna exacta antes de pedir a IA
2. **OpenCode modo Plan:** `opencode` → `TAB` Plan (describe sin tocar archivos) → revisar plan → `TAB` Build recién entonces aplica
3. **Diff obligatorio:** `git diff` línea por línea antes de aplicar sobre BD. Si una línea no se entiende, no se aplica
4. **Kiro:** steering docs en `.kiro/steering/` con convenciones de nombres, ENUM, borrado lógico `activo`

## Protocolo de seguridad (copia, transacción, respaldo) — ver `TP02/protocolo_seguridad.md`
- **Copia:** siempre sobre `foodstore_copia` (`CREATE DATABASE ... TEMPLATE`), nunca sobre `foodstore` real
- **Transacción:** todo `ALTER/INSERT/UPDATE/DELETE` primero en `BEGIN; ...; ROLLBACK;` para inspeccionar, luego `BEGIN; ...; COMMIT;`
- **Respaldo:** `pg_dump -Fc` antes de DDL estructural
- **Entorno:** Windows 11 + PostgreSQL 18 (`C:\Program Files\PostgreSQL\18\bin\psql.exe`), `psql` 2 pestañas para Parte 2, autocommit OFF

## Comandos frecuentes
```powershell
# PostgreSQL (Windows — usar ruta completa si no está en PATH)
& "C:\Program Files\PostgreSQL\18\bin\psql.exe" -U postgres -h localhost -d foodstore -f TP01/schema.sql
& "C:\Program Files\PostgreSQL\18\bin\psql.exe" -U postgres -h localhost -c "SELECT * FROM producto;"

# Git
git status; git diff; git diff --cached
git log --oneline -10
git add TP02/protocolo_seguridad.md TP02/restricciones/*.sql
git commit -m "feat: ..."

# Backups (dentro de TP02 para orden)
& "C:\Program Files\PostgreSQL\18\bin\pg_dump.exe" -U postgres -h localhost -Fc foodstore -f TP02/backups/foodstore_2026-09-04.dump
```

## Reglas para agentes
- Delegar escritura, nunca decisión: todo lo generado se lee y se prueba en copia dentro de transacción
- No ejecutar `DROP DATABASE`/`DROP TABLE` sin `BEGIN;` + `pg_dump` previo
- No asumir `psql` en PATH en Windows — usar ruta completa o verificar con `Get-Command`
- Ignorar `Guia_Referencia_SQL.md` (no es entregable TP2)
- Mensajes commit descriptivos: qué regla de negocio se garantiza, no solo "agrego constraint"
- Cada script committeado debe ser defendible oralmente línea por línea
