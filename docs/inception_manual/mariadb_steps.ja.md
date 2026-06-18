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

### 重要な設定項目：各設定の意味

- **`bind-address`**: MariaDB がどのネットワークインターフェース（入り口）で接続を待機するかを指定します。
    - **`127.0.0.1`**: 自分自身からの接続のみ許可（Inception では通信不可）。
    - **`0.0.0.0`**: すべての入り口を開放。Docker ネットワーク経由で WordPress からの接続を受け入れるために必須の設定です。
- **`datadir`**: データベースの実体（テーブルデータ、ユーザー情報等）が保存される物理的なパスです。
    - **永続化**: このディレクトリを Docker ボリュームにマウントすることで、コンテナを消してもデータが残るようにします。
- **`socket`**: 同じコンピューター（コンテナ）内のプロセス間通信 (IPC) に特化した「窓口」です。
    - **具体的な使用者**: 
        - **管理者**: コンテナ内で `mariadb` コマンドを実行し、サーバーを操作する際に自動的に使用されます。
        - **初期化スクリプト**: `init.sh` 内で DB やユーザーを作成するコマンドがサーバーと通信する際に使用されます。
    - **技術的な仕組み**: ネットワークカードやプロトコルスタックを通さず、OS カーネルがメモリ上で直接データを転送します。

### なぜファイル名が「50-server.cnf」なのか？

MariaDB は `/etc/mysql/mariadb.conf.d/` ディレクトリ内のファイルを **ファイル名の昇順（辞書順/ASCII順）** に読み込みます。

- **優先順位**: 同じ設定項目が複数のファイルにある場合、**後から読み込まれた設定が優先（上書き）** されます。
- **数字を使うメリット**:
    - **文字（a, b, c）も使用可能**: `a.cnf` より `b.cnf` が後に読み込まれますが、数字の方が「10 と 20 の間に 15 を入れる」といった修正が容易です。
    - **一目瞭然**: アルファベット名よりも、数字の方が読み込み順序を直感的に理解しやすく、管理ミスを防げます。
- **50 の意味**: これは Debian 系の慣習で、標準的なアプリケーション設定であることを示します。OS が用意した初期設定（10番台など）を読み込んだ後に、自分の設定（50番）で上書きするという流れが一般的です。

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

### スクリプトの動作解説：何が行われているのか？

1.  **ランタイムディレクトリの作成**: `/run/mysqld` は MariaDB が通信用のソケットファイルを置く場所です。これがないと起動エラーになるため、起動時に必ず作成し、`mysql` ユーザーに権限を与えます。
2.  **データベースの初期化 (`mysql_install_db`)**: ボリュームが空の場合のみ、システムテーブルを生成します。2回目以降の起動（データが既にある場合）はスキップされるため、データは保護されます。
3.  **一時的なバックグラウンド起動 (`mysqld_safe &`)**: 設定コマンド (`mysql -e`) を実行するためには、MariaDB サーバーが動いている必要があります。そのため、設定作業用に一旦バックグラウンドで起動させます。
4.  **SQLによる自動セットアップ**:
    - **rootパスワード**: `ALTER USER` で最高管理者のパスワードを設定します。
    - **DB作成**: `CREATE DATABASE` で WordPress 専用の領域を確保します。
    - **ユーザー作成と権限付与**: `CREATE USER` と `GRANT` を使い、WordPress が DB に接続するための専用アカウントを作成し、適切な権限を与えます。
5.  **クリーンな終了 (`shutdown`) と本番起動 (`exec mysqld`)**: 
    - **なぜ一旦止めるのか？**: 初期設定を行うために一時起動した MariaDB はバックグラウンド（脇役）プロセスです。
    - **PID 1 (主役) の移譲**: `exec` を使って MariaDB をフォアグラウンドで再起動することで、MariaDB がコンテナの **PID 1** になります。
    - **Graceful Shutdown**: PID 1 になることで、`docker stop` などの終了シグナルを MariaDB が直接受け取れるようになります。これにより、データの書き込みを完了させてから安全に終了することが可能になり、データ破損を防げます。
- **ディレクトリ存在チェック (`if [ ! -d ... ]`)**:
    - **`[ ! -d "path" ]`**: 「指定したパスにディレクトリが存在**しない**場合」という条件式です。
    - **べき等性 (Idempotency) の確保**: 起動スクリプトにおいて、このチェックは「初回起動時のみ特定の処理（DB作成など）を行い、再起動時にはスキップする」ために使用されます。これにより、既存のデータを破壊することなく、何度コンテナを起動しても安全にシステムが立ち上がるようになります。

### SQL 文法のポイント解説

`init.sh` 内で実行される SQL 命令の意味は以下の通りです。

- **`ALTER USER`**: 既存ユーザー（主に root）の設定を変更します。パスワードの付与に使用します。
- **`CREATE DATABASE IF NOT EXISTS`**: データベースを新規作成します。`IF NOT EXISTS` を付けることで、再起動時にエラーが出るのを防ぎます。
- **`CREATE USER ... @'%'`**: 新しいユーザーを作成します。`%` は「ワイルドカード」であり、**外部のコンテナ（WordPress 等）からの接続を許可する** ために必須の設定です。
- **`GRANT ALL PRIVILEGES ON db.* TO user`**: 作成したデータベースに対する全操作権限をユーザーに与えます。
- **`FLUSH PRIVILEGES`**: 変更した権限情報を MariaDB のメモリに即座に反映させる「反映ボタン」のような役割です。
- **バッククォート (`` ` ``) の使用**: データベース名やユーザー名を囲むことで、SQL の予約語との衝突を防ぎ、安全に識別子として扱わせます。

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

### Dockerfile 命令の解説

- **`COPY`**: ホスト上の設定ファイルやスクリプトをコンテナ内の指定パスにコピーします。これにより、外部接続を許可する設定 (`50-server.cnf`) などを反映させます。
- **`EXPOSE 3306`**: コンテナが 3306 番ポートで通信を待ち受けていることを明示します。
    - **具体的な役割**: MariaDB サーバーは、起動すると 3306 番窓口（ポート）を常に見張っています。WordPress 等の他のコンテナが MariaDB と通信したい場合、この **3306 番を宛先として** データを送る必要があります。
    - **注意**: このポートは Docker ネットワーク内部でのみ有効です。外部（ホスト OS）から接続したい場合は、別途ポートマッピングが必要になります。
- **`ENTRYPOINT`**: コンテナ起動時に必ず実行されるプログラムを指定します。Inception では、データベースの自動初期化を確実に行うために、作成した `init.sh` を指定することが必須級のテクニックとなります。

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
