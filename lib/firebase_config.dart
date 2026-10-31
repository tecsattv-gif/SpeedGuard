/// Configuração do Firebase (Firestore) para compartilhar radares
/// entre usuários. Enquanto estiver vazio, os reportes ficam só
/// no aparelho. Veja o passo a passo no README.
const String firebaseProjectId = '';
const String firebaseApiKey = '';

bool get communityEnabled =>
    firebaseProjectId.isNotEmpty && firebaseApiKey.isNotEmpty;
