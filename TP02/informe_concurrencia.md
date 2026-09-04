# Informe de Concurrencia — Food Store (TP2 Parte 2)

> **Laboratorio con 2 sesiones concurrentes sobre esquema propio** — PDF p4-5.
> **Motor:** PostgreSQL 18.6 MVCC — `psql` 2 pestañas sobre `foodstore_copia` (protocolo `protocolo_seguridad.md`).
> **Esquema:** `TP01/schema.sql` — tabla elegida `producto(id, precio, stock, categoria_id)` y `pedido` para phantom.
> **Estrategia SAFE:** Lectura No Repetible + Lectura Fantasma + Espera `FOR UPDATE` (riesgo <15%, sin deadlock).

---

## Preparación común (una vez, sobre `foodstore_copia`)

```sql
-- Conectar a foodstore_copia (2 pestañas psql: Sesión A y Sesión B)
-- Pestaña A: & "C:\Program Files\PostgreSQL\18\bin\psql.exe" -U postgres -h localhost -d foodstore_copia
-- Pestaña B: idem en otra ventana

-- Verificar aislamiento por defecto
SHOW transaction_isolation; -- debe ser read committed

-- Datos semilla mínimos (si foodstore estaba vacío)
INSERT INTO categoria (nombre) VALUES ('Pizzas'), ('Bebidas') ON CONFLICT (nombre) DO NOTHING;
INSERT INTO producto (nombre, precio, stock, categoria_id) VALUES
  ('Muzzarella', 1000.00, 20, (SELECT id FROM categoria WHERE nombre='Pizzas')),
  ('Coca 1.5L', 800.00, 30, (SELECT id FROM categoria WHERE nombre='Bebidas')),
  ('Napolitana', 1500.00, 15, (SELECT id FROM categoria WHERE nombre='Pizzas'))
ON CONFLICT DO NOTHING;

INSERT INTO cliente (nombre, email) VALUES ('Ana Gómez', 'ana@test.com'), ('Luis Paz', 'luis@test.com') ON CONFLICT (email) DO NOTHING;
INSERT INTO pedido (forma_pago, cliente_id) VALUES ('EFECTIVO', (SELECT id FROM cliente WHERE email='ana@test.com')) ON CONFLICT DO NOTHING;

-- Verificar ids (anotar para laboratorio)
SELECT id, nombre, precio, stock, categoria_id, activo FROM producto ORDER BY id; -- ids 1,2,3
SELECT id, nombre FROM categoria ORDER BY id; -- id 1 Pizzas, 2 Bebidas
SELECT id, nombre, email FROM cliente ORDER BY id;
SELECT id, forma_pago, cliente_id, fecha FROM pedido ORDER BY id;
```

> **IMPORTANTE `psql`:** Cada pestaña debe mostrar `foodstore_copia=#` y tras `BEGIN;` pasa a `foodstore_copia=*#` (tx abierta). `SET TRANSACTION ISOLATION LEVEL` debe ir **inmediatamente después de `BEGIN`**, antes de cualquier `SELECT`.

---

## Escenario 1 — Lectura No Repetible

| Campo | Contenido |
|---|---|
| **Escenario** | Lectura No Repetible (Non-Repeatable Read) — misma fila leída dos veces en misma tx da valores distintos porque otra tx la modificó y commiteó |
| **Tabla/fila Food Store** | `producto.precio` `id=1` (Muzzarella) — mutable, historia `1000 → 1050` del PDF p4 de Parte 3, `NUMERIC CHECK>=0` |
| **Cómo se reprodujo** | Ver comandos abajo (Sesión A / Sesión B en orden numerado, con `READ COMMITTED`) |
| **Qué se observó** | En `READ COMMITTED`: 1ra `SELECT` → `1000.00`, 2da `SELECT` tras `COMMIT` de B → `1050.00` **anomalía visible**. En `REPEATABLE READ`: ambas `SELECT` → `1000.00` (snapshot congelado), no hay anomalía |
| **Explicación de la IA** | *Copiada tal cual de OpenCode + muse-spark-1.2 (prompt: "Sobre Food Store producto(id,precio) en PostgreSQL MVCC, explica qué nivel evita Non-Repeatable y por qué: READ COMMITTED vs REPEATABLE READ vs SERIALIZABLE"):* <br> > "La lectura no repetible se evita con `REPEATABLE READ` (o `SERIALIZABLE`) porque congela el snapshot al inicio de la transacción. En `READ COMMITTED` cada sentencia ve el snapshot al inicio de la sentencia, por eso la segunda SELECT ve el COMMIT de la concurrente. En PG `REPEATABLE READ` usa Snapshot Isolation (xmin/xmax), no locks." |
| **Verificación en el motor** | Se repitió **idéntico** cambiando solo `SET TRANSACTION ISOLATION LEVEL` a `REPEATABLE READ` — la 2da lectura mantuvo `1000.00`. Confirma que IA acertó. También se probó `SHOW transaction_isolation;` antes de cada `SELECT` para trazar. |
| **Conclusión** | IA **acertó**. Nivel que resuelve: `REPEATABLE READ` (o `SERIALIZABLE`). Mecanismo: snapshot por transacción vs por sentencia (MVCC). `READ COMMITTED` permite la anomalía por diseño ANSI. |

### Comandos exactos — No Repetible (ejecutar en orden)

```sql
-- RESET previo (cualquier sesión)
UPDATE producto SET precio = 1000.00 WHERE id = 1; COMMIT;
SELECT id, nombre, precio FROM producto WHERE id = 1; -- 1000.00

-- --- PRUEBA 1: READ COMMITTED (debe mostrar anomalía) ---
-- Sesión A (izquierda)
BEGIN;
SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
SHOW transaction_isolation; -- read committed
SELECT precio FROM producto WHERE id = 1; -- 1ra lectura → 1000.00 (anotar)
-- (pausa, dejar A abierta)

-- Sesión B (derecha) — mientras A está pausada
BEGIN;
SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
UPDATE producto SET precio = 1050.00 WHERE id = 1; -- modifica misma fila
COMMIT; -- hace visible para nuevas sentencias

-- Sesión A (vuelve)
SELECT precio FROM producto WHERE id = 1; -- 2da lectura → 1050.00 ¡ANOMALÍA!
COMMIT;

-- Restaurar para siguiente prueba
UPDATE producto SET precio = 1000.00 WHERE id = 1; COMMIT;

-- --- PRUEBA 2: REPEATABLE READ (debe NO mostrar anomalía) ---
-- Sesión A
BEGIN ISOLATION LEVEL REPEATABLE READ;
SELECT precio FROM producto WHERE id = 1; -- 1ra lectura → 1000.00
-- (pausa)

-- Sesión B (igual que antes)
BEGIN; UPDATE producto SET precio = 1050.00 WHERE id = 1; COMMIT;

-- Sesión A
SELECT precio FROM producto WHERE id = 1; -- 2da lectura → 1000.00 (snapshot congelado) ¡NO ANOMALÍA!
COMMIT;
SELECT precio FROM producto WHERE id = 1; -- fuera de tx → 1050.00 (ahora sí ve)
-- Restaurar
UPDATE producto SET precio = 1000.00 WHERE id = 1; COMMIT;
```

**Captura `psql` real (motor PostgreSQL 18.6, `foodstore_copia`, clave 1234, 2026-09-04):**

*Prueba READ COMMITTED (con anomalía):*
```
=== RESET precio 1000 ===
UPDATE 1
 id | precio  
----+---------
  1 | 1000.00

=== OUTPUT A RC (Sesión A — BEGIN ISOLATION LEVEL READ COMMITTED) ===
 transaction_isolation | read committed
 BEGIN
 | A1_RC_START |  1 | Muzzarella | 1000.00 |
 SELECT pg_sleep(3) -> (waiting)
 | A2_RC_AFTER_B_COMMIT | 1 | Muzzarella | 1050.00 |  <-- ANOMALÍA: cambió
 COMMIT
 | A3_RC_FINAL | 1 | Muzzarella | 1050.00 |

=== OUTPUT B RC (Sesión B — UPDATE concurrente) ===
 BEGIN
 | 1 | Muzzarella | 1050.00 |  UPDATE 1
 COMMIT  B_DONE_RC
```

*Prueba REPEATABLE READ (sin anomalía, snapshot congelado):*
```
=== OUTPUT A RR (BEGIN ISOLATION LEVEL REPEATABLE READ) ===
 | A1_RR_START | 1 | Muzzarella | 1000.00 |
 SELECT pg_sleep(3)
 | A2_RR_AFTER_B_COMMIT | 1 | Muzzarella | 1000.00 |  <-- NO anomalía (snapshot)
 COMMIT
 | A3_RR_FINAL | 1 | Muzzarella | 1050.00 | (fuera de tx ya ve 1050)

=== OUTPUT B RR ===
 BEGIN | 1 | Muzzarella | 1050.00 | UPDATE 1 COMMIT
```

> Verificación: RC muestra `1000 → 1050` (misma tx, distinta lectura). RR mantiene `1000 → 1000` hasta `COMMIT`. IA acertó.

**Diagnóstico (capturado en 3ra pestaña):** `pg_stat_activity` durante RR/PH mostró `wait_event_type=Lock` solo en escenario `FOR UPDATE` (no en NR, que no bloquea — solo snapshot).

---

## Escenario 2 — Lectura Fantasma (Phantom Read)

| Campo | Contenido |
|---|---|
| **Escenario** | Lectura Fantasma — `COUNT(*)`/`SUM` repetido en misma tx cambia porque otra tx insertó fila nueva que cumple `WHERE` y commiteó. No es misma fila modificada (NR), es fila nueva. |
| **Tabla/fila Food Store** | `producto` por `categoria_id=1` (Pizzas) — `SELECT COUNT(*) FROM producto WHERE categoria_id=1 AND activo=TRUE`. Alternativa válida: `pedido` por `cliente_id` (`COUNT(*) FROM pedido WHERE cliente_id=1`). Elegida `producto` por ser más visual y no exigir `ENUM` ni FK cliente. |
| **Cómo se reprodujo** | Ver comandos (A `COUNT` → B `INSERT Fantasma` + `COMMIT` → A `COUNT` de nuevo). Misma prueba en `READ COMMITTED` y `REPEATABLE READ`. |
| **Qué se observó** | `READ COMMITTED`: 1er `COUNT` → `2`, 2do `COUNT` tras `COMMIT` de B → `3` **fantasma visible**. `REPEATABLE READ` (PG): 1er y 2do `COUNT` → `2` **no fantasma** (snapshot congelado). Fuera de tx `COUNT` → `3`. |
| **Explicación de la IA** | *Copiada tal cual (mismo prompt, cambiando "Phantom"):* <br> > "El phantom se evita solo con `SERIALIZABLE`, que hace predicate locking. `REPEATABLE READ` permite phantoms según ANSI." |
| **Verificación en el motor** | **Discrepancia documentada (PDF p5 "la que vale es la que confirma el motor"):** IA afirmó solo `SERIALIZABLE`, pero en **PostgreSQL** `REPEATABLE READ` ya previene phantom read-only (MVCC snapshot por transacción, no por sentencia). Se verificó repitiendo con `REPEATABLE READ` → `2→2` (no fantasma) y con `SERIALIZABLE` → también `2→2`. La discrepancia se deja constancia: IA genérica ANSI vs PG real. |
| **Conclusión** | IA **parcialmente incorrecta para PG**. En teoría ANSI: `SERIALIZABLE` es el único que garantiza. En PostgreSQL real: `REPEATABLE READ` ya alcanza para lecturas (MVCC), `SERIALIZABLE` añade SSI para escrituras concurrentes. Evidencia del motor corrige a la IA. |

### Comandos exactos — Fantasma (usar `categoria_id=1`)

```sql
-- Preparar: verificar COUNT inicial
SELECT COUNT(*) FROM producto WHERE categoria_id = 1; -- ej 2

-- --- PRUEBA 1: READ COMMITTED (debe mostrar fantasma) ---
-- Sesión A
BEGIN ISOLATION LEVEL READ COMMITTED;
SELECT COUNT(*) FROM producto WHERE categoria_id = 1; -- 1er COUNT → 2
-- (pausa)

-- Sesión B
BEGIN;
INSERT INTO producto (nombre, precio, stock, categoria_id) VALUES ('Fantasma Pizza TP2', 999.00, 10, 1);
COMMIT; -- nueva fila visible para nuevas sentencias

-- Sesión A
SELECT COUNT(*) FROM producto WHERE categoria_id = 1; -- 2do COUNT → 3 ¡FANTASMA!
SELECT * FROM producto WHERE categoria_id = 1 ORDER BY id; -- se ve la fila nueva
COMMIT;

-- Limpieza para repetir (importante: DELETE + COMMIT)
DELETE FROM producto WHERE nombre = 'Fantasma Pizza TP2';
COMMIT;
SELECT COUNT(*) FROM producto WHERE categoria_id = 1; -- vuelve a 2

-- --- PRUEBA 2: REPEATABLE READ (debe NO mostrar fantasma) ---
-- Sesión A
BEGIN ISOLATION LEVEL REPEATABLE READ;
SELECT COUNT(*) FROM producto WHERE categoria_id = 1; -- 1er COUNT → 2
-- (pausa)

-- Sesión B (igual INSERT + COMMIT)
BEGIN; INSERT INTO producto (nombre, precio, stock, categoria_id) VALUES ('Fantasma Pizza TP2', 999.00, 10, 1); COMMIT;

-- Sesión A
SELECT COUNT(*) FROM producto WHERE categoria_id = 1; -- 2do COUNT → 2 (no ve fantasma) ¡EVITADO!
SELECT * FROM producto WHERE categoria_id = 1 ORDER BY id; -- tampoco ve la fila nueva
COMMIT;
SELECT COUNT(*) FROM producto WHERE categoria_id = 1; -- fuera de tx → 3 (ahora sí)
-- Limpieza
DELETE FROM producto WHERE nombre = 'Fantasma Pizza TP2'; COMMIT;

-- --- PRUEBA 3 (opcional): SERIALIZABLE — también 2→2 ---
BEGIN ISOLATION LEVEL SERIALIZABLE; SELECT COUNT(*) FROM producto WHERE categoria_id=1; -- 2
-- B: INSERT ... COMMIT;
-- A: SELECT COUNT(*) ... -- 2
```

**Captura `psql` real (motor, 2026-09-04):**

*Phantom READ COMMITTED (fantasma visible):*
```
=== A PH RC (BEGIN ISOLATION LEVEL READ COMMITTED) ===
 transaction_isolation | read committed
 | A1_PH_RC_START |   2 |
 pg_sleep(3)
 | A2_PH_RC_AFTER |   3 |  <-- FANTASMA: 2→3
 | id |       nombre       | precio  | 6 | Fantasma Pizza TP2 | 999.00 |
 COMMIT | A3_PH_RC_FINAL | 3 |

=== B PH RC ===
 BEGIN | 6 | Fantasma Pizza TP2 | INSERT 0 1 COMMIT
```

*Phantom REPEATABLE READ (no fantasma, snapshot):*
```
=== A PH RR (BEGIN ISOLATION LEVEL REPEATABLE READ) ===
 transaction_isolation | repeatable read
 | A1_PH_RR_START |   2 |
 pg_sleep(3)
 | A2_PH_RR_AFTER |   2 |  <-- NO fantasma (snapshot)
 | id | nombre      | 1 Muzzarella | 3 Napolitana | (sin fantasma)
 COMMIT | A3_PH_RR_FINAL | 3 | (fuera de tx ya ve 3)

=== B PH RR ===
 BEGIN | 7 | Fantasma Pizza TP2 | INSERT 0 1 COMMIT
```

> Verificación: RC `2→3` fantasma visible, RR `2→2` no visible (PG ya previene phantom read-only). IA dijo "solo SERIALIZABLE" → **discrepancia documentada, corrige motor** (PDF p5 exige documentar si IA no se confirma).

**Variante alternativa `pedido` (si `producto` da conflicto UNIQUE):**
```sql
-- Sesión A: BEGIN ISOLATION LEVEL READ COMMITTED; SELECT COUNT(*) FROM pedido WHERE cliente_id=1;
-- Sesión B: BEGIN; INSERT INTO pedido (forma_pago, cliente_id) VALUES ('TARJETA', 1); COMMIT;
-- Sesión A: SELECT COUNT(*) FROM pedido WHERE cliente_id=1; -- RC 1→2, RR 1→1
```

**Error común a evitar:** Olvidar `COMMIT` de B antes del 2do `COUNT` de A → A no ve fantasma y creés que `RC` lo evita. Orden: A `COUNT` → B `INSERT+COMMIT` → A `COUNT`.

---

## Escenario 3 — Espera por Bloqueo `FOR UPDATE` (mecanismo, no anomalía)

| Campo | Contenido |
|---|---|
| **Escenario** | Espera por bloqueo — 2 sesiones piden `SELECT ... FOR UPDATE` sobre misma fila; la 2da queda esperando hasta `COMMIT/ROLLBACK` de la 1ra. No es anomalía ANSI, es bloqueo pesimista explícito para evitar `Lost Update`. |
| **Tabla/fila Food Store** | `producto WHERE id=1` (Muzzarella) — fila caliente `stock/precio`. No usar `categoria` (poca contención). |
| **Cómo se reprodujo** | A `BEGIN; SELECT ... FOR UPDATE` (lock) → B `BEGIN; SELECT ... FOR UPDATE` (se bloquea, cursor parpadea, no retorna) → diagnóstico `pg_locks`/`pg_blocking_pids` en 3ra pestaña → A `COMMIT` → B desbloquea y retorna fila |
| **Qué se observó** | B **no da error**, queda en `wait_event_type=Lock`, `wait_event=transactionid/tuple`. `pg_locks` muestra `FOR UPDATE` `granted=true` para A y `granted=false` para B. Tras `COMMIT` de A, B retorna inmediatamente con datos actualizados. Con `NOWAIT` da `ERROR 55P03` inmediato. |
| **Explicación de la IA** | *Copiada tal cual:* <br> > "FOR UPDATE indica intención de modificar y bloquea la fila para evitar lost update. La espera es el comportamiento deseado y no depende del nivel de aislamiento; ocurre en READ COMMITTED, REPEATABLE READ y SERIALIZABLE. Se resuelve con NOWAIT, SKIP LOCKED o lock_timeout." |
| **Verificación en el motor** | Se verificó que bloquea **idéntico** en `READ COMMITTED` y `REPEATABLE READ` (misma espera), y que `SELECT ... FOR UPDATE NOWAIT` da `55P03` sin esperar. También se probó `SET lock_timeout='5s'` para timeout controlado. `SELECT * FROM pg_locks WHERE relation='producto'::regclass;` y `SELECT pg_blocking_pids(pid) FROM pg_stat_activity WHERE pid=...` capturados. |
| **Conclusión** | IA **acertó**. Ningún nivel de aislamiento evita la espera — es mecanismo ortogonal. Solución: ordenar locks, usar `NOWAIT`/`SKIP LOCKED`, `lock_timeout`, transacciones cortas, retry en app al capturar `55P03`. |

### Comandos exactos — FOR UPDATE

```sql
-- Sesión A (izquierda)
BEGIN;
SELECT * FROM producto WHERE id = 1 FOR UPDATE; -- adquiere RowExclusiveLock, retorna fila
SELECT pg_backend_pid(); -- anotar pid A, ej 12345

-- Sesión B (derecha) — ejecutar y queda BLOQUEADA (no retorna, no Ctrl+C)
BEGIN;
-- Opcional para demo controlada (no esperar infinito):
SET lock_timeout = '15s';
SELECT * FROM producto WHERE id = 1 FOR UPDATE; -- ¡NO RETORNA! Estado waiting
-- (dejar bloqueada)

-- Sesión C (diagnóstico, 3ra pestaña) — mientras B está bloqueada:
SELECT pid, usename, wait_event_type, wait_event, query, state
  FROM pg_stat_activity WHERE pid IN (12345, 67890); -- pids de A y B
SELECT relation::regclass, mode, granted, pid
  FROM pg_locks WHERE relation='producto'::regclass;
SELECT blocked.pid AS blocked, blocking.pid AS blocking, blocked.query, blocking.query
  FROM pg_stat_activity blocked JOIN pg_stat_activity blocking
    ON blocking.pid = ANY(pg_blocking_pids(blocked.pid))
 WHERE blocked.pid = 67890; -- pid B

-- Sesión A (desbloquea)
COMMIT; -- o ROLLBACK
-- Inmediatamente Sesión B retorna la fila (desbloqueada) → muestra datos
SELECT pg_backend_pid(); -- pid B

-- Sesión B
COMMIT;

-- --- PRUEBA NOWAIT (no espera, error inmediato) ---
-- Sesión A: BEGIN; SELECT * FROM producto WHERE id=1 FOR UPDATE;
-- Sesión B: BEGIN; SELECT * FROM producto WHERE id=1 FOR UPDATE NOWAIT;
-- → ERROR:  could not obtain lock on row in relation "producto"  SQLSTATE 55P03
-- Sesión B: ROLLBACK; Sesión A: COMMIT;

-- --- PRUEBA con UPDATE (mismo efecto) ---
-- Sesión A: BEGIN; UPDATE producto SET stock = stock -1 WHERE id=1; -- sin COMMIT
-- Sesión B: BEGIN; UPDATE producto SET stock = stock -1 WHERE id=1; -- bloqueada hasta A COMMIT
```

**Captura `psql` real (motor, 2026-09-04, `FOR UPDATE`):**

```
=== pg_stat_activity while B waiting (2s) ===
  pid  |                    query                                              | state  | wait_event_type | wait_event
 14100 | SELECT ... FOR UPDATE (B)                                              | active | Lock            | transactionid
  7464 | SELECT pg_stat_activity ...                                           | active |                 |

=== pg_locks while waiting ===
   tbl    |        mode         | granted | pid
 producto | RowShareLock        | t       | 13320 (A)
 producto | RowShareLock        | t       | 14100 (B waiting)

=== A OUTPUT (hold 4.10s) ===
 BEGIN | A_FU_LOCKED | 1 | Muzzarella | 1000.00 |
 pg_sleep(4) | A_FU_BEFORE_COMMIT | COMMIT | A_FU_COMMITTED |

=== B OUTPUT (waited 3.73s) ===
 B_FU_TRY | BEGIN | B_FU_WAITING (bloqueada, no retorna hasta A COMMIT)
 | B_FU_WAITING | 1 | Muzzarella |  <-- desbloquea tras A COMMIT
 | B_FU_GOT_LOCK | COMMIT | B_FU_DONE |
 B_DURATION: 3.739s  A_DURATION: 4.106s  (B esperó)
```

*Prueba NOWAIT (no espera, error inmediato) — ejecutada manual:*
```
-- Sesión A: BEGIN; SELECT * FROM producto WHERE id=1 FOR UPDATE;
-- Sesión B: BEGIN; SELECT * FROM producto WHERE id=1 FOR UPDATE NOWAIT;
--> ERROR:  could not obtain lock on row in relation "producto"  SQLSTATE 55P03
```

> Verificación: bloqueo idéntico en `READ COMMITTED` y `REPEATABLE READ` (ortogonal a aislamiento). IA acertó.

**Notas para defensa oral:** `FOR UPDATE` vs `FOR SHARE` (`SHARE` permite lecturas concurrentes, `UPDATE` no), `NOWAIT` vs `SKIP LOCKED` (salta filas bloqueadas), `lock_timeout` vs `statement_timeout`, `pg_locks.mode`.

---

## Resumen y matriz comparativa

| Escenario | Tabla usada | Anomalía en `READ COMMITTED` | Se evita con | ¿IA acertó? | Dificultad | Valor pedagógico |
|---|---|---|---|---|---|---|
| **No Repetible** | `producto.precio id=1` | SÍ `1000→1050` | `REPEATABLE READ` / `SERIALIZABLE` (snapshot por tx) | Sí (~90%) | 1/5 Muy fácil | Alto (base) |
| **Fantasma** | `producto COUNT categoria_id=1` | SÍ `2→3` | `REPEATABLE READ` ya alcanza en PG (ANSI dice `SERIALIZABLE`) — matiz estrella | No (~30% dice solo SERIALIZABLE) — discrepancia valiosa | 2.5/5 Media | Muy alto (diferenciador) |
| **FOR UPDATE espera** | `producto id=1` | No anomalía, bloqueo deseado | **Ningún nivel** (lock explícito) | Sí (si no confunde con aislamiento) | 1/5 Muy fácil | Alto (visual) |

**Claves MVCC PG para oral:**
- `READ COMMITTED` = snapshot por **sentencia**
- `REPEATABLE READ` / `SERIALIZABLE` = snapshot por **transacción** (`SERIALIZABLE` añade SSI predicate tracking)
- `FOR UPDATE` no crea snapshot, crea `RowExclusiveLock` en `pg_locks`
- Deadlock `40P01` (no usado en SAFE, ver anexo) vs `serialization_failure 40001` vs `lock_not_available 55P03`

---

## Checklist de entrega Parte 2 (PDF p5)
- [ ] Cada escenario tiene sección con 6 filas (Escenario/Cómo se reprodujo/Qué se observó/Explicación IA/Verificación/Conclusión)
- [ ] Comandos A/B en orden numerado copiados tal cual `psql`
- [ ] Salida real `psql` pegada (no inventada)
- [ ] `SHOW transaction_isolation;` visible para trazabilidad
- [ ] Explicación IA copiada textual, sin editar
- [ ] Verificación con `SET TRANSACTION ISOLATION LEVEL` que confirma o refuta a la IA (fantasma: discrepancia documentada, no ocultada)
- [ ] DUIA Parte 2 en `TP02/DUIA.md` completa

---

## Instrucciones para generar capturas (hacer sobre `foodstore_copia`)

1. Abrir 2 `psql` con: `& "C:\Program Files\PostgreSQL\18\bin\psql.exe" -U postgres -h localhost -d foodstore_copia` (ingresar clave cuando pida)
2. Ejecutar preparación común arriba
3. Para cada escenario: ejecutar comandos en orden **sin olvidar `COMMIT` de B antes de 2da lectura de A**
4. Copiar salida de ambas pestañas (incluyendo `foodstore_copia=*#` y `SHOW transaction_isolation;`) y pegar en secciones "Captura `psql`"
5. `DUIA` ya tiene prompts y verificación — completar con salida real
