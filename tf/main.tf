terraform {
  required_version = ">= 1.16"

  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.30"
    }
  }
}

provider "kubernetes" {
  config_path    = "~/.kube/config"
  config_context = "aiops"
}

# To samo co k8s/netpol-postgres.yaml: do Postgresa wpuszczamy tylko orders-api na 5432.
resource "kubernetes_network_policy_v1" "postgres_ingress" {
  metadata {
    name      = "kantyna-postgres-ingress"
    namespace = "piotr-z"
    labels = {
      "app.kubernetes.io/name"     = "postgres"
      "app.kubernetes.io/instance" = "kantyna"
      "app.kubernetes.io/part-of"  = "kantyna"
    }
  }

  spec {
    pod_selector {
      match_labels = {
        "app.kubernetes.io/name"     = "postgres"
        "app.kubernetes.io/instance" = "kantyna"
      }
    }

    policy_types = ["Ingress"]

    ingress {
      from {
        pod_selector {
          match_labels = {
            "app.kubernetes.io/name"     = "orders-api"
            "app.kubernetes.io/instance" = "kantyna"
          }
        }
      }
      ports {
        protocol = "TCP"
        port     = "5432"
      }
    }
  }
}
