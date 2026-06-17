# NGINX 構築・完全手順書

この手順書に従えば、NGINXコンテナをプロジェクト要件（Mandatory）を満たした状態で完成させることができます。

---

## 1. 構成図とディレクトリ準備

まず、以下の構造になっているか確認してください。

```text
srcs/requirements/nginx/
├── Dockerfile
├── conf/
│   └── nginx.conf
└── tools/
    └── (必要に応じてスクリプトを配置)
```

---

## 2. NGINX 設定ファイルの作成 (`conf/nginx.conf`)

この設定ファイルが、HTTPS通信の受け口と WordPress への橋渡し（プロキシ）を行います。

```nginx
events {
    # 同時接続数の設定（デフォルトでOK）
    worker_connections 1024;
}

http {
    # MIMEタイプの読み込み
    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    server {
        # ポート443(SSL)で待ち受ける
        listen 443 ssl;
        listen [::]:443 ssl;

        # サーバー名（自分のログイン名.42.fr）
        server_name ${DOMAIN_NAME};

        # SSL証明書と秘密鍵のパス
        ssl_certificate     /etc/nginx/ssl/inception.crt;
        ssl_certificate_key /etc/nginx/ssl/inception.key;

        # TLSプロトコルの制限（課題要件: TLSv1.2 または TLSv1.3 のみ）
        ssl_protocols TLSv1.2 TLSv1.3;

        # ドキュメントルートの設定（WordPressと共有するボリューム）
        root /var/www/html;
        index index.php index.html index.htm;

        # 通常のファイルリクエストへの対応
        location / {
            try_files $uri $uri/ =404;
        }

        # PHPファイルリクエストへの対応（FastCGIプロキシ）
        location ~ \.php$ {
            # WordPressコンテナのポート9000へ転送
            fastcgi_pass wordpress:9000;
            include fastcgi_params;
            # 実行するPHPファイルのフルパスを指定
            fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
        }
    }
}
```
*(注: `server_name` に `${DOMAIN_NAME}` と書いていますが、NGINXの標準設定ファイルでは環境変数は使えません。Dockerfile内で `envsubst` を使って置換するか、自分のログイン名を直接書き込んでください。)*

---

## 3. Dockerfile の作成

Dockerfile内で `openssl` を使い、自己署名証明書を自動生成します。

```dockerfile
# ベースイメージの指定
FROM debian:trixie

# NGINX と OpenSSL のインストール
RUN apt-get update && apt-get install -y \
    nginx \
    openssl \
    && rm -rf /var/lib/apt/lists/*

# SSL証明書の保存ディレクトリ作成
RUN mkdir -p /etc/nginx/ssl

# 自己署名証明書の生成
# -nodes: 秘密鍵を暗号化しない（起動時にパスワード入力を求められないようにするため）
# -subj: 対話形式を避け、一行で証明書情報を入力
RUN openssl req -x509 -nodes \
    -out /etc/nginx/ssl/inception.crt \
    -keyout /etc/nginx/ssl/inception.key \
    -subj "/C=JP/ST=Tokyo/L=Tokyo/O=42Tokyo/OU=Student/CN=ssawa.42.fr"

# 設定ファイルのコピー
COPY conf/nginx.conf /etc/nginx/nginx.conf

# NGINX が使用するポート（HTTPS）
EXPOSE 443

# NGINX をフォアグラウンドで起動（PID 1 を維持するため）
# daemon off; を指定しないとコンテナがすぐに終了してしまいます
CMD ["nginx", "-g", "daemon off;"]
```

---

## 4. Docker Compose での設定 (`srcs/docker-compose.yml`)

NGINXは、WordPressとファイルを共有するためにボリュームをマウントする必要があります。

```yaml
services:
  nginx:
    build:
      context: ./requirements/nginx
    image: nginx
    container_name: nginx
    restart: always
    # WordPressが起動してからNGINXを立ち上げる
    depends_on:
      - wordpress
    # 外部（ホスト）にポート443を公開する唯一のサービス
    ports:
      - "443:443"
    volumes:
      - wordpress_data:/var/www/html
    networks:
      - inception_network

# (networks と volumes の定義は mariadb/wordpress の手順書と同じ)
```

---

## 5. 動作確認・テスト

1.  `make` で全コンテナを起動。
2.  **VM内またはMacのブラウザからアクセス**:
    - `https://<login>.42.fr` にアクセス。
    - 自己署名証明書のため「安全ではありません」と出ますが、「詳細」→「アクセスする」で進んでください。
3.  **TLSバージョンの確認**:
    - ターミナルから `curl` を使って確認できます。
    ```bash
    curl -I -v --tlsv1.2 https://<login>.42.fr --insecure
    ```
    - `TLSv1.2` または `TLSv1.3` で接続されていることを確認してください。
4.  **証明書の中身を確認**:
    ```bash
    docker exec -it nginx openssl x509 -in /etc/nginx/ssl/inception.crt -text -noout
    ```

---

## 6. よくあるエラー（502 Bad Gateway）の解決策

ブラウザに `502 Bad Gateway` と表示された場合、NGINX は動いていますが、その後ろの WordPress と通信できていません。

- **原因1**: WordPress コンテナの PHP-FPM が起動していない。
- **原因2**: WordPress コンテナの `www.conf` で `listen = 9000` になっていない（UNIXソケットのまま）。
- **原因3**: `docker-compose.yml` でコンテナ名が `wordpress` 以外になっている（NGINXはサービス名で名前解決します）。
- **原因4**: 両方のコンテナにボリュームが正しくマウントされておらず、NGINX側でPHPファイルが見つからない。

---

### 注意事項
- **セキュリティ**: ポート 80 (HTTP) は開けないでください。要件により 443 (HTTPS) のみがエントリポイントです。
- **設定ファイルの場所**: Debianのデフォルトでは `/etc/nginx/sites-available/default` を読み込むようになっています。`nginx.conf` で直接 `server` ブロックを書く場合は、既存のデフォルト設定と衝突しないように注意してください。
