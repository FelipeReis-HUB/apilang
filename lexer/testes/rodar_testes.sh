#!/bin/sh
# Executa o apilex em cada testes/*.api e compara a saída (stdout + stderr)
# com testes/*.esperado. Use "./rodar_testes.sh --atualizar" para regravar
# os arquivos esperados depois de conferi-los manualmente.
cd "$(dirname "$0")" || exit 2
LEX=../apilex
falhas=0
total=0
for t in *.api; do
    nome=${t%.api}
    total=$((total + 1))
    $LEX "$t" > "$nome.out" 2>&1
    if [ "$1" = "--atualizar" ]; then
        cp "$nome.out" "$nome.esperado"
        echo "atualizado: $nome"
    elif diff -u "$nome.esperado" "$nome.out" > /dev/null; then
        echo "ok    $nome"
    else
        echo "FALHA $nome"
        diff -u "$nome.esperado" "$nome.out"
        falhas=$((falhas + 1))
    fi
done
echo "$((total - falhas))/$total testes passaram"
[ "$falhas" -eq 0 ]
