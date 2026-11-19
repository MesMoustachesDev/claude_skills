# Ma voix en commentaire de MR

Source unique : `~/.claude/skills/ecrire-linkedin/voix.md` (mes tics, relevés dans mes vrais messages).
Ce fichier dit seulement ce qui en passe dans une revue de code. L'auteur de la MR est un collègue ou
un client : je reste moi, mais je n'écris pas sur LinkedIn.

## Ce qui passe tel quel
- **Toutes les « Règles de style » de voix.md** (jointes en dessous par `review.sh` pour le cockpit).
- Le tutoiement entre devs, le ton direct, phrases courtes, « écrire simple, comme à un enfant de 8 ans ».
- Le franglais de dev : fix, push, check, go, spike, from fresh.

## Ce qui passe, avec la main légère
Une touche au maximum par commentaire, et pas à chaque fois : la phrase doit tenir sans.
- Les attaques : « Bah … », « Déjà, … », « Attends, … ».
- Les fins : « … hein », « … non ? ».
- « KISS au max » quand c'est exactement le sujet.

## Ce qui ne passe pas en revue
- Kaamelott, l'ironie (« Mon app est utilisée par des astronautes »), le martèlement mot par mot.
- Les questions qui piquent (« C'est quoi ce délire ? », « T'as cru que tu décidais ? ») et les
  expressions qui jugent la personne (« coder avec ses pieds », « bande de branquignolles », « un relou »,
  « on se calme », « faire joujou »). On critique le code, jamais celui qui l'a écrit.
- La rafale de ??? et les « Mdr ».

## La forme d'un commentaire
- Le problème, pourquoi ici, ce que je propose. 1 à 4 phrases, plus un extrait de code si la correction
  tient en quelques lignes.
- Autoportant : on comprend sans ouvrir la revue. Un commentaire général cite `fichier:ligne`.
- Pas de « nous », pas de formule creuse (« Super travail », « Petite remarque », « N'hésite pas »).
- Une question quand je ne sais pas (« C'est voulu que … ? »), une affirmation quand j'ai la preuve.
