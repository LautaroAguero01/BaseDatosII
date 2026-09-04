# Declaración de Uso de IA (DUIA) — TP1 Food Store

**Materia:** Base de Datos I — UTN  
**Alumno:** Apellido_Nombre — Fecha: 2026-08-27  
**Proyecto:** Food Store — Semana 1 (ER → Relacional → Normalización → DDL)

## Herramientas utilizadas
- **OpenCode + Muse Spark (muse-spark-1.2-contributor-free)** como motor primario de generación y revisión, conforme a Sección 7 del PDF (“La IA como motor primario”).
- **Kiro** (mencionado en consigna Sección 7) — flujo transversal de segundo año, no aplicado aún en Semana 1 salvo puesta a punto del repo.
- **dbdiagram.io** para diagrama ER (DBML en `docs/er.dbml`).
- **PostgreSQL** (validación sintáctica de `schema.sql`, sin ejecución con datos aún).

## Uso por parte
| Parte | Uso de IA | Prompt / Spec | Verificación humana |
|---|---|---|---|
| **Parte 1 ER** | Generación de `docs/er.dbml` Crow's Foot, diccionario y respuestas guía Q1-Q3 | “A partir de R1-R7, genera ER Crow's Foot minimalista, diccionario y respuestas fundadas a las 3 preguntas guía del PDF p3” | Revisado: cardinalidades R1 parcial/total y justificación N:M vs 1:N; decisión nombre compuesto documentada |
| **Parte 2 Relacional** | Derivación a 5 tablas con notación `tabla (atributos)` y respuestas guía | “Deriva ER a relacional con reglas 1:N→FK en N, N:M→intermedia PK compuesta, justifica PK compuesta y responde 2 preguntas guía p3” | Revisado: FKs NOT NULL por participación total, PK compuesta preservada |
| **Parte 3 Normalización** | Desarrollo 7 pasos 1FN→BCNF con FDs y preguntas de integración | “Normaliza U(nro_pedido,fecha,cliente,producto,categoria,precio_unitario,cantidad,subtotal,forma_pago) listando FDs, clave (nro_pedido,producto), pista precio temporal Muzzarella, y responde integración” | Revisado: FD `producto→precio_unitario` descartada por contraejemplo temporal; BCNF verificada explícitamente; subtotal tratado como derivado |
| **Parte 4 DDL** | Generación de `schema.sql` con ENUM, PK/FK RESTRICT, UNIQUE, 3 CHECKs, NOT NULL, DEFAULT, 2 INDEX comentados | “Escribe schema.sql PostgreSQL ejecutable con tipos adecuados, ENUM forma_pago, FK ON DELETE RESTRICT justificado por R7, CHECK precio/stock/cantidad, UNIQUE email, INDEX pedagógico” | Revisado: tipos `NUMERIC(10,2)` no FLOAT, `BIGINT GENERATED ALWAYS AS IDENTITY`, script idempotente con DROP IF EXISTS, orden FK, comentarios ON DELETE |
| **Documentación** | Estructuración de `PLAN.md`, `docs/01_y_02_diseno.md`, `docs/03_normalizacion.md` | “Organiza con 3 hitos secuenciales para handoff a otro modelo” | Revisado: entregables en `Apellido_Nombre_TP1.zip` |

## Prompts clave (resumen)
1. `Analiza PDF p2 R1-R7 y p4 planilla; decide clave (nro_pedido,producto) y FDs, destacando pista precio Muzzarella 1000→1050`
2. `Genera DBML Crow's Foot con 4 entidades + intermedia PK compuesta, R7 activo, R6 email UNIQUE, R5 CHECKs`
3. `Escribe DDL PostgreSQL idempotente con comentarios de diseño no obvio (ej ON DELETE RESTRICT)`

## Criterio y responsabilidad
- Ningún script se ejecuta sin lectura previa (riesgo fundacional Sección 7).
- El estudiante es responsable final de cada decisión de diseño y script, la IA es motor primario pero no reemplaza el criterio.
- Flujo de segundo año: repo versionado con `schema.sql`, revisión de diff, copia/transacción/respaldo (protocolo cátedra) — registrado para Semana 2 (concurrencia/transacciones).

## Estado Sección 7
- Puesta a punto OpenCode/Kiro sobre repo: **realizada** (este repo).
- Escenarios de concurrencia / anomalías de aislamiento: **anticipado Semana 2**, no corresponde a Semana 1 salvo mención.
- Primer ejercicio de integridad versionado en Git: **realizado** (este `schema.sql`).

---
*Declaración conforme a Sección 7 del TP1 — documentación completa de herramienta, propósito y prompts.*
