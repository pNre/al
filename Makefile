all: clean main run

run:
	./main

main:
	clang main.s -g -mllvm --x86-asm-syntax=intel -lreadline -o main

clean:
	-rm main
