# サービス解説 02: WordPress と PHP-FPM

Inceptionプロジェクトにおける最大の難関の一つが、「NGINX なしで WordPress を動かす」という要件です。本章では、そもそもWordPressとは何かという基礎と、これを実現するための仕組み（PHP-FPM）、そして自動化のためのツールについて解説します。

## 1. そもそも WordPress とは何か？

WordPress（ワードプレス）は、世界中のWebサイトの4割以上で使われていると言われる **CMS (コンテンツ・マネジメント・システム)** です。

HTMLやCSSの知識がなくても、ブログの記事を書いたり、Webサイトのデザインを変更したりできる「管理画面」を提供してくれます。

### WordPress の正体
WordPress の実体は、単なる **「何千個もの PHP言語 で書かれたプログラムの集まり（ソースコード）」** です。
しかし、WordPress単体では何もできません。以下の2つの「協力者」がいて初めてWebサイトとして機能します。

1.  **Webサーバー (今回はNGINX):** 外部からのアクセスを受け取り、「このPHPプログラムを動かして！」と指示を出してくれる窓口。
2.  **データベース (今回はMariaDB):** WordPressが生成した記事のデータや、ユーザーのパスワードなどを永続的に保存しておく巨大な倉庫。

つまり WordPress は、**「NGINX（入り口）と MariaDB（データ倉庫）の間でビジネスロジック（処理）を実行する、アプリケーション層の主役」** なのです。

## 2. PHP-FPM とは何か？

普段私たちが「Webサーバー（Apacheなど）でPHPを動かす」と言う時、多くの場合 PHP は Webサーバーの「一部（モジュール）」として動作しています。

しかし今回の要件では、NGINX（Webサーバー）と WordPress（PHP）は **別々のコンテナに物理的に分かれています**。

そこで登場するのが **PHP-FPM (FastCGI Process Manager)** です。
PHP-FPM は、Webサーバー機能を持たない **「PHPを実行するためだけの独立したプログラム（プロセス）」** です。

*   **動き:** PHP-FPM は、デフォルトで `9000` 番ポートを開けて待機しています。
*   **通信:** NGINXから「このPHPファイルを実行して！」という依頼（FastCGIプロトコル）をネットワーク経由で受け取り、PHPプログラムを実行して、その結果（HTMLなど）をNGINXに返します。

### PHP-FPM の設定変更 (UNIXソケット vs TCPソケット)
Debian等で `php-fpm` をインストールすると、デフォルトでは `listen = /run/php/php8.4-fpm.sock` のように、コンテナ内でのみ使える特殊なファイル（UNIXソケット）で待機する設定になっています。

これは **「プロセス間通信 (IPC)」** の方式に関わります。
*   **UNIXドメインソケット (`.sock` ファイル):** Linuxの「ファイルシステム」を使って、**同じPC（コンテナ）の中にいるプロセス同士**が超高速でデータをやり取りする仕組みです。しかし、外の世界（別のコンテナ）とは通信できません。
*   **TCPソケット (`9000` などのポート):** IPアドレスとポート番号を使って、ネットワーク越しに通信する仕組みです。

今回のInceptionでは「NGINXコンテナ」と「WordPressコンテナ」が物理的に分かれているため、どんなに高速でも「同じPC内限定」のUNIXソケットは使えません。そのため、ネットワーク経由で指示を受け取れるように設定ファイル（`www.conf`）を以下のように書き換える必要があります。

```ini
; 変更前 (UNIXソケット: 同じコンテナ内のみ)
listen = /run/php/php8.4-fpm.sock

; 変更後 (TCPソケット: ポート9000で、誰からでも通信を受け付ける)
listen = 9000
```
これを実現するために、自分で書き換えた `www.conf` を `Dockerfile` でコンテナ内に `COPY` して上書きします。

## 2. WP-CLI を使った WordPress の完全自動化

WordPress を普通にインストールすると、ブラウザからアクセスして「データベース名」「ユーザー名」「パスワード」を手動で入力する初期画面（インストーラー）が表示されます。

しかし、Dockerコンテナは「起動したら全て自動で完了している」状態（IaC）が求められるため、手作業での入力はNGです。

そこで **WP-CLI (WordPress Command Line Interface)** というツールを使います。これを使うと、黒い画面（ターミナル）のコマンドだけでWordPressのインストールからユーザー作成まで全て行えます。

### WP-CLI の実行例 (起動スクリプト内で使用するイメージ)

```bash
# 1. wp-config.php (設定ファイル) を作成し、DB接続情報を書き込む
wp config create --dbname=$MYSQL_DATABASE --dbuser=$MYSQL_USER --dbpass=$MYSQL_PASSWORD --dbhost=mariadb --allow-root

# 2. WordPress をインストール（サイト名、URL、管理者情報を設定）
wp core install --url=$DOMAIN_NAME --title="Inception Site" --admin_user=$WP_ADMIN_USER --admin_password=$WP_ADMIN_PASSWORD --admin_email=$WP_ADMIN_EMAIL --allow-root

# 3. 課題要件の「管理者以外の一般ユーザー」を作成
wp user create $WP_USER $WP_USER_EMAIL --user_pass=$WP_USER_PASSWORD --role=author --allow-root
```
*(※ `--allow-root` は、コンテナのrootユーザーとしてWP-CLIを実行するために必要なオプションです)*

## 3. WordPressコンテナの `Dockerfile` の流れ

1.  `FROM debian`
2.  `RUN apt-get` で `php-fpm`, `php-mysqli`（DBと話すための拡張）, `curl`, `mariadb-client` などをインストール。
3.  `curl` を使って `wp-cli.phar` をダウンロードし、実行権限を与えて `/usr/local/bin/wp` に配置。
4.  WordPress本体（ソースコード）をダウンロードして `/var/www/html` に展開。
5.  設定済みの `www.conf` を `COPY`。
6.  上記「WP-CLIのコマンド」と「最後に `php-fpm` を起動する処理」を書いた **起動スクリプト（`setup.sh`）** を `COPY`。
7.  `EXPOSE 9000`
8.  `ENTRYPOINT ["/setup.sh"]`

このように、WordPressコンテナは「PHPを実行する環境」と「初期セットアップを自動で行うスクリプト」の2つの役割を持たせることが正解です。
