# DimDim WebApp – Checkpoint 2 (Aplicações e Banco em Nuvem)

API REST em **Java 17 + Spring Boot 3** com persistência em **Azure SQL Database (PaaS)**,
publicada em **Azure App Service (Web App)** via **Azure CLI** e monitorada com **Application Insights**.

## Integrantes

| Nome | RM |
|---|---|
| Felipe Maglio Filho | 563512 |
| Mateus Granja dos Santos | 564930 |

## Modelo de dados (master-detail)

`CLIENTE (1) ──< (N) TRANSACAO`, com a FK `TRANSACAO.ID_CLIENTE → CLIENTE.ID_CLIENTE`.
O DDL completo (tabelas, colunas, PKs, FK, UNIQUE, CHECK e índice) está em [`ddl.sql`](ddl.sql).

## Estrutura do repositório

```
├── pom.xml          # build Maven (gera target/app.jar)
├── ddl.sql          # DDL das tabelas (também embutido no jar e executado na inicialização)
├── deploy.sh        # Azure CLI: cria os recursos e faz o deploy
├── README.md
└── src/main
    ├── java/br/com/dimdim/...        # código-fonte (model, repository, controller)
    └── resources/application.properties
```

## How-to: implantação na nuvem

### Pré-requisitos
- Conta Azure com assinatura ativa
- [Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli) (`az --version`)
- JDK 17 e Maven (`java -version`, `mvn -version`)
- Terminal Bash (Linux, macOS ou **Git Bash** no Windows) com `curl` e `openssl`

### 1. Registrar os provedores de recursos (uma vez por assinatura)
Se a assinatura nunca usou esses serviços, o Azure retorna `MissingSubscriptionRegistration`.

```bash
az provider register --namespace Microsoft.Sql
az provider register --namespace Microsoft.Web
az provider register --namespace Microsoft.Insights
az provider register --namespace Microsoft.OperationalInsights

# aguardar até os quatro ficarem "Registered"
for p in Microsoft.Sql Microsoft.Web Microsoft.Insights Microsoft.OperationalInsights; do
  echo -n "$p: "; az provider show -n $p --query registrationState -o tsv
done
```

### 2. Clonar, compilar e autenticar

```bash
git clone https://github.com/FelipeMaglio/cp-devops
cd <PASTA_DO_REPOSITORIO>

mvn clean package -DskipTests      # deve terminar em BUILD SUCCESS e gerar target/app.jar

az login
az account show                    # confirme a assinatura
```

### 3. Executar o deploy (a partir da raiz do projeto)

```bash
bash deploy.sh
```

> A senha do SQL Server é **gerada automaticamente** a cada execução e salva apenas no arquivo
> local `deploy-secrets.txt`, que está no `.gitignore` e **nunca** é commitado.

### O que o `deploy.sh` faz, em ordem

| # | Etapa | Comando principal |
|---|---|---|
| 1 | Cria o Resource Group `rg-dimdim` | `az group create` |
| 2 | Cria o SQL Server, testando as regiões permitidas pela assinatura até uma aceitar (`southafricanorth`, `chilecentral`, `eastus2`, `eastus`, `southcentralus`) | `az sql server create` |
| 3 | Libera o firewall (serviços Azure e o IP de quem executa) e cria o banco `dimdimdb` (Basic) | `az sql server firewall-rule create`, `az sql db create` |
| 4 | Cria as tabelas: o `ddl.sql` é embutido no `app.jar` e executado pela aplicação na primeira inicialização (script idempotente) | `spring.sql.init` |
| 5 | Cria o App Service Plan (B1 Linux; F1 se faltar cota) e o Web App `JAVA:17-java17`, testando as regiões permitidas | `az appservice plan create`, `az webapp create` |
| 6 | Cria o Application Insights na região do Web App (e ativa Always On e log do app) | `az monitor app-insights component create` |
| 7 | Configura as App Settings (`DB_URL`, `DB_USER`, `DB_PASS`, connection string do Insights, agente `~3`, `WEBSITES_PORT=8080`) | `az webapp config appsettings set` |
| 8 | Gera o `target/app.jar` e publica | `mvn clean package`, `az webapp deploy --type jar` |
| 9 | Aguarda `GET /api/clientes` responder HTTP 200 (confirma aplicação e banco) | `curl` |

> **Regiões:** a assinatura usada tem uma política (*Allowed resource deployment regions*) que limita as
> regiões, e algumas delas podem estar sem capacidade para novos SQL Servers. Por isso o script testa
> uma região por vez, com um nome novo a cada tentativa. As mensagens de erro das regiões que recusam
> são esperadas, desde que o script chegue em "SQL Server criado em `<região>`".

### Criação das tabelas
Não há passo manual: o `ddl.sql` é copiado para dentro do `app.jar` (configuração de `resources` no `pom.xml`)
e executado pelo Spring (`spring.sql.init.mode=always`) a cada inicialização. O Hibernate está com `ddl-auto=none`: o schema é controlado só pelo `ddl.sql`.
O script só cria o que ainda não existe, então reiniciar o app não apaga dados. Para conferir as tabelas,
use o **Query editor** do portal (veja "Conferindo a persistência no banco").

### Resultado
Ao final, o script imprime a URL do app e grava, no `deploy-secrets.txt`, o servidor, o banco, o usuário,
a senha e a URL do Web App. Para recuperar a URL depois:

```bash
echo https://$(az webapp list -g rg-dimdim --query "[0].defaultHostName" -o tsv)
```

### Rodar localmente (opcional)
```bash
export DB_URL="jdbc:sqlserver://<servidor>.database.windows.net:1433;database=dimdimdb;encrypt=true;"
export DB_USER="dimdimadmin"
export DB_PASS="<senha do deploy-secrets.txt>"
mvn spring-boot:run
```
Para isso, o seu IP precisa estar liberado no firewall do SQL Server.

### Limpeza dos recursos
```bash
az group delete --name rg-dimdim --yes --no-wait
```

### Problemas comuns

| Erro | Causa e solução |
|---|---|
| `MissingSubscriptionRegistration` | Registrar os provedores (passo 1) e aguardar `Registered`. |
| `RegionDoesNotAllowProvisioning` | A região está sem capacidade para novos SQL Servers. O script segue para a próxima região; se todas falharem, tentar mais tarde. |
| `RequestDisallowedByAzure` | A política da assinatura bloqueia a região. Usar só as regiões permitidas (`az policy assignment list`). |
| `command not found: java/mvn` | Instalar JDK 17 e Maven e configurar `JAVA_HOME` e `PATH` (no Git Bash, via `~/.bashrc`). |
| App retorna 503 | Se for logo após o deploy, a aplicação ainda está iniciando (1 a 2 minutos). Se persistir, ver o log: `az webapp log tail -g rg-dimdim -n <NOME_DO_WEBAPP>`. Se o log mostrar `Schema-validation: wrong column type`, conferir se `spring.jpa.hibernate.ddl-auto=none`. Se mostrar erro de conexão, conferir as App Settings (`DB_URL`, `DB_USER`, `DB_PASS`) e o firewall do SQL Server. |
| Reiniciar / reimplantar só o app | `mvn clean package -DskipTests` e `az webapp deploy -g rg-dimdim -n <NOME_DO_WEBAPP> --src-path target/app.jar --type jar` |

## Endpoints e JSON

Base URL: `https://<NOME_DO_WEBAPP>.azurewebsites.net` (impressa no final do `deploy.sh`).

### Clientes

| Método | Rota | Descrição |
|---|---|---|
| GET | `/api/clientes` | Lista todos |
| GET | `/api/clientes/{id}` | Busca por id |
| POST | `/api/clientes` | Cria |
| PUT | `/api/clientes/{id}` | Atualiza |
| DELETE | `/api/clientes/{id}` | Exclui (e as transações do cliente) |

**POST / PUT (body)**
```json
{ "nome": "Steves Jobs", "email": "steves@dimdim.com" }
```
**Resposta (201)**
```json
{ "id": 1, "nome": "Steves Jobs", "email": "steves@dimdim.com", "dtCadastro": "2025-01-01T10:00:00" }
```

### Transações

| Método | Rota | Descrição |
|---|---|---|
| GET | `/api/transacoes` | Lista todas |
| GET | `/api/transacoes/{id}` | Busca por id |
| GET | `/api/clientes/{idCliente}/transacoes` | Lista as transações de um cliente |
| POST | `/api/clientes/{idCliente}/transacoes` | Cria uma transação para o cliente |
| PUT | `/api/transacoes/{id}` | Atualiza tipo e valor |
| DELETE | `/api/transacoes/{id}` | Exclui |

**POST / PUT (body)**
```json
{ "tipo": "PIX", "valor": 150.75 }
```
**Resposta (201)**
```json
{ "id": 1, "idCliente": 1, "tipo": "PIX", "valor": 150.75, "dtTransacao": "2025-01-01T10:05:00" }
```

### Códigos de resposta
| Código | Significado |
|---|---|
| 200 / 201 / 204 | Sucesso (consulta/atualização, criação, exclusão) |
| 400 | Validação falhou (campo obrigatório, e-mail inválido, valor ≤ 0) |
| 404 | Registro não encontrado |
| 409 | Violação de integridade (ex.: e-mail já cadastrado) |

### Exemplos com curl
```bash
APP=https://<NOME_DO_WEBAPP>.azurewebsites.net

# Criar cliente
curl -X POST $APP/api/clientes -H "Content-Type: application/json" \
  -d '{"nome":"Steves Jobs","email":"steves@dimdim.com"}'

# Criar transação para o cliente 1
curl -X POST $APP/api/clientes/1/transacoes -H "Content-Type: application/json" \
  -d '{"tipo":"PIX","valor":150.75}'

# Listar
curl $APP/api/clientes
curl $APP/api/clientes/1/transacoes

# Atualizar cliente 1 e transação 1
curl -X PUT $APP/api/clientes/1 -H "Content-Type: application/json" \
  -d '{"nome":"Steves Jobs Jr","email":"steves@dimdim.com"}'
curl -X PUT $APP/api/transacoes/1 -H "Content-Type: application/json" \
  -d '{"tipo":"CREDITO","valor":200.00}'

# Excluir transação 1 e cliente 1
curl -X DELETE $APP/api/transacoes/1
curl -X DELETE $APP/api/clientes/1
```

## Conferindo a persistência no banco

Após **cada operação** (POST, PUT, DELETE), consultar o banco pelo Query editor do portal:

```sql
SELECT * FROM CLIENTE;
SELECT * FROM TRANSACAO;
```

## Application Insights

No portal Azure, abra o recurso `ai-dimdim`:
- **Live metrics**: requisições em tempo real durante os testes.
- **Transaction search**: cada chamada HTTP registrada.
- **Logs**: consulta de exemplo `requests | order by timestamp desc`.

O Web App envia a telemetria pelo agente Java do Application Insights, ativado pelas App Settings
`ApplicationInsightsAgent_EXTENSION_VERSION=~3` e `APPLICATIONINSIGHTS_CONNECTION_STRING`.
