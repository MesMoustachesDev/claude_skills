# slugify

`slugify(title, {maxLength = 40})` rend le slug d'un titre de recette.

1. Minuscules ; les lettres accentuées perdent leur accent (é è ê ë → e, à â → a, ç → c, î ï → i,
   ô → o, ù û ü → u, œ → oe, æ → ae).
2. Tout ce qui n'est ni lettre a-z ni chiffre devient un tiret ; plusieurs tirets de suite n'en font
   qu'un ; pas de tiret en tête ni en fin.
3. Un slug de `maxLength` caractères ou moins est rendu tel quel. Au-delà, il est coupé au dernier
   tiret qui lui laisse au plus `maxLength` caractères, tiret exclu (jamais au milieu d'un mot) :
   `slugify('ab cd ef', maxLength: 5)` → `ab-cd`. Un premier mot plus long que la limite est coupé net
   à `maxLength` caractères.
4. Un titre sans aucune lettre ni chiffre → `ArgumentError`.
5. `maxLength` < 1 → `ArgumentError`.
