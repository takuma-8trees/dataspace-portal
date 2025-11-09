## 1. Buildx builder setup

```bash 
# Create and use a new builder
docker buildx create --name dataspace-builder --use # example builder name

# Install QEMU for multi-arch support
docker run --rm --privileged tonistiigi/binfmt:latest --install all
```


## 2. Build Backend
Create a `dataspace-portal/authority-portal-backend/authority-portal-quarkus/Dockerfile`
``` Dockerfile
FROM eclipse-temurin:17
WORKDIR /app
COPY build/quarkus-app /app/
ENV JAVA_OPTIONS=""
EXPOSE 8080
ENTRYPOINT ["sh","-c","java $JAVA_OPTIONS -jar /app/quarkus-run.jar"]
```

Build and push a image

```bash
cd authority-portal-backend

docker buildx build \
  --platform linux/amd64,linux/arm64 \
  --push \
  -t ghcr.io/takuma-8trees/authority-portal-backend:latest \ # Temporally pushed to my private ghcr
  -f authority-portal-quarkus/Dockerfile.package \
  --build-arg QUARKUS_PROFILE=prod \
  .
```
## 3. Build Frontend

```bash
cd authority-portal-frontend

# build frontend artifacts
npm ci
npm run build

# build and push the multi-arch image
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  --push \
  -t ghcr.io/takuma-8trees/authority-portal-frontend:latest \
  -f docker/Dockerfile \
  .
```

### 4 Catalog Crawler

The crawler uses a dockerfile that expects the crawler jar in `authority-portal-backend/catalog-crawler/.../app.jar` (I built it locally first):

```bash
cd authority-portal-backend

# build the crawler jar (run the project-specific Gradle task locally)
# ./gradlew :catalog-crawler:build -x test

docker buildx build \
  --platform linux/amd64,linux/arm64 \
  --push \
  -t ghcr.io/takuma-8trees/authority-portal-crawler:latest \
  -f catalog-crawler/Dockerfile \
  .
```

### 5 Test & verification
After pushing the images, I verified the manifests and tested runtime behavior on my machine using the following commands.

Inspect the published multi-arch manifest(s):

```bash
docker buildx imagetools inspect ghcr.io/takuma-8trees/authority-portal-backend:latest
docker buildx imagetools inspect ghcr.io/takuma-8trees/authority-portal-frontend:latest
docker buildx imagetools inspect ghcr.io/takuma-8trees/authority-portal-crawler:latest
```

Run a specific architecture locally (force arm64 or amd64) and check health endpoints / index page:

Backend (arm64):
```bash
docker run --rm --platform linux/arm64 -e QUARKUS_HTTP_PORT=8080 -p 8080:8080 ghcr.io/takuma-8trees/authority-portal-backend:latest &
sleep 5
curl -sS http://localhost:8080/q/health/ready
```

Frontend (arm64)
```bash
docker run --rm --platform linux/arm64 -p 8081:8080 ghcr.io/takuma-8trees/authority-portal-frontend:latest &
sleep 2
curl -sS http://localhost:8081/ | head -n 10
```

Crawler (if it exposes a port):
```bash
docker run --rm --platform linux/arm64 -p 11003:11003 ghcr.io/takuma-8trees/authority-portal-crawler:latest &
sleep 2
curl -sS http://localhost:11003/ || echo "no HTTP endpoint; check container logs"
```
