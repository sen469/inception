#!/bin/bash
set -euo pipefail

require_env() {
    local name="$1"
    if [ -z "${!name:-}" ]; then
        echo "Error: ${name} is not set." >&2
        exit 1
    fi
}

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

set_wp_secret_key() {
    local name="$1"
    wp config set "${name}" "$(openssl rand -base64 48)" --allow-root
}

case "$(printf '%s' "${WP_ADMIN_USER}" | tr '[:upper:]' '[:lower:]')" in
    *admin*)
        echo "Error: WP_ADMIN_USER must not contain 'admin'." >&2
        exit 1
        ;;
esac

# WordPressの展開先ディレクトリへ移動
cd /var/www/html

# WordPress本体が未展開の場合のみイメージ内の原本からコピーする
if [ ! -f "wp-load.php" ]; then
    echo "WordPress copying..."
    cp -a /usr/src/wordpress/. /var/www/html/
fi
chown -R www-data:www-data /var/www/html

# MariaDBの起動を待つ
db_attempts=0
until mysqladmin ping -h mariadb -u "${MYSQL_USER}" -p"${MYSQL_PASSWORD}" --silent; do
    db_attempts=$((db_attempts + 1))
    if [ "${db_attempts}" -ge 60 ]; then
        echo "Error: MariaDB did not become reachable within 120 seconds." >&2
        exit 1
    fi
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
        --skip-check \
        --skip-salts \
        --allow-root
    set_wp_secret_key AUTH_KEY
    set_wp_secret_key SECURE_AUTH_KEY
    set_wp_secret_key LOGGED_IN_KEY
    set_wp_secret_key NONCE_KEY
    set_wp_secret_key AUTH_SALT
    set_wp_secret_key SECURE_AUTH_SALT
    set_wp_secret_key LOGGED_IN_SALT
    set_wp_secret_key NONCE_SALT
fi

echo "WordPress HTTPS settings ensuring..."
wp config set FORCE_SSL_ADMIN true --raw --allow-root
wp config set WP_HOME "https://${DOMAIN_NAME}" --allow-root
wp config set WP_SITEURL "https://${DOMAIN_NAME}" --allow-root

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
chown -R www-data:www-data /var/www/html

# PHP-FPMの実行用ディレクトリ作成（エラー回避）
mkdir -p /run/php

# メインプロセスとして PHP-FPM をフォアグラウンドで起動
echo "PHP-FPM starting..."
php_fpm="$(command -v php-fpm || find /usr/sbin -maxdepth 1 -name 'php-fpm*' | sort | tail -n 1)"
if [ -z "${php_fpm}" ]; then
    echo "Error: php-fpm binary was not found." >&2
    exit 1
fi
exec "${php_fpm}" -F
