#!/usr/bin/env bash
PS4='+(${BASH_SOURCE}:${LINENO}): ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'

main() {
    echo ">>running express setup"
    _set_constants
    _get_commandline_opts $@
    _default_config_for_citest
    if [[ "$generate_httpd" ]]; then _setup_httpd_config; fi
    if [[ "$generate_sp_keys" || "$force_keygen" ]]; then _generate_sp_keys; fi
    if [[ "$generate_sp_metadata" ]]; then _generate_sp_metadata; fi
    if [[ "$generate_sp_config" ]]; then _generate_sp_config; fi
    _fix_file_privileges
}

_set_constants() {
    setupdir='/opt/install'
}

_get_commandline_opts() {
    metadata_edited='sp_metadata.xml'
    setupfilebasename='express_setup.yaml'
    while getopts ':ac:hkKmo:s' opt; do
      case $opt in
        a) generate_httpd='True'; generate_sp_keys='True'; generate_sp_metadata='True'; generate_sp_config='True';;
        c) setupfilebasename=$OPTARG;;
        h) generate_httpd='True';;
        k) generate_sp_keys='True';;
        K) force_keygen='True';;
        m) generate_sp_metadata='True';;
        o) metadata_edited=$OPTARG;;
        s) generate_sp_config='True';;
        :) echo "Option -$OPTARG requires an argument"; exit 1;;
        *) echo "usage: $0 OPTIONS
           Configure apache + shibd and generate SP metadata

           OPTIONS:
           -a  all: includes -h, -k, -m and -s
           -c  express configuration file (default: $setupfile)
           -h  copy /etc/httpd/ from /opt/install/etc/httpd/ and modify files with express config
           -k  generate SP key pair if not existing (sp_cert.pem, sp_key.pem)
           -K  generate SP key pair (overwrite existing SP signature keys)
           -m  generate SP metadata for federation registration (keygen.sh + post-processing)
           -o  filename of post-processed metadata file (default: $metadata_edited)
           -s  generate SP config (shibboleth2.xml & files defined in profile of express config)
           "; exit 0;;
      esac
    done
    shift $((OPTIND-1))
    if ! [[ $generate_httpd || $generate_sp_keys || $force_keygen || $generate_sp_metadata || $generate_sp_config ]]; then
        echo "No action selected: need to specify at least one of -a, -h, -k, -K, -m or -s"
    fi
    setupfile=${setupdir}/config/$setupfilebasename
    if [[ ! -e "$setupfile" ]]; then
        echo "${setupfile} does not exist"
        exit 1
    fi
}


_default_config_for_citest() {
    # use default config if no custom config is found (only useful for CI-tests)
    if [[ ! -e $setupfile ]]; then
        cat ${setupdir}/etc/hosts.d/testdom.test >> /etc/hosts  # FQDNs for default config
    fi
}


_setup_httpd_config() {
    hostname=$( /opt/bin/get_config_value.py $setupfile httpd hostname )
    echo ">>generating httpd config for ${hostname}"
    cp /opt/install/etc/httpd/httpd.conf /etc/httpd/conf/httpd.conf
    sed -e "s/sp.example.org/$hostname/" ${setupdir}/etc/httpd/conf.d/vhost.conf > /etc/httpd/conf.d/vhost.conf
    cp -n ${setupdir}/etc/httpd/conf.d/* /etc/httpd/conf.d/
    echo "PidFile /run/httpd/httpd.pid" > /etc/httpd/conf.d/pidfile.conf
}


_generate_sp_keys() {
    entityID=$( /opt/bin/get_config_value.py $setupfile Shibboleth2 entityID )
    hostname=$( /opt/bin/get_config_value.py $setupfile httpd hostname )
    cd /etc/shibboleth
    if [[ -e sp-cert.pem ]]; then
        if [[ "$force_keygen" ]]; then
            echo "generate SP signing key pair"
            ./keygen.sh -f -u shibd -g shibd -y 10 -h $hostname -e $entityID
        else
            echo "Keeping existing signing key & cert (sp_cert.pem). To generate a new key use option -K"
        fi
    else
        echo "generate SP signing key pair"
        touch sp-cert.pem sp-key.pem
        ./keygen.sh -f -u shibd -g shibd -y 10 -h $hostname -e $entityID
    fi
}


_generate_sp_metadata() {
    echo "generate SP metadata for host=$hostname and entityID=$entityID"
    ./metagen.sh \
        -2DL \
        -f urn:oasis:names:tc:SAML:2.0:nameid-format:transient \
        -f urn:oasis:names:tc:SAML:2.0:nameid-format:persistent \
        -c sp-cert.pem -h $hostname -e $entityID > /tmp/sp_metadata_to_be_edited.xml
    _create_metadata_postprocessor
    _postprocess_metadata
}


_create_metadata_postprocessor() {
    echo "create XSLT for processing SP-generated metadata (/tmp/postprocess_metadata.xslt)"
    /opt/bin/render_template.py $setupfile ${setupdir}/templates/postprocess_metadata.xml 'Metadata' \
        > /tmp/postprocess_metadata.xslt
}


_postprocess_metadata() {
    echo ">>post-processing SP metadata"
    metadata_edited_path=/etc/shibboleth/export
    mkdir -p $metadata_edited_path
    xsltproc /tmp/postprocess_metadata.xslt /tmp/sp_metadata_to_be_edited.xml \
        > $metadata_edited_path/$metadata_edited
    echo "created ${metadata_edited_path}/${metadata_edited}"
}


_generate_sp_config() {
    _generate_sp_config_xml
    _copy_shibboleth2_profile
}


_generate_sp_config_xml() {
    echo ">>generating /etc/shibboleth/shibboleth2.xml"
    /opt/bin/render_template.py $setupfile ${setupdir}/templates/shibboleth2.xml 'Shibboleth2' \
        > /etc/shibboleth/shibboleth2.xml
}


_copy_shibboleth2_profile() {
    profile=$( /opt/bin/get_config_value.py ${setupfile} Shibboleth2 Profile )
    printf ">>copying for profile ${profile} to /etc/shibboleth/:\n$(ls -l ${setupdir}/etc/shibboleth/attr_mapping/$profile/*)\n"
    cp ${setupdir}/etc/shibboleth/attr_mapping/$profile/* /etc/shibboleth/
}


_fix_file_privileges() {
    chown -R httpd:shibd /etc/httpd/ /run/httpd/ /var/log/httpd/
    chown -R shibd:shibd /etc/shibboleth/ /var/log/shibboleth/
    chmod -R 775  /run/httpd/
    (( $? > 0 )) && echo "This operation requires chmod kernel capabilites for root. Start container without --cap-drop=all"
    chmod -R 755  /var/log/shibboleth/
}


main $@
