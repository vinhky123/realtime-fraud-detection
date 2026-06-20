# Lộ trình học Terraform — Fraud Detection Project

> Học theo dự án thực tế. Không học lý thuyết suông.
> Target: viết được toàn bộ infra Phase 1 của project bằng Terraform.

---

## Tại sao học Terraform theo hướng này?

Mày đã có sẵn:
- Một project thực với AWS infra cụ thể (VPC, DynamoDB, S3, IAM, Glue)
- Terraform module structure đã định sẵn (`modules/compute`, `networking`, `storage`, `iam`)
- Mục tiêu rõ ràng (Phase 1 deliverables)

Học Terraform theo lý thuyết → nhàm, quên ngay. Học bằng cách build infra của project này → vừa học vừa làm xong việc.

---

## Cách tư duy khi viết Terraform

> Đây là phần quan trọng nhất. Hiểu được tư duy này thì mọi thứ còn lại tự khắc rõ.

### Mental model: Terraform là "compiler" cho infrastructure

Cách nghĩ đúng:
- **Code của mày** = bản mô tả trạng thái mày muốn ("desired state")
- **State file** = bản ghi trạng thái hiện tại ("current state")
- **`terraform apply`** = Terraform tính delta → gọi AWS API để đưa current → desired

```
Mày viết:                    Terraform làm:
"tôi muốn S3 bucket          → aws s3api create-bucket ...
 tên fraud-lake-dev"         → lưu vào .tfstate

Mày sửa thành:               Terraform làm:
"tôi muốn versioning=on"     → aws s3api put-bucket-versioning ...
                             → update .tfstate

Mày xóa resource:            Terraform làm:
(remove khỏi .tf file)       → aws s3api delete-bucket ...
                             → xóa khỏi .tfstate
```

**Rule #1:** Không bao giờ sửa tay trên AWS Console khi đã dùng Terraform.
Nếu sửa tay → state drift → Terraform không biết → `plan` sẽ nói "phải xóa cái mày vừa tạo".

---

### Cách tư duy cấu trúc folder

**Câu hỏi đặt ra:** Khi nào tách thành module riêng? Khi nào để chung?

**Nguyên tắc:** Module = một nhóm resources có thể **deploy độc lập** và **tái sử dụng**.

```
Nên tách module khi:                    Không cần tách khi:
✅ Có thể dùng lại ở env khác          ❌ Chỉ dùng 1 lần, không bao giờ đổi
✅ Nhóm logic riêng biệt               ❌ Chỉ có 1-2 resources đơn giản
✅ Team khác nhau own                  ❌ Luôn deploy cùng nhau
✅ Thay đổi độc lập với nhau
```

**Cấu trúc folder chuẩn cho project này:**

```
infra/terraform/
│
├── modules/                    ← "Thư viện" — reusable, không có AWS creds ở đây
│   ├── networking/             ← VPC, subnets, SGs, IGW, NAT
│   ├── storage/                ← S3, DynamoDB, Glue
│   ├── iam/                    ← Users, Roles, Policies
│   └── compute/                ← ECS, ALB, EC2, Route53
│
└── environments/               ← "Entry point" — nơi thực sự gọi modules
    ├── dev/                    ← terraform init/apply chạy ở đây
    │   ├── main.tf             ← Gọi modules + truyền config cụ thể
    │   ├── variables.tf        ← Khai báo vars cho env này
    │   ├── terraform.tfvars    ← Giá trị thực (không commit file nhạy cảm)
    │   ├── outputs.tf          ← Export ra để dùng sau
    │   ├── backend.tf          ← Remote state config
    │   └── locals.tf           ← Computed values dùng chung trong env
    └── prod/
        └── ... (cấu trúc y chang dev, values khác)
```

**Tư duy phân tầng:**
```
environments/dev/    ← Tầng 1: "Tôi muốn infra dev trông như thế này"
      ↓ gọi
modules/storage/     ← Tầng 2: "Đây là cách tạo storage"
      ↓ tạo
AWS Resources        ← Tầng 3: S3 bucket, DynamoDB table thực tế
```

---

### Cách truyền biến (Variables)

Có **3 loại variables** với mục đích khác nhau:

#### Loại 1: `variable` — Input từ ngoài vào module

```hcl
# modules/storage/variables.tf
variable "bucket_name" {
  description = "Tên S3 bucket"   # Luôn viết description
  type        = string             # Luôn khai báo type
  # Không có default → bắt buộc phải truyền vào
}

variable "enable_versioning" {
  type    = bool
  default = true                   # Có default → optional, dùng được nếu không truyền
}

variable "tags" {
  type    = map(string)            # map = key-value pairs
  default = {}
}
```

**Các types hay dùng:**
```hcl
type = string           # "fraud-lake-dev"
type = number           # 3
type = bool             # true / false
type = list(string)     # ["ap-southeast-1a", "ap-southeast-1b"]
type = map(string)      # { Environment = "dev", Project = "fraud" }
type = object({         # Structured object
  cidr = string
  az   = string
})
```

#### Loại 2: `local` — Computed values trong nội bộ file/module

```hcl
# environments/dev/locals.tf
locals {
  env     = "dev"
  project = "fraud-detection"
  region  = "ap-southeast-1"

  # Computed từ locals khác
  name_prefix = "${local.project}-${local.env}"   # "fraud-detection-dev"

  # Tags dùng chung cho toàn bộ env — không cần repeat ở mọi module call
  common_tags = {
    Environment = local.env
    Project     = local.project
    ManagedBy   = "terraform"
  }
}
```

> **Dùng `local` khi:** Giá trị lặp lại nhiều lần, hoặc cần tính toán từ values khác.
> **Dùng `variable` khi:** Giá trị cần người dùng/CI truyền vào từ ngoài.

#### Loại 3: `terraform.tfvars` — Giá trị thực tế cho environment

```hcl
# environments/dev/terraform.tfvars
# File này KHÔNG commit nếu có credentials nhạy cảm
aws_region  = "ap-southeast-1"
bucket_name = "fraud-lake-dev"
```

**Thứ tự ưu tiên khi Terraform resolve variable value (cao → thấp):**
```
1. -var flag:         terraform apply -var="bucket_name=xyz"
2. .tfvars file:      terraform.tfvars hoặc *.auto.tfvars
3. Environment vars:  TF_VAR_bucket_name=xyz
4. default value:     default = "..."
5. Terraform hỏi:     (interactive prompt nếu không có gì cả)
```

---

### Cách export và truyền giữa các modules

Đây là flow quan trọng nhất — hiểu cái này là hiểu 80% Terraform:

```
Module A tạo resource
    → khai báo output
    → Environment gọi module A
    → lấy output bằng module.A.output_name
    → truyền vào Module B qua variable
```

**Ví dụ thực tế trong project:**

**Bước 1:** Module storage tạo S3, khai báo output ARN
```hcl
# modules/storage/outputs.tf
output "bucket_arn" {
  description = "ARN của S3 bucket — dùng để gán IAM policy"
  value       = aws_s3_bucket.fraud_lake.arn
  # arn:aws:s3:::fraud-lake-dev  ← đây là giá trị thực
}

output "dynamodb_table_arn" {
  value = aws_dynamodb_table.user_features.arn
}
```

**Bước 2:** Module IAM khai báo variable để nhận ARN
```hcl
# modules/iam/variables.tf
variable "s3_bucket_arn" {
  description = "ARN của S3 bucket để gán vào IAM policy"
  type        = string
}

variable "dynamodb_table_arn" {
  type = string
}
```

**Bước 3:** Environment wiring — nơi hai modules "gặp nhau"
```hcl
# environments/dev/main.tf

# Gọi storage trước
module "storage" {
  source = "../../modules/storage"

  bucket_name = "${local.name_prefix}-lake"   # "fraud-detection-dev-lake"
  tags        = local.common_tags
}

# Gọi IAM sau, truyền output của storage vào
module "iam" {
  source = "../../modules/iam"

  # module.storage.bucket_arn → lấy output "bucket_arn" từ module "storage"
  s3_bucket_arn      = module.storage.bucket_arn
  dynamodb_table_arn = module.storage.dynamodb_table_arn
  tags               = local.common_tags
}
```

**Terraform tự hiểu dependency:** Vì `module.iam` dùng output của `module.storage`,
Terraform sẽ tự apply `storage` trước, rồi mới apply `iam`.

---

### Visualize full data flow

```
environments/dev/locals.tf
  local.common_tags = { Environment="dev", Project="fraud-detection" }
  local.name_prefix = "fraud-detection-dev"
         │
         ▼
environments/dev/main.tf
  module "storage" {
    bucket_name = "fraud-detection-dev-lake"  ← hardcoded ở đây
    tags        = local.common_tags           ← từ locals
  }
         │ truyền variable vào
         ▼
modules/storage/variables.tf        modules/storage/main.tf
  variable "bucket_name"    ─────►  resource "aws_s3_bucket" "fraud_lake" {
  variable "tags"                     bucket = var.bucket_name
                                      tags   = var.tags
                                    }
                                         │ tạo ra
                                         ▼
                                    AWS: S3 bucket "fraud-detection-dev-lake"
                                         │
                                         │ attribute: .arn
                                         ▼
modules/storage/outputs.tf
  output "bucket_arn" {
    value = aws_s3_bucket.fraud_lake.arn   ← "arn:aws:s3:::fraud-detection-dev-lake"
  }
         │ export ra ngoài
         ▼
environments/dev/main.tf
  module "iam" {
    s3_bucket_arn = module.storage.bucket_arn   ← nhận output từ storage
  }
         │ truyền variable vào
         ▼
modules/iam/variables.tf        modules/iam/main.tf
  variable "s3_bucket_arn" ──► resource "aws_iam_user_policy" {
                                 policy = jsonencode({
                                   Resource = var.s3_bucket_arn
                                 })
                               }
```

---

### Quy tắc vàng khi thiết kế modules

**1. Module không biết environment của nó**
```hcl
# ❌ Sai — module hardcode "dev"
resource "aws_s3_bucket" "main" {
  bucket = "fraud-lake-dev"   # Vậy prod thì sao?
}

# ✅ Đúng — nhận từ variable
resource "aws_s3_bucket" "main" {
  bucket = var.bucket_name    # Caller quyết định tên
}
```

**2. Output mọi thứ mà caller có thể cần**
```hcl
# ✅ Output cả ID lẫn ARN — caller tự chọn dùng cái nào
output "bucket_id"   { value = aws_s3_bucket.main.id }
output "bucket_arn"  { value = aws_s3_bucket.main.arn }
output "bucket_name" { value = aws_s3_bucket.main.bucket }
```

**3. Tags luôn là variable, không bao giờ hardcode**
```hcl
# ✅ Tags từ caller, merge với tags riêng của module nếu cần
variable "tags" {
  type    = map(string)
  default = {}
}

resource "aws_s3_bucket" "main" {
  tags = merge(var.tags, {
    Module = "storage"    # Tag thêm vào nếu muốn track module source
  })
}
```

**4. Không dùng AWS creds trong module — chỉ trong environment**
```hcl
# environments/dev/versions.tf  ← provider chỉ khai báo ở đây
provider "aws" {
  region = local.region
}
```

---

## Giai đoạn 1 — Terraform Fundamentals (2–3 ngày)

### 1.1 Cài đặt & cấu hình

```bash
# Cài terraform (Windows - dùng chocolatey)
choco install terraform

# Hoặc download binary từ hashicorp.com

# Cài AWS CLI
choco install awscli

# Cấu hình credentials
aws configure
# → nhập AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, region: ap-southeast-1
```

### 1.2 Các khái niệm cốt lõi cần hiểu

| Khái niệm | Hiểu ngắn gọn |
|---|---|
| **Provider** | Plugin kết nối Terraform với AWS (hoặc GCP, Azure...) |
| **Resource** | Một tài nguyên AWS cụ thể: `aws_vpc`, `aws_s3_bucket`... |
| **State** | File `.tfstate` — Terraform lưu "trạng thái thực tế" của infra |
| **Plan** | `terraform plan` — xem Terraform sẽ làm gì (chưa thực hiện) |
| **Apply** | `terraform apply` — thực sự tạo/sửa/xóa resources |
| **Module** | Nhóm resources có thể tái sử dụng (như functions trong code) |
| **Variable** | Input cho module/config, tránh hardcode |
| **Output** | Giá trị export ra để dùng ở chỗ khác (VPC ID, Subnet ID...) |
| **Data Source** | Đọc resource đã tồn tại, không tạo mới |
| **Remote State** | Lưu `.tfstate` trên S3 thay vì local (quan trọng cho team) |

### 1.3 Cấu trúc file Terraform cơ bản

```
module/
├── main.tf        # Resources chính
├── variables.tf   # Khai báo input variables
├── outputs.tf     # Khai báo outputs
└── versions.tf    # Provider + Terraform version constraints
```

### 1.4 Workflow cơ bản

```bash
terraform init      # Download providers, khởi tạo backend
terraform fmt       # Format code
terraform validate  # Kiểm tra syntax
terraform plan      # Preview changes
terraform apply     # Áp dụng changes
terraform destroy   # Xóa toàn bộ resources
```

---

## Giai đoạn 2 — Viết Module đầu tiên: S3 + DynamoDB (2 ngày)

> Bắt đầu với storage vì đây là thứ đơn giản nhất và Phase 1 cần ngay.

### 2.1 Module Storage (`infra/terraform/modules/storage/`)

**`main.tf`** — S3 bucket:
```hcl
resource "aws_s3_bucket" "fraud_lake" {
  bucket = var.bucket_name
  tags   = var.tags
}

resource "aws_s3_bucket_versioning" "fraud_lake" {
  bucket = aws_s3_bucket.fraud_lake.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_dynamodb_table" "user_features" {
  name         = var.dynamodb_table_name
  billing_mode = "PAY_PER_REQUEST"  # On-demand, không cần capacity planning
  hash_key     = "user_id"

  attribute {
    name = "user_id"
    type = "S"  # String
  }

  tags = var.tags
}
```

**`variables.tf`**:
```hcl
variable "bucket_name" {
  description = "S3 bucket name for the data lake"
  type        = string
}

variable "dynamodb_table_name" {
  description = "DynamoDB table name for user features"
  type        = string
  default     = "user_features_v1"
}

variable "tags" {
  description = "Common tags"
  type        = map(string)
  default     = {}
}
```

**`outputs.tf`**:
```hcl
output "bucket_name" {
  value = aws_s3_bucket.fraud_lake.bucket
}

output "bucket_arn" {
  value = aws_s3_bucket.fraud_lake.arn
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.user_features.name
}

output "dynamodb_table_arn" {
  value = aws_dynamodb_table.user_features.arn
}
```

**Bài học từ module này:**
- `var.xxx` = dùng variable
- `resource_type.resource_name.attribute` = reference output của resource khác
- `billing_mode = "PAY_PER_REQUEST"` = on-demand (không cần tính throughput)

---

## Giai đoạn 3 — Module Networking: VPC (2 ngày)

> Đây là module phức tạp nhất, nhưng là nền tảng của mọi thứ.

### 3.1 Hiểu VPC architecture của project

```
VPC (10.0.0.0/16)
├── Public Subnet A  (10.0.1.0/24) — ap-southeast-1a  → ALB, EC2 Relay
├── Public Subnet B  (10.0.2.0/24) — ap-southeast-1b  → ALB (HA)
├── Private Subnet A (10.0.3.0/24) — ap-southeast-1a  → ECS Fargate
└── Private Subnet B (10.0.4.0/24) — ap-southeast-1b  → ECS Fargate (HA)
```

### 3.2 Concept quan trọng: `for_each` và `count`

```hcl
# Tạo nhiều subnets không cần copy-paste
variable "public_subnets" {
  default = {
    "subnet-a" = { cidr = "10.0.1.0/24", az = "ap-southeast-1a" }
    "subnet-b" = { cidr = "10.0.2.0/24", az = "ap-southeast-1b" }
  }
}

resource "aws_subnet" "public" {
  for_each          = var.public_subnets
  vpc_id            = aws_vpc.main.id
  cidr_block        = each.value.cidr
  availability_zone = each.value.az

  tags = { Name = "public-${each.key}" }
}
```

### 3.3 Concept quan trọng: Dependencies ngầm

```hcl
# Terraform tự hiểu resource này cần VPC → tạo VPC trước
resource "aws_subnet" "public" {
  vpc_id = aws_vpc.main.id  # ← implicit dependency
  ...
}

# Đôi khi cần explicit dependency
resource "aws_internet_gateway_attachment" "main" {
  depends_on = [aws_vpc.main]  # ← explicit
  ...
}
```

---

## Giai đoạn 4 — Module IAM (1 ngày)

> Đây là module quan trọng về security, cần hiểu IAM policy syntax.

### 4.1 IAM User cho Flink local (`flink-local`)

```hcl
resource "aws_iam_user" "flink_local" {
  name = "flink-local"
  tags = var.tags
}

resource "aws_iam_access_key" "flink_local" {
  user = aws_iam_user.flink_local.name
}

resource "aws_iam_user_policy" "flink_local" {
  name = "flink-local-policy"
  user = aws_iam_user.flink_local.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:PutObject", "s3:GetObject"]
        Resource = "${var.s3_bucket_arn}/raw/*"
      },
      {
        Effect   = "Allow"
        Action   = ["dynamodb:PutItem", "dynamodb:GetItem", "dynamodb:UpdateItem"]
        Resource = var.dynamodb_table_arn
      }
    ]
  })
}

# Output credentials (sensitive)
output "flink_access_key_id" {
  value     = aws_iam_access_key.flink_local.id
  sensitive = true
}

output "flink_secret_access_key" {
  value     = aws_iam_access_key.flink_local.secret
  sensitive = true
}
```

**Bài học từ module này:**
- `jsonencode()` = convert HCL map → JSON string (dùng cho IAM policies)
- `sensitive = true` = ẩn giá trị trong terraform output
- Module nhận input ARN từ module storage (cross-module dependency)

---

## Giai đoạn 5 — Environments & Remote State (1 ngày)

### 5.1 Cấu trúc environment

```
infra/terraform/
├── modules/
│   ├── storage/
│   ├── networking/
│   ├── iam/
│   └── compute/
└── environments/
    └── dev/
        ├── main.tf         ← Gọi các modules
        ├── variables.tf
        ├── outputs.tf
        └── backend.tf      ← Remote state config
```

### 5.2 Remote State (S3 backend)

> QUAN TRỌNG: Không bao giờ commit `.tfstate` vào git. Dùng S3 backend.

**`backend.tf`** — tạo thủ công bucket này trước (bootstrap):
```hcl
terraform {
  backend "s3" {
    bucket         = "fraud-terraform-state-dev"
    key            = "dev/terraform.tfstate"
    region         = "ap-southeast-1"
    dynamodb_table = "terraform-state-lock"  # Chống concurrent apply
    encrypt        = true
  }
}
```

### 5.3 Gọi modules trong `environments/dev/main.tf`

```hcl
module "storage" {
  source = "../../modules/storage"

  bucket_name         = "fraud-lake-dev"
  dynamodb_table_name = "user_features_v1"
  tags = {
    Environment = "dev"
    Project     = "fraud-detection"
  }
}

module "iam" {
  source = "../../modules/iam"

  s3_bucket_arn      = module.storage.bucket_arn
  dynamodb_table_arn = module.storage.dynamodb_table_arn
  tags               = local.common_tags
}

module "networking" {
  source = "../../modules/networking"

  vpc_cidr = "10.0.0.0/16"
  env      = "dev"
  tags     = local.common_tags
}
```

**Bài học:**
- `module.storage.bucket_arn` = lấy output từ module khác
- `local.xxx` = local values (tính toán một lần, dùng nhiều chỗ)
- Thứ tự apply: Terraform tự tính dựa trên dependencies

---

## Thứ tự học & làm (Timeline thực tế)

```
Tuần 1:
  Ngày 1-2: Đọc fundamentals (1.1 → 1.4), cài tool, chạy hello-world AWS
  Ngày 3-4: Viết module storage/ → apply S3 + DynamoDB thật lên AWS
  Ngày 5:   Viết module iam/ → tạo flink-local user

Tuần 2:
  Ngày 1-2: Viết module networking/ → VPC, subnets, security groups
  Ngày 3:   Setup remote state (S3 backend)
  Ngày 4-5: Wire environments/dev/main.tf → gọi tất cả modules
             terraform plan → review → terraform apply
             Verify: S3 bucket, DynamoDB table, VPC tồn tại trên AWS Console
```

---

## Resources để tra cứu

| Resource | Link |
|---|---|
| Terraform Docs (official) | https://developer.hashicorp.com/terraform/docs |
| AWS Provider Docs | https://registry.terraform.io/providers/hashicorp/aws/latest/docs |
| Terraform Best Practices | https://www.terraform-best-practices.com/ |

> **Tip:** Khi cần tạo bất kỳ resource AWS nào, Google `terraform aws_<resource>` → vào registry.terraform.io → copy example → tùy chỉnh theo nhu cầu.

---

## Lỗi hay gặp khi mới học

| Lỗi | Nguyên nhân | Fix |
|---|---|---|
| `Error: Provider not configured` | Chưa chạy `terraform init` | `terraform init` |
| `Error: Invalid reference` | Sai tên module/resource | Kiểm tra `module.xxx.output_name` |
| `Error: Cycle detected` | Hai resources depend lẫn nhau | Dùng `depends_on` hoặc tách module |
| State drift | Sửa tay trên AWS Console | `terraform refresh` hoặc `terraform import` |
| `.tfstate` conflict | Hai người apply cùng lúc | Dùng DynamoDB state lock |

---

## Next Steps sau khi xong Phase 1 infra

Sau khi viết xong modules cho Phase 1, mày sẽ tự học được:
- `aws_ecs_cluster`, `aws_ecs_task_definition` (Phase 4 — Backend ECS)
- `aws_lb`, `aws_lb_listener` (Phase 4 — ALB)
- `aws_glue_catalog_database`, `aws_glue_crawler` (Phase 3 — Glue)
- `aws_route53_record` (Phase 4 — DNS)

Pattern luôn giống nhau: tìm resource trong docs → copy example → tuỳ chỉnh.
