# infra-hares

Orquestación e infraestructura del stack **HARE-S** (Gestión y Catálogo de Pruebas de Lectura y Rendimiento Escolar).

Aquí vive **toda la orquestación**: el `docker-compose` que levanta los 5 servicios, la configuración de pgAdmin, las variables de entorno del stack y la guía de despliegue. No contiene código de aplicación.

## Requisito: carpetas hermanas

Los 4 repos deben estar clonados como carpetas hermanas en cada máquina donde se ejecute `docker compose`:

```text
HARE-S/
├── back-hares/        # API Flask + su Dockerfile
├── front-hares/       # SPA Vue + su Dockerfile
├── proxy-hares/       # reverse proxy nginx + su Dockerfile
└── infra-hares/       # este repo: orquestación
```

## Servicios

| Servicio | Imagen | Función |
|---|---|---|
| `database` | `postgres:18-alpine` | Persistencia relacional |
| `backend` | Propia (`../back-hares`) | API REST (Flask + Gunicorn) |
| `frontend` | Propia (`../front-hares`) | Sirve la interfaz estática |
| `proxy` | Propia (`../proxy-hares`) | Único punto de entrada |
| `import` | Propia (`../back-hares`) | Carga de datos maestros (perfil tools) |
| `pgadmin` | `dpage/pgadmin4` | Administración BBDD (perfil tools) |

## Uso

```bash
# Red externa previa (solo la primera vez)
docker network create public

# Copiar variables de entorno
cp .env.example .env     # y rellenar los valores

# Construir y levantar
docker compose up -d

# Configurar host para pgAdmin (perfil tools)
docker compose --profile tools up -d pgadmin
```

Documentación detallada: `guide/deployment.md`.

### Guía rápida de comandos

> ⚠️ `docker compose ...` **solo funciona desde `infra-hares`**. En `back-hares`/`front-hares`/`proxy-hares` no hay `docker-compose.yml` y dará `no configuration file provided`.

| Quieres... | Comando | ¿Desde dónde? |
|---|---|---|
| Levantar el stack | `docker compose up -d --build` | `infra-hares` |
| Ver el stack del proyecto | `docker compose ps` | `infra-hares` |
| Ver TODOS los contenedores | `docker ps` | Cualquier carpeta |
| Entrar a un contenedor | `docker exec -it hares_backend bash` | Cualquier carpeta |
| Parar (sin borrar datos) | `docker compose down` | `infra-hares` |
| Parar borrando datos ⚠️ | NO usar `docker compose down -v` | — |

Hoja completa: `guide/comandos.md`.

## Estructura

```
infra-hares/
├── docker-compose.yml          # orquesta todo el stack
├── docker-compose.override.yml # puertos de desarrollo + db-test
├── .env.example                # variables de entorno (placeholders)
├── pgadmin/
│   └── servers.json            # conexión preconfigurada a database
├── scripts/
│   └── run_tests.sh            # levanta db-test y ejecuta pytest del backend
└── guide/
    └── deployment.md           # instrucciones de despliegue del stack
```