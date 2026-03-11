# OS-aware venv paths
venv_bin := if os_family() == "windows" { ".venv/Scripts" } else { ".venv/bin" }
python    := if os_family() == "windows" { "python" }        else { "python3" }

# List all available recipes
default:
    @just --list

# ---------------------------------------------------------------------------
# setup
# ---------------------------------------------------------------------------

# setup -> venv, .env, pip+npm install, infra, migrations
[unix]
setup:
    #!/usr/bin/env sh
    set -e

    if [ ! -d .venv ]; then
        echo "==> Creating Python venv..."
        python3 -m venv .venv
    fi

    if [ -f .env ]; then
        echo "==> .env already exists, skipping."
    else
        cp .env.example .env
        echo "==> .env created from .env.example - review SECRET_KEY before going to prod."
    fi

    echo "==> Installing Python dependencies..."
    .venv/bin/pip install --upgrade pip --quiet
    .venv/bin/pip install -r requirements.txt --quiet

    echo "==> Installing Node dependencies..."
    cd frontend && npm install --silent && cd ..

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
        echo "    v $container"
    done

    echo "==> Running migrations..."
    .venv/bin/alembic upgrade head

    echo ""
    echo "Setup complete. Run 'just dev' to start."

# setup -> venv, .env, pip+npm install, infra, migrations
[windows]
setup:
    #!powershell
    $ErrorActionPreference = 'Stop'

    if (-not (Test-Path .venv)) {
        Write-Host "==> Creating Python venv..."
        python -m venv .venv
    }

    if (Test-Path .env) {
        Write-Host "==> .env already exists, skipping."
    } else {
        Copy-Item .env.example .env
        Write-Host "==> .env created from .env.example - review SECRET_KEY before going to prod."
    }

    Write-Host "==> Installing Python dependencies..."
    .venv\Scripts\pip install --upgrade pip --quiet
    .venv\Scripts\pip install -r requirements.txt --quiet

    Write-Host "==> Installing Node dependencies..."
    Set-Location frontend; npm install --silent; Set-Location ..

    Write-Host "==> Starting Postgres + Redis..."
    docker-compose -f docker-compose.dev.yml up -d postgres redis

    Write-Host "==> Waiting for healthchecks..."
    foreach ($container in @("openthreat-db", "openthreat-redis")) {
        $i = 0
        while ($true) {
            $health = (docker inspect $container 2>$null | ConvertFrom-Json).State.Health.Status
            if ($health -eq "healthy") { break }
            $i++
            if ($i -ge 30) { Write-Error "Timeout: $container did not become healthy."; exit 1 }
            Start-Sleep 1
        }
        Write-Host "    v $container"
    }

    Write-Host "==> Running migrations..."
    .venv\Scripts\alembic upgrade head

    Write-Host ""
    Write-Host "Setup complete. Run 'just dev' to start."

# ---------------------------------------------------------------------------
# dev
# ---------------------------------------------------------------------------

# dev -> start backend + frontend in one session (blocking, Ctrl+C stops all)
[unix]
[no-exit-message]
dev:
    #!/usr/bin/env sh
    trap 'kill 0' INT TERM
    echo "==> Starting backend on :8000 and frontend on :3000"
    .venv/bin/uvicorn backend.main:app --reload --host 0.0.0.0 --port 8000 &
    cd frontend && npm run dev &
    wait

# dev -> start backend + frontend in parallel (Ctrl+C stops all)
[windows]
[no-exit-message]
dev:
    #!powershell
    Write-Host "==> Starting backend on :8000 and frontend on :3000"
    $b = Start-Process -NoNewWindow -PassThru powershell -ArgumentList "-c .venv\Scripts\uvicorn backend.main:app --reload --host 0.0.0.0 --port 8000"
    $f = Start-Process -NoNewWindow -PassThru powershell -ArgumentList "-c Set-Location frontend; npm run dev"
    try { Wait-Process $b.Id, $f.Id }
    finally { Stop-Process -Id $b.Id, $f.Id -ErrorAction SilentlyContinue }

# ---------------------------------------------------------------------------
# test
# ---------------------------------------------------------------------------

TARGET := ""

# test -> full suite with coverage; use TARGET=tests/foo.py for a single file
[unix]
test:
    #!/usr/bin/env sh
    if [ -n "{{TARGET}}" ]; then
        echo "==> Running tests: {{TARGET}}"
        .venv/bin/pytest {{TARGET}} -v
    else
        echo "==> Running full test suite with coverage..."
        .venv/bin/pytest --cov=backend --cov-report=term-missing --cov-report=html
        echo "==> Coverage report saved to htmlcov/index.html"
    fi

# test -> full suite with coverage; use TARGET=tests/foo.py for a single file
[windows]
test:
    #!powershell
    if ("{{TARGET}}" -ne "") {
        Write-Host "==> Running tests: {{TARGET}}"
        .venv\Scripts\pytest {{TARGET}} -v
    } else {
        Write-Host "==> Running full test suite with coverage..."
        .venv\Scripts\pytest --cov=backend --cov-report=term-missing --cov-report=html
        Write-Host "==> Coverage report saved to htmlcov/index.html"
    }

# ---------------------------------------------------------------------------
# check
# ---------------------------------------------------------------------------

# check -> auto-format (black+isort) then lint (flake8)
[unix]
check:
    #!/usr/bin/env sh
    set -e
    echo "==> Formatting with black + isort..."
    .venv/bin/black backend/ tests/
    .venv/bin/isort backend/ tests/
    echo "==> Linting with flake8..."
    .venv/bin/flake8 backend/ tests/
    echo "All checks passed."

# check -> auto-format (black+isort) then lint (flake8)
[windows]
check:
    #!powershell
    $ErrorActionPreference = 'Stop'
    Write-Host "==> Formatting with black + isort..."
    .venv\Scripts\black backend/ tests/
    .venv\Scripts\isort backend/ tests/
    Write-Host "==> Linting with flake8..."
    .venv\Scripts\flake8 backend/ tests/
    Write-Host "All checks passed."

# ---------------------------------------------------------------------------
# infra
# ---------------------------------------------------------------------------

# infra -> manage Docker infra: just infra [up|down|clean]
[unix]
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
            echo "    v $container"
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

# infra -> manage Docker infra: just infra [up|down|clean]
[windows]
infra action="up":
    #!powershell
    switch ("{{action}}") {
        "up" {
            docker-compose -f docker-compose.dev.yml up -d postgres redis
            Write-Host "==> Waiting for healthchecks..."
            foreach ($container in @("openthreat-db", "openthreat-redis")) {
                $i = 0
                while ($true) {
                    $health = (docker inspect $container 2>$null | ConvertFrom-Json).State.Health.Status
                    if ($health -eq "healthy") { break }
                    $i++
                    if ($i -ge 30) { Write-Error "Timeout: $container did not become healthy."; exit 1 }
                    Start-Sleep 1
                }
                Write-Host "    v $container"
            }
        }
        "down"  { docker-compose -f docker-compose.dev.yml down }
        "clean" {
            Write-Host "WARNING: this will delete all database volumes."
            docker-compose -f docker-compose.dev.yml down -v
        }
        default { Write-Error "Unknown action: {{action}}. Use up | down | clean."; exit 1 }
    }

# ---------------------------------------------------------------------------
# migrate / worker
# ---------------------------------------------------------------------------

# migrate -> run pending Alembic migrations
[unix]
migrate:
    .venv/bin/alembic upgrade head

# migrate -> run pending Alembic migrations
[windows]
migrate:
    .venv\Scripts\alembic upgrade head

# worker -> start Celery worker
[unix]
worker:
    .venv/bin/celery -A backend.celery_app worker --loglevel=info

# worker -> start Celery worker
[windows]
worker:
    .venv\Scripts\celery -A backend.celery_app worker --loglevel=info

