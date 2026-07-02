*このプロジェクトは ssawa により 42 カリキュラムの一環として作成されました。*

# Inception

## 概要

Inception は、Docker Compose を使って小さな本番風 Web インフラを構築する課題です。
このスタックは、役割を分離した3つのサービスで構成されています。

- `nginx`: 外部公開される唯一の入口です。HTTPS の `443` 番ポートで待ち受け、
  TLSv1.2 または TLSv1.3 のみを受け付けます。
- `wordpress`: PHP-FPM で WordPress を実行します。NGINX は含めません。
- `mariadb`: WordPress 用のデータベースです。NGINX は含めません。

各サービスは `srcs/requirements/` 配下にある専用 Dockerfile からビルドします。
ベースイメージは、2026年7月時点で Debian の1つ前の安定版である
`debian:bookworm` です。許可された Debian ベースイメージ以外のサービス用
完成済みイメージは Docker Hub から取得しません。

内部通信には Docker のユーザー定義 bridge network を使います。
ホストへポート公開するのは NGINX だけです。WordPress と MariaDB は Compose
ネットワーク内のサービス名でのみ到達できます。WordPress ファイルと MariaDB
データは名前付き Docker volume に保存し、その local driver の保存先を
`/home/<login>/data/wordpress` と `/home/<login>/data/mariadb` に向けています。

### 主な設計判断

**仮想マシンと Docker:** 仮想マシンは独自のカーネルを含む完全な OS を仮想化します。
Docker コンテナはホストカーネルを共有し、Linux namespace と cgroup により
プロセスを分離します。そのため、サービス単位のインフラを軽量かつ再現性高く
構成できます。

**Secrets と環境変数:** ドメイン名やデータベース名のような非秘密情報は
`srcs/.env` に置きます。パスワードは Docker Compose secrets として
`/run/secrets/...` にマウントします。これにより、`docker inspect` で平文の
環境変数として露出することを避けます。

**Docker network と host network:** このスタックではユーザー定義 bridge network
を使います。コンテナ同士は `mariadb` や `wordpress` というサービス名で解決でき、
内部ポートをホストへ公開する必要がありません。`network: host`、`links`、
`--link` は使いません。

**Docker volume と bind mount:** サービスには生のホストパスではなく、
`mariadb_data` と `wordpress_data` という名前付き Docker volume をマウントします。
これらの volume は local driver option により、課題要件どおり
`/home/<login>/data` 配下へ保存されます。

## 手順

ローカル環境ファイルを作成します。

```sh
cp srcs/.env.example srcs/.env
```

`srcs/.env` を編集し、`USER_LOGIN` と `DOMAIN_NAME` を自分の 42 ログインに
合わせます。例は `ssawa` と `ssawa.42.fr` です。

ローカル secret ファイルを作成します。これらのファイルは意図的に Git 管理外です。

```sh
mkdir -p secrets
read -rsp 'MariaDB ユーザーパスワード: ' DB_PASSWORD && printf '\n'
printf '%s\n' "$DB_PASSWORD" > secrets/db_password.txt
read -rsp 'MariaDB root パスワード: ' DB_ROOT_PASSWORD && printf '\n'
printf '%s\n' "$DB_ROOT_PASSWORD" > secrets/db_root_password.txt
read -rsp 'WordPress 管理者パスワード: ' WP_OWNER_PASSWORD && printf '\n'
printf '%s\n' "$WP_OWNER_PASSWORD" > secrets/wp_admin_password.txt
read -rsp 'WordPress 一般ユーザーパスワード: ' WP_AUTHOR_PASSWORD && printf '\n'
printf '%s\n' "$WP_AUTHOR_PASSWORD" > secrets/wp_user_password.txt
unset DB_PASSWORD DB_ROOT_PASSWORD WP_OWNER_PASSWORD WP_AUTHOR_PASSWORD
```

VM 側の名前解決にドメインを追加します。

```sh
echo '127.0.0.1 ssawa.42.fr' | sudo tee -a /etc/hosts
```

スタックをビルドして起動します。

```sh
make
```

よく使うコマンドは次の通りです。

```sh
make ps
make logs
make config
make down
make clean
make fclean
```

起動後、次の URL を開きます。

- Web サイト: `https://<login>.42.fr`
- WordPress 管理画面: `https://<login>.42.fr/wp-admin`

TLS 証明書は自己署名証明書なので、ブラウザは証明書警告を表示します。
この課題では想定される挙動です。

## 参考資料

- 42 Inception 課題本文: `docs/subject.ja.md`
- レビュー防衛資料: `docs/inception_manual/review_book.ja.md`
- ユーザー向け手順書: `USER_DOC.md`
- 開発者向け説明書: `DEV_DOC.md`
- Debian リリース情報: https://www.debian.org/releases/
- Docker Compose ドキュメント: https://docs.docker.com/compose/
- Dockerfile リファレンス: https://docs.docker.com/reference/dockerfile/
- NGINX ドキュメント: https://nginx.org/en/docs/
- MariaDB ドキュメント: https://mariadb.com/kb/en/documentation/
- WordPress CLI ドキュメント: https://developer.wordpress.org/cli/commands/
- PHP-FPM ドキュメント: https://www.php.net/manual/ja/install.fpm.php

AI は、課題要件との照合、entrypoint script の堅牢化、Docker Compose 設定の改善、
レビュー向け資料の下書きに使用しました。最終的なファイルは、評価前に学生本人が
読み、検証し、自分の言葉で説明できる状態にしておく必要があります。
