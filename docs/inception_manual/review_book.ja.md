# Inception レビュー防衛書

## 序章: このプロジェクトで証明すべきこと

Inception は「WordPress を Docker で動かす課題」ではなく、複数の独立したサービスを、明確な責務分離、永続化、ネットワーク分離、秘密情報管理、プロセス管理の原則に従って構築できることを示す課題です。

評価では、画面が表示されるだけでは不十分です。次のことを説明できる必要があります。

- なぜ3つのコンテナに分けたのか。
- なぜ NGINX だけが外部公開されているのか。
- WordPress と MariaDB はどう接続しているのか。
- データはどこに永続化されるのか。
- `.env` と secrets の役割は何が違うのか。
- なぜ `tail -f` や `sleep infinity` を使っていないのか。
- コンテナ停止時にメインプロセスがどう終了するのか。

この文書は、その説明をレビューでそのまま使える粒度まで落とし込んだものです。

## 第1章: 全体アーキテクチャ

構成は3層です。

```text
Browser
  |
  | HTTPS 443 / TLSv1.2 or TLSv1.3
  v
nginx container
  |
  | FastCGI / wordpress:9000
  v
wordpress container
  |
  | MariaDB protocol / mariadb:3306
  v
mariadb container
```

`nginx` は入口、`wordpress` はアプリケーション、`mariadb` はデータベースです。各コンテナは1つの主要サービスだけを担当します。これは障害範囲を小さくし、設定の責任を明確にするためです。

ホストに公開されるポートは `443` だけです。`wordpress:9000` と `mariadb:3306` は Docker network の内部通信にだけ使われます。つまり、外部から直接 DB に接続したり、PHP-FPM に接続したりする設計ではありません。

## 第2章: Docker と VM の違い

仮想マシンはハードウェアを仮想化し、ゲストOSごとに独立したカーネルを持ちます。Docker コンテナはホストの Linux カーネルを共有し、namespace と cgroup でプロセス、ネットワーク、ファイルシステム、リソースを分離します。

そのため Docker は VM より軽量です。ただし、コンテナは VM ではありません。コンテナ内で複数のデーモンを雑に起動したり、`tail -f` でコンテナを維持したりするのは、Docker のプロセスモデルを理解していない実装です。

このプロジェクトでは各コンテナの PID 1 が実サービスになるように構成しています。

## 第3章: ファイル単位の責務

### `Makefile`

プロジェクトの操作入口です。

主なターゲット:

| ターゲット | 役割 |
| --- | --- |
| `all` / `up` | 設定ファイルを確認し、データディレクトリを作り、Compose を起動する。 |
| `check-env` | `srcs/.env` と必須キーが存在することを確認する。 |
| `check-secrets` | 4つの secret ファイルが存在し、空でないことを確認する。 |
| `check-config` | `check-env` と `check-secrets` の両方を実行する。 |
| `down` | コンテナとネットワークを停止・削除する。 |
| `clean` | `down` に加えてイメージと Docker volume を削除する。 |
| `fclean` | ホスト上の `/home/<login>/data` も削除する。 |
| `config` | Compose の最終展開結果を表示する。 |

`check-config` がある理由は、空パスワードや未設定値のままコンテナを起動しないためです。Docker は未定義の環境変数を空文字として扱うことがあるため、起動前に失敗させる方が安全です。`fclean` はホスト上のデータを削除するため、`check-env` で `USER_LOGIN` を確認してから削除します。

`down`, `logs`, `ps` も `docker-compose.yml` の変数展開に `.env` を必要とするため、`check-env` を通してから Compose を呼びます。

### `srcs/docker-compose.yml`

インフラの接続関係を定義する中心ファイルです。

定義内容:

- `mariadb`, `wordpress`, `nginx` の3サービス。
- `mariadb_data`, `wordpress_data` の2つの named volume。
- `inception_network` の bridge network。
- DB と WordPress パスワード用の secrets。

重要なのは `ports:` が `nginx` にしかない点です。

```yaml
nginx:
  ports:
    - "443:443"
```

`wordpress` と `mariadb` に `ports:` がないので、ホストから直接アクセスできません。これは「NGINX が唯一の entrypoint」という課題要件を満たすためです。

### `srcs/.env.example`

`.env` のテンプレートです。ここには秘密情報を置きません。入れるのはログイン名、ドメイン名、DB名、ユーザー名、メールアドレスなど、設定値として必要だがパスワードではない情報です。

実際の `srcs/.env` は Git に入れません。

### `docs/inception_manual/secrets.example.md`

ローカルに作る secret ファイルの一覧です。

```text
secrets/db_password.txt
secrets/db_root_password.txt
secrets/wp_admin_password.txt
secrets/wp_user_password.txt
```

Compose はこれらをコンテナ内の `/run/secrets/...` にマウントします。アプリケーション側は `_FILE` 変数を通じてファイルを読みます。

### `srcs/requirements/nginx/Dockerfile`

NGINX イメージを作る Dockerfile です。

責務:

- `debian:bookworm` をベースにする。
- `nginx` と `openssl` をインストールする。
- 自己署名証明書を生成する。
- `nginx.conf` を配置する。
- `nginx -g "daemon off;"` で NGINX をフォアグラウンド起動する。

`debian:bookworm` を使う理由は、2026年7月時点で Debian 13 `trixie` が stable、Debian 12 `bookworm` が oldstable であり、課題文の “penultimate stable version” に合わせるためです。

### `srcs/requirements/nginx/conf/nginx.conf`

HTTPS と FastCGI 転送の設定です。

重要な設定:

```nginx
listen 443 ssl;
ssl_protocols TLSv1.2 TLSv1.3;
root /var/www/html;
fastcgi_pass wordpress:9000;
```

`ssl_protocols` により TLSv1.0 や TLSv1.1 を許可しません。

`fastcgi_pass wordpress:9000;` の `wordpress` はコンテナ名ではなく Compose サービス名による DNS 解決です。Docker の user-defined bridge network では、同じネットワークに参加するサービス名が DNS 名として使えます。

`try_files $uri $uri/ /index.php?$args;` は WordPress のパーマリンクを動かすために必要です。静的ファイルが存在しなければ `index.php` に渡し、WordPress がルーティングを処理します。

### `srcs/requirements/mariadb/Dockerfile`

MariaDB イメージを作る Dockerfile です。

責務:

- `debian:bookworm` をベースにする。
- `mariadb-server` と `mariadb-client` を入れる。
- `50-server.cnf` を配置する。
- `init.sh` を entrypoint として配置する。

Dockerfile にはパスワードを一切書きません。パスワードは実行時に secrets から渡されます。

### `srcs/requirements/mariadb/conf/50-server.cnf`

MariaDB のサーバー設定です。

```ini
bind-address = 0.0.0.0
port = 3306
datadir = /var/lib/mysql
socket = /run/mysqld/mysqld.sock
```

`bind-address = 0.0.0.0` は、別コンテナの WordPress から TCP 接続を受けるために必要です。ただし `ports:` でホスト公開していないため、外部に DB を公開しているわけではありません。

### `srcs/requirements/mariadb/tools/init.sh`

MariaDB の起動前初期化を行う entrypoint です。

処理の流れ:

1. 必須環境変数を検証する。
2. secrets ファイルからパスワードを読む。
3. DB名とユーザー名が安全な識別子か検査する。
4. `/run/mysqld` を作り、`/run/mysqld` と `/var/lib/mysql` の所有者を `mysql:mysql` に揃える。
5. `/var/lib/mysql/mysql` がなければ DB ディレクトリを初期化する。
6. 一時的に MariaDB を起動し、DB とユーザーと権限を作る。
7. 一時 MariaDB を停止する。異常終了時にも `trap` で後始末を試みる。
8. `exec mysqld --user=mysql --datadir=/var/lib/mysql` で本番プロセスを起動する。

`exec` が重要です。`exec` はシェルプロセスを MariaDB プロセスに置き換えます。これにより MariaDB が PID 1 になり、Docker の停止シグナルを直接受け取れます。

初期化済み判定に `/var/lib/mysql/mysql` を使う理由は、MariaDB のシステムテーブルが存在するかでデータディレクトリの初期化状態を判断できるからです。これにより再起動時に既存 DB を壊しません。

### `srcs/requirements/wordpress/Dockerfile`

WordPress + PHP-FPM イメージを作る Dockerfile です。

責務:

- `debian:bookworm` をベースにする。
- `php-fpm`, `php-cli`, `php-mysqli`, `mariadb-client`, `curl`, `ca-certificates`, `openssl` を入れる。
- WP-CLI を `/usr/local/bin/wp` に置く。
- WordPress 本体を `/usr/src/wordpress` に用意する。
- PHP-FPM pool 設定を配置する。
- `/var/www/html` を作り、`www-data` 所有にする。
- `setup.sh` を entrypoint として配置する。

WordPress 本体は Dockerfile で `/usr/src/wordpress` に用意し、entrypoint で永続 volume `/var/www/html` へコピーします。これにより、WordPress ファイルは永続 volume に置きつつ、初回起動時に外部ネットワークへ依存しない構成にできます。

### `srcs/requirements/wordpress/conf/www.conf`

PHP-FPM の pool 設定です。

```ini
listen = 0.0.0.0:9000
clear_env = no
pm = dynamic
```

`listen = 0.0.0.0:9000` により、NGINX コンテナから FastCGI 接続を受けられます。

`clear_env = no` は PHP-FPM が環境変数を完全に消さないための設定です。ただし、実装では secrets を entrypoint が読み、WP-CLI 初期化に使うため、パスワードを PHP アプリケーションへ積極的に公開する設計ではありません。

### `srcs/requirements/wordpress/tools/setup.sh`

WordPress の entrypoint です。

処理の流れ:

1. 必須環境変数を検証する。
2. secrets から DB と WordPress ユーザーのパスワードを読む。
3. `WP_ADMIN_USER` に `admin` が含まれていないか検査する。
4. WordPress 本体がなければ `/usr/src/wordpress` から `/var/www/html` へコピーする。
5. MariaDB が応答するまで `mysqladmin ping` で最大120秒待つ。
6. `wp-config.php` がなければ `--skip-check --skip-salts` で作り、認証キーとsaltを `openssl rand` でローカル生成する。既存 `wp-config.php` がある場合は再生成しない。
7. `FORCE_SSL_ADMIN`, `WP_HOME`, `WP_SITEURL` を HTTPS に揃える。
8. WordPress が未インストールなら `wp core install` する。
9. 一般ユーザーがいなければ `wp user create` する。
10. `exec php-fpm -F` で PHP-FPM を PID 1 として起動する。

`depends_on` だけでなく `mysqladmin ping` を使う理由は、`depends_on` が起動順を制御するだけで、MariaDB が SQL を受け付けられる状態かまでは保証しないためです。

HTTPS については、NGINX が `fastcgi_param HTTPS on;` を PHP-FPM に渡し、WordPress の `wp-config.php` でも `FORCE_SSL_ADMIN`, `WP_HOME`, `WP_SITEURL` を HTTPS に揃えます。

## 第4章: secrets と `.env`

このプロジェクトでは役割を分けています。

| 種類 | 置くもの | 例 |
| --- | --- | --- |
| `.env` | 秘密ではない設定値 | `DOMAIN_NAME`, `MYSQL_DATABASE`, `WP_USER` |
| secrets | パスワード | DBパスワード、rootパスワード、WPパスワード |

`.env` は Compose の変数展開と環境変数注入に使います。一方、secrets はファイルとしてコンテナにマウントされます。

レビューで聞かれたら、次のように答えます。

> `.env` は設定値を渡すために使います。パスワードは `docker inspect` などで見えやすい environment に直接置かず、Compose secrets として `/run/secrets` にファイルマウントしています。entrypoint は `_FILE` 変数を見て secret ファイルを読みます。

## 第5章: named volume と `/home/login/data`

課題は named volume の使用と、ホスト上 `/home/login/data` への保存を同時に要求します。

この実装では named volume に local driver options を設定しています。

```yaml
volumes:
  wordpress_data:
    driver: local
    driver_opts:
      type: none
      o: bind
      device: /home/${USER_LOGIN}/data/wordpress
```

サービス定義で直接 `- /home/login/data:/var/www/html` のようなホストパスをマウントしているわけではありません。サービスは Docker の named volume をマウントし、その named volume の実体の保存先を local driver options で指定しています。

評価では、`docker volume inspect` の `Mountpoint` や `Options` を見せると説明しやすいです。Compose project 名を `-p` で固定していない場合、volume や network の実名は実行ディレクトリ名に依存して `<project>_wordpress_data` のようになります。名前が違う場合は `docker volume ls` と `docker network ls` で実名を確認します。

## 第6章: PID 1 と停止処理

Docker コンテナでは、PID 1 のプロセスが終了するとコンテナも終了します。したがって、コンテナを生かすために `tail -f` を動かすのは間違いです。コンテナは「意味のあるメインプロセス」を PID 1 として持つべきです。

この実装では次のようになっています。

| コンテナ | PID 1 になるプロセス |
| --- | --- |
| `nginx` | `nginx -g daemon off;` |
| `wordpress` | `php-fpm -F` |
| `mariadb` | `mysqld --user=mysql` |

entrypoint の最後で `exec` を使うと、シェルが残らず、メインプロセスに置き換わります。これにより `docker stop` の `SIGTERM` が本来のサービスへ届きやすくなります。

## 第7章: セキュリティ上の説明

### 外部公開の最小化

外部公開は `443` のみです。MariaDB をホストに公開しないため、DB に対する直接攻撃面を減らしています。

### TLS バージョン

NGINX は TLSv1.2 と TLSv1.3 のみを許可します。古い TLSv1.0/TLSv1.1 は無効です。

### パスワード

Dockerfile にはパスワードを書きません。`.env.example` にも実パスワードを書きません。実パスワードはローカルの `secrets/*.txt` に置き、Git から除外します。

### root 権限

初期化スクリプトはディレクトリ作成や権限変更のため root で始まりますが、MariaDB 本体は `--user=mysql` で実行します。WordPress のファイル所有者は `www-data` に揃えます。

## 第8章: レビューでの回答例

**Q. なぜ3コンテナに分けるのですか。**  
A. NGINX、WordPress/PHP-FPM、MariaDB は責務が異なるためです。分離することで、外部公開は NGINX だけ、DB は内部ネットワークだけ、という境界を明確にできます。

**Q. WordPress は MariaDB の IP をどう知るのですか。**  
A. IP を直接知る必要はありません。Compose の user-defined bridge network ではサービス名が DNS 名になります。WordPress は `mariadb` という名前で接続します。

**Q. NGINX は PHP をどう実行しますか。**  
A. NGINX 自身は PHP を実行しません。`.php` リクエストを FastCGI で `wordpress:9000` の PHP-FPM に渡します。

**Q. `depends_on` があるのに、なぜ DB 待ち処理が必要ですか。**  
A. `depends_on` はコンテナ起動順だけを保証します。MariaDB が接続可能になるタイミングは別なので、`mysqladmin ping` で実際に応答するまで待ちます。ただし無限待機にはせず、上限時間を超えたら失敗させます。

**Q. なぜ admin というユーザー名は禁止なのですか。**  
A. 課題要件で WordPress 管理者名に `admin`、`administrator` などを含めることが禁止されているためです。この実装では `admin` を含む名前を起動時に拒否します。

**Q. なぜ自己署名証明書なのですか。**  
A. ローカル VM 上の課題環境で公開ドメインの正式証明書を取得する必要はありません。目的は NGINX が HTTPS/TLS を正しく終端できることを示すことです。

**Q. Docker image の `latest` を使っていない理由は。**  
A. `latest` は実体が時間で変わり、再現性が低いからです。また課題で禁止されています。明示的に `debian:bookworm` を指定しています。

**Q. secrets は完全に安全ですか。**  
A. 完全ではありません。コンテナ内で読める以上、権限を持つ人は取得できます。ただし environment に直接パスワードを置くより露出面を減らせます。今回の目的は、Git に秘密情報を入れず、Compose 設定や Dockerfile に平文パスワードを書かないことです。

## 第9章: 静的チェック観点

レビュー前に、少なくとも次を確認します。

- `srcs/docker-compose.yml` で `ports:` が `nginx` だけにある。
- `network: host`, `links:`, `--link` が使われていない。
- Dockerfile に `latest` がない。
- Dockerfile にパスワード文字列がない。
- entrypoint に `tail -f`, `sleep infinity`, `while true` がない。
- `ssl_protocols TLSv1.2 TLSv1.3;` がある。
- `srcs/.env` と `secrets/*.txt` が Git 追跡されていない。
- `README.md` の先頭行が課題指定の italic 文である。
- `USER_DOC.md` と `DEV_DOC.md` がルートにある。

## 終章: 評価での姿勢

この課題の評価では「動いた」よりも「なぜそう設計したか」を説明できることが重要です。特に、Docker network、named volume、secrets、PID 1、TLS、entrypoint の初期化処理は高確率で質問されます。

各質問では、単語だけで答えず、必ず実装ファイルの行動に結びつけて説明します。

例:

> Docker network を使っています。

だけでは弱いです。

> `srcs/docker-compose.yml` の `inception_network` に3サービスを参加させています。NGINX は `wordpress:9000`、WordPress は `mariadb` というサービス名で接続します。ホスト公開は NGINX の `443` だけなので、MariaDB は外部から直接アクセスできません。

ここまで説明できれば、実装と概念が結びついていることを示せます。
