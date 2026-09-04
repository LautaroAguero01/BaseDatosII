# Declaración de Uso de IA (DUIA) — TP2 Food Store

**Materia:** Base de Datos II — UTN  
**Alumno:** Lautaro Agustín Agüero — Fecha: 2026-09-04  
**Proyecto:** Food Store — Semana 2 (Concurrencia, Integridad, IA como motor primario)  
**Repo:** `https://github.com/LautaroAguero01/BaseDatosII.git` — rama `main`

> DUIA única para TP2 (3 secciones: Parte 1, Parte 2, Parte 3) — conforme PDF p4-5 y formato `TP01/DUIA.md`.

---

## Herramientas utilizadas (transversal)
- **OpenCode + Muse Spark (muse-spark-1.2-contributor-free)** — motor primario de generación y revisión (PDF Sección 3.1, modo Plan → Build, `/init` para `AGENTS.md`)
- **Kiro** — steering docs `.kiro/steering/tech.md` y `structure.md` (convenciones `BIGINT IDENTITY`, `ENUM`, `FK RESTRICT`, borrado lógico `activo`)
- **PostgreSQL 18.6** — `C:\Program Files\PostgreSQL\18\bin\psql.exe` + `pg_dump` — validación sintáctica y pruebas en `foodstore_copia`
- **psql 2 pestañas** — laboratorio de concurrencia Parte 2 (no DBeaver autocommit)

---

## Parte 1 — Integridad versionada (A+B ganador)

| Campo | Detalle |
|---|---|
| **Herramienta** | OpenCode + Muse Spark (muse-spark-1.2-contributor-free) |
| **Spec / prompt utilizado** | Spec A: `Impedir INSERT en pedido con fecha futura: ALTER TABLE pedido ADD CONSTRAINT chk_pedido_fecha_no_futura CHECK (fecha <= now() + interval '5 minutes') con tolerancia clock skew, tabla.columna exacta pedido.fecha` <br> Spec B: `Impedir INSERT/UPDATE en pedido_producto si producto.activo=FALSE o categoria.activo=FALSE (R7 baja lógica): TRIGGER BEFORE INSERT OR UPDATE que haga SELECT activo JOIN categoria y RAISE EXCEPTION si inactivo, tabla pedido_producto.producto_id → producto.activo → categoria.activo` |
| **Qué generó** | `TP02/restricciones/01_check_fecha.sql` (2 CHECK + COMMENT, idempotente con DROP IF EXISTS) y `TP02/restricciones/02_trigger_producto_activo.sql` (FUNCTION `fn_bloquear_producto_inactivo()` ~45 líneas + TRIGGER `trg_pedido_producto_activo` BEFORE INSERT OR UPDATE FOR EACH ROW, con DECLARE, SELECT INTO, IF NOT FOUND, RAISE con ERRCODE/HINT, RETURN NEW) |
| **Qué se aceptó** | 100% de la estructura: `CHECK (fecha <= now() + interval '5 minutes')` y `CHECK (fecha >= '2020-01-01')`, y `TRIGGER` con `RAISE EXCEPTION 'Producto % inactivo'` + validación de categoría. Mensajes y códigos `check_violation` se dejaron tal cual por ser defendibles. |
| **Qué se modificó o descartó, y por qué** | - En `01` se añadió `DROP CONSTRAINT IF EXISTS` y segundo `CHECK >= '2020-01-01'` para evitar fechas absurdas (no estaba en spec inicial, mejora defensa en profundidad). Se eligió `now() + interval '5 minutes'` en vez de `clock_timestamp()` porque `CHECK` requiere expresión estable y `now()` es inicio de tx (explicable en oral). <br> - En `02` se separó `SELECT producto` y `SELECT categoria` en dos queries (en vez de un JOIN) para mensajes de error específicos y trazabilidad oral. Se descartó alternativa `RETURN NULL` (silenciosa) por `RAISE EXCEPTION` (explícita). Se mantuvo `INSERT OR UPDATE` sin `WHEN` para validar siempre (costo mínimo). |
| **Verificación realizada** | Sobre `foodstore_copia` (protocolo `protocolo_seguridad.md:1-3`): `CREATE DATABASE foodstore_copia TEMPLATE foodstore` + `pg_dump -Fc` antes de DDL. <br> **A:** `BEGIN; \i 01_check_fecha.sql; INSERT INTO pedido(forma_pago,cliente_id) VALUES ('EFECTIVO',1) -- OK; INSERT INTO pedido(fecha,forma_pago,cliente_id) VALUES (now()+interval '1 day','EFECTIVO',1) -- ERROR 23514 check_violation; ROLLBACK;` <br> **B:** `BEGIN; \i 02_trigger...sql; INSERT válido con producto activo -- OK; UPDATE producto SET activo=FALSE; INSERT -- ERROR P0001 "Producto ... inactivo — baja lógica R7"; UPDATE categoria SET activo=FALSE; INSERT -- ERROR P0001 "Categoría ... inactiva"; ROLLBACK;` <br> `git diff` leído línea por línea antes de `COMMIT`; `SELECT conname FROM pg_constraint` y `SELECT tgname FROM pg_trigger` verificados. |
| **Estado** | Commiteado: `feat: Parte 1 restricciones A+B (CHECK fecha + TRIGGER baja lógica R7)` — defendible oral línea por línea |

> **Nota revisión humana:** Ningún script se ejecutó sin lectura previa (riesgo fundacional PDF p5). Responsable final: estudiante.

---

## Parte 2 — Laboratorio concurrencia (SAFE: No Repetible + Fantasma + FOR UPDATE)

| Campo | Detalle |
|---|---|
| **Herramienta** | OpenCode + Muse Spark (muse-spark-1.2) |
| **Spec / prompt utilizado** | `Sobre Food Store producto(id,precio,stock,categoria_id) en PostgreSQL MVCC, explica qué nivel de aislamiento evita [Non-Repeatable/Phantom/FOR UPDATE] y por qué: READ COMMITTED vs REPEATABLE READ vs SERIALIZABLE. Respuesta concisa citable para informe.` — prompt repetido por escenario, respuesta guardada tal cual en `TP02/informe_concurrencia.md` sección "Explicación de la IA" |
| **Qué generó** | Explicaciones por escenario + esqueleto de comandos `psql` 2 sesiones (A/B) con `BEGIN ISOLATION LEVEL`, `SELECT ... FOR UPDATE`, `pg_locks`, `pg_blocking_pids` — base para `TP02/informe_concurrencia.md` |
| **Qué se aceptó** | Secuencias de comandos y diagnósticos `SHOW transaction_isolation;`, `SELECT * FROM pg_locks`, `SELECT pg_blocking_pids(pid)` — validados en motor |
| **Qué se modificó o descartó, y por qué** | Se corrigieron IAs que afirmaban "Phantom solo SERIALIZABLE" — en PG `REPEATABLE READ` ya previene phantom read-only (snapshot por transacción, no por sentencia) — discrepancia documentada en informe como exige PDF p5 "la que vale es la que confirma el motor". Se descartó sugerencia "FOR UPDATE evita phantom con isolation level" — `FOR UPDATE` es lock pesimista ortogonal a aislamiento, documentado como tal. |
| **Verificación realizada** | Sobre `foodstore_copia` con 2 pestañas `psql` (`-d foodstore_copia`): <br> **NR:** `A: BEGIN ISOLATION LEVEL READ COMMITTED; SELECT precio FROM producto WHERE id=1;` → `B: UPDATE producto SET precio=1050 WHERE id=1; COMMIT;` → `A: SELECT precio ... -- RC:1050 anómalo / RR:1000 no anómalo` <br> **Fantasma:** `A: BEGIN ISOLATION LEVEL READ COMMITTED; SELECT COUNT(*) FROM producto WHERE categoria_id=1;` → `B: INSERT INTO producto(nombre,precio,stock,categoria_id) VALUES ('Fantasma TP2',999,10,1); COMMIT;` → `A: SELECT COUNT(*) ... -- RC:3 fantasma / RR:2 no fantasma` <br> **FOR UPDATE:** `A: BEGIN; SELECT * FROM producto WHERE id=1 FOR UPDATE;` → `B: SELECT * FROM producto WHERE id=1 FOR UPDATE; -- bloquea (waiting) hasta A:COMMIT` <br> Capturas de salida `psql` y `pg_locks` en informe. `SET TRANSACTION` siempre inmediatamente tras `BEGIN` (antes de primer SELECT). |
| **Estado** | Pendiente captura final en `TP02/informe_concurrencia.md` — ver archivo para tabla por escenario |

---

## Parte 3 — Lectura crítica

| Campo | Detalle |
|---|---|
| **Herramienta** | OpenCode + Muse Spark (muse-spark-1.2) |
| **Spec / prompt utilizado** | `Analiza 2 scripts del PDF p6 supuestamente para "dar de baja registros vencidos": Script1 UPDATE funcion SET activa=FALSE; Script2 DELETE FROM categoria WHERE id NOT IN (SELECT categoria_id FROM producto); Para cada uno: qué filas afectaría realmente, por qué no coincide con consigna, y versión corregida con WHERE / NOT EXISTS.` |
| **Qué generó** | Análisis de efecto real + correcciones: Script1 necesita `WHERE pelicula_id IN (...)` o `WHERE fecha_fin < CURRENT_DATE`; Script2 `NOT IN` con NULL → 0 filas, corregir a `NOT EXISTS (SELECT 1 FROM producto WHERE producto.categoria_id=categoria.id)` |
| **Qué se aceptó** | Identificación de efecto real y correcciones con `WHERE` y `NOT EXISTS` — base para `TP02/ejercicio_lectura_critica.md` |
| **Qué se modificó o descartó, y por qué** | Se añadió en Script2 mención explícita a Food Store: `categoria.activo` y `ON DELETE RESTRICT` — borrar categoría vacía pero inactiva vs activa, y que en Food Store `producto.categoria_id NOT NULL` hace que `NOT IN` sin NULL sí borraría, pero con genérico con NULL falla — matiz para 10/10. Se descartó `WHERE id NOT IN (SELECT categoria_id FROM producto WHERE categoria_id IS NOT NULL)` por preferir `NOT EXISTS` (NULL-safe y más eficiente con EXISTS). |
| **Verificación realizada** | `BEGIN; SELECT COUNT(*) FROM funcion; UPDATE funcion SET activa=FALSE; SELECT COUNT(*) WHERE activa=FALSE; ROLLBACK;` y `BEGIN; SELECT COUNT(*) FROM categoria WHERE id NOT IN (SELECT categoria_id FROM producto); EXPLAIN SELECT ... WHERE NOT EXISTS (...); ROLLBACK;` — efecto real inspeccionado sin commit |
| **Estado** | Pendiente `TP02/ejercicio_lectura_critica.md` |

---

*Criterio y responsabilidad (PDF p6): se delega escritura, nunca decisión. Todo lo generado se leyó y probó en copia dentro de transacción antes de darlo por bueno. Defensa oral preparada línea por línea.*
