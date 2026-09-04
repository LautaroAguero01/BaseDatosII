# Protocolo de Seguridad — Food Store (Base de Datos II)

> Parte 0 — Condición no negociable para cualquier script propio o generado por IA (PDF TP2 p2-3).
> Adaptado al entorno real del alumno. Sin este archivo no se avanza a Parte 1.
> **Ubicación:** `TP02/protocolo_seguridad.md` (movido a carpeta TP02 para orden; PDF pide raíz, este repo lo centraliza en TP02 — dejar constancia).

## Entorno real
- **OS:** Windows 11 (PowerShell 5.1)
- **Motor:** PostgreSQL 18.6 — `C:\Program Files\PostgreSQL\18\bin\psql.exe` / `pg_dump.exe` / `createdb.exe`
- **BD principal:** `foodstore` (esquema `TP01/schema.sql` aplicado)
- **BD de trabajo:** `foodstore_copia` (copia de desarrollo, nunca datos reales de terceros)
- **Cliente para concurrencia:** `psql` 2 pestañas (no DBeaver con autocommit ON)
- **Repo:** `H:\Universidad\2026\2do Semestre\Base de Datos II\BaseDatosII` — rama `main`

> **PATH en Windows:** `psql` no está en `PATH` por defecto. Usar ruta completa o agregar:
> ```powershell
> $env:Path += ";C:\Program Files\PostgreSQL\18\bin"
> # permanente:
> setx PATH "$env:Path;C:\Program Files\PostgreSQL\18\bin"
> ```

## Los 3 pasos — siempre, sin excepción, incluso si el cambio parece trivial

### 1. Copia — nunca sobre datos que importan
Trabajar sobre base de desarrollo clonada de la plantilla.

```powershell
# NOTA: todos los comandos se ejecutan desde la RAÍZ del repo (BaseDatosII/), aunque este archivo viva en TP02/
# Crear BD principal si no existe y aplicar esquema
& "C:\Program Files\PostgreSQL\18\bin\psql.exe" -U postgres -h localhost -c "CREATE DATABASE foodstore;" 2>&1
& "C:\Program Files\PostgreSQL\18\bin\psql.exe" -U postgres -h localhost -d foodstore -f "TP01/schema.sql"

# Crear/Recrear copia de trabajo (método TEMPLATE — rápido, sin dump/restore)
& "C:\Program Files\PostgreSQL\18\bin\psql.exe" -U postgres -h localhost -c "DROP DATABASE IF EXISTS foodstore_copia;"
& "C:\Program Files\PostgreSQL\18\bin\psql.exe" -U postgres -h localhost -c "CREATE DATABASE foodstore_copia TEMPLATE foodstore;"

# Alternativa con createdb -T (equivalente):
# & "C:\Program Files\PostgreSQL\18\bin\createdb.exe" -U postgres -h localhost -T foodstore foodstore_copia

# Verificar
& "C:\Program Files\PostgreSQL\18\bin\psql.exe" -U postgres -h localhost -l | Select-String "foodstore"
& "C:\Program Files\PostgreSQL\18\bin\psql.exe" -U postgres -h localhost -d foodstore_copia -c "SELECT count(*) FROM producto;"
```

**Cuándo se salta:** nunca.

### 2. Transacción — inspeccionar antes de confirmar
Todo script que escribe corre primero dentro de `BEGIN; ...; ROLLBACK;` para ver filas afectadas y mensajes antes de `COMMIT`.

```sql
-- Patrón obligatorio sobre foodstore_copia
BEGIN;
\i TP02/restricciones/01_check_fecha.sql
-- Pruebas válidas e inválidas:
INSERT INTO pedido (forma_pago, cliente_id) VALUES ('EFECTIVO', 1); -- debe OK
INSERT INTO pedido (fecha, forma_pago, cliente_id) VALUES ('2099-01-01 10:00:00+00', 'EFECTIVO', 1); -- debe ERROR
SELECT * FROM pedido ORDER BY id DESC LIMIT 3; -- inspeccionar
ROLLBACK; -- deshace todo, no quedó nada

-- Solo si ROLLBACK mostró lo esperado, aplicar definitivo:
BEGIN;
\i TP02/restricciones/01_check_fecha.sql
COMMIT;

-- También para DML de prueba en laboratorio de concurrencia:
BEGIN;
UPDATE producto SET precio = 1050 WHERE id = 1;
SELECT id, nombre, precio FROM producto WHERE id = 1;
ROLLBACK;
```

**Para DBeaver (si se usa en Parte 1):** desactivar `Autocommit` (barra superior → `Auto-commit OFF`), o envolver siempre en `BEGIN;`/`ROLLBACK;`. Para Parte 2 usar `psql` 2 pestañas — DBeaver oculta el estado de la transacción.

**Cuándo se salta:** nunca. Incluso `SELECT` de diagnóstico va dentro de transacción si le sigue un `ALTER`.

### 3. Respaldo — pg_dump antes de DDL estructural
`pg_dump` de la copia antes de `ALTER`, `DROP`, `CREATE TYPE`, `CREATE TRIGGER`/migración, para volver atrás sin depender del `ROLLBACK`.

```powershell
# Directorio de respaldos (dentro de TP02 para orden, versionado en .gitignore)
New-Item -ItemType Directory -Force -Path "TP02/backups" | Out-Null

# Respaldo custom (-Fc) antes de cada cambio estructural
& "C:\Program Files\PostgreSQL\18\bin\pg_dump.exe" -U postgres -h localhost -Fc foodstore_copia -f "TP02/backups/foodstore_copia_$(Get-Date -Format 'yyyy-MM-dd_HHmm').dump"
# Alternativa SQL plano (-Fp) para diff legible:
& "C:\Program Files\PostgreSQL\18\bin\pg_dump.exe" -U postgres -h localhost -Fp foodstore_copia -f "TP02/backups/foodstore_copia_$(Get-Date -Format 'yyyy-MM-dd_HHmm').sql"

# Verificar respaldo
Get-ChildItem TP02/backups/*.dump, TP02/backups/*.sql | Sort-Object LastWriteTime -Descending | Select-Object -First 3 Name, Length, LastWriteTime | Format-Table -AutoSize
# Probar restore en BD temporal (opcional):
# & "C:\Program Files\PostgreSQL\18\bin\psql.exe" -U postgres -h localhost -c "CREATE DATABASE foodstore_restore_test;"
# & "C:\Program Files\PostgreSQL\18\bin\pg_restore.exe" -U postgres -h localhost -d foodstore_restore_test "TP02/backups/foodstore_copia_....dump"

# Restore si algo salió mal:
# & "C:\Program Files\PostgreSQL\18\bin\psql.exe" -U postgres -h localhost -c "DROP DATABASE foodstore_copia;"
# & "C:\Program Files\PostgreSQL\18\bin\psql.exe" -U postgres -h localhost -c "CREATE DATABASE foodstore_copia TEMPLATE foodstore;" # o desde dump
```

**Cuándo se salta:** nunca. `ROLLBACK` no salva un `DROP DATABASE` commiteado ni un `ALTER` que bloqueó la tabla.

## Checklist operativo (usar en cada script)
- [ ] `foodstore_copia` existe y es copia fresca (`SELECT pg_database.datname FROM pg_database WHERE datname='foodstore_copia';`)
- [ ] `pg_dump` generado y verificado (`backups/*.dump` con fecha de hoy, tamaño >0)
- [ ] Script ejecutado primero con `BEGIN; \i script.sql; -- pruebas; ROLLBACK;` y se leyó cada mensaje
- [ ] `git diff` leído línea por línea (si una línea no se entiende, no se aplica)
- [ ] Segundo paso con `BEGIN; \i script.sql; COMMIT;` solo si el anterior mostró lo esperado
- [ ] `psql` usado para Parte 2 con 2 sesiones, `SHOW transaction_isolation;` verificado

## Qué hacer si falla
- **Autenticación `FATAL: password`:** configurar `PGPASSWORD` o `pgpass.conf` (`%APPDATA%\postgresql\pgpass.conf` con `localhost:5432:*:postgres:TU_CLAVE`), o usar pgAdmin para copiar clave
- **Base en uso al recrear copia:** `SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname='foodstore_copia' AND pid <> pg_backend_pid();` luego `DROP DATABASE`
- **Backup no restaura:** verificar con `pg_restore --list` antes de confiar

---
*Protocolo commiteado antes de Parte 1 — sin este archivo no se continúa (PDF p3).*
