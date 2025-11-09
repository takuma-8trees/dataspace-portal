# dataspace-portal/local-deploy

Docker Compose を使って Dataspace Portal の production に近い構成をローカルで再現するための資料です。

このフォルダには、主要なサービスを単一の Docker ネットワーク上で起動するための簡易な docker-compose 設定とヘルパースクリプトが含まれます。開発・検証用途向けであり、本番環境用ではありません。

## 含まれるサービス（最小再現）
- Keycloak (quay.io/keycloak/keycloak)
- PostgreSQL (postgres:16)
- oauth2-proxy (quay.io/oauth2-proxy/oauth2-proxy)
- Caddy (caddy:2.7) — 簡易リバースプロキシ／TLS終端
- Authority Portal の backend / frontend（GHCR の公開イメージ）
- Catalog crawler（EDC ベース）と、ローカル用の Logging House スタブ

## 重要な注意点
- リポジトリ内に Keycloak の realm JSON が含まれています（後述）。realm のインポートが必要です。
- `.env.sample` をコピーして `.env` を作り、Postgres パスワードや Keycloak 管理者パスワード、oauth2-proxy の cookie secret、クライアントシークレットなどを設定してください。
- これは開発／ローカル検証用です。本番でそのまま使わないでください。TLS 設定に関する節を参照してください。

## クイックスタート
1. サンプル環境ファイルをコピーして編集します：

```bash
cp .env.sample .env
# .env を編集して最低限以下を設定してください：
# POSTGRES_PASSWORD, KEYCLOAK_ADMIN_PASSWORD, OAUTH2_PROXY_COOKIE_SECRET
# 必要に応じて CRAWLER_EDC_CLIENT_ID やクrawler の DB 設定も
```

2. （任意）Postgres の初期 SQL を再実行したい場合はボリュームを削除します：

```bash
docker compose -f local-deploy/docker-compose.yml down -v
```

3. スタックを起動します：

```bash
docker compose -f local-deploy/docker-compose.yml up -d
```

4. Keycloak の realm をインポートし、クライアントシークレットを取得します（推奨）：

付属のヘルパースクリプトで realm JSON をインポートし、クライアントシークレットを取得して `local-deploy/.env` を更新できます。

```bash
cd local-deploy
./scripts/import_realm_and_extract_secrets.sh \
  --kc-url http://localhost:8081 \
  --admin-user "$KEYCLOAK_ADMIN_USERNAME" --admin-pass "$KEYCLOAK_ADMIN_PASSWORD" \
  --realm-json ../authority-portal-backend/authority-portal-quarkus/src/main/resources/realm.json \
  --env-file .env --update-env
```

5. oauth2-proxy を再起動して `.env` の変更を反映します：

```bash
docker compose -f local-deploy/docker-compose.yml up -d oauth2-proxy
```

6. 基本的な確認：

```bash
curl -s http://localhost:8081/realms/authority-portal/.well-known/openid-configuration | jq .issuer
docker compose -f local-deploy/docker-compose.yml logs --tail=200 oauth2-proxy
```

## 既定のアクセス先（ローカル）
- フロントエンド (Caddy 経由): http://localhost
- Keycloak 管理 UI (ホストマッピング): http://localhost:8081
- Catalog crawler: http://localhost:11003
- Logging House スタブ: http://localhost:9200

## 起動後に必要な手順（要点）
- リポジトリ内の realm JSON を Keycloak にインポートしてください。
  パス: `authority-portal-backend/authority-portal-quarkus/src/main/resources/realm.json`
- realm をインポート後、以下のクライアントシークレットを取得して `.env` に反映します：
  - `oauth2-proxy` → `OAUTH2_PROXY_CLIENT_SECRET`
  - `authority-portal-client` → `AP_CLIENT_SECRET`

## Catalog crawler に関するメモ
- crawler は Postgres と DAPS/Keycloak に接続する必要があります。接続情報およびクライアント ID（SKI/AKI）を `.env` に設定してください。
- コネクタ（EDC）が同じ realm / DAPS に登録されていないと、クローリングは行われません。

## Logging House
- ローカル検証のために簡易 HTTP スタブを用意しています。本番の logging-house イメージがある場合は差し替えてください。

## 開発（HTTP）と本番（TLS）の考え方（C → A → B）
- C（自動化）: `./scripts/import_realm_and_extract_secrets.sh` を使って realm をインポートし、クライアントシークレットを `.env` に書き込みます。
- A（開発）: compose はローカル HTTP（oauth2-proxy のデバッグ/skip-discovery モード）での素早い検証をサポートします。これは安全でないため開発のみ利用してください。
- B（本番/TLS）: 本番では TLS を有効にし、oauth2-proxy を discovery（HTTPS issuer）で動かし、cookie の secure オプション等を有効にしてください。

## ローカル HTTP クイックスタート（補足）
- 上記の import スクリプトで realm とクライアントシークレットを設定すれば、最小限の手順でログインフローの検証ができます。

## セキュリティ注意事項
- クライアントシークレットや API キー、パスワードをリポジトリに保存しないでください。Vault や Kubernetes Secret、環境変数等の安全なストアを利用してください。
- HTTP モードは開発専用です。プロダクションでは必ず TLS を使用し、`cookie-secure=true` を有効にしてください。

## トラブルシューティング
- oauth2-proxy が Keycloak から "HTTPS required" を返す場合は Keycloak が TLS を要求しています。開発用であれば realm の `sslRequired` を `none` にするか、oauth2-proxy を skip-discovery モードで explicit endpoint を使ってください。
- コンテナが `exec format error` で落ちる場合、ホストのアーキテクチャ（例: linux/arm64）とイメージのアーキテクチャ（例: linux/amd64）が合っていません。対処法:
  - QEMU/binfmt を有効にして amd64 イメージを arm64 ホストで動かす。
  - 対象アーキテクチャ向けにローカルでイメージをビルドし、`docker-compose.yml` を `build:` に変更する。
  - `platform: linux/amd64` をサービスに追加する（QEMU が必要）。

## TLS（本番向けガイダンス）
- 推奨: Caddy 等を TLS 終端にして公開エンドポイントを作り、内部はリバースプロキシで Keycloak / oauth2-proxy を参照する構成が簡単です。Caddy は Let's Encrypt による自動証明書発行に対応しています。

### パターン 1 — Caddy + Let's Encrypt（推奨）
- 公開 DNS を用意してドメイン（例: `keycloak.example.com`, `portal.example.com`）が Caddy のホストを指すようにします。
- Caddyfile で Keycloak と oauth2-proxy を内部へリバースプロキシし、`X-Forwarded-*` ヘッダを渡すようにします。
- Keycloak の `KC_HOSTNAME` を公開ホスト名に設定し、oauth2-proxy の issuer を `https://...` にします。

### パターン 2 — mkcert を使ったローカル HTTPS（開発）
- `mkcert` でローカル CA を作り、`keycloak.local` や `portal.local` の証明書を生成して Caddy にマウントします。`/etc/hosts` にエントリを追加してローカルで名前解決します。

## 次の改善案（必要なら実装します）
- `platform: linux/amd64` を使った compose 例、あるいは arm64 向けにローカルビルドする `docker-compose` バリアント。
- Caddy + Let's Encrypt の production 用 `docker-compose` と `Caddyfile` テンプレート。
- 環境を一括でブートストラップするワンショットスクリプト（realm import、`.env` 更新、oauth2-proxy 再起動、スモークテスト）。

ご希望があればどれを作るか教えてください。対応します。
