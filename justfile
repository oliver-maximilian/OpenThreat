# Pfad zum venv-Bin-Verzeichnis
venv_bin := ".venv/bin"

# Zeige alle verfügbaren Rezepte
default:
    @just --list

# Erstellt .venv falls nicht vorhanden
venv-create:
    #!/usr/bin/env sh
    if [ ! -d .venv ]; then
        echo "Erstelle Python-venv in .venv ..."
        python3 -m venv .venv
        echo "✓ .venv erstellt"
    else
        echo "✓ .venv existiert bereits"
    fi

# Kopiert .env.dist nach .env + stellt sicher dass .venv existiert
init: venv-create
    #!/usr/bin/env sh
    if [ -f .env ]; then
        echo ".env existiert bereits – nichts geändert."
        echo "Zum Zurücksetzen: just init-force"
    else
        cp .env.dist .env
        echo ".env wurde aus .env.dist erstellt."
        echo "Bitte prüfe die Werte in .env, besonders SECRET_KEY."
    fi

# Überschreibt .env immer mit .env.dist
init-force:
    cp .env.dist .env
    @echo ".env wurde (neu) aus .env.dist erstellt."

# Startet Postgres + Redis im Hintergrund
infra-up:
    #!/usr/bin/env sh
    docker-compose -f docker-compose.dev.yml up -d postgres redis
    echo "Warte auf Healthchecks..."
    for container in openthreat-db openthreat-redis; do
        i=0
        while ! docker inspect "$container" 2>/dev/null | grep -q '"Status": "healthy"'; do
            i=$((i + 1))
            if [ $i -ge 30 ]; then
                echo "Timeout: $container ist nicht healthy geworden." >&2
                exit 1
            fi
            sleep 1
        done
        echo "✓ $container ist healthy"
    done

# Stoppt und entfernt Infrastruktur-Container
infra-down:
    docker-compose -f docker-compose.dev.yml down

# Stoppt und löscht auch die Volumes (Achtung: alle DB-Daten gehen verloren)
infra-clean:
    docker-compose -f docker-compose.dev.yml down -v

# Installiert Python-Abhängigkeiten in .venv
backend-install: venv-create
    {{venv_bin}}/pip install --upgrade pip
    {{venv_bin}}/pip install -r requirements.txt

# Führt Datenbankmigrationen aus
migrate:
    {{venv_bin}}/alembic upgrade head

# Startet den FastAPI-Entwicklungsserver
backend-dev:
    {{venv_bin}}/uvicorn backend.main:app --reload --host 0.0.0.0 --port 8000

# Startet den Celery-Worker
worker:
    {{venv_bin}}/celery -A backend.celery_app worker --loglevel=info

# Installiert Node-Abhängigkeiten
frontend-install:
    cd frontend && npm install

# Startet den Next.js-Entwicklungsserver
frontend-dev:
    cd frontend && npm run dev

# Baut das Frontend für Produktion
frontend-build:
    cd frontend && npm run build

# Führt alle Tests aus
test:
    {{venv_bin}}/pytest

# Tests mit Coverage-Report
test-cov:
    {{venv_bin}}/pytest --cov=backend --cov-report=term-missing --cov-report=html

# Nur einen bestimmten Test oder Ordner ausführen (Beispiel: just test-only tests/test_api_vulnerabilities.py)
test-only target:
    {{venv_bin}}/pytest {{target}} -v

# Formatiert Backend-Code
fmt:
    {{venv_bin}}/black backend/ tests/
    {{venv_bin}}/isort backend/ tests/

# Lint-Check (ohne Änderungen)
lint:
    {{venv_bin}}/flake8 backend/ tests/
    {{venv_bin}}/black --check backend/ tests/
    {{venv_bin}}/isort --check-only backend/ tests/

# Vollständiger Quickstart: init → Infra → Migration → Dev-Server
quickstart: init infra-up backend-install migrate frontend-install
    @echo ""
    @echo "✓ Infrastruktur läuft"
    @echo "✓ Migrationen angewendet"
    @echo "✓ Abhängigkeiten installiert"
    @echo ""
    @echo "Starte jetzt in zwei separaten Terminals:"
    @echo "  just backend-dev"
    @echo "  just frontend-dev"
    @echo ""
    @echo "Backend:  http://localhost:8000"
    @echo "API-Docs: http://localhost:8000/docs"
    @echo "Frontend: http://localhost:3000"

# Quickstart komplett in einer Session (blockiert – Ctrl+C beendet alles)
quickstart-run: init infra-up backend-install migrate frontend-install
    #!/usr/bin/env sh
    trap 'kill 0' INT TERM
    .venv/bin/uvicorn backend.main:app --reload --host 0.0.0.0 --port 8000 &
    cd frontend && npm run dev &
    wait
