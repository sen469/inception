# srcs 実装注釈書

この文書は、`srcs/` 配下の各ファイルについて「何が書かれているか」だけでなく、「なぜその書き方にしているか」を説明するための注釈書です。

レビューで聞かれる可能性が高い観点は次の通りです。

- 課題要件をどの行で満たしているか。
- Docker の責務分離、ネットワーク分離、永続化をどう表現しているか。
- パスワードをなぜ `.env` ではなく secrets に分けているか。
- entrypoint がなぜ最後に `exec` しているか。
- 再起動時にデータを壊さないため、どこで冪等性を確保しているか。

`srcs/.env` はローカル入力であり Git 管理外です。この文書では tracked なテンプレートである `srcs/.env.example` を説明します。

## 1. `srcs/.env.example`

```env
USER_LOGIN=ssawa
DOMAIN_NAME=ssawa.42.fr

MYSQL_DATABASE=wordpress
MYSQL_USER=wp_user

WP_ADMIN_USER=ssawa_owner
WP_ADMIN_EMAIL=ssawa@example.com

WP_USER=ssawa_author
WP_USER_EMAIL=author@example.com
```

このファイルは `.env` のひな形です。Compose の変数展開、Makefile のデータ保存先、WordPress の初期ユーザー作成に使う「非秘密情報」だけを置きます。

`USER_LOGIN` は `/home/${USER_LOGIN}/data/...` のパスに使います。課題はデータを `/home/login/data` に置くことを要求しているため、ログイン名を Compose と Makefile の両方から参照できるようにしています。

`DOMAIN_NAME` は `login.42.fr` 形式のドメインです。NGINX の証明書の CN、NGINX の `server_name`、WordPress の `WP_HOME` / `WP_SITEURL` に使います。

`MYSQL_DATABASE` と `MYSQL_USER` は WordPress 用の DB と DB ユーザーです。root ユーザーで WordPress を接続しないために、専用の一般 DB ユーザーを作ります。

`WP_ADMIN_USER` は WordPress 管理者です。課題では `admin` という管理者名が禁止されているため、`setup.sh` 側で `admin` を含む名前を拒否します。ここでは `ssawa_owner` とし、明示的に `admin` を避けています。

パスワードがない理由は重要です。課題は `.env` の使用を要求しますが、同時に資格情報を Git リポジトリへ置くことを強く避けるべきとしています。そのため `.env` は非秘密値、`secrets/*.txt` は秘密値という分担にしています。

## 2. `srcs/docker-compose.yml`

### 2.1 MariaDB サービス

```yaml
services:
  mariadb:
    build:
      context: ./requirements/mariadb
    image: mariadb
    container_name: mariadb
    restart: always
    environment:
      MYSQL_DATABASE: ${MYSQL_DATABASE}
      MYSQL_USER: ${MYSQL_USER}
      MYSQL_PASSWORD_FILE: /run/secrets/db_password
      MYSQL_ROOT_PASSWORD_FILE: /run/secrets/db_root_password
    secrets:
      - db_password
      - db_root_password
    volumes:
      - mariadb_data:/var/lib/mysql
    networks:
      - inception_network
```

`build.context` は MariaDB 専用 Dockerfile の場所です。各サービスを専用 Dockerfile からビルドする課題要件を満たします。

`image: mariadb` と `container_name: mariadb` は、サービス名とイメージ名を対応させるためです。レビューでは `docker images`、`docker ps`、Compose ファイルを見ながら、サービス単位で分離されていることを説明できます。

`restart: always` は、コンテナが落ちたときに Docker が再起動するための設定です。課題の「クラッシュ時に再起動する」要件に対応します。

`MYSQL_PASSWORD_FILE` と `MYSQL_ROOT_PASSWORD_FILE` は、パスワード本体ではなく secret ファイルのパスです。entrypoint はこのファイルを読みます。Compose の environment にパスワードを直接書かないため、`docker inspect` で秘密値が見えにくくなります。

`mariadb_data:/var/lib/mysql` は DB の実データを named volume に保存します。MariaDB は `/var/lib/mysql` にデータディレクトリを作るため、ここを永続化しないとコンテナ再作成時に DB が消えます。

`ports:` がない点も重要です。MariaDB は Docker network 内からのみアクセスさせ、ホストには公開しません。

### 2.2 WordPress サービス

```yaml
  wordpress:
    build:
      context: ./requirements/wordpress
    image: wordpress
    container_name: wordpress
    restart: always
    depends_on:
      - mariadb
    environment:
      DOMAIN_NAME: ${DOMAIN_NAME}
      MYSQL_DATABASE: ${MYSQL_DATABASE}
      MYSQL_USER: ${MYSQL_USER}
      MYSQL_PASSWORD_FILE: /run/secrets/db_password
      WP_ADMIN_USER: ${WP_ADMIN_USER}
      WP_ADMIN_PASSWORD_FILE: /run/secrets/wp_admin_password
      WP_ADMIN_EMAIL: ${WP_ADMIN_EMAIL}
      WP_USER: ${WP_USER}
      WP_USER_PASSWORD_FILE: /run/secrets/wp_user_password
      WP_USER_EMAIL: ${WP_USER_EMAIL}
    secrets:
      - db_password
      - wp_admin_password
      - wp_user_password
    volumes:
      - wordpress_data:/var/www/html
    networks:
      - inception_network
```

WordPress は `mariadb` に依存するため `depends_on` を置いています。ただし、`depends_on` は「MariaDB が SQL を受け付ける状態」までは保証しません。そのため `setup.sh` 側でも `mysqladmin ping` による待機を行います。

`DOMAIN_NAME` は WordPress のサイト URL と管理画面 URL を HTTPS に固定するために使います。

DB パスワード、WordPress 管理者パスワード、一般ユーザーパスワードはすべて `_FILE` で渡します。`.env` には置かず、Compose secrets から読みます。

`wordpress_data:/var/www/html` は WordPress 本体、`wp-config.php`、アップロードファイル、テーマ、プラグインを永続化するためです。WordPress の実行ディレクトリを volume にしないと、コンテナ再作成時にサイトファイルが失われます。

WordPress にも `ports:` はありません。PHP-FPM は NGINX から `wordpress:9000` で呼ばれるだけです。

### 2.3 NGINX サービス

```yaml
  nginx:
    build:
      context: ./requirements/nginx
      args:
        DOMAIN_NAME: ${DOMAIN_NAME}
    image: nginx
    container_name: nginx
    restart: always
    depends_on:
      - wordpress
    ports:
      - "443:443"
    volumes:
      - wordpress_data:/var/www/html
    networks:
      - inception_network
```

NGINX は唯一の外部入口です。そのため、`ports:` はここだけにあります。`443:443` によりホストの HTTPS 443 番を NGINX コンテナの 443 番へ接続します。

`args.DOMAIN_NAME` はビルド時に自己署名証明書の CN と `nginx.conf` の `server_name` に反映します。実行時の環境変数ではなく、イメージ内の設定ファイルへ埋め込む設計です。

`wordpress_data:/var/www/html` を NGINX にもマウントする理由は、静的ファイルや PHP ファイルの存在確認を NGINX が行うためです。PHP の実行自体は WordPress コンテナの PHP-FPM が担当します。

### 2.4 Volume、Network、Secrets

```yaml
volumes:
  mariadb_data:
    driver: local
    driver_opts:
      type: none
      o: bind
      device: /home/${USER_LOGIN:?set USER_LOGIN in srcs/.env}/data/mariadb
  wordpress_data:
    driver: local
    driver_opts:
      type: none
      o: bind
      device: /home/${USER_LOGIN:?set USER_LOGIN in srcs/.env}/data/wordpress
```

サービス側は named volume をマウントしていますが、volume の実体は local driver option で `/home/<login>/data/...` に向けています。これにより「Docker volume を使う」ことと「ホスト上の指定パスにデータを置く」ことを同時に満たします。

`${USER_LOGIN:?set USER_LOGIN in srcs/.env}` は、`USER_LOGIN` が未設定なら Compose 展開時に失敗させるための書き方です。空のまま `/home//data` のような危険なパスを作らせません。

```yaml
networks:
  inception_network:
    driver: bridge
```

user-defined bridge network を使うことで、サービス名 `nginx`、`wordpress`、`mariadb` が DNS 名として使えます。`network: host`、`links`、`--link` は使いません。

```yaml
secrets:
  db_password:
    file: ../secrets/db_password.txt
  db_root_password:
    file: ../secrets/db_root_password.txt
  wp_admin_password:
    file: ../secrets/wp_admin_password.txt
  wp_user_password:
    file: ../secrets/wp_user_password.txt
```

Compose ファイルは `srcs/docker-compose.yml` なので、`../secrets/...` はリポジトリルート直下の `secrets/` を指します。これらのファイルは Git 管理外です。

## 3. `.dockerignore`

NGINX:

```dockerignore
*
!Dockerfile
!conf
!conf/**
!tools
!tools/**
```

MariaDB / WordPress:

```dockerignore
*
!Dockerfile
!conf
!conf/**
!tools
!tools/**
```

最初の `*` は、ビルドコンテキストに全ファイルを送らないという意味です。その後の `!` で、ビルドに必要な Dockerfile、設定ファイル、entrypoint だけを許可します。

これにより、不要なファイルや誤って置いた秘密情報がイメージのビルドコンテキストに入るリスクを下げます。3サービスとも起動スクリプトや設定ファイルなど、ビルドに必要なファイルだけを許可しています。

## 4. `srcs/requirements/nginx/Dockerfile`

```dockerfile
FROM debian:bookworm
```

課題は `latest` を禁止し、Debian の安定版のうち最後から2番目のバージョンを使うことを求めています。2026年7月時点では `bookworm` がその解釈に合います。

```dockerfile
RUN apt-get update && apt-get install -y --no-install-recommends \
    bash \
    netcat-openbsd \
    nginx \
    openssl \
    && rm -rf /var/lib/apt/lists/*
```

NGINX 本体、自己署名証明書を作るための OpenSSL、起動待ち script 用の Bash、TCP 接続確認用の `netcat-openbsd` を入れます。`--no-install-recommends` は不要な推奨パッケージを減らすためです。`/var/lib/apt/lists/*` を消すのは、apt のインデックスをイメージに残さないためです。

```dockerfile
ARG DOMAIN_NAME=ssawa.42.fr
RUN openssl req -x509 -nodes \
    -days 365 \
    -newkey rsa:4096 \
    -out /etc/nginx/ssl/inception.crt \
    -keyout /etc/nginx/ssl/inception.key \
    -subj "/C=JP/ST=Tokyo/L=Tokyo/O=42Tokyo/OU=Student/CN=${DOMAIN_NAME}"
```

自己署名証明書をビルド時に作ります。`-nodes` は秘密鍵を暗号化しない指定です。暗号化すると NGINX 起動時にパスフレーズ入力が必要になり、コンテナの自動起動に向きません。`CN=${DOMAIN_NAME}` により証明書の識別名を評価用ドメインに合わせます。

```dockerfile
COPY conf/nginx.conf /etc/nginx/nginx.conf
RUN sed -i "s/__DOMAIN_NAME__/${DOMAIN_NAME}/g" /etc/nginx/nginx.conf
```

設定ファイル内の `__DOMAIN_NAME__` をビルド時引数で置換します。テンプレート化することで、設定ファイルをログイン名固定にしません。

```dockerfile
COPY tools/entrypoint.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/entrypoint.sh
EXPOSE 443
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
```

entrypoint は `wordpress:9000` が接続可能になるまで待ってから NGINX を起動します。`EXPOSE` はドキュメント的な宣言です。実際の公開は Compose の `ports:` が行います。

## 5. `srcs/requirements/nginx/tools/entrypoint.sh`

```bash
#!/bin/bash
set -euo pipefail

host="${WORDPRESS_HOST:-wordpress}"
port="${WORDPRESS_PORT:-9000}"
attempts=0
max_attempts=60
```

接続先は既定で `wordpress:9000` です。環境変数で上書きできるようにしているため、将来サービス名やポートを変えた場合にも script の編集なしで対応できます。

```bash
until nc -z "${host}" "${port}" >/dev/null 2>&1; do
    attempts=$((attempts + 1))
    if [ "${attempts}" -ge "${max_attempts}" ]; then
        echo "Error: ${host}:${port} did not become reachable within 120 seconds." >&2
        exit 1
    fi
    echo "Waiting for ${host}:${port}..."
    sleep 2
done
```

`nc -z` はデータを送らずに TCP 接続できるかだけを確認します。Compose の `depends_on` は起動順だけを保証し、PHP-FPM が listen 済みかは保証しません。そのため、NGINX が先に起動して一時的な 502 を返すことを避けるためにここで待ちます。最大120秒で失敗させ、無限待機にはしません。

```bash
exec nginx -g "daemon off;"
```

最後は `exec` で NGINX をフォアグラウンド起動します。shell を NGINX に置き換えるため、コンテナの PID 1 は最終的に NGINX になります。`tail -f` のような維持ハックではありません。

## 6. `srcs/requirements/nginx/conf/nginx.conf`

```nginx
events {
    worker_connections 1024;
}
```

NGINX には `events` ブロックが必須です。`worker_connections` は同時接続数の上限です。この課題では高負荷運用ではないため、一般的な値で十分です。

```nginx
http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;
    server_tokens off;
```

`mime.types` を読み込むことで CSS、画像、JavaScript などを適切な Content-Type で返せます。`server_tokens off` は NGINX のバージョン情報をレスポンスに出しにくくする設定です。

```nginx
server {
    listen 443 ssl;
    listen [::]:443 ssl;
    server_name __DOMAIN_NAME__;
```

IPv4 と IPv6 の 443 番で HTTPS を待ち受けます。80 番は listen しません。課題が「443 のみ」を要求しているためです。

```nginx
ssl_certificate     /etc/nginx/ssl/inception.crt;
ssl_certificate_key /etc/nginx/ssl/inception.key;
ssl_protocols TLSv1.2 TLSv1.3;
ssl_prefer_server_ciphers off;
```

証明書と鍵は Dockerfile で生成したものです。`ssl_protocols TLSv1.2 TLSv1.3;` により TLSv1.0 と TLSv1.1 を拒否します。これは課題要件そのものです。

```nginx
root /var/www/html;
index index.php index.html index.htm;
```

`/var/www/html` は WordPress volume のマウント先です。NGINX と WordPress が同じファイルツリーを見るため、NGINX は静的ファイルの有無を判断できます。

```nginx
location / {
    try_files $uri $uri/ /index.php?$args;
}
```

まず実ファイル、次にディレクトリを探し、なければ WordPress の `index.php` に渡します。これがないと、WordPress の投稿ページや固定ページのパーマリンクが 404 になりやすくなります。

```nginx
location ~ \.php$ {
    try_files $uri =404;
    fastcgi_pass wordpress:9000;
    fastcgi_index index.php;
    include fastcgi_params;
    fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
    fastcgi_param HTTPS on;
}
```

PHP ファイルは NGINX 自身では実行せず、WordPress コンテナの PHP-FPM に FastCGI で渡します。`wordpress` は Docker network の DNS 名です。`SCRIPT_FILENAME` は PHP-FPM に「どの PHP ファイルを実行するか」を伝えるために必要です。`HTTPS on` は WordPress に HTTPS リクエストとして認識させるためです。

```nginx
location ~ /\. {
    deny all;
}
```

`.htaccess`、`.git`、`.env` のような隠しファイルを Web 経由で返さないための防御です。

## 6. `srcs/requirements/mariadb/Dockerfile`

```dockerfile
FROM debian:bookworm
```

NGINX と同じく、`latest` を避けて Debian の明示タグを使います。

```dockerfile
RUN apt-get update && apt-get install -y --no-install-recommends \
    mariadb-server \
    mariadb-client \
    && rm -rf /var/lib/apt/lists/*
```

`mariadb-server` は DB 本体、`mariadb-client` は初期化時に `mysql` や `mysqladmin` を使うために必要です。

```dockerfile
COPY conf/50-server.cnf /etc/mysql/mariadb.conf.d/50-server.cnf
COPY tools/init.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/init.sh
```

サーバー設定と entrypoint をイメージへ入れます。`chmod +x` は Dockerfile 内で実行権限を保証するためです。ホスト側のファイル権限に依存しません。

```dockerfile
EXPOSE 3306
ENTRYPOINT ["/usr/local/bin/init.sh"]
```

`EXPOSE 3306` は MariaDB が使う内部ポートの宣言です。Compose で `ports:` を書いていないため、ホストへは公開されません。`ENTRYPOINT` は初期化と本起動をまとめて担当します。

## 7. `srcs/requirements/mariadb/conf/50-server.cnf`

```ini
[mysqld]
bind-address = 0.0.0.0
port = 3306
datadir = /var/lib/mysql
socket = /run/mysqld/mysqld.sock
```

`bind-address = 0.0.0.0` は、別コンテナの WordPress から接続を受けるためです。`127.0.0.1` にすると MariaDB コンテナ自身からしか接続できません。

ただし、外部公開とは違います。Compose で `3306:3306` を書いていないため、ホストや外部ネットワークから直接 DB へ入る設計ではありません。

`datadir = /var/lib/mysql` は named volume のマウント先と一致します。DB の実体は volume に残るため、コンテナ再作成後もデータを維持できます。

## 8. `srcs/requirements/mariadb/tools/init.sh`

### 8.1 厳格モード

```bash
#!/bin/bash
set -euo pipefail
```

`bash` を使うのは、配列的な展開や `[[ ... =~ ... ]]` の正規表現判定を使うためです。`set -euo pipefail` は、エラー、未定義変数、パイプ内の失敗を見逃しにくくします。

### 8.2 環境変数と secrets の検証

```bash
require_env() {
    local name="$1"
    if [ -z "${!name:-}" ]; then
        echo "Error: ${name} is not set." >&2
        exit 1
    fi
}
```

必須変数が空なら即終了します。未設定のまま DB 名やユーザー名が空になると、意図しない SQL を実行する危険があるためです。

```bash
read_secret() {
    local name="$1"
    local file_name="${name}_FILE"
    local file_path="${!file_name:-}"

    if [ -n "${file_path}" ]; then
        if [ ! -r "${file_path}" ]; then
            echo "Error: ${file_name} points to an unreadable file: ${file_path}" >&2
            exit 1
        fi
        export "${name}=$(tr -d '\r\n' < "${file_path}")"
    fi

    if [ -z "${!name:-}" ]; then
        echo "Error: ${name} or ${file_name} must be set." >&2
        exit 1
    fi
}
```

`MYSQL_PASSWORD_FILE=/run/secrets/db_password` のような変数から secret ファイルを読みます。`tr -d '\r\n'` は、ファイル末尾の改行をパスワードの一部として扱わないためです。

### 8.3 SQL 用の入力制限

```bash
require_simple_identifier() {
    local name="$1"
    local value="${!name}"
    if ! [[ "${value}" =~ ^[A-Za-z0-9_]+$ ]]; then
        echo "Error: ${name} must contain only letters, digits, and underscores." >&2
        exit 1
    fi
}
```

DB 名と DB ユーザー名は SQL 識別子として使うため、英数字と underscore に制限します。これにより、設定ミスや SQL への予期しない文字混入を避けます。

```bash
sql_escape() {
    local value="$1"
    value="${value//\\/\\\\}"
    value="${value//\'/\\\'}"
    printf "%s" "${value}"
}
```

パスワードは SQL 文字列として使うため、バックスラッシュとシングルクォートを escape します。識別子は制限し、パスワードは escape する、という役割分担です。

### 8.4 初期化判定と権限修正

```bash
chown -R mysql:mysql /run/mysqld
chown -R mysql:mysql /var/lib/mysql
```

volume の実体はホスト側ディレクトリです。所有者がずれていると MariaDB が書けないため、起動前に `mysql:mysql` に揃えます。

```bash
db_initialized=true
if [ ! -d "/var/lib/mysql/mysql" ]; then
    db_initialized=false
    mysql_install_db --user=mysql --datadir=/var/lib/mysql > /dev/null
fi
```

`/var/lib/mysql/mysql` は MariaDB のシステム DB です。これがなければ初回起動と判断し、`mysql_install_db` を実行します。存在する場合は既存データを使い、DB を壊しません。

### 8.5 一時サーバーと後始末

```bash
mysqld_safe --datadir=/var/lib/mysql &
temporary_pid="$!"
trap cleanup_temporary_server EXIT
```

SQL で root パスワード、DB、ユーザー、権限を設定するには、一度 MariaDB を起動する必要があります。ただしこれは初期化用の一時起動です。最後に本番プロセスとして `mysqld` を `exec` します。

`trap` は途中で失敗した場合にも一時 MariaDB を止めるためです。一時プロセスが残ると、同じデータディレクトリを本起動する際に衝突します。

### 8.6 起動待ちと SQL 実行

```bash
until mysqladmin ping >/dev/null 2>&1; do
    startup_attempts=$((startup_attempts + 1))
    if [ "${startup_attempts}" -ge 60 ]; then
        echo "Error: MariaDB did not become ready within 60 seconds." >&2
        exit 1
    fi
    sleep 1
done
```

無限待機ではなく最大60秒で失敗させます。レビューでは「失敗時に原因を見つけやすくするため、永久ループではなく timeout にしている」と説明できます。

```sql
CREATE DATABASE IF NOT EXISTS `...`;
CREATE USER IF NOT EXISTS '...'@'%' IDENTIFIED BY '...';
ALTER USER '...'@'%' IDENTIFIED BY '...';
GRANT ALL PRIVILEGES ON `...`.* TO '...'@'%';
FLUSH PRIVILEGES;
```

`IF NOT EXISTS` により再実行時に失敗しにくくしています。`ALTER USER` も実行するため、既存ユーザーのパスワードを secret に合わせ直せます。`'%'` は Docker network 内の別コンテナから接続できるようにする指定です。

### 8.7 本起動

```bash
mysqladmin -u root -p"${MYSQL_ROOT_PASSWORD}" shutdown
wait "${temporary_pid}" >/dev/null 2>&1 || true
trap - EXIT
exec mysqld --user=mysql --datadir=/var/lib/mysql
```

一時サーバーを止めてから、MariaDB 本体をフォアグラウンドで起動します。`exec` により shell が `mysqld` に置き換わるため、Docker の停止シグナルが MariaDB に直接届きます。

## 9. `srcs/requirements/wordpress/Dockerfile`

```dockerfile
FROM debian:bookworm
```

他サービスと同じく Debian の明示タグです。サービスごとに専用 Dockerfile を持つ課題要件を満たします。

```dockerfile
RUN apt-get update && apt-get install -y --no-install-recommends \
    php-fpm \
    php-cli \
    php-mysqli \
    curl \
    ca-certificates \
    openssl \
    mariadb-client \
    && rm -rf /var/lib/apt/lists/*
```

`php-fpm` は NGINX から FastCGI で呼ばれる PHP 実行環境です。`php-cli` は WP-CLI を実行するために必要です。`php-mysqli` は WordPress が MariaDB に接続するために必要です。`mariadb-client` は `mysqladmin ping` で DB 起動待ちをするために入れます。`openssl` は WordPress の secret key / salt をローカル生成するために使います。

```dockerfile
RUN curl -fsSL -o wp-cli.phar https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar \
    && chmod +x wp-cli.phar \
    && mv wp-cli.phar /usr/local/bin/wp
```

WP-CLI は WordPress の設定、インストール、ユーザー作成を非対話で行うために使います。`-f` は HTTP エラーで失敗、`-sS` は静かにしつつエラーは表示、`-L` は redirect 追従です。

```dockerfile
RUN mkdir -p /usr/src/wordpress \
    && wp core download --path=/usr/src/wordpress --allow-root \
    && chown -R www-data:www-data /usr/src/wordpress
```

WordPress 本体をビルド時に取得してイメージ内へ置きます。起動時に毎回外部ネットワークから WordPress を取得しないため、起動の再現性が上がります。初回起動時はここから volume へコピーします。

```dockerfile
COPY conf/www.conf /tmp/www.conf
RUN set -eux; \
    pool_dir="$(find /etc/php -path '*/fpm/pool.d' -type d | head -n 1)"; \
    test -n "${pool_dir}"; \
    cp /tmp/www.conf "${pool_dir}/www.conf"; \
    rm /tmp/www.conf
```

Debian の PHP minor version により `/etc/php/8.2/fpm/pool.d` のようなパスが変わる可能性があります。そのため固定パスではなく `find` で実ディレクトリを探します。見つからなければ `test -n` でビルドを失敗させます。

```dockerfile
RUN mkdir -p /var/www/html && chown -R www-data:www-data /var/www/html
COPY tools/setup.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/setup.sh
WORKDIR /var/www/html
EXPOSE 9000
ENTRYPOINT ["/usr/local/bin/setup.sh"]
```

`/var/www/html` は WordPress volume のマウント先です。`WORKDIR` をそこにすることで WP-CLI の実行場所を揃えます。`EXPOSE 9000` は PHP-FPM の内部ポートです。ホスト公開はしません。

## 10. `srcs/requirements/wordpress/conf/www.conf`

```ini
[www]
user = www-data
group = www-data
listen = 0.0.0.0:9000
clear_env = no
pm = dynamic
pm.max_children = 5
pm.start_servers = 2
pm.min_spare_servers = 1
pm.max_spare_servers = 3
```

`user` と `group` は PHP-FPM worker の実行ユーザーです。WordPress ファイルの所有者も `www-data` に揃えるため、ファイル書き込み権限の問題を減らせます。

`listen = 0.0.0.0:9000` は、別コンテナの NGINX から FastCGI 接続を受けるためです。`127.0.0.1:9000` にすると WordPress コンテナ自身からしか接続できません。

`clear_env = no` は PHP-FPM worker から環境変数を参照できるようにする設定です。この実装では主な初期化は entrypoint の shell と WP-CLI が行いますが、WordPress や PHP 側で環境値が必要になった場合にも隠されません。

`pm = dynamic` と各 `pm.*` は PHP-FPM の worker 数制御です。課題規模では小さな値で十分です。

## 11. `srcs/requirements/wordpress/tools/setup.sh`

### 11.1 入力検証

```bash
require_env DOMAIN_NAME
require_env MYSQL_DATABASE
require_env MYSQL_USER
require_env WP_ADMIN_USER
require_env WP_ADMIN_EMAIL
require_env WP_USER
require_env WP_USER_EMAIL
read_secret MYSQL_PASSWORD
read_secret WP_ADMIN_PASSWORD
read_secret WP_USER_PASSWORD
```

非秘密値は環境変数から、秘密値は secret ファイルから読みます。DB パスワード、WordPress 管理者パスワード、一般ユーザーパスワードを `.env` に置かない設計です。

```bash
case "$(printf '%s' "${WP_ADMIN_USER}" | tr '[:upper:]' '[:lower:]')" in
    *admin*)
        echo "Error: WP_ADMIN_USER must not contain 'admin'." >&2
        exit 1
        ;;
esac
```

課題は管理者名に `admin` を含めることを禁止しています。大文字小文字を無視するため、いったん lower-case に変換してから判定します。

### 11.2 WordPress 本体の配置

```bash
cd /var/www/html
if [ ! -f "wp-load.php" ]; then
    cp -a /usr/src/wordpress/. /var/www/html/
fi
chown -R www-data:www-data /var/www/html
```

`wp-load.php` は WordPress 本体が存在するかの目印です。なければ Dockerfile で用意した `/usr/src/wordpress` から volume へコピーします。すでに存在する場合はコピーしないため、再起動で既存ファイルを上書きしません。

### 11.3 MariaDB の起動待ち

```bash
until mysqladmin ping -h mariadb -u "${MYSQL_USER}" -p"${MYSQL_PASSWORD}" --silent; do
    db_attempts=$((db_attempts + 1))
    if [ "${db_attempts}" -ge 60 ]; then
        echo "Error: MariaDB did not become reachable within 120 seconds." >&2
        exit 1
    fi
    sleep 2
done
```

Compose の `depends_on` だけでは DB の準備完了を保証できません。ここで実際に MariaDB へ接続できるまで待ちます。60回、2秒間隔なので最大120秒です。無限待機にしないため、障害時は明確に失敗します。

### 11.4 `wp-config.php` 作成と salt

```bash
if [ ! -f "wp-config.php" ]; then
    wp config create \
        --dbname="${MYSQL_DATABASE}" \
        --dbuser="${MYSQL_USER}" \
        --dbpass="${MYSQL_PASSWORD}" \
        --dbhost=mariadb \
        --skip-check \
        --skip-salts \
        --allow-root
    set_wp_secret_key AUTH_KEY
    ...
fi
```

`wp-config.php` がなければ作成します。存在する場合は再作成しません。再作成すると既存サイト設定を壊す可能性があるためです。

`--dbhost=mariadb` は Compose サービス名です。固定 IP ではないため、コンテナ再作成後も名前解決で接続できます。

`--skip-salts` にしているのは、WP-CLI が外部 API から salt を取得する挙動に依存しないためです。代わりに `openssl rand -base64 48` でローカル生成した値を `wp config set` します。既存 `wp-config.php` がある場合は salt を再生成しないため、再起動のたびにログインセッションが無効化されることも避けられます。

### 11.5 HTTPS 設定

```bash
wp config set FORCE_SSL_ADMIN true --raw --allow-root
wp config set WP_HOME "https://${DOMAIN_NAME}" --allow-root
wp config set WP_SITEURL "https://${DOMAIN_NAME}" --allow-root
```

NGINX は HTTPS を終端し、PHP-FPM へ `HTTPS on` を渡します。WordPress 側でもサイト URL と管理画面を HTTPS に固定することで、HTTP URL への redirect や mixed content を避けます。

### 11.6 WordPress の初期インストールとユーザー作成

```bash
if ! wp core is-installed --allow-root; then
    wp core install \
        --url="https://${DOMAIN_NAME}" \
        --title="Inception WordPress" \
        --admin_user="${WP_ADMIN_USER}" \
        --admin_password="${WP_ADMIN_PASSWORD}" \
        --admin_email="${WP_ADMIN_EMAIL}" \
        --skip-email \
        --allow-root
fi
```

`wp core is-installed` で DB 側の初期化済み状態を確認します。未インストールの場合だけ管理者を作るため、再起動で WordPress を二重初期化しません。

```bash
if ! wp user get "${WP_USER}" --allow-root >/dev/null 2>&1; then
    wp user create \
        "${WP_USER}" \
        "${WP_USER_EMAIL}" \
        --user_pass="${WP_USER_PASSWORD}" \
        --role=author \
        --allow-root
fi
```

一般ユーザーも存在確認してから作成します。`--role=author` は管理者ではない通常ユーザーを用意するためです。課題は管理者とは別のユーザーを要求しています。

### 11.7 PHP-FPM の本起動

```bash
mkdir -p /run/php
php_fpm="$(command -v php-fpm || find /usr/sbin -maxdepth 1 -name 'php-fpm*' | sort | tail -n 1)"
if [ -z "${php_fpm}" ]; then
    echo "Error: php-fpm binary was not found." >&2
    exit 1
fi
exec "${php_fpm}" -F
```

Debian の PHP-FPM バイナリ名は環境により `php-fpm` または `php-fpm8.2` のようになる可能性があります。そのため `command -v` と `find` の両方で探します。

最後の `exec ... -F` が重要です。`-F` は PHP-FPM をフォアグラウンドで起動する指定です。`exec` により shell が PHP-FPM に置き換わるため、コンテナの PID 1 が PHP-FPM になります。`tail -f` でコンテナを維持する必要はありません。

## 12. レビューでの答え方

`なぜこのファイルが必要ですか。` と聞かれたら、次のように答えます。

| ファイル | 一言での責務 |
| --- | --- |
| `srcs/.env.example` | 非秘密設定値のテンプレート。実 `.env` は Git 管理外。 |
| `srcs/docker-compose.yml` | 3サービス、2 volume、1 network、4 secrets の接続図。 |
| `nginx/.dockerignore` | NGINX ビルドに必要なファイルだけを context に入れる。 |
| `nginx/Dockerfile` | Debian から NGINX と自己署名 TLS 証明書を持つ入口イメージを作る。 |
| `nginx/conf/nginx.conf` | 443/TLS と WordPress PHP-FPM への FastCGI 転送を定義する。 |
| `nginx/tools/entrypoint.sh` | `wordpress:9000` の準備完了を待ち、最後に NGINX を PID 1 にする。 |
| `mariadb/.dockerignore` | MariaDB ビルドに必要な設定と entrypoint だけを context に入れる。 |
| `mariadb/Dockerfile` | Debian から MariaDB サーバーと初期化 entrypoint を持つ DB イメージを作る。 |
| `mariadb/conf/50-server.cnf` | WordPress コンテナから DB 接続できるよう MariaDB の待受を設定する。 |
| `mariadb/tools/init.sh` | secrets を読み、初回 DB 初期化を行い、最後に MariaDB 本体を PID 1 にする。 |
| `wordpress/.dockerignore` | WordPress ビルドに必要な設定と entrypoint だけを context に入れる。 |
| `wordpress/Dockerfile` | PHP-FPM、WP-CLI、WordPress 本体を持つアプリケーションイメージを作る。 |
| `wordpress/conf/www.conf` | PHP-FPM が NGINX から `9000` で FastCGI を受ける設定。 |
| `wordpress/tools/setup.sh` | secrets を読み、WordPress を冪等に初期化し、最後に PHP-FPM を PID 1 にする。 |

この表を入口にして、詳しく聞かれたら該当章のコードブロックと説明へ進むと、レビュー中に説明が破綻しにくくなります。
