#!/usr/bin/env bash
# Repro — widget_functions : un morceau d'écran est une classe widget, pas une méthode qui renvoie un widget.
# Cas réel : send_form_page.dart (feature error_redirect) a ajouté _bodyFor, _warnings, _stepsCard,
# _actions sans qu'aucun check le voie. Le package n'avait qu'un fichier de présentation : `xargs grep -n`
# sur un seul fichier n'imprime pas son nom, et le filtre de périmètre jetait tout (design_system et
# l10n_strings étaient aveugles de même).
source "$(dirname "$0")/fixture.sh"
need_fvm

R="$TMP_ROOT/repo"; mk_repo "$R"; write_cfg "$R"
P=app/features/feat
mk_pkg "$R/$P" feat
mkdir -p "$R/$P/lib/src/presentation/ui"
cat > "$R/$P/lib/src/presentation/ui/feat_page.dart" <<'EOF'
class FeatPage extends StatelessWidget {
  Widget build(BuildContext context) => _legacy(context);

  Widget _legacy(BuildContext context) => const SizedBox();
}
EOF
commit "$R" "develop" >/dev/null
git -C "$R" checkout -q -b feature/x
pipeline "$R" x '{"mode":"extend","package":"app/features/feat"}'

echo "widget_functions — méthode préexistante, seul fichier de présentation"
run_g "$R" widget_functions x
expect_rc 0 "vert : la dette existante n'est pas jugée"

echo "widget_functions — méthodes ajoutées par la feature"
cat >> "$R/$P/lib/src/presentation/ui/feat_page.dart" <<'EOF'

class FeatBody extends StatelessWidget {
  Widget build(BuildContext context) => Column(children: _rows());

  List<Widget> _rows() => const [];

  Widget _bodyFor(
    BuildContext context,
  ) =>
      const SizedBox();

  PreferredSizeWidget get _bar => AppBar();
}
EOF
run_g "$R" widget_functions x
expect_rc 1 "rouge"
expect_out "feat_page.dart:10:  List<Widget> _rows()" "List<Widget> nommée, avec le fichier"
expect_out "feat_page.dart:12:  Widget _bodyFor(" "déclaration sur plusieurs lignes"
expect_out "feat_page.dart:17:  PreferredSizeWidget get _bar" "getter"
expect_no_out "feat_page.dart:4:" "la méthode préexistante reste de la dette"
expect_no_out "feat_page.dart:8:" "build n'est pas signalée"

finish
