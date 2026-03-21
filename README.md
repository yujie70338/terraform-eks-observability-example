# terraform-eks-observability-example

> 以 Terraform 與 Helm 為核心，在 AWS 上建立具備完整可觀測性與節點隔離的 EKS 生產環境範例。

---

## 目錄

- [專案概覽](#專案概覽)
- [系統架構](#系統架構)
- [技術棧](#技術棧)
- [目錄結構](#目錄結構)
- [前置需求](#前置需求)
- [快速開始](#快速開始)
- [驗收指令](#驗收指令)
- [成果截圖](#成果截圖)
- [資源回收](#資源回收)

---

## 專案概覽

本專案示範如何在 AWS 環境下，透過 Infrastructure as Code (IaC) 一鍵部署一個高可用、可觀測且具備強健隔離機制的 EKS 叢集。

**核心驗收標準：**

| 項目 | 說明 |
|------|------|
| 基礎設施 | Terraform 自動化建立 VPC、EKS、Node Groups、IAM |
| 資源隔離 | App Pod 與監控 Pod 物理隔離於不同 Taint 節點 |
| 高可用性 | PDB 確保維護期間至少 10% 服務可用 |
| 可觀測性 | 公網存取 Grafana Dashboard，接收 Telegram 告警 |
| 安全性 | 非 Root 執行、PSS Baseline、EBS 全磁碟加密 |

---

## 系統架構

```
Internet
    │
    ▼
[ALB - internet-facing]
    │  (IP Mode)
    ├──────────────────────┐
    ▼                      ▼
[App Nodes - t3.small]  [Infra Nodes - t3.medium]
 Taint: dedicated=app    Taint: dedicated=infra
    │                      │
[static-web Pods]       [Prometheus / Grafana / Alertmanager]
```

**網路分層：**
- **Public Subnets (3 AZ)**：放置 ALB
- **Private Subnets (3 AZ)**：放置 EKS 節點（透過單一 NAT Gateway 對外）

**節點隔離策略：**

| Node Group | 機型 | Taint | Label | 用途 |
|-----------|------|-------|-------|------|
| infra | t3.medium | `dedicated=infra:NoSchedule` | `role=infra` | 監控、ALB Controller |
| app | t3.small | `dedicated=app:NoSchedule` | `role=app` | 業務應用 |

---

## 技術棧

| 類別 | 工具 |
|------|------|
| 基礎設施 | Terraform >= 1.5、AWS Provider ~> 5.40 |
| 容器平台 | Amazon EKS v1.32 |
| 流量調度 | AWS Load Balancer Controller（ALB IP Mode）|
| 應用容器 | nginx:alpine、multi-platform image（amd64/arm64）|
| 監控 | kube-prometheus-stack（Prometheus + Grafana + Alertmanager）|
| 告警 | Alertmanager + Telegram Bot |
| CI/CD | GitHub Actions |

---

## 目錄結構

```
.
├── app/
│   ├── Dockerfile          # 多平台 multi-stage build，非 Root 安全設定
│   └── index.html          # 靜態網頁原始碼
├── helm/
│   ├── aws-load-balancer-controller/
│   │   └── values.yaml     # ALB Controller Helm 配置
│   ├── monitoring/
│   │   └── values.yaml     # kube-prometheus-stack 配置（Tolerations、Telegram 告警）
│   └── static-web/
│       ├── Chart.yaml
│       ├── values.yaml
│       └── templates/
│           ├── deployment.yaml   # Tolerations、PSS securityContext
│           ├── ingress.yaml      # ALB internet-facing, IP mode
│           ├── namespace.yaml    # PSS Baseline label
│           ├── pdb.yaml          # minAvailable: 10%
│           └── service.yaml      # ClusterIP
├── terraform/
│   ├── versions.tf         # Provider 版本鎖定
│   ├── providers.tf        # AWS / K8s / Helm Provider
│   ├── backend.tf          # S3 Remote State（預留，本次建置 .tfstate 存在地端）
│   ├── variables.tf        # 變數定義
│   ├── locals.tf           # cluster_name、common_tags、Subnet CIDR
│   ├── data.tf             # 動態資料（AZs）
│   ├── vpc.tf              # 3 Public + 3 Private Subnets、單 NAT
│   ├── eks.tf              # EKS v1.32、CoreDNS Tolerations、Node Groups
│   ├── irsa.tf             # ALB Controller + Prometheus IRSA
│   ├── outputs.tf          # 環境資訊的 output 輸出
│   └── policies/
│       └── alb-controller-policy.json
└── docs/
    └── screenshots/        # 驗收截圖
```

---

## 前置需求

- AWS CLI（已設定具備足夠權限的 credentials）
- Terraform >= 1.5
- kubectl
- Helm >= 3
- Docker（含 buildx 支援）

---

## 快速開始

### Step 1：建立基礎設施

```bash
cd terraform/

# 複製並填入實際參數
cp terraform.tfvars.example terraform.tfvars  # 依需求調整

terraform init
terraform apply
```

建立完成後設定 kubectl：

```bash
aws eks update-kubeconfig --region ap-northeast-1 --name eks-obs-dev
kubectl get nodes
```

### Step 2：安裝 AWS Load Balancer Controller

```bash
helm repo add eks https://aws.github.io/eks-charts && helm repo update

# 填入 IAM Role ARN
cp helm/aws-load-balancer-controller/values.secret.yaml.example \
   helm/aws-load-balancer-controller/values.secret.yaml
# 編輯 values.secret.yaml，填入 terraform output -raw alb_controller_role_arn

helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  -f helm/aws-load-balancer-controller/values.yaml \
  -f helm/aws-load-balancer-controller/values.secret.yaml
```

### Step 3：安裝 kube-prometheus-stack

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# 填入 Telegram Bot Token 與 Chat ID
cp helm/monitoring/values.secret.yaml.example helm/monitoring/values.secret.yaml
# 編輯 values.secret.yaml

helm install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  -n monitoring --create-namespace \
  -f helm/monitoring/values.yaml \
  -f helm/monitoring/values.secret.yaml
```

### Step 4：部署靜態網頁應用

```bash
helm install static-web helm/static-web -n app --create-namespace
```

---

## 驗收指令

```bash
# 確認節點 Taint 設定
kubectl get nodes -o custom-columns=NAME:.metadata.name,TAINTS:.spec.taints

# 確認 Pod 依隔離原則分佈在正確節點
kubectl get pods -o wide -A

# 確認 PDB 生效
kubectl get pdb -n app

# 取得應用 ALB DNS
kubectl get ingress -n app

# 取得 Grafana ALB DNS
kubectl get ingress -n monitoring
```

---

## 環境清理

驗收完成後執行以下指令避免產生額外費用：

```bash
helm uninstall static-web -n app
helm uninstall kube-prometheus-stack -n monitoring
helm uninstall aws-load-balancer-controller -n kube-system

cd terraform/
terraform destroy
```

