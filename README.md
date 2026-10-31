# SpeedGuard

App Android de alerta de radares para o mundo todo, feito em Flutter. Avisa por voz e vibração antes de radares fixos, de semáforo e reportados pelo usuário, e se adapta automaticamente à lei de cada país.

Autor: Luiz Alberto Cardoso

## Funções (versão 1.0)

- **Mapa** (OpenStreetMap) com sua posição e os radares da região
- **Base mundial de radares** baixada automaticamente do OpenStreetMap num raio de 50 km, atualizada a cada 24 h ou a cada 30 km rodados, e guardada para uso offline
- **Alerta por voz e vibração** cerca de 25 segundos antes do radar (entre 300 m e 1,2 km), dizendo o tipo, a distância e o limite
- **Aviso "Reduza a velocidade"** quando você passa do limite perto do radar
- Só avisa radares **à frente** e, quando o sentido do radar é conhecido, só para quem vai naquele sentido
- **Velocímetro** grande, que fica vermelho acima do limite
- **Funciona com a tela apagada ou em segundo plano** (notificação "SpeedGuard ativo")
- **Reportar radar**: salva um radar na sua posição atual, com limite opcional (fica só no aparelho por enquanto)
- **Regras por país**, detectado pelo GPS:

| País | Comportamento |
|---|---|
| França | Não mostra radares no mapa; avisa só "zona de perigo à frente" |
| Suíça | Alertas desligados (proibido por lei) |
| Alemanha | Funciona, com aviso de que só passageiros podem usar |
| Demais países | Modo completo |

> Antes de publicar na Play Store, revisar a legislação de cada país e completar a lista em `lib/country_rules.dart`.

## Estrutura

| Arquivo | O que faz |
|---|---|
| `lib/main.dart` | Telas, mapa, GPS e voz |
| `lib/alert_engine.dart` | Decide quando e o que avisar |
| `lib/radar_service.dart` | Baixa radares (Overpass/OSM), cache, radares do usuário, detecção do país |
| `lib/country_rules.dart` | Regras por país |
| `lib/models.dart` | Modelo do radar |
| `android/app/src/main/AndroidManifest.xml` | Permissões (GPS, segundo plano, internet) |

## Como gerar o APK

O GitHub Actions compila sozinho a cada push na `main` (ou manualmente em **Actions → Build APK → Run workflow**). O APK fica em **Actions → última execução → Artifacts → SpeedGuard-apk**.

O workflow roda `flutter create` para gerar os arquivos Android que não estão no repositório, sem sobrescrever o manifesto.

## Próximas versões

- Compartilhar radares móveis entre usuários (Firebase)
- Botão flutuante por cima do Google Maps / Waze
- Ícone próprio e idiomas além do português

## Créditos

Dados de radares e mapas: © colaboradores do OpenStreetMap (ODbL).
