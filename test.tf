provider "kubernetes" {

}

provider "helm" {

}

resource "kubernetes_namespace" "test" {
    metadata {
        name = "ralf-dev"
    }
}

resource "kubernetes_secret" "credentials" {
    metadata {
        name = "credentials"
    }

    data = {
        username = "admin"
        password = var.password
    }

    type = "kubernetes.io/basic-auth"
}

resource "kubernetes_deployment" "test-deployment" {
    metadata {
        name = "test-deployment"
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
    }
    spec {
        rule {
            host = "${kubernetes_namespace.test.metadata[0].name}"
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

resource "helm_release" "postgres" {
  name  = "postgres"
  chart = "stable/postgres"
  version = "6.3.13"
}

output "name" {
  value = kubernetes_deployment.test-deployment.metadata[0].name
}

output "url" {
  value = "${kubernetes_ingress.ingress.spec[0].rule[0].host}${kubernetes_ingress.ingress.spec[0].rule[0].http[0].path[0].path}"
}

output "password" {
  value = kubernetes_secret.credentials.data.password
}
