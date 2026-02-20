# BALLX Graphic (WordPress Plugin) — Documentação Técnica

Este repositório contém o plugin **BALLX Graphic**, responsável por:

1) Expor endpoints REST públicos no WordPress (`/wp-json/ballx/v1/*`) para **feeds de gráfico e compatibilidade com medidores** (ticker/trades/pairs/summary/orderbook).  
2) Renderizar um **gráfico (frontend)** via shortcode `[ballx_graph]` usando **Lightweight Charts**.  
3) Ler eventos **on-chain** (logs) via **Etherscan API V2 (chainid=137 / Polygon)** e transformar em candles (time/price/volume).

> **Objetivo de produto:** o mesmo plugin atende dois mundos:
> - **BALLX Store (vendas reais)**: valores em “unidade humana” (ex.: 1, 10, 50000 BALLX) com anti-inflação por centavos no BRL.
> - **Mercado especulativo / exchanges**: quando necessário, também aceita amount em **wei (18 casas)**.

---

## Arquitetura Geral

**Fluxo completo:**

1. **On-chain**: contrato emite evento `TradeRecorded` (topic0 configurável).
2. **WordPress**: endpoint `GET /wp-json/ballx/v1/chart` consulta logs na Etherscan API V2.
3. **Normalização**: plugin converte:
   - `brlValueCents` → BRL (divisão por `brl_scale`, padrão 100).
   - `amountBallx` → BALLX (auto-detecção humano vs wei).
   - Gera candles `[{time, price, volume}]`.
4. **Frontend**: `assets/ballx-graph.js` faz `fetch` do endpoint e plota `price` como série (Area).
5. **Medidores**: endpoints de compatibilidade (“exchange/*”) usam o chart como fonte.

---

## Estrutura de Arquivos (referência)

- `ballx-graphic.php` (bootstrap do plugin)
- `includes/class-ballx-graphic-settings.php` (tela/configurações WP Admin)
- `includes/class-ballx-graphic-rest.php` (endpoints REST e lógica do chart)
- `includes/class-ballx-graphic-shortcode.php` (shortcode + enqueue scripts)
- `assets/ballx-graph.js` (render do gráfico no frontend)

---

## Bootstrap do Plugin (`ballx-graphic.php`)

### Constantes
- `BALLX_GRAPHIC_VERSION`
- `BALLX_GRAPHIC_PATH`
- `BALLX_GRAPHIC_URL`

### Includes
Carrega as 3 classes principais:
- `Settings`
- `Rest`
- `Shortcode`

### Inicialização
No hook `plugins_loaded`, chama:
- `Settings::init()`
- `Rest::init()`
- `Shortcode::init()`

---

## Configurações (Admin) — `Settings`

### Opção persistida
- `Settings::OPT_NAME = ballx_graphic_settings`
- `Settings::OPT_GROUP = ballx_graphic_group`

### Defaults importantes

| Campo | Default | Função |
|------|---------|--------|
| `polygonscan_api_key` | `''` | API Key usada na Etherscan API V2 |
| `rpc_url` | `''` | Reservado para futuro (leitura direta por RPC) |
| `contract` | `0xa0d5...6140` | Contrato que emite os logs |
| `topic0` | `0xd693...ab6f` | Assinatura (topic0) do evento TradeRecorded |
| `token_decimals` | `18` | Padrão ERC20. Usado quando detectar wei |
| `brl_scale` | `100` | Converte centavos → reais (100 = centavos) |
| `cache_seconds` | `60` | Cache do endpoint chart |

### Sanitização
- `contract` e `topic0` são normalizados em `lowercase`.
- `brl_scale >= 1`
- `cache_seconds >= 5`
- `token_decimals >= 0`

---

## REST API — `Rest`

### Rotas disponíveis

Base: `/wp-json/ballx/v1`

#### 1) Chart
- **GET** `/chart`
- Retorna candles para gráfico + `last_price`.
- É a **fonte canônica** para os endpoints de “exchange”.

#### 2) Exchange compatibility (feeds)
- **GET** `/exchange/pairs`
- **GET** `/exchange/ticker?symbol=BALLXBRL`
- **GET** `/exchange/summary`
- **GET** `/exchange/trades?symbol=BALLXBRL&limit=50`
- **GET** `/exchange/orderbook?symbol=BALLXBRL`

> Observação: `orderbook` é intencionalmente vazio (compatibilidade). BALLX não mantém livro de ofertas neste modelo.

---

## Endpoint Principal — `GET /chart`

### Fonte de dados: Etherscan API V2 (Polygon)

O plugin usa:
- URL base: `https://api.etherscan.io/v2/api`
- Parâmetros:
  - `chainid=137`
  - `module=logs`
  - `action=getLogs`
  - `fromBlock=1`
  - `toBlock=latest`
  - `address=<contract>`
  - `topic0=<topic0>`
  - `apikey=<key>`

### Formato do evento esperado

O parser assume o layout **non-indexed** do `data`:

TradeRecorded (data): [0] amountBallx [1] brlValueCents [2] authorized [3] offset_reason [4] refHash

- Cada “word” tem 32 bytes (64 hex chars).
- O plugin valida `strlen(data) >= 64*5`.

### Conversão BRL: centavos → reais

- `brlValueCents` é lido do log e interpretado como inteiro.
- Converte para reais assim:

brlValue = brlCents / brl_scale

- Por padrão `brl_scale = 100` (centavos).
- Isso evita o erro clássico: mostrar “1000” como “R$ 1000,00” quando na verdade era “R$ 10,00”.

✅ **Recomendação oficial**: manter `brl_scale=100` se o contrato emite centavos.

### Conversão amountBallx (Humano vs Wei)

O endpoint precisa suportar:

- **BALLX Store**: amountBallx em unidade humana  
  Ex.: `1` significa **1 BALLX**.
- **Exchanges / Integrações**: amountBallx em wei  
  Ex.: `1000000000000000000` significa **1 BALLX** (18 casas).

Regra implementada (robusta e sem “float minúsculo”):

- Se o valor vier como **GMP string** com **>= 18 dígitos** → tratar como **wei** e dividir por `token_decimals`.
- Se o valor vier como número normal e `>= 1e12` → tratar como **wei**.
- Caso contrário → tratar como **unidade humana** (decimals=0).

Isso garante:
- Na BALLX Store: tudo aparece “humano” (1, 10, 50k).
- Em exchanges: se vier wei, o gráfico também funciona.

### Cálculo do preço

price = brlValue / amount

### Proteções anti-lixo
Para não poluir gráfico/feeds:
- Ignora `price <= 0` ou não finito.
- Ignora `price > 1_000_000_000` (indicador de escala quebrada / teste errado).

### Saída do endpoint

Exemplo de resposta:

```json
{
  "ok": true,
  "symbol": "BALLX/BRL",
  "currency": "BRL",
  "last_price": 1.25,
  "timestamp": 1710000000,
  "count": 120,
  "candles": [
    { "time": 1710000000, "price": 1.20, "volume": 10.0 },
    { "time": 1710000300, "price": 1.25, "volume": 5.0 }
  ],
  "logs_total": 350
}


---

Endpoints “Exchange” (Compatibilidade com Medidores)

GET /exchange/pairs

Retorna lista de pares disponíveis.

Atualmente: BALLXBRL (base BALLX, quote BRL)


GET /exchange/ticker?symbol=BALLXBRL

Calcula a partir do chart:

last

high_24h

low_24h

volume_24h_base  (BALLX)

volume_24h_quote (BRL)  ✅ Economic Throughput

vwap_24h (média ponderada)

change_24h e change_pct_24h


> Nota para medidores: volume em BRL aqui representa o “fluxo econômico” (soma de price*volume nas últimas 24h).



GET /exchange/trades?symbol=BALLXBRL&limit=50

Retorna “trades” sintetizados a partir dos últimos candles:

trade_id = time-price

price, amount, timestamp

side fixo como "buy" (modelo atual não mantém “sell side” separado)


> Esse endpoint existe para compatibilidade e visualização.
O dado base continua sendo o /chart.



GET /exchange/orderbook

Retorna bids/asks vazios (compatibilidade).


---

Shortcode + Frontend Gráfico

Shortcode: [ballx_graph]

Enfileira:

lightweight-charts@4.2.0 (standalone)

assets/ballx-graph.js (script do gráfico)


Localiza:

BALLX_GRAPH.endpoint = rest_url('ballx/v1/chart')


Render:

<div id="ballx-chart" style="width:100%;min-height:300px;height:300px;position:relative;"></div>



JS (assets/ballx-graph.js)

Responsabilidades:

1. Captura BALLX_GRAPH.endpoint.


2. Inicializa chart com createChart.


3. Cria série Area:

Preferencial: chart.addAreaSeries(...)

Fallback: chart.addSeries(LightweightCharts.AreaSeries, ...)



4. Faz fetch do endpoint e transforma:

candles[] → {time: Number(c.time), value: Number(c.price)}



5. fitContent() e resize handler.


6. Workaround Elementor:

DOMContentLoaded

setTimeout(1200) caso o container renderize atrasado.





---

Cache e Performance

Cache do Chart

Implementado via set_transient() com chave:

ballx_chart_cache_v1_<contract>_<topic0>


TTL: cache_seconds (mínimo 5s)


Por que cache é crítico?

getLogs pode ser pesado (muitos logs).

Sem cache, o site pode sofrer lentidão e/ou rate-limit da API.



---

Requisitos do Servidor

WordPress + REST API habilitada

PHP com wp_remote_get

Recomendado: extensão GMP (gmp_init, gmp_strval)

Sem GMP, valores muito grandes podem virar null e serem ignorados.




---

Troubleshooting (Checklist)

1) /chart retorna ok=false “Config incompleta”

Verificar no admin:

API key

contract

topic0



2) /chart retorna “API NOTOK”

Rate limit / API key inválida / parâmetros errados.

Checar message e result na resposta.


3) Preço “explodindo”

Normalmente indica mismatch:

amount vindo humano mas tratado como wei, ou vice-versa

brl_scale errado (100 vs 1)


Correção padrão:

manter brl_scale=100 se o contrato emite centavos

manter token_decimals=18 (padrão) e deixar o auto-detect resolver



4) Gráfico não aparece no Elementor

O plugin já tem:

min-height no container

setTimeout(1200) pra reinicializar


Se mesmo assim falhar, ver console do navegador:

“LightweightCharts não carregou”

“JSON inválido do feed”

“Sem dados válidos para plotar”




---

Decisão de Design (importante para repositório público)

✅ token_decimals permanece 18 por padrão (padrão ERC20 e compatível com mercado).
✅ BALLX Store usa unidade humana, então o plugin implementa auto-detecção por magnitude para suportar ambos sem quebrar o gráfico.

Isso permite:

Produto real (BALLX Store) com valores legíveis e anti-inflação de centavos.

Integração futura com exchanges/medidores que usem 18 casas.



---

Próximos Passos (Roadmap Técnico)

Implementar modo alternativo de leitura por RPC (Settings já tem rpc_url).

Melhorar agregação (candles por minuto/5min/1h) se necessário para grandes volumes.

Adicionar paginação ou fromBlock configurável para reduzir carga em chains grandes.

Endpoint “health” (status dos dados/cache/API) para monitoramento.



---

Licença e Uso

Este plugin foi construído para ser:

funcional em WordPress

tecnicamente consistente para integradores

compatível com medidores (ticker/trades/pairs)

capaz de evoluir para leitura direta RPC e uso por exchanges


Se você for integrar em exchange/medidor, a recomendação é usar:

/exchange/ticker para preço e volume 24h

/exchange/trades para trades recentes

/chart para gráfico/time-series
