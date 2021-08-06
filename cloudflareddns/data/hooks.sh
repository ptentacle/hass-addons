#!/bin/bash
# shellcheck disable=SC2034
set -e

CONFIG_PATH=/data/options.json

CLOUDFLARE_AUTH_KEY=$(jq --raw-output '.token' $CONFIG_PATH)
ZONE_ID=$(jq --raw-output '.zone_id' $CONFIG_PATH)
SYS_CERTFILE=$(jq --raw-output '.lets_encrypt.certfile' $CONFIG_PATH)
SYS_KEYFILE=$(jq --raw-output '.lets_encrypt.keyfile' $CONFIG_PATH)


# https://github.com/lukas2511/dehydrated/blob/master/docs/examples/hook.sh

deploy_challenge() {
    local DOMAIN="${1}" TOKEN_FILENAME="${2}" TOKEN_VALUE="${3}" ALIAS
    ALIAS="$DOMAIN"

    # This hook is called once for every domain that needs to be
    # validated, including any alternative names you may have listed.

    # get the dns TXT record id
    DNSRECORDID=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records?type=TXT&name=$ALIAS" \
        -H "Authorization: Bearer $CLOUDFLARE_AUTH_KEY" \
        -H "Content-Type: application/json" | jq -r  '{"result"}[] | .[0] | .id')

    # update TXT record
    SUCCESS=$(curl -s -X PUT "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records/$DNSRECORDID" \
        -H "Authorization: Bearer $CLOUDFLARE_AUTH_KEY" \
        -H "Content-Type: application/json" \
        --data "{\"type\":\"TXT\",\"name\":\"$ALIAS\",\"content\":\"$TOKEN_VALUE\",\"ttl\":1,\"proxied\":false}" | jq -r  {"success"}[])

}

clean_challenge() {
    local DOMAIN="${1}" TOKEN_FILENAME="${2}" TOKEN_VALUE="${3}" ALIAS
    ALIAS="$DOMAIN"

    # This hook is called after attempting to validate each domain,
    # whether or not validation was successful. Here you can delete
    # files or DNS records that are no longer needed.
    #
    # The parameters are the same as for deploy_challenge.

    # get the dns TXT record id
    DNSRECORDID=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records?type=TXT&name=$ALIAS" \
        -H "Authorization: Bearer $CLOUDFLARE_AUTH_KEY" \
        -H "Content-Type: application/json" | jq -r  '{"result"}[] | .[0] | .id')

    # update TXT record
    SUCCESS=$(curl -s -X PUT "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records/$DNSRECORDID" \
        -H "Authorization: Bearer $CLOUDFLARE_AUTH_KEY" \
        -H "Content-Type: application/json" \
        --data "{\"type\":\"TXT\",\"name\":\"$ALIAS\",\"content\":\"removed\",\"ttl\":1,\"proxied\":false}" | jq -r  {"success"}[])

}

deploy_cert() {
    local DOMAIN="${1}" KEYFILE="${2}" CERTFILE="${3}" FULLCHAINFILE="${4}" CHAINFILE="${5}" TIMESTAMP="${6}"

    # This hook is called once for each certificate that has been
    # produced. Here you might, for instance, copy your new certificates
    # to service-specific locations and reload the service.
    #
    # Parameters:
    # - DOMAIN
    #   The primary domain name, i.e. the certificate common
    #   name (CN).
    # - KEYFILE
    #   The path of the file containing the private key.
    # - CERTFILE
    #   The path of the file containing the signed certificate.
    # - FULLCHAINFILE
    #   The path of the file containing the full certificate chain.
    # - CHAINFILE
    #   The path of the file containing the intermediate certificate(s).
    # - TIMESTAMP
    #   Timestamp when the specified certificate was created.

     cp -f "$FULLCHAINFILE" "/ssl/$SYS_CERTFILE"
     cp -f "$KEYFILE" "/ssl/$SYS_KEYFILE"
}


HANDLER="$1"; shift
if [[ "${HANDLER}" =~ ^(deploy_challenge|clean_challenge|deploy_cert)$ ]]; then
  "$HANDLER" "$@"
fi
