#!/bin/bash

# Script para aplicar políticas de segurança no API Manager
# Uso: ./apply-policies.sh <api-id> <environment> <cluster> <is-public>
#
# Este script:
# 1. Lista políticas existentes na API
# 2. Carrega políticas corporativas (baseadas em ambiente/cluster/isPublic)
# 3. Carrega políticas customizadas da API
# 4. Aplica políticas de forma inteligente (apenas novas ou alteradas)

set -e

API_ID=$1
ENVIRONMENT=$2
CLUSTER=$3
IS_PUBLIC=$4

echo "=================================================="
echo "🔒 Aplicando Políticas de Segurança"
echo "=================================================="
echo "API ID: $API_ID"
echo "Ambiente: $ENVIRONMENT"
echo "Cluster: $CLUSTER"
echo "API Pública: $IS_PUBLIC"
echo ""

# Ler configurações
CONFIG_FILE="api/api-config.yaml"
ENV_FILE="api/${ENVIRONMENT}.yaml"

# Verificar se arquivo de ambiente existe
if [ ! -f "$ENV_FILE" ]; then
    echo "❌ Erro: Arquivo de ambiente não encontrado: $ENV_FILE"
    exit 1
fi

# Extrair configurações
ORG_ID=$(yq eval '.organizationId' $CONFIG_FILE)
ENV_ID=$(yq eval ".environment.environmentId" $ENV_FILE)

echo "🏢 Organization ID: $ORG_ID"
echo "🌍 Environment ID: $ENV_ID"
echo ""

# ============================================================================
# PASSO 1: LISTAR POLÍTICAS EXISTENTES
# ============================================================================
echo "=================================================="
echo "🔍 PASSO 1: Listar políticas existentes"
echo "=================================================="

# Desabilitar exit on error temporariamente
set +e
EXISTING_POLICIES=$(anypoint-cli-v4 api-mgr:policy:list "$API_ID" \
    --client_id "$ANYPOINT_CLIENT_ID" \
    --client_secret "$ANYPOINT_CLIENT_SECRET" \
    --organization "$ORG_ID" \
    --environment "$ENV_ID" \
    --output json 2>/dev/null)

LIST_STATUS=$?
set -e

if [ $LIST_STATUS -ne 0 ]; then
    echo "⚠️  Erro ao listar políticas existentes. Assumindo que não há políticas."
    EXISTING_POLICIES="[]"
fi

# Validar se é um array JSON válido
if ! echo "$EXISTING_POLICIES" | jq empty 2>/dev/null; then
    EXISTING_POLICIES="[]"
fi

POLICY_COUNT=$(echo "$EXISTING_POLICIES" | jq 'length' 2>/dev/null || echo "0")
echo "📊 Políticas existentes: $POLICY_COUNT"

if [ "$POLICY_COUNT" != "0" ]; then
    echo "$EXISTING_POLICIES" | jq -r '.[] | "   - \(.template.assetId) v\(.template.assetVersion) (ID: \(.id), Order: \(.order // "N/A"))"' 2>/dev/null || true
fi
echo ""

# ============================================================================
# PASSO 2: CARREGAR POLÍTICAS CORPORATIVAS
# ============================================================================
echo "=================================================="
echo "🏢 PASSO 2: Carregar políticas corporativas"
echo "=================================================="

# Determinar o tipo de gateway baseado em isPublic
if [ "$IS_PUBLIC" == "true" ]; then
    GATEWAY_TYPE="public"
else
    GATEWAY_TYPE="private"
fi

# Path para arquivo de políticas corporativas
# Estrutura: policies/corporate/{environment}/{cluster}/{gateway-type}.yaml
CORPORATE_POLICIES_FILE="policies/corporate/${ENVIRONMENT}/${CLUSTER}/${GATEWAY_TYPE}.yaml"

echo "🔍 Buscando políticas corporativas em: $CORPORATE_POLICIES_FILE"

# Criar array vazio se arquivo não existir
if [ ! -f "$CORPORATE_POLICIES_FILE" ]; then
    echo "ℹ️  Arquivo de políticas corporativas não encontrado. Usando apenas políticas da API."
    CORPORATE_POLICIES="[]"
else
    echo "✅ Arquivo de políticas corporativas encontrado"
    # Não fazemos nada aqui, usaremos o arquivo diretamente com yq
fi

# ============================================================================
# PASSO 3: CARREGAR POLÍTICAS DA API
# ============================================================================
echo ""
echo "=================================================="
echo "📦 PASSO 3: Carregar políticas da API"
echo "=================================================="

# Verificar se a seção policies existe no arquivo de ambiente
POLICIES_SECTION=$(yq eval '.policies' "$ENV_FILE" 2>/dev/null)

if [ "$POLICIES_SECTION" == "null" ] || [ -z "$POLICIES_SECTION" ]; then
    echo "ℹ️  Nenhuma política customizada definida no arquivo de ambiente"
    API_POLICIES="[]"
fi

echo ""

# ============================================================================
# PASSO 4: MESCLAR E APLICAR POLÍTICAS
# ============================================================================
echo "=================================================="
echo "🔨 PASSO 4: Processar e aplicar políticas"
echo "=================================================="

# Função para aplicar uma política
apply_policy() {
    local POLICY_NAME=$1
    local POLICY_GROUP_ID=$2
    local POLICY_VERSION=$3
    local POLICY_CONFIG=$4
    local POLICY_ORDER=$5
    local POLICY_TYPE=$6  # inbound ou outbound
    
    echo ""
    echo "📝 Aplicando política: $POLICY_NAME"
    echo "   Versão: $POLICY_VERSION"
    echo "   Ordem: $POLICY_ORDER"
    echo "   Tipo: $POLICY_TYPE"
    echo "   Group ID: $POLICY_GROUP_ID"
    
    # Verificar se política já existe
    EXISTING_POLICY=$(echo "$EXISTING_POLICIES" | jq -c ".[] | select(.template.assetId==\"$POLICY_NAME\" and .template.assetVersion==\"$POLICY_VERSION\")" 2>/dev/null | head -n 1)
    
    if [ -n "$EXISTING_POLICY" ] && [ "$EXISTING_POLICY" != "null" ]; then
        POLICY_ID=$(echo "$EXISTING_POLICY" | jq -r '.id' 2>/dev/null)
        echo "   ✅ Política já existe (ID: $POLICY_ID)"
        echo "   ℹ️  Pulando aplicação (políticas são imutáveis)"
        return 0
    fi
    
    echo "   🔨 Aplicando nova política..."
    
    # Mostrar todos os parâmetros recebidos
    echo ""
    echo "   📋 DEBUG - Parâmetros Recebidos:"
    echo "   ================================"
    echo "   POLICY_NAME: $POLICY_NAME"
    echo "   POLICY_GROUP_ID: $POLICY_GROUP_ID"
    echo "   POLICY_VERSION: $POLICY_VERSION"
    echo "   POLICY_ORDER: $POLICY_ORDER"
    echo "   POLICY_TYPE: $POLICY_TYPE"
    echo "   API_ID: $API_ID"
    echo "   ORG_ID: $ORG_ID"
    echo "   ENV_ID: $ENV_ID"
    echo ""
    
    # Mostrar configuração (se houver)
    if [ -n "$POLICY_CONFIG" ] && [ "$POLICY_CONFIG" != "null" ] && [ "$POLICY_CONFIG" != "{}" ]; then
        echo "   📝 Configuração da Política (YAML→JSON):"
        echo "$POLICY_CONFIG" | jq . 2>/dev/null || echo "$POLICY_CONFIG"
        echo ""
    else
        echo "   ⚠️  Nenhuma configuração fornecida para esta política"
        echo "   ⚠️  Se a política requer configuração obrigatória, o comando falhará!"
        echo ""
    fi
    
    # Construir comando com sintaxe correta
    # Sintaxe: api-mgr:policy:apply [flags] <apiInstanceId> <policyId>
    CMD="anypoint-cli-v4 api-mgr:policy:apply"
    CMD="$CMD --client_id \"$ANYPOINT_CLIENT_ID\""
    CMD="$CMD --client_secret \"$ANYPOINT_CLIENT_SECRET\""
    CMD="$CMD --organization \"$ORG_ID\""
    CMD="$CMD --environment \"$ENV_ID\""
    CMD="$CMD --groupId \"$POLICY_GROUP_ID\""
    CMD="$CMD --policyVersion \"$POLICY_VERSION\""
    CMD="$CMD --output json"
    
    # Adicionar pointcut (obrigatório para definir onde a política se aplica)
    # O pointcut define os métodos e URIs onde a política será aplicada
    POINTCUT_JSON='[{"methodRegex":".*","uriTemplateRegex":".*"}]'
    CMD="$CMD --pointcut '$POINTCUT_JSON'"
    
    # Adicionar configuração se fornecida via arquivo
    HAS_CONFIG=false
    CONFIG_FILE_PATH=""
    
    if [ -n "$POLICY_CONFIG" ] && [ "$POLICY_CONFIG" != "null" ] && [ "$POLICY_CONFIG" != "{}" ]; then
        # Validar JSON
        if echo "$POLICY_CONFIG" | jq empty 2>/dev/null; then
            # Criar arquivo temporário com a configuração
            CONFIG_FILE_PATH="/tmp/policy-config-${API_ID}-${POLICY_NAME}-$$.json"
            echo "$POLICY_CONFIG" | jq . > "$CONFIG_FILE_PATH"
            
            CMD="$CMD --configFile '$CONFIG_FILE_PATH'"
            HAS_CONFIG=true
            
            echo "   📄 Arquivo de configuração criado: $CONFIG_FILE_PATH"
        else
            echo "   ⚠️  AVISO: Configuração JSON inválida, tentando aplicar sem config"
            echo "   JSON problemático: $POLICY_CONFIG"
        fi
    fi
    
    # Adicionar API ID e Policy ID (asset name) como argumentos posicionais
    CMD="$CMD \"$API_ID\" \"$POLICY_NAME\""
    
    # Mostrar comando completo (mascarando credenciais)
    echo "   📋 DEBUG - Comando Completo a Executar:"
    echo "   ========================================"
    DISPLAY_CMD="anypoint-cli-v4 api-mgr:policy:apply"
    DISPLAY_CMD="$DISPLAY_CMD --client_id \"***\""
    DISPLAY_CMD="$DISPLAY_CMD --client_secret \"***\""
    DISPLAY_CMD="$DISPLAY_CMD --organization \"$ORG_ID\""
    DISPLAY_CMD="$DISPLAY_CMD --environment \"$ENV_ID\""
    DISPLAY_CMD="$DISPLAY_CMD --groupId \"$POLICY_GROUP_ID\""
    DISPLAY_CMD="$DISPLAY_CMD --policyVersion \"$POLICY_VERSION\""
    DISPLAY_CMD="$DISPLAY_CMD --output json"
    DISPLAY_CMD="$DISPLAY_CMD --pointcut '$POINTCUT_JSON'"
    
    if [ "$HAS_CONFIG" = true ]; then
        DISPLAY_CMD="$DISPLAY_CMD --configFile '$CONFIG_FILE_PATH'"
        echo "$DISPLAY_CMD \"$API_ID\" \"$POLICY_NAME\""
        echo ""
        echo "   📝 Conteúdo do arquivo de configuração:"
        cat "$CONFIG_FILE_PATH" | jq . 2>/dev/null || cat "$CONFIG_FILE_PATH"
    else
        echo "$DISPLAY_CMD \"$API_ID\" \"$POLICY_NAME\""
    fi
    
    echo ""
    
    # Executar comando
    echo "   🚀 Executando comando..."
    set +e
    APPLY_RESULT=$(eval $CMD 2>&1)
    APPLY_STATUS=$?
    set -e
    
    echo ""
    if [ $APPLY_STATUS -ne 0 ]; then
        echo "   ❌ ERRO ao aplicar política!"
        echo ""
        echo "   📋 Detalhes do Erro:"
        echo "   ===================="
        echo "$APPLY_RESULT" | head -n 50  # Limitar para não poluir muito
        echo ""
        echo "   💡 Possíveis Causas:"
        echo "   • Política requer configuração obrigatória (verifique docs da política)"
        echo "   • JSON de configuração mal formatado"
        echo "   • Group ID ou Policy Version incorretos"
        echo "   • Política não existe no Exchange"
        echo "   • Permissões insuficientes do Connected App"
        echo ""
        
        # Tentar identificar erro específico
        if echo "$APPLY_RESULT" | grep -qi "schema"; then
            echo "   ⚠️  ERRO DE SCHEMA DETECTADO!"
            echo "   Esta política provavelmente requer configuração obrigatória."
            echo "   Verifique se a configuração está correta no arquivo YAML."
            echo ""
        fi
        
        if echo "$APPLY_RESULT" | grep -qi "not found"; then
            echo "   ⚠️  POLÍTICA NÃO ENCONTRADA!"
            echo "   Verifique:"
            echo "   • Policy Name: $POLICY_NAME"
            echo "   • Group ID: $POLICY_GROUP_ID"
            echo "   • Version: $POLICY_VERSION"
            echo ""
        fi
        
        # Limpar arquivo temporário
        [ -n "$CONFIG_FILE_PATH" ] && [ -f "$CONFIG_FILE_PATH" ] && rm -f "$CONFIG_FILE_PATH"
        
        return 1
    else
        echo "   ✅ Política aplicada com sucesso!"
        echo ""
        
        # Mostrar resultado completo
        echo "   📋 Resposta da API:"
        echo "$APPLY_RESULT" | jq . 2>/dev/null || echo "$APPLY_RESULT"
        echo ""
        
        # Tentar extrair ID da política aplicada
        NEW_POLICY_ID=$(echo "$APPLY_RESULT" | jq -r '.id // empty' 2>/dev/null)
        if [ -n "$NEW_POLICY_ID" ]; then
            echo "   📋 Policy ID aplicada: $NEW_POLICY_ID"
        fi
        
        # Limpar arquivo temporário
        [ -n "$CONFIG_FILE_PATH" ] && [ -f "$CONFIG_FILE_PATH" ] && rm -f "$CONFIG_FILE_PATH"
    fi
    
    return 0
}

# ============================================================================
# PROCESSAR POLÍTICAS CORPORATIVAS (se existirem)
# ============================================================================
if [ -f "$CORPORATE_POLICIES_FILE" ]; then
    echo ""
    echo "🏢 Processando políticas corporativas..."
    
    # Processar políticas inbound
    CORPORATE_INBOUND_COUNT=$(yq eval '.policies.inbound | length' "$CORPORATE_POLICIES_FILE" 2>/dev/null || echo "0")
    
    if [ "$CORPORATE_INBOUND_COUNT" != "0" ] && [ "$CORPORATE_INBOUND_COUNT" != "null" ]; then
        echo ""
        echo "📥 Políticas Inbound Corporativas: $CORPORATE_INBOUND_COUNT"
        
        for i in $(seq 0 $((CORPORATE_INBOUND_COUNT - 1))); do
            ENABLED=$(yq eval ".policies.inbound[$i].enabled" "$CORPORATE_POLICIES_FILE" 2>/dev/null)
            
            if [ "$ENABLED" == "true" ]; then
                NAME=$(yq eval ".policies.inbound[$i].name" "$CORPORATE_POLICIES_FILE" 2>/dev/null)
                VERSION=$(yq eval ".policies.inbound[$i].version" "$CORPORATE_POLICIES_FILE" 2>/dev/null)
                GROUP_ID=$(yq eval ".policies.inbound[$i].groupId" "$CORPORATE_POLICIES_FILE" 2>/dev/null)
                ORDER=$(yq eval ".policies.inbound[$i].order" "$CORPORATE_POLICIES_FILE" 2>/dev/null)
                
                # Converter configuração YAML para JSON
                CONFIG_JSON=$(yq eval ".policies.inbound[$i].configuration" "$CORPORATE_POLICIES_FILE" -o=json 2>/dev/null || echo "{}")
                
                apply_policy "$NAME" "$GROUP_ID" "$VERSION" "$CONFIG_JSON" "$ORDER" "inbound"
            fi
        done
    fi
    
    # Processar políticas outbound
    CORPORATE_OUTBOUND_COUNT=$(yq eval '.policies.outbound | length' "$CORPORATE_POLICIES_FILE" 2>/dev/null || echo "0")
    
    if [ "$CORPORATE_OUTBOUND_COUNT" != "0" ] && [ "$CORPORATE_OUTBOUND_COUNT" != "null" ]; then
        echo ""
        echo "📤 Políticas Outbound Corporativas: $CORPORATE_OUTBOUND_COUNT"
        
        for i in $(seq 0 $((CORPORATE_OUTBOUND_COUNT - 1))); do
            ENABLED=$(yq eval ".policies.outbound[$i].enabled" "$CORPORATE_POLICIES_FILE" 2>/dev/null)
            
            if [ "$ENABLED" == "true" ]; then
                NAME=$(yq eval ".policies.outbound[$i].name" "$CORPORATE_POLICIES_FILE" 2>/dev/null)
                VERSION=$(yq eval ".policies.outbound[$i].version" "$CORPORATE_POLICIES_FILE" 2>/dev/null)
                GROUP_ID=$(yq eval ".policies.outbound[$i].groupId" "$CORPORATE_POLICIES_FILE" 2>/dev/null)
                ORDER=$(yq eval ".policies.outbound[$i].order" "$CORPORATE_POLICIES_FILE" 2>/dev/null)
                
                # Converter configuração YAML para JSON
                CONFIG_JSON=$(yq eval ".policies.outbound[$i].configuration" "$CORPORATE_POLICIES_FILE" -o=json 2>/dev/null || echo "{}")
                
                apply_policy "$NAME" "$GROUP_ID" "$VERSION" "$CONFIG_JSON" "$ORDER" "outbound"
            fi
        done
    fi
fi

# ============================================================================
# PROCESSAR POLÍTICAS DA API (customizadas)
# ============================================================================
echo ""
echo "📦 Processando políticas customizadas da API..."

# Processar políticas inbound
API_INBOUND_COUNT=$(yq eval '.policies.inbound | length' "$ENV_FILE" 2>/dev/null || echo "0")

if [ "$API_INBOUND_COUNT" != "0" ] && [ "$API_INBOUND_COUNT" != "null" ]; then
    echo ""
    echo "📥 Políticas Inbound da API: $API_INBOUND_COUNT"
    
    for i in $(seq 0 $((API_INBOUND_COUNT - 1))); do
        ENABLED=$(yq eval ".policies.inbound[$i].enabled" "$ENV_FILE" 2>/dev/null)
        
        if [ "$ENABLED" == "true" ]; then
            NAME=$(yq eval ".policies.inbound[$i].name" "$ENV_FILE" 2>/dev/null)
            VERSION=$(yq eval ".policies.inbound[$i].version" "$ENV_FILE" 2>/dev/null)
            GROUP_ID=$(yq eval ".policies.inbound[$i].groupId" "$ENV_FILE" 2>/dev/null)
            ORDER=$(yq eval ".policies.inbound[$i].order" "$ENV_FILE" 2>/dev/null)
            
            # Converter configuração YAML para JSON
            CONFIG_JSON=$(yq eval ".policies.inbound[$i].configuration" "$ENV_FILE" -o=json 2>/dev/null || echo "{}")
            
            apply_policy "$NAME" "$GROUP_ID" "$VERSION" "$CONFIG_JSON" "$ORDER" "inbound"
        fi
    done
fi

# Processar políticas outbound
API_OUTBOUND_COUNT=$(yq eval '.policies.outbound | length' "$ENV_FILE" 2>/dev/null || echo "0")

if [ "$API_OUTBOUND_COUNT" != "0" ] && [ "$API_OUTBOUND_COUNT" != "null" ]; then
    echo ""
    echo "📤 Políticas Outbound da API: $API_OUTBOUND_COUNT"
    
    for i in $(seq 0 $((API_OUTBOUND_COUNT - 1))); do
        ENABLED=$(yq eval ".policies.outbound[$i].enabled" "$ENV_FILE" 2>/dev/null)
        
        if [ "$ENABLED" == "true" ]; then
            NAME=$(yq eval ".policies.outbound[$i].name" "$ENV_FILE" 2>/dev/null)
            VERSION=$(yq eval ".policies.outbound[$i].version" "$ENV_FILE" 2>/dev/null)
            GROUP_ID=$(yq eval ".policies.outbound[$i].groupId" "$ENV_FILE" 2>/dev/null)
            ORDER=$(yq eval ".policies.outbound[$i].order" "$ENV_FILE" 2>/dev/null)
            
            # Converter configuração YAML para JSON
            CONFIG_JSON=$(yq eval ".policies.outbound[$i].configuration" "$ENV_FILE" -o=json 2>/dev/null || echo "{}")
            
            apply_policy "$NAME" "$GROUP_ID" "$VERSION" "$CONFIG_JSON" "$ORDER" "outbound"
        fi
    done
fi

echo ""
echo "=================================================="
echo "✅ Aplicação de políticas concluída"
echo "=================================================="
echo "API ID: $API_ID"
echo "Ambiente: $ENVIRONMENT"
echo "Cluster: $CLUSTER"
echo "Gateway Type: $GATEWAY_TYPE"
echo ""
echo "📊 Próximos passos:"
echo "   1. Verificar políticas no API Manager"
echo "   2. Testar endpoint com políticas aplicadas"
echo "=================================================="


