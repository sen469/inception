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
