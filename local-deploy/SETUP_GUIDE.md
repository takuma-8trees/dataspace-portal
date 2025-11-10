# Dataspace Portal ローカル環境セットアップガイド

## 前提条件

- Docker & Docker Compose
- ローカルの `local-deploy` ディレクトリ

## セットアップ手順

### 1. 環境変数の確認

`.env` ファイルが正しく設定されているか確認：

```bash
cd local-deploy
cat .env
```

必要な変数：
- `POSTGRES_PASSWORD`: PostgreSQLのパスワード
- `KEYCLOAK_ADMIN_USERNAME`: Keycloak管理者ユーザー名
- `KEYCLOAK_ADMIN_PASSWORD`: Keycloak管理者パスワード
- `OAUTH2_PROXY_COOKIE_SECRET`: OAuth2 Proxyのクッキー秘密鍵（32バイト）
- `OAUTH2_PROXY_CLIENT_SECRET`: OAuth2 Proxyのクライアントシークレット
- `AP_CLIENT_SECRET`: Authority Portalのクライアントシークレット
- `AP_CONFIG_API_KEY`: 設定APIキー

### 2. 古いデータをクリーンアップ（初回または再構築時）

```bash
docker compose down -v
```

### 3. PostgreSQLとKeycloakを起動

```bash
docker compose up -d postgres keycloak
```

### 4. Keycloakの起動を待つ

```bash
# 約30-60秒待つ
sleep 30

# Keycloakが起動したか確認
curl http://localhost:8081/realms/authority-portal/.well-known/openid-configuration

# または
docker compose logs keycloak --tail=20
```

### 5. Keycloak Realmをインポート

```bash
./scripts/import_realm_and_extract_secrets.sh \
  --kc-url http://localhost:8081 \
  --admin-user admin \
  --admin-pass admin123 \
  --realm-json ../authority-portal-backend/authority-portal-quarkus/src/main/resources/realm.json \
  --env-file .env --update-env
```

### 6. 残りのサービスを起動

```bash
docker compose up -d
```

### 7. 動作確認

```bash
# すべてのサービスの状態確認
docker compose ps

# バックエンドのログ確認
docker compose logs backend --tail=50

# フロントエンドにアクセス
curl http://localhost

# または、ブラウザで http://localhost を開く
```

## トラブルシューティング

### バックエンドが起動しない

**エラー**: `The config property authority-portal.deployment.environments.test.* is required`

**原因**: 設定ファイルが読み込まれていない

**解決策**:
1. `docker-compose.yml` でボリュームマウントを確認：
   ```yaml
   volumes:
     - ./config/application.properties:/deployments/config/application.properties:ro
   ```

2. 設定ファイルの内容を確認：
   ```bash
   cat config/application.properties
   ```

3. バックエンドを再起動：
   ```bash
   docker compose restart backend
   ```

### Keycloakがパスワード認証エラー

**エラー**: `password authentication failed for user "postgres"`

**原因**: 古いデータベースが残っている

**解決策**:
```bash
docker compose down -v
docker compose up -d postgres keycloak
```

### OAuth2 Proxyが動作しない

**エラー**: `invalid_client` または認証エラー

**原因**: クライアントシークレットが正しくない

**解決策**:
1. Realmインポート後、`.env` のシークレットが更新されたか確認
2. OAuth2 Proxyを再起動：
   ```bash
   docker compose up -d oauth2-proxy
   ```

## Client Credentials Flowのテスト準備

### Keycloakでサービスアカウントクライアントを作成

1. Keycloak Admin Console にアクセス: http://localhost:8081
2. Realm: `authority-portal` を選択
3. Clients → Create client
   - Client ID: `api-client`
   - Client authentication: ON
   - Service accounts roles: ON
4. Credentials タブでシークレットを取得
5. Service Account Roles でロールを設定:
   - UR_AUTHORITY-PORTAL_PARTICIPANT-USER

### トークン取得テスト

```bash
TOKEN=$(curl -s -X POST \
  "http://localhost:8081/realms/authority-portal/protocol/openid-connect/token" \
  -d "grant_type=client_credentials" \
  -d "client_id=api-client" \
  -d "client_secret=YOUR_CLIENT_SECRET")

echo $TOKEN
```

### API呼び出しテスト

```bash
curl -X POST \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "filter": {},
    "searchQuery": "",
    "pageOneBased": 1
  }' \
  "http://localhost/api/catalog/catalog-page?environmentId=test"
```

## 参考

- [README.md](README.md) - Docker Compose構成の詳細
- [README.ja.md](README.ja.md) - 日本語ドキュメント
- [Keycloak Documentation](https://www.keycloak.org/documentation)
