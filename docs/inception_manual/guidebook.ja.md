# Inception 最強ガイドブック：提出までこれ一冊

このガイドブックは、42の課題「Inception」を単なる作業（コピペ）ではなく、**「システム設計の理解」**を伴って完遂し、ピア評価で自信を持って説明できるように構成されています。

---

## 0. プロジェクトの全体像（三層アーキテクチャ）

Inceptionは、現代のWebインフラの標準である**三層アーキテクチャ**をDockerで再現する課題です。

1.  **プレゼンテーション層 (NGINX)**: TLS 1.2/1.3で通信を保護し、リクエストを後段へ受け渡す。
2.  **アプリケーション層 (WordPress + PHP-FPM)**: WP-CLIで自動インストールされ、ロジックを実行する。
3.  **データ層 (MariaDB)**: データベース専用。外部ネットワークからは隔離されている。

---

## 1. 基礎知識と必須ルール

設計を始める前に、不合格（Fail）に直結するルールを再確認してください。

- **OS**: Debian (penultimate stable: trixie or bookworm) または Alpine。
- **NGINX**: ポート443以外からアクセスさせてはいけない。
- **Docker Network**: `network: host` は禁止。コンテナ間は名前解決 (`mariadb`, `wordpress` など) で通信する。
- **Volumes**: バインドマウント禁止。ホストの `/home/login/data` に保存される「ネームドボリューム」を使用する。
- **PID 1**: コンテナ内のメインプロセスが PID 1 であること（詳細は 4章参照）。
- **ハック禁止**: `tail -f`, `sleep infinity` など、無限ループでコンテナを維持させてはいけない。

---

## 2. インフラ設定の重要ポイント

### 2.1 ドメイン解決 (`/etc/hosts`)
VM内とMac/Windows側の両方で `/etc/hosts` に以下を追記します。
```text
127.0.0.1   <login>.42.fr
```

### 2.2 秘密情報の管理
`.env` ファイルにはパスワードなどの機密情報を書きますが、Gitには**絶対に**含めてはいけません。
評価要件にある通り、**Docker Secrets** を使用してパスワードをファイル (`secrets/`) から読み込ませる方法が最もセキュアで推奨されます。

---

## 3. 各サービスの技術的詳細

### 3.1 NGINX: SSLとFastCGI
- **SSL**: `openssl req -x509` で自己署名証明書を生成。
- **FastCGI**: `.php` リクエストを `wordpress:9000` へ転送します。
  ```nginx
  fastcgi_pass wordpress:9000;
  ```

### 3.2 MariaDB: 隔離と初期化
- **50-server.cnf**: `bind-address = 0.0.0.0` に設定しないと WordPress から接続できません。
- **初期化**: 起動時に `mysql` コマンドでデータベースと2人のユーザー（admin, 一般ユーザー）を作成します。

### 3.3 WordPress: WP-CLIの活用
- **PHP-FPM**: `www.conf` で `listen = 9000` に設定。
- **自動化**: ブラウザで設定画面を開くのはNG。`wp core install` をエントリポイントスクリプト内で実行して自動化します。

---

## 4. エントリポイントの「魔法」: PID 1 と `exec "$@"`

コンテナが正しく終了せず、`docker stop` で10秒待たされるのは、シェルスクリプトが PID 1 になっているからです。

**最強のエントリポイント・テンプレート:**
```bash
#!/bin/bash
# 1. 必要な初期設定（DB作成やWPインストールなど）を書く
echo "Configuring service..."

# 2. 最後にメインプロセスに PID 1 を譲る
exec "$@"
```
`exec "$@"` を使うことで、シェルスクリプトのプロセスが消滅し、Dockerfileの `CMD` に書いたプログラム（`php-fpm` や `nginx`）が PID 1 に置き換わります。

---

## 5. 自動化 (Makefile)

Makefileは、評価者が最初に触るインターフェースです。

- `make`: ディレクトリ作成 ➔ `docker-compose up --build -d`
- `make clean`: コンテナ停止とネットワーク削除
- `make fclean`: イメージ、ボリューム、データディレクトリも含めた完全削除

---

## 6. トラブルシューティング

| エラー | 原因の切り分け |
| :--- | :--- |
| **502 Bad Gateway** | NGINX ➔ WordPress 間の接続失敗。PHP-FPMが動いているか、ポート9000が開いているか確認。 |
| **Database Connection Error** | WordPress ➔ MariaDB 間の接続失敗。パスワードの不一致、またはDB起動完了前にWPがアクセスした。 |
| **File Not Found (NGINX)** | 静的ファイル用ボリュームが NGINX と WordPress の両方にマウントされているか確認。 |

---

## 7. 評価（Defense）対策チェックリスト

評価中に必ず聞かれる質問と、確認すべき点です。

- [ ] **Dockerのメリットは？**: 仮想マシン(VM)と比較した軽量性、環境の再現性について語れるか。
- [ ] **Docker Networkの見せ方**: `docker network inspect` でコンテナ同士が繋がっている様子を見せられるか。
- [ ] **ボリュームの永続性**: `make fclean` でコンテナを消しても、ホストの `/home/login/data` を見ればデータが残っていることを示せるか。
- [ ] **PID 1 の確認**: `docker exec <container> ps` を実行し、メインプロセスが PID 1 であることを証明できるか。
- [ ] **SSLの確認**: ブラウザの鍵マークをクリックし、TLS 1.2/1.3 であることを示せるか。

---

**このガイドを読み終えたら、次は各コンテナの `Dockerfile` と `setup.sh` を実際に書き始めましょう！**
