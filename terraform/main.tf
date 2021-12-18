provider "aws" {
  region = local.region
}

locals {
  name            = "fargate-${random_string.suffix.result}"
  cluster_version = "1.20"
  region          = "ap-southeast-1"
}

################################################################################
# EKS Module
################################################################################

module "eks" {
  source = "../terraform_modules/eks"

  cluster_name    = local.name
  cluster_version = local.cluster_version

  vpc_id          = "vpc-0da8da8c11e6f1edf"
  subnets         = ["subnet-08abb19f82387f0c6", "subnet-038dcee6be2f5b138"]
  fargate_subnets = ["subnet-08952609ed9afb8b7"]

  cluster_endpoint_private_access = true
  cluster_endpoint_public_access  = true

  
  node_groups = {
    example = {
      desired_capacity = 1

      instance_types = ["t3.large"]
      k8s_labels = {
        Example    = "managed_node_groups"
      }
      additional_tags = {
        CreatedBy = "shad_zam"
      }
      update_config = {
        max_unavailable_percentage = 50 # or set `max_unavailable`
      }
    }
  }

  fargate_profiles = {
    default = {
      name = "default"
      selectors = [
        {
          namespace = "kube-system"
          labels = {
            k8s-app = "kube-dns"
          }
        },
        {
          namespace = "default"
          labels = {
            WorkerType = "fargate"
          }
        }
      ]

      tags = {
        Owner = "shad_zam"
      }

      timeouts = {
        create = "20m"
        delete = "20m"
      }
    }

    secondary = {
      name = "secondary"
      selectors = [
        {
          namespace = "default"
          labels = {
            Environment = "test"
          }
        }
      ]

      # Using specific subnets instead of the ones configured in EKS (`subnets` and `fargate_subnets`)
      subnets = [module.vpc.private_subnets[1]]

      tags = {
        Owner = "secondary"
      }
    }
  }

  manage_aws_auth = false

  tags = {
    Example    = local.name
  }
}


##############################################
# Calling submodule with existing EKS cluster
##############################################

module "fargate_profile_existing_cluster" {
  source = "../terraform_modules/fargate"

  cluster_name = module.eks.cluster_id
  subnets      = ["subnet-08abb19f82387f0c6", "subnet-038dcee6be2f5b138"]

  fargate_profiles = {
    profile1 = {
      name = "profile1"
      selectors = [
        {
          namespace = "kube-system"
          labels = {
            k8s-app = "kube-dns"
          }
        },
        {
          namespace = "profile"
          labels = {
            WorkerType = "fargate"
          }
        }
      ]

      tags = {
        Owner     = "profile1"
        submodule = "true"
      }
    }

    profile2 = {
      name = "profile2"
      selectors = [
        {
          namespace = "default"
          labels = {
            Fargate = "profile2"
          }
        }
      ]

      # Using specific subnets instead of the ones configured in EKS (`subnets` and `fargate_subnets`)
      subnets = [subnet-038dcee6be2f5b138]

      tags = {
        Owner     = "profile2"
        submodule = "true"
      }

      timeouts = {
        delete = "20m"
      }
    }
  }

  tags = {
    Example    = local.name
  }
}

################################################################################
# Kubernetes provider configuration
################################################################################

data "aws_eks_cluster" "cluster" {
  name = module.eks.cluster_id
}

data "aws_eks_cluster_auth" "cluster" {
  name = module.eks.cluster_id
}

provider "kubernetes" {
  host                   = data.aws_eks_cluster.cluster.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.cluster.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.cluster.token
}

################################################################################
# Supporting Resources
################################################################################



resource "random_string" "suffix" {
  length  = 8
  special = false
}



