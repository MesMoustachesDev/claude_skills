# record_collections.awk — imprime "fichier:ligne:texte" pour chaque champ nommé d'un record littéral dont la
# valeur est une Map, une List ou un Set littéral (const ou non, typé ou non), quand ce record est comparé :
# dans un expect / equals / verify / when… Le == d'un record compare ses champs avec ==, et celui d'une
# collection compare l'identité ; mocktail compare aussi les arguments avec ==.
# Un "(" ouvre un record (ou une simple parenthèse) quand le dernier caractère significatif avant lui n'est ni
# un identifiant ni ">", ")", "]", "?", "!" ; sinon c'est un appel, dont les arguments nommés ne comptent pas.
BEGIN { cmp = "^(expect|expectLater|equals|verify|verifyNever|verifyInOrder|when|emits|emitsInOrder|contains|containsAll)$" }
FNR == 1 { depth = 0; prev = "("; ident = ""; inblock = 0 }
function compared(   d) { for (d = depth; d > 0; d--) if (kind[d] == "C" && name[d] ~ cmp) return 1; return 0 }
{
  raw = $0; line = $0
  gsub(/\\./, "", line)
  gsub(/'[^']*'/, "''", line); gsub(/"[^"]*"/, "\"\"", line)
  if (inblock) { if (match(line, /\*\//)) { line = substr(line, RSTART + 2); inblock = 0 } else next }
  sub(/\/\/.*$/, "", line)
  if (match(line, /\/\*/)) {
    head = substr(line, 1, RSTART - 1); rest = substr(line, RSTART + 2)
    if (match(rest, /\*\//)) line = head substr(rest, RSTART + 2); else { line = head; inblock = 1 }
  }
  for (i = 1; i <= length(line); i++) {
    c = substr(line, i, 1)
    if (c ~ /[A-Za-z0-9_]/) { ident = (prev ~ /[A-Za-z0-9_]/ ? ident : "") c }
    if (c == "(") {
      depth++
      if (prev ~ /[A-Za-z0-9_>)\]?!]/) { kind[depth] = "C"; name[depth] = (prev ~ /[A-Za-z0-9_]/ ? ident : "") }
      else { kind[depth] = "R"; name[depth] = "" }
    } else if (c == "{" || c == "[") {
      if (depth > 0 && kind[depth] == "R" && compared() \
          && substr(line, 1, i - 1) ~ /(^|[(,])[ \t]*[A-Za-z_][A-Za-z0-9_]*:[ \t]*(const[ \t]+)?(<[^>]*>[ \t]*)?$/ \
          && !seen[FILENAME, FNR]++)
        print FILENAME ":" FNR ":" raw
      depth++; kind[depth] = "B"; name[depth] = ""
    } else if (c == ")" || c == "}" || c == "]") {
      if (depth > 0) depth--
    }
    if (c !~ /[ \t]/) prev = c
  }
}
