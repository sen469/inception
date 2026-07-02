# Inception DEV_DOC

この文書は、実装を説明し、レビューでの質問に耐えるための開発者向け資料です。ユーザー向けの操作手順は `USER_DOC.md`、課題本文は `docs/subject.ja.md` を参照してください。`srcs/` 配下の実ファイルをコードブロック単位で読みたい場合は、`docs/inception_manual/source_walkthrough.ja.md` を参照してください。

## 1. 要件対応表

| 課題要件 | 実装 |
| --- | --- |
| Docker Compose を使う | `srcs/docker-compose.yml` |
| サービスごとに専用Dockerfile | `srcs/requirements/{nginx,wordpress,mariadb}/Dockerfile` |
| NGINX は TLSv1.2/TLSv1.3 のみ | `nginx.conf` の `ssl_protocols TLSv1.2 TLSv1.3;` |
| WordPress + php-fpm、NGINXなし | `wordpress` コンテナは `php-fpm` のみを起動 |
| MariaDB、NGINXなし | `mariadb` コンテナは `mysqld` のみを起動 |
| 2つの永続ボリューム | `mariadb_data`, `wordpress_data` |
| データ保存先 `/home/login/data` | volume `driver_opts.device` |
| コンテナ間ネットワーク | `inception_network` |
| クラッシュ時再起動 | 各サービス `restart: always` |
| `network: host` / `links` 禁止 | 未使用 |
| `tail -f` 等の維持ハック禁止 | 各 entrypoint の最後で実サービスを `exec` |
| WordPress DB に管理者と一般ユーザー | `setup.sh` の `wp core install` と `wp user create` |
| 管理者名に `admin` 禁止 | `setup.sh` 起動時に検査 |
| `latest` タグ禁止 | `debian:bookworm` を明示 |
| Dockerfile にパスワード禁止 | パスワードは `secrets/` |
| `.env` 使用 | `srcs/.env` |
| NGINX が唯一の入口 | `ports:` は `nginx` の `443:443` のみ |

## 2. ディレクトリ構造

```text
.
├── Makefile
├── README.md
├── README.ja.md
├── USER_DOC.md
├── DEV_DOC.md
├── srcs
│   ├── .env.example
│   ├── docker-compose.yml
│   └── requirements
│       ├── mariadb
│       ├── nginx
│       └── wordpress
└── docs
    ├── subject.md
    └── subject.ja.md
```

実際の `srcs/.env` と `secrets/*.txt` はローカルに作成します。秘密情報を Git に入れないため、`.gitignore` で除外しています。

## 3. ファイル別説明

### `Makefile`

評価者が最初に使う入口です。`make` は `up` を実行します。`check-env` で `srcs/.env` と必須キー、`check-secrets` で4つの secret ファイルを検査します。`check-config` はその両方を実行し、欠けている場合は Docker を起動する前に失敗させます。`check-port` はホストの `443` 番が既に使われていないかを確認し、NGINX 起動時の `bind: address already in use` を build 前に検出します。

`COMPOSE` には `docker compose --env-file srcs/.env -f srcs/docker-compose.yml` を定義しています。Compose ファイルが `srcs/` にあるため、明示的に env file を渡して読み取り位置の曖昧さをなくしています。

`DATA_DIR = /home/$(USER_LOGIN)/data` です。`up` は設定、secrets、`443` 番ポートの空き状況を確認し、`mariadb` と `wordpress` の保存先ディレクトリを作成してから Compose を起動します。`down`, `logs`, `ps` も Compose の変数展開に `.env` を必要とするため、`check-env` を通してから実行します。`fclean` は `USER_LOGIN` を確認してから、このプロジェクトのデータディレクトリだけを削除します。

Compose project 名は `-p` で固定していません。そのため、network や volume の実名は通常 `<project>_inception_network`, `<project>_mariadb_data`, `<project>_wordpress_data` になります。評価環境では `docker network ls` や `docker volume ls` で実名を確認してから inspect します。

### `srcs/.env.example`

Git に入れてよい非秘密値のテンプレートです。実際の `srcs/.env` にはログイン名、ドメイン名、DB名、ユーザー名、メールアドレスを設定します。パスワードはここに置きません。

### `docs/inception_manual/secrets.example.md`

ローカルで作るべき secret ファイル一覧です。実体の `secrets/*.txt` は Git から除外します。

### `docs/inception_manual/source_walkthrough.ja.md`

`srcs/` 配下の各ファイルを、実際のコード断片と設計意図を対応させて説明する注釈書です。この `DEV_DOC.md` が全体設計とレビュー観点をまとめる文書であるのに対し、`source_walkthrough.ja.md` は「この行はなぜ必要か」を確認するための資料です。

### `srcs/docker-compose.yml`

3つのサービス、2つの名前付きボリューム、1つの bridge network、4つの secrets を定義します。

`nginx` だけが `ports: "443:443"` を持ちます。`wordpress` と `mariadb` は `ports:` を持たないため、ホストから直接到達できません。

`secrets:` は `../secrets/*.txt` を読み、コンテナ内では `/run/secrets/...` にマウントされます。スクリプト側は `MYSQL_PASSWORD_FILE` のような `_FILE` 変数を読みます。

名前付きボリュームは次の形です。

```yaml
volumes:
  mariadb_data:
    driver: local
    driver_opts:
      type: none
      o: bind
      device: /home/${USER_LOGIN}/data/mariadb
```

サービス定義で直接 `/home/login/data:/...` のようなホストパスをマウントしているわけではなく、サービスは `mariadb_data` と `wordpress_data` という Docker named volume をマウントしています。保存場所を `/home/login/data` に置くため、named volume 側の local driver options で `device` を指定しています。

### `srcs/requirements/nginx/Dockerfile`

`debian:bookworm` をベースに、`nginx`, `openssl`, `netcat-openbsd` を入れます。ビルド時引数 `DOMAIN_NAME` を使って自己署名証明書を生成し、`nginx.conf` 内の `__DOMAIN_NAME__` を置換します。`netcat-openbsd` は entrypoint が `wordpress:9000` の TCP 接続可能状態を確認するために使います。

最後は次の entrypoint です。

```dockerfile
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
```

`entrypoint.sh` は `wordpress:9000` が開くまで最大120秒待ち、それから `exec nginx -g "daemon off;"` を実行します。これにより、`make up` 直後に NGINX が PHP-FPM 準備前の WordPress へ接続して一時的な `502 Bad Gateway` を返す状況を減らします。最後は `exec` で NGINX をフォアグラウンド起動するため、`tail -f` のような維持ハックではありません。

### `srcs/requirements/nginx/tools/entrypoint.sh`

NGINX の起動前待機スクリプトです。`WORDPRESS_HOST` と `WORDPRESS_PORT` があればそれを使い、未設定なら `wordpress:9000` を待ちます。Compose の `depends_on` はコンテナ起動順だけを保証し、PHP-FPM が実際に listen しているかまでは保証しません。そのため NGINX 側で TCP 接続可能性を確認してから起動します。

### `srcs/requirements/nginx/conf/nginx.conf`

HTTPS の入口です。

重要行:

```nginx
listen 443 ssl;
ssl_protocols TLSv1.2 TLSv1.3;
root /var/www/html;
fastcgi_pass wordpress:9000;
```

`wordpress:9000` は Docker network のサービス名解決です。IPアドレスを固定しないため、コンテナ再作成後も名前で接続できます。

`location /` は `try_files $uri $uri/ /index.php?$args;` です。静的ファイルがあれば返し、なければ WordPress の `index.php` に渡します。これにより投稿ページなどの WordPress ルーティングが動きます。

PHP location では `fastcgi_index index.php` と `fastcgi_param HTTPS on` も設定しています。前者はディレクトリアクセス時の既定 PHP ファイルを明示し、後者は WordPress 側に HTTPS リクエストとして認識させるためです。`.htaccess` や `.git` のような隠しファイルは `deny all` で返しません。

### `srcs/requirements/mariadb/Dockerfile`

`debian:bookworm` に `mariadb-server` と `mariadb-client` を入れます。設定ファイルと entrypoint をコピーし、`ENTRYPOINT ["/usr/local/bin/init.sh"]` で初期化スクリプトを起動します。

### `srcs/requirements/mariadb/conf/50-server.cnf`

`bind-address = 0.0.0.0` が重要です。MariaDB の初期設定は localhost のみを待ち受けることがありますが、WordPress は別コンテナなので TCP 接続できるように全インターフェースで待ち受けます。

外部公開はしていません。ホストに `3306` を publish していないため、到達できるのは Docker network 内のコンテナだけです。

### `srcs/requirements/mariadb/tools/init.sh`

MariaDB の entrypoint です。責務は4つです。

1. 必須環境変数と secrets を検証する。
2. 初回起動時だけ `/var/lib/mysql` を初期化する。
3. DB、DBユーザー、権限を作る。
4. 最後に `exec mysqld --user=mysql --datadir=/var/lib/mysql` で MariaDB を PID 1 にする。

ホスト上の `/home/<login>/data/mariadb` を実体にする named volume は、環境によって所有者がずれる可能性があります。そのため entrypoint は毎回 `/run/mysqld` と `/var/lib/mysql` を `mysql:mysql` に揃えてから MariaDB を起動します。

`read_secret MYSQL_PASSWORD` は `MYSQL_PASSWORD_FILE=/run/secrets/db_password` を読み、改行を除去して環境変数に入れます。パスワード本体を Compose の environment に書かないため、`docker inspect` で平文値が出にくくなります。

初期化済み判定は `/var/lib/mysql/mysql` の存在です。このディレクトリがあれば既存DBを使い、なければ `mysql_install_db` を実行します。これによりコンテナ再起動で DB を破壊しません。

一時起動した MariaDB は SQL 実行後に `mysqladmin shutdown` で止めます。起動待ちは最大60秒で、準備完了しない場合は明確に失敗します。異常終了時の `trap` でも、root パスワードあり、なし、最後に一時プロセスの停止を試し、初期化用プロセスを残しにくくしています。その後、フォアグラウンドの `mysqld` に置き換えるため、Docker の停止シグナルが MariaDB に直接届きます。

### `srcs/requirements/wordpress/Dockerfile`

`debian:bookworm` に `php-fpm`, `php-cli`, `php-mysqli`, `mariadb-client`, `curl`, `ca-certificates`, `openssl` を入れます。`php-cli` は WP-CLI の Phar を実行するために必要です。WP-CLI は `curl -fsSL` で取得し、HTTPエラーや取得失敗をビルド時に検出できるようにしてから `/usr/local/bin/wp` に配置します。ビルド時に WordPress 本体を `/usr/src/wordpress` へ取得します。初回起動時は外部ネットワークへ取りに行かず、このディレクトリから永続ボリューム `/var/www/html` へコピーします。

PHP-FPM の設定ディレクトリは Debian の PHP minor version に依存するため、`find /etc/php -path '*/fpm/pool.d'` で実際のディレクトリを探して `www.conf` を配置します。見つからない場合は `test -n "${pool_dir}"` でビルドを失敗させます。これにより `bookworm` の PHP 8.2 固定パスに過度に依存しません。

### `srcs/requirements/wordpress/conf/www.conf`

PHP-FPM の pool 設定です。

```ini
listen = 0.0.0.0:9000
clear_env = no
```

`listen = 0.0.0.0:9000` により NGINX コンテナから FastCGI 接続を受けます。`clear_env = no` は PHP-FPM ワーカーから環境変数を見えるようにします。

### `srcs/requirements/wordpress/tools/setup.sh`

WordPress の entrypoint です。責務は5つです。

1. 必須環境変数と secrets を検証する。
2. 管理者ユーザー名に `admin` が含まれていないか確認する。
3. WordPress 本体がなければ `/usr/src/wordpress` から `/var/www/html` へコピーする。
4. MariaDB を最大120秒待って、`wp-config.php` と WordPress DB を初期化する。
5. `FORCE_SSL_ADMIN`, `WP_HOME`, `WP_SITEURL` を `https://<domain>` に揃える。
6. 最後に PHP-FPM を `exec ... -F` でフォアグラウンド起動する。

`wp core is-installed` によって DB 初期化済みか確認するため、再起動時に WordPress を二重インストールしません。一般ユーザーも `wp user get` で存在確認してから作成します。

`wp config create` は `--skip-check --skip-salts` で実行し、DB接続確認とsalt取得に余計な外部依存を持たせません。認証キーとsaltは `wp-config.php` の新規作成時だけ `openssl rand -base64 48` でローカル生成します。再起動のたびにsaltを変えると既存ログインセッションを無効化するため、既存 `wp-config.php` がある場合は再生成しません。

NGINX は TLS を終端し、PHP-FPM へ `HTTPS on` を渡します。WordPress 側でも `FORCE_SSL_ADMIN`, `WP_HOME`, `WP_SITEURL` を `wp-config.php` に設定するため、管理画面とサイトURLを HTTPS 前提として説明できます。

## 4. サービス対応表

| Compose service | Image | Container | Dockerfile | Main process | External port |
| --- | --- | --- | --- | --- | --- |
| `nginx` | `nginx` | `nginx` | `srcs/requirements/nginx/Dockerfile` | `entrypoint.sh` -> `nginx -g "daemon off;"` | `443:443` |
| `wordpress` | `wordpress` | `wordpress` | `srcs/requirements/wordpress/Dockerfile` | `php-fpm -F` | none |
| `mariadb` | `mariadb` | `mariadb` | `srcs/requirements/mariadb/Dockerfile` | `mysqld --user=mysql` | none |

課題要件では、各 Docker image が対応する service と同じ名前を持ち、各 service が専用コンテナで動く必要があります。この表の通り、`image`, `container_name`, Dockerfile の配置はサービス単位で分離しています。

## 5. コンテナ間通信

通信経路は次の通りです。

```text
Browser
  -> https://<login>.42.fr:443
  -> nginx
  -> FastCGI wordpress:9000
  -> MariaDB mariadb:3306
```

Docker の user-defined bridge network では、Compose サービス名が DNS 名になります。したがって NGINX は `wordpress:9000`、WordPress は `mariadb` で接続できます。

## 6. 永続化

WordPress ファイル:

```text
/home/<login>/data/wordpress
```

MariaDB データ:

```text
/home/<login>/data/mariadb
```

コンテナを消しても named volume のデータが残れば、WordPress の投稿やDB内容は維持されます。完全初期化したい場合は `make fclean` でホスト側データディレクトリも削除します。

## 7. レビュー時の確認コマンド

Compose 展開:

```sh
make config
```

外部公開ポート:

```sh
docker compose --env-file srcs/.env -f srcs/docker-compose.yml ps
```

NGINX TLS:

```sh
docker exec nginx nginx -T | grep ssl_protocols
openssl s_client -connect <login>.42.fr:443 -tls1_2
openssl s_client -connect <login>.42.fr:443 -tls1_3
```

禁止TLSが失敗すること:

```sh
openssl s_client -connect <login>.42.fr:443 -tls1_1
```

ネットワーク:

```sh
docker network ls | grep inception_network
docker network inspect srcs_inception_network
```

ボリューム:

```sh
docker volume ls | grep '_mariadb_data\|_wordpress_data'
docker volume inspect srcs_mariadb_data
docker volume inspect srcs_wordpress_data
```

WordPress ユーザー:

```sh
docker exec wordpress wp user list --allow-root --path=/var/www/html
```

DB:

```sh
docker exec mariadb mariadb -u root -p -e 'SHOW DATABASES;'
```

PID 1:

```sh
docker exec nginx ps -p 1 -o pid,comm,args
docker exec wordpress ps -p 1 -o pid,comm,args
docker exec mariadb ps -p 1 -o pid,comm,args
```

## 8. よく聞かれる質問

**なぜ NGINX だけ ports があるのか。**  
課題が「NGINX が唯一の entrypoint」と要求しているためです。WordPress と MariaDB を host に公開すると、攻撃面が増え、要件にも反します。

**なぜ `depends_on` だけで DB 起動待ちにしないのか。**  
`depends_on` はコンテナの起動順を制御しますが、DB が SQL を受け付ける準備完了までは保証しません。そのため `setup.sh` で `mysqladmin ping` を使って最大120秒待ちます。準備できなければ無限に待たず、原因をログに残して終了します。

**なぜ `exec` が必要か。**  
entrypoint の最後で `exec` しないと、PID 1 がシェルのままになり、Docker の `SIGTERM` が本来のデーモンへ正しく届きにくくなります。`exec` はシェルをメインプロセスに置き換えます。

**なぜ `bind-address = 0.0.0.0` なのか。**  
MariaDB コンテナ内の localhost は MariaDB コンテナ自身です。WordPress は別コンテナなので、Docker network 経由の TCP 接続を受け付ける必要があります。

**なぜ secrets を使うのか。**  
パスワードを Compose の environment に直接置くと、`docker inspect` などで見えやすくなります。secrets はファイルとして `/run/secrets` にマウントされ、設定値としての露出を減らせます。

**なぜ `debian:bookworm` なのか。**  
2026-07-02時点で Debian 13 `trixie` が stable、Debian 12 `bookworm` が oldstable です。課題文の “penultimate stable version” を厳密に解釈し、最後から2番目の安定版として `bookworm` を使います。

## 9. 失敗しやすい点

`srcs/.env` がない、または必須キーが空だと Makefile は起動前に失敗します。これは意図した挙動です。

secret ファイルが空だと起動前に失敗します。空パスワード状態を避けるためです。

`WP_ADMIN_USER` に `admin` を含めると WordPress コンテナが失敗します。課題の禁止事項を起動時に検査しています。

既存ボリュームがある状態で DB root password を変更すると、保存済みDBと secret が不一致になることがあります。完全にやり直す場合は `make fclean` でデータを消します。

`https://<login>.42.fr` が開けない場合、まず `/etc/hosts`、次に `make ps`、最後に `make logs` の順に確認します。
