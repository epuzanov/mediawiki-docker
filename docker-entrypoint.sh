#!/bin/bash

set -e

case "$MEDIAWIKI_DB_TYPE" in
    mysql)
        DEFAULT_DB_PORT='3306'
        DEFAULT_DB_INSTALL_USER='root'
        ;;
    postgres)
        DEFAULT_DB_PORT='5432'
        DEFAULT_DB_INSTALL_USER='postgres'
        ;;
    mssql)
        DEFAULT_DB_PORT='1433'
        DEFAULT_DB_INSTALL_USER='sa'
        ;;
    *)
        DEFAULT_DB_PORT='0'
        DEFAULT_DB_INSTALL_USER='root'
        ;;
esac

: ${MEDIAWIKI_SITE_SERVER:=//wiki}
: ${MEDIAWIKI_SITE_NAME:=MediaWiki}
: ${MEDIAWIKI_SITE_LANG:=en}
: ${MEDIAWIKI_ADMIN_USER:=admin}
: ${MEDIAWIKI_ADMIN_PASS:=password}
: ${MEDIAWIKI_DB_TYPE:=mysql}
: ${MEDIAWIKI_DB_HOST:=db}
: ${MEDIAWIKI_DB_PORT:=$DEFAULT_DB_PORT}
: ${MEDIAWIKI_DB_SCHEMA:=mediawiki}
: ${MEDIAWIKI_DB_USER:=wikiuser}
: ${MEDIAWIKI_DB_INSTALL_USER:=$DEFAULT_DB_INSTALL_USER}
: ${MEDIAWIKI_DB_INSTALL_PASSWORD:=password}
: ${MEDIAWIKI_DB_NAME:=wikidb}
: ${MEDIAWIKI_UPDATE:=false}
: ${MEDIAWIKI_SHARED:=/etc/mediawiki}
: ${MEDIAWIKI_MAX_UPLOAD_SIZE:=209715200}
: ${APACHE_CONFDIR:=/etc/apache2}
: ${APACHE_ENVVARS:=$APACHE_CONFDIR/envvars}
: ${APACHE_PID_FILE:=${APACHE_RUN_DIR:=/var/run/apache2}/apache2.pid}



if [ -z "$MEDIAWIKI_DB_PASSWORD" ]; then
    MEDIAWIKI_DB_PASSWORD=`tr -cd '[:alnum:]' < /dev/urandom | fold -w16 | head -n1`
fi

if [ -f "$APACHE_ENVVARS" ]; then
    . "$APACHE_ENVVARS"
fi

if [ -f "$APACHE_PID_FILE" ]; then
    rm -f "$APACHE_PID_FILE"
fi

if [ ! -e "$MEDIAWIKI_SHARED/server.key" -o ! -e "$MEDIAWIKI_SHARED/server.crt" -o ! -e "$MEDIAWIKI_SHARED/server-ca.crt" ]; then
    HOSTNAME=`echo $MEDIAWIKI_SITE_SERVER | sed -e "s/[^/]*\/\/\([^@]*@\)\?\([^:/]*\).*/\2/"`
    openssl req -x509 -newkey rsa:4096 -keyout $MEDIAWIKI_SHARED/server.key -out $MEDIAWIKI_SHARED/server.crt -days 365 -nodes -subj "/C=DE/ST=Bonn/L=NRW/O=$MEDIAWIKI_SITE_NAME/OU=Org/CN=$HOSTNAME"
    cp $MEDIAWIKI_SHARED/server.crt $MEDIAWIKI_SHARED/server-ca.crt
fi

if [ $MEDIAWIKI_DB_TYPE = 'sqlite' -a ! -d $MEDIAWIKI_SHARED/data ]; then
    mkdir $MEDIAWIKI_SHARED/data
    chown -R www-data:www-data $MEDIAWIKI_SHARED/data
fi

if [ ! -e "$MEDIAWIKI_SHARED/php.ini" ]; then
    echo "upload_max_filesize = $MEDIAWIKI_MAX_UPLOAD_SIZE" > $MEDIAWIKI_SHARED/php.ini
    echo "post_max_size = $MEDIAWIKI_MAX_UPLOAD_SIZE" >> $MEDIAWIKI_SHARED/php.ini
fi

if [ ! -e "$MEDIAWIKI_SHARED/LocalSettings.php" ]; then
    if [ $MEDIAWIKI_DB_PORT != '0' ]; then
        # Wait for the DB to come up
        while [ `/bin/nc -q 3 $(echo $MEDIAWIKI_DB_HOST | cut -d/ -f1) $MEDIAWIKI_DB_PORT < /dev/null > /dev/null; echo $?` != 0 ]; do
            echo "Waiting for database to come up at $MEDIAWIKI_DB_HOST:$MEDIAWIKI_DB_PORT..."
            sleep 1
        done
    fi

    cd /var/www/html
    php maintenance/install.php \
        --confpath "$MEDIAWIKI_SHARED" \
        --dbname "$MEDIAWIKI_DB_NAME" \
        --dbschema "$MEDIAWIKI_DB_SCHEMA" \
        --dbport "$MEDIAWIKI_DB_PORT" \
        --dbserver "$MEDIAWIKI_DB_HOST" \
        --dbtype "$MEDIAWIKI_DB_TYPE" \
        --dbuser "$MEDIAWIKI_DB_USER" \
        --dbpass "$MEDIAWIKI_DB_PASSWORD" \
        --dbpath "$MEDIAWIKI_SHARED/data" \
        --installdbuser "$MEDIAWIKI_DB_INSTALL_USER" \
        --installdbpass "$MEDIAWIKI_DB_INSTALL_PASSWORD" \
        --server "$MEDIAWIKI_SITE_SERVER" \
        --scriptpath "" \
        --lang "$MEDIAWIKI_SITE_LANG" \
        --pass "$MEDIAWIKI_ADMIN_PASS" \
        "$MEDIAWIKI_SITE_NAME" \
        "$MEDIAWIKI_ADMIN_USER"

    if [ $MEDIAWIKI_DB_TYPE = 'sqlite' ]; then
        chown -R www-data:www-data $MEDIAWIKI_SHARED/data
    fi

    cd extensions
    for EXT in */ ; do
        echo "require_once \"\$IP/extensions/${EXT:0:-1}/${EXT:0:-1}.php\";" >> $MEDIAWIKI_SHARED/LocalSettings.php
    done

    cd ..
    if [[ $MEDIAWIKI_EXTENSIONS == *"Collection"* ]] ; then
        MEDIAWIKI_MWLIB_PASS=`tr -cd '[:alnum:]' < /dev/urandom | fold -w16 | head -n1`
        sed -i 's/wgEnableUploads = false/wgEnableUploads = true/g' $MEDIAWIKI_SHARED/LocalSettings.php
        sed -i "s/wgLanguageCode = \"en\"/wgLanguageCode = \"$MEDIAWIKI_SITE_LANG\"/g" $MEDIAWIKI_SHARED/LocalSettings.php
        sed -i "s/#\$wgCacheDirectory/\$wgCacheDirectory/g" $MEDIAWIKI_SHARED/LocalSettings.php
        echo "\$wgEnableApi = true;" >> $MEDIAWIKI_SHARED/LocalSettings.php
        echo "\$wgEnableWriteAPI = true;" >> $MEDIAWIKI_SHARED/LocalSettings.php
        echo "\$wgMaxArticleSize = 10240;" >> $MEDIAWIKI_SHARED/LocalSettings.php
        echo "\$wgMaxUploadSize = $MEDIAWIKI_MAX_UPLOAD_SIZE;" >> $MEDIAWIKI_SHARED/LocalSettings.php
        echo "\$wgFileExtensions = array_merge(\$wgFileExtensions, array('pdf', 'docx', 'xlsx', 'txt'));" >> $MEDIAWIKI_SHARED/LocalSettings.php
        echo "\$wgGroupPermissions['*']['read'] = false;" >> $MEDIAWIKI_SHARED/LocalSettings.php
        echo "\$wgGroupPermissions['user']['collectionsaveasuserpage'] = true;" >> $MEDIAWIKI_SHARED/LocalSettings.php
        echo "\$wgGroupPermissions['autoconfirmed']['collectionsaveascommunitypage'] = true;" >> $MEDIAWIKI_SHARED/LocalSettings.php
        echo "\$wgCollectionPODPartners = false;" >> $MEDIAWIKI_SHARED/LocalSettings.php
        echo "\$wgCollectionFormats = array('rl' => 'PDF', 'odf' => 'ODT');" >> $MEDIAWIKI_SHARED/LocalSettings.php
        echo "\$wgCollectionMWServeURL=\"http://mwlib:8899\";" >> $MEDIAWIKI_SHARED/LocalSettings.php
        echo "\$wgCollectionMWServeCredentials=\"mwlib:$MEDIAWIKI_MWLIB_PASS\";" >> $MEDIAWIKI_SHARED/LocalSettings.php
        echo "if (gethostbyaddr(\$_SERVER['REMOTE_ADDR']) == 'mwlib') {" >> $MEDIAWIKI_SHARED/LocalSettings.php
        echo "    \$wgServer = \"http://wiki\";" >> $MEDIAWIKI_SHARED/LocalSettings.php
        echo "    \$wgGroupPermissions['*']['read'] = true;" >> $MEDIAWIKI_SHARED/LocalSettings.php
        echo "}" >> $MEDIAWIKI_SHARED/LocalSettings.php
        php maintenance/createAndPromote.php --bot --conf $MEDIAWIKI_SHARED/LocalSettings.php mwlib $MEDIAWIKI_MWLIB_PASS
    fi
    if [ -e "$MEDIAWIKI_SHARED/dump.xml" ]; then
        php maintenance/importDump.php --conf $MEDIAWIKI_SHARED/LocalSettings.php $MEDIAWIKI_SHARED/dump.xml $MEDIAWIKI_DB_NAME
    fi
fi

if [ -e "$MEDIAWIKI_SHARED/LocalSettings.php" -a $MEDIAWIKI_UPDATE = true ]; then
    cd /var/www/html
    php maintenance/update.php --quick --conf $MEDIAWIKI_SHARED/LocalSettings.php
fi

exec "$@"
