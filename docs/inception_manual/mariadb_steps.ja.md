# MariaDB 構築・解説

対象ファイル:

```text
srcs/requirements/mariadb/
├── Dockerfile
├── .dockerignore
├── conf/50-server.cnf
└── tools/init.sh
```

## 1. 役割

MariaDB コンテナは WordPress のデータベースだけを担当します。NGINX は含めず、ホストにも `3306` を公開しません。WordPress コンテナだけが Docker network 経由で `mariadb:3306` に接続します。

## 2. Dockerfile

`debian:bookworm` をベースに、`mariadb-server` と `mariadb-client` をインストールします。

```dockerfile
FROM debian:bookworm
RUN apt-get update && apt-get install -y --no-install-recommends mariadb-server mariadb-client
```

設定ファイル `50-server.cnf` と entrypoint `init.sh` をコピーし、コンテナ起動時に `init.sh` を実行します。

Dockerfile にパスワードは書きません。DBパスワードと root パスワードは実行時に secrets として渡します。

## 3. `50-server.cnf`

重要な設定:

```ini
[mysqld]
bind-address = 0.0.0.0
port = 3306
datadir = /var/lib/mysql
socket = /run/mysqld/mysqld.sock
```

`bind-address = 0.0.0.0` は別コンテナからの接続を受けるために必要です。ただし Compose で `ports:` を指定していないため、ホスト外部へ DB を公開する設定ではありません。

## 4. `init.sh`

entrypoint の責務は次です。

1. `MYSQL_DATABASE`, `MYSQL_USER` を検査する。
2. `MYSQL_PASSWORD_FILE`, `MYSQL_ROOT_PASSWORD_FILE` から secrets を読む。
3. DB名とユーザー名が英数字とアンダースコアだけか検査する。
4. `/run/mysqld` を作り、`/run/mysqld` と `/var/lib/mysql` を `mysql` ユーザーに所有させる。
5. `/var/lib/mysql/mysql` がなければ `mysql_install_db` で初期化する。
6. 一時 MariaDB を起動し、最大60秒待ってから DB、ユーザー、権限を作る。
7. 一時 MariaDB を停止する。異常終了時にも `trap` で停止を試みる。
8. 最後に `exec mysqld --user=mysql --datadir=/var/lib/mysql` で本番プロセスを起動する。

## 5. 初期化済み判定

`/var/lib/mysql/mysql` は MariaDB のシステムテーブル領域です。このディレクトリが存在する場合、DB ディレクトリは初期化済みと判断できます。

ホスト上の `/home/<login>/data/mariadb` を実体にする named volume は、作成タイミングや環境によって所有者がずれる可能性があります。そのため entrypoint は毎回 `/var/lib/mysql` を `mysql:mysql` に揃えます。MariaDB 本体は最後に `--user=mysql` で起動するため、データディレクトリを `mysql` が読める必要があります。

これにより、コンテナ再起動時に `mysql_install_db` を再実行して既存データを壊すことを避けます。

## 6. SQL の意味

初回起動時は root パスワードを設定し、WordPress 用 DB とユーザーを作ります。

```sql
ALTER USER 'root'@'localhost' IDENTIFIED BY '...';
CREATE DATABASE IF NOT EXISTS `wordpress`;
CREATE USER IF NOT EXISTS 'wp_user'@'%' IDENTIFIED BY '...';
GRANT ALL PRIVILEGES ON `wordpress`.* TO 'wp_user'@'%';
FLUSH PRIVILEGES;
```

`'%'` は接続元ホストのワイルドカードです。WordPress は別コンテナなので、localhost 限定では接続できません。

## 7. PID 1

初期化のために一時的に `mysqld_safe` をバックグラウンド起動しますが、それは設定作業用です。通常系では `mysqladmin shutdown` で停止し、異常系でも `trap` で root パスワードあり、なし、一時プロセス停止の順に後始末を試みます。最後は `exec mysqld ...` で MariaDB 本体をフォアグラウンド起動します。

`exec` によりシェルではなく MariaDB が PID 1 になります。Docker の停止シグナルを MariaDB が直接受け取れるため、より安全に終了できます。

## 8. レビューでの説明

MariaDB は内部ネットワークだけで使う DB サービスです。外部公開せず、データは named volume `mariadb_data` に永続化します。初期化スクリプトは再起動しても既存データを壊さないよう、初期化済み判定を持っています。
