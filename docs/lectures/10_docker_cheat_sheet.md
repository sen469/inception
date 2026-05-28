# 第10章: 付録 - プロフェッショナルのためのDockerコマンド・リファレンス（完全版）

Dockerには膨大な数のコマンドとオプションが存在しますが、公式マニュアルの全てを暗記する必要はありません。本章では、開発現場やInception課題において**実際に使う可能性が高い、実用的なコマンドとオプションの組み合わせ**を網羅的に網羅しました。

---

## 10.1 コンテナの実行とライフサイクル制御 (`docker run`, `start`, `stop`, `rm`)

コンテナを作成・起動・停止するための最も重要なコマンド群です。

### `docker run` (イメージからコンテナを作成して起動)
`docker run [オプション] [イメージ名] [コマンド]`
| オプション | 意味・用途 | 例 |
| :--- | :--- | :--- |
| `-d`, `--detach` | バックグラウンドで実行（Webサーバー等に必須） | `docker run -d nginx` |
| `-p`, `--publish` | ポートの転送 `[ホストのポート]:[コンテナのポート]` | `docker run -p 8080:80 nginx` |
| `--name` | コンテナに任意の名前を付ける | `docker run --name my-web nginx` |
| `-v`, `--volume` | ボリュームやホストのディレクトリをマウント `[ホストパス]:[コンテナパス]` | `docker run -v $(pwd):/app nginx` |
| `-e`, `--env` | 環境変数を注入する | `docker run -e MYSQL_ROOT_PASSWORD=pass mariadb` |
| `--env-file` | `.env` ファイルから環境変数を一括で読み込む | `docker run --env-file ./.env nginx` |
| `-it` | 対話モード（シェルなどを起動する際に必須） | `docker run -it ubuntu bash` |
| `--rm` | コンテナ停止時に、そのコンテナを自動的に削除する（使い捨て用） | `docker run --rm alpine ls -l` |
| `--network` | 接続するネットワークを指定する | `docker run --network my-net nginx` |
| `--restart` | 再起動ポリシー（`always`, `on-failure` 等） | `docker run --restart always nginx` |

### ライフサイクル管理
| コマンド | オプション・解説 |
| :--- | :--- |
| `docker stop [コンテナ]` | 安全に停止(`SIGTERM`送信)。10秒待ってダメなら強制終了。 |
| `docker stop -t 30 [コンテナ]` | 強制終了するまでの待機時間を30秒に延ばす。 |
| `docker kill [コンテナ]` | 即座に強制終了(`SIGKILL`送信)。 |
| `docker start [コンテナ]` | 停止中のコンテナを再起動する。 |
| `docker restart [コンテナ]` | コンテナを再起動する（stop -> start の連続）。 |
| `docker rm [コンテナ]` | 停止中のコンテナを削除する。 |
| `docker rm -f [コンテナ]` | **稼働中**のコンテナでも強制的に削除する。 |
| `docker rm -v [コンテナ]` | コンテナと一緒に、紐づいている無名ボリュームも削除する。 |

---

## 10.2 イメージのビルドと管理 (`docker build`, `images`, `rmi`)

### `docker build` (Dockerfileからイメージを作成)
`docker build [オプション] [Dockerfileのあるディレクトリパス]`
| オプション | 意味・用途 | 例 |
| :--- | :--- | :--- |
| `-t`, `--tag` | イメージに名前とタグを付ける `[名前]:[タグ]` | `docker build -t my-app:1.0 .` |
| `-f`, `--file` | デフォルト(`Dockerfile`)以外の名前のファイルを指定 | `docker build -f Dockerfile.dev .` |
| `--no-cache` | キャッシュを一切使わず、完全にゼロからビルドする | `docker build --no-cache -t my-app .` |
| `--target` | マルチステージビルドで、特定のステージまででビルドを止める | `docker build --target builder .` |

### イメージ管理
| コマンド | オプション・解説 |
| :--- | :--- |
| `docker images` | ローカルのイメージ一覧を表示。 |
| `docker images -a` | 中間レイヤーのイメージも含めて全て表示。 |
| `docker images -q` | イメージのIDだけを表示（スクリプト処理に便利）。 |
| `docker rmi [イメージ]` | イメージを削除。 |
| `docker rmi -f [イメージ]` | 使用中のイメージでも強制的に削除する。 |
| `docker pull [イメージ]` | Docker Hub等からイメージをダウンロードする。 |
| `docker push [イメージ]` | Docker Hub等へイメージをアップロードする。 |

---

## 10.3 状況確認とデバッグ (`ps`, `logs`, `exec`, `inspect`)

中身が見えないコンテナのトラブルシューティングを行うための生命線です。

| コマンド | オプション・解説 |
| :--- | :--- |
| `docker ps` | 稼働中のコンテナ一覧を表示。 |
| `docker ps -a` | 停止中も含めた全てのコンテナを表示。 |
| `docker ps -q` | コンテナIDのみを表示。 |
| `docker logs [コンテナ]` | コンテナの標準出力を表示。 |
| `docker logs -f [コンテナ]` | ログをリアルタイムで追い続ける（`tail -f` と同じ）。 |
| `docker logs --tail 100 [コンテナ]`| 最新の100行だけを表示する。 |
| `docker exec -it [コンテナ] [コマンド]`| 稼働中のコンテナ内でコマンドを実行する（例: `bash` や `sh`）。 |
| `docker exec -u root -it [コンテナ] bash`| コンテナ内に `root` ユーザーとして潜入する。 |
| `docker inspect [コンテナ/イメージ]`| 設定、ネットワーク、ボリューム等、全メタデータをJSONで出力。 |
| `docker top [コンテナ]` | コンテナ内で動いているプロセスの一覧を表示。 |

---

## 10.4 ボリュームとネットワーク管理 (`volume`, `network`)

| コマンド | オプション・解説 |
| :--- | :--- |
| `docker volume ls` | ボリューム一覧を表示。 |
| `docker volume create [名前]` | 新しいボリュームを手動で作成。 |
| `docker volume inspect [名前]` | ボリュームの物理的な保存先(Mountpoint)等を確認。 |
| `docker volume rm [名前]` | ボリュームを削除（使用中のものは削除不可）。 |
| `docker network ls` | ネットワーク一覧を表示。 |
| `docker network create [名前]` | 新しいカスタムブリッジネットワークを作成。 |
| `docker network inspect [名前]` | ネットワークに参加しているコンテナとIPアドレスを確認。 |
| `docker network connect [ネットワーク] [コンテナ]`| 稼働中のコンテナを別のネットワークに参加させる。 |

---

## 10.5 Docker Compose (`docker-compose`)

複数のコンテナを一括管理します。ディレクトリに `docker-compose.yml` がある前提です。

| コマンド | オプション・解説 |
| :--- | :--- |
| `docker-compose up -d` | 全てをビルド・作成し、バックグラウンドで起動。 |
| `docker-compose up --build -d` | キャッシュがあっても**必ずイメージを再ビルド**してから起動。 |
| `docker-compose down` | コンテナ、デフォルトネットワークを停止・削除。 |
| `docker-compose down -v` | 上記に加え、**定義されたボリュームも完全に削除**（完全リセット）。 |
| `docker-compose stop` | コンテナを停止するだけ（削除はしない）。 |
| `docker-compose start` | 停止中のコンテナを起動する。 |
| `docker-compose restart` | 全コンテナを再起動する。 |
| `docker-compose ps` | Composeで管理されているコンテナの状態を表示。 |
| `docker-compose logs -f` | 全コンテナのログをリアルタイムで混ざって表示。 |
| `docker-compose logs -f [サービス名]`| 特定のサービス（例: `nginx`）のログだけを表示。 |
| `docker-compose exec [サービス名] sh`| 特定のサービス（コンテナ）の中に入る。 |
| `docker-compose -f [ファイル名] up` | `docker-compose.yml` 以外の設定ファイルを使用する。 |

---

## 10.6 一括クリーンアップ (`prune`)

ディスク容量が足りなくなった時や、環境を真っ新にしたい時に使います。

| コマンド | オプション・解説 |
| :--- | :--- |
| `docker system prune` | 停止中のコンテナ、未使用のネットワーク、ダングリングイメージ（名前のないゴミイメージ）を削除。 |
| `docker system prune -a` | 上記に加え、**使用されていない全てのイメージ**を削除。 |
| `docker system prune -a --volumes` | 上記に加え、**使用されていない全てのボリューム**も削除。（最強のリセットコマンド） |
| `docker image prune -a` | 使用されていないイメージだけを全て削除。 |
| `docker volume prune` | どのコンテナにもマウントされていないボリュームを全て削除。 |

---
**💡 究極の奥義**
「すべてのコンテナを一括で強制終了して削除する」スクリプト的な使い方です（自己責任で！）：
```bash
docker rm -f $(docker ps -aq)
```
