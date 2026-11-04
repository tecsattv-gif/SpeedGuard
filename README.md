# SpeedGuard

App Android de alerta de radares para o mundo todo, feito em Flutter. Avisa por voz e vibração antes de radares fixos, de semáforo e reportados pelo usuário, e se adapta automaticamente à lei de cada país.

Autor: Luiz Alberto Cardoso

**Site do app:** https://tecsattv-gif.github.io/SpeedGuard/ (recursos, vídeo tutorial e passo a passo)

## Funções (versão 1.26.2)

- **Visual neon** com as cores da tela de abertura: fundo roxo escuro, velocímetro com borda violeta brilhante, botão INICIAR em degradê vermelho→rosa, cartões e botões roxos; o painel flutuante e a janela de reportar seguem a mesma paleta
- **Tela de abertura** (2,5 s) com a arte do SpeedGuard (velocímetro e rastro de luz) e os créditos do autor
- **Ícone próprio** com o velocímetro (inclui ícone adaptativo do Android 8+)
- **Mapa** (OpenStreetMap) com sua posição e os radares da região
- **Navegar** (botão ao lado de Opções): digite o destino e escolha **Google Maps** ou **Waze**; o app abre já navegando (campo vazio só abre o app). Se o monitoramento estiver parado, o SpeedGuard liga sozinho antes, e o painel flutuante (se ligado) avisa os radares por cima da navegação
- **Opções do mapa** (botão **Opções** no canto de baixo à esquerda), como no CamSam: liga e desliga cada camada, com bolinha colorida. O que fica desligado some do mapa e não gera aviso:
  - 🔴 Radares fixos (inclui os reportados) · 🟠 Radares de semáforo · 🟣 Radares móveis
  - 🟠 Filas · 🔴 Acidentes · 🟠 Obras · 🟠 Perigos (obstáculo, avaria, pista escorregadia) · 🔵 Polícia
  - Mais: **O mapa segue você**
- **Avisos de trânsito reportados pelos motoristas**: no botão de reportar aparecem **Fila, Acidente, Obras, Perigo e Polícia** acima das placas de velocidade; um toque já reporta para todos. Cada aviso **some sozinho depois de 6 horas** e é **apagado do Firebase automaticamente** pelo primeiro celular que baixar a região depois disso (as regras só permitem apagar aviso já vencido); se alguém reportar o mesmo aviso no mesmo lugar (até 150 m), ele não duplica e ganha mais 6 h. Os avisos usam os mesmos alertas de 1000 a 100 m dos radares
- **Tutorial em vídeo** (Configurações → **Tutorial**): vídeo de 7 min, narrado, mostrando como configurar e usar o app. O vídeo vai dentro do app (`assets/tutorial.mp4`, ~11 MB) e funciona sem internet; tem play/pausa, voltar e avançar 10 s e barra para arrastar
- **Pessoas conectadas**: dois cards pequenos, lado a lado no alto da tela (acima do círculo da velocidade), mostram quantas pessoas estão com o SpeedGuard conectado agora: 🌍 **no mundo** e com a bandeira do **país onde você está** (ex.: 🇫🇷 12 no país). Conta quem está com o app aberto ou monitorando; atualiza a cada minuto e quem fecha o app sai da contagem em até 4 minutos. Cada aparelho grava só o código do país e o horário na coleção `presence` do Firebase (sem dados pessoais). Os cards só aparecem depois que as regras da coleção `presence` (abaixo) forem publicadas no console
- **Ícone no mapa** (Configurações → Ícone no mapa): **Seta**, **Carro**, **Caminhão** (cavalo com carreta) ou **Moto**, desenhados vistos de cima e girando conforme a direção
- **Card de status limpo**: enquanto os radares da região são baixados aparece só um símbolo girando ao lado da velocidade; ao terminar, o card "N radares carregados" aparece por 4 segundos e some. Com radar à frente o card volta mostrando a distância
- **Cores do app** em Configurações: **Roxo** (padrão), **Azul**, **Verde claro**, **Verde**, **Verde escuro**, **Laranja**, **Vermelho**, **Grafite** ou **Preto** (fundo preto puro; Verde claro, Verde escuro e Preto desde a 1.27.1). Troca na hora o app inteiro (fundos, bordas, botões, velocímetro e o painel flutuante); as cores de alerta (vermelho e laranja dos radares) continuam as mesmas para não confundir
- **Aparência** em Configurações: **Auto** (segue o modo claro/escuro do celular), **Claro** ou **Escuro**. No modo escuro o mapa também fica escurecido para não ofuscar à noite. A tela de abertura e o painel flutuante continuam sempre escuros
- **Duas telas no app aberto**, como no CamSam: o botão ao lado de Configurações alterna entre o **Mapa** e a **Tela de alerta** (sem mapa). A tela de alerta mostra **6 faixas verdes** (setas para cima) com o caminho livre. Com radar à frente aparecem a placa do limite, a distância e o tipo do radar, e **a cada aviso uma faixa fica vermelha, de baixo para cima** (1000 m = 1 faixa, 800 m = 2, 500 m = 3, 400 m = 4, 300 m = 5, 100 m = as 6), junto com o aviso sonoro. Acima do limite aparece "REDUZA A VELOCIDADE". O app lembra a última tela escolhida
- **Parks à frente** (1.24.0), em Configurações (ligado por padrão): mostra num card azul, em cima dos botões Opções/Navegar, o **próximo park no seu sentido** — áreas de descanso (`highway=rest_area`), áreas de serviço (`highway=services`) e estacionamentos de caminhão (`amenity=parking` com `hgv=yes/designated` ou `parking=truck_stop`) do OpenStreetMap, num raio de 60 km (baixados de novo a cada 25 km). Mostra distância, nome, tipo, lado (perto) e o que tem marcado no mapa: WC, chuveiro, combustível, restaurante, vagas, pago/grátis. Toque no card para ver os **3 próximos**; o botão de rota abre o **Google Maps** (ou o Waze) até o park. Aviso de voz a 2 km: "Park a 2 quilômetros, à direita." Áreas de autoestrada do lado contrário (outra pista) são ignoradas. O painel flutuante mostra "P 12 km". A distância é em linha reta (pela estrada pode ser um pouco mais)
  - **1.29.0 — parks só do seu sentido**: a base grava a pista (via de mão única principal) ao lado de cada park (até 300 m). Park de autoestrada só aparece quando a pista dele vai no seu sentido — a qualquer distância (antes o lado só era conferido até 3 km, e longe apareciam parks dos dois sentidos). Vale para o card, o botão P e a lista de parks da rota (comparando com o sentido da rota naquele ponto). Park de estrada comum (mão dupla) serve os dois sentidos
  - **Botão P** (1.24.1), ao lado de Navegar: abre a janela **Parks à frente** com os 3 próximos parks no seu sentido (nome, distância, tipo, lado e o que oferecem). Um toque no park abre a rota no **Google Maps** (ou no Waze, se não houver Google Maps). Funciona também com o monitoramento parado; parado sem direção, mostra os 3 mais perto
  - **Compartilhar park** (1.24.2): botão separado ao lado da rota, na janela do P e no card. Envia por WhatsApp, SMS, e-mail etc. o nome, o tipo, o que o park oferece e o link do Google Maps
  - **Parks da rota** (1.25.0): ao digitar um destino em **Navegar**, o SpeedGuard calcula a mesma rota (OSRM, do OpenStreetMap; o Google Maps não deixa outros apps lerem a rota dele) e busca os parks a até 600 m dela, só do seu sentido. O botão P passa a mostrar **os 20 próximos parks da rota** (5 na 1.25.4, 10 na 1.26.1), com a **distância pela estrada**, antes mesmo de sair; os que ficam para trás saem da lista, e o card e o aviso de 2 km usam o próximo da rota. Se você sair da rota, volta a mostrar os parks à frente pelo rumo. Ao chegar ao destino (ou no botão **Encerrar rota**) a rota é apagada. O destino é procurado no Nominatim (OpenStreetMap). A rota é de carro e pode diferir da do Google se ele desviar por trânsito
  - **1.25.1**: as buscas no OpenStreetMap (radares, limite da via, parks, parks da rota) entram numa **fila única** — antes iam juntas, o servidor recusava (erro 429) e a lista de parks ficava vazia. Estacionamentos de caminhão também são reconhecidos por `hgv=only` e pelo nome (truck, camion, LKW, vrachtwagen, safe parking, Autohof). A janela do P se atualiza sozinha enquanto busca, e o botão Encerrar rota não fica mais embaixo da barra do Android
  - **1.25.2**: a busca dos parks da rota é feita por **retângulos de ~15 km** ao longo do caminho (até 8 por busca, ~120 km), filtrando depois pela distância até a rota. A busca "em volta da linha da rota" da 1.25.0 era lenta demais no servidor e a lista ficava carregando para sempre
  - **1.25.3**: a rota é buscada **trecho a trecho** (~60 km por vez, começando pelo mais perto). A lista do P já mostra os primeiros parks enquanto o resto carrega ("12 parks até agora · buscando o resto da rota (2/7)…"); trecho que falhar é pulado; radares e limite da via não ficam mais esperando a rota inteira
  - **1.25.4**: busca **leve**: só os primeiros 80 km da rota (o resto vem sozinho quando faltam menos de 40 km do já buscado), por retângulos e só com filtros que o servidor responde rápido (`highway=rest_area/services`, `amenity=parking` com `hgv`, `parking=truck_stop`); a busca por nome saiu. Parks em volta (sem rota): raio de ~25 km. O P mostra os **5 próximos** da rota
  - **1.26.1**: o P mostra os **10 próximos parks** da rota (**20** desde a 1.26.2), com a **distância em destaque** (azul, antes do nome). Com a base própria a rota é carregada em pedaços de 200 km (o próximo vem quando faltam menos de 120 km)
- **Aviso de velocidade excedida** (1.23.0), em Configurações (ligado por padrão):
  - **Caminhão** (veículo escolhido em Configurações): funciona como o limitador — passou do valor escolhido em Configurações → **Limitador do caminhão** (**80**, ou de **90 a 95 km/h**: 90, 91, 92, 93, 94, 95 — desde a 1.29.2, para caminhões cujo limitador só corta acima de 90; a placa continua mostrando 90, só a contagem começa mais acima): **não fala nada**, o velocímetro fica vermelho com a contagem dos 30 s; **aos 20 s** (faltando 10 s) fala "Atenção." e **aos 30 s** fala uma vez "Velocidade excedida. Tempo excedido." e o velocímetro mostra **"VELOCIDADE EXCEDIDA"** até você voltar ao limite (desde a 1.28.7). O aviso de velocidade **não vibra** o celular (desde a 1.28.8). Voltou para o valor escolhido ou menos, a contagem zera. Se a via tiver limite menor que o do caminhão, avisa uma vez "Limite da via 70."
  - **Carro, moto e seta**: a mesma contagem, usando o limite da via
  - **Som do aviso de velocidade** (1.27.2), em Configurações logo abaixo do aviso: **Voz** (as frases acima), **Bipe** (um bipe aos 20 s e o bipe rápido aos 30 s; "Limite da via" vira um bipe curto) ou **Mudo** (1.27.4: sem som nenhum, mas o aviso na tela continua igual — velocímetro vermelho, contagem dos 30 s embaixo e depois "VELOCIDADE EXCEDIDA"). O aviso na tela também continua com Alertas sonoros desligado. É separado do som dos radares
  - Em cima do velocímetro aparece a **placa com o limite da via** (no caminhão, no máximo o do limitador) e, acima do limite, o velocímetro fica vermelho com a **contagem regressiva dos 30 s** (depois dos 30 s mostra "VELOCIDADE EXCEDIDA"). O painel flutuante também mostra a placa e, desde a 1.27.5, a **contagem dos 30 s** embaixo da velocidade (depois "EXCEDIDA"); ao passar dos 30 s abre por cima do mapa um **pop-up vermelho "VELOCIDADE EXCEDIDA"** com a velocidade, que fecha sozinho em 6 s ou com um toque (uma vez por excesso)
  - O limite da via vem do OpenStreetMap (`maxspeed`; no caminhão `maxspeed:hgv`, ou o menor entre o limite da via e o máximo de caminhão do país: Bélgica 90 em autoestrada e 60 nas outras vias, Alemanha/Holanda/Áustria 80, França/Espanha/Portugal/Itália/Luxemburgo 90) — vias baixadas num raio de 2,5 km, de novo a cada 1,8 km rodados. Via sem limite no mapa: não mostra placa (o caminhão continua com o limitador)
- **GPS** (1.22.1): usa o provedor normal do Android (*fused*), como até a 1.21.0 — a velocidade e a posição na tela são as do GPS, sem atraso. Um filtro leve só descarta leituras de antena/Wi‑Fi que chegam no meio de leituras boas (jogavam o veículo para uma rua ao lado com 0 km/h) e saltos impossíveis. Se o GPS ficar de 2 a 6 s sem mandar leitura acima de 30 km/h, **só os avisos de radar** seguem o veículo pela última velocidade e direção. (A 1.22.0 forçava o chip de GPS e corrigia a velocidade; em alguns celulares isso deixou tudo lento e foi desfeito.)
- **Só radares da minha via** (1.28.0), em Configurações (ligado por padrão): o app só avisa os radares que estão na **mesma rodovia/rua** onde o veículo está. Usa as vias do OpenStreetMap já baixadas para o limite da via (raio de 2,5 km): descobre a via atual (número, como `E 40`/`A 2`, ou o nome) e, para cada radar à frente, vê qual via passa mais perto dele (até 40 m). Se a mais perto for outra (rua ao lado, marginal, rua que cruza por baixo/por cima), o radar é ignorado. Desde a **1.28.1** também confere o **sentido**: em autoestrada e via de mão única, radar da pista do outro sentido é ignorado (mesmo sendo a mesma rodovia, ex.: R0), e radar em **alça de entrada/saída** (`*_link`) não conta como a rodovia. Quando não dá para saber (vias ainda não baixadas, radar fora da área baixada) ou o radar está a menos de 20 m (60 m na 1.28.0), avisa como antes, para não perder radar. **1.28.2**: a checagem ficou leve — as vias perto de cada radar são calculadas uma vez só (com um teste rápido de "caixa" de cada via) em vez de a cada leitura do GPS; na 1.28.0/1.28.1 isso atrasava o velocímetro e o painel flutuante. **1.28.3**: o mapa desenha só os radares da área da tela (no máximo 250, os mais perto do centro). Com o raio de 60 km, em cidade grande (Bruxelas: ~1.100 radares) o app redesenhava todos a cada leitura do GPS e o velocímetro e o ícone do veículo travavam. Os avisos continuam usando todos os radares carregados. **1.28.4**: cada etapa da leitura do GPS (mapa, avisos, limite da via, parks…) roda protegida — um erro numa delas não congela mais o velocímetro e o card (antes a tela só se atualizava no fim do cálculo dos avisos). O erro fica em Configurações → **Diagnóstico (último erro)**
  - **1.29.0 — via de cada radar na base própria**: a base (`tools/road_match.py`, no workflow `data.yml`) grava, para cada radar, as vias a até 50 m dele: tipo (`highway`), número (`ref`), nome, se é mão única (e o sentido) e o rumo do trecho. O app não depende mais do Overpass para isso e ignora o radar quando: a via é **mão única no sentido contrário** (pista do outro sentido); a via é de **mão dupla e atravessada** em relação ao seu rumo (rua que cruza); a via tem **outro número/nome** que a sua (paralela, marginal); é **alça de entrada/saída** e você está na rodovia (ou o contrário); ou, sem saber a sua via, você está a **mais de 70 km/h** e o radar é de rua de bairro. A sua via (número/nome) continua vindo do Overpass, agora num raio de 1,5 km (mais leve). Mapas enormes (EUA) ficam sem essa informação e usam a regra anterior
- **Parado = 0 km/h** (1.28.5): parado, o GPS do celular "anda" sozinho e o velocímetro marcava 1, 3 e até 11 km/h. Agora, se o GPS disser menos de 4 km/h, ou se em 3 s o veículo andou menos de 6 m, o app mostra 0 (e não conta como excesso de velocidade)
- **Sentido do radar**: no OpenStreetMap uns marcam o sentido do trânsito e outros para onde a câmera aponta. Desde a 1.22.1 o radar só é ignorado quando está atravessado em relação à via (antes radares marcados "ao contrário" não avisavam)
- **Radares de semáforo** (1.23.1): o app passou a ler também as **relações de fiscalização** do OpenStreetMap (`type=enforcement`), que é como a maioria dos radares de semáforo e muitos de velocidade estão marcados — a câmera é o membro `device` (ou `from`) e o tipo/limite vêm da relação. Também reconhece radar de semáforo marcado em `speed_camera`, `camera:type` ou `surveillance:type` (`traffic_signals`/`red_light`). Avisam como os outros: "Radar de semáforo a 1000 metros." e depois as distâncias. Na 1ª abertura da 1.23.1 os radares da região são baixados de novo
- **Atualização pelo próprio app** (1.27.0): cada build do GitHub publica o APK numa **Release** (`v1.27.0`, etc.). Ao abrir o app (com o monitoramento parado, no máximo a cada 6 h) o SpeedGuard pergunta ao GitHub qual é a última versão; se houver uma mais nova aparece "Nova versão do SpeedGuard — Atualizar / Agora não". Com **Atualizar** o app baixa o APK (com barra de progresso) e abre o instalador do Android, que pede a confirmação final; na 1ª vez o Android pede para liberar **Instalar apps desconhecidos** para o SpeedGuard. "Agora não" não pergunta de novo pela mesma versão. Em Configurações → **Procurar atualização do app** dá para verificar na hora. Como o APK sai sempre com a mesma chave, instala por cima sem perder configurações. A 1.27.0 em si precisa ser instalada à mão uma última vez (Actions ou Releases). Desde a **1.28.9** a versão instalada aparece em Configurações (embaixo de Procurar atualização e no item "SpeedGuard <versão>"), lida do próprio app e atualizada sozinha a cada nova versão (antes ficava fixa em "1.19.0")
- **Base própria de parks e radares** (1.26.0): toda segunda-feira o GitHub (workflow `data.yml` + `tools/build_data.py`) baixa os mapas oficiais de cada país da **Europa e das Américas** (do Norte, Central e do Sul — desde a 1.26.1) no **Geofabrik**, um continente em paralelo (os EUA vêm num arquivo só; os pedaços por estado são ignorados), separa com o `osmium` os parks (áreas de descanso/serviço e estacionamentos de caminhão) e os radares (inclusive os das relações de fiscalização, como os de semáforo) e publica em pedaços de 2° × 2° no ramo **`data`** do repositório (sem histórico; cada semana substitui a anterior). O app baixa só os pedaços perto de onde está (`raw.githubusercontent.com`), guarda no celular e usa por 7 dias — **funciona offline e não depende dos servidores Overpass**, que às vezes caem todos juntos (aconteceu em 02/11/2026: 502, 504 e sem resposta). Região fora da base (fora da Europa e das Américas) ou sem internet e sem cópia guardada: o app usa o Overpass como antes. O limite de velocidade da via continua vindo do Overpass. Primeira base completa (03/11/2026): **57.701 parks** e **57.918 radares** em 1.089 pedaços. Para gerar a base na hora: Actions → "Base de parks e radares" → Run workflow (dá para escolher só alguns países)
  - **1.26.3**: os radares da base são carregados num raio de **60 km** (antes 30; o Overpass, quando usado de reserva, continua com 30 km) e baixados de novo a cada 20 km rodados — perto da fronteira (ex.: Bilzen, a ~35 km da Alemanha) o mapa já mostra o outro lado sem precisar arrastar. O app confere a versão da base (`meta.json`, a cada 3 h) e **baixa de novo os pedaços guardados de uma versão anterior**, mesmo com menos de 7 dias (antes um pedaço baixado de uma base incompleta ficava no celular por 7 dias — foi por isso que a Alemanha aparecia sem radares). Pedaço que não existe na base (mar, por exemplo) conta como vazio em vez de jogar tudo para o Overpass. **Atualizar radares agora** ignora a cópia guardada e baixa tudo de novo
- **Base mundial de radares** baixada automaticamente do OpenStreetMap num raio de 60 km (30 km quando vem do Overpass), atualizada a cada 6 h ou a cada 20 km rodados, e guardada para uso offline. Usa três servidores Overpass (overpass-api.de, private.coffee e mail.ru): se um estiver fora do ar, ocupado ou estourar o tempo, tenta o próximo. Resposta com erro interno do servidor não apaga os radares já salvos, e depois de uma falha o app espera 90 s antes de tentar de novo (antes pedia a cada leitura do GPS e o servidor bloqueava). Configurações → **Atualizar radares agora** força o download na hora
- **Ver radares de outra região**: arraste o mapa para qualquer lugar do mundo e aproxime o zoom; 1 segundo depois de soltar, o app baixa os radares da área que está na tela (com uma margem em volta) e mostra o símbolo girando enquanto carrega. Esses radares são só para ver no mapa; os avisos continuam usando os radares em volta de você
- **Volume dos avisos** (1.27.3), em Configurações logo abaixo de Alertas sonoros: barra de 10% a 100% que vale para a voz e os bipes (radares e velocidade excedida); 100% é o volume do celular. Ao soltar a barra o app toca uma amostra
- **Radares de velocidade média** (1.29.1): antes apareciam como "Radar fixo". Agora têm tipo e camada próprios (Opções → **Velocidade média**, cor ciano). Das relações de fiscalização `enforcement=average_speed` o app pega o **início** (`from`, ou a câmera) e o **fim** (`to`) do trecho. Avisos: "Radar de velocidade média a 1000 metros. Limite 70." … e "Fim da velocidade média a …". Ao passar pelo início: "Controle de velocidade média iniciado. Limite 70." e embaixo do velocímetro aparece **"Média 68"** (vermelho acima do limite), medida pela distância e tempo desde o início. Média acima do limite: "Média 75. Acima do limite. Reduza." (no máximo a cada 60 s). No fim: "Fim do controle de velocidade média. Média 68." Trecho sem fim no mapa: a média some depois de 40 km ou 40 min. Segue os modos Voz/Bipe/Mudo do aviso de velocidade
- **Avisos a 1000, 800, 500, 400, 300 e 100 m** do radar (desde a 1.22.0; antes eram de 500 a 100 m), com vibração. O radar aparece na tela a partir de 1100 m. Em Configurações → **Alertas sonoros** dá para escolher:
  - **Voz**: o 1º aviso já fala o limite do radar — "Radar fixo a 1000 metros. Limite 80." —, depois "800 metros.", "500 metros.", "400 metros.", "300 metros." e por fim "100 metros. Limite 80."
  - **Bipe**: um bipe a cada aviso, cada vez mais agudo (bipe duplo a 100 m), e uma sequência rápida se estiver acima do limite. Os bipes só abaixam a música/navegação por um instante
  - Se o radar aparecer já perto (ex.: a 250 m), só o aviso daquela distância é dado
  - **Modo discreto** (voz): fala só a distância ("1000 metros")
- **Aviso "Reduza a velocidade"** quando você passa do limite perto do radar
- Só avisa radares **à frente** e, quando o sentido do radar é conhecido, só para quem vai naquele sentido
- **Velocímetro** grande, que fica vermelho acima do limite
- **Funciona com a tela apagada ou em segundo plano** (notificação "SpeedGuard ativo")
- **Reportar radar** (móvel ou fixo) na sua posição atual: abre uma janela com as placas de limite prontas (30, 40, 50, 60, 70, 80, 90, 100, 110, 120, 130 ou "?") e **um toque já salva**, sem digitar. O radar vai para o Firebase e **todos os usuários veem**. **Sem duplicados**: se já houver um radar compartilhado a menos de 150 m, no mesmo sentido, o app não cria outro; o reporte conta como confirmação (radar móvel ganha mais 48 h) e aparece "Esse radar já estava reportado"
- **Confirmação de radares móveis**: eles não somem sozinhos. Depois de 48 h, quem passar a menos de 150 m recebe a pergunta "O radar móvel ainda está aqui?" na tela e na bolha flutuante. **Sim** mantém por mais 48 h; **Não** apaga o radar
- **Painel flutuante** (some ao tocar em **PARAR**) por cima do Google Maps / Waze, no estilo do CamSam (ativar em Configurações; pede a permissão "Sobrepor a outros apps"). Aparece no canto superior esquerdo, pode ser arrastado e não bloqueia o resto do mapa. Em **Configurações**, com "Bolha flutuante" ligada, aparecem logo abaixo as opções (desligada, elas ficam escondidas):
  - **Tamanho**: Pequeno, Médio (igual ao CamSam, 64 × 250 dp) ou Grande
  - **Formato**: Vertical (retrato) ou Horizontal (paisagem, 240 × 72 dp no Médio), com uma miniatura mostrando como fica
  - O tamanho é convertido para pixels e conferido pelo próprio painel ao abrir, para ficar certo em qualquer tela

  - **Toque duplo no painel**: abre o SpeedGuard direto em tela cheia (o painel some e volta quando você sair do app). Desde a 1.6.4 não aparece mais a janela "Completar ação usando" pedindo para escolher outro app
  - **Reportar pelo painel** (botão + do painel): a janela traz em cima os avisos **Fila, Acidente, Obras, Perigo e Polícia** e embaixo Móvel/Fixo com as placas de velocidade, igual à janela do app em tela cheia (desde a 1.21.0; antes o painel só reportava radares). Um toque já envia para todos; o app confirma por voz ("Obras reportado. Obrigado!")
  - **Fechar o painel**: toque no **✕** no canto de cima, ou segure o dedo parado sobre ele por meio segundo (vibra e fecha na hora, mesmo com o app em segundo plano). O monitoramento e a voz continuam; o painel volta da próxima vez que você sair do SpeedGuard

  Conteúdo do painel:
  - em cima: velocidade atual (vermelha acima do limite)
  - no meio: as mesmas **6 faixas verdes** da tela de alerta. De 1000 m até o radar, **a cada aviso uma faixa fica vermelha, de baixo para cima**, com a placa do limite e a distância (laranja, ou vermelho se estiver acima do limite); o aviso de voz ou bipe toca junto. Depois de passar o radar, as faixas voltam a ficar verdes. Também mostra a pergunta "Radar ainda aí?" com ✓/✗
  - embaixo: botão **+** que abre a janela de reportar radar com as velocidades prontas, sem sair do Maps. Fecha sozinha em 20 s se nada for escolhido; o app confirma por voz "Radar reportado"
  - como usar: ative **Configurações → Bolha flutuante**, permita "Sobrepor a outros apps", toque em **INICIAR** e abra o Maps/Waze. O painel abre no instante em que você sai do SpeedGuard (exigência do Android 15+) e some quando você volta para ele. Se faltar a permissão, o app avisa ao voltar
- Placas no mapa mostram o limite inteiro, inclusive com 3 dígitos (110, 130)
- Cores no mapa: vermelho = fixo, amarelo = semáforo, violeta = reportado por usuários, laranja = seu reporte local; sua posição é o ícone escolhido (seta, carro, caminhão ou moto)
- **Regras por país**, detectado pelo GPS:

| País | Comportamento |
|---|---|
| Suíça | Alertas desligados (proibido por lei) |
| Alemanha | Funciona, com aviso de que só passageiros podem usar |
| Demais países (inclusive França) | Modo completo |

> França: o modo "zona de perigo" foi removido a pedido do autor. Lá, usar ao dirigir um app que mostra a posição exata dos radares é infração (art. R413-15 do Code de la route).

> Antes de publicar na Play Store, revisar a legislação de cada país e completar a lista em `lib/country_rules.dart`.

## Estrutura

| Arquivo | O que faz |
|---|---|
| `lib/main.dart` | Telas, mapa, GPS e voz |
| `lib/park_service.dart` | Parks à frente: busca no OpenStreetMap, filtro pelo sentido e aviso a 2 km |
| `lib/tile_store.dart` | Base própria: baixa e guarda no celular os pedaços de parks e radares |
| `lib/update_service.dart` | Atualização pelo app: procura a última Release no GitHub, pergunta, baixa o APK e abre o instalador |
| `tools/build_data.py` | Gera a base própria a partir dos mapas do Geofabrik (roda no GitHub) |
| `lib/overpass_gate.dart` | Fila única das buscas no Overpass (evita o erro 429) |
| `lib/route_service.dart` | Rota até o destino digitado (Nominatim + OSRM) e posição do veículo na rota |
| `lib/road_limit.dart` | Limite de velocidade da via onde o veículo está (OpenStreetMap) e máximos de caminhão por país |
| `lib/speed_watch.dart` | Contagem dos 30 s acima do limite e frases de aviso |
| `lib/gps_filter.dart` | Filtro leve do GPS: descarta leituras de antena/Wi‑Fi e estima a posição só para os avisos quando o GPS atrasa |
| `lib/alert_engine.dart` | Decide quando e o que avisar |
| `lib/radar_service.dart` | Baixa radares (Overpass/OSM), cache, radares do usuário, detecção do país |
| `lib/community_service.dart` | Radares compartilhados entre usuários (Firestore via REST) |
| `lib/presence_service.dart` | Contagem de pessoas conectadas no mundo e no país (Firestore via REST) |
| `lib/tutorial_page.dart`, `assets/tutorial.mp4` | Tela do vídeo tutorial (Configurações → Tutorial) |
| `lib/firebase_config.dart` | ID do projeto e chave do Firebase |
| `lib/layers.dart` | Camadas do painel Opções (radares e avisos de trânsito) |
| `lib/vehicle_icon.dart` | Ícones da sua posição (seta, carro, caminhão, moto) |
| `lib/alert_view.dart` | Tela de alerta (6 faixas, placa e distância) |
| `lib/overlay.dart` | Painel flutuante sobre outros apps |
| `assets/sounds/` | Bipes dos avisos (1000 a 100 m e acima do limite) |
| `lib/theme.dart` | Paleta de cores e tema do app |
| `lib/splash_screen.dart` | Tela de abertura com créditos (2,5 s) |
| `assets/splash.png`, `assets/icon.png` | Arte da abertura e do ícone (criação original) |
| `android/app/src/main/res/` | Ícones do app e fundo escuro de abertura |
| `lib/speed_picker.dart` | Janela de reportar radar com as velocidades prontas |
| `lib/country_rules.dart` | Regras por país |
| `lib/models.dart` | Modelo do radar |
| `android/app/src/main/AndroidManifest.xml` | Permissões (GPS, segundo plano, internet) |
| `docs/` | Site de divulgação (GitHub Pages): `index.html`, imagens, vídeo, `robots.txt` e `sitemap.xml` |

## Site de divulgação (GitHub Pages)

A pasta `docs/` é o site público do app, com recursos, vídeo tutorial, passo a passo e regras por país. Para publicar: **Settings → Pages → Build and deployment → Deploy from a branch → `main` / `/docs` → Save**. O endereço fica https://tecsattv-gif.github.io/SpeedGuard/. Mudanças em `docs/` não disparam o build do APK.

Para aparecer no Google: no [Google Search Console](https://search.google.com/search-console), adicione a propriedade com prefixo de URL `https://tecsattv-gif.github.io/SpeedGuard/`, verifique pelo arquivo HTML (coloque-o em `docs/`) e envie o sitemap `sitemap.xml`.

## Como gerar o APK

O GitHub Actions compila sozinho a cada push na `main` (ou manualmente em **Actions → Build APK → Run workflow**). O APK fica em **Actions → última execução → Artifacts → SpeedGuard-apk**.

**Assinatura fixa (obrigatória):** o APK é assinado sempre com a mesma chave (CN=SpeedGuard). Ela fica no repositório **criptografada** em `android/signing.enc`; a senha vem do segredo **`SPEEDGUARD_KEYSTORE`** (Settings → Secrets and variables → Actions), que nunca sai do GitHub. Não apague nem troque esse segredo nem o arquivo: sem eles as atualizações deixam de instalar por cima. O build confere a chave e **para com erro** se ela estiver ilegível ou se o APK sair assinado com outra chave. Histórico: até a 1.23.1 o segredo estava corrompido e cada build saía com uma chave diferente — por isso aparecia "conflito com um pacote já existente". Na **1.23.2** é preciso **desinstalar uma última vez**; dali em diante as versões instalam por cima.

O workflow roda `flutter create` para gerar os arquivos Android que não estão no repositório, sem sobrescrever o manifesto.

## Radares compartilhados (Firebase)

**Já ativado** desde a versão 1.6.3. Os radares reportados ficam no Cloud Firestore do projeto Firebase **SpeedGuard001** (ID `speedguard001`, plano Spark gratuito), na coleção `radars`; as pessoas conectadas ficam na coleção `presence`. O app acessa pela API REST, com o ID do projeto e a chave de API da Web em `lib/firebase_config.dart`. A chave não é secreta (vai dentro do app); quem protege os dados são as regras abaixo, publicadas no console (na versão 1.19.0 entrou `'acidente'` na lista da regra de apagar; republique em **Firestore → Regras → Publicar**):

```
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /radars/{id} {
      allow read: if true;
      allow create: if request.resource.data.keys().hasOnly(
          ['lat','lon','cell','type','maxSpeed','direction','createdAt','checkAfter'])
        && request.resource.data.lat is number
        && request.resource.data.lon is number;
      // confirmação "ainda está": só renova o prazo
      allow update: if request.resource.data.diff(resource.data)
          .affectedKeys().hasOnly(['checkAfter']);
      // apaga radar móvel ("não está mais") ou aviso com mais de 6 h
      allow delete: if resource.data.type == 'movel'
        || (resource.data.type in ['fila', 'acidente', 'obra', 'perigo', 'policia']
            && resource.data.checkAfter < request.time.toMillis());
    }
    // pessoas conectadas: um documento por aparelho (país + horário)
    match /presence/{id} {
      allow read: if true;
      allow create, update: if request.resource.data.keys().hasOnly(
          ['country','bucket','cbucket','lastSeen'])
        && request.resource.data.bucket is int
        && request.resource.data.country is string
        && request.resource.data.country.size() <= 3;
    }
  }
}
```

Para trocar de projeto: crie o Firestore (edição Standard, modo produção), publique essas regras, registre um app Web `</>` em **Configurações do projeto** e coloque o novo `projectId` e `apiKey` em `lib/firebase_config.dart`. Deixando os dois vazios, os reportes ficam só no aparelho.

## Próximas versões

- Exigir mais de uma resposta "Não" antes de apagar, para evitar abuso
- Idiomas além do português

## Créditos

Dados de radares e mapas: © colaboradores do OpenStreetMap (ODbL).
