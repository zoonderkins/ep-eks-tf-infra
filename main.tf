data "aws_availability_zones" "available" {}


data "aws_eks_cluster_auth" "main" {
  # 作用: 獲取 EKS 叢集的認證資訊
  name = module.eks.cluster_name
}

# Configure Kubernetes provider
provider "kubernetes" {
  # 作用: 配置 Kubernetes 提供者
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  token                  = data.aws_eks_cluster_auth.main.token
}

# Configure Helm provider
provider "helm" {
  # 作用: 配置 Helm 提供者 
  # cluster_ca_certificate: 使用 base64 解碼後的 CA 憑證
  # token: 使用 data.aws_eks_cluster_auth.main.token 獲取的認證令牌
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
    token                  = data.aws_eks_cluster_auth.main.token
  }
}

locals {
  cluster_name           = "ep-k8s-101-eks-demo-edward"
  region                 = "us-east-1"
  cluster_version        = "1.32"
  cluster_upgrade_policy = "STANDARD" # 集群升級策略

  ami_type_AL2023 = "AL2023_x86_64_STANDARD"

  volume_size = 30
  volume_type = "gp3"

  instance_types = [
    "t3.medium",
  ]

  min_size     = 1
  max_size     = 1
  desired_size = 1

  # 作用: 獲取可用區列表
  azs = slice(data.aws_availability_zones.available.names, 0, 2)

  vpc_cidr = "10.0.0.0/16"

  cluster_ip_family         = "ipv4"
  cluster_service_ipv4_cidr = "10.100.0.0/16"

  tags = {
    Terraform = true
  }
}

module "eks" {

  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.37"

  cluster_name    = local.cluster_name
  cluster_version = local.cluster_version

  cluster_endpoint_private_access = true
  cluster_endpoint_public_access  = true

  # 常見的認證模式
  ## API_AND_CONFIG_MAP

  authentication_mode                      = "API_AND_CONFIG_MAP"

  # 作用: 啟用集群創建者管理員權限
  enable_cluster_creator_admin_permissions = true

  cluster_addons = {
    kube-proxy = {
      most_recent       = true
      resolve_conflicts = "OVERWRITE"
    }
    coredns = {
      most_recent       = true
      resolve_conflicts = "OVERWRITE"
    }
    vpc-cni = {
      most_recent       = true
      before_compute    = true
      resolve_conflicts = "OVERWRITE"
    }
    eks-pod-identity-agent = {
      most_recent       = true
      before_compute    = true
      resolve_conflicts = "OVERWRITE"
    }
  }

  node_security_group_additional_rules = {
    egress_all = {
      description      = "Node all egress"
      protocol         = "-1"
      from_port        = 0
      to_port          = 0
      type             = "egress"
      cidr_blocks      = ["0.0.0.0/0"]
      ipv6_cidr_blocks = ["::/0"]
    }
  }

  cluster_upgrade_policy = {
    support_type = local.cluster_upgrade_policy
  }

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  cluster_ip_family         = local.cluster_ip_family
  cluster_service_ipv4_cidr = local.cluster_service_ipv4_cidr

  eks_managed_node_group_defaults = {
    ami_type       = local.ami_type_AL2023
    instance_types = local.instance_types

    use_name_prefix = false

    min_size = local.min_size
    max_size = local.max_size
    # This value is ignored after the initial creation
    # https://github.com/bryantbiggs/eks-desired-size-hack
    desired_size = local.desired_size

    use_latest_ami_release_version = true

    capacity_type = "ON_DEMAND" # or SPOT

    block_device_mappings = {
      xvda = {
        device_name = "/dev/xvda"
        ebs = {
          volume_size           = local.volume_size
          volume_type           = local.volume_type
          delete_on_termination = true
        }
      }
    }

    # 我們使用下面的 IRSA 來管理權限
    # 但是，我們必須在創建集群時先部署這個策略（當創建一個新的集群時）
    # 然後在集群/節點組創建後關閉它。沒有這個初始策略，
    # VPC CNI 無法分配 IP 地址，節點無法加入集群
    # 更多詳情請參考 https://github.com/aws/containers-roadmap/issues/1666
    iam_role_attach_cni_policy = true
  }

  eks_managed_node_groups = {
    al2023-mng1 = {
      ami_type = local.ami_type_AL2023
    }
  }

  tags = local.tags
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.21.0"

  name = local.cluster_name
  cidr = local.vpc_cidr

  azs = local.azs
  private_subnets = [
    cidrsubnet(local.vpc_cidr, 8, 10),
    cidrsubnet(local.vpc_cidr, 8, 20),
  ]
  public_subnets = [
    cidrsubnet(local.vpc_cidr, 8, 30),
    cidrsubnet(local.vpc_cidr, 8, 40),
  ]

  enable_nat_gateway   = true
  single_nat_gateway   = true # 單一 NAT
  enable_dns_hostnames = true

  public_subnet_tags = {
    "kubernetes.io/role/elb" = 1
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = 1
  }

  tags = local.tags
}
