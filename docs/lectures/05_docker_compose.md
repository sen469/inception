# 第5章: Docker Composeによるマルチコンテナ・オーケストレーション

前章までで、単一のコンテナを制御する方法と、その元となるイメージの設計図（Dockerfile）の書き方を学びました。しかし、実際のシステム構築（Inception課題を含む）では、Webサーバー、アプリケーション、データベースなど複数のコンテナが複雑に連携して動作します。これらを `docker run` コマンドだけで管理するのは非現実的です。そこで登場するのが **Docker Compose** です。

## 5.1 宣言的インフラストラクチャへのパラダイムシフト

`docker run` は「これを実行しろ」と命令する **命令的（Imperative）** なアプローチです。
対して `docker-compose.yml` は「システムはこうあるべきだ」という最終的な状態を定義する **宣言的（Declarative）** なアプローチを採用しています。

Composeツールは、現在のシステム状態とYAMLファイルに書かれた「あるべき状態」の差分を計算し、必要なコンテナだけを作成・再起動してくれます。これにより、複雑なシステム全体を `docker-compose up -d` というたった一つのコマンドで、誰の環境でも確実に再現できるようになりました。

## 5.2 `docker-compose.yml` の構造解剖

Composeファイルは主に3つのトップレベル要素（`services`, `networks`, `volumes`）から構成されます。

### 1. Services (コンテナの定義)
各コンテナの設定を記述します。
```yaml
services:
  nginx:
    build:
      context: ./requirements/nginx
      dockerfile: Dockerfile
    image: inception_nginx
    ports:
      - "443:443"
    depends_on:
      - wordpress
    networks:
      - inception_network
```
*   **build**: Inceptionの課題では既存イメージ（`image: nginx`）の直接使用が禁止されています。代わりに `build` ディレクティブを使って、指定したディレクトリ（`context`）にある `Dockerfile` を基にローカルでイメージを構築させます。
*   **depends_on**: コンテナの起動順序を制御します。上記の場合、`wordpress` が起動した*後*に `nginx` が起動します（ただし、アプリケーションの準備完了までは待機しない点に注意が必要です）。

### 2. Networks (内部ネットワークとサービスディスカバリ)
Docker Composeにおける最も強力な機能の一つが、コンテナ間の名前解決（DNS）です。
```yaml
networks:
  inception_network:
    driver: bridge
```
同じカスタムネットワーク（`inception_network`）に所属するコンテナ同士は、**サービス名（例: `mariadb`, `wordpress`）をそのままホスト名として通信できます。**
Dockerエンジンに内蔵されたDNSサーバーが、サービス名を自動的にコンテナの内部IPアドレス（例: `172.18.0.3`）に変換（サービスディスカバリ）してくれます。したがって、動的に変わるIPアドレスをハードコードする必要は一切ありません。

*※Inceptionの課題では `network: host`（ホストのネットワークを共有する設定）や、古い非推奨機能である `--link` の使用は明示的に禁止されています。必ずカスタムネットワークを定義してください。*

### 3. Volumes (永続化データ領域)
コンテナは「使い捨て」を前提として設計されているため、コンテナを削除すると内部のデータも消滅します。これを防ぐためにボリュームを定義します（詳細なメカニズムは次章で解説します）。

```yaml
volumes:
  wordpress_data:
    driver: local
```

## 5.3 環境変数と構成の分離

インフラのコード化において、「コード（構成）」と「環境変数（パスワードやドメイン名）」は分離すべきです。Composeでは、同一ディレクトリにある `.env` ファイルを自動的に読み込みます。

```yaml
services:
  mariadb:
    # ...
    environment:
      MYSQL_DATABASE: ${MYSQL_DATABASE_NAME}
      MYSQL_USER: ${MYSQL_USER}
```
このように記述することで、認証情報がGitHubなどのリポジトリに漏洩するリスクを防ぎ、本番環境と開発環境で異なる設定を簡単に注入することができます。

## 5.4 まとめ
Docker Composeを活用することで、システム全体を単一のコードベースとして統合的に管理できるようになります。次章では、複数コンテナの運用において最も慎重な設計が求められる「ネットワーク」と「データの永続化（Volumes）」について深く掘り下げます。
