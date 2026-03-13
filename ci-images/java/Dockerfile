FROM eclipse-temurin:25-jdk

RUN apt-get update && apt-get install -y --no-install-recommends \
        git \
        curl \
        unzip \
    && rm -rf /var/lib/apt/lists/*

# Gradle wrapper handles its own version — no need to install Gradle globally
# SonarQube scanner runs via Gradle plugin

WORKDIR /workspace
