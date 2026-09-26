# PlugSpot IPC — versão 1 (implementada)

O formato é JSON Lines: cada pedido e resposta é um objecto JSON UTF-8 seguido
por `\n`. Uma ligação pode transportar vários pedidos, cada um correlacionado
por `id`. O protocolo não transporta código executável.

## Pedido

```json
{"protocol_version":1,"id":"b4ea8056-...","method":"get_plugins","params":{"offset":0,"limit":100}}
```

Campos obrigatórios: `protocol_version`, `id`, `method`. `params` é opcional e
específico do método. O cliente gera IDs únicos por pedido.

## Resposta com sucesso

```json
{"protocol_version":1,"id":"b4ea8056-...","ok":true,"result":{"items":[{"id":"query:Plugins#VST3:FabFilter:Pro-Q%204","name":"Pro-Q 4","format":"VST3","vendor":"FabFilter"}],"next_offset":100,"total":1373,"truncated":false}}
```

`hello` inclui `live_version`, `python_version` e as capacidades suportadas
pela instância do Remote Script. `python_version` identifica o runtime embutido
no Live e destina-se a diagnóstico; a compatibilidade da aplicação é decidida
pela versão do Live.

## Resposta com erro

```json
{"protocol_version":1,"id":"b4ea8056-...","ok":false,"error":{"code":"live_unavailable","message":"Ableton Live is not ready","retryable":true}}
```

O servidor devolve o mesmo `id`. `message` serve para diagnóstico; clientes
devem tomar decisões por `code`, não pelo texto.

## Métodos v1

| Método | Parâmetros | Resultado esperado |
| --- | --- | --- |
| `hello` | nenhum | versões de protocolo, Live e Python embutido, capacidades do bridge |
| `ping` | nenhum | resposta curta de disponibilidade |
| `get_status` | nenhum | estado do Live e da superfície PlugSpot |
| `get_plugins` | `offset`, `limit` opcionais | página ordenada de VST3 reconhecidos pelo Browser, com `total`, `next_offset` e `truncated` |
| `get_selected_track` | nenhum | ID opaco quando disponível e nome da track actual |
| `get_mixer` | nenhum | tracks, returns, master e dispositivos/chains, com volume, pan e cor quando disponíveis |
| `load_plugin` | `plugin_id` | pede ao Live que carregue o item VST3 na track seleccionada; inclui a track efectiva |
| `refresh_library` | nenhum | descarta a cache PlugSpot e volta a ler os itens actualmente indexados pelo Live |
| `shutdown` | nenhum | método reservado no dispatcher; não usado pelo fluxo normal |

`plugin_id` é opaco para o cliente. O adaptador usa o URI do Browser. O URI
`query:Plugins#VST3:FabFilter:Pro-Q%204` manteve-se após reiniciar Live; a
estabilidade foi observada para este item e continua a ser tratada como detalhe
interno do adaptador.

`get_mixer` devolve `set_name`, `set_path`, `set_id`, `live_version`,
`tracks`, `return_tracks` e `master_track`. Cada track inclui `id`, `name`,
`kind`, `color`, `volume`, `pan` e `devices`. Devices incluem `name`,
`class_name`, rack `chains`, parâmetros automáveis expostos pelo Live e
`preset_name`/`preset_index` quando o plugin os disponibiliza. Campos sem
suporte no Live vêm como `null` ou lista vazia. Este método só lê o estado.

Snapshots são escritos pelo Remote Script fora do `.als` em
`~/Library/Application Support/PlugSpot/MixerSnapshots`. O cliente lê esses
ficheiros localmente; consulta e escrita dos snapshots não são métodos IPC.

## Identidade e concorrência

- cada pedido tem deadline no cliente e resposta correlacionada;
- comandos que alteram o Live (`load_plugin`) voltam a ler a track seleccionada
  imediatamente antes da inserção;
- a resposta do load inclui a track efectiva para tornar explícito o destino;
- pedidos com versão desconhecida ou método desconhecido falham sem side effect;
- limitar tamanho do frame; `get_plugins` é paginado para evitar respostas
  ilimitadas.

## Códigos de erro iniciais

`unsupported_protocol`, `unknown_method`, `invalid_request`, `invalid_params`,
`frame_too_large`, `live_unavailable`, `browser_unavailable`, `plugin_not_found`,
`track_unavailable`, `mixer_unavailable`, `track_not_empty`, `incompatible_track`, `load_failed`,
`invalid_plugin`, `internal_error`.

## Estado e validação

Este contrato está implementado no adaptador, despachante Python, Remote Script
e cliente Swift via UDS. Um pedido real no Live 12.4.2 confirmou comunicação e
uma chamada de inserção; o utilizador confirmou que o FabFilter Pro-Q 4 carregou.
`get_mixer` e os listeners de snapshot ainda precisam de validação com um Set
real. Alterações incompatíveis exigem incrementar `protocol_version`.
