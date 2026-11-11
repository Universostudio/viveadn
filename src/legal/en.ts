import type { TextosLegales } from './tipos'

// English translation of the master text (es.ts). Placeholders: {titular} {nif} {domicilio} {emailLegal} {emailSoporte} {registro}.
// Version 1: translated from the Spanish master, pending review by a lawyer.
const en: TextosLegales = {
  privacidad: {
    titulo: 'Privacy policy',
    resumen: 'What data Vive ADN processes, for what purpose, on what legal basis, for how long, and how to exercise your rights.',
    secciones: [
      {
        id: 'quienes-somos',
        titulo: '1. Who we are and what role we have',
        parrafos: [
          "Vive ADN is a web platform for churches to manage their members, houses of prayer, consolidation, training, events and reports. It is provided by {titular}, with registered address at {domicilio} and tax ID (NIF) {nif}. For any privacy matter you can write to {emailLegal}.",
          "We have two distinct roles, and it is worth telling them apart because they determine whom you should contact:",
        ],
        lista: [
          "Controllers of the data of the people who use the platform: those who create a church account, those who receive an invitation and those who contact us.",
          "Processors of the data of the members, attendees and visitors that each church registers. For that data the controller is the church, which decides for what purposes and how it is used. We process it on its behalf and following its instructions, under the data processing agreement that forms part of the Terms of use.",
        ],
      },
      {
        id: 'si-eres-miembro',
        titulo: '2. If you are a member or visitor of a church',
        parrafos: [
          "Your data has been registered by your church, or you provided it yourself when registering for an event using a QR code. The controller of that processing is the church, not us. To find out what it does with your data, on what legal basis and for how long, and to exercise your rights, contact the church first.",
          "If you do not know which church your registration belongs to, or the church does not reply, write to us at {emailLegal} and we will help it handle your request.",
        ],
      },
      {
        id: 'datos-como-responsables',
        titulo: '3. Data we process as controllers',
        parrafos: ["This is the data we process on our own behalf, what we use it for and the basis on which we rely:"],
        lista: [
          "Account data (first name, surnames, email address, church and role, and the password, which is managed by the authentication service without us being able to see it). We use it to create the account, identify you and give you access. Legal basis: performance of a contract, Article 6.1.b of the GDPR.",
          "Security data, such as a non-reversible fingerprint of the IP address and registration attempts. We use it to curb abuse and protect all churches. Legal basis: legitimate interest in the security of the service, Article 6.1.f of the GDPR.",
          "Communications you send us, for example a support enquiry. We use them to assist you. Legal basis: performance of a contract or legitimate interest in replying to you.",
          "Data we must keep to comply with legal obligations. Legal basis: Article 6.1.c of the GDPR.",
        ],
        cierre: [
          "We keep account data while the account is active and, afterwards, for as long as legal obligations or the defence of possible claims require. Vive ADN does not process or store payments: a church's contributions go directly to the sites it uses.",
        ],
      },
      {
        id: 'datos-como-encargados',
        titulo: '4. Data we process as processors for each church',
        parrafos: [
          "Depending on what each church decides to register, the platform may contain: first name, surnames, email, phone number, address, date of birth, tags and notes; attendance at houses of prayer and events; consolidation follow-up; training progress and certificates; each person's consent status to receive messages by email, WhatsApp or SMS, with its history; and the messages prepared from the platform.",
          "By its nature, the mere fact of belonging to a church can reveal religious beliefs, which the GDPR treats as a special category of data (Article 9). Each church is responsible for having a basis that allows it, for example Article 9.2.d of the GDPR, which covers processing by a foundation, association or other not-for-profit body with a religious aim, in the course of its legitimate activities and with appropriate safeguards, provided the processing relates solely to its current or former members or to persons who have regular contact with it in connection with its purposes, and that the data are not disclosed outside it without the consent of the data subjects, or the explicit consent of the person. We do not decide or assess that basis: we apply the church's instructions.",
          "Children under 14 cannot give their consent by themselves (Article 7 of Organic Act 3/2018). Registration by QR requires declaring that you are at least that age.",
        ],
      },
      {
        id: 'registro-qr-y-mensajes',
        titulo: '5. Registration by QR and communications',
        parrafos: [
          "When you register for an event using a QR code, you are asked to accept that the church stores your data to record your attendance and to follow up with you after your visit. In addition, you can tick, each one separately and without them being pre-ticked, the boxes to receive messages from the church by email, by WhatsApp or by SMS. Not ticking any of them does not prevent you from registering.",
          "We keep as evidence which text you accepted, in which version and on which date, so that the church can prove it.",
          "Messages are sent only to those who have given their consent for that channel, and every message must make it easy to unsubscribe, in accordance with Article 21 of Spanish Act 34/2002 on information society services and electronic commerce. As of the date of this version the platform does not send real messages: this section describes the rules that will apply when that function is activated.",
        ],
      },
      {
        id: 'destinatarios',
        titulo: '6. Who else has access to the data',
        parrafos: [
          "To provide the service we use providers that act as sub-processors: the database, authentication and file storage infrastructure, the web hosting and the sending of invitation emails. We do not sell data or use it for advertising. We disclose it to third parties only when the law requires it or an authority orders it.",
          "Some providers belong to groups headquartered outside the European Economic Area. In that case, transfers rely on the safeguards of Chapter V of the GDPR, such as an adequacy decision or the standard contractual clauses. Anyone who asks at {emailLegal} can obtain the updated list of sub-processors and the region where the data is hosted.",
        ],
      },
      {
        id: 'conservacion',
        titulo: '7. How long we keep churches\' data',
        parrafos: [
          "Each church's data is kept while its account is active. When a church requests to cancel, its account goes through the recess and suspension stages, and then deletion is scheduled: first a soft deletion, with a fixed period of 30 days during which it can still be recovered, and then the final purge of the data and the files.",
          "Backups are renewed according to their own cycle and may keep data for a limited time after deletion. Before cancellation, the church can download all its data in JSON and CSV format.",
        ],
      },
      {
        id: 'derechos',
        titulo: '8. Your rights',
        parrafos: ["You have the right to:"],
        lista: [
          "access your data and obtain a copy;",
          "rectify inaccurate data;",
          "request its erasure;",
          "request the restriction of its processing;",
          "object to the processing;",
          "receive your data in a structured format and transfer it to another controller (portability);",
          "withdraw at any time a consent you have given, without affecting what was done before withdrawing it.",
        ],
        cierre: [
          "To exercise them over a church's data, contact that church. For the data we process as controllers, write to {emailLegal}. We reply within one month, extendable under Article 12.3 of the GDPR. We do not make automated decisions with legal effects on individuals.",
          "If you consider that we have not handled your data properly, you can lodge a complaint with the Spanish Data Protection Agency (AEPD), www.aepd.es.",
        ],
      },
      {
        id: 'seguridad',
        titulo: '9. Security',
        parrafos: [
          "We apply technical and organisational measures appropriate to the risk: each church can access only its own data, access is limited by roles and permissions, communications are encrypted in transit, passwords are managed by a specialised authentication service, and changes to consent and to the life cycle are logged. No system is infallible. If a security breach affecting personal data occurs, we will notify the affected church without undue delay.",
        ],
      },
      {
        id: 'cambios',
        titulo: '10. Changes to this policy',
        parrafos: [
          "If we change this policy we will publish a new version, with its number and date, and we will give notice of important changes. Earlier versions are kept in the platform's version log.",
        ],
      },
    ],
  },

  terminos: {
    titulo: 'Terms of use',
    resumen: 'The conditions for using Vive ADN, the responsibilities of each party and the data processing agreement.',
    secciones: [
      {
        id: 'objeto',
        titulo: '1. Purpose and acceptance',
        parrafos: [
          "These terms govern the use of Vive ADN, a web platform provided by {titular}, with registered address at {domicilio} and tax ID (NIF) {nif}. By creating an account or using the service you accept these terms. If you do so on behalf of a church, you declare that you have authority to bind it.",
        ],
      },
      {
        id: 'servicio',
        titulo: '2. The service',
        parrafos: [
          "Vive ADN allows each church to manage its members, houses of prayer, consolidation, training, events, communication and reports. We work to keep the service continuously available, but we do not guarantee that there will be no interruptions, and we may modify or withdraw features, giving reasonable advance notice where possible.",
        ],
      },
      {
        id: 'cuentas',
        titulo: '3. Accounts and roles',
        parrafos: [
          "Each church has an owner who invites other people and assigns them a role with permissions. The church is responsible for the people to whom it gives access, for ensuring that their contact details are correct and for ensuring that they keep their credentials safe. Tell us without delay if you suspect unauthorised access.",
        ],
      },
      {
        id: 'responsabilidad-iglesia',
        titulo: '4. The church\'s responsibility for its data',
        parrafos: [
          "The church is the controller of the data of its members and visitors, and Vive ADN is its processor. For that reason the church undertakes to:",
        ],
        lista: [
          "have a legal basis for each processing activity and, in the case of data revealing religious beliefs, one of the exceptions in Article 9.2 of the GDPR;",
          "inform individuals in accordance with Articles 13 and 14 of the GDPR;",
          "send messages only to those who have given their consent for that channel, and respect unsubscribes;",
          "not register children under 14 without the authorisation of the person who holds their parental authority or guardianship;",
          "handle individuals' rights, with our help when it needs it;",
          "not enter data it does not need, nor health data, criminal data or other data that the platform is not designed to safeguard.",
        ],
      },
      {
        id: 'uso-aceptable',
        titulo: '5. Acceptable use',
        parrafos: ["The following is not permitted:"],
        lista: [
          "using the platform to send unsolicited communications or to send them to someone who has unsubscribed;",
          "impersonating another person or another church;",
          "attempting to access another church's data, circumventing the limits of the service or testing its security without our written permission;",
          "copying, decompiling or reselling the service;",
          "entering unlawful content or content that infringes the rights of third parties.",
        ],
        cierre: ["We may suspend an account that breaches these rules, giving notice where possible."],
      },
      {
        id: 'condiciones-economicas',
        titulo: '6. Plans and financial terms',
        parrafos: [
          "The plans set usage limits, for example on the number of people with access. As of the date of this version the service has no real charges. If they were introduced, the price, whether it includes taxes and the means of payment will be notified before applying it, and it will require your acceptance. Vive ADN does not process or store a church's offerings or contributions: it only displays links to the sites that the church itself configures.",
        ],
      },
      {
        id: 'propiedad',
        titulo: '7. Ownership of the data and of the service',
        parrafos: [
          "The data that each church enters belongs to the church. It grants us the right to process it solely to provide the service to it. The software, the brand, the design and the texts of Vive ADN belong to {titular} or its licensors, and these terms do not transfer any right over them except the right to use the service.",
        ],
      },
      {
        id: 'responsabilidad',
        titulo: '8. Liability',
        parrafos: [
          "We provide the service with reasonable diligence, but we are not liable for indirect damages or loss of profits, or for any unlawful use that a church makes of the platform. Our total liability is limited to what the law allows to be limited, and nothing in these terms excludes liability for wilful misconduct or liability that cannot be excluded by law.",
        ],
      },
      {
        id: 'baja-exportacion',
        titulo: '9. Cancellation, export and deletion',
        parrafos: [
          "The church can download all its data at any time in JSON and CSV format, with a fingerprint of each table to check that they are complete. It can request cancellation whenever it wishes. After cancellation, the account goes through recess and suspension, and then its deletion is scheduled: a soft deletion with a fixed period of 30 days, during which it can be recovered, and the final purge of the data and the files. Backups are renewed according to their cycle and may keep data for a further limited time.",
        ],
      },
      {
        id: 'cambios',
        titulo: '10. Changes to these terms',
        parrafos: [
          "We may modify these terms. We will publish the new version with its number and date and will give reasonable advance notice of changes that are detrimental to you. If you do not agree, you can cancel before they come into force.",
        ],
      },
      {
        id: 'ley',
        titulo: '11. Governing law and jurisdiction',
        parrafos: [
          "These terms are governed by Spanish law. To resolve any dispute, the parties submit to the courts and tribunals of Seville, without prejudice to the jurisdiction that the law imposes in favour of consumers. You can write to us at {emailLegal} before going to them.",
        ],
      },
      {
        id: 'encargo',
        titulo: '12. Annex: data processing agreement (Article 28 of the GDPR)',
        parrafos: [
          "This annex governs the processing of personal data that {titular} (the processor) carries out on behalf of each church (the controller) when providing it with the service. It is deemed accepted when the church accepts these terms.",
        ],
        lista: [
          "Subject matter and duration: hosting, storing, organising, consulting, exporting and deleting the data that the church registers, for as long as the service lasts and until the deletion described in section 9 is completed.",
          "Nature and purpose: exclusively providing the platform's functions to the church.",
          "Types of data: identification and contact details, date of birth, notes, attendance, consolidation, training, communication consents and data that, by their nature, reveal religious beliefs. Categories of data subjects: members, attendees, visitors and collaborators of the church.",
          "Instructions: the processor processes the data only on the church's documented instructions, which are the church's use of the platform and what it communicates to us in writing. If it considers that an instruction infringes data protection law, it will inform the church.",
          "Confidentiality: the persons authorised to process the data have committed to keeping it confidential.",
          "Security: the processor applies the measures of Article 32 of the GDPR described in the privacy policy.",
          "Sub-processors: the church grants a general authorisation to use the providers necessary to provide the service. The processor imposes on them the same data protection obligations, remains liable to the church for their compliance and, if it adds or replaces any of them, will notify the church so that it can object.",
          "International transfers: they are carried out only with the safeguards of Chapter V of the GDPR.",
          "Data subjects' rights: the processor will assist the church in handling them, and will forward to the church any request it receives directly.",
          "Security breaches: the processor will notify the church of them without undue delay after becoming aware of them and will provide the necessary information.",
          "Assistance: the processor will assist the church with any data protection impact assessments and prior consultations that are necessary.",
          "End of the service: the church can export all its data and, after cancellation, the processor will delete it in accordance with section 9, unless a rule requires it to be kept.",
          "Audit: the processor will make available to the church the information necessary to demonstrate compliance and will allow reasonable audits, with prior notice.",
        ],
        cierre: [
          "The church, as controller, undertakes to comply with the provisions of section 4 and to give the processor lawful instructions.",
        ],
      },
    ],
  },

  aviso: {
    titulo: 'Legal notice',
    resumen: 'Who the owner of Vive ADN is, the conditions of use of the website and the governing law.',
    secciones: [
      {
        id: 'titular',
        titulo: '1. Owner of the website',
        parrafos: [
          "In compliance with Article 10 of Spanish Act 34/2002 on information society services and electronic commerce, you are informed that the owner of this website is {titular}, with registered address at {domicilio}, tax ID (NIF) {nif} and contact email {emailLegal}.",
          { texto: 'Public registry registration details: {registro}.', si: 'registro' },
        ],
      },
      {
        id: 'objeto',
        titulo: '2. Purpose',
        parrafos: [
          "This website, available at viveadn.com, offers Vive ADN, a platform for churches to manage their members, houses of prayer, consolidation, training, events and reports.",
        ],
      },
      {
        id: 'uso',
        titulo: '3. Conditions of use',
        parrafos: [
          "Access to the site confers the status of user and implies acceptance of this notice. The use of accounts and services is also governed by the Terms of use. You undertake to use the site lawfully and not to harm its operation or the rights of third parties.",
        ],
      },
      {
        id: 'propiedad',
        titulo: '4. Intellectual and industrial property',
        parrafos: [
          "The software, the design, the texts, the logos and the Vive ADN brand belong to {titular} or its licensors. Their reproduction, distribution or transformation without express authorisation is prohibited, except as permitted by law. The data that each church enters belongs to the church.",
        ],
      },
      {
        id: 'responsabilidad',
        titulo: '5. Liability and links',
        parrafos: [
          "We take reasonable steps to ensure that the information on the site is correct and up to date, without guaranteeing that there will be no errors or interruptions. The site may display links to third-party sites, for example the collection links that each church configures, over whose content we have no control and for which we are not liable.",
        ],
      },
      {
        id: 'datos',
        titulo: '6. Data protection',
        parrafos: [
          "The processing of personal data is described in the Privacy policy, and the use of storage on your device in the Cookie policy.",
        ],
      },
      {
        id: 'ley',
        titulo: '7. Governing law and jurisdiction',
        parrafos: [
          "This notice is governed by Spanish law. For any dispute, the parties submit to the courts and tribunals of Seville, unless the law imposes another jurisdiction in favour of consumers. You can contact us at {emailLegal}.",
        ],
      },
    ],
  },

  cookies: {
    titulo: 'Cookie policy',
    resumen: 'What Vive ADN stores on your device, what it is for and how to delete it.',
    secciones: [
      {
        id: 'que-usamos',
        titulo: '1. What we store on your device',
        parrafos: [
          "Vive ADN does not use advertising, analytics or tracking cookies, whether its own or third-party, and does not load third-party resources in order to display. To work, it stores two items in your browser's local storage, which serves a function similar to that of a cookie:",
        ],
        lista: [
          "The session: an identifier that keeps your session open once you have logged in. It is necessary for the service you have requested and disappears when you log out. It is managed by the authentication service.",
          "The language: the language preference you choose (key viveadn.idioma). It remembers your choice and is kept until you delete it.",
        ],
      },
      {
        id: 'consentimiento',
        titulo: '2. Why we do not ask for consent',
        parrafos: [
          "Article 22.2 of Spanish Act 34/2002 does not require consent for storage or access of a technical nature that is strictly necessary to provide a service expressly requested by the user. The guidance of the Spanish Data Protection Agency (AEPD) includes among these cases authentication and the personalisation of the interface, such as language. For that reason we do not display a cookie notice. If in the future we add storage that is not necessary, we will ask for your consent beforehand and update this policy.",
        ],
      },
      {
        id: 'servidores',
        titulo: '3. Server logs',
        parrafos: [
          "Like any web service, the hosting provider and the authentication provider may record technical data about each connection, such as the IP address, to maintain security and operation. This is explained in the Privacy policy.",
        ],
      },
      {
        id: 'borrar',
        titulo: '4. How to delete it',
        parrafos: [
          "You can log out from the application, or delete the site's data from your browser settings. If you do, you will have to log in again and choose the language again.",
        ],
      },
      {
        id: 'cambios',
        titulo: '5. Changes',
        parrafos: ["We will publish any change here, with a new version and its date."],
      },
    ],
  },
}

export default en
