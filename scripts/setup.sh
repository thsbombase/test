#!/usr/bin/env bash

set -e

# Prepare environment file
if [ ! -f .env ]; then
    echo "Creating .env from .env.example..."
    cp .env.example .env
fi

# Install Composer dependencies if missing
if [ ! -f vendor/bin/sail ]; then
    composer install --no-interaction
fi

# Start Docker containers
./vendor/bin/sail up -d

# Install PHP dependencies
./vendor/bin/sail composer install

# Generate application key if missing
if ! grep -qE '^APP_KEY=.+$' .env; then
    ./vendor/bin/sail artisan key:generate
fi

# Wait for MySQL to become ready
echo "Waiting for MySQL..."

for attempt in {1..60}; do
    if ./vendor/bin/sail exec -T mysql sh -c \
        'mysql --protocol=TCP -h 127.0.0.1 -u"$MYSQL_USER" -p"$MYSQL_PASSWORD" "$MYSQL_DATABASE" -e "SELECT 1"' \
        >/dev/null 2>&1; then
        echo "MySQL is ready!"
        break
    fi

    if [ "$attempt" -eq 60 ]; then
        echo "MySQL failed to become ready."
        exit 1
    fi

    sleep 2
done

# Clear configuration cache
./vendor/bin/sail artisan config:clear

# Run database migrations and seeders
./vendor/bin/sail artisan migrate --seed --force

# Create storage symbolic link
if [ ! -L public/storage ]; then
    ./vendor/bin/sail artisan storage:link
fi

# Generate Wayfinder routes
./vendor/bin/sail artisan wayfinder:generate

# Install frontend dependencies
./vendor/bin/sail npm install

# Build frontend assets
./vendor/bin/sail npm run build

# Clear Laravel caches
./vendor/bin/sail artisan optimize:clear

echo "Installation completed successfully!"