# ベースイメージの指定
FROM debian:bookworm

# 必要なパッケージのインストール
# php-fpm, php-cli (WP-CLI実行用), php-mysqli (DB接続用), curl (WP-CLIダウンロード用), mariadb-client (DB起動待ち用)
RUN apt-get update && apt-get install -y --no-install-recommends \
    php-fpm \
    php-cli \
    php-mysqli \
    curl \
    ca-certificates \
    openssl \
    mariadb-client \
    && rm -rf /var/lib/apt/lists/*

# WP-CLI のインストール
RUN curl -fsSL -o wp-cli.phar https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar \
    && chmod +x wp-cli.phar \
    && mv wp-cli.phar /usr/local/bin/wp

# WordPress 本体をイメージ内に用意し、初回起動時に永続ボリュームへコピーする
RUN mkdir -p /usr/src/wordpress \
    && wp core download --path=/usr/src/wordpress --allow-root \
    && chown -R www-data:www-data /usr/src/wordpress

# PHP-FPM 設定ファイルのコピー
COPY conf/www.conf /tmp/www.conf
RUN set -eux; \
    pool_dir="$(find /etc/php -path '*/fpm/pool.d' -type d | head -n 1)"; \
    test -n "${pool_dir}"; \
    cp /tmp/www.conf "${pool_dir}/www.conf"; \
    rm /tmp/www.conf

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
