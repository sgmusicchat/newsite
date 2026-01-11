FROM php:8.2-fpm-alpine

# Install PHP extensions for MySQL
RUN apk add --no-cache mysql-client \
    && docker-php-ext-install pdo pdo_mysql mysqli

# Copy PHP configuration
RUN echo "memory_limit = 256M" > /usr/local/etc/php/conf.d/custom.ini \
    && echo "max_execution_time = 30" >> /usr/local/etc/php/conf.d/custom.ini

# Copy application code
COPY . /var/www/html

# Set permissions
RUN chown -R www-data:www-data /var/www/html

# Expose PHP-FPM port
EXPOSE 9000

CMD ["php-fpm"]
