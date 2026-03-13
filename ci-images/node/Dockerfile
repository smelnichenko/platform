FROM node:22-bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
        git \
        curl \
        python3 \
        python3-pip \
        python3-venv \
    && rm -rf /var/lib/apt/lists/*

# Install Helm (for helm lint)
RUN curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Install ansible-lint via pipx
RUN pip3 install --break-system-packages pipx \
    && pipx install ansible-lint \
    && pipx ensurepath
ENV PATH="/root/.local/bin:${PATH}"

# sonarqube-scanner installed via npx at runtime (no global install needed)

WORKDIR /workspace
