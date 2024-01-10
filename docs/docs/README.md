# Practica 3: Terraform + SCV + JENKINS

Para realizar la practica, debemos crear un archivo Terraform que despliegue dos contenedores Docker (uno Docker in Docker y otro Jenkins).

## Explicacion de archivos

### Dockerfile 

```bash
FROM jenkins/jenkins
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
RUN jenkins-plugin-cli --plugins "blueocean docker-workflow"
```

Con este Dockerfile construimos la imagen de Jenkins. El mismo se puede obtener en el tutorial indicado en las transparencias.

### Jenkinsfile

```ruby
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
A continuación, se explica el archivo Jenkinsfile obtenido del tutorial "build a python application" dividido en partes:

#### PARTE 1: Declaración del pipeline.

```ruby
pipeline {
    agent none
    options {
        skipStagesAfterUnstable()
    }
```
En esta primera parte, definimos un pipeline en Jenkins. Indicamos que no hay un agente predeterminado
para ejecutar el pipeline y configuramos una opción para omitir las etapas restantes después de que una etapa haya sido marcada como "Unstable".

#### PARTE 2: Declaración por etapas (Build).

```ruby
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
```

Esta parte del Jenkinsfile se encarga de la etapa de construcción del pipeline. Utiliza un contenedor Docker con Python 3.12.1 en Alpine 3.19 como entorno de ejecución. En esta etapa, se compilan los archivos add2vals.py y calc.py usando el comando python -m py_compile, y los resultados se almacenan temporalmente en 'compiled-results' para su uso posterior en el pipeline.

#### PARTE 3: Declaración por etapas (Test).

```ruby
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
```

Esta sección ejecuta pruebas automatizadas en un entorno Docker utilizando la imagen qnib/pytest. Los pasos incluyen la ejecución de pruebas con pytest, la generación de un informe en formato JUnit, y la publicación de los resultados en Jenkins. La sección siempre publica los resultados de las pruebas JUnit después de cada ejecución.

#### PARTE 4: Declaración por etapas (Deliver).

```ruby
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
```

Esta sección del Jenkinsfile orquesta la entrega de la aplicación. Utiliza cualquier agente disponible y establece variables de entorno para la ubicación del volumen y la imagen de Docker. Los pasos incluyen la construcción y empaquetado de la aplicación con PyInstaller en un contenedor Docker, recuperando resultados previamente compilados. Las acciones posteriores al éxito archivan los artefactos generados y realizan limpieza de directorios en el contenedor Docker.


### Terraform

Siguiendo el formato de explicación del Jenkinsfile, dividiré el archivo terraform (main.tf) en partes.

#### Parte 1: Configuración de proveedores y redes.

```ruby
terraform {
  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 3.0.1"  
    }
  }
}

provider "docker" {}  

resource "docker_network" "jenkins" {
  name = "jenkins-network"
}

resource "docker_volume" "jenkins_certs" {
  name = "jenkins-docker-certs"
}

resource "docker_volume" "jenkins_data" {
  name = "jenkins-data"
}
```
Este bloque inicializa Terraform y declara el proveedor Docker, especificando la versión. Luego, se definen dos volúmenes de Docker y una red para su uso en las siguientes partes del script.

#### Parte 2: Configuración del contenedor Docker para Jenkins.

```ruby
resource "docker_container" "jenkins_docker" {
  name = "jenkins-docker"
  image = "docker:dind"
  restart = "unless-stopped"
  privileged = true
  env = [
    "DOCKER_TLS_CERTDIR=/certs"
  ]

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

  volumes {
    volume_name = docker_volume.jenkins_certs.name
    container_path = "/certs/client"
  }

  volumes {
    volume_name = docker_volume.jenkins_data.name
    container_path = "/var/jenkins_home"
  }

  networks_advanced {
    name = docker_network.jenkins.name
    aliases = [ "docker" ]
  }

  command = ["--storage-driver", "overlay2"]
}
```

En esta parte definimos tanto volúmenes como la red a usar.En este bloque, se define un contenedor Docker llamado "jenkins_docker". Este contenedor utiliza la imagen "docker:dind" (Docker-in-Docker), tiene configuraciones de red y puertos específicos, y utiliza volúmenes para gestionar certificados y datos de Jenkins. El contenedor también tiene privilegios elevados y se inicia con el comando "--storage-driver overlay2".

#### Parte 3: Configuración del contenedor Docker para Jenkins Blueocean

```ruby
resource "docker_container" "jenkins_blueocean" {
  name = "jenkins-blueocean"
  image = "myjenkins-blueocean"
  restart = "unless-stopped"
  env = [
    "DOCKER_HOST=tcp://docker:2376", 
    "DOCKER_CERT_PATH=/certs/client", 
    "DOCKER_TLS_VERIFY=1", 
  ]

  ports {
    internal = 8080
    external = 8080
  }

  ports {
    internal = 50000
    external = 50000
  }

  volumes {
    volume_name = docker_volume.jenkins_data.name
    container_path = "/var/jenkins_home"
  }
 
  volumes {
    volume_name = docker_volume.jenkins_certs.name
    container_path = "/certs/client"
    read_only = true
  }

  networks_advanced {
    name = docker_network.jenkins.name 
  }
}
```
En este bloque, se define un segundo contenedor Docker llamado "jenkins_blueocean". Este contenedor utiliza una imagen personalizada "myjenkins-blueocean" y tiene configuraciones de red, puertos y volúmenes similares al contenedor de Jenkins anterior. Además, se establecen variables de entorno para la conexión a Docker y se configura el volumen de certificados como de solo lectura.

En resumen, el archivo Terraform define proveedores, redes y volúmenes de Docker, así como dos contenedores Docker para Jenkins y Jenkins Blue Ocean, cada uno con su propia configuración de red, volúmenes y puertos expuestos.


## Creacion y despliegue de la practica.

#### Creacion de .tf
Lo primero de todo sera crear nuestro archivo terrafor (en mi caso main.tf) el cual cree los dos contenedores Docker mencionados anteriormente. 

#### Creación de Dockerfile

Luego siguiendo el tutorial creamos el Dockerfile y ejecutamos lo siguiente para crear la imagen 
```ruby
docker build -t myjenkins-blueocean .
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

