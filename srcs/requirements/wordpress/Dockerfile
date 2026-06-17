# ベースイメージの指定
FROM debian:trixie

# 必要なパッケージのインストール
# php-fpm, php-mysqli (DB接続用), curl (WP-CLIダウンロード用), mariadb-client (DB起動待ち用)
RUN apt-get update && apt-get install -y \
    php-fpm \
    php-mysqli \
    curl \
    mariadb-client \
    && rm -rf /var/lib/apt/lists/*

# WP-CLI のインストール
RUN curl -O https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar \
    && chmod +x wp-cli.phar \
    && mv wp-cli.phar /usr/local/bin/wp

# PHP-FPM 設定ファイルのコピー
COPY conf/www.conf /etc/php/8.4/fpm/pool.d/www.conf

# WordPress ソースコードの保存先ディレクトリ
RUN mkdir -p /var/www/html && chown -R www-data:www-data /var/www/html

# セットアップスクリプトのコピー
COPY tools/setup.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/setup.sh

# 作業ディレクトリ
WORKDIR /var/www/html

# ポート9000
EXPOSE 9000

# エントリポイント
ENTRYPOINT ["/usr/local/bin/setup.sh"]
