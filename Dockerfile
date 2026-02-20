# 1. Gunakan image resmi AWS Lambda Python 3.12
FROM public.ecr.aws/lambda/python:3.12

# 2. Instal library sistem menggunakan DNF
RUN dnf install -y \
    atk \
    cups-libs \
    gtk3 \
    libXcomposite \
    alsa-lib \
    libXcursor \
    libXdamage \
    libXext \
    libXi \
    libXrandr \
    libXtst \
    pango \
    at-spi2-atk \
    libXt \
    xorg-x11-server-Xvfb \
    dbus-glib \
    dbus-glib-devel && \
    dnf clean all

# 3. Instal Poetry
RUN pip install poetry

# Simpan browser Playwright di path yang konsisten untuk runtime Lambda
ENV PLAYWRIGHT_BROWSERS_PATH=/opt/pw-browsers
RUN mkdir -p /opt/pw-browsers

# 4. Copy file project dan instal dependencies
COPY pyproject.toml poetry.lock ./
RUN poetry config virtualenvs.create false && \
    poetry install --only main --no-interaction --no-ansi --no-root

# 5. Instal browser Chromium untuk Playwright
RUN playwright install chromium

# 6. Copy source code ke folder task Lambda
COPY src/ ${LAMBDA_TASK_ROOT}/src/

# Handler diatur via Terraform/AWS Console