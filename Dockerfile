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
    libxrandr1 \
    libxi6 \
    libasound2 \
    libpulse0 \
    libglib2.0-0 \
    && rm -rf /var/lib/apt/lists/*

# Download and extract Godot 4.7 Stable Linux Editor
WORKDIR /opt/godot
RUN curl -fsSL https://downloads.tuxfamily.org/godotengine/4.7/Godot_v4.7-stable_linux.x86_64.zip -o godot.zip \
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

# Run the Godot server headlessly
CMD ["/opt/godot/godot", "--headless", "--path", "/app"]
