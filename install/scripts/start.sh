#!/bin/bash

function main {
    # transition from root to daemon user is handled by shibd/httpd; must start as root
    if [ $(id -u) -ne 0 ]; then
        echo "must start shibd and httpd as root"
        exit 1
    fi
    get_commandline_opts $@
    if [[ "$restart_httpd" ]]; then
        restart_httpd
    elif [[ "$restart_shibd" ]]; then
        restart_shibd
    else
        cleanup_and_prep_shibd
        start_shibd
        start_httpd
    fi
}


get_commandline_opts() {
    while getopts ':HS' opt; do
      case $opt in
        H) restart_httpd='True';;
        S) restart_shibd='True';;
        *) echo "usage: $0 OPTIONS
           Start shibd and httpd

           OPTIONS:
           -H  restart httpd only (graceful)
           -S  restart shibd only
           "; exit 0;;
      esac
    done
    shift $((OPTIND-1))
    if [[ "$restart_httpd" && "$restart_shibd" ]]; then
        echo "-S and -H are mutually exclusive"
        exit 1
    fi
}


function cleanup_and_prep_shibd {

    # correct ownership (docker run will reset the ownership of volumes at creation time).
    # Only a problem with /etc/shibboleth, where mod_shib needs to have access with the httpd id

    # Make sure we're not confused by old, incompletely-shutdown shibd or httpd
    # context after restarting the container. httpd/shibd won't start correctly if thinking it is already running.
    rm -rf /var/lock/subsys/shibd
    su - shibd  -c '[ -e /run/shibboleth/shibd.sock ] && rm /run/shibboleth/shibd.*'
}


function start_shibd {
    echo "starting shibd"
    export LD_LIBRARY_PATH=/opt/shibboleth/lib64
    /usr/sbin/shibd -u shibd -g root -p /var/run/shibboleth/shib.pid
}


function restart_shibd {
    echo "restarting shibd"
    kill $(cat /var/run/shibboleth/shib.pid)
    sleep 2
    export LD_LIBRARY_PATH=/opt/shibboleth/lib64
    /usr/sbin/shibd -u shibd -g root -p /var/run/shibboleth/shib.pid
}


function start_httpd {
    echo "starting httpd"
    # `docker run` 1.12.6 will reset ownership and permissions on /run/httpd; therefore it need to be done again:
    # do not start with root to avoid permission conflicts on log files
    #su - $HTTPDUSER  -c 'rm -f /run/httpd/* 2>/dev/null || true'
    #su - $HTTPDUSER  -c 'httpd -t -d /etc/httpd/ -f conf/httpd.conf'
    #su - $HTTPDUSER  -c 'httpd -DFOREGROUND -d /etc/httpd/ -f conf/httpd.conf'

    # logging to stderr requires httpd to start as root (inside docker as of 17.05.0-ce)
    # pidfile in /run/httpd requires added kernel capabilities -> move to /var/log
    rm -f /run/httpd/* /var/log/httpd/httpd.pid 2>/dev/null || true
    /usr/sbin/httpd -t -d /etc/httpd/ -f conf/httpd.conf
    /usr/sbin/httpd -DFOREGROUND -d /etc/httpd/ -f conf/httpd.conf
}


function restart_httpd {
    echo "restarting httpd"
    /usr/sbin/httpd -d /etc/httpd/ -f conf/httpd.conf -k graceful
}


main $@

