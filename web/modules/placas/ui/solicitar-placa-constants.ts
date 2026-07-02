// Constantes e tipos do wizard público de solicitação de placa.

export const TOTAL_STEPS = 6;
export const STEP_NAMES = ['', 'Seus dados', 'Interesse', 'Seu nível', 'Comprovação', 'Declaração', 'Endereço'];
export const UFS = ['AC', 'AL', 'AP', 'AM', 'BA', 'CE', 'DF', 'ES', 'GO', 'MA', 'MT', 'MS', 'MG', 'PA', 'PB', 'PR', 'PE', 'PI', 'RJ', 'RN', 'RS', 'RO', 'RR', 'SC', 'SP', 'SE', 'TO'];

/** Turmas selecionáveis (T1..T38) — conjunto fechado para evitar divergência de preenchimento. */
export const TURMAS = Array.from({ length: 38 }, (_, i) => `T${i + 1}`);

/** Sugestões de profissão do autocomplete (dedupe preserva a ordem canônica do legado). */
export const PROFISSOES = Array.from(
  new Set([
    'Empresário', 'Empresária', 'Empreendedor', 'Empreendedora', 'Autônomo', 'Autônoma',
    'Profissional liberal', 'Prestador de serviços', 'Prestadora de serviços', 'Consultor', 'Consultora',
    'Mentor', 'Mentora', 'Coach', 'Palestrante', 'Perito', 'Perita', 'Corretor', 'Corretora',
    'Corretor de imóveis', 'Corretora de imóveis', 'Representante comercial', 'Executivo comercial',
    'Executiva comercial', 'Vendedor', 'Vendedora', 'Closer', 'SDR', 'Consultor de vendas',
    'Consultora de vendas', 'Atendente', 'Recepcionista', 'Assistente administrativo', 'Auxiliar administrativo',
    'Secretária', 'Secretário', 'Administrador', 'Administradora', 'Analista administrativo', 'Analista de operações',
    'Coordenador', 'Coordenadora', 'Supervisor', 'Supervisora', 'Gerente', 'Gerente comercial',
    'Gerente administrativo', 'Gerente financeiro', 'Gerente de operações', 'Diretor', 'Diretora',
    'Diretor executivo', 'CEO', 'CFO', 'COO', 'Controller', 'Analista financeiro', 'Consultor financeiro',
    'Consultora financeira', 'Planejador financeiro', 'Planejadora financeira', 'Assessor de investimentos',
    'Assessora de investimentos', 'Investidor', 'Investidora', 'Economista', 'Contador', 'Contadora',
    'Auditor', 'Auditora', 'Analista contábil', 'Assistente contábil', 'Advogado', 'Advogada', 'Jurista',
    'Procurador', 'Procuradora', 'Defensor público', 'Defensora pública', 'Delegado', 'Delegada', 'Escrevente',
    'Oficial de cartório', 'Tabelião', 'Tabeliã', 'Médico', 'Médica', 'Cirurgião', 'Cirurgiã', 'Dentista',
    'Odontólogo', 'Odontóloga', 'Enfermeiro', 'Enfermeira', 'Fisioterapeuta', 'Nutricionista', 'Psicólogo',
    'Psicóloga', 'Psicanalista', 'Terapeuta', 'Terapeuta ocupacional', 'Fonoaudiólogo', 'Fonoaudióloga',
    'Farmacêutico', 'Farmacêutica', 'Biomédico', 'Biomédica', 'Veterinário', 'Veterinária', 'Educador físico',
    'Educadora física', 'Esteticista', 'Biomédica esteta', 'Cosmetóloga', 'Massoterapeuta', 'Podólogo', 'Podóloga',
    'Manicure', 'Cabeleireiro', 'Cabeleireira', 'Barbeiro', 'Maquiador', 'Maquiadora', 'Professor', 'Professora',
    'Pedagogo', 'Pedagoga', 'Coordenador pedagógico', 'Coordenadora pedagógica', 'Diretor escolar', 'Diretora escolar',
    'Tutor', 'Tutora', 'Instrutor', 'Instrutora', 'Treinador', 'Treinadora', 'Analista de RH', 'Psicopedagogo',
    'Psicopedagoga', 'Programador', 'Programadora', 'Desenvolvedor', 'Desenvolvedora', 'Engenheiro de software',
    'Engenheira de software', 'Analista de sistemas', 'Analista de dados', 'Cientista de dados',
    'Arquiteto de software', 'Arquiteta de software', 'Especialista em segurança da informação', 'Profissional de TI',
    'Analista de suporte', 'DevOps', 'Product manager', 'Product owner', 'UX designer', 'UI designer', 'Designer',
    'Designer gráfico', 'Designer de interiores', 'Social media', 'Copywriter', 'Redator', 'Redatora', 'Jornalista',
    'Relações públicas', 'Publicitário', 'Publicitária', 'Especialista em marketing', 'Analista de marketing',
    'Gestor de tráfego', 'Gestora de tráfego', 'Especialista em SEO', 'Videomaker', 'Editor de vídeo',
    'Editora de vídeo', 'Fotógrafo', 'Fotógrafa', 'Engenheiro', 'Engenheira', 'Engenheiro civil', 'Engenheira civil',
    'Engenheiro mecânico', 'Engenheira mecânica', 'Engenheiro eletricista', 'Engenheira eletricista',
    'Engenheiro de produção', 'Engenheira de produção', 'Engenheiro agrônomo', 'Engenheira agrônoma', 'Arquiteto',
    'Arquiteta', 'Urbanista', 'Técnico em edificações', 'Mestre de obras', 'Construtor', 'Construtora',
    'Empreiteiro', 'Empreiteira', 'Corretor de obras', 'Eletricista', 'Encanador', 'Pintor', 'Serralheiro',
    'Marceneiro', 'Carpinteiro', 'Técnico industrial', 'Operador industrial', 'Supervisor industrial',
    'Gerente industrial', 'Comprador', 'Compradora', 'Analista de suprimentos', 'Analista de compras',
    'Analista de qualidade', 'Coordenador de produção', 'Coordenadora de produção', 'Produtor rural', 'Produtora rural',
    'Pecuarista', 'Agricultor', 'Agricultora', 'Veterinário do agronegócio', 'Consultor do agronegócio',
    'Consultora do agronegócio', 'Técnico agrícola', 'Zootecnista', 'Logístico', 'Logística', 'Analista de logística',
    'Coordenador logístico', 'Coordenadora logística', 'Motorista', 'Transportador', 'Transportadora', 'Despachante',
    'Comprador logístico', 'Gestor', 'Gestora', 'Gestor comercial', 'Gestora comercial', 'Gestor financeiro',
    'Gestora financeira', 'Gestor de projetos', 'Gestora de projetos', 'Gestor hospitalar', 'Gestora hospitalar',
    'Consultor empresarial', 'Consultora empresarial', 'Consultor jurídico', 'Consultora jurídica',
    'Consultor tributário', 'Consultora tributária', 'Consultor de RH', 'Consultora de RH', 'Consultor de tecnologia',
    'Consultora de tecnologia', 'Consultor de gestão', 'Consultora de gestão', 'Consultor de negócios',
    'Consultora de negócios', 'Mecânico', 'Mecânica', 'Técnico', 'Técnica', 'Analista', 'Especialista',
    'Especialista comercial', 'Especialista financeiro', 'Especialista tributário', 'Especialista em atendimento',
    'Assistente comercial', 'Auxiliar de escritório', 'Operador de caixa', 'Empresário do comércio',
    'Empresária do comércio', 'Industrial', 'Comerciante', 'Comerciante varejista', 'Distribuidor', 'Distribuidora',
  ]),
);

export const INTERESSES = [
  { v: 'pessoal', l: 'Apenas fazer a minha Holding e/ou da minha família', sub: 'Interesse exclusivamente pessoal, sem intenção de oferecer o serviço a terceiros.' },
  { v: 'familia_e_possivel', l: 'Minha Holding + possibilidade de oferecer a outros clientes', sub: 'Interesse pessoal com abertura para eventualmente prestar o serviço a outros.' },
  { v: 'profissional', l: 'Trabalhar com Holding Familiar', sub: 'Objetivo principal é prestar o serviço de Holding como profissão.' },
];

export const ESPACOS = [
  { v: 'holding_masters', l: 'Holding Masters' },
  { v: 'aurum', l: 'Mentoria Aurum' },
  { v: 'coach_platina', l: 'Coach Platina' },
  { v: 'mastermind', l: 'Mastermind Diamante' },
];

export const NIVEIS = [
  { v: 'iniciante', ic: 'sprout', nm: 'Iniciante', fx: 'Ainda não comecei' },
  { v: 'em_formacao', ic: 'biblioteca', nm: 'Em Formação', fx: 'Estudando o curso' },
  { v: 'pessoal', ic: 'user', nm: 'Pessoal', fx: 'Só minha holding' },
  { v: 'profissional', ic: 'briefcase', nm: 'Profissional', fx: 'Oferecendo a clientes' },
  { v: 'ouro', ic: 'medal', nm: 'Ouro', fx: 'Primeiros R$ 50k faturado' },
  { v: 'platina', ic: 'coins', nm: 'Platina', fx: 'R$ 500k em 12 meses' },
  { v: 'diamante', ic: 'gem', nm: 'Diamante', fx: 'R$ 1M em 12 meses' },
  { v: 'diamante_vermelho', ic: 'gem', nm: 'Diamante Vermelho', fx: 'R$ 5M em 12 meses' },
];

export type Form = Record<string, string>;
export type View = 'loading' | 'form' | 'success' | 'cadastro' | 'tracking' | 'error';

/** Config personalizável (níveis/faixas + textos) resolvida no server e injetada no client. */
export interface FormConfig {
  niveis: { v: string; ic: string; nm: string; fx: string }[];
  textos: { upload_info: string; cadastro_info: string; espacos: { v: string; l: string }[] };
}
