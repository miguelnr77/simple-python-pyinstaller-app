terraform {
  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 3.0.2"
    }
  }
}

provider "docker" {}

resource "docker_network" "jenkins_network" {
  name = "jenkins-container-network"
}

resource "docker_volume" "jenkins_docker_certs" {
  name = "jenkins-docker-certs"
}

resource "docker_volume" "jenkins_data" {
  name = "jenkins-data"
}
resource "docker_volume" "home" {
	name = "home_volume"
}

resource "docker_container" "jenkins_docker" {
  name  = "jenkins-docker"
  image = "docker:dind"
  rm    = true
  privileged = true

  env = [
    "DOCKER_TLS_CERTDIR=/certs",
  ]

  volumes {
    volume_name    = docker_volume.jenkins_docker_certs.name
    container_path = "/certs/client"
  }

  volumes {
    volume_name    = docker_volume.jenkins_data.name
    container_path = "/var/jenkins_home"
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

  networks_advanced {
    name = docker_network.jenkins_network.name
    aliases = ["docker"]
  }
}

resource "docker_image" "jenkins_image" {
  name = "myjenkins-blueocean:2.426.2-1"

  build {
    context    = "/home/miguelnr7/GitHub/simple-python-pyinstaller-app"
    dockerfile = "Dockerfile"
  }
}

resource "docker_container" "jenkins_container" {
  depends_on   = [docker_image.jenkins_image]
  name         = "jenkins_container"
  image        = docker_image.jenkins_image.name
  networks_advanced {
  	name = docker_network.jenkins_network.name
  }
  restart      = "on-failure"

  env = [
    "DOCKER_HOST=tcp://docker:2376",
    "DOCKER_CERT_PATH=/certs/client",
    "DOCKER_TLS_VERIFY=1",
    "JAVA_OPTS=-Dhudson.plugins.git.GitSCM.ALLOW_LOCAL_CHECKOUT=true",
  ]

  volumes {
    volume_name = docker_volume.jenkins_docker_certs.name
    container_path = "/certs/client"
  }

  volumes {
    volume_name = docker_volume.jenkins_data.name
    container_path = "/var/jenkins_home"
  }

  volumes {
    volume_name     = docker_volume.home.name
    container_path  = "/home"
  }

  ports {
    internal = 8080
    external = 8080
  }
}


