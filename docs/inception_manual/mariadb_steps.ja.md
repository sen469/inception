# MariaDB 構築・完全手順書

この手順書に従えば、MariaDBコンテナをプロジェクト要件（Mandatory）を満たした状態で完成させることができます。

---

## 1. 構成図とディレクトリ準備

まず、以下の構造になっているか確認してください。

```text
srcs/requirements/mariadb/
├── Dockerfile
├── conf/
│   └── 50-server.cnf
└── tools/
    └── init.sh
```

---

## 2. 設定ファイルの準備 (`conf/50-server.cnf`)

Debian等のデフォルト設定では外部接続が禁止されています。これを許可します。

1.  ベースとなる設定ファイルを（もしあれば）コピーして持ってくるか、新規作成します。
2.  以下の箇所を必ず修正してください。

```ini
[mysqld]
# デフォルトの 127.0.0.1 から 0.0.0.0 に変更
# これにより、別コンテナ（wordpress）からの接続が可能になります。
bind-address = 0.0.0.0

# ポート番号（デフォルト3306）
port = 3306

# データ保存先（コンテナ内のパス）
datadir = /var/lib/mysql

# ソケットファイル
socket = /run/mysqld/mysqld.sock
```

---

## 3. 初期化スクリプトの作成 (`tools/init.sh`)

MariaDBは、インストール直後は空っぽです。WordPress用のDBとユーザーを自動で作る必要があります。

**実装のポイント:**
- MariaDBを一時的に起動して設定を行う。
- 環境変数を使ってパスワードなどを柔軟に変更可能にする。
- 最後に `exec mysqld` で PID 1 を譲る。

```bash
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
```

---

## 4. Dockerfile の作成

```dockerfile
# ベースイメージの指定 (Debian trixie 等)
FROM debian:trixie

# パッケージの更新と MariaDB のインストール
RUN apt-get update && apt-get install -y \
    mariadb-server \
    mariadb-client \
    && rm -rf /var/lib/apt/lists/*

# 設定ファイルのコピー
COPY conf/50-server.cnf /etc/mysql/mariadb.conf.d/50-server.cnf

# 初期化スクリプトのコピー
COPY tools/init.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/init.sh

# MariaDBが使用するポート
EXPOSE 3306

# エントリポイントの指定
ENTRYPOINT ["/usr/local/bin/init.sh"]
```

---

## 5. Docker Compose での接続設定 (`srcs/docker-compose.yml`)

```yaml
services:
  mariadb:
    build:
      context: ./requirements/mariadb
    image: mariadb
    container_name: mariadb
    restart: always
    environment:
      MYSQL_DATABASE: ${MYSQL_DATABASE}
      MYSQL_USER: ${MYSQL_USER}
      MYSQL_PASSWORD: ${MYSQL_PASSWORD}
      MYSQL_ROOT_PASSWORD: ${MYSQL_ROOT_PASSWORD}
    volumes:
      - mariadb_data:/var/lib/mysql
    networks:
      - inception_network

volumes:
  mariadb_data:
    driver: local
    driver_opts:
      type: none
      o: bind
      device: /home/${USER_LOGIN}/data/mariadb

networks:
  inception_network:
    driver: bridge
```

---

## 6. 動作確認・テスト

1.  `make` でコンテナを起動。
2.  以下のコマンドでDBコンテナに入り、正しく設定されているか確認する。
    ```bash
    docker exec -it mariadb mariadb -u <user_name> -p
    ```
3.  SQLを叩いてみる：
    ```sql
    SHOW DATABASES; -- 自分の作ったDBがあるか？
    SELECT User FROM mysql.user; -- 自分の作ったユーザーがあるか？
    ```

---

### 注意事項
- **PID 1**: `ps` コマンドで `mysqld` が PID 1 になっていることを確認してください。
- **秘密情報**: `.env` ファイルに書いたパスワードが正しく反映されているか確認してください。
