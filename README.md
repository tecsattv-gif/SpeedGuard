# SpeedGuard

App Android de alerta de radares para o mundo todo, feito em Flutter. Avisa por voz e vibração antes de radares fixos, de semáforo e reportados pelo usuário, e se adapta automaticamente à lei de cada país.

Autor: Luiz Alberto Cardoso

## Funções (versão 1.2)

- **Mapa** (OpenStreetMap) com sua posição e os radares da região
- **Base mundial de radares** baixada automaticamente do OpenStreetMap num raio de 50 km, atualizada a cada 24 h ou a cada 30 km rodados, e guardada para uso offline
- **Alerta por voz e vibração** cerca de 25 segundos antes do radar (entre 300 m e 1,2 km), dizendo o tipo, a distância e o limite
- **Aviso "Reduza a velocidade"** quando você passa do limite perto do radar
- Só avisa radares **à frente** e, quando o sentido do radar é conhecido, só para quem vai naquele sentido
- **Velocímetro** grande, que fica vermelho acima do limite
- **Funciona com a tela apagada ou em segundo plano** (notificação "SpeedGuard ativo")
- **Reportar radar** (móvel ou fixo) na sua posição atual, com limite opcional. Com o Firebase configurado, **todos os usuários veem**. Sem Firebase, fica só no aparelho
- **Confirmação de radares móveis**: eles não somem sozinhos. Depois de 48 h, quem passar a menos de 150 m recebe a pergunta "O radar móvel ainda está aqui?" na tela e na bolha flutuante. **Sim** mantém por mais 48 h; **Não** apaga o radar
- **Bolha flutuante** por cima do Google Maps / Waze, com velocidade, distância e limite do próximo radar (ativar em Configurações; pede a permissão "Sobrepor a outros apps")
- **Modo discreto**: só vibra e diz "Radar", sem detalhes
- Cores no mapa: vermelho = fixo, amarelo = semáforo, roxo = reportado por usuários, laranja = seu reporte local
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
| `lib/overlay.dart` | Bolha flutuante |
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
- Ícone próprio e idiomas além do português

## Créditos

Dados de radares e mapas: © colaboradores do OpenStreetMap (ODbL).
