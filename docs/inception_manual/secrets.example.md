# ローカル secrets テンプレート

次のファイルをローカルの `secrets/` 配下に作成します。実ファイルはコミットしません。

```text
secrets/db_password.txt
secrets/db_root_password.txt
secrets/wp_admin_password.txt
secrets/wp_user_password.txt
```

各ファイルには、強いパスワードを1行だけ入れます。WordPress 管理者パスワードは
`wp core install` が受け入れる強度にする必要があるため、12文字以上で大文字、
小文字、数字、記号を混ぜてください。

ローカルの疎通確認用に、作業ディレクトリへ仮の `secrets/*.txt` が存在していても
構いません。これらは Docker Compose secrets の入力ファイルであり、このリポジトリでは
Git 管理外です。本番相当の評価や共有環境で使う前に、仮の値は必ず置き換えてください。
