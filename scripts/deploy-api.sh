#!/bin/bash

# Script para registrar ou atualizar API no API Manager
# Uso: ./deploy-api.sh <api-name> <api-version> <environment> <api-exists>

set -e

API_NAME=$1
API_VERSION=$2
ENVIRONMENT=$3
API_EXISTS=$4

echo "=================================================="
echo "🚀 Deploy da API no API Manager"
echo "=================================================="
echo "API: $API_NAME"
echo "Versão: $API_VERSION"
echo "Ambiente: $ENVIRONMENT"
echo "API existe: $API_EXISTS"
echo ""

# Ler configuração
CONFIG_FILE="api/api-config.yaml"

# Extrair configurações do ambiente
ENV_ID=$(yq eval ".environments.$ENVIRONMENT.environmentId" $CONFIG_FILE)
ORG_ID=$(yq eval ".environments.$ENVIRONMENT.organizationId" $CONFIG_FILE)
UPSTREAM_URL=$(yq eval ".environments.$ENVIRONMENT.upstreamUrl" $CONFIG_FILE)
BASE_PATH=$(yq eval ".environments.$ENVIRONMENT.basePath" $CONFIG_FILE)
PROJECT_ACRONYM=$(yq eval '.api.projectAcronym' $CONFIG_FILE)
PATH_STRATEGY=$(yq eval '.version.pathStrategy' $CONFIG_FILE)
EXPOSURE_TYPE=$(yq eval '.api.exposureType' $CONFIG_FILE)

# Validar exposureType
if [ "$EXPOSURE_TYPE" != "public" ] && [ "$EXPOSURE_TYPE" != "internal" ]; then
    echo "⚠️  Aviso: exposureType inválido. Usando 'public' por padrão"
    EXPOSURE_TYPE="public"
fi

echo "🌐 Tipo de exposição: $EXPOSURE_TYPE"

# Construir o path exposto baseado na estratégia de versionamento
case $PATH_STRATEGY in
    "major")
        VERSION_PATH="v$(echo $API_VERSION | cut -d'.' -f1)"
        ;;
    "major-minor")
        VERSION_PATH="v$(echo $API_VERSION | cut -d'.' -f1,2 | tr '.' '_')"
        ;;
    "full")
        VERSION_PATH="v$(echo $API_VERSION | tr '.' '_')"
        ;;
    "none")
        VERSION_PATH=""
        ;;
    *)
        VERSION_PATH="v$(echo $API_VERSION | cut -d'.' -f1)"
        ;;
esac

# Construir o path final: /api/{acronym}/{version}/{base-path}
if [ -n "$VERSION_PATH" ]; then
    EXPOSED_PATH="/api/$(echo $PROJECT_ACRONYM | tr '[:upper:]' '[:lower:]')/$VERSION_PATH$BASE_PATH"
else
    EXPOSED_PATH="/api/$(echo $PROJECT_ACRONYM | tr '[:upper:]' '[:lower:]')$BASE_PATH"
fi

echo "📋 Configurações:"
echo "   Organization ID: $ORG_ID"
echo "   Environment ID: $ENV_ID"
echo "   Upstream URL: $UPSTREAM_URL"
echo "   Path exposto: $EXPOSED_PATH"
echo "   Tipo de exposição: $EXPOSURE_TYPE"
echo ""

# Salvar tipo de exposição para uso em políticas
echo "$EXPOSURE_TYPE" > /tmp/exposure-type.txt

# Ler Asset ID do Exchange
ASSET_ID=$(head -n 1 /tmp/exchange-asset-id.txt)
ASSET_VERSION=$(tail -n 1 /tmp/exchange-asset-id.txt)

echo "📦 Exchange Asset:"
echo "   Asset ID: $ASSET_ID"
echo "   Versão: $ASSET_VERSION"
echo ""

# Verificar se precisa criar ou atualizar
if [ "$API_EXISTS" == "true" ] && [ -f "/tmp/api-id.txt" ]; then
    # Atualizar API existente
    API_ID=$(cat /tmp/api-id.txt)
    
    echo "🔄 Atualizando API existente (ID: $API_ID)..."
    
    # Atualizar a versão da especificação
    anypoint-cli-v4 api-mgr api manage \
        --organization "$ORG_ID" \
        --environment "$ENV_ID" \
        --apiId "$API_ID" \
        --apiVersion "$API_VERSION" \
        --withPolicies true
    
    # Atualizar upstream
    echo "🔄 Atualizando upstream..."
    anypoint-cli-v4 api-mgr proxy update \
        --organization "$ORG_ID" \
        --environment "$ENV_ID" \
        --apiId "$API_ID" \
        --targetUrl "$UPSTREAM_URL"
    
    echo "✅ API atualizada com sucesso!"
    
else
    # Criar nova API
    echo "📝 Registrando nova API no API Manager..."
    
    # Criar arquivo de configuração temporário para a API
    TEMP_CONFIG=$(mktemp)
    
    cat > "$TEMP_CONFIG" <<EOF
{
  "spec": {
    "groupId": "$(echo $ASSET_ID | cut -d'/' -f1)",
    "assetId": "$(echo $ASSET_ID | cut -d'/' -f2)",
    "version": "$ASSET_VERSION"
  },
  "endpoint": {
    "deploymentType": "HF",
    "uri": "$EXPOSED_PATH",
    "proxyUri": "$UPSTREAM_URL",
    "isCloudHub": false
  },
  "instanceLabel": "$API_NAME-$ENVIRONMENT"
}
EOF

    echo "📄 Configuração da API:"
    cat "$TEMP_CONFIG" | jq .
    echo ""
    
    # Criar API no API Manager (Connected Gateway)
    RESULT=$(anypoint-cli-v4 api-mgr api create \
        --organization "$ORG_ID" \
        --environment "$ENV_ID" \
        --name "$API_NAME" \
        --assetId "$(echo $ASSET_ID | cut -d'/' -f2)" \
        --assetVersion "$ASSET_VERSION" \
        --instanceLabel "$API_NAME-$ENVIRONMENT" \
        --targetUrl "$UPSTREAM_URL" \
        --proxyType "hybrid" \
        --output json)
    
    API_ID=$(echo "$RESULT" | jq -r '.id')
    
    if [ -z "$API_ID" ] || [ "$API_ID" == "null" ]; then
        echo "❌ Erro ao criar API no API Manager"
        echo "$RESULT"
        exit 1
    fi
    
    echo "✅ API registrada com sucesso!"
    echo "📋 API ID: $API_ID"
    
    # Salvar API ID
    echo "$API_ID" > /tmp/api-id.txt
    
    rm -f "$TEMP_CONFIG"
fi

# Salvar informações para próximos jobs
echo "$API_ID" > /tmp/api-id.txt
echo "$EXPOSED_PATH" > /tmp/exposed-path.txt

echo ""
echo "=================================================="
echo "✅ Deploy da API concluído"
echo "=================================================="
echo "API ID: $API_ID"
echo "Path exposto: $EXPOSED_PATH"
echo "=================================================="

