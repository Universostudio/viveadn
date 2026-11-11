import type { TextosLegales } from './tipos'

// Traduction française du texte maître (espagnol). Marqueurs : {titular} {nif} {domicilio} {emailLegal} {emailSoporte} {registro}.
// Version 1 : traduction à faire réviser par un avocat.
const fr: TextosLegales = {
  privacidad: {
    titulo: "Politique de confidentialité",
    resumen: "Quelles données Vive ADN traite, pourquoi, sur quelle base légale, pendant combien de temps et comment exercer vos droits.",
    secciones: [
      {
        id: 'quienes-somos',
        titulo: "1. Qui nous sommes et quel rôle nous avons",
        parrafos: [
          "Vive ADN est une plateforme web permettant aux églises de gérer leurs membres, leurs maisons de prière, la consolidation, la formation, les événements et les rapports. Elle est proposée par {titular}, domicilié à {domicilio}, NIF {nif}. Pour toute question relative à la vie privée, vous pouvez écrire à {emailLegal}.",
          "Nous avons deux rôles distincts, et il convient de les distinguer, car c'est d'eux que dépend l'interlocuteur auquel vous devez vous adresser :",
        ],
        lista: [
          "Responsables du traitement des données des personnes qui utilisent la plateforme : celles qui créent le compte d'une église, celles qui reçoivent une invitation et celles qui nous contactent.",
          "Sous-traitants pour les données des membres, des participants et des visiteurs que chaque église enregistre. Pour ces données, le responsable du traitement est l'église, qui décide de leurs finalités et de leurs modalités d'utilisation. Nous les traitons pour son compte et selon ses instructions, conformément au contrat de sous-traitance qui fait partie des Conditions d'utilisation.",
        ],
      },
      {
        id: 'si-eres-miembro',
        titulo: "2. Si vous êtes membre ou visiteur d'une église",
        parrafos: [
          "Vos données ont été enregistrées par votre église, ou vous les avez fournies vous-même en vous inscrivant à un événement au moyen d'un code QR. Le responsable de ce traitement est l'église, et non nous. Pour savoir ce qu'elle fait de vos données, sur quelle base légale et pendant combien de temps, et pour exercer vos droits, adressez-vous d'abord à elle.",
          "Si vous ne savez pas à quelle église correspond votre inscription, ou si l'église ne vous répond pas, écrivez-nous à {emailLegal} et nous l'aiderons à traiter votre demande.",
        ],
      },
      {
        id: 'datos-como-responsables',
        titulo: "3. Données que nous traitons en tant que responsables du traitement",
        parrafos: ["Voici les données que nous traitons pour notre propre compte, les raisons pour lesquelles nous les utilisons et ce sur quoi nous nous fondons :"],
        lista: [
          "Données du compte (nom, prénoms, adresse électronique, église et rôle, ainsi que le mot de passe, géré par le service d'authentification sans que nous puissions le voir). Nous les utilisons pour créer le compte, vous identifier et vous donner accès. Base légale : exécution du contrat, article 6.1.b du RGPD.",
          "Données de sécurité, telles qu'une empreinte non réversible de l'adresse IP et les tentatives d'inscription. Nous les utilisons pour freiner les abus et protéger toutes les églises. Base légale : intérêt légitime lié à la sécurité du service, article 6.1.f du RGPD.",
          "Communications que vous nous envoyez, par exemple une demande d'assistance. Nous les utilisons pour vous répondre. Base légale : exécution du contrat ou intérêt légitime à vous répondre.",
          "Données que nous devons conserver pour respecter des obligations légales. Base légale : article 6.1.c du RGPD.",
        ],
        cierre: [
          "Nous conservons les données du compte tant que le compte est actif et, ensuite, pendant la durée exigée par les obligations légales ou la défense d'éventuelles réclamations. Vive ADN ne traite ni ne conserve aucun paiement : les contributions d'une église parviennent directement aux sites qu'elle utilise.",
        ],
      },
      {
        id: 'datos-como-encargados',
        titulo: "4. Données que nous traitons en tant que sous-traitants de chaque église",
        parrafos: [
          "Selon ce que chaque église décide d'enregistrer, la plateforme peut contenir : nom, prénoms, adresse électronique, téléphone, adresse postale, date de naissance, étiquettes et notes ; présence aux maisons de prière et aux événements ; suivi de la consolidation ; progression dans la formation et certificats ; l'état du consentement de chaque personne à recevoir des messages par courrier électronique, WhatsApp ou SMS, avec son historique ; et les messages préparés depuis la plateforme.",
          "Par sa nature, le simple fait d'appartenir à une église peut révéler des convictions religieuses, que le RGPD considère comme une catégorie particulière de données (article 9). Chaque église est responsable de disposer d'une base qui le permette, par exemple l'article 9.2.d du RGPD, qui couvre le traitement effectué par une fondation, une association ou tout autre organisme à but non lucratif poursuivant une finalité religieuse, dans le cadre de ses activités légitimes et moyennant des garanties appropriées, à condition que le traitement se rapporte exclusivement aux membres actuels ou anciens de cet organisme ou aux personnes entretenant avec lui des contacts réguliers en lien avec ses finalités, et que les données ne soient pas communiquées à l'extérieur sans le consentement des personnes concernées, ou le consentement explicite de la personne. Nous ne décidons ni n'évaluons cette base : nous appliquons les instructions de l'église.",
          "Les mineurs de moins de 14 ans ne peuvent pas donner eux-mêmes leur consentement (article 7 de la loi organique 3/2018). L'inscription par QR exige de déclarer avoir au moins cet âge.",
        ],
      },
      {
        id: 'registro-qr-y-mensajes',
        titulo: "5. Inscription par QR et communications",
        parrafos: [
          "Lorsque vous vous inscrivez à un événement au moyen d'un code QR, il vous est demandé d'accepter que l'église conserve vos données afin d'enregistrer votre présence et de vous accompagner après votre visite. Vous pouvez en outre cocher, chacune séparément et sans qu'elles soient cochées à l'avance, les cases permettant de recevoir des messages de l'église par courrier électronique, par WhatsApp ou par SMS. Ne cocher aucune case ne vous empêche pas de vous inscrire.",
          "Nous conservons comme preuve le texte que vous avez accepté, dans quelle version et à quelle date, afin que l'église puisse le démontrer.",
          "Des messages ne sont envoyés qu'aux personnes ayant donné leur consentement pour ce canal, et chaque message doit permettre de se désinscrire facilement, conformément à l'article 21 de la loi espagnole 34/2002 sur les services de la société de l'information et le commerce électronique. À la date de cette version, la plateforme n'envoie pas de messages réels : cette section décrit les règles qui s'appliqueront lorsque cette fonction sera activée.",
        ],
      },
      {
        id: 'destinatarios',
        titulo: "6. Qui d'autre accède aux données",
        parrafos: [
          "Pour fournir le service, nous recourons à des prestataires qui agissent en tant que sous-traitants ultérieurs : l'infrastructure de base de données, d'authentification et de stockage de fichiers, l'hébergement du site web et l'envoi des courriers électroniques d'invitation. Nous ne vendons pas les données et ne les utilisons pas à des fins publicitaires. Nous ne les communiquons à des tiers que lorsque la loi l'exige ou qu'une autorité l'ordonne.",
          "Certains prestataires appartiennent à des groupes dont le siège se trouve en dehors de l'Espace économique européen. Dans ce cas, les transferts reposent sur les garanties du chapitre V du RGPD, comme une décision d'adéquation ou les clauses contractuelles types. Toute personne qui en fait la demande à {emailLegal} peut obtenir la liste à jour des sous-traitants ultérieurs et la région dans laquelle les données sont hébergées.",
        ],
      },
      {
        id: 'conservacion',
        titulo: "7. Combien de temps nous conservons les données des églises",
        parrafos: [
          "Les données de chaque église sont conservées tant que son compte est actif. Lorsqu'une église demande sa résiliation, son compte passe par les étapes de mise en retrait et de suspension, puis la suppression est programmée : d'abord une suppression logique, avec un délai fixe de 30 jours pendant lequel les données peuvent encore être récupérées, puis la purge définitive des données et des fichiers.",
          "Les données disparaissent des systèmes actifs 30 jours après la résiliation et des copies de sauvegarde dans un délai maximal de 14 jours supplémentaires, car les copies sont renouvelées selon leur propre cycle et ne sont pas conservées au-delà de ce délai. Avant la résiliation, l'église peut télécharger toutes ses données aux formats JSON et CSV.",
        ],
      },
      {
        id: 'derechos',
        titulo: "8. Vos droits",
        parrafos: ["Vous avez le droit de :"],
        lista: [
          "accéder à vos données et en obtenir une copie ;",
          "rectifier les données inexactes ;",
          "demander leur effacement ;",
          "demander la limitation de leur traitement ;",
          "vous opposer au traitement ;",
          "recevoir vos données dans un format structuré et les transmettre à un autre responsable du traitement (portabilité) ;",
          "retirer à tout moment un consentement que vous avez donné, sans que cela affecte ce qui a été fait avant son retrait.",
        ],
        cierre: [
          "Pour les exercer à l'égard des données d'une église, adressez-vous à cette église. Pour les données que nous traitons en tant que responsables du traitement, écrivez à {emailLegal}. Nous répondons dans un délai d'un mois, prorogeable conformément à l'article 12.3 du RGPD. Nous ne prenons pas de décisions automatisées produisant des effets juridiques à l'égard des personnes.",
          "Si vous considérez que nous n'avons pas correctement traité vos données, vous pouvez introduire une réclamation auprès de l'Agence espagnole de protection des données (AEPD), www.aepd.es.",
        ],
      },
      {
        id: 'seguridad',
        titulo: "9. Sécurité",
        parrafos: [
          "Nous appliquons des mesures techniques et organisationnelles adaptées au risque : chaque église n'accède qu'à ses propres données, l'accès est limité par rôles et permissions, les communications circulent chiffrées, les mots de passe sont gérés par un service d'authentification spécialisé, et les modifications de consentement et de cycle de vie sont enregistrées. Aucun système n'est infaillible. En cas de violation de la sécurité affectant des données personnelles, nous la notifierons à l'église concernée dans les meilleurs délais.",
        ],
      },
      {
        id: 'cambios',
        titulo: "10. Modifications de cette politique",
        parrafos: [
          "Si nous modifions cette politique, nous publierons une nouvelle version, avec son numéro et sa date, et nous signalerons les changements importants. Les versions antérieures sont conservées dans le registre des versions de la plateforme.",
        ],
      },
    ],
  },

  terminos: {
    titulo: "Conditions d'utilisation",
    resumen: "Les conditions d'utilisation de Vive ADN, les responsabilités de chaque partie et le contrat de sous-traitance du traitement des données.",
    secciones: [
      {
        id: 'objeto',
        titulo: "1. Objet et acceptation",
        parrafos: [
          "Les présentes conditions régissent l'utilisation de Vive ADN, une plateforme web proposée par {titular}, domicilié à {domicilio}, NIF {nif}. En créant un compte ou en utilisant le service, vous acceptez ces conditions. Si vous le faites au nom d'une église, vous déclarez avoir le pouvoir de l'engager.",
        ],
      },
      {
        id: 'servicio',
        titulo: "2. Le service",
        parrafos: [
          "Vive ADN permet à chaque église de gérer ses membres, ses maisons de prière, la consolidation, la formation, les événements, la communication et les rapports. Nous œuvrons pour que le service soit disponible en continu, mais nous ne garantissons pas l'absence d'interruptions, et nous pouvons modifier ou retirer des fonctions moyennant un préavis raisonnable lorsque cela est possible.",
        ],
      },
      {
        id: 'cuentas',
        titulo: "3. Comptes et rôles",
        parrafos: [
          "Chaque église a un propriétaire qui invite d'autres personnes et leur attribue un rôle assorti de permissions. L'église répond des personnes auxquelles elle donne accès, de l'exactitude de leurs données de contact et de la conservation soigneuse de leurs identifiants. Prévenez-nous sans délai si vous soupçonnez un accès non autorisé.",
        ],
      },
      {
        id: 'responsabilidad-iglesia',
        titulo: "4. Responsabilité de l'église à l'égard de ses données",
        parrafos: [
          "L'église est le responsable du traitement des données de ses membres et visiteurs, et Vive ADN est son sous-traitant. C'est pourquoi l'église s'engage à :",
        ],
        lista: [
          "disposer d'une base légale pour chaque traitement et, s'agissant de données révélant des convictions religieuses, de l'une des exceptions de l'article 9.2 du RGPD ;",
          "informer les personnes conformément aux articles 13 et 14 du RGPD ;",
          "n'envoyer de messages qu'aux personnes ayant donné leur consentement pour ce canal, et respecter les désinscriptions ;",
          "ne pas enregistrer de mineurs de moins de 14 ans sans l'autorisation de la personne qui exerce l'autorité parentale ou la tutelle ;",
          "traiter les demandes d'exercice des droits des personnes, avec notre aide lorsqu'elle en a besoin ;",
          "ne pas saisir de données dont elle n'a pas besoin ni de données de santé, pénales ou autres que la plateforme n'est pas conçue pour garder.",
        ],
      },
      {
        id: 'uso-aceptable',
        titulo: "5. Utilisation acceptable",
        parrafos: ["Il est interdit de :"],
        lista: [
          "utiliser la plateforme pour envoyer des communications non sollicitées ou à une personne qui s'est désinscrite ;",
          "usurper l'identité d'une autre personne ou d'une autre église ;",
          "tenter d'accéder aux données d'une autre église, contourner les limites du service ou tester sa sécurité sans notre autorisation écrite ;",
          "copier, décompiler ou revendre le service ;",
          "introduire un contenu illicite ou portant atteinte aux droits de tiers.",
        ],
        cierre: ["Nous pouvons suspendre un compte qui enfreint ces règles, en vous prévenant lorsque cela est possible."],
      },
      {
        id: 'condiciones-economicas',
        titulo: "6. Formules et conditions économiques",
        parrafos: [
          "Les formules établissent des limites d'utilisation, par exemple en nombre de personnes ayant accès. À la date de cette version, le service ne donne lieu à aucun paiement réel. Si des paiements étaient introduits, le prix, la mention de l'inclusion ou non des taxes et le mode de paiement seraient communiqués avant leur application, et votre acceptation serait requise. Vive ADN ne traite ni ne conserve les offrandes ou contributions d'une église : il se limite à afficher des liens vers les sites que l'église configure elle-même.",
        ],
      },
      {
        id: 'propiedad',
        titulo: "7. Propriété des données et du service",
        parrafos: [
          "Les données que chaque église saisit appartiennent à l'église. Elle nous concède le droit de les traiter uniquement pour lui fournir le service. Le logiciel, la marque, le design et les textes de Vive ADN appartiennent à {titular} ou à ses concédants de licence, et les présentes conditions ne transmettent aucun droit sur ceux-ci, hormis celui d'utiliser le service.",
        ],
      },
      {
        id: 'responsabilidad',
        titulo: "8. Responsabilité",
        parrafos: [
          "Nous fournissons le service avec une diligence raisonnable, mais nous ne répondons ni des dommages indirects, ni des pertes de bénéfices, ni de l'usage illicite que ferait une église de la plateforme. Notre responsabilité totale est limitée dans la mesure où la loi permet de la limiter, et rien dans les présentes conditions n'exclut la responsabilité en cas de dol ni celle qui ne peut être légalement exclue.",
        ],
      },
      {
        id: 'baja-exportacion',
        titulo: "9. Résiliation, exportation et suppression",
        parrafos: [
          "L'église peut télécharger à tout moment toutes ses données aux formats JSON et CSV, avec une empreinte de chaque table permettant de vérifier qu'elles sont complètes. Elle peut demander sa résiliation quand elle le souhaite. Après la résiliation, le compte passe par la mise en retrait et la suspension, puis sa suppression est programmée : une suppression logique avec un délai fixe de 30 jours, pendant lequel il peut être récupéré, et la purge définitive des données et des fichiers. Les données disparaissent des systèmes actifs 30 jours après la résiliation et des copies de sauvegarde dans un délai maximal de 14 jours supplémentaires.",
        ],
      },
      {
        id: 'cambios',
        titulo: "10. Modifications de ces conditions",
        parrafos: [
          "Nous pouvons modifier ces conditions. Nous publierons la nouvelle version avec son numéro et sa date et nous vous préviendrons moyennant un préavis raisonnable des modifications qui vous sont défavorables. Si vous n'êtes pas d'accord, vous pouvez résilier avant leur entrée en vigueur.",
        ],
      },
      {
        id: 'ley',
        titulo: "11. Loi applicable et juridiction",
        parrafos: [
          "Les présentes conditions sont régies par la loi espagnole. Pour résoudre tout différend, les parties se soumettent aux juges et tribunaux de Séville, sans préjudice du for que la loi impose en faveur des consommateurs. Vous pouvez nous écrire à {emailLegal} avant d'y recourir.",
        ],
      },
      {
        id: 'encargo',
        titulo: "12. Annexe : contrat de sous-traitance du traitement (article 28 du RGPD)",
        parrafos: [
          "Cette annexe régit le traitement de données personnelles que {titular} (le sous-traitant) effectue pour le compte de chaque église (le responsable du traitement) en lui fournissant le service. Elle est réputée acceptée lorsque l'église accepte les présentes conditions.",
        ],
        lista: [
          "Objet et durée : héberger, stocker, organiser, consulter, exporter et supprimer les données que l'église enregistre, pendant toute la durée du service et jusqu'à l'achèvement de la suppression décrite au point 9.",
          "Nature et finalité : exclusivement fournir à l'église les fonctions de la plateforme.",
          "Types de données : identification et contact, date de naissance, notes, présence, consolidation, formation, consentements de communication et celles qui, par leur nature, révèlent des convictions religieuses. Catégories de personnes concernées : membres, participants, visiteurs et collaborateurs de l'église.",
          "Instructions : le sous-traitant ne traite les données que sur instructions documentées de l'église, qui correspondent à l'usage qu'elle fait de la plateforme et à ce qu'elle nous communique par écrit. S'il considère qu'une instruction enfreint la réglementation en matière de protection des données, il en informera l'église.",
          "Confidentialité : les personnes autorisées à traiter les données se sont engagées à en respecter la confidentialité.",
          "Sécurité : le sous-traitant applique les mesures de l'article 32 du RGPD décrites dans la politique de confidentialité.",
          "Sous-traitants ultérieurs : l'église donne une autorisation générale de recourir aux prestataires nécessaires à la fourniture du service. Le sous-traitant leur impose les mêmes obligations en matière de protection des données, répond devant l'église de leur respect et, s'il en ajoute ou en remplace un, le lui communiquera afin que l'église puisse s'y opposer.",
          "Transferts internationaux : ils ne sont effectués qu'avec les garanties du chapitre V du RGPD.",
          "Droits des personnes concernées : le sous-traitant aidera l'église à y répondre, et transmettra à l'église toute demande qu'il reçoit directement.",
          "Violations de la sécurité : le sous-traitant les notifiera à l'église dans les meilleurs délais après en avoir pris connaissance et lui fournira les informations nécessaires.",
          "Assistance : le sous-traitant aidera l'église dans les analyses d'impact et les consultations préalables qui seraient nécessaires.",
          "Fin du service : l'église peut exporter toutes ses données et, après la résiliation, le sous-traitant les supprimera conformément au point 9, sauf si une norme exige de les conserver.",
          "Audit : le sous-traitant mettra à la disposition de l'église les informations nécessaires pour démontrer le respect des obligations et permettra des audits raisonnables, moyennant préavis.",
        ],
        cierre: [
          "L'église, en tant que responsable du traitement, s'engage à respecter ce qui est prévu au point 4 et à donner au sous-traitant des instructions licites.",
        ],
      },
    ],
  },

  aviso: {
    titulo: "Mentions légales",
    resumen: "Qui est le titulaire de Vive ADN, les conditions d'utilisation du site web et la loi applicable.",
    secciones: [
      {
        id: 'titular',
        titulo: "1. Titulaire du site web",
        parrafos: [
          "Conformément à l'article 10 de la loi espagnole 34/2002 sur les services de la société de l'information et le commerce électronique, il est indiqué que le titulaire de ce site web est {titular}, domicilié à {domicilio}, NIF {nif}, adresse électronique de contact {emailLegal}.",
          { texto: "Données d'inscription dans un registre public : {registro}.", si: 'registro' },
        ],
      },
      {
        id: 'objeto',
        titulo: "2. Objet",
        parrafos: [
          "Ce site web, accessible sur viveadn.com, propose Vive ADN, une plateforme permettant aux églises de gérer leurs membres, leurs maisons de prière, la consolidation, la formation, les événements et les rapports.",
        ],
      },
      {
        id: 'uso',
        titulo: "3. Conditions d'utilisation",
        parrafos: [
          "L'accès au site confère la qualité d'utilisateur et implique l'acceptation des présentes mentions. L'utilisation des comptes et des services est en outre régie par les Conditions d'utilisation. Vous vous engagez à utiliser le site de manière licite et à ne pas porter atteinte à son fonctionnement ni aux droits de tiers.",
        ],
      },
      {
        id: 'propiedad',
        titulo: "4. Propriété intellectuelle et industrielle",
        parrafos: [
          "Le logiciel, le design, les textes, les logos et la marque Vive ADN appartiennent à {titular} ou à ses concédants de licence. Leur reproduction, distribution ou transformation sans autorisation expresse est interdite, sauf dans la mesure permise par la loi. Les données que chaque église saisit appartiennent à l'église.",
        ],
      },
      {
        id: 'responsabilidad',
        titulo: "5. Responsabilité et liens",
        parrafos: [
          "Nous faisons le nécessaire, dans une mesure raisonnable, pour que les informations du site soient exactes et à jour, sans garantir l'absence d'erreurs ni d'interruptions. Le site peut afficher des liens vers des sites de tiers, par exemple ceux de collecte de fonds que configure chaque église, dont nous ne contrôlons pas le contenu et dont nous ne répondons pas.",
        ],
      },
      {
        id: 'datos',
        titulo: "6. Protection des données",
        parrafos: [
          "Le traitement des données personnelles est décrit dans la Politique de confidentialité, et l'utilisation du stockage sur votre appareil, dans la Politique de cookies.",
        ],
      },
      {
        id: 'ley',
        titulo: "7. Loi applicable et juridiction",
        parrafos: [
          "Les présentes mentions sont régies par la loi espagnole. Pour tout litige, les parties se soumettent aux juges et tribunaux de Séville, sauf si la loi impose un autre for en faveur des consommateurs. Vous pouvez nous contacter à {emailLegal}.",
        ],
      },
    ],
  },

  cookies: {
    titulo: "Politique de cookies",
    resumen: "Ce que Vive ADN stocke sur votre appareil, à quoi cela sert et comment l'effacer.",
    secciones: [
      {
        id: 'que-usamos',
        titulo: "1. Ce que nous stockons sur votre appareil",
        parrafos: [
          "Vive ADN n'utilise aucun cookie publicitaire, d'analyse ou de suivi, propre ou de tiers, et ne charge aucune ressource de tiers pour s'afficher. Pour fonctionner, il enregistre deux données dans le stockage local de votre navigateur, qui remplit une fonction semblable à celle d'un cookie :",
        ],
        lista: [
          "La session : un identifiant qui maintient votre session ouverte une fois que vous vous êtes connecté. Il est nécessaire au service que vous avez demandé et disparaît lorsque vous vous déconnectez. Il est géré par le service d'authentification.",
          "La langue : la préférence de langue que vous choisissez (clé viveadn.idioma). Elle mémorise votre choix et est conservée jusqu'à ce que vous l'effaciez.",
        ],
      },
      {
        id: 'consentimiento',
        titulo: "2. Pourquoi nous ne demandons pas de consentement",
        parrafos: [
          "L'article 22.2 de la loi espagnole 34/2002 n'exige pas de consentement pour le stockage ou l'accès de nature technique strictement nécessaire à la fourniture d'un service expressément demandé par la personne utilisatrice. Le guide de l'Agence espagnole de protection des données (AEPD) inclut parmi ces cas l'authentification et la personnalisation de l'interface, comme la langue. C'est pourquoi nous n'affichons pas de bandeau de cookies. Si nous ajoutons à l'avenir un stockage non nécessaire, nous demanderons d'abord votre consentement et nous mettrons à jour cette politique.",
        ],
      },
      {
        id: 'servidores',
        titulo: "3. Journaux du serveur",
        parrafos: [
          "Comme tout service web, le prestataire d'hébergement et celui d'authentification peuvent enregistrer des données techniques de chaque connexion, telles que l'adresse IP, pour assurer la sécurité et le fonctionnement. Cela est expliqué dans la Politique de confidentialité.",
        ],
      },
      {
        id: 'borrar',
        titulo: "4. Comment l'effacer",
        parrafos: [
          "Vous pouvez vous déconnecter depuis l'application, ou effacer les données du site depuis les paramètres de votre navigateur. Si vous le faites, vous devrez vous reconnecter et choisir de nouveau la langue.",
        ],
      },
      {
        id: 'cambios',
        titulo: "5. Modifications",
        parrafos: ["Nous publierons ici toute modification, avec une nouvelle version et sa date."],
      },
    ],
  },
}

export default fr
