#!/bin/bash

set -e

: ${MEDIAWIKI_DB_TYPE:=sqlite}

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
: ${MEDIAWIKI_DB_HOST:=db}
: ${MEDIAWIKI_DB_PORT:=$DEFAULT_DB_PORT}
: ${MEDIAWIKI_DB_SCHEMA:=mediawiki}
: ${MEDIAWIKI_DB_USER:=wikiuser}
: ${MEDIAWIKI_DB_INSTALL_USER:=$DEFAULT_DB_INSTALL_USER}
: ${MEDIAWIKI_DB_NAME:=wikidb}
: ${MEDIAWIKI_DB_PREFIX:=}
: ${MEDIAWIKI_UPDATE:=false}
: ${MEDIAWIKI_SCRIPTPATH:=}
: ${MEDIAWIKI_BASEDIR:=/var/www/html}
: ${MEDIAWIKI_SHARED:=/data}
: ${MEDIAWIKI_MAX_UPLOAD_SIZE:=209715200}
: ${MEDIAWIKI_LDAP_SERVER_NAMES:=dc1.domain.net}
: ${MEDIAWIKI_LDAP_PROXY_AGENT:=CN=ldapsearch,OU=Users,DC=domain,DC=net}
: ${MEDIAWIKI_LDAP_PROXY_AGENT_PASSWORD:=Pa55word}
: ${MEDIAWIKI_LDAP_BASEDNS:=dc=domain,dc=net}
: ${MEDIAWIKI_LDAP_REQUIRED_GROUPS:=CN=wiki-users,OU=Users,DC=domain,DC=net}

if [ "2" != "$(ls -al $MEDIAWIKI_SHARED | grep -c ^d )" -a "0" = "$(ls -al $MEDIAWIKI_SHARED | grep -c ^- )" ]; then
    cd $MEDIAWIKI_SHARED
    for CONTAINER_NAME in */ ; do
        CONTAINER_NAME=${CONTAINER_NAME:0:-1}
        if [ ! -e "$CONTAINER_NAME/vhost.conf" ]; then
            while [ ! -f "$CONTAINER_NAME/LocalSettings.php" ]; do
                sleep 10
            done
            WGSERVERNAME=`grep -Po 'wgServer = ".*\/\/\K(.+)(?=";)' $CONTAINER_NAME/LocalSettings.php || echo "127.0.0.1"`
            WGSCRIPTPATH=`grep -Po 'wgScriptPath = "\K(.+)(?=";)' $CONTAINER_NAME/LocalSettings.php || echo ""`
            echo "Use VHost $WGSERVERNAME $WGSCRIPTPATH/ /data/$CONTAINER_NAME $CONTAINER_NAME" > $CONTAINER_NAME/vhost.conf
        fi
    done
    export APACHE_SNAME="127.0.0.1"
    export APACHE_SCRIPTPATH="/"
    exec "$@ -DFPM"
fi


case $(grep -o "^www-data\|^wwwrun\|^apache" /etc/passwd) in
    apache)
        MEDIAWIKI_HTTPD_USERGROUP="apache:apache"
        ;;
    www-data)
        MEDIAWIKI_HTTPD_USERGROUP="www-data:www-data"
        ;;
    wwwrun)
        MEDIAWIKI_HTTPD_USERGROUP="wwwrun:www"
        ;;
    *)
        MEDIAWIKI_HTTPD_USERGROUP="www-data:www-data"
        ;;
esac

MEDIAWIKI_SECURE_LOGIN=false
if [ "https" = "${MEDIAWIKI_SITE_SERVER:0:5}" ]; then
    MEDIAWIKI_SITE_SERVER=${MEDIAWIKI_SITE_SERVER:6}
    MEDIAWIKI_SECURE_LOGIN=true
fi

if [ -z "$MEDIAWIKI_DB_PASSWORD" ]; then
    MEDIAWIKI_DB_PASSWORD=`tr -cd '[:alnum:]' < /dev/urandom | fold -w15 | head -n1`
    MEDIAWIKI_DB_PASSWORD="$MEDIAWIKI_DB_PASSWORD!"
fi

if [ -z "$MEDIAWIKI_DB_INSTALL_PASSWORD" ]; then
    MEDIAWIKI_DB_INSTALL_USER=$MEDIAWIKI_DB_USER
    MEDIAWIKI_DB_INSTALL_PASSWORD=$MEDIAWIKI_DB_PASSWORD
fi

if [ ! -e "$MEDIAWIKI_SHARED/server.key" -o ! -e "$MEDIAWIKI_SHARED/server.crt" -o ! -e "$MEDIAWIKI_SHARED/server-ca.crt" ]; then
    HOSTNAME=`echo $MEDIAWIKI_SITE_SERVER | sed -e "s/[^/]*\/\/\([^@]*@\)\?\([^:/]*\).*/\2/"`
    openssl req -x509 -newkey rsa:4096 -keyout $MEDIAWIKI_SHARED/server.key -out $MEDIAWIKI_SHARED/server.crt -days 365 -nodes -subj "/C=US/ST=None/L=None/O=$MEDIAWIKI_SITE_NAME/OU=Org/CN=$HOSTNAME"
    cp $MEDIAWIKI_SHARED/server.crt $MEDIAWIKI_SHARED/server-ca.crt
fi

if [ ! -d $MEDIAWIKI_SHARED/cache ]; then
    mkdir $MEDIAWIKI_SHARED/cache
    chown -R $MEDIAWIKI_HTTPD_USERGROUP $MEDIAWIKI_SHARED/cache
fi

if [ ! -d $MEDIAWIKI_SHARED/images ]; then
    mkdir $MEDIAWIKI_SHARED/images
    cp $MEDIAWIKI_BASEDIR/resources/assets/wiki.png $MEDIAWIKI_SHARED/images/wiki.png
    chown -R $MEDIAWIKI_HTTPD_USERGROUP $MEDIAWIKI_SHARED/images
fi

if [ $MEDIAWIKI_DB_TYPE = 'sqlite' -a ! -d $MEDIAWIKI_SHARED/data ]; then
    mkdir $MEDIAWIKI_SHARED/data
    chown -R $MEDIAWIKI_HTTPD_USERGROUP $MEDIAWIKI_SHARED/data
fi

if [ ! -e "$MEDIAWIKI_SHARED/wiki.png" ]; then
    cp $MEDIAWIKI_BASEDIR/resources/assets/wiki.png $MEDIAWIKI_SHARED/wiki.png
fi

if [ ! -e "$MEDIAWIKI_SHARED/LocalSettings.php" ]; then
    if [ $MEDIAWIKI_DB_PORT != '0' ]; then
        # Wait for the DB to come up
        while [ `ncat -w 3 $(echo $MEDIAWIKI_DB_HOST | cut -d/ -f1) $MEDIAWIKI_DB_PORT < /dev/null > /dev/null; echo $?` != 0 ]; do
            echo "Waiting for database to come up at $MEDIAWIKI_DB_HOST:$MEDIAWIKI_DB_PORT..."
            sleep 1
        done
    fi

    cd $MEDIAWIKI_BASEDIR
    /usr/bin/php maintenance/install.php \
        --confpath "$MEDIAWIKI_SHARED" \
        --dbname "$MEDIAWIKI_DB_NAME" \
        --dbprefix "$MEDIAWIKI_DB_PREFIX" \
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
        --scriptpath "$MEDIAWIKI_SCRIPTPATH" \
        --lang "$MEDIAWIKI_SITE_LANG" \
        --pass "$MEDIAWIKI_ADMIN_PASS" \
        "$MEDIAWIKI_SITE_NAME" \
        "$MEDIAWIKI_ADMIN_USER"

    if [ $MEDIAWIKI_DB_TYPE = 'sqlite' ]; then
        chown -R $MEDIAWIKI_HTTPD_USERGROUP $MEDIAWIKI_SHARED/data
    fi

    cd extensions
    for EXT in */ ; do
        if [ -e "${EXT:0:-1}/${EXT:0:-1}.php" ]; then
            echo "require_once \"\$IP/extensions/${EXT:0:-1}/${EXT:0:-1}.php\";" >> $MEDIAWIKI_SHARED/LocalSettings.php
        else
            echo "wfLoadExtension( '${EXT:0:-1}' );" >> $MEDIAWIKI_SHARED/LocalSettings.php
        fi
    done

    cd ..
    sed -i 's/wgEnableUploads = false/wgEnableUploads = true/g' $MEDIAWIKI_SHARED/LocalSettings.php
    sed -i "s/wgLanguageCode = \"en\"/wgLanguageCode = \"$MEDIAWIKI_SITE_LANG\"/g" $MEDIAWIKI_SHARED/LocalSettings.php
    if [ -z "$MEDIAWIKI_MEMCACHED" ] ; then
        if [ "0" != "$(php -m | grep -ic apcu)" ] ; then
            sed -i "s/wgMainCacheType = CACHE_NONE/wgMainCacheType = CACHE_ACCEL/g" $MEDIAWIKI_SHARED/LocalSettings.php
        fi
    else
        sed -i "s/wgMainCacheType = CACHE_NONE/wgMainCacheType = CACHE_MEMCACHED/g" $MEDIAWIKI_SHARED/LocalSettings.php
        sed -i "s/wgMemCachedServers = \[/wgMemCachedServers = \['$MEDIAWIKI_MEMCACHED'/g" $MEDIAWIKI_SHARED/LocalSettings.php
    fi
    echo "\$wgSecureLogin = $MEDIAWIKI_SECURE_LOGIN;" >> $MEDIAWIKI_SHARED/LocalSettings.php
    echo "\$wgEnableApi = true;" >> $MEDIAWIKI_SHARED/LocalSettings.php
    echo "\$wgEnableWriteAPI = true;" >> $MEDIAWIKI_SHARED/LocalSettings.php
    echo "\$wgFileExtensions = array_merge(\$wgFileExtensions, array('pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'txt', 'svg', 'ogg'));" >> $MEDIAWIKI_SHARED/LocalSettings.php
    echo "" >> $MEDIAWIKI_SHARED/LocalSettings.php
    echo "# Upload Limits" >> $MEDIAWIKI_SHARED/LocalSettings.php
    echo "\$wgMaxArticleSize = 10240;" >> $MEDIAWIKI_SHARED/LocalSettings.php
    echo "\$wgMaxUploadSize = $MEDIAWIKI_MAX_UPLOAD_SIZE;" >> $MEDIAWIKI_SHARED/LocalSettings.php
    echo "ini_set('upload_max_filesize', \$wgMaxUploadSize);" >> $MEDIAWIKI_SHARED/LocalSettings.php
    echo "ini_set('post_max_size', \$wgMaxUploadSize + 1024);" >> $MEDIAWIKI_SHARED/LocalSettings.php
    echo "ini_set('memory_limit', \$wgMaxUploadSize + 2048);" >> $MEDIAWIKI_SHARED/LocalSettings.php
    echo "" >> $MEDIAWIKI_SHARED/LocalSettings.php
    echo "# Permissions" >> $MEDIAWIKI_SHARED/LocalSettings.php
    echo "\$wgBlockDisablesLogin = true;" >> $MEDIAWIKI_SHARED/LocalSettings.php
    echo "\$wgGroupPermissions['*']['read'] = false;" >> $MEDIAWIKI_SHARED/LocalSettings.php
    if [ -d $MEDIAWIKI_BASEDIR/extensions/ParserFunctions ]; then
        echo "" >> $MEDIAWIKI_SHARED/LocalSettings.php
        echo "#ParserFunctions Config" >> $MEDIAWIKI_SHARED/LocalSettings.php
        echo "array_push(\$wgUrlProtocols, 'file://');" >> $MEDIAWIKI_SHARED/LocalSettings.php
        echo "\$wgPFEnableStringFunctions = true;" >> $MEDIAWIKI_SHARED/LocalSettings.php
    fi
    if [ -d $MEDIAWIKI_BASEDIR/extensions/WikiEditor ] ; then
        echo "" >> $MEDIAWIKI_SHARED/LocalSettings.php
        echo "# WikiEditor Settings" >> $MEDIAWIKI_SHARED/LocalSettings.php
        echo "\$wgDefaultUserOptions['usebetatoolbar'] = 1;" >> $MEDIAWIKI_SHARED/LocalSettings.php
        echo "\$wgDefaultUserOptions['usebetatoolbar-cgd'] = 1;" >> $MEDIAWIKI_SHARED/LocalSettings.php
        echo "\$wgDefaultUserOptions['wikieditor-preview'] = 1;" >> $MEDIAWIKI_SHARED/LocalSettings.php
        echo "\$wgDefaultUserOptions['wikieditor-publish'] = 1;" >> $MEDIAWIKI_SHARED/LocalSettings.php
    fi
    if [ -d $MEDIAWIKI_BASEDIR/extensions/VisualEditor ] ; then
        SERVERNAME=`grep -Po 'wgServer = ".*\/\/\K(.+)(?=";)' $MEDIAWIKI_SHARED/LocalSettings.php`
        echo "" >> $MEDIAWIKI_SHARED/LocalSettings.php
        echo "# VisualEditor Settings" >> $MEDIAWIKI_SHARED/LocalSettings.php
        echo "\$wgVisualEditorEnableWikitext = true;" >> $MEDIAWIKI_SHARED/LocalSettings.php
        echo "\$wgDefaultUserOptions['visualeditor-enable'] = 1;" >> $MEDIAWIKI_SHARED/LocalSettings.php
        echo "\$wgDefaultUserOptions['visualeditor-newwikitext'] = 1;" >> $MEDIAWIKI_SHARED/LocalSettings.php
        echo "\$wgVirtualRestConfig['modules']['parsoid'] = array('url'=>'http://parsoid:8000', 'domain'=>'$SERVERNAME');" >> $MEDIAWIKI_SHARED/LocalSettings.php
        echo "\$wgVirtualRestConfig['modules']['parsoid']['forwardCookies'] = true;" >> $MEDIAWIKI_SHARED/LocalSettings.php
    fi
    if [ -d $MEDIAWIKI_BASEDIR/extensions/LdapAuthentication ]; then
        echo "" >> $MEDIAWIKI_SHARED/LocalSettings.php
        echo "# LDAP Config" >> $MEDIAWIKI_SHARED/LocalSettings.php
        echo "#\$wgAuth = new LdapAuthenticationPlugin();" >> $MEDIAWIKI_SHARED/LocalSettings.php
        echo "\$wgLDAPDomainNames = array( \"AD\" );" >> $MEDIAWIKI_SHARED/LocalSettings.php
        echo "\$wgLDAPServerNames = array( \"AD\"=>\"$MEDIAWIKI_LDAP_SERVER_NAMES\" );" >> $MEDIAWIKI_SHARED/LocalSettings.php
        echo "\$wgLDAPEncryptionType = array( \"AD\"=>\"tls\" );" >> $MEDIAWIKI_SHARED/LocalSettings.php
        echo "\$wgLDAPProxyAgent = array( \"AD\"=>\"$MEDIAWIKI_LDAP_PROXY_AGENT\" );" >> $MEDIAWIKI_SHARED/LocalSettings.php
        echo "\$wgLDAPProxyAgentPassword = array( \"AD\"=>\"$MEDIAWIKI_LDAP_PROXY_AGENT_PASSWORD\" );" >> $MEDIAWIKI_SHARED/LocalSettings.php
        echo "\$wgLDAPBaseDNs = array( \"AD\"=>\"$MEDIAWIKI_LDAP_BASEDNS\" );" >> $MEDIAWIKI_SHARED/LocalSettings.php
        echo "\$wgLDAPSearchAttributes = array( \"AD\"=>\"sAMAccountName\" );" >> $MEDIAWIKI_SHARED/LocalSettings.php
        echo "\$wgLDAPGroupsUseMemberOf = array( \"AD\"=>true );" >> $MEDIAWIKI_SHARED/LocalSettings.php
        echo "\$wgLDAPGroupUseFullDN = array( \"AD\"=>true );" >> $MEDIAWIKI_SHARED/LocalSettings.php
        echo "\$wgLDAPGroupObjectclass = array( \"AD\"=>\"group\");" >> $MEDIAWIKI_SHARED/LocalSettings.php
        echo "\$wgLDAPGroupAttribute = array( \"AD\"=>\"member\" );" >> $MEDIAWIKI_SHARED/LocalSettings.php
        echo "\$wgLDAPGroupSearchNestedGroups = array( \"AD\"=>true );" >> $MEDIAWIKI_SHARED/LocalSettings.php
        echo "\$wgLDAPGroupNameAttribute = array( \"AD\"=>\"cn\" );" >> $MEDIAWIKI_SHARED/LocalSettings.php
        echo "\$wgLDAPPreferences = array( \"AD\"=>array( \"email\"=>\"mail\", \"realname\"=>\"displayname\" ) );" >> $MEDIAWIKI_SHARED/LocalSettings.php
        echo "\$wgLDAPUseLDAPGroups = array( \"AD\"=>true );" >> $MEDIAWIKI_SHARED/LocalSettings.php
        echo "\$wgLDAPActiveDirectory = array( \"AD\"=>true );" >> $MEDIAWIKI_SHARED/LocalSettings.php
        echo "\$wgLDAPRequiredGroups =array( \"AD\"=>array( \"$MEDIAWIKI_LDAP_REQUIRED_GROUPS\" ));" >> $MEDIAWIKI_SHARED/LocalSettings.php
        echo "\$wgLDAPUseSSL = false;" >> $MEDIAWIKI_SHARED/LocalSettings.php
        echo "\$wgLDAPUseLocal = false;" >> $MEDIAWIKI_SHARED/LocalSettings.php
        echo "\$wgLDAPAddLDAPUsers = false;" >> $MEDIAWIKI_SHARED/LocalSettings.php
        echo "\$wgLDAPUpdateLDAP = false;" >> $MEDIAWIKI_SHARED/LocalSettings.php
        echo "\$wgLDAPMailPassword = false;" >> $MEDIAWIKI_SHARED/LocalSettings.php
        echo "\$wgLDAPRetrievePrefs = true;" >> $MEDIAWIKI_SHARED/LocalSettings.php
        echo "\$wgMinimalPasswordLength = 1;" >> $MEDIAWIKI_SHARED/LocalSettings.php
    fi
    if [ -d $MEDIAWIKI_BASEDIR/extensions/Collection ]; then
        echo "" >> $MEDIAWIKI_SHARED/LocalSettings.php
        echo "# Collection Config" >> $MEDIAWIKI_SHARED/LocalSettings.php
        MEDIAWIKI_MWLIB_PASS=`tr -cd '[:alnum:]' < /dev/urandom | fold -w16 | head -n1`
        echo "\$wgGroupPermissions['user']['collectionsaveasuserpage'] = true;" >> $MEDIAWIKI_SHARED/LocalSettings.php
        echo "\$wgGroupPermissions['autoconfirmed']['collectionsaveascommunitypage'] = true;" >> $MEDIAWIKI_SHARED/LocalSettings.php
        echo "\$wgCollectionPODPartners = false;" >> $MEDIAWIKI_SHARED/LocalSettings.php
        echo "\$wgCollectionFormats = array('rl' => 'PDF', 'odf' => 'ODT');" >> $MEDIAWIKI_SHARED/LocalSettings.php
        echo "\$wgCollectionMWServeURL=\"http://mwlib:8899\";" >> $MEDIAWIKI_SHARED/LocalSettings.php
        echo "\$wgCollectionMWServeCredentials=\"mwlib:$MEDIAWIKI_MWLIB_PASS\";" >> $MEDIAWIKI_SHARED/LocalSettings.php
        php maintenance/createAndPromote.php --bot --conf $MEDIAWIKI_SHARED/LocalSettings.php mwlib $MEDIAWIKI_MWLIB_PASS
    fi
    if [ -e "$MEDIAWIKI_SHARED/dump.xml" ]; then
        php maintenance/importDump.php --conf $MEDIAWIKI_SHARED/LocalSettings.php $MEDIAWIKI_SHARED/dump.xml
    else
        if [ -e "$MEDIAWIKI_BASEDIR/maintenance/default.xml" ]; then
            php maintenance/importDump.php --conf $MEDIAWIKI_SHARED/LocalSettings.php $MEDIAWIKI_BASEDIR/maintenance/default.xml
        fi
    fi
fi

if [ -e "$MEDIAWIKI_SHARED/LocalSettings.php" -a $MEDIAWIKI_UPDATE = true ]; then
    cd $MEDIAWIKI_BASEDIR
    php maintenance/update.php --quick --conf $MEDIAWIKI_SHARED/LocalSettings.php
fi

export APACHE_SNAME=`grep -Po 'wgServer = ".*\/\/\K(.+)(?=";)' $MEDIAWIKI_SHARED/LocalSettings.php || echo "127.0.0.1"`
export APACHE_SCRIPTPATH=`grep -Po 'wgScriptPath = "\K(.+)(?=";)' $MEDIAWIKI_SHARED/LocalSettings.php || echo ""`
if [ "x$APACHE_SCRIPTPATH" = "x" ]; then
    export APACHE_SCRIPTPATH="/"
fi

for v in $(compgen -A variable | grep "MEDIAWIKI_.*") ; do
  unset ${v}
done

exec "$@"
