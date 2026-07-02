# ベースイメージの指定
FROM debian:bookworm

# NGINX、OpenSSL、起動待ちに必要なツールのインストール
RUN apt-get update && apt-get install -y --no-install-recommends \
    bash \
    netcat-openbsd \
    nginx \
    openssl \
    && rm -rf /var/lib/apt/lists/*

# SSL証明書の保存ディレクトリ作成
RUN mkdir -p /etc/nginx/ssl

ARG DOMAIN_NAME=ssawa.42.fr
# 自己署名証明書の生成
# -nodes: 秘密鍵を暗号化しない（起動時にパスワード入力を求められないようにするため）
# -subj: 対話形式を避け、一行で証明書情報を入力
RUN openssl req -x509 -nodes \
    -days 365 \
    -newkey rsa:4096 \
    -out /etc/nginx/ssl/inception.crt \
    -keyout /etc/nginx/ssl/inception.key \
    -subj "/C=JP/ST=Tokyo/L=Tokyo/O=42Tokyo/OU=Student/CN=${DOMAIN_NAME}"
# 設定ファイルのコピー
COPY conf/nginx.conf /etc/nginx/nginx.conf
RUN sed -i "s/__DOMAIN_NAME__/${DOMAIN_NAME}/g" /etc/nginx/nginx.conf

# WordPress/PHP-FPM の準備完了を待ってから NGINX を起動する
COPY tools/entrypoint.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/entrypoint.sh

# NGINX が使用するポート（HTTPS）
EXPOSE 443

# NGINX をメインプロセスとしてフォアグラウンドで起動する
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
