# main.tf
terraform {
  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 3.0.1"
    }
  }
}

#Indicamos proveedor

provider "docker" {}

resource "docker_network" "jenkins_network" {
  name = "red_jenkins"
  ipam_config {
    subnet = "172.21.0.0/24"
  }
}

resource "docker_volume" "jenkins-docker-certs" {
  name = "jenkins-docker-certs"
}

resource "docker_volume" "jenkins-data" {
  name = "jenkins-data"
}

resource "docker_image" "docker_in_docker" {
  name = "docker:dind"
  keep_locally = false
}


resource "docker_container" "jenkins_docker" {
  name      = "jenkins-docker"
  image     = docker_image.docker_in_docker.image_id
  privileged = true
  rm = true
  networks_advanced {
    name = docker_network.jenkins_network.name
    ipv4_address = "172.21.0.3"
  }
  
  env = [
    "DOCKER_TLS_CERTDIR=/certs",
  ]

  volumes {
    volume_name     = docker_volume.jenkins-docker-certs.name
    container_path  = "/certs/client"
  }

  volumes {
    volume_name     = docker_volume.jenkins-data.name
    container_path  = "/var/jenkins_home"
  }
  
  ports { 
    internal = 3000
    external = 3000
  }
  
  ports {
    internal = 5000
    external = 5000
  }
  
  ports {
    internal = 2376
    external = 2376
  }
}

variable "host" {
  description = "Docker host."
  type        = string
  default     = "tcp://172.21.0.3:2376"
}

variable "cert" {
  description = "Path to Docker certificates."
  type        = string
  default     = "/certs/client"
}

variable "tls" {
  description = "Enable or disable TLS for Docker."
  type        = bool
  default     = true
}
resource "docker_image" "jenkins_image" {
  name = "myjenkins-blueocean:2.426.2-1"

  build {
    context    = "/home/miguelnr7/GitHub/simple-python-pyinstaller-app"
    dockerfile = "Dockerfile"
  }
}

resource "docker_container" "jenkins_container" {
  name          = "jenkContainer"
  image         = docker_image.jenkins_image.name
  
  networks_advanced {
    name = docker_network.jenkins_network.name
  }
  
  env = [
    "DOCKER_HOST=${var.host}",
    "DOCKER_CERTS_PATH=${var.cert}",
    "DOCKER_TLS_VERIFY=${var.tls}",
    "JAVA_OPTS=-Dhudson.plugins.git.GitSCM.ALLOW_LOCAL_CHECKOUT=true",
  ]

  volumes {
    volume_name     = docker_volume.jenkins-docker-certs.name
    container_path  = "/certs/client"
  }

  volumes {
    volume_name     = docker_volume.jenkins-data.name
    container_path  = "/var/jenkins_home"
  }
  
  ports {
    internal = 50000
    external = 50001
  }
  ports {
    internal = 8080
    external = 8081
  }
  
  restart = "on-failure"
}

  
  
