# Practica 3: Terraform + SCV + JENKINS

Para realizar la practica, debemos crear un archivo Terraform que despliegue dos contenedores Docker (uno Docker in Docker y otro Jenkins).

## Explicacion de archivos

### Dockerfile 

```bash
FROM jenkins/jenkins:2.426.1-jdk17
USER root
RUN apt-get update && apt-get install -y lsb-release
RUN curl -fsSLo /usr/share/keyrings/docker-archive-keyring.asc \
  https://download.docker.com/linux/debian/gpg
RUN echo "deb [arch=$(dpkg --print-architecture) \
  signed-by=/usr/share/keyrings/docker-archive-keyring.asc] \
  https://download.docker.com/linux/debian \
  $(lsb_release -cs) stable" > /etc/apt/sources.list.d/docker.list
RUN apt-get update && apt-get install -y docker-ce-cli
USER jenkins
RUN jenkins-plugin-cli --plugins "blueocean:1.27.9 docker-workflow:572.v950f58993843"
```

Con este Dockerfile construimos la imagen de Jenkins. El mismo se puede obtener en el tutorial indicado en las transparencias.

### Jenkinsfile

```bash
pipeline {
    agent none
    options {
        skipStagesAfterUnstable()
    }
    stages {
        stage('Build') {
            agent {
                docker {
                    image 'python:3.12.1-alpine3.19'
                }
            }
            steps {
                sh 'python -m py_compile sources/add2vals.py sources/calc.py'
                stash(name: 'compiled-results', includes: 'sources/*.py*')
            }
        }
        stage('Test') {
            agent {
                docker {
                    image 'qnib/pytest'
                }
            }
            steps {
                sh 'py.test --junit-xml test-reports/results.xml sources/test_calc.py'
            }
            post {
                always {
                    junit 'test-reports/results.xml'
                }
            }
        }
        stage('Deliver') { 
            agent any
            environment { 
                VOLUME = '$(pwd)/sources:/src'
                IMAGE = 'cdrx/pyinstaller-linux:python2'
            }
            steps {
                dir(path: env.BUILD_ID) { 
                    unstash(name: 'compiled-results') 
                    sh "docker run --rm -v ${VOLUME} ${IMAGE} 'pyinstaller -F add2vals.py'" 
                }
            }
            post {
                success {
                    archiveArtifacts "${env.BUILD_ID}/sources/dist/add2vals" 
                    sh "docker run --rm -v ${VOLUME} ${IMAGE} 'rm -rf build dist'"
                }
            }
        }
    }
}
```
Con este Jenkinsfile (obtenido del tutorial), especificamos un pipeline de tres etapas. En cada etapa se usa un contenedor Docker diferente para la compilación, pruebas y construcción de la aplicación Python. 

### Terraform

Para la explicación del archivo terraform, dividiré el mismo archivo.

#### Configuración

```bash
terraform {
  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 3.0.1"
    }
  }
}
provider "docker" {}
```
Ene sta primera parte definimos proveedor Docker y versión.

#### Volúmenes y Redes

```bash
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
```

En esta parte definimos tanto volúmenes como la red a usar.

#### Docker in Docker

```bash
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
```
Esto define la creacion del Docker in Docker. Se configura con privilegios y se le asignan volumenes para almacenar certificados TLS de Docker y datos Jenkins. Además se exponen puertos y se intengra en una red específica con el alias "docker".

#### Docker Jenkins

```bash
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
```

Este fragmento construye una imagen Docker para jenkins y un contenedor que usa esa imagen. La imagen esta basada en el Dockerfile que se describe anteriormente. El contenedor al igual que el anterior se configura con volúmenes, variables de entorno y puertos necesarios para ejecutar Jenkins en un entorno Dockerizado.


## Proceso de creación

#### Creacion de .tf
Lo primero de todo sera crear nuestro archivo terrafor (en mi caso main.tf) el cual cree los dos contenedores Docker mencionados anteriormente. 

#### Creación de Dockerfile

Luego siguiendo el tutorial creamos el Dockerfile y ejecutamos lo siguiente para crear la imagen 
```bash
docker build -t myjenkins-blueocean:2.426.2-1 .
```

#### Lanzamos terraform 

Seguidamente realizamos un terraform init el cual descargara lo indicado en el .tf (deendecias, version, etc..) y luego un terraform apply que nos servira para confirmar esa config.

#### Acceso a Jenkins

Accediendo a jenkins (localhost:8080) nos pedirá desbloquearlo. Para ello debemos meter en la terminal el siguiente comando docker logs jenkins-blueocean y obtener el codigo que esta entre asteriscos

Luego registramos nuestro usuario y instalamos plugins recomendados.

#### Creacion del Pipeline

Para crear el pipeline pulsamos en new item. Añadimos nombre y pulsamos en Pipeline-Save.

Luego pulsamos la opcion Pipeline y escogemos Pipeline script from SCM en lugar del que viene por defecto, escogemos Git y añadimos URL de nuestro repositorio del Fork. Finalmente creamos el archivo.

#### Lanzamiento del Pipeline

Lanzamos el pipeline pulsando en Run y luego rapidamente en la ventana emergente Open. Tras esto veremos como el pipeline se ejcuta correctamente.



