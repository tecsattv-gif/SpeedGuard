# SpeedGuard

App Android de alerta de radares para o mundo todo, feito em Flutter. Avisa por voz e vibração antes de radares fixos, de semáforo e reportados pelo usuário, e se adapta automaticamente à lei de cada país.

Autor: Luiz Alberto Cardoso

## Funções (versão 1.18.1)

- **Visual neon** com as cores da tela de abertura: fundo roxo escuro, velocímetro com borda violeta brilhante, botão INICIAR em degradê vermelho→rosa, cartões e botões roxos; o painel flutuante e a janela de reportar seguem a mesma paleta
- **Tela de abertura** (2,5 s) com a arte do SpeedGuard (velocímetro e rastro de luz) e os créditos do autor
- **Ícone próprio** com o velocímetro (inclui ícone adaptativo do Android 8+)
- **Mapa** (OpenStreetMap) com sua posição e os radares da região
- **Navegar** (botão ao lado de Opções): digite o destino e escolha **Google Maps** ou **Waze**; o app abre já navegando (campo vazio só abre o app). Se o monitoramento estiver parado, o SpeedGuard liga sozinho antes, e o painel flutuante (se ligado) avisa os radares por cima da navegação
- **Opções do mapa** (botão **Opções** no canto de baixo à esquerda), como no CamSam: liga e desliga cada camada, com bolinha colorida. O que fica desligado some do mapa e não gera aviso:
  - 🔴 Radares fixos (inclui os reportados) · 🟠 Radares de semáforo · 🟣 Radares móveis
  - 🟠 Filas · 🟠 Obras · 🟠 Perigos (acidente, obstáculo, avaria, pista escorregadia) · 🔵 Polícia
  - Mais: **O mapa segue você**
- **Avisos de trânsito reportados pelos motoristas**: no botão de reportar aparecem **Fila, Obras, Perigo e Polícia** acima das placas de velocidade; um toque já reporta para todos. Cada aviso **some sozinho depois de 6 horas** e é **apagado do Firebase automaticamente** pelo primeiro celular que baixar a região depois disso (as regras só permitem apagar aviso já vencido); se alguém reportar o mesmo aviso no mesmo lugar (até 150 m), ele não duplica e ganha mais 6 h. Os avisos usam os mesmos alertas de 500 a 100 m dos radares
- **Tutorial em vídeo** (Configurações → **Tutorial**): vídeo de 7 min, narrado, mostrando como configurar e usar o app. O vídeo vai dentro do app (`assets/tutorial.mp4`, ~11 MB) e funciona sem internet; tem play/pausa, voltar e avançar 10 s e barra para arrastar
- **Pessoas conectadas**: dois cards pequenos, um embaixo do outro, logo abaixo do círculo da velocidade (à esquerda), mostram quantas pessoas estão com o SpeedGuard conectado agora: 🌍 **no mundo** e com a bandeira do **país onde você está** (ex.: 🇫🇷 12 no país). Conta quem está com o app aberto ou monitorando; atualiza a cada minuto e quem fecha o app sai da contagem em até 4 minutos. Cada aparelho grava só o código do país e o horário na coleção `presence` do Firebase (sem dados pessoais). Os cards só aparecem depois que as regras da coleção `presence` (abaixo) forem publicadas no console
- **Ícone no mapa** (Configurações → Ícone no mapa): **Seta**, **Carro**, **Caminhão** (cavalo com carreta) ou **Moto**, desenhados vistos de cima e girando conforme a direção
- **Card de status limpo**: enquanto os radares da região são baixados aparece só um símbolo girando ao lado da velocidade; ao terminar, o card "N radares carregados" aparece por 4 segundos e some. Com radar à frente o card volta mostrando a distância
- **Cores do app** em Configurações: **Roxo** (padrão), **Azul**, **Verde**, **Laranja**, **Vermelho** ou **Grafite**. Troca na hora o app inteiro (fundos, bordas, botões, velocímetro e o painel flutuante); as cores de alerta (vermelho e laranja dos radares) continuam as mesmas para não confundir
- **Aparência** em Configurações: **Auto** (segue o modo claro/escuro do celular), **Claro** ou **Escuro**. No modo escuro o mapa também fica escurecido para não ofuscar à noite. A tela de abertura e o painel flutuante continuam sempre escuros
- **Duas telas no app aberto**, como no CamSam: o botão ao lado de Configurações alterna entre o **Mapa** e a **Tela de alerta** (sem mapa). A tela de alerta mostra **5 faixas verdes** (setas para cima) com o caminho livre. Com radar à frente aparecem a placa do limite, a distância e o tipo do radar, e **a cada 100 m uma faixa fica vermelha, de baixo para cima** (500 m = 1 faixa … 100 m = as 5), junto com o aviso sonoro. Acima do limite aparece "REDUZA A VELOCIDADE". O app lembra a última tela escolhida
- **Base mundial de radares** baixada automaticamente do OpenStreetMap num raio de 50 km, atualizada a cada 24 h ou a cada 30 km rodados, e guardada para uso offline
- **Ver radares de outra região**: arraste o mapa para qualquer lugar do mundo e aproxime o zoom; 1 segundo depois de soltar, o app baixa os radares da área que está na tela (com uma margem em volta) e mostra o símbolo girando enquanto carrega. Esses radares são só para ver no mapa; os avisos continuam usando os radares em volta de você
- **Avisos a cada 100 m** do radar (500, 400, 300, 200 e 100 m), com vibração. Em Configurações → **Alertas sonoros** dá para escolher:
  - **Voz**: "Radar fixo a 500 metros. Limite 80.", depois "400 metros.", "300 metros.", "200 metros." e "100 metros. Limite 80."
  - **Bipe**: um bipe a cada 100 m, cada vez mais agudo (bipe duplo a 100 m), e uma sequência rápida se estiver acima do limite. Os bipes só abaixam a música/navegação por um instante
  - Se o radar aparecer já perto (ex.: a 250 m), só o aviso daquela distância é dado
  - **Modo discreto** (voz): fala só a distância ("500 metros")
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
  - **Fechar o painel**: toque no **✕** no canto de cima, ou segure o dedo parado sobre ele por meio segundo (vibra e fecha na hora, mesmo com o app em segundo plano). O monitoramento e a voz continuam; o painel volta da próxima vez que você sair do SpeedGuard

  Conteúdo do painel:
  - em cima: velocidade atual (vermelha acima do limite)
  - no meio: as mesmas **5 faixas verdes** da tela de alerta. De 500 m até o radar, **a cada 100 m uma faixa fica vermelha, de baixo para cima**, com a placa do limite e a distância (laranja, ou vermelho se estiver acima do limite); o aviso de voz ou bipe toca junto. Depois de passar o radar, as faixas voltam a ficar verdes. Também mostra a pergunta "Radar ainda aí?" com ✓/✗
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
| `lib/alert_engine.dart` | Decide quando e o que avisar |
| `lib/radar_service.dart` | Baixa radares (Overpass/OSM), cache, radares do usuário, detecção do país |
| `lib/community_service.dart` | Radares compartilhados entre usuários (Firestore via REST) |
| `lib/presence_service.dart` | Contagem de pessoas conectadas no mundo e no país (Firestore via REST) |
| `lib/tutorial_page.dart`, `assets/tutorial.mp4` | Tela do vídeo tutorial (Configurações → Tutorial) |
| `lib/firebase_config.dart` | ID do projeto e chave do Firebase |
| `lib/layers.dart` | Camadas do painel Opções (radares e avisos de trânsito) |
| `lib/vehicle_icon.dart` | Ícones da sua posição (seta, carro, caminhão, moto) |
| `lib/alert_view.dart` | Tela de alerta (5 faixas, placa e distância) |
| `lib/overlay.dart` | Painel flutuante sobre outros apps |
| `assets/sounds/` | Bipes dos avisos (500 a 100 m e acima do limite) |
| `lib/theme.dart` | Paleta de cores e tema do app |
| `lib/splash_screen.dart` | Tela de abertura com créditos (2,5 s) |
| `assets/splash.png`, `assets/icon.png` | Arte da abertura e do ícone (criação original) |
| `android/app/src/main/res/` | Ícones do app e fundo escuro de abertura |
| `lib/speed_picker.dart` | Janela de reportar radar com as velocidades prontas |
| `lib/country_rules.dart` | Regras por país |
| `lib/models.dart` | Modelo do radar |
| `android/app/src/main/AndroidManifest.xml` | Permissões (GPS, segundo plano, internet) |

## Como gerar o APK

O GitHub Actions compila sozinho a cada push na `main` (ou manualmente em **Actions → Build APK → Run workflow**). O APK fica em **Actions → última execução → Artifacts → SpeedGuard-apk**.

O workflow roda `flutter create` para gerar os arquivos Android que não estão no repositório, sem sobrescrever o manifesto.

## Radares compartilhados (Firebase)

**Já ativado** desde a versão 1.6.3. Os radares reportados ficam no Cloud Firestore do projeto Firebase **SpeedGuard001** (ID `speedguard001`, plano Spark gratuito), na coleção `radars`; as pessoas conectadas ficam na coleção `presence`. O app acessa pela API REST, com o ID do projeto e a chave de API da Web em `lib/firebase_config.dart`. A chave não é secreta (vai dentro do app); quem protege os dados são as regras abaixo, já publicadas no console:

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
        || (resource.data.type in ['fila', 'obra', 'perigo', 'policia']
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
