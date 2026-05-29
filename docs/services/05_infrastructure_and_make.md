# サービス解説 05: インフラの自動化 (Makefile と Hosts設定)

Inception課題の最後の仕上げは、作成したすべてのコンテナ群（NGINX, WordPress, MariaDB）を一つのシステムとして統合し、誰でもボタン一つで起動できるようにすることです。本章ではホストマシンの設定と Makefile の書き方について解説します。

## 1. ローカルドメインの解決 (`/etc/hosts`)

課題の要件に以下の記載があります。
> To make things simpler, you have to configure your domain name so it points to your local IP address.
> This domain name must be `login.42.fr`.

通常、ブラウザに `login.42.fr` のようなドメイン名を入力すると、インターネット上のDNSサーバーに「このドメインのIPアドレスは何番ですか？」と問い合わせに行きます。しかし今回は自分のPC（VM）の中で動かしているため、インターネットに問い合わせても見つかりません。

そこで、自分のPC内にある **`/etc/hosts`** というファイルを編集します。このファイルは、インターネット上のDNSよりも優先して名前解決（ドメイン名からIPアドレスへの変換）を行う「ローカルの電話帳」です。

### 設定方法
ホストマシン（VM）のターミナルで `sudo nano /etc/hosts`（または vim）を開き、以下の一行を追加します。

```text
127.0.0.1   login.42.fr
```
*(※ `login` の部分はご自身のログイン名)*

これにより、VM内のブラウザ（または `curl` コマンド）で `https://login.42.fr` にアクセスした際、「あ、それは `127.0.0.1`（つまり自分自身のPC）のことだな」と解釈され、PCのポート443で待ち受けている Docker の NGINX コンテナに通信が届くようになります。

### 🌐 VM外のPC（MacやWindows）のブラウザからアクセスするには？
Inceptionの評価（Defense）では、「あなたのMac（またはWindows）のブラウザから、VMの中で動いているWordPressの画面を見せる」必要があります。
これを実現するためには、以下の**2つのステップ**が追加で必要になります。

#### 1. Mac/Windows 側の `/etc/hosts` も変更する
VMの中だけでなく、あなたが今触っているMac（またはWindows）にも「`login.42.fr` はどこにあるか」を教えなければなりません。
Macのターミナル（VMのターミナルではありません）を開き、`sudo nano /etc/hosts` で以下を追記します。

```text
127.0.0.1   login.42.fr
```
（※Mac上でアクセスされた通信を、一旦Mac自身（127.0.0.1）に向けます）

#### 2. VirtualBox の「ポートフォワーディング」を設定する
Macに向けられた通信を、VirtualBoxの中で動いているVMに「転送（横流し）」する設定です。

1.  VirtualBoxのマネージャー画面を開き、対象のVMを選んで「設定 (Settings)」をクリックします。
2.  「ネットワーク (Network)」タブ ＞ 「アダプター1 (NATになっているはずです)」 ＞ 「高度 (Advanced)」を開きます。
3.  **「ポートフォワーディング (Port Forwarding)」** ボタンをクリックします。
4.  右上の「＋」ボタンを押して、以下のルールを追加します。
    *   名前: 任意（`HTTPS` など）
    *   プロトコル: `TCP`
    *   ホストポート: `443` (Macの443番ポートへのアクセスを...)
    *   ゲストポート: `443` (...VMの443番ポートへ転送する)

この設定により、**「Macのブラウザで `https://login.42.fr` (Macのポート443) にアクセス → VirtualBoxがVMのポート443へ転送 → VMの中で動いているNGINXコンテナが受け取る」** という完璧な経路が開通します！

## 2. データ保存先ディレクトリの作成

課題要件では、データはホストの `/home/login/data/` 配下に保存することが求められています。
コンテナを起動する前に、ホストマシン側でこのディレクトリが存在していないと Docker Compose はマウントエラーを起こします。

```bash
mkdir -p /home/login/data/wordpress
mkdir -p /home/login/data/mariadb
```

## 3. Makefile による完全自動化

課題要件のもう一つの大きな柱が **Makefile** です。
長い `docker-compose` コマンドや、上記のディレクトリ作成処理などをすべて隠蔽し、短いコマンドでインフラを管理できるようにします。

リポジトリのルート（`srcs` と同じ階層）に作成する `Makefile` の構成例です。

```makefile
# 変数定義（docker-compose.yml のパス）
COMPOSE_FILE = ./srcs/docker-compose.yml

# プロジェクトをビルドして起動する
all: up

# コンテナの起動（ディレクトリが無ければ作成する処理も入れると親切です）
up:
	mkdir -p /home/login/data/wordpress
	mkdir -p /home/login/data/mariadb
	docker-compose -f $(COMPOSE_FILE) up -d --build

# コンテナの停止
down:
	docker-compose -f $(COMPOSE_FILE) down

# コンテナ、ネットワーク、イメージ、ボリュームの完全削除（初期化）
clean:
	docker-compose -f $(COMPOSE_FILE) down -v
	docker system prune -a --force

# ターゲットがファイル名ではないことを宣言
.PHONY: all up down clean
```

### `make` コマンドの使い方
*   **`make` (または `make up`)**: 環境全体のディレクトリが作成され、イメージがビルドされ、3つのコンテナがバックグラウンドで起動します。
*   **`make down`**: コンテナが安全に停止し、ネットワークが解除されます（データは残ります）。
*   **`make clean`**: すべてを跡形もなく消し去り、最初の状態に戻します。

## 4. 総まとめ（あなたのタスクの流れ）

これで Inception 課題に必要な全ての知識のピースが揃いました。実際の作業は以下の順番で進めるのがおすすめです。

1.  **ホストの準備:** VMの `/etc/hosts` を編集し、データ用のディレクトリ（`/home/login/data`）を作っておく。
2.  **証明書:** NGINX用の自己署名SSL証明書を作成する処理を Dockerfile に書く。
3.  **NGINX:** `nginx.conf` を書き、NGINXコンテナ単体で起動するかテストする。
4.  **MariaDB:** 設定ファイルと初期化SQLスクリプト（`.sh`）を書き、DBコンテナ単体で起動するかテストする。
5.  **WordPress:** `www.conf` と WP-CLIを使った初期化スクリプト（`.sh`）を書き、PHP-FPMコンテナを準備する。
6.  **連携:** `docker-compose.yml` を書き、3つのコンテナをネットワークとボリュームで繋ぐ。
7.  **自動化:** `Makefile` を書いて、すべてを1コマンドで操作できるようにする。

焦らず、まずは1つ1つのコンテナを単独で動かし、最後に Compose で繋ぐ「ボトムアップ」のアプローチで進めると、トラブルシューティングが格段に楽になります！
