# Makefile de infraestructura — DolyNation
#
# El servicio `backend` de docker-compose.prod.yml se construye desde
# ./backend, que es un clone del repo dolynation-atl-back. Estos targets
# se encargan de clonarlo antes de levantar el stack.

BACKEND_REPO ?= https://github.com/DolyLanguagesORG/dolynation-atl-back.git
BACKEND_DIR  ?= backend

.PHONY: backend up down logs reset

# Clona el backend si no está presente.
backend:
	@test -d $(BACKEND_DIR) || git clone --depth 1 $(BACKEND_REPO) $(BACKEND_DIR)

# Levanta Postgres + backend en producción.
up: backend
	docker compose -f docker-compose.prod.yml up -d --build

down:
	docker compose -f docker-compose.prod.yml down

logs:
	docker compose -f docker-compose.prod.yml logs -f

# Borra volúmenes (datos) y contenedores.
reset:
	docker compose -f docker-compose.prod.yml down -v
