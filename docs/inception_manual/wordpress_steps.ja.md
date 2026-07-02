# WordPress + PHP-FPM 構築・解説

対象ファイル:

```text
srcs/requirements/wordpress/
├── Dockerfile
├── .dockerignore
├── conf/www.conf
└── tools/setup.sh
```

## 1. 役割

WordPress コンテナは PHP-FPM と WordPress だけを担当します。NGINX は含めません。NGINX から `wordpress:9000` に届いた FastCGI リクエストを PHP-FPM が処理し、必要に応じて MariaDB に接続します。

## 2. Dockerfile

`debian:bookworm` をベースに、次をインストールします。

- `php-fpm`
- `php-cli`
- `php-mysqli`
- `mariadb-client`
- `curl`
- `ca-certificates`
- `openssl`

WP-CLI は公式の Phar を `curl -fsSL` で取得し、`/usr/local/bin/wp` に置きます。WP-CLI は PHP CLI で動くため、`php-cli` を明示的に入れます。ビルド時に WordPress 本体を `/usr/src/wordpress` へ取得し、初回起動時はそこから永続ボリューム `/var/www/html` へコピーします。PHP-FPM の設定パスは PHP minor version に依存するため、Dockerfile 内で `/etc/php/*/fpm/pool.d` を探して `www.conf` を配置します。設定ディレクトリが見つからない場合は、そのまま曖昧に進まずビルドを失敗させます。

## 3. `www.conf`

重要な設定:

```ini
[www]
user = www-data
group = www-data
listen = 0.0.0.0:9000
clear_env = no
```

`listen = 0.0.0.0:9000` により、別コンテナの NGINX から FastCGI 接続を受けられます。ホストへ `9000` を公開しているわけではありません。

## 4. `setup.sh`

entrypoint の責務は次です。

1. 必須環境変数を検査する。
2. `MYSQL_PASSWORD_FILE`, `WP_ADMIN_PASSWORD_FILE`, `WP_USER_PASSWORD_FILE` から secrets を読む。
3. 管理者ユーザー名に `admin` が含まれていないか検査する。
4. WordPress 本体がなければ `/usr/src/wordpress` から `/var/www/html` へコピーする。
5. MariaDB が応答するまで `mysqladmin ping -h mariadb` で最大120秒待つ。
6. `wp-config.php` がなければ `wp config create --skip-check --skip-salts` で作り、認証キーとsaltを `openssl rand` でローカル生成する。既存 `wp-config.php` がある場合はログインセッションを壊さないよう再生成しない。
7. `FORCE_SSL_ADMIN`, `WP_HOME`, `WP_SITEURL` を `https://<domain>` に揃える。
8. 未インストールなら `wp core install` する。
9. 一般ユーザーがいなければ `wp user create` する。
10. 最後に PHP-FPM を `exec ... -F` で起動する。

`depends_on` は起動順だけを保証し、DB が接続可能かまでは保証しません。そのため `mysqladmin ping` が必要です。ただし無限には待たず、最大120秒で失敗させます。

HTTPS については、NGINX が PHP-FPM に `HTTPS on` を渡し、WordPress 側は `wp-config.php` に `FORCE_SSL_ADMIN`, `WP_HOME`, `WP_SITEURL` を設定します。これにより、管理画面とサイトURLを HTTPS 前提にできます。

## 5. secrets

パスワードは `.env` ではなく Compose secrets から読みます。

```yaml
MYSQL_PASSWORD_FILE: /run/secrets/db_password
WP_ADMIN_PASSWORD_FILE: /run/secrets/wp_admin_password
WP_USER_PASSWORD_FILE: /run/secrets/wp_user_password
```

スクリプト内の `read_secret` は `_FILE` 変数が指すファイルを読み、末尾改行を取り除いて実際の値として使います。

## 6. 冪等性

WordPress 本体、`wp-config.php`、DBインストール状態、一般ユーザーの存在をそれぞれ確認してから作成します。これにより、コンテナ再起動時にインストール処理が二重実行されることを避けます。

## 7. レビューでの説明

WordPress コンテナは HTTP を直接公開しません。PHP-FPM が内部ネットワークの `9000` で待ち受け、NGINX だけが外部入口になります。DB接続先は IP ではなく Compose サービス名 `mariadb` です。
