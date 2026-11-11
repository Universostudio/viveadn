import type { TextosLegales } from './tipos'

// Tradução para português do Brasil do texto maestro (es.ts). A lei aplicável é o RGPD europeu e a lei espanhola.
// Marcadores: {titular} {nif} {domicilio} {emailLegal} {emailSoporte} {registro}.
// Pendente de revisão por um advogado.
const ptBR: TextosLegales = {
  privacidad: {
    titulo: "Política de privacidade",
    resumen: "Quais dados a Vive ADN trata, para quê, com qual base legal, por quanto tempo e como exercer seus direitos.",
    secciones: [
      {
        id: 'quienes-somos',
        titulo: "1. Quem somos e qual é o nosso papel",
        parrafos: [
          "A Vive ADN é uma plataforma web para que as igrejas gerenciem seus membros, casas de oração, consolidação, formação, eventos e relatórios. É oferecida por {titular}, com domicílio em {domicilio} e NIF {nif}. Para qualquer questão de privacidade, você pode escrever para {emailLegal}.",
          "Temos dois papéis distintos, e convém diferenciá-los, porque deles depende a quem você deve se dirigir:",
        ],
        lista: [
          "Responsáveis pelo tratamento dos dados das pessoas que usam a plataforma: quem cria a conta de uma igreja, quem recebe um convite e quem entra em contato conosco.",
          "Subcontratantes no tratamento dos dados dos membros, frequentadores e visitantes que cada igreja registra. Nesses dados, a responsável pelo tratamento é a igreja, que decide para quê e como são usados. Nós os tratamos por conta dela e seguindo as suas instruções, conforme o contrato de subcontratação que faz parte dos Termos de uso.",
        ],
      },
      {
        id: 'si-eres-miembro',
        titulo: "2. Se você é membro ou visitante de uma igreja",
        parrafos: [
          "Seus dados foram registrados pela sua igreja, ou foram fornecidos por você ao se registrar em um evento por meio de um código QR. A responsável por esse tratamento é a igreja, não nós. Para saber o que ela faz com seus dados, com qual base legal e por quanto tempo, e para exercer seus direitos, dirija-se primeiro a ela.",
          "Se você não sabe a qual igreja corresponde o seu registro, ou a igreja não responde, escreva para {emailLegal} e a ajudaremos a atender o seu pedido.",
        ],
      },
      {
        id: 'datos-como-responsables',
        titulo: "3. Dados que tratamos como responsáveis pelo tratamento",
        parrafos: ["Estes são os dados que tratamos por nossa conta, para quê os usamos e em que nos baseamos:"],
        lista: [
          "Dados da conta (nome, sobrenomes, e-mail, igreja e função, e a senha, que é gerenciada pelo serviço de autenticação sem que possamos vê-la). Nós os usamos para criar a conta, identificar você e dar-lhe acesso. Base legal: execução do contrato, artigo 6.1.b do RGPD.",
          "Dados de segurança, como um hash irreversível do endereço IP e as tentativas de registro. Nós os usamos para conter abusos e proteger todas as igrejas. Base legal: interesse legítimo na segurança do serviço, artigo 6.1.f do RGPD.",
          "Comunicações que você nos envia, por exemplo uma consulta de suporte. Nós as usamos para atender você. Base legal: execução do contrato ou interesse legítimo em responder a você.",
          "Dados que devemos conservar para cumprir obrigações legais. Base legal: artigo 6.1.c do RGPD.",
        ],
        cierre: [
          "Conservamos os dados da conta enquanto a conta estiver ativa e, depois, pelo tempo exigido pelas obrigações legais ou pela defesa de possíveis reclamações. A Vive ADN não processa nem guarda pagamentos: as contribuições de uma igreja chegam diretamente aos sites que ela usa.",
        ],
      },
      {
        id: 'datos-como-encargados',
        titulo: "4. Dados que tratamos como subcontratantes de cada igreja",
        parrafos: [
          "Conforme o que cada igreja decidir registrar, a plataforma pode conter: nome, sobrenomes, e-mail, telefone, endereço, data de nascimento, etiquetas e notas; frequência a casas de oração e eventos; acompanhamento de consolidação; progresso de formação e certificados; o estado de consentimento de cada pessoa para receber mensagens por e-mail, WhatsApp ou SMS, com o seu histórico; e as mensagens preparadas a partir da plataforma.",
          "Por sua natureza, o simples fato de pertencer a uma igreja pode revelar convicções religiosas, que o RGPD considera uma categoria especial de dados (artigo 9). Cada igreja é responsável por contar com uma base que o permita, por exemplo o artigo 9.2.d do RGPD, que ampara o tratamento por uma fundação, associação ou outro organismo sem fins lucrativos com finalidade religiosa, no âmbito de suas atividades legítimas e com as devidas garantias, desde que se refira exclusivamente a seus membros atuais ou antigos ou a pessoas que mantenham contatos regulares com ele em relação com suas finalidades, e que os dados não sejam comunicados fora dele sem o consentimento dos titulares, ou o consentimento explícito da pessoa. Nós não decidimos nem avaliamos essa base: aplicamos as instruções da igreja.",
          "Os menores de 14 anos não podem prestar por si mesmos o seu consentimento (artigo 7 da Lei Orgânica 3/2018). O registro por QR exige declarar que se tem pelo menos essa idade.",
        ],
      },
      {
        id: 'registro-qr-y-mensajes',
        titulo: "5. Registro por QR e comunicações",
        parrafos: [
          "Ao se registrar em um evento por meio de um código QR, pede-se que você aceite que a igreja guarde seus dados para registrar sua presença e acompanhá-lo após a sua visita. Além disso, você pode marcar, cada uma separadamente e sem que venham marcadas de antemão, as caixas para receber mensagens da igreja por e-mail, por WhatsApp ou por SMS. Não marcar nenhuma não impede você de se registrar.",
          "Guardamos como evidência qual texto você aceitou, em qual versão e em qual data, para que a igreja possa demonstrá-lo.",
          "Só são enviadas mensagens a quem deu o seu consentimento para esse canal, e cada mensagem deve permitir o cancelamento com facilidade, de acordo com o artigo 21 da Lei espanhola 34/2002. Na data desta versão, a plataforma não envia mensagens reais: esta seção descreve as regras que serão aplicadas quando essa função for ativada.",
        ],
      },
      {
        id: 'destinatarios',
        titulo: "6. Quem mais acessa os dados",
        parrafos: [
          "Para prestar o serviço, usamos fornecedores que atuam como subcontratantes ulteriores: a infraestrutura de banco de dados, autenticação e armazenamento de arquivos, a hospedagem do site e o envio de e-mails de convite. Não vendemos dados nem os usamos para publicidade. Só os comunicamos a terceiros quando a lei o exige ou uma autoridade o ordena.",
          "Alguns fornecedores pertencem a grupos com sede fora do Espaço Econômico Europeu. Nesse caso, as transferências se apoiam nas garantias do capítulo V do RGPD, como uma decisão de adequação ou as cláusulas contratuais-padrão. Quem solicitar a {emailLegal} pode obter a lista atualizada de subcontratantes ulteriores e a região em que os dados são hospedados.",
        ],
      },
      {
        id: 'conservacion',
        titulo: "7. Por quanto tempo conservamos os dados das igrejas",
        parrafos: [
          "Os dados de cada igreja são conservados enquanto a sua conta estiver ativa. Quando uma igreja solicita o seu cancelamento, a conta passa pelas etapas de recesso e suspensão, e depois é programada a exclusão: primeiro uma exclusão lógica, com um prazo fixo de 30 dias durante o qual ainda pode ser recuperada, e depois a eliminação definitiva dos dados e dos arquivos.",
          "As cópias de segurança são renovadas conforme o seu próprio ciclo e não são mantidas além desse prazo. Os dados desaparecem dos sistemas ativos 30 dias após o cancelamento e das cópias de segurança em no máximo 14 dias adicionais. Antes do cancelamento, a igreja pode baixar todos os seus dados em formato JSON e CSV.",
        ],
      },
      {
        id: 'derechos',
        titulo: "8. Seus direitos",
        parrafos: ["Você tem direito a:"],
        lista: [
          "acessar seus dados e obter uma cópia;",
          "retificar os dados inexatos;",
          "pedir a sua eliminação;",
          "pedir que o seu tratamento seja limitado;",
          "opor-se ao tratamento;",
          "receber seus dados em formato estruturado e transferi-los a outro responsável pelo tratamento (portabilidade);",
          "retirar a qualquer momento um consentimento que tenha dado, sem que isso afete o que foi feito antes de retirá-lo.",
        ],
        cierre: [
          "Para exercê-los sobre os dados de uma igreja, dirija-se a essa igreja. Para os dados que tratamos como responsáveis pelo tratamento, escreva para {emailLegal}. Respondemos no prazo de um mês, prorrogável conforme o artigo 12.3 do RGPD. Não tomamos decisões automatizadas com efeitos jurídicos sobre as pessoas.",
          "Se você considera que não tratamos bem os seus dados, pode apresentar reclamação perante a Agência Espanhola de Proteção de Dados (AEPD), www.aepd.es.",
        ],
      },
      {
        id: 'seguridad',
        titulo: "9. Segurança",
        parrafos: [
          "Aplicamos medidas técnicas e organizativas adequadas ao risco: cada igreja só acessa os seus próprios dados, o acesso é limitado por funções e permissões, as comunicações trafegam criptografadas, as senhas são gerenciadas por um serviço de autenticação especializado, e as alterações de consentimento e de ciclo de vida ficam registradas. Nenhum sistema é infalível. Se ocorrer uma violação de segurança que afete dados pessoais, a notificaremos à igreja afetada sem demora injustificada.",
        ],
      },
      {
        id: 'cambios',
        titulo: "10. Alterações nesta política",
        parrafos: [
          "Se alterarmos esta política, publicaremos uma versão nova, com o seu número e a sua data, e avisaremos sobre as mudanças importantes. As versões anteriores são conservadas no registro de versões da plataforma.",
        ],
      },
    ],
  },

  terminos: {
    titulo: "Termos de uso",
    resumen: "As condições para usar a Vive ADN, as responsabilidades de cada parte e o contrato de subcontratação do tratamento de dados.",
    secciones: [
      {
        id: 'objeto',
        titulo: "1. Objeto e aceitação",
        parrafos: [
          "Estes termos regulam o uso da Vive ADN, uma plataforma web oferecida por {titular}, com domicílio em {domicilio} e NIF {nif}. Ao criar uma conta ou usar o serviço, você aceita estes termos. Se o faz em nome de uma igreja, declara que tem autoridade para obrigá-la.",
        ],
      },
      {
        id: 'servicio',
        titulo: "2. O serviço",
        parrafos: [
          "A Vive ADN permite que cada igreja gerencie seus membros, casas de oração, consolidação, formação, eventos, comunicação e relatórios. Trabalhamos para que o serviço esteja disponível de forma contínua, mas não garantimos que não haverá interrupções, e podemos modificar ou retirar funções, avisando com antecedência razoável quando for possível.",
        ],
      },
      {
        id: 'cuentas',
        titulo: "3. Contas e funções",
        parrafos: [
          "Cada igreja tem um proprietário que convida outras pessoas e lhes atribui uma função com permissões. A igreja responde pelas pessoas às quais dá acesso, por seus dados de contato serem corretos e por elas guardarem suas credenciais com cuidado. Avise-nos sem demora se suspeitar de um acesso não autorizado.",
        ],
      },
      {
        id: 'responsabilidad-iglesia',
        titulo: "4. Responsabilidade da igreja sobre seus dados",
        parrafos: [
          "A igreja é a responsável pelo tratamento dos dados de seus membros e visitantes, e a Vive ADN é sua subcontratante. Por isso, a igreja se obriga a:",
        ],
        lista: [
          "contar com uma base legal para cada tratamento e, tratando-se de dados que revelam convicções religiosas, com uma das exceções do artigo 9.2 do RGPD;",
          "informar as pessoas conforme os artigos 13 e 14 do RGPD;",
          "enviar mensagens somente a quem tenha dado o seu consentimento para esse canal, e respeitar os cancelamentos;",
          "não registrar menores de 14 anos sem a autorização de quem exerça a responsabilidade parental ou a tutela;",
          "atender os direitos das pessoas, com a nossa ajuda quando precisar;",
          "não introduzir dados de que não necessite nem dados de saúde, penais ou outros que a plataforma não foi concebida para custodiar.",
        ],
      },
      {
        id: 'uso-aceptable',
        titulo: "5. Uso aceitável",
        parrafos: ["Não é permitido:"],
        lista: [
          "usar a plataforma para enviar comunicações não solicitadas ou a quem tenha cancelado o recebimento;",
          "se passar por outra pessoa ou por outra igreja;",
          "tentar acessar dados de outra igreja, burlar os limites do serviço ou testar a sua segurança sem a nossa permissão por escrito;",
          "copiar, descompilar ou revender o serviço;",
          "introduzir conteúdo ilícito ou que viole direitos de terceiros.",
        ],
        cierre: ["Podemos suspender uma conta que descumpra estas regras, avisando quando for possível."],
      },
      {
        id: 'condiciones-economicas',
        titulo: "6. Planos e condições econômicas",
        parrafos: [
          "Os planos estabelecem limites de uso, por exemplo de pessoas com acesso. Na data desta versão, o serviço não tem cobranças reais. Se vierem a ser introduzidas, serão informados o preço, se inclui impostos e a forma de pagamento antes de aplicá-lo, e será necessária a sua aceitação. A Vive ADN não processa nem guarda as ofertas ou contribuições de uma igreja: apenas mostra links para os sites que a própria igreja configura.",
        ],
      },
      {
        id: 'propiedad',
        titulo: "7. Propriedade dos dados e do serviço",
        parrafos: [
          "Os dados que cada igreja introduz são da igreja. Ela nos concede o direito de tratá-los unicamente para prestar-lhe o serviço. O software, a marca, o design e os textos da Vive ADN pertencem a {titular} ou a seus licenciantes, e estes termos não transmitem nenhum direito sobre eles, salvo o de usar o serviço.",
        ],
      },
      {
        id: 'responsabilidad',
        titulo: "8. Responsabilidade",
        parrafos: [
          "Prestamos o serviço com a diligência razoável, mas não respondemos por danos indiretos nem por lucros cessantes, nem pelo uso ilícito que uma igreja faça da plataforma. Nossa responsabilidade total se limita ao que a lei permita limitar, e nada nestes termos exclui a responsabilidade por dolo nem a que não possa ser excluída legalmente.",
        ],
      },
      {
        id: 'baja-exportacion',
        titulo: "9. Cancelamento, exportação e exclusão",
        parrafos: [
          "A igreja pode baixar a qualquer momento todos os seus dados em formato JSON e CSV, com um hash de cada tabela para comprovar que estão completos. Pode solicitar o cancelamento quando quiser. Após o cancelamento, a conta passa por recesso e suspensão, e depois é programada a sua exclusão: uma exclusão lógica com um prazo fixo de 30 dias, durante o qual pode ser recuperada, e a eliminação definitiva dos dados e dos arquivos. As cópias de segurança são renovadas conforme o seu ciclo. Os dados desaparecem dos sistemas ativos 30 dias após o cancelamento e das cópias de segurança em no máximo 14 dias adicionais.",
        ],
      },
      {
        id: 'cambios',
        titulo: "10. Alterações nestes termos",
        parrafos: [
          "Podemos modificar estes termos. Publicaremos a versão nova com o seu número e a sua data e avisaremos com antecedência razoável sobre as mudanças que o prejudiquem. Se você não estiver de acordo, pode cancelar antes que entrem em vigor.",
        ],
      },
      {
        id: 'ley',
        titulo: "11. Lei aplicável e jurisdição",
        parrafos: [
          "Estes termos se regem pela lei espanhola. Para resolver qualquer divergência, as partes se submetem aos juízos e tribunais de Sevilha, sem prejuízo do foro que a lei imponha em favor dos consumidores. Você pode nos escrever para {emailLegal} antes de recorrer a eles.",
        ],
      },
      {
        id: 'encargo',
        titulo: "12. Anexo: contrato de subcontratação do tratamento (artigo 28 do RGPD)",
        parrafos: [
          "Este anexo regula o tratamento de dados pessoais que {titular} (o subcontratante) realiza por conta de cada igreja (a responsável pelo tratamento) ao prestar-lhe o serviço. Entende-se aceito quando a igreja aceita estes termos.",
        ],
        lista: [
          "Objeto e duração: hospedar, armazenar, organizar, consultar, exportar e excluir os dados que a igreja registre, durante o tempo de vigência do serviço e até que se complete a exclusão descrita na seção 9.",
          "Natureza e finalidade: exclusivamente prestar à igreja as funções da plataforma.",
          "Tipos de dados: identificação e contato, data de nascimento, notas, frequência, consolidação, formação, consentimentos de comunicação e os que, por sua natureza, revelem convicções religiosas. Categorias de titulares dos dados: membros, frequentadores, visitantes e colaboradores da igreja.",
          "Instruções: o subcontratante trata os dados somente seguindo as instruções documentadas da igreja, que são o uso que esta faz da plataforma e o que nos comunique por escrito. Se considerar que uma instrução infringe a normativa de proteção de dados, informará a igreja.",
          "Confidencialidade: as pessoas autorizadas a tratar os dados se comprometeram a manter a sua confidencialidade.",
          "Segurança: o subcontratante aplica as medidas do artigo 32 do RGPD descritas na política de privacidade.",
          "Subcontratantes ulteriores: a igreja concede uma autorização geral para recorrer aos fornecedores necessários para prestar o serviço. O subcontratante impõe a eles as mesmas obrigações de proteção de dados, responde perante a igreja pelo seu cumprimento e, se incorporar ou substituir algum, comunicará isso para que a igreja possa se opor.",
          "Transferências internacionais: só são realizadas com as garantias do capítulo V do RGPD.",
          "Direitos dos titulares dos dados: o subcontratante ajudará a igreja a atendê-los e encaminhará à igreja qualquer solicitação que receba diretamente.",
          "Violações de segurança: o subcontratante as notificará à igreja sem demora injustificada após tomar conhecimento delas e lhe fornecerá a informação necessária.",
          "Assistência: o subcontratante ajudará a igreja com as avaliações de impacto e consultas prévias que sejam necessárias.",
          "Fim do serviço: a igreja pode exportar todos os seus dados e, após o cancelamento, o subcontratante os eliminará conforme a seção 9, salvo se uma norma exigir conservá-los.",
          "Auditoria: o subcontratante colocará à disposição da igreja a informação necessária para demonstrar o cumprimento e permitirá auditorias razoáveis, mediante aviso prévio.",
        ],
        cierre: [
          "A igreja, como responsável pelo tratamento, se obriga a cumprir o previsto na seção 4 e a dar ao subcontratante instruções lícitas.",
        ],
      },
    ],
  },

  aviso: {
    titulo: "Aviso legal",
    resumen: "Quem é o titular da Vive ADN, as condições de uso do site e a lei aplicável.",
    secciones: [
      {
        id: 'titular',
        titulo: "1. Titular do site",
        parrafos: [
          "Em cumprimento do artigo 10 da Lei espanhola 34/2002, de serviços da sociedade da informação e de comércio eletrônico, informa-se que o titular deste site é {titular}, com domicílio em {domicilio}, NIF {nif} e e-mail de contato {emailLegal}.",
          { texto: "Dados de inscrição em registro público: {registro}.", si: 'registro' },
        ],
      },
      {
        id: 'objeto',
        titulo: "2. Objeto",
        parrafos: [
          "Este site, acessível em viveadn.com, oferece a Vive ADN, uma plataforma para que as igrejas gerenciem seus membros, casas de oração, consolidação, formação, eventos e relatórios.",
        ],
      },
      {
        id: 'uso',
        titulo: "3. Condições de uso",
        parrafos: [
          "O acesso ao site atribui a condição de usuário e implica aceitar este aviso. O uso das contas e dos serviços se rege, além disso, pelos Termos de uso. Você se compromete a usar o site de forma lícita e a não prejudicar o seu funcionamento nem os direitos de terceiros.",
        ],
      },
      {
        id: 'propiedad',
        titulo: "4. Propriedade intelectual e industrial",
        parrafos: [
          "O software, o design, os textos, os logotipos e a marca Vive ADN pertencem a {titular} ou a seus licenciantes. Fica proibida a sua reprodução, distribuição ou transformação sem autorização expressa, salvo o que a lei permita. Os dados que cada igreja introduz são da igreja.",
        ],
      },
      {
        id: 'responsabilidad',
        titulo: "5. Responsabilidade e links",
        parrafos: [
          "Fazemos o razoável para que a informação do site seja correta e esteja atualizada, sem garantir que não haverá erros nem interrupções. O site pode mostrar links para sites de terceiros, por exemplo os de arrecadação que cada igreja configura, sobre cujo conteúdo não temos controle nem respondemos.",
        ],
      },
      {
        id: 'datos',
        titulo: "6. Proteção de dados",
        parrafos: [
          "O tratamento de dados pessoais é descrito na Política de privacidade, e o uso de armazenamento no seu dispositivo, na Política de cookies.",
        ],
      },
      {
        id: 'ley',
        titulo: "7. Lei aplicável e jurisdição",
        parrafos: [
          "Este aviso se rege pela lei espanhola. Para qualquer controvérsia, as partes se submetem aos juízos e tribunais de Sevilha, salvo se a lei impuser outro foro em favor dos consumidores. Você pode nos contatar em {emailLegal}.",
        ],
      },
    ],
  },

  cookies: {
    titulo: "Política de cookies",
    resumen: "O que a Vive ADN armazena no seu dispositivo, para que serve e como apagá-lo.",
    secciones: [
      {
        id: 'que-usamos',
        titulo: "1. O que armazenamos no seu dispositivo",
        parrafos: [
          "A Vive ADN não usa cookies de publicidade, de análise nem de rastreamento, próprios ou de terceiros, e não carrega recursos de terceiros para ser exibida. Para funcionar, guarda dois dados no armazenamento local do seu navegador, que cumpre uma função semelhante à de um cookie:",
        ],
        lista: [
          "A sessão: um identificador que mantém a sua sessão aberta depois que você iniciou sessão. É necessário para o serviço que você solicitou e desaparece ao encerrar a sessão. É gerenciado pelo serviço de autenticação.",
          "O idioma: a preferência de idioma que você escolhe (chave viveadn.idioma). Lembra a sua escolha e é conservada até que você a apague.",
        ],
      },
      {
        id: 'consentimiento',
        titulo: "2. Por que não pedimos consentimento",
        parrafos: [
          "O artigo 22.2 da Lei espanhola 34/2002 não exige consentimento para o armazenamento ou acesso de natureza técnica estritamente necessário para prestar um serviço expressamente solicitado pela pessoa usuária. O guia da Agência Espanhola de Proteção de Dados (AEPD) inclui entre esses casos a autenticação e a personalização da interface, como o idioma. Por isso não mostramos um aviso de cookies. Se no futuro acrescentarmos armazenamento não necessário, pediremos antes o seu consentimento e atualizaremos esta política.",
        ],
      },
      {
        id: 'servidores',
        titulo: "3. Registros do servidor",
        parrafos: [
          "Como qualquer serviço web, o fornecedor de hospedagem e o de autenticação podem registrar dados técnicos de cada conexão, como o endereço IP, para manter a segurança e o funcionamento. Isso é explicado na Política de privacidade.",
        ],
      },
      {
        id: 'borrar',
        titulo: "4. Como apagá-lo",
        parrafos: [
          "Você pode encerrar a sessão a partir do aplicativo, ou apagar os dados do site nas configurações do seu navegador. Se o fizer, terá de iniciar sessão novamente e escolher outra vez o idioma.",
        ],
      },
      {
        id: 'cambios',
        titulo: "5. Alterações",
        parrafos: ["Publicaremos aqui qualquer alteração, com uma versão nova e a sua data."],
      },
    ],
  },
}

export default ptBR
