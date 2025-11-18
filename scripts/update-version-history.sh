#!/bin/bash

# Script para atualizar histórico de versões
# Uso: ./update-version-history.sh <version> <environment> <commit-hash>

set -e

VERSION=$1
ENVIRONMENT=$2
COMMIT_HASH=$3

echo "=================================================="
echo "📝 Atualizando Histórico de Versões"
echo "=================================================="
echo "Versão: $VERSION"
echo "Ambiente: $ENVIRONMENT"
echo "Commit: $COMMIT_HASH"
echo ""

VERSION_FILE="api/version.yaml"

# Obter timestamp atual em formato ISO 8601
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Obter usuário que fez o deploy
DEPLOYED_BY="${GITHUB_ACTOR:-github-actions}"

echo "🕐 Timestamp: $TIMESTAMP"
echo "👤 Deployed by: $DEPLOYED_BY"
echo ""

# Atualizar a versão atual do ambiente
yq eval -i ".environments.$ENVIRONMENT.current = \"$VERSION\"" "$VERSION_FILE"

# Verificar se a versão já existe no histórico
EXISTING_VERSION=$(yq eval ".environments.$ENVIRONMENT.history[] | select(.version == \"$VERSION\") | .version" "$VERSION_FILE")

if [ -n "$EXISTING_VERSION" ]; then
    echo "🔄 Versão $VERSION já existe no histórico, atualizando..."
    
    # Atualizar entrada existente
    HISTORY_LENGTH=$(yq eval ".environments.$ENVIRONMENT.history | length" "$VERSION_FILE")
    
    for i in $(seq 0 $((HISTORY_LENGTH - 1))); do
        HIST_VERSION=$(yq eval ".environments.$ENVIRONMENT.history[$i].version" "$VERSION_FILE")
        
        if [ "$HIST_VERSION" == "$VERSION" ]; then
            yq eval -i ".environments.$ENVIRONMENT.history[$i].deployedAt = \"$TIMESTAMP\"" "$VERSION_FILE"
            yq eval -i ".environments.$ENVIRONMENT.history[$i].deployedBy = \"$DEPLOYED_BY\"" "$VERSION_FILE"
            yq eval -i ".environments.$ENVIRONMENT.history[$i].commitHash = \"$COMMIT_HASH\"" "$VERSION_FILE"
            yq eval -i ".environments.$ENVIRONMENT.history[$i].status = \"active\"" "$VERSION_FILE"
            break
        fi
    done
else
    echo "➕ Adicionando nova versão ao histórico..."
    
    # Adicionar nova entrada ao histórico
    yq eval -i ".environments.$ENVIRONMENT.history += [{
        \"version\": \"$VERSION\",
        \"deployedAt\": \"$TIMESTAMP\",
        \"deployedBy\": \"$DEPLOYED_BY\",
        \"commitHash\": \"$COMMIT_HASH\",
        \"status\": \"active\"
    }]" "$VERSION_FILE"
fi

echo "✅ Histórico atualizado!"
echo ""
echo "📋 Conteúdo atualizado:"
yq eval ".environments.$ENVIRONMENT" "$VERSION_FILE"

echo ""
echo "=================================================="
echo "✅ Atualização do histórico concluída"
echo "=================================================="

