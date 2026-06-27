# Use a lightweight Debian image
FROM debian:bookworm-slim

# Install essential packages and Godot dependencies
RUN apt-get update && apt-get install -y \
    curl \
    unzip \
    ca-certificates \
    libfontconfig1 \
    libxcursor1 \
    libxinerama1 \
    libxrandr2 \
    libxi6 \
    libasound2 \
    libpulse0 \
    libglib2.0-0 \
    && rm -rf /var/lib/apt/lists/*

# Download and extract Godot 4.7 Stable Linux Editor from GitHub Releases (reliable CDN)
WORKDIR /opt/godot
RUN curl -fsSL https://github.com/godotengine/godot/releases/download/4.7-stable/Godot_v4.7-stable_linux.x86_64.zip -o godot.zip \
    && unzip godot.zip \
    && rm godot.zip \
    && mv Godot_v4.7-stable_linux.x86_64 godot \
    && chmod +x godot

# Set up the application directory and copy project files
WORKDIR /app
COPY . .

# Render exposes a random port via the PORT environment variable.
# Godot will automatically read this environment variable and listen on it.
EXPOSE 10555

# Run the Godot server headlessly, locating project.godot dynamically to support subfolders.
# Performs a first headless import pass to build the script class cache before starting the server.
CMD ["sh", "-c", "PROJECT_PATH=$(find /app -name project.godot | head -n 1 | xargs -I {} dirname '{}'); if [ -z \"$PROJECT_PATH\" ]; then echo \"ERROR: project.godot was not found in /app! Please make sure you have uploaded the project.godot file.\"; exit 1; fi; echo \"Running Godot in project path: $PROJECT_PATH\"; echo \"Step 1: Performing headless import and building script class cache...\"; /opt/godot/godot --headless --path \"$PROJECT_PATH\" --editor --quit || true; echo \"Step 2: Starting dedicated server...\"; /opt/godot/godot --headless --path \"$PROJECT_PATH\""]
