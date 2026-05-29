# サービス解説 01: NGINX と HTTPS (TLS) 通信

Inceptionプロジェクトにおける NGINX（エンジンエックス）は、システム全体への「唯一の入り口（エントリポイント）」として機能します。本章では、NGINXの役割と設定方法について解説します。

## 1. そもそも Webサーバー とは何か？

Webブラウザ（ChromeやSafari）でURLを入力した時、インターネットの向こう側でそのリクエスト（「このページを見せて」というお願い）を受け取り、適切なファイル（HTML、画像、CSSなど）をブラウザに送り返してくれるソフトウェアのことです。
代表的なものに **Apache (アパッチ)** や、今回使用する **NGINX (エンジンエックス)** があります。

*   **役割:** レストランにおける「ウェイター」のような存在です。お客さん（ブラウザ）から注文（HTTPリクエスト）を受け取って厨房（アプリケーション層）に伝え、出来上がった料理（HTML等のデータ）をお客さんのテーブル（画面）に運びます。

## 2. そもそも SSL/TLS (HTTPS) とは何か？

インターネット上の通信は、バケツリレーのように複数のコンピューターを経由して相手に届きます。SSL（Secure Sockets Layer）は、この通信を **「暗号化」** して安全にやり取りするための仕組みです。現在はバージョンアップして **TLS (Transport Layer Security)** という名前に変わっていますが、今でも習慣的に「SSL」と呼ばれます。

*   **HTTP (暗号化なし):** 「ハガキ」でやり取りしているような状態です。パスワードなどを送信すると、途中で盗み見られた際に中身が丸見えになってしまいます。
*   **HTTPS (暗号化あり / ポート443):** 「頑丈な金庫」に入れてやり取りする状態です。送信時に解読不能な暗号に変換され、通信相手のサーバー（NGINX）だけが持つ「特別なカギ（秘密鍵）」を使ってのみ元のデータに戻す（復号化する）ことができます。

今回の課題では、「古い弱い暗号化（SSLv3 や TLSv1.0など）は使わず、最新の頑丈な暗号化プロトコル（TLSv1.2 または TLSv1.3）だけを使って安全に通信させなさい」という厳格なルールが定められています。

### 証明書と「署名（デジタル署名）」とは？

HTTPS通信を行うには、「暗号化のカギ」だけでなく、**「そのサーバーが本当に本物であることの証明（身分証明書）」** が必要です。

通常、インターネット上の本物のWebサイトを作る時は、シマンテックやLet's Encryptのような**信頼できる第三者機関（認証局）**に身分を証明してもらい、彼らの**「署名（電子的なハンコ）」**が入った証明書を発行してもらいます。ブラウザは「この第三者機関がハンコを押しているなら、このサイトは本物だ」と信用します。

しかし今回は、インターネット上ではなく手元のPCの中だけで動くテスト環境（`login.42.fr`）なので、第三者機関は証明書を発行してくれません。

そこで登場するのが、`openssl` コマンドを使って作成する**「自己署名証明書（通称：オレオレ証明書）」**です。
これは、自分で作った証明書に、自分で「私は本物です」という署名（ハンコ）を押したものです。第三者の保証がないため、ブラウザでアクセスした際に「この接続ではプライバシーが保護されません（安全ではありません）」という警告が出ますが、通信の暗号化自体は完璧に行われます。今回の課題ではこの自己署名証明書を使うことが想定されています。

## 3. NGINX の2つの大きな役割

NGINX は元々非常に高速な Webサーバーですが、今回のプロジェクトでは以下の2つの役割を担います。

1.  **HTTPS (TLS) 通信の終端（SSL Termination）**
    *   ユーザーからの暗号化された通信（HTTPS / ポート443）を受け取り、復号化します。
    *   上記の要件に従い、古い脆弱なプロトコルを弾く門番の役割を果たします。
2.  **リバースプロキシ (FastCGIプロキシ)**
    *   「画像のちょうだい」というリクエストなら、NGINX 自身が持っている画像を返します。
    *   「このPHPプログラムを実行して」というリクエスト（例: `index.php` へのアクセス）が来たら、NGINX は自分で処理せず、後ろにいる **WordPress コンテナの 9000 番ポート** へそのまま丸投げ（プロキシ）します。

## 4. nginx.conf の基本構造と書き方

コンテナ内にコピーして使う `nginx.conf`（または `default.conf`）の基本的な書き方のイメージです。

```nginx
# イベント処理に関する設定（基本はこのままでOK）
events {
    worker_connections 1024;
}

http {
    # MIMEタイプ（拡張子とファイル種類の紐付け）を読み込む
    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    server {
        # ポート443(HTTPS)で待ち受ける
        listen 443 ssl;
        # IPv6用の設定
        listen [::]:443 ssl;

        # サーバー名（ドメイン名）。要件により login.42.fr になります。
        server_name login.42.fr; # ← 自分のログイン名に変更

        # SSL証明書と秘密鍵の場所を指定
        ssl_certificate     /etc/nginx/ssl/inception.crt;
        ssl_certificate_key /etc/nginx/ssl/inception.key;

        # 【重要】TLS 1.2 と 1.3 のみを許可する（課題要件）
        ssl_protocols TLSv1.2 TLSv1.3;

        # Webサイトのルートディレクトリと、最初に読み込むファイル
        root /var/www/html;
        index index.php index.html index.htm;

        # 1. 通常のアクセスに対する処理
        location / {
            try_files $uri $uri/ =404;
        }

        # 2. PHPファイルへのアクセスに対する処理（FastCGI）
        location ~ \.php$ {
            # WordPressコンテナ（サービス名: wordpress）のポート9000へ転送
            fastcgi_pass wordpress:9000;
            # FastCGIの基本設定ファイルを読み込む
            include fastcgi_params;
            # 実行するPHPファイルの絶対パスを教える
            fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
        }
    }
}
```

## 5. なぜ NGINX と WordPress の両方にデータが必要なのか？ (FastCGIの裏側)

上記の設定で一番下の行 `fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;` に注目してください。

実は、**NGINX というソフトウェアは、PHP のコードを1ミリも理解できません。** NGINX にとっての `index.php` は、ただの「意味不明な文字列が書かれたテキストファイル」です。

ではどうやってPHPを動かしているのか？
NGINXが行っているのは「翻訳と丸投げ」です。ブラウザからのHTTPリクエストを **FastCGI** という別の通信ルールに翻訳し、ネットワーク越しにポート9000で待っている PHP-FPM（WordPressコンテナ）に送りつけています。

この時、一番重要なのが `SCRIPT_FILENAME` というパラメータです。
NGINXは「僕のフォルダ構造で言うと、この絶対パス（`/var/www/html/index.php`）にあるファイルを処理してくれ！」と伝言を送ります。
これを受け取った PHP-FPM は、**自分のコンテナの中にある** 同じ絶対パスのファイルを探して実行します。

もしWordPressコンテナの中にそのファイルがなかったら `File not found.` というエラー（502 Bad Gateway や 404）になります。
また、NGINX自身も静的な画像（`.png` や `.css`）を直接返すために、WordPressのファイル群にアクセスできる必要があります。

**結論：**
だからこそ、`docker-compose.yml` で「WordPressのデータが入った Named Volume」を、**NGINX と WordPress の両方のコンテナの `/var/www/html` にマウント（共有）しなければならない** のです。

## 6. 次のアクション (openssl コマンドの解剖)

NGINXの `Dockerfile` の中で `openssl` を使って自己署名証明書を作成し、上記のような `nginx.conf` をコンテナ内の適切な場所に `COPY` するよう設定します。

証明書を作成する `openssl` コマンドは非常に長く複雑に見えますが、それぞれのオプションには明確な意味があります。

```bash
# Dockerfile に書く RUN コマンドの例
RUN mkdir -p /etc/nginx/ssl && \
    openssl req -x509 -nodes -out /etc/nginx/ssl/inception.crt -keyout /etc/nginx/ssl/inception.key -subj "/C=JP/ST=Tokyo/L=Tokyo/O=42Tokyo/OU=Student/CN=login.42.fr"
```

### コマンドとオプションの意味
*   **`req`**: PKCS#10 X.509 Certificate Signing Request (CSR) 管理を行うサブコマンドです。証明書の作成や署名要求を行います。
*   **`-x509`**: 署名要求（CSR）を作るのではなく、**「自分自身で署名した本物の証明書（自己署名証明書）」** を直接出力しろ、という指示です。
*   **`-nodes`**: (No DES の略) 秘密鍵をパスワードで暗号化（保護）しない、という指示です。これを付けないと、NGINXが起動するたびにパスワードを手入力で聞かれてしまい、コンテナの自動起動ができなくなってしまいます。
*   **`-out [パス]`**: 作成した **証明書 (Certificate: .crt)** を保存する場所を指定します。（NGINX設定の `ssl_certificate` に対応）
*   **`-keyout [パス]`**: 作成した **秘密鍵 (Private Key: .key)** を保存する場所を指定します。（NGINX設定の `ssl_certificate_key` に対応）
*   **`-subj "..."`**: (Subject の略) 証明書に記載される「身分証明書の中身」を一行で一気に入力するためのオプションです。これを付けないと対話型のプロンプト（国はどこですか？等は聞かれる状態）になり、Dockerのビルドが途中で止まってしまいます。
    *   `/C=JP`: Country (国)
    *   `/ST=Tokyo`: State (都道府県)
    *   `/L=Tokyo`: Locality (市区町村)
    *   `/O=42Tokyo`: Organization (組織名)
    *   `/OU=Student`: Organizational Unit (部門名)
    *   **`/CN=login.42.fr`**: Common Name (コモンネーム)。**これが最も重要です！** アクセスする際のドメイン名（ログイン名）と完全に一致している必要があります。

これらの意味を理解して `Dockerfile` に組み込めば、NGINXコンテナのベースは完成です！
