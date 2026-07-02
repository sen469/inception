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

require_simple_identifier() {
    local name="$1"
    local value="${!name}"
    if ! [[ "${value}" =~ ^[A-Za-z0-9_]+$ ]]; then
        echo "Error: ${name} must contain only letters, digits, and underscores." >&2
        exit 1
    fi
}

sql_escape() {
    local value="$1"
    value="${value//\\/\\\\}"
    value="${value//\'/\\\'}"
    printf "%s" "${value}"
}

require_env MYSQL_DATABASE
require_env MYSQL_USER
read_secret MYSQL_PASSWORD
read_secret MYSQL_ROOT_PASSWORD
require_simple_identifier MYSQL_DATABASE
require_simple_identifier MYSQL_USER

# MariaDBのランタイムディレクトリを作成
if [ ! -d "/run/mysqld" ]; then
    mkdir -p /run/mysqld
fi
chown -R mysql:mysql /run/mysqld
chown -R mysql:mysql /var/lib/mysql

db_initialized=true

# データベースが未初期化の場合のみ初期化を実行
if [ ! -d "/var/lib/mysql/mysql" ]; then
    db_initialized=false
    echo "Initializing MariaDB database..."
    mysql_install_db --user=mysql --datadir=/var/lib/mysql > /dev/null
fi

# 一時的にMariaDBを起動（初期設定のため）
mysqld_safe --datadir=/var/lib/mysql &
temporary_pid="$!"

cleanup_temporary_server() {
    if kill -0 "${temporary_pid}" >/dev/null 2>&1; then
        mysqladmin -u root -p"${MYSQL_ROOT_PASSWORD}" shutdown >/dev/null 2>&1 \
            || mysqladmin -u root shutdown >/dev/null 2>&1 \
            || kill "${temporary_pid}" >/dev/null 2>&1 \
            || true
        wait "${temporary_pid}" >/dev/null 2>&1 || true
    fi
}
trap cleanup_temporary_server EXIT

# 起動を待つ
startup_attempts=0
until mysqladmin ping >/dev/null 2>&1; do
    startup_attempts=$((startup_attempts + 1))
    if [ "${startup_attempts}" -ge 60 ]; then
        echo "Error: MariaDB did not become ready within 60 seconds." >&2
        exit 1
    fi
    echo "Waiting for MariaDB to start..."
    sleep 1
done

# 初期設定SQLの実行
escaped_mysql_password="$(sql_escape "${MYSQL_PASSWORD}")"
escaped_root_password="$(sql_escape "${MYSQL_ROOT_PASSWORD}")"

if [ "${db_initialized}" = false ]; then
    mysql -u root << EOF
ALTER USER 'root'@'localhost' IDENTIFIED BY '${escaped_root_password}';
CREATE DATABASE IF NOT EXISTS \`${MYSQL_DATABASE}\`;
CREATE USER IF NOT EXISTS '${MYSQL_USER}'@'%' IDENTIFIED BY '${escaped_mysql_password}';
ALTER USER '${MYSQL_USER}'@'%' IDENTIFIED BY '${escaped_mysql_password}';
GRANT ALL PRIVILEGES ON \`${MYSQL_DATABASE}\`.* TO '${MYSQL_USER}'@'%';
FLUSH PRIVILEGES;
EOF
else
mysql -u root -p"${MYSQL_ROOT_PASSWORD}" << EOF
CREATE DATABASE IF NOT EXISTS \`${MYSQL_DATABASE}\`;
CREATE USER IF NOT EXISTS '${MYSQL_USER}'@'%' IDENTIFIED BY '${escaped_mysql_password}';
ALTER USER '${MYSQL_USER}'@'%' IDENTIFIED BY '${escaped_mysql_password}';
GRANT ALL PRIVILEGES ON \`${MYSQL_DATABASE}\`.* TO '${MYSQL_USER}'@'%';
FLUSH PRIVILEGES;
EOF
fi

# 一時起動したMariaDBを停止
mysqladmin -u root -p"${MYSQL_ROOT_PASSWORD}" shutdown
wait "${temporary_pid}" >/dev/null 2>&1 || true
trap - EXIT

# メインプロセスとしてMariaDBをフォアグラウンドで起動
echo "MariaDB starting..."
exec mysqld --user=mysql --datadir=/var/lib/mysql
