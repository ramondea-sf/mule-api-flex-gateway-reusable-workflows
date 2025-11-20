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

# Ler configurações
CONFIG_FILE="api/api-config.yaml"
ENV_FILE="api/${ENVIRONMENT}.yaml"

# Verificar se arquivo de ambiente existe
if [ ! -f "$ENV_FILE" ]; then
    echo "❌ Erro: Arquivo de ambiente não encontrado: $ENV_FILE"
    exit 1
fi

# Organization ID vem do config global
ORG_ID=$(yq eval '.organizationId' $CONFIG_FILE)

# Environment ID vem do arquivo de ambiente
ENV_ID=$(yq eval ".environment.environmentId" $ENV_FILE)

echo "🏢 Organização: $ORG_ID"
echo "🌍 Environment ID: $ENV_ID"
echo ""

# ============================================================================
# DEBUG: Mostrar todas as variáveis
# ============================================================================
echo "=================================================="
echo "🔍 DEBUG - Parâmetros de Verificação"
echo "=================================================="
echo "📁 Arquivos de configuração:"
echo "   CONFIG_FILE: $CONFIG_FILE"
echo "   ENV_FILE: $ENV_FILE"
echo ""
echo "🔍 Busca:"
echo "   API_NAME: $API_NAME"
echo "   ENVIRONMENT: $ENVIRONMENT"
echo "   INSTANCE_LABEL: ${API_NAME}-${ENVIRONMENT}"
echo ""
echo "🏢 Anypoint Platform:"
echo "   ORG_ID: $ORG_ID"
echo "   ENV_ID: $ENV_ID"
echo "=================================================="
echo ""

# Listar todas as APIs no API Manager
echo "📋 Listando APIs no API Manager..."

API_LIST=$(anypoint-cli-v4 api-mgr api list \
    --client_id "$ANYPOINT_CLIENT_ID" \
    --client_secret "$ANYPOINT_CLIENT_SECRET" \
    --organization "$ORG_ID" \
    --environment "$ENV_ID" \
    --output json 2>/dev/null || echo "[]")

# Debug: mostrar lista de APIs (primeiras 500 chars)
echo "DEBUG: Lista de APIs encontradas:"
echo "$API_LIST" | head -c 500
echo ""

# Verificar se a API existe (buscar por instanceLabel que contém o nome e ambiente)
INSTANCE_LABEL="${API_NAME}-${ENVIRONMENT}"

# Tentar buscar pela instanceLabel primeiro
API_ID=$(echo "$API_LIST" | jq -r ".assets[] | select(.instanceLabel==\"$INSTANCE_LABEL\") | .id" 2>/dev/null | head -n 1)

# Se não encontrar, tentar buscar pelo nome da API
if [ -z "$API_ID" ] || [ "$API_ID" == "null" ]; then
    API_ID=$(echo "$API_LIST" | jq -r ".assets[] | select(.assetId==\"$API_NAME\") | .id" 2>/dev/null | head -n 1)
fi

if [ -z "$API_ID" ] || [ "$API_ID" == "null" ]; then
    echo "❌ API não encontrada no API Manager"
    echo "ℹ️  Buscando por instanceLabel: $INSTANCE_LABEL ou assetId: $API_NAME"
    
    if [ -n "$GITHUB_OUTPUT" ]; then
        echo "api-exists=false" >> $GITHUB_OUTPUT
    fi
    echo "false" > /tmp/api-exists.txt
else
    echo "✅ API encontrada no API Manager"
    echo "📋 API ID: $API_ID"
    
    # Obter mais detalhes da API
    API_DETAILS=$(echo "$API_LIST" | jq -r ".assets[] | select(.id==$API_ID)")
    CURRENT_VERSION=$(echo "$API_DETAILS" | jq -r '.assetVersion // "unknown"')
    
    echo "📋 Versão atual: $CURRENT_VERSION"
    
    if [ -n "$GITHUB_OUTPUT" ]; then
        echo "api-exists=true" >> $GITHUB_OUTPUT
        echo "api-id=$API_ID" >> $GITHUB_OUTPUT
        echo "current-version=$CURRENT_VERSION" >> $GITHUB_OUTPUT
    fi
    
    echo "true" > /tmp/api-exists.txt
    echo "$API_ID" > /tmp/api-id.txt
    echo "$CURRENT_VERSION" > /tmp/current-api-version.txt
fi

echo ""
echo "=================================================="
echo "✅ Verificação concluída"
echo "=================================================="

