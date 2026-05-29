# debian のTrixieをいれる
FROM debian:trixie

# nginxとopensslをインストール
RUN apt-get update && apt-get install -y nginx openssl

# nginx/のconfigファイルをコンテナの中にコピーする
COPY conf/nginx.conf /etc/nginx/nginx.conf

# NGINXが動くポートを開ける
EXPOSE 443

# コンテナ起動時にNGINXをフォアグラウンドで動かす
CMD ["nginx", "-g", "daemon off;"]
