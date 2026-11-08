import 'package:flutter/material.dart';

import 'i18n.dart';
import 'theme.dart';

/// Ajuda offline (Configurações → Ajuda): perguntas e respostas prontas,
/// com busca. Fica dentro do app, então funciona sem internet e sem limite.
class HelpPage extends StatefulWidget {
  const HelpPage({super.key});

  @override
  State<HelpPage> createState() => _HelpPageState();
}

class _Faq {
  final String _q;
  final String _a;
  String get q => tr(_q);
  String get a => tr(_a);
  const _Faq(this._q, this._a);
}

class _Group {
  final String _title;
  final IconData icon;
  final List<_Faq> items;
  String get title => tr(_title);
  const _Group(this._title, this.icon, this.items);
}

const _groups = <_Group>[
  _Group('Começar', Icons.play_arrow, [
    _Faq('Como começo a usar o SpeedGuard?',
        'Abra o app, aceite a permissão de localização ("Permitir o tempo todo", para avisar com a tela apagada) e toque em INICIAR. A partir daí o app avisa os radares à frente por voz. Para desligar, toque em PARAR.'),
    _Faq('O app funciona com a tela apagada ou com outro app aberto?',
        'Sim. Enquanto estiver monitorando aparece a notificação "SpeedGuard ativo" e os avisos continuam com a tela apagada ou com o Google Maps/Waze na frente. Se o celular cortar o app, tire o SpeedGuard da economia de bateria nas configurações do Android.'),
    _Faq('Qual veículo devo escolher?',
        'Em Configurações → Ícone no mapa escolha Seta, Carro, Caminhão ou Moto. Com Caminhão o app usa o limite de caminhão da via, o limitador e mostra os parks e a Localização em grupo.'),
    _Faq('Tem um vídeo explicando?',
        'Sim: Configurações → Tutorial. É um vídeo narrado de 7 minutos que já vem dentro do app e funciona sem internet.'),
    _Faq('O celular fecha o app sozinho (Xiaomi). O que faço?',
        'No Android vá em Configurações → Apps → SpeedGuard → Economia de bateria e escolha Sem restrições. No Xiaomi ligue também o Início automático. Assim o app continua avisando com a tela apagada e o aviso do grupo funciona com o app fechado.'),
    _Faq('O que são os números no alto da tela?',
        'São os cards de pessoas conectadas: 🌍 mostra quantas pessoas estão com o SpeedGuard aberto no mundo e o outro, com a bandeira, no país onde você está agora. A conta atualiza a cada minuto.'),
  ]),
  _Group('Avisos de radar', Icons.campaign, [
    _Faq('Em que distâncias o app avisa?',
        'A 1000, 800, 500, 400, 300 e 100 metros. O primeiro aviso já fala o limite do radar, por exemplo: "Radar fixo a 1000 metros. Limite 80."'),
    _Faq('Como troco voz por bipe ou deixo mais baixo?',
        'Em Configurações → Alertas sonoros escolha Voz ou Bipe (ou o Modo discreto, que fala só a distância). Logo abaixo fica a barra de Volume dos avisos, de 10% a 100%.'),
    _Faq('Por que o app não avisou um radar de uma rua do lado?',
        'De propósito: com "Só radares da minha via" ligado (Configurações), o app só avisa os radares da rodovia e do sentido em que você está. Radares de ruas paralelas, marginais, alças ou da pista contrária são ignorados.'),
    _Faq('Passei por um radar e o app não avisou. O que faço?',
        'Confira em Opções (canto de baixo à esquerda) se a camada daquele tipo de radar está ligada. Depois toque em Configurações → Atualizar radares agora. Se o radar não estiver no mapa, reporte-o com o botão de reportar para que todos passem a ser avisados.'),
    _Faq('O que é o radar de velocidade média?',
        'É um trecho com câmera no início e no fim. Ao passar pelo início o app fala "Controle de velocidade média iniciado" e mostra embaixo do velocímetro a sua média no trecho (vermelha acima do limite). No fim fala a média final.'),
    _Faq('O app avisa radar da pista contrária. Como paro?',
        'Ande um pouco (o app precisa saber o seu sentido), toque no radar no mapa e escolha "Este radar é da outra pista". No seu sentido ele não avisa mais; na pista dele continua avisando para quem passa lá.'),
    _Faq('O app avisa radar de semáforo?',
        'Sim, os semáforos com câmera que estão no mapa. Confira em Opções (canto de baixo à esquerda) se a camada "Radares de semáforo" está ligada. Se faltar algum, reporte com o botão de reportar.'),
    _Faq('O app avisa pedágio?',
        'Sim. A 1000 m de um pedágio à frente ele fala "Pedágio em 1 quilômetro" e mostra um aviso amarelo por 15 segundos, uma vez por praça. Liga e desliga em Configurações → Aviso de pedágio. Pedágio eletrônico sem cabine pode não ser avisado.'),
    _Faq('Por que não tenho avisos na Suíça?',
        'Na Suíça avisar radares é proibido por lei, então o app desliga os alertas lá. Na Alemanha funciona, com o aviso de que só passageiros podem usar.'),
  ]),
  _Group('Reportar e confirmar', Icons.add_location_alt, [
    _Faq('Como reporto um radar?',
        'Toque no botão de reportar radar e escolha a placa com a velocidade (ou "?"). Um toque já salva na sua posição atual e todos os usuários passam a ver.'),
    _Faq('Como reporto fila, acidente, obras, perigo ou polícia?',
        'Na mesma janela de reportar, acima das placas, ficam Fila, Acidente, Obras, Perigo e Polícia. Funciona também pela janela do painel flutuante. Esses avisos somem sozinhos depois de 6 horas.'),
    _Faq('O app me perguntou se o radar móvel ainda está lá. Por quê?',
        'Radares móveis não somem sozinhos. Depois de 48 h, quem passa perto recebe a pergunta: Sim mantém o radar por mais 48 h e Não apaga. Se ninguém responder, ele continua ativo.'),
    _Faq('Um radar do mapa não existe mais. Como tiro?',
        'Toque no radar no mapa → Este radar não existe mais. Ele some na hora para você; para os outros some quando 2 pessoas avisarem. Para ver de novo os que você escondeu: Configurações → Radares escondidos → Mostrar de novo.'),
    _Faq('Como apago um radar que só eu salvei?',
        'Quando você reporta sem internet, o radar fica salvo só no seu celular. Toque nele no mapa → Excluir este radar.'),
  ]),
  _Group('Velocidade e limitador', Icons.speed, [
    _Faq('Como funciona o aviso de velocidade excedida?',
        'Acima do limite o velocímetro fica vermelho e começa a contagem de 30 s, sem falar nada. Aos 20 s fala "Atenção." e aos 30 s "Velocidade excedida. Tempo excedido." Voltando ao limite, a contagem zera.'),
    _Faq('Como mudo o valor do limitador do caminhão?',
        'Com Caminhão escolhido, vá em Configurações → Limitador do caminhão e escolha o valor (de 80 a 95 km/h, ou 100, 110, 120 e 130).'),
    _Faq('Quero só o aviso na tela, sem som. Dá?',
        'Sim: em Configurações → Som do aviso de velocidade escolha Mudo. O velocímetro vermelho, a contagem e "VELOCIDADE EXCEDIDA" continuam aparecendo.'),
    _Faq('De onde vem a placa de limite em cima do velocímetro?',
        'Do OpenStreetMap. Com caminhão aparece o limite para caminhão (no máximo o do limitador). Se a via não tiver limite no mapa, a placa não aparece.'),
    _Faq('Parado, o velocímetro mostra 0. Está certo?',
        'Sim. Parado, o GPS "anda" sozinho alguns metros, então abaixo de 4 km/h o app mostra 0 e não conta como excesso.'),
    _Faq('Como testo se a contagem aparece por cima de outros apps?',
        'Com a Bolha flutuante desligada, toque em Configurações → Testar pop-up da contagem, minimize o SpeedGuard e abra outro app (ex.: YouTube). O círculo vermelho com a contagem tem de aparecer por cima. Se não aparecer, libere a permissão "Sobrepor a outros apps".'),
  ]),
  _Group('Painel flutuante e navegação', Icons.picture_in_picture_alt, [
    _Faq('Como ligo o painel flutuante por cima do Google Maps?',
        'Em Configurações ligue Bolha flutuante e aceite a permissão "Sobrepor a outros apps". Logo abaixo escolha o Tamanho e o Formato (vertical ou horizontal). O painel pode ser arrastado e some ao tocar em PARAR.'),
    _Faq('Como navego até um destino?',
        'Toque em Navegar, digite o destino e escolha Google Maps ou Waze. Se o monitoramento estiver parado, o SpeedGuard liga sozinho antes.'),
    _Faq('Como alterno entre o mapa e a tela de alerta?',
        'Use o botão ao lado de Configurações. A tela de alerta mostra 6 faixas verdes que vão ficando vermelhas a cada aviso, de 1000 m até 100 m.'),
    _Faq('Como escolho o que aparece no mapa?',
        'Toque em Opções (canto de baixo à esquerda) e ligue ou desligue cada camada. O que fica desligado some do mapa e não gera aviso. Ali também ficam "O mapa segue você" e "Mapa gira com o veículo".'),
  ]),
  _Group('Parks e rotas', Icons.local_parking, [
    _Faq('Como vejo os parks à frente?',
        'O card azul acima de Opções/Navegar mostra o próximo park no seu sentido. O botão P, ao lado de Navegar, abre os 3 próximos; um toque abre a rota no Google Maps. O app avisa por voz a 2 km.'),
    _Faq('Como vejo todos os parks da minha rota?',
        'Digite o destino em Navegar. O app calcula a rota e o botão P passa a mostrar os 30 próximos parks da rota, com a distância pela estrada. Para apagar a rota: Encerrar rota.'),
    _Faq('Aparecem áreas sem vaga de caminhão. Como filtro?',
        'Ligue Configurações → Só parks de caminhão. Assim aparecem só estacionamentos e paradas com vagas de caminhão.'),
    _Faq('Como mando um park para um colega?',
        'Toque no botão de compartilhar ao lado do park (na janela do P ou no card). Vai por WhatsApp, SMS ou e-mail, com o link do Google Maps.'),
    _Faq('Como adiciono um park que não está no mapa?',
        'Só com Caminhão escolhido. Abra o botão P → Adicionar park aqui, leia o aviso e escolha Park privado (pago), Park free (grátis) ou Zona industrial. Marque Onde estou ou Marcar no mapa e dê um nome. O park aparece para todos os motoristas, então só adicione onde você mesmo parou e tem certeza de que o caminhão entra, manobra e sai.'),
    _Faq('Como mudo de lugar ou excluo um park que eu adicionei?',
        'Toque no park no mapa. Se foi você que adicionou neste celular, aparecem Mudar de lugar (toque ou arraste no mapa até o lugar certo e confirme) e Excluir park. Excluir tira o park para todos.'),
    _Faq('Como gravo e reaproveito uma rota?',
        'No botão Rotas, toque em Gravar rota agora e, no fim, em Parar gravação para dar um nome. Depois dá para ver no mapa, seguir no Google Maps, compartilhar o arquivo GPX ou importar um GPX recebido.'),
    _Faq('Dá para navegar pela rota gravada dentro do app?',
        'Sim: Rotas → escolha a rota → Navegar por esta rota (no app). Um painel verde mostra a próxima curva, quanto falta e a hora de chegada, e a voz avisa as curvas. Se sair mais de 80 m da linha, o painel fica vermelho "Fora da rota". Não tem nome de rua nem número de saída de rotunda.'),
    _Faq('Como faço o caminho de volta de uma rota gravada?',
        'Na rota, toque em Navegar no sentido contrário (volta) ou Google Maps no sentido contrário (volta). Se você já está no fim da rota, o app abre sozinho o caminho de volta.'),
    _Faq('Parei a navegação no meio. Como continuo?',
        'A navegação fica guardada até chegar ao destino, mesmo se o app fechar. Ao abrir o app aparece "Continuar a rota …?" (ou em Rotas → Continuar rota). Ela continua do ponto onde você está.'),
    _Faq('Como acrescento mais um trecho numa rota gravada?',
        'Rotas → escolha a rota → Continuar gravando esta rota. O caminho novo entra no fim da mesma rota, com os km e o tempo somados.'),
    _Faq('Como vejo os colegas no mapa?',
        'Com Caminhão escolhido: Configurações → Localização em grupo. Ponha foto, apelido e o mesmo código de grupo dos colegas e ligue Compartilhar minha localização. Um toque no colega abre o Google Maps até ele.'),
    _Faq('O que é o botão 👥 Grupo?',
        'Aparece no mapa (à direita, em cima) quando o grupo está configurado. Abre a lista dos colegas com foto, apelido, país, velocidade e distância. Tocar no colega leva o mapa até ele; o botão ➜ abre o Google Maps.'),
    _Faq('Como sei que um colega mudou de país?',
        'O app manda a notificação "Grupo SpeedGuard" quando um colega do grupo entra noutro país. Com o app fechado o aviso pode demorar de 15 a 30 minutos; no Xiaomi a bateria do SpeedGuard precisa estar em Sem restrições.'),
  ]),
  _Group('Aparência', Icons.palette, [
    _Faq('Como mudo as cores do app?',
        'Em Configurações → Cores do app escolha uma das cores (Roxo, Azul, Verde claro, Verde, Verde escuro, Laranja, Vermelho, Grafite ou Preto). A bolha flutuante muda junto.'),
    _Faq('Como deixo o app claro ou escuro?',
        'Em Configurações → Aparência escolha Claro, Escuro ou Auto (segue o modo do celular).'),
    _Faq('Como troco o veículo que aparece no mapa?',
        'Em Configurações → Ícone no mapa escolha Seta, Carro, Caminhão ou Moto. A foto do veículo aparece embaixo da placa de limite (com Seta, só a placa).'),
  ]),
  _Group('Atualização e problemas', Icons.build, [
    _Faq('Como atualizo o app?',
        'Quando sai versão nova, o app pergunta ao abrir: toque em Atualizar e confirme no instalador do Android. Na primeira vez o Android pede para liberar "Instalar apps desconhecidos". Também dá para verificar em Configurações → Procurar atualização do app.'),
    _Faq('O app funciona sem internet?',
        'Os avisos de radar e os parks funcionam sem internet com a base que já está guardada no celular. A internet é necessária para baixar regiões novas, reportar e ver os avisos dos outros motoristas.'),
    _Faq('Os radares não carregam. O que faço?',
        'Confira a internet e toque em Configurações → Atualizar radares agora. Se continuar, veja Configurações → Diagnóstico (último erro) e mande o texto para o suporte.'),
    _Faq('Como vejo radares de outra região?',
        'Arraste o mapa até o lugar e aproxime o zoom. Um segundo depois o app baixa os radares da área da tela. Esses são só para ver; os avisos usam os radares em volta de você.'),
  ]),
];

class _HelpPageState extends State<HelpPage> {
  final _search = TextEditingController();
  String _q = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  static String _norm(String s) {
    const from = 'áàâãäéèêëíìîïóòôõöúùûüçñ';
    const to = 'aaaaaeeeeiiiiooooouuuucn';
    final b = StringBuffer();
    for (final ch in s.toLowerCase().split('')) {
      final i = from.indexOf(ch);
      b.write(i >= 0 ? to[i] : ch);
    }
    return b.toString();
  }

  bool _match(_Faq f) {
    if (_q.isEmpty) return true;
    final text = _norm('${f.q} ${f.a}');
    return _norm(_q)
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .every(text.contains);
  }

  @override
  Widget build(BuildContext context) {
    final groups = [
      for (final g in _groups)
        if (g.items.any(_match))
          _Group(g.title, g.icon, g.items.where(_match).toList()),
    ];
    return Scaffold(
      backgroundColor: SG.page,
      appBar: AppBar(title: Text(tr('Ajuda'))),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _search,
              onChanged: (v) => setState(() => _q = v.trim()),
              decoration: InputDecoration(
                hintText: tr('Procurar (ex.: limitador, park, bipe)'),
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _q.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _search.clear();
                          setState(() => _q = '');
                        },
                      ),
                filled: true,
                fillColor: SG.card,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: SG.line),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: SG.line),
                ),
              ),
            ),
          ),
          Expanded(
            child: groups.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        tr('Nada encontrado. Tente outra palavra ou veja o vídeo em Configurações → Tutorial.'),
                        textAlign: TextAlign.center,
                        style: TextStyle(color: SG.textSoft),
                      ),
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                    children: [
                      for (final g in groups) ...[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(4, 14, 4, 6),
                          child: Row(children: [
                            Icon(g.icon, color: SG.accent, size: 20),
                            const SizedBox(width: 8),
                            Text(g.title,
                                style: TextStyle(
                                    color: SG.accent,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16)),
                          ]),
                        ),
                        for (final f in g.items)
                          Card(
                            color: SG.card,
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                              side: BorderSide(color: SG.line),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: Theme(
                              data: Theme.of(context)
                                  .copyWith(dividerColor: Colors.transparent),
                              child: ExpansionTile(
                                key: ValueKey('${f.q}|${_q.isNotEmpty}'),
                                initiallyExpanded: _q.isNotEmpty,
                                iconColor: SG.accent,
                                collapsedIconColor: SG.textSoft,
                                title: Text(f.q,
                                    style: TextStyle(
                                        color: SG.text,
                                        fontWeight: FontWeight.w600)),
                                childrenPadding:
                                    const EdgeInsets.fromLTRB(16, 0, 16, 14),
                                expandedAlignment: Alignment.centerLeft,
                                children: [
                                  Text(f.a,
                                      style: TextStyle(
                                          color: SG.text, height: 1.35)),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
