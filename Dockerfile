FROM php:7.2-apache-stretch

# Required Components
# @see https://secure.phabricator.com/book/phabricator/article/installation_guide/#installing-required-comp
RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    git \
    mercurial \
    subversion \
    ca-certificates \
    python-pygments \
    imagemagick \
    procps \
  && rm -rf /var/lib/apt/lists/*

# install the PHP extensions we need
RUN set -ex; \
    \
    if command -v a2enmod; then \
        a2enmod rewrite; \
    fi; \
    \
    savedAptMark="$(apt-mark showmanual)"; \
    \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        libcurl4-gnutls-dev \
    libjpeg62-turbo-dev \
        libpng-dev \
    libfreetype6-dev \
    ; \
    \
  docker-php-ext-configure gd \
        --with-jpeg-dir=/usr \
        --with-png-dir=/usr \
    --with-freetype-dir=/usr \
  ; \
  \
    docker-php-ext-install -j "$(nproc)" \
    gd \
    opcache \
    mbstring \
    iconv \
    mysqli \
    curl \
    pcntl \
    ; \
  \
  # reset apt-mark's "manual" list so that "purge --auto-remove" will remove all build dependencies
    apt-mark auto '.*' > /dev/null; \
    apt-mark manual $savedAptMark; \
    ldd "$(php -r 'echo ini_get("extension_dir");')"/*.so \
        | awk '/=>/ { print $3 }' \
        | sort -u \
        | xargs -r dpkg-query -S \
        | cut -d: -f1 \
        | sort -u \
        | xargs -rt apt-mark manual; \
    \
    apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false; \
    rm -rf /var/lib/apt/lists/*

RUN pecl channel-update pecl.php.net \
  && pecl install apcu \
  && docker-php-ext-enable apcu

# set recommended PHP.ini settings
# see https://secure.php.net/manual/en/opcache.installation.php
RUN { \
        echo 'opcache.memory_consumption=128'; \
        echo 'opcache.interned_strings_buffer=8'; \
        echo 'opcache.max_accelerated_files=4000'; \
        echo 'opcache.revalidate_freq=60'; \
        echo 'opcache.fast_shutdown=1'; \
        # From Phabricator
        echo 'opcache.validate_timestamps=0'; \
    } > /usr/local/etc/php/conf.d/opcache-recommended.ini

# Set the default timezone.
RUN { \
        echo 'date.timezone="UTC"'; \
    } > /usr/local/etc/php/conf.d/timezone.ini

# File Uploads
RUN { \
        echo 'post_max_size=32M'; \
        echo 'upload_max_filesize=32M'; \
    } > /usr/local/etc/php/conf.d/uploads.ini

ENV APACHE_DOCUMENT_ROOT /var/www/phabricator/webroot

RUN { \
        echo '<VirtualHost *:80>'; \
        echo '  DocumentRoot ${APACHE_DOCUMENT_ROOT}'; \
        echo '  RewriteEngine on'; \
        echo '  RewriteRule ^(.*)$ /index.php?__path__=$1 [B,L,QSA]'; \
        echo '</VirtualHost>'; \
    } > /etc/apache2/sites-available/000-default.conf

# Repository Folder.
RUN mkdir /var/repo \
  && chown www-data:www-data /var/repo

COPY ./ /var/www

WORKDIR /var/www

RUN git submodule update --init --recursive

ENV PATH "$PATH:/var/www/phabricator/bin"
