/// Configuração do Firebase (Firestore) para compartilhar radares
/// entre usuários (projeto Firebase "SpeedGuard001").
/// Se os dois campos ficarem vazios, os reportes ficam só no aparelho.
const String firebaseProjectId = 'speedguard001';
const String firebaseApiKey = 'AIzaSyCOr4JdcCHIL1I7XEZgmw-QSQE7yVimfQg';

bool get communityEnabled =>
    firebaseProjectId.isNotEmpty && firebaseApiKey.isNotEmpty;
