# Inception 静的監査メモ

このメモは、Docker build やコンテナ起動を行わずに、ファイル内容だけで確認できる項目をまとめたものです。実行確認の代替ではありませんが、レビュー前のセルフチェックに使えます。

## 1. 提出ファイル配置

ルート直下の Markdown は提出必須の3ファイルだけにする。

```text
README.md
USER_DOC.md
DEV_DOC.md
```

追加資料は `docs/` 配下に置く。

## 2. `srcs` の必須構成

```text
srcs/
├── .env.example
├── docker-compose.yml
└── requirements
    ├── mariadb
    │   ├── Dockerfile
    │   ├── conf/50-server.cnf
    │   └── tools/init.sh
    ├── nginx
    │   ├── Dockerfile
    │   └── conf/nginx.conf
    └── wordpress
        ├── Dockerfile
        ├── conf/www.conf
        └── tools/setup.sh
```

実際の `srcs/.env` はローカル作成で、Git に入れない。

## 3. 禁止事項検索

次の文字列が `srcs` 実装に出てこないことを確認する。

```text
latest
network: host
links:
--link
tail -f
sleep infinity
while true
MYSQL_PASSWORD: ${MYSQL_PASSWORD}
MYSQL_ROOT_PASSWORD: ${MYSQL_ROOT_PASSWORD}
WP_ADMIN_PASSWORD: ${WP_ADMIN_PASSWORD}
WP_USER_PASSWORD: ${WP_USER_PASSWORD}
```

ただし、ドキュメント中で「禁止事項として説明している」場合の出現は問題ではない。

## 4. Compose の見るべき点

`srcs/docker-compose.yml` で確認する。

- サービスは `mariadb`, `wordpress`, `nginx` の3つ。
- 各サービスに `build.context` がある。
- 各サービスの `image` はサービス名と一致する。
- 各サービスに `restart: always` がある。
- `ports:` は `nginx` の `443:443` だけ。
- `wordpress` と `mariadb` には `ports:` がない。
- `mariadb_data` と `wordpress_data` の2 named volumes がある。
- named volumes の `device` は `/home/${USER_LOGIN}/data/...`。
- `inception_network` は bridge network。
- secrets は `../secrets/*.txt` から読む。

## 4.1 Makefile の見るべき点

- `check-config` が `srcs/.env` の存在を確認している。
- `check-config` が `USER_LOGIN`, `DOMAIN_NAME`, DB名、DBユーザー、WordPressユーザー情報を確認している。
- `check-config` が4つの secret ファイルが空でないことを確認している。
- `down`, `logs`, `ps` が `check-env` を通してから Compose を呼ぶ。
- `fclean` が `check-env` を通して `USER_LOGIN` を確認してから `/home/<login>/data` を削除する。
- `fclean` がプロジェクト外の Docker 資源をまとめて削除しない。

## 5. Dockerfile の見るべき点

各 Dockerfile で確認する。

- `FROM debian:bookworm` を使う。
- `latest` を使わない。
- パスワードを書かない。
- 既存の WordPress / MariaDB / NGINX イメージを使わない。
- WP-CLI の取得に `curl -fsSL` を使い、HTTPエラー時に失敗する。
- WP-CLI 実行用に `php-cli` を入れている。
- WordPress Dockerfile は WordPress 本体を `/usr/src/wordpress` に用意している。
- WordPress Dockerfile は salt のローカル生成用に `openssl` を入れている。
- `apt-get install` 後に `/var/lib/apt/lists/*` を削除する。
- メインプロセスを正しくフォアグラウンド起動する。

## 6. entrypoint の見るべき点

`init.sh` と `setup.sh` で確認する。

- `set -euo pipefail` がある。
- 必須環境変数を検査している。
- secrets を `_FILE` 経由で読んでいる。
- 無限ループでコンテナを維持していない。
- 起動待ちループには失敗上限があり、準備できない場合は終了する。
- WordPress 本体は起動時に外部取得せず、`/usr/src/wordpress` からコピーする。
- `wp config create` は `--skip-check --skip-salts` を使い、saltは初回のみ `openssl rand` で生成する。
- 最後に `exec` で実サービスへ置き換えている。
- 再起動時に初期化処理を二重実行しない条件分岐がある。

## 7. NGINX 設定の見るべき点

`srcs/requirements/nginx/conf/nginx.conf` で確認する。

- `listen 443 ssl;`
- `ssl_protocols TLSv1.2 TLSv1.3;`
- `root /var/www/html;`
- `try_files $uri $uri/ /index.php?$args;`
- `fastcgi_pass wordpress:9000;`
- `fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;`
- `fastcgi_param HTTPS on;`
- 隠しファイルを `deny all` している。

## 7.1 WordPress HTTPS 設定の見るべき点

`srcs/requirements/wordpress/tools/setup.sh` で確認する。

- `wp core install --url="https://${DOMAIN_NAME}"` を使っている。
- `FORCE_SSL_ADMIN` を `true` にしている。
- `WP_HOME` と `WP_SITEURL` を `https://${DOMAIN_NAME}` にしている。

## 8. Dockerなしで実施した静的確認

実行確認ではなく、ファイル整合性として次を確認する。

```sh
bash -n srcs/requirements/mariadb/tools/init.sh
bash -n srcs/requirements/wordpress/tools/setup.sh
find . -maxdepth 1 -type f -name '*.md'
rg -n 'latest|network:\s*host|links:|--link|tail -f|sleep infinity|while true' srcs Makefile
```

Docker build とコンテナ起動は別途、提出前に本人が実施する必要があります。
