# Guía rápida de comandos del stack (HARE-S)

Toda la orquestación vive en **`infra-hares`**. Los comandos de `docker compose` **solo funcionan desde esa carpeta**.

```text
HARE-S/
├── back-hares/        # API Flask (solo código + Dockerfile)
├── front-hares/       # SPA Vue (solo código + Dockerfile)
├── proxy-hares/       # reverse proxy nginx (solo código + Dockerfile)
└── infra-hares/       # ← AQUÍ se ejecuta docker compose
```

---

## Levantar el stack (lo único imprescindible)

```bash
cd infra-hares
docker compose up -d --build
```

- `-d`: corre en segundo plano (la terminal queda libre).
- `--build`: reconstruye las imágenes al cambiar código (recomendado tras `git pull`).

## Ver si está todo arriba

| Quieres... | Comando | ¿Desde dónde? |
|---|---|---|
| Ver el stack del proyecto | `docker compose ps` | **Solo en `infra-hares`** |
| Ver TODOS los contenedores activos | `docker ps` | Cualquier carpeta |
| Ver los proyectos compose existentes | `docker compose ls` | Cualquier carpeta |

> ⚠️ En `back-hares` NO existe `docker-compose.yml`: `docker compose ps` allí falla con
> `no configuration file provided`. No es un error: es que ahí no hay orquestación.
> Usa `docker ps` para ver los contenedores desde cualquier sitio.

## Estado esperado

```
hares_backend      Up     API (puerto 5000)
hares_database     Up     PostgreSQL (puerto 5433)
hares_frontend     Up     Interfaz (puerto 80 interno)
hares_proxy        Up     Entrada única (puerto 80)
infra-hares-db-test-1 Up  BBDD de tests (db-test)
```

## Comprobar que responde

```bash
curl http://localhost/api/health   # backend → 200
curl http://localhost/             # frontend → 200
```

## Opciones por servicio

```bash
# Logs en vivo de un servicio (backend/frontend/proxy/database)
docker compose logs -f backend

# Reiniciar un servicio
docker compose restart backend

# Entrar a la consola de un contenedor
docker exec -it hares_backend bash
```

## Parar y reiniciar

```bash
# Parar todo (los datos NO se borran)
docker compose down

# Parar y borrar contenedores + imágenes + volúmenes (LOS DATOS SE PIERDEN)
# ⚠️ NO usar salvo que quieras resetear la base de datos
docker compose down -v
```

## Herramientas (perfil `tools`)

```bash
# pgAdmin (http://127.0.0.1:5050)
docker compose --profile tools up -d pgadmin

# Tests del backend (levanta db-test y ejecuta pytest)
./scripts/run_tests.sh
```

## Errores frecuentes

| Síntoma | Causa | Solución |
|---|---|---|
| `no configuration file provided` | Estás en un repo sin compose | `cd infra-hares` o usa `docker ps` |
| Puerto 80/5000 ocupado | Otro contenedor viejo sigue vivo | `docker ps` y parar el antiguo |
| `network public not found` | La red externa no existe | `docker network create public` |
| Tardan en estar "healthy" | PostgreSQL aún inicializa | Esperar ~15 s o `docker compose ps` |