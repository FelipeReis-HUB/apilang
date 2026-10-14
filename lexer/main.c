/*
 * main.c - Driver do analisador léxico da ApiLang.
 *
 * Uso:  apilex [arquivo.api]      (sem argumento, lê da entrada padrão)
 *
 * Imprime a lista de tokens (linha:coluna, classe, lexema/valor) na saída
 * padrão e os erros léxicos na saída de erro. Código de saída: 0 se não
 * houve erro léxico, 1 caso contrário, 2 se o arquivo não pôde ser aberto.
 */
#include <stdio.h>
#include <stdlib.h>
#include "tokens.h"

extern FILE *yyin;
extern char *yytext;
extern const char *lex_filename;

/* Imprime uma string escapando caracteres de controle. */
static void print_escaped(const char *s)
{
    putchar('"');
    for (; *s; s++) {
        switch (*s) {
        case '\n': fputs("\\n", stdout);  break;
        case '\t': fputs("\\t", stdout);  break;
        case '\r': fputs("\\r", stdout);  break;
        case '"':  fputs("\\\"", stdout); break;
        case '\\': fputs("\\\\", stdout); break;
        default:   putchar(*s);
        }
    }
    putchar('"');
}

int main(int argc, char **argv)
{
    if (argc > 2) {
        fprintf(stderr, "uso: %s [arquivo.api]\n", argv[0]);
        return 2;
    }
    if (argc == 2) {
        yyin = fopen(argv[1], "r");
        if (!yyin) {
            perror(argv[1]);
            return 2;
        }
        lex_filename = argv[1];
    }

    int count = 0, tok;
    printf("%-9s %-12s %s\n", "LIN:COL", "TOKEN", "LEXEMA / VALOR");
    while ((tok = yylex()) != TOK_EOF) {
        char pos[32];
        snprintf(pos, sizeof pos, "%d:%d", yylloc.first_line, yylloc.first_column);
        printf("%-9s %-12s ", pos, token_name(tok));
        switch (tok) {
        case IDENT:
            printf("%s", yylval.sval);
            free(yylval.sval);
            break;
        case STRING_LIT:
            print_escaped(yylval.sval);
            free(yylval.sval);
            break;
        case INT_LIT:
            printf("%-12s = %lld", yytext, yylval.ival);
            break;
        case FLOAT_LIT:
            printf("%-12s = %.15g", yytext, yylval.fval);
            break;
        case CHAR_LIT:
            printf("%-12s = U+%04X", yytext, yylval.cval);
            break;
        case TOK_ERROR:
            printf("(ver mensagem de erro)");
            break;
        default:
            printf("%s", yytext);
        }
        putchar('\n');
        count++;
    }

    printf("-- %d tokens, %d erro(s) léxico(s)\n", count, lex_error_count);
    return lex_error_count > 0 ? 1 : 0;
}
