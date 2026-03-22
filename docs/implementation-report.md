# EKS Observability 實作項目回覆

> Git Repo: https://github.com/yujie70338/terraform-eks-observability-example

---

## 目錄

1. [靜態頁面 Dockerfile 與 Image](#1-靜態頁面-dockerfile-與-image)
2. [Helm Chart 打包](#2-helm-chart-打包)
3. [Terraform 建置 EKS 與部署](#3-terraform-建置-eks-與部署)
4. [Grafana 監控 Dashboard](#4-grafana-監控-dashboard)
5. [Alertmanager Telegram 告警](#5-alertmanager-telegram-告警)
6. [CI/CD Pipeline（加分項）](#6-cicd-pipeline加分項)

---

## 1. 靜態頁面 Dockerfile 與 Image

### Dockerfile 設計重點

> 原始檔案：[app/Dockerfile](../app/Dockerfile)

```dockerfile
FROM --platform=$BUILDPLATFORM alpine:3.19 AS builder
WORKDIR /build
COPY index.html .

FROM --platform=$TARGETPLATFORM nginx:alpine

RUN touch /var/run/nginx.pid && \
    chown -R nginx:nginx /var/run/nginx.pid /var/cache/nginx /var/log/nginx /etc/nginx/conf.d

COPY --from=builder /build/index.html /usr/share/nginx/html/index.html
RUN sed -i 's/listen\(.*\)80;/listen 8080;/' /etc/nginx/conf.d/default.conf

EXPOSE 8080
USER nginx
CMD ["nginx", "-g", "daemon off;"]
```

| 設計決策 | 說明 |
|----------|------|
| Multi-stage build | 分離建置環境與執行環境，縮小最終 image 體積 |
| `--platform=$BUILDPLATFORM` | Builder stage 使用本機平台加速建置 |
| `--platform=$TARGETPLATFORM` | Runtime stage 根據目標平台選擇正確 binary |
| `USER nginx` | 非 Root 執行，符合 PSS Baseline 安全規範 |
| Port 8080 | 非特權 port（< 1024 需要 root），配合非 root 執行 |

### 手動建置指令

```bash
# Multi-platform build（amd64 + arm64）
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  -t yujie70338/static-web:v1.0.0 \
  --push \
  app/
```

### 關於 Layer Cache

本專案 Dockerfile 未額外設計 layer cache 分層，原因如下：

此服務為純靜態頁面，build 流程中**沒有套件安裝步驟**（如 `npm install`、`pip install`），整個 Builder stage 只有一行 `COPY index.html`。

Layer cache 的效益體現在「依賴安裝耗時」的場景，例如：

```dockerfile
# 有 npm install 的專案才需要這種分層設計
COPY package.json package-lock.json ./   # ← 變動少，cache 命中率高
RUN npm ci                               # ← 耗時，希望 cache
COPY src/ ./                             # ← 變動頻繁，放最後
```

本專案 build 時間極短，不需要此優化。CI 中已加入 **BuildKit GHA cache**（`cache-from: type=gha`），可跨 workflow run 重用 Docker layer，達到 cache 加速效果。

### DockerHub Public Image

🔗 **https://hub.docker.com/r/yujie70338/static-web/tags**

### CI 自動化建置

> Pipeline 設定：[.github/workflows/app-helm.yml](../.github/workflows/app-helm.yml)
> GitHub Actions：https://github.com/yujie70338/terraform-eks-observability-example/actions/workflows/app-helm.yml

每次 `app/**` 變動觸發：

1. **Hadolint**：Dockerfile 靜態分析
2. **Build**（amd64）→ **Trivy** 漏洞掃描
3. **Push**（amd64 + arm64）到 DockerHub，tag 格式為 git SHA 前 7 碼
4. **Helm upgrade** 部署到 EKS，並驗證 rollout 狀態

---

## 2. Helm Chart 打包

### Chart 結構

```
helm/static-web/
├── Chart.yaml
├── values.yaml
└── templates/
    ├── namespace.yaml    # PSS Baseline label
    ├── deployment.yaml   # Tolerations, SecurityContext
    ├── service.yaml      # ClusterIP
    ├── ingress.yaml      # ALB internet-facing, IP mode
    └── pdb.yaml          # minAvailable: 10%
```

### 未額外建立 ConfigMap、NetworkPolicy、RBAC 的原因

| 資源 | 未建立原因 |
|------|------------|
| ConfigMap | 應用為純靜態 HTML，無動態設定需求；nginx 預設設定已透過 `RUN sed` (第 14 行) 在 Dockerfile 修改 |
| NetworkPolicy | 本專案為 demo 環境，已安裝 AWS VPC CNI addon，但未啟用其 Network Policy Controller（預設關閉）；生產環境應啟用以限制和管理 cluster 內的流量 |
| RBAC | 靜態網頁 Pod 不需存取 Kubernetes API，無需 ServiceAccount 額外授權；監控元件（Prometheus）的 RBAC 由 kube-prometheus-stack chart 自動管理 |

### PDB 設定

> 原始檔案：[helm/static-web/templates/pdb.yaml](../helm/static-web/templates/pdb.yaml)

```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: {{ .Release.Name }}
  namespace: {{ .Values.namespace }}
spec:
  minAvailable: {{ .Values.pdb.minAvailable }}   # "10%"
  selector:
    matchLabels:
      app: {{ .Release.Name }}
```

`minAvailable: 10%` 確保在節點維護、滾動更新期間，至少 10% 的 Pod 保持 Running 狀態，避免服務完全中斷。

### Deployment 額外的安全設定（PSS Baseline）

> 原始檔案：[helm/static-web/templates/deployment.yaml](../helm/static-web/templates/deployment.yaml)

```yaml
# Pod-level
securityContext:
  runAsNonRoot: true
  seccompProfile:
    type: RuntimeDefault

# Container-level
securityContext:
  allowPrivilegeEscalation: false
  runAsUser: 101        # nginx user
  capabilities:
    drop: [ALL]
```

### Ingress（ALB IP Mode）

> 原始檔案：[helm/static-web/templates/ingress.yaml](../helm/static-web/templates/ingress.yaml)

```yaml
annotations:
  alb.ingress.kubernetes.io/scheme: internet-facing
  alb.ingress.kubernetes.io/target-type: ip
  alb.ingress.kubernetes.io/listen-ports: '[{"HTTP": 80}]'
```

選用 IP Mode（`target-type: ip`）而非預設 Instance Mode 的原因：

| | IP Mode | Instance Mode |
|---|---|---|
| 流量路徑 | ALB → Pod IP（直連）| ALB → NodePort → kube-proxy → Pod |
| 延遲 | 較低（少一跳）| 較高 |
| 需求 | Pod 必須在 VPC 可路由網段 | 無 |
| 本專案適用 | EKS 節點在 Private Subnet，Pod IP 可被 ALB 直接路由 | ― |

### values.yaml 核心配置

> 原始檔案：[helm/static-web/values.yaml](../helm/static-web/values.yaml)

```yaml
image:
  repository: yujie70338/static-web
  tag: "v1.0.0"

replicaCount: 2

resources:
  requests:
    cpu: 50m
    memory: 32Mi
  limits:
    cpu: 100m
    memory: 64Mi

nodeSelector:
  role: app                   # 只調度到 App Node Group

tolerations:
  - key: "dedicated"
    value: "app"
    effect: "NoSchedule"      # 容忍 App Node 的 Taint

pdb:
  enabled: true
  minAvailable: "10%"
```

---

## 3. Terraform 建置 EKS 與部署

### 架構概覽

```
Internet
    │
    ▼
[ALB - internet-facing]
    │  (IP Mode)
    ├──────────────────────────┐
    ▼                          ▼
[App Nodes - t3.small]    [Infra Nodes - t3.medium]
 Taint: dedicated=app      Taint: dedicated=infra
    │                          │
[static-web Pods]         [Prometheus / Grafana / Alertmanager]
                          [AWS Load Balancer Controller]
```

### 網路設計

| 子網路 | 數量 | 用途 |
|--------|------|------|
| Public Subnet | 3（3 AZ） | ALB |
| Private Subnet | 3（3 AZ） | EKS 節點 |
| NAT Gateway | 1（共用節省成本） | 出站流量 |

### 節點隔離策略

| Node Group | 機型 | Taint | Label | 用途 |
|-----------|------|-------|-------|------|
| infra | t3.medium | `dedicated=infra:NoSchedule` | `role=infra` | 監控元件、ALB Controller |
| app | t3.small | `dedicated=app:NoSchedule` | `role=app` | 靜態網站 |

透過 Taint + Toleration 確保應用 Pod 與監控 Pod **物理隔離**在不同節點，互不干擾。

### 為何檔案結構較為扁平

本專案採用扁平（flat）的目錄結構，主要基於以下考量：

| 考量 | 說明 |
|------|------|
| 單一應用程式 | 整個 Helm Chart 僅服務一個靜態網站，不需要拆分成多個子模組或 library chart |
| 單一環境 | 本專案僅部署一套環境，不存在 dev / prod 環境切換需求，無需建立 `envs/dev/`、`envs/prod/` 等子目錄 |
| Terraform 模組已封裝複雜度 | VPC、EKS、IRSA 等基礎設施邏輯由社群模組（`terraform-aws-modules`）封裝，`terraform/` 目錄只需放置呼叫這些模組的頂層設定檔，不需要額外的 `modules/` 子目錄 |
| 無自訂模組需求 | 所有資源邏輯已由社群模組封裝，`terraform/` 底下各檔案職責單一（vpc.tf、eks.tf、irsa.tf 等），沒有可複用的邏輯需要抽取成自訂模組，強行建立 `modules/` 子目錄只會增加不必要的間接層 |

### Terraform 核心模組

> 相關檔案：[terraform/](../terraform/)

### Remote State Backend（S3 Native Locking）

> 原始檔案：[terraform/backend.tf](../terraform/backend.tf)

```hcl
terraform {
  backend "s3" {
    bucket       = "eks-obs-tfstate-760033296418"
    key          = "eks-obs/terraform.tfstate"
    region       = "ap-northeast-1"
    use_lockfile = true   # S3-native state locking（Terraform >= 1.11）
    encrypt      = true
  }
}
```

State 儲存於 S3，透過 `use_lockfile = true` 啟用 S3 原生鎖定機制，**不需要額外建立 DynamoDB Table**（Terraform 1.11+ 新功能）。本機與 CI 共用同一份 state，確保 `terraform destroy` 可正確追蹤 CI 建立的資源。

```hcl
# vpc.tf - 使用 terraform-aws-modules
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.5"
  # 3 Public + 3 Private Subnets, 單 NAT
}

# eks.tf
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.8"

  cluster_version = "1.35"
  enable_irsa     = true    # 支援 IRSA

  eks_managed_node_groups = {
    infra = {
      taints = [{ key = "dedicated", value = "infra", effect = "NO_SCHEDULE" }]
    }
    app = {
      taints = [{ key = "dedicated", value = "app", effect = "NO_SCHEDULE" }]
    }
  }
}

# irsa.tf - AWS Load Balancer Controller IRSA
resource "aws_iam_role" "alb_controller" {
  # OIDC 信任 kube-system/aws-load-balancer-controller SA
}
```

### Terraform pipeline 自動化部署

> Pipeline 設定：[.github/workflows/terraform.yml](../.github/workflows/terraform.yml)

> GitHub Actions：https://github.com/yujie70338/terraform-eks-observability-example/actions/workflows/terraform.yml

`terraform/**` 變動觸發：
1. **Lint**：`terraform fmt -check` + `terraform validate`
2. **Security Scan**：Checkov 靜態分析（soft fail）
3. **Plan**：產生變更計畫，自動回覆 PR Comment
4. **Apply**（僅 main push）：透過 OIDC 取得 AWS 臨時憑證後執行

### Terraform 手動部署步驟

```bash
# 1. 建立基礎設施
cd terraform/
terraform init
terraform apply

# 2. 設定 kubectl
aws eks update-kubeconfig --region ap-northeast-1 --name eks-obs-dev

# 3. 安裝 AWS Load Balancer Controller
helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  -f helm/aws-load-balancer-controller/values.yaml \
  -f helm/aws-load-balancer-controller/values.secret.yaml

# 4. 安裝 kube-prometheus-stack（監控）
helm install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  -n monitoring --create-namespace \
  -f helm/monitoring/values.yaml \
  -f helm/monitoring/values.secret.yaml

# 5. 部署應用
helm install static-web helm/static-web -n app --create-namespace
```

### 驗收指令

```bash
# 確認節點 Taint 隔離
kubectl get nodes -o custom-columns=NAME:.metadata.name,TAINTS:.spec.taints

# 確認 Pod 分佈在正確節點
kubectl get pods -o wide -A

# 確認 PDB 生效
kubectl get pdb -n app

# 查看 ALB DNS
kubectl get ingress -n app
```

---

## 4. Grafana 監控 Dashboard

### 部署方式

使用 `kube-prometheus-stack` Helm Chart，包含：
- **Prometheus**：指標收集與儲存
- **Grafana**：視覺化 Dashboard
- **Alertmanager**：告警路由
- **node-exporter**：節點層級指標（CPU/Memory/Disk/Network）
- **kube-state-metrics**：K8s 資源狀態指標

所有監控元件均調度至 **Infra Node Group**（透過 nodeSelector + Tolerations）。

### 資料持久化策略

本專案監控元件（Prometheus、Grafana）**未啟用 PersistentVolume（PV/PVC）**，原因如下：

| 考量 | 說明 |
|------|------|
| 節省成本 | 啟用 PVC 需建立 AWS EBS Volume，會產生額外的 EBS 儲存費用；本專案為驗收用途，不需要跨 Pod 重啟保留歷史指標 |
| 降低複雜度 | `emptyDir` 開箱即用 |
| 驗收時限短 | 指標與 Dashboard 設定僅需在驗收期間存活，Pod 重啟後資料消失不影響驗收目標 |

Prometheus 與 Grafana 均使用 `emptyDir` 作為暫存儲存，資料於 Pod 重啟後清空，屬預期行為。

### Grafana 對外存取

Grafana 透過 ALB Ingress 提供公網存取：

```bash
kubectl get ingress -n monitoring
# NAME                                CLASS   HOSTS   ADDRESS                    PORTS
# kube-prometheus-stack-grafana       alb     *       xxx.ap-northeast-1.elb...  80
```

### Dashboard 截圖

> 本專案未購買網域，以節省成本。無自訂域名即無法申請 TLS 憑證，因此 Grafana 與應用程式均透過 ALB 產生的預設 DNS 以 **HTTP** 存取，截圖中瀏覽器顯示「不安全」屬預期行為。

> 截圖存放於 `docs/screetshots/` 目錄

- **Node Exporter Full Dashboard**：CPU、Memory、Disk I/O、Network 總覽
- **Kubernetes Cluster Overview**：Pod 狀態、Deployment 健康度
- **Namespace 資源使用率**：app / monitoring namespace 的 CPU/Memory 使用量

---

## 5. Alertmanager Telegram 告警

### 設定架構

```
Grafana Alert Rule（Pod CPU > 0 持續觸發）
    │
    ▼ (評估週期到達)
Grafana Alerting
    │
    ▼ (Contact Point: Telegram Bot API)
Telegram Chat
```

### Alert Rule 設定

在 Grafana UI 建立 Alert Rule，以 Pod CPU 使用率為指標，閾值設為 `0`（確保持續觸發以驗證通知流程）：

```promql
sum(rate(container_cpu_usage_seconds_total{
  namespace="app",
  container!=""
}[5m])) by (pod)
```

**條件**：`IS ABOVE 0`

### Contact Point 設定（Telegram）

Grafana → Alerting → Contact Points → New Contact Point：

| 欄位 | 值 |
|------|----|
| Name | `telegram` |
| Type | Telegram |
| BOT API Token | `<TELEGRAM_BOT_TOKEN>` |
| Chat ID | `<CHAT_ID>` |

### 告警截圖

> 截圖存放於 `docs/screetshots/` 目錄

---

## 6. CI/CD Pipeline（加分項）

本專案實作兩條獨立的 GitHub Actions Pipeline。

### Terraform Pipeline（.github/workflows/terraform.yml）

```
PR / Push to main (terraform/**)
    │
    ├─ Lint & Validate ──→ terraform fmt -check + terraform validate
    ├─ Security Scan ────→ Checkov 靜態安全掃描（soft fail）
    ├─ Plan ─────────────→ 產生 Plan，自動回覆 PR Comment
    └─ Apply ────────────→ (僅 main push) 自動套用基礎設施變更
```

### App & Helm Pipeline（.github/workflows/app-helm.yml）

```
PR / Push to main (app/** or helm/static-web/**)
    │
    ├─ Lint & Validate ──→ Hadolint + Helm lint + template dry-run
    ├─ Build & Scan ─────→ Docker buildx (amd64 scan) + Trivy 漏洞掃描
    │                       └─ (main only) multi-platform push to DockerHub
    └─ Deploy ───────────→ (main only) helm upgrade --install + rollout 驗證
```

### OIDC 取得臨時憑證

GitHub Actions 透過 OIDC 向 AWS 取得臨時憑證，**不需要儲存 AWS Access Key**：

```
GitHub Actions JWT
    │
    ▼  AssumeRoleWithWebIdentity
AWS STS
    │
    ▼  Temporary Credentials (1hr)
Terraform / kubectl / helm
```

```hcl
# terraform/oidc-github.tf
resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
}

resource "aws_iam_role" "github_actions" {
  # 信任條件：只信任本 repo
  # token.actions.githubusercontent.com:sub = "repo:yujie70338/...:*"
}
```

> **關於 IAM 權限範圍**：本專案為測試環境，GitHub Actions Role 附加了 `AdministratorAccess` 以避免逐一調試 Terraform 所需的細粒度權限。生產環境應依照最小權限原則（Least Privilege），僅授予 Terraform 實際操作所需的 IAM 權限（如 EC2、EKS、VPC、IAM 的限定操作）。

### Image Tag 策略

| 情境 | Tag |
|------|-----|
| 每次 build | `yujie70338/static-web:<git-sha-7碼>` |
| merge to main | 同上 + `yujie70338/static-web:latest` |

使用 git SHA 作為 tag 確保每個版本可追溯，並透過 Helm `--set image.tag=<sha>` 注入到部署。

---