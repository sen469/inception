# 番外編: Dockerを使わずに直接構築してみよう (Native Setup)

「Dockerを使うと何が嬉しいのか？」を本当に理解するための最良の方法は、**「一度Dockerを使わずに、すべて手作業で構築してみる（The Hard Way）」** ことです。

このチュートリアルでは、VirtualBox上の Debian (VM) に直接 NGINX、MariaDB、PHP-FPM、WordPress をインストールし、Inception課題と同じ構成を手動で作り上げます。この「面倒くさい手作業」を自動化・隔離するのがDocker（およびDockerfile）の役割だということが、肌で理解できるはずです。

---

## ステップ 1: 必要なソフトウェアのインストール

まずは、3つのコンテナに分けて入れるはずだったソフトウェアを、一つのVMに全てインストールします。ターミナルで以下のコマンドを実行してください。

```bash
# パッケージリストの更新
sudo apt-get update

# NGINX (Webサーバー), MariaDB (データベース), PHP-FPM, その他必要なツールをインストール
sudo apt-get install -y nginx mariadb-server php-fpm php-mysql openssl wget curl
```

## ステップ 2: MariaDB (データベース) のセットアップ

データベースの常駐プログラム（デーモン）を操作し、WordPress用の保存場所（データベース）と、そこにアクセスできるユーザーを作成します。

### データベースサーバーの起動・停止・確認コマンド
Linux上でサービスを管理する基本的なコマンドです。まずは起動しているか確認し、起動しましょう。

```bash
# 状態確認 (active (running) かどうか)
sudo systemctl status mariadb

# 起動
sudo systemctl start mariadb

# (参考) 停止する場合は: sudo systemctl stop mariadb
# (参考) 再起動する場合は: sudo systemctl restart mariadb
```

### データベースとユーザーの作成
サーバーが起動したら、データベースと直接対話するための専用ツール「MariaDBコンソール」に入ります。

```bash
sudo mysql -u root
```

#### 💡 `-u root` の意味と、root以外で入るとどうなるか？
Linuxのシステム管理者が「rootユーザー」と呼ばれるように、**データベース（MariaDB）の中にも、すべての権限を持つ絶対的な管理者である「rootユーザー」が存在します。**
（※ Linuxのrootと、MariaDBのrootは、名前は同じですが別の存在です）

*   **なぜ `root` で入るのか？**
    これから「新しいデータベースを作る」「新しいユーザーを作る」というシステムレベルの重大な操作を行うため、最高権限が必要だからです。
*   **root以外（`sudo mysql` だけ、または `-u 存在しないユーザー` 等）で入ろうとすると？**
    権限がないため `Access denied for user...` というエラーで弾かれるか、運良く入れても「データベースを作れない」「他のユーザーの情報が見られない」といった制限だらけの状態で何も作業ができません。

#### 💡 MariaDBコンソールとは？
ターミナル上で上記のコマンドを打つと、入力待ちの左側の文字が `$` や `#` から **`MariaDB [(none)]>`** という表示に切り替わります。
ここはもう、Linuxの普通のシェル（bash）ではありません。**「SQL」というデータベース専用の言語しか通じない、データベースの内部世界**です。ここでは `ls` や `cd` などのLinuxコマンドはエラーになります。

この専用のコンソール空間の中で、以下のSQLコマンドを1行ずつ入力し、最後に必ず `;`（セミコロン）をつけて `Enter` を押して実行していきます。

#### 💡 SQLコマンドの成功・失敗はどうやって確認するの？
Linuxのbashのように `echo $?` を打つ必要はありません。MariaDBコンソールは非常に親切で、**コマンドを打った直後に必ず画面上に結果を英語で報告してくれます。**

*   **成功した場合:** `Query OK, 1 row affected (0.00 sec)` のような文字が出ます。「Query OK」と出れば成功です。
*   **失敗した場合:** `ERROR 1064 (42000): You have an error in your SQL syntax...` のように、`ERROR` という文字と共に何がダメだったのかを教えてくれます。エラーが出たら、スペルミスやセミコロンの忘れがないか確認して打ち直してください。

```sql
-- 1. WordPress用のデータベースを作成
CREATE DATABASE wordpress_db;

-- 2. WordPress専用のユーザーを作成（パスワードは 'wp_password' とします）
CREATE USER 'wp_user'@'localhost' IDENTIFIED BY 'wp_password';

-- 3. 作成したユーザーに、データベースへの全権限を付与
GRANT ALL PRIVILEGES ON wordpress_db.* TO 'wp_user'@'localhost';

-- 4. 権限を反映させる
FLUSH PRIVILEGES;

-- 5. 終了して元のターミナルに戻る
exit
```

### 🔍 状態確認: データベースが正しく作られたか確かめる
作成した `wp_user` でログインできるか、そして `wordpress_db` が見えるかを確認します。

```bash
# 新しく作ったユーザーでログインを試みる（パスワード wp_password を聞かれます）
mysql -u wp_user -p

# ログインできたら、データベース一覧を表示
SHOW DATABASES;
# ↑ リストの中に `wordpress_db` があれば成功です！
exit
```

## ステップ 3: WordPressのダウンロードと配置

次に、WordPress本体（PHPのソースコード群）をダウンロードして、Webサーバーから見える場所に配置します。

```bash
# WordPressの最新版をダウンロードして解凍
wget https://wordpress.org/latest.tar.gz
tar -xzvf latest.tar.gz

# 解凍したフォルダを Webサーバーのルートディレクトリ（/var/www/html）に移動
sudo mv wordpress /var/www/html/

# NGINXとPHPがファイルを読み書きできるように、所有権を www-data（Webサーバーユーザー）に変更
sudo chown -R www-data:www-data /var/www/html/wordpress
```

## ステップ 4: SSL証明書の作成と NGINX の設定

HTTPSで通信するための自己署名証明書（オレオレ証明書）を作成し、NGINXに「PHP-FPMに処理を丸投げする」設定を書きます。

### 1. 証明書の作成
```bash
sudo mkdir -p /etc/nginx/ssl
sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout /etc/nginx/ssl/inception.key \
  -out /etc/nginx/ssl/inception.crt \
  -subj "/C=JP/ST=Tokyo/L=Tokyo/O=42Tokyo/OU=Student/CN=login.42.fr"
```

### 2. NGINX の設定ファイル作成
NGINXの設定ファイルを新規作成します。
```bash
sudo nano /etc/nginx/sites-available/wordpress
```
以下の内容を貼り付けて保存します（`Ctrl+O`, `Enter`, `Ctrl+X`）。

```nginx
server {
    listen 443 ssl;
    listen [::]:443 ssl;
    server_name login.42.fr; # ← 自分のドメインに変更

    ssl_certificate /etc/nginx/ssl/inception.crt;
    ssl_certificate_key /etc/nginx/ssl/inception.key;
    ssl_protocols TLSv1.2 TLSv1.3;

    # 先ほど配置したWordPressのディレクトリを指定
    root /var/www/html/wordpress;
    index index.php index.html index.htm;

    location / {
        try_files $uri $uri/ =404;
    }

    location ~ \.php$ {
        # 同じOS内なので、TCPポート(9000)ではなくUNIXソケットを使って超高速通信する
        fastcgi_pass unix:/run/php/php8.4-fpm.sock;
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
    }
}
```

### 3. 設定の有効化
作成した設定ファイルを有効にし、デフォルトの設定を無効にします。
```bash
sudo ln -s /etc/nginx/sites-available/wordpress /etc/nginx/sites-enabled/
sudo rm -f /etc/nginx/sites-enabled/default
```

## ステップ 5: サービスの起動と確認

すべての準備が整いました。PHP-FPMとNGINXを再起動して設定を読み込ませます。

```bash
sudo systemctl restart php8.4-fpm
sudo systemctl restart nginx
```

### 🔍 状態確認: ポートとログを確認する
エラーなく起動したか、そして「本当にポート443で待ち受けているか」をネットワークレベルで確認します。

```bash
# NGINXの設定ファイルに文法エラーがないかテストする
sudo nginx -t
# ↑ "syntax is ok" と "test is successful" が出れば設定成功です！

# ポートの待機状況を確認する (ssコマンド)
sudo ss -tulpn | grep nginx
# ↑ ":443" の文字があり、nginx がLISTEN（待機）していることが確認できれば完璧です。
```

### 🌐 ホストPC (MacやWindows) のブラウザからアクセスするための設定
VMの中のブラウザを使うのではなく、普段使っているMacやWindowsのブラウザから `https://login.42.fr` にアクセスして構築したサイトを見るためには、以下の**2つの設定**が必要です。

#### 1. Mac/Windows 側の `/etc/hosts` の設定
あなたが今触っているMac（またはWindows）に「`login.42.fr` への通信は、インターネットではなく自分自身（127.0.0.1）に向けろ」と教えます。

*   **Macの場合:** ターミナルを開き、`sudo nano /etc/hosts` で以下を追記します。
    ```text
    127.0.0.1   login.42.fr
    ```
*   **Windowsの場合:** メモ帳を管理者権限で開き、`C:\Windows\System32\drivers\etc\hosts` に上記の一行を追記します。

#### 2. VirtualBox の「ポートフォワーディング」設定
上記の `hosts` 設定により、Macのブラウザからの通信は「Mac自身の443番ポート」に向かいます。これを、VirtualBoxの中で動いている「VMの443番ポート」へ転送（横流し）する設定を行います。

1.  VirtualBoxのマネージャー画面を開き、対象のVMを選んで「設定 (Settings)」をクリックします。
2.  「ネットワーク (Network)」タブ ＞ 「アダプター1 (NATになっているはずです)」 ＞ 「高度 (Advanced)」を開きます。
3.  **「ポートフォワーディング (Port Forwarding)」** ボタンをクリックします。
4.  右上の「＋」ボタンを押して、以下のルールを追加します。
    *   名前: 任意（`HTTPS` など）
    *   プロトコル: `TCP`
    *   ホストポート: `443` (Macの443番ポートへのアクセスを...)
    *   ゲストポート: `443` (...VMの443番ポートへ転送する)

この設定により、**[Macのブラウザ] → [Macの443] → (VirtualBoxが転送) → [VMの443] → [NGINX]** という通信経路が開通します。

### ブラウザでアクセスしてログを監視する
アクセスする前に、NGINXのアクセスログとエラーログをリアルタイムで監視（tail）状態にしておきましょう。こうすることで、ブラウザの裏側で何が起きているかが見えます。

```bash
# 別のターミナルタブを開くか、または同じタブで以下のコマンドを実行
sudo tail -f /var/log/nginx/access.log /var/log/nginx/error.log
```

ブラウザを開き、**`https://login.42.fr`** にアクセスしてください。
（※自己署名証明書なので「この接続ではプライバシーが保護されません」と警告が出ますが、「詳細設定」から「〜に進む（安全ではありません）」をクリックして進んでください）

アクセスした瞬間、ターミナル（`tail -f`）にアクセスログがダーッと流れるはずです！

WordPressの初期セットアップ画面（言語選択）が表示されれば、**構築大成功** です！
画面の指示に従い、ステップ2で作成したデータベース情報（DB名:`wordpress_db`, ユーザー:`wp_user`, パスワード:`wp_password`, ホスト:`localhost`）を入力すると、WordPressのインストールが完了します。

---

## まとめ：これらを Docker でやるとはどういうことか？

お疲れ様でした。かなり多くのコマンドを打ち、設定ファイルをいじりましたね。

Inception課題の Docker 化（IaC）とは、**「いまあなたがやったこのすべての手作業コマンドを、3つの `Dockerfile` と初期化スクリプトに分割して記述し、1つのVMに混ぜるのではなく、3つの独立した隔離空間（コンテナ）に分けて自動構築させること」** に他なりません。

この「手作業での構築手順」がイメージできていれば、Dockerfileを書く作業は単なる「自分の行動の翻訳（コード化）」になります。迷ったときは、この手動構築の手順に立ち返ってみてください！
�翻訳（コード化）」になります。迷ったときは、この手動構築の手順に立ち返ってみてください！
