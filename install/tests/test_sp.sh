#!/usr/bin/env bash


# minimum viable test: check for AuthnRequest

curl -s -o /tmp/authRequest.http -w "%{http_code}" http://localhost:8080/secure/test.php > /tmp/http_code
if (( $?>0 )); then
    echo 'Request to SP failed at http://localhost:8080/secure/test.php'
    exit 1
fi

if [[ $(cat /tmp/http_code) != '302' ]]; then
    echo "Request to SP should have returned HTTP code 302, but returned $(cat /tmp/http_code)"
    exit 2
fi

#test_str='idp/profile/SAML2/Redirect/SSO?SAMLRequest'
test_str='role/idp.ds?entityID='
grep $test_str /tmp/authRequest.http
if (( $?>0 )); then
    echo 'Request to SP should contain idp/profile/SAML2/Redirect/SSO?SAMLRequest, but request was:'
    cat /tmp/authRequest.http
    exit 3
fi

#curl \
#    -H "X-Forwarded-Host: www.termino.gv.at" \
#    -H "X-Forwarded-Proto: https" \
#    -H "X-Forwarded-For: 8.8.8.8" \
#    http://localhost:8080/Shibboleth.sso/Login
