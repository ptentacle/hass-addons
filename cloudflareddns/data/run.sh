#!/bin/bash

CERT_DIR=/data/letsencrypt
WORK_DIR=/data/workdir

# Let's encrypt
LE_UPDATE="0"

# DuckDNS
if bashio::config.has_value "ipv4"; then IPV4=$(bashio::config 'ipv4'); else IPV4=""; fi
if bashio::config.has_value "ipv6"; then IPV6=$(bashio::config 'ipv6'); else IPV6=""; fi
CLOUDFLARE_AUTH_KEY=$(bashio::config 'token')
ZONE_ID=$(bashio::config 'zone_id')
DOMAINS=$(bashio::config 'domains')
WAIT_TIME=$(bashio::config 'seconds')

# Function that performe a renew
function le_renew() {
    local domain_args=()
    local domains=''

    domains=$(bashio::config 'domains')

    bashio::log.info "Renew certificate for domains: $(echo -n "${domains}")"

    domain_args=("--domain" "${domains}")

    dehydrated --cron --hook ./hooks.sh --challenge dns-01 "${domain_args[@]}" --out "${CERT_DIR}" --config "${WORK_DIR}/config" || true
    LE_UPDATE="$(date +%s)"
}

# Register/generate certificate if terms accepted
if bashio::config.true 'lets_encrypt.accept_terms'; then
    # Init folder structs
    mkdir -p "${CERT_DIR}"
    mkdir -p "${WORK_DIR}"

    # Clean up possible stale lock file
    if [ -e "${WORK_DIR}/lock" ]; then
        rm -f "${WORK_DIR}/lock"
        bashio::log.warning "Reset dehydrated lock file"
    fi

    # Generate new certs
    if [ ! -d "${CERT_DIR}/live" ]; then
        # Create empty dehydrated config file so that this dir will be used for storage
        touch "${WORK_DIR}/config"

        dehydrated --register --accept-terms --config "${WORK_DIR}/config"
    fi
fi

# Run duckdns
while true; do

    [[ ${IPV4} != *:/* ]] && ipv4=${IPV4} || ipv4=$(curl -s -m 10 "${IPV4}")
    [[ ${IPV6} != *:/* ]] && ipv6=${IPV6} || ipv6=$(curl -s -m 10 "${IPV6}")

    # IPv4
    domains=$(bashio::config 'domains')

    # get the dns A record id
    dnsrecordid=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/dns_records?type=A&name=${domains}" \
    -H "Authorization: Bearer ${CLOUDFLARE_AUTH_KEY}" \
    -H "Content-Type: application/json" | jq -r  '{"result"}[] | .[0] | .id')

    # update A record
    answer=$(curl -s -X PUT "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/dns_records/${dnsrecordid}" \
    -H "Authorization: Bearer ${CLOUDFLARE_AUTH_KEY}" \
    -H "Content-Type: application/json" \
    --data "{\"type\":\"A\",\"name\":\"${domain}\",\"content\":\"${IPV4}\",\"ttl\":1,\"proxied\":false}" | jq -r  {"success"}[])

    if [ "${answer}" == "true" ]; then
        bashio::log.info "Update A record success"
    else
        bashio::log.warning "Update A record failed"
    fi
    
    
    now="$(date +%s)"
    if bashio::config.true 'lets_encrypt.accept_terms' && [ $((now - LE_UPDATE)) -ge 43200 ]; then
        le_renew
    fi
    
    sleep "${WAIT_TIME}"
done
