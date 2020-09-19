FROM epuzanov/php

MAINTAINER Egor Puzanov

ENV DEBIAN_FRONTEND noninteractive

ARG MEDIAWIKI_VERSION=1.34.2
ENV MEDIAWIKI_VERSION $MEDIAWIKI_VERSION

ARG MEDIAWIKI_EXTENSIONS="Collection LdapAuthentication VisualEditor"
ENV MEDIAWIKI_EXTENSIONS $MEDIAWIKI_EXTENSIONS

RUN mkdir /data && \
    rm -f /var/www/html/* && \
    cd /var/www && \
    git clone --depth 1 --recurse-submodules -b $MEDIAWIKI_VERSION https://gerrit.wikimedia.org/r/mediawiki/core.git html && \
    cd html/extensions && \
    for EXT in $MEDIAWIKI_EXTENSIONS ; do git clone --depth 1 --recurse-submodules -b $(echo $MEDIAWIKI_VERSION | sed "s/\([0-9]*\)\.\([0-9]*\).*/REL\1_\2/") https://gerrit.wikimedia.org/r/mediawiki/extensions/$EXT.git && \
    cd $EXT && \
    git submodule update --init && \
    cd .. && \
    rm -rf $EXT/.git* $EXT/.js* ; done && \
    cd .. && \
    rm -rf cache images .git* .js* .mailmap .rubocop.yml .travis.yml && \
    ln -s /data/cache cache && \
    ln -s /data/images images && \
    ln -s /data/LocalSettings.php /var/www/html/LocalSettings.php

VOLUME /data
COPY mediawiki.conf /etc/apache2/sites-enabled/mediawiki.conf
COPY default.xml /var/www/html/maintenance/default.xml
COPY entrypoint.sh /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]

CMD ["httpd-foreground", "-DFOREGROUND"]
