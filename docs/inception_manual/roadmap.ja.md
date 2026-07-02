# Inception プロジェクト・ロードマップ

このロードマップは、現在の実装を基準に Mandatory を説明するための進行表です。古い `.env` パスワード直書き方式や `debian:trixie` 前提ではなく、`debian:bookworm` と Compose secrets を使う現在の構成に合わせています。

## 1. 準備フェーズ

- VM に Docker と Docker Compose を用意する。
- `/etc/hosts` に `<login>.42.fr` を登録する。
- `srcs/.env.example` を `srcs/.env` にコピーし、ログイン名、ドメイン名、DB名、ユーザー名、メールアドレスを設定する。
- `secrets/` に4つの secret ファイルを作る。
- `/home/<login>/data/mariadb` と `/home/<login>/data/wordpress` は `make up` が作成する。

## 2. MariaDB フェーズ

- `srcs/requirements/mariadb/Dockerfile` は `debian:bookworm` から MariaDB をビルドする。
- `50-server.cnf` は `bind-address = 0.0.0.0` にして、WordPress コンテナからの TCP 接続を受ける。
- `init.sh` は secrets を読み、初回だけ DB を初期化し、DB とユーザーを作成する。
- 最後は `exec mysqld --user=mysql --datadir=/var/lib/mysql` で MariaDB を PID 1 にする。

## 3. WordPress フェーズ

- `srcs/requirements/wordpress/Dockerfile` は PHP-FPM、PHP CLI、mysqli、MariaDB client、curl、CA証明書、openssl、WP-CLI を入れる。
- `www.conf` は `listen = 0.0.0.0:9000` にして NGINX からの FastCGI を受ける。
- `setup.sh` は secrets を読み、MariaDB の応答を待ち、WordPress 本体、`wp-config.php`、管理者、一般ユーザーを作る。
- 管理者ユーザー名に `admin` を含む場合は起動時に失敗させる。
- 最後は PHP-FPM を `exec ... -F` でフォアグラウンド起動する。

## 4. NGINX フェーズ

- `srcs/requirements/nginx/Dockerfile` は `nginx` と `openssl` を入れ、自己署名証明書を作る。
- `nginx.conf` は `listen 443 ssl;` と `ssl_protocols TLSv1.2 TLSv1.3;` を設定する。
- `location ~ \.php$` は `fastcgi_pass wordpress:9000;` で PHP-FPM に渡す。
- `ports:` は NGINX の `443:443` だけにする。

## 5. 統合フェーズ

- `srcs/docker-compose.yml` は3サービス、2 named volumes、1 bridge network、4 secrets を定義する。
- `mariadb_data` と `wordpress_data` は Docker named volume として定義し、local driver の保存先を `/home/${USER_LOGIN}/data/...` に向ける。
- `Makefile` は `check-env` と `check-secrets` で `.env` の存在、必須キー、secrets の存在を確認してから起動する。

## 6. ドキュメントフェーズ

提出必須としてルートに置く Markdown は次の3つです。

- `README.md`
- `USER_DOC.md`
- `DEV_DOC.md`
- `docs/inception_manual/source_walkthrough.ja.md`

追加の学習資料とレビュー防衛資料は `docs/` 配下に置きます。

## 7. 静的チェック項目

- Dockerfile に `latest` がない。
- Dockerfile と Compose に平文パスワードがない。
- `ports:` は `nginx` の `443:443` のみ。
- `network: host`, `links`, `--link` を使っていない。
- entrypoint に `tail -f`, `sleep infinity`, `while true` がない。
- `ssl_protocols TLSv1.2 TLSv1.3;` がある。
- `srcs/.env` と `secrets/*.txt` は Git 管理外。
