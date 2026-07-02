# NGINX 構築・解説

対象ファイル:

```text
srcs/requirements/nginx/
├── Dockerfile
├── .dockerignore
├── conf/nginx.conf
└── tools/entrypoint.sh
```

## 1. 役割

NGINX はこのインフラの唯一の入口です。ホストに公開されるポートは `443` だけで、HTTP 80、WordPress 9000、MariaDB 3306 は公開しません。

## 2. Dockerfile

現在の実装は `debian:bookworm` を使います。`nginx`, `openssl`, `netcat-openbsd` をインストールし、ビルド時引数 `DOMAIN_NAME` で自己署名証明書の Common Name を決めます。`netcat-openbsd` は NGINX 起動前に `wordpress:9000` が接続可能か確認するために使います。

```dockerfile
FROM debian:bookworm
RUN apt-get update && apt-get install -y --no-install-recommends \
    bash \
    netcat-openbsd \
    nginx \
    openssl
```

証明書は `/etc/nginx/ssl/inception.crt`、秘密鍵は `/etc/nginx/ssl/inception.key` に作られます。最後は次の entrypoint で起動します。

```dockerfile
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
```

entrypoint は `wordpress:9000` が開くまで最大120秒待ち、その後 `exec nginx -g "daemon off;"` を実行します。`daemon off;` は NGINX をフォアグラウンドで動かすための正規設定です。`tail -f` のようなコンテナ維持ハックではありません。

## 3. `tools/entrypoint.sh`

Compose の `depends_on` は起動順だけを保証し、WordPress コンテナ内の PHP-FPM が `9000` 番を listen したことまでは保証しません。NGINX が先に起動すると、短時間だけ `502 Bad Gateway` が出ることがあります。

この entrypoint は `nc -z wordpress 9000` で TCP 接続できるまで待ちます。接続可能になってから NGINX を起動するため、初回アクセス時の一時的な 502 を避けやすくなります。

## 4. `nginx.conf`

重要な設定は次です。

```nginx
listen 443 ssl;
listen [::]:443 ssl;
server_name __DOMAIN_NAME__;
ssl_protocols TLSv1.2 TLSv1.3;
root /var/www/html;
index index.php index.html index.htm;
```

`__DOMAIN_NAME__` は Dockerfile の `sed` で `DOMAIN_NAME` に置換されます。NGINX 設定ファイル内では通常のシェル環境変数展開は行われないため、ビルド時に明示的に置換します。

WordPress ルーティングは次で処理します。

```nginx
location / {
    try_files $uri $uri/ /index.php?$args;
}
```

静的ファイルがあれば NGINX が返し、なければ WordPress の `index.php` に渡します。

PHP は NGINX が実行するのではなく、FastCGI で WordPress コンテナの PHP-FPM に渡します。

```nginx
location ~ \.php$ {
    try_files $uri =404;
    fastcgi_pass wordpress:9000;
    fastcgi_index index.php;
    include fastcgi_params;
    fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
    fastcgi_param HTTPS on;
}
```

`wordpress` は Docker Compose のサービス名です。同じ user-defined bridge network 内ではサービス名で名前解決できます。

隠しファイルは外部へ返しません。

```nginx
location ~ /\. {
    deny all;
}
```

## 5. Compose上の接続

`srcs/docker-compose.yml` では NGINX だけが `ports:` を持ちます。

```yaml
ports:
  - "443:443"
```

WordPress ファイルを読む必要があるため、`wordpress_data:/var/www/html` を NGINX にもマウントします。

## 6. レビューでの説明

NGINX は TLS 終端とリクエスト転送だけを担当します。PHP 実行は WordPress コンテナの PHP-FPM、DB は MariaDB コンテナです。この分離により、外部入口を NGINX だけに限定できます。
