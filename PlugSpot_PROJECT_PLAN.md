# PlugSpot --- Plano de Projeto

## Requisitos inegociáveis do produto (2026-09-26)

1. **Imagens dos plugins são a função principal do BubblePlug.** A preparação
   das imagens tem de funcionar, identificar corretamente cada plugin e permitir
   captura, repetição e atribuição manual. A biblioteca deste Mac pode continuar
   com itens sem imagem ou com ecrãs de erro quando o plugin local está inativo,
   corrompido ou incompleto; isso não exige bloquear o lançamento nem atingir
   zero falhas locais. O BubblePlug deve deixar esses casos visivelmente por
   resolver, sem os apresentar como imagem válida, e permitir continuar a usar a
   app e tratar as imagens mais tarde.
2. **BubblePlug tem de ser leve durante a produção musical.** Não pode manter
   scans recorrentes, carregar plugins em paralelo, consumir RAM com a biblioteca
   inteira descodificada, nem competir de forma perceptível com o Live. Na primeira
   preparação, plugins sem imagem devem ser abertos um de cada vez num processo
   auxiliar VST3 incluído no BP; o BP fotografa a janela desse processo sem criar
   tracks no Live. Depois de cada captura,
   o editor e o processo são fechados. As imagens ficam em cache persistente e são descodificadas sob
   procura, com memória limitada. Em aberturas seguintes, só plugins novos ou
   ainda sem imagem entram na fila.

Estes dois requisitos têm prioridade sobre conveniência de implementação. A
preparação inicial pode demorar, mas tem de mostrar o plugin actual e progresso,
   permitir pausa/continuação, fechar o processo auxiliar e não repetir trabalho já
guardado. O fluxo só está pronto quando a biblioteca fica completa sem exigir
scans demorados em cada arranque.

## Nome e identidade visual (2026-09-26)

- Identidade visível: **BubblePlug**, com o logo aprovado de dois meios-knobs
  invertidos junto ao fader, dentro de uma bolha de sabão iridescente.
- Direção visual aceite para a interface: biblioteca em cartões, item escolhido
  destacado e cadeia de plugins numa prateleira inferior, com linguagem visual
  própria de módulos e fluxo de sinal.
- Tema aplicado à biblioteca, fabricantes, chains, mixer, categorias e definições:
  azul-noite, ciano e bordas iridescentes discretas. Logo na bolha e cabeçalho;
  ícone macOS, recriação SVG editável e banner GitHub em `docs/branding`.
- Os identificadores, executável, Remote Script e caminhos de suporte continuam
  PlugSpot, para manter compatibilidade com os dados e launcher existentes.
- Compilação concluída; revisão visual interactiva e legibilidade a 75% ficam
  para validação manual do utilizador.

> Documento de planeamento técnico e funcional\
> Estado: núcleo e UX principal implementados; faltam validação integrada no Live, trabalho de acabamento e preparação para distribuição\
> Plataforma inicial: macOS (Intel + Apple Silicon)\
> DAW: Ableton Live 12.4.2 como baseline validada; compatibilidade posterior controlada em P5.7\
> Formato inicial: VST3\
> Filosofia: gratuito, open-source, offline e leve

------------------------------------------------------------------------

## Estado atual e trabalho em falta (2026-09-26)

**Implementado no código:** catálogo VST3 do Live, pesquisa, agrupamento
provisório de variantes, Favorites/Recent, categorias locais, Vendors,
Cards/List, imagens de recursos locais, fila temporária de chains, bolha e
atalho configurável, import/export JSON, import/export de Collections Ableton,
ponte UDS, vista Mixer e consulta offline de snapshots.

**Verificado pelo utilizador:** uma inserção do FabFilter Pro-Q 4 através do
PlugSpot. Os outros comportamentos listados abaixo não devem ser tratados como
validados apenas porque compilam.

### Prioridades restantes

1. **Amanhã (2026-09-27) — partilha comunitária de imagens via GitHub:** desenhar e implementar a opção opt-in no primeiro arranque, comparar IDs exatos/versões dos plugins com um índice remoto compacto, descarregar imagens já contribuídas e deixar a captura local para os plugins sem imagem. Definir formato/versionamento do índice, limites de tamanho/cache e fluxo explícito de revisão e consentimento antes de qualquer contribuição. Confirmar condições de redistribuição das imagens e desenhar proteção contra associações incorretas. O BP deve continuar funcional offline com o catálogo local.
2. **Concluir e rever a captura por host VST3 incluído no BP:** o helper baseado no SDK oficial da Steinberg já abre o editor da classe com nome exato, captura e termina fora do Live, incluindo classes em shells. O estudo de duração e desempenho já foi feito; falta rever a cobertura e a correspondência visual, corrigir imagens vazias/incorretas e atribuir manualmente imagens onde a captura não produz um editor válido. O helper não deve processar áudio nem ficar residente durante produção. A captura por track temporária do Live deixou de ser usada na preparação inicial.
3. **Teste integral manual no Live:** verificar inserção simples e chains;
   biblioteca e filtros; bolha, foco, atalho e lifecycle; mixer e snapshots;
   import/export de Collections com backup e recuperação. O utilizador ainda
   precisa de executar este ciclo no Ableton. Uma inserção do Pro-Q 4 já foi
   confirmada, mas não valida os restantes fluxos.
4. **Corrigir o que surgir no teste integral** e repetir as verificações
   afetadas. A compilação não substitui a validação no Live.
5. **Acabamento da biblioteca:** avaliar agrupamento de variantes e classificar
   VST2/VST3/CLAP/AU/Component numa fase posterior; a V1 continua VST3. O limite
   de seis categorias locais está decidido e implementado.
6. **Chain Sets próprios:** secção persistente e exportação `.adg` implementadas;
   o utilizador confirmou que a exportação dos tipos suportados funciona no Live.
7. **Medições reais:** concluídas para arranque, CPU, memória, captura de imagens
   e utilização prolongada no Ableton; não são um bloqueio pendente.
8. **Compatibilidade e distribuição:** o build agora cria slices x86_64 e
   arm64 e os junta num Universal; falta executar o slice arm64 num Mac Apple
   Silicon e recolher feedback voluntário. Criar um instalador de utilizador
   (os scripts existentes só instalam a integração local), testar
   instalação/atualização/remoção, escolher licença e decidir
   assinatura/notarização.
9. **Publicação GitHub:** o repositório Git local já tem um commit inicial; falta
   criar/autenticar o remoto e publicar depois de o utilizador confirmar o envio.

A pré-validação de plugins foi removida a pedido do utilizador; plugins
problemáticos podem continuar a fechar o Live. Não há ainda uma suite de testes
no repositório. A compilação confirma que o código compila, não valida a
integração real do Remote Script. Categorias BubblePlug limitam-se a seis,
correspondendo às seis cores do Ableton disponíveis para esta organização.

------------------------------------------------------------------------

## 1. Visão do projeto

**PlugSpot** é uma aplicação macOS complementar ao Ableton Live cujo
objetivo é tornar a procura e o carregamento de plugins VST3
substancialmente mais rápidos e agradáveis do que através do Browser
tradicional do Live.

A experiência central é deliberadamente simples:

1.  O utilizador abre o Ableton Live.
2.  O PlugSpot é iniciado juntamente com o Live.
3.  Surge um pequeno botão/balão flutuante sobre o ambiente de trabalho.
4.  O utilizador seleciona uma track no Ableton.
5.  Abre o PlugSpot pelo balão ou por um atalho global.
6.  Pesquisa um plugin por nome, fabricante, categoria ou tag.
7.  Seleciona o resultado com rato ou teclado.
8.  O PlugSpot pede ao Ableton para carregar esse VST3 na track
    selecionada.
9.  O utilizador pode continuar a carregar outros plugins sem fechar o
    painel.
10. Quando o Ableton termina normalmente, o PlugSpot também termina; se o Live
    fechar inesperadamente, o PlugSpot permanece à espera e volta a ligar quando
    o Live reabrir. Depois de um crash, um snapshot local da mixer pode ser
    consultado fora do Live, abrindo o PlugSpot manualmente.

O projeto começa como ferramenta de uso pessoal, mas será estruturado
para poder ser publicado gratuitamente no GitHub.

O objetivo inicial inclui apenas um host VST3 auxiliar para capturar imagens dos
editores. Não inclui processar áudio, substituir o Browser inteiro do Ableton,
criar uma DAW, gerir licenças de plugins,
disponibilizar cloud sync ou suportar várias DAWs.

------------------------------------------------------------------------

## 2. Princípios do projeto

### 2.1 Leveza

O computador de referência inicial é um Mac Intel mais antigo utilizado
para produção musical. Consequentemente, consumo de CPU, GPU e RAM é um
requisito funcional, não apenas uma otimização posterior.

Evitar:

-   Electron/Chromium salvo necessidade técnica futura muito forte;
-   polling agressivo;
-   scanning permanente;
-   animações constantes;
-   blur e efeitos gráficos dispendiosos sem benefício;
-   processos residentes quando o Ableton está fechado;
-   cloud e serviços web desnecessários;
-   alojar ou processar áudio/VSTs no processo principal do PlugSpot.

**Critério de aceitação:** o catálogo indica claramente quando está visualmente
incompleto e permite adiar a captura sem impedir o uso das restantes funções.
A preparação inicial abre no máximo um
editor VST3 de cada vez no helper, fecha-o após capturar e
permite pausar/retomar. A imagem resolvida fica em cache persistente; a app
descodifica apenas o que a interface precisa e limita a memória usada para
previews. Não há novo scan completo em cada abertura.

### 2.2 Offline-first

O funcionamento normal deverá ser 100% offline.

A pesquisa, biblioteca, favoritos, categorias, tags, recentes e
preferências serão locais.

Nenhuma conta PlugSpot será necessária.

### 2.3 Ableton como fonte de verdade para disponibilidade

Na V1, não queremos considerar "instalado" um VST3 apenas porque existe
no filesystem.

A biblioteca deverá partir, sempre que tecnicamente possível, dos
plugins que **o próprio Ableton reconhece no seu Browser**.

Isto evita apresentar plugins que o Live não consegue utilizar.

### 2.4 Organização independente depois da importação

Na primeira configuração, o PlugSpot tentará importar organização já
existente no Ableton --- tags, categorias, Collections/Favorites ou
informação equivalente que esteja acessível.

Depois da importação:

-   a biblioteca organizacional do PlugSpot torna-se independente;
-   alterar favoritos/tags no PlugSpot não altera o Ableton;
-   alterar a organização no Ableton não altera automaticamente o
    PlugSpot;
-   poderá existir uma ação manual de reimportação.

### 2.5 Isolar dependências não oficiais

A funcionalidade crítica de Browser/loading depende, no estado atual
conhecido, da API interna utilizada por Python Remote Scripts do
Ableton.

Toda essa dependência deve ficar isolada numa camada/bridge.

Objetivo:

``` text
UI / Database / Search
          │
          ▼
    AbletonBridge
          │
    implementação atual
          ▼
Python Remote Script
```

Se futuramente o Extensions SDK oficial disponibilizar Browser/VST3
loading:

``` text
AbletonBridge
      │
      ▼
Extensions SDK
```

sem reescrever o restante produto.

------------------------------------------------------------------------

## 3. Nome

### Nome de trabalho

**PlugSpot**

Razões:

-   remete para "plugin";
-   remete para Spotlight;
-   descreve bem a pesquisa rápida;
-   não depende diretamente da marca Ableton;
-   permite evolução futura.

### Alternativa

**AblePlug**

Vantagens:

-   imediatamente compreensível.

Desvantagens:

-   pode parecer que a aplicação é ela própria um plugin;
-   ligação mais direta ao nome Ableton;
-   menos diferenciador.

### Por decidir antes de publicação

-   disponibilidade do nome;
-   conflitos em GitHub;
-   marca existente;
-   domínio, caso algum dia seja necessário;
-   identidade visual.

Até lá, usar **PlugSpot** como codename/nome de projeto.

------------------------------------------------------------------------

## 4. Scope confirmado da V1

### Suportado

-   macOS;
-   Intel x86_64;
-   Apple Silicon arm64;
-   Universal Binary (build cross-compiled; arm64 runtime still awaiting
    Apple Silicon hardware feedback);
-   Ableton Live 12.4.2 como baseline testada; patches 12.4 posteriores são aceites com aviso até validação;
-   VST3;
-   funcionamento offline;
-   aplicação nativa macOS;
-   comunicação local com Ableton;
-   pesquisa;
-   categorias;
-   tags;
-   favoritos;
-   recentes;
-   vista Cards;
-   vista List;
-   rato;
-   teclado;
-   botão flutuante;
-   atalho global para abrir;
-   biblioteca local;
-   importação inicial de organização do Ableton, conforme informação
    acessível;
-   import/export da configuração/biblioteca PlugSpot;
-   carregamento na track atualmente selecionada;
-   carregamento de vários plugins consecutivamente;
-   vista visual da mixer e snapshots locais consultáveis offline (em validação).

### Explicitamente fora da V1

-   Windows;
-   Linux;
-   Logic Pro;
-   Pro Tools;
-   Cubase;
-   AU;
-   VST2;
-   AAX;
-   hosting de VST;
-   processamento áudio;
-   cloud sync;
-   contas;
-   AI search;
-   pesquisa semântica;
-   marketplace;
-   telemetria obrigatória;
-   presets VST3 arbitrários;
-   chains próprias do PlugSpot;
-   screenshots automáticos;
-   inserção entre dois devices específicos;
-   suporte a versões antigas do Live.

------------------------------------------------------------------------

## 5. Experiência de utilização

### 5.1 Arranque

Objetivo:

``` text
Ableton Live inicia
       ↓
PlugSpot bridge inicia
       ↓
PlugSpot.app é iniciado
       ↓
Ligação local estabelecida
       ↓
Biblioteca/cache validada
       ↓
Bubble aparece
```

Não queremos PlugSpot permanentemente aberto desde o login do macOS.

### 5.2 Encerramento

Fecho normal do Live encerra PlugSpot. Num crash do Live, a app fica disponível/à espera da bridge seguinte e os snapshots locais ficam preservados.

Objetivo:

``` text
Ableton Live termina
       ↓
Bridge perde lifecycle / envia shutdown
       ↓
PlugSpot guarda estado pendente
       ↓
PlugSpot.app termina
```

A forma exata de garantir launch/shutdown limpo ainda necessita de spike
técnico.

### 5.3 Bubble

Características:

-   pequeno;
-   visível junto à janela do Live enquanto está activo;
-   nível normal de janela, sem se sobrepor globalmente às outras aplicações;
-   arrastável;
-   posição persistente;
-   sem animações contínuas;
-   clique abre painel;
-   desaparece quando PlugSpot termina.

Dimensão inicial sugerida: aproximadamente 40--50 px, ajustável após
testes UX.

### 5.4 Painel rápido

Conceito próximo de Spotlight/Raycast, mas visualmente orientado para
plugins.

Elementos:

``` text
╭──────────────────────────────────────────────╮
│ 🔎 Search plugins...                     ⚙︎ │
├──────────────────────────────────────────────┤
│ All    ★ Favorites    Recent                 │
│                                              │
│ EQ  Dynamics  Reverb  Delay  Saturation ... │
│                                              │
│       resultados em Cards ou List            │
│                                              │
╰──────────────────────────────────────────────╯
```

Ao abrir:

-   foco automático no campo Search;
-   utilizador pode começar imediatamente a escrever;
-   clicar fora fecha o painel, mas não termina a aplicação.

### 5.5 Cards + List

O utilizador poderá alternar entre dois modos.

#### Cards

Adequado para navegação visual.

Cada card deverá poder apresentar:

-   thumbnail/placeholder;
-   nome;
-   fabricante;
-   categoria;
-   favorito.

#### List

Adequado para velocidade/densidade.

Exemplo:

``` text
[icon] Pro-Q 4       FabFilter       EQ          ★
[icon] Pro-C 2       FabFilter       Dynamics    ☆
[icon] Saturn 2      FabFilter       Saturation  ★
```

A preferência fica guardada.

### 5.6 Pesquisa

V1: pesquisa convencional.

Campos pesquisáveis:

-   nome;
-   fabricante;
-   categoria;
-   tags.

Desejável:

-   case-insensitive;
-   tolerância razoável a espaços/hífens;
-   prefix matching;
-   fuzzy matching leve se não afetar desempenho.

Exemplos:

``` text
pro q
fabfilter
eq
saturation
```

### 5.7 Controlo

Rato e teclado têm igual importância.

Teclado:

-   atalho global abre PlugSpot;
-   texto pesquisa;
-   ↑ / ↓ selecionam resultados;
-   Enter carrega;
-   Esc fecha painel.

Rato:

-   clique no bubble;
-   clique no campo;
-   clique em filtros;
-   clique em plugin;
-   clique em favorito;
-   alternância Cards/List.

### 5.8 Depois de carregar

A janela principal fica disponível para carregar vários plugins; um duplo
clique envia o plugin e minimiza PlugSpot para a bolha.

Exemplo:

``` text
Pro-Q → Enter
✓ Pro-Q loaded

Pro-C → Enter
✓ Pro-C loaded
```

Poderá existir setting:

``` text
[ ] Close after loading
```

Quando ativo, o PlugSpot fecha o painel após um carregamento
bem-sucedido.

------------------------------------------------------------------------

## 6. Integração com Ableton --- conhecimento atual

### 6.1 O que sabemos

Projetos open-source atuais demonstram que Python Remote Scripts
conseguem aceder ao objeto Browser através de APIs internas do Live,
incluindo padrões baseados em:

``` python
application().browser
```

Há implementações públicas que:

-   percorrem o Browser;
-   pesquisam BrowserItems;
-   expõem plugins a aplicações externas;
-   carregam devices/plugins;
-   acedem ao Live Set;
-   identificam tracks e estado selecionado;
-   comunicam via TCP/OSC/HTTP/local socket.

Isto torna tecnicamente viável o núcleo do PlugSpot.

### 6.2 Extensions SDK

O Extensions SDK oficial é importante para o futuro, mas a informação
pesquisada até à fase atual indica que a versão presente não oferece
todas as capacidades de Browser/third-party VST3 loading necessárias ao
PlugSpot.

Decisão atual:

**não depender do Extensions SDK para o núcleo da V1.**

Manter arquitetura que permita migrar futuramente.

### 6.3 Bridge proposta

``` text
┌──────────────────────────┐
│       PlugSpot.app       │
│ Swift / SwiftUI          │
│                          │
│ UI                       │
│ Search                   │
│ Database                 │
│ Settings                 │
└─────────────┬────────────┘
              │
       IPC localhost
              │
┌─────────────▼────────────┐
│   PlugSpot Remote Script │
│          Python          │
└─────────────┬────────────┘
              │
       Live internal API
              │
┌─────────────▼────────────┐
│      Ableton Live        │
│                          │
│ Browser → VST3           │
│ Selected Track           │
│ Device Chain             │
└──────────────────────────┘
```

------------------------------------------------------------------------

## 7. IPC --- comunicação app ↔ Ableton

### Decisão de trabalho

Usar um contrato JSON Lines versionado sobre **Unix Domain Socket** local.
Esta opção evita abrir uma porta de rede para uma app exclusivamente macOS.
Confirmar suporte no Python embutido do Live 12.4.2 e ciclo de vida no Sprint 0;
se houver incompatibilidade, considerar TCP restrito a loopback.

### Requisitos do protocolo

Deve suportar pelo menos:

``` text
HELLO
PING
GET_VERSION
GET_PLUGINS
GET_SELECTED_TRACK
LOAD_PLUGIN
REFRESH_LIBRARY
SHUTDOWN
ERROR
```

Exemplo conceptual:

``` json
{
  "type": "load_plugin",
  "plugin_id": "...",
  "request_id": "..."
}
```

Resposta:

``` json
{
  "type": "load_plugin_result",
  "request_id": "...",
  "success": true
}
```

O contrato inicial está em [docs/PROTOCOL.md](docs/PROTOCOL.md). O acesso ao
Browser e o carregamento continuam pendentes do spike; o protocolo não assume
que IDs ou operações internas do Live já foram validados.

------------------------------------------------------------------------

## 8. Biblioteca de plugins

### Fonte primária

Browser do Ableton.

Objetivo:

``` text
Ableton Browser
      ↓
VST3 disponíveis
      ↓
normalização
      ↓
PlugSpot DB
```

### Informação pretendida por plugin

Modelo conceptual:

``` text
Plugin
- id
- ableton_identifier
- name
- manufacturer
- format
- category
- tags[]
- favorite
- thumbnail_path
- first_seen
- last_seen
- last_used
- use_count
- available
```

### Identificador

**Questão importante a validar.**

Não devemos assumir que o nome é suficiente.

Exemplo:

``` text
Company A / Compressor
Company B / Compressor
```

Precisamos de identificar qual propriedade/URI/path do BrowserItem é
estável entre sessões.

Isto é tarefa prioritária do spike técnico.

------------------------------------------------------------------------

## 9. Base de dados local

Preferência atual: **SQLite**.

Razões:

-   pequena;
-   local;
-   robusta;
-   rápida;
-   sem servidor;
-   adequada a milhares de plugins/tags;
-   fácil de exportar/migrar.

Tabelas candidatas:

``` text
plugins
manufacturers
categories
tags
plugin_tags
favorites
usage_history
settings
library_metadata
```

Pode ser simplificado durante implementação.

Não criar schema complexo antes de sabermos exatamente quais metadados o
Ableton fornece.

------------------------------------------------------------------------

## 10. Categorias e tags

### Primeira execução

Tentar importar:

-   tags do Live;
-   categorias;
-   Collections/Favorites;
-   VST Sub Categories;
-   outros metadados acessíveis.

### Depois

PlugSpot passa a manter a sua própria organização.

Exemplo:

``` text
Pro-Q 4

Category:
EQ

Tags:
✓ Mixing
✓ Vocal
✓ Surgical
✓ FabFilter
```

O utilizador pode:

-   adicionar tag;
-   remover tag;
-   mudar categoria;
-   favoritar/desfavoritar.

### Reimportação

Settings:

``` text
Import from Ableton...
Re-import Ableton organization...
Import PlugSpot Library...
Export PlugSpot Library...
```

Reimportar do Ableton **não deverá destruir automaticamente
personalizações do PlugSpot**.

Precisaremos definir estratégia de merge.

------------------------------------------------------------------------

## 11. Favoritos

Favoritos do PlugSpot tornam-se independentes depois do bootstrap
inicial.

Devem:

-   aparecer imediatamente;
-   poder ser filtrados;
-   ser pesquisáveis;
-   funcionar em Cards/List.

------------------------------------------------------------------------

## 12. Recentes e histórico

Guardar localmente:

-   último uso;
-   número de carregamentos.

Permite:

``` text
Recent
Most Used
```

`Most Used` pode ficar para V1.1; guardar `use_count` desde V1 evita
migração posterior.

Nenhuma informação sai do computador.

------------------------------------------------------------------------

## 13. Imagens/thumbnails

### Decisão V1

As imagens não são empacotadas nem descarregadas. Na primeira abertura com um
catálogo novo, o BubblePlug procura imagens locais em `~/Library/Application
Support` e `/Library/Application Support`, depois nos bundles VST3 reconhecidos
pelo Ableton. Mostra uma barra de progresso de 0 a 100% com a indicação de que
mais plugins podem prolongar a preparação. Guarda um índice e miniaturas em
disco; nas aberturas seguintes, os cartões leem esse índice sem repetir a
procura. Um novo catálogo ou scan do Ableton inicia nova preparação.

### Razão

Captura automática da janela do plugin pode exigir:

1.  instanciar plugin;
2.  esperar carregamento;
3.  abrir GUI;
4.  detetar janela;
5.  capturar;
6.  fechar;
7.  lidar com authorization dialogs;
8.  lidar com splash screens;
9.  lidar com Metal/OpenGL;
10. lidar com plugins que crasham.

Esse método continua fora do âmbito: pode instanciar centenas de plugins e
fechar o Live. Em vez disso, a versão actual só lê imagens que o fabricante já
instalou no bundle, sem abrir nem executar o plugin.

### Estratégias a estudar posteriormente

A vista `Vendors` apresenta os fabricantes em lista ou cartões, com contagem
dos plugins por fabricante. O PlugSpot procura ficheiros de logo dentro dos
bundles VST3 locais. Nos cartões de plugins, procura imagens com nome do produto
ou imagens na pasta padrão `Snapshots`; ignora recursos pequenos como botões e
controlos da interface.

#### A --- screenshot automático da janela

Vantagem: - biblioteca visual sem servidor.

Desvantagens: - pesado; - lento; - frágil; - pode carregar centenas de
VSTs.

#### B --- base de thumbnails distribuída

Vantagem: - experiência imediata.

Desvantagens: - tamanho; - cobertura incompleta; - manutenção; -
direitos/licenciamento das imagens.

#### C --- cache local de recursos instalados

Imagens selecionadas são reduzidas e guardadas em `~/Library/Caches/PlugSpot/Artwork`.
O índice guarda o caminho de cada miniatura encontrada e fica fora do `.app`.
As imagens são lidas da cache de disco quando aparecem na interface; o BP
limita a quantidade de imagens descodificadas que mantém em memória.
Quando o bundle não fornece arte apropriada, a interface mostra as iniciais do
plugin ou fabricante.

#### D --- imagem personalizada

O menu `Missing Images…` lista plugins e fabricantes sem imagem. `Load Image…`
permite escolher uma imagem local para cada item. A escolha é copiada para
`~/Library/Application Support/PlugSpot/CustomArtwork`, permanece após um novo
scan e substitui a imagem encontrada automaticamente.

O scan local procura primeiro snapshots VST3 pelo CID exato em `moduleinfo.json`.
Os restantes ficheiros só são aceites quando o nome do plugin aparece como nome
exato do ficheiro ou pasta, com dimensões de imagem adequadas. Correspondências
parciais como `EchoBoy` dentro de `EchoBoy Jr` e nomes genéricos como `background`
deixam de ser aceites. O scan continua a consultar Application Support e os
bundles VST3, mas não abre nem instancia plugins.

Na primeira preparação, o BP abre sequencialmente cada plugin VST3 que ainda não
tem imagem num host auxiliar incluído na app, fotografa a janela do editor e fecha esse
processo antes de avançar. O Live não recebe plugins nem tracks temporárias.
O helper escolhe a classe exata dentro do bundle, incluindo shells; se a imagem
vier preta ou branca, espera pelo editor e só guarda conteúdo visível. A captura
é feita pelo processo principal do BP com a permissão Screen Recording da app;
o helper não precisa de uma permissão separada.
Plugins novos ou ainda sem imagem são os únicos a repetir este processo em
aberturas futuras. A captura oportunista após uma inserção normal também pode
preencher uma imagem em falta.

**Critério de lançamento:** validar o fluxo de preparação, a associação exata
entre plugin e imagem, a persistência/resume, a atribuição manual e a ausência de
scans repetidos. Não é necessário que este Mac termine com zero itens sem imagem:
plugins locais podem estar inativos, corrompidos ou apresentar ecrãs de
configuração. Esses casos devem ficar identificados como pendentes, sem serem
confundidos com imagens válidas. A captura pode ser adiada; o progresso aparece
num painel discreto junto à Dock. Usar um índice persistente e processar apenas
plugins novos ou ainda pendentes.

### Estado

**Em implementação:** há imagens locais em
cartões/lista, correspondência estrita por snapshot/CID ou nome exato, cache em
disco e captura oportunista. O helper VST3 foi compilado e integrado em Intel e
Apple Silicon, e capturou editores reais de HOFA, Waves, A1StereoControl e
FabFilter. A primeira corrida completa, com espera mínima de 4 segundos, está
documentada em `artifacts/artwork-scan-report-20260926.md`: 971 ficheiros
capturados, 12 falhas e pelo menos 38 imagens impróprias. A segunda corrida,
com 1,10 segundos, está em curso. A quantidade de imagens em falta nesta
instalação depende do estado dos plugins locais e não é, por si só, um critério
de bloqueio à distribuição.

------------------------------------------------------------------------

## 14. Chains

**Implementado:** fila temporária de plugins para construir e carregar uma
chain. Um clique acrescenta o plugin à fila; a fila permite remover itens e
alterar a ordem antes de carregar. A fila actual não fica guardada entre
sessões.

**Implementado no código:** secção própria **Chain Sets** com gravação local da
fila atual, listagem, carregamento de volta para a fila, renomeação e remoção.
Os sets persistem na base de dados local entre sessões. A fila de plugins
continua temporária até ser guardada como um set.
Um clique num set expande os plugins por baixo do nome e prepara a fila para
editar; `Save Changes` atualiza o set. As imagens aparecem também na fila,
com símbolo local e iniciais como alternativa imediata.
Na fila, um cartão pode ser seleccionado para alterar a variante de canal
(por exemplo Mono/Stereo) antes de carregar; os cartões podem ser arrastados
para mudar a ordem.

**Implementado e confirmado pelo utilizador no Live para tipos suportados:** botão `Export
.adg` em cada Chain Set. Gera um rack comprimido Ableton a partir dos IDs VST3
exatos; os plugins ficam em série na mesma chain e são instanciados no estado
predefinido. São aceites cadeias só de efeitos de áudio ou um instrumento no
início seguido por efeitos de áudio. MIDI effects, mais de um instrumento ou
uma ordem incompatível são recusados com uma explicação, em vez de produzirem
um rack com sinal diferente do esperado.

Um duplo clique carrega imediatamente esse plugin e minimiza a janela PlugSpot
para uma bolha flutuante que reabre a janela.

Possibilidades:

### Exportação Ableton `.adg`

`.adg` é o formato Ableton para grupos de dispositivos/Racks. A exportação
pretendida converte cada Chain Set num rack que o Live possa carregar. Este
formato contém uma árvore real de dispositivos e pode conter estado de plugins;
uma lista de IDs de plugins, por si só, não constitui um preset `.adg` válido.
O exportador usa um template Audio Effect Rack do Live e um template Instrument
Rack de código aberto; limpa o estado do preset e preenche os IDs VST3 e a ordem
dos dispositivos. Não inclui estado/preset privado. O utilizador confirmou que
os tipos suportados são exportados e carregados corretamente no Live.

Fluxo pretendido:

``` text
PlugSpot
  ↓
Chains
  ↓
Vocal Chain
  ↓
load .adg
```

Chain Sets guardados descrevem a ordem e as variantes de plugins. Se um plugin
não estiver instalado, o Live pode mostrar um dispositivo em falta ao abrir o
rack. O estado privado/preset interno de cada plugin não é exportado.

------------------------------------------------------------------------

## 15. Presets

Presets arbitrários continuam fora da V1. Para snapshots de mixer, o Remote
Script guarda `PluginDevice.presets`/`selected_preset_index` e parâmetros
automáveis quando o Live os expõe. Isto não é uma cópia do estado privado do
plugin, não garante o nome do instrumento interno do Kontakt e não garante que
o PlugSpot consiga restaurar um preset. Ver P7.1.

------------------------------------------------------------------------

## 16. Inserção dentro da chain

### V1

Carregar no comportamento padrão/fim adequado da device chain da track
selecionada.

### Futuro

Possibilidade:

``` text
EQ
Compressor
[INSERT HERE]
Saturation
Limiter
```

Ainda não confirmado de forma suficientemente robusta.

🟡 Spike futuro.

------------------------------------------------------------------------

## 17. Performance

Metas preliminares, não contratos rígidos:

-   abertura do painel aparentemente instantânea;
-   pesquisa sem lag perceptível;
-   consumo idle mínimo;
-   zero scanning contínuo;
-   nenhum processamento áudio;
-   database reads cacheáveis;
-   biblioteca reconstruída apenas quando necessário.

### Refresh

Não rescanear constantemente.

Possíveis triggers:

-   primeira execução;
-   botão Refresh;
-   mudança detetada na biblioteca do Live;
-   versão/cache incompatível.

------------------------------------------------------------------------

## 18. Resiliência

### Ableton não responde

PlugSpot deve:

-   manter UI responsiva;
-   apresentar erro curto;
-   permitir retry;
-   nunca bloquear indefinidamente.

### Plugin desapareceu

Marcar:

``` text
available = false
```

e atualizar biblioteca.

### Plugin falha ao carregar

O erro deve ser tratado como falha do pedido.

PlugSpot não hospeda o VST e não deve crashar por causa dele.

### Bridge cai

Tentar reconectar de forma limitada.

Não criar loop agressivo.

### App abre sem Ableton

Idealmente isto não acontecerá no fluxo normal.

Se for aberta manualmente:

``` text
Ableton Live is not running.
[Quit]
```

ou terminar automaticamente após curta verificação.

Decidir durante UX final.

------------------------------------------------------------------------

## 19. Segurança

Toda a comunicação:

-   local;
-   sem bind público;
-   sem Internet;
-   sem execução arbitrária de comandos enviada pela UI.

Não criar uma API genérica capaz de executar Python arbitrário dentro do
Live.

Definir mensagens explicitamente permitidas.

Exemplo:

``` text
LOAD_PLUGIN
```

é permitido.

``` text
EXECUTE_PYTHON("...")
```

não deve existir.

------------------------------------------------------------------------

## 20. Estrutura preliminar do repositório

``` text
plugspot/
│
├── README.md
├── LICENSE
├── CONTRIBUTING.md
├── docs/
│   ├── PROJECT_PLAN.md
│   ├── ARCHITECTURE.md
│   ├── PROTOCOL.md
│   └── DEVELOPMENT.md
│
├── macos/
│   └── PlugSpot/
│       ├── App/
│       ├── UI/
│       ├── Models/
│       ├── Database/
│       ├── Search/
│       ├── AbletonBridge/
│       └── Settings/
│
├── ableton/
│   └── PlugSpotRemote/
│       ├── __init__.py
│       ├── browser.py
│       ├── transport.py
│       └── lifecycle.py
│
├── shared/
│   └── protocol/
│
├── tests/
│
└── scripts/
    ├── install_remote_script.sh
    └── package.sh
```

Estrutura sujeita a alteração depois do protótipo.

------------------------------------------------------------------------

# 21. PRIORIDADES DE IMPLEMENTAÇÃO

## P0 --- Provar a viabilidade

Não construir UI bonita antes destas tarefas.

### P0.1 --- Criar Remote Script mínimo

Objetivo:

-   Live reconhece PlugSpotRemote;
-   script inicializa;
-   log confirma execução.

**Done quando:** abrir Live produz confirmação inequívoca de que o
script corre.

### P0.2 --- Inspecionar Browser API no Live atual

Determinar concretamente:

-   roots disponíveis;
-   localização de VST3;
-   propriedades de BrowserItem;
-   URI/path/id;
-   fabricante;
-   nome;
-   metadata acessível.

**Done quando:** conseguimos exportar uma lista de VST3 reconhecidos
pelo Live.

### P0.3 --- Identificador estável

Fechar resposta para:

> Como identificamos inequivocamente um VST3 entre sessões?

Testar:

-   path;
-   URI;
-   BrowserItem identifier;
-   nome + vendor;
-   outras propriedades.

**Done quando:** fechar/reabrir Live e reencontrar o mesmo plugin
através do ID guardado.

### P0.4 --- Track selecionada

Remote Script deve identificar a track atualmente selecionada.

**Done quando:** mudar seleção no Live e obter corretamente a nova
track.

### P0.5 --- Load de VST3

Selecionar track e carregar plugin conhecido por ID.

**Teste inicial sugerido:** qualquer VST3 pequeno e estável instalado na
máquina.

**Done quando:** comando programático insere o plugin na track correta
repetidamente.

### P0.6 --- Múltiplos loads

Carregar:

``` text
Plugin A
Plugin B
Plugin C
```

sem interação manual no Browser.

Confirmar ordem e comportamento.

### P0.7 --- IPC mínimo

Criar comunicação:

``` text
test client → Remote Script → Ableton
```

Implementar:

-   ping;
-   list plugins;
-   selected track;
-   load plugin.

**Done quando:** processo externo consegue carregar plugin.

------------------------------------------------------------------------

## P1 --- Aplicação macOS mínima

### P1.1 --- Criar app Swift/SwiftUI Universal

**Estado (2026-09-26):** o script compila x86_64 e arm64 separadamente e junta
as duas slices num bundle Universal. A slice Intel foi compilada neste Mac; a
slice arm64 foi cross-compilada, mas ainda não foi executada num Mac Apple
Silicon. A execução real precisa de feedback voluntário.

Targets:

-   x86_64;
-   arm64.

Confirmar execução no Intel de desenvolvimento.

### P1.2 --- AbletonBridge

**Implementado:** abstraction Swift e cliente UDS.

Criar abstraction:

``` swift
protocol AbletonBridge {
    func connect()
    func plugins()
    func selectedTrack()
    func loadPlugin(id:)
}
```

UI nunca deverá depender diretamente do socket.

### P1.3 --- Lifecycle

**Implementado no código; runtime ainda por validar.**

Experimentar melhor forma de:

-   Live iniciar PlugSpot;
-   evitar duplicados;
-   Live fechar PlugSpot;
-   PlugSpot recuperar se bridge reiniciar.

### P1.4 --- Bubble

Implementar:

-   arranque em bolha;
-   arrasto livre e posição bloqueável;
-   persistência de posição;
-   clique;
-   baixo consumo.

**Implementado:** a janela principal é ocultada no arranque e a bolha aparece
depois de a bridge do Live responder. A janela é ocultada com `orderOut`, sem
criar uma miniatura no Dock. A bolha acompanha a janela do Live e surge por
defeito no canto inferior esquerdo, com margem. O arrasto usa a posição global
do cursor e guarda a posição relativamente à janela do Live; Settings permite
bloquear e repor a posição. Teste visual em runtime ainda pendente.

**Requisito adicional:** a bolha deve acompanhar a janela do Ableton ao mover,
redimensionar ou passar para ecrã inteiro, incluindo quando o Live usa um
espaço próprio. Ao clicar, a janela do PlugSpot deve abrir no mesmo ecrã da
janela do Live sem mudar de ecrã. O PlugSpot funciona como extensão do Live e
não deve aparecer no Dock, mesmo quando a janela principal está minimizada.

**Implementação (2026-09-25):** PlugSpot usa `LSUIElement` para não aparecer
no Dock. A janela mostra apenas o botão amarelo, reconfigurado para minimizar
para a bolha; os botões fechar e maximizar estão ocultos/desactivados. O botão
principal de carregar também minimiza para a bolha depois de enviar o plugin.
O catálogo VST3 é guardado localmente em UserDefaults e restaurado sem novo scan
ao reaparecer a janela ou reiniciar PlugSpot. O botão Refresh e a reconexão após
queda do Live continuam a pedir um scan actualizado. Posição persistente da
bolha e teste visual do ciclo de vida continuam pendentes.

**Acompanhamento inicial (2026-09-25):** enquanto a bolha está visível, o
PlugSpot consulta a lista de janelas visíveis e acompanha a maior janela do
processo Ableton Live a cada 200 ms, mantendo-a dentro do ecrã. A panel é auxiliar
de ecrã inteiro, sem nível flutuante global; ao reabrir, a janela do PlugSpot é
movida para o Space/ecrã activo e centrada no monitor do Live. Mover o Live entre
monitores e Spaces em runtime continua por confirmar visualmente.

**Definições da bolha (2026-09-25):** o menu Settings expõe tamanhos 75%,
100%, 120% e 150%, transparência de 0% (sólida) a 100% (invisível), posição
livre por arrasto persistida relativamente à janela do Live, e atalho global
personalizável. O atalho inicial é Control+Option+P; o utilizador pode gravar
outra combinação com Control ou Command, e conflitos de registo aparecem como
erro no painel. A posição acompanha a janela do Live sem prender o utilizador a
um canto fixo. Build passou; a interação real com a janela e o atalho ainda
precisam de verificação visual.

### P1.5 --- Painel básico

Sem design final.

Apenas:

-   Search;
-   lista;
-   seleção;
-   Enter;
-   click;
-   Esc.

### P1.6 --- Fluxo completo

**Parcial:** utilizador confirmou uma carga simples do FabFilter Pro-Q 4; chain,
atalho, todas as tracks e lifecycle ainda não têm verificação completa.

Objetivo histórico do projeto:

``` text
Open Live
→ click bubble
→ type "pro q"
→ Enter
→ Pro-Q loads
```

Quando isto estiver sólido, o núcleo está validado.

------------------------------------------------------------------------

## P2 --- Biblioteca local

### P2.1 --- SQLite

Implementar schema mínimo.

### P2.2 --- Sync de disponibilidade

Comparar DB com Browser atual.

### P2.3 --- Search index

Pesquisa por:

-   nome;
-   fabricante;
-   categoria;
-   tags.

### P2.4 --- Recentes

Actualizar `last_used` e `use_count` numa base SQLite local quando o Live
aceita um pedido de carregamento. **Implementado na primeira versão.**

### P2.5 --- Favoritos

Adicionar/remover favoritos persistidos localmente e filtrá-los na biblioteca.
**Implementado na primeira versão.**

### P2.6 --- Formatos e variantes de plugins (adiado)

Implementar depois do fluxo base de pesquisa e carregamento:

- distinguir e filtrar formatos separadamente: VST2, VST3, CLAP e AU/AUX/
  Component (`.component`), confirmando quais são expostos pelo Live;
- identificar variantes do mesmo produto sem depender de fabricante específico
  ou de sufixos conhecidos como Mono/Stereo;
- apresentar uma ficha/cartão por plugin e oferecer nesse cartão as opções de
  formato e de configuração de canal (Mono, Stereo, 5.1, entre outras);
- preservar o identificador exacto da variante escolhida para o carregamento;
- evitar juntar produtos diferentes que partilhem apenas o nome.

Esta tarefa está deliberadamente adiada; o catálogo actual continua limitado a
VST3 e o agrupamento existente é provisório.

------------------------------------------------------------------------

## P3 --- Organização/importação

### P3.1 --- Investigar tags/Collections Live

**Concluído para Collections VST3 no macOS de referência.** A Browser API não
expõe a atribuição de Collections. O Live guarda os nomes em `Library.cfg` e
as atribuições na base local `Live-files-*.db`; a base `Live-plugins-1.db`
associa o identificador VST3 ao fabricante. O leitor do PlugSpot abre estes
ficheiros em modo só de leitura. O campo `colors` é uma máscara: o bit
`1 << índice` identifica a Collection `color:colors=índice` (1–7).

O importador actual só traz VST3 de áudio/instrumento cujo fabricante e nome
correspondem a uma família VST3 visível no catálogo actual. A API do Browser
não expõe Collections. Os ficheiros `.xmp` do User Library cobrem apenas
parte dos dispositivos guardados nessa biblioteca, por isso não servem como
índice completo dos plugins instalados. Metadados VST2, AU, categorias
automáticas e tags do Browser ainda não são importados.

### P3.2 --- Bootstrap

Existe uma acção manual no menu da aplicação para importar Collections do
Ableton. A pergunta de primeira execução ainda não está implementada.

Interacção planeada para primeira execução:

``` text
Import organization from Ableton?
```

### P3.3 --- Tags próprias

**Pendente:** tags livres além das categorias locais ainda não têm CRUD dedicado.

### P3.4 --- Categorias próprias

Permitir correção manual.

### P3.5 --- Import/export PlugSpot

**Implementado:** `plugspot-library.json` inclui versão do schema, favoritos,
labels, recentes e categorias. A importação faz merge e preserva os dados
existentes. Ainda falta uma UX de conflito/limpeza de labels obsoletas.

### P3.6 --- Reimport

O merge inicial usa inserção sem duplicados. Reimportar Collections do Live
acrescenta relações e favoritos, sem apagar alterações no PlugSpot. Ainda
falta uma revisão que permita remover relações obsoletas importadas.

### P3.7 --- Exportar Collections para o Live

**Implementado; falta a primeira execução completa pelo utilizador.** O menu faz
uma verificação prévia só de leitura, bloqueia se algum plugin favorito/categorizado
não tiver uma correspondência única de família no catálogo VST3 e mostra quantos
itens globais do Browser serão limpos. Após confirmação, pede ao Live para sair;
o prompt nativo do Live permite guardar um Set alterado ou cancelar a saída. O
launcher aguarda o fim do processo Live, cria backups, actualiza `Library.cfg`
e aplica as máscaras de cor numa transacção SQLite, com diário durável para
recuperar os backups em caso de interrupção, depois reabre Live. Se Live
continuar activo, se faltar espaço para backup ou se uma verificação falhar, os
ficheiros não são alterados. A Browser API não expõe escrita de Collections,
por isso esta operação offline coordenada é específica do Live 12.4.2 validado.
O primeiro preflight real encontrou 92/92 famílias, 145 variantes VST3 e 120
itens actualmente coloridos no índice de 172.192 itens.

------------------------------------------------------------------------

## P4 --- UX V1

### P4.1 --- Cards

**Implementado:** vista de cartões com imagem local do plugin quando encontrada,
fallback com iniciais, nome, fabricante, categorias e favorito.

### P4.2 --- List

**Implementado:** vista List compacta, incluindo favoritos e menu de
categorias.

### P4.3 --- Alternância Cards/List

**Implementado:** alternância na interface e preferência persistida localmente.

### P4.4 --- Categorias

Filtros rápidos. Quando várias categorias estão activas, a família tem de
conter todas elas (AND/intersecção), para que categorias extra não aumentem os
resultados.

O modelo actual limita as categorias próprias a seis cores/slots exportáveis:
sete Collections do Ableton menos o slot reservado a Favorites. Continua por
decidir se as categorias locais devem ser ilimitadas e só a exportação deve
limitar o mapeamento a cores. No editor, escolher cor é feito por
amostras quadradas, sem rótulos visíveis “Color 1”, “Color 2”, etc.

### P4.5 --- Favorites/Recent

Tabs/filtros.

### P4.6 --- Atalho global

O atalho global é configurável nas definições. O valor inicial implementado é
Control+Option+P. Registo do atalho e conflito com outras apps precisam de teste
visual no macOS.

### P4.7 --- Fechar/minimizar após carregar

O duplo clique minimiza a janela para a bolha. Um setting separado de
“Close after loading” não está implementado.

### P4.8 --- Feedback

Exemplo:

``` text
✓ Pro-Q 4 loaded
```

Sem notificações intrusivas.

### P4.9 --- Chain temporária

**Implementada (2026-09-25):** clique simples acrescenta o plugin à fila no
rodapé; é possível remover ou reordenar itens antes de usar `Load Chain`. Duplo
clique carrega imediatamente um único plugin e minimiza PlugSpot para a bolha.
`Load Chain` envia os plugins da fila sequencialmente e pára no primeiro erro,
mantendo na fila os itens ainda não enviados. O menu contextual ainda oferece
um comando `Load` directo; rever se esta alternativa conflita com a regra UX de
clique simples/duplo clique e botão único.

### P4.10 --- Vista por fabricante

**Implementada:** `Vendors` é um separador junto de `All`, `Favorites` e
`Recent`. Mostra fabricantes em lista ou cartões; escolher um fabricante abre
a lista dos seus plugins. Não apresenta a lista de fabricantes no topo das
outras vistas. Os cartões mostram logos locais dos bundles e os plugins usam
imagens locais quando os bundles fornecem recursos adequados; sem download ou
imagens incluídas no pacote PlugSpot.

------------------------------------------------------------------------

## P5 --- Robustez

### P5.1 --- Erros IPC

**Implementado:** falhas de transporte apresentam instruções claras para
conexão recusada, permissões/caminho, interrupções e respostas inválidas.
Falhas do Live são apresentadas por código com orientação específica para
plugin em falta, track incompatível, Browser indisponível e versão incompatível.

### P5.2 --- Reconexão

**Implementada no código:** após três pings falhados, PlugSpot mostra o estado
desligado e continua a tentar de dois em dois segundos sem terminar a app.
Quando o Live volta, a biblioteca é actualizada; se já houver uma leitura em
curso, a actualização fica pendente até essa leitura acabar. A validação com
Live a fechar e reabrir continua por fazer.

### P5.3 --- Plugin removido

**Implementado no código:** ao actualizar o catálogo, os plugins que já não
existem são removidos da fila de chain e a selecção inválida é limpa. Os dados
locais de favoritos, categorias e recentes são preservados; os separadores
Favorites e Recent indicam quantos registos guardados não constam do catálogo
actual. A validação com remoção/renomeação real no Live continua pendente.

### P5.4 --- Ableton fecha inesperadamente

**Implementado no código, pendente de validação com crash real:** o PlugSpot
detecta a perda do bridge sem encerrar. A biblioteca carregada e o estado da
janela/fila permanecem na sessão; favoritos, categorias e recentes estão na
base local. Quando o Remote Script volta a iniciar, apodera-se do lock, remove
o socket obsoleto deixado pelo processo terminado e abre um socket novo. O
PlugSpot reconecta e actualiza o catálogo por P5.2. Um fecho normal continua a
ser tratado pelo launcher de lifecycle e termina a app.

### P5.5 --- PlugSpot crash/restart

**Implementado no código; requer build e actualização do launcher instalado:**
enquanto o socket do Live continuar activo, o launcher deve detectar se
`PlugSpotApp` terminou inesperadamente e voltar a abri-la, até três vezes por
sessão do Live. O comando explícito `Quit PlugSpot` deixa um marcador para o
launcher não contrariar o utilizador; esse marcador é removido quando começa
uma nova sessão do Remote Script. Favoritos, categorias e recentes sobrevivem
porque ficam na base SQLite local. O comportamento real após crash e o limite
de tentativas continuam pendentes de validação.

### P5.6 --- Remote Script não instalado

**Implementado no código; validação visual pendente:** após três falhas, o
PlugSpot distingue Live fechado de Live aberto sem bridge. Se o script não
estiver na pasta padrão, indica correr `macos/install-launcher.sh` e verificar
a localização da User Library. Se estiver presente mas não responder, indica
seleccioná-lo em Settings → Link, Tempo & MIDI, reiniciar o Live e consultar o
log `~/Documents/plugspot-remote.log`.

### P5.7 --- Version compatibility

**Implementado no código; testes de versões adicionais pendentes.** O handshake
`hello` informa a versão do Live e a versão do Python embutido. PlugSpot aceita
Live 12.4.2, a baseline validada. Aceita também patches 12.4 posteriores com
um aviso de que não foram plenamente validados; versões anteriores a 12.4.2 e
outras séries ficam bloqueadas até serem verificadas. O runtime Python conhecido
é 3.11.6; a versão é registada para diagnóstico, sem um requisito de runtime
mais restritivo ainda definido. A exportação offline das Collections continua
estritamente limitada ao Live 12.4.2, conforme as verificações do worker.

Em 25-09-2026, as notas oficiais da Ableton indicam Live 12.4.6 como a versão
mais recente, posterior à baseline 12.4.2. Essa versão fica na faixa de patch
aceite com aviso até ser testada. Referência: [Live 12 Release Notes](https://www.ableton.com/en/release-notes/live-12/).

### P5.8 --- Biblioteca grande

**Optimizadas e benchmark sintético executado:** a UI calcula as famílias de
plugins uma vez por catálogo em vez de repetir o agrupamento em cada recálculo
da vista. O adaptador substitui a cache de BrowserItems no refresh, libertando
referências antigas e impedindo carregar itens removidos. `AbletonLibrary`
reserva capacidade para a quantidade total anunciada pelo primeiro page.

Benchmark com Browser simulado: 1.373 entradas — 6 páginas, 17 ms e 1,18 MiB
de pico Python; 8.000 entradas — 32 páginas, 98 ms e 6,54 MiB. Teste de refresh
confirmou que um item removido passa a devolver `plugin_not_found`. A referência
real conhecida do Live tem 1.373 entradas VST3.

**Ainda por validar:** tempo das chamadas reais à Browser API no Live e fluidez/
memória da UI SwiftUI em catálogo grande. O benchmark simulado não inclui esses
custos. O build local, entretanto, foi corrigido e confirmado em P5.9.

### P5.9 --- CPU/RAM profiling

**Profiling de código e build local (2026-09-25):** o Mac de referência é um
iMac18,2 Intel Core i7 quad-core 3,6 GHz, 20 GB RAM, x86_64, macOS 13.7.8.
A app compilou com sucesso pelo script `macos/build-app.sh`, usando o SDK
`MacOSX13.3.sdk`; o `xcrun --show-sdk-platform-path` deste Command Line Tools
falha ao resolver `PlatformPath`, mas o script usa o SDK instalado como fallback.
O executável produzido é Mach-O x86_64.

Na leitura do código, o catálogo é agrupado uma vez por refresh (`catalogFamilies`),
e a UI usa `List`/`LazyVGrid` para listas e cartões. O monitor da ligação envia
um ping a cada 2 segundos; o Remote Script agenda o processamento da bridge em
ticks do Live. A pausa de 450 ms ocorre somente entre inserções de uma chain.
O benchmark sintético do adaptador, registado em P5.8, mediu 1.373 entradas em
17 ms / 1,18 MiB e 8.000 entradas em 98 ms / 6,54 MiB (memória Python medida
com `tracemalloc`, não a memória total do PlugSpot).

**Nota histórica:** no momento desta inspeção não havia processo PlugSpot ou
Live em execução (`ps`), pelo que não foi possível recolher CPU/RSS nesse
ensaio. Foram feitas medições reais posteriores de arranque, CPU, memória,
captura de imagens e utilização prolongada no Ableton; esses testes estão
concluídos e não são um bloqueio atual.

### P5.10 --- Histórico: validação de segurança de plugins removida

**Decisão actual (2026-09-25):** removida por pedido do utilizador. O PlugSpot
envia a carga directamente ao Ableton; não executa pluginval, o validador
Steinberg, `auval` ou outro scanner antes da carga. Um plugin instável pode
continuar a fechar o Live. Não voltar a introduzir pré-validação sem nova decisão
do utilizador.

**Registo histórico:** o protótipo do validador Steinberg foi removido do build.
AmpliTube 5 VST3 5.8.2 e AU terminaram com crash em subprocessos de validação;
o caso HOFA 4U Meter falhou testes do helper apesar de o utilizador confirmar
que carrega normalmente no Live. Esses resultados demonstraram falsos positivos
para o contexto do host e não justificam bloquear cargas. A análise permanece
como histórico, não como plano actual. Referências: [Ableton — Plug-ins Tips and
Troubleshooting](https://help.ableton.com/hc/en-us/articles/5232428442002-Plug-ins-Tips-and-Troubleshooting),
[Steinberg VST3 Validator](https://github.com/steinbergmedia/vst3_public_sdk/tree/master/samples/vst-hosting/validator).

**Limpeza de código concluída (2026-09-26):** removidos o helper, o script de
build, o alvo de validação do scanner, a API/cache SQLite e o schema da tabela
para novas bases de dados. Tabelas antigas permanecem intactas. O fluxo de carga
continua directo; a validação de plugins não faz parte do plano actual.

------------------------------------------------------------------------

## P6 --- Packaging/open source

### P6.1 --- Instalador

Precisamos tornar simples instalar:

-   PlugSpot.app;
-   PlugSpot Remote Script.

Idealmente um único fluxo.

### P6.2 --- Code signing

Avaliar requisitos Apple.

### P6.3 --- Notarization

Avaliar para distribuição fora da App Store.

### P6.4 --- License

Escolher licença open-source.

Candidatos:

-   MIT;
-   Apache-2.0;
-   GPLv3.

### P6.5 --- README

Incluir:

-   screenshots;
-   requisitos;
-   instalação;
-   utilização;
-   arquitetura;
-   troubleshooting.

### P6.6 --- GitHub Releases

Universal binary/package.

------------------------------------------------------------------------

## P7 --- Ideias futuras

### P7.1 --- Snapshot da mixer por Live Set

Adicionar um botão na janela principal para alternar entre a biblioteca actual
e uma vista visual da mixer. A vista mostra a estrutura da mixer e a cadeia de
dispositivos de cada track de áudio/MIDI, Group, Return e Master. Quando um Set
é guardado no Live, o PlugSpot deve gerar/actualizar um ficheiro
próprio associado àquele Set, com pelo menos:

- caminho/identidade do Set, data e versão do snapshot;
- nome e tipo de cada track, incluindo grupos, Returns e Master;
- ordem e nomes dos dispositivos/plugins por cadeia e por ramo de rack quando
  os dados estiverem acessíveis;
- fabricante, formato e variante do plugin quando identificáveis;
- disponibilidade actual: encontrado, ausente ou não identificável;
- preset/nome do preset e estado recuperável do dispositivo, apenas quando o
  Live ou o plugin exponha esses dados de forma segura e suportada.

O objectivo é consultar o mapa e identificar dispositivos em Sets antigos
quando um plugin já não está instalado, e recuperar a informação guardada no
último snapshot depois de um crash do Live. O snapshot não substitui nem edita
o `.als`; deve continuar legível mesmo que o Live já não consiga carregar um
plugin.

**Estado:** o botão alterna entre a biblioteca e a mixer, actualiza ao abrir e guarda um snapshot JSON atómico em `~/Library/Application Support/PlugSpot/MixerSnapshots`. O Remote Script ouve alterações nas tracks, dispositivos, presets e parâmetros expostos; agrupa-as e guarda após dois segundos sem alterações, esperando que o playback pare antes de gravar valores animados. O snapshot inclui valores de parâmetros que o Live expõe e o preset seleccionado quando o plugin disponibiliza essa informação. A interface lista os snapshots por Set e data, permite abri-los offline e mostra automaticamente o mais recente quando o Live está indisponível. Ainda falta testar estes listeners e a consulta com snapshots reais do Live.

**Pesquisa inicial:** o Live Object Model expõe `Song.tracks`,
`Song.return_tracks`, `Song.master_track` e `Track.devices`, por isso o mapa de
tracks e dispositivos parece tecnicamente acessível. Falta validar a API Python
do Remote Script na versão suportada e encontrar um sinal fiável de que o Set
acabou de ser guardado. A documentação consultada não estabelece que o Live
exponha esse evento ao Control Surface. O snapshot inicial e as alterações
observadas ficam guardados fora do Live; ainda é preciso associar correctamente
Sets não guardados e confirmar o comportamento dos listeners no Live suportado.
Capturar ou restaurar o estado interno completo de plugins de terceiros não
pode ser prometido com base na lista de dispositivos ou nos parâmetros
automáveis. Ver: [Live Object Model — Song](https://docs.cycling74.com/apiref/lom/song/),
[Live Object Model — Track](https://docs.cycling74.com/apiref/lom/track/).

------------------------------------------------------------------------

# 22. V1.1 / Pós-MVP

Candidatos, por prioridade a reavaliar:

1.  classificação de formatos e deduplicação geral de variantes;
2.  categorias locais sem o limite das cores exportáveis;
3.  tags livres e merge/reimport com limpeza de relações obsoletas;
4.  chains persistentes e suporte a `.adg`;
5.  recuperação de estado interno/presets de terceiros onde o plugin permita;
6.  automação de testes e matriz de versões/arquitecturas;
7.  instalador, assinatura, notarização e publicação;
8.  AU, Windows e outras DAWs.

Nenhum destes deve atrasar o MVP.

------------------------------------------------------------------------

# 23. Questões ainda abertas

## Críticas --- responder por spike

### Q1 --- Qual é o identificador estável do BrowserItem VST3?

**Estado:** o URI observado manteve-se para Pro-Q 4 depois de reiniciar Live;
identidade de variantes e estabilidade geral ainda não estão demonstradas.

### Q2 --- Qual é a melhor forma de iniciar PlugSpot a partir do lifecycle do Live?

**Estado:** Remote Script + launcher implementados; validar arranque/fecho e crash em runtime.

### Q3 --- Qual é a melhor forma de encerrar PlugSpot quando Live fecha?

**Estado:** launcher implementado; distinguir/testar fecho normal e crash continua pendente.

### Q4 --- Que metadata de tags/Collections conseguimos obter diretamente?

**Estado:** parcialmente conhecido; testar versão atual.

### Q5 --- Qual IPC é mais simples/robusto?

**Estado:** UDS implementado; não há listener de rede.

### Q6 --- Como o Browser representa plugins duplicados/variantes?

**Estado:** investigação e implementação adiadas para P2.6. A lista actual
agrupa algumas variantes de canal por sufixo; não é ainda uma identificação
geral de família entre formatos e produtos.

Casos:

-   versões diferentes;
-   mono/stereo;
-   vendor duplicado;
-   nomes iguais.

### Q7 --- O load sempre entra na posição desejada no fim da chain?

Validar com:

-   audio track;
-   MIDI track;
-   instrument presente;
-   racks;
-   return;
-   master.

------------------------------------------------------------------------

## Não críticas --- podem esperar

### Q8 --- Thumbnails

**Estado:** lookup local dos recursos do VST3 e cache limitado implementados.

### Q9 --- Presets

**Estado:** nome/índice e parâmetros automáveis podem entrar nos snapshots;
serialização/restauro do instrumento e estado privado de Kontakt/plugins não
está implementado nem garantido.

### Q10 --- Chains próprias

**Pedido registado (2026-09-26):** implementar Chain Sets persistentes com
criação, edição, remoção e exportação `.adg`. O formato `.adg` corresponde a
presets de Device Group/Rack do Ableton; a compatibilidade dos ficheiros gerados
tem de ser verificada no Live antes de prometer compatibilidade. A exportação já
está implementada no código, com limites de tipo/ordem documentados na Secção 14.

### Q11 --- Inserção entre devices

### Q12 --- Extensions SDK substituir Remote Script

------------------------------------------------------------------------

# 24. Matriz de verificação

| Área | Evidência actual | Falta verificar |
| --- | --- | --- |
| Catálogo VST3 e UDS | Executado no Live 12.4.2; 1.373 entradas no snapshot de referência | Refresh real após instalar/remover plugins |
| Carga simples | Utilizador confirmou FabFilter Pro-Q 4 numa track de áudio | Repetição, track MIDI, Return, Master e plugins adicionais |
| Chain temporária | Implementada no código | Ordem, primeiro erro e vários loads em Live |
| Chain Sets locais | Implementados no código | Guardar, reabrir, renomear, remover e verificar persistência entre sessões |
| Export Chain Set `.adg` | Utilizador confirmou exportação e funcionamento no Live para tipos suportados | Sem teste pendente para o âmbito suportado |
| Categorias e export JSON | Implementadas no código | Merge/reimport e round-trip de todas as categorias/dados |
| Export Collections Live | Preflight real feito | Um ciclo completo com backup, rollback e reabertura |
| Bolha/lifecycle | Código implementado | Spaces, fullscreen, foco, arrasto, fecho normal e crash |
| Mixer/snapshot | Código implementado; build passou | Listeners, debounce, snapshot legível e crash/restart num Set real |
| Recuperação offline | Browser de snapshots implementado | Abrir arquivo real quando Live está fechado/terminou abruptamente |
| Performance | Medições reais de arranque, CPU, memória, captura e utilização prolongada concluídas | Nenhum teste de desempenho pendente nesta fase |
| Empacotamento | Builds x86_64, arm64 e Universal compilados; arm64 sem teste de hardware | Instalador, licença, signing/notarization e feedback runtime Apple Silicon |

A carga Pro-Q 4 e a exportação `.adg` para tipos suportados foram confirmadas
directamente pelo utilizador. As verificações ainda abertas estão detalhadas em
`docs/RELEASE_QA_CHECKLIST.md`; a implementação por si só não conta como
validação manual.

------------------------------------------------------------------------

# 25. Definição de MVP concluído

O MVP ainda não está pronto para distribuição. Além dos fluxos de biblioteca e
carga, os requisitos de conclusão incluem: lifecycle e bolha verificados,
carregamento de chains validado, export Collections verificado com backup,
recuperação de snapshots testada, execução do slice arm64 em hardware Apple
Silicon, instalador,
licença e documentação de utilizador. O comportamento depois de carregar um
plugin continua a ser o próprio Ableton a instanciar o plugin; não há validador
prévio por decisão do utilizador.

------------------------------------------------------------------------

# 26. Critérios de qualidade

Não considerar "pronto" apenas porque funciona uma vez.

### Integração

-   loading consistente;
-   identificação correta;
-   erros tratados.

### Performance

-   bubble praticamente irrelevante em idle;
-   pesquisa imediata;
-   sem scans desnecessários.

### UX

O PlugSpot só tem valor se for **mais rápido do que abrir e procurar no
Browser do Ableton**.

Este é o teste fundamental.

### Manutenção

-   dependência do Live isolada;
-   protocolo documentado;
-   database migrável;
-   código modular;
-   logs úteis.

------------------------------------------------------------------------

# 27. Logging

Durante desenvolvimento:

``` text
[PlugSpot/App]
[PlugSpot/Bridge]
[PlugSpot/DB]
[PlugSpot/Search]
[PlugSpot/Remote]
```

Logs devem ajudar a responder:

-   conectou?
-   que versão do Live?
-   quantos VST3 encontrou?
-   que ID tentou carregar?
-   em que track?
-   que erro ocorreu?

Release final deve evitar logging excessivo.

------------------------------------------------------------------------

# 28. Ordem correta de desenvolvimento

**Não começar pela interface visual.**

Sequência:

``` text
1. Remote Script corre
        ↓
2. Browser é enumerável
        ↓
3. ID estável é descoberto
        ↓
4. Track selecionada funciona
        ↓
5. Plugin carrega
        ↓
6. Processo externo consegue mandar carregar
        ↓
7. Swift app comunica
        ↓
8. Bubble + Search
        ↓
9. SQLite
        ↓
10. Tags/Favorites/Recent
        ↓
11. Import Ableton
        ↓
12. Cards/List/design
        ↓
13. Robustez
        ↓
14. Packaging
        ↓
15. GitHub release
```

Se os passos 1--6 falharem de forma fundamental, paramos e reavaliamos
antes de investir na aplicação.

------------------------------------------------------------------------

# 29. Primeiro sprint recomendado

## Sprint 0 --- Technical Proof

### Tarefa 0.1

Criar repositório.

### Tarefa 0.2

Documentar versão exata de Ableton/macOS/Python interno.

### Tarefa 0.3

Instalar Remote Script mínimo.

### Tarefa 0.4

Dump da árvore relevante do Browser.

### Tarefa 0.5

Isolar apenas VST3.

### Tarefa 0.6

Guardar IDs/propriedades de 5--10 plugins.

### Tarefa 0.7

Reiniciar Live e verificar estabilidade dos IDs.

### Tarefa 0.8

Obter selected track.

### Tarefa 0.9

Carregar plugin por ID.

### Tarefa 0.10

Carregar três plugins seguidos.

### Tarefa 0.11

Criar IPC mínimo.

### Tarefa 0.12

Criar CLI de teste externa:

``` text
plugspot-test list
plugspot-test track
plugspot-test load <id>
```

### Gate do Sprint 0

Só avançamos se:

``` text
external command
      ↓
Remote Script
      ↓
Ableton
      ↓
VST3 loaded successfully
```

for repetível e estável.

------------------------------------------------------------------------

# 30. Segundo sprint recomendado

## Sprint 1 --- Native Shell

1.  criar projeto Swift/SwiftUI;
2.  Universal Binary;
3.  implementar AbletonBridge;
4.  conectar;
5.  listar plugins;
6.  Search simples;
7.  carregar;
8.  criar bubble;
9.  abrir/fechar painel;
10. keyboard navigation.

**Gate:**

``` text
Bubble → Search → Enter → Plugin
```

------------------------------------------------------------------------

# 31. Terceiro sprint recomendado

## Sprint 2 --- Library

1.  SQLite;
2.  cache;
3.  favorites;
4.  recent;
5.  categories;
6.  tags;
7.  refresh;
8.  persistence;
9.  Cards/List.

------------------------------------------------------------------------

# 32. Quarto sprint recomendado

## Sprint 3 --- Ableton Migration

1.  investigar metadata real;
2.  importar organização;
3.  onboarding;
4.  reimport;
5.  export;
6.  import;
7.  merge strategy.

------------------------------------------------------------------------

# 33. Quinto sprint recomendado

## Sprint 4 --- Release Candidate

1.  performance;
2.  Intel profiling;
3.  Apple Silicon test;
4.  crash handling;
5.  packaging;
6.  install/uninstall;
7.  documentation;
8.  license;
9.  GitHub Actions, se útil;
10. primeira release pública.

------------------------------------------------------------------------

# 34. Regra para novas funcionalidades

Antes de adicionar algo perguntar:

> Isto torna encontrar/carregar um plugin mais rápido ou mais agradável
> sem tornar o PlugSpot pesado/frágil?

Se não, não entra na V1.

Exemplos:

**Sim:** - melhores filtros; - favoritos; - recentes; - keyboard
navigation.

**Provavelmente depois:** - AI; - cloud; - animações; - screenshots
automáticos; - analytics; - múltiplas DAWs.

------------------------------------------------------------------------

# 35. Visão futura possível

Sem compromisso de implementação:

``` text
PlugSpot
│
├── Plugins
│   ├── VST3
│   └── AU
│
├── Favorites
├── Recent
├── Tags
│
├── Chains
│   ├── Vocal
│   ├── Drum Bus
│   └── Master
│
├── Racks (.adg)
│
└── Search
```

Mas a força do projeto deve continuar a ser:

**abrir → pesquisar → carregar.**

------------------------------------------------------------------------

# 36. Resumo das certezas

Temos como decisões firmes:

-   nome de trabalho PlugSpot;
-   open-source/grátis como objetivo;
-   Ableton apenas;
-   Live 12.4.2 como versão inicial de referência; outras versões serão verificadas no Sprint 0;
-   macOS primeiro;
-   Intel + Apple Silicon;
-   VST3 primeiro;
-   offline;
-   nativo e leve;
-   bubble;
-   painel rápido;
-   Cards + List;
-   rato + teclado;
-   pesquisa convencional;
-   favoritos;
-   recentes;
-   categorias;
-   tags;
-   organização própria;
-   importação inicial do Ableton;
-   import/export;
-   vários plugins por sessão do painel;
-   Remote Script como bridge atual;
-   isolamento da integração Ableton;
-   SQLite como preferência;
-   captura de screenshots de GUI adiada; lookup de arte local implementado;
-   fila temporária, Chain Sets persistentes e exportação `.adg` implementados;
    falta validar ficheiros gerados no Live;
-   recuperação integral de presets de terceiros não prometida.

------------------------------------------------------------------------

# 37. O que ainda precisamos provar

1.  comportamento da mixer, listeners debounced e autosave com um Set real;
2.  leitura offline de snapshots depois de um crash/fecho do Live;
3.  carga de chains e compatibilidade em diferentes tipos de track;
4.  lifecycle e comportamento visual da bolha em Spaces, fullscreen e monitores;
5.  ciclo real de export Collections, incluindo backup e rollback;
6.  CPU/RAM/latência no iMac Intel depois de fechadas as funcionalidades;
7.  teste runtime do slice arm64 em Apple Silicon, instalador, licença e
    publicação (os builds arm64 e Universal já são produzidos pelo script).

A carga do FabFilter Pro-Q 4 por PlugSpot já foi confirmada pelo utilizador.
A pré-validação de plugins foi retirada e não faz parte desta lista.

------------------------------------------------------------------------

# 38. Próxima ação

Instalar a versão atualizada do Remote Script e executar o teste integral manual
no Ableton: arranque e encerramento, bolha, pesquisa e filtros, inserção simples
e chains, mixer e recuperação de snapshots, e exportação de Collections com
backup e rollback. O Sprint 0 não precisa de ser repetido; a
bridge/catalogação estão demonstradas e o utilizador já confirmou uma carga do
FabFilter Pro-Q 4.
