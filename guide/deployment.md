# Instrucciones de despliegue

> Guía de despliegue del **stack completo HARE-S** — Programa de Gestión de Mejora de Comprensión Lectora (Peñascal).
> El `docker-compose.yml` de este repositorio (`infra-hares`) levanta `database`, `backend`, `import`, `frontend` y `proxy`.
> Lo que aquí se afirma se considera la configuración correcta. Si algo cambia en el código, se actualiza este documento en el mismo commit.

---

## 0. Una condición derivada de los repos git

`back-hares`, `front-hares` y `proxy-hares` son repositorios git **separados**, pero el compose de `infra-hares` construye el backend, el frontend y el proxy desde sus repos hermanos (`build: ../back-hares`, `build: ../front-hares`, `build: ../proxy-hares`). Por tanto **los cuatro deben estar clonados como carpetas hermanas** en cada máquina donde se ejecute `docker compose`:

```text
HARE-S/
├── back-hares/    # API Flask
├── front-hares/   # interfaz estática
├── proxy-hares/   # reverse proxy (único punto de entrada)
└── infra-hares/   # aquí vive docker-compose.yml
```

Quien clone solo `infra-hares` no podrá construir los servicios `frontend`, `backend` ni `proxy`: los `Dockerfile` se versionan en sus propios repos.

Además, el proxy pertenece a la red externa `public` (`external: true` en Compose). Antes del primer `up` hay que crearla:

```bash
docker network create public   # solo la primera vez
```

Las imágenes del stack se eligen por variables de entorno (`POSTGRES_IMAGE`, `NGINX_IMAGE`); la imagen de Python está fijada en `back-hares/Dockerfile` (`python:3.14-alpine`). Los valores por defecto son las imágenes oficiales; las `dhi.io/*` están documentadas en `.env.example` para cuando la organización tenga acceso al registro.

---

## 1. Objetivo

Poner en producción los servicios de servidor —base de datos, API, importador y herramienta de administración— mediante contenedores, de forma reproducible y sin pasos manuales no documentados.

`frontend` y `proxy` aparecen aquí solo como contexto: el backend no se despliega solo, pero su configuración se documenta en la guía del frontend.

El sistema maneja **datos personales de alumnado menor de edad**. Eso condiciona el despliegue en tres puntos que no son negociables: ningún servicio salvo el proxy se expone al exterior, los secretos nunca entran al repositorio, y existe copia de seguridad verificada antes de cualquier despliegue.

---

## 2. Arquitectura desplegada

Cinco servicios sobre cuatro redes:

| Servicio | Imagen | Función | Redes |
|---|---|---|---|
| `database` | `dhi.io/postgresql:18.6-alpine3.24-fips` | Persistencia relacional | `db-network` |
| `backend` | Propia, base `dhi.io/python:3.14.7-alpine3.24-fips` | API REST (Flask + Gunicorn) | `db-network`, `backend-network` |
| `frontend` | Propia, base `dhi.io/nginx:1.31.5-alpine3.24-fips` | Sirve la interfaz estática. **Ver guía del frontend** | `frontend-network` |
| `proxy` | Propia, base `dhi.io/nginx:1.31.5-alpine3.24-fips` | Único punto de entrada. Config en `proxy-hares/nginx.conf` | `public`, `backend-network`, `frontend-network` |
| `import` | Propia, base `dhi.io/python:3.14.7-alpine3.24-fips` | Carga de datos maestros desde fichero | `db-network` |
| `pgadmin` | `dpage/pgadmin4` | Administración de la base de datos. **Bajo perfil, no arranca por defecto** | `db-network` |

**Regla de red:** `public` es la única red externa y solo `proxy` está en ella. `database` no es alcanzable desde `frontend` ni desde el exterior bajo ninguna circunstancia. Si al revisar el `docker-compose.yml` un servicio distinto de `proxy` publica puertos con `ports:`, es un error — **con la única excepción de `pgadmin`, que publica exclusivamente en `127.0.0.1` y está sujeto al apartado 7**.

**Volúmenes:** `data_dir` montado en `/var/lib/postgresql` es el único estado persistente de la aplicación. `pgadmin_data` guarda la configuración de la herramienta de administración y no contiene datos del proyecto.

### Nota sobre las imágenes DHI

Las imágenes `dhi.io/*` son **Docker Hardened Images, un producto de suscripción**. Antes del primer despliegue hay que confirmar que la organización tiene acceso:

```bash
docker pull dhi.io/postgresql:18.6-alpine3.24-fips
```

Si falla por autenticación, hay dos caminos: solicitar el acceso, o sustituir por las imágenes oficiales equivalentes (`postgres:18-alpine`, `python:3.14-alpine`, `nginx:1.31.5-alpine`). **Esa sustitución debe acordarse con el cliente**, porque las DHI fueron una elección suya y la variante `fips` tiene implicaciones de cumplimiento.

En el compose esto se resuelve con variables, sin tocar código: `POSTGRES_IMAGE` y `NGINX_IMAGE` en `.env` (ver `.env.example`). La imagen de Python está fijada en el `Dockerfile`; los valores por defecto son las oficiales, y para activar DHI basta descomentar las líneas comentadas en `.env`.

### Nota sobre Alpine y PostgreSQL

Alpine usa `musl` en vez de `glibc`. El conector de PostgreSQL para Python puede no encontrar rueda precompilada y necesitar compilación en el `Dockerfile`:

```dockerfile
RUN apk add --no-cache --virtual .build-deps gcc musl-dev postgresql-dev \
 && pip install --no-cache-dir -r requirements.txt \
 && apk del .build-deps
```

Instalar y desinstalar las dependencias de compilación en la **misma capa** es lo que evita que acaben en la imagen final.

---

### Contrato con el frontend

El backend se compromete a tres cosas, y el frontend puede darlas por ciertas:

- Toda la API cuelga de **`/api`**. El proxy enruta ese prefijo al backend y el resto al frontend.
- La sesión viaja en **cookie `HttpOnly`**. El frontend no recibe ni maneja ningún token.
- Al no haber sesión válida se devuelve **`401`**, nunca una redirección. Es el frontend quien decide qué hacer con ese `401`.

Cualquier cambio en estos tres puntos se avisa al equipo de interfaz antes de fusionar.

---

## 3. Requisitos previos

Antes de desplegar, comprobar que se dispone de:

- [ ] Docker y Docker Compose v2 en el servidor.
- [ ] Acceso al registro de imágenes (ver apartado anterior).
- [ ] `client_id` y `client_secret` del proyecto de Google Cloud (ver US-51 del backlog).
- [ ] Certificado TLS para el dominio de producción.
- [ ] Fichero `.env` cumplimentado a partir de `.env.example`.
- [ ] Copia de seguridad reciente y **verificada** si ya hay datos en producción.
- [ ] Credenciales de pgAdmin definidas en `.env` (distintas de las de PostgreSQL).

---

## 4. Variables de entorno

**El fichero `.env` nunca se sube al repositorio.** Debe estar en `.gitignore` desde el primer commit. En el repositorio vive únicamente `.env.example`, con las claves y sin los valores.

```bash
# --- Base de datos ---
POSTGRES_DB=comprension_lectora
POSTGRES_USER=app_user
POSTGRES_PASSWORD=            # generar; no reutilizar de otro entorno
DATABASE_URL=postgresql://app_user:${POSTGRES_PASSWORD}@database:5432/comprension_lectora

# --- Aplicación ---
APP_ENV=production            # production | development
SECRET_KEY=                   # generar con: openssl rand -hex 32
SESSION_TYPE=sqlalchemy       # sesión en servidor, NO la cookie firmada de Flask
SESSION_MAX_AGE_MINUTES=120
FLASK_APP=app.app:create_app

# --- Autenticación Google (EP-12) ---
GOOGLE_CLIENT_ID=
GOOGLE_CLIENT_SECRET=
GOOGLE_REDIRECT_URI=https://<dominio-produccion>/api/auth/callback
ALLOWED_HD=grupopenascal.com  # claim hd exigido en el ID token

# --- Desarrollo (US-50) ---
DEV_AUTH_BYPASS=false         # DEBE ser false en producción
```

### Comprobaciones obligatorias al arrancar

La aplicación debe **negarse a arrancar** si:

- Falta cualquier variable sin valor por defecto.
- `APP_ENV=production` y `DEV_AUTH_BYPASS=true` a la vez.
- `SECRET_KEY` tiene menos de 32 bytes.
- `SESSION_TYPE` no está configurado para almacenamiento en servidor.
- `ALLOWED_HD` está vacío.

Un fallo ruidoso al arrancar es preferible a un sistema que levanta con el bypass de autenticación activo. Esto no es defensivo de más: es la diferencia entre un despliegue fallido y una brecha.

> **Cambio respecto al borrador inicial:** el proyecto **no usa JWT**. Se usan sesiones de servidor con cookie `HttpOnly`, `Secure`, `SameSite=Lax`. El motivo está en US-45: revocar un acceso debe ser borrar una fila, no mantener una lista de tokens revocados.
>
> **Y tampoco la sesión por defecto de Flask**, que guarda el estado dentro de la propia cookie firmada. Con ella, cerrar sesión no invalida nada en el servidor y deshabilitar un usuario no corta sus sesiones activas — se incumplen US-45 y US-49. De ahí `SESSION_TYPE=sqlalchemy`.

---

## 5. Procedimiento de despliegue

El orden importa. Los servicios no pueden arrancar en paralelo sin más: el backend necesita que las migraciones hayan corrido, y las migraciones necesitan que PostgreSQL acepte conexiones.

### 5.1 Obtener el código

```bash
git checkout main
git pull origin main
```

Solo se despliega desde `main`. Ver apartado 10.

### 5.2 Construir y levantar

```bash
docker network create public   # solo la primera vez (red externa del proxy)
docker compose build --no-cache
docker compose up -d database
```

Esperar a que la base de datos esté sana antes de continuar:

```bash
docker compose ps database          # STATUS debe ser "healthy"
```

El `healthcheck` del servicio `database` debe estar declarado en el compose:

```yaml
healthcheck:
  test: ["CMD-SHELL", "pg_isready -U ${POSTGRES_USER} -d ${POSTGRES_DB}"]
  interval: 5s
  timeout: 3s
  retries: 10
```

Sin healthcheck, `depends_on` solo garantiza que el contenedor ha arrancado, no que PostgreSQL acepte conexiones. Es la causa más común de fallo intermitente en el primer despliegue.

### 5.3 Inicializar el esquema

> **Estado conocido del historial de migraciones.** El repositorio contiene dos cadenas Alembic independientes (`001..005` y `d759ec76f0af..`) que crean las mismas tablas (`users`, `sessions`, `audit_logs`), por lo que hoy `alembic upgrade head` **no es reproducible** en una base de datos vacía (múltiples cabezas y `create table` duplicados). El bootstrap fiable del esquema es el script que ya usaba el proyecto en local, basado en los modelos (`db.create_all()`), que además registra la función SQL `uuidv7()`:

```bash
docker compose run --rm backend python scripts/init_db.py
```

El script es **aditivo** (no borra tablas existentes ni datos). Se puede repetir con seguridad tras errores. Reparar el historial Alembic (fusión de cabezas) es una mejora pendiente y **fuera de alcance** de este despliegue; ticket/RO pendiente con el tutor.

El arranque del esquema **nunca** se hace automáticamente al levantar el backend: es un paso explícito y controlado para evitar que dos réplicas migren a la vez.

### 5.4 Levantar el resto

```bash
docker compose up -d
docker compose ps
```

Los cinco servicios deben aparecer levantados, salvo `import`, que es un job puntual y no permanece en ejecución.

### 5.5 Apagado

```bash
docker compose down
```

En entornos con Docker rootless donde el apagado falla por permisos:

```bash
bash scripts/docker_down_safe.sh
```

**Nunca usar `docker compose down -v` en producción.** La opción `-v` borra los volúmenes, y con ellos toda la base de datos.

---

## 6. Carga de datos maestros

El servicio `import` es un job puntual que carga datos de prueba anónimos (BE-05): centros, secciones, alumnado, catálogo de pruebas, catálogo mínimo de libros y resultados sintéticos. Sin argumentos usa los CSV por defecto de `data/seeds/`.

```bash
docker compose --profile tools run --rm import
```

Con CSV personalizados:

```bash
docker compose --profile tools run --rm \
  -v /ruta/al/fichero:/data:ro \
  import python -m app.importer --students /data/import_data.csv --tests /data/tests.csv
```

El importador es **idempotente**: se identifica por `external_id`, no por nombre. Reejecutarlo con el mismo fichero no crea duplicados. Si el recuento de filas cambia tras una segunda ejecución, hay un error y debe reportarse.

Formato esperado: CSV con separador `;`, codificación UTF-8, y el campo `sections` como lista separada por comas.

> **Decisión pendiente:** hay dos caminos de escritura a la base de datos —este contenedor y el endpoint de subida de US-10—. Mientras no se unifiquen, ambos deben usar el mismo módulo de validación. Duplicar la lógica de validación garantiza que divergirán.

---

## 7. Administración de la base de datos con pgAdmin

pgAdmin se incluye como herramienta de administración y para acreditar el modelo de datos ante el cliente. **Es el servicio más delicado del despliegue** y merece leer este apartado entero antes de añadirlo al compose.

### 7.1 Por qué requiere cuidado

pgAdmin necesita estar en `db-network` para alcanzar PostgreSQL. Si además se le publica un puerto al exterior, se convierte en **un puente directo desde internet hasta la base de datos**, saltándose toda la segmentación de red del apartado 2. Quien entre en pgAdmin no accede a la aplicación: accede a las tablas, con capacidad de leer y modificar cualquier expediente de alumnado.

Dicho de otra forma: el resto de la arquitectura está diseñada para que nadie llegue a `database` desde fuera, y un `ports: "5050:80"` mal puesto anula ese diseño de un plumazo.

### 7.2 Regla de despliegue

**pgAdmin se levanta bajo un perfil de Compose, no por defecto:**

```yaml
pgadmin:
  image: dpage/pgadmin4:latest
  profiles: ["tools"]              # no arranca con "docker compose up"
  environment:
    PGADMIN_DEFAULT_EMAIL: ${PGADMIN_EMAIL}
    PGADMIN_DEFAULT_PASSWORD: ${PGADMIN_PASSWORD}
    PGADMIN_CONFIG_SERVER_MODE: "True"
    PGADMIN_CONFIG_MASTER_PASSWORD_REQUIRED: "True"
  ports:
    - "127.0.0.1:5050:80"          # solo localhost, nunca 0.0.0.0
  volumes:
    - pgadmin_data:/var/lib/pgadmin
    - ./pgadmin/servers.json:/pgadmin4/servers.json:ro
  networks:
    - db-network
  depends_on:
    database:
      condition: service_healthy
```

Los dos detalles que hacen que esto sea seguro:

- **`profiles: ["tools"]`** — no arranca con un `docker compose up` normal. Hay que pedirlo explícitamente. Un servicio de administración que se levanta solo acaba corriendo en producción sin que nadie lo decidiera.
- **`127.0.0.1:5050:80`** — el puerto se publica **solo en la interfaz local del servidor**, no en todas. Sin ese prefijo, Docker publica en `0.0.0.0` y pgAdmin queda accesible desde internet aunque haya cortafuegos, porque Docker escribe sus propias reglas de `iptables` y se salta `ufw`. Es un fallo muy frecuente y muy silencioso.

### 7.3 Uso

**En desarrollo**, en la máquina local:

```bash
docker compose --profile tools up -d pgadmin
```
Acceder en `http://localhost:5050`.

**En producción**, mediante túnel SSH desde el equipo del administrador:

```bash
ssh -L 5050:localhost:5050 usuario@servidor
```
Y abrir `http://localhost:5050` en el navegador local. Así pgAdmin nunca se expone en internet y el acceso queda sujeto a las credenciales SSH del servidor.

**Apagarlo al terminar:**
```bash
docker compose --profile tools down
```

### 7.4 Configuración de la conexión

Para no reconfigurar la conexión en cada arranque, `pgadmin/servers.json`:

```json
{
  "Servers": {
    "1": {
      "Name": "Comprension Lectora",
      "Group": "Servers",
      "Host": "database",
      "Port": 5432,
      "MaintenanceDB": "comprension_lectora",
      "Username": "app_user",
      "SSLMode": "prefer"
    }
  }
}
```

El host es **`database`**, el nombre del servicio en la red interna de Docker — no `localhost` ni una IP. La contraseña **no se pone aquí**: este fichero sí va al repositorio, así que se introduce a mano en la primera conexión.

### 7.5 Variables adicionales

Añadir a `.env` y a `.env.example`:

```bash
# --- pgAdmin (solo herramienta de administración) ---
PGADMIN_EMAIL=admin@grupopenascal.com
PGADMIN_PASSWORD=              # distinta de la de la base de datos
```

Contraseña **distinta** a la de PostgreSQL. Si son la misma, comprometer pgAdmin equivale a comprometer la base de datos directamente, y se pierde la capacidad de revocar un acceso sin tocar el otro.

### 7.6 Advertencias prácticas

- La imagen `dpage/pgadmin4` **no existe como imagen DHI**. Rompe la homogeneidad del apartado 2; conviene mencionárselo al cliente y fijar una versión concreta en vez de `latest` antes de pasar a producción.
- El contenedor corre como UID 5050. Si el volumen `pgadmin_data` da errores de permisos al arrancar, la causa es esa; se resuelve dejando que Docker gestione el volumen con nombre en lugar de montar un directorio del host.
- pgAdmin es para **consultar y acreditar el modelo**, no para modificar datos de producción a mano. Un `UPDATE` directo se salta las validaciones de la API, el registro de auditoría de US-49 y las reglas de negocio. Si hace falta corregir datos, se hace por la aplicación o por una migración versionada.
- Nunca conectar con el superusuario de PostgreSQL. Usar `app_user`, o crear un usuario de solo lectura para las consultas de comprobación.

---

## 8. Verificación de integridad

Tras cada despliegue, en este orden:

**Servicios**
```bash
docker compose ps
docker compose logs --tail=50 backend
docker compose logs --tail=50 database
```
No debe haber errores de conexión ni reinicios en bucle.

**Conectividad de la API**
```bash
curl -i https://<dominio>/api/health
```
Respuesta esperada: `200 OK`.

**Autenticación** — la comprobación más importante:
```bash
curl -i https://<dominio>/api/students
```
Respuesta esperada: **`401 Unauthorized`**. Si devuelve `200` con datos, el despliegue está expuesto y hay que revertir de inmediato.

**Aislamiento de red**
```bash
docker compose exec frontend sh -c "nc -zv database 5432"
```
Debe **fallar**. Si conecta, la segmentación de redes está mal configurada.

**pgAdmin no expuesto**
```bash
docker compose ps                    # pgadmin NO debe aparecer en un despliegue normal
ss -tlnp | grep 5050                 # si aparece, debe ser 127.0.0.1:5050, nunca 0.0.0.0:5050
```
Desde fuera del servidor, `curl http://<dominio>:5050` debe dar tiempo de espera agotado o conexión rechazada. Si responde con la pantalla de login de pgAdmin, **revertir el despliegue de inmediato**: la base de datos está expuesta a internet.

**Base de datos**
```bash
docker compose exec database psql -U ${POSTGRES_USER} -d ${POSTGRES_DB} -c "\dt"
```
Las 14 tablas de los modelos deben existir (incluidas `sessions`, `flask_session_store`, `audit_logs`, `import_reports`, `user_sections`). El esquema se crea con `scripts/init_db.py` (sección 5.3); **no** se valida con `alembic current`, porque el historial Alembic del repositorio es no reproducible (ver nota de 5.3) y `db.create_all()` es la fuente de verdad del esquema.

**Login completo:** entrar con una cuenta `@grupopenascal.com` y comprobar que una cuenta ajena al dominio es rechazada.

---

## 9. Copias de seguridad

Sin copia verificada no hay despliegue. Con datos de menores, una pérdida no es un incidente técnico sino un problema legal.

**Generar copia**
```bash
docker compose exec -T database \
  pg_dump -U ${POSTGRES_USER} -Fc ${POSTGRES_DB} \
  > backups/backup_$(date +%Y%m%d_%H%M%S).dump
```

**Restaurar**
```bash
docker compose exec -T database \
  pg_restore -U ${POSTGRES_USER} -d ${POSTGRES_DB} --clean --if-exists \
  < backups/backup_XXXXXXXX.dump
```

Reglas:
- Copia automática diaria.
- Copia manual **antes** de cada despliegue que incluya migraciones.
- Las copias se guardan cifradas y fuera del servidor de aplicación.
- **Restauración probada al menos una vez.** Una copia que nunca se ha restaurado no es una copia, es una suposición.
- El directorio `backups/` va en `.gitignore`.

---

## 10. Control de versiones y despliegue

| Rama | Uso |
|---|---|
| `main` | Única rama desplegable. Protegida |
| `develop` | Integración del trabajo del equipo |
| `feature/US-XX-descripcion` | Una rama por historia de usuario |

Condiciones para fusionar a `main`:

- [ ] Los tests de `pytest` pasan.
- [ ] Código formateado y sin errores del linter.
- [ ] Comentarios y nombres de identificadores **en inglés**; documentación de usuario en castellano.
- [ ] Sin secretos, credenciales ni ficheros `.env` en el diff.
- [ ] Revisado por otra persona del equipo.
- [ ] Migraciones incluidas si el esquema cambió.

Cada despliegue a producción se etiqueta:
```bash
git tag -a v1.2.0 -m "Sprint 4: registro de resultados"
git push origin v1.2.0
```
Sin etiquetas no se sabe qué versión está corriendo, y volver atrás pasa a ser arqueología.

---

## 11. Reglas de seguridad

- **Secretos fuera del repositorio.** Si un secreto llega a subirse, no basta con borrarlo en el commit siguiente: hay que **rotarlo**, porque queda en el historial.
- **Solo `proxy` expone puertos.**
- **TLS obligatorio en producción.** Las cookies de sesión llevan `Secure`; sin HTTPS no se envían y el login no funcionará.
- **Contenedores como usuario no privilegiado.** Las imágenes DHI ya lo hacen; no revertirlo con `USER root` en el `Dockerfile`.
- **`DEV_AUTH_BYPASS=false`** en producción, verificado en cada despliegue.
- **Todos los endpoints de `/api/*` exigen sesión**, salvo `/api/health` y las rutas del flujo de autenticación.
- **Registro de auditoría activo** (US-49): accesos, modificaciones de resultados y exportaciones.
- **pgAdmin nunca se levanta por defecto ni se publica en `0.0.0.0`.** Ver apartado 7. Un `docker compose ps` en producción no debería mostrarlo.

---

## 12. Solución de problemas

| Síntoma | Causa probable | Comprobación |
|---|---|---|
| Backend reinicia en bucle | No conecta con la base de datos | `docker compose logs backend`; revisar `DATABASE_URL` y que el host sea `database`, no `localhost` |
| `relation does not exist` | Esquema sin inicializar | Ejecutar `scripts/init_db.py` (sección 5.3) |
| Login redirige y falla | `redirect_uri` no coincide | Debe ser idéntica en `.env` y en Google Cloud, incluido el protocolo |
| Sesión no persiste | Cookie `Secure` sin HTTPS | Comprobar TLS en el proxy |
| Cuentas ajenas al dominio entran | Falta validación del claim `hd` | Revisar el backend: el parámetro `hd` de la petición **no** restringe nada |
| Datos duplicados tras importar | `external_id` no se está usando | Revisar la lógica de US-08 |
| Imagen no descarga | Sin acceso a DHI | Ver apartado 2 |
| `permission denied` al parar | Docker rootless | `bash scripts/docker_down_safe.sh` |
| pgAdmin no conecta con la BBDD | Host mal puesto | En `servers.json` el host es `database`, no `localhost` |
| pgAdmin falla al arrancar por permisos | UID 5050 sobre un directorio del host | Usar el volumen con nombre `pgadmin_data`, no un `bind mount` |
| pgAdmin accesible desde internet | Puerto publicado sin `127.0.0.1:` | Docker escribe sus propias reglas de `iptables` y se salta `ufw`. Corregir el `ports:` y redesplegar |

---

## 13. Decisiones abiertas

Pendientes de confirmar con el cliente. Mientras no se cierren, no se dan por supuestas en el código:

1. **DHI vs imágenes oficiales**, según haya suscripción.
2. **`import` como job puntual o mecanismo permanente** (afecta al apartado 6).
3. **Dominio y certificado TLS de producción.**
4. **Responsable de la consola de Google Cloud** — bloquea EP-12.
5. **Política de retención de datos**: cuánto tiempo se conserva el histórico de un alumno tras su baja.
6. **Quién tiene acceso a pgAdmin en producción** y si se crea un usuario de solo lectura para consultas de comprobación.

---

*Última actualización: 08/09/2026 · Ver `structure.md`, `testing.md` y `workflow.md` de esta misma carpeta, y `frontend/guides/deployment.md` para la interfaz.*
