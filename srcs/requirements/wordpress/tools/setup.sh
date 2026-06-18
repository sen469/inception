#!/bin/bash
set -e

# WordPressの展開先ディレクトリへ移動
cd /var/www/html

# WordPressが未インストールの場合のみダウンロードとインストールを実行
if [ ! -f "wp-config.php" ]; then
    echo "WordPress downloading and installing..."

    # WP本体のダウンロード
    wp core download --allow-root

    # MariaDBの起動を待つ
    until mysqladmin ping -h mariadb -u ${MYSQL_USER} -p${MYSQL_PASSWORD} --silent; do
        echo "Waiting for MariaDB..."
        sleep 2
    done

    # wp-config.phpの作成
    wp config create \
        --dbname=${MYSQL_DATABASE} \
        --dbuser=${MYSQL_USER} \
        --dbpass=${MYSQL_PASSWORD} \
        --dbhost=mariadb \
        --allow-root

    # WordPressのインストール
    wp core install \
        --url=${DOMAIN_NAME} \
        --title="Inception WordPress" \
        --admin_user=${WP_ADMIN_USER} \
        --admin_password=${WP_ADMIN_PASSWORD} \
        --admin_email=${WP_ADMIN_EMAIL} \
        --skip-email \
        --allow-root

    # 一般ユーザーの作成
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
# バージョンを自動判定して起動するか、Dockerfileで入れたバージョンを指定
exec php-fpm8.4 -F
