*This project has been created as part of the 42 curriculum by ssawa.*

# Inception

## Description

Inception builds a small production-style web infrastructure with Docker
Compose. The stack contains three isolated services:

- `nginx`: the only public entry point, listening on HTTPS port `443` and
  accepting only TLSv1.2 or TLSv1.3.
- `wordpress`: WordPress served by PHP-FPM, without NGINX.
- `mariadb`: the database service, without NGINX.

Each service is built from its own Dockerfile under `srcs/requirements/`.
The images are based on `debian:bookworm`, the penultimate stable Debian release
as of July 2026. No service image is pulled from Docker Hub except for the
allowed Debian base image.

The project uses a private Docker bridge network for internal communication.
Only NGINX publishes a host port; WordPress and MariaDB are reachable only by
service name inside the Compose network. WordPress files and MariaDB data are
stored in named Docker volumes whose local driver devices point to
`/home/<login>/data/wordpress` and `/home/<login>/data/mariadb`.

### Main Design Choices

**Virtual machine vs Docker:** a VM virtualizes a complete operating system,
including its own kernel. Docker containers share the host kernel and isolate
processes with Linux namespaces and cgroups. This makes containers lighter and
more reproducible for service-oriented infrastructure.

**Secrets vs environment variables:** non-sensitive configuration such as the
domain name and database name is stored in `srcs/.env`. Passwords are mounted as
Docker Compose secrets under `/run/secrets/...`, which avoids exposing them as
plain environment values through `docker inspect`.

**Docker network vs host network:** the stack uses a user-defined bridge network
so containers can resolve each other by service name (`mariadb`, `wordpress`)
without exposing internal ports on the host. `network: host`, `links`, and
`--link` are not used.

**Docker volumes vs bind mounts:** the services mount Docker named volumes
(`mariadb_data` and `wordpress_data`), not raw host paths. Those named volumes
use local driver options so Docker stores their data under `/home/<login>/data`,
as required by the subject.

## Instructions

Create the local environment file:

```sh
cp srcs/.env.example srcs/.env
```

Edit `srcs/.env` so `USER_LOGIN` and `DOMAIN_NAME` match your 42 login, for
example `ssawa` and `ssawa.42.fr`.

Create local secret files. These files are intentionally ignored by Git:

```sh
mkdir -p secrets
read -rsp 'Database password: ' DB_PASSWORD && printf '\n'
printf '%s\n' "$DB_PASSWORD" > secrets/db_password.txt
read -rsp 'Database root password: ' DB_ROOT_PASSWORD && printf '\n'
printf '%s\n' "$DB_ROOT_PASSWORD" > secrets/db_root_password.txt
read -rsp 'WordPress owner password: ' WP_OWNER_PASSWORD && printf '\n'
printf '%s\n' "$WP_OWNER_PASSWORD" > secrets/wp_admin_password.txt
read -rsp 'WordPress author password: ' WP_AUTHOR_PASSWORD && printf '\n'
printf '%s\n' "$WP_AUTHOR_PASSWORD" > secrets/wp_user_password.txt
unset DB_PASSWORD DB_ROOT_PASSWORD WP_OWNER_PASSWORD WP_AUTHOR_PASSWORD
```

Add the domain to the VM host resolver:

```sh
echo '127.0.0.1 ssawa.42.fr' | sudo tee -a /etc/hosts
```

Build and start the stack:

```sh
make
```

Useful commands:

```sh
make ps
make logs
make config
make down
make clean
make fclean
```

After startup, open:

- Website: `https://<login>.42.fr`
- WordPress dashboard: `https://<login>.42.fr/wp-admin`

The TLS certificate is self-signed, so the browser will show a certificate
warning. That is expected for this project.

## Resources

- 42 Inception subject: `docs/subject.md` and `docs/subject.ja.md`
- Review defense notes in Japanese: `docs/inception_manual/review_book.ja.md`
- User guide: `USER_DOC.md`
- Developer guide: `DEV_DOC.md`
- Debian releases: https://www.debian.org/releases/
- Docker Compose documentation: https://docs.docker.com/compose/
- Dockerfile reference: https://docs.docker.com/reference/dockerfile/
- NGINX documentation: https://nginx.org/en/docs/
- MariaDB documentation: https://mariadb.com/kb/en/documentation/
- WordPress CLI documentation: https://developer.wordpress.org/cli/commands/
- PHP-FPM documentation: https://www.php.net/manual/en/install.fpm.php

AI assistance was used to review the project against the subject, harden the
entrypoint scripts, improve the Docker Compose configuration, and draft
review-oriented documentation. The resulting files should still be read,
tested, and defended by the student during peer evaluation.
