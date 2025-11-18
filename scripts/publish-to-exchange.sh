#!/bin/bash

# Script para publicar especificação da API no Exchange
# Uso: ./publish-to-exchange.sh <api-name> <api-version> <environment>
#
# IMPORTANTE: Este script SEMPRE publica version.current do api-config.yaml
# O controle de qual versão deployar no Gateway é feito via deployedVersion

set -e

API_NAME=$1
API_VERSION=$2  # Recebe version.current do workflow
ENVIRONMENT=$3

echo "=================================================="
echo "📦 Publicando API no Exchange"
echo "=================================================="
echo "API: $API_NAME"
echo "Versão a publicar: $API_VERSION"
echo "Ambiente: $ENVIRONMENT"
echo ""

# Instalar yq se não estiver disponível
if ! command -v yq &> /dev/null; then
    echo "Instalando yq..."
    sudo wget -qO /usr/local/bin/yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64
    sudo chmod +x /usr/local/bin/yq
fi

# Ler configurações globais
CONFIG_FILE="api/api-config.yaml"
ENV_FILE="api/${ENVIRONMENT}.yaml"

# Verificar se arquivo de ambiente existe
if [ ! -f "$ENV_FILE" ]; then
    echo "❌ Erro: Arquivo de ambiente não encontrado: $ENV_FILE"
    exit 1
fi

# Extrair informações do arquivo de configuração global
SWAGGER_PATH=$(yq eval '.api.swaggerPath' $CONFIG_FILE)
DESCRIPTION=$(yq eval '.api.description' $CONFIG_FILE)
PROJECT_ACRONYM=$(yq eval '.api.projectAcronym' $CONFIG_FILE)
SPEC_TYPE=$(yq eval '.api.specType' $CONFIG_FILE)
ORG_ID=$(yq eval '.organizationId' $CONFIG_FILE)

# Verificar qual versão será deployada no Gateway (lê do arquivo de ambiente)
DEPLOYED_VERSION=$(yq eval ".environment.deployedVersion" $ENV_FILE)

if [ -z "$DEPLOYED_VERSION" ] || [ "$DEPLOYED_VERSION" == "null" ] || [ "$DEPLOYED_VERSION" == "" ]; then
    DEPLOYED_VERSION=$API_VERSION
    echo "ℹ️  Versão para deploy no Gateway: $DEPLOYED_VERSION (usando version.current)"
else
    echo "ℹ️  Versão para deploy no Gateway: $DEPLOYED_VERSION (configurada em deployedVersion)"
fi

# Validar specType
if [ "$SPEC_TYPE" != "oas" ] && [ "$SPEC_TYPE" != "raml" ]; then
    echo "❌ Erro: specType inválido. Use 'oas' ou 'raml'"
    exit 1
fi

echo "📋 Tipo de especificação: $SPEC_TYPE"

# Validar se o arquivo swagger existe
if [ ! -f "$SWAGGER_PATH" ]; then
    echo "❌ Erro: Arquivo Swagger não encontrado: $SWAGGER_PATH"
    exit 1
fi

echo "📄 Arquivo Swagger: $SWAGGER_PATH"
echo "🏢 Organização: $ORG_ID"
echo ""

# Verificar se a versão já existe no Exchange
echo "🔍 Verificando se versão $API_VERSION já existe no Exchange..."

GROUP_ID=$ORG_ID
ASSET_ID=$API_NAME

# Tentar descrever o asset específico
VERSION_EXISTS=$(anypoint-cli-v4 exchange asset describe \
    --organization "$GROUP_ID" \
    --groupId "$GROUP_ID" \
    --assetId "$ASSET_ID" \
    --version "$API_VERSION" \
    --output json 2>/dev/null || echo "")

if [ -n "$VERSION_EXISTS" ] && [ "$VERSION_EXISTS" != "null" ]; then
    echo "⚠️  Versão $API_VERSION já existe no Exchange"
    echo "ℹ️  Pulando publicação (versões no Exchange são imutáveis)"
    echo ""
    echo "✅ Usando asset existente: $GROUP_ID:$ASSET_ID:$API_VERSION"
    
    # Salvar informações para próximos jobs
    echo "$GROUP_ID" > /tmp/exchange-group-id.txt
    echo "$ASSET_ID" > /tmp/exchange-asset-id.txt
    echo "$DEPLOYED_VERSION" > /tmp/exchange-version.txt
    
    # Salvar também a versão deployada
    echo "$DEPLOYED_VERSION" > /tmp/version-to-deploy.txt
    
    echo ""
    echo "=================================================="
    echo "✅ Verificação concluída - Asset já existe"
    echo "=================================================="
    exit 0
fi

echo "✅ Versão $API_VERSION não existe, publicando nova versão..."

# Criar diretório temporário para preparar o asset
TEMP_DIR=$(mktemp -d)
echo "📁 Diretório temporário: $TEMP_DIR"

# Copiar arquivo Swagger
cp "$SWAGGER_PATH" "$TEMP_DIR/api.yaml"

# Criar exchange.json com metadados
cat > "$TEMP_DIR/exchange.json" <<EOF
{
  "name": "$API_NAME",
  "description": "$DESCRIPTION",
  "tags": ["rest-api", "flex-gateway", "$PROJECT_ACRONYM"],
  "properties": {
    "apiVersion": "v1",
    "mainFile": "api.yaml"
  }
}
EOF

echo "📝 Metadados do Exchange criados"

# Publicar no Exchange
echo ""
echo "📤 Publicando no Exchange..."

cd "$TEMP_DIR"

# Upload do asset usando Anypoint CLI v4
# Nota: O comando upload cria uma nova versão ou sobrescreve se permitido
anypoint-cli-v4 exchange asset upload \
    --organization "$GROUP_ID" \
    --groupId "$GROUP_ID" \
    --assetId "$ASSET_ID" \
    --version "$API_VERSION" \
    --name "$API_NAME" \
    --type "rest-api" \
    --classifier "$SPEC_TYPE" \
    --apiVersion "v1" \
    --files api.yaml \
    --properties exchange.json

UPLOAD_STATUS=$?

cd - > /dev/null

# Limpar diretório temporário
rm -rf "$TEMP_DIR"

if [ $UPLOAD_STATUS -eq 0 ]; then
    echo "✅ API publicada com sucesso no Exchange!"
    echo ""
    echo "📋 Detalhes:"
    echo "   Group ID: $GROUP_ID"
    echo "   Asset ID: $ASSET_ID"
    echo "   Versão publicada: $API_VERSION"
    echo "   Versão para deploy: $DEPLOYED_VERSION"
    
    # Salvar informações para uso posterior
    echo "$GROUP_ID" > /tmp/exchange-group-id.txt
    echo "$ASSET_ID" > /tmp/exchange-asset-id.txt
    echo "$DEPLOYED_VERSION" > /tmp/exchange-version.txt
    
    # Salvar também a versão que será deployada
    echo "$DEPLOYED_VERSION" > /tmp/version-to-deploy.txt
    
    # Link para o Exchange (construído dinamicamente)
    EXCHANGE_URL="https://anypoint.mulesoft.com/exchange/$GROUP_ID/$ASSET_ID/$API_VERSION"
    echo "   URL: $EXCHANGE_URL"
else
    echo "❌ Erro ao publicar no Exchange"
    exit 1
fi

echo ""
echo "=================================================="
echo "✅ Publicação no Exchange concluída"
echo "=================================================="

