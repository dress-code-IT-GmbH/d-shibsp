# switching between RH/CentOS
# use either:
# intra/ubi7-py36 is registry.access.redhat.com/ubi7/python-36 with memcached installed
# https://github.com/dress-code-IT-GmbH/d-centos7-py36-memcached
# centos/python-36-centos7 + memcached
# and label it as intra/rhorcs7-py36-memcached
FROM intra/rhorcs7-py36-memcached

USER root
LABEL capabilities='--cap-drop=all --cap-add=dac_override --cap-add=setuid --cap-add=setgid --cap-add=chown --cap-add=net_raw'

# allow build behind firewall
ARG HTTPS_PROXY=''
ARG TIMEZONE='Europe/Vienna'
RUN ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime

RUN yum -y update \
 && yum -y install httpd iputils logrotate mod_php mod_ssl mod_wsgi net-tools psmisc \
 && yum clean all && rm -rf /var/cache/yum
COPY install/security:shibboleth.repo /etc/yum.repos.d

RUN echo $'export LD_LIBRARY_PATH=/opt/shibboleth/lib64:$LD_LIBRARY_PATH\n' > /etc/sysconfig/shibd \
 && chmod +x /etc/sysconfig/shibd
 # beware: yum update may re-install packages and reset ownerships/permissions to defaults.
 # therefore set permissions always after yum update

# Run https and shibd as a non-root user, separate uids for httpd and shibd, with common group shibd.
# Allow httpd/mod_shib access to /var/run/shibboleth and /etc/shibboleth using group shibd
# Prevent yum to create default uid for shibd to control user mapping between host and container

ENV HTTPDUSER httpd
ENV HTTPDUID 344005
ENV SHIBDGID 343005
RUN groupadd --gid $SHIBDGID shibd \
 && adduser --gid $SHIBDGID --uid $HTTPDUID $HTTPDUSER \
 && mkdir -p /var/log/httpd /var/log/shibboleth-www /var/www/tmp \
 && chown -R $HTTPDUID:shibd /etc/httpd /var/log/httpd /var/log/shibboleth-www /var/www/tmp \
 && rm -rf /etc/httpd/modules /etc/httpd/logs /etc/httpd/run \
 && ln -s /usr/lib64/httpd/modules /etc/httpd/modules\
 && ln -s /var/log/httpd /etc/httpd/logs \
 && ln -s /run/httpd /etc/httpd/run


# prepare express setup from /opt/install/etc
RUN mkdir -p /opt/etc/shibboleth/attr_mapping
COPY install /opt/install
COPY install/opt /opt
COPY install/etc/shibboleth/attr_mapping /opt/etc/shibboleth/attr_mapping
COPY install/www/* /var/www/vhost/html/
COPY install/scripts/* /opt/bin/
RUN chmod +x /opt/bin/*.sh \
 && mv /etc/httpd/conf /etc/httpd/conf.orig \
 && mv /etc/httpd/conf.d/ /etc/httpd/conf.d.orig/ \
 && mkdir -p /etc/httpd/conf /etc/httpd/conf.d


# require jinja + yaml for express setup, manifest2.sh
RUN pip3 install jinja2 pyyaml


RUN mkdir /var/log/startup \
 && chmod 777 /var/log/startup  # must be writeable by root

# First add user "shibd" and install shibboleth SP, then rename to "$SHIBUSER".
# Set permissions for shibd user to write to /var/cache and /var/run /var/log
ENV SHIBDUSER shibd
ENV SHIBDUID 343005
RUN adduser --gid $SHIBDGID --uid $SHIBDUID shibd \
 && mkdir -p /etc/shibboleth /var/log/shibboleth /var/run/shibboleth \
 && yum -y install shibboleth.x86_64 shibboleth-embedded-ds \
 && yum -y clean all && rm -rf /var/cache/yum \
 # key material is useless on an image -> remove!
 && rm -f /etc/shibboleth/sp-cert.pem /etc/shibboleth/sp-key.pem  \
 && mkdir -p /etc/shibboleth/export \
 && rm -f /etc/shibboleth/shibboleth2.xml  \
 && chown $SHIBDUID:$SHIBDGID /etc/shibboleth /var/log/shibboleth /var/run/shibboleth \
 && chmod 700 /var/log/shibboleth \
 && chmod 750 /var/run/shibboleth /etc/shibboleth /etc/shibboleth/*.sh
RUN [[ "$SHIBDUSER" == 'shibd' ]] || usermod -l $SHIBDUSER shibd

# run optional script (see install/build/more.sh.default)
RUN if test -e /opt/install/build/more.sh; then sh /opt/install/build/more.sh; fi

CMD /opt/bin/start.sh

VOLUME /etc/httpd/conf \
       /etc/httpd/conf.d \
       /etc/shibboleth \
       /opt/etc \
       /run/httpd \
       /var/log \
       /var/www

ARG HTTPD_PORT=8080
EXPOSE $HTTPD_PORT

COPY install/opt/bin/manifest2.sh /opt/bin/manifest2.sh
