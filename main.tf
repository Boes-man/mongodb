provider "aws" {
  region = "ap-southeast-2"
}

locals {
  cluster_name = "aws-eks-test"
}

data "aws_eks_cluster" "cluster" {
  name = module.eks.cluster_id
}

data "aws_eks_cluster_auth" "cluster" {
  name = module.eks.cluster_id
}

data "aws_availability_zones" "available" {
}

variable "volume_count" {
  type        = number
  description = "Number of volumes to create"
  default     = 1
}

variable "availability_zone" {
  type        = string
  description = "Availability zone"
  default     = "ap-southeast-2a"
}

variable "volume_size" {
  type        = string
  description = "Size of the DB storage volume."
  default     = "10"
}

variable "environment_tag" {
  type        = string
  description = "Environment tag"
  default     = "Production"
}

variable "keypair_name" {
  type        = string
  description = "Keypair name"
  default     = "mongo-publicKey"
}

variable "replica_count" {
  type        = number
  description = "Number of Replica nodes"
  default     = 0
}

provider "kubernetes" {
  host                   = data.aws_eks_cluster.cluster.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.cluster.certificate_authority.0.data)
  token                  = data.aws_eks_cluster_auth.cluster.token
#  load_config_file       = false
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "3.2.0"

  name                 = "k8s-eks-vpc"
  cidr                 = "172.16.0.0/16"
  azs                  = data.aws_availability_zones.available.names
  private_subnets      = ["172.16.1.0/24", "172.16.2.0/24", "172.16.3.0/24"]
  public_subnets       = ["172.16.4.0/24", "172.16.5.0/24", "172.16.6.0/24"]
  enable_nat_gateway   = true
  single_nat_gateway   = true
  enable_dns_hostnames = true

  public_subnet_tags = {
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
    "kubernetes.io/role/elb"                      = "1"
  }

  private_subnet_tags = {
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
    "kubernetes.io/role/internal-elb"             = "1"
  }
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "17.1.0"

  cluster_name    = "${local.cluster_name}"
  cluster_version = "1.21"  #"1.17"
  subnets         = module.vpc.private_subnets

  vpc_id = module.vpc.vpc_id

  node_groups = {
    first = {
      desired_capacity = 3 
      max_capacity     = 10
      min_capacity     = 2
      instance_type = "m5.large"
    }
  }

  write_kubeconfig   = true
  kubeconfig_output_path = "./"
}

resource "aws_ebs_volume" "mongo-data-vol" {
  count             = var.volume_count
  availability_zone = var.availability_zone
  type              = "gp2"
  size              = var.volume_size

  tags = {
    Name        = "mongo-data-ebs-volume"
    Environment = var.environment_tag
  }
}

resource "aws_s3_bucket" "mongo-bkp" {
  bucket = "mongo-tmp-bucket"

  tags = {
    Name        = "mongo-tmp-bkp"
    Environment = "test"
  }
}

resource "aws_s3_bucket_acl" "mongo-s3-acl" {
  bucket = aws_s3_bucket.mongo-bkp.id
  acl    = "public-read"
}

module "mongodb" {
  source                 = "./terraform-aws-mongodb-ec2/"
  vpc_id                 = module.vpc.vpc_id
  subnet_id              = module.vpc.public_subnets[0]
  ssh_user               = "ubuntu"
  instance_type          = "t2.micro"
  ami_filter_name        = "ubuntu/images/hvm-ssd/ubuntu-bionic-18.04-amd64-server-*"
  ami_owners             = ["099720109477"]
  data_volumes           = aws_ebs_volume.mongo-data-vol[0].id
  mongodb_version        = "4.2"
  replicaset_name        = "mongo-rp0"
  replica_count          = var.replica_count
  private_key            = file("/Users/danwessels/.ssh/id_rsa_np")
  public_key             = file("/Users/danwessels/.ssh/id_rsa_np.pub")
  keypair_name           = var.keypair_name
  tags = {
    Name        = "MongoDB Server"
    Environment = "terraform-mongo-testing"
  }
}

output "mongo_server_ip_address" {
  value = module.mongodb.mongo_server_public_ip
}

output "ebs-vol-id" {
  value = aws_ebs_volume.mongo-data-vol.*.id
}

# output "s3-bucket" {
#   value = aws_s3_bucket.mongo-bkp.s3_bucket_bucket_domain_name
# }