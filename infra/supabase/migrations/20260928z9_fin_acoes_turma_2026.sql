-- 20260928z9 — ações de 2026 ganham a coluna turma a partir do nome ("T39 · …"), para o evento do dia herdar a turma.
update fin.acoes set turma = substring(nome from '^(T\d+) · ') where nome ~ '^T\d+ · ' and turma is distinct from substring(nome from '^(T\d+) · ');
