#!/bin/bash
set -e

# MariaDBのランタイムディレクトリを作成
if [ ! -d "/run/mysqld" ]; then
    mkdir -p /run/mysqld
    chown -R mysql:mysql /run/mysqld
fi

# データベースが未初期化の場合のみ初期化を実行
if [ ! -d "/var/lib/mysql/mysql" ]; then
    echo "Initializing MariaDB database..."
    mysql_install_db --user=mysql --datadir=/var/lib/mysql > /dev/null
fi

# 一時的にMariaDBを起動（初期設定のため）
mysqld_safe --datadir=/var/lib/mysql &
# 起動を待つ
until mysqladmin ping >/dev/null 2>&1; do
    echo "Waiting for MariaDB to start..."
    sleep 1
done

# 初期設定SQLの実行
# rootパスワードの設定、不要なユーザー/DBの削除、WordPress用DB/ユーザーの作成
mysql -u root << EOF
-- rootユーザーのパスワード設定（推奨）
ALTER USER 'root'@'localhost' IDENTIFIED BY '${MYSQL_ROOT_PASSWORD}';
-- WordPress用データベース作成
CREATE DATABASE IF NOT EXISTS \`${MYSQL_DATABASE}\`;
-- WordPress用ユーザー作成（% は全ホストからの接続を許可）
CREATE USER IF NOT EXISTS \`${MYSQL_USER}\`@'%' IDENTIFIED BY '${MYSQL_PASSWORD}';
-- 権限付与
GRANT ALL PRIVILEGES ON \`${MYSQL_DATABASE}\`.* TO \`${MYSQL_USER}\`@'%';
-- 反映
FLUSH PRIVILEGES;
EOF

# 一時起動したMariaDBを停止
mysqladmin -u root -p${MYSQL_ROOT_PASSWORD} shutdown

# メインプロセスとしてMariaDBをフォアグラウンドで起動
echo "MariaDB starting..."
exec mysqld --user=mysql --datadir=/var/lib/mysql
