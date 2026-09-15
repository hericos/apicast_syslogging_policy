# 3scale APIcast Syslogging Policy

[![APIcast](https://img.shields.io/badge/3scale-APIcast-C6272D?logo=redhatopenshift&logoColor=white)](https://github.com/3scale/apicast)
[![Lua](https://img.shields.io/badge/Lua-OpenResty-2C2D72?logo=lua&logoColor=white)](https://openresty.org/)

Política customizada para o **APIcast** (gateway de API do 3scale) que intercepta cada chamada de API e envia requisição, resposta, cabeçalhos e metadados de timing — serializados em JSON — para um servidor **syslog**, com foco em auditoria e não-repúdio.

## Sumário

- [O que faz](#o-que-faz)
- [Estrutura do projeto](#estrutura-do-projeto)
- [Instalação](#instalação)
- [Configuração](#configuração)
- [Formato do log emitido](#formato-do-log-emitido)
- [Créditos](#créditos)
- [Licença](#licença)

## O que faz

A cada requisição processada pelo APIcast, a policy `SysLogging`:

1. Coleta o request completo (headers, body, método, query args, cabeçalho raw, `request_id`);
2. Coleta a resposta (headers, status, body — se bufferizado);
3. Coleta métricas de upstream (endereço, tempos de conexão/resposta, cache status, bytes recebidos);
4. Serializa tudo como um único JSON;
5. Envia esse JSON, via TCP ou UDP, para um servidor syslog configurado — com buffer, retry automático e flush periódico opcional.

Útil para trilhas de auditoria, compliance e depuração de integrações, sem precisar instrumentar cada backend individualmente.

## Estrutura do projeto

```
.
├── apicast-policy.json   # Manifesto da policy (nome, versão, schema de configuração)
├── init.lua              # Ponto de entrada exigido pelo APIcast
├── syslogging.lua        # Lógica da policy: monta o payload e aciona o logger
└── socket.lua            # Cliente de logging assíncrono e resiliente (buffer, TCP/UDP, TLS, retry)
```

## Instalação

1. Copie os arquivos deste repositório para o diretório de políticas customizadas do seu APIcast, dentro de uma pasta com o nome da policy (ex.: `apicast/policies/syslogging/0.0.1/`):

   ```bash
   mkdir -p apicast/policies/syslogging/0.0.1
   cp apicast-policy.json init.lua syslogging.lua socket.lua apicast/policies/syslogging/0.0.1/
   ```

2. Registre a policy no 3scale (via API/Toolbox ou na UI, em **Integration → Policies**) e adicione **SysLogging Policy** à cadeia de políticas do seu serviço.

3. Preencha os campos de configuração (ver seção abaixo) e publique a configuração do gateway.

> Compatível com deployments do APIcast tanto standalone (Docker) quanto no OpenShift/3scale operator, desde que o diretório de policies customizadas seja montado corretamente no gateway.

## Configuração

Schema completo em [`apicast-policy.json`](apicast-policy.json):

| Campo | Tipo | Default | Descrição |
|---|---|---|---|
| `SYSLOG_HOST` | string | — | Endereço do servidor syslog (**obrigatório**) |
| `SYSLOG_PORT` | integer | — | Porta do servidor syslog (**obrigatório**) |
| `SYSLOG_PROTOCOL` | `tcp` \| `udp` | `tcp` | Protocolo de transporte usado no envio |
| `APICAST_PAYLOAD_BASE64` | `"true"` \| `"false"` | `"false"` | Codifica em base64 os campos de body/headers raw antes de logar |
| `SYSLOG_FLUSH_LIMIT` | string (bytes) | `"0"` | Tamanho de buffer que dispara um flush imediato (`0` = desabilitado) |
| `SYSLOG_PERIODIC_FLUSH` | string (segundos) | `"0"` | Intervalo de flush periódico do buffer (`0` = desabilitado) |
| `SYSLOG_DROP_LIMIT` | string (bytes) | `"1048576"` | Tamanho máximo do buffer; acima disso, mensagens são descartadas |

Exemplo de configuração da policy:

```json
{
  "name": "SysLogging",
  "version": "0.0.1",
  "configuration": {
    "SYSLOG_HOST": "syslog.internal.example.com",
    "SYSLOG_PORT": 514,
    "SYSLOG_PROTOCOL": "tcp",
    "APICAST_PAYLOAD_BASE64": "false",
    "SYSLOG_PERIODIC_FLUSH": "5"
  }
}
```

## Formato do log emitido

Cada requisição gera um objeto JSON com três blocos:

```jsonc
{
  "request": {
    "body": "...",
    "headers": { "...": "..." },
    "start_time": 1710000000.123,
    "http_version": 1.1,
    "raw": "GET /foo HTTP/1.1\r\n...",
    "method": "GET",
    "uri_args": { "...": "..." },
    "request_id": "..."
  },
  "response": {
    "body": "...",
    "headers": { "...": "..." },
    "status": 200
  },
  "upstream": {
    "addr": "10.0.0.5:8080",
    "bytes_received": "1234",
    "cache_status": "MISS",
    "connect_time": "0.001",
    "header_time": "0.010",
    "response_length": "1234",
    "response_time": "0.012",
    "status": "200"
  }
}
```

Quando `APICAST_PAYLOAD_BASE64` está ativado, os campos `request.body`, `request.raw` e `response.body` são codificados em base64 antes do envio.

## Créditos

O cliente de logging assíncrono em [`socket.lua`](socket.lua) é baseado no [`lua-resty-logger-socket`](https://github.com/cloudflare/lua-resty-logger-socket), de Jiale Zhi (Cloudflare), adaptado para uso como policy do APIcast.

## Licença

Este repositório ainda não define uma licença explícita. Entre em contato com o autor ([@hericos](https://github.com/hericos)) antes de reutilizar o código em outros projetos.
