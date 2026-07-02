# Local secrets template

Create these files locally under `secrets/`. Do not commit the real files.

```text
secrets/db_password.txt
secrets/db_root_password.txt
secrets/wp_admin_password.txt
secrets/wp_user_password.txt
```

Each file should contain exactly one strong password. The WordPress administrator
password must be strong enough for `wp core install`; use at least 12 characters
with mixed character classes.
