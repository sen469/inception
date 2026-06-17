# WordPress + PHP-FPM 構築・完全手順書

この手順書に従えば、WordPressコンテナをプロジェクト要件（Mandatory）を満たした状態で完成させることができます。

---

## 1. 構成図とディレクトリ準備

まず、以下の構造になっているか確認してください。

```text
srcs/requirements/wordpress/
├── Dockerfile
├── conf/
│   └── www.conf
└── tools/
    └── setup.sh
```

---

## 2. PHP-FPM 設定の準備 (`conf/www.conf`)

デフォルトではUNIXソケット（コンテナ内限定）で待機しているため、ネットワーク経由（NGINXコンテナから）の要求を受け取れるように変更します。

1.  `/etc/php/<version>/fpm/pool.d/www.conf` の内容をベースにします。
2.  以下の箇所を必ず修正してください。

```ini
[www]
user = www-data
group = www-data

; 変更前: listen = /run/php/php8.4-fpm.sock
; 変更後: ポート9000で全てのホストからの要求を待機
listen = 9000

; プロセスの管理設定（任意）
pm = dynamic
pm.max_children = 5
pm.start_servers = 2
pm.min_spare_servers = 1
pm.max_spare_servers = 3
```

---

## 3. 自動セットアップスクリプトの作成 (`tools/setup.sh`)

WP-CLIを使って、ブラウザ操作なしでWordPressをインストール・設定します。

```bash
#!/bin/bash
set -e

# WordPressの展開先ディレクトリへ移動
cd /var/www/html

# WordPressが未インストールの場合のみダウンロードとインストールを実行
if [ ! -f "wp-config.php" ]; then
    echo "WordPress downloading and installing..."

    # WP本体のダウンロード
    wp core download --allow-root

    # wp-config.phpの作成 (MariaDBとの接続設定)
    # --dbhost=mariadb は docker-compose.yml のサービス名
    wp config create \
        --dbname=${MYSQL_DATABASE} \
        --dbuser=${MYSQL_USER} \
        --dbpass=${MYSQL_PASSWORD} \
        --dbhost=mariadb \
        --allow-root

    # WordPressのインストール (サイト設定と管理者作成)
    wp core install \
        --url=${DOMAIN_NAME} \
        --title="Inception WordPress" \
        --admin_user=${WP_ADMIN_USER} \
        --admin_password=${WP_ADMIN_PASSWORD} \
        --admin_email=${WP_ADMIN_EMAIL} \
        --skip-email \
        --allow-root

    # 一般ユーザーの作成 (課題要件: 2人目のユーザー)
    wp user create \
        ${WP_USER} \
        ${WP_USER_EMAIL} \
        --user_pass=${WP_USER_PASSWORD} \
        --role=author \
        --allow-root

    echo "WordPress setup completed."
fi

# PHP-FPMの実行用ディレクトリ作成（エラー回避）
mkdir -p /run/php

# メインプロセスとして PHP-FPM をフォアグラウンドで起動
echo "PHP-FPM starting..."
exec php-fpm8.4 -F
```
*(※ `php-fpm8.4` の部分は使用するDebian/PHPのバージョンに合わせて調整してください。例: trixieなら8.4、bookwormなら8.2など)*

---

## 4. Dockerfile の作成

```dockerfile
# ベースイメージの指定
FROM debian:trixie

# 必要なパッケージのインストール
# php-fpm, php-mysqli (DB接続用), curl (WP-CLIダウンロード用), mariadb-client (DB起動待ち用)
RUN apt-get update && apt-get install -y \
    php-fpm \
    php-mysqli \
    curl \
    mariadb-client \
    && rm -rf /var/lib/apt/lists/*

# WP-CLI のインストール
RUN curl -O https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar \
    && chmod +x wp-cli.phar \
    && mv wp-cli.phar /usr/local/bin/wp

# PHP-FPM 設定ファイルのコピー
COPY conf/www.conf /etc/php/8.4/fpm/pool.d/www.conf

# WordPress ソースコードの保存先ディレクトリ
RUN mkdir -p /var/www/html && chown -R www-data:www-data /var/www/html

# セットアップスクリプトのコピー
COPY tools/setup.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/setup.sh

# 作業ディレクトリ
WORKDIR /var/www/html

# ポート9000
EXPOSE 9000

# エントリポイント
ENTRYPOINT ["/usr/local/bin/setup.sh"]
```

---

## 5. Docker Compose での設定 (`srcs/docker-compose.yml`)

```yaml
services:
  wordpress:
    build:
      context: ./requirements/wordpress
    image: wordpress
    container_name: wordpress
    restart: always
    # MariaDBが起動してからWPを立ち上げる
    depends_on:
      - mariadb
    environment:
      DOMAIN_NAME: ${DOMAIN_NAME}
      MYSQL_DATABASE: ${MYSQL_DATABASE}
      MYSQL_USER: ${MYSQL_USER}
      MYSQL_PASSWORD: ${MYSQL_PASSWORD}
      WP_ADMIN_USER: ${WP_ADMIN_USER}
      WP_ADMIN_PASSWORD: ${WP_ADMIN_PASSWORD}
      WP_ADMIN_EMAIL: ${WP_ADMIN_EMAIL}
      WP_USER: ${WP_USER}
      WP_USER_PASSWORD: ${WP_USER_PASSWORD}
      WP_USER_EMAIL: ${WP_USER_EMAIL}
    volumes:
      - wordpress_data:/var/www/html
    networks:
      - inception_network

volumes:
  wordpress_data:
    driver: local
    driver_opts:
      type: none
      o: bind
      device: /home/${USER_LOGIN}/data/wordpress
```

---

## 6. 動作確認・テスト

1.  `make` で全コンテナを起動。
2.  以下のコマンドでWordPressコンテナに入り、ファイルが生成されているか確認。
    ```bash
    docker exec -it wordpress ls -la /var/www/html
    ```
3.  MariaDBとの接続テスト：
    ```bash
    docker exec -it wordpress wp db check --allow-root
    ```
4.  ユーザー一覧の確認：
    ```bash
    docker exec -it wordpress wp user list --allow-root
    ```

---

### 注意事項
- **ボリュームの共有**: WordPressのソースコードが置かれる `/var/www/html` は、**NGINXコンテナとも共有する**必要があります（NGINXが静的ファイルを読み込むため）。Docker Composeの `nginx` サービス側にも同じボリュームをマウントしてください。
- **PHPバージョンの不一致**: DebianのバージョンによってPHPのバージョンが異なります。Dockerfile内のパス（`/etc/php/X.X/...`）やバイナリ名（`php-fpmX.X`）が一致しているか必ず確認してください。
