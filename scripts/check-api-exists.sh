#!/bin/bash

# Script para verificar se a API já existe no API Manager
# Uso: ./check-api-exists.sh <api-name> <environment>

set -e

API_NAME=$1
ENVIRONMENT=$2

echo "=================================================="
echo "🔍 Verificando se API existe no API Manager"
echo "=================================================="
echo "API: $API_NAME"
echo "Ambiente: $ENVIRONMENT"
echo ""

# Ler configuração
CONFIG_FILE="api/api-config.yaml"

ENV_ID=$(yq eval ".environments.$ENVIRONMENT.environmentId" $CONFIG_FILE)
ORG_ID=$(yq eval ".environments.$ENVIRONMENT.organizationId" $CONFIG_FILE)

echo "🏢 Organização: $ORG_ID"
echo "🌍 Environment ID: $ENV_ID"
echo ""

# Listar todas as APIs no API Manager
echo "📋 Listando APIs no API Manager..."

API_LIST=$(anypoint-cli-v4 api-mgr api list \
    --organization "$ORG_ID" \
    --environment "$ENV_ID" \
    --output json 2>/dev/null || echo "[]")

# Verificar se a API existe (buscar por nome)
API_ID=$(echo "$API_LIST" | jq -r ".[] | select(.name==\"$API_NAME\") | .id" | head -n 1)

if [ -z "$API_ID" ] || [ "$API_ID" == "null" ]; then
    echo "❌ API não encontrada no API Manager"
    echo "api-exists=false" >> $GITHUB_OUTPUT
    echo "false" > /tmp/api-exists.txt
else
    echo "✅ API encontrada no API Manager"
    echo "📋 API ID: $API_ID"
    echo "api-exists=true" >> $GITHUB_OUTPUT
    echo "api-id=$API_ID" >> $GITHUB_OUTPUT
    echo "true" > /tmp/api-exists.txt
    echo "$API_ID" > /tmp/api-id.txt
fi

echo ""
echo "=================================================="
echo "✅ Verificação concluída"
echo "=================================================="

