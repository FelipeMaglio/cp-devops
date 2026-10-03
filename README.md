# DimDim WebApp – Checkpoint 2 (Aplicações e Banco em Nuvem)

API REST em **Java 17 + Spring Boot 3** com persistência em **Azure SQL Database (PaaS)**,
publicada em **Azure App Service** via **Azure CLI** e monitorada com **Application Insights**.

**Integrantes / Grupo:** _preencher_

## Modelo de dados (master-detail)

`CLIENTE (1) ──< (N) TRANSACAO` — FK `TRANSACAO.ID_CLIENTE → CLIENTE.ID_CLIENTE`.
O DDL está em [`sql/ddl.sql`](sql/ddl.sql).

## Estrutura

```
├── pom.xml
├── sql/ddl.sql               # DDL das tabelas
├── deploy.sh         # Azure CLI: cria recursos + deploy
└── src/main/java/...         # código-fonte
```

## How-to: implantação na nuvem

### Pré-requisitos
- Azure CLI (`az --version`), conta Azure com assinatura ativa
- JDK 17 e Maven
- `sqlcmd` (opcional – ou use o Query editor do portal para rodar o DDL)

### Passo a passo
```bash
git clone <URL_DO_REPOSITORIO>
cd dimdim-webapp
az login
# edite as variáveis no topo de deploy.sh (senha, região)
deploy.sh
```

O script executa, em ordem:
1. Resource Group
2. SQL Server + regras de firewall + banco `dimdimdb`
3. Execução do `sql/ddl.sql`
4. Application Insights
5. App Service Plan (B1 Linux) + Web App (`JAVA:17-java17`)
6. App Settings (`DB_URL`, `DB_USER`, `DB_PASS`, connection string do Insights, agente `~3`)
7. `mvn package` e `az webapp deploy` do `app.jar`

> Se o `sqlcmd` não estiver instalado, comente a linha dele no script e rode `sql/ddl.sql`
> no **Query editor** do banco no portal Azure (antes de testar a API).

### Rodar localmente (opcional)
```bash
export DB_URL="jdbc:sqlserver://<server>.database.windows.net:1433;database=dimdimdb;encrypt=true;"
export DB_USER=dimdimadmin
export DB_PASS='...'
mvn spring-boot:run
```

### Limpeza
```bash
az group delete -n rg-dimdim --yes --no-wait
```

## Endpoints e JSON

Base: `https://<APP>.azurewebsites.net`

### Clientes
| Método | Rota | Descrição |
|---|---|---|
| GET | `/api/clientes` | lista |
| GET | `/api/clientes/{id}` | busca |
| POST | `/api/clientes` | cria |
| PUT | `/api/clientes/{id}` | atualiza |
| DELETE | `/api/clientes/{id}` | exclui (e suas transações) |

**POST / PUT**
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
| GET | `/api/transacoes` | lista todas |
| GET | `/api/transacoes/{id}` | busca |
| GET | `/api/clientes/{idCliente}/transacoes` | lista do cliente |
| POST | `/api/clientes/{idCliente}/transacoes` | cria para o cliente |
| PUT | `/api/transacoes/{id}` | atualiza tipo/valor |
| DELETE | `/api/transacoes/{id}` | exclui |

**POST / PUT**
```json
{ "tipo": "PIX", "valor": 150.75 }
```
**Resposta (201)**
```json
{ "id": 1, "idCliente": 1, "tipo": "PIX", "valor": 150.75, "dtTransacao": "2025-01-01T10:05:00" }
```

### Exemplos com curl
```bash
APP=https://<APP>.azurewebsites.net
curl -X POST $APP/api/clientes -H "Content-Type: application/json" \
  -d '{"nome":"Steves Jobs","email":"steves@dimdim.com"}'
curl -X POST $APP/api/clientes/1/transacoes -H "Content-Type: application/json" \
  -d '{"tipo":"PIX","valor":150.75}'
curl -X PUT $APP/api/transacoes/1 -H "Content-Type: application/json" \
  -d '{"tipo":"CREDITO","valor":200.00}'
curl -X DELETE $APP/api/transacoes/1
```

### Conferindo a persistência (mostrar na apresentação)
```sql
SELECT * FROM CLIENTE;
SELECT * FROM TRANSACAO;
```

## Application Insights
No portal: recurso `ai-dimdim` → **Live metrics**, **Transaction search** e **Logs**
(consulta de exemplo: `requests | order by timestamp desc`).
