# Ejercicio de Lectura Crítica — TP2 Parte 3

> **Por qué se lee antes de ejecutar** — PDF p6. Protocolo `protocolo_seguridad.md` existe porque cuando falla, el costo se mide en datos reales que no vuelven.

---

## Script 1 — `UPDATE funcion SET activa = FALSE;`

> **Generado para:** "dar de baja las funciones de películas retiradas de cartel" (esquema genérico de cátedra: `funcion(id, pelicula_id, activa, fecha, ...)` + `pelicula(id, estado)`)

### Qué haría realmente tal como está escrito

```sql
UPDATE funcion SET activa = FALSE;
-- Sin WHERE → afecta TODAS las filas de funcion, sin excepción
-- Si hay 10.000 funciones históricas, las 10.000 pasan a activa=FALSE
-- Incluye funciones vigentes, futuras, pasadas y ya inactivas (todas)
```

**Estimación de filas:** `SELECT count(*) FROM funcion;` filas (100%). Equivalente a `TRUNCATE` lógico de la cartelera.

### Por qué no coincide con la consigna que dice cumplir

- Consigna dice **"funciones de películas retiradas de cartel"** → subconjunto (solo películas con `estado='RETIRADA'` o `fecha_fin < CURRENT_DATE` o `activa=FALSE` en `pelicula`).
- Script no filtra por `pelicula_id` ni por `fecha` ni por `estado` → desactiva funciones de películas **activas** también (ej: estreno de mañana desaparece de cartel).
- Pérdida de granularidad: no hay `WHERE pelicula_id IN (...)` ni `WHERE EXISTS (... pelicula ...)`.
- Además: no está en transacción ni con `SELECT` previo — viola protocolo de copia/transacción/respaldo. Si se ejecuta en producción, no hay `ROLLBACK` sin backup.

### Versión corregida

```sql
-- Opción A (recomendada): por estado de película (si existe pelicula.estado)
BEGIN;
-- 1. Inspeccionar qué se va a tocar (protocolo)
SELECT f.id, f.pelicula_id, p.titulo, p.estado, f.activa, f.fecha
  FROM funcion f JOIN pelicula p ON p.id = f.pelicula_id
 WHERE p.estado = 'RETIRADA' AND f.activa = TRUE;
-- 2. Si el SELECT devuelve el subconjunto correcto, recién entonces:
UPDATE funcion
   SET activa = FALSE
 WHERE pelicula_id IN (SELECT id FROM pelicula WHERE estado = 'RETIRADA')
   AND activa = TRUE; -- idempotente, no re-desactiva ya inactivas
-- 3. Verificar
SELECT count(*) AS desactivadas FROM funcion WHERE activa = FALSE;
-- Si ok: COMMIT; si no: ROLLBACK;
```

```sql
-- Opción B: por fecha de fin de cartel (si no hay estado, sino vigencia)
BEGIN;
SELECT * FROM funcion WHERE fecha < CURRENT_DATE - interval '1 day' AND activa = TRUE;
UPDATE funcion SET activa = FALSE
 WHERE fecha < CURRENT_DATE - interval '1 day'
   AND activa = TRUE;
-- COMMIT / ROLLBACK
```

```sql
-- Opción C: por lista explícita (si el operador pasa ids)
BEGIN;
UPDATE funcion SET activa = FALSE WHERE id IN (101, 205, 310) AND activa = TRUE;
-- COMMIT / ROLLBACK
```

**Qué cambia vs original:** añade `WHERE` que restringe a retiradas, `AND activa=TRUE` para no tocar ya inactivas, envuelto en `BEGIN; ...; ROLLBACK;` primero, y `SELECT` previo para contar filas afectadas. Sin `WHERE` era 100% de filas; con `WHERE` es <10% (solo retiradas).

### Mapeo a Food Store (para entender el patrón)

En Food Store el equivalente sería:
```sql
-- ❌ Mal (misma trampa que Script 1): desactiva todos los productos
UPDATE producto SET activo = FALSE;
-- ✅ Bien: solo los de categoría retirada o con stock 0 hace 6 meses
UPDATE producto SET activo = FALSE WHERE categoria_id IN (SELECT id FROM categoria WHERE activo=FALSE) AND activo=TRUE;
```

### Defensa oral — qué responder si preguntan "qué hace esta línea"

- `UPDATE funcion SET activa=FALSE;` sin `WHERE` → Table Scan + Row Exclusive Lock sobre todas las filas, WAL enorme, dispara `TRIGGER` `AFTER UPDATE` por cada fila, no hay predicate. Si se saca `WHERE` corregido, vuelve al bug.
- `WHERE pelicula_id IN (SELECT id FROM pelicula WHERE estado='RETIRADA')` → semi-join, solo toca retiradas. Sin esa subquery, toca todas.

---

## Script 2 — `DELETE FROM categoria WHERE id NOT IN (SELECT categoria_id FROM producto);`

> **Generado para:** "limpiar las categorías sin productos asociados" (esquema genérico `categoria(id)` + `producto(id, categoria_id)`)

### Qué haría realmente tal como está escrito

```sql
DELETE FROM categoria WHERE id NOT IN (SELECT categoria_id FROM producto);
```

**Caso 1 — `producto.categoria_id` tiene al menos un `NULL`:**
- `SELECT categoria_id FROM producto` devuelve `{1, 2, NULL, 3}`
- `id NOT IN (1,2,NULL,3)` → `id <> 1 AND id <> 2 AND id <> NULL AND id <> 3` → `UNKNOWN` por `NULL` (tres valores) → `WHERE` filtra `UNKNOWN` como falso
- **Resultado: 0 filas borradas**, aunque haya categorías vacías. **No borra nada** — fallo silencioso.

**Caso 2 — `producto.categoria_id` es `NOT NULL` (como en Food Store `TP01/schema.sql:62`):**
- `SELECT` no tiene `NULL`, entonces `NOT IN` **sí funciona** y borra categorías sin productos.
- **Pero** borra **todas** las vacías sin distinguir `activo`, sin `ON DELETE RESTRICT`, sin transacción, y sin verificar si categoría vacía es intencional (ej: "Próximamente" creada para futuro catálogo).

**Estimación de filas:** `0` si hay un `NULL` anywhere, o `SELECT count(*) FROM categoria c WHERE NOT EXISTS (SELECT 1 FROM producto p WHERE p.categoria_id=c.id)` filas si `NOT NULL`.

### Por qué no coincide con la consigna que dice cumplir

- Consigna dice "categorías sin productos asociados" → intención es limpiar huérfanas. Pero `NOT IN` con `NULL` no limpia ninguna (falla silenciosa, peor que no hacer nada porque el operador cree que limpió).
- No maneja `NULL` correctamente — trampa clásica `NOT IN` vs `NOT EXISTS`.
- No respeta baja lógica `R7` (`categoria.activo`): borrar física categoría vacía pero inactiva vs activa tiene implicancias distintas; mejor `UPDATE activo=FALSE` que `DELETE`.
- No respeta `ON DELETE RESTRICT` (`TP01/schema.sql:62`): en Food Store `producto.categoria_id ON DELETE RESTRICT` ya bloquearía `DELETE` si tuviera productos, pero `NOT IN` intenta borrar igual sin `CASCADE`.
- No está en `BEGIN;` ni con `pg_dump` previo — si hay `NULL` y no borra, el operador puede reintentar con `DELETE FROM categoria;` (sin WHERE) y borrar todo.

### Versión corregida — `NOT EXISTS` (NULL-safe, eficiente)

```sql
-- ✅ Recomendada: NOT EXISTS (siempre correcta, corta al primer match, NULL-safe)
BEGIN;
-- 1. Inspeccionar huérfanas (protocolo)
SELECT c.id, c.nombre, c.activo
  FROM categoria c
 WHERE NOT EXISTS (SELECT 1 FROM producto p WHERE p.categoria_id = c.id);
-- 2. Si son las que querés borrar y no hay NULLs problemáticos:
DELETE FROM categoria c
 WHERE NOT EXISTS (SELECT 1 FROM producto p WHERE p.categoria_id = c.id)
   AND c.activo = FALSE; -- opcional: solo inactivas y vacías (respeta R7)
-- 3. Verificar
SELECT count(*) AS borradas FROM categoria; -- o RETURNING
-- COMMIT / ROLLBACK;
-- Alternativa con RETURNING para auditar:
DELETE FROM categoria c
 WHERE NOT EXISTS (SELECT 1 FROM producto p WHERE p.categoria_id = c.id)
RETURNING id, nombre;
```

```sql
-- ✅ Alternativa si se insiste en NOT IN: filtrar NULL explícitamente
BEGIN;
SELECT * FROM categoria WHERE id NOT IN (SELECT categoria_id FROM producto WHERE categoria_id IS NOT NULL);
DELETE FROM categoria
 WHERE id NOT IN (SELECT categoria_id FROM producto WHERE categoria_id IS NOT NULL)
   AND activo = FALSE;
-- COMMIT / ROLLBACK
```

```sql
-- ✅ Food Store específico (con baja lógica): no DELETE físico, sino baja lógica
BEGIN;
UPDATE categoria SET activo = FALSE
 WHERE NOT EXISTS (SELECT 1 FROM producto p WHERE p.categoria_id = categoria.id)
   AND activo = TRUE;
-- COMMIT / ROLLBACK
```

**Qué cambia vs original:**
- `NOT IN (SELECT categoria_id FROM producto)` → `NOT EXISTS (SELECT 1 FROM producto WHERE producto.categoria_id = categoria.id)` → no le afecta `NULL`, usa índice `idx_producto_categoria`, y es `EXISTS` correlacionado (más eficiente).
- Añade `WHERE categoria_id IS NOT NULL` si se mantiene `NOT IN`.
- Envuelto en `BEGIN; ...; ROLLBACK;` + `SELECT` previo (protocolo).
- Opcional `AND activo=FALSE` para no borrar categorías vacías pero activas (ej: "Próximamente").

### Comparativa `NOT IN` vs `NOT EXISTS` (para defensa oral)

| Consulta | Con `NULL` en subconsulta | Sin `NULL` | Performance | ¿Recomendada? |
|---|---|---|---|---|
| `WHERE id NOT IN (SELECT categoria_id FROM producto)` | **0 filas** (bug) | Correcta pero frágil | Escaneo + `Hash Anti Join` con `NULL` handling | ❌ No |
| `WHERE id NOT IN (SELECT categoria_id FROM producto WHERE categoria_id IS NOT NULL)` | Correcta | Correcta | Igual + filtro | ⚠️ Ok si filtras NULL |
| `WHERE NOT EXISTS (SELECT 1 FROM producto WHERE producto.categoria_id=categoria.id)` | **Correcta siempre** | Correcta | `Index Scan` en `idx_producto_categoria`, corta al primer match | ✅ Sí |

### Defensa oral — qué hace cada línea

- `WHERE id NOT IN (...)` sin `WHERE categoria_id IS NOT NULL` → si subquery tiene `NULL`, predicado es `UNKNOWN` y no borra. Sacar `IS NOT NULL` reintroduce bug.
- `WHERE NOT EXISTS (SELECT 1 ... WHERE p.categoria_id=c.id)` → correlacionada, por cada `categoria` busca 1 producto; si no existe, borra. Sin `WHERE p.categoria_id=c.id`, borraría todas (siempre `NOT EXISTS` vacío → true).
- `AND c.activo=FALSE` → protege categorías vacías pero activas; sin ello borrarías "Próximamente".

---

## Patrón común (PDF p6) y protocolo

En ambos scripts la sintaxis es válida y la intención razonable — el fallo fue **no interponer**: copia para que error no toque real, transacción para inspeccionar `SELECT count(*)`, y respaldo `pg_dump` para cuando `ROLLBACK` no alcanza.

**Protocolo aplicado a estos scripts:**
```sql
BEGIN;
-- SELECT count(*) previo que muestra filas afectadas
-- UPDATE/DELETE con WHERE corregido
-- SELECT count(*) posterior
ROLLBACK; -- inspeccionar
-- Si ok: BEGIN; UPDATE/DELETE corregido; COMMIT;
```

**Antes de ejecutar cualquier script generado por IA:**
- [ ] `CREATE DATABASE foodstore_copia TEMPLATE foodstore;`
- [ ] `pg_dump -Fc foodstore_copia -f backups/...dump`
- [ ] `BEGIN; script; SELECT; ROLLBACK;` — leer cada línea, contar filas, validar `WHERE` y manejo de `NULL`
- [ ] `git diff` si es DDL versionado

---
*Archivo commiteado — defendible línea por línea (PDF p4.3).*
