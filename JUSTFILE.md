# Task Runner Guide

## 🔧 Overview

OpenThreat uses [`just`](https://github.com/casey/just) as its command runner. It consolidates all common development tasks (setup, dev server, testing, linting, infrastructure) into a single `justfile` at the project root.

Unlike `make`, `just` has no build semantics — it is a straightforward, cross-platform script runner with clean syntax and helpful error messages.

---

## 📦 Installation

### macOS

```bash
# Homebrew (recommended)
brew install just

# Cargo (if Rust is installed)
cargo install just
```

### Windows

```powershell
# Winget (built-in on Windows 11)
winget install Casey.Just

# Scoop
scoop install just

# Chocolatey
choco install just

# Cargo (if Rust is installed)
cargo install just
```

### Linux

```bash
# Debian / Ubuntu
curl --proto '=https' --tlsv1.2 -sSf https://just.systems/install.sh | bash -s -- --to /usr/local/bin

# Arch Linux
pacman -S just

# Fedora / RHEL (COPR)
dnf copr enable ianhattendorf/just && dnf install just

# Cargo (universal)
cargo install just
```

Verify the installation:

```bash
just --version
```

---

## 🚀 Recipes

List all available recipes at any time:

```bash
just
# or
just --list
```

---

### `just setup`

Full one-time project setup. Run this after cloning the repository.

This will:
- ✅ Create a Python virtual environment (`.venv/`)
- ✅ Copy `.env.example` → `.env` (if not already present)
- ✅ Install Python dependencies (`requirements.txt`)
- ✅ Install Node dependencies (`frontend/`)
- ✅ Start PostgreSQL + Redis via Docker Compose
- ✅ Wait for container healthchecks to pass
- ✅ Run all Alembic migrations

```bash
just setup
```

---

### `just dev`

Starts the backend (`:8000`) and frontend (`:3000`) simultaneously in a single terminal.

```bash
just dev
```

Press `Ctrl+C` to stop both processes.

---

### `just test`

Runs the full test suite with a coverage report.

```bash
# Full suite + coverage
just test

# Single file or directory
just test TARGET=tests/test_api_vulnerabilities.py
```

The HTML coverage report is saved to `htmlcov/index.html`.

---

### `just check`

Auto-formats the code (black + isort) and runs the linter (flake8).

```bash
just check
```

---

### `just infra`

Manages the Docker infrastructure (PostgreSQL + Redis).

```bash
just infra        # Start Postgres + Redis (default)
just infra up     # Explicit start
just infra down   # Stop containers
just infra clean  # Stop containers and delete volumes
```

> ⚠️ `just infra clean` deletes all database data and cannot be undone.

---

### `just migrate`

Runs all pending Alembic migrations against the database.

```bash
just migrate
```

---

### `just worker`

Starts the Celery worker for background tasks (CVE fetching, LLM processing).

```bash
just worker
```

See [docs/CELERY_GUIDE.md](docs/CELERY_GUIDE.md) for details on background task configuration.

---

## 🖥️ Platform Notes

The `justfile` supports both Unix (macOS/Linux) and Windows out of the box. Each recipe has a `[unix]` and a `[windows]` variant:

| | Unix | Windows |
|-|------|---------|
| **Shell** | `#!/usr/bin/env sh` | `#!powershell` (PowerShell 5+) |
| **venv path** | `.venv/bin/` | `.venv\Scripts\` |
| **Process management** | `trap` + `&` + `wait` | `Start-Process` + `Wait-Process` |

No additional configuration is needed — `just` detects the OS automatically.
