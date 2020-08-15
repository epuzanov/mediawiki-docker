FROM epuzanov/php

MAINTAINER Egor Puzanov

ENV DEBIAN_FRONTEND noninteractive

ARG MEDIAWIKI_VERSION=REL1_34
ENV MEDIAWIKI_VERSION $MEDIAWIKI_VERSION

ARG MEDIAWIKI_SKINS="MonoBook Timeless Vector"
ENV MEDIAWIKI_SKINS $MEDIAWIKI_SKINS

ARG MEDIAWIKI_EXTENSIONS="CategoryTree Cite CiteThisPage CodeEditor Collection ConfirmEdit Gadgets ImageMap InputBox Interwiki LdapAuthentication LocalisationUpdate MultimediaViewer OATHAuth ParserFunctions PdfHandler Poem Renameuser ReplaceText SpamBlacklist SyntaxHighlight_GeSHi TitleBlacklist VisualEditor WikiEditor"
ENV MEDIAWIKI_EXTENSIONS $MEDIAWIKI_EXTENSIONS

RUN mkdir /data && \
    rm -f /var/www/html/* && \
    cd /var/www && \
    git clone --depth 1 -b $MEDIAWIKI_VERSION https://gerrit.wikimedia.org/r/mediawiki/core.git html && \
    cd html && \
    git clone -b $MEDIAWIKI_VERSION https://gerrit.wikimedia.org/r/mediawiki/vendor.git vendor && \
    cd skins && \
    for SKIN in $MEDIAWIKI_SKINS ; do git clone -b $MEDIAWIKI_VERSION https://gerrit.wikimedia.org/r/mediawiki/skins/$SKIN.git && \
    rm -rf $SKIN/.git* $SKIN/.js* ; done && \
    cd ../extensions && \
    rm -rf * && \
    for EXT in $MEDIAWIKI_EXTENSIONS ; do git clone -b $MEDIAWIKI_VERSION https://gerrit.wikimedia.org/r/mediawiki/extensions/$EXT.git && \
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
