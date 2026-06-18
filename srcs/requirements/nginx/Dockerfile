# ベースイメージの指定
FROM debian:trixie

# NGINX と OpenSSL のインストール
RUN apt-get update && apt-get install -y \
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
    -out /etc/nginx/ssl/inception.crt \
    -keyout /etc/nginx/ssl/inception.key \
    -subj "/C=JP/ST=Tokyo/L=Tokyo/O=42Tokyo/OU=Student/CN=${DOMAIN_NAME}"
# 設定ファイルのコピー
COPY conf/nginx.conf /etc/nginx/nginx.conf

# NGINX が使用するポート（HTTPS）
EXPOSE 443

# NGINX をフォアグラウンドで起動（PID 1 を維持するため）
# daemon off; を指定しないとコンテナがすぐに終了してしまいます
CMD ["nginx", "-g", "daemon off;"]
