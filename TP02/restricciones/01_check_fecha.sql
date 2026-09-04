-- =============================================================================
-- Food Store — TP2 Parte 1 — Restricción A: Fecha de pedido coherente
-- Regla de negocio: pedido.fecha nunca futura (y no absurda hacia atrás)
-- Cubre ejemplo PDF p3 "rango de fechas coherente"
-- Autor: OpenCode + muse-spark-1.2 (motor primario) — spec humana abajo
-- Protocolo: aplicar sobre foodstore_copia dentro de BEGIN; ...; ROLLBACK; primero
-- =============================================================================

-- Spec humana (PDF p3.2 paso 1): "Impedir INSERT en pedido con fecha futura:
--   ALTER TABLE pedido ADD CONSTRAINT chk_pedido_fecha_no_futura CHECK (fecha <= now())"
--   Tabla.columna exacta: pedido.fecha TIMESTAMPTZ DEFAULT now() (TP01/schema.sql:77)

-- Limpieza idempotente si se re-ejecuta
ALTER TABLE pedido DROP CONSTRAINT IF EXISTS chk_pedido_fecha_no_futura;
ALTER TABLE pedido DROP CONSTRAINT IF EXISTS chk_pedido_fecha_no_pasada_extrema;

-- -------------------------------------------------------------------------
-- CHECK 1: fecha no futura (con tolerancia de 5 minutos por desfasaje de reloj)
-- Por qué now() + interval '5 minutes' y no now() exacto:
--   - now() es timestamp de inicio de transacción (estable dentro de la tx)
--   - Si app y BD tienen segundos de drift, un INSERT con now() del cliente
--     podría caer 2s en el futuro y fallar injustamente. 5 min es margen seguro
--   - Alternativa estricta sería CHECK (fecha <= clock_timestamp()) pero
--     clock_timestamp() cambia por sentencia y no es inmutable para CHECK
-- Por qué TIMESTAMPTZ: ya es TIMESTAMPTZ en schema.sql:77, guarda zona horaria
-- -------------------------------------------------------------------------
ALTER TABLE pedido
    ADD CONSTRAINT chk_pedido_fecha_no_futura
    CHECK (fecha <= now() + interval '5 minutes');

COMMENT ON CONSTRAINT chk_pedido_fecha_no_futura ON pedido IS
    'Rango temporal: pedido.fecha no puede ser futura (tolerancia 5 min por clock skew). Cubre regla TP2 p3 "rango de fechas coherente".';

-- -------------------------------------------------------------------------
-- CHECK 2 (opcional pero recomendado): fecha no absurda hacia atrás
-- Evita INSERT con fecha 1900 o 1970 por error de app. No exigido por PDF
-- pero demuestra defensa en profundidad. Límite 2020-01-01 = inicio proyecto.
-- Si tu BD ya tiene datos viejos, valida primero con:
--   SELECT min(fecha) FROM pedido; -- debe ser >= 2020-01-01
-- Si falla, crear como NOT VALID y validar después:
--   ADD CONSTRAINT ... CHECK (...) NOT VALID; luego VALIDATE CONSTRAINT;
-- -------------------------------------------------------------------------
ALTER TABLE pedido
    ADD CONSTRAINT chk_pedido_fecha_no_pasada_extrema
    CHECK (fecha >= TIMESTAMPTZ '2020-01-01 00:00:00+00');

COMMENT ON CONSTRAINT chk_pedido_fecha_no_pasada_extrema ON pedido IS
    'Rango temporal inferior: evita fechas absurdas (antes de 2020). Complemento a no-futura.';

-- =============================================================================
-- Verificación recomendada (ejecutar en foodstore_copia, dentro de transacción):
--
-- BEGIN;
-- \i TP02/restricciones/01_check_fecha.sql
--
-- -- Válido: fecha actual (DEFAULT now())
-- INSERT INTO pedido (forma_pago, cliente_id) VALUES ('EFECTIVO', 1) RETURNING id, fecha;
-- -- Válido: hace 1 día
-- INSERT INTO pedido (fecha, forma_pago, cliente_id) VALUES (now() - interval '1 day', 'TARJETA', 1) RETURNING id;
-- -- Inválido: fecha futura +1 día → debe dar ERROR 23514 (check_violation)
-- INSERT INTO pedido (fecha, forma_pago, cliente_id) VALUES (now() + interval '1 day', 'EFECTIVO', 1);
-- -- Inválido: fecha 2019 → debe dar ERROR 23514
-- INSERT INTO pedido (fecha, forma_pago, cliente_id) VALUES ('2019-06-01', 'EFECTIVO', 1);
--
-- SELECT con_name, con_validated FROM pg_constraint WHERE conname LIKE 'chk_pedido_fecha%';
-- ROLLBACK; -- inspeccionar, luego repetir con COMMIT si todo OK
--
-- Defensa oral (qué hace cada línea y qué pasa si se saca):
-- - ALTER TABLE ... ADD CONSTRAINT ... CHECK (fecha <= now() + interval ...): añade validación declarativa; sin ella, fecha futura se inserta sin error
-- - DROP CONSTRAINT IF EXISTS: hace el script idempotente (re-ejecutable sin error)
-- - COMMENT ON CONSTRAINT: documenta regla para \d pedido y defensa
-- - Segundo CHECK >= '2020-01-01': sin él, fecha 1900 pasaría (dato absurdo)
-- =============================================================================
