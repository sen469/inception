# ベースイメージの指定 (Debian trixie 等)
FROM debian:trixie

# パッケージの更新と MariaDB のインストール
RUN apt-get update && apt-get install -y \
    mariadb-server \
    mariadb-client \
    && rm -rf /var/lib/apt/lists/*

# 設定ファイルのコピー
COPY conf/50-server.cnf /etc/mysql/mariadb.conf.d/50-server.cnf

# 初期化スクリプトのコピー
COPY tools/init.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/init.sh

# MariaDBが使用するポート
EXPOSE 3306

# エントリポイントの指定
ENTRYPOINT ["/usr/local/bin/init.sh"]
