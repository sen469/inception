#!/bin/bash
set -e

# WordPressの展開先ディレクトリへ移動
cd /var/www/html

# WordPress本体が未展開の場合のみダウンロードする
if [ ! -f "wp-load.php" ]; then
    echo "WordPress downloading..."
    wp core download --allow-root
fi

# MariaDBの起動を待つ
until mysqladmin ping -h mariadb -u "${MYSQL_USER}" -p"${MYSQL_PASSWORD}" --silent; do
    echo "Waiting for MariaDB..."
    sleep 2
done

# wp-config.phpが無い場合のみ作成する
if [ ! -f "wp-config.php" ]; then
    echo "WordPress config creating..."
    wp config create \
        --dbname="${MYSQL_DATABASE}" \
        --dbuser="${MYSQL_USER}" \
        --dbpass="${MYSQL_PASSWORD}" \
        --dbhost=mariadb \
        --allow-root
fi

# DB上でWordPressが未インストールの場合のみ初期化する
if ! wp core is-installed --allow-root; then
    echo "WordPress installing..."
    wp core install \
        --url="https://${DOMAIN_NAME}" \
        --title="Inception WordPress" \
        --admin_user="${WP_ADMIN_USER}" \
        --admin_password="${WP_ADMIN_PASSWORD}" \
        --admin_email="${WP_ADMIN_EMAIL}" \
        --skip-email \
        --allow-root
fi

# 一般ユーザーが存在しない場合のみ作成する
if ! wp user get "${WP_USER}" --allow-root >/dev/null 2>&1; then
    echo "WordPress user creating..."
    wp user create \
        "${WP_USER}" \
        "${WP_USER_EMAIL}" \
        --user_pass="${WP_USER_PASSWORD}" \
        --role=author \
        --allow-root
fi

echo "WordPress setup completed."

# PHP-FPMの実行用ディレクトリ作成（エラー回避）
mkdir -p /run/php

# メインプロセスとして PHP-FPM をフォアグラウンドで起動
echo "PHP-FPM starting..."
# バージョンを自動判定して起動するか、Dockerfileで入れたバージョンを指定
exec php-fpm8.4 -F
