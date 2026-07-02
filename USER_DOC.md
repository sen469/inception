# Inception USER_DOC

この文書は、評価者または運用者が Inception スタックを起動し、停止し、状態を確認するための手順書です。実装の深い説明は `DEV_DOC.md` を参照してください。

## 1. 提供されるサービス

このプロジェクトは Docker Compose で次の3サービスを起動します。

| サービス | 役割 | 外部公開 |
| --- | --- | --- |
| `nginx` | HTTPS の入口。TLS 終端と PHP リクエストの転送を担当する。 | `443:443` のみ |
| `wordpress` | WordPress と PHP-FPM。PHP を実行し、DBへ接続する。 | なし |
| `mariadb` | WordPress 用データベース。 | なし |

外部から直接アクセスできるのは `nginx` だけです。`wordpress` と `mariadb` は Docker の内部ネットワーク上でのみ通信します。

## 2. 起動前に必要なファイル

`srcs/.env` を作成します。

```sh
cp srcs/.env.example srcs/.env
```

最低限、次の値を確認してください。

| 変数 | 意味 |
| --- | --- |
| `USER_LOGIN` | 42のログイン名。データ保存先 `/home/<login>/data` に使う。 |
| `DOMAIN_NAME` | `login.42.fr` 形式のドメイン名。 |
| `MYSQL_DATABASE` | WordPress 用データベース名。 |
| `MYSQL_USER` | WordPress が DB 接続に使う一般 DB ユーザー。 |
| `WP_ADMIN_USER` | WordPress 管理者ユーザー。`admin` を含めてはいけない。 |
| `WP_USER` | WordPress 一般ユーザー。 |

パスワードは `.env` ではなく、次の secrets ファイルに保存します。

```text
secrets/db_password.txt
secrets/db_root_password.txt
secrets/wp_admin_password.txt
secrets/wp_user_password.txt
```

これらは Git 追跡対象外です。実際のパスワードをリポジトリに入れないでください。

## 3. ドメイン設定

VM内で次のように `/etc/hosts` を設定します。`ssawa` は自分のログインに置き換えます。

```sh
echo '127.0.0.1 ssawa.42.fr' | sudo tee -a /etc/hosts
```

ブラウザをホスト側から開く構成の場合は、ホスト側の hosts にも VM の IP とドメインを登録します。

## 4. 起動と停止

起動:

```sh
make
```

状態確認:

```sh
make ps
```

ログ確認:

```sh
make logs
```

停止:

```sh
make down
```

このプロジェクトのコンテナ、イメージ、Dockerボリュームを削除:

```sh
make clean
```

ホスト上の永続データも削除:

```sh
make fclean
```

`fclean` は `.env` の `USER_LOGIN` を確認したうえで、`/home/<login>/data/mariadb` と `/home/<login>/data/wordpress` を削除します。WordPress の投稿や DB 内容も消えるため注意してください。

## 5. Webサイトと管理画面へのアクセス

Webサイト:

```text
https://<login>.42.fr
```

WordPress管理画面:

```text
https://<login>.42.fr/wp-admin
```

自己署名証明書を使うため、ブラウザは警告を表示します。Inception では自己署名証明書で TLS を構成できていれば問題ありません。

## 6. 正常性確認

Compose のサービス状態:

```sh
make ps
```

HTTPS 応答:

```sh
curl -kI https://<login>.42.fr
```

TLS バージョン確認:

```sh
openssl s_client -connect <login>.42.fr:443 -tls1_2
openssl s_client -connect <login>.42.fr:443 -tls1_3
```

MariaDB の DB 確認:

```sh
docker exec -it mariadb mariadb -u root -p
```

WordPress ユーザー確認:

```sh
docker exec -it wordpress wp user list --allow-root --path=/var/www/html
```

PID 1 確認:

```sh
docker exec nginx ps -p 1 -o pid,comm,args
docker exec wordpress ps -p 1 -o pid,comm,args
docker exec mariadb ps -p 1 -o pid,comm,args
```

期待値は、NGINX、PHP-FPM、MariaDB がそれぞれメインプロセスとして動いていることです。

## 7. クレデンシャル管理

秘密情報の場所は `secrets/` です。Compose はこれらをコンテナ内の `/run/secrets/<name>` としてマウントします。

パスワードを変更したい場合は、対象 secret ファイルを書き換えてから `make re` します。ただし、MariaDB の root パスワードなど、既存DB内に保存済みの値はボリュームの状態と一致している必要があります。完全に初期化し直す場合は `make fclean` を使います。
