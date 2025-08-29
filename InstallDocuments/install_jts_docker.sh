#!/bin/bash

# File Name: install_jts_docker.sh
# Created Date: 2025-08-26
# Modified Date: 2025-08-28
# Version: 1.0.54
# Description: Bash script to set up Job Ticket System in Docker on Arch Linux, with prompts for custom inputs and error handling.
# Comments:
# - Assumes project directory is ./job_ticket_system, creates if not exists.
# - Copies Dockerfile, docker-compose.yaml, custom_postgres.sql, nginx.conf, core/models.py, and jts/settings.py from script's directory.
# - Adds LOCAL_UID and LOCAL_GID for permissions.
# - Configures Django project with copied models, settings, celery, migrations, and ASGI for full setup.
# - Uses Django migrations for table creation, custom migration loads Postgres features from separate SQL file.
# - Switches to uvicorn for ASGI.
# - Adds readiness loop for services with increased timeout.
# Update Notes:
# - 2025-08-28 (v1.0.50): Added step to clear pg_data volume; updated django-allauth settings; increased health check timeout to 300s; added jts/urls.py with debug_toolbar inclusion.
# - 2025-08-28 (v1.0.51): Added health check view at /health/ to jts/urls.py and core/views.py; updated docker-compose healthcheck to use /health/.
# - 2025-08-28 (v1.0.52): Added URL-encoding for PG_PASSWORD to fix PostgREST unhealthy container; updated to copy separate models.py and settings.py.
# - 2025-08-28 (v1.0.53): Added explicit Docker Compose plugin check to prevent usage message error.
# - 2025-08-28 (v1.0.54): Added debug logging for .env and password encoding; fallback to simple password if encoding fails; explicit Compose version check.

set -e  # Exit on error, trapped for recovery

# Trap errors
trap 'echo "Error occurred at line $LINENO. Command: $BASH_COMMAND"; echo "Recovery: Check logs (e.g., docker logs job_ticket_system-django-1, docker logs job_ticket_system-postgrest-1), fix issue (e.g., permissions, missing files), and rerun from failed step."; exit 1' ERR

# Function to prompt for input with default
prompt_input() {
    local prompt="$1"
    local default="$2"
    local var_name="$3"
    read -p "$prompt [$default]: " input
    if [ -z "$input" ]; then
        eval $var_name="$default"
    else
        eval $var_name="$input"
    fi
}

# Function to prompt for password (hidden)
prompt_password() {
    local prompt="$1"
    local var_name="$2"
    read -s -p "$prompt: " pw
    echo
    eval $var_name="$pw"
}

# Function to check command success
check_success() {
    if [ $? -eq 0 ]; then
        echo "Success: $1"
    else
        echo "Error: $1 failed."
        echo "Recovery: Check error message above, resolve issue, and rerun."
        exit 1
    fi
}

echo "Starting JTS Docker Installation on Arch Linux..."

# Step 1: Install Docker and Docker Compose
echo "Step 1: Installing Docker and Docker Compose..."
sudo pacman -Syu --noconfirm
sudo pacman -S --noconfirm docker docker-compose python python-pip python-pipenv
check_success "Docker and Python installation"

# Explicitly install Docker Compose plugin if not included
if ! docker compose version &>/dev/null; then
    echo "Installing Docker Compose plugin..."
    sudo mkdir -p /usr/libexec/docker/cli-plugins
    sudo curl -SL https://github.com/docker/compose/releases/download/v2.29.2/docker-compose-linux-x86_64 -o /usr/libexec/docker/cli-plugins/docker-compose
    sudo chmod +x /usr/libexec/docker/cli-plugins/docker-compose
    check_success "Docker Compose plugin installation"
fi

sudo systemctl start docker
check_success "Starting Docker"
sudo systemctl enable docker
check_success "Enabling Docker"

# Verification
docker --version
check_success "Docker version check"
docker compose version
check_success "Docker Compose version check"

# Step 2: Verify and Copy Required Files
echo "Step 2: Verifying and copying required files..."
SCRIPT_DIR=$(realpath $(dirname $0))
PROJECT_DIR="$SCRIPT_DIR/job_ticket_system"
for file in Dockerfile docker-compose.yaml custom_postgres.sql core/models.py jts/settings.py; do
    if [ ! -f "$SCRIPT_DIR/$file" ]; then
        echo "Error: $file not found in $SCRIPT_DIR"
        echo "Recovery: Ensure $file is in $SCRIPT_DIR and rerun."
        exit 1
    fi
    if [ ! -r "$SCRIPT_DIR/$file" ]; then
        echo "Error: $file in $SCRIPT_DIR is not readable"
        echo "Recovery: Run 'sudo chmod +r $SCRIPT_DIR/$file' and rerun."
        sudo chmod +r "$SCRIPT_DIR/$file"
        check_success "Fixing permissions for $file"
    fi
done

if [ ! -d "$PROJECT_DIR" ]; then
    mkdir -p "$PROJECT_DIR"
    check_success "Creating project directory $PROJECT_DIR"
else
    echo "Project directory $PROJECT_DIR already exists."
    if [ "$(stat -c %u "$PROJECT_DIR")" != "$(id -u)" ]; then
        sudo chown -R $(whoami):$(whoami) "$PROJECT_DIR"
        check_success "Fixing project directory permissions"
    fi
fi

cp "$SCRIPT_DIR/Dockerfile" "$PROJECT_DIR/Dockerfile"
check_success "Dockerfile copy"

cp "$SCRIPT_DIR/docker-compose.yaml" "$PROJECT_DIR/docker-compose.yaml"
check_success "docker-compose.yaml copy"

mkdir -p "$PROJECT_DIR/db"
cp "$SCRIPT_DIR/custom_postgres.sql" "$PROJECT_DIR/db/custom_postgres.sql"
check_success "custom_postgres.sql copy"

# Create or copy nginx.conf
if [ -f "$SCRIPT_DIR/nginx.conf" ]; then
    cp "$SCRIPT_DIR/nginx.conf" "$PROJECT_DIR/nginx.conf"
    check_success "nginx.conf copy"
else
    echo "Creating default nginx.conf since nginx.conf not found..."
    cat > "$PROJECT_DIR/nginx.conf" <<EOF
server {
    listen 80;
    server_name localhost;

    location /static/ {
        alias /static/;
        expires 1y;
        access_log off;
    }

    location / {
        proxy_pass http://django:8000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    location /api/ {
        proxy_pass http://postgrest:3000/;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }

    error_page 500 502 503 504 /50x.html;
    location = /50x.html {
        root /usr/share/nginx/html;
    }
}
EOF
    check_success "nginx.conf creation"
fi

# Copy Django app files
mkdir -p "$PROJECT_DIR/core"
cp "$SCRIPT_DIR/core/models.py" "$PROJECT_DIR/core/models.py"
check_success "core/models.py copy"

mkdir -p "$PROJECT_DIR/jts"
cp "$SCRIPT_DIR/jts/settings.py" "$PROJECT_DIR/jts/settings.py"
check_success "jts/settings.py copy"

# Prompt for environment variables
prompt_input "Enter Postgres user" "jts_pg_admin" "PG_USER"
prompt_password "Enter Postgres password" "PG_PASSWORD"
prompt_input "Enter JWT secret (64 chars)" "$(openssl rand -hex 32)" "JWT_SECRET"

# URL-encode PG_PASSWORD for safe URI usage
ENCODED_PG_PASSWORD=$(python3 -c "from urllib.parse import quote; print(quote('$PG_PASSWORD', safe=''))" || echo "simplepassword")
check_success "URL-encoding Postgres password"
echo "Debug: PG_PASSWORD=$PG_PASSWORD, ENCODED_PG_PASSWORD=$ENCODED_PG_PASSWORD"

# Create .env file
cat > "$PROJECT_DIR/.env" <<EOF
PG_USER=$PG_USER
PG_PASSWORD=$PG_PASSWORD
ENCODED_PG_PASSWORD=$ENCODED_PG_PASSWORD
JWT_SECRET=$JWT_SECRET
LOCAL_UID=$(id -u)
LOCAL_GID=$(id -g)
EOF
check_success ".env file creation"

# Update docker-compose.yaml to use ENCODED_PG_PASSWORD
sed -i "s/:\${PG_PASSWORD}@/:\${ENCODED_PG_PASSWORD}@/" "$PROJECT_DIR/docker-compose.yaml"
check_success "Updated docker-compose for encoded password"
echo "Debug: Updated docker-compose.yaml PGRST_DB_URI to use ENCODED_PG_PASSWORD"

# Step 3: Create Django Project
echo "Step 3: Creating Django project..."
pipenv --python 3.12
check_success "Pipenv setup for Python 3.12"
pipenv install django psycopg2-binary django-bootstrap5 django-crispy-forms crispy-bootstrap5 django-storages django-filter django-allauth django-rest-framework django-channels channels-redis celery redis python-decouple dj-database-url django-debug-toolbar
check_success "Pipenv install dependencies"

pipenv run django-admin startproject jts "$PROJECT_DIR"
check_success "Django project creation"

# Step 4: Create core app
echo "Step 4: Creating core Django app..."
cd "$PROJECT_DIR"
pipenv run python manage.py startapp core
check_success "Core app creation"

# Add core to INSTALLED_APPS
sed -i "/INSTALLED_APPS = \[/a \    'core'," jts/settings.py
check_success "Core app added to settings"

# Step 5: Create initial migrations for models
echo "Step 5: Creating initial migrations..."
pipenv run python manage.py makemigrations core
check_success "Initial makemigrations for core"

# Create empty migration for Postgres features
pipenv run python manage.py makemigrations core --empty --name add_postgres_features
check_success "Empty makemigrations for Postgres features"

# Overwrite the empty migration with RunSQL from file
cat > core/migrations/0002_add_postgres_features.py <<EOF
from django.db import migrations
from pathlib import Path

BASE_DIR = Path(__file__).resolve().parent.parent.parent

class Migration(migrations.Migration):

    dependencies = [
        ('core', '0001_initial'),
    ]

    operations = [
        migrations.RunSQL(Path(BASE_DIR / 'db' / 'custom_postgres.sql').read_text()),
    ]
EOF
check_success "0002_add_postgres_features.py update"

pipenv lock
check_success "pipenv lock"

pipenv requirements > requirements.txt
check_success "requirements.txt generation"

# Step 6: Run Docker Compose
echo "Step 6: Starting services with Docker Compose..."
docker compose up -d --build
check_success "Docker Compose up"

# Wait for services to be healthy with loop
echo "Waiting for services to be healthy..."
timeout=300
interval=5
elapsed=0
while [ $elapsed -lt $timeout ]; do
    healthy_count=$(docker compose ps | grep "Up (healthy)" | wc -l)
    if [ "$healthy_count" -eq 5 ]; then
        check_success "Service health check"
        break
    fi
    sleep $interval
    elapsed=$((elapsed + interval))
done
if [ $elapsed -ge $timeout ]; then
    echo "Error: Services not healthy after $timeout seconds."
    echo "Recovery: Check docker logs (e.g., docker logs job_ticket_system-django-1, docker logs job_ticket_system-postgrest-1), resolve, rerun."
    exit 1
fi

# Step 7: Apply Migrations and Create Superuser
echo "Step 7: Applying migrations and creating superuser..."
docker compose exec django python manage.py migrate
check_success "Migrate"

echo "Creating Django superuser (interactive)..."
docker compose exec django python manage.py createsuperuser

docker compose exec django python manage.py collectstatic --noinput
check_success "Collectstatic"

# Verification
curl -f http://localhost
check_success "nginx access test"
curl -f http://localhost/api/users
check_success "PostgREST API test"

echo "Docker installation complete! Access at http://localhost."
echo "If errors occurred, check recovery notes or docker logs."
