# Sprint 0 — registo da prova técnica

Registo histórico da prova feita em 2026-09-25 no Mac de teste. O gate e as
caixas assinaladas abaixo representam o estado no fim desse sprint; o estado
actual e as tarefas restantes estão em `PlugSpot_PROJECT_PLAN.md`. Não assumir
que IDs, propriedades ou métodos da API interna são estáveis.

## Ambiente

- Data: 2026-09-25
- macOS / versão: macOS 13.7.8 (Ventura)
- Modelo / arquitectura (Intel ou Apple Silicon): iMac18,2, Intel Core i7 quad-core 3,6 GHz, 20 GB RAM, x86_64
- Ableton Live / versão exacta: Live 12 Suite 12.4.2
- Python do Remote Script, se conhecido: Python 3.11.6 (embedded)
- Plugins VST3 de teste: 418 bundles encontrados em `/Library/Audio/Plug-Ins/VST3`; 1.373 itens carregáveis reconhecidos na árvore VST3 do Browser.

## Observações

| Prova | Resultado | Evidência / notas |
| --- | --- | --- |
| Remote Script carrega | Confirmado | `PlugSpot` aparece nas MIDI Remote Scripts do Log.txt e escreve no log de diagnóstico. |
| Versão do Live obtida | Confirmado | 12.4.2 via `Application.get_major_version/minor_version/bugfix_version`. |
| Track seleccionada obtida | Confirmado | A track seleccionada no teste foi `1-MIDI`. |
| Browser enumerável | Confirmado | Árvore `Plug-Ins` percorrida: 2.223 itens sem truncar. URI distingue `#VST3:` de `#VST:`. |
| VST3 distinguíveis de outros itens | Confirmado | Ex.: Pro-Q 4 VST3 tem URI `query:Plugins#VST3:FabFilter:Pro-Q%204`; há também um item homónimo sob `#VST:Local`. |
| ID mantém-se após reiniciar Live | Confirmado para o URI observado | `query:Plugins#VST3:FabFilter:Pro-Q%204` repetiu-se antes e depois do reinício do Live. |
| Pedido de inserção VST3 chega ao Live | Confirmado | Pedido real pelo socket UDS para `query:Plugins#VST3:Arturia:Pigments`; resposta `ok:true`, track efectiva `1-Pigments`; Log.txt regista “Going to create: Pigments”. |
| Processador Pigments inicializa | Falhou | Live registou `plugin processor could not be initialized` e `Failed: Pigments` para Arturia Pigments 4.0.1.2949. A API de inserção foi alcançada; falta testar se a falha é específica deste plugin. |
| FabFilter Pro-Q 4 VST3 carrega manualmente pela app | Confirmado pelo utilizador | O utilizador seleccionou uma track de áudio e confirmou que o pedido de carga pela interface do PlugSpot funcionou. |
| Formatos VST2/AU ou dispositivos Live infiltram-se na lista VST3 | Não | O adaptador parte de `application.browser.plugins` e só aceita URI com prefixo literal `query:Plugins#VST3:`. O Browser separou `#VST:` e `#VST3:`; dispositivos Live estão noutros nós (`instruments`, `audio_effects`, etc.). |
| Variantes de canal aparecem como plugins separados | Confirmado | O snapshot tem 1.373 entradas depois de remover 279 itens `.vstpreset`. 720 entradas são Waves e incluem variantes `Mono`, `Stereo`, `Mono/Stereo` e surround. Agrupando o sufixo de canal, ficam cerca de 982 nomes de plugin, dos quais 331 Waves. |
| Segundo load num alvo diferente | Não executado | A track seleccionada passou a chamar-se `1-Pigments` e o adaptador recusou o segundo load porque já não estava vazia (`track_not_empty`). Não se tentou contornar a protecção no mesmo canal. |
| Três loads consecutivos funcionam | Pendente | |
| Inserção observada em audio/MIDI/return/master | Pendente | |

## Preparação observada

- Mac de teste: macOS 13.7.8 (Ventura), iMac18,2 Intel x86_64 com 20 GB de RAM.
- Live 12 Suite 12.4.2 executou o script PlugSpot a partir de `~/Music/Ableton/User Library/Remote Scripts/PlugSpot`.
- O Live embebe Python 3.11.6. A API usada expõe `application` e `song` como propriedades no `ControlSurface` deste script.
- `Application.browser` existe e expõe `plugins`, `instruments`, `audio_effects`, `midi_effects`, `sounds`, `drums`, `max_for_live`, `user_folders` e `user_library`.
- Contagem directa de filhos observada: Plug-Ins 2, Instruments 24, Audio Effects 47, MIDI Effects 16, Sounds 17, Drums 167, Max for Live 3, User Library 24.
- A árvore Plug-Ins percorreu 2.223 itens sem truncar. O Browser reconheceu 1.373 entradas carregáveis sob `#VST3:`. O URI do FabFilter Pro-Q 4 repetiu-se após reiniciar Live: `query:Plugins#VST3:FabFilter:Pro-Q%204`. Isto confirma só o caso observado, não todos os IDs/variantes.
- A contagem física dos bundles VST3 varia entre as medições registadas neste sprint (418/419 no sistema, mais 1 na pasta do utilizador); os itens indexados no Browser são identificados pela URI. O URI do Pro-Q persistiu, mas a identidade persistente geral continua por confirmar.
- A contagem física observada em `/Library/Audio/Plug-Ins/VST3` é 419 bundles de sistema e há mais 1 em `~/Library/Audio/Plug-Ins/VST3`. Há também 244 bundles VST2 e 385 componentes AU em pastas separadas; nenhum destes formatos é admitido pelo prefixo URI do catálogo.
- A diferença entre bundles físicos e entradas Live deve-se sobretudo à expansão das Waveshells em variantes mono, stereo e surround. O PlugSpot agora agrupa estas opções em famílias e conserva os URIs exactos no selector de variantes; os valores 1.373/982 vêm do snapshot do Live e da normalização dos nomes, não do número de ficheiros instalados.
- A presença de bundles VST3 no sistema não prova que o Live os tenha indexado ou reconhecido. A árvore do Browser distingue `#VST3:` de `#VST:` e contém o Pro-Q 4 VST3.
- O primeiro teste de inserção seleccionou por nome o item errado (`query:Plugins#VST:Local:FabFilter%20Pro-Q%204`) e a faixa activa era MIDI. Logo após o registo imediatamente anterior à chamada `browser.load_item`, Live 12.4.2 sofreu `EXC_BAD_ACCESS` no main thread (relatório `Live-2026-09-25-152844.ips`). A causa exacta não está simbolizada; removeram-se a chamada automática e o gatilho de execução única. Após isso, Live voltou a arrancar e percorreu a árvore sem erro, reconhecendo 1.373 itens VST3.
- O primeiro teste teve um erro de acesso a `application`; corrigido no script e validado após reiniciar Live e selecionar PlugSpot.
- Depois do crash, Live voltou a abrir com o script seguro. Nova enumeração terminou sem erro: 2.223 itens percorridos, 1.373 entradas VST3 classificadas e o URI do Pro-Q 4 repetido.

## Decisão do gate

- [ ] Avançar para IPC mínimo
- [x] Investigar API / compatibilidade
- [ ] Reavaliar a viabilidade

Justificação: A primeira tentativa (URI VST, no arranque e numa track MIDI) coincidiu com crash nativo. O ensaio controlado comprovou que o caminho UDS → callback no Live → `browser.load_item` funciona. Embora Pigments tenha falhado a inicialização, o utilizador confirmou que o FabFilter Pro-Q 4 VST3 carregou pela app numa track de áudio. A viabilidade de inserção está confirmada; múltiplos loads e outros tipos de track continuam pendentes.
