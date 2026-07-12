#!/bin/bash
set -e

VPS_IP="${VPS_IP:-192.144.12.78}"
IP_DASHED="${VPS_IP//./-}"
EMAIL="${CERT_EMAIL:-noreply@localhost.local}"

DEV_DOMAINS=(
  "dev.${IP_DASHED}.nip.io"
  "api.dev.${IP_DASHED}.nip.io"
  "pg.dev.${IP_DASHED}.nip.io"
)

STAGE_DOMAINS=(
  "stage.${IP_DASHED}.nip.io"
  "api.stage.${IP_DASHED}.nip.io"
  "pg.stage.${IP_DASHED}.nip.io"
)

issue_cert() {
    local env_name="$1"
    shift
    local domains=("$@")
    local cert_dir="/opt/garden-nook/nginx/ssl/${env_name}"
    
    echo "Выпуск сертификата для окружения: ${env_name}"
    echo "════════════════════════════════════════════════════"
    echo "Домены:"
    for d in "${domains[@]}"; do
        echo "  • $d"
    done
    
    local domain_args=""
    for d in "${domains[@]}"; do
        domain_args="${domain_args} -d ${d}"
    done
    
    # certbot с --cert-name чтобы все домены были в одном сертификате
    certbot certonly \
        --standalone \
        --preferred-challenges http \
        --non-interactive \
        --agree-tos \
        --email "${EMAIL}" \
        --cert-name "garden-nook-${env_name}" \
        ${domain_args}
    
    # Копируем сертификаты в директорию nginx
    # Используем -L чтобы получить сами файлы, а не симлинки
    cp -L /etc/letsencrypt/live/garden-nook-${env_name}/fullchain.pem "${cert_dir}/fullchain.pem"
    cp -L /etc/letsencrypt/live/garden-nook-${env_name}/privkey.pem "${cert_dir}/privkey.pem"
    cp -L /etc/letsencrypt/live/garden-nook-${env_name}/chain.pem "${cert_dir}/chain.pem"
    cp -L /etc/letsencrypt/live/garden-nook-${env_name}/cert.pem "${cert_dir}/cert.pem"
    
    # Устанавливаем права, чтобы nginx мог прочитать
    chmod 644 "${cert_dir}/fullchain.pem"
    chmod 644 "${cert_dir}/chain.pem"
    chmod 644 "${cert_dir}/cert.pem"
    chmod 600 "${cert_dir}/privkey.pem"
    
    echo "Сертификат для ${env_name} успешно выпущен"
    echo "Действителен до: $(openssl x509 -in "${cert_dir}/fullchain.pem" -noout -enddate | cut -d= -f2)"
}

echo "VPS IP: ${VPS_IP}"
echo "IP с дефисами: ${IP_DASHED}"
echo "Email для Let's Encrypt: ${EMAIL}"
echo ""

if docker ps --format '{{.Names}}' | grep -q "^nginx$"; then
    docker stop nginx
    NGINX_WAS_RUNNING=true
else
    NGINX_WAS_RUNNING=false
fi

issue_cert "dev" "${DEV_DOMAINS[@]}"
issue_cert "stage" "${STAGE_DOMAINS[@]}"

echo ""
echo "Перезапускаем nginx..."
if [ "${NGINX_WAS_RUNNING}" = true ]; then
    docker start nginx
else
    cd /opt/garden-nook
    docker compose -f docker/nginx/docker-compose.yml up -d
fi

echo "Все сертификаты успешно выпущены/обновлены!"