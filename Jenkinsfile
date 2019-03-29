pipeline {
    agent any
    environment {
        compose_cfg='dc.yaml'
        compose_setup_cfg='dc-setup.yaml'
        compose_f_opt='-f dc.yaml'
        container='shibsp'
        d_containers="${container} dc_${container}_run_1"
        d_volumes="${container}.etc_openldap ${container}.var_db"
        network='dfrontend'
        service='shibsp'
    }
    options { disableConcurrentBuilds() }
    parameters {
        string(defaultValue: 'True', description: '"True": initial cleanup: remove container and volumes; otherwise leave empty', name: 'start_clean')
        string(defaultValue: '', description: '"True": "Set --nocache for docker build; otherwise leave empty', name: 'nocache')
        string(defaultValue: '', description: '"True": push docker image after build; otherwise leave empty', name: 'pushimage')
        string(defaultValue: '', description: '"True": keep running after test; otherwise leave empty to delete container and volumes', name: 'keep_running')
    }

    stages {
        stage('Config ') {
            steps {
                 sh '''#!/bin/bash -e
                    echo "using ${compose_cfg} as docker-compose config file"
                    if [[ "$DOCKER_REGISTRY_USER" ]]; then
                        echo "  Docker registry user: $DOCKER_REGISTRY_USER"
                        ./dcshell/update_config.sh "${compose_cfg}.default" > $compose_cfg
                        ./dcshell/update_config.sh "${compose_setup_cfg}.default" > $compose_setup_cfg
                    else
                        cp "${compose_cfg}.default" $compose_cfg
                        cp "${compose_setup_cfg}.default" $compose_setup_cfg
                    fi
                    egrep '( image:| container_name:)' $compose_cfg || echo "missing keys in ${compose_cfg}"
                '''
           }
        }
        stage('Cleanup ') {
            when {
                expression { params.$start_clean?.trim() != '' }
            }
            steps {
                sh '''#!/bin/bash -e
                    source ./jenkins_scripts.sh
                    remove_containers $d_containers && echo '.'
                    remove_volumes $d_volumes && echo '.'
                '''
            }
        }
        stage('Build') {
            steps {
                sh '''#!/bin/bash -e
                    source ./jenkins_scripts.sh
                    remove_container_if_not_running
                    if [[ "$nocache" ]]; then
                         nocacheopt='-c'
                         echo 'build with option nocache'
                    fi
                    export MANIFEST_SCOPE='local'
                    export PROJ_HOME='.'
                    ./dcshell/build $compose_f_opt $nocacheopt || \
                        (rc=$?; echo "build failed with rc rc?"; exit $rc)
                '''
            }
        }
        stage('Setup + Run') {
            steps {
                sh '''#!/bin/bash -e
                    >&2 echo "setup test config"
                    docker-compose -f dc-setup.yaml run --rm shibsp \
                        cp /opt/install/config/express_setup_citest.yaml /opt/etc/express_setup_citest.yaml
                    docker-compose -f dc-setup.yaml run --rm shibsp \
                        /opt/install/scripts/express_setup.sh -c express_setup_citest.yaml -a || rc=$?
                    if ((rc>0)); then echo 'express setup failed'; exit 1; fi
                    >&2 echo "start server"
                    docker-compose $compose_f_opt up -d
                    sleep 2
                    docker-compose $compose_f_opt logs shibsp
                '''
            }
        }
        stage('Test') {
            steps {
                sh '''
                    sleep 1
                    docker-compose $compose_f_opt exec -T shibsp /opt/install/tests/test_sp.sh
                '''
            }
        }
        stage('Push ') {
            when {
                expression { params.pushimage?.trim() != '' }
            }
            steps {
                sh '''#!/bin/bash -e
                    default_registry=$(docker info 2> /dev/null |egrep '^Registry' | awk '{print $2}')
                    echo "  Docker default registry: $default_registry"
                    ./dcshell/build $compose_f_opt -P
                    rc=$?
                    ((rc>0)) && echo "'docker-compose push' failed with code=${rc}"
                    exit $rc
                '''
            }
        }
    }
    post {
        always {
            sh '''
                if [[ "$keep_running" ]]; then
                    echo "Keep container running"
                else
                    source ./jenkins_scripts.sh
                    remove_containers $d_containers && echo 'containers removed'
                    remove_volumes $d_volumes && echo 'volumes removed'
                fi
            '''
        }
    }
}