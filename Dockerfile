# 1. Gunakan image resmi AWS Lambda Python 3.12
FROM public.ecr.aws/lambda/python:3.12

# 2. Instal library sistem lengkap untuk Chromium + Playwright
RUN dnf install -y \
    alsa-lib \
    at-spi2-atk \
    at-spi2-core \
    atk \
    cairo \
    cups-libs \
    dbus \
    dbus-glib \
    dbus-glib-devel \
    fontconfig \
    freetype \
    gcc \
    gdk-pixbuf2 \
    glib2 \
    glibc \
    gtk3 \
    hicolor-icon-theme \
    libX11 \
    libXScrnSaver \
    libXcomposite \
    libXcursor \
    libXdamage \
    libXext \
    libXfixes \
    libXi \
    libXinerama \
    libXrandr \
    libXrender \
    libXtst \
    libdbus-1 \
    libdrm \
    libexpat \
    libgbm \
    libpng \
    libstdc++ \
    libxcb \
    libxkbcommon \
    libxkbcommon-x11 \
    libnss3 \
    libnspr4 \
    mesa-libGL \
    mesa-libGLU \
    pango \
    xorg-x11-fonts-Type1 \
    xorg-x11-server-Xvfb && \
    dnf clean all && \
    rm -rf /var/cache/dnf/*

# 3. Set up nsswitch untuk glibc compatibility
RUN echo "hosts: files dns" > /etc/nsswitch.conf

# 4. Instal Poetry
RUN pip install poetry

# Simpan browser Playwright di path yang konsisten untuk runtime Lambda
ENV PLAYWRIGHT_BROWSERS_PATH=/opt/pw-browsers
ENV CHROME_REMOTE_DEBUGGING_PORT=9222
RUN mkdir -p /opt/pw-browsers /tmp/chromium-profile

# 5. Copy file project dan instal dependencies
COPY pyproject.toml poetry.lock ./
RUN poetry config virtualenvs.create false && \
    poetry install --only main --no-interaction --no-ansi --no-root

# 6. Instal browser Chromium untuk Playwright dengan verbose output
RUN python -c "from playwright.async_api import async_playwright; import asyncio; asyncio.run(async_playwright().__aenter__().chromium.launch())" || \
    playwright install chromium

# 7. Copy source code ke folder task Lambda
COPY src/ ${LAMBDA_TASK_ROOT}/src/

# 8. Verify Chromium is installed
RUN ls -lah ${PLAYWRIGHT_BROWSERS_PATH}/chromium-* || echo "Chromium installation may be incomplete"

# Handler diatur via Terraform/AWS Console