provider "kubernetes" {
    config_path = "~/.kube/config-switch-dev"
}

provider "helm" {

}

provider "random" {}

resource "random_password" "password" {
  length = 32
  special = true
  upper = true
  number = true
}

resource "kubernetes_secret" "credentials" {
    metadata {
        name = "credentials"
        namespace = var.namespace
    }

    data = {
        username = "admin"
        password = var.password != "" ? var.password : random_password.password.result
    }

    type = "kubernetes.io/basic-auth"
}

resource "kubernetes_deployment" "test-deployment" {
    metadata {
        name = "test-deployment"
        namespace = var.namespace
        labels = {
            app = "nginx"
        }
    }

    spec {
        replicas = 2

        selector {
            match_labels = {
                app = "nginx"
            }
        }

        template {
            metadata {
                labels = {
                    app = "nginx"
                }
            }

            spec {
                container {
                    name = "nginx"
                    image = "nginx"

                    volume_mount {
                        mount_path = "/etc/secret-volume"
                        name = "secret-volume"
                    }
                }

                volume {
                    name = "secret-volume"
                    secret {
                        secret_name = kubernetes_secret.credentials.metadata[0].name
                    }
                }
            }
        }
    }
}

resource "kubernetes_service" "service" {
    metadata {
        name = "service"
        namespace = var.namespace
    }

    spec {
        selector = {
            app = "nginx"
        }

        port {
            port = 80
        }
    }
}

resource "kubernetes_ingress" "ingress" {
    metadata {
        name = "ingress"
        namespace = var.namespace
    }
    spec {
        rule {
            host = "${var.namespace}.dev.renku.ch"
            http {
                path {
                    backend {
                        service_name = kubernetes_service.service.metadata[0].name
                        service_port = 80
                    }

                    path = "/nginx-test"
                }
            }
        }
    }
}

data "helm_repository" "stable" {
  name = "stable"
  url  = "https://kubernetes-charts.storage.googleapis.com"
}

resource "helm_release" "postgres" {
  name  = "postgres"
  chart = "stable/postgresql"
  repository = data.helm_repository.stable.metadata[0].name
  version = "6.3.13"
  namespace = var.namespace

  set {
      name = "livenessProbe.periodSeconds"
      value = 9
  }
}

output "name" {
  value = kubernetes_deployment.test-deployment.metadata[0].name
}

output "url" {
  value = "${kubernetes_ingress.ingress.spec[0].rule[0].host}${kubernetes_ingress.ingress.spec[0].rule[0].http[0].path[0].path}"
}

output "password" {
  value = kubernetes_secret.credentials.data.password
  sensitive = true
}
