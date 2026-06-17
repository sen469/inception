# Inception プロジェクト・ロードマップ

このドキュメントは、42の課題「Inception」をスタートからゴールまで進めるための手順書です。
ボーナスパートを除いた、**Mandatory（必須パート）**を確実にクリアすることを目的に構成されています。

---

## 1. 準備フェーズ：インフラと共通設定

まずは土台となる環境と共通設定を整えます。

- [ ] **仮想マシンの準備**
  - Debian または Alpine の VM を用意し、Docker と Docker Compose をインストールする。
- [ ] **ドメイン設定**
  - VM の `/etc/hosts` に `127.0.0.1 <your_login>.42.fr` を追加する。
- [ ] **ディレクトリ構造の整備**
  - `srcs/requirements/` 以下に `mariadb`, `wordpress`, `nginx` のディレクトリを作成。
  - 各ディレクトリに `Dockerfile`, `conf/`, `tools/` を配置。
- [ ] **環境変数の設定 (`srcs/.env`)**
  - DB名、DBユーザー名、DBパスワード、WP管理者情報、WP一般ユーザー情報、ドメイン名を定義。
  - **注意:** パスワード類は Docker secrets を使うことが推奨されているため、`secrets/` ディレクトリの利用も検討する。
- [ ] **ホスト側のデータ保存先作成**
  - `/home/<your_login>/data/mariadb` と `/home/<your_login>/data/wordpress` を作成する。

---

## 2. データベースフェーズ：MariaDB

WordPress のデータを保存する基盤を作ります。

- [ ] **Dockerfile の作成**
  - `debian:trixie` (または指定のバージョン) をベースにする。
  - `mariadb-server` をインストール。
- [ ] **設定ファイルの編集 (`50-server.cnf`)**
  - `bind-address = 0.0.0.0` に変更し、外部接続を許可する。
- [ ] **初期化スクリプト (`init.sh`) の作成**
  - コンテナ起動時に以下の処理を行う。
    - データベースの作成。
    - 管理者ユーザーの作成。
    - 一般ユーザーの作成。
    - 権限の付与 (`FLUSH PRIVILEGES`)。
  - `mysqld_safe` または `mysqld` をフォアグラウンドで実行（PID 1）。

---

## 3. アプリケーションフェーズ：WordPress + PHP-FPM

Web アプリケーションの本体を設定します。

- [ ] **Dockerfile の作成**
  - `php-fpm` と `mariadb-client`, `curl` などをインストール。
  - `wp-cli` をダウンロードし、実行権限を付与して `/usr/local/bin/wp` に配置。
- [ ] **PHP-FPM の設定 (`www.conf`)**
  - `listen = 9000` に設定（ポート 9000 で NGINX からの要求を待機）。
- [ ] **エントリーポイントスクリプト (`setup.sh`) の作成**
  - WordPress が未インストールの場合に以下を実行。
    - `wp core download`
    - `wp config create` (DB接続情報の設定)
    - `wp core install` (サイト名、管理者情報の設定)
    - `wp user create` (一般ユーザーの作成)
  - `php-fpm -F` をフォアグラウンドで実行。

---

## 4. サーバーフェーズ：NGINX

インフラへの唯一のエントリーポイントです。

- [ ] **SSL 証明書の生成**
  - `openssl` を使い、TLS v1.2/v1.3 用の自己署名証明書と秘密鍵を生成する。
- [ ] **設定ファイルの作成 (`nginx.conf`)**
  - ポート 443 で listen。
  - `ssl_protocols TLSv1.2 TLSv1.3;` を指定。
  - `fastcgi_pass wordpress:9000;` を含め、PHPのリクエストをWordPressコンテナに飛ばす設定。
- [ ] **Dockerfile の完成**
  - NGINXをインストールし、設定ファイルと証明書をコピー。
  - `nginx -g "daemon off;"` で実行。

---

## 5. 統合フェーズ：Docker Compose & Makefile

すべてを連携させ、自動化します。

- [ ] **`srcs/docker-compose.yml` の記述**
  - `services`: `mariadb`, `wordpress`, `nginx` のビルドコンテキスト、環境変数、ボリューム、ネットワーク、依存関係 (`depends_on`) を設定。
  - `volumes`: ネームドボリュームを定義し、ホストパスに紐付け。
  - `networks`: 共通のネットワークを定義。
- [ ] **Makefile の完成**
  - `all`: データ用ディレクトリ作成 + `docker-compose up --build -d`。
  - `down`: `docker-compose down`。
  - `re`: `fclean` 実行後に `all`。
  - `clean`: コンテナ停止。
  - `fclean`: コンテナ、ボリューム、イメージ、ネットワークの全削除。

---

## 6. 最終確認・ドキュメントフェーズ

評価基準を満たしているか確認します。

- [ ] **動作確認**
  - `https://<your_login>.42.fr` にアクセスして WordPress が表示されるか。
  - SSL証明書が有効か、TLS 1.2/1.3が使われているか。
  - DBに2人のユーザーが正しく作成されているか。
  - ボリュームを削除してもデータが永続化されているか。
- [ ] **必須ドキュメントの作成**
  - `README.md`
  - `USER_DOC.md`
  - `DEV_DOC.md`
- [ ] **禁止事項のチェック**
  - `latest` タグを使っていないか。
  - Dockerfileにパスワードを直書きしていないか。
  - `network: host` や `links:` を使っていないか。
  - `tail -f` などのハックを使っていないか。
