# サービス解説 03: MariaDB とデータベース管理

Inceptionスタックの最下層（データ層）を担うのが MariaDB コンテナです。本章では、そもそもデータベースとは何かという基礎から、MariaDB をコンテナで動かす際の設定、そして自動初期化の手法について解説します。

## 1. そもそもデータベース (DB) / MariaDB とは何か？

Webサイト（WordPressなど）は、記事の文章、ユーザーのパスワード、コメントなどの「永続的に保存すべきデータ」を扱います。これらを単なるテキストファイルとして保存すると、同時に複数の人がアクセスした際にデータが壊れたり、検索が非常に遅くなったりします。

これを解決するのが **リレーショナル・データベース管理システム (RDBMS)** です。
データをエクセルのような「表（テーブル）」の形式で整理し、**SQL** という専用の言語を使って「高速に検索・追加・更新・削除」を行うための専門ソフトウェアです。

**MariaDB と MySQL の関係:**
MariaDB は、世界で最も普及しているデータベースである MySQL から派生（フォーク）したソフトウェアです。MySQLが企業（Oracle社）に買収された後、オープンソースの理念を保つためにオリジナルの開発者たちによって作られました。そのため、コマンド（`mysql`等）や使い方は MySQL と完全に互換性があります。

## 2. 外部からの通信を許可する (bind-address)

MariaDB（やMySQL）を Debian 等にインストールすると、デフォルトの設定ではセキュリティ上 **「自分自身（localhost / 127.0.0.1）からの接続しか受け付けない」** ようになっています。

今回は WordPress コンテナからネットワーク（Dockerネットワーク）経由で接続されるため、この設定を変更しなければなりません。

MariaDB の設定ファイル（通常 `/etc/mysql/mariadb.conf.d/50-server.cnf` 等）の中にある `bind-address` を以下のように変更します。

```ini
# 変更前
bind-address = 127.0.0.1

# 変更後（0.0.0.0 は「すべてのIPアドレスからの接続を許可する」という意味）
bind-address = 0.0.0.0
```
WordPressコンテナの `www.conf` と同じように、自分で書き換えた設定ファイルを `Dockerfile` で `COPY` して上書きします。

## 3. データベースとユーザーの自動作成

コンテナが起動した際、初期状態の MariaDB には WordPress 用のデータベースも、専用のユーザーも存在しません。これらを起動時に自動で作るためのシェルスクリプト（Entrypoint）を用意する必要があります。

### SQL文を使った初期化
ターミナル上で MariaDB を操作するには、以下のように `mysql -e` コマンドに直接SQL文を渡す方法が便利です。

```bash
# データベースの作成
mysql -e "CREATE DATABASE IF NOT EXISTS \`${MYSQL_DATABASE}\`;"

# ユーザーの作成（パスワード付き）
mysql -e "CREATE USER IF NOT EXISTS \`${MYSQL_USER}\`@'%' IDENTIFIED BY '${MYSQL_PASSWORD}';"

# ユーザーにデータベースへの全権限を付与
mysql -e "GRANT ALL PRIVILEGES ON \`${MYSQL_DATABASE}\`.* TO \`${MYSQL_USER}\`@'%';"

# 権限の変更を反映
mysql -e "FLUSH PRIVILEGES;"
```

### FLUSH PRIVILEGES; の裏側にある真実
「権限を反映させるおまじない」と説明されることが多い上記の `FLUSH PRIVILEGES;` ですが、内部では何が起きているのでしょうか。

MariaDBは高速化のため、ユーザーの権限データ（誰がどのデータベースにアクセスできるか）を「ディスク上のテーブル」から**「メモリ（RAM）上へキャッシュ」**して保持しています。
システムが直接ディスク上のテーブルを書き換えたり複雑な権限変更を行った際、「ディスク上のデータ」と「メモリ上のキャッシュ」にズレが生じることがあります。
`FLUSH PRIVILEGES;` は、MariaDB に対して「今すぐメモリ上の古い権限キャッシュを全部捨てて、もう一度ディスクから最新の情報を読み込み直しなさい！」と強制するコマンドです。確実に権限変更を適用させてから WordPress に明け渡すための安全策（フェイルセーフ）なのです。

### 注意点: MariaDB デーモンの起動タイミング
初期化スクリプトを書く際、初心者が必ず陥る罠があります。
「スクリプトの中で `mysql -e` コマンドを実行しようとしても、**まだ MariaDB のサーバー（デーモン）が起動していないからエラーになる**」という問題です。

**正しい流れ（スクリプトの例）:**
1.  まず、バックグラウンドで MariaDB サーバーを一時的に起動する（例: `service mariadb start` または `mysqld_safe &`）。
2.  数秒待つか、通信できるか確認する。
3.  `mysql -e` コマンドを使って、上記の初期化SQLを実行する。
4.  （もし `mysqld_safe &` で起動していたら、一度それを停止する）
5.  最後に、コンテナのメインプロセス（PID 1）として MariaDB をフォアグラウンドで正式に起動する。

## 4. セキュリティと機密情報の渡し方

上記のスクリプト例では `${MYSQL_USER}` のような変数を使っています。
この変数の値（パスワードなど）は、`docker-compose.yml` から渡されます。

**NGな例:** Dockerfile に直接書く
```dockerfile
ENV MYSQL_PASSWORD=super_secret_password
```

**OKな例:** `docker-compose.yml` と `.env` または Docker Secrets を使う
```yaml
# docker-compose.yml の記述
services:
  mariadb:
    environment:
      MYSQL_DATABASE: ${DB_NAME}
      MYSQL_USER: ${DB_USER}
      MYSQL_PASSWORD: ${DB_PASS}
```

※ Inceptionの要件では、パスワード等は `.env` ファイルか Docker Secrets に保存し、Gitリポジトリ（Githubなど）には絶対にコミットしない（`.gitignore` に書く）ことが強く求められています。

## 5. MariaDBコンテナの `Dockerfile` の流れ

1.  `FROM debian`
2.  `RUN apt-get` で `mariadb-server` をインストール。
3.  `bind-address = 0.0.0.0` に変更した設定ファイルを `COPY`。
4.  上記の「データベースとユーザーを作成するシェルスクリプト（`init.sh`）」を `COPY` して実行権限（`chmod +x`）を付与。
5.  `EXPOSE 3306`
6.  `ENTRYPOINT ["/init.sh"]`
