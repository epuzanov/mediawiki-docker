FROM debian:jessie

MAINTAINER Egor Puzanov <epuzanov@gmx.de>

ENV DEBIAN_FRONTEND noninteractive

ARG MEDIAWIKI_VERSION=REL1_28
ENV MEDIAWIKI_VERSION $MEDIAWIKI_VERSION

ARG MEDIAWIKI_SKINS="CologneBlue Modern MonoBook Vector"
ENV MEDIAWIKI_SKINS $MEDIAWIKI_SKINS

ARG MEDIAWIKI_EXTENSIONS="Cite CiteThisPage Collection ConfirmEdit Gadgets ImageMap InputBox Interwiki LocalisationUpdate Nuke ParserFunctions PdfHandler Poem Renameuser SpamBlacklist SyntaxHighlight_GeSHi TitleBlacklist WikiEditor"
ENV MEDIAWIKI_EXTENSIONS $MEDIAWIKI_EXTENSIONS

ARG MEDIAWIKI_MAX_UPLOAD_SIZE=209715200
ENV MEDIAWIKI_MAX_UPLOAD_SIZE $MEDIAWIKI_MAX_UPLOAD_SIZE

ARG SQLSRV_VERSION=v4.2.0-preview
ENV SQLSRV_VERSION $SQLSRV_VERSION

RUN set -x; apt-get update \
    && apt-get install -y --no-install-recommends \
        apt-transport-https \
        ca-certificates \
        curl \
        apache2 \
        locales \
        netcat \
        git \
        imagemagick \
    && echo "en_US.UTF-8 UTF-8" > /etc/locale.gen \
    && locale-gen \
    && rm -rf /var/lib/apt/lists/* \
    && rm -rf /var/cache/apt/archives/*

COPY mediawiki.conf /etc/apache2/conf-available/mediawiki.conf
COPY redirect.conf /etc/apache2/sites-available/redirect.conf

RUN set -x; mkdir /etc/mediawiki \
    && a2enmod ssl \
    && a2enmod rewrite \
    && a2enconf mediawiki \
    && a2disconf other-vhosts-access-log \
    && a2ensite default-ssl \
    && a2ensite redirect \
    && sed -i "s/Listen 80/Listen 80\nListen 81/g" /etc/apache2/ports.conf \
    && sed -i "s/#SSLCertificateChainFile \/etc\/apache2\/ssl.crt/SSLCertificateChainFile \/etc\/ssl\/certs/g" /etc/apache2/sites-available/default-ssl.conf \
    && ln -sfT /dev/stderr "/var/log/apache2/error.log" \
    && ln -sfT /dev/stdout "/var/log/apache2/access.log" \
    && ln -sfT /dev/stdout "/var/log/apache2/other_vhosts_access.log" \
    && ln -s /etc/mediawiki/server.crt /etc/ssl/certs/ssl-cert-snakeoil.pem \
    && ln -s /etc/mediawiki/server-ca.crt /etc/ssl/certs/server-ca.crt \
    && ln -s /etc/mediawiki/server.key /etc/ssl/private/ssl-cert-snakeoil.key \
    && rm -rf /var/www/html

RUN set -x; cd /tmp \
    && curl https://www.dotdeb.org/dotdeb.gpg | apt-key add - \
    && echo "deb http://packages.dotdeb.org jessie all" > /etc/apt/sources.list.d/dotdeb.list \
    && curl https://packages.microsoft.com/keys/microsoft.asc | apt-key add - \
    && curl https://packages.microsoft.com/config/debian/8/prod.list > /etc/apt/sources.list.d/mssql-release.list \
    && apt-get update \
    && ACCEPT_EULA=Y  apt-get install -y --no-install-recommends msodbcsql \
    && apt-get install -y --no-install-recommends \
        libapache2-mod-php7.0 \
        php7.0-mbstring \
        php7.0-xml \
        php7.0-intl \
        php7.0-mysql \
        php7.0-pgsql \
        php7.0-sqlite \
        php7.0-cli \
        php7.0-curl \
    && rm -rf /var/lib/apt/lists/* \
    && rm -rf /var/cache/apt/archives/* \
    && a2dismod mpm_event \
    && a2enmod mpm_prefork \
    && ln -s /etc/mediawiki/php.ini /etc/php/7.0/apache2/conf.d/30-mediawiki.ini \
    && curl -L https://github.com/Microsoft/msphpsql/releases/download/$SQLSRV_VERSION/Debian8-7.0.tar | tar -x \
    && cp ./Debian8-7.0/php_sqlsrv_7_nts.so /usr/lib/php/20151012/ \
    && echo -e "; priority=20\nextension=php_sqlsrv_7_nts.so" > /etc/php/7.0/mods-available/sqlsrv.ini \
    && phpenmod sqlsrv \
    && rm -fr /tmp/*

RUN set -x; cd /var/www \
    && git clone --depth 1 -b $MEDIAWIKI_VERSION https://gerrit.wikimedia.org/r/p/mediawiki/core.git html \
    && cd html \
    && sed -i "s/^}$/\tfunction getText() \{\n\t\treturn \$this->error;\n\t}\n}/g" includes/libs/rdbms/exception/DBQueryError.php \
    && sed -i "s/function ignoreErrors/function ignoreErrorsOld/g" includes/db/DatabaseMssql.php \
    && git clone -b $MEDIAWIKI_VERSION https://gerrit.wikimedia.org/r/p/mediawiki/vendor.git vendor \
    && cd skins \
    && for SKIN in $MEDIAWIKI_SKINS ; do git clone -b $MEDIAWIKI_VERSION https://gerrit.wikimedia.org/r/p/mediawiki/skins/$SKIN.git \
    && rm -rf $SKIN/.git* $SKIN/.js* ; done \
    && cd ../extensions \
    && for EXT in $MEDIAWIKI_EXTENSIONS ; do git clone -b $MEDIAWIKI_VERSION https://gerrit.wikimedia.org/r/p/mediawiki/extensions/$EXT.git \
    && rm -rf $EXT/.git* $EXT/.js* ; done \
    && cd .. \
    && sed -i "s/\$wgScriptPath ? \$wgScriptPath : \"\//\"http:\/\/\wiki\//g" ./extensions/Collection/RenderingAPI.php \
    && rm -rf mw-config images/* .git* .js* .mailmap .rubocop.yml .travis.yml \
    && chown -R www-data:www-data images cache \
    && ln -s /etc/mediawiki/LocalSettings.php /var/www/html/LocalSettings.php \
    && mv /var/www/html/resources/assets/wiki.png /etc/mediawiki/ \
    && ln -s /etc/mediawiki/wiki.png /var/www/html/resources/assets/wiki.png

COPY docker-entrypoint.sh /entrypoint.sh

VOLUME /var/www/html/images
VOLUME /etc/mediawiki

EXPOSE 80 81 443
ENTRYPOINT ["/entrypoint.sh"]
CMD ["apachectl", "-e", "info", "-D", "FOREGROUND"]

