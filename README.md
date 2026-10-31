# SpeedGuard

App Android de alerta de radares para o mundo todo, feito em Flutter. Avisa por voz e vibração antes de radares fixos, de semáforo e reportados pelo usuário, e se adapta automaticamente à lei de cada país.

Autor: Luiz Alberto Cardoso

## Funções (versão 1.6)

- **Visual neon** com as cores da tela de abertura: fundo roxo escuro, velocímetro com borda violeta brilhante, botão INICIAR em degradê vermelho→rosa, cartões e botões roxos; o painel flutuante e a janela de reportar seguem a mesma paleta
- **Tela de abertura** (2,5 s) com a arte do SpeedGuard (velocímetro e rastro de luz) e os créditos do autor
- **Ícone próprio** com o velocímetro (inclui ícone adaptativo do Android 8+)
- **Mapa** (OpenStreetMap) com sua posição e os radares da região
- **Base mundial de radares** baixada automaticamente do OpenStreetMap num raio de 50 km, atualizada a cada 24 h ou a cada 30 km rodados, e guardada para uso offline
- **Alerta por voz e vibração** cerca de 25 segundos antes do radar (entre 300 m e 1,2 km), dizendo o tipo, a distância e o limite
- **Aviso "Reduza a velocidade"** quando você passa do limite perto do radar
- Só avisa radares **à frente** e, quando o sentido do radar é conhecido, só para quem vai naquele sentido
- **Velocímetro** grande, que fica vermelho acima do limite
- **Funciona com a tela apagada ou em segundo plano** (notificação "SpeedGuard ativo")
- **Reportar radar** (móvel ou fixo) na sua posição atual: abre uma janela com as placas de limite prontas (30, 40, 50, 60, 70, 80, 90, 100, 110, 120, 130 ou "?") e **um toque já salva**, sem digitar. Com o Firebase configurado, **todos os usuários veem**. Sem Firebase, fica só no aparelho
- **Confirmação de radares móveis**: eles não somem sozinhos. Depois de 48 h, quem passar a menos de 150 m recebe a pergunta "O radar móvel ainda está aqui?" na tela e na bolha flutuante. **Sim** mantém por mais 48 h; **Não** apaga o radar
- **Painel flutuante** por cima do Google Maps / Waze, no estilo do CamSam (ativar em Configurações; pede a permissão "Sobrepor a outros apps"). Aparece no canto superior esquerdo, pode ser arrastado e não bloqueia o resto do mapa. Em **Configurações**, logo abaixo de "Bolha flutuante", dá para escolher:
  - **Tamanho**: Pequeno, Médio (igual ao CamSam, 64 × 250 dp) ou Grande
  - **Formato**: Vertical (retrato) ou Horizontal (paisagem, 240 × 72 dp no Médio), com uma miniatura mostrando como fica
  - O tamanho é convertido para pixels e conferido pelo próprio painel ao abrir, para ficar certo em qualquer tela

  Conteúdo do painel:
  - em cima: velocidade atual (vermelha acima do limite)
  - no meio: setas verdes com caminho livre; perto de radar, a placa do limite e a distância (laranja, ou vermelho se estiver acima do limite); a pergunta "Radar ainda aí?" com ✓/✗
  - embaixo: botão **+** que abre a janela de reportar radar com as velocidades prontas, sem sair do Maps. Fecha sozinha em 20 s se nada for escolhido; o app confirma por voz "Radar reportado"
  - como usar: ative **Configurações → Bolha flutuante**, permita "Sobrepor a outros apps", toque em **INICIAR** e abra o Maps/Waze. O painel abre no instante em que você sai do SpeedGuard (exigência do Android 15+) e some quando você volta para ele. Se faltar a permissão, o app avisa ao voltar
- **Modo discreto**: só vibra e diz "Radar", sem detalhes
- Cores no mapa: vermelho = fixo, amarelo = semáforo, violeta = reportado por usuários, laranja = seu reporte local; sua posição é a seta rosa
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
| `lib/firebase_config.dart` | ID do projeto e chave do Firebase |
| `lib/overlay.dart` | Painel flutuante sobre outros apps |
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

## Ativar radares compartilhados (Firebase)

1. Em [console.firebase.google.com](https://console.firebase.google.com), crie um projeto (ex.: `speedguard`)
2. **Build → Firestore Database → Criar banco de dados** (modo produção, local mais próximo)
3. Na aba **Regras**, cole e publique:

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
      // confirmação "não está mais": apaga só radares móveis
      allow delete: if resource.data.type == 'movel';
    }
  }
}
```

4. Em **Configurações do projeto → Geral**, copie o **ID do projeto** e a **Chave de API da Web** (se não aparecer, adicione um app Web `</>` primeiro)
5. Coloque os dois em `lib/firebase_config.dart` e faça push

## Próximas versões

- Exigir mais de uma resposta "Não" antes de apagar, para evitar abuso
- Idiomas além do português

## Créditos

Dados de radares e mapas: © colaboradores do OpenStreetMap (ODbL).
