import type { TextosLegales } from './tipos'

// Texto maestro (español). Marcadores: {titular} {nif} {domicilio} {emailLegal} {emailSoporte} {registro}.
// Versión 1: redactada con las fuentes de docs/LEGAL.md, pendiente de revisión por un abogado.
const es: TextosLegales = {
  privacidad: {
    titulo: 'Política de privacidad',
    resumen: 'Qué datos trata Vive ADN, para qué, con qué base legal, durante cuánto tiempo y cómo ejercer tus derechos.',
    secciones: [
      {
        id: 'quienes-somos',
        titulo: '1. Quiénes somos y qué papel tenemos',
        parrafos: [
          'Vive ADN es una plataforma web para que las iglesias gestionen sus miembros, casas de oración, consolidación, formación, eventos e informes. La ofrece {titular}, con domicilio en {domicilio} y NIF {nif}. Para cualquier cuestión de privacidad puedes escribir a {emailLegal}.',
          'Tenemos dos papeles distintos, y conviene distinguirlos porque de ellos depende a quién debes dirigirte:',
        ],
        lista: [
          'Responsables del tratamiento de los datos de las personas que usan la plataforma: quienes crean la cuenta de una iglesia, quienes reciben una invitación y quienes se ponen en contacto con nosotros.',
          'Encargados del tratamiento de los datos de los miembros, asistentes y visitantes que cada iglesia registra. En esos datos la responsable es la iglesia, que decide para qué y cómo se usan. Nosotros los tratamos por su cuenta y siguiendo sus instrucciones, conforme al contrato de encargo que forma parte de los Términos de uso.',
        ],
      },
      {
        id: 'si-eres-miembro',
        titulo: '2. Si eres miembro o visitante de una iglesia',
        parrafos: [
          'Tus datos los ha registrado tu iglesia, o los has facilitado tú al registrarte en un evento mediante un código QR. La responsable de ese tratamiento es la iglesia, no nosotros. Para saber qué hace con tus datos, con qué base legal y por cuánto tiempo, y para ejercer tus derechos, dirígete primero a ella.',
          'Si no sabes a qué iglesia corresponde tu registro, o la iglesia no te responde, escríbenos a {emailLegal} y la ayudaremos a atender tu petición.',
        ],
      },
      {
        id: 'datos-como-responsables',
        titulo: '3. Datos que tratamos como responsables',
        parrafos: ['Estos son los datos que tratamos por nuestra cuenta, para qué los usamos y en qué nos basamos:'],
        lista: [
          'Datos de la cuenta (nombre, apellidos, correo electrónico, iglesia y rol, y la contraseña que gestiona el servicio de autenticación sin que podamos verla). Los usamos para crear la cuenta, identificarte y darte acceso. Base legal: ejecución del contrato, artículo 6.1.b del RGPD.',
          'Datos de seguridad, como una huella no reversible de la dirección IP y los intentos de registro. Los usamos para frenar abusos y proteger a todas las iglesias. Base legal: interés legítimo en la seguridad del servicio, artículo 6.1.f del RGPD.',
          'Comunicaciones que nos envías, por ejemplo una consulta de soporte. Las usamos para atenderte. Base legal: ejecución del contrato o interés legítimo en responderte.',
          'Datos que debamos conservar para cumplir obligaciones legales. Base legal: artículo 6.1.c del RGPD.',
        ],
        cierre: [
          'Conservamos los datos de la cuenta mientras la cuenta esté activa y, después, durante el tiempo que exijan las obligaciones legales o la defensa de posibles reclamaciones. Vive ADN no procesa ni guarda pagos: las aportaciones de una iglesia llegan directamente a los sitios que ella usa.',
        ],
      },
      {
        id: 'datos-como-encargados',
        titulo: '4. Datos que tratamos como encargados de cada iglesia',
        parrafos: [
          'Según lo que cada iglesia decida registrar, la plataforma puede contener: nombre, apellidos, correo, teléfono, dirección, fecha de nacimiento, etiquetas y notas; asistencia a casas de oración y eventos; seguimiento de consolidación; progreso de formación y certificados; el estado de consentimiento de cada persona para recibir mensajes por correo, WhatsApp o SMS, con su historial; y los mensajes preparados desde la plataforma.',
          'Por su naturaleza, el simple hecho de pertenecer a una iglesia puede revelar convicciones religiosas, que el RGPD considera una categoría especial de datos (artículo 9). Cada iglesia es responsable de contar con una base que lo permita, por ejemplo el artículo 9.2.d del RGPD, que ampara el tratamiento por una fundación, asociación u otro organismo sin ánimo de lucro con finalidad religiosa, en el ámbito de sus actividades legítimas y con las debidas garantías, siempre que se refiera exclusivamente a sus miembros actuales o antiguos o a personas que mantengan contactos regulares con él en relación con sus fines, y que los datos no se comuniquen fuera de él sin el consentimiento de las personas interesadas, o el consentimiento explícito de la persona. Nosotros no decidimos ni valoramos esa base: aplicamos las instrucciones de la iglesia.',
          'Los menores de 14 años no pueden prestar por sí mismos su consentimiento (artículo 7 de la Ley Orgánica 3/2018). El registro por QR exige declarar que se tiene al menos esa edad.',
        ],
      },
      {
        id: 'registro-qr-y-mensajes',
        titulo: '5. Registro por QR y comunicaciones',
        parrafos: [
          'Al registrarte en un evento mediante un código QR se te pide aceptar que la iglesia guarde tus datos para registrar tu asistencia y acompañarte tras tu visita. Además, puedes marcar, cada una por separado y sin que vengan marcadas de antemano, las casillas para recibir mensajes de la iglesia por correo electrónico, por WhatsApp o por SMS. No marcar ninguna no te impide registrarte.',
          'Guardamos como evidencia qué texto aceptaste, en qué versión y en qué fecha, para que la iglesia pueda demostrarlo.',
          'Solo se envían mensajes a quien ha dado su consentimiento para ese canal, y cada mensaje debe permitir darse de baja con facilidad, de acuerdo con el artículo 21 de la Ley 34/2002. En la fecha de esta versión la plataforma no envía mensajes reales: esta sección describe las reglas que se aplicarán cuando esa función se active.',
        ],
      },
      {
        id: 'destinatarios',
        titulo: '6. Quién más accede a los datos',
        parrafos: [
          'Para prestar el servicio usamos proveedores que actúan como subencargados: la infraestructura de base de datos, autenticación y almacenamiento de archivos, el alojamiento de la web y el envío de correos de invitación. No vendemos datos ni los usamos para publicidad. Solo los comunicamos a terceros cuando lo exige la ley o lo ordena una autoridad.',
          'Los datos de las iglesias se alojan en la región {regionDatos} de nuestro proveedor de infraestructura, situada en la Unión Europea.',
          'Algunos proveedores pertenecen a grupos con sede fuera del Espacio Económico Europeo. En ese caso, las transferencias se apoyan en las garantías del capítulo V del RGPD, como una decisión de adecuación o las cláusulas contractuales tipo. Quien lo pida a {emailLegal} puede obtener la lista actualizada de subencargados y la región en la que se alojan los datos.',
        ],
      },
      {
        id: 'conservacion',
        titulo: '7. Cuánto tiempo conservamos los datos de las iglesias',
        parrafos: [
          'Los datos de cada iglesia se conservan mientras su cuenta esté activa. Cuando una iglesia solicita su baja, su cuenta queda suspendida de inmediato y se inicia un borrado suave con un plazo fijo de 30 días, durante el cual el propietario de la iglesia puede cancelar la baja y recuperar la cuenta; pasado ese plazo se realiza la purga definitiva de los datos y de los archivos.',
          'Los datos desaparecen de los sistemas activos a los 30 días de la baja y de las copias de seguridad en un máximo de 14 días más, ya que las copias se renuevan según su propio ciclo y no se conservan más allá de ese plazo. La iglesia puede descargar todos sus datos en formato JSON y CSV antes de solicitar la baja y también durante esos 30 días.',
        ],
      },
      {
        id: 'derechos',
        titulo: '8. Tus derechos',
        parrafos: ['Tienes derecho a:'],
        lista: [
          'acceder a tus datos y obtener una copia;',
          'rectificar los datos inexactos;',
          'pedir su supresión;',
          'pedir que se limite su tratamiento;',
          'oponerte al tratamiento;',
          'recibir tus datos en un formato estructurado y trasladarlos a otro responsable (portabilidad);',
          'retirar en cualquier momento un consentimiento que hayas dado, sin que afecte a lo hecho antes de retirarlo.',
        ],
        cierre: [
          'Para ejercerlos sobre los datos de una iglesia, dirígete a esa iglesia. Para los datos que tratamos como responsables, escribe a {emailLegal}. Respondemos en el plazo de un mes, ampliable según el artículo 12.3 del RGPD. No tomamos decisiones automatizadas con efectos jurídicos sobre las personas.',
          'Si consideras que no hemos tratado bien tus datos, puedes reclamar ante la Agencia Española de Protección de Datos, www.aepd.es.',
        ],
      },
      {
        id: 'seguridad',
        titulo: '9. Seguridad',
        parrafos: [
          'Aplicamos medidas técnicas y organizativas adecuadas al riesgo: cada iglesia solo accede a sus propios datos, el acceso se limita por roles y permisos, las comunicaciones viajan cifradas, las contraseñas las gestiona un servicio de autenticación especializado, y los cambios de consentimiento y de ciclo de vida quedan registrados. Ningún sistema es infalible. Si ocurre una violación de seguridad que afecte a datos personales, la notificaremos a la iglesia afectada sin dilación indebida.',
        ],
      },
      {
        id: 'cambios',
        titulo: '10. Cambios en esta política',
        parrafos: [
          'Si cambiamos esta política publicaremos una versión nueva, con su número y su fecha, y avisaremos de los cambios importantes. Las versiones anteriores se conservan en el registro de versiones de la plataforma.',
        ],
      },
    ],
  },

  terminos: {
    titulo: 'Términos de uso',
    resumen: 'Las condiciones para usar Vive ADN, las responsabilidades de cada parte y el contrato de encargo del tratamiento de datos.',
    secciones: [
      {
        id: 'objeto',
        titulo: '1. Objeto y aceptación',
        parrafos: [
          'Estos términos regulan el uso de Vive ADN, una plataforma web ofrecida por {titular}, con domicilio en {domicilio} y NIF {nif}. Al crear una cuenta o usar el servicio aceptas estos términos. Si lo haces en nombre de una iglesia, declaras que tienes autoridad para obligarla.',
        ],
      },
      {
        id: 'servicio',
        titulo: '2. El servicio',
        parrafos: [
          'Vive ADN permite a cada iglesia gestionar sus miembros, casas de oración, consolidación, formación, eventos, comunicación e informes. Trabajamos para que el servicio esté disponible de forma continua, pero no garantizamos que no haya interrupciones, y podemos modificar o retirar funciones avisando con antelación razonable cuando sea posible.',
        ],
      },
      {
        id: 'cuentas',
        titulo: '3. Cuentas y roles',
        parrafos: [
          'Cada iglesia tiene un propietario que invita a otras personas y les asigna un rol con permisos. La iglesia responde de las personas a las que da acceso, de que sus datos de contacto sean correctos y de que guarden sus credenciales con cuidado. Avísanos sin demora si sospechas un acceso no autorizado.',
        ],
      },
      {
        id: 'responsabilidad-iglesia',
        titulo: '4. Responsabilidad de la iglesia sobre sus datos',
        parrafos: [
          'La iglesia es la responsable del tratamiento de los datos de sus miembros y visitantes, y Vive ADN es su encargada. Por eso la iglesia se obliga a:',
        ],
        lista: [
          'contar con una base legal para cada tratamiento y, tratándose de datos que revelan convicciones religiosas, con una de las excepciones del artículo 9.2 del RGPD;',
          'informar a las personas conforme a los artículos 13 y 14 del RGPD;',
          'enviar mensajes solo a quien haya dado su consentimiento para ese canal, y respetar las bajas;',
          'no registrar a menores de 14 años sin la autorización de quien ejerza su patria potestad o tutela;',
          'atender los derechos de las personas, con nuestra ayuda cuando la necesite;',
          'no introducir datos que no necesite ni datos de salud, penales u otros que la plataforma no está diseñada para custodiar.',
        ],
      },
      {
        id: 'uso-aceptable',
        titulo: '5. Uso aceptable',
        parrafos: ['No está permitido:'],
        lista: [
          'usar la plataforma para enviar comunicaciones no solicitadas o a quien se haya dado de baja;',
          'suplantar a otra persona o a otra iglesia;',
          'intentar acceder a datos de otra iglesia, eludir los límites del servicio o probar su seguridad sin nuestro permiso por escrito;',
          'copiar, descompilar o revender el servicio;',
          'introducir contenido ilícito o que vulnere derechos de terceros.',
        ],
        cierre: ['Podemos suspender una cuenta que incumpla estas reglas, avisando cuando sea posible.'],
      },
      {
        id: 'condiciones-economicas',
        titulo: '6. Planes y condiciones económicas',
        parrafos: [
          'Los planes establecen límites de uso, por ejemplo de personas con acceso. En la fecha de esta versión el servicio no tiene cobros reales. Si se introdujeran, se informará del precio, de si incluye impuestos y de la forma de pago antes de aplicarlo, y requerirá tu aceptación. Vive ADN no procesa ni guarda las ofrendas o aportaciones de una iglesia: solo muestra enlaces a los sitios que la propia iglesia configura.',
        ],
      },
      {
        id: 'propiedad',
        titulo: '7. Propiedad de los datos y del servicio',
        parrafos: [
          'Los datos que cada iglesia introduce son de la iglesia. Nos concede el derecho a tratarlos únicamente para prestarle el servicio. El software, la marca, el diseño y los textos de Vive ADN son de {titular} o de sus licenciantes, y estos términos no transmiten ningún derecho sobre ellos salvo el de usar el servicio.',
        ],
      },
      {
        id: 'responsabilidad',
        titulo: '8. Responsabilidad',
        parrafos: [
          'Prestamos el servicio con la diligencia razonable, pero no respondemos de daños indirectos ni de pérdidas de beneficios, ni del uso ilícito que una iglesia haga de la plataforma. Nuestra responsabilidad total se limita a lo que la ley permita limitar, y nada de estos términos excluye la responsabilidad por dolo ni la que no pueda excluirse legalmente.',
        ],
      },
      {
        id: 'baja-exportacion',
        titulo: '9. Baja, exportación y borrado',
        parrafos: [
          'La iglesia puede descargar en cualquier momento todos sus datos en formato JSON y CSV, con una huella de cada tabla para comprobar que están completos. Puede solicitar su baja cuando quiera. Al solicitar la baja, la cuenta queda suspendida de inmediato y se inicia un borrado suave con un plazo fijo de 30 días, durante el cual el propietario de la iglesia puede cancelar la baja y recuperar la cuenta; pasado ese plazo se realiza la purga definitiva de los datos y de los archivos. Los datos desaparecen de los sistemas activos a los 30 días de la baja y de las copias de seguridad en un máximo de 14 días más.',
        ],
      },
      {
        id: 'cambios',
        titulo: '10. Cambios en estos términos',
        parrafos: [
          'Podemos modificar estos términos. Publicaremos la versión nueva con su número y su fecha y avisaremos con antelación razonable de los cambios que te perjudiquen. Si no estás de acuerdo, puedes darte de baja antes de que entren en vigor.',
        ],
      },
      {
        id: 'ley',
        titulo: '11. Ley aplicable y jurisdicción',
        parrafos: [
          'Estos términos se rigen por la ley española. Para resolver cualquier discrepancia, las partes se someten a los juzgados y tribunales de Sevilla, sin perjuicio del fuero que la ley imponga a favor de los consumidores. Puedes escribirnos a {emailLegal} antes de acudir a ellos.',
        ],
      },
      {
        id: 'encargo',
        titulo: '12. Anexo: contrato de encargo del tratamiento (artículo 28 del RGPD)',
        parrafos: [
          'Este anexo regula el tratamiento de datos personales que {titular} (el encargado) realiza por cuenta de cada iglesia (la responsable) al prestarle el servicio. Se entiende aceptado cuando la iglesia acepta estos términos.',
        ],
        lista: [
          'Objeto y duración: alojar, almacenar, organizar, consultar, exportar y borrar los datos que la iglesia registre, durante el tiempo que dure el servicio y hasta que se complete el borrado descrito en el apartado 9.',
          'Naturaleza y finalidad: exclusivamente prestar las funciones de la plataforma a la iglesia.',
          'Tipos de datos: identificación y contacto, fecha de nacimiento, notas, asistencia, consolidación, formación, consentimientos de comunicación y los que, por su naturaleza, revelen convicciones religiosas. Categorías de personas: miembros, asistentes, visitantes y colaboradores de la iglesia.',
          'Instrucciones: el encargado trata los datos solo siguiendo las instrucciones documentadas de la iglesia, que son el uso que esta hace de la plataforma y lo que nos comunique por escrito. Si considera que una instrucción infringe la normativa de protección de datos, lo informará a la iglesia.',
          'Confidencialidad: las personas autorizadas para tratar los datos se han comprometido a mantener su confidencialidad.',
          'Seguridad: el encargado aplica las medidas del artículo 32 del RGPD descritas en la política de privacidad.',
          'Subencargados: la iglesia concede una autorización general para recurrir a los proveedores necesarios para prestar el servicio. El encargado les impone las mismas obligaciones de protección de datos, responde ante la iglesia de su cumplimiento y, si incorpora o sustituye alguno, lo comunicará para que la iglesia pueda oponerse.',
          'Ubicación de los datos y transferencias internacionales: los datos se alojan en la región {regionDatos}, situada en la Unión Europea; cualquier transferencia fuera del Espacio Económico Europeo solo se realiza con las garantías del capítulo V del RGPD.',
          'Derechos de las personas: el encargado ayudará a la iglesia a atenderlos, y trasladará a la iglesia cualquier solicitud que reciba directamente.',
          'Violaciones de seguridad: el encargado las notificará a la iglesia sin dilación indebida tras tener conocimiento de ellas y le facilitará la información necesaria.',
          'Asistencia: el encargado ayudará a la iglesia con las evaluaciones de impacto y consultas previas que sean necesarias.',
          'Fin del servicio: la iglesia puede exportar todos sus datos y, tras la baja, el encargado los suprimirá conforme al apartado 9, salvo que una norma exija conservarlos.',
          'Auditoría: el encargado pondrá a disposición de la iglesia la información necesaria para demostrar el cumplimiento y permitirá auditorías razonables, previo aviso.',
        ],
        cierre: [
          'La iglesia, como responsable, se obliga a cumplir lo previsto en el apartado 4 y a dar al encargado instrucciones lícitas.',
        ],
      },
    ],
  },

  aviso: {
    titulo: 'Aviso legal',
    resumen: 'Quién es el titular de Vive ADN, las condiciones de uso del sitio web y la ley aplicable.',
    secciones: [
      {
        id: 'titular',
        titulo: '1. Titular del sitio web',
        parrafos: [
          'En cumplimiento del artículo 10 de la Ley 34/2002, de servicios de la sociedad de la información y de comercio electrónico, se informa de que el titular de este sitio web es {titular}, con domicilio en {domicilio}, NIF {nif} y correo electrónico de contacto {emailLegal}.',
          { texto: 'Datos de inscripción en registro público: {registro}.', si: 'registro' },
        ],
      },
      {
        id: 'objeto',
        titulo: '2. Objeto',
        parrafos: [
          'Este sitio web, accesible en viveadn.com, ofrece Vive ADN, una plataforma para que las iglesias gestionen sus miembros, casas de oración, consolidación, formación, eventos e informes.',
        ],
      },
      {
        id: 'uso',
        titulo: '3. Condiciones de uso',
        parrafos: [
          'El acceso al sitio atribuye la condición de usuario e implica aceptar este aviso. El uso de las cuentas y de los servicios se rige además por los Términos de uso. Te comprometes a usar el sitio de forma lícita y a no dañar su funcionamiento ni los derechos de terceros.',
        ],
      },
      {
        id: 'propiedad',
        titulo: '4. Propiedad intelectual e industrial',
        parrafos: [
          'El software, el diseño, los textos, los logotipos y la marca Vive ADN pertenecen a {titular} o a sus licenciantes. Queda prohibida su reproducción, distribución o transformación sin autorización expresa, salvo lo que permita la ley. Los datos que cada iglesia introduce son de la iglesia.',
        ],
      },
      {
        id: 'responsabilidad',
        titulo: '5. Responsabilidad y enlaces',
        parrafos: [
          'Hacemos lo razonable para que la información del sitio sea correcta y esté actualizada, sin garantizar que no haya errores ni interrupciones. El sitio puede mostrar enlaces a sitios de terceros, por ejemplo los de recaudo que configura cada iglesia, sobre cuyo contenido no tenemos control ni respondemos.',
        ],
      },
      {
        id: 'datos',
        titulo: '6. Protección de datos',
        parrafos: [
          'El tratamiento de datos personales se describe en la Política de privacidad, y el uso de almacenamiento en tu dispositivo, en la Política de cookies.',
        ],
      },
      {
        id: 'ley',
        titulo: '7. Ley aplicable y jurisdicción',
        parrafos: [
          'Este aviso se rige por la ley española. Para cualquier controversia, las partes se someten a los juzgados y tribunales de Sevilla, salvo que la ley imponga otro fuero a favor de los consumidores. Puedes contactarnos en {emailLegal}.',
        ],
      },
    ],
  },

  cookies: {
    titulo: 'Política de cookies',
    resumen: 'Qué almacena Vive ADN en tu dispositivo, para qué sirve y cómo borrarlo.',
    secciones: [
      {
        id: 'que-usamos',
        titulo: '1. Qué almacenamos en tu dispositivo',
        parrafos: [
          'Vive ADN no usa cookies de publicidad, de analítica ni de seguimiento, propias ni de terceros, y no carga recursos de terceros para mostrarse. Para funcionar guarda dos datos en el almacenamiento local de tu navegador, que cumple una función similar a la de una cookie:',
        ],
        lista: [
          'La sesión: un identificador que mantiene abierta tu sesión una vez has iniciado sesión. Es necesario para el servicio que has pedido y desaparece al cerrar sesión. Lo gestiona el servicio de autenticación.',
          'El idioma: la preferencia de idioma que eliges (clave viveadn.idioma). Recuerda tu elección y se conserva hasta que la borres.',
        ],
      },
      {
        id: 'consentimiento',
        titulo: '2. Por qué no pedimos consentimiento',
        parrafos: [
          'El artículo 22.2 de la Ley 34/2002 no exige consentimiento para el almacenamiento o acceso de índole técnica estrictamente necesario para prestar un servicio expresamente solicitado por la persona usuaria. La guía de la Agencia Española de Protección de Datos incluye entre estos casos la autenticación y la personalización de la interfaz, como el idioma. Por eso no mostramos un aviso de cookies. Si en el futuro añadimos almacenamiento no necesario, pediremos antes tu consentimiento y actualizaremos esta política.',
        ],
      },
      {
        id: 'servidores',
        titulo: '3. Registros del servidor',
        parrafos: [
          'Como cualquier servicio web, el proveedor de alojamiento y el de autenticación pueden registrar datos técnicos de cada conexión, como la dirección IP, para mantener la seguridad y el funcionamiento. Esto se explica en la Política de privacidad.',
        ],
      },
      {
        id: 'borrar',
        titulo: '4. Cómo borrarlo',
        parrafos: [
          'Puedes cerrar sesión desde la aplicación, o borrar los datos del sitio desde la configuración de tu navegador. Si lo haces, tendrás que iniciar sesión de nuevo y elegir otra vez el idioma.',
        ],
      },
      {
        id: 'cambios',
        titulo: '5. Cambios',
        parrafos: ['Publicaremos aquí cualquier cambio, con una versión nueva y su fecha.'],
      },
    ],
  },
}

export default es
