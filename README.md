# SpeedGuard

App Android de alerta de radares para o mundo todo, feito em Flutter. Avisa por voz e vibração antes de radares fixos, de semáforo e reportados pelo usuário, e se adapta automaticamente à lei de cada país.

Autor: Luiz Alberto Cardoso

**Site do app:** https://tecsattv-gif.github.io/SpeedGuard/ (recursos, vídeo tutorial e passo a passo)

## Funções (versão 1.25.3)

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
- **Cores do app** em Configurações: **Roxo** (padrão), **Azul**, **Verde**, **Laranja**, **Vermelho** ou **Grafite**. Troca na hora o app inteiro (fundos, bordas, botões, velocímetro e o painel flutuante); as cores de alerta (vermelho e laranja dos radares) continuam as mesmas para não confundir
- **Aparência** em Configurações: **Auto** (segue o modo claro/escuro do celular), **Claro** ou **Escuro**. No modo escuro o mapa também fica escurecido para não ofuscar à noite. A tela de abertura e o painel flutuante continuam sempre escuros
- **Duas telas no app aberto**, como no CamSam: o botão ao lado de Configurações alterna entre o **Mapa** e a **Tela de alerta** (sem mapa). A tela de alerta mostra **6 faixas verdes** (setas para cima) com o caminho livre. Com radar à frente aparecem a placa do limite, a distância e o tipo do radar, e **a cada aviso uma faixa fica vermelha, de baixo para cima** (1000 m = 1 faixa, 800 m = 2, 500 m = 3, 400 m = 4, 300 m = 5, 100 m = as 6), junto com o aviso sonoro. Acima do limite aparece "REDUZA A VELOCIDADE". O app lembra a última tela escolhida
- **Parks à frente** (1.24.0), em Configurações (ligado por padrão): mostra num card azul, em cima dos botões Opções/Navegar, o **próximo park no seu sentido** — áreas de descanso (`highway=rest_area`), áreas de serviço (`highway=services`) e estacionamentos de caminhão (`amenity=parking` com `hgv=yes/designated` ou `parking=truck_stop`) do OpenStreetMap, num raio de 60 km (baixados de novo a cada 25 km). Mostra distância, nome, tipo, lado (perto) e o que tem marcado no mapa: WC, chuveiro, combustível, restaurante, vagas, pago/grátis. Toque no card para ver os **3 próximos**; o botão de rota abre o **Google Maps** (ou o Waze) até o park. Aviso de voz a 2 km: "Park a 2 quilômetros, à direita." Áreas de autoestrada do lado contrário (outra pista) são ignoradas. O painel flutuante mostra "P 12 km". A distância é em linha reta (pela estrada pode ser um pouco mais)
  - **Botão P** (1.24.1), ao lado de Navegar: abre a janela **Parks à frente** com os 3 próximos parks no seu sentido (nome, distância, tipo, lado e o que oferecem). Um toque no park abre a rota no **Google Maps** (ou no Waze, se não houver Google Maps). Funciona também com o monitoramento parado; parado sem direção, mostra os 3 mais perto
  - **Compartilhar park** (1.24.2): botão separado ao lado da rota, na janela do P e no card. Envia por WhatsApp, SMS, e-mail etc. o nome, o tipo, o que o park oferece e o link do Google Maps
  - **Parks da rota** (1.25.0): ao digitar um destino em **Navegar**, o SpeedGuard calcula a mesma rota (OSRM, do OpenStreetMap; o Google Maps não deixa outros apps lerem a rota dele) e busca os parks a até 600 m dela, só do seu sentido. O botão P passa a mostrar **todos os parks da rota**, com a **distância pela estrada**, antes mesmo de sair; os que ficam para trás saem da lista, e o card e o aviso de 2 km usam o próximo da rota. Se você sair da rota, volta a mostrar os parks à frente pelo rumo. Ao chegar ao destino (ou no botão **Encerrar rota**) a rota é apagada. O destino é procurado no Nominatim (OpenStreetMap). A rota é de carro e pode diferir da do Google se ele desviar por trânsito
  - **1.25.1**: as buscas no OpenStreetMap (radares, limite da via, parks, parks da rota) entram numa **fila única** — antes iam juntas, o servidor recusava (erro 429) e a lista de parks ficava vazia. Estacionamentos de caminhão também são reconhecidos por `hgv=only` e pelo nome (truck, camion, LKW, vrachtwagen, safe parking, Autohof). A janela do P se atualiza sozinha enquanto busca, e o botão Encerrar rota não fica mais embaixo da barra do Android
  - **1.25.2**: a busca dos parks da rota é feita por **retângulos de ~15 km** ao longo do caminho (até 8 por busca, ~120 km), filtrando depois pela distância até a rota. A busca "em volta da linha da rota" da 1.25.0 era lenta demais no servidor e a lista ficava carregando para sempre
  - **1.25.3**: a rota é buscada **trecho a trecho** (~60 km por vez, começando pelo mais perto). A lista do P já mostra os primeiros parks enquanto o resto carrega ("12 parks até agora · buscando o resto da rota (2/7)…"); trecho que falhar é pulado; radares e limite da via não ficam mais esperando a rota inteira
- **Aviso de velocidade excedida** (1.23.0), em Configurações (ligado por padrão):
  - **Caminhão** (veículo escolhido em Configurações): funciona como o limitador — passou de **90 km/h** (ou 80, escolhido em Configurações → Limitador do caminhão), o app fala na hora "Limite de 90 excedido.", **aos 20 s** "Atenção. Você só tem 10 segundos para voltar aos 90." e **aos 30 s** "Velocidade excedida. Volte para os 90.", que se repete a cada 30 s enquanto continuar acima. Voltou para 90 ou menos, a contagem zera. Se a via tiver limite menor que o do caminhão, avisa uma vez "Limite da via 70."
  - **Carro, moto e seta**: a mesma contagem, usando o limite da via
  - Em cima do velocímetro aparece a **placa com o limite da via** (no caminhão, no máximo o do limitador) e, acima do limite, o velocímetro fica vermelho com a **contagem regressiva dos 30 s** (depois mostra "EXCEDIDA"). O painel flutuante também mostra a placa
  - O limite da via vem do OpenStreetMap (`maxspeed`; no caminhão `maxspeed:hgv`, ou o menor entre o limite da via e o máximo de caminhão do país: Bélgica 90 em autoestrada e 60 nas outras vias, Alemanha/Holanda/Áustria 80, França/Espanha/Portugal/Itália/Luxemburgo 90) — vias baixadas num raio de 2,5 km, de novo a cada 1,8 km rodados. Via sem limite no mapa: não mostra placa (o caminhão continua com o limitador)
- **GPS** (1.22.1): usa o provedor normal do Android (*fused*), como até a 1.21.0 — a velocidade e a posição na tela são as do GPS, sem atraso. Um filtro leve só descarta leituras de antena/Wi‑Fi que chegam no meio de leituras boas (jogavam o veículo para uma rua ao lado com 0 km/h) e saltos impossíveis. Se o GPS ficar de 2 a 6 s sem mandar leitura acima de 30 km/h, **só os avisos de radar** seguem o veículo pela última velocidade e direção. (A 1.22.0 forçava o chip de GPS e corrigia a velocidade; em alguns celulares isso deixou tudo lento e foi desfeito.)
- **Sentido do radar**: no OpenStreetMap uns marcam o sentido do trânsito e outros para onde a câmera aponta. Desde a 1.22.1 o radar só é ignorado quando está atravessado em relação à via (antes radares marcados "ao contrário" não avisavam)
- **Radares de semáforo** (1.23.1): o app passou a ler também as **relações de fiscalização** do OpenStreetMap (`type=enforcement`), que é como a maioria dos radares de semáforo e muitos de velocidade estão marcados — a câmera é o membro `device` (ou `from`) e o tipo/limite vêm da relação. Também reconhece radar de semáforo marcado em `speed_camera`, `camera:type` ou `surveillance:type` (`traffic_signals`/`red_light`). Avisam como os outros: "Radar de semáforo a 1000 metros." e depois as distâncias. Na 1ª abertura da 1.23.1 os radares da região são baixados de novo
- **Base mundial de radares** baixada automaticamente do OpenStreetMap num raio de 30 km, atualizada a cada 6 h ou a cada 15 km rodados, e guardada para uso offline. Usa três servidores Overpass (overpass-api.de, private.coffee e mail.ru): se um estiver fora do ar, ocupado ou estourar o tempo, tenta o próximo. Resposta com erro interno do servidor não apaga os radares já salvos, e depois de uma falha o app espera 90 s antes de tentar de novo (antes pedia a cada leitura do GPS e o servidor bloqueava). Configurações → **Atualizar radares agora** força o download na hora
- **Ver radares de outra região**: arraste o mapa para qualquer lugar do mundo e aproxime o zoom; 1 segundo depois de soltar, o app baixa os radares da área que está na tela (com uma margem em volta) e mostra o símbolo girando enquanto carrega. Esses radares são só para ver no mapa; os avisos continuam usando os radares em volta de você
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
