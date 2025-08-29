# File Name: Dockerfile
# Created Date: 2025-08-26
# Modified Date: 2025-08-28
# Version: 1.0.13
# Description: Dockerfile for the Job Ticket System Django application, setting up Python 3.12 with pyenv and pip.
# Comments:
# - Uses Arch Linux base image with pyenv to ensure Python 3.12.
# - Installs comprehensive build dependencies for pyenv.
# - Installs dependencies via pip -r requirements.txt.
# Update Notes:
# - 2025-08-27 (v1.0.12): Removed redundant Django project/app init and verifications (handled on host).
# - 2025-08-28 (v1.0.13): Changed CMD to uvicorn for ASGI support (channels/websockets).

FROM archlinux:latest

# Install system dependencies, including build tools for pyenv and requirements for Python packages
RUN pacman -Syu --noconfirm && \
    pacman -S --noconfirm python git base-devel gcc make zlib openssl bzip2 libffi readline xz tk ncurses libyaml sqlite patch curl gdbm db linux-api-headers rust postgresql-libs freetype2 lcms2 libimagequant libjpeg-turbo libraqm libtiff libxcb openjpeg2

# Install pyenv and set up shell environment
RUN git clone https://github.com/pyenv/pyenv.git /pyenv && \
    echo 'export PYENV_ROOT="/pyenv"' >> /root/.bashrc && \
    echo 'export PATH="$PYENV_ROOT/bin:$PATH"' >> /root/.bashrc && \
    echo 'eval "$(pyenv init --path)"' >> /root/.bashrc && \
    echo 'eval "$(pyenv init -)"' >> /root/.bashrc && \
    /bin/bash -c "source /root/.bashrc && pyenv install 3.12.0" || { echo "pyenv install 3.12.0 failed"; exit 1; }

# Set pyenv environment
ENV PYENV_ROOT=/pyenv
ENV PATH=$PYENV_ROOT/shims:$PYENV_ROOT/bin:$PATH
RUN /bin/bash -c "source /root/.bashrc && pyenv global 3.12.0"

# Verify Python version
RUN python --version | grep "3.12.0" || { echo "Python 3.12.0 not set"; exit 1; }

# Set working directory
WORKDIR /app

# Copy requirements.txt
COPY requirements.txt ./

# Install Python dependencies
RUN pip install -r requirements.txt || { echo "pip install failed"; exit 1; }

# Verify celery installation
RUN celery --version || { echo "celery not installed"; exit 1; }

# Verify django installation
RUN django-admin --version || { echo "django not installed"; exit 1; }

# Copy project files (includes pre-initialized Django project from host)
COPY . .

# Expose port for Django
EXPOSE 8000

# Command to run migrations and start uvicorn
CMD ["sh", "-c", "python manage.py migrate && uvicorn jts.asgi:application --host 0.0.0.0 --port 8000 --workers 4"]
