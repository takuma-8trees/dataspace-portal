# Authority Portal API アクセスガイド

## 概要

このドキュメントでは、Sovity Dataspace Portal (Authority Portal) のAPIへのアクセス方法について説明します。

- **現状**: Cookie認証（ブラウザ経由のみ）
- **提案**: OAuth2 Client Credentials Flowのサポート追加

---

## 現状: Cookie認証によるAPI利用

### 認証方式

Authority Portalは現在、**OAuth2 Proxy経由のCookie認証**のみをサポートしています。

**アーキテクチャ:**
```
Browser → OAuth2 Proxy → Authority Portal Backend
          (Cookie認証)
```

### 利用可能なAPIエンドポイント

#### カタログAPI

**エンドポイント:** `POST /api/catalog/catalog-page`

**リクエスト例:**
```json
{
  "filter": {},
  "searchQuery": "",
  "pageOneBased": 1
}
```

**レスポンス例:**
```json
{
  "dataOffers": [...],
  "availableFilters": {...},
  "totalCount": 42
}
```

#### データオファー詳細API

**エンドポイント:** `POST /api/catalog/data-offer-detail-page`

### 現状でのAPI利用方法

#### 方法1: ブラウザのDevToolsからCookieを取得

1. **ブラウザでAuthority Portalにログイン**
   ```
   https://portal.mobility-dataspace.eu/
   ```

2. **DevTools（F12）を開く**
   - `Network` タブを選択
   - カタログページに移動
   - `/api/catalog/catalog-page` リクエストを見つける

3. **リクエストヘッダーからCookieをコピー**
   ```
   Cookie: _oauth2_proxy=xxxxx; session=yyyyy
   ```

4. **curlでAPIを呼び出す**
   ```bash
   curl -X POST \
     -H "Cookie: _oauth2_proxy=xxxxx; session=yyyyy" \
     -H "Content-Type: application/json" \
     -d '{
       "filter": {},
       "searchQuery": "",
       "pageOneBased": 1
     }' \
     "https://portal.mobility-dataspace.eu/api/catalog/catalog-page?environmentId=prod"
   ```

#### 方法2: ブラウザから直接curlコマンドをコピー（推奨）

1. **NetworkタブでAPIリクエストを右クリック**
2. **`Copy` → `Copy as cURL (bash)` を選択**
3. **コピーされたコマンドをそのまま実行**

```bash
curl 'https://portal.mobility-dataspace.eu/api/catalog/catalog-page?environmentId=prod' \
  -H 'accept: application/json' \
  -H 'content-type: application/json' \
  -H 'cookie: _oauth2_proxy=xxxxx; session=yyyyy' \
  --data-raw '{"filter":{},"searchQuery":"","pageOneBased":1}'
```

#### 方法3: Pythonスクリプト

```python
import requests

cookies = {
    '_oauth2_proxy': 'xxxxx',
    'session': 'yyyyy'
}

headers = {
    'Content-Type': 'application/json'
}

data = {
    "filter": {},
    "searchQuery": "",
    "pageOneBased": 1
}

response = requests.post(
    'https://portal.mobility-dataspace.eu/api/catalog/catalog-page?environmentId=prod',
    cookies=cookies,
    headers=headers,
    json=data
)

print(response.json())
```

### 現状の制限事項

❌ **以下のユースケースには対応できません:**

1. **CI/CDパイプライン**
   - 自動ビルド・テストでのカタログ情報取得
   - 定期的なデータ同期

2. **バックエンドサーバー間通信**
   - 他システムからの自動連携
   - Machine-to-Machine (M2M) 通信

3. **CLIツール・スクリプト**
   - コマンドラインからの操作
   - バッチ処理

4. **外部監視・分析ツール**
   - リアルタイム監視
   - データ分析パイプライン

**理由:** Cookieは手動でブラウザから取得する必要があり、有効期限があるため。

---

## 提案: OAuth2 Client Credentials Flow

### なぜClient Credentials Flowか？

| 項目 | Cookie認証 | Client Credentials |
|------|-----------|-------------------|
| **対象** | ブラウザのみ | プログラム・サーバー |
| **認証** | 手動ログイン | 自動（ClientID/Secret） |
| **有効期限** | セッションベース | トークンで管理 |
| **管理** | ブラウザセッション | Keycloak Admin UI |
| **標準化** | 独自実装 | OAuth2標準 |
| **セキュリティ** | Cookie依存 | トークンベース |
| **実装コスト** | N/A | ほぼゼロ（設定のみ） |

### 実装案

#### Phase 1: 最小実装（設定のみ）

**Keycloakでサービスアカウントクライアントを作成:**

1. Keycloak Admin Consoleにアクセス
2. Realm: `authority-portal` を選択
3. `Clients` → `Create client`
   - **Client ID**: `api-client`
   - **Client authentication**: ON
   - **Service accounts roles**: ON
4. `Credentials` タブでシークレットを取得
5. `Service Account Roles` でロールを設定:
   - `UR_AUTHORITY-PORTAL_PARTICIPANT-USER`

**既存のJWT認証フローがそのまま動作:**

Authority Portalは既にJWT認証をサポートしているため、コード変更不要。

#### Phase 2: ドキュメント整備

- API利用ガイドの作成
- サンプルコード（Python, curl, Node.js等）
- OpenAPI仕様書の公開

#### Phase 3: 拡張機能（オプション）

- Read-Onlyな公開APIエンドポイント
- レート制限の追加
- 分析用クエリの最適化

### 使用例

#### 1. トークン取得

```bash
TOKEN=$(curl -s -X POST \
  "https://identity.mobility-dataspace.eu/realms/authority-portal/protocol/openid-connect/token" \
  -d "grant_type=client_credentials" \
  -d "client_id=api-client" \
  -d "client_secret=YOUR_CLIENT_SECRET" \
  | jq -r '.access_token')

echo "Token: ${TOKEN:0:50}..."
```

#### 2. API呼び出し

```bash
curl -X POST \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "filter": {},
    "searchQuery": "",
    "pageOneBased": 1
  }' \
  "https://portal.mobility-dataspace.eu/api/catalog/catalog-page?environmentId=prod"
```

#### 3. Pythonでの利用

```python
import requests

# トークン取得
token_response = requests.post(
    'https://identity.mobility-dataspace.eu/realms/authority-portal/protocol/openid-connect/token',
    data={
        'grant_type': 'client_credentials',
        'client_id': 'api-client',
        'client_secret': 'YOUR_CLIENT_SECRET'
    }
)

token = token_response.json()['access_token']

# API呼び出し
headers = {
    'Authorization': f'Bearer {token}',
    'Content-Type': 'application/json'
}

data = {
    "filter": {},
    "searchQuery": "",
    "pageOneBased": 1
}

response = requests.post(
    'https://portal.mobility-dataspace.eu/api/catalog/catalog-page?environmentId=prod',
    headers=headers,
    json=data
)

print(response.json())
```

### ユースケース

#### 1. データカタログの定期監視

```bash
#!/bin/bash
# daily-catalog-check.sh

TOKEN=$(curl -s -X POST "$KEYCLOAK_URL/realms/authority-portal/protocol/openid-connect/token" \
  -d "grant_type=client_credentials" \
  -d "client_id=$CLIENT_ID" \
  -d "client_secret=$CLIENT_SECRET" \
  | jq -r '.access_token')

CATALOG=$(curl -s -X POST \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"filter":{},"searchQuery":"","pageOneBased":1}' \
  "$API_URL/api/catalog/catalog-page?environmentId=prod")

# 新しいデータオファーをチェック
NEW_OFFERS=$(echo $CATALOG | jq '.totalCount')
echo "Total data offers: $NEW_OFFERS"

# Slackに通知
curl -X POST $SLACK_WEBHOOK -d "{\"text\":\"New catalog update: $NEW_OFFERS offers\"}"
```

#### 2. CI/CDでのテスト

```yaml
# .github/workflows/catalog-test.yml
name: Catalog Integration Test

on:
  schedule:
    - cron: '0 0 * * *'  # 毎日実行

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - name: Get Token
        id: token
        run: |
          TOKEN=$(curl -s -X POST ${{ secrets.KEYCLOAK_URL }}/realms/authority-portal/protocol/openid-connect/token \
            -d "grant_type=client_credentials" \
            -d "client_id=${{ secrets.CLIENT_ID }}" \
            -d "client_secret=${{ secrets.CLIENT_SECRET }}" \
            | jq -r '.access_token')
          echo "::add-mask::$TOKEN"
          echo "token=$TOKEN" >> $GITHUB_OUTPUT

      - name: Test Catalog API
        run: |
          curl -f -X POST \
            -H "Authorization: Bearer ${{ steps.token.outputs.token }}" \
            -H "Content-Type: application/json" \
            -d '{"filter":{},"searchQuery":"","pageOneBased":1}' \
            "${{ secrets.API_URL }}/api/catalog/catalog-page?environmentId=prod"
```

#### 3. データ分析パイプライン

```python
# analytics/fetch_catalog.py
import requests
import pandas as pd
from datetime import datetime

class CatalogAnalytics:
    def __init__(self, keycloak_url, api_url, client_id, client_secret):
        self.keycloak_url = keycloak_url
        self.api_url = api_url
        self.client_id = client_id
        self.client_secret = client_secret
        self.token = None

    def get_token(self):
        response = requests.post(
            f'{self.keycloak_url}/realms/authority-portal/protocol/openid-connect/token',
            data={
                'grant_type': 'client_credentials',
                'client_id': self.client_id,
                'client_secret': self.client_secret
            }
        )
        self.token = response.json()['access_token']

    def fetch_catalog(self, environment_id='prod'):
        headers = {
            'Authorization': f'Bearer {self.token}',
            'Content-Type': 'application/json'
        }
        
        response = requests.post(
            f'{self.api_url}/api/catalog/catalog-page',
            params={'environmentId': environment_id},
            headers=headers,
            json={'filter': {}, 'searchQuery': '', 'pageOneBased': 1}
        )
        
        return response.json()

    def analyze(self):
        self.get_token()
        catalog = self.fetch_catalog()
        
        # DataFrameに変換
        df = pd.DataFrame(catalog['dataOffers'])
        
        # 分析
        print(f"Total offers: {len(df)}")
        print(f"Online connectors: {df['connectorOnlineStatus'].value_counts()}")
        
        # 結果を保存
        df.to_csv(f'catalog_{datetime.now().isoformat()}.csv')

if __name__ == '__main__':
    analytics = CatalogAnalytics(
        keycloak_url=os.getenv('KEYCLOAK_URL'),
        api_url=os.getenv('API_URL'),
        client_id=os.getenv('CLIENT_ID'),
        client_secret=os.getenv('CLIENT_SECRET')
    )
    analytics.analyze()
```

---

## ローカル環境でのテスト手順

### 前提条件

- Docker & Docker Compose
- このリポジトリのクローン

### 1. 環境構築

```bash
cd local-deploy

# 環境変数を設定
cp .env.sample .env
# .env を編集してパスワードを設定

# Docker Composeで起動
docker compose down -v
docker compose up -d

# Keycloakが起動するまで待つ（約1分）
sleep 60
```

### 2. Keycloak Realmのインポート

**ブラウザで手動インポート:**

1. http://localhost:8081 を開く
2. `admin` / (設定したパスワード) でログイン
3. 左上のドロップダウン → "Create realm"
4. "Import" を選択
5. `authority-portal-backend/authority-portal-quarkus/src/main/resources/realm.json` をアップロード
6. "Create" をクリック

### 3. サービスアカウントクライアントの作成

1. Keycloak Admin Console で `authority-portal` Realmを選択
2. `Clients` → `Create client`
3. 設定:
   ```
   Client ID: api-client
   Name: API Client for Testing
   ```
4. `Next` をクリック
5. 設定:
   ```
   Client authentication: ON
   Authorization: OFF
   Standard flow: OFF
   Direct access grants: OFF
   Service accounts roles: ON
   ```
6. `Save` をクリック
7. `Credentials` タブでClient Secretをコピー
8. `Service Account Roles` タブ:
   - `Assign role` をクリック
   - `Filter by clients` を選択
   - `UR_AUTHORITY-PORTAL_PARTICIPANT-USER` を追加

### 4. Client Credentials Flowのテスト

```bash
# トークン取得
TOKEN=$(curl -s -X POST \
  "http://localhost:8081/realms/authority-portal/protocol/openid-connect/token" \
  -d "grant_type=client_credentials" \
  -d "client_id=api-client" \
  -d "client_secret=YOUR_CLIENT_SECRET" \
  | grep -o '"access_token":"[^"]*"' | cut -d'"' -f4)

echo "Token acquired: ${TOKEN:0:50}..."

# API呼び出し
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

### 期待される結果

```json
{
  "dataOffers": [],
  "availableFilters": {...},
  "totalCount": 0
}
```

---

## コミュニティへの提案

### GitHub Issue テンプレート

**タイトル:**
```
Support OAuth2 Client Credentials Flow for programmatic API access
```

**本文:**

```markdown
## Problem Statement

Currently, the Authority Portal API only supports Cookie-based authentication via OAuth2 Proxy, which is designed for browser-based access. This makes it difficult or impossible to access the API programmatically from:

- CI/CD pipelines
- External monitoring/analytics tools
- CLI tools and scripts
- Other systems requiring M2M (Machine-to-Machine) communication

## Use Cases

### 1. Automated Catalog Monitoring
- Detect new data offers automatically
- Monitor connector online status
- Generate periodic reports

### 2. System Integration
- Corporate portal integration
- Third-party tool integration
- Data analysis pipelines

### 3. DevOps Automation
- CI/CD workflows
- Automated testing
- Infrastructure monitoring

### 4. Data Analytics
- Real-time data catalog analysis
- Business intelligence integration
- Trend analysis and reporting

## Proposed Solution

Add support for **OAuth2 Client Credentials Flow** to enable programmatic API access.

### Why Client Credentials Flow?

| Feature | Current (Cookie) | Proposed (Client Credentials) |
|---------|-----------------|------------------------------|
| **Target Audience** | Browser users only | Programs & servers |
| **Authentication** | Manual login | Automatic (ClientID/Secret) |
| **Expiration** | Session-based | Token with configurable TTL |
| **Management** | Browser session | Keycloak Admin UI |
| **Industry Standard** | N/A | OAuth2 RFC 6749 |
| **Security** | Cookie-based | Token-based with rotation |
| **Implementation Cost** | N/A | **Near zero** (configuration only) |

### Benefits

✅ **Minimal implementation cost** - Leverages existing Keycloak infrastructure  
✅ **Industry standard** - OAuth2 is widely adopted in enterprise systems  
✅ **Secure** - Token-based authentication with expiration and rotation  
✅ **Easy to manage** - Keycloak admin UI for client management  
✅ **No breaking changes** - Existing Cookie auth continues to work  
✅ **Improved developer experience** - Standard OAuth2 libraries available  
✅ **Better auditability** - Keycloak provides comprehensive logging  

### Implementation Plan

**Phase 1: Enable Service Accounts (Minimal - Configuration Only)**

No code changes required. Authority Portal already supports JWT authentication.

Steps:
1. Document how to create service account clients in Keycloak
2. Document the token acquisition process
3. Verify existing JWT authentication works with client credentials tokens

Estimated effort: **1-2 days for documentation**

**Phase 2: Documentation & Examples (Optional)**

- Create comprehensive API usage guide
- Provide code examples (Python, JavaScript, curl, etc.)
- Publish OpenAPI specification
- Add to deployment documentation

Estimated effort: **2-3 days**

**Phase 3: Enhanced Features (Optional - Future)**

- Read-only public API endpoints
- Rate limiting per client
- Query optimization for analytics use cases
- Dedicated API documentation portal

Estimated effort: **1-2 weeks**

## Example Usage

### 1. Token Acquisition

```bash
TOKEN=$(curl -s -X POST \
  "https://keycloak.example.com/realms/authority-portal/protocol/openid-connect/token" \
  -d "grant_type=client_credentials" \
  -d "client_id=api-client" \
  -d "client_secret=xxxxx" \
  | jq -r '.access_token')
```

### 2. API Call

```bash
curl -X POST \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "filter": {},
    "searchQuery": "",
    "pageOneBased": 1
  }' \
  "https://portal.example.com/api/catalog/catalog-page?environmentId=prod"
```

### 3. Python Example

```python
import requests

# Get token
token_response = requests.post(
    'https://keycloak.example.com/realms/authority-portal/protocol/openid-connect/token',
    data={
        'grant_type': 'client_credentials',
        'client_id': 'api-client',
        'client_secret': 'xxxxx'
    }
)
token = token_response.json()['access_token']

# Call API
response = requests.post(
    'https://portal.example.com/api/catalog/catalog-page?environmentId=prod',
    headers={'Authorization': f'Bearer {token}'},
    json={'filter': {}, 'searchQuery': '', 'pageOneBased': 1}
)
print(response.json())
```

## Technical Details

### Current Architecture

```
Browser → OAuth2 Proxy (Cookie) → Authority Portal Backend (JWT validation)
                                   ↓
                                Keycloak (OIDC)
```

### Proposed Architecture

```
Browser → OAuth2 Proxy (Cookie) ↘
                                 → Authority Portal Backend (JWT validation)
Service → Keycloak (Client Credentials) ↗                    ↓
                                                          Keycloak (OIDC)
```

**Key Point:** The backend already validates JWTs. No code changes needed.

### Security Considerations

1. **Token Expiration**: Configurable TTL (default: 5-60 minutes)
2. **Token Rotation**: Refresh tokens for long-running services
3. **Scope Limitation**: Restrict to read-only operations if needed
4. **Audit Logging**: Keycloak provides comprehensive audit logs
5. **Rate Limiting**: Can be added at OAuth2 Proxy or backend level

### Compatibility

- ✅ No breaking changes to existing authentication
- ✅ Works with existing JWT validation logic
- ✅ Compatible with all Authority Portal versions using Keycloak
- ✅ Can be deployed gradually (per-realm or per-environment)

## Related

This feature would benefit all dataspaces using the Authority Portal:

- ✅ Mobility Dataspace (MDS)
- ✅ Manufacturing-X
- ✅ Catena-X
- ✅ Other Gaia-X dataspaces
- ✅ Private enterprise dataspaces

## Alternatives Considered

### 1. API Key Authentication

**Pros:**
- Simple to implement
- Easy for users

**Cons:**
- Not industry standard
- Requires custom implementation
- Static secrets (security concern)
- No built-in expiration
- Manual key management

**Decision:** Client Credentials is preferred due to standards compliance and zero implementation cost.

### 2. Personal Access Tokens (PAT)

**Pros:**
- User-scoped
- Revocable

**Cons:**
- Requires new token management system
- Not suitable for service accounts
- Additional maintenance burden

**Decision:** Client Credentials better suited for M2M communication.

## Testing

I have successfully tested this approach in a local environment:

1. ✅ Set up local Authority Portal with Docker Compose
2. ✅ Created service account client in Keycloak
3. ✅ Obtained token via client credentials grant
4. ✅ Called catalog API with Bearer token
5. ✅ Verified JWT validation works correctly

See [API Access Guide](../docs/api-access-guide.md) for detailed testing instructions.

## Willingness to Contribute

- [x] I am willing to contribute documentation
- [x] I can provide testing guidance
- [x] I can help with community feedback
- [ ] I can submit a PR if code changes are needed (currently none required)

## References

- [OAuth 2.0 RFC 6749 - Client Credentials Grant](https://datatracker.ietf.org/doc/html/rfc6749#section-4.4)
- [Keycloak Service Accounts](https://www.keycloak.org/docs/latest/server_admin/#_service_accounts)
- [Mobility Dataspace Documentation](https://mobility-dataspace.eu/)
```

### 提案先

1. **sovity/dataspace-portal** (このリポジトリ)
   - Issue: https://github.com/sovity/dataspace-portal/issues/new?template=feature_request.md

2. **Mobility Dataspace** (MDSコミュニティ)
   - 公式フォーラム・Slackチャンネル
   - 技術ワーキンググループ

3. **Gaia-X / Catena-X** (より広範なコミュニティ)
   - Eclipse Dataspace Working Group
   - Catena-X Technical Committee

---

## まとめ

### 現状の課題

- Cookie認証のみ → プログラムからのアクセスが困難
- 手動でのトークン取得 → 自動化できない
- ブラウザ依存 → M2M通信に対応できない

### 提案する解決策

- OAuth2 Client Credentials Flow の追加
- **実装コスト: ほぼゼロ**（Keycloak設定のみ）
- 既存機能への影響なし

### 期待される効果

- CI/CDパイプラインでの自動化
- 外部システムとの連携
- データ分析・監視の容易化
- 開発者体験の向上

### 次のステップ

1. ✅ ローカル環境でテスト
2. ⏳ コミュニティへの提案（Issue作成）
3. ⏳ フィードバックの収集
4. ⏳ ドキュメント整備
5. ⏳ 本番環境への展開

---

## 参考リンク

- [Sovity Dataspace Portal](https://github.com/sovity/dataspace-portal)
- [Mobility Dataspace](https://mobility-dataspace.eu/)
- [OAuth 2.0 Specification](https://oauth.net/2/)
- [Keycloak Documentation](https://www.keycloak.org/documentation)
- [Eclipse Dataspace Components](https://github.com/eclipse-edc/Connector)
