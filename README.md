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
├── ddl.sql          # DDL das tabelas
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
- Terminal Bash (Linux, macOS ou Git Bash no Windows) com `curl` e `openssl`
- `sqlcmd` (opcional): se não tiver, o DDL é executado pelo Query editor do portal

### Passo a passo

```bash
# 1) Clonar o repositório
git clone <URL_DO_REPOSITORIO>
cd <PASTA_DO_REPOSITORIO>

# 2) Autenticar no Azure e conferir a assinatura
az login
az account show

# 3) Executar o deploy (a partir da raiz do projeto)
bash deploy.sh
```

> A senha do SQL Server é **gerada automaticamente** a cada execução e salva apenas no arquivo
> local `deploy-secrets.txt`, que está no `.gitignore` e **nunca** é commitado.

### O que o `deploy.sh` faz, em ordem

| # | Etapa | Comando principal |
|---|---|---|
| 1 | Cria o Resource Group (`rg-dimdim`, região `eastus`) | `az group create` |
| 2 | Cria o SQL Server (tenta `eastus`, `eastus2`, `centralus`, `westus3` e `brazilsouth` até uma aceitar) | `az sql server create` |
| 3 | Libera o firewall (serviços Azure e o IP de quem executa) e cria o banco `dimdimdb` (Basic) | `az sql server firewall-rule create`, `az sql db create` |
| 4 | Executa o `ddl.sql` no banco | `sqlcmd` (ou Query editor do portal) |
| 5 | Cria o Application Insights | `az monitor app-insights component create` |
| 6 | Cria o App Service Plan (B1 Linux) e o Web App (`JAVA:17-java17`) | `az appservice plan create`, `az webapp create` |
| 7 | Configura as App Settings (`DB_URL`, `DB_USER`, `DB_PASS`, connection string do Insights, agente `~3`, `WEBSITES_PORT=8080`) | `az webapp config appsettings set` |
| 8 | Gera o `target/app.jar` e publica | `mvn clean package`, `az webapp deploy --type jar` |
| 9 | Aguarda a aplicação responder HTTP 200 | `curl` |

### Se o `sqlcmd` não estiver instalado
O script pausa na etapa 4. Nesse momento:
1. No portal Azure, abra **SQL databases → dimdimdb → Query editor**.
2. Entre com o usuário e a senha que estão no `deploy-secrets.txt`.
3. Cole e execute o conteúdo do `ddl.sql`.
4. Volte ao terminal e pressione **ENTER**.

Se o Query editor bloquear o acesso, adicione seu IP em **SQL server → Networking → Firewall rules**.

### Rodar localmente (opcional)
```bash
export DB_URL="jdbc:sqlserver://<servidor>.database.windows.net:1433;database=dimdimdb;encrypt=true;"
export DB_USER="dimdimadmin"
export DB_PASS="<senha do deploy-secrets.txt>"
mvn spring-boot:run
```

### Limpeza dos recursos
```bash
az group delete --name rg-dimdim --yes --no-wait
```

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

# Atualizar transação 1
curl -X PUT $APP/api/transacoes/1 -H "Content-Type: application/json" \
  -d '{"tipo":"CREDITO","valor":200.00}'

# Excluir transação 1
curl -X DELETE $APP/api/transacoes/1
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
