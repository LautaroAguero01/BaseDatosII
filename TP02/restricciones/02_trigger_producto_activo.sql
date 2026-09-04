-- =============================================================================
-- Food Store — TP2 Parte 1 — Restricción B: Baja lógica real (R7)
-- Regla de negocio: no vender producto inactivo ni de categoría inactiva
-- Cierra el mayor agujero de TP01/schema.sql: producto.activo y categoria.activo
-- existen (líneas 28,61) pero jamás se validan en pedido_producto (líneas 94-102)
-- Autor: OpenCode + muse-spark-1.2 — spec humana abajo
-- Protocolo: pg_dump antes de CREATE TRIGGER, luego BEGIN; \i ...; ROLLBACK;
-- =============================================================================

-- Spec humana (PDF p3.2): "Impedir INSERT/UPDATE en pedido_producto si
--   producto.activo = FALSE o categoria.activo = FALSE (baja lógica R7).
--   Si cualquiera está inactivo, la venta debe fallar con RAISE EXCEPTION."
--   Tablas.columnas exactas: pedido_producto.producto_id → producto.activo → categoria.activo

-- Limpieza idempotente
DROP TRIGGER IF EXISTS trg_pedido_producto_activo ON pedido_producto;
DROP FUNCTION IF EXISTS fn_bloquear_producto_inactivo();

-- -------------------------------------------------------------------------
-- Función: valida que producto y su categoría estén activos
-- Por qué TRIGGER y no CHECK/FK:
--   - CHECK solo ve fila actual, no puede hacer JOIN a producto/categoria
--   - FK solo valida existencia, no valor de columna activo
--   - Necesita lectura cruzada → TRIGGER BEFORE con SELECT es la herramienta
-- Por qué BEFORE FOR EACH ROW:
--   - BEFORE permite abortar con RAISE antes de escribir
--   - FOR EACH ROW valida fila por fila (no STATEMENT)
-- Por qué RAISE EXCEPTION y no RETURN NULL:
--   - RAISE aborta tx con mensaje claro (ERROR  P0001) que ve la app
--   - RETURN NULL en BEFORE silenciosamente descarta fila sin error (no deseado)
-- -------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_bloquear_producto_inactivo()
RETURNS TRIGGER AS $$
DECLARE
    v_prod_activo BOOLEAN;
    v_prod_nombre TEXT;
    v_cat_id      BIGINT;
    v_cat_activo  BOOLEAN;
    v_cat_nombre  TEXT;
BEGIN
    -- 1. Buscar producto y su categoría (una sola query con JOIN sería más corta,
    --    pero separada permite mensajes de error más específicos para defensa oral)
    SELECT activo, nombre, categoria_id
      INTO v_prod_activo, v_prod_nombre, v_cat_id
      FROM producto
     WHERE id = NEW.producto_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Producto % no existe (FK debería haberlo bloqueado antes)', NEW.producto_id
            USING ERRCODE = 'foreign_key_violation';
    END IF;

    IF NOT v_prod_activo THEN
        RAISE EXCEPTION 'Producto % (id=%) inactivo — baja lógica R7: no se puede vender', v_prod_nombre, NEW.producto_id
            USING ERRCODE = 'check_violation',
                  HINT = 'Reactivar producto con UPDATE producto SET activo=TRUE WHERE id=' || NEW.producto_id;
    END IF;

    -- 2. Validar categoría del producto
    SELECT activo, nombre
      INTO v_cat_activo, v_cat_nombre
      FROM categoria
     WHERE id = v_cat_id;

    -- Si categoría no existe, FK ya habría fallado, pero se chequea por robustez
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Categoría % del producto % no existe', v_cat_id, NEW.producto_id;
    END IF;

    IF NOT v_cat_activo THEN
        RAISE EXCEPTION 'Categoría % (id=%) inactiva — producto % no se puede vender', v_cat_nombre, v_cat_id, v_prod_nombre
            USING ERRCODE = 'check_violation',
                  HINT = 'Reactivar categoría con UPDATE categoria SET activo=TRUE WHERE id=' || v_cat_id;
    END IF;

    -- Todo ok → dejar que la fila se inserte/actualice
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION fn_bloquear_producto_inactivo() IS
    'TP2 Parte1 B: bloquea venta de producto/categoría inactiva (R7). Usada por trg_pedido_producto_activo.';

-- -------------------------------------------------------------------------
-- Trigger: se dispara en INSERT o UPDATE que toque producto_id
-- Por qué INSERT OR UPDATE y no solo INSERT:
--   - INSERT cubre nueva línea de pedido
--   - UPDATE cubre cambio de producto en línea existente (ej: UPDATE pedido_producto SET producto_id=2)
--   - Si solo se cambia cantidad/precio_unitario sin tocar producto_id, el trigger igual
--     re-valida (seguro, costo 1 SELECT extra). Alternativa: WHEN (OLD.producto_id IS DISTINCT FROM NEW.producto_id)
--     para optimizar, pero se deja simple para defensa oral.
-- -------------------------------------------------------------------------
CREATE TRIGGER trg_pedido_producto_activo
    BEFORE INSERT OR UPDATE ON pedido_producto
    FOR EACH ROW
    EXECUTE FUNCTION fn_bloquear_producto_inactivo();

COMMENT ON TRIGGER trg_pedido_producto_activo ON pedido_producto IS
    'R7 baja lógica: impide venta si producto o categoría están inactivos.';

-- =============================================================================
-- Verificación recomendada (sobre foodstore_copia, dentro de transacción):
--
-- -- Preparar datos semilla si no existen:
-- INSERT INTO categoria (nombre) VALUES ('Pizzas Test') ON CONFLICT (nombre) DO NOTHING;
-- INSERT INTO producto (nombre, precio, stock, categoria_id) VALUES ('Prod Activo Test', 100, 10, (SELECT id FROM categoria WHERE nombre='Pizzas Test' LIMIT 1)) ON CONFLICT DO NOTHING;
-- SELECT id, nombre, activo FROM producto WHERE nombre='Prod Activo Test'; -- anotar id
-- SELECT id, nombre, activo FROM categoria WHERE nombre='Pizzas Test';
--
-- BEGIN;
-- \i TP02/restricciones/02_trigger_producto_activo.sql
--
-- -- Caso válido: producto y categoría activos → debe INSERT OK
-- INSERT INTO cliente (nombre, email) VALUES ('Test Cliente', 'test_activo@test.com') ON CONFLICT (email) DO NOTHING;
-- INSERT INTO pedido (forma_pago, cliente_id) VALUES ('EFECTIVO', (SELECT id FROM cliente WHERE email='test_activo@test.com')) RETURNING id; -- anotar pedido_id
-- INSERT INTO pedido_producto (pedido_id, producto_id, cantidad, precio_unitario)
--   VALUES ((SELECT max(id) FROM pedido), (SELECT id FROM producto WHERE nombre='Prod Activo Test'), 1, 100); -- OK
--
-- -- Caso inválido 1: desactivar producto y reintentar → debe ERROR P0001
-- UPDATE producto SET activo=FALSE WHERE nombre='Prod Activo Test';
-- INSERT INTO pedido_producto (pedido_id, producto_id, cantidad, precio_unitario)
--   VALUES ((SELECT max(id) FROM pedido), (SELECT id FROM producto WHERE nombre='Prod Activo Test'), 1, 100);
-- -- → ERROR: Producto Prod Activo Test (id=...) inactivo — baja lógica R7
--
-- -- Caso inválido 2: reactivar producto, desactivar categoría → debe ERROR
-- UPDATE producto SET activo=TRUE WHERE nombre='Prod Activo Test';
-- UPDATE categoria SET activo=FALSE WHERE nombre='Pizzas Test';
-- INSERT INTO pedido_producto (pedido_id, producto_id, cantidad, precio_unitario)
--   VALUES ((SELECT max(id) FROM pedido), (SELECT id FROM producto WHERE nombre='Prod Activo Test'), 1, 100);
-- -- → ERROR: Categoría Pizzas Test (id=...) inactiva
--
-- -- Restaurar
-- UPDATE categoria SET activo=TRUE WHERE nombre='Pizzas Test';
-- SELECT * FROM pg_trigger WHERE tgname='trg_pedido_producto_activo';
--
-- ROLLBACK; -- inspeccionar, luego repetir con COMMIT si OK
--
-- Defensa oral (qué hace cada línea y qué pasa si se saca):
-- - DROP TRIGGER/FUNCTION IF EXISTS: idempotencia; sin ello segunda ejecución falla
-- - DECLARE v_prod_activo BOOLEAN: variable para guardar SELECT; sin ella no se puede chequear
-- - SELECT ... INTO ... FROM producto WHERE id=NEW.producto_id: lee estado actual; sin ella trigger no sabe si está activo
-- - IF NOT FOUND: maneja producto inexistente; sin ello RAISE no distingue FK
-- - IF NOT v_prod_activo THEN RAISE EXCEPTION: aborta venta; sin ello producto inactivo se vendería (agujero R7)
-- - SELECT de categoria: valida categoría; sin ello categoría inactiva dejaría vender
-- - RETURN NEW: permite INSERT; si fuera RETURN NULL la fila se descarta silenciosamente sin error (bug)
-- - CREATE TRIGGER BEFORE INSERT OR UPDATE FOR EACH ROW: momento y granularidad; AFTER no bloquearía, STATEMENT no ve NEW
-- =============================================================================
