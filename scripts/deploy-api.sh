#!/bin/bash

# Script para registrar ou atualizar API no API Manager
# Uso: ./deploy-api.sh <api-name> <api-version> <environment> <api-exists>
#
# Este script cria ou atualiza uma API no API Manager usando a CLI v4

set -e

API_NAME=$1
API_VERSION=$2  # Recebe version.current do workflow
ENVIRONMENT=$3
API_EXISTS=$4

echo "=================================================="
echo "🚀 Deploy da API no API Manager"
echo "=================================================="
echo "API: $API_NAME"
echo "Versão da especificação: $API_VERSION"
echo "Ambiente: $ENVIRONMENT"
echo "API existe: $API_EXISTS"
echo ""

# Ler configurações
CONFIG_FILE="api/api-config.yaml"
ENV_FILE="api/${ENVIRONMENT}.yaml"

# Verificar se arquivo de ambiente existe
if [ ! -f "$ENV_FILE" ]; then
    echo "❌ Erro: Arquivo de ambiente não encontrado: $ENV_FILE"
    exit 1
fi

# Extrair configurações GLOBAIS (do api-config.yaml)
ORG_ID=$(yq eval '.organizationId' $CONFIG_FILE)
PROJECT_ACRONYM=$(yq eval '.api.projectAcronym' $CONFIG_FILE)
PATH_STRATEGY=$(yq eval '.version.pathStrategy' $CONFIG_FILE)
EXPOSURE_TYPE=$(yq eval '.api.exposureType' $CONFIG_FILE)

# Extrair configurações ESPECÍFICAS do AMBIENTE (do arquivo ${ENVIRONMENT}.yaml)
ENV_ID=$(yq eval ".environment.environmentId" $ENV_FILE)
UPSTREAM_URL=$(yq eval ".environment.upstreamUrl" $ENV_FILE)
BASE_PATH=$(yq eval ".environment.basePath" $ENV_FILE)

# Validar exposureType
if [ "$EXPOSURE_TYPE" != "public" ] && [ "$EXPOSURE_TYPE" != "internal" ]; then
    echo "⚠️  Aviso: exposureType inválido. Usando 'public' por padrão"
    EXPOSURE_TYPE="public"
fi

echo "🌐 Tipo de exposição: $EXPOSURE_TYPE"

# Ler informações do Exchange (geradas pelo script anterior)
GROUP_ID=$(cat /tmp/exchange-group-id.txt)
ASSET_ID=$(cat /tmp/exchange-asset-id.txt)
DEPLOY_VERSION=$(cat /tmp/version-to-deploy.txt)

# ============================================================================
# DEBUG: Mostrar todas as variáveis
# ============================================================================
echo ""
echo "=================================================="
echo "🔍 DEBUG - Variáveis de Deploy"
echo "=================================================="
echo "📁 Arquivos de configuração:"
echo "   CONFIG_FILE: $CONFIG_FILE"
echo "   ENV_FILE: $ENV_FILE"
echo ""
echo "📦 Informações da API:"
echo "   API_NAME: $API_NAME"
echo "   API_VERSION (spec): $API_VERSION"
echo "   DEPLOY_VERSION (a deployar): $DEPLOY_VERSION"
echo "   API_EXISTS: $API_EXISTS"
echo ""
echo "🏢 Anypoint Platform:"
echo "   ORG_ID: $ORG_ID"
echo "   ENV_ID: $ENV_ID"
echo "   ENVIRONMENT: $ENVIRONMENT"
echo ""
echo "📦 Exchange Asset:"
echo "   GROUP_ID: $GROUP_ID"
echo "   ASSET_ID: $ASSET_ID"
echo "   DEPLOY_VERSION: $DEPLOY_VERSION"
echo ""
echo "🌐 Configurações de Gateway:"
echo "   UPSTREAM_URL: $UPSTREAM_URL"
echo "   BASE_PATH: $BASE_PATH"
echo "   EXPOSURE_TYPE: $EXPOSURE_TYPE"
echo "   PATH_STRATEGY: $PATH_STRATEGY"
echo "   PROJECT_ACRONYM: $PROJECT_ACRONYM"
echo ""
echo "📋 Path que será exposto:"
echo "   VERSION_PATH será calculado com base em PATH_STRATEGY"
echo "=================================================="
echo ""

# Construir o path exposto baseado na estratégia de versionamento
case $PATH_STRATEGY in
    "major")
        VERSION_PATH="v$(echo $DEPLOY_VERSION | cut -d'.' -f1)"
        ;;
    "major-minor")
        VERSION_PATH="v$(echo $DEPLOY_VERSION | cut -d'.' -f1,2 | tr '.' '_')"
        ;;
    "full")
        VERSION_PATH="v$(echo $DEPLOY_VERSION | tr '.' '_')"
        ;;
    "none")
        VERSION_PATH=""
        ;;
    *)
        VERSION_PATH="v$(echo $DEPLOY_VERSION | cut -d'.' -f1)"
        ;;
esac

# Construir o path final: /api/{acronym}/{version}/{base-path}
if [ -n "$VERSION_PATH" ]; then
    EXPOSED_PATH="/api/$(echo $PROJECT_ACRONYM | tr '[:upper:]' '[:lower:]')/$VERSION_PATH$BASE_PATH"
else
    EXPOSED_PATH="/api/$(echo $PROJECT_ACRONYM | tr '[:upper:]' '[:lower:]')$BASE_PATH"
fi

echo ""
echo "=================================================="
echo "✅ Path Final Calculado"
echo "=================================================="
echo "   Estratégia: $PATH_STRATEGY"
echo "   Versão: $DEPLOY_VERSION"
echo "   VERSION_PATH: $VERSION_PATH"
echo "   PROJECT_ACRONYM: $(echo $PROJECT_ACRONYM | tr '[:upper:]' '[:lower:]')"
echo "   BASE_PATH: $BASE_PATH"
echo ""
echo "🌐 PATH EXPOSTO FINAL:"
echo "   $EXPOSED_PATH"
echo "=================================================="
echo ""
echo "📋 Resumo da Configuração:"
echo "   Organization ID: $ORG_ID"
echo "   Environment ID: $ENV_ID"
echo "   Upstream URL: $UPSTREAM_URL"
echo "   Tipo de exposição: $EXPOSURE_TYPE"
echo ""

# Salvar tipo de exposição para uso em políticas
echo "$EXPOSURE_TYPE" > /tmp/exposure-type.txt

# Verificar se precisa criar ou atualizar
if [ "$API_EXISTS" == "true" ] && [ -f "/tmp/api-id.txt" ]; then
    # Atualizar API existente
    API_ID=$(cat /tmp/api-id.txt)
    CURRENT_VERSION=$(cat /tmp/current-api-version.txt 2>/dev/null || echo "unknown")
    
    echo "🔄 Atualizando API existente (ID: $API_ID)..."
    echo "   Versão atual: $CURRENT_VERSION"
    echo "   Nova versão: $DEPLOY_VERSION"
    
    # Verificar se a versão é diferente
    if [ "$CURRENT_VERSION" != "$DEPLOY_VERSION" ]; then
        echo "🔄 Versão diferente detectada, atualizando..."
        
        # Atualizar a API com a nova versão do Exchange
        # Nota: Não existe comando direto para atualizar apenas a versão
        # Precisamos usar o comando 'api-mgr api manage' ou recriar
        
        # Opção 1: Deletar e recriar (mais seguro para mudança de versão)
        echo "⚠️  Para trocar versão, é necessário recriar a API"
        echo "⚠️  Políticas e configurações serão perdidas"
        read -p "Continuar? (y/n) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "❌ Operação cancelada pelo usuário"
            exit 1
        fi
        
        # Deletar API antiga
        echo "🗑️  Removendo API antiga..."
        anypoint-cli-v4 api-mgr api delete \
            --organization "$ORG_ID" \
            --environment "$ENV_ID" \
            --apiId "$API_ID" || true
        
        # Aguardar um pouco
        sleep 2
        
        # Marcar para criar nova
        API_EXISTS="false"
    else
        echo "✅ Mesma versão, mantendo API existente"
        echo "ℹ️  Para atualizar upstream ou configurações, use o API Manager UI"
    fi
fi

# Criar nova API (ou recriar após delete)
if [ "$API_EXISTS" != "true" ]; then
    echo "📝 Registrando nova API no API Manager..."
    
    # Determinar o tipo de endpoint baseado no exposureType
    # Para Flex Gateway, sempre usamos proxyUri (não muleVersion4OrAbove)
    ENDPOINT_TYPE="proxyUri"
    
    # Construir comando para criar API
    # Nota: O comando varia dependendo da versão da CLI
    echo "🔨 Criando API Manager instance..."
    
    # Criar a API usando a sintaxe correta do anypoint-cli-v4
    RESULT=$(anypoint-cli-v4 api-mgr api manage \
        --organization "$ORG_ID" \
        --environment "$ENV_ID" \
        --type "rest-api" \
        --apiVersion "$DEPLOY_VERSION" \
        --withProxy \
        --uri "$EXPOSED_PATH" \
        --proxyUri "$UPSTREAM_URL" \
        --deploymentType "hybrid" \
        --scheme "https" \
        --port 443 \
        --path "$EXPOSED_PATH" \
        --muleVersion4OrAbove \
        --groupId "$GROUP_ID" \
        --assetId "$ASSET_ID" \
        --assetVersion "$DEPLOY_VERSION" \
        --instanceLabel "$API_NAME-$ENVIRONMENT" \
        --output json 2>&1 || echo '{"error": true}')
    
    echo "DEBUG: Resultado da criação:"
    echo "$RESULT"
    echo ""
    
    # Tentar extrair API ID do resultado
    API_ID=$(echo "$RESULT" | jq -r '.id // empty' 2>/dev/null)
    
    # Se não conseguir pelo JSON, tentar outra abordagem
    if [ -z "$API_ID" ] || [ "$API_ID" == "null" ]; then
        # Aguardar um pouco e listar novamente para pegar o ID
        echo "⏳ Aguardando propagação..."
        sleep 3
        
        API_LIST=$(anypoint-cli-v4 api-mgr api list \
            --organization "$ORG_ID" \
            --environment "$ENV_ID" \
            --output json 2>/dev/null || echo "[]")
        
        INSTANCE_LABEL="${API_NAME}-${ENVIRONMENT}"
        API_ID=$(echo "$API_LIST" | jq -r ".assets[] | select(.instanceLabel==\"$INSTANCE_LABEL\") | .id" 2>/dev/null | head -n 1)
    fi
    
    if [ -z "$API_ID" ] || [ "$API_ID" == "null" ]; then
        echo "❌ Erro ao criar API no API Manager"
        echo "Resultado: $RESULT"
        echo ""
        echo "⚠️  Verifique se:"
        echo "   1. Os IDs de organização e ambiente estão corretos"
        echo "   2. A Connected App tem permissões suficientes"
        echo "   3. O asset existe no Exchange"
        exit 1
    fi
    
    echo "✅ API registrada com sucesso!"
    echo "📋 API ID: $API_ID"
fi

# Salvar informações para próximos jobs
echo "$API_ID" > /tmp/api-id.txt
echo "$EXPOSED_PATH" > /tmp/exposed-path.txt
echo "$DEPLOY_VERSION" > /tmp/deployed-version.txt

echo ""
echo "=================================================="
echo "✅ Deploy da API concluído"
echo "=================================================="
echo "API ID: $API_ID"
echo "Path exposto: $EXPOSED_PATH"
echo "Versão deployada: $DEPLOY_VERSION"
echo "=================================================="

