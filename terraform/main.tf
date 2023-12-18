# main.tf
terraform {
  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 3.0.1"
    }
  }
}

provider "docker" {}

resource "docker_network" "jenkins_network" {
  name = "jenkins_unique_name"
}

resource "docker_volume" "jenkins-docker-certs" {
  name = "jenkins-docker-certs"
}

resource "docker_volume" "jenkins-data" {
  name = "jenkins-data"
}

resource "docker_container" "docker_in_docker" {
  name      = "dind"
  image     = "docker:dind"
  privileged = true
  network_mode	= "jenkins"
  
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
}

variable "host" {
  description = "Docker host."
  type        = string
  default     = "tcp://172.25.0.3:2376"
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
  
  network_mode	= "jenkins"
  
  env = [
    "DOCKER_HOST=${var.host}",
    "DOCKER_CERTS_PATH=${var.cert}",
    "DOCKER_TLS_VERIFY=${var.tls}",
  ]

  volumes {
    volume_name     = docker_volume.jenkins-docker-certs.name
    container_path  = "/certs/client"
  }

  volumes {
    volume_name     = docker_volume.jenkins-data.name
    container_path  = "/var/jenkins_home"
  }
}

  
  
