import 'package:flutter/material.dart';

import 'theme.dart';

/// Ajuda offline (Configurações → Ajuda): perguntas e respostas prontas,
/// com busca. Fica dentro do app, então funciona sem internet e sem limite.
class HelpPage extends StatefulWidget {
  const HelpPage({super.key});

  @override
  State<HelpPage> createState() => _HelpPageState();
}

class _Faq {
  final String q;
  final String a;
  const _Faq(this.q, this.a);
}

class _Group {
  final String title;
  final IconData icon;
  final List<_Faq> items;
  const _Group(this.title, this.icon, this.items);
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
    _Faq('Como gravo e reaproveito uma rota?',
        'No botão Rotas, toque em Gravar rota agora e, no fim, em Parar gravação para dar um nome. Depois dá para ver no mapa, seguir no Google Maps, compartilhar o arquivo GPX ou importar um GPX recebido.'),
    _Faq('Como vejo os colegas no mapa?',
        'Com Caminhão escolhido: Configurações → Localização em grupo. Ponha foto, apelido e o mesmo código de grupo dos colegas e ligue Compartilhar minha localização. Um toque no colega abre o Google Maps até ele.'),
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
    const from = 'áàâãäéèêëíìîïóòôõöúùûüç';
    const to = 'aaaaaeeeeiiiiooooouuuuc';
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
      appBar: AppBar(title: const Text('Ajuda')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _search,
              onChanged: (v) => setState(() => _q = v.trim()),
              decoration: InputDecoration(
                hintText: 'Procurar (ex.: limitador, park, bipe)',
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
                        'Nada encontrado. Tente outra palavra ou veja o vídeo em Configurações → Tutorial.',
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
