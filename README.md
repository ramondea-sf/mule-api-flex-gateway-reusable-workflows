# Pipeline de Deploy de APIs para Flex Gateway

Este repositório contém uma pipeline automatizada usando GitHub Actions para publicar e gerenciar APIs no MuleSoft Flex Gateway através do Anypoint Platform.

## 📋 Índice

- [Visão Geral](#visão-geral)
- [Recursos](#recursos)
- [Pré-requisitos](#pré-requisitos)
- [Configuração Inicial](#configuração-inicial)
- [Estrutura do Projeto](#estrutura-do-projeto)
- [Como Usar](#como-usar)
- [Versionamento](#versionamento)
- [Ambientes](#ambientes)
- [Políticas](#políticas)
- [Alertas](#alertas)
- [Troubleshooting](#troubleshooting)

## 🎯 Visão Geral

Esta pipeline permite que times de desenvolvimento publiquem suas APIs no Exchange da MuleSoft e façam deploy automático no API Manager com Flex Gateway, incluindo:

- ✅ Publicação automática da especificação OpenAPI/Swagger no Exchange
- ✅ Registro e atualização de APIs no API Manager
- ✅ Deploy no Flex Gateway
- ✅ Aplicação automática de políticas
- ✅ Configuração de alertas e monitoramento
- ✅ Controle de versão usando SEMVER
- ✅ Padronização de paths expostos
- ✅ Suporte a múltiplos ambientes (dev, staging, prod)

## 🚀 Recursos

### Fluxo Automático

```
Push no GitHub
    ↓
Validação de Configuração
    ↓
Publicação no Exchange
    ↓
Verificação de API Existente
    ↓
    ├─→ API Existe → Atualizar versão + upstream + políticas + alertas
    │
    └─→ API Nova → Registrar + Deploy + Políticas + Alertas
    ↓
Atualização do Histórico de Versões
```

### Versionamento SEMVER

A pipeline suporta versionamento semântico completo (major.minor.patch) e permite diferentes estratégias de exposição do path:

- `major`: /api/crf/v1/minha-api
- `major-minor`: /api/crf/v1_0/minha-api
- `full`: /api/crf/v1_0_0/minha-api
- `none`: /api/crf/minha-api

### Padronização de Paths

Os paths são automaticamente padronizados seguindo o formato:

```
/api/{sigla-projeto}/{versão}/{base-path}
```

Exemplo: `/api/crf/v1/usuarios`

## 📦 Pré-requisitos

### No Anypoint Platform

1. **Connected App** (para autenticação):
   - Acesse: `Anypoint Platform → Access Management → Connected Apps`
   - Crie uma nova Connected App com as permissões:
     - Exchange Contributor
     - API Manager Environment Administrator
     - Runtime Manager Administrator
   - Anote o `Client ID` e `Client Secret`

2. **Organization ID** e **Environment IDs**:
   - Encontre em: `Anypoint Platform → Access Management → Organization`
   - Anote os IDs de cada ambiente (dev, staging, prod)

3. **Flex Gateway** configurado e rodando em cada ambiente

### No GitHub

1. Configure os Secrets no repositório:
   - `Settings → Secrets and variables → Actions → New repository secret`
   - Adicione:
     - `ANYPOINT_CLIENT_ID`: Client ID da Connected App
     - `ANYPOINT_CLIENT_SECRET`: Client Secret da Connected App

## ⚙️ Configuração Inicial

### 1. Clone o Repositório

```bash
git clone <seu-repositorio>
cd mule-api-flex-gateway-pipeline
```

### 2. Configure sua API

Edite o arquivo `api/api-config.yaml` com as informações da sua API:

```yaml
api:
  name: "minha-api"
  projectAcronym: "CRF"
  description: "Descrição da minha API"
  swaggerPath: "app/swagger.yaml"
  
version:
  current: "1.0.0"
  pathStrategy: "major"

environments:
  dev:
    enabled: true
    upstreamUrl: "https://dev-backend.exemplo.com"
    environmentId: "seu-env-id-dev"
    organizationId: "seu-org-id"
    basePath: "/minha-api"
```

### 3. Adicione seu Swagger/OpenAPI

Coloque o arquivo da especificação da sua API no caminho definido em `swaggerPath`:

```bash
# Exemplo:
cp seu-swagger.yaml app/swagger.yaml
```

### 4. Configure a Versão

Edite `api/version.yaml` para definir a versão inicial:

```yaml
current: "1.0.0"
```

## 📁 Estrutura do Projeto

```
.
├── .github/
│   └── workflows/
│       └── api-deployment.yml       # Workflow principal
├── api/
│   ├── api-config.yaml              # Configuração da API
│   └── version.yaml                 # Controle de versões
├── app/
│   └── swagger.yaml                 # Especificação OpenAPI/Swagger
├── scripts/
│   ├── publish-to-exchange.sh       # Script de publicação no Exchange
│   ├── check-api-exists.sh          # Verifica se API existe
│   ├── deploy-api.sh                # Deploy da API
│   ├── apply-policies.sh            # Aplica políticas
│   ├── configure-alerts.sh          # Configura alertas
│   └── update-version-history.sh    # Atualiza histórico
└── README.md
```

## 🎮 Como Usar

### Deploy Automático (Push)

1. **Ambiente DEV** - Push na branch `dev`:
```bash
git checkout dev
git add .
git commit -m "feat: adicionar nova API"
git push origin dev
```

2. **Ambiente STAGING** - Push na branch `staging`:
```bash
git checkout staging
git merge dev
git push origin staging
```

3. **Ambiente PROD** - Push na branch `main`:
```bash
git checkout main
git merge staging
git push origin main
```

### Deploy Manual (Workflow Dispatch)

Você também pode executar o deploy manualmente:

1. Acesse: `Actions → API Deployment Pipeline → Run workflow`
2. Selecione:
   - Branch desejada
   - Ambiente (dev/staging/prod)
   - Opção de forçar atualização (se necessário)
3. Clique em `Run workflow`

## 📌 Versionamento

### Como Atualizar a Versão

1. Edite o arquivo `api/api-config.yaml`:
```yaml
version:
  current: "1.1.0"  # Nova versão
```

2. Commit e push:
```bash
git add api/api-config.yaml
git commit -m "chore: bump version to 1.1.0"
git push
```

### Regras SEMVER

- **MAJOR** (X.0.0): Mudanças incompatíveis na API
- **MINOR** (x.Y.0): Novas funcionalidades compatíveis
- **PATCH** (x.y.Z): Correções de bugs compatíveis

Exemplo:
- `1.0.0` → `2.0.0`: Quebra compatibilidade
- `1.0.0` → `1.1.0`: Adiciona nova funcionalidade
- `1.0.0` → `1.0.1`: Corrige um bug

### Histórico de Versões

O arquivo `api/version.yaml` mantém automaticamente o histórico de todas as versões publicadas:

```yaml
environments:
  dev:
    current: "1.0.0"
    history:
      - version: "1.0.0"
        deployedAt: "2025-11-14T10:30:00Z"
        deployedBy: "github-actions"
        commitHash: "abc123"
        status: "active"
```

## 🌍 Ambientes

### Configuração por Ambiente

Cada ambiente pode ter configurações específicas:

```yaml
environments:
  dev:
    enabled: true                          # Habilitar deploy neste ambiente
    upstreamUrl: "https://dev.exemplo.com" # URL do backend
    environmentId: "dev-env-id"            # ID do ambiente no Anypoint
    organizationId: "org-id"               # ID da organização
    basePath: "/usuarios"                  # Path base da API
```

### Mapeamento Branch → Ambiente

| Branch    | Ambiente | Deploy Automático |
|-----------|----------|-------------------|
| `dev`     | dev      | ✅                |
| `staging` | staging  | ✅                |
| `main`    | prod     | ✅                |

## 🛡️ Políticas

### Políticas Pré-configuradas

O arquivo `api/api-config.yaml` inclui as seguintes políticas:

1. **Rate Limiting SLA-Based**
   - Limita requisições por período
   - Configurável por endpoint

2. **Client ID Enforcement**
   - Validação de client_id e client_secret
   - Obrigatório para controle de acesso

3. **CORS**
   - Cross-Origin Resource Sharing
   - Configuração de origens, métodos e headers permitidos

4. **JWT Validation** (Opcional)
   - Validação de tokens JWT
   - Integração com Identity Providers

### Adicionar Nova Política

Edite `api/api-config.yaml`:

```yaml
policies:
  - name: "nova-politica"
    enabled: true
    configuration:
      param1: "valor1"
      param2: "valor2"
    order: 5
```

### Desabilitar uma Política

```yaml
policies:
  - name: "jwt-validation"
    enabled: false  # Política não será aplicada
```

## 🔔 Alertas

### Tipos de Alertas Suportados

1. **Alta Taxa de Erro (5xx)**
```yaml
alerts:
  - name: "high-error-rate"
    enabled: true
    severity: "warning"
    condition:
      type: "response-code"
      codes: ["5xx"]
      threshold: 10
      periodMinutes: 5
```

2. **Violação de SLA (Response Time)**
```yaml
alerts:
  - name: "sla-violation"
    enabled: true
    severity: "critical"
    condition:
      type: "response-time"
      thresholdMs: 1000
      percentile: 95
      periodMinutes: 5
```

3. **Limite de Requisições**
```yaml
alerts:
  - name: "request-limit"
    enabled: true
    severity: "info"
    condition:
      type: "request-count"
      threshold: 1000
      periodMinutes: 1
```

### Configurar Notificações

```yaml
alerts:
  - name: "meu-alerta"
    notification:
      recipients:
        - "time-dev@exemplo.com"
        - "gestor@exemplo.com"
```

## 🔧 Troubleshooting

### Problema: Pipeline Falha na Validação

**Solução:**
1. Verifique se o arquivo `api/api-config.yaml` está correto
2. Confirme que o arquivo Swagger existe no path especificado
3. Valide a versão SEMVER (deve ser X.Y.Z)

### Problema: Erro ao Publicar no Exchange

**Solução:**
1. Verifique se o `ANYPOINT_CLIENT_ID` e `ANYPOINT_CLIENT_SECRET` estão configurados
2. Confirme as permissões da Connected App (Exchange Contributor)
3. Verifique se o `organizationId` está correto

### Problema: Erro ao Registrar API no API Manager

**Solução:**
1. Confirme que o `environmentId` está correto
2. Verifique se a Connected App tem permissões de API Manager
3. Valide se o Flex Gateway está configurado no ambiente

### Problema: Políticas Não São Aplicadas

**Solução:**
1. Verifique se as políticas estão habilitadas (`enabled: true`)
2. Confirme que seu plano do Anypoint Platform suporta as políticas
3. Valide a configuração JSON de cada política

### Problema: Alertas Não São Criados

**Solução:**
1. Verifique se sua organização tem permissões para criar alertas
2. Confirme que os emails dos destinatários estão corretos
3. Valide a configuração de cada alerta

### Ver Logs Detalhados

Para ver logs detalhados de um deploy:

1. Acesse: `Actions → Selecione o workflow → Clique no job com erro`
2. Expanda as etapas para ver logs completos

## 📚 Exemplos

### Exemplo 1: API REST Simples

```yaml
api:
  name: "usuarios-api"
  projectAcronym: "USR"
  description: "API de gerenciamento de usuários"
  swaggerPath: "app/usuarios-swagger.yaml"
  
version:
  current: "1.0.0"
  pathStrategy: "major"

environments:
  dev:
    enabled: true
    upstreamUrl: "https://dev-usuarios.exemplo.com"
    environmentId: "dev-env-id"
    organizationId: "org-id"
    basePath: "/usuarios"
```

**Path exposto:** `/api/usr/v1/usuarios`

### Exemplo 2: API com Autenticação JWT

```yaml
policies:
  - name: "jwt-validation"
    enabled: true
    configuration:
      jwtOrigin: "httpBearerAuthenticationHeader"
      signingMethod: "rsa"
      jwtKeyOrigin: "jwks"
      jwksUrl: "https://auth.exemplo.com/.well-known/jwks.json"
      jwksCacheTtl: 3600
      skipClientIdValidation: false
    order: 1
```

### Exemplo 3: Versionamento Completo no Path

```yaml
version:
  current: "1.2.3"
  pathStrategy: "full"
```

**Path exposto:** `/api/crf/v1_2_3/minha-api`

## 🤝 Contribuindo

Para contribuir com melhorias nesta pipeline:

1. Crie uma branch de feature: `git checkout -b feature/minha-melhoria`
2. Faça suas alterações
3. Commit: `git commit -m "feat: adicionar melhoria X"`
4. Push: `git push origin feature/minha-melhoria`
5. Abra um Pull Request

## 📄 Licença

Este projeto é de uso interno da organização.

## 🆘 Suporte

Para dúvidas ou problemas:

- 📧 Email: time-gateway@exemplo.com
- 💬 Slack: #api-gateway
- 📖 Documentação MuleSoft: https://docs.mulesoft.com/

---

**Desenvolvido com ❤️ pelo Time de Gateway**

