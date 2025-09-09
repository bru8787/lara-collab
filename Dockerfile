# --- Stage 1: PHP deps (composer) ---
FROM laravelsail/php82-composer:latest AS vendor
WORKDIR /var/www/html
COPY composer.json composer.lock ./
RUN composer install --no-dev --prefer-dist --no-scripts --no-progress --optimize-autoloader
COPY . .
RUN composer dump-autoload -o

# --- Stage 2: Frontend build (Vite) ---
FROM node:20-alpine AS assets
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY --from=vendor /var/www/html /app
RUN npm run build

# --- Stage 3: Runtime PHP-FPM ---
FROM php:8.2-fpm-alpine AS app
WORKDIR /var/www/html

# estensioni essenziali
RUN apk add --no-cache bash icu-dev libzip-dev oniguruma-dev libpng-dev freetype-dev libjpeg-turbo-dev \
    && docker-php-ext-configure gd --with-freetype --with-jpeg \
    && docker-php-ext-install bcmath ctype fileinfo intl mbstring pdo_mysql zip gd

# opcache consigliato in prod
RUN docker-php-ext-install opcache \
    && { echo "opcache.enable=1"; echo "opcache.validate_timestamps=0"; echo "opcache.jit_buffer_size=64M"; } > /usr/local/etc/php/conf.d/opcache.ini

# copia codice e artefatti
COPY --from=vendor /var/www/html /var/www/html
COPY --from=assets /app/public/build /var/www/html/public/build

# permessi laravel
RUN chown -R www-data:www-data storage bootstrap/cache

# Entrypoint che fa le operazioni di prima partenza
COPY docker/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]
CMD ["php-fpm", "-y", "/usr/local/etc/php-fpm.conf", "-R"]