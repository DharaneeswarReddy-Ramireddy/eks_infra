provider "aws" {
  region = "us-west-2"
}

# Fetch Default VPC
data "aws_vpc" "default" {
  default = true
}

# Fetch All Public Subnets in Default VPC
data "aws_subnets" "public_subnets" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }

  filter {
    name   = "map-public-ip-on-launch"
    values = ["true"]
  }
}

# Create EKS Cluster
resource "aws_eks_cluster" "example" {
  name     = "dharan-eks-cluster"
  role_arn = "arn:aws:iam::866934333672:role/dharan-eks"

  vpc_config {
    subnet_ids              = data.aws_subnets.public_subnets.ids
    endpoint_public_access  = true
    endpoint_private_access = false
  }
}

# Node Group
resource "aws_eks_node_group" "default" {
  cluster_name    = aws_eks_cluster.example.name
  node_group_name = "default-node-group"
  node_role_arn   = "arn:aws:iam::866934333672:role/dharan-node-group"

  subnet_ids = data.aws_subnets.public_subnets.ids

  scaling_config {
    desired_size = 2
    max_size     = 2
    min_size     = 2
  }

  instance_types = ["t2.medium"]

  depends_on = [kubernetes_config_map.aws_auth]
}

# Fetch EKS Cluster Auth Token
data "aws_eks_cluster_auth" "example" {
  name = aws_eks_cluster.example.name
}

# Kubernetes Provider
provider "kubernetes" {
  host                   = aws_eks_cluster.example.endpoint
  cluster_ca_certificate = base64decode(aws_eks_cluster.example.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.example.token
}

# Automate aws-auth ConfigMap
resource "kubernetes_config_map" "aws_auth" {
  metadata {
    name      = "aws-auth"
    namespace = "kube-system"
  }

  data = {
    mapRoles = <<EOT
    - rolearn: arn:aws:iam::866934333672:role/dharan-node-group
      username: system:node:{{EC2PrivateDNSName}}
      groups:
        - system:bootstrappers
        - system:nodes
    - rolearn: arn:aws:iam::866934333672:role/dharan-eks
      username: admin
      groups:
        - system:masters
    EOT
    mapUsers = <<EOT
    - userarn: arn:aws:iam::866934333672:user/Dharan
      username: admin
      groups:
        - system:masters
    EOT
  }

  depends_on = [aws_eks_cluster.example]
}

# Add-ons
resource "aws_eks_addon" "coredns" {
  cluster_name  = aws_eks_cluster.example.name
  addon_name    = "coredns"
  addon_version = "v1.11.3-eksbuild.1"

  depends_on = [aws_eks_cluster.example]
}

resource "aws_eks_addon" "kube_proxy" {
  cluster_name  = aws_eks_cluster.example.name
  addon_name    = "kube-proxy"
  addon_version = "v1.31.2-eksbuild.3"

  depends_on = [aws_eks_cluster.example]
}

resource "aws_eks_addon" "vpc_cni" {
  cluster_name  = aws_eks_cluster.example.name
  addon_name    = "vpc-cni"
  addon_version = "v1.19.0-eksbuild.1"

  depends_on = [aws_eks_cluster.example]
}

resource "aws_eks_addon" "pod_identity_agent" {
  cluster_name  = aws_eks_cluster.example.name
  addon_name    = "eks-pod-identity-agent"
  addon_version = "v1.3.4-eksbuild.1"

  depends_on = [aws_eks_cluster.example]
}

resource "aws_eks_addon" "ebs_csi" {
  cluster_name  = aws_eks_cluster.example.name
  addon_name    = "aws-ebs-csi-driver"
  addon_version = "v1.37.0-eksbuild.1"

  depends_on = [aws_eks_cluster.example]
}

# Outputs
output "eks_cluster_endpoint" {
  value = aws_eks_cluster.example.endpoint
}

output "eks_cluster_certificate_authority" {
  value = aws_eks_cluster.example.certificate_authority[0].data
}

output "eks_cluster_arn" {
  value = aws_eks_cluster.example.arn
}

output "node_group_role_arn" {
  value = aws_eks_node_group.default.node_role_arn
}

output "node_group_instance_types" {
  value = aws_eks_node_group.default.instance_types
}
