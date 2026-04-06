# Lacrei Saúde — DevOps Challenge

Pipeline de deploy seguro, escalável e eficiente para ambientes de staging e produção na AWS.

---

## Índice

- [Arquitetura](#arquitetura)
- [Tecnologias utilizadas](#tecnologias-utilizadas)
- [Setup dos ambientes](#setup-dos-ambientes)
- [Fluxo de CI/CD](#fluxo-de-cicd)
- [Segurança](#segurança)
- [Observabilidade](#observabilidade)
- [Rollback](#rollback)
- [Proposta de integração com Asaas](#proposta-de-integração-com-asaas)
- [Erros encontrados e decisões técnicas](#erros-encontrados-e-decisões-técnicas)
- [Checklist de segurança](#checklist-de-segurança)
- [Feedback recebido e melhorias aplicadas](#feedback-recebido-e-melhorias-aplicadas)
- [Ferramentas de IA utilizadas](#ferramentas-de-ia-utilizadas)

---

## Arquitetura

```
GitHub Repository
       │
       ├── branch staging ──► Deploy Staging  (107.22.123.27:3000)
       │
       └── branch main ────► Deploy Production (100.29.209.58:3000)
                                    ▲
                              aprovação manual
```

### Infraestrutura AWS (provisionada via Terraform)

- VPC dedicada com subnet pública
- Internet Gateway + Route Table
- 2 instâncias EC2 t2.micro com Docker e AWS CLI instalados via user_data
- Elastic IPs fixos para cada instância
- ECR privado com scan on push e tag immutability
- IAM Role com permissões mínimas (ECR pull + CloudWatch logs)
- CloudWatch Log Groups para staging (7 dias) e produção (30 dias)
- Security Groups com regras por ambiente

---

## Tecnologias utilizadas

| Tecnologia | Finalidade |
|---|---|
| Node.js 20 LTS | Aplicação fictícia |
| Docker | Containerização |
| Terraform | Infraestrutura como código |
| GitHub Actions | Pipeline CI/CD |
| AWS EC2 | Hospedagem dos containers |
| AWS ECR | Registro de imagens Docker |
| AWS IAM | Controle de acesso com menor privilégio |
| AWS CloudWatch | Logs e monitoramento |
| ESLint | Lint do código |

---

## Setup dos ambientes

### Pré-requisitos

- Conta AWS ativa
- Terraform instalado
- AWS CLI configurado (`aws configure`)
- Node.js 20 LTS
- Docker

### Provisionar infraestrutura

```bash
cd infra/
terraform init
terraform apply
```

Os outputs exibirão os IPs e URLs de cada ambiente.

### Configurar secrets no GitHub

Acesse **Settings → Secrets and variables → Actions** e adicione:

| Secret | Descrição |
|---|---|
| `AWS_ACCESS_KEY_ID` | Access Key da conta AWS |
| `AWS_SECRET_ACCESS_KEY` | Secret Key da conta AWS |
| `AWS_REGION` | Região AWS (ex: us-east-1) |
| `ECR_REPOSITORY` | URL do repositório ECR |
| `STAGING_HOST` | IP público do EC2 staging |
| `PRODUCTION_HOST` | IP público do EC2 produção |
| `EC2_SSH_KEY` | Conteúdo do arquivo .pem |
| `ALLOWED_ORIGINS` | Origens permitidas no CORS |

---

## Fluxo de CI/CD

```
┌─────────────────────────────────────────────────────┐
│                   branch staging                     │
│                       │                              │
│                       ▼                              │
│              ┌─────────────────┐                     │
│              │  Build & Test   │                     │
│              │  - lint         │                     │
│              │  - docker build │                     │
│              │  - testes       │                     │
│              └────────┬────────┘                     │
│                       │                              │
│                       ▼                              │
│           ┌───────────────────────┐                  │
│           │    Deploy Staging     │                  │
│           │  push ECR + SSH EC2   │                  │
│           │  validação /status    │                  │
│           └───────────────────────┘                  │
└─────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────┐
│              Pull Request staging → main             │
│                  (aprovação manual)                  │
│                       │                              │
│                       ▼                              │
│              ┌─────────────────┐                     │
│              │  Build & Test   │                     │
│              └────────┬────────┘                     │
│                       │                              │
│                       ▼                              │
│     ┌─────────────────────────────────────┐          │
│     │  Aprovação manual obrigatória        │          │
│     │  (GitHub Environment: production)   │          │
│     └──────────────────┬──────────────────┘          │
│                        │                             │
│                        ▼                             │
│           ┌───────────────────────┐                  │
│           │   Deploy Production   │                  │
│           │  push ECR + SSH EC2   │                  │
│           │  validação /status    │                  │
│           └───────────────────────┘                  │
└─────────────────────────────────────────────────────┘
```

### Detalhes do pipeline

- **Lint:** ESLint valida o código antes de qualquer build
- **Build & Test:** build da imagem Docker, sobe o container e valida o `/status` com teste Node.js
- **Deploy Staging:** ativado apenas por push no branch `staging` — push ECR com tag `staging-{SHA}`, deploy via SSH, validação pós-deploy
- **Aprovação manual:** deploy em produção exige aprovação de revisor no GitHub Environment `production`
- **Deploy Production:** ativado apenas por push no branch `main` — push ECR com tag `prod-{SHA}`, deploy via SSH, validação pós-deploy

---

## Segurança

### Princípio do menor privilégio

- IAM Role da EC2 com permissões mínimas: apenas ECR pull e CloudWatch logs
- Credenciais AWS gerenciadas via GitHub Secrets — nunca expostas no código
- Security Groups com portas mínimas necessárias por ambiente

### Container

- Dockerfile multi-stage para imagem enxuta
- Usuário não-root dentro do container (`appuser`)
- HEALTHCHECK configurado
- `.dockerignore` impedindo arquivos sensíveis na imagem

### Headers de segurança

A API retorna os seguintes headers em todas as respostas:

- `X-Content-Type-Options: nosniff`
- `X-Frame-Options: DENY`
- `X-XSS-Protection: 1; mode=block`
- `Access-Control-Allow-Origin` controlado por variável de ambiente `ALLOWED_ORIGINS`

### HTTPS/TLS — Proposta de implementação

Configurar Nginx como reverse proxy com certificado SSL via Let's Encrypt (Certbot):

```bash
sudo apt install -y nginx certbot python3-certbot-nginx
sudo certbot --nginx -d api.lacrei.com.br
```

Configuração do Nginx:

```nginx
server {
    listen 443 ssl;
    server_name api.lacrei.com.br;

    ssl_certificate /etc/letsencrypt/live/api.lacrei.com.br/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/api.lacrei.com.br/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;

    location / {
        proxy_pass http://localhost:3000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-Proto https;
    }
}

server {
    listen 80;
    server_name api.lacrei.com.br;
    return 301 https://$host$request_uri;
}
```

> Nota: HTTPS requer um domínio registrado. Para ambientes de teste sem domínio, pode-se utilizar certificado autoassinado ou AWS Certificate Manager com Load Balancer.

---

## Observabilidade

### Logs

- CloudWatch Log Group `/lacrei/staging` com retenção de 7 dias
- CloudWatch Log Group `/lacrei/production` com retenção de 30 dias
- Logs do container acessíveis via:

```bash
docker logs lacrei-staging
docker logs lacrei-production
```

### Acessar logs no CloudWatch

1. Acesse **CloudWatch → Log Groups**
2. Selecione `/lacrei/staging` ou `/lacrei/production`

### Proposta de alarmes

| Alarme | Métrica | Threshold | Ação |
|---|---|---|---|
| CPU alta staging | CPUUtilization | > 80% por 2 períodos | SNS → e-mail/Slack |
| CPU alta produção | CPUUtilization | > 80% por 2 períodos | SNS → e-mail/Slack |
| Falha no deploy | GitHub Actions | Qualquer falha | Notificação GitHub |

> Alarmes não implementados para evitar custos no ambiente de teste ($0.10/alarme/mês).

---

## Rollback

### Como executar rollback

Cada deploy é taggeado com o SHA do commit. Para reverter:

```bash
export STAGING_HOST=107.22.123.27
export PRODUCTION_HOST=100.29.209.58
export SSH_KEY_PATH=/caminho/para/lacrei-key.pem
export AWS_REGION=us-east-1
export ECR_REPOSITORY=653306034196.dkr.ecr.us-east-1.amazonaws.com/lacrei-api

# Rollback staging
./scripts/rollback.sh staging staging-{SHA_ANTERIOR}

# Rollback produção
./scripts/rollback.sh production prod-{SHA_ANTERIOR}
```

### Localizar SHA anterior

```bash
aws ecr list-images --repository-name lacrei-api --region us-east-1
```

Ou via console AWS → ECR → lacrei-api → tags disponíveis.

### Estratégias de rollback

| Estratégia | Descrição | Status |
|---|---|---|
| Revert de imagem Docker | Redeployar imagem anterior via script | Implementado |
| Git revert | Reverter commit no GitHub dispara pipeline automaticamente | Disponível |
| Blue/Green | Dois containers rodando com alternância via Nginx upstream | Proposta |

---

## Proposta de integração com Asaas

### Visão geral

A Asaas é uma plataforma de pagamentos com API REST. A integração seria utilizada para split de pagamento entre profissionais de saúde e a plataforma Lacrei.

### Fluxo proposto

```
Cliente
   │
   ▼
Lacrei API ──► POST /v3/payments (Asaas API)
                    │
                    ├──► Cobrança criada
                    │
                    └──► Webhook Asaas ──► Lacrei API /webhook/asaas
                                               │
                                               └──► Atualiza status do pagamento
```

### Endpoints principais

| Método | Endpoint Asaas | Descrição |
|---|---|---|
| POST | `/v3/payments` | Criar cobrança com split |
| GET | `/v3/payments/{id}` | Consultar cobrança |
| POST | `/v3/transfers` | Transferência entre carteiras |
| POST | `/v3/customers` | Criar cliente |

### Segurança na integração

- API Key armazenada no **AWS Secrets Manager**
- Validação de assinatura nos webhooks
- HTTPS obrigatório em todas as chamadas
- Variável `ASAAS_API_KEY` injetada no container via secret

### Exemplo de payload com split

```json
{
  "customer": "cus_000000000001",
  "billingType": "PIX",
  "value": 150.00,
  "dueDate": "2026-04-30",
  "description": "Consulta médica - Lacrei Saúde",
  "split": [
    {
      "walletId": "wallet_profissional_123",
      "percentualValue": 80
    },
    {
      "walletId": "wallet_lacrei_456",
      "percentualValue": 20
    }
  ]
}
```

---

## Erros encontrados e decisões técnicas

| Erro | Causa | Solução |
|---|---|---|
| `package-lock.json` ausente | `npm ci` exige lockfile | Rodado `npm install` localmente para gerar |
| `src/index.js` não encontrado no Docker | Arquivo estava na raiz em vez da pasta `src/` | Criada pasta `src/` e movido o arquivo |
| Dockerfile com formatação RTF | Arquivo criado com Bloco de Notas | Recriado via `Set-Content` no PowerShell |
| Sem VPC padrão na AWS | Conta AWS sem VPC default | Criada VPC completa via Terraform |
| SSH timeout do GitHub Actions | IPs dinâmicos do Actions bloqueados | Porta 22 aberta para `0.0.0.0/0` temporariamente |
| `aws: command not found` na EC2 | AWS CLI não instalado via user_data | Instalado manualmente via SSH; corrigido no user_data.sh |
| `docker: command not found` na EC2 | Instâncias recriadas perderam instalação | Reinstalado Docker via SSH |
| Pipe `\|` quebrado no SSH Action | appleboy/ssh-action não suporta pipe inline | Substituído por variável intermediária `TOKEN` |
| Tag imutável no ECR | `staging-latest` não pode ser sobrescrita | Removida tag `latest`, usando apenas SHA do commit |
| Recursos já existentes no Terraform | `terraform destroy` não limpou tudo | Usado `terraform import` para reimportar recursos |

---

## Checklist de segurança

- [x] Secrets gerenciados via GitHub Secrets
- [x] Credenciais AWS nunca expostas no código
- [x] IAM Role com permissões mínimas nas instâncias EC2
- [x] Usuário não-root no container Docker
- [x] Dockerfile multi-stage
- [x] HEALTHCHECK configurado no container
- [x] Headers de segurança na API
- [x] CORS configurado via variável de ambiente
- [x] Tag immutability no ECR
- [x] Scan on push ativado no ECR
- [x] Aprovação manual obrigatória antes do deploy em produção
- [x] Lint no pipeline (ESLint)
- [x] Testes automatizados no pipeline
- [x] Fluxo de promoção staging → produção via branches
- [x] Logs com retenção configurada no CloudWatch
- [x] Alerta de billing configurado na AWS
- [x] `.gitignore` protegendo arquivos sensíveis e de estado
- [ ] HTTPS/TLS (proposto via Nginx + Let's Encrypt — requer domínio)
- [ ] Alarmes CloudWatch (proposto — não implementado para evitar custos)
- [ ] AWS Secrets Manager para secrets da aplicação (proposto)

---

## Feedback recebido e melhorias aplicadas

**Pontos de melhoria identificados e como foram resolvidos:**

| Ponto de melhoria | Como foi resolvido |
|---|---|
| HTTPS/TLS apenas como proposta documental | Adicionada proposta detalhada com configuração Nginx + Let's Encrypt e explicação sobre requisito de domínio |
| Restrição de acesso em portas públicas | Security Groups revisados; porta 22 documentada como temporariamente aberta para CI/CD via GitHub Actions |
| Logs realmente acessíveis e monitoramento operacional | CloudWatch Log Groups provisionados via Terraform com retenção configurada por ambiente |
| Ausência de lint no pipeline | ESLint adicionado como etapa obrigatória antes do build |
| Inconsistência nos testes | Teste corrigido para rodar após o container subir, garantindo que o `/status` está acessível |
| Arquivos não versionados no repositório | `.gitignore` atualizado para excluir `node_modules`, `terraform.tfstate`, `.terraform/` e binários |
| Fluxo de promoção staging → produção pouco claro | Branches dedicados criados (`staging` e `main`) com pipeline separado por ambiente e aprovação manual obrigatória para produção |

### Patch de mudanças — v1 para v2

```
v1 (primeira entrega)                    v2 (entrega revisada)
─────────────────────────────────────── ────────────────────────────────────────
Pipeline rodava em main para ambos       Branch staging → deploy staging
os ambientes                             Branch main → deploy produção

Sem etapa de lint                        ESLint adicionado como etapa obrigatória

Teste rodava sem container ativo         Container sobe antes dos testes

node_modules e tfstate versionados       .gitignore corrigido, arquivos removidos

user_data.sh incompleto                  user_data.sh instala Docker + AWS CLI
                                         automaticamente na criação da instância

IAM Role criada separadamente            IAM Role, policy e instance profile
                                         consolidados no main.tf

CloudWatch em arquivo separado           CloudWatch integrado ao main.tf
```

---

## Ferramentas de IA utilizadas

Durante o desenvolvimento deste projeto, contei com o auxílio de ferramentas de inteligência artificial para apoiar diferentes etapas do trabalho. Quero deixar isso registrado com transparência, pois acredito que o uso consciente dessas ferramentas faz parte da rotina moderna de desenvolvimento.

**Claude (Anthropic)** e **Gemini (Google)** foram utilizados para:

- Formatação e revisão do README
- Revisão de código (Dockerfile, pipeline YAML, scripts Terraform)
- Suporte durante a implementação do CI/CD — etapa onde encontrei mais dificuldades práticas por não ter experiência prévia consolidada com GitHub Actions e integração SSH em instâncias EC2

O uso dessas ferramentas não substituiu o aprendizado técnico — pelo contrário, cada erro encontrado e cada decisão tomada ao longo do processo foram compreendidos e documentados. As IAs funcionaram como um par de programação que ajudou a acelerar a resolução de problemas e a melhorar a qualidade da documentação, mantendo o protagonismo técnico e o entendimento do que foi construído.

Acredito que saber utilizar bem essas ferramentas é, em si, uma habilidade relevante no mercado de DevOps atual.
