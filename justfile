# Path to venv bin directory
venv_bin := ".venv/bin"

# List all available recipes
default:
    @just --list

# setup -> venv, .env, pip+npm install, infra, migrations
setup:
    #!/usr/bin/env sh
    set -e

    # .venv
    if [ ! -d .venv ]; then
        echo "==> Creating Python venv..."
        python3 -m venv .venv
    fi

    # .env
    if [ -f .env ]; then
        echo "==> .env already exists, skipping."
    else
        cp .env.example .env
        echo "==> .env created from .env.example – review SECRET_KEY before going to prod."
    fi

    # Python deps
    echo "==> Installing Python dependencies..."
    .venv/bin/pip install --upgrade pip --quiet
    .venv/bin/pip install -r requirements.txt --quiet

    # Node deps
    echo "==> Installing Node dependencies..."
    cd frontend && npm install --silent && cd ..

    # Infrastructure
    echo "==> Starting Postgres + Redis..."
    docker-compose -f docker-compose.dev.yml up -d postgres redis

    echo "==> Waiting for healthchecks..."
    for container in openthreat-db openthreat-redis; do
        i=0
        while ! docker inspect "$container" 2>/dev/null | grep -q '"Status": "healthy"'; do
            i=$((i + 1))
            if [ $i -ge 30 ]; then
                echo "Timeout: $container did not become healthy." >&2
                exit 1
            fi
            sleep 1
        done
        echo "    $container"
    done

    # Migrations
    echo "==> Running migrations..."
    .venv/bin/alembic upgrade head

    echo ""
    echo "Setup complete. Run 'just dev' to start."

# dev -> start backend + frontend in one session (blocking, Ctrl+C stops all)
[no-exit-message]
dev:
    #!/usr/bin/env sh
    trap 'kill 0' INT TERM
    echo "==> Starting backend on :8000 and frontend on :3000"
    .venv/bin/uvicorn backend.main:app --reload --host 0.0.0.0 --port 8000 &
    cd frontend && npm run dev &
    wait

TARGET := ""
# test -> full suite with coverage; use TARGET=tests/foo.py for a single file
test:
    #!/usr/bin/env sh
    source {{venv_bin}}/activate
    if [ -n "{{TARGET}}" ]; then
        echo "==> Running tests: {{TARGET}}"
        pytest {{TARGET}} -v
    else
        echo "==> Running full test suite with coverage..."
        pytest --cov=backend --cov-report=term-missing --cov-report=html
        echo "==> Coverage report saved to htmlcov/index.html"
    fi

# check -> auto-format (black+isort) then lint (flake8)
check:
    #!/usr/bin/env sh
    source {{venv_bin}}/activate
    set -e
    echo "==> Formatting with black + isort..."
    black backend/ tests/
    isort backend/ tests/
    echo "==> Linting with flake8..."
    flake8 backend/ tests/
    echo "All checks passed."

# infra -> manage Docker infra: just infra [up|down|clean]
infra action="up":
    #!/usr/bin/env sh
    case "{{action}}" in
      up)
        docker-compose -f docker-compose.dev.yml up -d postgres redis
        echo "==> Waiting for healthchecks..."
        for container in openthreat-db openthreat-redis; do
            i=0
            while ! docker inspect "$container" 2>/dev/null | grep -q '"Status": "healthy"'; do
                i=$((i + 1))
                if [ $i -ge 30 ]; then
                    echo "Timeout: $container did not become healthy." >&2
                    exit 1
                fi
                sleep 1
            done
            echo "    $container"
        done
        ;;
      down)
        docker-compose -f docker-compose.dev.yml down
        ;;
      clean)
        echo "WARNING: this will delete all database volumes."
        docker-compose -f docker-compose.dev.yml down -v
        ;;
      *)
        echo "Unknown action: {{action}}. Use up | down | clean." >&2
        exit 1
        ;;
    esac

# migrate -> run pending Alembic migrations
migrate:
    #!/usr/bin/env sh
    source {{venv_bin}}/activate
    alembic upgrade head

# worker -> start Celery worker
worker:
    #!/usr/bin/env sh
    source {{venv_bin}}/activate
    celery -A backend.celery_app worker --loglevel=info

