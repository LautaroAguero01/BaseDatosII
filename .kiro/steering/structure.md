# Steering — Estructura del Proyecto

## Layout
- `TP01/schema.sql` — fuente de verdad DDL (orden FK: categoria → cliente → producto → pedido → pedido_producto)
- `TP01/DUIA.md` — DUIA Semana 1 (referencia formato)
- `TP02/TP2_Laboratorio_Concurrencia_IA.pdf` — consigna (7 páginas, 4 partes)
- `TP02/protocolo_seguridad.md` — Parte 0 (adaptado Windows/psql, movido a TP02 para orden)
- `TP02/restricciones/` — Parte 1 scripts versionados (`01_check_fecha.sql`, `02_trigger_activo.sql`)
- `TP02/informe_concurrencia.md` — Parte 2 (3 escenarios SAFE: No Repetible, Fantasma, FOR UPDATE)
- `TP02/ejercicio_lectura_critica.md` — Parte 3 (2 scripts)
- `TP02/DUIA.md` — DUIA única (secciones Parte1/2/3 con tabla Herramienta/Prompt/Qué generó/Qué se aceptó/Verificación)
- `TP02/backups/` — dumps `pg_dump -Fc` (gitignored, movido a TP02 para orden)

## Dependencias entre partes
- Parte 0 bloquea todo: sin protocolo no se toca BD
- Parte 1 deja restricciones que se asumen en Parte 2 (pero no rompen concurrencia — A es CHECK, B es TRIGGER activo que no bloquea lecturas)
- Parte 2 usa tablas `producto` y `pedido` de `TP01/schema.sql`; requiere datos semilla `Muzzarella/Coca/Napolitana` + `categoria Pizzas/Bebidas`
- Parte 3 independiente, usa esquema genérico `funcion/categoria/producto` del PDF p6, no Food Store

## Orden de creación DDL
1. `DROP TABLE IF EXISTS pedido_producto, pedido, producto, cliente, categoria CASCADE; DROP TYPE IF EXISTS forma_pago_enum CASCADE;`
2. `CREATE TYPE forma_pago_enum`
3. `CREATE TABLE categoria → cliente → producto → pedido → pedido_producto` (respeta FK)
4. `CREATE INDEX idx_pedido_cliente, idx_producto_categoria`

## Git
- Commits atómicos por parte: `chore: protocolo seguridad Parte 0` → `feat: chk_pedido_fecha...` → `feat: trigger producto activo` → `docs: informe concurrencia` → `docs: lectura crítica`
- Siempre `git status` + `git diff` antes de `git add` + mensaje descriptivo con regla de negocio
