CC     = gcc
CFLAGS = -std=c11 -D_POSIX_C_SOURCE=200809L -Wall -Wextra -O2
LEX    = flex

apilex: lex.yy.c main.c tokens.h
	$(CC) $(CFLAGS) -Wno-unused-function -o $@ lex.yy.c main.c

lex.yy.c: apilang.l tokens.h
	$(LEX) -o $@ apilang.l

test: apilex
	./testes/rodar_testes.sh

clean:
	rm -f apilex lex.yy.c testes/*.out

.PHONY: test clean
