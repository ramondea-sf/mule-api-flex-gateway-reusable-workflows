#!/bin/bash

# Script para publicar especificação da API no Exchange
# Uso: ./publish-to-exchange.sh <api-name> <api-version> <environment>

set -e

API_NAME=$1
API_VERSION=$2
ENVIRONMENT=$3

echo "=================================================="
echo "📦 Publicando API no Exchange"
echo "=================================================="
echo "API: $API_NAME"
echo "Versão: $API_VERSION"
echo "Ambiente: $ENVIRONMENT"
echo ""

# Instalar yq se não estiver disponível
if ! command -v yq &> /dev/null; then
    echo "Instalando yq..."
    sudo wget -qO /usr/local/bin/yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64
    sudo chmod +x /usr/local/bin/yq
fi

# Ler configuração
CONFIG_FILE="api/api-config.yaml"

# Extrair informações do arquivo de configuração
SWAGGER_PATH=$(yq eval '.api.swaggerPath' $CONFIG_FILE)
DESCRIPTION=$(yq eval '.api.description' $CONFIG_FILE)
PROJECT_ACRONYM=$(yq eval '.api.projectAcronym' $CONFIG_FILE)
SPEC_TYPE=$(yq eval '.api.specType' $CONFIG_FILE)
ORG_ID=$(yq eval ".environments.$ENVIRONMENT.organizationId" $CONFIG_FILE)

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
  "tags": ["rest-api", "flex-gateway", "$PROJECT_ACRONYM", "$ENVIRONMENT"],
  "dependencies": [],
  "properties": {
    "apiVersion": "v1",
    "mainFile": "api.yaml"
  }
}
EOF

echo "📝 Metadados do Exchange criados"

# Verificar se a API já existe no Exchange
echo ""
echo "🔍 Verificando se a API já existe no Exchange..."

# Listar assets do Exchange
ASSET_ID="${ORG_ID}/${API_NAME}"
EXISTING_VERSIONS=$(anypoint-cli-v4 exchange asset describe \
    --organization "$ORG_ID" \
    "$ASSET_ID" 2>/dev/null | grep -o '"version":"[^"]*"' | cut -d'"' -f4 || echo "")

if echo "$EXISTING_VERSIONS" | grep -q "$API_VERSION"; then
    echo "⚠️  Versão $API_VERSION já existe no Exchange"
    echo "📝 Atualizando asset existente..."
    ACTION="update"
else
    echo "✅ Versão $API_VERSION não existe, criando nova versão..."
    ACTION="create"
fi

# Publicar no Exchange
echo ""
echo "📤 Publicando no Exchange..."

cd "$TEMP_DIR"

# Upload do asset usando Anypoint CLI v4
anypoint-cli-v4 exchange asset upload \
    --organization "$ORG_ID" \
    --name "$API_NAME" \
    --version "$API_VERSION" \
    --apiVersion "v1" \
    --type "rest-api" \
    --classifier "$SPEC_TYPE" \
    --files @api.yaml \
    --properties @exchange.json

if [ $? -eq 0 ]; then
    echo "✅ API publicada com sucesso no Exchange!"
    echo ""
    echo "📋 Detalhes:"
    echo "   Asset ID: $ASSET_ID"
    echo "   Versão: $API_VERSION"
    
    # Salvar Asset ID para uso posterior
    echo "$ASSET_ID" > /tmp/exchange-asset-id.txt
    echo "$API_VERSION" >> /tmp/exchange-asset-id.txt
    
    # Link para o Exchange (construído dinamicamente)
    EXCHANGE_URL="https://anypoint.mulesoft.com/exchange/$ORG_ID/$API_NAME/$API_VERSION"
    echo "   URL: $EXCHANGE_URL"
else
    echo "❌ Erro ao publicar no Exchange"
    exit 1
fi

# Limpar diretório temporário
cd -
rm -rf "$TEMP_DIR"

echo ""
echo "=================================================="
echo "✅ Publicação no Exchange concluída"
echo "=================================================="

