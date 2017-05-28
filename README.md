# What is MediaWiki?

MediaWiki is a free and open-source wiki app, used to power wiki websites such
as Wikipedia, Wiktionary and Commons, developed by the Wikimedia Foundation and
others.

> [wikipedia.org/wiki/MediaWiki](https://en.wikipedia.org/wiki/MediaWiki)

# How to use this image

    docker run --name some-mediawiki --link some-mysql:mysql -v /local/wiki_config/path:/etc/mediawiki:rw -v /local/wiki_images/path:/var/www/html/images:rw -d epuzanov/mediawiki

Partial explanation of arguments:

 - `--link` allows you to connect this container with a database container. See `Configure Database` below for more details.
 - `-v` is used to mount a shared folder with the container. See `Shared Volume` below for more details.

 Having troubling accessing your MediaWiki server? See `Accessing MediaWiki` below for help.

## Extra configuration options

Use the following environmental variables to generate a `LocalSettings.php` and perform automatic installation of MediaWiki.

 - `-e MEDIAWIKI_SITE_SERVER=` (**required** set this to the server host and include the protocol (and port if necessary) like `//my-wiki`; configures `$wgServer`)
 - `-e MEDIAWIKI_SITE_NAME=` (defaults to `MediaWiki`; configures `$wgSitename`)
 - `-e MEDIAWIKI_SITE_LANG=` (defaults to `en`; configures `$wgLanguageCode`)
 - `-e MEDIAWIKI_ADMIN_USER=` (defaults to `admin`; configures default administrator username)
 - `-e MEDIAWIKI_ADMIN_PASS=` (defaults to `password`; configures default administrator password)
 - `-e MEDIAWIKI_UPDATE=true` (defaults to `false`; run `php maintenance/update.php`)

As mentioned, this will generate the `LocalSettings.php` file that is required by MediaWiki. If you mounted a shared volume (see `Shared Volume` below), the generated `LocalSettings.php` will be automatically moved to your share volume allowing you to edit it.

## Choosing MediaWiki version

We currently track latest MediaWiki production branches, as run on wikipedia.org.

 - `epuzanov/mediawiki:latest` (currently uses `REL1_28`)

To use one of these pre-built containers, simply specify the tag as part of the `docker run` command:

    docker run --name some-mediawiki --link db -v /local/data/path:/data:rw -d epuzanov/mediawiki

## Docker Compose

See https://github.com/epuzanov/mediawiki-docker for a fully-featured docker-compose setup with mwlib.

### Run database, mwlib and wiki containers

    docker-compose up -d

#### Stop and remove database, mwlib and wiki containers

    docker-compose down

## Configure Database

The example above uses `--link` to connect the MediaWiki container with a running [mysql](https://hub.docker.com/_/mysql/) container. This is probably not the best idea for use in production, keeping data in docker containers can be dangerous.
Supported Databases:
 - MySQL (MEDIAWIKI_DB_TYPE=mysql)
 - Postgres (MEDIAWIKI_DB_TYPE=postgres)
 - SQLite (MEDIAWIKI_DB_TYPE=sqlite)
 - MS SQL (MEDIAWIKI_DB_TYPE=mssql)

### Using SQLite

You can use SQLite backand for small MediaWiki setup without dedicated Database Server. MediaWiki SQLite database files will be saved in wiki configuration Shared Volume.

    docker run --name some-mediawiki -v /local/wiki_config/path:/etc/mediawiki:rw -v /local/wiki_images/path:/var/www/html/images:rw -e MEDIAWIKI_DB_TYPE=sqlite -d epuzanov/mediawiki

### Using MySQL

You can use MySQL as your database server:

    docker run --name some-mediawiki --link some-mysql:db -v /local/wiki_config/path:/etc/mediawiki:rw -v /local/wiki_images/path:/var/www/html/images:rw -e MEDIAWIKI_DB_TYPE=mysql -e MEDIAWIKI_DB_INSTALL_PASSWORD=password -d epuzanov/mediawiki

### Using Postgres

You can use Postgres instead of MySQL as your database server:

    docker run --name some-mediawiki --link some-postgres:db -v /local/wiki_config/path:/etc/mediawiki:rw -v /local/wiki_images/path:/var/www/html/images:rw -e MEDIAWIKI_DB_TYPE=postgres -e MEDIAWIKI_DB_INSTALL_PASSWORD=password -d epuzanov/mediawiki

### Using Database Server

You can use the following environment variables for connecting to another database server:

 - `-e MEDIAWIKI_DB_TYPE=...` (defaults to `mysql`, but can also be `postgres`)
 - `-e MEDIAWIKI_DB_HOST=...` (defaults to the address of the linked database container)
 - `-e MEDIAWIKI_DB_PORT=...` (defaults to the port of the linked database container or to the default for specified db type)
 - `-e MEDIAWIKI_DB_USER=...` (defaults to `root` or `postgres` based on db type being `mysql`, or `postgres` respsectively)
 - `-e MEDIAWIKI_DB_PASSWORD=...` (defaults to the password of the linked database container)
 - `-e MEDIAWIKI_DB_NAME=...` (defaults to `mediawiki`)
 - `-e MEDIAWIKI_DB_SCHEMA`... (defaults to `mediawiki`, applies only to when using postgres)

If the `MEDIAWIKI_DB_NAME` specified does not already exist on the provided MySQL server, it will be created automatically upon container startup, provided that the `MEDIAWIKI_DB_INSTALL_USER` specified has the necessary permissions to create it.

To use with an external database server, use `MEDIAWIKI_DB_HOST` (along with
`MEDIAWIKI_DB_USER` and `MEDIAWIKI_DB_PASSWORD` if necessary):

    docker run --name some-mediawiki \
        -e MEDIAWIKI_DB_HOST=10.0.0.1
        -e MEDIAWIKI_DB_PORT=3306 \
        -e MEDIAWIKI_DB_USER=wikiuser \
        -e MEDIAWIKI_DB_PASSWORD=password \
        epuzanov/mediawiki

## Shared Volume

If provided mount a shared volume using the `-v` argument when running `docker run`, the mediawiki container will automatically look for a `LocalSettings.php` file, SSL certificats and wiki.png logo file. This allows you to easily configure (`LocalSettings.php`), update SSL certificats and MediaWiki Logo.

It is highly recommend you mount a shared volume so uploaded files and images will be outside of the docker container.

By default the shared volume must be mounted to `/etc/mediawiki` on the container.

## Accessing MediaWiki

If you'd like to be able to access the instance from the host without the container's IP, standard port mappings can be used using the `-p` or `-P` argument when running `docker run`. See [docs.docker.com](https://docs.docker.com/reference/run/#expose-incoming-ports) for more help.

    docker run --name some-mediawiki -p 80:80 -v /local/wiki_config/path:/etc/mediawiki:rw -v /local/wiki_images/path:/var/www/html/images:rw -e MEDIAWIKI_DB_TYPE=sqlite -d epuzanov/mediawiki

Then, access it via `http://localhost` or `http://host-ip` in a browser. You can also force using HTTPS with `-p 81:80` argument:

    docker run --name some-mediawiki -p 80:81 -p 443:443 -v /local/wiki_config/path:/etc/mediawiki:rw -v /local/wiki_images/path:/var/www/html/images:rw -e MEDIAWIKI_DB_TYPE=sqlite -d epuzanov/mediawiki

## Enabling SSL/TLS/HTTPS

To enable SSL on your server, place your certificate files inside your mounted share volume as `server.key`, `server.crt` and `server-ca.crt`.

**Note** When enabling SSL, you must update the `$wgServer` in your `LocalSettings.php` to include `https://` or `//` as the prefix. If using automatic install, update the `MEDIAWIKI_SITE_SERVER` environmental variable.
